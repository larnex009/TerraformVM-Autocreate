locals {
  # Merge each VM with what we know about its image (type / OS / size)
  vm_cfg = {
    for name, vm in var.vms : name => merge(vm, {
      image_type = vm.image_type != null ? vm.image_type : try(var.images[vm.image_name].image_type, "unknown")
      os_type    = vm.os_type != null ? vm.os_type : try(var.images[vm.image_name].os_type, "unknown")
      tpl_gb     = try(var.images[vm.image_name].template_disk_size_gb, 0)
    })
  }

  # Linux template + extra storage  => GROW the root disk (cloud-init growpart/resizefs extends the filesystem)
  # Windows template + extra storage => add a SEPARATE second disk
  # ISO (any OS)                     => CD-ROM + blank OS disk (+ separate extra disk if requested)
  vm_disks = {
    for name, c in local.vm_cfg : name => concat(

      # ---- TEMPLATE: cloned boot disk
      c.image_type == "template" ? [{
        image_uuid    = data.nutanix_image.selected[c.image_name].id
        size_mib      = (c.os_type == "linux" && c.extra_disk_size_gb > 0 && c.tpl_gb > 0) ? (c.tpl_gb + c.extra_disk_size_gb) * 1024 : null
        device_type   = "DISK"
        adapter_type  = "SCSI"
        index         = 0
        use_container = false
      }] : [],

      # ---- ISO: CD-ROM + blank OS disk
      c.image_type == "iso" ? [
        {
          image_uuid    = data.nutanix_image.selected[c.image_name].id
          size_mib      = null
          device_type   = "CDROM"
          adapter_type  = "IDE"
          index         = 0
          use_container = false
        },
        {
          image_uuid    = null
          size_mib      = c.os_disk_size_gb * 1024
          device_type   = "DISK"
          adapter_type  = "SCSI"
          index         = 0
          use_container = true
        }
      ] : [],

      # ---- Extra separate disk (everything except Linux templates, which grow root instead)
      (c.extra_disk_size_gb > 0 && !(c.image_type == "template" && c.os_type == "linux")) ? [{
        image_uuid    = null
        size_mib      = c.extra_disk_size_gb * 1024
        device_type   = "DISK"
        adapter_type  = "SCSI"
        index         = 1
        use_container = true
      }] : []
    )
  }
}

resource "nutanix_virtual_machine" "vm" {
  for_each = local.vm_cfg

  name        = each.key
  description = each.value.description
  cluster_uuid = data.nutanix_cluster.target.id

  num_sockets          = each.value.cpu_sockets
  num_vcpus_per_socket = each.value.cpu_cores
  memory_size_mib      = each.value.memory_mb
  boot_type            = each.value.boot_type

  # ISO installs must boot from the CD-ROM first
  boot_device_order_list = each.value.image_type == "iso" ? ["CDROM", "DISK"] : null

  # LEGACY boot needs an explicit boot device. For templates, boot from the cloned system disk (SCSI 0).
  # UEFI / SECURE_BOOT do not need this.
  boot_device_disk_address = (
    each.value.image_type == "template" && (each.value.boot_type == null || each.value.boot_type == "LEGACY")
    ? { adapter_type = "SCSI", device_index = "0" }
    : null
  )

  # ---------------- NIC ----------------
  nic_list {
    subnet_uuid = data.nutanix_subnet.selected[each.value.subnet_name].id

    dynamic "ip_endpoint_list" {
      # Only for IPAM-managed subnets. On unmanaged subnets the IP is set inside the guest (see sysprep below).
      for_each = (each.value.ip_address != null && each.value.use_ipam) ? [each.value.ip_address] : []
      content {
        ip   = ip_endpoint_list.value
        type = "ASSIGNED"
      }
    }
  }

  # ---------------- DISKS ----------------
  dynamic "disk_list" {
    for_each = local.vm_disks[each.key]
    content {
      data_source_reference = disk_list.value.image_uuid == null ? null : {
        kind = "image"
        uuid = disk_list.value.image_uuid
      }
      disk_size_mib = disk_list.value.size_mib

      device_properties {
        device_type = disk_list.value.device_type
        disk_address = {
          device_index = tostring(disk_list.value.index)
          adapter_type = disk_list.value.adapter_type
        }
      }

      dynamic "storage_config" {
        for_each = (disk_list.value.use_container && var.storage_container_uuid != "") ? [1] : []
        content {
          storage_container_reference {
            kind = "storage_container"
            uuid = var.storage_container_uuid
          }
        }
      }
    }
  }

  # ---------------- GUEST CUSTOMISATION ----------------
  # Linux template -> cloud-init (hostname, ssh key, grow root fs)
  guest_customization_cloud_init_user_data = (
    each.value.os_type == "linux" && each.value.image_type == "template"
    ? base64encode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
        hostname = each.key
        ssh_key  = var.linux_ssh_public_key
        password = var.linux_password
      }))
    : null
  )

  # Windows template -> sysprep: computer name, optional admin password, optional in-guest static IP.
  # NOTE: the template image must be sysprepped/generalised, otherwise Windows ignores this.
  guest_customization_sysprep = (
    each.value.os_type == "windows" && each.value.image_type == "template" && (
      var.windows_admin_password != "" || (each.value.ip_address != null && !each.value.use_ipam)
    )
    ? {
        install_type = "PREPARED"
        unattend_xml = base64encode(templatefile("${path.module}/templates/unattend.xml.tftpl", {
          computer_name  = substr(each.key, 0, 15)
          admin_password = var.windows_admin_password
          static_ip      = (each.value.ip_address != null && !each.value.use_ipam) ? each.value.ip_address : ""
          prefix         = coalesce(each.value.subnet_cidr, "24")
          gateway        = coalesce(each.value.gateway, "")
          dns            = join(",", [for d in each.value.dns_servers : "'${d}'"])
        }))
      }
    : null
  )

  lifecycle {
    precondition {
      condition     = contains(var.subnets, each.value.subnet_name)
      error_message = "Subnet '${each.value.subnet_name}' is not in subnets.auto.tfvars."
    }
    precondition {
      condition     = contains(keys(var.images), each.value.image_name)
      error_message = "Image '${each.value.image_name}' is not described in var.images (images.auto.tfvars)."
    }
    precondition {
      condition     = each.value.image_type != "template" || each.value.os_type != "linux" || each.value.extra_disk_size_gb == 0 || each.value.tpl_gb > 0
      error_message = "Linux template with extra disk: set template_disk_size_gb for this image in images.auto.tfvars."
    }
    precondition {
      condition     = each.value.ip_address == null || each.value.use_ipam || (each.value.gateway != null && each.value.subnet_cidr != null)
      error_message = "VM '${each.key}': static ip_address on an unmanaged subnet needs subnet_cidr and gateway (or set use_ipam = true if the subnet is IPAM-managed)."
    }
    # Don't recreate a VM later just because guest-customisation text changed
    ignore_changes = [
      guest_customization_cloud_init_user_data,
      guest_customization_sysprep,
    ]
  }
}
