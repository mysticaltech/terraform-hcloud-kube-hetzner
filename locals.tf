locals {
  # ssh_agent_identity is not set if the private key is passed directly, but if ssh agent is used, the public key tells ssh agent which private key to use.
  # For terraforms provisioner.connection.agent_identity, we need the public key as a string.
  ssh_agent_identity = var.ssh_private_key == null ? var.ssh_public_key : null

  # If passed, a key already registered within hetzner is used.
  # Otherwise, a new one will be created by the module.
  hcloud_ssh_key_id = var.hcloud_ssh_key_id == null ? hcloud_ssh_key.k3s[0].id : var.hcloud_ssh_key_id

  # if given as a variable, we want to use the given token. This is needed to restore the cluster
  k3s_token = var.k3s_token == null ? random_password.k3s_token.result : var.k3s_token

  kubernetes_distribution        = var.kubernetes_distribution_type
  secrets_encryption_config_file = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/encryption-config.yaml" : "/etc/rancher/k3s/encryption-config.yaml"
  secrets_encryption_config = var.secrets_encryption ? yamlencode({
    apiVersion = "apiserver.config.k8s.io/v1"
    kind       = "EncryptionConfiguration"
    resources = [{
      resources = ["secrets"]
      providers = [
        {
          aescbc = {
            keys = [{
              name   = "key1"
              secret = base64encode(random_password.secrets_encryption_key[0].result)
            }]
          }
        },
        {
          identity = {}
        }
      ]
    }]
  }) : ""

  k3s_encryption_config_path  = "/etc/rancher/k3s/encryption-config.yaml"
  k3s_encryption_provider_key = base64sha256(local.k3s_token)
  k3s_encryption_config       = <<-EOT
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: kube-hetzner
              secret: ${local.k3s_encryption_provider_key}
      - identity: {}
EOT
  k3s_encryption_write_files = var.k3s_encryption_at_rest && local.kubernetes_distribution == "k3s" ? [
    {
      path        = local.k3s_encryption_config_path
      permissions = "0600"
      content     = local.k3s_encryption_config
    }
  ] : []

  # k3s endpoint used for agent registration, respects control_plane_endpoint override
  k3s_endpoint = coalesce(var.control_plane_endpoint, "https://${var.use_control_plane_lb ? hcloud_load_balancer_network.control_plane.*.ip[0] : module.control_planes[keys(module.control_planes)[0]].private_ipv4_address}:${var.kubeapi_port}")

  ccm_version    = var.hetzner_ccm_version != null ? var.hetzner_ccm_version : data.github_release.hetzner_ccm[0].release_tag
  csi_version    = length(data.github_release.hetzner_csi) == 0 ? var.hetzner_csi_version : data.github_release.hetzner_csi[0].release_tag
  kured_version  = length(data.github_release.kured) == 0 ? var.kured_version : data.github_release.kured[0].release_tag
  calico_version = length(data.github_release.calico) == 0 ? var.calico_version : data.github_release.calico[0].release_tag

  # Determine kured YAML suffix based on version (>= 1.20.0 uses -combined.yaml, < 1.20.0 uses -dockerhub.yaml)
  kured_yaml_suffix = provider::semvers::compare(local.kured_version, "1.20.0") >= 0 ? "combined" : "dockerhub"

  cilium_ipv4_native_routing_cidr = coalesce(var.cilium_ipv4_native_routing_cidr, var.cluster_ipv4_cidr)

  # Check if the user has set custom DNS servers.
  has_dns_servers = length(var.dns_servers) > 0

  # Bit size of the "network_ipv4_cidr".
  network_size = 32 - split("/", var.network_ipv4_cidr)[1]

  # Bit size of each subnet
  subnet_size = local.network_size - log(var.subnet_amount, 2)

  # Separate out IPv4 and IPv6 DNS hosts.
  dns_servers_ipv4 = [for ip in var.dns_servers : ip if provider::assert::ipv4(ip)]
  dns_servers_ipv6 = [for ip in var.dns_servers : ip if provider::assert::ipv6(ip)]

  is_ref_myipv4_used = (
    contains(coalesce(var.firewall_kube_api_source, []), var.myipv4_ref) ||
    contains(coalesce(var.firewall_ssh_source, []), var.myipv4_ref) ||
    contains(flatten([
      for rule in var.extra_firewall_rules : concat(lookup(rule, "source_ips", []), lookup(rule, "destination_ips", []))
    ]), var.myipv4_ref)
  )
  my_public_ipv4      = try(trimspace(data.http.my_ipv4[0].response_body), null)
  my_public_ipv4_cidr = can(cidrhost("${local.my_public_ipv4}/32", 0)) ? "${local.my_public_ipv4}/32" : null

  use_robot_ccm = var.robot_ccm_enabled && var.robot_user != "" && var.robot_password != ""
  # Key of the kube_system_secret-items is the name of the Secret. Values of those items are the key-value pairs of Secret.
  kube_system_secrets = {
    "hcloud" = merge(
      {
        "token"   = var.hcloud_token,
        "network" = data.hcloud_network.k3s.name
      },
      local.use_robot_ccm ? {
        "robot-user"     = var.robot_user,
        "robot-password" = var.robot_password
      } : {}
    ),
    "hcloud-csi" = { "token" = var.hcloud_token }
  }

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
      "[ -s /tmp/encryption-config.yaml ] && mv /tmp/encryption-config.yaml /etc/rancher/k3s/encryption-config.yaml && chmod 0600 /etc/rancher/k3s/encryption-config.yaml",
      # if the server has already been initialized just stop here
      "[ -e /etc/rancher/k3s/k3s.yaml ] && exit 0",
      local.install_additional_k3s_environment,
      local.install_system_alias,
      local.install_kubectl_bash_completion,
    ],
    local.has_dns_servers ? [
      join("\n", compact([
        "# Wait for NetworkManager to be ready",
        "if ! timeout 60 bash -c 'until systemctl is-active --quiet NetworkManager; do echo \"Waiting for NetworkManager to be ready...\"; sleep 2; done'; then",
        "  echo \"ERROR: NetworkManager is not active after timeout\" >&2",
        "  exit 0  # Don't fail cloud-init",
        "fi",
        "# Get the default interface",
        "IFACE=$(ip route show default 2>/dev/null | awk '/^default/ && /dev/ {for(i=1;i<=NF;i++) if($i==\"dev\") {print $(i+1); exit}}')",
        "if [ -z \"$IFACE\" ]; then",
        "  # Fallback: try to get any interface that's up and has an IP",
        "  IFACE=$(ip route show 2>/dev/null | awk '!/^default/ && /dev/ {for(i=1;i<=NF;i++) if($i==\"dev\") {print $(i+1); exit}}')",
        "fi",
        "if [ -n \"$IFACE\" ]; then",
        "  CONNECTION=$(nmcli -g GENERAL.CONNECTION device show \"$IFACE\" 2>/dev/null | head -1)",
        "  if [ -n \"$CONNECTION\" ]; then",
        "    # Disable auto-DNS for both protocols when custom DNS servers are provided",
        "    nmcli con mod \"$CONNECTION\" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes",
        length(local.dns_servers_ipv4) > 0 ? "    nmcli con mod \"$CONNECTION\" ipv4.dns ${join(",", local.dns_servers_ipv4)}" : "",
        length(local.dns_servers_ipv6) > 0 ? "    nmcli con mod \"$CONNECTION\" ipv6.dns ${join(",", local.dns_servers_ipv6)}" : "",
        "  fi",
        "fi"
      ]))
    ] : [],
    local.has_dns_servers ? ["systemctl restart NetworkManager"] : [],
    [
      join("\n", [
        "# Ensure persistent private-network default route (Hetzner DHCP change Aug 11, 2025)",
        "set +e  # Allow idempotent network adjustments",
        "METRIC=30000",
        "",
        "# Determine the private interface dynamically (no hardcoded eth1)",
        "PRIV_IF=$(ip -4 route show ${var.network_ipv4_cidr} 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}' | head -n 1)",
        "if [ -z \"$PRIV_IF\" ]; then",
        "  ROUTE_LINE=$(ip -4 route get ${local.network_gw_ipv4} 2>/dev/null)",
        "  if [ -n \"$ROUTE_LINE\" ] && ! echo \"$ROUTE_LINE\" | grep -q ' via '; then",
        "    PRIV_IF=$(echo \"$ROUTE_LINE\" | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}' | head -n 1)",
        "  fi",
        "fi",
        "if [ -n \"$PRIV_IF\" ]; then",
        "  if systemctl is-active --quiet NetworkManager; then",
        "    NM_CONN=$(nmcli -g GENERAL.CONNECTION device show \"$PRIV_IF\" 2>/dev/null | head -1)",
        "    if [ -n \"$NM_CONN\" ]; then",
        "      # Persist a default route via the private gateway with higher metric than public NICs",
        "      ROUTE_READY=0",
        "      ROUTE_LINE=$(nmcli -g ipv4.routes connection show \"$NM_CONN\" | tr ',' '\\n' | awk '$1==\"0.0.0.0/0\" && $2==\"${local.network_gw_ipv4}\"{print $0; exit}')",
        "      if [ -n \"$ROUTE_LINE\" ]; then",
        "        CUR_ROUTE_METRIC=$(echo \"$ROUTE_LINE\" | awk '{print $3}')",
        "        if [ -z \"$CUR_ROUTE_METRIC\" ] || [ \"$CUR_ROUTE_METRIC\" != \"$METRIC\" ]; then",
        "          nmcli connection modify \"$NM_CONN\" -ipv4.routes \"$ROUTE_LINE\" >/dev/null 2>&1 || true",
        "          if nmcli connection modify \"$NM_CONN\" +ipv4.routes \"0.0.0.0/0 ${local.network_gw_ipv4} $METRIC\" >/dev/null 2>&1; then",
        "            ROUTE_READY=1",
        "          else",
        "            echo \"Warning: Failed to update default route metric on $PRIV_IF. Node may be affected by Hetzner DHCP changes.\" >&2",
        "          fi",
        "        else",
        "          ROUTE_READY=1",
        "        fi",
        "      else",
        "        if nmcli connection modify \"$NM_CONN\" +ipv4.routes \"0.0.0.0/0 ${local.network_gw_ipv4} $METRIC\" >/dev/null 2>&1; then",
        "          ROUTE_READY=1",
        "        else",
        "          echo \"Warning: Failed to persist default route on $PRIV_IF. Node may be affected by Hetzner DHCP changes.\" >&2",
        "        fi",
        "      fi",
        "      if [ \"$ROUTE_READY\" -eq 1 ]; then",
        "        nmcli connection modify \"$NM_CONN\" ipv4.never-default yes >/dev/null 2>&1 || true",
        "        nmcli connection modify \"$NM_CONN\" ipv6.never-default yes >/dev/null 2>&1 || true",
        "        nmcli connection modify \"$NM_CONN\" ipv4.route-metric $METRIC >/dev/null 2>&1 || true",
        "        nmcli connection up \"$NM_CONN\" >/dev/null 2>&1 || true",
        "      fi",
        "    fi",
        "  fi",
        "  # Runtime guard to cover current leases before dispatcher hooks fire",
        "  EXISTING_RT=$(ip -4 route show default dev \"$PRIV_IF\" | awk '$3==\"${local.network_gw_ipv4}\"{print $0; exit}')",
        "  if [ -n \"$EXISTING_RT\" ]; then",
        "    CUR_RT_METRIC=$(echo \"$EXISTING_RT\" | awk 'match($0,/metric ([0-9]+)/,m){print m[1]}')",
        "    if [ -z \"$CUR_RT_METRIC\" ] || [ \"$CUR_RT_METRIC\" != \"$METRIC\" ]; then",
        "      ip -4 route change default via ${local.network_gw_ipv4} dev \"$PRIV_IF\" metric $METRIC 2>/dev/null || true",
        "    fi",
        "  else",
        "    ip -4 route add default via ${local.network_gw_ipv4} dev \"$PRIV_IF\" metric $METRIC 2>/dev/null || true",
        "  fi",
        "else",
        "  echo \"Info: Unable to identify interface that reaches ${local.network_gw_ipv4}; skipping private default route setup.\"",
        "fi",
        "",
        "set -e"
      ])
    ],
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
      "[ -s /tmp/encryption-config.yaml ] && mv /tmp/encryption-config.yaml /etc/rancher/rke2/encryption-config.yaml && chmod 0600 /etc/rancher/rke2/encryption-config.yaml",
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
        "https://github.com/kubereboot/kured/releases/download/${local.kured_version}/kured-${local.kured_version}-${local.kured_yaml_suffix}.yaml",
        "https://github.com/rancher/system-upgrade-controller/releases/download/${var.sys_upgrade_controller_version}/system-upgrade-controller.yaml",
        "https://github.com/rancher/system-upgrade-controller/releases/download/${var.sys_upgrade_controller_version}/crd.yaml"
      ],
      var.hetzner_ccm_use_helm ? [] : ["https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/${local.ccm_version}/ccm-networks.yaml"],
      var.enable_load_balancer_monitoring && var.hetzner_ccm_use_helm ? ["load_balancer_monitoring.yaml"] : [],
      var.disable_hetzner_csi ? [] : ["hcloud-csi.yaml"],
      lookup(local.ingress_controller_install_resources, var.ingress_controller, []),
      local.kubernetes_distribution == "k3s" ? lookup(local.cni_install_resources, var.cni_plugin, []) : [],
      var.cni_plugin == "cilium" && var.cilium_egress_gateway_enabled && var.cilium_egress_gateway_ha_enabled ? ["cilium_egress_gateway_ha.yaml"] : [],
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

  apply_k3s_selinux = [<<-EOT
echo "Checking k3s SELinux policy status..."
if command -v semodule >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1 && rpm -q k3s-selinux >/dev/null 2>&1; then
  if [ -f /usr/share/selinux/packages/k3s.pp ]; then
    echo "Applying k3s SELinux policy..."
    semodule -v -i /usr/share/selinux/packages/k3s.pp || true
  else
    echo "k3s SELinux policy file not found at /usr/share/selinux/packages/k3s.pp; skipping"
  fi
else
  echo "k3s-selinux package or semodule not available; skipping"
fi
EOT
  ]
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

  # Used for mapping existing node names (which include the random suffix) back into nodepool names.
  cluster_prefix_for_node_names = var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""

  configured_control_plane_nodepool_names = distinct([for np in var.control_plane_nodepools : np.name])
  configured_agent_nodepool_names         = distinct([for np in var.agent_nodepools : np.name])

  # Union for any cluster-wide checks.
  configured_nodepool_names = distinct(concat(
    local.configured_control_plane_nodepool_names,
    local.configured_agent_nodepool_names,
  ))

  existing_control_plane_servers_info = [
    for s in data.hcloud_servers.existing_control_plane_nodes.servers : {
      # Remove the per-server random suffix (e.g. "-abc") that the host module appends.
      name_base = trimprefix(
        length(split("-", s.name)) > 1
        ? join("-", slice(split("-", s.name), 0, length(split("-", s.name)) - 1))
        : s.name,
        local.cluster_prefix_for_node_names,
      )

      # Optional: populated after the first apply on this version. Missing labels => treated as unknown.
      os_label = contains(["microos", "leapmicro"], try(s.labels["kube-hetzner/os"], "")) ? try(s.labels["kube-hetzner/os"], null) : null
    }
  ]

  existing_agent_servers_info = [
    for s in data.hcloud_servers.existing_agent_nodes.servers : {
      # Remove the per-server random suffix (e.g. "-abc") that the host module appends.
      name_base = trimprefix(
        length(split("-", s.name)) > 1
        ? join("-", slice(split("-", s.name), 0, length(split("-", s.name)) - 1))
        : s.name,
        local.cluster_prefix_for_node_names,
      )

      # Optional: populated after the first apply on this version. Missing labels => treated as unknown.
      os_label = contains(["microos", "leapmicro"], try(s.labels["kube-hetzner/os"], "")) ? try(s.labels["kube-hetzner/os"], null) : null
    }
  ]

  existing_servers_info = concat(local.existing_control_plane_servers_info, local.existing_agent_servers_info)

  existing_control_plane_servers_nodepool_os = [
    for s in local.existing_control_plane_servers_info : merge(s, {
      # Choose the best-matching nodepool for this server name ("longest prefix wins") so that:
      # - node name suffixes (e.g. "-0") don't break matching
      # - nodepool "auto" doesn't incorrectly match "auto-large"
      nodepool = (
        length([
          for np in local.configured_control_plane_nodepool_names :
          np
          if startswith(s.name_base, np) && (length(s.name_base) == length(np) || substr(s.name_base, length(np), 1) == "-")
        ]) > 0
        ? one([
          for np in local.configured_control_plane_nodepool_names :
          np
          if(
            startswith(s.name_base, np)
            && (length(s.name_base) == length(np) || substr(s.name_base, length(np), 1) == "-")
            && length(np) == max([
              for np2 in local.configured_control_plane_nodepool_names :
              length(np2)
              if startswith(s.name_base, np2) && (length(s.name_base) == length(np2) || substr(s.name_base, length(np2), 1) == "-")
            ]...)
          )
        ])
        : null
      )
    })
  ]

  existing_agent_servers_nodepool_os = [
    for s in local.existing_agent_servers_info : merge(s, {
      # Choose the best-matching nodepool for this server name ("longest prefix wins") so that:
      # - node name suffixes (e.g. "-0") don't break matching
      # - nodepool "auto" doesn't incorrectly match "auto-large"
      nodepool = (
        length([
          for np in local.configured_agent_nodepool_names :
          np
          if startswith(s.name_base, np) && (length(s.name_base) == length(np) || substr(s.name_base, length(np), 1) == "-")
        ]) > 0
        ? one([
          for np in local.configured_agent_nodepool_names :
          np
          if(
            startswith(s.name_base, np)
            && (length(s.name_base) == length(np) || substr(s.name_base, length(np), 1) == "-")
            && length(np) == max([
              for np2 in local.configured_agent_nodepool_names :
              length(np2)
              if startswith(s.name_base, np2) && (length(s.name_base) == length(np2) || substr(s.name_base, length(np2), 1) == "-")
            ]...)
          )
        ])
        : null
      )
    })
  ]

  existing_control_plane_nodepool_names = distinct(compact([for s in local.existing_control_plane_servers_nodepool_os : s.nodepool]))
  existing_agent_nodepool_names         = distinct(compact([for s in local.existing_agent_servers_nodepool_os : s.nodepool]))

  existing_os_labels_by_control_plane_nodepool = {
    for np in local.configured_control_plane_nodepool_names :
    np => distinct(compact([for s in local.existing_control_plane_servers_nodepool_os : s.os_label if s.nodepool == np]))
  }

  existing_os_labels_by_agent_nodepool = {
    for np in local.configured_agent_nodepool_names :
    np => distinct(compact([for s in local.existing_agent_servers_nodepool_os : s.os_label if s.nodepool == np]))
  }

  existing_cluster_os_labels = distinct(compact([for s in local.existing_servers_info : s.os_label]))

  control_plane_nodepool_default_os = {
    for nodepool_name in local.configured_control_plane_nodepool_names :
    nodepool_name => (
      !contains(local.existing_control_plane_nodepool_names, nodepool_name)
      ? "leapmicro"
      : (
        length(local.existing_os_labels_by_control_plane_nodepool[nodepool_name]) == 1
        ? local.existing_os_labels_by_control_plane_nodepool[nodepool_name][0]
        : "microos"
      )
    )
  }

  agent_nodepool_default_os = {
    for nodepool_name in local.configured_agent_nodepool_names :
    nodepool_name => (
      !contains(local.existing_agent_nodepool_names, nodepool_name)
      ? "leapmicro"
      : (
        length(local.existing_os_labels_by_agent_nodepool[nodepool_name]) == 1
        ? local.existing_os_labels_by_agent_nodepool[nodepool_name][0]
        : "microos"
      )
    )
  }

  control_plane_nodes_from_integer_counts = merge([
    for pool_index, nodepool_obj in var.control_plane_nodepools : {
      for node_index in range(coalesce(nodepool_obj.count, 0)) :
      format("%s-%s-%s", pool_index, node_index, nodepool_obj.name) => {
        nodepool_name : nodepool_obj.name,
        server_type : nodepool_obj.server_type,
        location : nodepool_obj.location,
        labels : concat(local.default_control_plane_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
        hcloud_labels : nodepool_obj.hcloud_labels,
        taints : compact(concat(local.default_control_plane_taints, nodepool_obj.taints)),
        kubelet_args : nodepool_obj.kubelet_args,
        backups : nodepool_obj.backups,
        swap_size : nodepool_obj.swap_size,
        zram_size : nodepool_obj.zram_size,
        index : node_index
        selinux : nodepool_obj.selinux
        os : coalesce(nodepool_obj.os, local.control_plane_nodepool_default_os[nodepool_obj.name])
        placement_group_compat_idx : nodepool_obj.placement_group_compat_idx,
        placement_group : nodepool_obj.placement_group,
        disable_ipv4 : nodepool_obj.disable_ipv4 || local.use_nat_router,
        disable_ipv6 : nodepool_obj.disable_ipv6 || local.use_nat_router,
        primary_ipv4_id : nodepool_obj.primary_ipv4_id,
        primary_ipv6_id : nodepool_obj.primary_ipv6_id,
        network_id : nodepool_obj.network_id,
        keep_disk : nodepool_obj.keep_disk,
        extra_write_files : nodepool_obj.extra_write_files,
        extra_runcmd : nodepool_obj.extra_runcmd,
        attached_volumes : nodepool_obj.attached_volumes,
      }
    }
  ]...)

  control_plane_nodes_from_maps_for_counts = merge([
    for pool_index, nodepool_obj in var.control_plane_nodepools : {
      for node_key, node_obj in coalesce(nodepool_obj.nodes, {}) :
      format("%s-%s-%s", pool_index, node_key, nodepool_obj.name) => merge(
        {
          nodepool_name : nodepool_obj.name,
          server_type : nodepool_obj.server_type,
          location : nodepool_obj.location,
          labels : concat(local.default_control_plane_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
          taints : compact(concat(local.default_control_plane_taints, nodepool_obj.taints)),
          kubelet_args : nodepool_obj.kubelet_args,
          backups : nodepool_obj.backups,
          swap_size : nodepool_obj.swap_size,
          zram_size : nodepool_obj.zram_size,
          selinux : nodepool_obj.selinux,
          os : coalesce(nodepool_obj.os, local.control_plane_nodepool_default_os[nodepool_obj.name]),
          placement_group_compat_idx : nodepool_obj.placement_group_compat_idx,
          placement_group : nodepool_obj.placement_group,
          index : floor(tonumber(node_key)),
          disable_ipv4 : nodepool_obj.disable_ipv4 || local.use_nat_router,
          disable_ipv6 : nodepool_obj.disable_ipv6 || local.use_nat_router,
          network_id : nodepool_obj.network_id,
          extra_write_files : nodepool_obj.extra_write_files,
          extra_runcmd : nodepool_obj.extra_runcmd,
        },
        { for key, value in node_obj : key => value if value != null },
        {
          labels : concat(local.default_control_plane_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels, coalesce(node_obj.labels, [])),
          taints : compact(concat(local.default_control_plane_taints, nodepool_obj.taints, coalesce(node_obj.taints, []))),
          extra_write_files : concat(nodepool_obj.extra_write_files, coalesce(node_obj.extra_write_files, [])),
          extra_runcmd : concat(nodepool_obj.extra_runcmd, coalesce(node_obj.extra_runcmd, [])),
        }
      )
    }
  ]...)

  control_plane_nodes = merge(
    local.control_plane_nodes_from_integer_counts,
    local.control_plane_nodes_from_maps_for_counts,
  )

  agent_nodes_from_integer_counts = merge([
    for pool_index, nodepool_obj in var.agent_nodepools : {
      # coalesce(nodepool_obj.count, 0) means we select those nodepools who's size is set by an integer count.
      for node_index in range(coalesce(nodepool_obj.count, 0)) :
      format("%s-%s-%s", pool_index, node_index, nodepool_obj.name) => {
        nodepool_name : nodepool_obj.name,
        server_type : nodepool_obj.server_type,
        longhorn_volume_size : coalesce(nodepool_obj.longhorn_volume_size, 0),
        longhorn_mount_path : nodepool_obj.longhorn_mount_path,
        floating_ip : lookup(nodepool_obj, "floating_ip", false),
        floating_ip_type : lookup(nodepool_obj, "floating_ip_type", "ipv4"),
        floating_ip_rdns : lookup(nodepool_obj, "floating_ip_rdns", false),
        location : nodepool_obj.location,
        labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
        hcloud_labels : nodepool_obj.hcloud_labels,
        taints : compact(concat(local.default_agent_taints, nodepool_obj.taints)),
        kubelet_args : nodepool_obj.kubelet_args,
        backups : lookup(nodepool_obj, "backups", false),
        swap_size : nodepool_obj.swap_size,
        zram_size : nodepool_obj.zram_size,
        index : node_index
        selinux : nodepool_obj.selinux
        os : coalesce(nodepool_obj.os, local.agent_nodepool_default_os[nodepool_obj.name])
        placement_group_compat_idx : nodepool_obj.placement_group_compat_idx,
        placement_group : nodepool_obj.placement_group,
        disable_ipv4 : nodepool_obj.disable_ipv4 || local.use_nat_router,
        disable_ipv6 : nodepool_obj.disable_ipv6 || local.use_nat_router,
        primary_ipv4_id : nodepool_obj.primary_ipv4_id,
        primary_ipv6_id : nodepool_obj.primary_ipv6_id,
        network_id : nodepool_obj.network_id,
        keep_disk : nodepool_obj.keep_disk,
        extra_write_files : nodepool_obj.extra_write_files,
        extra_runcmd : nodepool_obj.extra_runcmd,
        attached_volumes : nodepool_obj.attached_volumes,
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
          longhorn_mount_path : nodepool_obj.longhorn_mount_path,
          floating_ip : lookup(nodepool_obj, "floating_ip", false),
          floating_ip_type : lookup(nodepool_obj, "floating_ip_type", "ipv4"),
          floating_ip_rdns : lookup(nodepool_obj, "floating_ip_rdns", false),
          location : nodepool_obj.location,
          labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
          hcloud_labels : nodepool_obj.hcloud_labels,
          taints : compact(concat(local.default_agent_taints, nodepool_obj.taints)),
          kubelet_args : nodepool_obj.kubelet_args,
          backups : lookup(nodepool_obj, "backups", false),
          swap_size : nodepool_obj.swap_size,
          zram_size : nodepool_obj.zram_size,
          selinux : nodepool_obj.selinux,
          os : coalesce(nodepool_obj.os, local.agent_nodepool_default_os[nodepool_obj.name]),
          placement_group_compat_idx : nodepool_obj.placement_group_compat_idx,
          placement_group : nodepool_obj.placement_group,
          index : floor(tonumber(node_key)),
          disable_ipv4 : nodepool_obj.disable_ipv4 || local.use_nat_router,
          disable_ipv6 : nodepool_obj.disable_ipv6 || local.use_nat_router,
          primary_ipv4_id : nodepool_obj.primary_ipv4_id,
          primary_ipv6_id : nodepool_obj.primary_ipv6_id,
          network_id : nodepool_obj.network_id,
          keep_disk : nodepool_obj.keep_disk,
          extra_write_files : nodepool_obj.extra_write_files,
          extra_runcmd : nodepool_obj.extra_runcmd,
          attached_volumes : nodepool_obj.attached_volumes,
        },
        { for key, value in node_obj : key => value if value != null },
        {
          labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels, coalesce(node_obj.labels, [])),
          taints : compact(concat(local.default_agent_taints, nodepool_obj.taints, coalesce(node_obj.taints, []))),
          extra_write_files : concat(nodepool_obj.extra_write_files, coalesce(node_obj.extra_write_files, [])),
          extra_runcmd : concat(nodepool_obj.extra_runcmd, coalesce(node_obj.extra_runcmd, [])),
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

  default_autoscaler_os = length(local.existing_servers_info) == 0 ? "leapmicro" : (
    length(local.existing_cluster_os_labels) == 1 ? local.existing_cluster_os_labels[0] : "microos"
  )

  autoscaler_nodepools_os = [
    for np in var.autoscaler_nodepools :
    coalesce(np.os, local.default_autoscaler_os)
  ]

  node_os_arch_pairs = concat(
    [
      for n in values(local.control_plane_nodes) :
      { os = n.os, arch = substr(n.server_type, 0, 3) == "cax" ? "arm" : "x86" }
    ],
    [
      for n in values(local.agent_nodes) :
      { os = n.os, arch = substr(n.server_type, 0, 3) == "cax" ? "arm" : "x86" }
    ],
    [
      for np in var.autoscaler_nodepools :
      { os = coalesce(np.os, local.default_autoscaler_os), arch = substr(np.server_type, 0, 3) == "cax" ? "arm" : "x86" }
    ],
  )

  os_arch_requirements = {
    microos = {
      arm = anytrue([for p in local.node_os_arch_pairs : p.os == "microos" && p.arch == "arm"])
      x86 = anytrue([for p in local.node_os_arch_pairs : p.os == "microos" && p.arch == "x86"])
    }
    leapmicro = {
      arm = anytrue([for p in local.node_os_arch_pairs : p.os == "leapmicro" && p.arch == "arm"])
      x86 = anytrue([for p in local.node_os_arch_pairs : p.os == "leapmicro" && p.arch == "x86"])
    }
  }

  snapshot_id_by_os = {
    leapmicro = {
      arm = var.leapmicro_arm_snapshot_id != "" ? var.leapmicro_arm_snapshot_id : try(data.hcloud_image.leapmicro_arm_snapshot[0].id, "")
      x86 = var.leapmicro_x86_snapshot_id != "" ? var.leapmicro_x86_snapshot_id : try(data.hcloud_image.leapmicro_x86_snapshot[0].id, "")
    }
    microos = {
      arm = var.microos_arm_snapshot_id != "" ? var.microos_arm_snapshot_id : try(data.hcloud_image.microos_arm_snapshot[0].id, "")
      x86 = var.microos_x86_snapshot_id != "" ? var.microos_x86_snapshot_id : try(data.hcloud_image.microos_x86_snapshot[0].id, "")
    }
  }

  use_existing_network = length(var.existing_network_id) > 0

  use_nat_router = var.nat_router != null

  ssh_bastion = coalesce(
    local.use_nat_router ? {
      bastion_host        = hcloud_server.nat_router[0].ipv4_address
      bastion_port        = var.ssh_port
      bastion_user        = "nat-router"
      bastion_private_key = var.ssh_private_key
    } : null,
    var.optional_bastion_host,
    {
      bastion_host        = null
      bastion_port        = null
      bastion_user        = null
      bastion_private_key = null
    }
  )

  # Create subnets from the base network CIDR.
  # Control planes allocate from the end of the range and agents from the start (0, 1, 2...)
  network_ipv4_subnets = [for index in range(var.subnet_amount) : cidrsubnet(var.network_ipv4_cidr, log(var.subnet_amount, 2), index)]

  cluster_ipv4_cidr_effective = var.cluster_ipv4_cidr != null && trimspace(var.cluster_ipv4_cidr) != "" ? var.cluster_ipv4_cidr : null
  service_ipv4_cidr_effective = var.service_ipv4_cidr != null && trimspace(var.service_ipv4_cidr) != "" ? var.service_ipv4_cidr : null
  cluster_ipv6_cidr_effective = var.cluster_ipv6_cidr != null && trimspace(var.cluster_ipv6_cidr) != "" ? var.cluster_ipv6_cidr : null
  service_ipv6_cidr_effective = var.service_ipv6_cidr != null && trimspace(var.service_ipv6_cidr) != "" ? var.service_ipv6_cidr : null

  cluster_cidrs = compact([
    local.cluster_ipv4_cidr_effective,
    local.cluster_ipv6_cidr_effective,
  ])
  service_cidrs = compact([
    local.service_ipv4_cidr_effective,
    local.service_ipv6_cidr_effective,
  ])

  cluster_cidr = join(",", local.cluster_cidrs)
  service_cidr = join(",", local.service_cidrs)

  # By convention the DNS service (usually core-dns) is assigned the 10th IP address in the service CIDR block
  cluster_dns_ipv4 = var.cluster_dns_ipv4 != null ? var.cluster_dns_ipv4 : (local.service_ipv4_cidr_effective != null ? cidrhost(local.service_ipv4_cidr_effective, 10) : null)
  cluster_dns_ipv6 = local.service_ipv6_cidr_effective != null ? cidrhost(local.service_ipv6_cidr_effective, 10) : null
  cluster_dns_values = compact([
    local.cluster_dns_ipv4,
    local.cluster_dns_ipv6,
  ])
  cluster_dns = join(",", local.cluster_dns_values)

  # The gateway's IP address is always the first IP address of the subnet's IP range
  network_gw_ipv4 = cidrhost(var.network_ipv4_cidr, 1)

  # if we are in a single cluster config, we use the default klipper lb instead of Hetzner LB
  control_plane_count    = length(var.control_plane_nodepools) > 0 ? sum([for v in var.control_plane_nodepools : length(coalesce(v.nodes, {})) + coalesce(v.count, 0)]) : 0
  agent_count            = length(var.agent_nodepools) > 0 ? sum([for v in var.agent_nodepools : length(coalesce(v.nodes, {})) + coalesce(v.count, 0)]) : 0
  autoscaler_max_count   = length(var.autoscaler_nodepools) > 0 ? sum([for v in var.autoscaler_nodepools : v.max_nodes]) : 0
  is_single_node_cluster = (local.control_plane_count + local.agent_count + local.autoscaler_max_count) == 1

  using_klipper_lb = var.enable_klipper_metal_lb || local.is_single_node_cluster

  has_external_load_balancer = local.using_klipper_lb || var.ingress_controller == "none"
  load_balancer_name         = "${var.cluster_name}-${var.ingress_controller}"
  managed_ingress_controllers = [
    "traefik",
    "nginx",
    "haproxy"
  ]
  is_managed_ingress_controller = contains(local.managed_ingress_controllers, var.ingress_controller)

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
    "nginx"   = "ingress-nginx"
    "haproxy" = "haproxy"
  }

  ingress_controller_namespace = var.ingress_target_namespace != "" ? var.ingress_target_namespace : (
    var.ingress_controller_use_system_namespace ? "kube-system" : lookup(local.default_ingress_namespace_mapping, var.ingress_controller, "")
  )
  ingress_replica_count     = (var.ingress_replica_count > 0) ? var.ingress_replica_count : (local.agent_count > 2) ? 3 : (local.agent_count == 2) ? 2 : 1
  ingress_max_replica_count = (var.ingress_max_replica_count > local.ingress_replica_count) ? var.ingress_max_replica_count : local.ingress_replica_count

  # disable k3s extras
  # TODO: Extend to work with rke2
  disable_extras      = concat(var.enable_local_storage ? [] : ["local-storage"], local.using_klipper_lb ? [] : ["servicelb"], ["traefik"], var.enable_metrics_server ? [] : ["metrics-server"])
  disable_rke2_extras = ["rke2-ingress-nginx"]

  # Determine if scheduling should be allowed on control plane nodes, which will be always true for single node clusters and clusters or if scheduling is allowed on control plane nodes
  allow_scheduling_on_control_plane = local.is_single_node_cluster ? true : var.allow_scheduling_on_control_plane
  # Determine if loadbalancer target should be allowed on control plane nodes, which will be always true for single node clusters or if scheduling is allowed on control plane nodes
  allow_loadbalancer_target_on_control_plane = local.is_single_node_cluster ? true : var.allow_scheduling_on_control_plane

  # Build list of label maps to include in LB target selector based on allow_loadbalancer_target_on_control_plane
  lb_target_groups = (
    local.allow_loadbalancer_target_on_control_plane ?
    [local.labels_control_plane_node, local.labels_agent_node] :
    [local.labels_agent_node]
  )

  upgrade_label = local.kubernetes_distribution == "rke2" ? "rke2_upgrade=true" : "k3s_upgrade=true"

  # Default node labels
  default_agent_labels = concat(
    var.exclude_agents_from_external_load_balancers ? ["node.kubernetes.io/exclude-from-external-load-balancers=true"] : [],
    var.automatically_upgrade_k3s ? [local.upgrade_label] : []
  )
  default_control_plane_labels = concat(local.allow_loadbalancer_target_on_control_plane ? [] : ["node.kubernetes.io/exclude-from-external-load-balancers=true"], var.automatically_upgrade_k3s ? [local.upgrade_label] : [])
  default_autoscaler_labels    = concat([], var.automatically_upgrade_k3s ? [local.upgrade_label] : [])

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
        port        = tostring(var.kubeapi_port)
        source_ips  = var.firewall_kube_api_source
      }
    ],
    length(var.cluster_autoscaler_metrics_firewall_source) == 0 || length(var.autoscaler_nodepools) == 0 ? [] : [
      {
        description = "Allow Incoming Requests to Cluster Autoscaler Metrics NodePort"
        direction   = "in"
        protocol    = "tcp"
        port        = "30085"
        source_ips  = var.cluster_autoscaler_metrics_firewall_source
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

  # convert the merged map back to a list and resolve the myipv4 placeholder
  firewall_rules_list = [for _, rule in local.firewall_rules_merged : {
    description     = rule.description
    direction       = rule.direction
    protocol        = rule.protocol
    port            = lookup(rule, "port", null)
    source_ips      = compact([for ip in lookup(rule, "source_ips", []) : ip == var.myipv4_ref ? local.my_public_ipv4_cidr : ip])
    destination_ips = compact([for ip in lookup(rule, "destination_ips", []) : ip == var.myipv4_ref ? local.my_public_ipv4_cidr : ip])
  } if rule != null]

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
      flannel-backend        = var.flannel_backend != null ? var.flannel_backend : (var.enable_wireguard ? "wireguard-native" : "vxlan")
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

  kubelet_arg                 = concat(["cloud-provider=external", "volume-plugin-dir=/var/lib/kubelet/volumeplugins"], var.k3s_kubelet_config != "" ? ["config=/etc/rancher/k3s/kubelet-config.yaml"] : [])
  kube_controller_manager_arg = "flex-volume-plugin-dir=/var/lib/kubelet/volumeplugins"
  flannel_iface               = "eth1"
  authentication_config_file  = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/authentication_config.yaml" : "/etc/rancher/k3s/authentication_config.yaml"
  audit_policy_file           = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/audit-policy.yaml" : "/etc/rancher/k3s/audit-policy.yaml"
  control_plane_service_name  = local.kubernetes_distribution == "rke2" ? "rke2-server" : "k3s"
  agent_service_name          = local.kubernetes_distribution == "rke2" ? "rke2-agent" : "k3s-agent"

  kube_apiserver_arg = concat(
    var.authentication_config != "" ? ["authentication-config=${local.authentication_config_file}"] : [],
    var.k3s_audit_policy_config != "" ? [
      "audit-policy-file=${local.audit_policy_file}",
      "audit-log-path=${var.k3s_audit_log_path}",
      "audit-log-maxage=${var.k3s_audit_log_maxage}",
      "audit-log-maxbackup=${var.k3s_audit_log_maxbackup}",
      "audit-log-maxsize=${var.k3s_audit_log_maxsize}"
    ] : []
  )

  cilium_values_default = <<EOT
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
k8sServicePort: "${local.kubernetes_distribution == "rke2" ? tostring(var.kubeapi_port) : "6444"}"

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
  acceleration: "${var.cilium_loadbalancer_acceleration_mode}"

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


MTU: %{if local.use_robot_ccm} 1350 %{else} 1450 %{endif}
  EOT

  cilium_values = module.values_merger_cilium.values

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

  longhorn_values_default = <<EOT
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

  longhorn_values = module.values_merger_longhorn.values

  csi_driver_smb_values_default = <<EOT
EOT

  csi_driver_smb_values = module.values_merger_csi_driver_smb.values

  hetzner_csi_values_default = <<-EOT
node:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
%{if !local.allow_scheduling_on_control_plane~}
              - key: "node-role.kubernetes.io/control-plane"
                operator: DoesNotExist
%{endif~}
              - key: "instance.hetzner.cloud/provided-by"
                operator: NotIn
                values:
                  - robot
EOT

  hetzner_csi_values = module.values_merger_hetzner_csi.values

  nginx_values_default = <<EOT
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

  nginx_values = module.values_merger_nginx.values

  hetzner_ccm_values_default = <<EOT
networking:
  enabled: true
  clusterCIDR: "${var.cluster_ipv4_cidr}"
%{if local.use_robot_ccm~}
robot:
  enabled: true
%{endif~}

args:
  cloud-provider: hcloud
  allow-untagged-cloud: ""
  route-reconciliation-period: 30s
  webhook-secure-port: "0"
%{if local.using_klipper_lb~}
  secure-port: "10288"
%{endif~}
env:
  HCLOUD_LOAD_BALANCERS_LOCATION:
    value: "${var.load_balancer_location}"
  HCLOUD_LOAD_BALANCERS_USE_PRIVATE_IP:
    value: "true"
  HCLOUD_LOAD_BALANCERS_ENABLED:
    value: "${!local.using_klipper_lb}"
  HCLOUD_LOAD_BALANCERS_DISABLE_PRIVATE_INGRESS:
    value: "true"
%{if local.use_robot_ccm~}
  HCLOUD_NETWORK_ROUTES_ENABLED:
    value: "false"
%{endif~}
# Use host network to avoid circular dependency with CNI
hostNetwork: true
  EOT

  hetzner_ccm_values = module.values_merger_hetzner_ccm.values

  haproxy_values_default = <<EOT
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

haproxy_values = module.values_merger_haproxy.values

traefik_values_default = <<EOT
image:
  tag: ${var.traefik_image_tag}
deployment:
  replicas: ${local.ingress_replica_count}
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
    http:
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
%{if !local.using_klipper_lb~}
  websecure:
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
    protocol: ${upper(option.protocol)}
    observability:
      metrics: false
      accessLogs: false
      tracing: false
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
%{if var.traefik_provider_kubernetes_gateway_enabled~}
providers:
  kubernetesGateway:
    enabled: true
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

traefik_values = module.values_merger_traefik.values

rancher_values_default = <<EOT
hostname: "${var.rancher_hostname != "" ? var.rancher_hostname : var.lb_hostname}"
replicas: ${length(local.control_plane_nodes)}
bootstrapPassword: "${length(var.rancher_bootstrap_password) == 0 ? resource.random_password.rancher_bootstrap[0].result : var.rancher_bootstrap_password}"
global:
  cattle:
    psp:
      enabled: false
  EOT

rancher_values = module.values_merger_rancher.values

cert_manager_values_default = <<EOT
crds:
  enabled: true
  keep: true
%{if var.traefik_provider_kubernetes_gateway_enabled~}
config:
  apiVersion: controller.config.cert-manager.io/v1alpha1
  kind: ControllerConfiguration
  enableGatewayAPI: true
%{endif~}
%{if var.ingress_controller == "nginx"~}
extraArgs:
  - --feature-gates=ACMEHTTP01IngressPathTypeExact=false
%{endif~}
  EOT

cert_manager_values = module.values_merger_cert_manager.values

kured_options = merge({
  "reboot-command" : "/usr/bin/systemctl reboot",
  "pre-reboot-node-labels" : "kured=rebooting",
  "post-reboot-node-labels" : "kured=done",
  "period" : "5m",
  "reboot-sentinel" : "/sentinel/reboot-required"
}, var.kured_options)
kured_reboot_sentinel = lookup(local.kured_options, "reboot-sentinel", "/sentinel/reboot-required")

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

k3s_kubelet_config_update_script = <<EOF
set -e
DATE=`date +%Y-%m-%d_%H-%M-%S`
BACKUP_FILE="/tmp/kubelet-config_$DATE.yaml"
HAS_BACKUP=false

if cmp -s /tmp/kubelet-config.yaml /etc/rancher/k3s/kubelet-config.yaml; then
  echo "No update required to the kubelet-config.yaml file"
else
  if [ -f "/etc/rancher/k3s/kubelet-config.yaml" ]; then
    echo "Backing up /etc/rancher/k3s/kubelet-config.yaml to $BACKUP_FILE"
    cp /etc/rancher/k3s/kubelet-config.yaml "$BACKUP_FILE"
    HAS_BACKUP=true
  fi
  echo "Updated kubelet-config.yaml detected, restart of k3s service required"
  cp /tmp/kubelet-config.yaml /etc/rancher/k3s/kubelet-config.yaml

  restart_failed() {
    local SERVICE_NAME="$1"
    echo "Error: Failed to restart $SERVICE_NAME"
    if [ "$HAS_BACKUP" = true ]; then
      echo "Restoring from backup $BACKUP_FILE"
      cp "$BACKUP_FILE" /etc/rancher/k3s/kubelet-config.yaml
      echo "Attempting to restart $SERVICE_NAME with restored config..."
      systemctl restart "$SERVICE_NAME" || echo "Warning: Restart after restore also failed"
    else
      echo "No backup available to restore (first-time config)"
      rm -f /etc/rancher/k3s/kubelet-config.yaml
      echo "Attempting to restart $SERVICE_NAME without kubelet config..."
      systemctl restart "$SERVICE_NAME" || echo "Warning: Restart without config also failed"
    fi
    exit 1
  }

  if systemctl is-active --quiet k3s; then
    systemctl restart k3s || restart_failed k3s
  elif systemctl is-active --quiet k3s-agent; then
    systemctl restart k3s-agent || restart_failed k3s-agent
  else
    echo "Warning: No active k3s or k3s-agent service found, skipping restart"
  fi
  echo "k3s service or k3s-agent service (re)started successfully"
fi
EOF

rke2_kubelet_config_update_script = <<EOF
set -e
DATE=`date +%Y-%m-%d_%H-%M-%S`
BACKUP_FILE="/tmp/kubelet-config_$DATE.yaml"
HAS_BACKUP=false

if cmp -s /tmp/kubelet-config.yaml /etc/rancher/rke2/kubelet-config.yaml; then
  echo "No update required to the kubelet-config.yaml file"
else
  if [ -f "/etc/rancher/rke2/kubelet-config.yaml" ]; then
    echo "Backing up /etc/rancher/rke2/kubelet-config.yaml to $BACKUP_FILE"
    cp /etc/rancher/rke2/kubelet-config.yaml "$BACKUP_FILE"
    HAS_BACKUP=true
  fi
  echo "Updated kubelet-config.yaml detected, restart of rke2 service required"
  cp /tmp/kubelet-config.yaml /etc/rancher/rke2/kubelet-config.yaml

  restart_failed() {
    local SERVICE_NAME="$1"
    echo "Error: Failed to restart $SERVICE_NAME"
    if [ "$HAS_BACKUP" = true ]; then
      echo "Restoring from backup $BACKUP_FILE"
      cp "$BACKUP_FILE" /etc/rancher/rke2/kubelet-config.yaml
      echo "Attempting to restart $SERVICE_NAME with restored config..."
      systemctl restart "$SERVICE_NAME" || echo "Warning: Restart after restore also failed"
    else
      echo "No backup available to restore (first-time config)"
      rm -f /etc/rancher/rke2/kubelet-config.yaml
      echo "Attempting to restart $SERVICE_NAME without kubelet config..."
      systemctl restart "$SERVICE_NAME" || echo "Warning: Restart without config also failed"
    fi
    exit 1
  }

  if systemctl is-active --quiet rke2-server; then
    systemctl restart rke2-server || restart_failed rke2-server
  elif systemctl is-active --quiet rke2-agent; then
    systemctl restart rke2-agent || restart_failed rke2-agent
  else
    echo "Warning: No active rke2-server or rke2-agent service found, skipping restart"
  fi
  echo "rke2-server service or rke2-agent service (re)started successfully"
fi
EOF

k3s_config_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`

restart_or_signal_update() {
  local SERVICE_NAME="$1"
  if ${var.k8s_config_updates_use_kured_sentinel}; then
    SENTINEL="${local.kured_reboot_sentinel}"
    mkdir -p "$(dirname "$SENTINEL")"
    touch "$SENTINEL"
    echo "Triggered Kured reboot sentinel at $SENTINEL instead of restarting $SERVICE_NAME"
    return 0
  fi
  systemctl restart "$SERVICE_NAME"
}

if cmp -s /tmp/config.yaml /etc/rancher/k3s/config.yaml; then
  echo "No update required to the config.yaml file"
else
  if [ -f "/etc/rancher/k3s/config.yaml" ]; then
    echo "Backing up /etc/rancher/k3s/config.yaml to /tmp/config_$DATE.yaml"
    cp /etc/rancher/k3s/config.yaml /tmp/config_$DATE.yaml
  fi
  echo "Updated config.yaml detected, restart of k3s service required"
  cp /tmp/config.yaml /etc/rancher/k3s/config.yaml
  if [ -s /tmp/encryption-config.yaml ]; then
    cp /tmp/encryption-config.yaml /etc/rancher/k3s/encryption-config.yaml
    chmod 0600 /etc/rancher/k3s/encryption-config.yaml
  fi
  if systemctl is-active --quiet k3s; then
    restart_or_signal_update k3s || (echo "Error: Failed to restart k3s. Restoring /etc/rancher/k3s/config.yaml from backup" && cp /tmp/config_$DATE.yaml /etc/rancher/k3s/config.yaml && restart_or_signal_update k3s)
  elif systemctl is-active --quiet k3s-agent; then
    restart_or_signal_update k3s-agent || (echo "Error: Failed to restart k3s-agent. Restoring /etc/rancher/k3s/config.yaml from backup" && cp /tmp/config_$DATE.yaml /etc/rancher/k3s/config.yaml && restart_or_signal_update k3s-agent)
  else
    echo "No active k3s or k3s-agent service found"
  fi
  echo "k3s service or k3s-agent service (re)started successfully"
fi
EOF

k3s_audit_policy_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`
AUDIT_POLICY_FILE="${local.audit_policy_file}"
SERVICE_NAME="${local.control_plane_service_name}"
BACKUP_FILE="/tmp/audit-policy_$DATE.yaml"
HAS_BACKUP=false

if [ -z "${var.k3s_audit_policy_config}" ] || [ "${var.k3s_audit_policy_config}" = " " ]; then
  echo "No audit policy config provided via Terraform, skipping audit policy setup"
  # Note: We intentionally DO NOT remove existing audit policies here.
  # This preserves any manually-configured audit policies for backward compatibility.
  exit 0
fi

# Config is provided, proceed with audit policy setup
if cmp -s /tmp/audit-policy.yaml "$AUDIT_POLICY_FILE"; then
  echo "No update required to the audit-policy.yaml file"
else
  if [ -f "$AUDIT_POLICY_FILE" ]; then
    echo "Backing up $AUDIT_POLICY_FILE to $BACKUP_FILE"
    cp "$AUDIT_POLICY_FILE" "$BACKUP_FILE"
    HAS_BACKUP=true
  fi
  echo "Updated audit-policy.yaml detected, restart of $SERVICE_NAME service required"
  cp /tmp/audit-policy.yaml "$AUDIT_POLICY_FILE"
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    if ! systemctl restart "$SERVICE_NAME"; then
      echo "Error: Failed to restart $SERVICE_NAME"
      if [ "$HAS_BACKUP" = true ]; then
        echo "Restoring $AUDIT_POLICY_FILE from backup $BACKUP_FILE"
        cp "$BACKUP_FILE" "$AUDIT_POLICY_FILE"
        systemctl restart "$SERVICE_NAME" || true
      fi
      exit 1
    fi
  else
    echo "$SERVICE_NAME is not active, skipping restart"
  fi
  echo "$SERVICE_NAME restarted successfully with new audit policy"
fi

# Ensure audit log directory exists with proper permissions
mkdir -p $(dirname ${var.k3s_audit_log_path})
chmod 750 $(dirname ${var.k3s_audit_log_path})
chown root:root $(dirname ${var.k3s_audit_log_path})
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

restart_or_signal_update() {
  local SERVICE_NAME="$1"
  if ${var.k8s_config_updates_use_kured_sentinel}; then
    SENTINEL="${local.kured_reboot_sentinel}"
    mkdir -p "$(dirname "$SENTINEL")"
    touch "$SENTINEL"
    echo "Triggered Kured reboot sentinel at $SENTINEL instead of restarting $SERVICE_NAME"
    return 0
  fi
  systemctl restart "$SERVICE_NAME"
}

if cmp -s /tmp/config.yaml /etc/rancher/rke2/config.yaml; then
  echo "No update required to the config.yaml file"
else
  if [ -f "/etc/rancher/rke2/config.yaml" ]; then
    echo "Backing up /etc/rancher/rke2/config.yaml to /tmp/config_$DATE.yaml"
    cp /etc/rancher/rke2/config.yaml /tmp/config_$DATE.yaml
  fi
  echo "Updated config.yaml detected, restart of rke2-server service required"
  cp /tmp/config.yaml /etc/rancher/rke2/config.yaml
  if [ -s /tmp/encryption-config.yaml ]; then
    cp /tmp/encryption-config.yaml /etc/rancher/rke2/encryption-config.yaml
    chmod 0600 /etc/rancher/rke2/encryption-config.yaml
  fi
  if systemctl is-active --quiet rke2-server; then
    restart_or_signal_update rke2-server || (echo "Error: Failed to restart rke2-server. Restoring /etc/rancher/rke2/config.yaml from backup" && cp /tmp/config_$DATE.yaml /etc/rancher/rke2/config.yaml && restart_or_signal_update rke2-server)
  elif systemctl is-active --quiet rke2-agent; then
    restart_or_signal_update rke2-agent || (echo "Error: Failed to restart rke2-agent. Restoring /etc/rancher/rke2/config.yaml from backup" && cp /tmp/config_$DATE.yaml /etc/rancher/rke2/config.yaml && restart_or_signal_update rke2-agent)
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
k8s_kubelet_config_update_script        = local.kubernetes_distribution == "k3s" ? local.k3s_kubelet_config_update_script : local.rke2_kubelet_config_update_script
k8s_config_update_script                = local.kubernetes_distribution == "k3s" ? local.k3s_config_update_script : local.rke2_config_update_script
k8s_authentication_config_update_script = local.kubernetes_distribution == "k3s" ? local.k3s_authentication_config_update_script : local.rke2_authentication_config_update_script

cloudinit_write_files_common = <<EOT
# Script to rename the private interface to eth1 and unify NetworkManager connection naming
- path: /etc/cloud/rename_interface.sh
  content: |
    #!/bin/bash
    set -euo pipefail
    sleep 8

    myinit() {
      # wait for a bit
      sleep 3

      # Somehow sometimes on private-ip only setups, the
      # interface may already be correctly named, and this
      # block should be skipped.
      if ! ip link show eth1 >/dev/null 2>&1; then
        # Find the private network interface by name, falling back to original logic.
        # The output of 'ip link show' is stored to avoid multiple calls.
        # Use '|| true' to prevent grep from causing script failure when no matches found
        IP_LINK_NO_FLANNEL=$(ip link show | grep -v 'flannel' || true)

        # Try to find an interface with a predictable name, e.g., enp1s0
        # Anchor pattern to second field to avoid false matches
        INTERFACE=$(awk '$2 ~ /^enp[0-9]+s[0-9]+:$/{sub(/:/,"",$2); print $2; exit}' <<< "$IP_LINK_NO_FLANNEL")

        # If no predictable name is found, use original logic as fallback
        if [ -z "$INTERFACE" ]; then
          INTERFACE=$(awk '/^3:/{p=$2} /^2:/{s=$2} END{iface=p?p:s; sub(/:/,"",iface); print iface}' <<< "$IP_LINK_NO_FLANNEL")
        fi

        # Ensure an interface was found
        if [ -z "$INTERFACE" ]; then
          echo "ERROR: Failed to detect network interface for renaming to eth1" >&2
          echo "Available interfaces:" >&2
          echo "$IP_LINK_NO_FLANNEL" >&2
          return 1
        fi

        MAC=$(cat "/sys/class/net/$INTERFACE/address") || return 1

        echo "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"$MAC\", NAME=\"eth1\"" > /etc/udev/rules.d/70-persistent-net.rules

        ip link set "$INTERFACE" down
        ip link set "$INTERFACE" name eth1
        ip link set eth1 up
      fi

      return 0
    }

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

    myrepeat myinit
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
  encoding: base64
  content: ${base64encode(file("${path.module}/templates/kube-hetzner-selinux.te"))}

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

# Create the k3s kubelet config file if needed
%{if var.k3s_kubelet_config != ""}
# Create k3s kubelet config file
- content: ${base64encode(var.k3s_kubelet_config)}
  encoding: base64
  path: /etc/rancher/k3s/kubelet-config.yaml
%{endif}
EOT

cloudinit_runcmd_common = <<EOT
# ensure that /var uses full available disk size, thanks to btrfs this is easy
- [btrfs, 'filesystem', 'resize', 'max', '/var']

# ensure iSCSI daemon is always enabled for storage workloads
- [systemctl, enable, '--now', iscsid]

# SELinux permission for the SSH alternative port
%{if var.ssh_port != 22}
# SELinux permission for the SSH alternative port.
- |
  semanage port -a -t ssh_port_t -p tcp ${var.ssh_port} 2>/dev/null || \
  semanage port -m -t ssh_port_t -p tcp ${var.ssh_port} 2>/dev/null || \
  echo "Port ${var.ssh_port} already configured for SSH"
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
- |
  if [ -f /etc/systemd/journald.conf ]; then
    sed -i 's/#SystemMaxUse=/SystemMaxUse=3G/g' /etc/systemd/journald.conf
    sed -i 's/#MaxRetentionSec=/MaxRetentionSec=1week/g' /etc/systemd/journald.conf
  elif [ -f /usr/lib/systemd/journald.conf ]; then
    mkdir -p /etc/systemd/journald.conf.d/
    printf '%s\n' "[Journal]" "SystemMaxUse=3G" "MaxRetentionSec=1week" > /etc/systemd/journald.conf.d/kube-hetzner.conf
  else
    echo "journald.conf not found, skipping journal size configuration"
  fi

# Reduces the default number of snapshots from 2-10 number limit, to 4 and from 4-10 number limit important, to 2
- |
  if [ -f /etc/snapper/configs/root ]; then
    sed -i 's/NUMBER_LIMIT="2-10"/NUMBER_LIMIT="4"/g' /etc/snapper/configs/root
    sed -i 's/NUMBER_LIMIT_IMPORTANT="4-10"/NUMBER_LIMIT_IMPORTANT="3"/g' /etc/snapper/configs/root
  else
    echo "Snapper config not found, skipping snapshot limit configuration"
  fi

# Allow network interface
- [chmod, '+x', '/etc/cloud/rename_interface.sh']

# Ensure sshd includes config.d directory and restart to apply the new config
- |
  if ! grep -q "^Include /etc/ssh/sshd_config.d/\\*.conf" /etc/ssh/sshd_config 2>/dev/null; then
    echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
  fi
- [systemctl, 'restart', 'sshd']

# Make sure the network is up
- [systemctl, restart, NetworkManager]
- [systemctl, status, NetworkManager]

# Cleanup some logs
- [truncate, '-s', '0', '/var/log/audit/audit.log']

# Create audit log directory for k3s
- [mkdir, '-p', '${dirname(var.k3s_audit_log_path)}']
- [chmod, '750', '${dirname(var.k3s_audit_log_path)}']
- [chown, 'root:root', '${dirname(var.k3s_audit_log_path)}']

# Add logic to truly disable SELinux if disable_selinux = true.
# We'll do it by appending to cloudinit_runcmd_common.
%{if var.disable_selinux}
- [sed, '-i', '-E', 's/^SELINUX=[a-z]+/SELINUX=disabled/', '/etc/selinux/config']
- [setenforce, '0']
%{endif}

EOT

}

# Cross-variable validations that can't be done in variable validation blocks
check "nat_router_requires_control_plane_lb" {
  assert {
    condition     = var.nat_router == null || var.use_control_plane_lb
    error_message = "When nat_router is enabled, use_control_plane_lb must be set to true."
  }
}

check "cluster_and_service_ipv6_cidrs_are_paired" {
  assert {
    condition = (
      (local.cluster_ipv6_cidr_effective == null && local.service_ipv6_cidr_effective == null) ||
      (local.cluster_ipv6_cidr_effective != null && local.service_ipv6_cidr_effective != null)
    )
    error_message = "cluster_ipv6_cidr and service_ipv6_cidr must be set together."
  }
}

check "cluster_and_service_cidr_stacks_are_aligned" {
  assert {
    condition = (
      (local.cluster_ipv4_cidr_effective == null) == (local.service_ipv4_cidr_effective == null) &&
      (local.cluster_ipv6_cidr_effective == null) == (local.service_ipv6_cidr_effective == null) &&
      length(local.cluster_cidrs) > 0
    )
    error_message = "Cluster and service CIDRs must use matching stacks (IPv4, IPv6, or both), and at least one stack must be configured."
  }
}

check "ccm_lb_has_eligible_targets" {
  assert {
    condition     = !(var.exclude_agents_from_external_load_balancers && !local.allow_loadbalancer_target_on_control_plane)
    error_message = "Warning: exclude_agents_from_external_load_balancers=true with allow_scheduling_on_control_plane=false leaves NO eligible targets for CCM-managed LoadBalancer services. Either set allow_scheduling_on_control_plane=true or disable exclude_agents_from_external_load_balancers."
  }
}

check "autoscaler_nodepools_os_consistent" {
  assert {
    condition     = length(distinct(local.autoscaler_nodepools_os)) <= 1
    error_message = "All autoscaler_nodepools must use the same effective OS. Set 'os' explicitly per autoscaler_nodepool (or omit it everywhere) so the module can select a single image set."
  }
}

check "system_upgrade_window_requires_supported_controller_version" {
  assert {
    condition = var.system_upgrade_schedule_window == null ? true : (
      try(provider::semvers::compare(trimprefix(var.sys_upgrade_controller_version, "v"), "0.15.0"), -1) >= 0
    )
    error_message = "system_upgrade_schedule_window requires sys_upgrade_controller_version v0.15.0 or newer."
  }
}

check "cilium_egress_gateway_ha_requires_cilium_egress_gateway" {
  assert {
    condition     = !var.cilium_egress_gateway_ha_enabled || (var.cni_plugin == "cilium" && var.cilium_egress_gateway_enabled)
    error_message = "cilium_egress_gateway_ha_enabled requires cni_plugin=\"cilium\" and cilium_egress_gateway_enabled=true."
  }
}
