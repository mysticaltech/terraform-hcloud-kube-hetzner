variable "hcloud_token" {
  description = "Hetzner Cloud API Token."
  type        = string
  sensitive   = true

  validation {
    condition     = trimspace(var.hcloud_token) != ""
    error_message = "hcloud_token must be non-empty."
  }
}

variable "kubernetes_distribution" {
  description = "Kubernetes distribution type. Can be either k3s or rke2."
  type        = string
  default     = "k3s"

  validation {
    condition     = contains(["k3s", "rke2"], var.kubernetes_distribution)
    error_message = "The Kubernetes distribution type must be either k3s or rke2."
  }
}

variable "cluster_token" {
  description = "Cluster join token (must match when restoring a cluster)."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.cluster_token == null || trimspace(var.cluster_token) != ""
    error_message = "cluster_token must be null or a non-empty token string."
  }
}

variable "robot_user" {
  type        = string
  default     = ""
  sensitive   = true
  description = "User for the Hetzner Robot webservice"
}

variable "robot_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Password for the Hetzner Robot webservice"
}

variable "enable_robot_ccm" {
  type        = bool
  default     = false
  description = "Enables the integration of Hetzner Robot dedicated servers via the Cloud Controller Manager (CCM). If true, `robot_user` and `robot_password` must also be provided, otherwise the integration will not be activated."

  validation {
    condition     = !var.enable_robot_ccm || (trimspace(var.robot_user) != "" && trimspace(var.robot_password) != "")
    error_message = "enable_robot_ccm requires non-empty robot_user and robot_password."
  }
}

variable "leapmicro_x86_snapshot_id" {
  description = "Leap Micro x86 snapshot ID to be used. If empty, the most recent leapmicro snapshot matching the selected kubernetes_distribution will be used."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.leapmicro_x86_snapshot_id) == "" || can(regex("^[0-9]+$", trimspace(var.leapmicro_x86_snapshot_id)))
    error_message = "leapmicro_x86_snapshot_id must be empty or a numeric Hetzner image/snapshot ID."
  }
}

variable "leapmicro_arm_snapshot_id" {
  description = "Leap Micro ARM snapshot ID to be used. If empty, the most recent leapmicro snapshot matching the selected kubernetes_distribution will be used."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.leapmicro_arm_snapshot_id) == "" || can(regex("^[0-9]+$", trimspace(var.leapmicro_arm_snapshot_id)))
    error_message = "leapmicro_arm_snapshot_id must be empty or a numeric Hetzner image/snapshot ID."
  }
}

variable "enabled_architectures" {
  description = "CPU architectures allowed for nodepools and snapshot lookups. Use [\"x86\"], [\"arm\"], or [\"x86\", \"arm\"]. Hetzner CAX server types are ARM; other Cloud server families are treated as x86."
  type        = list(string)
  default     = ["x86", "arm"]

  validation {
    condition = (
      length(var.enabled_architectures) > 0 &&
      length(var.enabled_architectures) == length(distinct(var.enabled_architectures)) &&
      alltrue([for architecture in var.enabled_architectures : contains(["x86", "arm"], architecture)])
    )
    error_message = "enabled_architectures must contain one or both of: x86, arm."
  }

  validation {
    condition = alltrue([
      for server_type in local.validation_all_server_types :
      contains(var.enabled_architectures, substr(server_type, 0, 3) == "cax" ? "arm" : "x86")
    ])
    error_message = "enabled_architectures must include every architecture used by control_plane_nodepools, agent_nodepools, and autoscaler_nodepools."
  }
}

variable "microos_x86_snapshot_id" {
  description = "MicroOS x86 snapshot ID to be used. If empty, the most recent image created will be used."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.microos_x86_snapshot_id) == "" || can(regex("^[0-9]+$", trimspace(var.microos_x86_snapshot_id)))
    error_message = "microos_x86_snapshot_id must be empty or a numeric Hetzner image/snapshot ID."
  }
}

variable "microos_arm_snapshot_id" {
  description = "MicroOS ARM snapshot ID to be used. If empty, the most recent image created will be used."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.microos_arm_snapshot_id) == "" || can(regex("^[0-9]+$", trimspace(var.microos_arm_snapshot_id)))
    error_message = "microos_arm_snapshot_id must be empty or a numeric Hetzner image/snapshot ID."
  }
}

variable "ssh_port" {
  description = "The main SSH port to connect to the nodes."
  type        = number
  default     = 22

  validation {
    condition     = var.ssh_port >= 0 && var.ssh_port <= 65535
    error_message = "The SSH port must use a valid range from 0 to 65535."
  }
}

variable "ssh_public_key" {
  description = "SSH public Key."
  type        = string

  validation {
    condition = can(regex(
      "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)\\s+",
      trimspace(var.ssh_public_key)
    ))
    error_message = "ssh_public_key must be a valid OpenSSH public key starting with a supported key type (for example: ssh-ed25519, ssh-rsa, or ecdsa-sha2-nistp256)."
  }
}

variable "ssh_private_key" {
  description = "SSH private Key."
  type        = string
  sensitive   = true

  validation {
    condition     = var.ssh_private_key == null || trimspace(var.ssh_private_key) != ""
    error_message = "ssh_private_key must be null for ssh-agent based authentication or a non-empty private key."
  }
}

variable "ssh_hcloud_key_label" {
  description = "Additional SSH public Keys by hcloud label. e.g. role=admin"
  type        = string
  default     = ""
}

variable "ssh_additional_public_keys" {
  description = "Additional SSH public Keys. Use them to grant other team members root access to your cluster nodes."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for key in var.ssh_additional_public_keys :
      trimspace(key) == "" || can(regex(
        "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)\\s+",
        trimspace(key)
      ))
    ])
    error_message = "ssh_additional_public_keys entries must be empty or valid OpenSSH public keys."
  }
}

variable "authentication_config" {
  description = "Strucutred authentication configuration. This can be used to define external authentication providers."
  type        = string
  default     = ""
}

variable "hcloud_ssh_key_id" {
  description = "If passed, a key already registered within hetzner is used. Otherwise, a new one will be created by the module."
  type        = string
  default     = null

  validation {
    condition     = var.hcloud_ssh_key_id == null || can(regex("^[1-9][0-9]*$", trimspace(var.hcloud_ssh_key_id)))
    error_message = "hcloud_ssh_key_id must be null or a positive numeric Hetzner SSH key ID."
  }
}

variable "ssh_max_auth_tries" {
  description = "The maximum number of authentication attempts permitted per connection."
  type        = number
  default     = 2

  validation {
    condition     = var.ssh_max_auth_tries >= 1 && var.ssh_max_auth_tries <= 100 && floor(var.ssh_max_auth_tries) == var.ssh_max_auth_tries
    error_message = "ssh_max_auth_tries must be an integer between 1 and 100."
  }
}

variable "network_region" {
  description = "Default region for network."
  type        = string
  default     = "eu-central"

  validation {
    condition     = contains(keys(local.validation_locations_by_region), var.network_region)
    error_message = "network_region must be one of: eu-central, us-east, us-west, ap-southeast."
  }

  validation {
    condition = alltrue([
      for location in local.validation_all_locations :
      contains(lookup(local.validation_locations_by_region, var.network_region, []), location)
    ])
    error_message = "network_region must match every configured control-plane, primary-network agent, primary-network autoscaler, NAT router, and private-network load balancer location."
  }

  validation {
    condition = var.network_region == var.network_region && alltrue([
      for _, attachment_count in local.validation_network_attachment_count_by_network :
      attachment_count <= 100
    ])
    error_message = "Each Hetzner private network supports at most 100 attached resources. Reduce static nodes, autoscaler max_nodes, NAT routers, load balancers, control-plane fanout, or extra_network_ids per network."
  }
}
variable "existing_network" {
  description = "Existing Hetzner Cloud Network to use as the primary kube-hetzner network. If null, the module creates the primary Network. NOTE: make sure network_ipv4_cidr matches the existing Network IP range."
  type = object({
    id = number
  })
  default = null

  validation {
    condition     = var.existing_network == null || (var.existing_network.id > 0 && floor(var.existing_network.id) == var.existing_network.id)
    error_message = "existing_network.id must be a positive integer Hetzner Network ID."
  }
}

variable "extra_network_ids" {
  description = "Additional network IDs to attach to every control plane and agent node."
  type        = list(number)
  default     = []

  validation {
    condition = (
      length(var.extra_network_ids) == length(distinct(var.extra_network_ids)) &&
      alltrue([for network_id in var.extra_network_ids : network_id > 0 && floor(network_id) == network_id])
    )
    error_message = "extra_network_ids must contain distinct positive integer Hetzner Network IDs."
  }

  validation {
    condition     = length(var.extra_network_ids) <= 2
    error_message = "A Hetzner server can attach to at most 3 Networks; extra_network_ids can contain at most 2 additional Networks."
  }
}

variable "multinetwork_mode" {
  description = "Optional multinetwork topology mode. Use \"disabled\" for the existing single-private-network behavior. \"cilium_public_overlay\" is an experimental preview that lets Cilium span multiple Hetzner Networks over public node addresses with WireGuard encryption."
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "cilium_public_overlay"], var.multinetwork_mode)
    error_message = "multinetwork_mode must be either \"disabled\" or \"cilium_public_overlay\"."
  }

  validation {
    condition     = var.multinetwork_mode != "cilium_public_overlay" || var.enable_experimental_cilium_public_overlay
    error_message = "multinetwork_mode=\"cilium_public_overlay\" is experimental and not release-supported for production clusters yet. Set enable_experimental_cilium_public_overlay=true only for lab validation."
  }

  validation {
    condition     = var.multinetwork_mode != "cilium_public_overlay" || var.cni_plugin == "cilium"
    error_message = "multinetwork_mode=\"cilium_public_overlay\" requires cni_plugin=\"cilium\"."
  }

  validation {
    condition     = var.multinetwork_mode != "cilium_public_overlay" || var.nat_router == null
    error_message = "multinetwork_mode=\"cilium_public_overlay\" is incompatible with nat_router. Public overlay nodes need direct public transport, not private-only NAT routing."
  }

  validation {
    condition = (
      var.multinetwork_mode != "cilium_public_overlay" ||
      var.control_plane_endpoint != null
    )
    error_message = "multinetwork_mode=\"cilium_public_overlay\" requires control_plane_endpoint to be set to a Kubernetes API endpoint reachable from every configured Hetzner Network."
  }

  validation {
    condition = (
      var.multinetwork_mode != "cilium_public_overlay" ||
      !var.enable_control_plane_load_balancer ||
      var.control_plane_load_balancer_enable_public_network
    )
    error_message = "multinetwork_mode=\"cilium_public_overlay\" requires control_plane_load_balancer_enable_public_network=true when the module-managed control-plane load balancer is enabled."
  }

  validation {
    condition = (
      var.multinetwork_mode != "cilium_public_overlay" ||
      var.ingress_controller == "none" ||
      var.ingress_controller == "custom" ||
      var.enable_klipper_metal_lb ||
      var.load_balancer_enable_public_network
    )
    error_message = "multinetwork_mode=\"cilium_public_overlay\" requires public Hetzner Load Balancers for managed ingress controllers. Set load_balancer_enable_public_network=true, use a custom/no ingress controller, or use Klipper/MetalLB."
  }

  validation {
    condition = (
      var.multinetwork_mode == "disabled" ||
      var.node_transport_mode != "tailscale"
    )
    error_message = "node_transport_mode=\"tailscale\" is an alternative cross-network transport and must be used with multinetwork_mode=\"disabled\"."
  }

}

variable "enable_experimental_cilium_public_overlay" {
  description = "Explicit opt-in gate for the experimental Cilium public-overlay multinetwork preview. This mode is not production-supported until live Cilium datapath validation passes."
  type        = bool
  default     = false
}

variable "multinetwork_transport_ip_family" {
  description = "Public transport address family for the experimental cilium_public_overlay preview. IPv4 is the conservative default; IPv6 and dualstack require public IPv6 on every node."
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "ipv6", "dualstack"], var.multinetwork_transport_ip_family)
    error_message = "multinetwork_transport_ip_family must be one of: ipv4, ipv6, dualstack."
  }

  validation {
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

  validation {
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
}

variable "multinetwork_cilium_mtu" {
  description = "Cilium device MTU used by the experimental cilium_public_overlay preview. The default leaves room for Hetzner public networking plus Cilium tunnel and WireGuard overhead."
  type        = number
  default     = 1370

  validation {
    condition     = var.multinetwork_cilium_mtu >= 1280 && var.multinetwork_cilium_mtu <= 1450 && floor(var.multinetwork_cilium_mtu) == var.multinetwork_cilium_mtu
    error_message = "multinetwork_cilium_mtu must be an integer between 1280 and 1450."
  }
}

variable "multinetwork_cilium_peer_ipv4_cidrs" {
  description = "IPv4 source CIDRs allowed to reach Cilium public overlay peer ports on every node when the experimental cilium_public_overlay preview is enabled."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.multinetwork_cilium_peer_ipv4_cidrs :
      can(cidrhost(cidr, 0)) && provider::assert::ipv4(cidrhost(cidr, 0))
    ])
    error_message = "multinetwork_cilium_peer_ipv4_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "multinetwork_cilium_peer_ipv6_cidrs" {
  description = "IPv6 source CIDRs allowed to reach Cilium public overlay peer ports on every node when the experimental cilium_public_overlay preview is enabled with IPv6 or dual-stack transport."
  type        = list(string)
  default     = ["::/0"]

  validation {
    condition = alltrue([
      for cidr in var.multinetwork_cilium_peer_ipv6_cidrs :
      can(cidrhost(cidr, 0)) && provider::assert::ipv6(cidrhost(cidr, 0))
    ])
    error_message = "multinetwork_cilium_peer_ipv6_cidrs must contain valid IPv6 CIDR blocks."
  }
}

