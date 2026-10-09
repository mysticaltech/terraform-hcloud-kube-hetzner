resource "ssh_sensitive_resource" "kubeconfig" {
  # Note: moved from remote_file to ssh_sensitive_resource because
  # remote_file does not support bastion hosts and ssh_sensitive_resource does.
  when = "create"

  bastion_host        = local.ssh_bastion.bastion_host
  bastion_port        = local.ssh_bastion.bastion_port
  bastion_user        = local.ssh_bastion.bastion_user
  bastion_private_key = local.ssh_bastion.bastion_private_key

  host        = provider::assert::ipv6(local.first_control_plane_ip) ? "[${local.first_control_plane_ip}]" : local.first_control_plane_ip
  port        = var.ssh_port
  user        = "root"
  private_key = var.ssh_private_key
  agent       = var.ssh_private_key == null

  # An ssh-agent with your SSH private keys should be running
  # Use 'private_key' to set the SSH key otherwise
  timeout = "15m"

  commands = [
    local.kubernetes_distribution == "rke2"
    ? "cat /etc/rancher/rke2/rke2.yaml"
    : "cat /etc/rancher/k3s/k3s.yaml"
  ]

  depends_on = [
    terraform_data.control_planes,
    terraform_data.control_planes_rke2,
  ]
}

locals {
  kubeconfig_server_address = var.kubeconfig_server_address != "" ? var.kubeconfig_server_address : (local.node_transport_tailscale_enabled && var.tailscale_node_transport.kubernetes.kubeconfig_endpoint == "first_control_plane_tailnet" ?
    local.tailscale_first_control_plane_host
    : (var.enable_control_plane_load_balancer ?
      (
        var.control_plane_load_balancer_enable_public_network ?
        hcloud_load_balancer.control_plane.*.ipv4[0]
        : (
          var.nat_router != null ?
          hcloud_server.nat_router[0].ipv4_address
          : hcloud_load_balancer_network.control_plane.*.ip[0]
        )
      )
      :
      (can(local.first_control_plane_endpoint_ip) ? local.first_control_plane_endpoint_ip : "unknown")
  ))
  kubeconfig_server_host = provider::assert::ipv6(local.kubeconfig_server_address) ? "[${local.kubeconfig_server_address}]" : local.kubeconfig_server_address
  kubeconfig_server      = "https://${local.kubeconfig_server_host}:${var.kubernetes_api_port}"
  kubeconfig_raw         = yamldecode(ssh_sensitive_resource.kubeconfig.result)
  kubeconfig_rewritten = merge(local.kubeconfig_raw, {
    clusters = [
      for index, cluster in local.kubeconfig_raw["clusters"] : index == 0 ? merge(cluster, {
        name = cluster["name"] == "default" ? var.cluster_name : cluster["name"]
        cluster = merge(cluster["cluster"], {
          server = local.kubeconfig_server
        })
      }) : cluster
    ]
    contexts = [
      for index, context in local.kubeconfig_raw["contexts"] : index == 0 ? merge(context, {
        name = context["name"] == "default" ? var.cluster_name : context["name"]
        context = merge(context["context"], {
          cluster = context["context"]["cluster"] == "default" ? var.cluster_name : context["context"]["cluster"]
          user    = context["context"]["user"] == "default" ? var.cluster_name : context["context"]["user"]
        })
      }) : context
    ]
    users = [
      for index, user in local.kubeconfig_raw["users"] : index == 0 ? merge(user, {
        name = user["name"] == "default" ? var.cluster_name : user["name"]
      }) : user
    ]
    "current-context" = local.kubeconfig_raw["current-context"] == "default" ? var.cluster_name : local.kubeconfig_raw["current-context"]
  })
  kubeconfig_external = yamlencode(local.kubeconfig_rewritten)
  kubeconfig_parsed   = local.kubeconfig_rewritten
  kubeconfig_data = {
    host                   = local.kubeconfig_parsed["clusters"][0]["cluster"]["server"]
    client_certificate     = base64decode(local.kubeconfig_parsed["users"][0]["user"]["client-certificate-data"])
    client_key             = base64decode(local.kubeconfig_parsed["users"][0]["user"]["client-key-data"])
    cluster_ca_certificate = base64decode(local.kubeconfig_parsed["clusters"][0]["cluster"]["certificate-authority-data"])
    cluster_name           = var.cluster_name
  }
}

resource "local_sensitive_file" "kubeconfig" {
  count           = var.create_kubeconfig ? 1 : 0
  content         = local.kubeconfig_external
  filename        = "${var.cluster_name}_kubeconfig.yaml"
  file_permission = "600"
}
