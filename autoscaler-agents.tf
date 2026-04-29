locals {
  cluster_prefix    = var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""
  first_nodepool_os = length(var.autoscaler_nodepools) == 0 ? local.default_autoscaler_os : local.autoscaler_nodepools_os[0]
  first_nodepool_snapshot_id = length(var.autoscaler_nodepools) == 0 ? "" : (
    local.snapshot_id_by_os[local.first_nodepool_os][substr(var.autoscaler_nodepools[0].server_type, 0, 3) == "cax" ? "arm" : "x86"]
  )

  # Only include architectures with a resolved snapshot id. This avoids writing empty values
  # into the autoscaler config when the cluster doesn't use that architecture.
  imageList = length(var.autoscaler_nodepools) == 0 ? {} : merge(
    local.snapshot_id_by_os[local.first_nodepool_os]["arm"] != "" ? { arm64 = tostring(local.snapshot_id_by_os[local.first_nodepool_os]["arm"]) } : {},
    local.snapshot_id_by_os[local.first_nodepool_os]["x86"] != "" ? { amd64 = tostring(local.snapshot_id_by_os[local.first_nodepool_os]["x86"]) } : {},
  )

  nodeConfigName = var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""
  autoscaler_network_keys = length(var.autoscaler_nodepools) == 0 ? [] : sort(distinct([
    for nodePool in var.autoscaler_nodepools : tostring(coalesce(nodePool.network_id, 0))
  ]))
  autoscaler_nodepools_by_network = {
    for network_key in local.autoscaler_network_keys :
    network_key => [
      for nodePool in var.autoscaler_nodepools : nodePool
      if tostring(coalesce(nodePool.network_id, 0)) == network_key
    ]
  }
  autoscaler_network_id_by_key = {
    for network_key in local.autoscaler_network_keys :
    network_key => network_key == "0" ? data.hcloud_network.k3s.id : tonumber(network_key)
  }
  autoscaler_name_by_network = {
    for network_key in local.autoscaler_network_keys :
    network_key => length(local.autoscaler_network_keys) == 1 && network_key == "0" ? "cluster-autoscaler" : "cluster-autoscaler-net-${network_key}"
  }
  cluster_autoscaler_metrics_node_port_by_network = {
    for index, network_key in local.autoscaler_network_keys :
    network_key => 30085 + index
  }
  cluster_autoscaler_metrics_node_ports = values(local.cluster_autoscaler_metrics_node_port_by_network)

  cluster_config_by_network = {
    for network_key in local.autoscaler_network_keys :
    network_key => {
      imagesForArch = local.imageList
      nodeConfigs = {
        for index, nodePool in var.autoscaler_nodepools :
        ("${local.nodeConfigName}${nodePool.name}") => merge(
          {
            cloudInit    = data.cloudinit_config.autoscaler_config[index].rendered
            labels       = nodePool.labels
            serverLabels = nodePool.server_labels
            taints       = nodePool.taints
          },
          nodePool.subnet_ip_range == null ? {} : { subnetIPRange = nodePool.subnet_ip_range }
        )
        if tostring(coalesce(nodePool.network_id, 0)) == network_key
      }
    }
  }
  rke2_cluster_config_by_network = {
    for network_key in local.autoscaler_network_keys :
    network_key => {
      imagesForArch = local.imageList
      nodeConfigs = {
        for index, nodePool in var.autoscaler_nodepools :
        ("${local.nodeConfigName}${nodePool.name}") => merge(
          {
            cloudInit    = data.cloudinit_config.autoscaler_config_rke2[index].rendered
            labels       = nodePool.labels
            serverLabels = nodePool.server_labels
            taints       = nodePool.taints
          },
          nodePool.subnet_ip_range == null ? {} : { subnetIPRange = nodePool.subnet_ip_range }
        )
        if tostring(coalesce(nodePool.network_id, 0)) == network_key
      }
    }
  }
  desired_cluster_config_by_network = local.kubernetes_distribution == "rke2" ? local.rke2_cluster_config_by_network : local.cluster_config_by_network

  autoscaler_yaml = length(var.autoscaler_nodepools) == 0 ? "" : join("\n", [
    for network_key in local.autoscaler_network_keys : templatefile(
      "${path.module}/templates/autoscaler.yaml.tpl",
      {
        autoscaler_name                            = local.autoscaler_name_by_network[network_key]
        leader_election_resource_name              = local.autoscaler_name_by_network[network_key]
        metrics_node_port                          = local.cluster_autoscaler_metrics_node_port_by_network[network_key]
        cloudinit_config                           = ""
        ca_image                                   = var.cluster_autoscaler_image
        ca_version                                 = var.cluster_autoscaler_version
        ca_replicas                                = var.cluster_autoscaler_replicas
        ca_resource_limits                         = var.cluster_autoscaler_resource_limits
        ca_resources                               = var.cluster_autoscaler_resource_values
        cluster_autoscaler_extra_args              = var.cluster_autoscaler_extra_args
        cluster_autoscaler_tolerations             = var.cluster_autoscaler_tolerations
        cluster_autoscaler_log_level               = var.cluster_autoscaler_log_level
        cluster_autoscaler_log_to_stderr           = var.cluster_autoscaler_log_to_stderr
        cluster_autoscaler_stderr_threshold        = var.cluster_autoscaler_stderr_threshold
        cluster_autoscaler_server_creation_timeout = tostring(var.cluster_autoscaler_server_creation_timeout)
        ssh_key                                    = local.hcloud_ssh_key_id
        ipv4_subnet_id                             = local.autoscaler_network_id_by_key[network_key]
        snapshot_id                                = local.first_nodepool_snapshot_id
        cluster_config                             = base64encode(jsonencode(local.desired_cluster_config_by_network[network_key]))
        firewall_id                                = hcloud_firewall.k3s.id
        cluster_name                               = local.cluster_prefix
        node_pools                                 = local.autoscaler_nodepools_by_network[network_key]
        enable_ipv4                                = var.autoscaler_enable_public_ipv4 && !local.use_nat_router
        enable_ipv6                                = var.autoscaler_enable_public_ipv6 && !local.use_nat_router
      }
    )
  ])
  # A concatenated list of all autoscaled nodes
  autoscaled_nodes = length(var.autoscaler_nodepools) == 0 ? {} : {
    for v in concat([
      for k, v in data.
      hcloud_servers.autoscaled_nodes : [for v in v.servers : v]
    ]...) : v.name => v
  }
}

