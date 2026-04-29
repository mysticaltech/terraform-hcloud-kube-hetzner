terraform {
  required_version = ">= 1.10.1"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.62.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

module "kube-hetzner" {
  source = "kube-hetzner/kube-hetzner/hcloud"
  # Pin to v3 once released.
  # version = "3.0.0"

  providers = {
    hcloud = hcloud
  }

  hcloud_token    = var.hcloud_token
  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  cluster_name       = var.cluster_name
  ingress_controller = "none"

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cx23"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  agent_nodepools = [
    {
      name        = "agent"
      server_type = "cx23"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 2
    }
  ]

  node_transport_mode      = "tailscale"
  firewall_kube_api_source = null
  firewall_ssh_source      = null

  tailscale_auth_key = var.tailscale_auth_key
  tailscale_node_transport = {
    bootstrap_mode  = "cloud_init"
    magicdns_domain = var.tailscale_magicdns_domain

    auth = {
      mode = "auth_key"
    }

    routing = {
      advertise_node_private_routes = false
    }
  }
}

output "kubeconfig" {
  value     = module.kube-hetzner.kubeconfig
  sensitive = true
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key content for cluster nodes."
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key content for Terraform provisioners."
  type        = string
  sensitive   = true
}

variable "tailscale_auth_key" {
  description = "Reusable Tailscale auth key for cluster nodes."
  type        = string
  sensitive   = true
}

variable "tailscale_magicdns_domain" {
  description = "Tailnet MagicDNS domain, for example example-tailnet.ts.net."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name prefix."
  type        = string
  default     = "tailscale-demo"
}
