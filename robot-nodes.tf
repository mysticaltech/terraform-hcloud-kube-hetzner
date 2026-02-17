locals {
  extra_robot_nodes_by_index = {
    for idx, node in var.extra_robot_nodes :
    tostring(idx) => merge(node, {
      ssh_private_key_effective = coalesce(node.ssh_private_key, var.ssh_private_key)
      flannel_iface_effective   = coalesce(node.flannel_iface, node.interface)
    })
  }

  extra_robot_nodes_gateway_ipv4 = cidrhost(local.network_ipv4_subnets[var.vswitch_subnet_index], 1)
  extra_robot_nodes_prefix       = split("/", local.network_ipv4_subnets[var.vswitch_subnet_index])[1]

  extra_robot_nodes_install_command = "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true INSTALL_K3S_SKIP_SELINUX_RPM=true ${var.install_k3s_version == "" ? "INSTALL_K3S_CHANNEL=${var.initial_k3s_channel}" : "INSTALL_K3S_VERSION=${var.install_k3s_version}"} INSTALL_K3S_EXEC='agent ${var.k3s_exec_agent_args}' sh -"
}

resource "terraform_data" "extra_robot_nodes" {
  for_each = local.extra_robot_nodes_by_index

  triggers_replace = {
    host          = each.value.host
    private_ipv4  = each.value.private_ipv4
    vlan_id       = tostring(each.value.vlan_id)
    interface     = each.value.interface
    mtu           = tostring(each.value.mtu)
    routes        = join(",", each.value.routes)
    labels        = join(",", each.value.labels)
    taints        = join(",", each.value.taints)
    flannel_iface = each.value.flannel_iface_effective
    token_sha1    = sha1(local.k3s_token)
    endpoint      = local.k3s_endpoint
    agent_args    = var.k3s_exec_agent_args
  }

  connection {
    type        = "ssh"
    user        = each.value.ssh_user
    host        = each.value.host
    port        = each.value.ssh_port
    private_key = each.value.ssh_private_key_effective
  }

  provisioner "file" {
    content = yamlencode(merge(
      {
        token              = local.k3s_token
        server             = local.k3s_endpoint
        node-ip            = each.value.private_ipv4
        prefer-bundled-bin = true
        kubelet-arg        = concat(local.kubelet_arg, var.k3s_global_kubelet_args, var.k3s_agent_kubelet_args)
        node-label         = each.value.labels
        node-taint         = each.value.taints
      },
      var.cni_plugin == "flannel" ? {
        flannel-iface = each.value.flannel_iface_effective
      } : {}
    ))
    destination = "/tmp/config.yaml"
  }

  provisioner "remote-exec" {
    inline = concat(
      [
        "set -euxo pipefail",
        "VLAN_CONN=vlan${each.value.vlan_id}",
        "nmcli connection show \"$VLAN_CONN\" >/dev/null 2>&1 || nmcli connection add type vlan con-name \"$VLAN_CONN\" ifname \"$VLAN_CONN\" vlan.parent ${each.value.interface} vlan.id ${each.value.vlan_id}",
        "nmcli connection modify \"$VLAN_CONN\" 802-3-ethernet.mtu ${each.value.mtu}",
        "nmcli connection modify \"$VLAN_CONN\" ipv4.addresses '${each.value.private_ipv4}/${local.extra_robot_nodes_prefix}'",
        "nmcli connection modify \"$VLAN_CONN\" ipv4.gateway '${local.extra_robot_nodes_gateway_ipv4}'",
        "nmcli connection modify \"$VLAN_CONN\" ipv4.method manual",
      ],
      [
        for route in each.value.routes :
        "nmcli -g ipv4.routes connection show \"vlan${each.value.vlan_id}\" | grep -Fq \"${route} ${local.extra_robot_nodes_gateway_ipv4}\" || nmcli connection modify \"vlan${each.value.vlan_id}\" +ipv4.routes \"${route} ${local.extra_robot_nodes_gateway_ipv4}\""
      ],
      [
        "nmcli connection up \"$VLAN_CONN\" || (nmcli connection down \"$VLAN_CONN\" || true; nmcli connection up \"$VLAN_CONN\")",
        "mkdir -p /etc/rancher/k3s",
        "install -m 0600 /tmp/config.yaml /etc/rancher/k3s/config.yaml",
        "systemctl stop k3s-agent >/dev/null 2>&1 || true",
        local.extra_robot_nodes_install_command,
        "systemctl enable --now k3s-agent"
      ]
    )
  }

  depends_on = [
    terraform_data.first_control_plane,
    hcloud_network_subnet.vswitch_subnet
  ]
}
