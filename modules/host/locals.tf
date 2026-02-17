locals {
  # ssh_agent_identity is not set if the private key is passed directly, but if ssh agent is used, the public key tells ssh agent which private key to use.
  # For terraforms provisioner.connection.agent_identity, we need the public key as a string.
  ssh_agent_identity = var.ssh_private_key == null ? var.ssh_public_key : null

  # the hosts name with its unique suffix attached
  name = var.append_random_suffix ? "${var.name}-${random_string.server.id}" : var.name

  # check if the user has set dns servers
  has_dns_servers = length(var.dns_servers) > 0

  default_connection_host = coalesce(
    hcloud_server.server.ipv4_address,
    hcloud_server.server.ipv6_address,
    try(one(hcloud_server.server.network).ip, null)
  )

  provisioner_connection_host = trimspace(var.connection_host) != "" ? var.connection_host : local.default_connection_host
}
