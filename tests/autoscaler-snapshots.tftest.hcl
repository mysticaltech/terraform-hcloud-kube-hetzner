# Offline full-module plans: no real provider reads, applies, or credentials.
mock_provider "hcloud" {
  mock_resource "hcloud_network" {
    defaults = { id = "123" }
  }
  mock_resource "hcloud_firewall" {
    defaults = { id = "234" }
  }
  mock_resource "hcloud_placement_group" {
    defaults = { id = "345" }
  }
  mock_resource "hcloud_ssh_key" {
    defaults = { id = "456" }
  }
  mock_resource "hcloud_primary_ip" {
    defaults = { id = "567", ip_address = "192.0.2.10" }
  }
  mock_resource "hcloud_server" {
    defaults = { id = "678", ipv4_address = "192.0.2.10", ipv6_address = "2001:db8::10", ipv6_network = "2001:db8::/64" }
  }
  mock_data "hcloud_network" {
    defaults = { ip_range = "10.0.0.0/8" }
  }
  mock_data "hcloud_image" {
    defaults = { id = "200", architecture = "x86", type = "snapshot" }
  }
  mock_data "hcloud_images" {
    defaults = {
      images = [{
        id          = 300, architecture = "x86", created = "2026-01-01T00:00:00Z", deprecated = "",
        description = "offline fixture", name = "", os_flavor = "opensuse", os_version = "", rapid_deploy = false, selector = "", type = "snapshot"
        labels = {
          "microos-snapshot"        = "yes"
          "kube-hetzner/os"         = "microos"
          "kube-hetzner/k8s-distro" = "k3s"
        }
      }]
    }
  }
}
mock_provider "http" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "ssh" {
  mock_resource "ssh_sensitive_resource" {
    defaults = {
      result = <<-YAML
        clusters:
          - name: default
            cluster:
              server: https://192.0.2.10:6443
              certificate-authority-data: Zml4dHVyZQ==
        contexts:
          - name: default
            context: {cluster: default, user: default}
        users:
          - name: default
            user:
              client-certificate-data: Zml4dHVyZQ==
              client-key-data: Zml4dHVyZQ==
        current-context: default
      YAML
    }
  }
}
mock_provider "local" {}

variables {
  hcloud_token          = "offline-test-not-a-credential"
  ssh_public_key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKubeHetznerRenderFixture"
  ssh_private_key       = null
  enabled_architectures = ["x86"]
  control_plane_nodepools = [{
    name = "cp", server_type = "cx23", location = "nbg1", count = 1, os = "leapmicro", labels = [], taints = []
  }]
  agent_nodepools = []
  autoscaler_nodepools = [{
    name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "leapmicro"
  }]
  hetzner_ccm_version              = "v1.25.0"
  enable_kured                     = false
  enable_hetzner_csi               = false
  enable_longhorn                  = false
  enable_cert_manager              = false
  enable_rancher                   = false
  enable_system_upgrade_controller = false
  ingress_controller               = "none"
  firewall_ssh_source              = ["0.0.0.0/0"]
  firewall_kube_api_source         = ["0.0.0.0/0"]
}

run "default_id" {
  command = plan
  assert {
    condition     = length(local.imageList) == 1 && local.imageList.amd64 == "200" && local.first_nodepool_snapshot_id == "200"
    error_message = "Default autoscaler config must keep numeric snapshot IDs."
  }
}

run "latest_leapmicro" {
  command = plan
  variables { cluster_autoscaler_snapshot_selection = "latest" }
  assert {
    condition     = length(local.imageList) == 1 && local.imageList.amd64 == "leapmicro-snapshot=yes,kube-hetzner/os=leapmicro,kube-hetzner/k8s-distro=k3s" && local.first_nodepool_snapshot_id == local.imageList.amd64
    error_message = "Both modern and legacy configs must use the complete selector."
  }
  assert {
    condition     = length(data.hcloud_image.leapmicro_x86_snapshot[0].with_status) == 1 && data.hcloud_image.leapmicro_x86_snapshot[0].with_status[0] == "available"
    error_message = "The readiness lookup must exclude unavailable Leap Micro images in latest mode."
  }
}