variable "node_transport_mode" {
  description = "Kubernetes node transport mode. \"hetzner_private\" keeps the classic Hetzner private Network transport. \"tailscale\" makes Tailscale the official node transport and secure Tailnet access path for single-network hardening and supported large-cluster multinetwork topologies."
  type        = string
  default     = "hetzner_private"

  validation {
    condition     = contains(["hetzner_private", "tailscale"], var.node_transport_mode)
    error_message = "node_transport_mode must be either \"hetzner_private\" or \"tailscale\"."
  }

  validation {
    condition = (
      var.node_transport_mode != "tailscale" ||
      trimspace(var.tailscale_node_transport.magicdns_domain != null ? var.tailscale_node_transport.magicdns_domain : "") != ""
    )
    error_message = "node_transport_mode=\"tailscale\" requires tailscale_node_transport.magicdns_domain so the module can build deterministic Tailnet endpoints."
  }

  validation {
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

  validation {
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

  validation {
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

  validation {
    condition = (
      var.node_transport_mode != "tailscale" ||
      var.cni_plugin != "flannel" ||
      coalesce(var.flannel_backend, "vxlan") != "host-gw"
    )
    error_message = "Tailscale node transport cannot use flannel_backend=\"host-gw\" because Tailscale is not a shared L2 network. Use VXLAN or wireguard-native."
  }

  validation {
    condition = (
      var.node_transport_mode != "tailscale" ||
      length(local.validation_tailnet_ipv4_cidr_starts_inside) == 0 &&
      length(local.validation_tailnet_ipv6_cidr_starts_inside) == 0
    )
    error_message = "Tailscale node transport cannot use cluster, service, or Hetzner network CIDRs that start inside Tailscale's reserved 100.64.0.0/10 or fd7a:115c:a1e0::/48 ranges."
  }

  validation {
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

  validation {
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

  validation {
    condition = (
      var.node_transport_mode != "tailscale" ||
      !var.enable_control_plane_load_balancer ||
      !var.control_plane_load_balancer_enable_public_network
    )
    error_message = "node_transport_mode=\"tailscale\" supports the module-managed control-plane Load Balancer only with control_plane_load_balancer_enable_public_network=false. Keep the Kubernetes API on the Tailnet/private network or use an explicit external endpoint you secure outside kube-hetzner."
  }
}

variable "tailscale_node_transport" {
  description = "Configuration for node_transport_mode=\"tailscale\". Tailscale is used as secure node transport and Tailnet access. In multinetwork topologies it advertises node-private routes; it is not a CNI and does not manage pod networking by itself."
  type = object({
    bootstrap_mode  = optional(string, "remote_exec")
    version         = optional(string, "latest")
    magicdns_domain = optional(string, null)
    hostname_mode   = optional(string, "node_name")

    auth = optional(object({
      mode                         = optional(string, "auth_key")
      advertise_tags_control_plane = optional(list(string), [])
      advertise_tags_agent         = optional(list(string), [])
      advertise_tags_autoscaler    = optional(list(string), [])
      oauth_static_nodes_ephemeral = optional(bool, false)
      oauth_autoscaler_ephemeral   = optional(bool, true)
      oauth_preauthorized          = optional(bool, true)
    }), {})

    ssh = optional(object({
      use_tailnet_for_terraform = optional(bool, true)
      enable_tailscale_ssh      = optional(bool, false)
    }), {})

    routing = optional(object({
      advertise_node_private_routes = optional(bool, true)
      advertise_additional_routes   = optional(list(string), [])
    }), {})

    kubernetes = optional(object({
      cni_mtu             = optional(number, 1280)
      kubeconfig_endpoint = optional(string, "first_control_plane_tailnet")
    }), {})

    enable_experimental_cilium = optional(bool, false)
    enable_experimental_rke2   = optional(bool, false)
  })
  default = {}

  validation {
    condition     = contains(["remote_exec", "cloud_init", "external"], var.tailscale_node_transport.bootstrap_mode)
    error_message = "tailscale_node_transport.bootstrap_mode must be one of: remote_exec, cloud_init, external."
  }

  validation {
    condition     = var.tailscale_node_transport.version == "latest" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.tailscale_node_transport.version))
    error_message = "tailscale_node_transport.version must be \"latest\" or a concrete Tailscale version such as \"1.96.4\"."
  }

  validation {
    condition     = contains(["auth_key", "oauth_client_secret", "external"], var.tailscale_node_transport.auth.mode)
    error_message = "tailscale_node_transport.auth.mode must be one of: auth_key, oauth_client_secret, external."
  }

  validation {
    condition = (
      var.tailscale_node_transport.auth.mode != "oauth_client_secret" ||
      (
        length(var.tailscale_node_transport.auth.advertise_tags_control_plane) > 0 &&
        length(var.tailscale_node_transport.auth.advertise_tags_agent) > 0 &&
        length(var.tailscale_node_transport.auth.advertise_tags_autoscaler) > 0
      )
    )
    error_message = "tailscale_node_transport.auth.mode=\"oauth_client_secret\" requires advertise_tags_control_plane, advertise_tags_agent, and advertise_tags_autoscaler because Tailscale OAuth auth keys must be tag-scoped."
  }

  validation {
    condition = (
      var.tailscale_node_transport.auth.mode == "oauth_client_secret" ||
      (
        var.tailscale_node_transport.auth.oauth_static_nodes_ephemeral == false &&
        var.tailscale_node_transport.auth.oauth_autoscaler_ephemeral == true &&
        var.tailscale_node_transport.auth.oauth_preauthorized == true
      )
    )
    error_message = "tailscale_node_transport.auth.oauth_* settings only apply when auth.mode=\"oauth_client_secret\". For auth_key mode, choose ephemeral/preapproved behavior when generating the Tailscale auth key."
  }

  validation {
    condition = alltrue([
      for tag in concat(
        var.tailscale_node_transport.auth.advertise_tags_control_plane,
        var.tailscale_node_transport.auth.advertise_tags_agent,
        var.tailscale_node_transport.auth.advertise_tags_autoscaler
      ) :
      can(regex("^tag:[A-Za-z0-9][A-Za-z0-9_-]*$", tag))
    ])
    error_message = "Tailscale advertise tags must start with tag: and contain only letters, numbers, underscores, or dashes after the prefix."
  }

  validation {
    condition     = contains(["node_name"], var.tailscale_node_transport.hostname_mode)
    error_message = "tailscale_node_transport.hostname_mode currently supports only \"node_name\"."
  }

  validation {
    condition     = var.tailscale_node_transport.kubernetes.cni_mtu >= 1180 && var.tailscale_node_transport.kubernetes.cni_mtu <= 1400 && floor(var.tailscale_node_transport.kubernetes.cni_mtu) == var.tailscale_node_transport.kubernetes.cni_mtu
    error_message = "tailscale_node_transport.kubernetes.cni_mtu must be an integer between 1180 and 1400."
  }

  validation {
    condition     = contains(["first_control_plane_tailnet", "explicit"], var.tailscale_node_transport.kubernetes.kubeconfig_endpoint)
    error_message = "tailscale_node_transport.kubernetes.kubeconfig_endpoint must be either \"first_control_plane_tailnet\" or \"explicit\"."
  }

  validation {
    condition = (
      var.tailscale_node_transport.kubernetes.kubeconfig_endpoint != "explicit" ||
      trimspace(var.kubeconfig_server_address) != ""
    )
    error_message = "tailscale_node_transport.kubernetes.kubeconfig_endpoint=\"explicit\" requires kubeconfig_server_address."
  }

  validation {
    condition = alltrue([
      for cidr in var.tailscale_node_transport.routing.advertise_additional_routes :
      can(cidrhost(cidr, 0))
    ])
    error_message = "tailscale_node_transport.routing.advertise_additional_routes must contain valid CIDR blocks."
  }
}

variable "tailscale_auth_key" {
  description = "Sensitive default Tailscale auth key used when node_transport_mode=\"tailscale\" and tailscale_node_transport.auth.mode=\"auth_key\". Role-specific keys override it. If this key is used by more than one node it must be reusable; single-use keys only register the first node. In cloud_init mode this is rendered into hcloud user_data and, for autoscaler nodes, a Kubernetes Secret."
  type        = string
  default     = null
  sensitive   = true
}

variable "tailscale_control_plane_auth_key" {
  description = "Optional control-plane-specific Tailscale auth key. Use this when static control-plane nodes need a different Tailscale key policy than agents or autoscaler-created nodes. It must be reusable if it is shared by multiple control-plane nodes."
  type        = string
  default     = null
  sensitive   = true
}

variable "tailscale_agent_auth_key" {
  description = "Optional static-agent-specific Tailscale auth key. Use this when static agents need a different Tailscale key policy than control planes or autoscaler-created nodes. It must be reusable if it is shared by multiple static agents."
  type        = string
  default     = null
  sensitive   = true
}

variable "tailscale_autoscaler_auth_key" {
  description = "Optional autoscaler-specific Tailscale auth key. Prefer a reusable, pre-approved, tagged, ephemeral key for autoscaler nodes so deleted machines do not linger in the tailnet."
  type        = string
  default     = null
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Sensitive Tailscale OAuth client secret used when node_transport_mode=\"tailscale\" and tailscale_node_transport.auth.mode=\"oauth_client_secret\". The module appends role-specific OAuth auth-key parameters for static and autoscaler nodes. In cloud_init mode this is rendered into hcloud user_data and, for autoscaler nodes, a Kubernetes Secret."
  type        = string
  default     = null
  sensitive   = true
}

variable "network_ipv4_cidr" {
  description = "The main network cidr that all subnets will be created upon."
  type        = string
  default     = "10.0.0.0/8"

  validation {
    condition = (
      can(cidrhost(var.network_ipv4_cidr, 0)) &&
      provider::assert::ipv4(cidrhost(var.network_ipv4_cidr, 0)) &&
      (
        can(regex("^10\\.", cidrhost(var.network_ipv4_cidr, 0))) ||
        can(regex("^172\\.(1[6-9]|2[0-9]|3[0-1])\\.", cidrhost(var.network_ipv4_cidr, 0))) ||
        can(regex("^192\\.168\\.", cidrhost(var.network_ipv4_cidr, 0)))
      )
    )
    error_message = "network_ipv4_cidr must be a valid RFC1918 IPv4 CIDR."
  }
}

variable "network_subnet_mode" {
  description = "Subnet allocation mode for the primary private network. Use \"per_nodepool\" to allocate dedicated subnets per control-plane and agent nodepool. Use \"shared\" to allocate one shared agent subnet from the start of the CIDR and one shared control-plane subnet from the end."
  type        = string
  default     = "per_nodepool"
  validation {
    condition     = contains(["per_nodepool", "shared"], var.network_subnet_mode)
    error_message = "network_subnet_mode must be either \"per_nodepool\" or \"shared\"."
  }
}

variable "subnet_count" {
  description = "The amount of subnets into which the network will be split. Must be a power of 2."
  type        = number
  default     = 256
  validation {
    condition     = var.subnet_count > 0 ? floor(log(var.subnet_count, 2)) == log(var.subnet_count, 2) : false
    error_message = "Subnet amount must be a power of 2."
  }
  validation {
    condition     = var.subnet_count > 0
    error_message = "Subnet amount must be greater than 0."
  }
  validation {
    # Host bits = 32 - prefix, must have enough bits to create subnet_count subnets
    condition     = can(cidrhost(var.network_ipv4_cidr, 0)) ? pow(2, 32 - tonumber(split("/", var.network_ipv4_cidr)[1])) >= var.subnet_count : true
    error_message = "The network CIDR is too small for the requested subnet amount. Reduce subnet_count or use a larger network."
  }
  validation {
    condition = var.subnet_count >= (
      (
        var.network_subnet_mode == "per_nodepool"
        ? length(var.control_plane_nodepools) + length(var.agent_nodepools)
        : 2
      ) + (var.nat_router == null ? 0 : (try(var.nat_router.enable_redundancy, false) ? 2 : 1))
    )
    error_message = "Subnet amount is too small for the selected network_subnet_mode and NAT router settings."
  }
}

variable "cluster_ipv4_cidr" {
  description = "Internal Pod CIDR, used for the controller and currently for calico/cilium."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition = (
      trimspace(var.cluster_ipv4_cidr) == "" ||
      provider::assert::cidrv4(var.cluster_ipv4_cidr)
    )
    error_message = "cluster_ipv4_cidr must be empty or a valid IPv4 CIDR."
  }
}

variable "service_ipv4_cidr" {
  description = "Internal Service CIDR, used for the controller and currently for calico/cilium."
  type        = string
  default     = "10.43.0.0/16"

  validation {
    condition = (
      trimspace(var.service_ipv4_cidr) == "" ||
      provider::assert::cidrv4(var.service_ipv4_cidr)
    )
    error_message = "service_ipv4_cidr must be empty or a valid IPv4 CIDR."
  }

  validation {
    condition     = (trimspace(var.service_ipv4_cidr) == "") == (trimspace(var.cluster_ipv4_cidr) == "")
    error_message = "cluster_ipv4_cidr and service_ipv4_cidr must both be set for IPv4 networking, or both be empty for IPv6-only networking."
  }

  validation {
    condition = (
      trimspace(var.service_ipv4_cidr) == "" ||
      trimspace(var.cluster_ipv4_cidr) == "" ||
      trimspace(var.service_ipv4_cidr) != trimspace(var.cluster_ipv4_cidr)
    )
    error_message = "cluster_ipv4_cidr and service_ipv4_cidr must not be identical."
  }
}

variable "cluster_ipv6_cidr" {
  description = "Internal Pod IPv6 CIDR. Set together with service_ipv6_cidr to enable dual-stack or IPv6-only cluster networking."
  type        = string
  default     = null

  validation {
    condition = (
      try(trimspace(var.cluster_ipv6_cidr), "") == "" ||
      provider::assert::cidrv6(var.cluster_ipv6_cidr)
    )
    error_message = "cluster_ipv6_cidr must be null, empty, or a valid IPv6 CIDR."
  }

  validation {
    condition = (
      (try(trimspace(var.cluster_ipv6_cidr), "") == "") ==
      (try(trimspace(var.service_ipv6_cidr), "") == "")
    )
    error_message = "cluster_ipv6_cidr and service_ipv6_cidr must be set together for dual-stack or IPv6-only networking."
  }

  validation {
    condition     = try(trimspace(var.cluster_ipv6_cidr), "") == "" || var.cni_plugin == "cilium"
    error_message = "IPv6 and dual-stack pod/service CIDRs are currently supported only with cni_plugin = \"cilium\"."
  }

  validation {
    condition = (
      try(trimspace(var.cluster_ipv6_cidr), "") == "" ||
      try(trimspace(var.service_ipv6_cidr), "") == "" ||
      trimspace(var.cluster_ipv6_cidr) != trimspace(var.service_ipv6_cidr)
    )
    error_message = "cluster_ipv6_cidr and service_ipv6_cidr must not be identical."
  }

  validation {
    condition = (
      trimspace(var.cluster_ipv4_cidr) != "" ||
      try(trimspace(var.cluster_ipv6_cidr), "") != ""
    )
    error_message = "At least one pod/service IP family must be enabled. Keep IPv4 CIDRs set, or set both IPv6 CIDRs for IPv6-only mode."
  }
}

variable "service_ipv6_cidr" {
  description = "Internal Service IPv6 CIDR. Set together with cluster_ipv6_cidr to enable dual-stack or IPv6-only cluster networking."
  type        = string
  default     = null

  validation {
    condition = (
      try(trimspace(var.service_ipv6_cidr), "") == "" ||
      provider::assert::cidrv6(var.service_ipv6_cidr)
    )
    error_message = "service_ipv6_cidr must be null, empty, or a valid IPv6 CIDR."
  }

}

variable "cluster_dns_ipv4" {
  description = "Internal Service IPv4 address of core-dns."
  type        = string
  default     = null

  validation {
    condition = (
      var.cluster_dns_ipv4 == null ||
      (
        provider::assert::ipv4(var.cluster_dns_ipv4) &&
        trimspace(var.service_ipv4_cidr) != ""
      )
    )
    error_message = "cluster_dns_ipv4 must be a valid IPv4 address and requires service_ipv4_cidr to be enabled."
  }
}

variable "kubernetes_api_port" {
  description = "Kubernetes API server port used for k3s control-plane listeners, load balancer listeners, firewall rules, and default join endpoints. RKE2 currently requires the default 6443 API port; RKE2 node registration still uses supervisor port 9345."
  type        = number
  default     = 6443

  validation {
    condition     = var.kubernetes_api_port >= 1 && var.kubernetes_api_port <= 65535
    error_message = "kubernetes_api_port must be between 1 and 65535."
  }

  validation {
    condition     = var.kubernetes_distribution != "rke2" || var.kubernetes_api_port == 6443
    error_message = "RKE2 currently requires kubernetes_api_port = 6443. RKE2 node registration uses supervisor port 9345, and RKE2 does not expose a supported https-listen-port equivalent for changing the Kubernetes API listener."
  }
}


variable "nat_router" {
  description = "Do you want to pipe all egress through a single nat router which is to be constructed? Note: Requires enable_control_plane_load_balancer=true unless node_transport_mode=\"tailscale\" provides the API/kubeconfig path through the tailnet. Automatically forwards kubernetes_api_port to the control plane LB when control_plane_load_balancer_enable_public_network=false. extra_runcmd commands run as root after NAT router cloud-init completes and rerun when the command list changes."
  nullable    = true
  default     = null
  type = object({
    server_type       = string
    location          = string
    labels            = optional(map(string), {})
    enable_sudo       = optional(bool, false)
    enable_redundancy = optional(bool, false)
    standby_location  = optional(string, "")
    extra_runcmd      = optional(list(string), [])
  })

  validation {
    condition     = var.nat_router == null || !try(var.nat_router.enable_redundancy, false) || try(var.nat_router.standby_location, "") != ""
    error_message = "When nat_router.enable_redundancy is true, standby_location must be provided."
  }

  validation {
    condition     = var.nat_router == null || var.enable_control_plane_load_balancer || var.node_transport_mode == "tailscale"
    error_message = "When nat_router is enabled, enable_control_plane_load_balancer must be set to true unless node_transport_mode=\"tailscale\" provides the API/kubeconfig path through the tailnet."
  }

  validation {
    condition = (
      var.nat_router == null ||
      var.node_transport_mode != "tailscale" ||
      var.ingress_controller == "none" ||
      var.ingress_controller == "custom" ||
      var.enable_klipper_metal_lb
    )
    error_message = "nat_router with node_transport_mode=\"tailscale\" makes Terraform-managed nodes private-only. Use Klipper/MetalLB, ingress_controller=\"custom\"/\"none\", or an external load balancer instead of managed Hetzner ingress."
  }
}

variable "use_private_nat_router_bastion" {
  type        = bool
  default     = false
  description = "Use the NAT router's private IP as the SSH bastion instead of its public IP. Requires the operator to have network-level access to the private network (for example Tailscale, Cloudflare Tunnel, WireGuard VPN, etc). Cloudflare here is an external access path, not kube-hetzner-managed node transport."

  validation {
    condition     = !var.use_private_nat_router_bastion || var.nat_router != null
    error_message = "use_private_nat_router_bastion requires nat_router to be configured."
  }
}

variable "nat_router_hcloud_token" {
  description = "API Token used by the nat-router to change ip assignment when nat_router.enable_redundancy is true."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.nat_router == null || !try(var.nat_router.enable_redundancy, false) || var.nat_router_hcloud_token != ""
    error_message = "When nat_router.enable_redundancy is true, nat_router_hcloud_token must be provided."
  }
}

variable "optional_bastion_host" {
  description = "Optional bastion host used to connect to cluster nodes. Useful when using a pre-existing NAT router."
  type = object({
    bastion_host        = string
    bastion_port        = number
    bastion_user        = string
    bastion_private_key = string
  })
  sensitive = true
  default   = null

  validation {
    condition = var.optional_bastion_host == null || (
      trimspace(var.optional_bastion_host.bastion_host) != "" &&
      trimspace(var.optional_bastion_host.bastion_user) != "" &&
      trimspace(var.optional_bastion_host.bastion_private_key) != "" &&
      var.optional_bastion_host.bastion_port >= 1 &&
      var.optional_bastion_host.bastion_port <= 65535 &&
      floor(var.optional_bastion_host.bastion_port) == var.optional_bastion_host.bastion_port
    )
    error_message = "optional_bastion_host requires non-empty host/user/private key and an integer bastion_port between 1 and 65535."
  }
}

variable "nat_router_subnet_index" {
  type        = number
  default     = 200
  description = "Subnet index for NAT router. Default 200 is safe for most deployments. Must not conflict with control plane (counting down from 255) or agent pools (counting up from 0)."

  validation {
    condition     = var.nat_router_subnet_index >= 0 && var.nat_router_subnet_index < var.subnet_count
    error_message = "NAT router subnet index must be between 0 and subnet_count."
  }

  validation {
    condition     = var.nat_router == null || !contains(local.validation_reserved_primary_network_subnet_indexes, var.nat_router_subnet_index)
    error_message = "nat_router_subnet_index must not collide with control-plane or agent subnet indexes."
  }

  validation {
    condition = (
      var.nat_router == null ||
      length(distinct(concat(
        local.validation_reserved_primary_network_subnet_indexes,
        [var.nat_router_subnet_index]
      ))) <= 50
    )
    error_message = "Hetzner Cloud Networks support at most 50 subnets. Disable NAT router subnet creation or reduce primary-network subnet allocations."
  }
}

variable "vswitch_subnet_index" {
  type        = number
  default     = 201
  description = "Subnet index (0-255) for vSwitch. Default 201 is safe for most deployments. Must not conflict with control plane (counting down from 255) or agent pools (counting up from 0)."

  validation {
    condition     = var.vswitch_subnet_index >= 0 && var.vswitch_subnet_index < var.subnet_count
    error_message = "vSwitch subnet index must be between 0 and subnet_count."
  }

  validation {
    condition     = var.vswitch_id == null || var.vswitch_subnet_index != var.nat_router_subnet_index || var.nat_router == null
    error_message = "vswitch_subnet_index must not equal nat_router_subnet_index when both vSwitch and nat_router are enabled."
  }

  validation {
    condition     = var.vswitch_id == null || !contains(local.validation_reserved_primary_network_subnet_indexes, var.vswitch_subnet_index)
    error_message = "vswitch_subnet_index must not collide with control-plane or agent subnet indexes."
  }

  validation {
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
}

variable "vswitch_id" {
  description = "Hetzner Cloud vSwitch ID. If defined, a subnet will be created in the IP-range defined by vswitch_subnet_index. The vSwitch must exist before this module is called."
  type        = number
  default     = null

  validation {
    condition     = var.vswitch_id == null || (var.vswitch_id > 0 && floor(var.vswitch_id) == var.vswitch_id)
    error_message = "vswitch_id must be null or a positive integer Hetzner vSwitch ID."
  }

  validation {
    condition     = var.vswitch_id == null || var.network_region == "eu-central"
    error_message = "Hetzner Cloud vSwitch coupling is supported only in network_region = \"eu-central\"."
  }
}

variable "expose_routes_to_vswitch" {
  description = "Expose primary Network routes to the coupled Robot vSwitch when vswitch_id is set and kube-hetzner manages the primary Network. Existing Networks must enable this outside the module."
  type        = bool
  default     = true

  validation {
    condition = (
      !var.expose_routes_to_vswitch ||
      var.vswitch_id == null ||
      var.existing_network == null
    )
    error_message = "expose_routes_to_vswitch can only be managed when kube-hetzner creates the primary Network. For existing_network, enable route exposure on that Network manually or set expose_routes_to_vswitch=false."
  }
}

variable "extra_robot_nodes" {
  description = "Optional existing Hetzner Robot nodes to configure as additional k3s agents through the vSwitch subnet."
  type = list(object({
    host            = string
    private_ipv4    = string
    vlan_id         = number
    interface       = optional(string, "enp6s0")
    mtu             = optional(number, 1350)
    ssh_user        = optional(string, "root")
    ssh_port        = optional(number, 22)
    ssh_private_key = optional(string, null)
    routes          = optional(list(string), ["10.0.0.0/8"])
    labels          = optional(list(string), ["instance.hetzner.cloud/provided-by=robot"])
    taints          = optional(list(string), [])
    flannel_iface   = optional(string, null)
  }))
  default = []

  validation {
    condition = alltrue([
      for node in var.extra_robot_nodes :
      trimspace(node.host) != "" && trimspace(node.private_ipv4) != ""
    ])
    error_message = "Each extra_robot_nodes entry requires non-empty host and private_ipv4 values."
  }

  validation {
    condition = alltrue([
      for node in var.extra_robot_nodes :
      can(cidrhost("${node.private_ipv4}/32", 0))
    ])
    error_message = "Each extra_robot_nodes.private_ipv4 must be a valid IPv4 address."
  }

  validation {
    condition = alltrue([
      for node in var.extra_robot_nodes :
      node.mtu >= 576 && node.mtu <= 9000
    ])
    error_message = "Each extra_robot_nodes.mtu must be between 576 and 9000."
  }

  validation {
    condition = alltrue([
      for node in var.extra_robot_nodes :
      node.vlan_id >= 1 && node.vlan_id <= 4094 && floor(node.vlan_id) == node.vlan_id
    ])
    error_message = "Each extra_robot_nodes.vlan_id must be an integer between 1 and 4094."
  }

  validation {
    condition = alltrue([
      for node in var.extra_robot_nodes :
      node.ssh_port >= 1 && node.ssh_port <= 65535 && floor(node.ssh_port) == node.ssh_port
    ])
    error_message = "Each extra_robot_nodes.ssh_port must be an integer between 1 and 65535."
  }

  validation {
    condition = alltrue([
      for node in var.extra_robot_nodes :
      trimspace(node.interface) != "" && trimspace(node.ssh_user) != ""
    ])
    error_message = "Each extra_robot_nodes interface and ssh_user must be non-empty."
  }

  validation {
    condition     = length(var.extra_robot_nodes) == 0 || var.vswitch_id != null
    error_message = "extra_robot_nodes requires vswitch_id so Robot nodes have a Cloud Network vSwitch subnet to join."
  }

  validation {
    condition     = length(var.extra_robot_nodes) == 0 || var.kubernetes_distribution == "k3s"
    error_message = "extra_robot_nodes currently supports only kubernetes_distribution = \"k3s\"."
  }

  validation {
    condition = alltrue(flatten([
      for node in var.extra_robot_nodes : [
        for route in node.routes :
        can(cidrhost(route, 0)) && provider::assert::ipv4(cidrhost(route, 0))
      ]
    ]))
    error_message = "Each extra_robot_nodes.routes entry must be a valid IPv4 CIDR."
  }
}

variable "load_balancer_location" {
  description = "Default load balancer location."
  type        = string
  default     = "nbg1"

  validation {
    condition     = contains(flatten(values(local.validation_locations_by_region)), var.load_balancer_location)
    error_message = "load_balancer_location must be one of the supported Hetzner Cloud locations: fsn1, hel1, nbg1, ash, hil, sin."
  }
}

variable "load_balancer_type" {
  description = "Default load balancer server type."
  type        = string
  default     = "lb11"

  validation {
    condition     = can(regex("^lb[1-9][0-9]*$", var.load_balancer_type))
    error_message = "load_balancer_type must be a Hetzner Load Balancer type such as lb11, lb21, or lb31."
  }
}

variable "load_balancer_enable_ipv6" {
  description = "Enable IPv6 for the ingress load balancer."
  type        = bool
  default     = true
}

variable "load_balancer_enable_public_network" {
  description = "Enable the public network of the ingress load balancer."
  type        = bool
  default     = true
}

variable "load_balancer_algorithm_type" {
  description = "Specifies the algorithm type of the load balancer."
  type        = string
  default     = "round_robin"

  validation {
    condition     = contains(["round_robin", "least_connections"], var.load_balancer_algorithm_type)
    error_message = "load_balancer_algorithm_type must be either \"round_robin\" or \"least_connections\"."
  }
}

variable "load_balancer_health_check_interval" {
  description = "Specifies the interval at which a health check is performed. Minimum is 3s."
  type        = string
  default     = "15s"

  validation {
    condition = (
      can(regex("^[0-9]+s$", var.load_balancer_health_check_interval)) &&
      tonumber(trimsuffix(var.load_balancer_health_check_interval, "s")) >= 3
    )
    error_message = "load_balancer_health_check_interval must be a duration in seconds with a minimum of 3s, for example \"15s\"."
  }
}

variable "load_balancer_health_check_timeout" {
  description = "Specifies the timeout of a single health check. Must not be greater than the health check interval. Minimum is 1s."
  type        = string
  default     = "10s"

  validation {
    condition = (
      can(regex("^[0-9]+s$", var.load_balancer_health_check_timeout)) &&
      can(regex("^[0-9]+s$", var.load_balancer_health_check_interval)) &&
      tonumber(trimsuffix(var.load_balancer_health_check_timeout, "s")) >= 1 &&
      tonumber(trimsuffix(var.load_balancer_health_check_timeout, "s")) <= tonumber(trimsuffix(var.load_balancer_health_check_interval, "s"))
    )
    error_message = "load_balancer_health_check_timeout must be a duration in seconds, at least 1s, and not greater than load_balancer_health_check_interval."
  }
}

variable "load_balancer_health_check_retries" {
  description = "Specifies the number of times a health check is retried before a target is marked as unhealthy."
  type        = number
  default     = 3

  validation {
    condition     = var.load_balancer_health_check_retries >= 1 && floor(var.load_balancer_health_check_retries) == var.load_balancer_health_check_retries
    error_message = "load_balancer_health_check_retries must be a positive integer."
  }
}

variable "enable_load_balancer_monitoring" {
  description = "Enable ServiceMonitor and PrometheusRule resources for Hetzner CCM load balancer metrics. Requires Prometheus Operator CRDs."
  type        = bool
  default     = false
}

variable "exclude_agents_from_external_load_balancers" {
  description = "Add node.kubernetes.io/exclude-from-external-load-balancers=true label to agent nodes. Enable this if you use both the Terraform-managed ingress LB and CCM-managed LoadBalancer services, and want to prevent double-registration of agents to the CCM LBs. Note: This excludes agents from ALL CCM-managed LoadBalancer services, not just ingress."
  type        = bool
  default     = false

  validation {
    condition = (
      !var.exclude_agents_from_external_load_balancers ||
      var.allow_scheduling_on_control_plane ||
      local.validation_is_single_node_cluster
    )
    error_message = "exclude_agents_from_external_load_balancers=true with allow_scheduling_on_control_plane=false leaves no eligible targets for CCM-managed LoadBalancer services unless this is a single-node cluster."
  }
}

variable "primary_ip_pool" {
  type = object({
    enable_ipv4 = optional(bool, false)
    enable_ipv6 = optional(bool, false)
    auto_delete = optional(bool, false)
  })
  default     = {}
  description = "Module-managed Primary IP pool settings. When enabled, kube-hetzner creates and assigns one Primary IP per node for the selected IP families."

  validation {
    condition     = !var.primary_ip_pool.auto_delete || var.primary_ip_pool.enable_ipv4 || var.primary_ip_pool.enable_ipv6
    error_message = "primary_ip_pool.auto_delete has an effect only when enable_ipv4 or enable_ipv6 is true."
  }
}

variable "control_plane_nodepools" {
  description = "Number of control plane nodes."
  type = list(object({
    name                  = string
    server_type           = string
    location              = string
    backups               = optional(bool)
    floating_ip           = optional(bool, false)
    floating_ip_id        = optional(number, null)
    labels                = list(string)
    hcloud_labels         = optional(map(string), {})
    taints                = list(string)
    count                 = optional(number, null)
    append_random_suffix  = optional(bool, true)
    swap_size             = optional(string, "")
    zram_size             = optional(string, "")
    kubelet_args          = optional(list(string), ["kube-reserved=cpu=250m,memory=1500Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    selinux               = optional(bool, true)
    placement_group_index = optional(number, 0)
    placement_group       = optional(string, null)
    os                    = optional(string)
    os_snapshot_id        = optional(string, null)
    enable_public_ipv4    = optional(bool, true)
    enable_public_ipv6    = optional(bool, true)
    primary_ipv4_id       = optional(number, null)
    primary_ipv6_id       = optional(number, null)
    keep_disk             = optional(bool)
    join_endpoint_type    = optional(string, "private")
    extra_write_files     = optional(list(any), [])
    extra_runcmd          = optional(list(any), [])
    attached_volumes = optional(list(object({
      size              = number
      mount_path        = string
      filesystem        = optional(string, "ext4")
      automount         = optional(bool, true)
      name              = optional(string, null)
      labels            = optional(map(string), {})
      delete_protection = optional(bool, null)
    })), [])
    nodes = optional(map(object({
      server_type           = optional(string)
      location              = optional(string)
      backups               = optional(bool)
      floating_ip           = optional(bool)
      floating_ip_id        = optional(number, null)
      labels                = optional(list(string))
      hcloud_labels         = optional(map(string), {})
      taints                = optional(list(string))
      append_random_suffix  = optional(bool)
      swap_size             = optional(string, "")
      zram_size             = optional(string, "")
      kubelet_args          = optional(list(string), ["kube-reserved=cpu=250m,memory=1500Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
      selinux               = optional(bool, true)
      placement_group_index = optional(number, null)
      placement_group       = optional(string, null)
      os                    = optional(string)
      os_snapshot_id        = optional(string, null)
      enable_public_ipv4    = optional(bool)
      enable_public_ipv6    = optional(bool)
      primary_ipv4_id       = optional(number, null)
      primary_ipv6_id       = optional(number, null)
      keep_disk             = optional(bool)
      join_endpoint_type    = optional(string, null)
      extra_write_files     = optional(list(any), [])
      extra_runcmd          = optional(list(any), [])
      attached_volumes = optional(list(object({
        size              = number
        mount_path        = string
        filesystem        = optional(string, "ext4")
        automount         = optional(bool, true)
        name              = optional(string, null)
        labels            = optional(map(string), {})
        delete_protection = optional(bool, null)
      })), [])
    })))
  }))
  default = []
  validation {
    condition = length(
      [for control_plane_nodepool in var.control_plane_nodepools : control_plane_nodepool.name]
      ) == length(
      distinct(
        [for control_plane_nodepool in var.control_plane_nodepools : control_plane_nodepool.name]
      )
    )
    error_message = "Names in control_plane_nodepools must be unique."
  }

  validation {
    condition = alltrue([
      for control_plane_nodepool in var.control_plane_nodepools :
      control_plane_nodepool.os == null || control_plane_nodepool.os == "microos" || control_plane_nodepool.os == "leapmicro"
    ])
    error_message = "The os must be either 'microos' or 'leapmicro'."
  }

  validation {
    condition = alltrue([
      for control_plane_nodepool in var.control_plane_nodepools :
      alltrue([
        for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
        control_plane_node.os == null || control_plane_node.os == "microos" || control_plane_node.os == "leapmicro"
      ])
    ])
    error_message = "The node os must be either 'microos' or 'leapmicro'."
  }

  validation {
    condition = alltrue([
      for control_plane_nodepool in var.control_plane_nodepools :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", control_plane_nodepool.name))
    ])
    error_message = "Names in control_plane_nodepools must use lowercase alphanumeric characters and dashes, and must not start or end with a dash."
  }

  validation {
    condition = (
      var.network_subnet_mode != "per_nodepool" ||
      length(var.control_plane_nodepools) + length(var.agent_nodepools) <= 50
    )
    error_message = "network_subnet_mode = \"per_nodepool\" creates one subnet per control-plane and agent nodepool, but Hetzner Cloud Networks support at most 50 subnets."
  }

  validation {
    condition     = alltrue([for control_plane_nodepool in var.control_plane_nodepools : (control_plane_nodepool.count == null) != (control_plane_nodepool.nodes == null)])
    error_message = "Set either nodes or count per control_plane_nodepool, not both."
  }

  validation {
    condition = alltrue([
      for control_plane_nodepool in var.control_plane_nodepools :
      control_plane_nodepool.count == null || (
        control_plane_nodepool.count >= 0 &&
        control_plane_nodepool.count == floor(control_plane_nodepool.count)
      )
    ])
    error_message = "Each control_plane_nodepool count must be a non-negative integer."
  }

  validation {
    condition = alltrue([for control_plane_nodepool in var.control_plane_nodepools :
      alltrue([for control_plane_key, _ in coalesce(control_plane_nodepool.nodes, {}) : can(tonumber(control_plane_key)) && tonumber(control_plane_key) == floor(tonumber(control_plane_key)) && 0 <= tonumber(control_plane_key) && tonumber(control_plane_key) < 154])
    ])
    # 154 because the private ip is derived from tonumber(key) + 101. See private_ipv4 in control_planes.tf
    error_message = "The key for each individual control plane node in a nodepool must be a stable integer in the range [0, 153] cast as a string."
  }

  validation {
    condition     = length(var.control_plane_nodepools) > 0
    error_message = "At least one control plane nodepool is required. Kubernetes cannot run without control plane nodes."
  }
  validation {
    condition     = length(var.control_plane_nodepools) == 0 || sum([for v in var.control_plane_nodepools : length(coalesce(v.nodes, {})) + coalesce(v.count, 0)]) >= 1
    error_message = "At least one control plane node is required (total count across all control_plane_nodepools must be >= 1)."
  }

  validation {
    condition = (
      (length(var.control_plane_nodepools) == 0 ? 0 : sum([
        for control_plane_nodepool in var.control_plane_nodepools :
        length(coalesce(control_plane_nodepool.nodes, {})) + coalesce(control_plane_nodepool.count, 0)
      ])) == 1 ||
      (length(var.control_plane_nodepools) == 0 ? 0 : sum([
        for control_plane_nodepool in var.control_plane_nodepools :
        length(coalesce(control_plane_nodepool.nodes, {})) + coalesce(control_plane_nodepool.count, 0)
      ])) % 2 == 1
    )
    error_message = "Control plane node count must be 1 or an odd number for etcd quorum safety."
  }

  validation {
    condition = alltrue([
      for control_plane_nodepool in var.control_plane_nodepools :
      contains(["private", "public"], control_plane_nodepool.join_endpoint_type) &&
      alltrue([
        for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
        control_plane_node.join_endpoint_type == null || contains(["private", "public"], control_plane_node.join_endpoint_type)
      ])
    ])
    error_message = "control_plane_nodepools join_endpoint_type must be either \"private\" or \"public\"."
  }

  validation {
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

  validation {
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

  validation {
    condition = alltrue([
      for control_plane_nodepool in var.control_plane_nodepools :
      (control_plane_nodepool.primary_ipv4_id == null || (control_plane_nodepool.enable_public_ipv4 && control_plane_nodepool.primary_ipv4_id > 0)) &&
      (control_plane_nodepool.primary_ipv6_id == null || (control_plane_nodepool.enable_public_ipv6 && control_plane_nodepool.primary_ipv6_id > 0)) &&
      alltrue([
        for _, control_plane_node in coalesce(control_plane_nodepool.nodes, {}) :
        (
          control_plane_node.primary_ipv4_id == null ||
          (coalesce(control_plane_node.enable_public_ipv4, control_plane_nodepool.enable_public_ipv4) && control_plane_node.primary_ipv4_id > 0)
          ) && (
          control_plane_node.primary_ipv6_id == null ||
          (coalesce(control_plane_node.enable_public_ipv6, control_plane_nodepool.enable_public_ipv6) && control_plane_node.primary_ipv6_id > 0)
        )
      ])
    ])
    error_message = "primary_ipv4_id/primary_ipv6_id values must be positive and require the matching public IP family to be enabled."
  }

  validation {
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

  validation {
    condition = alltrue([
      for control_plane_nodepool in var.control_plane_nodepools :
      (
        control_plane_nodepool.placement_group == null ||
        control_plane_nodepool.count == null ||
        control_plane_nodepool.count <= 10
      )
    ])
    error_message = "A Hetzner spread placement group supports at most 10 servers. Split count-based control-plane nodepools with an explicit placement_group into groups of 10 or fewer."
  }

  validation {
    condition = alltrue(flatten([
      for np in var.control_plane_nodepools : [
        for vol in coalesce(np.attached_volumes, []) : (
          vol.size >= 10 &&
          vol.size <= 10240 &&
          contains(["ext4", "xfs"], vol.filesystem) &&
          can(regex("^/var/[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$", vol.mount_path)) &&
          !contains(split("/", vol.mount_path), "..") &&
          !contains(split("/", vol.mount_path), ".")
        )
      ]
    ]))
    error_message = "Each attached_volumes entry in control_plane_nodepools must have size between 10 and 10240 GB, filesystem in [ext4,xfs], and a mount_path under /var without '.' or '..'."
  }

  validation {
    condition = alltrue(flatten([
      for np in var.control_plane_nodepools : concat(
        [
          can(regex("^$|[1-9][0-9]{0,3}(G|M)$", np.swap_size)),
          can(regex("^$|[1-9][0-9]{0,3}(G|M)$", np.zram_size))
        ],
        flatten([
          for node in values(coalesce(np.nodes, {})) : [
            can(regex("^$|[1-9][0-9]{0,3}(G|M)$", node.swap_size)),
            can(regex("^$|[1-9][0-9]{0,3}(G|M)$", node.zram_size))
          ]
        ])
      )
    ]))
    error_message = "control_plane_nodepools swap_size and zram_size must be empty or match sizes like 512M, 1G, or 32G."
  }
}

variable "agent_nodepools" {
  description = "Number of agent nodes."
  type = list(object({
    name                  = string
    server_type           = string
    location              = string
    backups               = optional(bool)
    floating_ip           = optional(bool)
    floating_ip_type      = optional(string, "ipv4")
    floating_ip_id        = optional(number, null)
    floating_ip_rdns      = optional(string, null)
    labels                = list(string)
    hcloud_labels         = optional(map(string), {})
    taints                = list(string)
    longhorn_volume_size  = optional(number)
    longhorn_mount_path   = optional(string, "/var/longhorn")
    append_random_suffix  = optional(bool, true)
    swap_size             = optional(string, "")
    zram_size             = optional(string, "")
    kubelet_args          = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    selinux               = optional(bool, true)
    placement_group_index = optional(number, 0)
    placement_group       = optional(string, null)
    subnet_ip_range       = optional(string, null)
    os                    = optional(string)
    os_snapshot_id        = optional(string, null)
    count                 = optional(number, null)
    enable_public_ipv4    = optional(bool, true)
    enable_public_ipv6    = optional(bool, true)
    primary_ipv4_id       = optional(number, null)
    primary_ipv6_id       = optional(number, null)
    network_id            = optional(number, null)
    keep_disk             = optional(bool)
    join_endpoint_type    = optional(string, "private")
    extra_write_files     = optional(list(any), [])
    extra_runcmd          = optional(list(any), [])
    attached_volumes = optional(list(object({
      size              = number
      mount_path        = string
      filesystem        = optional(string, "ext4")
      automount         = optional(bool, true)
      name              = optional(string, null)
      labels            = optional(map(string), {})
      delete_protection = optional(bool, null)
    })), [])
    nodes = optional(map(object({
      server_type               = optional(string)
      location                  = optional(string)
      backups                   = optional(bool)
      floating_ip               = optional(bool)
      floating_ip_type          = optional(string, null)
      floating_ip_id            = optional(number, null)
      floating_ip_rdns          = optional(string, null)
      labels                    = optional(list(string))
      hcloud_labels             = optional(map(string), {})
      taints                    = optional(list(string))
      longhorn_volume_size      = optional(number)
      longhorn_mount_path       = optional(string, null)
      append_random_suffix      = optional(bool)
      swap_size                 = optional(string, "")
      zram_size                 = optional(string, "")
      kubelet_args              = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
      selinux                   = optional(bool, true)
      placement_group_index     = optional(number, null)
      placement_group           = optional(string, null)
      append_index_to_node_name = optional(bool, true)
      os                        = optional(string)
      os_snapshot_id            = optional(string, null)
      enable_public_ipv4        = optional(bool)
      enable_public_ipv6        = optional(bool)
      primary_ipv4_id           = optional(number, null)
      primary_ipv6_id           = optional(number, null)
      network_id                = optional(number)
      keep_disk                 = optional(bool)
      join_endpoint_type        = optional(string, null)
      extra_write_files         = optional(list(any), [])
      extra_runcmd              = optional(list(any), [])
      attached_volumes = optional(list(object({
        size              = number
        mount_path        = string
        filesystem        = optional(string, "ext4")
        automount         = optional(bool, true)
        name              = optional(string, null)
        labels            = optional(map(string), {})
        delete_protection = optional(bool, null)
      })), [])
    })))
  }))
  default = []

  validation {
    condition = length(
      [for agent_nodepool in var.agent_nodepools : agent_nodepool.name]
      ) == length(
      distinct(
        [for agent_nodepool in var.agent_nodepools : agent_nodepool.name]
      )
    )
    error_message = "Names in agent_nodepools must be unique."
  }

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      agent_nodepool.os == null || agent_nodepool.os == "microos" || agent_nodepool.os == "leapmicro"
    ])
    error_message = <<-EOF
    Invalid 'os' value at the nodepool level. The 'os' for each 'agent_nodepool' must be either 'microos' or 'leapmicro'.
    Please correct the nodepool 'os' value.
    EOF
  }

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      alltrue([
        for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
        agent_node.os == null || agent_node.os == "microos" || agent_node.os == "leapmicro"
      ])
    ])
    error_message = <<-EOF
    Invalid 'os' value at the node level. Each node's 'os' within a nodepool must be either 'microos', 'leapmicro', or unset.
    Please correct any invalid node 'os' values.
    EOF
  }

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", agent_nodepool.name))
    ])
    error_message = "Names in agent_nodepools must use lowercase alphanumeric characters and dashes, and must not start or end with a dash."
  }

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      contains(["ipv4", "ipv6"], coalesce(agent_nodepool.floating_ip_type, "ipv4")) &&
      alltrue([
        for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
        agent_node.floating_ip_type == null || contains(["ipv4", "ipv6"], agent_node.floating_ip_type)
      ])
    ])
    error_message = "floating_ip_type must be either \"ipv4\" or \"ipv6\" at nodepool and node level."
  }

  validation {
    condition     = alltrue([for agent_nodepool in var.agent_nodepools : (agent_nodepool.count == null) != (agent_nodepool.nodes == null)])
    error_message = "Set either nodes or count per agent_nodepool, not both."
  }

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      agent_nodepool.count == null || (
        agent_nodepool.count >= 0 &&
        agent_nodepool.count == floor(agent_nodepool.count)
      )
    ])
    error_message = "Each agent_nodepool count must be a non-negative integer."
  }

  validation {
    condition = alltrue([for agent_nodepool in var.agent_nodepools :
      alltrue([for agent_key, agent_node in coalesce(agent_nodepool.nodes, {}) : can(tonumber(agent_key)) && tonumber(agent_key) == floor(tonumber(agent_key)) && 0 <= tonumber(agent_key) && tonumber(agent_key) < 154])
    ])
    # 154 because the private ip is derived from tonumber(key) + 101. See private_ipv4 in agents.tf
    error_message = "The key for each individual node in a nodepool must be a stable integer in the range [0, 153] cast as a string."
  }

  validation {
    condition = alltrue([
      for network_id in distinct([for agent_nodepool in var.agent_nodepools : coalesce(agent_nodepool.network_id, 0)]) :
      sum([
        for agent_nodepool in var.agent_nodepools :
        coalesce(agent_nodepool.network_id, 0) == network_id ? (length(coalesce(agent_nodepool.nodes, {})) + coalesce(agent_nodepool.count, 0)) : 0
      ]) <= 100
    ])
    error_message = "Each Hetzner private network supports at most 100 attached servers. Use different network_id values to spread larger clusters."
  }

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      (agent_nodepool.network_id == null || (agent_nodepool.network_id > 0 && floor(agent_nodepool.network_id) == agent_nodepool.network_id)) &&
      alltrue([
        for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
        agent_node.network_id == null || (agent_node.network_id > 0 && floor(agent_node.network_id) == agent_node.network_id)
      ])
    ])
    error_message = "agent_nodepools network_id values must be null/omitted for the primary kube-hetzner network or positive integer Hetzner Network IDs."
  }

  validation {
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

  validation {
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

  validation {
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

  validation {
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

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      contains(["private", "public"], agent_nodepool.join_endpoint_type) &&
      alltrue([
        for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
        agent_node.join_endpoint_type == null || contains(["private", "public"], agent_node.join_endpoint_type)
      ])
    ])
    error_message = "agent_nodepools join_endpoint_type must be either \"private\" or \"public\"."
  }

  validation {
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

  validation {
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

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      (agent_nodepool.primary_ipv4_id == null || (agent_nodepool.enable_public_ipv4 && agent_nodepool.primary_ipv4_id > 0)) &&
      (agent_nodepool.primary_ipv6_id == null || (agent_nodepool.enable_public_ipv6 && agent_nodepool.primary_ipv6_id > 0)) &&
      alltrue([
        for _, agent_node in coalesce(agent_nodepool.nodes, {}) :
        (
          agent_node.primary_ipv4_id == null ||
          (coalesce(agent_node.enable_public_ipv4, agent_nodepool.enable_public_ipv4) && agent_node.primary_ipv4_id > 0)
          ) && (
          agent_node.primary_ipv6_id == null ||
          (coalesce(agent_node.enable_public_ipv6, agent_nodepool.enable_public_ipv6) && agent_node.primary_ipv6_id > 0)
        )
      ])
    ])
    error_message = "primary_ipv4_id/primary_ipv6_id values must be positive and require the matching public IP family to be enabled."
  }

  validation {
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

  validation {
    condition = alltrue([
      for agent_nodepool in var.agent_nodepools :
      (
        agent_nodepool.placement_group == null ||
        agent_nodepool.count == null ||
        agent_nodepool.count <= 10
      )
    ])
    error_message = "A Hetzner spread placement group supports at most 10 servers. Split count-based agent nodepools with an explicit placement_group into groups of 10 or fewer."
  }

  validation {
    condition = alltrue(flatten([
      for np in var.agent_nodepools : concat(
        [
          can(regex("^/var/[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$", np.longhorn_mount_path)) &&
          !contains(split("/", np.longhorn_mount_path), "..") &&
          !contains(split("/", np.longhorn_mount_path), ".")
        ],
        [
          for node in values(coalesce(np.nodes, {})) : (
            node.longhorn_mount_path == null || (
              can(regex("^/var/[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$", node.longhorn_mount_path)) &&
              !contains(split("/", node.longhorn_mount_path), "..") &&
              !contains(split("/", node.longhorn_mount_path), ".")
            )
          )
        ]
      )
    ]))
    error_message = "Each longhorn_mount_path must be a valid, absolute path within a subdirectory of '/var/', not contain '.' or '..' components, and not end with a slash. This applies to both nodepool-level and node-level settings."
  }

  validation {
    condition = alltrue([
      for np in var.agent_nodepools : (
        (
          coalesce(np.floating_ip, false) ?
          (coalesce(np.floating_ip_type, "ipv4") == "ipv4" ? np.enable_public_ipv4 : np.enable_public_ipv6)
          : true
        ) &&
        alltrue([
          for _, node in coalesce(np.nodes, {}) : (
            coalesce(node.floating_ip, np.floating_ip, false) ?
            (
              coalesce(node.floating_ip_type, np.floating_ip_type, "ipv4") == "ipv4" ?
              coalesce(node.enable_public_ipv4, np.enable_public_ipv4) :
              coalesce(node.enable_public_ipv6, np.enable_public_ipv6)
            )
            : true
          )
        ])
      )
    ])
    error_message = "floating_ip_type requires the matching public IP family to be enabled on the nodepool."
  }

  validation {
    condition = alltrue(flatten([
      for np in var.agent_nodepools : concat(
        [
          np.longhorn_volume_size == null || (np.longhorn_volume_size >= 10 && np.longhorn_volume_size <= 10240)
        ],
        [
          for node in values(coalesce(np.nodes, {})) :
          node.longhorn_volume_size == null || (node.longhorn_volume_size >= 10 && node.longhorn_volume_size <= 10240)
        ]
      )
    ]))
    error_message = "longhorn_volume_size must be null or between 10 and 10240 GB at nodepool and node level."
  }

  validation {
    condition = alltrue(flatten([
      for np in var.agent_nodepools : concat(
        [
          can(regex("^$|[1-9][0-9]{0,3}(G|M)$", np.swap_size)),
          can(regex("^$|[1-9][0-9]{0,3}(G|M)$", np.zram_size))
        ],
        flatten([
          for node in values(coalesce(np.nodes, {})) : [
            can(regex("^$|[1-9][0-9]{0,3}(G|M)$", node.swap_size)),
            can(regex("^$|[1-9][0-9]{0,3}(G|M)$", node.zram_size))
          ]
        ])
      )
    ]))
    error_message = "agent_nodepools swap_size and zram_size must be empty or match sizes like 512M, 1G, or 32G."
  }

  validation {
    condition = alltrue(flatten([
      for np in var.agent_nodepools : concat(
        [
          for vol in coalesce(np.attached_volumes, []) : (
            vol.size >= 10 &&
            vol.size <= 10240 &&
            contains(["ext4", "xfs"], vol.filesystem) &&
            can(regex("^/var/[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$", vol.mount_path)) &&
            !contains(split("/", vol.mount_path), "..") &&
            !contains(split("/", vol.mount_path), ".")
          )
        ],
        flatten([
          for node in values(coalesce(np.nodes, {})) : [
            for vol in coalesce(node.attached_volumes, []) : (
              vol.size >= 10 &&
              vol.size <= 10240 &&
              contains(["ext4", "xfs"], vol.filesystem) &&
              can(regex("^/var/[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*$", vol.mount_path)) &&
              !contains(split("/", vol.mount_path), "..") &&
              !contains(split("/", vol.mount_path), ".")
            )
          ]
        ])
      )
    ]))
    error_message = "Each attached_volumes entry in agent_nodepools must have size between 10 and 10240 GB, filesystem in [ext4,xfs], and a mount_path under /var without '.' or '..'."
  }

}

