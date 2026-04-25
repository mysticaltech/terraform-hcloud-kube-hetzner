data "http" "hetzner_ccm_release" {
  count = var.hetzner_ccm_version == null ? 1 : 0
  url   = "https://api.github.com/repos/hetznercloud/hcloud-cloud-controller-manager/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
  }
}

data "http" "hetzner_csi_release" {
  count = var.hetzner_csi_version == null && !var.disable_hetzner_csi ? 1 : 0
  url   = "https://api.github.com/repos/hetznercloud/csi-driver/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
  }
}

data "http" "kured_release" {
  count = var.kured_version == null ? 1 : 0
  url   = "https://api.github.com/repos/kubereboot/kured/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
  }
}

data "http" "calico_release" {
  count = var.calico_version == null && var.cni_plugin == "calico" ? 1 : 0
  url   = "https://api.github.com/repos/projectcalico/calico/releases/latest"

  request_headers = {
    Accept = "application/vnd.github+json"
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
}

data "hcloud_servers" "existing_control_plane_nodes" {
  with_selector = "provisioner=terraform,engine=${local.kubernetes_distribution},cluster=${var.cluster_name},role=control_plane_node"
}

data "hcloud_servers" "existing_agent_nodes" {
  with_selector = "provisioner=terraform,engine=${local.kubernetes_distribution},cluster=${var.cluster_name},role=agent_node"
}

data "hcloud_image" "microos_x86_snapshot" {
  count             = var.enable_x86 && local.os_arch_requirements.microos.x86 && var.microos_x86_snapshot_id == "" ? 1 : 0
  with_selector     = "microos-snapshot=yes"
  with_architecture = "x86"
  most_recent       = true
}

data "hcloud_image" "microos_arm_snapshot" {
  count             = var.enable_arm && local.os_arch_requirements.microos.arm && var.microos_arm_snapshot_id == "" ? 1 : 0
  with_selector     = "microos-snapshot=yes"
  with_architecture = "arm"
  most_recent       = true
}

data "hcloud_image" "leapmicro_x86_snapshot" {
  count             = var.enable_x86 && local.os_arch_requirements.leapmicro.x86 && var.leapmicro_x86_snapshot_id == "" ? 1 : 0
  with_selector     = "leapmicro-snapshot=yes,kube-hetzner/os=leapmicro,kube-hetzner/k8s-distro=${local.kubernetes_distribution}"
  with_architecture = "x86"
  most_recent       = true
}

data "hcloud_image" "leapmicro_arm_snapshot" {
  count             = var.enable_arm && local.os_arch_requirements.leapmicro.arm && var.leapmicro_arm_snapshot_id == "" ? 1 : 0
  with_selector     = "leapmicro-snapshot=yes,kube-hetzner/os=leapmicro,kube-hetzner/k8s-distro=${local.kubernetes_distribution}"
  with_architecture = "arm"
  most_recent       = true
}
