locals {
  # ssh_agent_identity is not set if the private key is passed directly, but if ssh agent is used, the public key tells ssh agent which private key to use.
  # For terraforms provisioner.connection.agent_identity, we need the public key as a string.
  ssh_agent_identity = var.ssh_private_key == null ? var.ssh_public_key : null

  # If passed, a key already registered within hetzner is used.
  # Otherwise, a new one will be created by the module.
  hcloud_ssh_key_id = var.hcloud_ssh_key_id == null ? hcloud_ssh_key.k3s[0].id : var.hcloud_ssh_key_id

  # if given as a variable, we want to use the given token. This is needed to restore the cluster
  k3s_token = var.k3s_token == null ? random_password.k3s_token.result : var.k3s_token

  kubernetes_distribution = var.kubernetes_distribution_type

  ccm_version    = var.hetzner_ccm_version != null ? var.hetzner_ccm_version : data.github_release.hetzner_ccm[0].release_tag
  csi_version    = length(data.github_release.hetzner_csi) == 0 ? var.hetzner_csi_version : data.github_release.hetzner_csi[0].release_tag
  kured_version  = var.kured_version != null ? var.kured_version : data.github_release.kured[0].release_tag
  calico_version = length(data.github_release.calico) == 0 ? var.calico_version : data.github_release.calico[0].release_tag

  cilium_ipv4_native_routing_cidr = coalesce(var.cilium_ipv4_native_routing_cidr, var.cluster_ipv4_cidr)

  # Check if the user has set custom DNS servers.
  has_dns_servers = length(var.dns_servers) > 0

  # Separate out IPv4 and IPv6 DNS hosts.
  dns_servers_ipv4 = [for ip in var.dns_servers : ip if provider::assert::ipv4(ip)]
  dns_servers_ipv6 = [for ip in var.dns_servers : ip if provider::assert::ipv6(ip)]

  additional_k3s_environment = join("\n",
    [
      for var_name, var_value in var.additional_k3s_environment :
      "${var_name}=\"${var_value}\""
    ]
  )
  install_additional_k3s_environment = <<-EOT
  cat >> /etc/environment <<EOF
  ${local.additional_k3s_environment}
  EOF
  set -a; source /etc/environment; set +a;
  EOT

  install_system_alias = <<-EOT
  cat > /etc/profile.d/00-alias.sh <<EOF
  alias k=kubectl
  EOF
  EOT

  install_kubectl_bash_completion = <<-EOT
  cat > /etc/bash_completion.d/kubectl <<EOF
  if command -v kubectl >/dev/null; then
    source <(kubectl completion bash)
    complete -o default -F __start_kubectl k
  fi
  EOF
  EOT

  common_pre_install_k3s_commands = concat(
    [
      "set -ex",
      # rename the private network interface to eth1
      "/etc/cloud/rename_interface.sh",
      # prepare the k3s config directory
      "mkdir -p /etc/rancher/k3s",
      # move the config file into place and adjust permissions
      "[ -f /tmp/config.yaml ] && mv /tmp/config.yaml /etc/rancher/k3s/config.yaml",
      "chmod 0600 /etc/rancher/k3s/config.yaml",
      # if the server has already been initialized just stop here
      "[ -e /etc/rancher/k3s/k3s.yaml ] && exit 0",
      local.install_additional_k3s_environment,
      local.install_system_alias,
      local.install_kubectl_bash_completion,
    ],
    length(local.dns_servers_ipv4) > 0 ? [
      "nmcli con mod eth0 ipv4.dns ${join(",", local.dns_servers_ipv4)}"
    ] : [],
    length(local.dns_servers_ipv6) > 0 ? [
      "nmcli con mod eth0 ipv6.dns ${join(",", local.dns_servers_ipv6)}"
    ] : [],
    local.has_dns_servers ? ["systemctl restart NetworkManager"] : [],
    # User-defined commands to execute just before installing k3s.
    var.preinstall_exec,
    # Wait for a successful connection to the internet.
    ["timeout 180s /bin/sh -c 'while ! ping -c 1 ${var.address_for_connectivity_test} >/dev/null 2>&1; do echo \"Ready for k3s installation, waiting for a successful connection to the internet...\"; sleep 5; done; echo Connected'"]
  )

  common_pre_install_rke2_commands = concat(
    [
      "set -ex",
      # rename the private network interface to eth1
      "/etc/cloud/rename_interface.sh",
      # prepare the rke2 config directory
      "mkdir -p /etc/rancher/rke2",
      # move the config file into place and adjust permissions
      "[ -f /tmp/config.yaml ] && mv /tmp/config.yaml /etc/rancher/rke2/config.yaml",
      "chmod 0600 /etc/rancher/rke2/config.yaml",
      # if the server has already been initialized just stop here
      "[ -e /etc/rancher/rke2/rke2.yaml ] && exit 0",
      local.install_additional_k3s_environment,
      local.install_system_alias,
      local.install_kubectl_bash_completion,
    ],
    length(local.dns_servers_ipv4) > 0 ? [
      "nmcli con mod eth0 ipv4.dns ${join(",", local.dns_servers_ipv4)}"
    ] : [],
    length(local.dns_servers_ipv6) > 0 ? [
      "nmcli con mod eth0 ipv6.dns ${join(",", local.dns_servers_ipv6)}"
    ] : [],
    local.has_dns_servers ? ["systemctl restart NetworkManager"] : [],
    # User-defined commands to execute just before installing rke2.
    var.preinstall_exec,
    # Wait for a successful connection to the internet.
    ["timeout 180s /bin/sh -c 'while ! ping -c 1 ${var.address_for_connectivity_test} >/dev/null 2>&1; do echo \"Ready for rke2 installation, waiting for a successful connection to the internet...\"; sleep 5; done; echo Connected'"]
  )

  common_pre_install_k8s_commands = var.kubernetes_distribution_type == "rke2" ? local.common_pre_install_rke2_commands : local.common_pre_install_k3s_commands

  common_post_install_k3s_commands  = concat(var.postinstall_exec, ["restorecon -v /usr/local/bin/k3s"])
  common_post_install_rke2_commands = concat(var.postinstall_exec, [])
  common_post_install_k8s_commands  = var.kubernetes_distribution_type == "rke2" ? local.common_post_install_rke2_commands : local.common_post_install_k3s_commands

  kustomization_backup_yaml = yamlencode({
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    resources = concat(
      [
        "https://github.com/kubereboot/kured/releases/download/${local.kured_version}/kured-${local.kured_version}-combined.yaml",
        "https://github.com/rancher/system-upgrade-controller/releases/download/${var.sys_upgrade_controller_version}/system-upgrade-controller.yaml",
        "https://github.com/rancher/system-upgrade-controller/releases/download/${var.sys_upgrade_controller_version}/crd.yaml"
      ],
      var.hetzner_ccm_use_helm ? ["hcloud-ccm-helm.yaml"] : ["https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/${local.ccm_version}/ccm-networks.yaml"],
      var.disable_hetzner_csi ? [] : ["hcloud-csi.yaml"],
      lookup(local.ingress_controller_install_resources, var.ingress_controller, []),
      local.kubernetes_distribution == "k3s" ? lookup(local.cni_install_resources, var.cni_plugin, []) : [],
      var.cni_plugin == "flannel" ? ["flannel-rbac.yaml"] : [],
      var.enable_longhorn ? ["longhorn.yaml"] : [],
      var.enable_csi_driver_smb ? ["csi-driver-smb.yaml"] : [],
      var.enable_cert_manager || var.enable_rancher ? ["cert_manager.yaml"] : [],
      var.enable_rancher ? ["rancher.yaml"] : [],
      var.rancher_registration_manifest_url != "" ? [var.rancher_registration_manifest_url] : []
    ),
    patches = concat([
      {
        target = {
          group     = "apps"
          version   = "v1"
          kind      = "Deployment"
          name      = "system-upgrade-controller"
          namespace = "system-upgrade"
        }
        patch = file("${path.module}/kustomize/system-upgrade-controller.yaml")
      },
      {
        path = "kured.yaml"
      }
      ],
      var.hetzner_ccm_use_helm ? [] : [{ path = "ccm.yaml" }]
    )
  })

  # TODO: What needs changing for rke2 here?
  apply_k3s_selinux  = ["/sbin/semodule -v -i /usr/share/selinux/packages/k3s.pp"]
  apply_rke2_selinux = ["/sbin/semodule -v -i /usr/share/selinux/packages/rke2.pp"]
  swap_node_label    = ["node.kubernetes.io/server-swap=enabled"]

  k3s_install_command  = "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true INSTALL_K3S_SKIP_SELINUX_RPM=true %{if var.install_k3s_version == ""}INSTALL_K3S_CHANNEL=${var.initial_k3s_channel}%{else}INSTALL_K3S_VERSION=${var.install_k3s_version}%{endif} INSTALL_K3S_EXEC='%s' sh -"
  rke2_install_command = "curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=${var.install_rke2_version} INSTALL_RKE2_EXEC='%s' sh -"

  install_k3s_server = concat(
    local.common_pre_install_k3s_commands,
    [format(local.k3s_install_command, "server ${var.k3s_exec_server_args}")],
    var.disable_selinux ? [] : local.apply_k3s_selinux,
    local.common_post_install_k8s_commands
  )
  install_rke2_server = concat(
    local.common_pre_install_k8s_commands,
    [format(local.rke2_install_command, "server ${var.k3s_exec_server_args}")],
    local.common_post_install_k8s_commands
  )

  install_k3s_agent = concat(
    local.common_pre_install_k3s_commands,
    [format(local.k3s_install_command, "agent ${var.k3s_exec_agent_args}")],
    var.disable_selinux ? [] : local.apply_k3s_selinux,
    local.common_post_install_k3s_commands
  )
  install_rke2_agent = concat(
    local.common_pre_install_k8s_commands,
    [format(local.rke2_install_command, "agent ${var.k3s_exec_agent_args}")],
    local.common_post_install_k8s_commands
  )

  install_k8s_server = var.kubernetes_distribution_type == "rke2" ? local.install_rke2_server : local.install_k3s_server
  install_k8s_agent  = var.kubernetes_distribution_type == "rke2" ? local.install_rke2_agent : local.install_k3s_agent
  kubectl_cli        = var.kubernetes_distribution_type == "rke2" ? "/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml" : "kubectl"

  control_plane_nodes = merge([
    for pool_index, nodepool_obj in var.control_plane_nodepools : {
      for node_index in range(nodepool_obj.count) :
      format("%s-%s-%s", pool_index, node_index, nodepool_obj.name) => {
        nodepool_name : nodepool_obj.name,
        server_type : nodepool_obj.server_type,
        location : nodepool_obj.location,
        labels : concat(local.default_control_plane_labels, nodepool_obj.swap_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
        taints : concat(local.default_control_plane_taints, nodepool_obj.taints),
        kubelet_args : nodepool_obj.kubelet_args,
        backups : nodepool_obj.backups,
        swap_size : nodepool_obj.swap_size,
        zram_size : nodepool_obj.zram_size,
        index : node_index
        selinux : nodepool_obj.selinux
        placement_group_compat_idx : nodepool_obj.placement_group_compat_idx,
        placement_group : nodepool_obj.placement_group,
        disable_ipv4 : nodepool_obj.disable_ipv4,
        disable_ipv6 : nodepool_obj.disable_ipv6,
        network_id : nodepool_obj.network_id,
      }
    }
  ]...)

  agent_nodes_from_integer_counts = merge([
    for pool_index, nodepool_obj in var.agent_nodepools : {
      # coalesce(nodepool_obj.count, 0) means we select those nodepools who's size is set by an integer count.
      for node_index in range(coalesce(nodepool_obj.count, 0)) :
      format("%s-%s-%s", pool_index, node_index, nodepool_obj.name) => {
        nodepool_name : nodepool_obj.name,
        server_type : nodepool_obj.server_type,
        longhorn_volume_size : coalesce(nodepool_obj.longhorn_volume_size, 0),
        floating_ip : lookup(nodepool_obj, "floating_ip", false),
        floating_ip_rdns : lookup(nodepool_obj, "floating_ip_rdns", false),
        location : nodepool_obj.location,
        labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
        taints : concat(local.default_agent_taints, nodepool_obj.taints),
        kubelet_args : nodepool_obj.kubelet_args,
        backups : lookup(nodepool_obj, "backups", false),
        swap_size : nodepool_obj.swap_size,
        zram_size : nodepool_obj.zram_size,
        index : node_index
        selinux : nodepool_obj.selinux
        placement_group_compat_idx : nodepool_obj.placement_group_compat_idx,
        placement_group : nodepool_obj.placement_group,
        disable_ipv4 : nodepool_obj.disable_ipv4,
        disable_ipv6 : nodepool_obj.disable_ipv6,
        network_id : nodepool_obj.network_id,
      }
    }
  ]...)

  agent_nodes_from_maps_for_counts = merge([
    for pool_index, nodepool_obj in var.agent_nodepools : {
      # coalesce(nodepool_obj.nodes, {}) means we select those nodepools who's size is set by an integer count.
      for node_key, node_obj in coalesce(nodepool_obj.nodes, {}) :
      format("%s-%s-%s", pool_index, node_key, nodepool_obj.name) => merge(
        {
          nodepool_name : nodepool_obj.name,
          server_type : nodepool_obj.server_type,
          longhorn_volume_size : coalesce(nodepool_obj.longhorn_volume_size, 0),
          floating_ip : lookup(nodepool_obj, "floating_ip", false),
          floating_ip_rdns : lookup(nodepool_obj, "floating_ip_rdns", false),
          location : nodepool_obj.location,
          labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
          taints : concat(local.default_agent_taints, nodepool_obj.taints),
          kubelet_args : nodepool_obj.kubelet_args,
          backups : lookup(nodepool_obj, "backups", false),
          swap_size : nodepool_obj.swap_size,
          zram_size : nodepool_obj.zram_size,
          selinux : nodepool_obj.selinux,
          placement_group_compat_idx : nodepool_obj.placement_group_compat_idx,
          placement_group : nodepool_obj.placement_group,
          index : floor(tonumber(node_key)),
          disable_ipv4 : nodepool_obj.disable_ipv4,
          disable_ipv6 : nodepool_obj.disable_ipv6,
          network_id : nodepool_obj.network_id,
        },
        { for key, value in node_obj : key => value if value != null },
        {
          labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" ? local.swap_node_label : [], nodepool_obj.labels, coalesce(node_obj.labels, [])),
          taints : concat(local.default_agent_taints, nodepool_obj.taints, coalesce(node_obj.taints, [])),
        },
        (
          node_obj.append_index_to_node_name ? { node_name_suffix : "-${floor(tonumber(node_key))}" } : {}
        )
      )
    }
  ]...)


  agent_nodes = merge(
    local.agent_nodes_from_integer_counts,
    local.agent_nodes_from_maps_for_counts,
  )

  use_existing_network = length(var.existing_network_id) > 0

  # The first two subnets are respectively the default subnet 10.0.0.0/16 use for potentially anything and 10.1.0.0/16 used for control plane nodes.
  # the rest of the subnets are for agent nodes in each nodepools.
  network_ipv4_subnets = [for index in range(256) : cidrsubnet(var.network_ipv4_cidr, 8, index)]
  # By convention the DNS service (usually core-dns) is assigned the 10th IP address in the service CIDR block
  cluster_dns_ipv4 = var.cluster_dns_ipv4 != null ? var.cluster_dns_ipv4 : cidrhost(var.service_ipv4_cidr, 10)

  # if we are in a single cluster config, we use the default klipper lb instead of Hetzner LB
  control_plane_count    = sum([for v in var.control_plane_nodepools : v.count])
  agent_count            = length(var.agent_nodepools) > 0 ? sum([for v in var.agent_nodepools : length(coalesce(v.nodes, {})) + coalesce(v.count, 0)]) : 0
  autoscaler_max_count   = length(var.autoscaler_nodepools) > 0 ? sum([for v in var.autoscaler_nodepools : v.max_nodes]) : 0
  is_single_node_cluster = (local.control_plane_count + local.agent_count + local.autoscaler_max_count) == 1

  using_klipper_lb = var.enable_klipper_metal_lb || local.is_single_node_cluster

  has_external_load_balancer = local.using_klipper_lb || var.ingress_controller == "none"
  load_balancer_name         = "${var.cluster_name}-${var.ingress_controller}"

  ingress_controller_service_names = {
    "traefik" = "traefik"
    "nginx"   = "nginx-ingress-nginx-controller"
    "haproxy" = "haproxy-kubernetes-ingress"
  }

  ingress_controller_install_resources = {
    "traefik" = ["traefik_ingress.yaml"]
    "nginx"   = ["nginx_ingress.yaml"]
    "haproxy" = ["haproxy_ingress.yaml"]
  }

  default_ingress_namespace_mapping = {
    "traefik" = "traefik"
    "nginx"   = "nginx"
    "haproxy" = "haproxy"
  }

  ingress_controller_namespace = var.ingress_target_namespace != "" ? var.ingress_target_namespace : lookup(local.default_ingress_namespace_mapping, var.ingress_controller, "")
  ingress_replica_count        = (var.ingress_replica_count > 0) ? var.ingress_replica_count : (local.agent_count > 2) ? 3 : (local.agent_count == 2) ? 2 : 1
  ingress_max_replica_count    = (var.ingress_max_replica_count > local.ingress_replica_count) ? var.ingress_max_replica_count : local.ingress_replica_count

  # disable k3s extras
  # TODO: Extend to work with rke2
  disable_extras      = concat(var.enable_local_storage ? [] : ["local-storage"], local.using_klipper_lb ? [] : ["servicelb"], ["traefik"], var.enable_metrics_server ? [] : ["metrics-server"])
  disable_rke2_extras = ["rke2-ingress-nginx"]

  # Determine if scheduling should be allowed on control plane nodes, which will be always true for single node clusters and clusters or if scheduling is allowed on control plane nodes
  allow_scheduling_on_control_plane = local.is_single_node_cluster ? true : var.allow_scheduling_on_control_plane
  # Determine if loadbalancer target should be allowed on control plane nodes, which will be always true for single node clusters or if scheduling is allowed on control plane nodes
  allow_loadbalancer_target_on_control_plane = local.is_single_node_cluster ? true : var.allow_scheduling_on_control_plane

  # Default k8s node labels
  default_agent_labels = concat([], var.automatically_upgrade_k3s ? [local.kubernetes_distribution == "rke2" ? "rke2_upgrade=true" : "k3s_upgrade=true"] : [])
  default_control_plane_labels = concat(
    local.allow_loadbalancer_target_on_control_plane ? [] : ["node.kubernetes.io/exclude-from-external-load-balancers=true"],
    var.automatically_upgrade_k3s ? [local.kubernetes_distribution == "rke2" ? "rke2_upgrade=true" : "k3s_upgrade=true"] : []
  )
  default_autoscaler_labels = concat([], var.automatically_upgrade_k3s ? [local.kubernetes_distribution == "rke2" ? "rke2_upgrade=true" : "k3s_upgrade=true"] : [])

  # Default k3s node taints
  default_control_plane_taints = concat([], local.allow_scheduling_on_control_plane ? [] : ["node-role.kubernetes.io/control-plane:NoSchedule"])
  default_agent_taints         = concat([], var.cni_plugin == "cilium" ? ["node.cilium.io/agent-not-ready:NoExecute"] : [])

  base_firewall_rules = concat(
    var.firewall_ssh_source == null ? [] : [
      # Allow all traffic to the ssh port
      {
        description = "Allow Incoming SSH Traffic"
        direction   = "in"
        protocol    = "tcp"
        port        = var.ssh_port
        source_ips  = var.firewall_ssh_source
      },
    ],
    var.firewall_kube_api_source == null ? [] : [
      {
        description = "Allow Incoming Requests to Kube API Server"
        direction   = "in"
        protocol    = "tcp"
        port        = "6443"
        source_ips  = var.firewall_kube_api_source
      }
    ],
    !var.restrict_outbound_traffic ? [] : [
      # Allow basic out traffic
      # ICMP to ping outside services
      {
        description     = "Allow Outbound ICMP Ping Requests"
        direction       = "out"
        protocol        = "icmp"
        port            = ""
        destination_ips = ["0.0.0.0/0", "::/0"]
      },

      # DNS
      {
        description     = "Allow Outbound TCP DNS Requests"
        direction       = "out"
        protocol        = "tcp"
        port            = "53"
        destination_ips = ["0.0.0.0/0", "::/0"]
      },
      {
        description     = "Allow Outbound UDP DNS Requests"
        direction       = "out"
        protocol        = "udp"
        port            = "53"
        destination_ips = ["0.0.0.0/0", "::/0"]
      },

      # HTTP(s)
      {
        description     = "Allow Outbound HTTP Requests"
        direction       = "out"
        protocol        = "tcp"
        port            = "80"
        destination_ips = ["0.0.0.0/0", "::/0"]
      },
      {
        description     = "Allow Outbound HTTPS Requests"
        direction       = "out"
        protocol        = "tcp"
        port            = "443"
        destination_ips = ["0.0.0.0/0", "::/0"]
      },

      #NTP
      {
        description     = "Allow Outbound UDP NTP Requests"
        direction       = "out"
        protocol        = "udp"
        port            = "123"
        destination_ips = ["0.0.0.0/0", "::/0"]
      }
    ],
    !local.using_klipper_lb ? [] : [
      # Allow incoming web traffic for single node clusters, because we are using k3s servicelb there,
      # not an external load-balancer.
      {
        description = "Allow Incoming HTTP Connections"
        direction   = "in"
        protocol    = "tcp"
        port        = "80"
        source_ips  = ["0.0.0.0/0", "::/0"]
      },
      {
        description = "Allow Incoming HTTPS Connections"
        direction   = "in"
        protocol    = "tcp"
        port        = "443"
        source_ips  = ["0.0.0.0/0", "::/0"]
      }
    ],
    var.block_icmp_ping_in ? [] : [
      {
        description = "Allow Incoming ICMP Ping Requests"
        direction   = "in"
        protocol    = "icmp"
        port        = ""
        source_ips  = ["0.0.0.0/0", "::/0"]
      }
    ]
  )

  # create a new firewall list based on base_firewall_rules but with direction-protocol-port as key
  # this is needed to avoid duplicate rules
  firewall_rules = { for rule in local.base_firewall_rules : format("%s-%s-%s", lookup(rule, "direction", "null"), lookup(rule, "protocol", "null"), lookup(rule, "port", "null")) => rule }

  # do the same for var.extra_firewall_rules
  extra_firewall_rules = { for rule in var.extra_firewall_rules : format("%s-%s-%s", lookup(rule, "direction", "null"), lookup(rule, "protocol", "null"), lookup(rule, "port", "null")) => rule }

  # merge the two lists
  firewall_rules_merged = merge(local.firewall_rules, local.extra_firewall_rules)

  # convert the merged list back to a list
  firewall_rules_list = values(local.firewall_rules_merged)

  labels = {
    "provisioner" = "terraform",
    "engine"      = local.kubernetes_distribution
    "cluster"     = var.cluster_name
  }

  labels_control_plane_node = {
    role = "control_plane_node"
  }
  labels_control_plane_lb = {
    role = "control_plane_lb"
  }

  labels_agent_node = {
    role = "agent_node"
  }

  cni_install_resources = {
    "calico" = ["https://raw.githubusercontent.com/projectcalico/calico/${coalesce(local.calico_version, "v3.27.2")}/manifests/calico.yaml"]
    "cilium" = ["cilium.yaml"]
  }

  prefer_bundled_bin_config = var.k3s_prefer_bundled_bin ? { "prefer-bundled-bin" = true } : {}

  cni_k3s_settings = {
    "flannel" = {
      disable-network-policy = var.disable_network_policy
      flannel-backend        = var.enable_wireguard ? "wireguard-native" : "vxlan"
    }
    "calico" = {
      disable-network-policy = true
      flannel-backend        = "none"
    }
    "cilium" = {
      disable-network-policy = true
      flannel-backend        = "none"
    }
  }

  # TODO: Needs review, straight copy & pasted from cni_k3s_settings
  #  Result: It seems that none of the settings are supported in rke2
  # cni_rke2_settings = {
  #   "flannel" = {
  #     disable-network-policy = var.disable_network_policy
  #     flannel-backend        = var.enable_wireguard ? "wireguard-native" : "vxlan"
  #   }
  #   "calico" = {
  #     disable-network-policy = true
  #     flannel-backend        = "none"
  #   }
  #   "cilium" = {
  #     disable-network-policy = true
  #     flannel-backend        = "none"
  #   }
  # }

  etcd_s3_snapshots = length(keys(var.etcd_s3_backup)) > 0 ? merge(
    {
      "etcd-s3" = true
    },
  var.etcd_s3_backup) : {}

  kubelet_arg                 = ["cloud-provider=external", "volume-plugin-dir=/var/lib/kubelet/volumeplugins"]
  kube_controller_manager_arg = "flex-volume-plugin-dir=/var/lib/kubelet/volumeplugins"
  flannel_iface               = "eth1"
  authentication_config_file = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/authentication_config.yaml" : "/etc/rancher/k3s/authentication_config.yaml"
  control_plane_service_name = local.kubernetes_distribution == "rke2" ? "rke2-server" : "k3s"
  agent_service_name         = local.kubernetes_distribution == "rke2" ? "rke2-agent" : "k3s-agent"

  kube_apiserver_arg = concat(
    var.authentication_config != "" ? ["authentication-config=${local.authentication_config_file}"] : [],
    var.k3s_audit_policy_config != "" ? [
      "audit-policy-file=/etc/rancher/k3s/audit-policy.yaml",
      "audit-log-path=${var.k3s_audit_log_path}",
      "audit-log-maxage=${var.k3s_audit_log_maxage}",
      "audit-log-maxbackup=${var.k3s_audit_log_maxbackup}",
      "audit-log-maxsize=${var.k3s_audit_log_maxsize}"
    ] : []
  )

  cilium_values = var.cilium_values != "" ? var.cilium_values : <<EOT
# Enable Kubernetes host-scope IPAM mode (required for K3s + Hetzner CCM)
ipam:
  mode: kubernetes
k8s:
  requireIPv4PodCIDR: true

# Replace kube-proxy with Cilium
kubeProxyReplacement: true
%{if var.disable_kube_proxy}
# Enable health check server (healthz) for the kube-proxy replacement
kubeProxyReplacementHealthzBindAddr: "0.0.0.0:10256"
%{endif~}

# Access to Kube API Server (mandatory if kube-proxy is disabled)
k8sServiceHost: "127.0.0.1"
k8sServicePort: "${local.kubernetes_distribution == "rke2" ? "6443" : "6444"}"

# Set Tunnel Mode or Native Routing Mode (supported by Hetzner CCM Route Controller)
routingMode: "${var.cilium_routing_mode}"
%{if var.cilium_routing_mode == "native"~}
# Set the native routable CIDR
ipv4NativeRoutingCIDR: "${local.cilium_ipv4_native_routing_cidr}"

# Bypass iptables Connection Tracking for Pod traffic (only works in Native Routing Mode)
installNoConntrackIptablesRules: true
%{endif~}

# Perform a gradual roll out on config update.
rollOutCiliumPods: true

endpointRoutes:
  # Enable use of per endpoint routes instead of routing via the cilium_host interface.
  enabled: true

loadBalancer:
  # Enable LoadBalancer & NodePort XDP Acceleration (direct routing (routingMode=native) is recommended to achieve optimal performance)
  acceleration: native

bpf:
  # Enable eBPF-based Masquerading ("The eBPF-based implementation is the most efficient implementation")
  masquerade: true
%{if var.enable_wireguard}
encryption:
  enabled: true
  # Enable node encryption for node-to-node traffic
  nodeEncryption: true
  type: wireguard
%{endif~}
%{if var.cilium_egress_gateway_enabled}
egressGateway:
  enabled: true
%{endif~}

%{if var.cilium_hubble_enabled}
hubble:
  relay:
    enabled: true
  ui:
    enabled: true
  metrics:
    enabled:
%{for metric in var.cilium_hubble_metrics_enabled~}
      - "${metric}"
%{endfor~}
%{endif~}

MTU: 1450
  EOT

  # Not to be confused with the other helm values, this is used for the calico.yaml kustomize patch
  # It also serves as a stub for a potential future use via helm values
  calico_values = var.calico_values != "" ? var.calico_values : <<EOT
kind: DaemonSet
apiVersion: apps/v1
metadata:
  name: calico-node
  namespace: kube-system
  labels:
    k8s-app: calico-node
spec:
  template:
    spec:
      volumes:
        - name: flexvol-driver-host
          hostPath:
            type: DirectoryOrCreate
            path: /var/lib/kubelet/volumeplugins/nodeagent~uds
      containers:
        - name: calico-node
          env:
            - name: CALICO_IPV4POOL_CIDR
              value: "${var.cluster_ipv4_cidr}"
            - name: FELIX_WIREGUARDENABLED
              value: "${var.enable_wireguard}"

  EOT

  desired_cni_values  = var.cni_plugin == "cilium" ? local.cilium_values : local.calico_values
  desired_cni_version = var.cni_plugin == "cilium" ? var.cilium_version : var.calico_version

  longhorn_values = var.longhorn_values != "" ? var.longhorn_values : <<EOT
defaultSettings:
%{if length(var.autoscaler_nodepools) != 0~}
  kubernetesClusterAutoscalerEnabled: true
%{endif~}
  defaultDataPath: /var/longhorn
persistence:
  defaultFsType: ${var.longhorn_fstype}
  defaultClassReplicaCount: ${var.longhorn_replica_count}
  %{if var.disable_hetzner_csi~}defaultClass: true%{else~}defaultClass: false%{endif~}
  EOT

  csi_driver_smb_values = var.csi_driver_smb_values != "" ? var.csi_driver_smb_values : <<EOT
  EOT

  hetzner_csi_values = var.hetzner_csi_values != "" ? var.hetzner_csi_values : (!local.allow_scheduling_on_control_plane ? <<-EOT
node:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "node-role.kubernetes.io/control-plane"
                operator: DoesNotExist
EOT
  : "")

  nginx_values = var.nginx_values != "" ? var.nginx_values : <<EOT
controller:
  watchIngressWithoutClass: "true"
  kind: "Deployment"
  replicaCount: ${local.ingress_replica_count}
  config:
    "use-forwarded-headers": "true"
    "compute-full-forwarded-for": "true"
    "use-proxy-protocol": "${!local.using_klipper_lb}"
%{if !local.using_klipper_lb~}
  service:
    annotations:
      "load-balancer.hetzner.cloud/name": "${local.load_balancer_name}"
      "load-balancer.hetzner.cloud/use-private-ip": "true"
      "load-balancer.hetzner.cloud/disable-private-ingress": "true"
      "load-balancer.hetzner.cloud/disable-public-network": "${var.load_balancer_disable_public_network}"
      "load-balancer.hetzner.cloud/ipv6-disabled": "${var.load_balancer_disable_ipv6}"
      "load-balancer.hetzner.cloud/location": "${var.load_balancer_location}"
      "load-balancer.hetzner.cloud/type": "${var.load_balancer_type}"
      "load-balancer.hetzner.cloud/uses-proxyprotocol": "${!local.using_klipper_lb}"
      "load-balancer.hetzner.cloud/algorithm-type": "${var.load_balancer_algorithm_type}"
      "load-balancer.hetzner.cloud/health-check-interval": "${var.load_balancer_health_check_interval}"
      "load-balancer.hetzner.cloud/health-check-timeout": "${var.load_balancer_health_check_timeout}"
      "load-balancer.hetzner.cloud/health-check-retries": "${var.load_balancer_health_check_retries}"
%{if var.lb_hostname != ""~}
      "load-balancer.hetzner.cloud/hostname": "${var.lb_hostname}"
%{endif~}
%{endif~}
  EOT

  haproxy_values = var.haproxy_values != "" ? var.haproxy_values : <<EOT
controller:
  kind: "Deployment"
  replicaCount: ${local.ingress_replica_count}
  ingressClass: null
  resources:
    requests:
      cpu: "${var.haproxy_requests_cpu}"
      memory: "${var.haproxy_requests_memory}"
  config:
    ssl-redirect: "false"
    forwarded-for: "true"
%{if !local.using_klipper_lb~}
    proxy-protocol: "${join(
  ", ",
  concat(
    ["127.0.0.1/32", "10.0.0.0/8"],
    var.haproxy_additional_proxy_protocol_ips
  )
)}"
%{endif~}
  service:
    type: LoadBalancer
    enablePorts:
      quic: false
      stat: false
      prometheus: false
