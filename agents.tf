resource "hcloud_primary_ip" "agents_ipv4" {
  for_each = var.primary_ip_pool.enable_ipv4 ? {
    for key, value in local.agent_nodes : key => value
    if !value.disable_ipv4 && value.primary_ipv4_id == null
  } : {}

  type          = "ipv4"
  name          = "${var.cluster_name}-agent-${each.key}-ipv4"
  location      = each.value.location
  auto_delete   = var.primary_ip_pool.auto_delete
  assignee_type = "server"

  lifecycle {
    ignore_changes = [location]
  }
}

resource "hcloud_primary_ip" "agents_ipv6" {
  for_each = var.primary_ip_pool.enable_ipv6 ? {
    for key, value in local.agent_nodes : key => value
    if !value.disable_ipv6 && value.primary_ipv6_id == null
  } : {}

  type          = "ipv6"
  name          = "${var.cluster_name}-agent-${each.key}-ipv6"
  location      = each.value.location
  auto_delete   = var.primary_ip_pool.auto_delete
  assignee_type = "server"

  lifecycle {
    ignore_changes = [location]
  }
}

module "agents" {
  source = "./modules/host"

  providers = {
    hcloud = hcloud,
  }

  for_each = local.agent_nodes

  name                             = "${var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""}${each.value.nodepool_name}${try(each.value.node_name_suffix, "")}"
  connection_host                  = lookup(var.node_connection_overrides, "${var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""}${each.value.nodepool_name}${try(each.value.node_name_suffix, "")}", "")
  os_snapshot_id                   = local.snapshot_id_by_os[each.value.os][substr(each.value.server_type, 0, 3) == "cax" ? "arm" : "x86"]
  os                               = each.value.os
  base_domain                      = var.base_domain
  ssh_keys                         = length(var.ssh_hcloud_key_label) > 0 ? concat([local.hcloud_ssh_key_id], data.hcloud_ssh_keys.keys_by_selector[0].ssh_keys.*.id) : [local.hcloud_ssh_key_id]
  ssh_port                         = var.ssh_port
  ssh_public_key                   = var.ssh_public_key
  ssh_private_key                  = var.ssh_private_key
  ssh_additional_public_keys       = length(var.ssh_hcloud_key_label) > 0 ? concat(var.ssh_additional_public_keys, data.hcloud_ssh_keys.keys_by_selector[0].ssh_keys.*.public_key) : var.ssh_additional_public_keys
  firewall_ids                     = each.value.disable_ipv4 && each.value.disable_ipv6 ? [] : [hcloud_firewall.k3s.id] # Cannot attach a firewall when public interfaces are disabled
  extra_firewall_ids               = each.value.disable_ipv4 && each.value.disable_ipv6 ? [] : var.extra_firewall_ids
  placement_group_id               = var.placement_group_disable ? null : (each.value.placement_group == null ? hcloud_placement_group.agent[each.value.placement_group_compat_idx].id : hcloud_placement_group.agent_named[each.value.placement_group].id)
  location                         = each.value.location
  server_type                      = each.value.server_type
  backups                          = each.value.backups
  ipv4_subnet_id                   = hcloud_network_subnet.control_plane[0].id
  dns_servers                      = var.dns_servers
  k3s_registries                   = var.k3s_registries
  k3s_registries_update_script     = local.k3s_registries_update_script
  cloudinit_write_files_common     = local.cloudinit_write_files_common
  k3s_kubelet_config               = var.k3s_kubelet_config
  k3s_kubelet_config_update_script = local.k8s_kubelet_config_update_script
  k3s_audit_policy_config          = ""
  k3s_audit_policy_update_script   = ""
  cloudinit_runcmd_common          = local.cloudinit_runcmd_common
  cloudinit_write_files_extra      = each.value.extra_write_files
  cloudinit_runcmd_extra           = each.value.extra_runcmd
  swap_size                        = each.value.swap_size
  zram_size                        = each.value.zram_size
  keep_disk_size                   = coalesce(each.value.keep_disk, var.keep_disk_agents)
  disable_ipv4                     = each.value.disable_ipv4
  disable_ipv6                     = each.value.disable_ipv6
  primary_ipv4_id                  = coalesce(each.value.primary_ipv4_id, try(hcloud_primary_ip.agents_ipv4[each.key].id, null))
  primary_ipv6_id                  = coalesce(each.value.primary_ipv6_id, try(hcloud_primary_ip.agents_ipv6[each.key].id, null))
  ssh_bastion                      = local.ssh_bastion
  network_id                       = data.hcloud_network.k3s.id
  extra_network_ids                = var.extra_network_ids
  private_ipv4                     = cidrhost(hcloud_network_subnet.agent[[for i, v in var.agent_nodepools : i if v.name == each.value.nodepool_name][0]].ip_range, each.value.index + (local.network_size >= 16 ? 101 : floor(pow(local.subnet_size, 2) * 0.4)))

