locals {
  source_folder_files = var.source_folder == "" ? toset([]) : try(fileset(var.source_folder, "**/*.tpl"), toset([]))

  source_files_sha = join("", [
    for file_path in local.source_folder_files :
    filesha1("${var.source_folder}/${file_path}")
  ])

  parameters_sha           = nonsensitive(sha256(jsonencode(var.template_parameters)))
  pre_commands_string_sha  = nonsensitive(sha256(var.pre_commands_string))
  post_commands_string_sha = nonsensitive(sha256(var.post_commands_string))
}