%{if !local.using_klipper_lb~}
    annotations:
      "load-balancer.hetzner.cloud/name": "${local.load_balancer_name}"
      "load-balancer.hetzner.cloud/use-private-ip": "true"
      "load-balancer.hetzner.cloud/disable-private-ingress": "true"
      "load-balancer.hetzner.cloud/disable-public-network": "${var.load_balancer_disable_public_network}"
      "load-balancer.hetzner.cloud/ipv6-disabled": "${var.load_balancer_disable_ipv6}"
      "load-balancer.hetzner.cloud/location": "${var.load_balancer_location}"
      "load-balancer.hetzner.cloud/type": "${var.load_balancer_type}"
      "load-balancer.hetzner.cloud/uses-proxyprotocol": "${!local.using_klipper_lb}"
      "load-balancer.hetzner.cloud/algorithm-type": "${var.load_balancer_algorithm_type}"
      "load-balancer.hetzner.cloud/health-check-interval": "${var.load_balancer_health_check_interval}"
      "load-balancer.hetzner.cloud/health-check-timeout": "${var.load_balancer_health_check_timeout}"
      "load-balancer.hetzner.cloud/health-check-retries": "${var.load_balancer_health_check_retries}"
%{if var.lb_hostname != ""~}
      "load-balancer.hetzner.cloud/hostname": "${var.lb_hostname}"
