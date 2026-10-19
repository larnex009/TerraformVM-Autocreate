############################################
# Prism Central connection
############################################
variable "nutanix_user" {
  type = string
}

variable "nutanix_password" {
  type      = string
  sensitive = true # supply via TF_VAR_nutanix_password, NOT in a committed file
}

variable "nutanix_endpoint" {
  type        = string
  description = "Prism Central IP or FQDN"
}

variable "nutanix_port" {
  type    = number
  default = 9440
}

variable "nutanix_insecure" {
  type    = bool
  default = true # true = skip TLS verification (self-signed cert)
}

############################################
# Cluster / storage
############################################
variable "cluster_name" {
  type        = string
  description = "Name of the Prism Element cluster (as shown in Prism Central) where VMs are created"
}

variable "storage_container_uuid" {
  type        = string
  default     = ""
  description = "Optional. Storage container UUID for NEW blank disks (extra disks / ISO OS disks). Empty = cluster default."
}

############################################
# Guest customisation
############################################
variable "linux_ssh_public_key" {
  type        = string
  default     = ""
  description = "Optional SSH public key injected by cloud-init into the image's default user"
}

variable "linux_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "windows_admin_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Optional. If set, a sysprep unattend is applied to Windows TEMPLATES (the image must be sysprepped/generalised)."
}

############################################
# Subnet list  (see subnets.auto.tfvars)
############################################
variable "subnets" {
  description = "Allowed subnet names in Prism Central"
  type        = list(string)
}

############################################
# Image catalogue  (see images.auto.tfvars)
############################################
variable "images" {
  description = "Describes every image you use: is it a bootable disk 'template' or an 'iso', and which OS."
  type = map(object({
    image_type            = string # "template" | "iso"
    os_type               = string # "windows" | "linux"
    template_disk_size_gb = optional(number, 0) # size of the template's disk (needed to grow Linux root)
  }))

  validation {
    condition     = alltrue([for k, v in var.images : contains(["template", "iso"], v.image_type)])
    error_message = "image_type must be \"template\" or \"iso\"."
  }
  validation {
    condition     = alltrue([for k, v in var.images : contains(["windows", "linux"], v.os_type)])
    error_message = "os_type must be \"windows\" or \"linux\"."
  }
}

############################################
# VM inventory  (see terraform.tfvars)
############################################
variable "vms" {
  description = "Map of VMs to create. The key is the VM name."
  type = map(object({
    cpu_cores          = number                  # vCPUs per socket
    cpu_sockets        = optional(number, 1)
    memory_mb          = number
    subnet_name        = string
    image_name         = string                  # must exist in var.images
    os_type            = optional(string)        # "windows" | "linux"; null = taken from images.auto.tfvars
    image_type         = optional(string)        # "template" | "iso";  null = taken from images.auto.tfvars
    extra_disk_size_gb = optional(number, 0)     # 0 = none
    os_disk_size_gb    = optional(number, 60)    # ONLY used for ISO installs (blank OS disk)
    ip_address         = optional(string)        # static IP; null = DHCP
    subnet_cidr        = optional(string)        # prefix length, e.g. "24" (needed for static IP on unmanaged subnets)
    gateway            = optional(string)        # e.g. "192.168.41.1" (needed for static IP on unmanaged subnets)
    dns_servers        = optional(list(string), [])
    use_ipam           = optional(bool, false)   # true ONLY if the subnet is IPAM-managed (Prism assigns the IP)
    boot_type          = optional(string)        # "LEGACY" | "UEFI" | "SECURE_BOOT"; null = provider default
    description        = optional(string, "Managed by Terraform")
  }))

  # ---- name validation against the lists (needs Terraform >= 1.9) ----
  validation {
    condition     = alltrue([for k, v in var.vms : contains(var.subnets, v.subnet_name)])
    error_message = "Unknown subnet_name (not in subnets.auto.tfvars): ${join(", ", [for k, v in var.vms : "${k} -> '${v.subnet_name}'" if !contains(var.subnets, v.subnet_name)])}"
  }
  validation {
    condition     = alltrue([for k, v in var.vms : contains(keys(var.images), v.image_name)])
    error_message = "Unknown image_name (not in images.auto.tfvars): ${join(", ", [for k, v in var.vms : "${k} -> '${v.image_name}'" if !contains(keys(var.images), v.image_name)])}"
  }
  validation {
    condition     = alltrue([for k, v in var.vms : (v.os_type == null || contains(["windows", "linux"], v.os_type)) && (v.image_type == null || contains(["template", "iso"], v.image_type))])
    error_message = "os_type must be windows or linux, and image_type must be template or iso."
  }
  validation {
    condition     = alltrue([for k, v in var.vms : v.boot_type == null ? true : contains(["LEGACY", "UEFI", "SECURE_BOOT"], v.boot_type)])
    error_message = "boot_type must be LEGACY, UEFI or SECURE_BOOT."
  }
}
