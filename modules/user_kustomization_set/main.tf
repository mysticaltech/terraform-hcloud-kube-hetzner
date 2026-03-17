
# Purpose of this module is to copy a single user kustomization "set" to control plane.
# The set contains the yaml-files for Kustomization and the postinstall.sh script.

resource "null_resource" "install_scripts" {

  triggers = {
    source_files_sha         = local.source_files_sha
    parameters_sha           = local.parameters_sha
    pre_commands_string_sha  = local.pre_commands_string_sha
    post_commands_string_sha = local.post_commands_string_sha
  }

  connection {
    user           = var.ssh_connection.user
    private_key    = var.ssh_connection.private_key
    agent_identity = var.ssh_connection.agent_identity
    host           = var.ssh_connection.host
    port           = var.ssh_connection.port

    bastion_host        = var.ssh_connection.bastion_host
    bastion_port        = var.ssh_connection.bastion_port
    bastion_user        = var.ssh_connection.bastion_user
    bastion_private_key = var.ssh_connection.bastion_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${var.destination_folder}"
    ]
  }

  provisioner "file" {
    content     = templatefile("${path.module}/templates/bash.sh.tpl", { commands = var.pre_commands_string })
    destination = "${var.destination_folder}/preinstall.sh"
  }

  provisioner "file" {
    content     = templatefile("${path.module}/templates/bash.sh.tpl", { commands = var.post_commands_string })
    destination = "${var.destination_folder}/postinstall.sh"
  }
}

resource "null_resource" "user_kustomization_template_files" {
  for_each = nonsensitive(local.source_folder_files)

  lifecycle {
    replace_triggered_by = [
      null_resource.install_scripts
    ]
  }

  connection {
    user           = var.ssh_connection.user
    private_key    = var.ssh_connection.private_key
    agent_identity = var.ssh_connection.agent_identity
    host           = var.ssh_connection.host
    port           = var.ssh_connection.port

    bastion_host        = var.ssh_connection.bastion_host
    bastion_port        = var.ssh_connection.bastion_port
    bastion_user        = var.ssh_connection.bastion_user
    bastion_private_key = var.ssh_connection.bastion_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p $(dirname \"${var.destination_folder}/${each.key}\")"
    ]
  }

  provisioner "file" {
    content     = templatefile("${var.source_folder}/${each.key}", var.template_parameters)
    destination = replace("${var.destination_folder}/${each.key}", ".tpl", "")
  }

  depends_on = [null_resource.install_scripts]
}