%{endif~}
%{endif~}
  EOT

traefik_values = var.traefik_values != "" ? var.traefik_values : <<EOT
image:
  tag: ${var.traefik_image_tag}
deployment:
  replicas: ${local.ingress_replica_count}
globalArguments: []
service:
  enabled: true
  type: LoadBalancer
%{if !local.using_klipper_lb~}
  annotations:
    "load-balancer.hetzner.cloud/name": "${local.load_balancer_name}"
    "load-balancer.hetzner.cloud/use-private-ip": "true"
    "load-balancer.hetzner.cloud/disable-private-ingress": "true"
    "load-balancer.hetzner.cloud/disable-public-network": "${var.load_balancer_disable_public_network}"
    "load-balancer.hetzner.cloud/ipv6-disabled": "${var.load_balancer_disable_ipv6}"
    "load-balancer.hetzner.cloud/location": "${var.load_balancer_location}"
    "load-balancer.hetzner.cloud/type": "${var.load_balancer_type}"
    "load-balancer.hetzner.cloud/uses-proxyprotocol": "${!local.using_klipper_lb}"
    "load-balancer.hetzner.cloud/algorithm-type": "${var.load_balancer_algorithm_type}"
    "load-balancer.hetzner.cloud/health-check-interval": "${var.load_balancer_health_check_interval}"
    "load-balancer.hetzner.cloud/health-check-timeout": "${var.load_balancer_health_check_timeout}"
    "load-balancer.hetzner.cloud/health-check-retries": "${var.load_balancer_health_check_retries}"
