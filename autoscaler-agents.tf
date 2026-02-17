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
  rke2_cluster_config = {
    imagesForArch : local.imageList
    nodeConfigs : {
      for index, nodePool in var.autoscaler_nodepools :
      ("${local.nodeConfigName}${nodePool.name}") => {
        cloudInit = data.cloudinit_config.autoscaler_config_rke2[index].rendered
        labels    = nodePool.labels
        taints    = nodePool.taints
      }
    }
  }
  desired_cluster_config = local.kubernetes_distribution == "rke2" ? local.rke2_cluster_config : local.cluster_config

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
      ipv4_subnet_id                             = local.primary_network_id
      snapshot_id                                = local.first_nodepool_snapshot_id
      cluster_config                             = base64encode(jsonencode(local.desired_cluster_config))
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
    inline = ["${local.kubectl_cli} apply -f /tmp/autoscaler.yaml"]
  }

  depends_on = [
    hcloud_load_balancer.cluster,
    terraform_data.control_planes,
    null_resource.control_planes_rke2,
    random_password.rancher_bootstrap,
    hcloud_volume.longhorn_volume
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
        sshAuthorizedKeys = concat([var.ssh_public_key], var.ssh_additional_public_keys)
        swap_size         = var.autoscaler_nodepools[count.index].swap_size
        zram_size         = var.autoscaler_nodepools[count.index].zram_size
        os                = local.autoscaler_nodepools_os[count.index]
        k3s_config = yamlencode(merge(
          {
            server = local.k3s_endpoint
            token  = local.k3s_token
            # Kubelet arg precedence (last wins): local.kubelet_arg > nodepool.kubelet_args > k3s_global_kubelet_args > k3s_autoscaler_kubelet_args
            kubelet-arg   = concat(local.kubelet_arg, var.autoscaler_nodepools[count.index].kubelet_args, var.k3s_global_kubelet_args, var.k3s_autoscaler_kubelet_args)
            flannel-iface = local.flannel_iface
            node-label    = concat(local.default_agent_labels, [for k, v in var.autoscaler_nodepools[count.index].labels : "${k}=${v}"], var.autoscaler_nodepools[count.index].swap_size != "" || var.autoscaler_nodepools[count.index].zram_size != "" ? local.swap_node_label : [])
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
        sshAuthorizedKeys = concat([var.ssh_public_key], var.ssh_additional_public_keys)
        swap_size         = var.autoscaler_nodepools[count.index].swap_size
        zram_size         = var.autoscaler_nodepools[count.index].zram_size
        os                = local.autoscaler_nodepools_os[count.index]
        k3s_config = yamlencode({
          server = "https://${var.use_control_plane_lb ? hcloud_load_balancer_network.control_plane.*.ip[0] : module.control_planes[keys(module.control_planes)[0]].private_ipv4_address}:9345"
          token  = local.k3s_token
          # Kubelet arg precedence (last wins): local.kubelet_arg > nodepool.kubelet_args > k3s_global_kubelet_args > k3s_autoscaler_kubelet_args
          kubelet-arg = concat(local.kubelet_arg, var.autoscaler_nodepools[count.index].kubelet_args, var.k3s_global_kubelet_args, var.k3s_autoscaler_kubelet_args)
          node-label  = concat(local.default_agent_labels, [for k, v in var.autoscaler_nodepools[count.index].labels : "${k}=${v}"])
          node-taint  = concat(local.default_agent_taints, [for taint in var.autoscaler_nodepools[count.index].taints : "${taint.key}=${tostring(taint.value)}:${taint.effect}"])
          selinux     = !var.disable_selinux
        })
        install_k3s_agent_script     = join("\n", concat(local.install_k8s_agent, ["systemctl start rke2-agent", "systemctl enable rke2-agent"]))
        cloudinit_write_files_common = local.cloudinit_write_files_common
        cloudinit_runcmd_common      = local.cloudinit_runcmd_common
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
        swap_size         = ""
        zram_size         = ""
        os                = local.first_nodepool_os
        k3s_config = yamlencode(merge(
          {
            server        = local.k3s_endpoint
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

resource "terraform_data" "autoscaled_nodes_registries" {
  for_each = local.autoscaled_nodes
  triggers_replace = {
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
    inline = [local.k8s_registries_update_script]
  }
}
moved {
  from = null_resource.autoscaled_nodes_registries
  to   = terraform_data.autoscaled_nodes_registries
}

resource "terraform_data" "autoscaled_nodes_kubelet_config" {
  for_each = var.k3s_kubelet_config != "" ? local.autoscaled_nodes : {}
  triggers_replace = {
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
moved {
  from = null_resource.autoscaled_nodes_kubelet_config
  to   = terraform_data.autoscaled_nodes_kubelet_config
}