variable "cluster_autoscaler_image" {
  type        = string
  default     = "registry.k8s.io/autoscaling/cluster-autoscaler"
  description = "Image of Kubernetes Cluster Autoscaler for Hetzner Cloud to be used."
}

variable "cluster_autoscaler_version" {
  type        = string
  default     = "v1.33.3"
  description = "Version of Kubernetes Cluster Autoscaler for Hetzner Cloud. Should be aligned with Kubernetes version. Available versions for the official image can be found at https://explore.ggcr.dev/?repo=registry.k8s.io%2Fautoscaling%2Fcluster-autoscaler."
}

variable "cluster_autoscaler_log_level" {
  description = "Verbosity level of the logs for cluster-autoscaler"
  type        = number
  default     = 4

  validation {
    condition     = var.cluster_autoscaler_log_level >= 0 && var.cluster_autoscaler_log_level <= 5
    error_message = "The log level must be between 0 and 5."
  }
}

variable "cluster_autoscaler_log_to_stderr" {
  description = "Determines whether to log to stderr or not"
  type        = bool
  default     = true
}

variable "cluster_autoscaler_stderr_threshold" {
  description = "Severity level above which logs are sent to stderr instead of stdout"
  type        = string
  default     = "INFO"

  validation {
    condition     = var.cluster_autoscaler_stderr_threshold == "INFO" || var.cluster_autoscaler_stderr_threshold == "WARNING" || var.cluster_autoscaler_stderr_threshold == "ERROR" || var.cluster_autoscaler_stderr_threshold == "FATAL"
    error_message = "The stderr threshold must be one of the following: INFO, WARNING, ERROR, FATAL."
  }
}

