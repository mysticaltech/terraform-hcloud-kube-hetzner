resource "terraform_data" "tailscale_control_planes" {
  for_each = local.tailscale_remote_exec_bootstrap_enabled ? local.control_plane_nodes : {}

  triggers_replace = {
    control_plane_id = module.control_planes[each.key].id
    bootstrap_mode   = var.tailscale_node_transport.bootstrap_mode
    version          = var.tailscale_node_transport.version
    tags             = join(",", var.tailscale_node_transport.auth.advertise_tags_control_plane)
    auth_mode        = var.tailscale_node_transport.auth.mode
    routes           = join(",", local.tailscale_advertise_additional_routes)
    route_probe      = local.network_gw_ipv4_by_network_id[local.control_plane_primary_network_id_by_node[each.key]]
    ssh              = tostring(var.tailscale_node_transport.ssh.enable_tailscale_ssh)
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.control_plane_initial_ips[each.key]
    port           = var.ssh_port
    timeout        = "10m"

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  provisioner "remote-exec" {
    inline = [local.tailscale_bootstrap_script_static_control_plane_by_node[each.key]]
  }
}

resource "terraform_data" "tailscale_agents" {
  for_each = local.tailscale_remote_exec_bootstrap_enabled ? local.agent_nodes : {}

  triggers_replace = {
    agent_id       = module.agents[each.key].id
    bootstrap_mode = var.tailscale_node_transport.bootstrap_mode
    version        = var.tailscale_node_transport.version
    tags           = join(",", var.tailscale_node_transport.auth.advertise_tags_agent)
    auth_mode      = var.tailscale_node_transport.auth.mode
    routes         = join(",", local.tailscale_advertise_additional_routes)
    route_probe    = local.network_gw_ipv4_by_network_id[local.agent_primary_network_id_by_node[each.key]]
    ssh            = tostring(var.tailscale_node_transport.ssh.enable_tailscale_ssh)
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.agent_initial_ips[each.key]
    port           = var.ssh_port
    timeout        = "10m"

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  provisioner "remote-exec" {
    inline = [local.tailscale_bootstrap_script_static_agent_by_node[each.key]]
  }
}
