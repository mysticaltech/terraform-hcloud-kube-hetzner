locals {
  ssh_public_key             = trimspace(var.ssh_public_key)
  ssh_additional_public_keys = [for key in var.ssh_additional_public_keys : trimspace(key) if trimspace(key) != ""]
  ssh_authorized_keys        = concat([local.ssh_public_key], local.ssh_additional_public_keys)

  # ssh_agent_identity is not set if the private key is passed directly, but if ssh agent is used, the public key tells ssh agent which private key to use.
  # For terraforms provisioner.connection.agent_identity, we need the public key as a string.
  ssh_agent_identity = var.ssh_private_key == null ? local.ssh_public_key : null

  # If passed, a key already registered within hetzner is used.
  # Otherwise, a new one will be created by the module.
  hcloud_ssh_key_id = coalesce(var.hcloud_ssh_key_id, try(tostring(hcloud_ssh_key.k3s[0].id), null))

  # if given as a variable, we want to use the given token. This is needed to restore the cluster
  cluster_token = var.cluster_token == null ? random_password.k3s_token.result : var.cluster_token

  node_transport_tailscale_enabled = var.node_transport_mode == "tailscale"
  tailscale_magicdns_domain        = trim(var.tailscale_node_transport.magicdns_domain != null ? var.tailscale_node_transport.magicdns_domain : "", ".")
  tailscale_use_tailnet_for_terraform = (
    local.node_transport_tailscale_enabled &&
    var.tailscale_node_transport.ssh.use_tailnet_for_terraform
  )
  tailscale_pre_terraform_ssh_enabled = (
    local.tailscale_use_tailnet_for_terraform &&
    contains(["cloud_init", "external"], var.tailscale_node_transport.bootstrap_mode)
  )
  tailscale_remote_exec_bootstrap_enabled = (
    local.node_transport_tailscale_enabled &&
    var.tailscale_node_transport.bootstrap_mode == "remote_exec"
  )
  tailscale_cloud_init_bootstrap_enabled = (
    local.node_transport_tailscale_enabled &&
    var.tailscale_node_transport.bootstrap_mode == "cloud_init"
  )
  tailscale_managed_bootstrap_enabled = (
    local.tailscale_remote_exec_bootstrap_enabled ||
    local.tailscale_cloud_init_bootstrap_enabled
  )
  tailscale_auth_mode                        = var.tailscale_node_transport.auth.mode
  tailscale_oauth_static_auth_parameters     = "?ephemeral=${var.tailscale_node_transport.auth.oauth_static_nodes_ephemeral}&preauthorized=${var.tailscale_node_transport.auth.oauth_preauthorized}"
  tailscale_oauth_autoscaler_auth_parameters = "?ephemeral=${var.tailscale_node_transport.auth.oauth_autoscaler_ephemeral}&preauthorized=${var.tailscale_node_transport.auth.oauth_preauthorized}"
  tailscale_auth_value_control_plane = (
    local.tailscale_auth_mode == "auth_key" ? try(coalesce(var.tailscale_control_plane_auth_key, var.tailscale_auth_key), "") :
    local.tailscale_auth_mode == "oauth_client_secret" ? "${try(coalesce(var.tailscale_oauth_client_secret), "")}${local.tailscale_oauth_static_auth_parameters}" :
    ""
  )
  tailscale_auth_value_agent = (
    local.tailscale_auth_mode == "auth_key" ? try(coalesce(var.tailscale_agent_auth_key, var.tailscale_auth_key), "") :
    local.tailscale_auth_mode == "oauth_client_secret" ? "${try(coalesce(var.tailscale_oauth_client_secret), "")}${local.tailscale_oauth_static_auth_parameters}" :
    ""
  )
  tailscale_auth_value_autoscaler = (
    local.tailscale_auth_mode == "auth_key" ? try(coalesce(var.tailscale_autoscaler_auth_key, var.tailscale_auth_key), "") :
    local.tailscale_auth_mode == "oauth_client_secret" ? "${try(coalesce(var.tailscale_oauth_client_secret), "")}${local.tailscale_oauth_autoscaler_auth_parameters}" :
    ""
  )
  tailscale_auth_flag                    = local.tailscale_auth_mode == "external" ? "" : "--auth-key"
  tailscale_accept_routes                = "true"
  tailscale_advertise_node_private_route = local.node_transport_tailscale_enabled && var.tailscale_node_transport.routing.advertise_node_private_routes ? "true" : "false"
  tailscale_enable_ssh                   = var.tailscale_node_transport.ssh.enable_tailscale_ssh ? "true" : "false"
  tailscale_advertise_additional_routes  = var.tailscale_node_transport.routing.advertise_additional_routes

  kubernetes_distribution        = var.kubernetes_distribution
  secrets_encryption_config_file = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/encryption-config.yaml" : "/etc/rancher/k3s/encryption-config.yaml"
  secrets_encryption_config = var.enable_secrets_encryption ? yamlencode({
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

  # k3s endpoint used for agent registration, respects control_plane_endpoint override
  multinetwork_overlay_enabled        = var.multinetwork_mode == "cilium_public_overlay"
  cross_network_transport_enabled     = local.multinetwork_overlay_enabled || local.node_transport_tailscale_enabled
  multinetwork_transport_ipv4_enabled = contains(["ipv4", "dualstack"], var.multinetwork_transport_ip_family)
  multinetwork_transport_ipv6_enabled = contains(["ipv6", "dualstack"], var.multinetwork_transport_ip_family)
  multinetwork_cilium_peer_source_cidrs = compact(concat(
    local.multinetwork_transport_ipv4_enabled ? var.multinetwork_cilium_peer_ipv4_cidrs : [],
    local.multinetwork_transport_ipv6_enabled ? var.multinetwork_cilium_peer_ipv6_cidrs : []
  ))
  gateway_api_crds_version            = try(provider::semvers::compare(trimprefix(var.cilium_version, "v"), "1.19.0"), 1) >= 0 ? "v1.4.1" : "v1.2.0"
  gateway_api_crds_enabled            = var.cilium_gateway_api_enabled || var.traefik_provider_kubernetes_gateway_enabled
  gateway_api_standard_crd_names      = ["gatewayclasses", "gateways", "httproutes", "referencegrants", "grpcroutes"]
  gateway_api_standard_crds_manifest  = local.gateway_api_crds_enabled ? join("\n---\n", [for name in local.gateway_api_standard_crd_names : data.http.gateway_api_standard_crds[name].response_body]) : ""
  gateway_api_standard_crds_file      = local.gateway_api_crds_enabled ? local.gateway_api_standard_crds_manifest : "# Gateway API CRDs disabled by kube-hetzner\n"
  gateway_api_standard_crds_resources = local.gateway_api_crds_enabled ? ["gateway-api-standard-crds.yaml"] : []
  cilium_routing_mode_effective       = local.cross_network_transport_enabled ? "tunnel" : var.cilium_routing_mode
  cilium_wireguard_effective          = local.multinetwork_overlay_enabled || var.enable_cni_wireguard_encryption
  cilium_mtu_effective                = local.node_transport_tailscale_enabled ? var.tailscale_node_transport.kubernetes.cni_mtu : (local.multinetwork_overlay_enabled ? var.multinetwork_cilium_mtu : (local.use_robot_ccm ? 1350 : 1450))

  control_plane_endpoint_host = var.control_plane_endpoint != null ? one(compact(regexall("^(?:https?://)?(?:.*@)?(?:\\[([a-fA-F0-9:]+)\\]|([^:/?#]+))", var.control_plane_endpoint)[0])) : null
  control_plane_private_host  = var.enable_control_plane_load_balancer ? hcloud_load_balancer_network.control_plane.*.ip[0] : module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
  control_plane_public_host = coalesce(
    local.control_plane_endpoint_host,
    var.enable_control_plane_load_balancer && var.control_plane_load_balancer_enable_public_network && local.multinetwork_transport_ipv4_enabled ? hcloud_load_balancer.control_plane.*.ipv4[0] : null,
    var.enable_control_plane_load_balancer && var.control_plane_load_balancer_enable_public_network && local.multinetwork_transport_ipv6_enabled ? hcloud_load_balancer.control_plane.*.ipv6[0] : null,
    local.multinetwork_transport_ipv4_enabled ? module.control_planes[keys(module.control_planes)[0]].ipv4_address : null,
    local.multinetwork_transport_ipv6_enabled ? module.control_planes[keys(module.control_planes)[0]].ipv6_address : null,
  )
  control_plane_public_host_formatted = local.control_plane_public_host != null && provider::assert::ipv6(local.control_plane_public_host) ? "[${local.control_plane_public_host}]" : local.control_plane_public_host
  control_plane_private_endpoint      = "https://${local.control_plane_private_host}:${var.kubernetes_api_port}"
  control_plane_public_endpoint       = var.control_plane_endpoint != null ? var.control_plane_endpoint : "https://${local.control_plane_public_host_formatted}:${var.kubernetes_api_port}"
  tailscale_first_control_plane_host  = local.node_transport_tailscale_enabled ? "${module.control_planes[keys(module.control_planes)[0]].name}.${local.tailscale_magicdns_domain}" : null
  tailscale_control_plane_join_host   = local.node_transport_tailscale_enabled ? module.control_planes[keys(module.control_planes)[0]].private_ipv4_address : null
  tailscale_k3s_join_endpoint         = local.node_transport_tailscale_enabled ? "https://${local.tailscale_control_plane_join_host}:${var.kubernetes_api_port}" : null
  tailscale_rke2_join_endpoint        = local.node_transport_tailscale_enabled ? "https://${local.tailscale_control_plane_join_host}:9345" : null

  # k3s endpoint used for agent registration.
  k3s_endpoint = local.node_transport_tailscale_enabled ? local.tailscale_k3s_join_endpoint : (local.multinetwork_overlay_enabled ? local.control_plane_public_endpoint : local.control_plane_private_endpoint)

  rke2_private_join_endpoint = "https://${local.control_plane_private_host}:9345"
  rke2_public_join_endpoint = (
    var.control_plane_endpoint != null
    ? "https://${local.control_plane_public_host_formatted}:9345"
    : "https://${local.control_plane_public_host_formatted}:9345"
  )
  rke2_join_endpoint = local.node_transport_tailscale_enabled ? local.tailscale_rke2_join_endpoint : (local.multinetwork_overlay_enabled ? local.rke2_public_join_endpoint : local.rke2_private_join_endpoint)

  ccm_version    = var.hetzner_ccm_version != null ? var.hetzner_ccm_version : jsondecode(data.http.hetzner_ccm_release[0].response_body).tag_name
  csi_version    = length(data.http.hetzner_csi_release) == 0 ? var.hetzner_csi_version : jsondecode(data.http.hetzner_csi_release[0].response_body).tag_name
  kured_version  = length(data.http.kured_release) == 0 ? var.kured_version : jsondecode(data.http.kured_release[0].response_body).tag_name
  calico_version = length(data.http.calico_release) == 0 ? var.calico_version : jsondecode(data.http.calico_release[0].response_body).tag_name

  # Determine kured YAML suffix based on version (>= 1.20.0 uses -combined.yaml, < 1.20.0 uses -dockerhub.yaml)
  kured_yaml_suffix = provider::semvers::compare(local.kured_version, "1.20.0") >= 0 ? "combined" : "dockerhub"

  cilium_ipv4_native_routing_cidr = var.cilium_ipv4_native_routing_cidr != null && trimspace(var.cilium_ipv4_native_routing_cidr) != "" ? var.cilium_ipv4_native_routing_cidr : local.cluster_ipv4_cidr_effective

  # Check if the user has set custom DNS servers.
  has_dns_servers = length(var.dns_servers) > 0

  registries_config_user = trimspace(var.registries_config) == "" ? {} : yamldecode(var.registries_config)
  embedded_registry_mirror_registries = var.embedded_registry_mirror.enabled ? [
    for registry in var.embedded_registry_mirror.registries : registry
  ] : []
  embedded_registry_mirror_mirrors = {
    for registry in local.embedded_registry_mirror_registries : registry => {}
  }
  registries_config_effective_map = var.embedded_registry_mirror.enabled ? merge(
    local.registries_config_user,
    {
      mirrors = merge(
        local.embedded_registry_mirror_mirrors,
        coalesce(try(local.registries_config_user.mirrors, null), {})
      )
    }
  ) : local.registries_config_user
  registries_config_effective = length(keys(local.registries_config_effective_map)) == 0 ? "" : yamlencode(local.registries_config_effective_map)
  embedded_registry_mirror_server_config = var.embedded_registry_mirror.enabled ? {
    "embedded-registry" = true
  } : {}
  disable_default_registry_endpoint_config = var.embedded_registry_mirror.enabled && var.embedded_registry_mirror.disable_default_endpoint ? {
    "disable-default-registry-endpoint" = true
  } : {}

  # Bit size of the "network_ipv4_cidr".
  network_size = 32 - split("/", var.network_ipv4_cidr)[1]

  # Bit size of each subnet
  subnet_size = local.network_size - log(var.subnet_count, 2)

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

  use_robot_ccm = var.enable_robot_ccm && var.robot_user != "" && var.robot_password != ""
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

  additional_kubernetes_install_environment = join("\n",
    [
      for var_name, var_value in var.additional_kubernetes_install_environment :
      "${var_name}=\"${var_value}\""
    ]
  )
  install_additional_kubernetes_environment = <<-EOT
  cat >> /etc/environment <<EOF
  ${local.additional_kubernetes_install_environment}
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

  tailscale_bootstrap_script_template = <<-EOT
  set -euo pipefail

  TS_VERSION='${var.tailscale_node_transport.version}'
  TS_AUTH_MODE='${local.tailscale_auth_mode}'
  TS_AUTH_FLAG='${local.tailscale_auth_flag}'
  TS_AUTH_VALUE_B64='__KH_TAILSCALE_AUTH_VALUE_B64__'
  TS_AUTH_VALUE="$(printf '%s' "$TS_AUTH_VALUE_B64" | base64 -d)"
  TS_HOSTNAME='__KH_TAILSCALE_HOSTNAME__'
  TS_ADVERTISE_TAGS='__KH_TAILSCALE_TAGS__'
  TS_ACCEPT_ROUTES='${local.tailscale_accept_routes}'
  TS_ADVERTISE_ROUTES='__KH_TAILSCALE_ADVERTISE_ROUTES__'
  TS_ADVERTISE_NODE_PRIVATE_ROUTE='__KH_TAILSCALE_ADVERTISE_NODE_PRIVATE_ROUTE__'
  TS_PRIVATE_ROUTE_PROBE='__KH_TAILSCALE_PRIVATE_ROUTE_PROBE__'
  TS_ENABLE_SSH='${local.tailscale_enable_ssh}'
  TS_TMPDIR=""
  TS_AUTH_FILE=""

  cleanup_tailscale_bootstrap() {
    if [ -n "$TS_AUTH_FILE" ]; then
      rm -f "$TS_AUTH_FILE"
    fi
    if [ -n "$TS_TMPDIR" ]; then
      rm -rf "$TS_TMPDIR"
    fi
  }
  trap cleanup_tailscale_bootstrap EXIT

  install_tailscale_static() {
    if command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1; then
      return 0
    fi

    case "$(uname -m)" in
      x86_64|amd64) TS_ARCH="amd64" ;;
      aarch64|arm64) TS_ARCH="arm64" ;;
      *) echo "Unsupported Tailscale architecture: $(uname -m)" >&2; exit 1 ;;
    esac

    if [ "$TS_VERSION" = "latest" ]; then
      TS_URL="https://pkgs.tailscale.com/stable/tailscale_latest_$${TS_ARCH}.tgz"
    else
      TS_URL="https://pkgs.tailscale.com/stable/tailscale_$${TS_VERSION}_$${TS_ARCH}.tgz"
    fi

    TS_TMPDIR="$(mktemp -d)"
    curl -fsSL "$TS_URL" -o "$TS_TMPDIR/tailscale.tgz"
    tar -xzf "$TS_TMPDIR/tailscale.tgz" -C "$TS_TMPDIR"
    TS_DIR="$(find "$TS_TMPDIR" -maxdepth 1 -type d -name 'tailscale_*' | head -n 1)"
    if [ -z "$TS_DIR" ]; then
      echo "Unable to find extracted Tailscale directory" >&2
      exit 1
    fi

    install -m 0755 "$TS_DIR/tailscale" /usr/local/bin/tailscale
    install -m 0755 "$TS_DIR/tailscaled" /usr/local/sbin/tailscaled
    mkdir -p /var/lib/tailscale

    cat >/etc/systemd/system/tailscaled.service <<'EOF'
  [Unit]
  Description=Tailscale node agent
  Documentation=https://tailscale.com/kb/
  Wants=network-online.target
  After=network-online.target

  [Service]
  Type=notify
  ExecStartPre=/sbin/modprobe tun
  ExecStart=/usr/local/sbin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=41641
  ExecStopPost=/usr/local/bin/tailscaled --cleanup
  Restart=on-failure
  RuntimeDirectory=tailscale
  RuntimeDirectoryMode=0755
  StateDirectory=tailscale
  StateDirectoryMode=0700

  [Install]
  WantedBy=multi-user.target
  EOF

    systemctl daemon-reload
    systemctl enable --now tailscaled
  }

  tailscale_is_running() {
    tailscale status --json 2>/dev/null | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'
  }

  install_tailscale_static
  timeout 120 bash -c 'until systemctl is-active --quiet tailscaled; do sleep 2; done'

  if [ "$TS_ADVERTISE_NODE_PRIVATE_ROUTE" = "true" ]; then
    TS_NODE_PRIVATE_IP="$(ip -4 route get "$TS_PRIVATE_ROUTE_PROBE" 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')"
    if [ -z "$TS_NODE_PRIVATE_IP" ]; then
      echo "Unable to discover private IPv4 used to reach $TS_PRIVATE_ROUTE_PROBE for Tailscale route advertisement" >&2
      exit 1
    fi
    TS_NODE_PRIVATE_ROUTE="$TS_NODE_PRIVATE_IP/32"
    if [ -n "$TS_ADVERTISE_ROUTES" ]; then
      TS_ADVERTISE_ROUTES="$TS_NODE_PRIVATE_ROUTE,$TS_ADVERTISE_ROUTES"
    else
      TS_ADVERTISE_ROUTES="$TS_NODE_PRIVATE_ROUTE"
    fi
  fi

  if [ -n "$TS_ADVERTISE_ROUTES" ]; then
    cat >/etc/sysctl.d/99-kube-hetzner-tailscale-router.conf <<'EOF'
  net.ipv4.ip_forward = 1
  net.ipv6.conf.all.forwarding = 1
  EOF
    sysctl --system >/dev/null
  fi

  TS_RUNNING="false"
  if tailscale_is_running; then
    TS_RUNNING="true"
  fi

  if [ "$TS_RUNNING" != "true" ]; then
    if [ "$TS_AUTH_MODE" = "external" ]; then
      echo "Tailscale auth.mode=external but node is not already logged in" >&2
      exit 1
    fi
    if [ -z "$TS_AUTH_VALUE" ]; then
      echo "Missing Tailscale auth value for $TS_AUTH_MODE" >&2
      exit 1
    fi
  fi

  UP_ARGS=(
    "--reset"
    "--hostname=$TS_HOSTNAME"
    "--accept-routes=$TS_ACCEPT_ROUTES"
    "--accept-dns=false"
  )
  if [ "$TS_AUTH_MODE" != "external" ] && [ -n "$TS_AUTH_VALUE" ]; then
    TS_AUTH_FILE="$(mktemp /run/kube-hetzner-tailscale-auth.XXXXXX)"
    chmod 0600 "$TS_AUTH_FILE"
    printf '%s' "$TS_AUTH_VALUE" > "$TS_AUTH_FILE"
    UP_ARGS+=("$TS_AUTH_FLAG=file:$TS_AUTH_FILE")
  fi
  if [ -n "$TS_ADVERTISE_TAGS" ]; then
    UP_ARGS+=("--advertise-tags=$TS_ADVERTISE_TAGS")
  fi
  if [ -n "$TS_ADVERTISE_ROUTES" ]; then
    UP_ARGS+=("--advertise-routes=$TS_ADVERTISE_ROUTES")
    UP_ARGS+=("--snat-subnet-routes=false")
  fi
  if [ "$TS_ENABLE_SSH" = "true" ]; then
    UP_ARGS+=("--ssh")
  fi
  tailscale up "$${UP_ARGS[@]}"

  timeout 180 bash -c 'until tailscale ip -4 >/dev/null 2>&1; do sleep 2; done'
  EOT

  tailscale_bootstrap_script_static_control_plane_by_node = {
    for node_key, _ in local.control_plane_nodes :
    node_key => replace(
      replace(
        replace(
          replace(
            replace(
              replace(local.tailscale_bootstrap_script_template, "__KH_TAILSCALE_TAGS__", join(",", var.tailscale_node_transport.auth.advertise_tags_control_plane)),
              "__KH_TAILSCALE_AUTH_VALUE_B64__",
              base64encode(local.tailscale_auth_value_control_plane)
            ),
            "__KH_TAILSCALE_ADVERTISE_ROUTES__",
            join(",", local.tailscale_advertise_additional_routes)
          ),
          "__KH_TAILSCALE_ADVERTISE_NODE_PRIVATE_ROUTE__",
          local.tailscale_advertise_node_private_route
        ),
        "__KH_TAILSCALE_PRIVATE_ROUTE_PROBE__",
        local.network_gw_ipv4_by_network_id[local.control_plane_primary_network_id_by_node[node_key]]
      ),
      "TS_HOSTNAME='__KH_TAILSCALE_HOSTNAME__'",
      "TS_HOSTNAME=\"$(hostname -s)\""
    )
  }
  tailscale_bootstrap_script_static_agent_by_node = {
    for node_key, _ in local.agent_nodes :
    node_key => replace(
      replace(
        replace(
          replace(
            replace(
              replace(local.tailscale_bootstrap_script_template, "__KH_TAILSCALE_TAGS__", join(",", var.tailscale_node_transport.auth.advertise_tags_agent)),
              "__KH_TAILSCALE_AUTH_VALUE_B64__",
              base64encode(local.tailscale_auth_value_agent)
            ),
            "__KH_TAILSCALE_ADVERTISE_ROUTES__",
            join(",", local.tailscale_advertise_additional_routes)
          ),
          "__KH_TAILSCALE_ADVERTISE_NODE_PRIVATE_ROUTE__",
          local.tailscale_advertise_node_private_route
        ),
        "__KH_TAILSCALE_PRIVATE_ROUTE_PROBE__",
        local.network_gw_ipv4_by_network_id[local.agent_primary_network_id_by_node[node_key]]
      ),
      "TS_HOSTNAME='__KH_TAILSCALE_HOSTNAME__'",
      "TS_HOSTNAME=\"$(hostname -s)\""
    )
  }
  tailscale_bootstrap_script_autoscaler_by_index = {
    for index, nodepool in var.autoscaler_nodepools :
    index => replace(
      replace(
        replace(
          replace(
            replace(
              replace(local.tailscale_bootstrap_script_template, "__KH_TAILSCALE_TAGS__", join(",", var.tailscale_node_transport.auth.advertise_tags_autoscaler)),
              "__KH_TAILSCALE_AUTH_VALUE_B64__",
              base64encode(local.tailscale_auth_value_autoscaler)
            ),
            "__KH_TAILSCALE_ADVERTISE_ROUTES__",
            join(",", local.tailscale_advertise_additional_routes)
          ),
          "__KH_TAILSCALE_ADVERTISE_NODE_PRIVATE_ROUTE__",
          local.tailscale_advertise_node_private_route
        ),
        "__KH_TAILSCALE_PRIVATE_ROUTE_PROBE__",
        local.network_gw_ipv4_by_network_id[coalesce(nodepool.network_id, 0) == 0 ? data.hcloud_network.k3s.id : nodepool.network_id]
      ),
      "TS_HOSTNAME='__KH_TAILSCALE_HOSTNAME__'",
      "TS_HOSTNAME=\"$(curl -fsS --max-time 2 http://169.254.169.254/hetzner/v1/metadata/hostname 2>/dev/null || hostname -s)\""
    )
  }

  private_default_route_repair_script = join("\n", [
    "# Ensure persistent private-network default route (Hetzner DHCP change Aug 11, 2025)",
    "set +e  # Allow idempotent network adjustments",
    "METRIC=30000",
    "if [ -z \"$KH_NETWORK_IPV4_CIDR\" ]; then KH_NETWORK_IPV4_CIDR=\"${var.network_ipv4_cidr}\"; fi",
    "if [ -z \"$KH_NETWORK_GW_IPV4\" ]; then KH_NETWORK_GW_IPV4=\"${local.network_gw_ipv4}\"; fi",
    "",
    "# Determine the private interface dynamically (no hardcoded eth1)",
    "PRIV_IF=$(ip -4 route show \"$KH_NETWORK_IPV4_CIDR\" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}' | head -n 1)",
    "if [ -z \"$PRIV_IF\" ]; then",
    "  ROUTE_LINE=$(ip -4 route get \"$KH_NETWORK_GW_IPV4\" 2>/dev/null)",
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
    "      ROUTE_LINE=$(nmcli -g ipv4.routes connection show \"$NM_CONN\" | tr ',' '\\n' | awk -v gw=\"$KH_NETWORK_GW_IPV4\" '$1==\"0.0.0.0/0\" && $2==gw{print $0; exit}')",
    "      if [ -n \"$ROUTE_LINE\" ]; then",
    "        CUR_ROUTE_METRIC=$(echo \"$ROUTE_LINE\" | awk '{print $3}')",
    "        if [ -z \"$CUR_ROUTE_METRIC\" ] || [ \"$CUR_ROUTE_METRIC\" != \"$METRIC\" ]; then",
    "          nmcli connection modify \"$NM_CONN\" -ipv4.routes \"$ROUTE_LINE\" >/dev/null 2>&1 || true",
    "          if nmcli connection modify \"$NM_CONN\" +ipv4.routes \"0.0.0.0/0 $KH_NETWORK_GW_IPV4 $METRIC\" >/dev/null 2>&1; then",
    "            ROUTE_READY=1",
    "          else",
    "            echo \"Warning: Failed to update default route metric on $PRIV_IF. Node may be affected by Hetzner DHCP changes.\" >&2",
    "          fi",
    "        else",
    "          ROUTE_READY=1",
    "        fi",
    "      else",
    "        if nmcli connection modify \"$NM_CONN\" +ipv4.routes \"0.0.0.0/0 $KH_NETWORK_GW_IPV4 $METRIC\" >/dev/null 2>&1; then",
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
    "  EXISTING_RT=$(ip -4 route show default dev \"$PRIV_IF\" | awk -v gw=\"$KH_NETWORK_GW_IPV4\" '$3==gw{print $0; exit}')",
    "  if [ -n \"$EXISTING_RT\" ]; then",
    "    CUR_RT_METRIC=$(echo \"$EXISTING_RT\" | awk 'match($0,/metric ([0-9]+)/,m){print m[1]}')",
    "    if [ -z \"$CUR_RT_METRIC\" ] || [ \"$CUR_RT_METRIC\" != \"$METRIC\" ]; then",
    "      ip -4 route change default via \"$KH_NETWORK_GW_IPV4\" dev \"$PRIV_IF\" metric $METRIC 2>/dev/null || true",
    "    fi",
    "  else",
    "    ip -4 route add default via \"$KH_NETWORK_GW_IPV4\" dev \"$PRIV_IF\" metric $METRIC 2>/dev/null || true",
    "  fi",
    "else",
    "  echo \"Info: Unable to identify interface that reaches $KH_NETWORK_GW_IPV4; skipping private default route setup.\"",
    "fi",
    "",
    "set -e"
  ])

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
      local.install_additional_kubernetes_environment,
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
    [local.private_default_route_repair_script],
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
      local.install_additional_kubernetes_environment,
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
        "    nmcli con mod \"$CONNECTION\" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes",
        length(local.dns_servers_ipv4) > 0 ? "    nmcli con mod \"$CONNECTION\" ipv4.dns ${join(",", local.dns_servers_ipv4)}" : "",
        length(local.dns_servers_ipv6) > 0 ? "    nmcli con mod \"$CONNECTION\" ipv6.dns ${join(",", local.dns_servers_ipv6)}" : "",
        "  fi",
        "fi"
      ]))
    ] : [],
    local.has_dns_servers ? ["systemctl restart NetworkManager"] : [],
    [local.private_default_route_repair_script],
    # User-defined commands to execute just before installing rke2.
    var.preinstall_exec,
    # Wait for a successful connection to the internet.
    ["timeout 180s /bin/sh -c 'while ! ping -c 1 ${var.address_for_connectivity_test} >/dev/null 2>&1; do echo \"Ready for rke2 installation, waiting for a successful connection to the internet...\"; sleep 5; done; echo Connected'"]
  )

  common_pre_install_k8s_commands = var.kubernetes_distribution == "rke2" ? local.common_pre_install_rke2_commands : local.common_pre_install_k3s_commands

  common_post_install_k3s_commands = concat(var.postinstall_exec, ["restorecon -v /usr/local/bin/k3s"])
  common_post_install_rke2_commands = concat(var.postinstall_exec, [<<-EOT
if command -v restorecon >/dev/null 2>&1; then
  [ -f /usr/local/bin/rke2 ] && restorecon -v /usr/local/bin/rke2 || true
  [ -f /opt/rke2/bin/rke2 ] && restorecon -v /opt/rke2/bin/rke2 || true
  [ -d /var/lib/rancher/rke2 ] && restorecon -RF /var/lib/rancher/rke2 || true
else
  echo "restorecon not available; skipping RKE2 relabel"
fi
EOT
  ])
  common_post_install_k8s_commands = var.kubernetes_distribution == "rke2" ? local.common_post_install_rke2_commands : local.common_post_install_k3s_commands

  kustomization_backup_yaml = yamlencode({
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    resources = concat(
      [
        "kured-base.yaml",
        "system-upgrade-controller.yaml",
        "system-upgrade-controller-crd.yaml"
      ],
      ["hcloud-ccm-helm.yaml"],
      local.gateway_api_standard_crds_resources,
      var.enable_load_balancer_monitoring ? ["load_balancer_monitoring.yaml"] : [],
      var.enable_hetzner_csi ? ["hcloud-csi.yaml"] : [],
      lookup(local.ingress_controller_install_resources, var.ingress_controller, []),
      local.kubernetes_distribution == "k3s" ? lookup(local.cni_install_resources, var.cni_plugin, []) : [],
      var.cni_plugin == "cilium" && var.cilium_egress_gateway_enabled && var.cilium_egress_gateway_ha_enabled ? ["cilium_egress_gateway_ha.yaml"] : [],
      local.kubernetes_distribution == "k3s" && var.cni_plugin == "flannel" ? ["flannel-rbac.yaml"] : [],
      var.enable_longhorn ? ["longhorn.yaml"] : [],
      var.enable_csi_driver_smb ? ["csi-driver-smb.yaml"] : [],
      var.enable_cert_manager || var.enable_rancher ? ["cert_manager.yaml"] : [],
      var.enable_rancher ? ["rancher.yaml"] : [],
      var.rancher_registration_manifest_url != "" ? [var.rancher_registration_manifest_url] : []
    ),
    patches = [
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
    ]
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

  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
    if ! semodule -l 2>/dev/null | awk '{print $1}' | grep -qx "k3s"; then
      echo "ERROR: SELinux is enforcing but k3s module is not loaded"
      exit 1
    fi
  fi
else
  echo "k3s-selinux package or semodule not available; skipping"
fi
EOT
  ]
  apply_rke2_selinux = [<<-EOT
echo "Checking rke2 SELinux policy status..."
if command -v semodule >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; then
  if rpm -q rke2-selinux >/dev/null 2>&1; then
    if [ -f /usr/share/selinux/packages/rke2.pp ]; then
      echo "Applying rke2 SELinux policy..."
      semodule -v -i /usr/share/selinux/packages/rke2.pp || true
    else
      echo "rke2 SELinux policy file not found at /usr/share/selinux/packages/rke2.pp; skipping"
    fi
  else
    echo "rke2-selinux package not installed; skipping policy apply"
  fi

  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
    if ! semodule -l 2>/dev/null | awk '{print $1}' | grep -qx "rke2"; then
      echo "ERROR: SELinux is enforcing but rke2 module is not loaded"
      exit 1
    fi
  fi
else
  echo "rpm or semodule not available; skipping rke2 SELinux policy checks"
fi
EOT
  ]
  swap_node_label = ["node.kubernetes.io/server-swap=enabled"]

  k3s_install_command  = "curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true INSTALL_K3S_SKIP_SELINUX_RPM=true %{if var.k3s_version == ""}INSTALL_K3S_CHANNEL=${var.k3s_channel}%{else}INSTALL_K3S_VERSION=${var.k3s_version}%{endif} INSTALL_K3S_EXEC='%s' sh -"
  rke2_install_command = "curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=${var.rke2_version} INSTALL_RKE2_EXEC='%s' sh -"

  install_k3s_server = concat(
    local.common_pre_install_k3s_commands,
    [format(local.k3s_install_command, "server ${var.control_plane_exec_args}")],
    var.enable_selinux ? local.apply_k3s_selinux : [],
    local.common_post_install_k8s_commands
  )
  install_rke2_server = concat(
    local.common_pre_install_k8s_commands,
    [format(local.rke2_install_command, "server ${var.control_plane_exec_args}")],
    var.enable_selinux ? local.apply_rke2_selinux : [],
    local.common_post_install_k8s_commands
  )

  install_k3s_agent = concat(
    local.common_pre_install_k3s_commands,
    [format(local.k3s_install_command, "agent ${var.agent_exec_args}")],
    var.enable_selinux ? local.apply_k3s_selinux : [],
    local.common_post_install_k3s_commands
  )
  install_rke2_agent = concat(
    local.common_pre_install_k8s_commands,
    [format(local.rke2_install_command, "agent ${var.agent_exec_args}")],
    var.enable_selinux ? local.apply_rke2_selinux : [],
    local.common_post_install_k8s_commands
  )

  install_k8s_server = var.kubernetes_distribution == "rke2" ? local.install_rke2_server : local.install_k3s_server
  install_k8s_agent  = var.kubernetes_distribution == "rke2" ? local.install_rke2_agent : local.install_k3s_agent
  kubectl_cli        = var.kubernetes_distribution == "rke2" ? "/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml" : "kubectl"

  # Used for mapping existing node names back into nodepool names. Matching below
  # handles optional random suffixes via longest-prefix semantics.
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
      name_base = trimprefix(s.name, local.cluster_prefix_for_node_names)

      # Optional: populated after the first apply on this version. Missing labels => treated as unknown.
      os_label = contains(["microos", "leapmicro"], try(s.labels["kube-hetzner/os"], "")) ? try(s.labels["kube-hetzner/os"], null) : null
    }
  ]

  existing_agent_servers_info = [
    for s in data.hcloud_servers.existing_agent_nodes.servers : {
      name_base = trimprefix(s.name, local.cluster_prefix_for_node_names)

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
        floating_ip : nodepool_obj.floating_ip,
        floating_ip_id : nodepool_obj.floating_ip_id,
        append_random_suffix : nodepool_obj.append_random_suffix,
        swap_size : nodepool_obj.swap_size,
        zram_size : nodepool_obj.zram_size,
        index : node_index
        selinux : nodepool_obj.selinux
        os : coalesce(nodepool_obj.os, local.control_plane_nodepool_default_os[nodepool_obj.name])
        os_snapshot_id : nodepool_obj.os_snapshot_id
        placement_group_index : nodepool_obj.placement_group == null ? nodepool_obj.placement_group_index + floor(node_index / 10) : nodepool_obj.placement_group_index,
        placement_group : nodepool_obj.placement_group,
        disable_ipv4 : !nodepool_obj.enable_public_ipv4 || local.use_nat_router,
        disable_ipv6 : !nodepool_obj.enable_public_ipv6 || local.use_nat_router,
        primary_ipv4_id : nodepool_obj.primary_ipv4_id,
        primary_ipv6_id : nodepool_obj.primary_ipv6_id,
        network_id : 0,
        keep_disk : nodepool_obj.keep_disk,
        join_endpoint_type : nodepool_obj.join_endpoint_type,
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
          append_random_suffix : nodepool_obj.append_random_suffix,
          location : nodepool_obj.location,
          floating_ip : nodepool_obj.floating_ip,
          floating_ip_id : nodepool_obj.floating_ip_id,
          labels : concat(local.default_control_plane_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
          hcloud_labels : nodepool_obj.hcloud_labels,
          taints : compact(concat(local.default_control_plane_taints, nodepool_obj.taints)),
          kubelet_args : nodepool_obj.kubelet_args,
          backups : nodepool_obj.backups,
          swap_size : nodepool_obj.swap_size,
          zram_size : nodepool_obj.zram_size,
          selinux : nodepool_obj.selinux,
          os : coalesce(nodepool_obj.os, local.control_plane_nodepool_default_os[nodepool_obj.name]),
          os_snapshot_id : nodepool_obj.os_snapshot_id,
          placement_group_index : nodepool_obj.placement_group_index,
          placement_group : nodepool_obj.placement_group,
          index : floor(tonumber(node_key)),
          disable_ipv4 : !nodepool_obj.enable_public_ipv4 || local.use_nat_router,
          disable_ipv6 : !nodepool_obj.enable_public_ipv6 || local.use_nat_router,
          primary_ipv4_id : nodepool_obj.primary_ipv4_id,
          primary_ipv6_id : nodepool_obj.primary_ipv6_id,
          network_id : 0,
          keep_disk : nodepool_obj.keep_disk,
          join_endpoint_type : nodepool_obj.join_endpoint_type,
          extra_write_files : nodepool_obj.extra_write_files,
          extra_runcmd : nodepool_obj.extra_runcmd,
          attached_volumes : nodepool_obj.attached_volumes,
        },
        { for key, value in node_obj : key => value if value != null },
        {
          labels : concat(local.default_control_plane_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels, coalesce(node_obj.labels, [])),
          hcloud_labels : merge(nodepool_obj.hcloud_labels, coalesce(node_obj.hcloud_labels, {})),
          taints : compact(concat(local.default_control_plane_taints, nodepool_obj.taints, coalesce(node_obj.taints, []))),
          disable_ipv4 : !coalesce(node_obj.enable_public_ipv4, nodepool_obj.enable_public_ipv4) || local.use_nat_router,
          disable_ipv6 : !coalesce(node_obj.enable_public_ipv6, nodepool_obj.enable_public_ipv6) || local.use_nat_router,
          extra_write_files : concat(nodepool_obj.extra_write_files, coalesce(node_obj.extra_write_files, [])),
          extra_runcmd : concat(nodepool_obj.extra_runcmd, coalesce(node_obj.extra_runcmd, [])),
          attached_volumes : concat(nodepool_obj.attached_volumes, coalesce(node_obj.attached_volumes, [])),
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
        floating_ip_type : nodepool_obj.floating_ip_type,
        floating_ip_id : lookup(nodepool_obj, "floating_ip_id", null),
        floating_ip_rdns : lookup(nodepool_obj, "floating_ip_rdns", false),
        location : nodepool_obj.location,
        labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
        hcloud_labels : nodepool_obj.hcloud_labels,
        taints : compact(concat(local.default_agent_taints, nodepool_obj.taints)),
        kubelet_args : nodepool_obj.kubelet_args,
        backups : lookup(nodepool_obj, "backups", false),
        append_random_suffix : nodepool_obj.append_random_suffix,
        swap_size : nodepool_obj.swap_size,
        zram_size : nodepool_obj.zram_size,
        index : node_index
        selinux : nodepool_obj.selinux
        os : coalesce(nodepool_obj.os, local.agent_nodepool_default_os[nodepool_obj.name])
        os_snapshot_id : nodepool_obj.os_snapshot_id
        placement_group_index : nodepool_obj.placement_group == null ? nodepool_obj.placement_group_index + floor(node_index / 10) : nodepool_obj.placement_group_index,
        placement_group : nodepool_obj.placement_group,
        disable_ipv4 : !nodepool_obj.enable_public_ipv4 || local.use_nat_router,
        disable_ipv6 : !nodepool_obj.enable_public_ipv6 || local.use_nat_router,
        primary_ipv4_id : nodepool_obj.primary_ipv4_id,
        primary_ipv6_id : nodepool_obj.primary_ipv6_id,
        network_id : coalesce(nodepool_obj.network_id, 0),
        keep_disk : nodepool_obj.keep_disk,
        join_endpoint_type : nodepool_obj.join_endpoint_type,
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
          floating_ip_type : nodepool_obj.floating_ip_type,
          floating_ip_id : lookup(nodepool_obj, "floating_ip_id", null),
          floating_ip_rdns : lookup(nodepool_obj, "floating_ip_rdns", false),
          location : nodepool_obj.location,
          labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels),
          hcloud_labels : nodepool_obj.hcloud_labels,
          taints : compact(concat(local.default_agent_taints, nodepool_obj.taints)),
          kubelet_args : nodepool_obj.kubelet_args,
          backups : lookup(nodepool_obj, "backups", false),
          append_random_suffix : nodepool_obj.append_random_suffix,
          swap_size : nodepool_obj.swap_size,
          zram_size : nodepool_obj.zram_size,
          selinux : nodepool_obj.selinux,
          os : coalesce(nodepool_obj.os, local.agent_nodepool_default_os[nodepool_obj.name]),
          os_snapshot_id : nodepool_obj.os_snapshot_id,
          placement_group_index : nodepool_obj.placement_group_index,
          placement_group : nodepool_obj.placement_group,
          index : floor(tonumber(node_key)),
          disable_ipv4 : !nodepool_obj.enable_public_ipv4 || local.use_nat_router,
          disable_ipv6 : !nodepool_obj.enable_public_ipv6 || local.use_nat_router,
          primary_ipv4_id : nodepool_obj.primary_ipv4_id,
          primary_ipv6_id : nodepool_obj.primary_ipv6_id,
          network_id : coalesce(nodepool_obj.network_id, 0),
          keep_disk : nodepool_obj.keep_disk,
          join_endpoint_type : nodepool_obj.join_endpoint_type,
          extra_write_files : nodepool_obj.extra_write_files,
          extra_runcmd : nodepool_obj.extra_runcmd,
          attached_volumes : nodepool_obj.attached_volumes,
        },
        { for key, value in node_obj : key => value if value != null },
        {
          labels : concat(local.default_agent_labels, nodepool_obj.swap_size != "" || nodepool_obj.zram_size != "" ? local.swap_node_label : [], nodepool_obj.labels, coalesce(node_obj.labels, [])),
          hcloud_labels : merge(nodepool_obj.hcloud_labels, coalesce(node_obj.hcloud_labels, {})),
          taints : compact(concat(local.default_agent_taints, nodepool_obj.taints, coalesce(node_obj.taints, []))),
          disable_ipv4 : !coalesce(node_obj.enable_public_ipv4, nodepool_obj.enable_public_ipv4) || local.use_nat_router,
          disable_ipv6 : !coalesce(node_obj.enable_public_ipv6, nodepool_obj.enable_public_ipv6) || local.use_nat_router,
          network_id : coalesce(node_obj.network_id, nodepool_obj.network_id, 0),
          extra_write_files : concat(nodepool_obj.extra_write_files, coalesce(node_obj.extra_write_files, [])),
          extra_runcmd : concat(nodepool_obj.extra_runcmd, coalesce(node_obj.extra_runcmd, [])),
          attached_volumes : concat(nodepool_obj.attached_volumes, coalesce(node_obj.attached_volumes, [])),
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
      {
        os           = n.os
        arch         = substr(n.server_type, 0, 3) == "cax" ? "arm" : "x86"
        needs_lookup = try(trimspace(n.os_snapshot_id), "") == ""
      }
    ],
    [
      for n in values(local.agent_nodes) :
      {
        os           = n.os
        arch         = substr(n.server_type, 0, 3) == "cax" ? "arm" : "x86"
        needs_lookup = try(trimspace(n.os_snapshot_id), "") == ""
      }
    ],
    [
      for np in var.autoscaler_nodepools :
      {
        os           = coalesce(np.os, local.default_autoscaler_os)
        arch         = substr(np.server_type, 0, 3) == "cax" ? "arm" : "x86"
        needs_lookup = true
      }
    ],
  )

  os_arch_requirements = {
    microos = {
      arm = anytrue([for p in local.node_os_arch_pairs : p.needs_lookup && p.os == "microos" && p.arch == "arm"])
      x86 = anytrue([for p in local.node_os_arch_pairs : p.needs_lookup && p.os == "microos" && p.arch == "x86"])
    }
    leapmicro = {
      arm = anytrue([for p in local.node_os_arch_pairs : p.needs_lookup && p.os == "leapmicro" && p.arch == "arm"])
      x86 = anytrue([for p in local.node_os_arch_pairs : p.needs_lookup && p.os == "leapmicro" && p.arch == "x86"])
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

  use_existing_network = var.existing_network != null

  use_nat_router = var.nat_router != null

  use_per_nodepool_subnets = var.network_subnet_mode == "per_nodepool"

  control_plane_primary_network_id_by_node = {
    for node_key, node in local.control_plane_nodes :
    node_key => (node.network_id == 0 ? data.hcloud_network.k3s.id : node.network_id)
  }

  agent_primary_network_id_by_node = {
    for node_key, node in local.agent_nodes :
    node_key => (node.network_id == 0 ? data.hcloud_network.k3s.id : node.network_id)
  }

  cluster_primary_network_keys = toset(concat(
    [for _, node in local.control_plane_nodes : node.network_id],
    [for _, node in local.agent_nodes : node.network_id],
  ))

  nodepool_network_refs = merge(
    {
      for node_key, node in local.control_plane_nodes :
      "control-plane:${node_key}" => node.network_id
    },
    {
      for node_key, node in local.agent_nodes :
      "agent:${node_key}" => node.network_id
    },
    {
      for index, nodepool in var.autoscaler_nodepools :
      "autoscaler:${index}" => coalesce(nodepool.network_id, 0)
    }
  )

  network_gw_ipv4_by_network_id = merge(
    { (data.hcloud_network.k3s.id) = cidrhost(data.hcloud_network.k3s.ip_range, 1) },
    [
      for _, network in data.hcloud_network.additional_nodepool_networks :
      { (network.id) = cidrhost(network.ip_range, 1) }
    ]...
  )

  network_ipv4_cidr_by_network_id = merge(
    { (data.hcloud_network.k3s.id) = data.hcloud_network.k3s.ip_range },
    [
      for _, network in data.hcloud_network.additional_nodepool_networks :
      { (network.id) = network.ip_range }
    ]...
  )

  k8s_install_network_env_by_control_plane = {
    for node_key, network_id in local.control_plane_primary_network_id_by_node :
    node_key => [
      "KH_NETWORK_IPV4_CIDR='${local.network_ipv4_cidr_by_network_id[network_id]}'",
      "KH_NETWORK_GW_IPV4='${local.network_gw_ipv4_by_network_id[network_id]}'",
    ]
  }

  k8s_install_network_env_by_agent = {
    for node_key, network_id in local.agent_primary_network_id_by_node :
    node_key => [
      "KH_NETWORK_IPV4_CIDR='${local.network_ipv4_cidr_by_network_id[network_id]}'",
      "KH_NETWORK_GW_IPV4='${local.network_gw_ipv4_by_network_id[network_id]}'",
    ]
  }

  external_agent_network_ids = distinct([
    for _, node in local.agent_nodes :
    node.network_id
    if node.network_id != 0
  ])

  control_plane_effective_extra_network_ids_by_node = {
    for node_key, node in local.control_plane_nodes :
    node_key => distinct([
      for network_id in concat(var.extra_network_ids, local.cross_network_transport_enabled ? [] : local.external_agent_network_ids) :
      network_id
      if network_id != 0 && network_id != node.network_id
    ])
  }

  agent_effective_extra_network_ids_by_node = {
    for node_key, node in local.agent_nodes :
    node_key => distinct([
      for network_id in var.extra_network_ids : network_id
      if network_id != 0 && network_id != node.network_id
    ])
  }

  uses_multi_primary_network = length(local.cluster_primary_network_keys) > 1

  control_plane_total_network_attachments_by_node = {
    for node_key, node in local.control_plane_nodes :
    node_key => 1 + length(local.control_plane_effective_extra_network_ids_by_node[node_key])
  }

  agent_total_network_attachments_by_node = {
    for node_key, node in local.agent_nodes :
    node_key => 1 + length(local.agent_effective_extra_network_ids_by_node[node_key])
  }

  control_plane_effective_join_endpoint_type_by_node = {
    for node_key, node in local.control_plane_nodes :
    node_key => local.multinetwork_overlay_enabled ? "public" : node.join_endpoint_type
  }

  agent_effective_join_endpoint_type_by_node = {
    for node_key, node in local.agent_nodes :
    node_key => local.multinetwork_overlay_enabled ? "public" : node.join_endpoint_type
  }

  autoscaler_effective_join_endpoint_type_by_index = {
    for index, nodepool in var.autoscaler_nodepools :
    index => local.multinetwork_overlay_enabled ? "public" : coalesce(nodepool.join_endpoint_type, "private")
  }

  k3s_agent_join_endpoint_by_node = {
    for node_key, _ in local.agent_nodes :
    node_key => local.node_transport_tailscale_enabled ? local.tailscale_k3s_join_endpoint : (local.agent_effective_join_endpoint_type_by_node[node_key] == "public" ? local.control_plane_public_endpoint : local.control_plane_private_endpoint)
  }

  rke2_agent_join_endpoint_by_node = {
    for node_key, _ in local.agent_nodes :
    node_key => local.node_transport_tailscale_enabled ? local.tailscale_rke2_join_endpoint : (local.agent_effective_join_endpoint_type_by_node[node_key] == "public" ? local.rke2_public_join_endpoint : local.rke2_private_join_endpoint)
  }

  public_join_endpoint_enabled = anytrue(concat(
    [for _, endpoint_type in local.control_plane_effective_join_endpoint_type_by_node : endpoint_type == "public"],
    [for _, endpoint_type in local.agent_effective_join_endpoint_type_by_node : endpoint_type == "public"],
    [for _, endpoint_type in local.autoscaler_effective_join_endpoint_type_by_index : endpoint_type == "public"]
  ))

  public_overlay_outbound_firewall_rules = concat(
    local.public_join_endpoint_enabled ? [
      {
        description     = "Allow Outbound Kubernetes API Requests"
        direction       = "out"
        protocol        = "tcp"
        port            = tostring(var.kubernetes_api_port)
        destination_ips = ["0.0.0.0/0", "::/0"]
      }
    ] : [],
    local.node_transport_tailscale_enabled ? [
      {
        description     = "Allow Outbound Tailscale Direct WireGuard"
        direction       = "out"
        protocol        = "udp"
        port            = "41641"
        destination_ips = ["0.0.0.0/0", "::/0"]
      },
      {
        description     = "Allow Outbound Tailscale STUN"
        direction       = "out"
        protocol        = "udp"
        port            = "3478"
        destination_ips = ["0.0.0.0/0", "::/0"]
      }
    ] : [],
    local.multinetwork_overlay_enabled ? [
      {
        description     = "Allow Outbound Kubelet API for public overlay nodes"
        direction       = "out"
        protocol        = "tcp"
        port            = "10250"
        destination_ips = ["0.0.0.0/0", "::/0"]
      },
      {
        description     = "Allow Outbound Cilium Health for public overlay nodes"
        direction       = "out"
        protocol        = "tcp"
        port            = "4240"
        destination_ips = ["0.0.0.0/0", "::/0"]
      },
      {
        description     = "Allow Outbound Cilium WireGuard public overlay peer traffic"
        direction       = "out"
        protocol        = "udp"
        port            = "51871"
        destination_ips = ["0.0.0.0/0", "::/0"]
      },
      {
        description     = "Allow Outbound Cilium Geneve public overlay peer traffic"
        direction       = "out"
        protocol        = "udp"
        port            = "6081"
        destination_ips = ["0.0.0.0/0", "::/0"]
      }
    ] : []
  )

  restricted_outbound_firewall_rules = flatten([
    [
      {
        description     = "Allow Outbound ICMP Ping Requests"
        direction       = "out"
        protocol        = "icmp"
        port            = ""
        destination_ips = ["0.0.0.0/0", "::/0"]
      },
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
      }
    ],
    local.public_overlay_outbound_firewall_rules,
    [
      {
        description     = "Allow Outbound UDP NTP Requests"
        direction       = "out"
        protocol        = "udp"
        port            = "123"
        destination_ips = ["0.0.0.0/0", "::/0"]
      }
    ]
  ])

  k3s_private_join_host_by_control_plane = {
    for node_key, _ in local.control_plane_nodes :
    node_key => (
      var.enable_control_plane_load_balancer ? local.control_plane_private_host : (
        length(local.control_plane_nodes) <= 1 ? null : (
          module.control_planes[node_key].private_ipv4_address == module.control_planes[keys(module.control_planes)[0]].private_ipv4_address ?
          module.control_planes[keys(module.control_planes)[1]].private_ipv4_address :
          module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
        )
      )
    )
  }

  k3s_control_plane_join_endpoint_by_node = {
    for node_key, _ in local.control_plane_nodes :
    node_key => (
      local.control_plane_effective_join_endpoint_type_by_node[node_key] == "public"
      ? local.control_plane_public_endpoint
      : (
        var.control_plane_endpoint != null
        ? var.control_plane_endpoint
        : (local.k3s_private_join_host_by_control_plane[node_key] == null ? null : "https://${local.k3s_private_join_host_by_control_plane[node_key]}:${var.kubernetes_api_port}")
      )
    )
  }

  rke2_control_plane_join_endpoint_by_node = {
    for node_key, _ in local.control_plane_nodes :
    node_key => local.control_plane_effective_join_endpoint_type_by_node[node_key] == "public" ? local.rke2_public_join_endpoint : local.rke2_private_join_endpoint
  }

  k3s_autoscaler_join_endpoint_by_index = {
    for index, _ in var.autoscaler_nodepools :
    index => local.node_transport_tailscale_enabled ? local.tailscale_k3s_join_endpoint : (local.autoscaler_effective_join_endpoint_type_by_index[index] == "public" ? local.control_plane_public_endpoint : local.control_plane_private_endpoint)
  }

  rke2_autoscaler_join_endpoint_by_index = {
    for index, _ in var.autoscaler_nodepools :
    index => local.node_transport_tailscale_enabled ? local.tailscale_rke2_join_endpoint : (local.autoscaler_effective_join_endpoint_type_by_index[index] == "public" ? local.rke2_public_join_endpoint : local.rke2_private_join_endpoint)
  }

  ssh_bastion = coalesce(
    local.use_nat_router ? {
      bastion_host        = var.use_private_nat_router_bastion ? local.nat_router_ip[0] : hcloud_server.nat_router[0].ipv4_address
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
  network_ipv4_subnets = [for index in range(var.subnet_count) : cidrsubnet(var.network_ipv4_cidr, log(var.subnet_count, 2), index)]

  cluster_ipv4_cidr_effective = var.cluster_ipv4_cidr != null && trimspace(var.cluster_ipv4_cidr) != "" ? var.cluster_ipv4_cidr : null
  service_ipv4_cidr_effective = var.service_ipv4_cidr != null && trimspace(var.service_ipv4_cidr) != "" ? var.service_ipv4_cidr : null
  cluster_ipv6_cidr_effective = var.cluster_ipv6_cidr != null && trimspace(var.cluster_ipv6_cidr) != "" ? var.cluster_ipv6_cidr : null
  service_ipv6_cidr_effective = var.service_ipv6_cidr != null && trimspace(var.service_ipv6_cidr) != "" ? var.service_ipv6_cidr : null
  cluster_has_ipv4            = local.cluster_ipv4_cidr_effective != null
  cluster_has_ipv6            = local.cluster_ipv6_cidr_effective != null

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
  cluster_dns                          = join(",", local.cluster_dns_values)
  ipv4_only_coredns_aaaa_filter_script = <<-EOT
KUBECTL="__KUBECTL__"
for COREDNS_CONFIGMAP in coredns rke2-coredns-rke2-coredns; do
  COREFILE="$($KUBECTL -n kube-system get configmap "$COREDNS_CONFIGMAP" -o jsonpath='{.data.Corefile}' 2>/dev/null || true)"
  if [ -n "$COREFILE" ] && ! printf '%s\n' "$COREFILE" | grep -q 'kube-hetzner-disable-ipv6-dns'; then
    printf '%s\n' "$COREFILE" | awk '
      BEGIN { inserted = 0 }
      /^\.:53[[:space:]]*\{/ && inserted == 0 {
        print
        print "    # kube-hetzner-disable-ipv6-dns"
        print "    template IN AAAA . {"
        print "        rcode NOERROR"
        print "    }"
        inserted = 1
        next
      }
      { print }
    ' > /tmp/kube-hetzner-Corefile
    $KUBECTL -n kube-system create configmap "$COREDNS_CONFIGMAP" --from-file=Corefile=/tmp/kube-hetzner-Corefile --dry-run=client -o yaml | $KUBECTL apply -f -
    $KUBECTL -n kube-system rollout restart "deployment/$COREDNS_CONFIGMAP" >/dev/null 2>&1 || true
  fi
done
EOT

  legacy_hetzner_ccm_cleanup_script = <<-EOT
KUBECTL="__KUBECTL__"

delete_legacy_ccm_resource() {
  resource="$1"
  name="$2"
  namespace="$${3:-}"

  if [ -n "$namespace" ]; then
    managed_by="$($KUBECTL -n "$namespace" get "$resource/$name" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || true)"
  else
    managed_by="$($KUBECTL get "$resource/$name" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || true)"
  fi

  if [ "$managed_by" = "Helm" ]; then
    echo "Keeping Helm-managed $resource/$name"
    return 0
  fi

  if [ -n "$namespace" ]; then
    $KUBECTL -n "$namespace" delete "$resource/$name" --ignore-not-found
  else
    $KUBECTL delete "$resource/$name" --ignore-not-found
  fi
}

delete_legacy_ccm_resource serviceaccount hcloud-cloud-controller-manager kube-system
delete_legacy_ccm_resource deployment hcloud-cloud-controller-manager kube-system
delete_legacy_ccm_resource clusterrole system:hcloud-cloud-controller-manager
delete_legacy_ccm_resource clusterrolebinding system:hcloud-cloud-controller-manager
delete_legacy_ccm_resource clusterrolebinding system:hcloud-cloud-controller-manager:restricted
EOT

  post_install_readiness_wait_script = <<-EOT
KUBECTL="__KUBECTL__"

wait_namespace_deployments() {
  ns="$1"
  timeout_seconds="$2"

  $KUBECTL get ns "$ns" >/dev/null 2>&1 || return 0

  deployments="$($KUBECTL -n "$ns" get deployment -o name 2>/dev/null || true)"
  if [ -z "$deployments" ]; then
    return 0
  fi

  printf '%s\n' "$deployments" | xargs $KUBECTL -n "$ns" wait --for=condition=Available --timeout="$${timeout_seconds}s"
}

wait_namespace_jobs() {
  ns="$1"
  timeout_seconds="$2"

  $KUBECTL get ns "$ns" >/dev/null 2>&1 || return 0

  jobs="$($KUBECTL -n "$ns" get job -o name 2>/dev/null || true)"
  if [ -z "$jobs" ]; then
    return 0
  fi

  printf '%s\n' "$jobs" | xargs $KUBECTL -n "$ns" wait --for=condition=Complete --timeout="$${timeout_seconds}s"
}

for ns in kube-system ${var.enable_cert_manager ? "cert-manager" : ""} ${var.enable_longhorn ? var.longhorn_namespace : ""}; do
  [ -n "$ns" ] && wait_namespace_jobs "$ns" 900
done

for ns in kube-system ${var.enable_cert_manager ? "cert-manager" : ""} ${var.enable_longhorn ? var.longhorn_namespace : ""} ${local.ingress_controller_namespace} system-upgrade; do
  [ -n "$ns" ] && wait_namespace_deployments "$ns" 600
done

for ns in kube-system ${var.enable_cert_manager ? "cert-manager" : ""} ${var.enable_longhorn ? var.longhorn_namespace : ""}; do
  [ -n "$ns" ] && wait_namespace_jobs "$ns" 300
done
EOT

  hetzner_ccm_networking_enabled       = local.cluster_has_ipv4 && !local.cross_network_transport_enabled
  hetzner_ccm_route_cluster_cidr       = local.cluster_ipv4_cidr_effective != null ? local.cluster_ipv4_cidr_effective : ""
  hetzner_ccm_instances_address_family = local.cluster_has_ipv6 ? (local.cluster_has_ipv4 ? "dualstack" : "ipv6") : "ipv4"

  # Keep the legacy single-network value available for templates that still
  # assume one primary network.
  network_gw_ipv4 = local.network_gw_ipv4_by_network_id[data.hcloud_network.k3s.id]

  # if we are in a single cluster config, we use the default klipper lb instead of Hetzner LB
  control_plane_count    = length(var.control_plane_nodepools) > 0 ? sum([for v in var.control_plane_nodepools : length(coalesce(v.nodes, {})) + coalesce(v.count, 0)]) : 0
  agent_count            = length(var.agent_nodepools) > 0 ? sum([for v in var.agent_nodepools : length(coalesce(v.nodes, {})) + coalesce(v.count, 0)]) : 0
  autoscaler_max_count   = length(var.autoscaler_nodepools) > 0 ? sum([for v in var.autoscaler_nodepools : v.max_nodes]) : 0
  is_single_node_cluster = (local.control_plane_count + local.agent_count + local.autoscaler_max_count) == 1

  using_klipper_lb = var.enable_klipper_metal_lb || local.is_single_node_cluster

  has_external_load_balancer_base = local.using_klipper_lb || var.ingress_controller == "none"
  combine_load_balancers_effective = (
    var.reuse_control_plane_load_balancer &&
    var.enable_control_plane_load_balancer &&
    !local.has_external_load_balancer_base
  )
  has_external_load_balancer = local.has_external_load_balancer_base || local.combine_load_balancers_effective
  skip_ingress_lb_wait       = local.has_external_load_balancer_base || var.ingress_controller == "custom"
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
    "nginx"   = "nginx"
    "haproxy" = "haproxy"
  }

  ingress_controller_namespace = var.ingress_target_namespace != "" ? var.ingress_target_namespace : (
    var.ingress_controller_use_system_namespace ? "kube-system" : lookup(local.default_ingress_namespace_mapping, var.ingress_controller, "")
  )
  ingress_replica_count     = (var.ingress_replica_count > 0) ? var.ingress_replica_count : (local.agent_count > 2) ? 3 : (local.agent_count == 2) ? 2 : 1
  ingress_max_replica_count = (var.ingress_max_replica_count > local.ingress_replica_count) ? var.ingress_max_replica_count : local.ingress_replica_count

  # Disable distribution-bundled addons that kube-hetzner replaces or manages.
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
    var.automatically_upgrade_kubernetes ? [local.upgrade_label] : []
  )
  default_control_plane_labels = concat(local.allow_loadbalancer_target_on_control_plane ? [] : ["node.kubernetes.io/exclude-from-external-load-balancers=true"], var.automatically_upgrade_kubernetes ? [local.upgrade_label] : [])
  default_autoscaler_labels    = concat([], var.automatically_upgrade_kubernetes ? [local.upgrade_label] : [])

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
        port        = tostring(var.kubernetes_api_port)
        source_ips  = var.firewall_kube_api_source
      }
    ],
    length(var.cluster_autoscaler_metrics_firewall_source) == 0 || length(var.autoscaler_nodepools) == 0 ? [] : [
      for metrics_node_port in local.cluster_autoscaler_metrics_node_ports :
      {
        description = "Allow Incoming Requests to Cluster Autoscaler Metrics NodePort"
        direction   = "in"
        protocol    = "tcp"
        port        = tostring(metrics_node_port)
        source_ips  = var.cluster_autoscaler_metrics_firewall_source
      }
    ],
    local.node_transport_tailscale_enabled ? [
      {
        description = "Allow Incoming Tailscale Direct WireGuard"
        direction   = "in"
        protocol    = "udp"
        port        = "41641"
        source_ips  = ["0.0.0.0/0", "::/0"]
      }
    ] : [],
    local.multinetwork_overlay_enabled ? [
      {
        description = "Allow Cilium WireGuard public overlay peer traffic"
        direction   = "in"
        protocol    = "udp"
        port        = "51871"
        source_ips  = local.multinetwork_cilium_peer_source_cidrs
      },
      {
        description = "Allow Cilium Geneve public overlay peer traffic"
        direction   = "in"
        protocol    = "udp"
        port        = "6081"
        source_ips  = local.multinetwork_cilium_peer_source_cidrs
      },
      {
        description = "Allow Kubelet API for public overlay nodes"
        direction   = "in"
        protocol    = "tcp"
        port        = "10250"
        source_ips  = local.multinetwork_cilium_peer_source_cidrs
      },
      {
        description = "Allow Cilium Health for public overlay nodes"
        direction   = "in"
        protocol    = "tcp"
        port        = "4240"
        source_ips  = local.multinetwork_cilium_peer_source_cidrs
      }
    ] : [],
    !var.restrict_outbound_traffic ? [] : local.restricted_outbound_firewall_rules,
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
    var.allow_inbound_icmp ? [
      {
        description = "Allow Incoming ICMP Ping Requests"
        direction   = "in"
        protocol    = "icmp"
        port        = ""
        source_ips  = ["0.0.0.0/0", "::/0"]
      }
    ] : []
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

  prefer_bundled_bin_config = var.prefer_bundled_bin ? { "prefer-bundled-bin" = true } : {}

  cni_k3s_settings = {
    "flannel" = {
      disable-network-policy = !var.enable_network_policy
      flannel-backend        = var.flannel_backend != null ? var.flannel_backend : (var.enable_cni_wireguard_encryption ? "wireguard-native" : "vxlan")
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

  etcd_s3_snapshots = length(keys(var.etcd_s3_backup)) > 0 ? merge(
    {
      "etcd-s3" = true
    },
  var.etcd_s3_backup) : {}

  registries_config_file      = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/registries.yaml" : "/etc/rancher/k3s/registries.yaml"
  kubelet_config_file         = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/kubelet-config.yaml" : "/etc/rancher/k3s/kubelet-config.yaml"
  kubelet_arg                 = concat(["cloud-provider=external", "volume-plugin-dir=/var/lib/kubelet/volumeplugins"], var.kubelet_config != "" ? ["config=${local.kubelet_config_file}"] : [])
  kube_controller_manager_arg = "flex-volume-plugin-dir=/var/lib/kubelet/volumeplugins"
  flannel_iface               = "eth1"
  authentication_config_file  = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/authentication_config.yaml" : "/etc/rancher/k3s/authentication_config.yaml"
  audit_policy_file           = local.kubernetes_distribution == "rke2" ? "/etc/rancher/rke2/audit-policy.yaml" : "/etc/rancher/k3s/audit-policy.yaml"
  control_plane_service_name  = local.kubernetes_distribution == "rke2" ? "rke2-server" : "k3s"
  agent_service_name          = local.kubernetes_distribution == "rke2" ? "rke2-agent" : "k3s-agent"

  kube_apiserver_arg = concat(
    var.authentication_config != "" ? ["authentication-config=${local.authentication_config_file}"] : [],
    var.audit_policy_config != "" ? [
      "audit-policy-file=${local.audit_policy_file}",
      "audit-log-path=${var.audit_log_path}",
      "audit-log-maxage=${var.audit_log_max_age}",
      "audit-log-maxbackup=${var.audit_log_max_backups}",
      "audit-log-maxsize=${var.audit_log_max_size}"
    ] : []
  )

  cilium_values_default = <<EOT
# Enable Kubernetes host-scope IPAM mode (required for K3s + Hetzner CCM)
ipam:
  mode: kubernetes
k8s:
%{if local.cluster_has_ipv4~}
  requireIPv4PodCIDR: true
%{endif~}
%{if local.cluster_has_ipv6~}
  requireIPv6PodCIDR: true
%{endif~}

ipv4:
  enabled: ${local.cluster_has_ipv4}
ipv6:
  enabled: ${local.cluster_has_ipv6}

# Replace kube-proxy with Cilium only when kube-proxy is disabled in k3s/rke2.
kubeProxyReplacement: ${!var.enable_kube_proxy}

%{if !var.enable_kube_proxy}
# Enable health check server (healthz) for the kube-proxy replacement
kubeProxyReplacementHealthzBindAddr: "0.0.0.0:10256"
%{endif~}

# Access to Kube API Server (mandatory if kube-proxy is disabled)
k8sServiceHost: "127.0.0.1"
k8sServicePort: "${local.kubernetes_distribution == "rke2" ? tostring(var.kubernetes_api_port) : "6444"}"

  # Set Tunnel Mode or Native Routing Mode. Cross-network transports force tunnel mode.
  routingMode: "${local.cilium_routing_mode_effective}"
%{if local.cilium_routing_mode_effective == "native"~}
%{if local.cluster_has_ipv4~}
# Set the native routable CIDR
ipv4NativeRoutingCIDR: "${local.cilium_ipv4_native_routing_cidr}"
%{endif~}
%{if local.cluster_has_ipv6~}
ipv6NativeRoutingCIDR: "${local.cluster_ipv6_cidr_effective}"
%{endif~}

# Bypass iptables Connection Tracking for Pod traffic (only works in Native Routing Mode)
installNoConntrackIptablesRules: true
%{endif~}
%{if local.cilium_routing_mode_effective == "tunnel" && local.cilium_wireguard_effective}
tunnelProtocol: "geneve"
%{endif~}
%{if local.multinetwork_overlay_enabled}
nodePort:
  addresses:
%{if local.multinetwork_transport_ipv4_enabled~}
    - "0.0.0.0/0"
%{endif~}
%{if local.multinetwork_transport_ipv6_enabled~}
    - "::/0"
%{endif~}
%{endif~}

# Perform a gradual roll out on config update.
rollOutCiliumPods: true

endpointRoutes:
  # Enable use of per endpoint routes instead of routing via the cilium_host interface.
  enabled: true

loadBalancer:
  # Enable LoadBalancer & NodePort XDP Acceleration (direct routing (routingMode=native) is recommended to achieve optimal performance)
  acceleration: "${var.cilium_load_balancer_acceleration_mode}"

bpf:
  # Cilium's eBPF masquerading depends on Cilium's BPF NodePort datapath.
  # Keep it off when kube-proxy owns NodePort to avoid Cilium startup failures.
  masquerade: ${!var.enable_kube_proxy}
%{if local.cilium_wireguard_effective}
encryption:
  enabled: true
  # Enable node encryption for node-to-node traffic
  nodeEncryption: true
  type: wireguard
%{endif~}
%{if var.cilium_gateway_api_enabled}
gatewayAPI:
  enabled: true
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


MTU: ${local.cilium_mtu_effective}
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
              value: "${var.enable_cni_wireguard_encryption}"

  EOT

  desired_cni_values  = var.cni_plugin == "cilium" ? local.cilium_values : local.calico_values
  desired_cni_version = var.cni_plugin == "cilium" ? var.cilium_version : var.calico_version
  # RKE2 supports built-in CNI selections. We only inject a custom manifest for cilium.
  rke2_cni = (
    var.cni_plugin == "cilium"
    ? "none"
    : (var.cni_plugin == "calico" ? "calico" : "canal")
  )
  rke2_manifest_cni_plugin = var.cni_plugin == "cilium" ? "cilium" : "rke2-noop"

  rke2_cni_config_manifest = (
    local.kubernetes_distribution == "rke2" && var.cni_plugin == "flannel"
    ? <<-EOT
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-canal
  namespace: kube-system
spec:
  valuesContent: |-
    flannel:
      iface: "${local.flannel_iface}"
EOT
    : <<-EOT
# kube-hetzner: no bundled RKE2 CNI HelmChartConfig is required for ${var.cni_plugin}.
EOT
  )

  longhorn_values_default = <<EOT
defaultSettings:
%{if length(var.autoscaler_nodepools) != 0~}
  kubernetesClusterAutoscalerEnabled: true
%{endif~}
  defaultDataPath: /var/longhorn
persistence:
  defaultFsType: ${var.longhorn_fstype}
  defaultClassReplicaCount: ${var.longhorn_replica_count}
  %{if !var.enable_hetzner_csi~}defaultClass: true%{else~}defaultClass: false%{endif~}
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
%{if local.combine_load_balancers_effective~}
      "load-balancer.hetzner.cloud/id": "${hcloud_load_balancer.control_plane.*.id[0]}"
%{else~}
      "load-balancer.hetzner.cloud/name": "${local.load_balancer_name}"
%{endif~}
      "load-balancer.hetzner.cloud/use-private-ip": "${!local.cross_network_transport_enabled}"
      "load-balancer.hetzner.cloud/disable-private-ingress": "true"
      "load-balancer.hetzner.cloud/disable-public-network": "${!var.load_balancer_enable_public_network}"
      "load-balancer.hetzner.cloud/ipv6-disabled": "${!var.load_balancer_enable_ipv6}"
      "load-balancer.hetzner.cloud/location": "${var.load_balancer_location}"
      "load-balancer.hetzner.cloud/type": "${var.load_balancer_type}"
      "load-balancer.hetzner.cloud/uses-proxyprotocol": "${!local.using_klipper_lb}"
      "load-balancer.hetzner.cloud/algorithm-type": "${var.load_balancer_algorithm_type}"
      "load-balancer.hetzner.cloud/health-check-interval": "${var.load_balancer_health_check_interval}"
      "load-balancer.hetzner.cloud/health-check-timeout": "${var.load_balancer_health_check_timeout}"
      "load-balancer.hetzner.cloud/health-check-retries": "${var.load_balancer_health_check_retries}"
%{if var.load_balancer_hostname != ""~}
      "load-balancer.hetzner.cloud/hostname": "${var.load_balancer_hostname}"
%{endif~}
%{endif~}
  EOT

  nginx_values = module.values_merger_nginx.values

  hetzner_ccm_values_default = <<EOT
networking:
  enabled: ${local.hetzner_ccm_networking_enabled}
%{if local.hetzner_ccm_networking_enabled~}
  clusterCIDR: "${local.hetzner_ccm_route_cluster_cidr}"
%{endif~}
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
    value: "${!local.cross_network_transport_enabled}"
  HCLOUD_LOAD_BALANCERS_ENABLED:
    value: "${!local.using_klipper_lb}"
  HCLOUD_LOAD_BALANCERS_DISABLE_PRIVATE_INGRESS:
    value: "true"
%{if local.use_robot_ccm || local.cross_network_transport_enabled~}
  HCLOUD_NETWORK_ROUTES_ENABLED:
    value: "false"
%{endif~}
%{if local.hetzner_ccm_instances_address_family != "ipv4"~}
  HCLOUD_INSTANCES_ADDRESS_FAMILY:
    value: "${local.hetzner_ccm_instances_address_family}"
%{endif~}
# Use host network to avoid circular dependency with CNI
hostNetwork: true
%{if local.cross_network_transport_enabled~}

# In public-overlay preview mode, external-network agents are not attached to
# the primary Hetzner Network. Pin CCM to control planes so its HCLOUD_NETWORK
# initialization sees the primary Network and can remove cloud taints.
nodeSelector:
  node-role.kubernetes.io/control-plane: "true"
%{endif~}

# The chart hardcodes base tolerations in its template and uses
# additionalTolerations for extras. The defaults miss not-ready:NoSchedule
# and cilium agent-not-ready, creating a bootstrap deadlock on fresh clusters
# where nodes are NotReady (no CNI) and Cilium hasn't started.
additionalTolerations:
  - key: "node.kubernetes.io/not-ready"
    effect: "NoSchedule"
  - key: "node.cilium.io/agent-not-ready"
    effect: "NoSchedule"
  - key: "node.cilium.io/agent-not-ready"
    effect: "NoExecute"
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
%{if local.combine_load_balancers_effective~}
      "load-balancer.hetzner.cloud/id": "${hcloud_load_balancer.control_plane.*.id[0]}"
%{else~}
      "load-balancer.hetzner.cloud/name": "${local.load_balancer_name}"
%{endif~}
      "load-balancer.hetzner.cloud/use-private-ip": "${!local.cross_network_transport_enabled}"
      "load-balancer.hetzner.cloud/disable-private-ingress": "true"
      "load-balancer.hetzner.cloud/disable-public-network": "${!var.load_balancer_enable_public_network}"
      "load-balancer.hetzner.cloud/ipv6-disabled": "${!var.load_balancer_enable_ipv6}"
      "load-balancer.hetzner.cloud/location": "${var.load_balancer_location}"
      "load-balancer.hetzner.cloud/type": "${var.load_balancer_type}"
      "load-balancer.hetzner.cloud/uses-proxyprotocol": "${!local.using_klipper_lb}"
      "load-balancer.hetzner.cloud/algorithm-type": "${var.load_balancer_algorithm_type}"
      "load-balancer.hetzner.cloud/health-check-interval": "${var.load_balancer_health_check_interval}"
      "load-balancer.hetzner.cloud/health-check-timeout": "${var.load_balancer_health_check_timeout}"
      "load-balancer.hetzner.cloud/health-check-retries": "${var.load_balancer_health_check_retries}"
%{if var.load_balancer_hostname != ""~}
      "load-balancer.hetzner.cloud/hostname": "${var.load_balancer_hostname}"
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
%{if local.combine_load_balancers_effective~}
    "load-balancer.hetzner.cloud/id": "${hcloud_load_balancer.control_plane.*.id[0]}"
%{else~}
    "load-balancer.hetzner.cloud/name": "${local.load_balancer_name}"
%{endif~}
    "load-balancer.hetzner.cloud/use-private-ip": "${!local.cross_network_transport_enabled}"
    "load-balancer.hetzner.cloud/disable-private-ingress": "true"
    "load-balancer.hetzner.cloud/disable-public-network": "${!var.load_balancer_enable_public_network}"
    "load-balancer.hetzner.cloud/ipv6-disabled": "${!var.load_balancer_enable_ipv6}"
    "load-balancer.hetzner.cloud/location": "${var.load_balancer_location}"
    "load-balancer.hetzner.cloud/type": "${var.load_balancer_type}"
    "load-balancer.hetzner.cloud/uses-proxyprotocol": "${!local.using_klipper_lb}"
    "load-balancer.hetzner.cloud/algorithm-type": "${var.load_balancer_algorithm_type}"
    "load-balancer.hetzner.cloud/health-check-interval": "${var.load_balancer_health_check_interval}"
    "load-balancer.hetzner.cloud/health-check-timeout": "${var.load_balancer_health_check_timeout}"
    "load-balancer.hetzner.cloud/health-check-retries": "${var.load_balancer_health_check_retries}"
%{if var.load_balancer_hostname != ""~}
    "load-balancer.hetzner.cloud/hostname": "${var.load_balancer_hostname}"
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
hostname: "${var.rancher_hostname != "" ? var.rancher_hostname : var.load_balancer_hostname}"
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
%{if local.gateway_api_crds_enabled~}
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
mkdir -p /etc/rancher/k3s
if cmp -s /tmp/registries.yaml /etc/rancher/k3s/registries.yaml; then
  echo "No update required to the registries.yaml file"
else
  if [ -f /etc/rancher/k3s/registries.yaml ]; then
    echo "Backing up /etc/rancher/k3s/registries.yaml to /tmp/registries_$DATE.yaml"
    cp /etc/rancher/k3s/registries.yaml /tmp/registries_$DATE.yaml
  fi
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
mkdir -p /etc/rancher/k3s

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
mkdir -p /etc/rancher/rke2

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
mkdir -p /etc/rancher/k3s

restart_or_signal_update() {
  local SERVICE_NAME="$1"
  if ${var.kubernetes_config_updates_use_kured_sentinel}; then
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
mkdir -p "$(dirname "$AUDIT_POLICY_FILE")"

if [ -z "${var.audit_policy_config}" ] || [ "${var.audit_policy_config}" = " " ]; then
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
mkdir -p $(dirname ${var.audit_log_path})
chmod 750 $(dirname ${var.audit_log_path})
chown root:root $(dirname ${var.audit_log_path})
EOF

bootstrap_control_plane_api_config_script = <<EOF
if [ -s /tmp/authentication_config.yaml ]; then
  install -D -m 0600 /tmp/authentication_config.yaml "${local.authentication_config_file}"
fi

if [ -s /tmp/audit-policy.yaml ]; then
  install -D -m 0600 /tmp/audit-policy.yaml "${local.audit_policy_file}"
  mkdir -p "$(dirname "${var.audit_log_path}")"
  chmod 750 "$(dirname "${var.audit_log_path}")"
  chown root:root "$(dirname "${var.audit_log_path}")"
fi
EOF

k3s_authentication_config_update_script = <<EOF
DATE=`date +%Y-%m-%d_%H-%M-%S`
mkdir -p "$(dirname "${local.authentication_config_file}")"
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
mkdir -p /etc/rancher/rke2
if cmp -s /tmp/registries.yaml /etc/rancher/rke2/registries.yaml; then
  echo "No update required to the registries.yaml file"
else
  if [ -f /etc/rancher/rke2/registries.yaml ]; then
    echo "Backing up /etc/rancher/rke2/registries.yaml to /tmp/registries_$DATE.yaml"
    cp /etc/rancher/rke2/registries.yaml /tmp/registries_$DATE.yaml
  fi
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
mkdir -p /etc/rancher/rke2

restart_or_signal_update() {
  local SERVICE_NAME="$1"
  if ${var.kubernetes_config_updates_use_kured_sentinel}; then
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
mkdir -p /etc/rancher/rke2
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
# Keep NetworkManager away from CNI-owned interfaces. RKE2 explicitly
# recommends this for Canal/Calico/Flannel interfaces, and it is harmless for
# k3s clusters using the same interface families.
- path: /etc/NetworkManager/conf.d/kube-hetzner-cni.conf
  content: |
    [keyfile]
    unmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali;interface-name:cilium*;interface-name:lxc*;interface-name:veth*
  permissions: "0644"

# Script to rename the private interface to eth1 and unify NetworkManager connection naming
- path: /etc/cloud/rename_interface.sh
  content: |
    #!/bin/bash
    set -euo pipefail
    sleep 8

    myinit() {
      # wait for a bit
      sleep 3

      # Somehow sometimes on private-ip only setups, the interface may already
      # be correctly named. Still refresh the udev rule so a stale MAC doesn't
      # break the next boot.
      if ip link show eth1 >/dev/null 2>&1; then
        MAC=$(cat /sys/class/net/eth1/address) || return 1
        echo "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"$MAC\", NAME=\"eth1\"" > /etc/udev/rules.d/70-persistent-net.rules
      else
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

# Lightweight wrapper invoked on every boot by kh-rename-interface.service.
# Fast-paths the common case (eth1 already present and the udev rule's MAC
# matches the current MAC) so subsequent boots pay no measurable cost. Only
# when the rule is stale (e.g. Hetzner reassigned the private NIC's MAC) do
# we fall through to the full rename_interface.sh — which handles detection,
# udev rule rewrite, and NetworkManager restart.
- path: /etc/cloud/rename_interface_boot.sh
  content: |
    #!/bin/bash
    set -eu

    UDEV_RULE=/etc/udev/rules.d/70-persistent-net.rules

    if ip link show eth1 >/dev/null 2>&1; then
      MAC=$(cat /sys/class/net/eth1/address)
      if [ -r "$UDEV_RULE" ] && grep -q "ATTR{address}==\"$MAC\"" "$UDEV_RULE"; then
        exit 0
      fi
    fi

    exec /etc/cloud/rename_interface.sh
  permissions: "0744"

# Systemd oneshot that self-heals the eth1 rename on every boot. The cloud-init
# run above only fires at first boot and freezes the current NIC MAC into
# /etc/udev/rules.d/70-persistent-net.rules. If Hetzner later reassigns that
# MAC (NIC detach/reattach, network reconfig, MicroOS transactional-update
# wiping the overlay, etc.) the udev rule no longer matches, eth1 never
# appears, and k3s/rke2 fails with `unable to find interface eth1`.
#
# Ordered After=NetworkManager.service because rename_interface.sh uses
# `nmcli` and restarts NetworkManager — running Before= would deadlock the
# boot. Ordered Before=k3s/rke2 so the rename (when needed) completes before
# the kubernetes services try to bind flannel-iface=eth1.
- path: /etc/systemd/system/kh-rename-interface.service
  content: |
    [Unit]
    Description=Ensure Hetzner private NIC is renamed to eth1
    After=systemd-udev-settle.service NetworkManager.service
    Before=k3s.service k3s-agent.service rke2-server.service rke2-agent.service
    ConditionPathExists=/etc/cloud/rename_interface_boot.sh

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/etc/cloud/rename_interface_boot.sh

    [Install]
    WantedBy=multi-user.target
  permissions: "0644"

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

# Create the kube_hetzner_selinux.te file, that allows in SELinux to not interfere with various needed services
- path: /root/kube_hetzner_selinux.te
  encoding: base64
  content: ${base64encode(file("${path.module}/templates/kube-hetzner-selinux.te"))}

# Shared Leap Micro policy used by host and autoscaler templates
- path: /root/k8s_custom_policies.te
  encoding: base64
  content: ${base64encode(file("${path.module}/templates/k8s-custom-policies.te"))}

# Create the distribution-specific registries file before Kubernetes starts.
%{if local.registries_config_effective != ""}
- content: ${base64encode(local.registries_config_effective)}
  encoding: base64
  path: ${local.registries_config_file}
%{endif}

# Create the distribution-specific kubelet config file if needed.
%{if var.kubelet_config != ""}
- content: ${base64encode(var.kubelet_config)}
  encoding: base64
  path: ${local.kubelet_config_file}
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

# Disable transactional updates during first boot. The host module re-enables
# the timer after provisioning when automatically_upgrade_os is true; keeping it
# active during cloud-init can race Kubernetes bootstrap on Leap Micro.
- |
  systemctl disable --now transactional-update.timer || true
  systemctl stop transactional-update.service || true
  rm -f /var/run/reboot-required /var/run/reboot-required.pkgs

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

# Reduces snapper limits to avoid disk pressure on small Hetzner VMs.
- |
  if [ -f /etc/snapper/configs/root ]; then
    sed -i 's/^NUMBER_LIMIT=".*"/NUMBER_LIMIT="4"/' /etc/snapper/configs/root
    sed -i 's/^NUMBER_LIMIT_IMPORTANT=".*"/NUMBER_LIMIT_IMPORTANT="3"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_HOURLY=".*"/TIMELINE_LIMIT_HOURLY="0"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_DAILY=".*"/TIMELINE_LIMIT_DAILY="3"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_MONTHLY=".*"/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root
    sed -i 's/^TIMELINE_LIMIT_YEARLY=".*"/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root
    systemctl disable --now snapper-timeline.timer || true
  else
    echo "Snapper config not found, skipping snapshot limit configuration"
  fi

# Allow network interface
- [chmod, '+x', '/etc/cloud/rename_interface.sh']
- [chmod, '+x', '/etc/cloud/rename_interface_boot.sh']

# Enable the self-heal oneshot so it runs on every subsequent boot. We don't
# start it here — first-boot rename happens via remote-exec before k3s/rke2
# install, and starting it now while eth1 already exists is a no-op.
- [systemctl, daemon-reload]
- [systemctl, enable, kh-rename-interface.service]

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
- [mkdir, '-p', '${dirname(var.audit_log_path)}']
- [chmod, '750', '${dirname(var.audit_log_path)}']
- [chown, 'root:root', '${dirname(var.audit_log_path)}']

# Add logic to truly disable SELinux if enable_selinux = false.
# We'll do it by appending to cloudinit_runcmd_common.
%{if !var.enable_selinux}
- [sed, '-i', '-E', 's/^SELINUX=[a-z]+/SELINUX=disabled/', '/etc/selinux/config']
- [setenforce, '0']
%{endif}

# Backup unlock for root SSH pubkey auth (belt-and-suspenders alongside the
# systemd oneshot baked into the Packer image). cloud-init runcmd is
# per-instance only, so the systemd unit is the real guard.
- [sed, '-i', 's/^root:!/root:/', '/etc/shadow']
- [systemctl, 'restart', 'sshd']

EOT

}

# Cross-variable validations should live in variable validation blocks where possible.