  labels = merge(local.labels, local.labels_agent_node, each.value.hcloud_labels, { "kube-hetzner/os" = each.value.os })

  automatically_upgrade_os = var.automatically_upgrade_os

  network_gw_ipv4 = local.network_gw_ipv4

  depends_on = [
    hcloud_network_subnet.control_plane,
    hcloud_placement_group.agent,
    hcloud_server.nat_router,
    terraform_data.nat_router_await_cloud_init,
  ]
}

locals {
  k3s-agent-config = { for k, v in local.agent_nodes : k => merge(
    {
      node-name = module.agents[k].name
      server    = local.k3s_endpoint
      token     = local.k3s_token
      # Kubelet arg precedence (last wins): local.kubelet_arg > v.kubelet_args > k3s_global_kubelet_args > k3s_agent_kubelet_args
      kubelet-arg = concat(
        local.kubelet_arg,
        v.kubelet_args,
        var.k3s_global_kubelet_args,
        var.k3s_agent_kubelet_args
      )
      flannel-iface = local.flannel_iface
      node-ip       = module.agents[k].private_ipv4_address
      node-label    = v.labels
      node-taint    = v.taints
    },
    var.agent_nodes_custom_config,
    local.prefer_bundled_bin_config,
    # Force selinux=false if disable_selinux = true.
    var.disable_selinux
    ? { selinux = false }
    : (v.selinux == true ? { selinux = true } : {})
  ) }

  rke2-agent-config = { for k, v in local.agent_nodes : k => merge(
    {
      node-name = module.agents[k].name
      server    = "https://${var.use_control_plane_lb ? hcloud_load_balancer_network.control_plane.*.ip[0] : module.control_planes[keys(module.control_planes)[0]].private_ipv4_address}:9345"
      token     = local.k3s_token
      # Kubelet arg precedence (last wins): local.kubelet_arg > v.kubelet_args > k3s_global_kubelet_args > k3s_agent_kubelet_args
      kubelet-arg = concat(
        local.kubelet_arg,
        v.kubelet_args,
        var.k3s_global_kubelet_args,
        var.k3s_agent_kubelet_args
      )
      node-ip    = module.agents[k].private_ipv4_address
      node-label = v.labels
      node-taint = v.taints
    },
    var.agent_nodes_custom_config,
    # Force selinux=false if disable_selinux = true.
    var.disable_selinux
    ? { selinux = false }
    : (v.selinux == true ? { selinux = true } : {})
  ) }

  agent_ips = {
    for k, v in module.agents : k => coalesce(
      lookup(var.node_connection_overrides, v.name, null),
      v.ipv4_address,
      v.ipv6_address,
      v.private_ipv4_address
    )
  }

  attached_agent_volumes = merge([
    for node_key, node in local.agent_nodes : {
      for volume_idx, volume in coalesce(node.attached_volumes, []) :
      "${node_key}-${volume_idx}" => {
        node_key          = node_key
        volume_idx        = volume_idx
        size              = volume.size
        mount_path        = volume.mount_path
        filesystem        = volume.filesystem
        automount         = volume.automount
        name              = volume.name
        labels            = volume.labels
        delete_protection = volume.delete_protection
      }
    }
  ]...)
}

