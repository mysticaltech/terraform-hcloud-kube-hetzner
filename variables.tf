variable "hcloud_token" {
  description = "Hetzner Cloud API Token."
  type        = string
  sensitive   = true
}

variable "k3s_token" {
  description = "k3s master token (must match when restoring a cluster)."
  type        = string
  sensitive   = true
  default     = null
}

variable "microos_x86_snapshot_id" {
  description = "MicroOS x86 snapshot ID to be used. Per default empty, the most recent image created using createkh will be used"
  type        = string
  default     = ""
}

variable "microos_arm_snapshot_id" {
  description = "MicroOS ARM snapshot ID to be used. Per default empty, the most recent image created using createkh will be used"
  type        = string
  default     = ""
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
}

variable "ssh_private_key" {
  description = "SSH private Key."
  type        = string
  sensitive   = true
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
}

variable "ssh_max_auth_tries" {
  description = "The maximum number of authentication attempts permitted per connection."
  type        = number
  default     = 2
}

variable "network_region" {
  description = "Default region for network."
  type        = string
  default     = "eu-central"
}
variable "existing_network_id" {
  # Unfortunately, we need this to be a list or null. If we only use a plain
  # string here, and check that existing_network_id is null, terraform will
  # complain that it cannot set `count` variables based on existing_network_id
  # != null, because that id is an output value from
  # hcloud_network.your_network.id, which terraform will only know after its
  # construction.
  description = "If you want to create the private network before calling this module, you can do so and pass its id here. NOTE: make sure to adapt network_ipv4_cidr accordingly to a range which does not collide with your other nodes."
  type        = list(string)
  default     = []
  nullable    = false
  validation {
    condition     = length(var.existing_network_id) == 0 || (can(var.existing_network_id[0]) && length(var.existing_network_id) == 1)
    error_message = "If you pass an existing_network_id, it must be enclosed in square brackets: [id]. This is necessary to be able to unambiguously distinguish between an empty network id (default) and a user-supplied network id."
  }
}
variable "network_ipv4_cidr" {
  description = "The main network cidr that all subnets will be created upon."
  type        = string
  default     = "10.0.0.0/8"
}

variable "cluster_ipv4_cidr" {
  description = "Internal Pod CIDR, used for the controller and currently for calico/cilium."
  type        = string
  default     = "10.42.0.0/16"
}

variable "service_ipv4_cidr" {
  description = "Internal Service CIDR, used for the controller and currently for calico/cilium."
  type        = string
  default     = "10.43.0.0/16"
}

variable "cluster_dns_ipv4" {
  description = "Internal Service IPv4 address of core-dns."
  type        = string
  default     = null
}


variable "nat_router" {
  description = "Do you want to pipe all egress through a single nat router which is to be constructed? Note: Requires use_control_plane_lb=true when enabled."
  nullable    = true
  default     = null
  type = object({
    server_type = string
    location    = string
    labels      = optional(map(string), {})
    enable_sudo = optional(bool, false)
  })
}

variable "nat_router_subnet_index" {
  type        = number
  default     = 200
  description = "Subnet index (0-255) for NAT router. Default 200 is safe for most deployments. Must not conflict with control plane (counting down from 255) or agent pools (counting up from 0)."

  validation {
    condition     = var.nat_router_subnet_index >= 0 && var.nat_router_subnet_index <= 255
    error_message = "NAT router subnet index must be between 0 and 255."
  }
}


variable "load_balancer_location" {
  description = "Default load balancer location."
  type        = string
  default     = "nbg1"
}

variable "load_balancer_type" {
  description = "Default load balancer server type."
  type        = string
  default     = "lb11"
}

variable "load_balancer_disable_ipv6" {
  description = "Disable IPv6 for the load balancer."
  type        = bool
  default     = false
}

variable "load_balancer_disable_public_network" {
  description = "Disables the public network of the load balancer."
  type        = bool
  default     = false
}