%{if var.lb_hostname != ""~}
    "load-balancer.hetzner.cloud/hostname": "${var.lb_hostname}"
%{endif~}
%{endif~}
ports:
%{if var.traefik_redirect_to_https || !local.using_klipper_lb~}
  web:
%{if var.traefik_redirect_to_https~}
    redirections:
      entryPoint:
        to: websecure
        scheme: https
        permanent: true
%{endif~}
%{if !local.using_klipper_lb~}
    proxyProtocol:
      trustedIPs:
        - 127.0.0.1/32
        - 10.0.0.0/8
%{for ip in var.traefik_additional_trusted_ips~}
        - "${ip}"
%{endfor~}
    forwardedHeaders:
      trustedIPs:
        - 127.0.0.1/32
        - 10.0.0.0/8
%{for ip in var.traefik_additional_trusted_ips~}
        - "${ip}"
%{endfor~}
%{endif~}
%{endif~}
  websecure:
%{if !local.using_klipper_lb~}
    proxyProtocol:
      trustedIPs:
        - 127.0.0.1/32
        - 10.0.0.0/8
%{for ip in var.traefik_additional_trusted_ips~}
        - "${ip}"
%{endfor~}
    forwardedHeaders:
      trustedIPs:
        - 127.0.0.1/32
        - 10.0.0.0/8
