resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "random_password" "secrets_encryption_key" {
  count   = var.secrets_encryption ? 1 : 0
  length  = 32
  special = false
}

check "encryption_mode_conflict" {
  assert {
    condition     = !(var.k3s_encryption_at_rest && var.secrets_encryption)
    error_message = "k3s_encryption_at_rest and secrets_encryption are mutually exclusive. Enable only one encryption mode."
  }
}

resource "hcloud_ssh_key" "k3s" {
  count      = var.hcloud_ssh_key_id == null && local.existing_hcloud_ssh_key_id == null ? 1 : 0
  name       = var.cluster_name
  public_key = var.ssh_public_key
  labels     = local.labels
}

data "hcloud_ssh_keys" "k3s_existing" {
  count = var.hcloud_ssh_key_id == null ? 1 : 0
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

data "hcloud_network" "additional_nodepool_networks" {
  for_each = local.external_nodepool_network_ids
  id       = tonumber(each.key)
}


resource "hcloud_network_subnet" "control_plane" {
  count        = local.use_per_nodepool_subnets ? length(var.control_plane_nodepools) : 1
  network_id   = data.hcloud_network.k3s.id
  type         = "cloud"
  network_zone = var.network_region
  ip_range     = local.use_per_nodepool_subnets ? local.network_ipv4_subnets[var.subnet_amount - 1 - count.index] : local.network_ipv4_subnets[var.subnet_amount - 1]
}

resource "hcloud_network_subnet" "agent" {
  count        = local.use_per_nodepool_subnets ? length(var.agent_nodepools) : 1
  network_id   = data.hcloud_network.k3s.id
  type         = "cloud"
  network_zone = var.network_region
  ip_range     = local.use_per_nodepool_subnets ? coalesce(var.agent_nodepools[count.index].subnet_ip_range, local.network_ipv4_subnets[count.index]) : local.network_ipv4_subnets[0]
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

check "network_attachment_limit_control_planes" {
  assert {
    condition     = alltrue([for _, attachments in local.control_plane_total_network_attachments_by_node : attachments <= 3])
    error_message = "A Hetzner server can be attached to at most 3 private networks. Reduce extra_network_ids or network_id fan-out for control planes."
  }
}

check "multinetwork_control_plane_on_primary_network" {
  assert {
    condition     = alltrue([for _, node in local.control_plane_nodes : node.network_id == 0])
    error_message = "Control plane nodepools must currently use network_id=0 (module primary network). External control-plane network_id values are not supported yet."
  }
}

check "network_attachment_limit_agents" {
  assert {
    condition     = alltrue([for _, attachments in local.agent_total_network_attachments_by_node : attachments <= 3])
    error_message = "A Hetzner server can be attached to at most 3 private networks. Reduce extra_network_ids or network_id fan-out for agents."
  }
}

check "network_server_limit" {
  assert {
    condition = alltrue([
      for network_id in local.cluster_primary_network_keys :
      (
        length([for _, node in local.control_plane_nodes : 1 if node.network_id == network_id]) +
        length([for _, node in local.agent_nodes : 1 if node.network_id == network_id])
      ) <= 100
    ])
    error_message = "Each Hetzner private network supports up to 100 attached servers. Distribute nodepools across network_id values."
  }
}

check "multinetwork_requires_public_join_endpoint" {
  assert {
    condition     = !local.uses_multi_primary_network || var.control_plane_endpoint != null || (var.use_control_plane_lb && var.control_plane_lb_enable_public_interface)
    error_message = "When using multiple primary private networks, set control_plane_endpoint (publicly reachable) or enable a public control-plane load balancer."
  }
}

check "multinetwork_autoscaler_not_supported" {
  assert {
    condition     = !(local.uses_multi_primary_network && length(var.autoscaler_nodepools) > 0)
    error_message = "Cluster autoscaler currently supports only a single HCLOUD_NETWORK. Disable autoscaler or use a single primary network."
  }
}
