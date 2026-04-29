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

  cni_plugin                 = "cilium"
  enable_kube_proxy          = false
  cilium_gateway_api_enabled = true
  enable_cert_manager        = true

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
      count       = 1
    }
  ]

  user_kustomizations = {
    "1" = {
      source_folder = "${path.module}/extra-manifests"
      kustomize_parameters = {
        gateway_hostname  = var.gateway_hostname
        certificate_email = var.certificate_email
      }
    }
  }
}

output "kubeconfig" {
  value     = module.kube-hetzner.kubeconfig
  sensitive = true
}

output "effective_kubeconfig_endpoint" {
  value = module.kube-hetzner.effective_kubeconfig_endpoint
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

variable "cluster_name" {
  description = "Cluster name prefix."
  type        = string
  default     = "cilium-gateway-demo"
}

variable "gateway_hostname" {
  description = "DNS hostname routed to the Cilium Gateway LoadBalancer."
  type        = string
}

variable "certificate_email" {
  description = "Email address used by the Let's Encrypt staging ClusterIssuer."
  type        = string
}