resource "terraform_data" "configure_autoscaler" {
  count = length(var.autoscaler_nodepools) > 0 ? 1 : 0

  triggers_replace = {
    template = local.autoscaler_yaml
  }
  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Upload the autoscaler resource defintion
  provisioner "file" {
    content     = local.autoscaler_yaml
    destination = "/tmp/autoscaler.yaml"
  }

  # Create/Apply the definition
  provisioner "remote-exec" {
    inline = concat(
      ["${local.kubectl_cli} apply -f /tmp/autoscaler.yaml"],
      [
        for autoscaler_name in values(local.autoscaler_name_by_network) :
        "${local.kubectl_cli} -n kube-system wait --for=condition=available --timeout=300s deployment/${autoscaler_name}"
      ]
    )
  }

  depends_on = [
    terraform_data.kustomization,
    terraform_data.rke2_kustomization
  ]
}
moved {
  from = null_resource.configure_autoscaler
  to   = terraform_data.configure_autoscaler
}

data "cloudinit_config" "autoscaler_config" {
  count = length(var.autoscaler_nodepools)

  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/templates/autoscaler-cloudinit.yaml.tpl",
      {
        hostname          = "autoscaler"
        dns_servers       = var.dns_servers
        has_dns_servers   = local.has_dns_servers
        sshAuthorizedKeys = local.ssh_authorized_keys
        swap_size         = var.autoscaler_nodepools[count.index].swap_size
        zram_size         = var.autoscaler_nodepools[count.index].zram_size
        os                = local.autoscaler_nodepools_os[count.index]
        k3s_config = yamlencode(merge(
          {
            server = local.k3s_autoscaler_join_endpoint_by_index[count.index]
            token  = local.cluster_token
            # Kubelet arg precedence (last wins): local.kubelet_arg < global_kubelet_args < autoscaler_kubelet_args < nodepool.kubelet_args
            kubelet-arg   = concat(local.kubelet_arg, var.autoscaler_nodepools[count.index].swap_size != "" || var.autoscaler_nodepools[count.index].zram_size != "" ? ["fail-swap-on=false"] : [], var.global_kubelet_args, var.autoscaler_kubelet_args, var.autoscaler_nodepools[count.index].kubelet_args)
            flannel-iface = local.flannel_iface
            node-label    = concat(local.default_agent_labels, [for k, v in var.autoscaler_nodepools[count.index].labels : "${k}=${v}"], var.autoscaler_nodepools[count.index].swap_size != "" || var.autoscaler_nodepools[count.index].zram_size != "" ? local.swap_node_label : [])
            node-taint    = compact(concat(local.default_agent_taints, [for taint in var.autoscaler_nodepools[count.index].taints : "${taint.key}=${tostring(taint.value)}:${taint.effect}"]))
            selinux       = var.enable_selinux
          },
          local.disable_default_registry_endpoint_config,
          var.agent_nodes_custom_config,
          local.prefer_bundled_bin_config,
          !var.enable_selinux
          ? { selinux = false }
          : {}
        ))
        install_k8s_agent_script = join("\n", concat(
          local.install_k8s_agent,
          local.kubernetes_distribution == "rke2" ? ["systemctl start rke2-agent", "systemctl enable rke2-agent"] : ["systemctl start k3s-agent"]
        ))
        cloudinit_write_files_common        = local.cloudinit_write_files_common
        cloudinit_runcmd_common             = local.cloudinit_runcmd_common,
        private_ipv4_default_route          = !var.autoscaler_enable_public_ipv4 || local.use_nat_router
        public_ipv4_default_route           = var.autoscaler_enable_public_ipv4 && !local.use_nat_router
        public_ipv6_default_route           = var.autoscaler_enable_public_ipv6 && !local.use_nat_router
        network_gw_ipv4                     = local.network_gw_ipv4_by_network_id[coalesce(var.autoscaler_nodepools[count.index].network_id, 0) == 0 ? data.hcloud_network.k3s.id : var.autoscaler_nodepools[count.index].network_id]
        multinetwork_public_overlay_enabled = local.multinetwork_overlay_enabled
        multinetwork_transport_ipv4_enabled = local.multinetwork_transport_ipv4_enabled
        multinetwork_transport_ipv6_enabled = local.multinetwork_transport_ipv6_enabled
        tailscale_bootstrap_script          = local.tailscale_cloud_init_bootstrap_enabled ? local.tailscale_bootstrap_script_autoscaler_by_index[count.index] : ""
      }
    )
  }
}

