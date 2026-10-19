# ---------- Prism Central ----------
nutanix_user     = "michael"      # password goes in env var TF_VAR_nutanix_password
nutanix_endpoint = "10.20.24.111" # Prism Central IP or FQDN
nutanix_port     = 9440
nutanix_insecure = true

# ---------- Cluster defaults ----------
cluster_name           = "cwgnuxcl01"
storage_container_uuid = "08d26e10-6b5d-4cbe-8d10-c6f99d2de9d9" # optional, e.g. "08d26e10-6b5d-4cbe-8d10-c6f99d2de9d9"

# ---------- Optional guest settings ----------
# linux_ssh_public_key = "ssh-ed25519 AAAA... you@host"

# ---------- VM inventory ----------
vms = {

  # Windows TEMPLATE + extra disk  -> separate 100 GB disk
  "Infraterra-win" = {
    cpu_cores          = 2
    memory_mb          = 8192
    subnet_name        = "NKP-VLAN"
    image_name         = "WIN2022-terra"
    os_type            = "windows"
    image_type         = "template"
    boot_type          = "LEGACY"           # change to "UEFI" if the template was built as UEFI
    extra_disk_size_gb = 100                # creates a separate secondary data disk for Windows
    ip_address         = "192.168.41.174"
    subnet_cidr        = "24"
    gateway            = "192.168.41.1"
   # dns_servers = "8.8.8.8"
  }

  # Linux TEMPLATE. To also grow the root disk, uncomment extra_disk_size_gb
  # AND set template_disk_size_gb for "Ubuntu 24.04" in images.auto.tfvars.
  #"lnx-app-demo-01" = {
  # cpu_cores   = 2
  #memory_mb   = 4096
  #subnet_name = "NKP-VLAN"
  #image_name  = "Ubuntu 24.04"
  # extra_disk_size_gb = 50
  #}

  # ISO install (blank 80 GB OS disk + CD-ROM)
  #"iso-test-01" = {
  # cpu_cores       = 2
  #memory_mb       = 4096
  #subnet_name     = "NKP-VLAN"
  #image_name      = "Ubuntu-Server 24.04 LTS"
  #os_disk_size_gb = 80
  #}
}
