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
  cni_plugin              = var.cni_plugin
  cilium_routing_mode     = var.cilium_routing_mode
  calico_values           = var.calico_values
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

  ingress_controller                                = var.ingress_controller
  enable_klipper_metal_lb                           = false
  enable_control_plane_load_balancer                = var.enable_control_plane_load_balancer
  control_plane_load_balancer_enable_public_network = var.control_plane_load_balancer_enable_public_network
  control_plane_endpoint                            = var.control_plane_endpoint
  multinetwork_mode                                 = var.multinetwork_mode
  enable_experimental_cilium_public_overlay         = var.enable_experimental_cilium_public_overlay
  multinetwork_transport_ip_family                  = var.multinetwork_transport_ip_family
  node_transport_mode                               = var.node_transport_mode
  firewall_kube_api_source                          = var.firewall_kube_api_source
  firewall_ssh_source                               = var.firewall_ssh_source
  extra_firewall_ids                                = var.extra_firewall_ids
  tailscale_auth_key                                = var.tailscale_auth_key
  tailscale_node_transport                          = var.tailscale_node_transport
  cluster_ipv4_cidr                                 = var.cluster_ipv4_cidr
  service_ipv4_cidr                                 = var.service_ipv4_cidr
  cluster_ipv6_cidr                                 = var.cluster_ipv6_cidr
  service_ipv6_cidr                                 = var.service_ipv6_cidr

  nginx_values       = var.nginx_values
  nginx_merge_values = var.nginx_merge_values

  control_plane_nodepools               = var.control_plane_nodepools
  agent_nodepools                       = var.agent_nodepools
  autoscaler_nodepools                  = var.autoscaler_nodepools
  cluster_autoscaler_snapshot_selection = var.cluster_autoscaler_snapshot_selection
  nat_router                            = var.nat_router
  vswitch_id                            = var.vswitch_id
  extra_robot_nodes                     = var.extra_robot_nodes
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

variable "cni_plugin" {
  type    = string
  default = "flannel"
}

variable "cilium_routing_mode" {
  type    = string
  default = "tunnel"
}

variable "calico_values" {
  type    = string
  default = ""
}

variable "ingress_controller" {
  type    = string
  default = "nginx"
}

variable "enable_control_plane_load_balancer" {
  type    = bool
  default = false
}

variable "control_plane_load_balancer_enable_public_network" {
  type    = bool
  default = true
}

variable "control_plane_endpoint" {
  type    = string
  default = null
}

variable "multinetwork_mode" {
  type    = string
  default = "disabled"
}

variable "enable_experimental_cilium_public_overlay" {
  type    = bool
  default = false
}

variable "multinetwork_transport_ip_family" {
  type    = string
  default = "ipv4"
}

variable "node_transport_mode" {
  type    = string
  default = "hetzner_private"
}

variable "firewall_kube_api_source" {
  type    = any
  default = ["0.0.0.0/0", "::/0"]
}

variable "firewall_ssh_source" {
  type    = any
  default = ["0.0.0.0/0", "::/0"]
}

variable "tailscale_auth_key" {
  type    = string
  default = null
}

variable "tailscale_node_transport" {
  type    = any
  default = {}
}

variable "cluster_ipv4_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

variable "service_ipv4_cidr" {
  type    = string
  default = "10.43.0.0/16"
}

variable "cluster_ipv6_cidr" {
  type    = string
  default = null
}

variable "service_ipv6_cidr" {
  type    = string
  default = null
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

variable "autoscaler_nodepools" {
  type    = any
  default = []
}

variable "nat_router" {
  type    = any
  default = null
}

variable "vswitch_id" {
  type    = number
  default = null
}

variable "extra_robot_nodes" {
  type    = any
  default = []
}

variable "extra_firewall_ids" {
  type    = list(number)
  default = []
}

variable "cluster_autoscaler_snapshot_selection" {
  type    = string
  default = "id"
}