variable "load_balancer_algorithm_type" {
  description = "Specifies the algorithm type of the load balancer."
  type        = string
  default     = "round_robin"
}

variable "load_balancer_health_check_interval" {
  description = "Specifies the interval at which a health check is performed. Minimum is 3s."
  type        = string
  default     = "15s"
}

variable "load_balancer_health_check_timeout" {
  description = "Specifies the timeout of a single health check. Must not be greater than the health check interval. Minimum is 1s."
  type        = string
  default     = "10s"
}

variable "load_balancer_health_check_retries" {
  description = "Specifies the number of times a health check is retried before a target is marked as unhealthy."
  type        = number
  default     = 3
}

variable "exclude_agents_from_external_load_balancers" {
  description = "Add node.kubernetes.io/exclude-from-external-load-balancers=true label to agent nodes. Enable this if you use both the Terraform-managed ingress LB and CCM-managed LoadBalancer services, and want to prevent double-registration of agents to the CCM LBs. Note: This excludes agents from ALL CCM-managed LoadBalancer services, not just ingress."
  type        = bool
  default     = false
}

variable "control_plane_nodepools" {
  description = "Number of control plane nodes."
  type = list(object({
    name                       = string
    server_type                = string
    location                   = string
    backups                    = optional(bool)
    labels                     = list(string)
    taints                     = list(string)
    count                      = number
    swap_size                  = optional(string, "")
    zram_size                  = optional(string, "")
    kubelet_args               = optional(list(string), ["kube-reserved=cpu=250m,memory=1500Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    selinux                    = optional(bool, true)
    placement_group_compat_idx = optional(number, 0)
    placement_group            = optional(string, null)
    disable_ipv4               = optional(bool, false)
    disable_ipv6               = optional(bool, false)
    network_id                 = optional(number, 0)
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
}

variable "agent_nodepools" {
  description = "Number of agent nodes."
  type = list(object({
    name                       = string
    server_type                = string
    location                   = string
    backups                    = optional(bool)
    floating_ip                = optional(bool)
    floating_ip_rdns           = optional(string, null)
    labels                     = list(string)
    taints                     = list(string)
    longhorn_volume_size       = optional(number)
    longhorn_mount_path        = optional(string, "/var/longhorn")
    swap_size                  = optional(string, "")
    zram_size                  = optional(string, "")
    kubelet_args               = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    selinux                    = optional(bool, true)
    placement_group_compat_idx = optional(number, 0)
    placement_group            = optional(string, null)
    count                      = optional(number, null)
    disable_ipv4               = optional(bool, false)
    disable_ipv6               = optional(bool, false)
    network_id                 = optional(number, 0)
    nodes = optional(map(object({
      server_type                = optional(string)
      location                   = optional(string)
      backups                    = optional(bool)
      floating_ip                = optional(bool)
      floating_ip_rdns           = optional(string, null)
      labels                     = optional(list(string))
      taints                     = optional(list(string))
      longhorn_volume_size       = optional(number)
      longhorn_mount_path        = optional(string, null)
      swap_size                  = optional(string, "")
      zram_size                  = optional(string, "")
      kubelet_args               = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
      selinux                    = optional(bool, true)
      placement_group_compat_idx = optional(number, 0)
      placement_group            = optional(string, null)
      append_index_to_node_name  = optional(bool, true)
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
    condition     = alltrue([for agent_nodepool in var.agent_nodepools : (agent_nodepool.count == null) != (agent_nodepool.nodes == null)])
    error_message = "Set either nodes or count per agent_nodepool, not both."
  }


  validation {
    condition = alltrue([for agent_nodepool in var.agent_nodepools :
      alltrue([for agent_key, agent_node in coalesce(agent_nodepool.nodes, {}) : can(tonumber(agent_key)) && tonumber(agent_key) == floor(tonumber(agent_key)) && 0 <= tonumber(agent_key) && tonumber(agent_key) < 154])
    ])
    # 154 because the private ip is derived from tonumber(key) + 101. See private_ipv4 in agents.tf
    error_message = "The key for each individual node in a nodepool must be a stable integer in the range [0, 153] cast as a string."
  }

  validation {
    condition = length(var.agent_nodepools) == 0 ? true : sum([for agent_nodepool in var.agent_nodepools : length(coalesce(agent_nodepool.nodes, {})) + coalesce(agent_nodepool.count, 0)]) <= 100
    # 154 because the private ip is derived from tonumber(key) + 101. See private_ipv4 in agents.tf
    error_message = "Hetzner does not support networks with more than 100 servers."
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

}

variable "cluster_autoscaler_image" {
  type        = string
  default     = "registry.k8s.io/autoscaling/cluster-autoscaler"
  description = "Image of Kubernetes Cluster Autoscaler for Hetzner Cloud to be used."
}

variable "cluster_autoscaler_version" {
  type        = string
  default     = "v1.32.0"
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
}

variable "cluster_autoscaler_server_creation_timeout" {
  type        = number
  default     = 15
  description = "Timeout (in minutes) until which a newly created server/node has to become available before giving up and destroying it."
}

variable "cluster_autoscaler_replicas" {
  type        = number
  default     = 1
  description = "Number of replicas for the cluster autoscaler deployment."

  validation {
    condition     = var.cluster_autoscaler_replicas >= 1
    error_message = "Number of cluster autoscaler replicas must be at least 1."
  }
}

variable "cluster_autoscaler_resource_limits" {
  type        = bool
  default     = true
  description = "Should cluster autoscaler enable default resource requests and limits. Default values are requests: 100m & 300Mi and limits: 100m & 300Mi."
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
      cpu    = "100m"
      memory = "300Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "300Mi"
    }
  }
  description = "Requests and limits for Cluster Autoscaler."
}

variable "autoscaler_nodepools" {
  description = "Cluster autoscaler nodepools."
  type = list(object({
    name         = string
    server_type  = string
    location     = string
    min_nodes    = number
    max_nodes    = number
    labels       = optional(map(string), {})
    kubelet_args = optional(list(string), ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = []
}

variable "autoscaler_labels" {
  description = "Labels for nodes created by the Cluster Autoscaler."
  type        = list(string)
  default     = []
}

variable "autoscaler_taints" {
  description = "Taints for nodes created by the Cluster Autoscaler."
  type        = list(string)
  default     = []
}

variable "autoscaler_disable_ipv4" {
  description = "Disable IPv4 on nodes created by the Cluster Autoscaler."
  type        = bool
  default     = false
}

variable "autoscaler_disable_ipv6" {
  description = "Disable IPv6 on nodes created by the Cluster Autoscaler."
  type        = bool
  default     = false
}

variable "hetzner_ccm_version" {
  type        = string
  default     = null
  description = "Version of Kubernetes Cloud Controller Manager for Hetzner Cloud. See https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases for the available versions."
}

variable "hetzner_ccm_use_helm" {
  type        = bool
  default     = false
  description = "Whether to use the helm chart for the Hetzner CCM or the legacy manifest which is the default."
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
}

variable "ingress_controller" {
  type        = string
  default     = "traefik"
  description = "The name of the ingress controller."

  validation {
    condition     = contains(["traefik", "nginx", "haproxy", "none"], var.ingress_controller)
    error_message = "Must be one of \"traefik\" or \"nginx\" or \"haproxy\" or \"none\""
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
  }))
  default     = []
  description = "Additional ports to pass to Traefik. These are the ones that go into the ports section of the Traefik helm values file."
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

variable "initial_k3s_channel" {
  type        = string
  default     = "v1.31" # Please update kube.tf.example too when changing this variable
  description = "Allows you to specify an initial k3s channel. See https://update.k3s.io/v1-release/channels for available channels."

  validation {
    condition     = contains(["stable", "latest", "testing", "v1.16", "v1.17", "v1.18", "v1.19", "v1.20", "v1.21", "v1.22", "v1.23", "v1.24", "v1.25", "v1.26", "v1.27", "v1.28", "v1.29", "v1.30", "v1.31", "v1.32", "v1.33", "v1.34"], var.initial_k3s_channel)
    error_message = "The initial k3s channel must be one of stable, latest or testing, or any of the minor kube versions like v1.26."
  }
}

variable "install_k3s_version" {
  type        = string
  default     = ""
  description = "Allows you to specify the k3s version (Example: v1.29.6+k3s2). Supersedes initial_k3s_channel. See https://github.com/k3s-io/k3s/releases for available versions."
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

variable "automatically_upgrade_k3s" {
  type        = bool
  default     = true
  description = "Whether to automatically upgrade k3s based on the selected channel."
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
}

variable "firewall_kube_api_source" {
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
  description = "Source networks that have Kube API access to the servers."
}

variable "firewall_ssh_source" {
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
  description = "Source networks that have SSH access to the servers."
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

variable "placement_group_disable" {
  type        = bool
  default     = false
  description = "Whether to disable placement groups."
}

variable "disable_kube_proxy" {
  type        = bool
  default     = false
  description = "Disable kube-proxy in K3s (default false)."
}

variable "disable_network_policy" {
  type        = bool
  default     = false
  description = "Disable k3s default network policy controller (default false, automatically true for calico and cilium)."
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
}

variable "cilium_hubble_enabled" {
  type        = bool
  default     = false
  description = "Enables Hubble Observability to collect and visualize network traffic."
}

variable "cilium_hubble_metrics_enabled" {
  type        = list(string)
  default     = []
  description = "Configures the list of Hubble metrics to collect"
}

variable "cilium_ipv4_native_routing_cidr" {
  type        = string
  default     = null
  description = "Used when Cilium is configured in native routing mode. The CNI assumes that the underlying network stack will forward packets to this destination without the need to apply SNAT. Default: value of \"cluster_ipv4_cidr\""
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
  default     = "1.17.0"
  description = "Version of Cilium. See https://github.com/cilium/cilium/releases for the available versions."
}

variable "calico_values" {
  type        = string
  default     = ""
  description = "Just a stub for a future helm implementation. Now it can be used to replace the calico kustomize patch of the calico manifest."
}

variable "enable_iscsid" {
  type        = bool
  default     = false
  description = "This is always true when enable_longhorn=true, however, you may also want this enabled if you perform your own installation of longhorn after this module runs."
}

variable "enable_longhorn" {
  type        = bool
  default     = false
  description = "Whether or not to enable Longhorn."
}

variable "longhorn_version" {
  type        = string
  default     = "*"
  description = "Version of longhorn."
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
  description = "Additional helm values file to pass to longhorn as 'valuesContent' at the HelmChart."
}

variable "longhorn_merge_values" {
  type        = string
  default     = ""
  description = "Additional Helm values to merge with defaults (or longhorn_values if set). User values take precedence. Requires valid YAML format."

  validation {
    condition     = var.longhorn_merge_values == "" || can(yamldecode(var.longhorn_merge_values))
    error_message = "longhorn_merge_values must be valid YAML format or empty string."
  }
}

variable "disable_hetzner_csi" {
  type        = bool
  default     = false
  description = "Disable hetzner csi driver."
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

variable "lb_hostname" {
  type        = string
  default     = ""
  description = "The Hetzner Load Balancer hostname, for either Traefik, HAProxy or Ingress-Nginx."

  validation {
    condition     = can(regex("^(?:(?:(?:[A-Za-z0-9])|(?:[A-Za-z0-9](?:[A-Za-z0-9\\-]+)?[A-Za-z0-9]))+(\\.))+([A-Za-z]{2,})([\\/?])?([\\/?][A-Za-z0-9\\-%._~:\\/?#\\[\\]@!\\$&\\'\\(\\)\\*\\+,;=]+)?$", var.lb_hostname)) || var.lb_hostname == ""
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

variable "block_icmp_ping_in" {
  type        = bool
  default     = false
  description = "Block entering ICMP ping."
}

variable "use_control_plane_lb" {
  type        = bool
  default     = false
  description = "When this is enabled, rather than the first node, all external traffic will be routed via a control-plane loadbalancer, allowing for high availability."
}

variable "control_plane_lb_type" {
  type        = string
  default     = "lb11"
  description = "The type of load balancer to use for the control plane load balancer. Defaults to lb11, which is the cheapest one."
}

variable "control_plane_lb_enable_public_interface" {
  type        = bool
  default     = true
  description = "Enable or disable public interface for the control plane load balancer . Defaults to true."
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
}

variable "additional_k3s_environment" {
  type        = map(any)
  default     = {}
  description = "Additional environment variables for the k3s binary. See for example https://docs.k3s.io/advanced#configuring-an-http-proxy ."
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


variable "extra_kustomize_deployment_commands" {
  type        = string
  default     = ""
  description = "Commands to be executed after the `kubectl apply -k <dir>` step."
}

variable "extra_kustomize_parameters" {
  type        = any
  default     = {}
  description = "All values will be passed to the `kustomization.tmp.yml` template."
}

variable "extra_kustomize_folder" {
  type        = string
  default     = "extra-manifests"
  description = "Folder from where to upload extra manifests"
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

variable "enable_wireguard" {
  type        = bool
  default     = false
  description = "Use wireguard-native as the backend for CNI."
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

variable "k3s_registries" {
  description = "K3S registries.yml contents. It used to access private docker registries."
  default     = " "
  type        = string
}

variable "k3s_kubelet_config" {
  description = "K3S kubelet-config.yaml contents. Used to configure the kubelet."
  default     = ""
  type        = string
}

variable "additional_tls_sans" {
  description = "Additional TLS SANs to allow connection to control-plane through it."
  default     = []
  type        = list(string)
}

variable "calico_version" {
  type        = string
  default     = null
  description = "Version of Calico. See https://github.com/projectcalico/calico/releases for the available versions."
}

variable "k3s_exec_server_args" {
  type        = string
  default     = ""
  description = "The control plane is started with `k3s server {k3s_exec_server_args}`. Use this to add kube-apiserver-arg for example."
}

variable "k3s_exec_agent_args" {
  type        = string
  default     = ""
  description = "Agents nodes are started with `k3s agent {k3s_exec_agent_args}`. Use this to add kubelet-arg for example."
}

variable "k3s_prefer_bundled_bin" {
  type        = bool
  default     = false
  description = "Whether to use the bundled k3s mount binary instead of the one from the distro's util-linux package."
}

variable "k3s_global_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Global kubelet args for all nodes."
}

variable "k3s_control_plane_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for control plane nodes."
}

variable "k3s_agent_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for agent nodes."
}

variable "k3s_autoscaler_kubelet_args" {
  type        = list(string)
  default     = []
  description = "Kubelet args for autoscaler nodes."
}

variable "ingress_target_namespace" {
  type        = string
  default     = ""
  description = "The namespace to deploy the ingress controller to. Defaults to ingress name."
}

variable "enable_local_storage" {
  type        = bool
  default     = false
  description = "Whether to enable or disable k3s local-storage. Warning: when enabled, there will be two default storage classes: \"local-path\" and \"hcloud-volumes\"!"
}

variable "disable_selinux" {
  type        = bool
  default     = false
  description = "Disable SELinux on all nodes."
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

variable "keep_disk_agents" {
  type        = bool
  default     = false
  description = "Whether to keep OS disks of nodes the same size when upgrading an agent node"
}

variable "keep_disk_cp" {
  type        = bool
  default     = false
  description = "Whether to keep OS disks of nodes the same size when upgrading a control-plane node"
}


variable "sys_upgrade_controller_version" {
  type        = string
  default     = "v0.14.2"
  description = "Version of the System Upgrade Controller for automated upgrades of k3s. See https://github.com/rancher/system-upgrade-controller/releases for the available versions."
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
