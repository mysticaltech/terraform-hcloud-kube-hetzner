resource "ssh_sensitive_resource" "kubeconfig" {
  # Note: moved from remote_file to ssh_sensitive_resource because
  # remote_file does not support bastion hosts and ssh_sensitive_resource does.
  # The default behaviour is to run file blocks and commands at create time
  # You can also specify 'destroy' to run the commands at destroy time
  when = "create"

  bastion_host        = local.ssh_bastion.bastion_host
  bastion_port        = local.ssh_bastion.bastion_port
  bastion_user        = local.ssh_bastion.bastion_user
  bastion_private_key = local.ssh_bastion.bastion_private_key

  host        = can(ipv6(local.first_control_plane_ip)) ? "[${local.first_control_plane_ip}]" : local.first_control_plane_ip
  port        = var.ssh_port
  user        = "root"
  private_key = var.ssh_private_key
  agent       = var.ssh_private_key == null

  # An ssh-agent with your SSH private keys should be running
  # Use 'private_key' to set the SSH key otherwise

  timeout = "15m"

  commands = [
    "cat /etc/rancher/k3s/k3s.yaml"
  ]

  depends_on = [null_resource.control_planes[0]]
}

locals {
  kubeconfig_server_address = var.kubeconfig_server_address != "" ? var.kubeconfig_server_address : (var.use_control_plane_lb ?
    (
      var.control_plane_lb_enable_public_interface ?
      hcloud_load_balancer.control_plane.*.ipv4[0]
      : (
        var.nat_router != null ?
        hcloud_server.nat_router[0].ipv4_address
        : hcloud_load_balancer_network.control_plane.*.ip[0]
      )
    )
    :
    (can(local.first_control_plane_ip) ? local.first_control_plane_ip : "unknown")
  )
  kubeconfig_external = replace(replace(ssh_sensitive_resource.kubeconfig.result, "127.0.0.1", local.kubeconfig_server_address), "default", var.cluster_name)
  kubeconfig_parsed   = yamldecode(local.kubeconfig_external)
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
