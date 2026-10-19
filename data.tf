# =====================================================
# Fetch cluster UUID
# =====================================================
data "nutanix_cluster" "target" {
  name = var.cluster_name
}

# =====================================================
# DYNAMIC SUBNET & IMAGE LOOKUPS
# =====================================================

# Query every subnet referenced in var.vms (by name -> UUID)
data "nutanix_subnet" "selected" {
  for_each    = toset([for vm in var.vms : vm.subnet_name])
  subnet_name = each.value
}

# Query every image (disk template OR ISO) referenced in var.vms (by name -> UUID)
data "nutanix_image" "selected" {
  for_each   = toset([for vm in var.vms : vm.image_name])
  image_name = each.value
}