%{for ip in var.traefik_additional_trusted_ips~}
        - "${ip}"
%{endfor~}
%{endif~}
%{if var.traefik_additional_ports != ""~}
%{for option in var.traefik_additional_ports~}
  ${option.name}:
    port: ${option.port}
    expose:
      default: true
    exposedPort: ${option.exposedPort}
    protocol: TCP
%{if !local.using_klipper_lb~}
    proxyProtocol:
      trustedIPs:
        - 127.0.0.1/32
        - 10.0.0.0/8
%{for ip in var.traefik_additional_trusted_ips~}
        - "${ip}"
%{endfor~}
    forwardedHeaders:
      trustedIPs:
        - 127.0.0.1/32
        - 10.0.0.0/8
%{for ip in var.traefik_additional_trusted_ips~}
        - "${ip}"
%{endfor~}
%{endif~}
%{endfor~}
%{endif~}
%{if var.traefik_pod_disruption_budget~}
podDisruptionBudget:
  enabled: true
  maxUnavailable: 33%
%{endif~}
additionalArguments:
  - "--providers.kubernetesingress.ingressendpoint.publishedservice=${local.ingress_controller_namespace}/traefik"
%{for option in var.traefik_additional_options~}
  - "${option}"
%{endfor~}
%{if var.traefik_resource_limits~}
resources:
  requests:
    cpu: "${var.traefik_resource_values.requests.cpu}"
    memory: "${var.traefik_resource_values.requests.memory}"
  limits:
    cpu: "${var.traefik_resource_values.limits.cpu}"
    memory: "${var.traefik_resource_values.limits.memory}"