variable "cluster_autoscaler_extra_args" {
  type        = list(string)
  default     = []
  description = "Extra arguments for the Cluster Autoscaler deployment."

  validation {
    condition = alltrue([
      for arg in var.cluster_autoscaler_extra_args :
      !startswith(arg, "--v=") &&
      !startswith(arg, "--logtostderr") &&
      !startswith(arg, "--stderrthreshold") &&
      !startswith(arg, "--cloud-provider") &&
      !startswith(arg, "--nodes") &&
      !startswith(arg, "--leader-elect-resource-name") &&
      !startswith(arg, "--status-config-map-name")
    ])
    error_message = "cluster_autoscaler_extra_args must not include arguments managed by the module: --v, --logtostderr, --stderrthreshold, --cloud-provider, --nodes, --leader-elect-resource-name, or --status-config-map-name."
  }
}

variable "cluster_autoscaler_tolerations" {
  description = "Additional tolerations to append to the cluster-autoscaler deployment."
  type = list(object({
    key               = optional(string)
    operator          = optional(string)
    value             = optional(string)
    effect            = optional(string)
    tolerationSeconds = optional(number)
  }))
  default = []
}

variable "cluster_autoscaler_server_creation_timeout" {
  type        = number
  default     = 15
  description = "Timeout (in minutes) until which a newly created server/node has to become available before giving up and destroying it."
}

