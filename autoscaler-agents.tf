locals {
  cluster_prefix = var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""
  first_nodepool_snapshot_id = length(var.autoscaler_nodepools) == 0 ? "" : (
    substr(var.autoscaler_nodepools[0].server_type, 0, 3) == "cax" ? data.hcloud_image.microos_arm_snapshot.id : data.hcloud_image.microos_x86_snapshot.id
  )

  imageList = {
    arm64 : tostring(data.hcloud_image.microos_arm_snapshot.id)
    amd64 : tostring(data.hcloud_image.microos_x86_snapshot.id)
  }

  nodeConfigName = var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""
  cluster_config = {
    imagesForArch : local.imageList
    nodeConfigs : {
      for index, nodePool in var.autoscaler_nodepools :
      ("${local.nodeConfigName}${nodePool.name}") => {
        cloudInit = data.cloudinit_config.autoscaler_config[index].rendered
        labels    = nodePool.labels
        taints    = nodePool.taints
      }
    }
  }

  isUsingLegacyConfig = length(var.autoscaler_labels) > 0 || length(var.autoscaler_taints) > 0

  autoscaler_yaml = length(var.autoscaler_nodepools) == 0 ? "" : templatefile(
    "${path.module}/templates/autoscaler.yaml.tpl",
    {
      cloudinit_config                           = local.isUsingLegacyConfig ? base64encode(data.cloudinit_config.autoscaler_legacy_config[0].rendered) : ""
      ca_image                                   = var.cluster_autoscaler_image
      ca_version                                 = var.cluster_autoscaler_version
      ca_replicas                                = var.cluster_autoscaler_replicas
      ca_resource_limits                         = var.cluster_autoscaler_resource_limits
      ca_resources                               = var.cluster_autoscaler_resource_values
      cluster_autoscaler_extra_args              = var.cluster_autoscaler_extra_args
      cluster_autoscaler_log_level               = var.cluster_autoscaler_log_level
      cluster_autoscaler_log_to_stderr           = var.cluster_autoscaler_log_to_stderr
      cluster_autoscaler_stderr_threshold        = var.cluster_autoscaler_stderr_threshold
      cluster_autoscaler_server_creation_timeout = tostring(var.cluster_autoscaler_server_creation_timeout)
      ssh_key                                    = local.hcloud_ssh_key_id
      ipv4_subnet_id                             = data.hcloud_network.k3s.id
      snapshot_id                                = local.first_nodepool_snapshot_id
      cluster_config                             = base64encode(jsonencode(local.cluster_config))
      firewall_id                                = hcloud_firewall.k3s.id
      cluster_name                               = local.cluster_prefix
      node_pools                                 = var.autoscaler_nodepools
      enable_ipv4                                = !(var.autoscaler_disable_ipv4 || local.use_nat_router)
      enable_ipv6                                = !(var.autoscaler_disable_ipv6 || local.use_nat_router)
  })
  # A concatenated list of all autoscaled nodes
  autoscaled_nodes = length(var.autoscaler_nodepools) == 0 ? {} : {
    for v in concat([
      for k, v in data.
      hcloud_servers.autoscaled_nodes : [for v in v.servers : v]
    ]...) : v.name => v
  }
}