run "microos_missing_os_label" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  override_data {
    target = data.hcloud_images.microos_x86_snapshots
    values = { images = [{
      id          = 300, architecture = "x86", created = "2026-01-01T00:00:00Z", deprecated = "",
      description = "offline fixture", name = "", os_flavor = "opensuse", os_version = "", rapid_deploy = false, selector = "", type = "snapshot",
      labels      = { "microos-snapshot" = "yes", "kube-hetzner/k8s-distro" = "k3s" }
    }] }
  }
  expect_failures = [terraform_data.validation_contract]
}

run "latest_microos" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  assert {
    condition     = local.imageList.amd64 == "microos-snapshot=yes,kube-hetzner/os=microos,kube-hetzner/k8s-distro=k3s" && local.snapshot_id_by_os.microos.x86 == "300"
    error_message = "Latest autoscaler mode must leave static-node snapshot resolution numeric."
  }
  assert {
    condition     = try(length(data.hcloud_image.leapmicro_x86_snapshot[0].with_status), 0) == 0
    error_message = "Static-only Leap Micro lookup behavior must remain unchanged."
  }
}

run "latest_rke2_both_architectures" {
  command = plan
  variables {
    kubernetes_distribution               = "rke2"
    cluster_autoscaler_snapshot_selection = "latest"
    enabled_architectures                 = ["arm", "x86"]
    autoscaler_nodepools = [
      { name = "arm", server_type = "cax11", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "leapmicro" },
      { name = "x86", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "leapmicro" },
    ]
  }
  assert {
    condition     = length(local.imageList) == 2 && local.imageList.arm64 == local.imageList.amd64 && local.first_nodepool_snapshot_id == local.imageList.arm64 && local.imageList.arm64 == "leapmicro-snapshot=yes,kube-hetzner/os=leapmicro,kube-hetzner/k8s-distro=rke2"
    error_message = "Both architecture entries must select the active distro; the API filters architecture."
  }
}

run "static_arm_id_is_not_an_autoscaler_pin" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    enabled_architectures                 = ["arm", "x86"]
    leapmicro_arm_snapshot_id             = "999"
    agent_nodepools = [{
      name = "arm-static", server_type = "cax11", location = "nbg1", count = 1, os = "leapmicro", labels = [], taints = []
    }]
  }
  assert {
    condition     = length(local.imageList) == 1 && contains(keys(local.imageList), "amd64") && local.snapshot_id_by_os.leapmicro.arm == "999"
    error_message = "A static-only architecture must retain its ID and not be emitted or rejected by latest autoscaler mode."
  }
}

run "no_autoscaler_pools" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools                  = []
    leapmicro_x86_snapshot_id             = "999"
  }
  assert {
    condition     = length(local.imageList) == 0 && local.first_nodepool_snapshot_id == "" && local.autoscaler_yaml == ""
    error_message = "An inactive autoscaler must not render images or reject static-node pins."
  }
}

run "dormant_pool_still_has_selector" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools = [{
      name = "dormant", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 0, os = "leapmicro"
    }]
  }
  assert {
    condition     = length(local.imageList) == 1 && local.first_nodepool_snapshot_id == local.imageList.amd64
    error_message = "A zero-capacity but configured pool still needs valid image configuration."
  }
}

run "latest_leapmicro_pin_rejected" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    leapmicro_x86_snapshot_id             = "999"
  }
  expect_failures = [terraform_data.validation_contract]
}

run "dormant_pin_rejected" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    leapmicro_x86_snapshot_id             = "999"
    autoscaler_nodepools = [{
      name = "dormant", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 0, os = "leapmicro"
    }]
  }
  expect_failures = [terraform_data.validation_contract]
}

run "latest_microos_pin_rejected" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    microos_x86_snapshot_id               = "999"
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  expect_failures = [terraform_data.validation_contract]
}

