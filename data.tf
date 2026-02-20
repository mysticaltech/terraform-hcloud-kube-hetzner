data "github_release" "hetzner_ccm" {
  count       = var.hetzner_ccm_version == null ? 1 : 0
  repository  = "hcloud-cloud-controller-manager"
  owner       = "hetznercloud"
  retrieve_by = "latest"
}

data "github_release" "hetzner_csi" {
  count       = var.hetzner_csi_version == null && !var.disable_hetzner_csi ? 1 : 0
  repository  = "csi-driver"
  owner       = "hetznercloud"
  retrieve_by = "latest"
}

// github_release for kured
data "github_release" "kured" {
  count       = var.kured_version == null ? 1 : 0
  repository  = "kured"
  owner       = "kubereboot"
  retrieve_by = "latest"
}

// github_release for kured
data "github_release" "calico" {
  count       = var.calico_version == null && var.cni_plugin == "calico" ? 1 : 0
  repository  = "calico"
  owner       = "projectcalico"
  retrieve_by = "latest"
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