%{endif~}
%{if var.traefik_autoscaling~}
autoscaling:
  enabled: true
  minReplicas: ${local.ingress_replica_count}
  maxReplicas: ${local.ingress_max_replica_count}
%{endif~}
  EOT

rancher_values = var.rancher_values != "" ? var.rancher_values : <<EOT
hostname: "${var.rancher_hostname != "" ? var.rancher_hostname : var.lb_hostname}"
replicas: ${length(local.control_plane_nodes)}
bootstrapPassword: "${length(var.rancher_bootstrap_password) == 0 ? resource.random_password.rancher_bootstrap[0].result : var.rancher_bootstrap_password}"
global:
  cattle:
    psp:
      enabled: false
  EOT

cert_manager_values = var.cert_manager_values != "" ? var.cert_manager_values : <<EOT
crds:
  enabled: true
  keep: true
  EOT

kured_options = merge({
  "reboot-command" : "/usr/bin/systemctl reboot",
  "pre-reboot-node-labels" : "kured=rebooting",
  "post-reboot-node-labels" : "kured=done",
  "period" : "5m",
  "reboot-sentinel" : "/sentinel/reboot-required"
}, var.kured_options)

k3s_registries_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`
if cmp -s /tmp/registries.yaml /etc/rancher/k3s/registries.yaml; then
  echo "No update required to the registries.yaml file"
else
  echo "Backing up /etc/rancher/k3s/registries.yaml to /tmp/registries_$DATE.yaml"
  cp /etc/rancher/k3s/registries.yaml /tmp/registries_$DATE.yaml
  echo "Updated registries.yaml detected, restart of k3s service required"
  cp /tmp/registries.yaml /etc/rancher/k3s/registries.yaml
  if systemctl is-active --quiet k3s; then
    systemctl restart k3s || (echo "Error: Failed to restart k3s. Restoring /etc/rancher/k3s/registries.yaml from backup" && cp /tmp/registries_$DATE.yaml /etc/rancher/k3s/registries.yaml && systemctl restart k3s)
  elif systemctl is-active --quiet k3s-agent; then
    systemctl restart k3s-agent || (echo "Error: Failed to restart k3s-agent. Restoring /etc/rancher/k3s/registries.yaml from backup" && cp /tmp/registries_$DATE.yaml /etc/rancher/k3s/registries.yaml && systemctl restart k3s-agent)
  else
    echo "No active k3s or k3s-agent service found"
  fi
  echo "k3s service or k3s-agent service restarted successfully"
fi
EOF

k3s_config_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`
if cmp -s /tmp/config.yaml /etc/rancher/k3s/config.yaml; then
  echo "No update required to the config.yaml file"
else
  if [ -f "/etc/rancher/k3s/config.yaml" ]; then
    echo "Backing up /etc/rancher/k3s/config.yaml to /tmp/config_$DATE.yaml"
    cp /etc/rancher/k3s/config.yaml /tmp/config_$DATE.yaml
  fi
  echo "Updated config.yaml detected, restart of k3s service required"
  cp /tmp/config.yaml /etc/rancher/k3s/config.yaml
  if systemctl is-active --quiet k3s; then
    systemctl restart k3s || (echo "Error: Failed to restart k3s. Restoring /etc/rancher/k3s/config.yaml from backup" && cp /tmp/config_$DATE.yaml /etc/rancher/k3s/config.yaml && systemctl restart k3s)
  elif systemctl is-active --quiet k3s-agent; then
    systemctl restart k3s-agent || (echo "Error: Failed to restart k3s-agent. Restoring /etc/rancher/k3s/config.yaml from backup" && cp /tmp/config_$DATE.yaml /etc/rancher/k3s/config.yaml && systemctl restart k3s-agent)
  else
    echo "No active k3s or k3s-agent service found"
  fi
  echo "k3s service or k3s-agent service (re)started successfully"
fi
EOF

k3s_authentication_config_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`
if cmp -s /tmp/authentication_config.yaml ${local.authentication_config_file}; then
  echo "No update required to the authentication_config.yaml file"
else
  if [ -f "${local.authentication_config_file}" ]; then
    echo "Backing up ${local.authentication_config_file} to /tmp/authentication_config_$DATE.yaml"
    cp "${local.authentication_config_file}" /tmp/authentication_config_$DATE.yaml
  fi
  echo "Updated authentication_config.yaml detected, restart of kubernetes service required"
  cp /tmp/authentication_config.yaml "${local.authentication_config_file}"
  if systemctl is-active --quiet ${local.control_plane_service_name}; then
    systemctl restart ${local.control_plane_service_name} || (echo "Error: Failed to restart ${local.control_plane_service_name}. Restoring ${local.authentication_config_file} from backup" && cp /tmp/authentication_config_$DATE.yaml "${local.authentication_config_file}" && systemctl restart ${local.control_plane_service_name})
  elif systemctl is-active --quiet ${local.agent_service_name}; then
    systemctl restart ${local.agent_service_name} || (echo "Error: Failed to restart ${local.agent_service_name}. Restoring ${local.authentication_config_file} from backup" && cp /tmp/authentication_config_$DATE.yaml "${local.authentication_config_file}" && systemctl restart ${local.agent_service_name})
  else
    echo "No active ${local.control_plane_service_name} or ${local.agent_service_name} service found"
  fi
  echo "${local.control_plane_service_name} service or ${local.agent_service_name} service (re)started successfully"
fi
EOF

rke2_registries_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`
if cmp -s /tmp/registries.yaml /etc/rancher/rke2/registries.yaml; then
  echo "No update required to the registries.yaml file"
else
  echo "Backing up /etc/rancher/rke2/registries.yaml to /tmp/registries_$DATE.yaml"
  cp /etc/rancher/rke2/registries.yaml /tmp/registries_$DATE.yaml
  echo "Updated registries.yaml detected, restart of rke2 service required"
  cp /tmp/registries.yaml /etc/rancher/rke2/registries.yaml
  if systemctl is-active --quiet rke2-server; then
    systemctl restart rke2-server || (echo "Error: Failed to restart rke2-server. Restoring /etc/rancher/rke2/registries.yaml from backup" && cp /tmp/registries_$DATE.yaml /etc/rancher/rke2/registries.yaml && systemctl restart rke2-server)
  elif systemctl is-active --quiet rke2-agent; then
    systemctl restart rke2-agent || (echo "Error: Failed to restart rke2-agent. Restoring /etc/rancher/rke2/registries.yaml from backup" && cp /tmp/registries_$DATE.yaml /etc/rancher/rke2/registries.yaml && systemctl restart rke2-agent)
  else
    echo "No active rke2-server or rke2-agent service found"
  fi
  echo "rke2-server service or rke2-agent service restarted successfully"