data "cloudinit_config" "autoscaler_config_rke2" {
  count = length(var.autoscaler_nodepools)

  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/templates/autoscaler-cloudinit.yaml.tpl",
      {
        hostname          = "autoscaler"
        dns_servers       = var.dns_servers
        has_dns_servers   = local.has_dns_servers
        sshAuthorizedKeys = local.ssh_authorized_keys
        swap_size         = var.autoscaler_nodepools[count.index].swap_size
        zram_size         = var.autoscaler_nodepools[count.index].zram_size
        os                = local.autoscaler_nodepools_os[count.index]
        k3s_config = yamlencode(merge(
          {
            server = local.rke2_autoscaler_join_endpoint_by_index[count.index]
            token  = local.cluster_token
            # Kubelet arg precedence (last wins): local.kubelet_arg < global_kubelet_args < autoscaler_kubelet_args < nodepool.kubelet_args
            kubelet-arg = concat(local.kubelet_arg, var.autoscaler_nodepools[count.index].swap_size != "" || var.autoscaler_nodepools[count.index].zram_size != "" ? ["fail-swap-on=false"] : [], var.global_kubelet_args, var.autoscaler_kubelet_args, var.autoscaler_nodepools[count.index].kubelet_args)
            node-label  = concat(local.default_agent_labels, [for k, v in var.autoscaler_nodepools[count.index].labels : "${k}=${v}"], var.autoscaler_nodepools[count.index].swap_size != "" || var.autoscaler_nodepools[count.index].zram_size != "" ? local.swap_node_label : [])
            node-taint  = compact(concat(local.default_agent_taints, [for taint in var.autoscaler_nodepools[count.index].taints : "${taint.key}=${tostring(taint.value)}:${taint.effect}"]))
            selinux     = var.enable_selinux
          },
          local.disable_default_registry_endpoint_config,
          var.agent_nodes_custom_config,
          local.prefer_bundled_bin_config,
          !var.enable_selinux
          ? { selinux = false }
          : {}
        ))
        install_k8s_agent_script            = join("\n", concat(local.install_k8s_agent, ["systemctl start rke2-agent", "systemctl enable rke2-agent"]))
        cloudinit_write_files_common        = local.cloudinit_write_files_common
        cloudinit_runcmd_common             = local.cloudinit_runcmd_common
        private_ipv4_default_route          = !var.autoscaler_enable_public_ipv4 || local.use_nat_router
        public_ipv4_default_route           = var.autoscaler_enable_public_ipv4 && !local.use_nat_router
        public_ipv6_default_route           = var.autoscaler_enable_public_ipv6 && !local.use_nat_router
        network_gw_ipv4                     = local.network_gw_ipv4_by_network_id[coalesce(var.autoscaler_nodepools[count.index].network_id, 0) == 0 ? data.hcloud_network.k3s.id : var.autoscaler_nodepools[count.index].network_id]
        multinetwork_public_overlay_enabled = local.multinetwork_overlay_enabled
        multinetwork_transport_ipv4_enabled = local.multinetwork_transport_ipv4_enabled
        multinetwork_transport_ipv6_enabled = local.multinetwork_transport_ipv6_enabled
        tailscale_bootstrap_script          = local.tailscale_cloud_init_bootstrap_enabled ? local.tailscale_bootstrap_script_autoscaler_by_index[count.index] : ""
      }
    )
  }
}

