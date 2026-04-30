# Cross-object module contract checks live here instead of input variable
# validation blocks so Terraform 1.15+ can initialize modules before every
# referenced variable/local has been evaluated. These are hard preconditions:
# invalid configurations still fail during plan before any infrastructure is
# changed.
resource "terraform_data" "validation_contract" {
  input = true

  lifecycle {
    # Moved from variable "enable_robot_ccm" validation near variables.tf:53.
    precondition {
      condition     = !var.enable_robot_ccm || (trimspace(var.robot_user) != "" && trimspace(var.robot_password) != "")
      error_message = "enable_robot_ccm requires non-empty robot_user and robot_password."
    }

    # Moved from variable "enabled_architectures" validation near variables.tf:95.
    precondition {
      condition = alltrue([
        for server_type in local.validation_all_server_types :
        contains(var.enabled_architectures, substr(server_type, 0, 3) == "cax" ? "arm" : "x86")
      ])
      error_message = "enabled_architectures must include every architecture used by control_plane_nodepools, agent_nodepools, and autoscaler_nodepools."
    }

    # Moved from variable "network_region" validation near variables.tf:217.
    precondition {
      condition     = contains(keys(local.validation_locations_by_region), var.network_region)
      error_message = "network_region must be one of: eu-central, us-east, us-west, ap-southeast."
    }

    # Moved from variable "network_region" validation near variables.tf:222.
    precondition {
      condition = alltrue([
        for location in local.validation_all_locations :
        contains(lookup(local.validation_locations_by_region, var.network_region, []), location)
      ])
      error_message = "network_region must match every configured control-plane, primary-network agent, primary-network autoscaler, NAT router, and private-network load balancer location."
    }

    # Moved from variable "network_region" validation near variables.tf:230.
    precondition {
      condition = var.network_region == var.network_region && alltrue([
        for _, attachment_count in local.validation_network_attachment_count_by_network :
        attachment_count <= 100
      ])
      error_message = "Each Hetzner private network supports at most 100 attached resources. Reduce static nodes, autoscaler max_nodes, NAT routers, load balancers, control-plane fanout, or extra_network_ids per network."
    }

    # Moved from variable "multinetwork_mode" validation near variables.tf:280.
    precondition {
      condition     = var.multinetwork_mode != "cilium_public_overlay" || var.enable_experimental_cilium_public_overlay
      error_message = "multinetwork_mode=\"cilium_public_overlay\" is experimental and not release-supported for production clusters yet. Set enable_experimental_cilium_public_overlay=true only for lab validation."
    }

    # Moved from variable "multinetwork_mode" validation near variables.tf:285.
    precondition {
      condition     = var.multinetwork_mode != "cilium_public_overlay" || var.cni_plugin == "cilium"
      error_message = "multinetwork_mode=\"cilium_public_overlay\" requires cni_plugin=\"cilium\"."
    }

    # Moved from variable "multinetwork_mode" validation near variables.tf:290.
    precondition {
      condition     = var.multinetwork_mode != "cilium_public_overlay" || var.nat_router == null
      error_message = "multinetwork_mode=\"cilium_public_overlay\" is incompatible with nat_router. Public overlay nodes need direct public transport, not private-only NAT routing."
    }

    # Moved from variable "multinetwork_mode" validation near variables.tf:295.
    precondition {
      condition = (
        var.multinetwork_mode != "cilium_public_overlay" ||
        var.control_plane_endpoint != null
      )
      error_message = "multinetwork_mode=\"cilium_public_overlay\" requires control_plane_endpoint to be set to a Kubernetes API endpoint reachable from every configured Hetzner Network."
    }

    # Moved from variable "multinetwork_mode" validation near variables.tf:303.
    precondition {
      condition = (
        var.multinetwork_mode != "cilium_public_overlay" ||
        !var.enable_control_plane_load_balancer ||
        var.control_plane_load_balancer_enable_public_network
      )
      error_message = "multinetwork_mode=\"cilium_public_overlay\" requires control_plane_load_balancer_enable_public_network=true when the module-managed control-plane load balancer is enabled."
    }

    # Moved from variable "multinetwork_mode" validation near variables.tf:312.
    precondition {
      condition = (
        var.multinetwork_mode != "cilium_public_overlay" ||
        var.ingress_controller == "none" ||
        var.ingress_controller == "custom" ||
        var.enable_klipper_metal_lb ||
        var.load_balancer_enable_public_network
      )
      error_message = "multinetwork_mode=\"cilium_public_overlay\" requires public Hetzner Load Balancers for managed ingress controllers. Set load_balancer_enable_public_network=true, use a custom/no ingress controller, or use Klipper/MetalLB."
    }

    # Moved from variable "multinetwork_mode" validation near variables.tf:323.
    precondition {
      condition = (
        var.multinetwork_mode == "disabled" ||
        var.node_transport_mode != "tailscale"
      )
      error_message = "node_transport_mode=\"tailscale\" is an alternative cross-network transport and must be used with multinetwork_mode=\"disabled\"."
    }

    # Moved from variable "multinetwork_transport_ip_family" validation near variables.tf:349.
    precondition {
      condition = (
        var.multinetwork_mode != "cilium_public_overlay" ||
        !contains(["ipv4", "dualstack"], var.multinetwork_transport_ip_family) ||
        (
          (length(var.autoscaler_nodepools) == 0 || var.autoscaler_enable_public_ipv4) &&
          alltrue([
            for control_plane_nodepool in var.control_plane_nodepools :
            control_plane_nodepool.enable_public_ipv4 &&
            alltrue([
              for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
              coalesce(control_plane_node.enable_public_ipv4, control_plane_nodepool.enable_public_ipv4)
            ])
          ]) &&
          alltrue([
            for agent_nodepool in var.agent_nodepools :
            agent_nodepool.enable_public_ipv4 &&
            alltrue([
              for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
              coalesce(agent_node.enable_public_ipv4, agent_nodepool.enable_public_ipv4)
            ])
          ])
        )
      )
      error_message = "multinetwork_mode=\"cilium_public_overlay\" with IPv4 transport requires public IPv4 enabled on all control-plane and agent nodes, plus autoscaler nodes when autoscaler_nodepools are configured."
    }

    # Moved from variable "multinetwork_transport_ip_family" validation near variables.tf:376.
    precondition {
      condition = (
        var.multinetwork_mode != "cilium_public_overlay" ||
        !contains(["ipv6", "dualstack"], var.multinetwork_transport_ip_family) ||
        (
          (length(var.autoscaler_nodepools) == 0 || var.autoscaler_enable_public_ipv6) &&
          alltrue([
            for control_plane_nodepool in var.control_plane_nodepools :
            control_plane_nodepool.enable_public_ipv6 &&
            alltrue([
              for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
              coalesce(control_plane_node.enable_public_ipv6, control_plane_nodepool.enable_public_ipv6)
            ])
          ]) &&
          alltrue([
            for agent_nodepool in var.agent_nodepools :
            agent_nodepool.enable_public_ipv6 &&
            alltrue([
              for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
              coalesce(agent_node.enable_public_ipv6, agent_nodepool.enable_public_ipv6)
            ])
          ])
        )
      )
      error_message = "multinetwork_mode=\"cilium_public_overlay\" with IPv6 or dual-stack transport requires public IPv6 enabled on all control-plane and agent nodes, plus autoscaler nodes when autoscaler_nodepools are configured."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:453.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        trimspace(var.tailscale_node_transport.magicdns_domain != null ? var.tailscale_node_transport.magicdns_domain : "") != ""
      )
      error_message = "node_transport_mode=\"tailscale\" requires tailscale_node_transport.magicdns_domain so the module can build deterministic Tailnet endpoints."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:461.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.tailscale_node_transport.auth.mode == "external" ||
        (
          var.tailscale_node_transport.auth.mode == "auth_key" &&
          (
            (
              var.tailscale_auth_key != null &&
              trimspace(var.tailscale_auth_key) != ""
            ) ||
            (
              var.tailscale_control_plane_auth_key != null &&
              trimspace(var.tailscale_control_plane_auth_key) != "" &&
              var.tailscale_agent_auth_key != null &&
              trimspace(var.tailscale_agent_auth_key) != ""
            )
          )
        ) ||
        (
          var.tailscale_node_transport.auth.mode == "oauth_client_secret" &&
          var.tailscale_oauth_client_secret != null &&
          trimspace(var.tailscale_oauth_client_secret) != ""
        )
      )
      error_message = "node_transport_mode=\"tailscale\" requires tailscale_auth_key or per-role Tailscale auth keys when auth.mode=\"auth_key\", tailscale_oauth_client_secret when auth.mode=\"oauth_client_secret\", or auth.mode=\"external\"."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:489.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.kubernetes_distribution == "k3s" ||
        (
          var.kubernetes_distribution == "rke2" &&
          var.cni_plugin == "cilium" &&
          var.tailscale_node_transport.enable_experimental_rke2 &&
          var.tailscale_node_transport.enable_experimental_cilium
        )
      )
      error_message = "Tailscale node transport is release-supported for k3s first. RKE2 requires cni_plugin=\"cilium\" plus tailscale_node_transport.enable_experimental_rke2=true and enable_experimental_cilium=true until live validation promotes it."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:503.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.cni_plugin == "flannel" ||
        (
          var.cni_plugin == "cilium" &&
          var.tailscale_node_transport.enable_experimental_cilium
        )
      )
      error_message = "Tailscale node transport supports cni_plugin=\"flannel\" first. Cilium requires tailscale_node_transport.enable_experimental_cilium=true until the Cilium/Tailscale datapath is live-proven. Calico is not supported yet."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:515.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.cni_plugin != "flannel" ||
        coalesce(var.flannel_backend, "vxlan") != "host-gw"
      )
      error_message = "Tailscale node transport cannot use flannel_backend=\"host-gw\" because Tailscale is not a shared L2 network. Use VXLAN or wireguard-native."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:524.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        length(local.validation_tailnet_ipv4_cidr_starts_inside) == 0 &&
        length(local.validation_tailnet_ipv6_cidr_starts_inside) == 0
      )
      error_message = "Tailscale node transport cannot use cluster, service, or Hetzner network CIDRs that start inside Tailscale's reserved 100.64.0.0/10 or fd7a:115c:a1e0::/48 ranges."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:533.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.firewall_kube_api_source == null ||
        (
          !contains(var.firewall_kube_api_source, "0.0.0.0/0") &&
          !contains(var.firewall_kube_api_source, "::/0")
        )
      )
      error_message = "node_transport_mode=\"tailscale\" must not leave the Kubernetes API open to the internet. Set firewall_kube_api_source=null to close public API access or restrict it to explicit CIDRs."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:545.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.firewall_ssh_source == null ||
        (
          !contains(var.firewall_ssh_source, "0.0.0.0/0") &&
          !contains(var.firewall_ssh_source, "::/0")
        )
      )
      error_message = "node_transport_mode=\"tailscale\" must not leave public SSH open to the internet. Set firewall_ssh_source=null for cloud-init/tailnet SSH paths or restrict it to explicit CIDRs for remote-exec bootstrap."
    }

    # Moved from variable "node_transport_mode" validation near variables.tf:557.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        !var.enable_control_plane_load_balancer ||
        !var.control_plane_load_balancer_enable_public_network
      )
      error_message = "node_transport_mode=\"tailscale\" supports the module-managed control-plane Load Balancer only with control_plane_load_balancer_enable_public_network=false. Keep the Kubernetes API on the Tailnet/private network or use an explicit external endpoint you secure outside kube-hetzner."
    }

    # Moved from variable "tailscale_node_transport" validation near variables.tf:671.
    precondition {
      condition = (
        var.tailscale_node_transport.kubernetes.kubeconfig_endpoint != "explicit" ||
        trimspace(var.kubeconfig_server_address) != ""
      )
      error_message = "tailscale_node_transport.kubernetes.kubeconfig_endpoint=\"explicit\" requires kubeconfig_server_address."
    }

    # Moved from variable "subnet_count" validation near variables.tf:765.
    precondition {
      # Host bits = 32 - prefix, must have enough bits to create subnet_count subnets
      condition     = can(cidrhost(var.network_ipv4_cidr, 0)) ? pow(2, 32 - tonumber(split("/", var.network_ipv4_cidr)[1])) >= var.subnet_count : true
      error_message = "The network CIDR is too small for the requested subnet amount. Reduce subnet_count or use a larger network."
    }

    # Moved from variable "subnet_count" validation near variables.tf:770.
    precondition {
      condition = var.subnet_count >= (
        (
          var.network_subnet_mode == "per_nodepool"
          ? length(var.control_plane_nodepools) + length(var.agent_nodepools)
          : 2
        ) + (var.nat_router == null ? 0 : (try(var.nat_router.enable_redundancy, false) ? 2 : 1))
      )
      error_message = "Subnet amount is too small for the selected network_subnet_mode and NAT router settings."
    }

    # Moved from variable "service_ipv4_cidr" validation near variables.tf:808.
    precondition {
      condition     = (trimspace(var.service_ipv4_cidr) == "") == (trimspace(var.cluster_ipv4_cidr) == "")
      error_message = "cluster_ipv4_cidr and service_ipv4_cidr must both be set for IPv4 networking, or both be empty for IPv6-only networking."
    }

    # Moved from variable "service_ipv4_cidr" validation near variables.tf:813.
    precondition {
      condition = (
        trimspace(var.service_ipv4_cidr) == "" ||
        trimspace(var.cluster_ipv4_cidr) == "" ||
        trimspace(var.service_ipv4_cidr) != trimspace(var.cluster_ipv4_cidr)
      )
      error_message = "cluster_ipv4_cidr and service_ipv4_cidr must not be identical."
    }

    # Moved from variable "cluster_ipv6_cidr" validation near variables.tf:836.
    precondition {
      condition = (
        (try(trimspace(var.cluster_ipv6_cidr), "") == "") ==
        (try(trimspace(var.service_ipv6_cidr), "") == "")
      )
      error_message = "cluster_ipv6_cidr and service_ipv6_cidr must be set together for dual-stack or IPv6-only networking."
    }

    # Moved from variable "cluster_ipv6_cidr" validation near variables.tf:844.
    precondition {
      condition     = try(trimspace(var.cluster_ipv6_cidr), "") == "" || var.cni_plugin == "cilium"
      error_message = "IPv6 and dual-stack pod/service CIDRs are currently supported only with cni_plugin = \"cilium\"."
    }

    # Moved from variable "cluster_ipv6_cidr" validation near variables.tf:849.
    precondition {
      condition = (
        try(trimspace(var.cluster_ipv6_cidr), "") == "" ||
        try(trimspace(var.service_ipv6_cidr), "") == "" ||
        trimspace(var.cluster_ipv6_cidr) != trimspace(var.service_ipv6_cidr)
      )
      error_message = "cluster_ipv6_cidr and service_ipv6_cidr must not be identical."
    }

    # Moved from variable "cluster_ipv6_cidr" validation near variables.tf:858.
    precondition {
      condition = (
        trimspace(var.cluster_ipv4_cidr) != "" ||
        try(trimspace(var.cluster_ipv6_cidr), "") != ""
      )
      error_message = "At least one pod/service IP family must be enabled. Keep IPv4 CIDRs set, or set both IPv6 CIDRs for IPv6-only mode."
    }

    # Moved from variable "cluster_dns_ipv4" validation near variables.tf:887.
    precondition {
      condition = (
        var.cluster_dns_ipv4 == null ||
        (
          provider::assert::ipv4(var.cluster_dns_ipv4) &&
          trimspace(var.service_ipv4_cidr) != ""
        )
      )
      error_message = "cluster_dns_ipv4 must be a valid IPv4 address and requires service_ipv4_cidr to be enabled."
    }

    # Moved from variable "kubernetes_api_port" validation near variables.tf:909.
    precondition {
      condition     = var.kubernetes_distribution != "rke2" || var.kubernetes_api_port == 6443
      error_message = "RKE2 currently requires kubernetes_api_port = 6443. RKE2 node registration uses supervisor port 9345, and RKE2 does not expose a supported https-listen-port equivalent for changing the Kubernetes API listener."
    }

    # Moved from variable "nat_router" validation near variables.tf:935.
    precondition {
      condition     = var.nat_router == null || var.enable_control_plane_load_balancer || var.node_transport_mode == "tailscale"
      error_message = "When nat_router is enabled, enable_control_plane_load_balancer must be set to true unless node_transport_mode=\"tailscale\" provides the API/kubeconfig path through the tailnet."
    }

    # Moved from variable "nat_router" validation near variables.tf:940.
    precondition {
      condition = (
        var.nat_router == null ||
        var.node_transport_mode != "tailscale" ||
        var.ingress_controller == "none" ||
        var.ingress_controller == "custom" ||
        var.enable_klipper_metal_lb
      )
      error_message = "nat_router with node_transport_mode=\"tailscale\" makes Terraform-managed nodes private-only. Use Klipper/MetalLB, ingress_controller=\"custom\"/\"none\", or an external load balancer instead of managed Hetzner ingress."
    }

    # Moved from variable "use_private_nat_router_bastion" validation near variables.tf:957.
    precondition {
      condition     = !var.use_private_nat_router_bastion || var.nat_router != null
      error_message = "use_private_nat_router_bastion requires nat_router to be configured."
    }

    # Moved from variable "nat_router_hcloud_token" validation near variables.tf:969.
    precondition {
      condition     = var.nat_router == null || !try(var.nat_router.enable_redundancy, false) || var.nat_router_hcloud_token != ""
      error_message = "When nat_router.enable_redundancy is true, nat_router_hcloud_token must be provided."
    }

    # Moved from variable "nat_router_subnet_index" validation near variables.tf:1004.
    precondition {
      condition     = var.nat_router_subnet_index >= 0 && var.nat_router_subnet_index < var.subnet_count
      error_message = "NAT router subnet index must be between 0 and subnet_count."
    }

    # Moved from variable "nat_router_subnet_index" validation near variables.tf:1009.
    precondition {
      condition     = var.nat_router == null || !contains(local.validation_reserved_primary_network_subnet_indexes, var.nat_router_subnet_index)
      error_message = "nat_router_subnet_index must not collide with control-plane or agent subnet indexes."
    }

    # Moved from variable "nat_router_subnet_index" validation near variables.tf:1014.
    precondition {
      condition = (
        var.nat_router == null ||
        length(distinct(concat(
          local.validation_reserved_primary_network_subnet_indexes,
          [var.nat_router_subnet_index]
        ))) <= 50
      )
      error_message = "Hetzner Cloud Networks support at most 50 subnets. Disable NAT router subnet creation or reduce primary-network subnet allocations."
    }

    # Moved from variable "vswitch_subnet_index" validation near variables.tf:1031.
    precondition {
      condition     = var.vswitch_subnet_index >= 0 && var.vswitch_subnet_index < var.subnet_count
      error_message = "vSwitch subnet index must be between 0 and subnet_count."
    }

    # Moved from variable "vswitch_subnet_index" validation near variables.tf:1036.
    precondition {
      condition     = var.vswitch_id == null || var.vswitch_subnet_index != var.nat_router_subnet_index || var.nat_router == null
      error_message = "vswitch_subnet_index must not equal nat_router_subnet_index when both vSwitch and nat_router are enabled."
    }

    # Moved from variable "vswitch_subnet_index" validation near variables.tf:1041.
    precondition {
      condition     = var.vswitch_id == null || !contains(local.validation_reserved_primary_network_subnet_indexes, var.vswitch_subnet_index)
      error_message = "vswitch_subnet_index must not collide with control-plane or agent subnet indexes."
    }

    # Moved from variable "vswitch_subnet_index" validation near variables.tf:1046.
    precondition {
      condition = (
        var.vswitch_id == null ||
        length(distinct(concat(
          local.validation_reserved_primary_network_subnet_indexes,
          var.nat_router == null ? [] : [var.nat_router_subnet_index],
          [var.vswitch_subnet_index]
        ))) <= 50
      )
      error_message = "Hetzner Cloud Networks support at most 50 subnets. Disable vSwitch subnet creation or reduce primary-network subnet allocations."
    }

    # Moved from variable "vswitch_id" validation near variables.tf:1069.
    precondition {
      condition     = var.vswitch_id == null || var.network_region == "eu-central"
      error_message = "Hetzner Cloud vSwitch coupling is supported only in network_region = \"eu-central\"."
    }

    # Moved from variable "expose_routes_to_vswitch" validation near variables.tf:1080.
    precondition {
      condition = (
        !var.expose_routes_to_vswitch ||
        var.vswitch_id == null ||
        var.existing_network == null
      )
      error_message = "expose_routes_to_vswitch can only be managed when kube-hetzner creates the primary Network. For existing_network, enable route exposure on that Network manually or set expose_routes_to_vswitch=false."
    }

    # Moved from variable "extra_robot_nodes" validation near variables.tf:1156.
    precondition {
      condition     = length(var.extra_robot_nodes) == 0 || var.vswitch_id != null
      error_message = "extra_robot_nodes requires vswitch_id so Robot nodes have a Cloud Network vSwitch subnet to join."
    }

    # Moved from variable "extra_robot_nodes" validation near variables.tf:1161.
    precondition {
      condition     = length(var.extra_robot_nodes) == 0 || var.kubernetes_distribution == "k3s"
      error_message = "extra_robot_nodes currently supports only kubernetes_distribution = \"k3s\"."
    }

    # Moved from variable "load_balancer_location" validation near variables.tf:1182.
    precondition {
      condition     = contains(flatten(values(local.validation_locations_by_region)), var.load_balancer_location)
      error_message = "load_balancer_location must be one of the supported Hetzner Cloud locations: fsn1, hel1, nbg1, ash, hil, sin."
    }

    # Moved from variable "load_balancer_health_check_timeout" validation near variables.tf:1241.
    precondition {
      condition = (
        can(regex("^[0-9]+s$", var.load_balancer_health_check_timeout)) &&
        can(regex("^[0-9]+s$", var.load_balancer_health_check_interval)) &&
        tonumber(trimsuffix(var.load_balancer_health_check_timeout, "s")) >= 1 &&
        tonumber(trimsuffix(var.load_balancer_health_check_timeout, "s")) <= tonumber(trimsuffix(var.load_balancer_health_check_interval, "s"))
      )
      error_message = "load_balancer_health_check_timeout must be a duration in seconds, at least 1s, and not greater than load_balancer_health_check_interval."
    }

    # Moved from variable "exclude_agents_from_external_load_balancers" validation near variables.tf:1274.
    precondition {
      condition = (
        !var.exclude_agents_from_external_load_balancers ||
        var.allow_scheduling_on_control_plane ||
        local.validation_is_single_node_cluster
      )
      error_message = "exclude_agents_from_external_load_balancers=true with allow_scheduling_on_control_plane=false leaves no eligible targets for CCM-managed LoadBalancer services unless this is a single-node cluster."
    }

    # Moved from variable "control_plane_nodepools" validation near variables.tf:1414.
    precondition {
      condition = (
        var.network_subnet_mode != "per_nodepool" ||
        length(var.control_plane_nodepools) + length(var.agent_nodepools) <= 50
      )
      error_message = "network_subnet_mode = \"per_nodepool\" creates one subnet per control-plane and agent nodepool, but Hetzner Cloud Networks support at most 50 subnets."
    }

    # Moved from variable "control_plane_nodepools" validation near variables.tf:1481.
    precondition {
      condition = (
        var.control_plane_endpoint != null ||
        !var.enable_control_plane_load_balancer ||
        !var.control_plane_load_balancer_enable_public_network ||
        alltrue([
          for control_plane_nodepool in var.control_plane_nodepools :
          control_plane_nodepool.join_endpoint_type != "public" &&
          alltrue([
            for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
            control_plane_node.join_endpoint_type != "public"
          ])
        ])
      )
      error_message = "control_plane_nodepools join_endpoint_type=\"public\" with the module-managed control-plane load balancer requires control_plane_endpoint. Hetzner Cloud nodes are not assumed to hairpin through the load balancer public IP."
    }

    # Moved from variable "control_plane_nodepools" validation near variables.tf:1498.
    precondition {
      condition = (
        var.control_plane_endpoint != null ||
        (var.enable_control_plane_load_balancer && var.control_plane_load_balancer_enable_public_network) ||
        !(
          var.multinetwork_mode == "cilium_public_overlay" ||
          anytrue([
            for control_plane_nodepool in var.control_plane_nodepools :
            control_plane_nodepool.join_endpoint_type == "public" ||
            anytrue([
              for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
              control_plane_node.join_endpoint_type == "public"
            ])
          ]) ||
          anytrue([
            for agent_nodepool in var.agent_nodepools :
            agent_nodepool.join_endpoint_type == "public" ||
            anytrue([
              for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
              agent_node.join_endpoint_type == "public"
            ])
          ]) ||
          anytrue([
            for autoscaler_nodepool in var.autoscaler_nodepools :
            coalesce(autoscaler_nodepool.join_endpoint_type, "private") == "public"
          ])
        ) ||
        alltrue(flatten([
          for control_plane_nodepool in var.control_plane_nodepools : concat(
            [
              for _ in range(max(0, floor(coalesce(control_plane_nodepool.count, 0)))) :
              control_plane_nodepool.enable_public_ipv4 || control_plane_nodepool.enable_public_ipv6
            ],
            [
              for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
              coalesce(control_plane_node.enable_public_ipv4, control_plane_nodepool.enable_public_ipv4) ||
              coalesce(control_plane_node.enable_public_ipv6, control_plane_nodepool.enable_public_ipv6)
            ]
          )
        ]))
      )
      error_message = "A public Kubernetes join endpoint without control_plane_endpoint or a public control-plane load balancer requires public IPv4 or IPv6 on every control-plane node."
    }

    # Moved from variable "control_plane_nodepools" validation near variables.tf:1561.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.tailscale_node_transport.bootstrap_mode == "external" ||
        alltrue(flatten([
          for control_plane_nodepool in var.control_plane_nodepools : concat(
            [
              for _ in range(max(0, floor(coalesce(control_plane_nodepool.count, 0)))) :
              var.nat_router != null || control_plane_nodepool.enable_public_ipv4 || control_plane_nodepool.enable_public_ipv6
            ],
            [
              for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
              var.nat_router != null ||
              coalesce(control_plane_node.enable_public_ipv4, control_plane_nodepool.enable_public_ipv4) ||
              coalesce(control_plane_node.enable_public_ipv6, control_plane_nodepool.enable_public_ipv6)
            ]
          )
        ]))
      )
      error_message = "Managed Tailscale bootstrap requires every control-plane node to have internet egress via public IPv4, public IPv6, or nat_router. Use tailscale_node_transport.bootstrap_mode=\"external\" only when your own bootstrap handles this."
    }

    # Moved from variable "agent_nodepools" validation near variables.tf:1823.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.tailscale_node_transport.routing.advertise_node_private_routes ||
        alltrue(flatten([
          for agent_nodepool in var.agent_nodepools : concat(
            [
              agent_nodepool.count == null ||
              agent_nodepool.count <= 0 ||
              coalesce(agent_nodepool.network_id, 0) == 0
            ],
            [
              for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
              coalesce(agent_node.network_id, agent_nodepool.network_id, 0) == 0
            ]
          )
        ]))
      )
      error_message = "tailscale_node_transport.routing.advertise_node_private_routes can be false only when all static agent nodepools stay on the primary Hetzner Network. External agent network_id values need approved node-private routes for cross-network Kubernetes traffic."
    }

    # Moved from variable "agent_nodepools" validation near variables.tf:1844.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.ingress_controller == "none" ||
        var.ingress_controller == "custom" ||
        var.enable_klipper_metal_lb ||
        var.load_balancer_enable_public_network ||
        alltrue(flatten([
          for agent_nodepool in var.agent_nodepools : concat(
            [
              agent_nodepool.count == null ||
              agent_nodepool.count <= 0 ||
              coalesce(agent_nodepool.network_id, 0) == 0
            ],
            [
              for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
              coalesce(agent_node.network_id, agent_nodepool.network_id, 0) == 0
            ]
          )
        ]))
      )
      error_message = "Tailscale node transport does not make Hetzner private Load Balancers span external static agent Networks. With external agent network_id values, managed Hetzner ingress needs public Load Balancers and public node targets; otherwise use Klipper/MetalLB, ingress_controller=\"custom\"/\"none\", or an external load balancer."
    }

    # Moved from variable "agent_nodepools" validation near variables.tf:1868.
    precondition {
      condition = 1 + length(distinct(concat(
        var.extra_network_ids,
        (var.multinetwork_mode == "cilium_public_overlay" || var.node_transport_mode == "tailscale") ? [] : flatten([
          for agent_nodepool in var.agent_nodepools : concat(
            coalesce(agent_nodepool.network_id, 0) == 0 ? [] : [coalesce(agent_nodepool.network_id, 0)],
            [
              for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
              coalesce(agent_node.network_id, agent_nodepool.network_id, 0)
              if coalesce(agent_node.network_id, agent_nodepool.network_id, 0) != 0
            ]
          )
        ])
      ))) <= 3
      error_message = "Control planes can attach to at most 3 Networks. Reduce extra_network_ids or use multinetwork_mode=\"cilium_public_overlay\" or node_transport_mode=\"tailscale\" so control planes do not fan out to every external agent Network."
    }

    # Moved from variable "agent_nodepools" validation near variables.tf:1885.
    precondition {
      condition = (
        length(distinct(concat(
          [0],
          flatten([
            for agent_nodepool in var.agent_nodepools : concat(
              [coalesce(agent_nodepool.network_id, 0)],
              [
                for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
                coalesce(agent_node.network_id, agent_nodepool.network_id, 0)
              ]
            )
          ])
        ))) <= 1 ||
        var.control_plane_endpoint != null ||
        var.multinetwork_mode == "cilium_public_overlay" ||
        var.node_transport_mode == "tailscale"
      )
      error_message = "When using multiple primary private networks, set control_plane_endpoint, enable multinetwork_mode=\"cilium_public_overlay\", or use node_transport_mode=\"tailscale\". The module-managed Hetzner control-plane load balancer is not treated as a cross-network public join endpoint."
    }

    # Moved from variable "agent_nodepools" validation near variables.tf:1918.
    precondition {
      condition = (
        var.control_plane_endpoint != null ||
        !var.enable_control_plane_load_balancer ||
        !var.control_plane_load_balancer_enable_public_network ||
        alltrue([
          for agent_nodepool in var.agent_nodepools :
          agent_nodepool.join_endpoint_type != "public" &&
          alltrue([
            for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
            agent_node.join_endpoint_type != "public"
          ])
        ])
      )
      error_message = "agent_nodepools join_endpoint_type=\"public\" with the module-managed control-plane load balancer requires control_plane_endpoint. Hetzner Cloud nodes are not assumed to hairpin through the load balancer public IP."
    }

    # Moved from variable "agent_nodepools" validation near variables.tf:1935.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.nat_router == null ||
        alltrue([
          for agent_nodepool in var.agent_nodepools :
          coalesce(agent_nodepool.network_id, 0) == 0 &&
          alltrue([
            for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
            coalesce(agent_node.network_id, agent_nodepool.network_id, 0) == 0
          ])
        ])
      )
      error_message = "node_transport_mode=\"tailscale\" can combine with nat_router only when all static agent nodes are on the primary Hetzner Network. The module NAT router does not provide egress for external Hetzner Networks."
    }

    # Moved from variable "agent_nodepools" validation near variables.tf:1970.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.tailscale_node_transport.bootstrap_mode == "external" ||
        alltrue(flatten([
          for agent_nodepool in var.agent_nodepools : concat(
            [
              for _ in range(max(0, floor(coalesce(agent_nodepool.count, 0)))) :
              (
                coalesce(agent_nodepool.network_id, 0) == 0 &&
                var.nat_router != null
              ) || agent_nodepool.enable_public_ipv4 || agent_nodepool.enable_public_ipv6
            ],
            [
              for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
              (
                coalesce(agent_node.network_id, agent_nodepool.network_id, 0) == 0 &&
                var.nat_router != null
              ) ||
              coalesce(agent_node.enable_public_ipv4, agent_nodepool.enable_public_ipv4) ||
              coalesce(agent_node.enable_public_ipv6, agent_nodepool.enable_public_ipv6)
            ]
          )
        ]))
      )
      error_message = "Managed Tailscale bootstrap requires every static agent node to have internet egress via public IPv4, public IPv6, or a nat_router on the primary Hetzner Network. External-network nodes need their own public egress unless tailscale_node_transport.bootstrap_mode=\"external\" handles bootstrap outside the module."
    }

    # Moved from variable "cluster_autoscaler_metrics_firewall_source" validation near variables.tf:2245.
    precondition {
      condition = alltrue([
        for source in var.cluster_autoscaler_metrics_firewall_source :
        source == var.myipv4_ref || can(cidrhost(source, 0))
      ])
      error_message = "cluster_autoscaler_metrics_firewall_source entries must be CIDR blocks or the myipv4_ref placeholder."
    }

    # Moved from variable "autoscaler_nodepools" validation near variables.tf:2290.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        length(var.autoscaler_nodepools) == 0 ||
        var.tailscale_node_transport.bootstrap_mode == "cloud_init"
      )
      error_message = "Tailscale node transport with autoscaler_nodepools requires tailscale_node_transport.bootstrap_mode=\"cloud_init\" because autoscaler-created nodes cannot be configured by Terraform remote-exec before joining."
    }

    # Moved from variable "autoscaler_nodepools" validation near variables.tf:2299.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.tailscale_node_transport.auth.mode != "auth_key" ||
        length(var.autoscaler_nodepools) == 0 ||
        (
          var.tailscale_autoscaler_auth_key != null &&
          trimspace(var.tailscale_autoscaler_auth_key) != ""
        ) ||
        (
          var.tailscale_auth_key != null &&
          trimspace(var.tailscale_auth_key) != ""
        )
      )
      error_message = "Tailscale node transport with autoscaler_nodepools and auth.mode=\"auth_key\" requires tailscale_autoscaler_auth_key or a shared tailscale_auth_key. Prefer an ephemeral, reusable, pre-approved autoscaler key."
    }

    # Moved from variable "autoscaler_nodepools" validation near variables.tf:2400.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.tailscale_node_transport.routing.advertise_node_private_routes ||
        alltrue([
          for autoscaler_nodepool in var.autoscaler_nodepools :
          autoscaler_nodepool.max_nodes <= 0 ||
          coalesce(autoscaler_nodepool.network_id, 0) == 0
        ])
      )
      error_message = "tailscale_node_transport.routing.advertise_node_private_routes can be false only when all autoscaler nodepools stay on the primary Hetzner Network. External autoscaler network_id values need approved node-private routes for cross-network Kubernetes traffic."
    }

    # Moved from variable "autoscaler_nodepools" validation near variables.tf:2413.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.ingress_controller == "none" ||
        var.ingress_controller == "custom" ||
        var.enable_klipper_metal_lb ||
        var.load_balancer_enable_public_network ||
        alltrue([
          for autoscaler_nodepool in var.autoscaler_nodepools :
          autoscaler_nodepool.max_nodes <= 0 ||
          coalesce(autoscaler_nodepool.network_id, 0) == 0
        ])
      )
      error_message = "Tailscale node transport does not make Hetzner private Load Balancers span external autoscaler Networks. With external autoscaler network_id values, managed Hetzner ingress needs public Load Balancers and public node targets; otherwise use Klipper/MetalLB, ingress_controller=\"custom\"/\"none\", or an external load balancer."
    }

    # Moved from variable "autoscaler_nodepools" validation near variables.tf:2448.
    precondition {
      condition = (
        var.control_plane_endpoint != null ||
        !var.enable_control_plane_load_balancer ||
        !var.control_plane_load_balancer_enable_public_network ||
        alltrue([
          for autoscaler_nodepool in var.autoscaler_nodepools :
          autoscaler_nodepool.join_endpoint_type != "public"
        ])
      )
      error_message = "autoscaler_nodepools join_endpoint_type=\"public\" with the module-managed control-plane load balancer requires control_plane_endpoint. Hetzner Cloud nodes are not assumed to hairpin through the load balancer public IP."
    }

    # Moved from variable "autoscaler_nodepools" validation near variables.tf:2461.
    precondition {
      condition = (
        length(var.autoscaler_nodepools) == 0 ||
        var.multinetwork_mode == "cilium_public_overlay" ||
        var.node_transport_mode == "tailscale" ||
        length(distinct(concat(
          [0],
          [for autoscaler_nodepool in var.autoscaler_nodepools : coalesce(autoscaler_nodepool.network_id, 0)],
          flatten([
            for agent_nodepool in var.agent_nodepools : concat(
              [coalesce(agent_nodepool.network_id, 0)],
              [
                for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
                coalesce(agent_node.network_id, agent_nodepool.network_id, 0)
              ]
            )
          ])
        ))) <= 1
      )
      error_message = "Cluster autoscaler across multiple Hetzner Networks requires multinetwork_mode=\"cilium_public_overlay\" or node_transport_mode=\"tailscale\" so autoscaled nodes have a cross-network join path."
    }

    # Moved from variable "autoscaler_nodepools" validation near variables.tf:2483.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.nat_router == null ||
        alltrue([
          for autoscaler_nodepool in var.autoscaler_nodepools :
          coalesce(autoscaler_nodepool.network_id, 0) == 0
        ])
      )
      error_message = "node_transport_mode=\"tailscale\" can combine with nat_router only when all autoscaler nodepools are on the primary Hetzner Network. The module NAT router does not provide egress for external Hetzner Networks."
    }

    # Moved from variable "autoscaler_enable_public_ipv6" validation near variables.tf:2507.
    precondition {
      condition     = var.autoscaler_enable_public_ipv4 || var.autoscaler_enable_public_ipv6 || var.nat_router != null || var.optional_bastion_host != null || var.control_plane_endpoint != null || var.enable_control_plane_load_balancer
      error_message = "Disabling both public IPv4 and IPv6 on autoscaler nodes requires a configured private access/join path such as nat_router, optional_bastion_host, control_plane_endpoint, or enable_control_plane_load_balancer."
    }

    # Moved from variable "autoscaler_enable_public_ipv6" validation near variables.tf:2512.
    precondition {
      condition = (
        var.node_transport_mode != "tailscale" ||
        var.tailscale_node_transport.bootstrap_mode == "external" ||
        length(var.autoscaler_nodepools) == 0 ||
        alltrue([
          for autoscaler_nodepool in var.autoscaler_nodepools :
          (
            coalesce(autoscaler_nodepool.network_id, 0) == 0 &&
            var.nat_router != null
          ) ||
          var.autoscaler_enable_public_ipv4 ||
          var.autoscaler_enable_public_ipv6
        ])
      )
      error_message = "Managed Tailscale bootstrap requires autoscaler-created nodes to have internet egress via public IPv4, public IPv6, or a nat_router on the primary Hetzner Network. External-network autoscaler nodepools need public egress unless tailscale_node_transport.bootstrap_mode=\"external\" handles bootstrap outside the module."
    }

    # Moved from variable "ingress_max_replica_count" validation near variables.tf:2631.
    precondition {
      condition     = var.ingress_replica_count == 0 || var.ingress_max_replica_count >= var.ingress_replica_count
      error_message = "ingress_max_replica_count must be greater than or equal to ingress_replica_count when ingress_replica_count is explicit."
    }

    # Moved from variable "traefik_provider_kubernetes_gateway_enabled" validation near variables.tf:2666.
    precondition {
      condition     = !var.traefik_provider_kubernetes_gateway_enabled || var.ingress_controller == "traefik"
      error_message = "traefik_provider_kubernetes_gateway_enabled requires ingress_controller = \"traefik\"."
    }

    # Moved from variable "traefik_provider_kubernetes_gateway_enabled" validation near variables.tf:2671.
    precondition {
      condition     = !(var.traefik_provider_kubernetes_gateway_enabled && var.cilium_gateway_api_enabled)
      error_message = "Choose either traefik_provider_kubernetes_gateway_enabled or cilium_gateway_api_enabled, not both. They install separate Gateway API controllers."
    }

    # Moved from variable "k3s_channel" validation near variables.tf:2863.
    precondition {
      condition = (
        var.k3s_version != "" ||
        contains(["stable", "latest", "testing"], var.k3s_channel)
      )
      error_message = "When k3s_version is empty, k3s_channel must be stable, latest, or testing. Use k3s_version for exact Kubernetes minor pinning because Rancher minor release channels are not reliable live installer targets."
    }

    # Moved from variable "rke2_channel" validation near variables.tf:2888.
    precondition {
      condition = (
        var.rke2_version != "" ||
        contains(["stable", "latest", "testing"], var.rke2_channel)
      )
      error_message = "When rke2_version is empty, rke2_channel must be stable, latest, or testing. Use rke2_version for exact Kubernetes minor pinning because Rancher minor release channels are not reliable live installer targets."
    }

    # Moved from variable "system_upgrade_schedule_window" validation near variables.tf:2967.
    precondition {
      condition = var.system_upgrade_schedule_window == null ? true : (
        try(provider::semvers::compare(trimprefix(var.system_upgrade_controller_version, "v"), "0.15.0"), -1) >= 0
      )
      error_message = "system_upgrade_schedule_window requires system_upgrade_controller_version v0.15.0 or newer."
    }

    # Moved from variable "extra_firewall_rules" validation near variables.tf:2986.
    precondition {
      condition = alltrue([
        for rule in var.extra_firewall_rules :
        contains(["in", "out"], lookup(rule, "direction", "")) &&
        contains(["tcp", "udp", "icmp", "esp", "gre"], lookup(rule, "protocol", "")) &&
        (
          !contains(["tcp", "udp"], lookup(rule, "protocol", "")) ||
          can(regex("^([0-9]+|[0-9]+-[0-9]+)$", tostring(lookup(rule, "port", ""))))
        ) &&
        alltrue([
          for source in lookup(rule, "source_ips", []) :
          source == var.myipv4_ref || can(cidrhost(source, 0))
        ]) &&
        alltrue([
          for destination in lookup(rule, "destination_ips", []) :
          destination == var.myipv4_ref || can(cidrhost(destination, 0))
        ])
      ])
      error_message = "extra_firewall_rules entries must use direction in/out, protocol tcp/udp/icmp/esp/gre, valid tcp/udp ports, and CIDR/myipv4 source/destination IPs."
    }

    # Moved from variable "firewall_kube_api_source" validation near variables.tf:3013.
    precondition {
      condition = var.firewall_kube_api_source == null || alltrue([
        for source in var.firewall_kube_api_source :
        source == var.myipv4_ref || can(cidrhost(source, 0))
      ])
      error_message = "firewall_kube_api_source must be null or a list of CIDR blocks/myipv4_ref placeholders."
    }

    # Moved from variable "firewall_ssh_source" validation near variables.tf:3027.
    precondition {
      condition = var.firewall_ssh_source == null || alltrue([
        for source in var.firewall_ssh_source :
        source == var.myipv4_ref || can(cidrhost(source, 0))
      ])
      error_message = "firewall_ssh_source must be null or a list of CIDR blocks/myipv4_ref placeholders."
    }

    # Moved from variable "enable_placement_groups" validation near variables.tf:3086.
    precondition {
      condition = !var.enable_placement_groups || alltrue([
        for group_key in distinct(local.validation_control_plane_placement_group_keys) :
        length([
          for existing_group_key in local.validation_control_plane_placement_group_keys :
          existing_group_key if existing_group_key == group_key
        ]) <= 10
      ])
      error_message = "Each control-plane Hetzner spread placement group can contain at most 10 servers. Split nodepools across placement_group or placement_group_index values, or disable placement groups."
    }

    # Moved from variable "enable_placement_groups" validation near variables.tf:3097.
    precondition {
      condition = !var.enable_placement_groups || alltrue([
        for group_key in distinct(local.validation_agent_placement_group_keys) :
        length([
          for existing_group_key in local.validation_agent_placement_group_keys :
          existing_group_key if existing_group_key == group_key
        ]) <= 10
      ])
      error_message = "Each agent Hetzner spread placement group can contain at most 10 servers. Split nodepools across placement_group or placement_group_index values, or disable placement groups."
    }

    # Moved from variable "enable_placement_groups" validation near variables.tf:3108.
    precondition {
      condition     = !var.enable_placement_groups || local.validation_module_created_placement_group_count <= 50
      error_message = "Hetzner projects support at most 50 placement groups. Reduce static nodepool count, split across projects, use autoscaler nodepools for burst capacity, or set enable_placement_groups=false if you accept no placement-group spread for this cluster."
    }

    # Moved from variable "enable_kube_proxy" validation near variables.tf:3119.
    precondition {
      condition     = var.enable_kube_proxy || var.cni_plugin == "cilium"
      error_message = "Disabling kube-proxy requires cni_plugin = \"cilium\" in this module."
    }

    # Moved from variable "cilium_egress_gateway_enabled" validation near variables.tf:3147.
    precondition {
      condition     = !var.cilium_egress_gateway_enabled || (var.cni_plugin == "cilium" && !var.enable_kube_proxy)
      error_message = "cilium_egress_gateway_enabled requires cni_plugin = \"cilium\" and enable_kube_proxy = false because Cilium Egress Gateway requires kube-proxy replacement."
    }

    # Moved from variable "cilium_egress_gateway_ha_enabled" validation near variables.tf:3158.
    precondition {
      condition     = !var.cilium_egress_gateway_ha_enabled || var.cilium_egress_gateway_enabled
      error_message = "cilium_egress_gateway_ha_enabled requires cilium_egress_gateway_enabled = true."
    }

    # Moved from variable "cilium_gateway_api_enabled" validation near variables.tf:3169.
    precondition {
      condition     = !var.cilium_gateway_api_enabled || (var.cni_plugin == "cilium" && !var.enable_kube_proxy)
      error_message = "cilium_gateway_api_enabled requires cni_plugin = \"cilium\" and enable_kube_proxy = false because Cilium Gateway API requires kube-proxy replacement."
    }

    # Moved from variable "cilium_gateway_api_enabled" validation near variables.tf:3174.
    precondition {
      condition     = !var.cilium_gateway_api_enabled || try(provider::semvers::compare(trimprefix(var.cilium_version, "v"), "1.17.0"), -1) >= 0
      error_message = "cilium_gateway_api_enabled requires cilium_version to be an exact Cilium semver >= 1.17.0."
    }

    # Moved from variable "cilium_hubble_enabled" validation near variables.tf:3185.
    precondition {
      condition     = !var.cilium_hubble_enabled || var.cni_plugin == "cilium"
      error_message = "cilium_hubble_enabled requires cni_plugin = \"cilium\"."
    }

    # Moved from variable "cilium_hubble_metrics_enabled" validation near variables.tf:3196.
    precondition {
      condition     = length(var.cilium_hubble_metrics_enabled) == 0 || (var.cni_plugin == "cilium" && var.cilium_hubble_enabled)
      error_message = "cilium_hubble_metrics_enabled requires cni_plugin = \"cilium\" and cilium_hubble_enabled = true."
    }

    # Moved from variable "cilium_ipv4_native_routing_cidr" validation near variables.tf:3219.
    precondition {
      condition = (
        var.cilium_ipv4_native_routing_cidr == null ||
        trimspace(var.cilium_ipv4_native_routing_cidr) == "" ||
        (var.cni_plugin == "cilium" && var.cilium_routing_mode == "native")
      )
      error_message = "cilium_ipv4_native_routing_cidr is only used with cni_plugin = \"cilium\" and cilium_routing_mode = \"native\"."
    }

    # Moved from variable "enable_rancher" validation near variables.tf:3430.
    precondition {
      condition     = !var.enable_rancher || trimspace(var.rancher_hostname) != "" || trimspace(var.load_balancer_hostname) != ""
      error_message = "enable_rancher requires rancher_hostname or load_balancer_hostname to be set."
    }

    # Moved from variable "reuse_control_plane_load_balancer" validation near variables.tf:3557.
    precondition {
      condition     = !var.reuse_control_plane_load_balancer || var.enable_control_plane_load_balancer
      error_message = "reuse_control_plane_load_balancer requires enable_control_plane_load_balancer = true."
    }

    # Moved from variable "flannel_backend" validation near variables.tf:3698.
    precondition {
      condition     = var.flannel_backend == null || (var.kubernetes_distribution == "k3s" && var.cni_plugin == "flannel")
      error_message = "flannel_backend applies only when kubernetes_distribution = \"k3s\" and cni_plugin = \"flannel\"."
    }

    # Moved from variable "embedded_registry_mirror" validation near variables.tf:3778.
    precondition {
      condition = (
        !var.embedded_registry_mirror.enabled ||
        var.node_transport_mode != "tailscale" ||
        var.tailscale_node_transport.routing.advertise_node_private_routes ||
        (
          alltrue(flatten([
            for agent_nodepool in var.agent_nodepools : concat(
              [
                agent_nodepool.count == null ||
                agent_nodepool.count <= 0 ||
                coalesce(agent_nodepool.network_id, 0) == 0
              ],
              [
                for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
                coalesce(agent_node.network_id, agent_nodepool.network_id, 0) == 0
              ]
            )
          ])) &&
          alltrue([
            for autoscaler_nodepool in var.autoscaler_nodepools :
            autoscaler_nodepool.max_nodes <= 0 ||
            coalesce(autoscaler_nodepool.network_id, 0) == 0
          ])
        )
      )
      error_message = "embedded_registry_mirror with Tailscale multinetwork nodepools requires tailscale_node_transport.routing.advertise_node_private_routes = true so registry peer traffic can cross Hetzner Network islands."
    }
  }
}
