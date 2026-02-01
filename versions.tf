terraform {
  required_version = ">= 1.8.0"
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 6.4.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.59.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.2"
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

# Prevent provider picking up `GITHUB_TOKEN` env var and trying to authenticate
provider "github" {
  token = ""
}
