
# Purpose of this module is to copy a single user kustomization "set" to control plane.
# The set contains the yaml-files for Kustomization and the postinstall.sh script.

resource "terraform_data" "validate_source_folder" {
  input = local.source_folder_validation_error

  lifecycle {
    precondition {
      condition     = local.source_folder_validation_error == ""
      error_message = local.source_folder_validation_error
    }
  }
}

resource "terraform_data" "install_scripts" {

  triggers_replace = merge({
    source_files_sha         = local.source_files_sha
    parameters_sha           = local.parameters_sha
    pre_commands_string_sha  = local.pre_commands_string_sha
    post_commands_string_sha = local.post_commands_string_sha
    apply_options_sha        = local.apply_options_sha
  }, var.replacement_triggers)

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
      "rm -rf ${jsonencode(var.destination_folder)}",
      "mkdir -p ${jsonencode(var.destination_folder)}",
      "mkdir -p ${jsonencode(local.apply_options_folder)}",
      "rm -f ${jsonencode(local.apply_options_file)}"
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

  provisioner "file" {
    content     = templatefile("${path.module}/templates/apply-options.sh.tpl", { options = var.apply_options })
    destination = local.apply_options_file
  }

  depends_on = [terraform_data.validate_source_folder]
}

resource "terraform_data" "user_kustomization_template_files" {
  for_each = local.source_folder_files

  lifecycle {
    replace_triggered_by = [
      terraform_data.install_scripts
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
    # each.key is constrained by local.source_folder_validation_error to a shell-safe relative template path.
    inline = [
      "mkdir -p \"$(dirname \"${var.destination_folder}/${each.key}\")\""
    ]
  }

  provisioner "file" {
    content     = templatefile("${local.source_folder}/${each.key}", var.template_parameters)
    destination = replace("${var.destination_folder}/${each.key}", "/\\.tpl$/", "")
  }

  depends_on = [terraform_data.install_scripts]
}

moved {
  from = null_resource.install_scripts
  to   = terraform_data.install_scripts
}

moved {
  from = null_resource.user_kustomization_template_files
  to   = terraform_data.user_kustomization_template_files
}
