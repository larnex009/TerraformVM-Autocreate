terraform {
  required_version = ">= 1.9.0"

  required_providers {
    nutanix = {
      source  = "nutanix/nutanix"
      version = "~> 1.9.0"
    }
  }
}

# Talks to PRISM CENTRAL (not an individual Prism Element)
provider "nutanix" {
  username     = var.nutanix_user
  password     = var.nutanix_password
  endpoint     = var.nutanix_endpoint
  port         = var.nutanix_port
  insecure     = var.nutanix_insecure
  wait_timeout = 60 # minutes to wait for a task (VM create etc.)
}
