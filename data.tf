data "http" "hetzner_ccm_release" {
  count = local.addon_version_inputs.hetzner_ccm == "latest" ? 1 : 0
  url   = "https://api.github.com/repos/hetznercloud/hcloud-cloud-controller-manager/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "http" "hetzner_csi_release" {
  count = local.addon_version_inputs.hetzner_csi == "latest" && var.enable_hetzner_csi ? 1 : 0
  url   = "https://api.github.com/repos/hetznercloud/csi-driver/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "http" "kured_release" {
  count = var.enable_kured && local.addon_version_inputs.kured == "latest" ? 1 : 0
  url   = "https://api.github.com/repos/kubereboot/kured/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "http" "kured_manifest" {
  count = var.enable_kured ? 1 : 0
  url   = "https://github.com/kubereboot/kured/releases/download/${local.kured_version}/kured-${local.kured_version}-${local.kured_yaml_suffix}.yaml"

  request_headers = {
    Accept = "text/plain"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "http" "system_upgrade_controller_manifest" {
  count = var.enable_system_upgrade_controller ? 1 : 0
  url   = "https://github.com/rancher/system-upgrade-controller/releases/download/${var.system_upgrade_controller_version}/system-upgrade-controller.yaml"

  request_headers = {
    Accept = "text/plain"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "http" "system_upgrade_controller_crd" {
  count = var.enable_system_upgrade_controller ? 1 : 0
  url   = "https://github.com/rancher/system-upgrade-controller/releases/download/${var.system_upgrade_controller_version}/crd.yaml"

  request_headers = {
    Accept = "text/plain"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "http" "gateway_api_standard_crds" {
  for_each = local.gateway_api_crds_enabled ? toset(local.gateway_api_standard_crd_names) : toset([])

  url = "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${local.gateway_api_crds_version}/config/crd/standard/gateway.networking.k8s.io_${each.key}.yaml"

  request_headers = {
    Accept = "text/plain"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "http" "calico_release" {
  count = local.addon_version_inputs.calico == "latest" && var.cni_plugin == "calico" ? 1 : 0
  url   = "https://api.github.com/repos/projectcalico/calico/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "hcloud_ssh_keys" "keys_by_selector" {
  count         = length(var.ssh_hcloud_key_label) > 0 ? 1 : 0
  with_selector = var.ssh_hcloud_key_label
}

data "http" "my_ipv4" {
  count = local.is_ref_myipv4_used ? 1 : 0

  url = "https://ipv4.icanhazip.com"

  request_headers = {
    Accept = "text/plain"
  }

  retry {
    attempts     = 4
    min_delay_ms = 1000
    max_delay_ms = 10000
  }
}

data "hcloud_server_types" "all" {}

data "hcloud_servers" "existing_control_plane_nodes" {
  with_selector = "provisioner=terraform,engine=${local.kubernetes_distribution},cluster=${var.cluster_name},role=control_plane_node"
}

data "hcloud_servers" "existing_agent_nodes" {
  with_selector = "provisioner=terraform,engine=${local.kubernetes_distribution},cluster=${var.cluster_name},role=agent_node"
}

data "hcloud_image" "microos_x86_snapshot" {
  count             = contains(var.enabled_architectures, "x86") && local.os_arch_requirements.microos.x86 && var.microos_x86_snapshot_id == "" ? 1 : 0
  with_selector     = "microos-snapshot=yes"
  with_architecture = "x86"
  most_recent       = true
}

data "hcloud_image" "microos_arm_snapshot" {
  count             = contains(var.enabled_architectures, "arm") && local.os_arch_requirements.microos.arm && var.microos_arm_snapshot_id == "" ? 1 : 0
  with_selector     = "microos-snapshot=yes"
  with_architecture = "arm"
  most_recent       = true
}

data "hcloud_image" "leapmicro_x86_snapshot" {
  count             = contains(var.enabled_architectures, "x86") && local.os_arch_requirements.leapmicro.x86 && var.leapmicro_x86_snapshot_id == "" ? 1 : 0
  with_selector     = "leapmicro-snapshot=yes,kube-hetzner/os=leapmicro,kube-hetzner/k8s-distro=${local.kubernetes_distribution}"
  with_architecture = "x86"
  most_recent       = true
}

data "hcloud_image" "leapmicro_arm_snapshot" {
  count             = contains(var.enabled_architectures, "arm") && local.os_arch_requirements.leapmicro.arm && var.leapmicro_arm_snapshot_id == "" ? 1 : 0
  with_selector     = "leapmicro-snapshot=yes,kube-hetzner/os=leapmicro,kube-hetzner/k8s-distro=${local.kubernetes_distribution}"
  with_architecture = "arm"
  most_recent       = true
}