variable "cluster_autoscaler_replicas" {
  type        = number
  default     = 1
  description = "Number of replicas for the cluster autoscaler deployment. Multiple replicas use leader election for HA."

  validation {
    condition     = var.cluster_autoscaler_replicas >= 1 && floor(var.cluster_autoscaler_replicas) == var.cluster_autoscaler_replicas
    error_message = "Number of cluster autoscaler replicas must be a positive integer."
  }
}

variable "cluster_autoscaler_resource_limits" {
  type        = bool
  default     = true
  description = "Should cluster autoscaler enable default resource requests and limits. Default values are requests: 10m & 64Mi and limits: 100m & 300Mi."
}

variable "cluster_autoscaler_resource_values" {
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "10m"
      memory = "64Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "300Mi"
    }
  }
  description = "Requests and limits for Cluster Autoscaler."
}

variable "cluster_autoscaler_metrics_firewall_source" {
  type        = list(string)
  default     = []
  description = "Optional source CIDRs allowed to scrape cluster-autoscaler metrics through NodePort 30085 (maps to pod port 8085)."

  validation {
    condition = alltrue([
      for source in var.cluster_autoscaler_metrics_firewall_source :
      source == var.myipv4_ref || can(cidrhost(source, 0))
    ])
    error_message = "cluster_autoscaler_metrics_firewall_source entries must be CIDR blocks or the myipv4_ref placeholder."
  }
}

variable "autoscaler_nodepools" {
  description = "Cluster autoscaler nodepools."
  type = list(object({
    name               = string
    server_type        = string
    location           = string
    min_nodes          = number
    max_nodes          = number
    labels             = optional(map(string), {})
    server_labels      = optional(map(string), {})
    kubelet_args       = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    os                 = optional(string)
    network_id         = optional(number, null)
    subnet_ip_range    = optional(string, null)
    join_endpoint_type = optional(string, null)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    swap_size = optional(string, "")
    zram_size = optional(string, "")
  }))
  default = []

  validation {
    condition = alltrue([
      for autoscaler_nodepool in var.autoscaler_nodepools :
      autoscaler_nodepool.os == null || autoscaler_nodepool.os == "microos" || autoscaler_nodepool.os == "leapmicro"
    ])
    error_message = <<-EOF
    Invalid 'os' value at the autoscaler nodepool level. The 'os' for each 'autoscaler_nodepool' must be either 'microos' or 'leapmicro'.
    Please correct the autoscaler nodepool 'os' value.
    EOF
  }

  validation {
    condition = (
      var.node_transport_mode != "tailscale" ||
      length(var.autoscaler_nodepools) == 0 ||
      var.tailscale_node_transport.bootstrap_mode == "cloud_init"
    )
    error_message = "Tailscale node transport with autoscaler_nodepools requires tailscale_node_transport.bootstrap_mode=\"cloud_init\" because autoscaler-created nodes cannot be configured by Terraform remote-exec before joining."
  }

  validation {
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

  validation {
    condition = (
      length(compact([
        for autoscaler_nodepool in var.autoscaler_nodepools : autoscaler_nodepool.os
      ])) == 0 ||
      length(compact([
        for autoscaler_nodepool in var.autoscaler_nodepools : autoscaler_nodepool.os
      ])) == length(var.autoscaler_nodepools)
    )
    error_message = "Set os explicitly on every autoscaler_nodepool, or omit os on every autoscaler_nodepool so the module can choose one effective OS."
  }

  validation {
    condition = length(distinct(compact([
      for autoscaler_nodepool in var.autoscaler_nodepools : autoscaler_nodepool.os
    ]))) <= 1
    error_message = "All autoscaler_nodepools with explicit os must use the same value."
  }

  validation {
    condition = length(
      [for autoscaler_nodepool in var.autoscaler_nodepools : autoscaler_nodepool.name]
      ) == length(
      distinct(
        [for autoscaler_nodepool in var.autoscaler_nodepools : autoscaler_nodepool.name]
      )
    )
    error_message = "Names in autoscaler_nodepools must be unique."
  }

  validation {
    condition = alltrue([
      for autoscaler_nodepool in var.autoscaler_nodepools :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", autoscaler_nodepool.name))
    ])
    error_message = "Names in autoscaler_nodepools must use lowercase alphanumeric characters and dashes, and must not start or end with a dash."
  }

  validation {
    condition = alltrue([
      for autoscaler_nodepool in var.autoscaler_nodepools :
      autoscaler_nodepool.min_nodes >= 0 &&
      autoscaler_nodepool.max_nodes >= 0 &&
      autoscaler_nodepool.min_nodes == floor(autoscaler_nodepool.min_nodes) &&
      autoscaler_nodepool.max_nodes == floor(autoscaler_nodepool.max_nodes) &&
      autoscaler_nodepool.min_nodes <= autoscaler_nodepool.max_nodes
    ])
    error_message = "Each autoscaler_nodepool must define non-negative integer min_nodes/max_nodes with min_nodes <= max_nodes."
  }

  validation {
    condition = alltrue(flatten([
      for autoscaler_nodepool in var.autoscaler_nodepools : [
        for autoscaler_taint in autoscaler_nodepool.taints :
        contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], autoscaler_taint.effect)
      ]
    ]))
    error_message = "Each autoscaler taint effect must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }

  validation {
    condition = alltrue([
      for autoscaler_nodepool in var.autoscaler_nodepools :
      can(regex("^$|[1-9][0-9]{0,3}(G|M)$", autoscaler_nodepool.swap_size))
    ])
    error_message = "Each autoscaler_nodepool swap_size must be empty or match sizes like 512M, 1G, or 32G."
  }

  validation {
    condition = alltrue([
      for autoscaler_nodepool in var.autoscaler_nodepools :
      can(regex("^$|[1-9][0-9]{0,3}(G|M)$", autoscaler_nodepool.zram_size))
    ])
    error_message = "Each autoscaler_nodepool zram_size must be empty or match sizes like 512M, 1G, or 32G."
  }

  validation {
    condition = alltrue([
      for autoscaler_nodepool in var.autoscaler_nodepools :
      autoscaler_nodepool.network_id == null || (autoscaler_nodepool.network_id > 0 && floor(autoscaler_nodepool.network_id) == autoscaler_nodepool.network_id)
    ])
    error_message = "autoscaler_nodepools network_id values must be null/omitted for the primary kube-hetzner network or positive integer Hetzner Network IDs."
  }

  validation {
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

  validation {
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

  validation {
    condition = alltrue([
      for autoscaler_nodepool in var.autoscaler_nodepools :
      autoscaler_nodepool.subnet_ip_range == null || (
        can(cidrhost(autoscaler_nodepool.subnet_ip_range, 0)) &&
        provider::assert::ipv4(cidrhost(autoscaler_nodepool.subnet_ip_range, 0))
      )
    ])
    error_message = "autoscaler_nodepools subnet_ip_range must be null or a valid IPv4 CIDR block inside the selected Hetzner private Network."
  }

  validation {
    condition = alltrue([
      for autoscaler_nodepool in var.autoscaler_nodepools :
      autoscaler_nodepool.join_endpoint_type == null || contains(["private", "public"], autoscaler_nodepool.join_endpoint_type)
    ])
    error_message = "autoscaler_nodepools join_endpoint_type must be null, \"private\", or \"public\"."
  }

  validation {
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

  validation {
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

  validation {
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
}

variable "autoscaler_enable_public_ipv4" {
  description = "Enable public IPv4 on nodes created by the Cluster Autoscaler."
  type        = bool
  default     = true
}

variable "autoscaler_enable_public_ipv6" {
  description = "Enable public IPv6 on nodes created by the Cluster Autoscaler."
  type        = bool
  default     = true

  validation {
    condition     = var.autoscaler_enable_public_ipv4 || var.autoscaler_enable_public_ipv6 || var.nat_router != null || var.optional_bastion_host != null || var.control_plane_endpoint != null || var.enable_control_plane_load_balancer
    error_message = "Disabling both public IPv4 and IPv6 on autoscaler nodes requires a configured private access/join path such as nat_router, optional_bastion_host, control_plane_endpoint, or enable_control_plane_load_balancer."
  }

  validation {
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
}

variable "hetzner_ccm_version" {
  type        = string
  default     = null
  description = "Version of Kubernetes Cloud Controller Manager for Hetzner Cloud. See https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases for the available versions."
}

variable "hetzner_csi_version" {
  type        = string
  default     = null
  description = "Version of Container Storage Interface driver for Hetzner Cloud. See https://github.com/hetznercloud/csi-driver/releases for the available versions."
}

variable "hetzner_csi_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to hetzner csi as 'valuesContent' at the HelmChart."
}

variable "hetzner_csi_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or hetzner_csi_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.hetzner_csi_merge_values == "" || can(yamldecode(var.hetzner_csi_merge_values))
    error_message = "hetzner_csi_merge_values must be valid YAML format or empty string."
  }
}


variable "restrict_outbound_traffic" {
  type        = bool
  default     = true
  description = "Whether or not to restrict the outbound traffic."
}

variable "enable_klipper_metal_lb" {
  type        = bool
  default     = false
  description = "Use klipper load balancer."
}

variable "etcd_s3_backup" {
  description = "Etcd cluster state backup to S3 storage"
  type        = map(any)
  sensitive   = true
  default     = {}

  validation {
    condition = length(keys(var.etcd_s3_backup)) == 0 || alltrue([
      for key in [
        "etcd-s3-endpoint",
        "etcd-s3-access-key",
        "etcd-s3-secret-key",
        "etcd-s3-bucket"
      ] :
      trimspace(tostring(lookup(var.etcd_s3_backup, key, ""))) != ""
    ])
    error_message = "etcd_s3_backup requires non-empty etcd-s3-endpoint, etcd-s3-access-key, etcd-s3-secret-key, and etcd-s3-bucket values when enabled."
  }
}

variable "enable_secrets_encryption" {
  description = "Enable API server EncryptionConfiguration for Kubernetes Secrets at rest."
  type        = bool
  default     = false
}

variable "ingress_controller" {
  type        = string
  default     = "traefik"
  description = "The name of the ingress controller."

  validation {
    condition     = contains(["traefik", "nginx", "haproxy", "none", "custom"], var.ingress_controller)
    error_message = "Must be one of \"traefik\" or \"nginx\" or \"haproxy\" or \"none\" or \"custom\""
  }
}

variable "ingress_replica_count" {
  type        = number
  default     = 0
  description = "Number of replicas per ingress controller. 0 means autodetect based on the number of agent nodes."

  validation {
    condition     = var.ingress_replica_count >= 0
    error_message = "Number of ingress replicas can't be below 0."
  }
}

variable "ingress_max_replica_count" {
  type        = number
  default     = 10
  description = "Number of maximum replicas per ingress controller. Used for ingress HPA. Must be higher than number of replicas."

  validation {
    condition     = var.ingress_max_replica_count >= 0
    error_message = "Number of ingress maximum replicas can't be below 0."
  }

  validation {
    condition     = var.ingress_replica_count == 0 || var.ingress_max_replica_count >= var.ingress_replica_count
    error_message = "ingress_max_replica_count must be greater than or equal to ingress_replica_count when ingress_replica_count is explicit."
  }
}

variable "traefik_image_tag" {
  type        = string
  default     = ""
  description = "Traefik image tag. Useful to use the beta version for new features. Example: v3.0.0-beta5"
}

variable "traefik_autoscaling" {
  type        = bool
  default     = true
  description = "Should traefik enable Horizontal Pod Autoscaler."
}

variable "traefik_redirect_to_https" {
  type        = bool
  default     = true
  description = "Should traefik redirect http traffic to https."
}

variable "traefik_pod_disruption_budget" {
  type        = bool
  default     = true
  description = "Should traefik enable pod disruption budget. Default values are maxUnavailable: 33% and minAvailable: 1."
}

variable "traefik_provider_kubernetes_gateway_enabled" {
  type        = bool
  default     = false
  description = "Should traefik enable the kubernetes gateway provider. Default is false."

  validation {
    condition     = !var.traefik_provider_kubernetes_gateway_enabled || var.ingress_controller == "traefik"
    error_message = "traefik_provider_kubernetes_gateway_enabled requires ingress_controller = \"traefik\"."
  }

  validation {
    condition     = !(var.traefik_provider_kubernetes_gateway_enabled && var.cilium_gateway_api_enabled)
    error_message = "Choose either traefik_provider_kubernetes_gateway_enabled or cilium_gateway_api_enabled, not both. They install separate Gateway API controllers."
  }
}

variable "traefik_resource_limits" {
  type        = bool
  default     = true
  description = "Should traefik enable default resource requests and limits. Default values are requests: 100m & 50Mi and limits: 300m & 150Mi."
}

variable "traefik_resource_values" {
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      memory = "50Mi"
      cpu    = "100m"
    }
    limits = {
      memory = "150Mi"
      cpu    = "300m"
    }
  }
  description = "Requests and limits for Traefik."
}

variable "traefik_additional_ports" {
  type = list(object({
    name        = string
    port        = number
    exposedPort = number
    protocol    = optional(string, "TCP")
  }))
  default     = []
  description = "Additional ports to pass to Traefik. These are the ones that go into the ports section of the Traefik helm values file."

  validation {
    condition = alltrue([
      for option in var.traefik_additional_ports :
      contains(["TCP", "UDP"], upper(option.protocol))
    ])
    error_message = "Each traefik_additional_ports item must set protocol to either TCP or UDP."
  }
}

variable "traefik_additional_options" {
  type        = list(string)
  default     = []
  description = "Additional options to pass to Traefik as a list of strings. These are the ones that go into the additionalArguments section of the Traefik helm values file."
}

variable "traefik_additional_trusted_ips" {
  type        = list(string)
  default     = []
  description = "Additional Trusted IPs to pass to Traefik. These are the ones that go into the trustedIPs section of the Traefik helm values file."

  validation {
    condition = alltrue([
      for source in var.traefik_additional_trusted_ips :
      can(cidrhost(source, 0))
    ])
    error_message = "traefik_additional_trusted_ips entries must be valid CIDR blocks."
  }
}

variable "traefik_version" {
  type        = string
  default     = ""
  description = "Version of Traefik helm chart. See https://github.com/traefik/traefik-helm-chart/releases for the available versions."
}

variable "traefik_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Traefik as 'valuesContent' at the HelmChart."
}

