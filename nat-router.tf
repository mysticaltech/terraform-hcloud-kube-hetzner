locals {
 nat_gateway_ip = var.nat_router != null ? cidrhost(hcloud_network_subnet.nat_router[0].ip_range, 1) : ""

  nat_router_ip = var.nat_router != null && var.nat_router.enable_redundancy ? {
    0 = cidrhost(hcloud_network_subnet.nat_router[0].ip_range, 2),
    1 = cidrhost(hcloud_network_subnet.nat_router[0].ip_range, 3)
  } : {
    0 = local.nat_gateway_ip
  }

  nat_router_name_basename = "nat-router"
  nat_router_name          = "${var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""}${local.nat_router_name_basename}"
}

resource "random_string" "nat_router" {
  count = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  length  = 3
  lower   = true
  special = false
  numeric = false
  upper   = false

  keepers = {
    # We re-create the apart of the name changes.
    name = local.nat_router_name
  }
}

resource "random_password" "nat_router_vip_auth_pass" {
  length = 8
  special = false
}

data "cloudinit_config" "nat_router_config" {
  count = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/templates/nat-router-cloudinit.yaml.tpl",
      {
        hostname                   = "nat-router"
        dns_servers                = var.dns_servers
        has_dns_servers            = local.has_dns_servers
        sshAuthorizedKeys          = concat([var.ssh_public_key], var.ssh_additional_public_keys)
        enable_sudo                = var.nat_router.enable_sudo
        enable_redundancy          = var.nat_router.enable_redundancy
        priority                   = count.index == 0 ? 150 : 100
        my_private_ip              = local.nat_router_ip[count.index]
        peer_private_ip            = var.nat_router.enable_redundancy ? local.nat_router_ip[(count.index == 0 ? 1 : 0)] : null
        hcloud_token               = var.nat_router_hcloud_token
        network_id                 = data.hcloud_network.k3s.id
        vip                        = local.nat_gateway_ip
        vip_auth_pass              = var.nat_router.enable_redundancy ? random_password.nat_router_vip_auth_pass.result : ""
        private_network_ipv4_range = data.hcloud_network.k3s.ip_range
        ssh_port                   = var.ssh_port
        ssh_max_auth_tries         = var.ssh_max_auth_tries
        enable_cp_lb_port_forward  = var.use_control_plane_lb && !var.control_plane_lb_enable_public_interface
        cp_lb_private_ip           = hcloud_load_balancer_network.control_plane.*.ip[0]
      }
    )
  }
}

resource "hcloud_network_route" "nat_route_public_internet" {
  count        = var.nat_router != null ? 1 : 0
  network_id  = data.hcloud_network.k3s.id
  destination = "0.0.0.0/0"
  gateway     = local.nat_gateway_ip
}

resource "hcloud_primary_ip" "nat_router_primary_ipv4" {
  # explicitly declare the ipv4 address, such that the address
  # is stable against possible replacements of the nat router
  count         = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0
  type          = "ipv4"
  name          = "${local.nat_router_name}-${random_string.nat_router[count.index].id}-ipv4"
  location      = var.nat_router.enable_redundancy && count.index == 1 ? var.nat_router.standby_location : var.nat_router.location
  auto_delete   = false
  assignee_type = "server"

  # Prevent recreation when user changes location after initial creation
  lifecycle {
    ignore_changes = [location]
  }
}

resource "hcloud_primary_ip" "nat_router_primary_ipv6" {
  # explicitly declare the ipv6 address, such that the address
  # is stable against possible replacements of the nat router
  count         = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0
  type          = "ipv6"
  name          = "${local.nat_router_name}-${random_string.nat_router[count.index].id}-ipv6"
  location      = var.nat_router.enable_redundancy && count.index == 1 ? var.nat_router.standby_location : var.nat_router.location
  auto_delete   = false
  assignee_type = "server"

  # Prevent recreation when user changes location after initial creation
  lifecycle {
    ignore_changes = [location]
  }
}

resource "hcloud_server" "nat_router" {
  count        = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0
  name         = "${local.nat_router_name}-${random_string.nat_router[count.index].id}"
  image        = "debian-12"
  server_type  = var.nat_router.server_type
  location     = var.nat_router.enable_redundancy && count.index == 1 ? var.nat_router.standby_location : var.nat_router.location
  ssh_keys     = length(var.ssh_hcloud_key_label) > 0 ? concat([local.hcloud_ssh_key_id], data.hcloud_ssh_keys.keys_by_selector[0].ssh_keys.*.id) : [local.hcloud_ssh_key_id]
  firewall_ids = [hcloud_firewall.k3s.id]
  user_data    = data.cloudinit_config.nat_router_config[count.index].rendered
  keep_disk    = false
  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.nat_router_primary_ipv4[count.index].id
    ipv6_enabled = true
    ipv6         = hcloud_primary_ip.nat_router_primary_ipv6[count.index].id
  }

  network {
    network_id = data.hcloud_network.k3s.id
    ip         = local.nat_router_ip[count.index]
    alias_ips  = []
  }

  labels = merge(
    {
      role = "nat_router"
    },
    try(var.nat_router.labels, {}),
  )

  lifecycle {
    ignore_changes = [network] # Ignore the additional alias ip added by keepalived
  }

}

resource "terraform_data" "nat_router_await_cloud_init" {
  count = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  depends_on = [
    hcloud_network_route.nat_route_public_internet,
    hcloud_server.nat_router,
  ]

  triggers_replace = {
    config = data.cloudinit_config.nat_router_config[count.index].rendered
  }

  connection {
    user           = "nat-router"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = hcloud_server.nat_router[0].ipv4_address
    port           = var.ssh_port
  }

  provisioner "remote-exec" {
    inline = ["cloud-init status --wait > /dev/null || echo 'Ready to move on'"]
    # on_failure = continue # this will fail because the reboot 
  }
}
moved {
  from = null_resource.nat_router_await_cloud_init
  to   = terraform_data.nat_router_await_cloud_init
}