data "hcloud_servers" "autoscaled_nodes" {
  for_each      = toset(var.autoscaler_nodepools[*].name)
  with_selector = "hcloud/node-group=${local.cluster_prefix}${each.value}"
}

resource "terraform_data" "autoscaled_nodes_registries" {
  for_each = local.autoscaled_nodes
  triggers_replace = {
    registries = local.registries_config_effective
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.tailscale_use_tailnet_for_terraform ? "${each.value.name}.${local.tailscale_magicdns_domain}" : coalesce(each.value.ipv4_address, each.value.ipv6_address, try(one(each.value.network).ip, null))
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  provisioner "file" {
    content     = local.registries_config_effective
    destination = "/tmp/registries.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k8s_registries_update_script]
  }
}
moved {
  from = null_resource.autoscaled_nodes_registries
  to   = terraform_data.autoscaled_nodes_registries
}

resource "terraform_data" "autoscaled_nodes_kubelet_config" {
  for_each = var.kubelet_config != "" ? local.autoscaled_nodes : {}
  triggers_replace = {
    kubelet_config = var.kubelet_config
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.tailscale_use_tailnet_for_terraform ? "${each.value.name}.${local.tailscale_magicdns_domain}" : coalesce(each.value.ipv4_address, each.value.ipv6_address, try(one(each.value.network).ip, null))
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  provisioner "file" {
    content     = var.kubelet_config
    destination = "/tmp/kubelet-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k8s_kubelet_config_update_script]
  }
}
moved {
  from = null_resource.autoscaled_nodes_kubelet_config
  to   = terraform_data.autoscaled_nodes_kubelet_config
}
