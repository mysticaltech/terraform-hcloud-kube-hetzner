module "values_merger_cilium" {
  source          = "./modules/values_merger"
  default_values  = local.cilium_values_default
  override_values = var.cilium_values
  merge_values    = var.cilium_merge_values
}

module "values_merger_longhorn" {
  source          = "./modules/values_merger"
  default_values  = local.longhorn_values_default
  override_values = var.longhorn_values
  merge_values    = var.longhorn_merge_values
}

module "values_merger_nginx" {
  source          = "./modules/values_merger"
  default_values  = local.nginx_values_default
  override_values = var.nginx_values
  merge_values    = var.nginx_merge_values
}

module "values_merger_hetzner_ccm" {
  source          = "./modules/values_merger"
  default_values  = local.hetzner_ccm_values_default
  override_values = var.hetzner_ccm_values
  merge_values    = var.hetzner_ccm_merge_values
}

module "values_merger_haproxy" {
  source          = "./modules/values_merger"
  default_values  = local.haproxy_values_default
  override_values = var.haproxy_values
  merge_values    = var.haproxy_merge_values
}

module "values_merger_traefik" {
  source          = "./modules/values_merger"
  default_values  = local.traefik_values_default
  override_values = var.traefik_values
  merge_values    = var.traefik_merge_values
}

module "values_merger_rancher" {
  source          = "./modules/values_merger"
  default_values  = local.rancher_values_default
  override_values = var.rancher_values
  merge_values    = var.rancher_merge_values
}

module "values_merger_cert_manager" {
  source          = "./modules/values_merger"
  default_values  = local.cert_manager_values_default
  override_values = var.cert_manager_values
  merge_values    = var.cert_manager_merge_values
}
