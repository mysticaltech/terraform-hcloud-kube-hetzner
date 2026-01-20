locals {
  nat_router_ip = var.nat_router != null ? cidrhost(hcloud_network_subnet.nat_router[0].ip_range, 1) : ""
}

data "cloudinit_config" "nat_router_config" {
  count = var.nat_router != null ? 1 : 0

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
  count       = var.nat_router != null ? 1 : 0
  network_id  = data.hcloud_network.k3s.id
  destination = "0.0.0.0/0"
  gateway     = local.nat_router_ip
}

resource "hcloud_primary_ip" "nat_router_primary_ipv4" {
  # explicitly declare the ipv4 address, such that the address
  # is stable against possible replacements of the nat router
  count         = var.nat_router != null ? 1 : 0
  type          = "ipv4"
  name          = "${var.cluster_name}-nat-router-ipv4"
  location      = var.nat_router.location
  auto_delete   = false
  assignee_type = "server"
}

resource "hcloud_primary_ip" "nat_router_primary_ipv6" {
  # explicitly declare the ipv4 address, such that the address
  # is stable against possible replacements of the nat router
  count         = var.nat_router != null ? 1 : 0
  type          = "ipv6"
  name          = "${var.cluster_name}-nat-router-ipv6"
  location      = var.nat_router.location
  auto_delete   = false
  assignee_type = "server"
}
resource "hcloud_server" "nat_router" {
  count        = var.nat_router != null ? 1 : 0
  name         = "${var.cluster_name}-nat-router"
  image        = "debian-12"
  server_type  = var.nat_router.server_type
  location     = var.nat_router.location
  ssh_keys     = length(var.ssh_hcloud_key_label) > 0 ? concat([local.hcloud_ssh_key_id], data.hcloud_ssh_keys.keys_by_selector[0].ssh_keys.*.id) : [local.hcloud_ssh_key_id]
  firewall_ids = [hcloud_firewall.k3s.id]
  user_data    = data.cloudinit_config.nat_router_config[0].rendered
  keep_disk    = false
  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.nat_router_primary_ipv4[0].id
    ipv6_enabled = true
    ipv6         = hcloud_primary_ip.nat_router_primary_ipv6[0].id
  }

  network {
    network_id = data.hcloud_network.k3s.id
    ip         = local.nat_router_ip
    alias_ips  = []
  }

  labels = merge(
    {
      role = "nat_router"
    },
    try(var.nat_router.labels, {}),
  )

}

resource "null_resource" "nat_router_await_cloud_init" {
  count = var.nat_router != null ? 1 : 0

  depends_on = [
    hcloud_network_route.nat_route_public_internet,
    hcloud_server.nat_router,
  ]

  triggers = {
    config = data.cloudinit_config.nat_router_config[0].rendered
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
