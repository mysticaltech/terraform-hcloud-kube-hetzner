locals {
  hcloud_token = "xxxxxxxxxxx"
}

module "kube-hetzner" {
  providers = {
    hcloud = hcloud
  }

  source       = "kube-hetzner/kube-hetzner/hcloud"
  hcloud_token = var.hcloud_token != "" ? var.hcloud_token : local.hcloud_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  cluster_name            = var.cluster_name
  kubernetes_distribution = var.kubernetes_distribution
  ingress_controller      = var.ingress_controller
  ingress_replica_count   = var.ingress_replica_count

  leapmicro_x86_snapshot_id = var.leapmicro_x86_snapshot_id
  leapmicro_arm_snapshot_id = var.leapmicro_arm_snapshot_id
  microos_x86_snapshot_id   = var.microos_x86_snapshot_id
  microos_arm_snapshot_id   = var.microos_arm_snapshot_id

  network_region = "eu-central"

  control_plane_nodepools = [
    {
      name        = "control-plane-nbg1"
      server_type = "cx23"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  agent_nodepools = [
    {
      name        = "agent-small"
      server_type = "cx23"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]
}

provider "hcloud" {
  token = var.hcloud_token != "" ? var.hcloud_token : local.hcloud_token
}

terraform {
  required_version = ">= 1.10.1"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.59.0"
    }
  }
}

output "kubeconfig" {
  value     = module.kube-hetzner.kubeconfig
  sensitive = true
}

variable "hcloud_token" {
  sensitive = true
  default   = ""
}

variable "kubernetes_distribution" {
  type        = string
  default     = "k3s"
  description = "Kubernetes distribution type. Can be either k3s or rke2."
}

variable "ingress_controller" {
  type        = string
  default     = "traefik"
  description = "The ingress controller to deploy. Valid values are traefik, nginx, haproxy, none, and custom."
}

variable "ingress_replica_count" {
  type        = number
  default     = 0
  description = "Number of replicas per ingress controller. 0 means autodetect based on the number of agent nodes."
}

variable "cluster_name" {
  type        = string
  default     = "k3s"
  description = "Name of the cluster."
}

variable "leapmicro_x86_snapshot_id" {
  type    = string
  default = ""
}

variable "leapmicro_arm_snapshot_id" {
  type    = string
  default = ""
}

variable "microos_x86_snapshot_id" {
  type    = string
  default = ""
}

variable "microos_arm_snapshot_id" {
  type    = string
  default = ""
}