variable "traefik_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or traefik_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.traefik_merge_values == "" || can(yamldecode(var.traefik_merge_values))
    error_message = "traefik_merge_values must be valid YAML format or empty string."
  }
}

variable "nginx_version" {
  type        = string
  default     = ""
  description = "Version of Nginx helm chart. See https://github.com/kubernetes/ingress-nginx?tab=readme-ov-file#supported-versions-table for the available versions."
}

variable "nginx_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to nginx as 'valuesContent' at the HelmChart."
}

variable "nginx_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or nginx_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.nginx_merge_values == "" || can(yamldecode(var.nginx_merge_values))
    error_message = "nginx_merge_values must be valid YAML format or empty string."
  }
}

variable "haproxy_requests_cpu" {
  type        = string
  default     = "250m"
  description = "Setting for HAProxy controller.resources.requests.cpu"
}

variable "haproxy_requests_memory" {
  type        = string
  default     = "400Mi"
  description = "Setting for HAProxy controller.resources.requests.memory"
}

variable "haproxy_additional_proxy_protocol_ips" {
  type        = list(string)
  default     = []
  description = "Additional trusted proxy protocol IPs to pass to haproxy."

  validation {
    condition = alltrue([
      for source in var.haproxy_additional_proxy_protocol_ips :
      can(cidrhost(source, 0))
    ])
    error_message = "haproxy_additional_proxy_protocol_ips entries must be valid CIDR blocks."
  }
}

variable "haproxy_version" {
  type        = string
  default     = ""
  description = "Version of HAProxy helm chart."
}

variable "haproxy_values" {
  type        = string
  default     = ""
  description = "Helm values file to pass to haproxy as 'valuesContent' at the HelmChart, overriding the default."
}

variable "haproxy_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or haproxy_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.haproxy_merge_values == "" || can(yamldecode(var.haproxy_merge_values))
    error_message = "haproxy_merge_values must be valid YAML format or empty string."
  }
}

variable "allow_scheduling_on_control_plane" {
  type        = bool
  default     = false
  description = "Whether to allow non-control-plane workloads to run on the control-plane nodes."
}

variable "enable_metrics_server" {
  type        = bool
  default     = true
  description = "Whether to enable or disable k3s metric server."
}

variable "k3s_channel" {
  type        = string
  default     = "stable" # Please update kube.tf.example too when changing this variable
  description = "Allows you to specify an initial k3s channel. Use stable, latest, or testing for live channel installs; use k3s_version for exact Kubernetes minor pinning. See https://update.k3s.io/v1-release/channels for available channels."

  validation {
    condition     = contains(["stable", "latest", "testing", "v1.16", "v1.17", "v1.18", "v1.19", "v1.20", "v1.21", "v1.22", "v1.23", "v1.24", "v1.25", "v1.26", "v1.27", "v1.28", "v1.29", "v1.30", "v1.31", "v1.32", "v1.33", "v1.34", "v1.35"], var.k3s_channel)
    error_message = "The initial k3s channel must be one of stable, latest or testing, or any of the minor kube versions like v1.26."
  }

  validation {
    condition = (
      var.k3s_version != "" ||
      contains(["stable", "latest", "testing"], var.k3s_channel)
    )
    error_message = "When k3s_version is empty, k3s_channel must be stable, latest, or testing. Use k3s_version for exact Kubernetes minor pinning because Rancher minor release channels are not reliable live installer targets."
  }
}

variable "k3s_version" {
  type        = string
  default     = ""
  description = "Allows you to specify the k3s version (Example: v1.29.6+k3s2). Supersedes k3s_channel. See https://github.com/k3s-io/k3s/releases for available versions."
}

variable "rke2_channel" {
  type        = string
  default     = "v1.32" # Please update kube.tf.example too when changing this variable
  description = "Allows you to specify an initial rke2 channel. Use stable, latest, or testing when rke2_version is empty; use rke2_version for exact Kubernetes minor pinning. See https://update.rke2.io/v1-release/channels for available channels."

  validation {
    condition     = contains(["stable", "latest", "testing", "v1.18", "v1.19", "v1.20", "v1.21", "v1.22", "v1.23", "v1.24", "v1.25", "v1.26", "v1.27", "v1.28", "v1.29", "v1.30", "v1.31", "v1.32", "v1.33", "v1.34", "v1.35"], var.rke2_channel)
    error_message = "The initial rke2 channel must be one of stable, latest or testing, or any of the minor kube versions like v1.31."
  }

  validation {
    condition = (
      var.rke2_version != "" ||
      contains(["stable", "latest", "testing"], var.rke2_channel)
    )
    error_message = "When rke2_version is empty, rke2_channel must be stable, latest, or testing. Use rke2_version for exact Kubernetes minor pinning because Rancher minor release channels are not reliable live installer targets."
  }
}

variable "rke2_version" {
  type        = string
  default     = "v1.32.5+rke2r1"
  description = "Allows you to specify the rke2 version (Example: v1.32.5+rke2r1). Supersedes rke2_channel. See https://github.com/rancher/rke2/releases for available versions."
}

variable "system_upgrade_enable_eviction" {
  type        = bool
  default     = true
  description = "Whether to directly delete pods during system upgrade (k3s) or evict them. Defaults to true. Disable this on small clusters to avoid system upgrades hanging since pods resisting eviction keep node unschedulable forever. NOTE: turning this off, introduces potential downtime of services of the upgraded nodes."
}

variable "system_upgrade_use_drain" {
  type        = bool
  default     = true
  description = "Wether using drain (true, the default), which will deletes and transfers all pods to other nodes before a node is being upgraded, or cordon (false), which just prevents schedulung new pods on the node during upgrade and keeps all pods running"
}

variable "automatically_upgrade_kubernetes" {
  type        = bool
  default     = true
  description = "Whether to automatically upgrade k3s based on the selected channel."
}

variable "system_upgrade_schedule_window" {
  type = object({
    days      = optional(list(string), [])
    startTime = optional(string, "")
    endTime   = optional(string, "")
    timeZone  = optional(string, "UTC")
  })
  default     = null
  description = "Schedule window for k3s automated upgrades (system-upgrade-controller v0.15.0+). When set, upgrade jobs will only be created within the specified time window. 'days' accepts lowercase day names (e.g. [\"monday\",\"tuesday\"]). 'startTime'/'endTime' use HH:MM format. 'timeZone' defaults to UTC. See https://docs.k3s.io/upgrades/automated#scheduling-upgrades"

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : (
      length(try(var.system_upgrade_schedule_window.days, [])) > 0 ||
      (try(var.system_upgrade_schedule_window.startTime, null) != null ? try(var.system_upgrade_schedule_window.startTime, "") : "") != "" ||
      (try(var.system_upgrade_schedule_window.endTime, null) != null ? try(var.system_upgrade_schedule_window.endTime, "") : "") != ""
    )
    error_message = "system_upgrade_schedule_window must have at least one of 'days', 'startTime', or 'endTime' set when not null."
  }

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : alltrue([
      for day in try(var.system_upgrade_schedule_window.days, []) :
      can(regex("^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$", day))
    ])
    error_message = "system_upgrade_schedule_window.days must contain lowercase day names (monday-sunday)."
  }

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : alltrue([
      for time_value in [
        try(var.system_upgrade_schedule_window.startTime, null) != null ? try(var.system_upgrade_schedule_window.startTime, "") : "",
        try(var.system_upgrade_schedule_window.endTime, null) != null ? try(var.system_upgrade_schedule_window.endTime, "") : ""
      ] :
      time_value == "" || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", time_value))
    ])
    error_message = "system_upgrade_schedule_window.startTime and endTime must use 24-hour HH:MM format when set."
  }

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : (
      (try(var.system_upgrade_schedule_window.timeZone, null) != null ? try(var.system_upgrade_schedule_window.timeZone, "") : "") == "" ||
      can(regex("^[A-Za-z_]+(?:/[A-Za-z0-9_+\\-]+)*$", try(var.system_upgrade_schedule_window.timeZone, null) != null ? try(var.system_upgrade_schedule_window.timeZone, "") : ""))
    )
    error_message = "system_upgrade_schedule_window.timeZone must be a valid IANA timezone name (for example, UTC or Europe/Budapest)."
  }

  validation {
    condition = var.system_upgrade_schedule_window == null ? true : (
      try(provider::semvers::compare(trimprefix(var.system_upgrade_controller_version, "v"), "0.15.0"), -1) >= 0
    )
    error_message = "system_upgrade_schedule_window requires system_upgrade_controller_version v0.15.0 or newer."
  }
}

variable "automatically_upgrade_os" {
  type        = bool
  default     = true
  description = "Whether to enable or disable automatic os updates. Defaults to true. Should be disabled for single-node clusters"
}

