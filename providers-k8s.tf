provider "kubernetes" {
  host                   = local.kubeconfig_data.host
  cluster_ca_certificate = local.kubeconfig_data.cluster_ca_certificate
  client_certificate     = local.kubeconfig_data.client_certificate
  client_key             = local.kubeconfig_data.client_key
}

provider "helm" {
  kubernetes = {
    host                   = local.kubeconfig_data.host
    cluster_ca_certificate = local.kubeconfig_data.cluster_ca_certificate
    client_certificate     = local.kubeconfig_data.client_certificate
    client_key             = local.kubeconfig_data.client_key
  }
}