run "legacy_microos_rejected" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  override_data {
    target = data.hcloud_images.microos_x86_snapshots
    values = { images = [{
      id          = 300, architecture = "x86", created = "2026-01-01T00:00:00Z", deprecated = "",
      description = "offline fixture", name = "", os_flavor = "opensuse", os_version = "", rapid_deploy = false, selector = "", type = "snapshot",
      labels      = { "microos-snapshot" = "yes" }
    }] }
  }
  expect_failures = [terraform_data.validation_contract]
}

run "wrong_os_microos_rejected" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  override_data {
    target = data.hcloud_images.microos_x86_snapshots
    values = { images = [{
      id          = 300, architecture = "x86", created = "2026-01-01T00:00:00Z", deprecated = "",
      description = "offline fixture", name = "", os_flavor = "opensuse", os_version = "", rapid_deploy = false, selector = "", type = "snapshot",
      labels      = { "microos-snapshot" = "yes", "kube-hetzner/os" = "leapmicro", "kube-hetzner/k8s-distro" = "k3s" }
    }] }
  }
  expect_failures = [terraform_data.validation_contract]
}

run "wrong_distro_microos_rejected" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  override_data {
    target = data.hcloud_images.microos_x86_snapshots
    values = { images = [{
      id          = 300, architecture = "x86", created = "2026-01-01T00:00:00Z", deprecated = "",
      description = "offline fixture", name = "", os_flavor = "opensuse", os_version = "", rapid_deploy = false, selector = "", type = "snapshot",
      labels      = { "microos-snapshot" = "yes", "kube-hetzner/os" = "microos", "kube-hetzner/k8s-distro" = "rke2" }
    }] }
  }
  expect_failures = [terraform_data.validation_contract]
}

run "missing_microos_rejected" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  override_data {
    target = data.hcloud_images.microos_x86_snapshots
    values = { images = [] }
  }
  expect_failures = [terraform_data.validation_contract]
}

run "legacy_microos_id_mode_preserved" {
  command = plan
  variables {
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  override_data {
    target = data.hcloud_images.microos_x86_snapshots
    values = { images = [{
      id          = 300, architecture = "x86", created = "2026-01-01T00:00:00Z", deprecated = "",
      description = "offline fixture", name = "", os_flavor = "opensuse", os_version = "", rapid_deploy = false, selector = "", type = "snapshot",
      labels      = { "microos-snapshot" = "yes" }
    }] }
  }
  assert {
    condition     = local.imageList.amd64 == "300"
    error_message = "Legacy MicroOS ID-mode compatibility must remain unchanged."
  }
}

run "invalid_selection_rejected" {
  command = plan
  variables { cluster_autoscaler_snapshot_selection = "newest" }
  expect_failures = [var.cluster_autoscaler_snapshot_selection]
}

run "existing_autoscaler_version_floor" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    cluster_autoscaler_version            = "v1.32.0"
  }
  expect_failures = [terraform_data.configure_autoscaler]
}

run "minimum_supported_autoscaler" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    cluster_autoscaler_version            = "v1.33.0"
  }
}

run "leapmicro_backup_rejected" {
  command = plan
  variables { cluster_autoscaler_snapshot_selection = "latest" }
  override_data {
    target = data.hcloud_image.leapmicro_x86_snapshot
    values = { id = 200, architecture = "x86", type = "backup" }
  }
  expect_failures = [terraform_data.validation_contract]
}

run "microos_backup_rejected" {
  command = plan
  variables {
    cluster_autoscaler_snapshot_selection = "latest"
    autoscaler_nodepools = [{
      name = "scale", server_type = "cx23", location = "nbg1", min_nodes = 0, max_nodes = 1, os = "microos"
    }]
  }
  override_data {
    target = data.hcloud_images.microos_x86_snapshots
    values = { images = [{
      id          = 300, architecture = "x86", created = "2026-01-01T00:00:00Z", deprecated = "",
      description = "offline fixture", name = "", os_flavor = "opensuse", os_version = "", rapid_deploy = false, selector = "", type = "backup",
      labels      = { "microos-snapshot" = "yes", "kube-hetzner/os" = "microos", "kube-hetzner/k8s-distro" = "k3s" }
    }] }
  }
  expect_failures = [terraform_data.validation_contract]
}