variable "extra_firewall_rules" {
  type        = list(any)
  default     = []
  description = "Additional firewall rules to apply to the cluster."

  validation {
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
}

variable "firewall_kube_api_source" {
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
  description = "Source networks that have Kube API access to the servers. WARNING: the 'myipv4' placeholder (auto-detected via icanhazip.com) can return an incorrect IP behind VPNs, proxies, CDNs, or CI/CD runners, silently locking you out. We recommend deploying with open access first, then tightening to your known CIDRs after the cluster is up."

  validation {
    condition = var.firewall_kube_api_source == null || alltrue([
      for source in var.firewall_kube_api_source :
      source == var.myipv4_ref || can(cidrhost(source, 0))
    ])
    error_message = "firewall_kube_api_source must be null or a list of CIDR blocks/myipv4_ref placeholders."
  }
}

variable "firewall_ssh_source" {
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
  description = "Source networks that have SSH access to the servers. WARNING: the 'myipv4' placeholder (auto-detected via icanhazip.com) can return an incorrect IP behind VPNs, proxies, CDNs, or CI/CD runners, causing provisioning to hang indefinitely. We recommend deploying with open access first, then tightening to your known CIDRs after the cluster is up."

  validation {
    condition = var.firewall_ssh_source == null || alltrue([
      for source in var.firewall_ssh_source :
      source == var.myipv4_ref || can(cidrhost(source, 0))
    ])
    error_message = "firewall_ssh_source must be null or a list of CIDR blocks/myipv4_ref placeholders."
  }
}

variable "extra_firewall_ids" {
  type        = list(number)
  default     = []
  description = "Additional firewall IDs to attach to every control plane and agent node."
}

variable "myipv4_ref" {
  type        = string
  default     = "myipv4"
  description = "Placeholder string that can be used in firewall source/destination IP lists and will be replaced by the apply runner's public IPv4 /32."

  validation {
    condition     = trimspace(var.myipv4_ref) != ""
    error_message = "myipv4_ref must be a non-empty placeholder string."
  }
}

variable "use_cluster_name_in_node_name" {
  type        = bool
  default     = true
  description = "Whether to use the cluster name in the node name."
}

variable "cluster_name" {
  type        = string
  default     = "k3s"
  description = "Name of the cluster."

  validation {
    condition     = can(regex("^[a-z0-9\\-]+$", var.cluster_name))
    error_message = "The cluster name must be in the form of lowercase alphanumeric characters and/or dashes."
  }
}

variable "base_domain" {
  type        = string
  default     = ""
  description = "Base domain of the cluster, used for reverse dns."

  validation {
    condition     = can(regex("^(?:(?:(?:[A-Za-z0-9])|(?:[A-Za-z0-9](?:[A-Za-z0-9\\-]+)?[A-Za-z0-9]))+(\\.))+([A-Za-z]{2,})([\\/?])?([\\/?][A-Za-z0-9\\-%._~:\\/?#\\[\\]@!\\$&\\'\\(\\)\\*\\+,;=]+)?$", var.base_domain)) || var.base_domain == ""
    error_message = "It must be a valid domain name (FQDN)."
  }
}

variable "enable_placement_groups" {
  type        = bool
  default     = true
  description = "Whether to enable Hetzner spread placement groups. Hetzner spread groups support at most 10 servers per group and 50 placement groups per project; count-based static nodepools without an explicit placement_group are auto-sharded every 10 servers."

  validation {
    condition = !var.enable_placement_groups || alltrue([
      for group_key in distinct(local.validation_control_plane_placement_group_keys) :
      length([
        for existing_group_key in local.validation_control_plane_placement_group_keys :
        existing_group_key if existing_group_key == group_key
      ]) <= 10
    ])
    error_message = "Each control-plane Hetzner spread placement group can contain at most 10 servers. Split nodepools across placement_group or placement_group_index values, or disable placement groups."
  }

  validation {
    condition = !var.enable_placement_groups || alltrue([
      for group_key in distinct(local.validation_agent_placement_group_keys) :
      length([
        for existing_group_key in local.validation_agent_placement_group_keys :
        existing_group_key if existing_group_key == group_key
      ]) <= 10
    ])
    error_message = "Each agent Hetzner spread placement group can contain at most 10 servers. Split nodepools across placement_group or placement_group_index values, or disable placement groups."
  }

  validation {
    condition     = !var.enable_placement_groups || local.validation_module_created_placement_group_count <= 50
    error_message = "Hetzner projects support at most 50 placement groups. Reduce static nodepool count, split across projects, use autoscaler nodepools for burst capacity, or set enable_placement_groups=false if you accept no placement-group spread for this cluster."
  }
}

variable "enable_kube_proxy" {
  type        = bool
  default     = true
  description = "Enable kube-proxy. Set false only with Cilium kube-proxy replacement."

  validation {
    condition     = var.enable_kube_proxy || var.cni_plugin == "cilium"
    error_message = "Disabling kube-proxy requires cni_plugin = \"cilium\" in this module."
  }
}

variable "enable_network_policy" {
  type        = bool
  default     = true
  description = "Enable the built-in K3s network policy controller for Flannel. Calico and Cilium force the built-in controller off."
}

variable "cni_plugin" {
  type        = string
  default     = "flannel"
  description = "CNI plugin for k3s."

  validation {
    condition     = contains(["flannel", "calico", "cilium"], var.cni_plugin)
    error_message = "The cni_plugin must be one of \"flannel\", \"calico\", or \"cilium\"."
  }
}

variable "cilium_egress_gateway_enabled" {
  type        = bool
  default     = false
  description = "Enables egress gateway to redirect and SNAT the traffic that leaves the cluster."

  validation {
    condition     = !var.cilium_egress_gateway_enabled || (var.cni_plugin == "cilium" && !var.enable_kube_proxy)
    error_message = "cilium_egress_gateway_enabled requires cni_plugin = \"cilium\" and enable_kube_proxy = false because Cilium Egress Gateway requires kube-proxy replacement."
  }
}

variable "cilium_egress_gateway_ha_enabled" {
  type        = bool
  default     = false
  description = "Deploys a lightweight controller that keeps CiliumEgressGatewayPolicy node selectors pointed at a currently Ready egress node."

  validation {
    condition     = !var.cilium_egress_gateway_ha_enabled || var.cilium_egress_gateway_enabled
    error_message = "cilium_egress_gateway_ha_enabled requires cilium_egress_gateway_enabled = true."
  }
}

variable "cilium_gateway_api_enabled" {
  type        = bool
  default     = false
  description = "Enable Cilium's Gateway API controller and install the standard Gateway API CRDs. Requires Cilium with kube-proxy replacement."

  validation {
    condition     = !var.cilium_gateway_api_enabled || (var.cni_plugin == "cilium" && !var.enable_kube_proxy)
    error_message = "cilium_gateway_api_enabled requires cni_plugin = \"cilium\" and enable_kube_proxy = false because Cilium Gateway API requires kube-proxy replacement."
  }

  validation {
    condition     = !var.cilium_gateway_api_enabled || try(provider::semvers::compare(trimprefix(var.cilium_version, "v"), "1.17.0"), -1) >= 0
    error_message = "cilium_gateway_api_enabled requires cilium_version to be an exact Cilium semver >= 1.17.0."
  }
}

variable "cilium_hubble_enabled" {
  type        = bool
  default     = false
  description = "Enables Hubble Observability to collect and visualize network traffic."

  validation {
    condition     = !var.cilium_hubble_enabled || var.cni_plugin == "cilium"
    error_message = "cilium_hubble_enabled requires cni_plugin = \"cilium\"."
  }
}

variable "cilium_hubble_metrics_enabled" {
  type        = list(string)
  default     = []
  description = "Configures the list of Hubble metrics to collect"

  validation {
    condition     = length(var.cilium_hubble_metrics_enabled) == 0 || (var.cni_plugin == "cilium" && var.cilium_hubble_enabled)
    error_message = "cilium_hubble_metrics_enabled requires cni_plugin = \"cilium\" and cilium_hubble_enabled = true."
  }
}

variable "cilium_ipv4_native_routing_cidr" {
  type        = string
  default     = null
  description = "Used when Cilium is configured in native routing mode. The CNI assumes that the underlying network stack will forward packets to this destination without the need to apply SNAT. Default: value of \"cluster_ipv4_cidr\""

  validation {
    condition = (
      var.cilium_ipv4_native_routing_cidr == null ||
      trimspace(var.cilium_ipv4_native_routing_cidr) == "" ||
      (
        can(cidrhost(var.cilium_ipv4_native_routing_cidr, 0)) &&
        provider::assert::ipv4(cidrhost(var.cilium_ipv4_native_routing_cidr, 0))
      )
    )
    error_message = "cilium_ipv4_native_routing_cidr must be null, empty, or a valid IPv4 CIDR."
  }

  validation {
    condition = (
      var.cilium_ipv4_native_routing_cidr == null ||
      trimspace(var.cilium_ipv4_native_routing_cidr) == "" ||
      (var.cni_plugin == "cilium" && var.cilium_routing_mode == "native")
    )
    error_message = "cilium_ipv4_native_routing_cidr is only used with cni_plugin = \"cilium\" and cilium_routing_mode = \"native\"."
  }
}

variable "cilium_routing_mode" {
  type        = string
  default     = "tunnel"
  description = "Set native-routing mode (\"native\") or tunneling mode (\"tunnel\")."

  validation {
    condition     = contains(["tunnel", "native"], var.cilium_routing_mode)
    error_message = "The cilium_routing_mode must be one of \"tunnel\" or \"native\"."
  }
}

variable "cilium_load_balancer_acceleration_mode" {
  type        = string
  default     = "best-effort"
  description = "Set Cilium loadBalancer.acceleration. Supported values are \"disabled\", \"native\" and \"best-effort\"."

  validation {
    condition     = contains(["disabled", "native", "best-effort"], var.cilium_load_balancer_acceleration_mode)
    error_message = "The cilium_load_balancer_acceleration_mode must be one of \"disabled\", \"native\" or \"best-effort\"."
  }
}

variable "cilium_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Cilium as 'valuesContent' at the HelmChart."
}

variable "cilium_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or cilium_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.cilium_merge_values == "" || can(yamldecode(var.cilium_merge_values))
    error_message = "cilium_merge_values must be valid YAML format or empty string."
  }
}

variable "cilium_version" {
  type        = string
  default     = "1.19.3"
  description = "Version of Cilium. See https://github.com/cilium/cilium/releases for the available versions."
}

variable "calico_values" {
  type        = string
  default     = ""
  description = "Just a stub for a future helm implementation. Now it can be used to replace the calico kustomize patch of the calico manifest."
}

variable "enable_longhorn" {
  type        = bool
  default     = false
  description = "Whether or not to enable Longhorn."
}

variable "longhorn_version" {
  type        = string
  default     = "*"
  description = "Longhorn Helm chart version."
}

variable "longhorn_helmchart_bootstrap" {
  type        = bool
  default     = false
  description = "Whether the HelmChart longhorn shall be run on control-plane nodes."
}

variable "longhorn_repository" {
  type        = string
  default     = "https://charts.longhorn.io"
  description = "By default the official chart which may be incompatible with rancher is used. If you need to fully support rancher switch to https://charts.rancher.io."
}

variable "longhorn_namespace" {
  type        = string
  default     = "longhorn-system"
  description = "Namespace for longhorn deployment, defaults to 'longhorn-system'"
}

variable "longhorn_fstype" {
  type        = string
  default     = "ext4"
  description = "The longhorn fstype."

  validation {
    condition     = contains(["ext4", "xfs"], var.longhorn_fstype)
    error_message = "Must be one of \"ext4\" or \"xfs\""
  }
}

variable "longhorn_replica_count" {
  type        = number
  default     = 3
  description = "Number of replicas per longhorn volume."

  validation {
    condition     = var.longhorn_replica_count > 0
    error_message = "Number of longhorn replicas can't be below 1."
  }
}

variable "longhorn_values" {
  type        = string
  default     = ""
  description = "Helm values passed as valuesContent to the Longhorn HelmChart. When set, this replaces the module defaults."
}

variable "longhorn_merge_values" {
  type        = string
  default     = ""
  description = "Helm values to merge with defaults (or longhorn_values if set). User values take precedence. Use for targeted overrides like image tags. Requires valid YAML format."

  validation {
    condition     = var.longhorn_merge_values == "" || can(yamldecode(var.longhorn_merge_values))
    error_message = "longhorn_merge_values must be valid YAML format or empty string."
  }
}

variable "enable_hetzner_csi" {
  type        = bool
  default     = true
  description = "Enable the Hetzner CSI driver."
}

variable "enable_csi_driver_smb" {
  type        = bool
  default     = false
  description = "Whether or not to enable csi-driver-smb."
}

variable "csi_driver_smb_version" {
  type        = string
  default     = "*"
  description = "Version of csi_driver_smb. See https://github.com/kubernetes-csi/csi-driver-smb/releases for the available versions."
}

variable "csi_driver_smb_helmchart_bootstrap" {
  type        = bool
  default     = false
  description = "Whether the HelmChart csi_driver_smb shall be run on control-plane nodes."
}

variable "csi_driver_smb_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to csi-driver-smb as 'valuesContent' at the HelmChart."
}

variable "csi_driver_smb_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or csi_driver_smb_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.csi_driver_smb_merge_values == "" || can(yamldecode(var.csi_driver_smb_merge_values))
    error_message = "csi_driver_smb_merge_values must be valid YAML format or empty string."
  }
}

variable "enable_cert_manager" {
  type        = bool
  default     = true
  description = "Enable cert manager."
}

variable "cert_manager_version" {
  type        = string
  default     = "*"
  description = "Version of cert_manager."
}

variable "cert_manager_helmchart_bootstrap" {
  type        = bool
  default     = false
  description = "Whether the HelmChart cert_manager shall be run on control-plane nodes."
}

variable "cert_manager_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Cert-Manager as 'valuesContent' at the HelmChart. Defaults are set in locals.tf. For cert-manager versions prior to v1.15.0, you need to set 'installCRDs: true'."
}

variable "cert_manager_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or cert_manager_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.cert_manager_merge_values == "" || can(yamldecode(var.cert_manager_merge_values))
    error_message = "cert_manager_merge_values must be valid YAML format or empty string."
  }
}

variable "enable_rancher" {
  type        = bool
  default     = false
  description = "Enable rancher."

  validation {
    condition     = !var.enable_rancher || trimspace(var.rancher_hostname) != "" || trimspace(var.load_balancer_hostname) != ""
    error_message = "enable_rancher requires rancher_hostname or load_balancer_hostname to be set."
  }
}

variable "rancher_version" {
  type        = string
  default     = "*"
  description = "Version of rancher."
}

variable "rancher_helmchart_bootstrap" {
  type        = bool
  default     = false
  description = "Whether the HelmChart rancher shall be run on control-plane nodes."
}

variable "rancher_install_channel" {
  type        = string
  default     = "stable"
  description = "The rancher installation channel."

  validation {
    condition     = contains(["stable", "latest"], var.rancher_install_channel)
    error_message = "The allowed values for the Rancher install channel are stable or latest."
  }
}

variable "rancher_hostname" {
  type        = string
  default     = ""
  description = "The rancher hostname."

  validation {
    condition     = can(regex("^(?:(?:(?:[A-Za-z0-9])|(?:[A-Za-z0-9](?:[A-Za-z0-9\\-]+)?[A-Za-z0-9]))+(\\.))+([A-Za-z]{2,})([\\/?])?([\\/?][A-Za-z0-9\\-%._~:\\/?#\\[\\]@!\\$&\\'\\(\\)\\*\\+,;=]+)?$", var.rancher_hostname)) || var.rancher_hostname == ""
    error_message = "It must be a valid domain name (FQDN)."
  }
}

variable "load_balancer_hostname" {
  type        = string
  default     = ""
  description = "The Hetzner Load Balancer hostname, for either Traefik, HAProxy or Ingress-Nginx."

  validation {
    condition     = can(regex("^(?:(?:(?:[A-Za-z0-9])|(?:[A-Za-z0-9](?:[A-Za-z0-9\\-]+)?[A-Za-z0-9]))+(\\.))+([A-Za-z]{2,})([\\/?])?([\\/?][A-Za-z0-9\\-%._~:\\/?#\\[\\]@!\\$&\\'\\(\\)\\*\\+,;=]+)?$", var.load_balancer_hostname)) || var.load_balancer_hostname == ""
    error_message = "It must be a valid domain name (FQDN)."
  }
}

variable "kubeconfig_server_address" {
  type        = string
  default     = ""
  description = "The hostname used for kubeconfig."
}

variable "rancher_registration_manifest_url" {
  type        = string
  description = "The url of a rancher registration manifest to apply. (see https://rancher.com/docs/rancher/v2.6/en/cluster-provisioning/registered-clusters/)."
  default     = ""
  sensitive   = true
}

variable "rancher_bootstrap_password" {
  type        = string
  default     = ""
  description = "Rancher bootstrap password."
  sensitive   = true

  validation {
    condition     = (length(var.rancher_bootstrap_password) >= 48) || (length(var.rancher_bootstrap_password) == 0)
    error_message = "The Rancher bootstrap password must be at least 48 characters long."
  }
}

variable "rancher_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Rancher as 'valuesContent' at the HelmChart."
}

