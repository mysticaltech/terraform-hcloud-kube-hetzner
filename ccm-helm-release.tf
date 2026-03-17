resource "helm_release" "hcloud_ccm" {
  count = var.hetzner_ccm_use_helm ? 1 : 0

  name             = "hcloud-cloud-controller-manager"
  repository       = "https://charts.hetzner.cloud"
  chart            = "hcloud-cloud-controller-manager"
  namespace        = "kube-system"
  create_namespace = false
  version          = local.ccm_version
  values           = [local.hetzner_ccm_values]

  wait            = true
  timeout         = 600
  cleanup_on_fail = true

  depends_on = [
    terraform_data.kube_system_secrets,
    terraform_data.control_planes,
    null_resource.control_planes_rke2
  ]
}
