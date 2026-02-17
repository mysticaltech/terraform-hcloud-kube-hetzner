resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "hcloud_ssh_key" "k3s" {
  count      = var.hcloud_ssh_key_id == null ? 1 : 0
  name       = var.cluster_name
  public_key = var.ssh_public_key
  labels     = local.labels
}

resource "hcloud_network" "k3s" {
  count                    = local.use_existing_network || local.use_multi_networks ? 0 : 1
  name                     = var.cluster_name
  ip_range                 = local.network_ip_ranges[local.primary_network_key]
  labels                   = local.labels
  expose_routes_to_vswitch = local.network_expose_routes_to_vswitch[local.primary_network_key]
}

resource "hcloud_network" "k3s_multi" {
  for_each = local.use_multi_networks ? {
    for network_key in local.network_keys :
    network_key => {
      ip_range                 = local.network_ip_ranges[network_key]
      expose_routes_to_vswitch = local.network_expose_routes_to_vswitch[network_key]
    }
  } : {}

  name                     = "${var.cluster_name}-${each.key}"
  ip_range                 = each.value.ip_range
  labels                   = local.labels
  expose_routes_to_vswitch = each.value.expose_routes_to_vswitch
}

data "hcloud_network" "k3s" {
  id = local.primary_network_id
}

check "public_join_endpoint_requires_public_control_plane_lb" {
  assert {
    condition     = !local.any_public_join_endpoint || (var.use_control_plane_lb && var.control_plane_lb_enable_public_interface)
    error_message = "join_endpoint_type=\"public\" requires use_control_plane_lb=true and control_plane_lb_enable_public_interface=true."
  }
}


# We start from the end of the subnets cidr array,
# as we would have fewer control plane nodepools, than agent ones.
resource "hcloud_network_subnet" "control_plane" {
  count        = local.use_multi_networks ? 0 : length(var.control_plane_nodepools)
  network_id   = data.hcloud_network.k3s.id
  type         = "cloud"
  network_zone = local.network_zones[local.primary_network_key]
  ip_range     = local.network_ipv4_subnets[var.subnet_amount - 1 - count.index]
}

# Here we start at the beginning of the subnets cidr array
resource "hcloud_network_subnet" "agent" {
  count        = local.use_multi_networks ? 0 : length(var.agent_nodepools)
  network_id   = data.hcloud_network.k3s.id
  type         = "cloud"
  network_zone = local.network_zones[local.primary_network_key]
  ip_range     = coalesce(var.agent_nodepools[count.index].subnet_ip_range, local.network_ipv4_subnets[count.index])
}

resource "hcloud_network_subnet" "control_plane_multi" {
  for_each = local.control_plane_subnet_specs_multi

  network_id   = local.network_ids[each.value.network_key]
  type         = "cloud"
  network_zone = each.value.network_zone
  ip_range     = each.value.ip_range
}

resource "hcloud_network_subnet" "agent_multi" {
  for_each = local.agent_subnet_specs_multi

  network_id   = local.network_ids[each.value.network_key]
  type         = "cloud"
  network_zone = each.value.network_zone
  ip_range     = each.value.ip_range
}

# Subnet for NAT router and other peripherals
resource "hcloud_network_subnet" "nat_router" {
  count        = var.nat_router != null ? 1 : 0
  network_id   = local.primary_network_id
  type         = "cloud"
  network_zone = local.network_zones[local.primary_network_key]
  ip_range     = local.network_ipv4_subnets[var.nat_router_subnet_index]
}

# Subnet for vSwitch
resource "hcloud_network_subnet" "vswitch_subnet" {
  count        = var.vswitch_id != null ? 1 : 0
  network_id   = local.primary_network_id
  type         = "vswitch"
  network_zone = local.network_zones[local.primary_network_key]
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
