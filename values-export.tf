resource "local_file" "cilium_values" {
  count           = var.export_values && var.cni_plugin == "cilium" ? 1 : 0
  content         = local.cilium_values
  filename        = "cilium_values.yaml"
  file_permission = "600"
}

resource "local_file" "cert_manager_values" {
  count           = var.export_values && var.enable_cert_manager ? 1 : 0
  content         = local.cert_manager_values
  filename        = "cert_manager_values.yaml"
  file_permission = "600"
}

resource "local_file" "hetzner_ccm_values" {
  count           = var.export_values && var.hetzner_ccm_use_helm ? 1 : 0
  content         = local.hetzner_ccm_values
  filename        = "hetzner_ccm_values.yaml"
  file_permission = "600"
}

resource "local_file" "csi_driver_smb_values" {
  count           = var.export_values && var.enable_csi_driver_smb ? 1 : 0
  content         = local.csi_driver_smb_values
  filename        = "csi_driver_smb_values.yaml"
  file_permission = "600"
}

resource "local_file" "longhorn_values" {
  count           = var.export_values && var.enable_longhorn ? 1 : 0
  content         = local.longhorn_values
  filename        = "longhorn_values.yaml"
  file_permission = "600"
}

resource "local_file" "traefik_values" {
  count           = var.export_values && var.ingress_controller == "traefik" ? 1 : 0
  content         = local.traefik_values
  filename        = "traefik_values.yaml"
  file_permission = "600"
}

resource "local_file" "nginx_values" {
  count           = var.export_values && var.ingress_controller == "nginx" ? 1 : 0
  content         = local.nginx_values
  filename        = "nginx_values.yaml"
  file_permission = "600"
}

resource "local_file" "haproxy_values" {
  count           = var.export_values && var.ingress_controller == "haproxy" ? 1 : 0
  content         = local.haproxy_values
  filename        = "haproxy_values.yaml"
  file_permission = "600"
}
