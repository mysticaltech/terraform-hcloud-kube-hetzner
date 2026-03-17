locals {
  user_kustomization_templates = try(fileset(var.extra_kustomize_folder, "**/*.yaml.tpl"), toset([]))
}

resource "terraform_data" "kustomization_user" {
  for_each = local.user_kustomization_templates

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p $(dirname /var/user_kustomize/${each.key})"
    ]
  }

  provisioner "file" {
    content     = templatefile("${var.extra_kustomize_folder}/${each.key}", var.extra_kustomize_parameters)
    destination = replace("/var/user_kustomize/${each.key}", ".yaml.tpl", ".yaml")
  }

  triggers_replace = {
    manifest_sha1      = sha1(templatefile("${var.extra_kustomize_folder}/${each.key}", var.extra_kustomize_parameters))
    control_plane_id   = terraform_data.first_control_plane.id
    kustomization_sha1 = sha1(templatefile("${var.extra_kustomize_folder}/kustomization.yaml.tpl", var.extra_kustomize_parameters))

  processed_kustomizes = {
    for key, config in var.user_kustomizations : key => merge(config, {
      # kustomize_parameters, pre_commands, and post_commands may contain secrets
      kustomize_parameters = sensitive(config.kustomize_parameters),
      pre_commands         = sensitive(config.pre_commands),
      post_commands        = sensitive(config.post_commands)
    })
  }
}

module "user_kustomizations" {

  source = "./modules/user_kustomizations"

  ssh_connection = {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  kustomizations_map = local.processed_kustomizes
  kubectl_cli        = local.kubectl_cli

  depends_on = [
    terraform_data.kustomization,
    null_resource.rke2_kustomization,
  ]
}
