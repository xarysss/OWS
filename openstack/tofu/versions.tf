terraform {
  required_version = ">= 1.8.0" # validations croisées entre variables

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # État local (dans /home/ows/OWS/openstack/tofu), jamais commité (.gitignore).
  # Pour travailler à deux, passer à un backend distant (ex. S3 Swift du projet).
}

# Les identifiants viennent de ~/.config/openstack/clouds.yaml (jamais dans Git).
# export OS_CLOUD=ows   avant tofu plan/apply.
provider "openstack" {
  cloud = var.os_cloud
}