fi
EOF

rke2_config_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`
if cmp -s /tmp/config.yaml /etc/rancher/rke2/config.yaml; then
  echo "No update required to the config.yaml file"
else
  if [ -f "/etc/rancher/rke2/config.yaml" ]; then
    echo "Backing up /etc/rancher/rke2/config.yaml to /tmp/config_$DATE.yaml"
    cp /etc/rancher/rke2/config.yaml /tmp/config_$DATE.yaml
  fi
  echo "Updated config.yaml detected, restart of rke2-server service required"
  cp /tmp/config.yaml /etc/rancher/rke2/config.yaml
  if systemctl is-active --quiet rke2-server; then
    systemctl restart rke2-server || (echo "Error: Failed to restart rke2-server. Restoring /etc/rancher/rke2/config.yaml from backup" && cp /tmp/config_$DATE.yaml /etc/rancher/rke2/config.yaml && systemctl restart rke2-server)
  elif systemctl is-active --quiet rke2-agent; then
    systemctl restart rke2-agent || (echo "Error: Failed to restart rke2-agent. Restoring /etc/rancher/rke2/config.yaml from backup" && cp /tmp/config_$DATE.yaml /etc/rancher/rke2/config.yaml && systemctl restart rke2-agent)
  else
    echo "No active rke2-server or rke2-agent service found"
  fi
  echo "rke2-server service or rke2-agent service (re)started successfully"
fi
EOF

rke2_authentication_config_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`
if cmp -s /tmp/authentication_config.yaml /etc/rancher/rke2/authentication_config.yaml; then
  echo "No update required to the authentication_config.yaml file"
else
  if [ -f "/etc/rancher/rke2/authentication_config.yaml" ]; then
    echo "Backing up /etc/rancher/rke2/authentication_config.yaml to /tmp/authentication_config_$DATE.yaml"
    cp /etc/rancher/rke2/authentication_config.yaml /tmp/authentication_config_$DATE.yaml
  fi
  echo "Updated authentication_config.yaml detected, restart of rke2-server service required"
  cp /tmp/authentication_config.yaml /etc/rancher/rke2/authentication_config.yaml
  if systemctl is-active --quiet rke2-server; then
    systemctl restart rke2-server || (echo "Error: Failed to restart rke2-server. Restoring /etc/rancher/rke2/authentication_config.yaml from backup" && cp /tmp/authentication_config_$DATE.yaml /etc/rancher/rke2/authentication_config.yaml && systemctl restart rke2-server)
  elif systemctl is-active --quiet rke2-agent; then
    systemctl restart rke2-agent || (echo "Error: Failed to restart rke2-agent. Restoring /etc/rancher/rke2/authentication_config.yaml from backup" && cp /tmp/authentication_config_$DATE.yaml /etc/rancher/rke2/authentication_config.yaml && systemctl restart rke2-agent)
  else
    echo "No active rke2-server or rke2-agent service found"
  fi
  echo "rke2-server service or rke2-agent service (re)started successfully"
fi
EOF

k8s_registries_update_script            = local.kubernetes_distribution == "k3s" ? local.k3s_registries_update_script : local.rke2_registries_update_script
k8s_config_update_script                = local.kubernetes_distribution == "k3s" ? local.k3s_config_update_script : local.rke2_config_update_script
k8s_authentication_config_update_script = local.kubernetes_distribution == "k3s" ? local.k3s_authentication_config_update_script : local.rke2_authentication_config_update_script

cloudinit_write_files_common = <<EOT
# Script to rename the private interface to eth1 and unify NetworkManager connection naming
- path: /etc/cloud/rename_interface.sh
  content: |
    #!/bin/bash
    set -euo pipefail

    sleep 11

    # Take row beginning with 3 if exists, 2 otherwise (if only a private ip)
    INTERFACE=$(ip link show | grep -v 'flannel' | awk 'BEGIN{l3=""}; /^3:/{l3=$2}; /^2:/{l2=$2}; END{if(l3!="") print l3; else print l2}' | sed 's/://g')
    MAC=$(cat /sys/class/net/$INTERFACE/address)

    cat <<EOF > /etc/udev/rules.d/70-persistent-net.rules
    SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="$MAC", NAME="eth1"
    EOF

    if [ "$INTERFACE" = "eth1" ]; then
      echo "Interface $INTERFACE already points to $MAC, skipping..."
      exit 0
    fi

    ip link set $INTERFACE down
    ip link set $INTERFACE name eth1
    ip link set eth1 up

    myrepeat () {
        # Current time + 300 seconds (5 minutes)
        local END_SECONDS=$((SECONDS + 300))
        while true; do
            >&2 echo "loop"
            if (( "$SECONDS" > "$END_SECONDS" )); then
                >&2 echo "timeout reached"
                exit 1
            fi
            # run command and check return code
            if $@ ; then
                >&2 echo "break"
                break
            else
                >&2 echo "got failure exit code, repeating"
                sleep 0.5
            fi
        done
    }

    myrename () {
        local eth="$1"
        local eth_connection

        # In case of a private-only network, eth0 may not exist
        if ip link show "$eth" &>/dev/null; then
            eth_connection=$(nmcli -g GENERAL.CONNECTION device show "$eth" || echo '')
            nmcli connection modify "$eth_connection" \
              con-name "$eth" \
              connection.interface-name "$eth"
        fi
    }

    myrepeat myrename eth0
    myrepeat myrename eth1

    systemctl restart NetworkManager
  permissions: "0744"

# Disable ssh password authentication
- content: |
    Port ${var.ssh_port}
    PasswordAuthentication no
    X11Forwarding no
    MaxAuthTries ${var.ssh_max_auth_tries}
    AllowTcpForwarding no
    AllowAgentForwarding no
    AuthorizedKeysFile .ssh/authorized_keys
  path: /etc/ssh/sshd_config.d/kube-hetzner.conf

# Set reboot method as "kured"
- content: |
    REBOOT_METHOD=kured
  path: /etc/transactional-update.conf

# Create Rancher repo config
- content: |
    [rancher-k3s-common-stable]
    name=Rancher K3s Common (stable)
    baseurl=https://rpm.rancher.io/k3s/stable/common/microos/noarch
    enabled=1
    gpgcheck=1
    repo_gpgcheck=0
    gpgkey=https://rpm.rancher.io/public.key
  path: /etc/zypp/repos.d/rancher-k3s-common.repo

# Create Rancher rke2 repo config
# TODO: Finish this if its needed like the above one? When is this used? Don't we just use the URL installation method?
# - content: |


