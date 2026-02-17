resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "random_password" "secrets_encryption_key" {
  count   = var.secrets_encryption ? 1 : 0
  length  = 32
  special = false
}

resource "hcloud_ssh_key" "k3s" {
  count      = var.hcloud_ssh_key_id == null ? 1 : 0
  name       = var.cluster_name
  public_key = var.ssh_public_key
  labels     = local.labels
}

resource "hcloud_network" "k3s" {
  count                    = local.use_existing_network ? 0 : 1
  name                     = var.cluster_name
  ip_range                 = var.network_ipv4_cidr
  labels                   = local.labels
  expose_routes_to_vswitch = var.vswitch_id != null
}

data "hcloud_network" "k3s" {
  id = local.use_existing_network ? var.existing_network_id[0] : hcloud_network.k3s[0].id
}


# Shared cluster subnet used for auto-assigned node private IPv4 addresses.
resource "hcloud_network_subnet" "control_plane" {
  count        = 1
  network_id   = data.hcloud_network.k3s.id
  type         = "cloud"
  network_zone = var.network_region
  ip_range     = local.network_ipv4_subnets[0]
}

# Agent subnet allocation is consolidated into the shared control_plane subnet.
resource "hcloud_network_subnet" "agent" {
  count        = 0
  network_id   = data.hcloud_network.k3s.id
  type         = "cloud"
  network_zone = var.network_region
  ip_range     = local.network_ipv4_subnets[0]
}

# Subnet for NAT router and other peripherals
resource "hcloud_network_subnet" "nat_router" {
  count        = var.nat_router != null ? 1 : 0
  network_id   = data.hcloud_network.k3s.id
  type         = "cloud"
  network_zone = var.network_region
  ip_range     = local.network_ipv4_subnets[var.nat_router_subnet_index]
}

# Subnet for vSwitch
resource "hcloud_network_subnet" "vswitch_subnet" {
  count        = var.vswitch_id != null ? 1 : 0
  network_id   = data.hcloud_network.k3s.id
  type         = "vswitch"
  network_zone = var.network_region
  ip_range     = local.network_ipv4_subnets[var.vswitch_subnet_index]
  vswitch_id   = var.vswitch_id
}

resource "hcloud_firewall" "k3s" {
  name   = var.cluster_name
  labels = local.labels

  dynamic "rule" {
    for_each = local.firewall_rules_list
    content {
      description     = rule.value.description
      direction       = rule.value.direction
      protocol        = rule.value.protocol
      port            = lookup(rule.value, "port", null)
      destination_ips = lookup(rule.value, "destination_ips", [])
      source_ips      = lookup(rule.value, "source_ips", [])
    }
  }

  lifecycle {
    precondition {
      condition     = !local.is_ref_myipv4_used || local.my_public_ipv4_cidr != null
      error_message = "Unable to resolve 'myipv4' to a valid public IPv4 address from https://ipv4.icanhazip.com."
    }
  }
}