resource "null_resource" "configure_autoscaler" {
  count = length(var.autoscaler_nodepools) > 0 ? 1 : 0

  triggers = {
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
    inline = ["kubectl apply -f /tmp/autoscaler.yaml"]
  }

  depends_on = [
    hcloud_load_balancer.cluster,
    null_resource.control_planes,
    random_password.rancher_bootstrap,
    hcloud_volume.longhorn_volume,
    data.hcloud_image.microos_x86_snapshot
  ]
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
        sshAuthorizedKeys = concat([var.ssh_public_key], var.ssh_additional_public_keys)
        k3s_config = yamlencode(merge(
          {
            server = "https://${var.use_control_plane_lb ? hcloud_load_balancer_network.control_plane.*.ip[0] : module.control_planes[keys(module.control_planes)[0]].private_ipv4_address}:6443"
            token  = local.k3s_token
            # Kubelet arg precedence (last wins): local.kubelet_arg > nodepool.kubelet_args > k3s_global_kubelet_args > k3s_autoscaler_kubelet_args
            kubelet-arg   = concat(local.kubelet_arg, var.autoscaler_nodepools[count.index].kubelet_args, var.k3s_global_kubelet_args, var.k3s_autoscaler_kubelet_args)
            flannel-iface = local.flannel_iface
            node-label    = concat(local.default_agent_labels, [for k, v in var.autoscaler_nodepools[count.index].labels : "${k}=${v}"])
            node-taint    = compact(concat(local.default_agent_taints, [for taint in var.autoscaler_nodepools[count.index].taints : "${taint.key}=${tostring(taint.value)}:${taint.effect}"]))
            selinux       = !var.disable_selinux
          },
          var.agent_nodes_custom_config,
          local.prefer_bundled_bin_config
        ))
        install_k3s_agent_script     = join("\n", concat(local.install_k3s_agent, ["systemctl start k3s-agent"]))
        cloudinit_write_files_common = local.cloudinit_write_files_common
        cloudinit_runcmd_common      = local.cloudinit_runcmd_common,
        private_network_only         = var.autoscaler_disable_ipv4 && var.autoscaler_disable_ipv6,
        network_gw_ipv4              = local.network_gw_ipv4
      }
    )
  }
}

data "cloudinit_config" "autoscaler_legacy_config" {
  count = length(var.autoscaler_nodepools) > 0 && local.isUsingLegacyConfig ? 1 : 0

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
        sshAuthorizedKeys = concat([var.ssh_public_key], var.ssh_additional_public_keys)
        k3s_config = yamlencode(merge(
          {
            server        = "https://${var.use_control_plane_lb ? hcloud_load_balancer_network.control_plane.*.ip[0] : module.control_planes[keys(module.control_planes)[0]].private_ipv4_address}:6443"
            token         = local.k3s_token
            kubelet-arg   = local.kubelet_arg
            flannel-iface = local.flannel_iface
            node-label    = concat(local.default_agent_labels, var.autoscaler_labels)
            node-taint    = compact(concat(local.default_agent_taints, var.autoscaler_taints))
            selinux       = !var.disable_selinux
          },
          var.agent_nodes_custom_config,
          local.prefer_bundled_bin_config
        ))
        install_k3s_agent_script     = join("\n", concat(local.install_k3s_agent, ["systemctl start k3s-agent"]))
        cloudinit_write_files_common = local.cloudinit_write_files_common
        cloudinit_runcmd_common      = local.cloudinit_runcmd_common,
        private_network_only         = var.autoscaler_disable_ipv4 && var.autoscaler_disable_ipv6,
        network_gw_ipv4              = local.network_gw_ipv4,
      }
    )
  }
}

data "hcloud_servers" "autoscaled_nodes" {
  for_each      = toset(var.autoscaler_nodepools[*].name)
  with_selector = "hcloud/node-group=${local.cluster_prefix}${each.value}"
}

resource "null_resource" "autoscaled_nodes_registries" {
  for_each = local.autoscaled_nodes
  triggers = {
    registries = var.k3s_registries
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = coalesce(each.value.ipv4_address, each.value.ipv6_address, try(one(each.value.network).ip, null))
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  provisioner "file" {
    content     = var.k3s_registries
    destination = "/tmp/registries.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k3s_registries_update_script]
  }
}

resource "null_resource" "autoscaled_nodes_kubelet_config" {
  for_each = var.k3s_kubelet_config != "" ? local.autoscaled_nodes : {}
  triggers = {
    kubelet_config = var.k3s_kubelet_config
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = coalesce(each.value.ipv4_address, each.value.ipv6_address, try(one(each.value.network).ip, null))
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  provisioner "file" {
    content     = var.k3s_kubelet_config
    destination = "/tmp/kubelet-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k3s_kubelet_config_update_script]
  }
}