variable "rancher_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or rancher_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.rancher_merge_values == "" || can(yamldecode(var.rancher_merge_values))
    error_message = "rancher_merge_values must be valid YAML format or empty string."
  }
}

variable "kured_version" {
  type        = string
  default     = null
  description = "Version of Kured. See https://github.com/kubereboot/kured/releases for the available versions."
}

variable "kured_options" {
  type    = map(string)
  default = {}
}

variable "kubernetes_config_updates_use_kured_sentinel" {
  type        = bool
  default     = false
  description = "When true, k3s/rke2 config updates trigger Kured via reboot sentinel instead of immediate service restarts."
}

variable "allow_inbound_icmp" {
  type        = bool
  default     = false
  description = "Allow inbound ICMP ping."
}

variable "enable_control_plane_load_balancer" {
  type        = bool
  default     = false
  description = "Creates a dedicated load balancer for the Kubernetes API (kubernetes_api_port). When enabled, kubectl and other API clients connect through this LB instead of directly to the first control plane node. Recommended for production clusters with multiple control plane nodes for high availability. Note: This is separate from the ingress load balancer for HTTP/HTTPS traffic."
}

variable "reuse_control_plane_load_balancer" {
  type        = bool
  default     = false
  description = "Reuse the control plane load balancer for ingress services as well. Requires enable_control_plane_load_balancer=true."

  validation {
    condition     = !var.reuse_control_plane_load_balancer || var.enable_control_plane_load_balancer
    error_message = "reuse_control_plane_load_balancer requires enable_control_plane_load_balancer = true."
  }
}

variable "control_plane_load_balancer_type" {
  type        = string
  default     = "lb11"
  description = "The type of load balancer to use for the control plane load balancer. Defaults to lb11, which is the cheapest one."

  validation {
    condition     = can(regex("^lb[1-9][0-9]*$", var.control_plane_load_balancer_type))
    error_message = "control_plane_load_balancer_type must be a Hetzner Load Balancer type such as lb11, lb21, or lb31."
  }
}

variable "control_plane_load_balancer_enable_public_network" {
  type        = bool
  default     = true
  description = "Enable the public interface for the control plane load balancer. Defaults to true. When disabled with nat_router enabled, the NAT router automatically forwards kubernetes_api_port to the private control plane load balancer."
}

variable "dns_servers" {
  type = list(string)

  default = [
    "185.12.64.1",
    "185.12.64.2",
    "2a01:4ff:ff00::add:1",
  ]
  description = "IP Addresses to use for the DNS Servers, set to an empty list to use the ones provided by Hetzner. The length is limited to 3 entries, more entries is not supported by kubernetes"

  validation {
    condition     = length(var.dns_servers) <= 3
    error_message = "The list must have no more than 3 items."
  }

  validation {
    condition     = alltrue([for ip in var.dns_servers : provider::assert::ip(ip)])
    error_message = "Some IP addresses are incorrect."
  }
}

variable "address_for_connectivity_test" {
  description = "The address to test for external connectivity before proceeding with the installation. Defaults to Google's public DNS."
  type        = string
  default     = "8.8.8.8"

  validation {
    condition     = trimspace(var.address_for_connectivity_test) != "" && can(regex("^[A-Za-z0-9_.:-]+$", var.address_for_connectivity_test))
    error_message = "address_for_connectivity_test must be a non-empty IP address or DNS hostname."
  }
}

variable "additional_kubernetes_install_environment" {
  type        = map(any)
  default     = {}
  description = "Additional environment variables for the k3s binary. See for example https://docs.k3s.io/advanced#configuring-an-http-proxy ."

  validation {
    condition = alltrue([
      for key, value in var.additional_kubernetes_install_environment :
      can(regex("^[A-Za-z_][A-Za-z0-9_]*$", key)) && value != null
    ])
    error_message = "additional_kubernetes_install_environment keys must be valid environment variable names and values must not be null."
  }
}

variable "preinstall_exec" {
  type        = list(string)
  default     = []
  description = "Additional to execute before the install calls, for example fetching and installing certs."
}

variable "postinstall_exec" {
  type        = list(string)
  default     = []
  description = "Additional to execute after the install calls, for example restoring a backup."
}

variable "user_kustomizations" {
  type = map(object({
    source_folder        = optional(string, "")
    kustomize_parameters = optional(map(any), {})
    pre_commands         = optional(string, "")
    post_commands        = optional(string, "")
  }))
  default = {
    "1" = {
      source_folder        = "extra-manifests"
      kustomize_parameters = {}
      pre_commands         = ""
      post_commands        = ""
    }
  }
  description = "Map of Kustomization-set entries, where key is the order number."

  validation {
    condition = alltrue([
      for key in keys(var.user_kustomizations) :
      can(regex("^[0-9]+$", key)) && tonumber(key) > 0
    ])
    error_message = "All keys in user_kustomizations must be positive numeric strings (e.g., '1', '2')."
  }
}

variable "create_kubeconfig" {
  type        = bool
  default     = true
  description = "Create the kubeconfig as a local file resource. Should be disabled for automatic runs."
}

variable "create_kustomization" {
  type        = bool
  default     = true
  description = "Create the kustomization backup as a local file resource. Should be disabled for automatic runs."
}

variable "export_values" {
  type        = bool
  default     = false
  description = "Export for deployment used values.yaml-files as local files."
}

variable "enable_cni_wireguard_encryption" {
  type        = bool
  default     = false
  description = "Enable WireGuard encryption in supported CNI integrations. For Flannel this selects wireguard-native unless flannel_backend is set explicitly."
}

variable "flannel_backend" {
  type        = string
  default     = null
  description = "Override the flannel backend used by k3s. When set, this takes precedence over enable_cni_wireguard_encryption. Valid values: vxlan, host-gw, wireguard-native. See https://docs.k3s.io/networking/basic-network-options for details. Use wireguard-native for Robot nodes with vSwitch to avoid MTU issues."

  validation {
    condition     = var.flannel_backend == null || contains(["vxlan", "host-gw", "wireguard-native"], var.flannel_backend)
    error_message = "The flannel_backend must be one of: vxlan, host-gw, wireguard-native."
  }

  validation {
    condition     = var.flannel_backend == null || (var.kubernetes_distribution == "k3s" && var.cni_plugin == "flannel")
    error_message = "flannel_backend applies only when kubernetes_distribution = \"k3s\" and cni_plugin = \"flannel\"."
  }
}

variable "control_planes_custom_config" {
  type        = any
  default     = {}
  description = "Additional configuration for control planes that will be added to k3s's config.yaml. E.g to allow etcd monitoring."
}

variable "agent_nodes_custom_config" {
  type        = any
  default     = {}
  description = "Additional configuration for agent nodes and autoscaler nodes that will be added to k3s's config.yaml. E.g to allow kube-proxy monitoring."
}

variable "registries_config" {
  description = "K3S registries.yml contents. It used to access private docker registries."
  default     = " "
  type        = string

  validation {
    condition     = trimspace(var.registries_config) == "" || can(yamldecode(var.registries_config))
    error_message = "registries_config must be empty or valid YAML."
  }

  validation {
    condition     = trimspace(var.registries_config) == "" || can(keys(yamldecode(var.registries_config)))
    error_message = "registries_config must decode to a YAML mapping."
  }
}

variable "embedded_registry_mirror" {
  type = object({
    enabled                  = optional(bool, false)
    registries               = optional(list(string), ["docker.io", "registry.k8s.io", "ghcr.io", "quay.io"])
    disable_default_endpoint = optional(bool, false)
  })
  default = {
    enabled                  = false
    registries               = ["docker.io", "registry.k8s.io", "ghcr.io", "quay.io"]
    disable_default_endpoint = false
  }
  description = "Opt-in k3s/RKE2 embedded distributed registry mirror (Spegel). Adds empty mirror entries for selected registries and enables the embedded-registry server setting."

  validation {
    condition     = !var.embedded_registry_mirror.enabled || length(var.embedded_registry_mirror.registries) > 0
    error_message = "embedded_registry_mirror.registries must contain at least one registry when embedded_registry_mirror.enabled = true."
  }

  validation {
    condition = alltrue([
      for registry in var.embedded_registry_mirror.registries :
      trimspace(registry) == registry && registry != ""
    ])
    error_message = "embedded_registry_mirror.registries must not contain empty strings or leading/trailing whitespace."
  }

  validation {
    condition = length(distinct([
      for registry in var.embedded_registry_mirror.registries : lower(registry)
    ])) == length(var.embedded_registry_mirror.registries)
    error_message = "embedded_registry_mirror.registries must not contain duplicates."
  }

  validation {
    condition = alltrue([
      for registry in var.embedded_registry_mirror.registries :
      registry == "*" || can(regex("^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?::[1-9][0-9]{0,4})?$", registry))
    ])
    error_message = "embedded_registry_mirror.registries entries must be registry hostnames, optional host:port values, or the wildcard \"*\"."
  }

  validation {
    condition     = var.embedded_registry_mirror.enabled || !var.embedded_registry_mirror.disable_default_endpoint
    error_message = "embedded_registry_mirror.disable_default_endpoint can be true only when embedded_registry_mirror.enabled = true."
  }

  validation {
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

variable "kubelet_config" {
  description = "K3S kubelet-config.yaml contents. Used to configure the kubelet."
  default     = ""
  type        = string

  validation {
    condition     = trimspace(var.kubelet_config) == "" || can(yamldecode(var.kubelet_config))
    error_message = "kubelet_config must be empty or valid YAML."
  }
}

variable "audit_policy_config" {
  description = "K3S audit-policy.yaml contents. Used to configure Kubernetes audit logging."
  default     = ""
  type        = string

  validation {
    condition     = trimspace(var.audit_policy_config) == "" || can(yamldecode(var.audit_policy_config))
    error_message = "audit_policy_config must be empty or valid YAML."
  }
}

variable "audit_log_path" {
  description = "Path where audit logs will be stored on control plane nodes"
  default     = "/var/log/k3s-audit/audit.log"
  type        = string

  validation {
    condition     = can(regex("^/[^\\x00]*[^/]$", var.audit_log_path))
    error_message = "audit_log_path must be an absolute file path and must not end with a slash."
  }
}

variable "audit_log_max_age" {
  description = "Maximum number of days to retain audit log files"
  default     = 30
  type        = number

  validation {
    condition     = var.audit_log_max_age >= 0 && floor(var.audit_log_max_age) == var.audit_log_max_age
    error_message = "audit_log_max_age must be a non-negative integer."
  }
}

variable "audit_log_max_backups" {
  description = "Maximum number of audit log files to retain"
  default     = 10
  type        = number

  validation {
    condition     = var.audit_log_max_backups >= 0 && floor(var.audit_log_max_backups) == var.audit_log_max_backups
    error_message = "audit_log_max_backups must be a non-negative integer."
  }
}

variable "audit_log_max_size" {
  description = "Maximum size in megabytes of the audit log file before rotation"
  default     = 100
  type        = number

  validation {
    condition     = var.audit_log_max_size >= 1 && floor(var.audit_log_max_size) == var.audit_log_max_size
    error_message = "audit_log_max_size must be a positive integer."
  }
}

variable "additional_tls_sans" {
  description = "Additional TLS SANs to allow connection to control-plane through it."
  default     = []
  type        = list(string)

  validation {
    condition = alltrue([
      for san in var.additional_tls_sans :
      trimspace(san) != "" &&
      (
        can(provider::assert::ip(san)) ||
        can(regex("^(?:(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)\\.)+[A-Za-z]{2,}$", san))
      )
    ])
    error_message = "additional_tls_sans entries must be non-empty IP addresses or DNS names."
  }
}

variable "calico_version" {
  type        = string
  default     = null
  description = "Version of Calico. See https://github.com/projectcalico/calico/releases for the available versions."
}

variable "control_plane_exec_args" {
  type        = string
  default     = ""
  description = "The control plane is started with `k3s server {control_plane_exec_args}`. Use this to add kube-apiserver-arg for example."
}

variable "agent_exec_args" {
  type        = string
  default     = ""
  description = "Agents nodes are started with `k3s agent {agent_exec_args}`. Use this to add kubelet-arg for example."
}

variable "prefer_bundled_bin" {
  type        = bool
  default     = false
  description = "Whether to use the bundled k3s mount binary instead of the one from the distro's util-linux package."
}

variable "global_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Global kubelet args for all nodes."
}

variable "control_plane_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for control plane nodes."
}

variable "agent_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for agent nodes."
}

variable "autoscaler_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for autoscaler nodes."
}

variable "ingress_target_namespace" {
  type        = string
  default     = ""
  description = "The namespace to deploy the ingress controller to. Defaults to ingress name."
}

variable "ingress_controller_use_system_namespace" {
  type        = bool
  default     = false
  description = "Deploy the selected ingress controller into kube-system unless ingress_target_namespace is explicitly set."
}

variable "enable_local_storage" {
  type        = bool
  default     = false
  description = "Whether to enable or disable k3s local-storage. Warning: when enabled, there will be two default storage classes: \"local-path\" and \"hcloud-volumes\"!"
}

variable "enable_selinux" {
  type        = bool
  default     = true
  description = "Enable SELinux on nodes that also have nodepool-level selinux enabled."
}

variable "enable_delete_protection" {
  type = object({
    floating_ip   = optional(bool, false)
    load_balancer = optional(bool, false)
    volume        = optional(bool, false)
  })
  default = {
    floating_ip   = false
    load_balancer = false
    volume        = false
  }
  description = "Enable or disable delete protection for resources in Hetzner Cloud."
}

variable "keep_disk_agent_nodes" {
  type        = bool
  default     = false
  description = "Whether to keep OS disks of nodes the same size when upgrading an agent node"
}

variable "keep_disk_control_plane_nodes" {
  type        = bool
  default     = false
  description = "Whether to keep OS disks of nodes the same size when upgrading a control-plane node"
}


variable "system_upgrade_controller_version" {
  type        = string
  default     = "v0.18.0"
  description = "Version of the System Upgrade Controller for automated upgrades of k3s. v0.15.0+ supports the 'window' parameter for scheduling upgrades. See https://github.com/rancher/system-upgrade-controller/releases for available versions."
}

variable "hetzner_ccm_values" {
  type        = string
  default     = ""
  description = "Additional helm values file to pass to Hetzner Controller Manager as 'valuesContent' at the HelmChart."
}

variable "hetzner_ccm_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or hetzner_ccm_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.hetzner_ccm_merge_values == "" || can(yamldecode(var.hetzner_ccm_merge_values))
    error_message = "hetzner_ccm_merge_values must be valid YAML format or empty string."
  }
}

variable "control_plane_endpoint" {
  type        = string
  description = "Optional external control plane endpoint URL (e.g. https://myapi.domain.com:6443). Used as the k3s 'server' value for agents and secondary control planes. If kubernetes_api_port is overridden, use the same port in this URL."
  default     = null
  validation {
    condition     = var.control_plane_endpoint == null || can(regex("^https?://(?:(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?|(?:[0-9]{1,3}\\.){3}[0-9]{1,3}|\\[[0-9a-fA-F:]+\\])(?::[0-9]{1,5})?(?:/.*)?$", var.control_plane_endpoint))
    error_message = "The control_plane_endpoint must be null or a valid URL (e.g., https://my-api.example.com:6443, or your configured kubernetes_api_port)."
  }
}

variable "node_connection_overrides" {
  type        = map(string)
  default     = {}
  description = "Optional map of node name => SSH host override. Use this to route Terraform SSH/provisioning through external access or overlay networks managed outside this module (for example ZeroTier, WireGuard, or Cloudflare Tunnel/WARP). For kube-hetzner-managed Tailscale node transport, use node_transport_mode=\"tailscale\". Cloudflare Access/Tunnel is external access only; Cloudflare Mesh/WARP is not a supported v3 node transport."

  validation {
    condition = alltrue([
      for host in values(var.node_connection_overrides) : trimspace(host) != ""
    ])
    error_message = "All node_connection_overrides values must be non-empty hostnames or IP addresses."
  }
}