# Create the kube_hetzner_selinux.te file, that allows in SELinux to not interfere with various needed services
- path: /root/kube_hetzner_selinux.te
  content: |
    module kube_hetzner_selinux 1.0;

    require {
        type kernel_t, bin_t, kernel_generic_helper_t, iscsid_t, iscsid_exec_t, var_run_t, var_lib_t,
            init_t, unlabeled_t, systemd_logind_t, systemd_hostnamed_t, container_t,
            cert_t, container_var_lib_t, etc_t, usr_t, container_file_t, container_log_t,
            container_share_t, container_runtime_exec_t, container_runtime_t, var_log_t, proc_t, io_uring_t, fuse_device_t, http_port_t,
            container_var_run_t;
        class key { read view };
        class file { open read execute execute_no_trans create link lock rename write append setattr unlink getattr watch };
        class sock_file { watch write create unlink };
        class unix_dgram_socket create;
        class unix_stream_socket { connectto read write };
        class dir { add_name create getattr link lock read rename remove_name reparent rmdir setattr unlink search write watch };
        class lnk_file { read create };
        class system module_request;
        class filesystem associate;
        class bpf map_create;
        class io_uring sqpoll;
        class anon_inode { create map read write };
        class tcp_socket name_connect;
        class chr_file { open read write };
    }

    #============= kernel_generic_helper_t ==============
    allow kernel_generic_helper_t bin_t:file execute_no_trans;
    allow kernel_generic_helper_t kernel_t:key { read view };
    allow kernel_generic_helper_t self:unix_dgram_socket create;

    #============= iscsid_t ==============
    allow iscsid_t iscsid_exec_t:file execute;
    allow iscsid_t var_run_t:sock_file write;
    allow iscsid_t var_run_t:unix_stream_socket connectto;

    #============= init_t ==============
    allow init_t unlabeled_t:dir { add_name remove_name rmdir search };
    allow init_t unlabeled_t:lnk_file create;
    allow init_t container_t:file { open read };
    allow init_t container_file_t:file { execute execute_no_trans };
    allow init_t fuse_device_t:chr_file { open read write };
    allow init_t http_port_t:tcp_socket name_connect;

    #============= systemd_logind_t ==============
    allow systemd_logind_t unlabeled_t:dir search;

    #============= systemd_hostnamed_t ==============
    allow systemd_hostnamed_t unlabeled_t:dir search;

    #============= container_t ==============
    allow container_t { cert_t container_log_t }:dir read;
    allow container_t { cert_t container_log_t }:lnk_file read;
    allow container_t cert_t:file { read open };
    allow container_t container_var_lib_t:dir { add_name remove_name write read create };
    allow container_t container_var_lib_t:file { append create open read write rename lock setattr getattr unlink };
    allow container_t etc_t:dir { add_name remove_name write create setattr watch };
    allow container_t etc_t:file { create setattr unlink write };
    allow container_t etc_t:sock_file { create unlink };
    allow container_t usr_t:dir { add_name create getattr link lock read rename remove_name reparent rmdir setattr unlink search write };
    allow container_t usr_t:file { append create execute getattr link lock read rename setattr unlink write };
    allow container_t container_file_t:file { open read write append getattr setattr lock };
    allow container_t container_file_t:sock_file watch;
    allow container_t container_log_t:file { open read write append getattr setattr watch };
    allow container_t container_share_t:dir { read write add_name remove_name };
    allow container_t container_share_t:file { read write create unlink };
    allow container_t container_runtime_exec_t:file { read execute execute_no_trans open };
    allow container_t container_runtime_t:unix_stream_socket { connectto read write };
    allow container_t kernel_t:system module_request;
    allow container_t var_log_t:dir { add_name write remove_name watch read };
    allow container_t var_log_t:file { create lock open read setattr write unlink getattr };
    allow container_t var_lib_t:dir { add_name remove_name write read create };
    allow container_t var_lib_t:file { append create open read write rename lock setattr getattr unlink };
    allow container_t proc_t:filesystem associate;
    allow container_t self:bpf map_create;
    allow container_t self:io_uring sqpoll;
    allow container_t io_uring_t:anon_inode { create map read write };
    allow container_t container_var_run_t:dir { add_name remove_name write };
    allow container_t container_var_run_t:file { create open read rename unlink write };

    # RKE2

    rke2_filetrans_named_content(container_runtime_t)
    rke2_filetrans_named_content(unconfined_service_t)

    #######################
    # type rke2_service_t #
    #######################
    rke2_service_domain_template(rke2_service)
    container_read_lib_files(rke2_service_t)
    allow rke2_service_t container_var_lib_t:sock_file { write };
    allow rke2_service_t container_runtime_t:unix_stream_socket { connectto };

    ##########################
    # type rke2_service_db_t #
    ##########################
    rke2_service_domain_template(rke2_service_db)
    container_manage_lib_dirs(rke2_service_db_t)
    container_manage_lib_files(rke2_service_db_t)
    allow rke2_service_db_t container_var_lib_t:file { map };

    #########################
    # Longhorn ISCSID_T FIX #
    #########################
    # https://github.com/longhorn/longhorn/issues/5627#issuecomment-1577498183
    allow iscsid_t self:capability dac_override;

    ###################
    # type rke2_tls_t #
    ###################
    type rke2_tls_t;
    container_file(rke2_tls_t);

# Create the k3s registries file if needed
# TODO: Review that this can stay and behaves the same in rke2 as with k3s
%{if var.k3s_registries != ""}
# Create k3s registries file
- content: ${base64encode(var.k3s_registries)}
  encoding: base64
  path: /etc/rancher/k3s/registries.yaml
%{endif}
EOT

cloudinit_runcmd_common = <<EOT
# ensure that /var uses full available disk size, thanks to btrfs this is easy
- [btrfs, 'filesystem', 'resize', 'max', '/var']

# SELinux permission for the SSH alternative port
%{if var.ssh_port != 22}
# SELinux permission for the SSH alternative port.
- [semanage, port, '-a', '-t', ssh_port_t, '-p', tcp, '${var.ssh_port}']
%{endif}

# Create and apply the necessary SELinux module for kube-hetzner
- [checkmodule, '-M', '-m', '-o', '/root/kube_hetzner_selinux.mod', '/root/kube_hetzner_selinux.te']
- ['semodule_package', '-o', '/root/kube_hetzner_selinux.pp', '-m', '/root/kube_hetzner_selinux.mod']
- [semodule, '-i', '/root/kube_hetzner_selinux.pp']
- [setsebool, '-P', 'virt_use_samba', '1']
- [setsebool, '-P', 'domain_kernel_load_modules', '1']

# Disable rebootmgr service as we use kured instead
- [systemctl, disable, '--now', 'rebootmgr.service']

# Bounds the amount of logs that can survive on the system
- [sed, '-i', 's/#SystemMaxUse=/SystemMaxUse=3G/g', /etc/systemd/journald.conf]
- [sed, '-i', 's/#MaxRetentionSec=/MaxRetentionSec=1week/g', /etc/systemd/journald.conf]

# Reduces the default number of snapshots from 2-10 number limit, to 4 and from 4-10 number limit important, to 2
- [sed, '-i', 's/NUMBER_LIMIT="2-10"/NUMBER_LIMIT="4"/g', /etc/snapper/configs/root]
- [sed, '-i', 's/NUMBER_LIMIT_IMPORTANT="4-10"/NUMBER_LIMIT_IMPORTANT="3"/g', /etc/snapper/configs/root]

# Allow network interface
- [chmod, '+x', '/etc/cloud/rename_interface.sh']

# Restart the sshd service to apply the new config
- [systemctl, 'restart', 'sshd']

# Make sure the network is up
- [systemctl, restart, NetworkManager]
- [systemctl, status, NetworkManager]

# Cleanup some logs
- [truncate, '-s', '0', '/var/log/audit/audit.log']

# Add logic to truly disable SELinux if disable_selinux = true.
# We'll do it by appending to cloudinit_runcmd_common.
%{if var.disable_selinux}
- [sed, '-i', '-E', 's/^SELINUX=[a-z]+/SELINUX=disabled/', '/etc/selinux/config']
- [setenforce, '0']
%{endif}
EOT
}
