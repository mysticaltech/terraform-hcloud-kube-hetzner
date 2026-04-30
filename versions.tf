terraform {
  required_version = ">= 1.10.1"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.62.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.2"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.8.1"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.7"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.1.1"
    }
    ssh = {
      source  = "loafoe/ssh"
      version = "2.7.0"
    }
    assert = {
      source  = "hashicorp/assert"
      version = ">= 0.16.0"
    }
    semvers = {
      source  = "anapsix/semvers"
      version = ">= 0.7.1"
    }
  }
}
