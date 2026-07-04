output "source_files_sha" {
  value = local.source_files_sha
}

output "parameters_sha" {
  value = local.parameters_sha
}

output "pre_commands_string_sha" {
  value = local.pre_commands_string_sha
}

output "post_commands_string_sha" {
  value = local.post_commands_string_sha
}

output "apply_options_sha" {
  value = local.apply_options_sha
}

output "files_count" {
  description = "Number of template files found in the source folder."
  value       = length(local.source_folder_files)
}

output "changes_sha" {
  value = sha256(join("", [
    local.source_files_sha, local.parameters_sha, local.pre_commands_string_sha, local.post_commands_string_sha, local.apply_options_sha
  ]))
}
