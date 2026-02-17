terraform {
  required_version = ">= 1.10.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.59.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.32.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.15.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

module "kube-hetzner" {
  source = "kube-hetzner/kube-hetzner/hcloud"

  providers = {
    hcloud = hcloud
  }

  hcloud_token    = var.hcloud_token
  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  cluster_name = var.cluster_name

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
}

locals {
  kubeconfig_data = module.kube-hetzner.kubeconfig_data
}

provider "kubernetes" {
  host                   = local.kubeconfig_data.host
  client_certificate     = local.kubeconfig_data.client_certificate
  client_key             = local.kubeconfig_data.client_key
  cluster_ca_certificate = local.kubeconfig_data.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = local.kubeconfig_data.host
    client_certificate     = local.kubeconfig_data.client_certificate
    client_key             = local.kubeconfig_data.client_key
    cluster_ca_certificate = local.kubeconfig_data.cluster_ca_certificate
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.3.6"
  create_namespace = true

  depends_on = [module.kube-hetzner]
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
  default     = "argocd-demo"
}