resource "terraform_data" "agent_config" {
  for_each = local.agent_nodes

  triggers_replace = {
    agent_id = module.agents[each.key].id
    config   = local.kubernetes_distribution == "rke2" ? sha1(yamlencode(local.rke2-agent-config[each.key])) : sha1(yamlencode(local.k3s-agent-config[each.key]))
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.agent_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Generating k3s agent config file
  provisioner "file" {
    content     = local.kubernetes_distribution == "rke2" ? yamlencode(local.rke2-agent-config[each.key]) : yamlencode(local.k3s-agent-config[each.key])
    destination = "/tmp/config.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k8s_config_update_script]
  }
}
moved {
  from = null_resource.agent_config
  to   = terraform_data.agent_config
}

resource "terraform_data" "agents" {
  for_each = local.agent_nodes

  triggers_replace = {
    agent_id = module.agents[each.key].id
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.agent_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Install k3s agent
  provisioner "remote-exec" {
    inline = local.install_k8s_agent
  }

  # Start the k3s agent and wait for it to have started
  provisioner "remote-exec" {
    inline = concat(["systemctl enable --now iscsid"], local.kubernetes_distribution == "rke2" ? [
      "timeout 120 systemctl start rke2-agent 2> /dev/null",
      "systemctl enable rke2-agent",
      <<-EOT
      timeout 120 bash <<EOF
        until systemctl status rke2-agent > /dev/null; do
          systemctl start rke2-agent 2> /dev/null
          echo "Waiting for the rke2 agent to start..."
          sleep 2
        done
      EOF
      EOT
      ] : [
      "timeout 120 systemctl start k3s-agent 2> /dev/null",
      <<-EOT
      timeout 120 bash <<EOF
        until systemctl status k3s-agent > /dev/null; do
          systemctl start k3s-agent 2> /dev/null
          echo "Waiting for the k3s agent to start..."
          sleep 2
        done
      EOF
      EOT
    ])
  }

  depends_on = [
    terraform_data.first_control_plane,
    terraform_data.agent_config,
    hcloud_network_subnet.control_plane
  ]
}
moved {
  from = null_resource.agents
  to   = terraform_data.agents
}

resource "hcloud_volume" "longhorn_volume" {
  for_each = { for k, v in local.agent_nodes : k => v if((v.longhorn_volume_size >= 10) && (v.longhorn_volume_size <= 10240) && var.enable_longhorn) }

  labels = {
    provisioner = "terraform"
    cluster     = var.cluster_name
    scope       = "longhorn"
  }
  name              = "${var.cluster_name}-longhorn-${module.agents[each.key].name}"
  size              = local.agent_nodes[each.key].longhorn_volume_size
  server_id         = module.agents[each.key].id
  automount         = true
  format            = var.longhorn_fstype
  delete_protection = var.enable_delete_protection.volume
}

resource "terraform_data" "configure_longhorn_volume" {
  for_each = { for k, v in local.agent_nodes : k => v if((v.longhorn_volume_size >= 10) && (v.longhorn_volume_size <= 10240) && var.enable_longhorn) }

  triggers_replace = {
    agent_id = module.agents[each.key].id
  }

  # Start the k3s agent and wait for it to have started
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "mkdir -p '${each.value.longhorn_mount_path}' >/dev/null",
      "mountpoint -q '${each.value.longhorn_mount_path}' || mount -o discard,defaults ${hcloud_volume.longhorn_volume[each.key].linux_device} '${each.value.longhorn_mount_path}'",
      "${var.longhorn_fstype == "ext4" ? "resize2fs" : "xfs_growfs"} ${hcloud_volume.longhorn_volume[each.key].linux_device}",
      # Match any non-comment line (^[^#]) with any first field, followed by a space and your mount path in the second column.
      # This prevents false positives like /data matching /data1.
      "awk -v path='${each.value.longhorn_mount_path}' '$0 !~ /^#/ && $2 == path { found=1; exit } END { exit !found }' /etc/fstab || echo '${hcloud_volume.longhorn_volume[each.key].linux_device} ${each.value.longhorn_mount_path} ${var.longhorn_fstype} discard,nofail,defaults 0 0' | tee -a /etc/fstab >/dev/null"
    ]
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.agent_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  depends_on = [
    hcloud_volume.longhorn_volume
  ]
}
moved {
  from = null_resource.configure_longhorn_volume
  to   = terraform_data.configure_longhorn_volume
}

resource "hcloud_volume" "attached_agent_volume" {
  for_each = local.attached_agent_volumes

  labels = merge(
    {
      provisioner = "terraform"
      cluster     = var.cluster_name
      scope       = "attached-volume"
      role        = "agent"
    },
    each.value.labels
  )

  name              = coalesce(each.value.name, "${var.cluster_name}-agent-${module.agents[each.value.node_key].name}-vol-${each.value.volume_idx}")
  size              = each.value.size
  server_id         = module.agents[each.value.node_key].id
  automount         = each.value.automount
  format            = each.value.filesystem
  delete_protection = coalesce(each.value.delete_protection, var.enable_delete_protection.volume)
}

resource "terraform_data" "configure_attached_agent_volume" {
  for_each = local.attached_agent_volumes

  triggers_replace = {
    agent_id    = module.agents[each.value.node_key].id
    volume_id   = hcloud_volume.attached_agent_volume[each.key].id
    mount_path  = each.value.mount_path
    filesystem  = each.value.filesystem
    volume_name = hcloud_volume.attached_agent_volume[each.key].name
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "systemctl enable --now iscsid",
      "mkdir -p '${each.value.mount_path}' >/dev/null",
      "mountpoint -q '${each.value.mount_path}' || mount -o discard,defaults ${hcloud_volume.attached_agent_volume[each.key].linux_device} '${each.value.mount_path}'",
      "${each.value.filesystem == "ext4" ? "resize2fs" : "xfs_growfs"} ${hcloud_volume.attached_agent_volume[each.key].linux_device}",
      "awk -v path='${each.value.mount_path}' '$0 !~ /^#/ && $2 == path { found=1; exit } END { exit !found }' /etc/fstab || echo '${hcloud_volume.attached_agent_volume[each.key].linux_device} ${each.value.mount_path} ${each.value.filesystem} discard,nofail,defaults 0 0' | tee -a /etc/fstab >/dev/null"
    ]
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.agent_ips[each.value.node_key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  depends_on = [
    hcloud_volume.attached_agent_volume
  ]
}

resource "hcloud_floating_ip" "agents" {
  for_each = { for k, v in local.agent_nodes : k => v if coalesce(lookup(v, "floating_ip"), false) }

  type              = local.agent_nodes[each.key].floating_ip_type
  labels            = local.labels
  home_location     = each.value.location
  delete_protection = var.enable_delete_protection.floating_ip
}

resource "hcloud_floating_ip_assignment" "agents" {
  for_each = { for k, v in local.agent_nodes : k => v if coalesce(lookup(v, "floating_ip"), false) }

  floating_ip_id = hcloud_floating_ip.agents[each.key].id
  server_id      = module.agents[each.key].id

  depends_on = [
    terraform_data.agents
  ]
}

resource "hcloud_rdns" "agents" {
  for_each = { for k, v in local.agent_nodes : k => v if lookup(v, "floating_ip_rdns", null) != null }

  floating_ip_id = hcloud_floating_ip.agents[each.key].id
  ip_address     = hcloud_floating_ip.agents[each.key].ip_address
  dns_ptr        = local.agent_nodes[each.key].floating_ip_rdns

  depends_on = [
    hcloud_floating_ip.agents
  ]
}

resource "terraform_data" "configure_floating_ip" {
  for_each = { for k, v in local.agent_nodes : k => v if coalesce(lookup(v, "floating_ip"), false) }

  triggers_replace = {
    agent_id         = module.agents[each.key].id
    floating_ip_id   = hcloud_floating_ip.agents[each.key].id
    floating_ip_type = local.agent_nodes[each.key].floating_ip_type
  }

  provisioner "remote-exec" {
    inline = [
      # Reconfigure eth0:
      #  - add floating_ip as first and other IP as second address
      #  - add 172.31.1.1 as default gateway (In the Hetzner Cloud, the
      #    special private IP address 172.31.1.1 is the default
      #    gateway for the public network)
      # The configuration is stored in file /etc/NetworkManager/system-connections/cloud-init-eth0.nmconnection
      <<-EOT
      ETH=eth1
      if ip link show eth0 &>/dev/null; then
          ETH=eth0
      fi

      NM_CONNECTION=$(nmcli -g GENERAL.CONNECTION device show "$ETH" 2>/dev/null)
      if [ -z "$NM_CONNECTION" ]; then
          echo "ERROR: No NetworkManager connection found for $ETH" >&2
          exit 1
      fi

      if [ "${local.agent_nodes[each.key].floating_ip_type}" = "ipv6" ]; then
          nmcli connection modify "$NM_CONNECTION" \
              ipv6.method manual \
              ipv6.addresses ${hcloud_floating_ip.agents[each.key].ip_address}/128,${module.agents[each.key].ipv6_address}/128 gw6 fe80::1 \
              ipv6.route-metric 100 \
          && nmcli connection up "$NM_CONNECTION"
      else
          nmcli connection modify "$NM_CONNECTION" \
              ipv4.method manual \
              ipv4.addresses ${hcloud_floating_ip.agents[each.key].ip_address}/32,${module.agents[each.key].ipv4_address}/32 gw4 172.31.1.1 \
              ipv4.route-metric 100 \
          && nmcli connection up "$NM_CONNECTION"
      fi
      EOT
    ]
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.agent_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  depends_on = [
    hcloud_floating_ip_assignment.agents
  ]
}
moved {
  from = null_resource.configure_floating_ip
  to   = terraform_data.configure_floating_ip
}
