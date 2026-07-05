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

module "sut" {
  source = "../.."

  providers = {
    hcloud = hcloud
  }

  hcloud_token    = var.hcloud_token
  ssh_public_key  = var.ssh_public_key
  ssh_private_key = null

  cluster_name            = "render-fixture"
  kubernetes_distribution = var.kubernetes_distribution
  network_region          = "eu-central"
  enabled_architectures   = ["x86"]

  leapmicro_x86_snapshot_id = "123456"
  microos_x86_snapshot_id   = "123456"

  hetzner_ccm_version              = "v1.25.0"
  kured_version                    = "1.18.0"
  enable_hetzner_csi               = false
  enable_longhorn                  = false
  enable_cert_manager              = false
  enable_rancher                   = false
  enable_system_upgrade_controller = false

  ingress_controller                 = var.ingress_controller
  enable_klipper_metal_lb            = false
  enable_control_plane_load_balancer = var.enable_control_plane_load_balancer

  nginx_values       = var.nginx_values
  nginx_merge_values = var.nginx_merge_values

  control_plane_nodepools = var.control_plane_nodepools
  agent_nodepools         = var.agent_nodepools
  nat_router              = var.nat_router
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type = string
}

variable "kubernetes_distribution" {
  type    = string
  default = "k3s"
}

variable "ingress_controller" {
  type    = string
  default = "nginx"
}

variable "enable_control_plane_load_balancer" {
  type    = bool
  default = false
}

variable "nginx_values" {
  type    = string
  default = ""
}

variable "nginx_merge_values" {
  type    = string
  default = ""
}

variable "control_plane_nodepools" {
  type = any
}

variable "agent_nodepools" {
  type = any
}

variable "nat_router" {
  type    = any
  default = null
}
