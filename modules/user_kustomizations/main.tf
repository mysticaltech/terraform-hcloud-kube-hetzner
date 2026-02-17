# Purpose of this module is to initiate the copy of each user kustomization "set" and the deploy them one by one in sequential order.


module "user_kustomization_set" {
  source = "../user_kustomization_set"

  for_each = nonsensitive(toset(keys(var.kustomizations_map)))

  ssh_connection = var.ssh_connection

  source_folder       = var.kustomizations_map[each.key].source_folder
  destination_folder  = "${local.base_destination_folder}/${each.key}"
  template_parameters = var.kustomizations_map[each.key].kustomize_parameters

  pre_commands_string  = var.kustomizations_map[each.key].pre_commands
  post_commands_string = var.kustomizations_map[each.key].post_commands
}

resource "null_resource" "kustomization_user_deploy" {

  triggers = {
    kustomization_shas = sha256(yamlencode(module.user_kustomization_set))
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
      <<-EOT
      #!/bin/bash
      set -e

      function cleanup {
        echo "Cleaning up ${local.base_destination_folder}..."
        rm -rf ${local.base_destination_folder}
      }
      trap cleanup EXIT
      sorted_dest_keys=$(printf '%s\n' ${join(" ", local.destination_keys)} | sort -n | tr '\n' ' ')

      for dest_key in $sorted_dest_keys; do
        dest_folder="${local.base_destination_folder}/$dest_key"

        if [ -d "$dest_folder" ]; then
          echo "Running pre-install script from $dest_folder"
          /bin/bash "$dest_folder/preinstall.sh"

          if [ -s "$dest_folder/kustomization.yaml" ] || [ -s "$dest_folder/kustomization.yml" ] || [ -s "$dest_folder/Kustomization" ]; then
            echo "Applying kustomization from $dest_folder"
            ${var.kubectl_cli} apply -k "$dest_folder"
          else
            echo "No valid kustomization file found in $dest_folder, skipping apply."
          fi

          echo "Running post-install script from $dest_folder"
          /bin/bash "$dest_folder/postinstall.sh"
        fi
      done
      EOT
    ]
  }

  depends_on = [
    module.user_kustomization_set,
  ]
}
