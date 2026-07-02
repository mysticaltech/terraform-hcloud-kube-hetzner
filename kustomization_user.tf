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
    manifest_sha1 = "${sha1(templatefile("${var.extra_kustomize_folder}/${each.key}", var.extra_kustomize_parameters))}"
  }

  depends_on = [
    terraform_data.kustomization
  ]
}
moved {
  from = null_resource.kustomization_user
  to   = terraform_data.kustomization_user
}

resource "terraform_data" "kustomization_user_deploy" {
  count = length(local.user_kustomization_templates) > 0 ? 1 : 0

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

  # Remove templates after rendering, and apply changes.
  # `kubectl apply -k` runs in its own provisioner so that a non-zero exit fails this
  # step directly. Previously it shared one remote-exec script with
  # extra_kustomize_deployment_commands; since remote-exec has no `set -e` and the exit
  # code is that of the LAST command, a failed apply was masked whenever a trailing
  # command succeeded — tofu then reported success while nothing reconciled.
  provisioner "remote-exec" {
    # Debugging: "sh -c 'for file in $(find /var/user_kustomize -type f -name \"*.yaml\" | sort -n); do echo \"\n### Template $${file}.tpl after rendering:\" && cat $${file}; done'",
    inline = [
      "rm -f /var/user_kustomize/**/*.yaml.tpl",
      "echo 'Applying user kustomization...'",
      "kubectl apply -k /var/user_kustomize/ --wait=true",
    ]
  }

  # User-supplied post-apply commands run only after a successful apply. The leading
  # "true" keeps inline non-empty when the variable is unset (compact() would otherwise
  # produce an empty list).
  provisioner "remote-exec" {
    inline = compact([
      "true",
      var.extra_kustomize_deployment_commands,
    ])
  }

  lifecycle {
    replace_triggered_by = [
      terraform_data.kustomization_user
    ]
  }

  depends_on = [
    terraform_data.kustomization_user
  ]
}
moved {
  from = null_resource.kustomization_user_deploy
  to   = terraform_data.kustomization_user_deploy
}
