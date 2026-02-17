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
