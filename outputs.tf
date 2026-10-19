output "vms" {
  value = {
    for name, vm in nutanix_virtual_machine.vm : name => {
      uuid = vm.id
      ip   = try(vm.nic_list_status[0].ip_endpoint_list[0].ip, "pending")
    }
  }
}

# UUIDs that the API lookups resolved (visible after plan/apply)
output "resolved_subnet_uuids" {
  value = { for n, s in data.nutanix_subnet.selected : n => s.id }
}

output "resolved_image_uuids" {
  value = { for n, i in data.nutanix_image.selected : n => i.id }
}

output "cluster_uuid" {
  value = data.nutanix_cluster.target.id
}
