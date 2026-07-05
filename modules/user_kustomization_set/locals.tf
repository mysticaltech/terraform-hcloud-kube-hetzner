locals {
  # Folder paths are not secrets; strip the sensitivity inherited from the
  # kustomizations map so validation error messages remain displayable.
  source_folder       = try(nonsensitive(trimspace(var.source_folder)), trimspace(var.source_folder))
  source_folder_files = local.source_folder == "" ? toset([]) : try(fileset(local.source_folder, "**/*.tpl"), toset([]))
  invalid_source_folder_files = sort([
    for file_path in local.source_folder_files : file_path
    if !can(regex("^[A-Za-z0-9._/-]+$", file_path)) || contains(split("/", file_path), "..")
  ])
  kustomization_template_files = setintersection(local.source_folder_files, toset([
    "kustomization.yaml.tpl",
    "kustomization.yml.tpl",
    "Kustomization.tpl"
  ]))
  entry_key_plain   = try(nonsensitive(var.entry_key), var.entry_key)
  allow_empty_plain = try(nonsensitive(var.allow_empty), var.allow_empty)
  entry_label       = local.entry_key_plain != "" ? "user_kustomizations[\"${local.entry_key_plain}\"]" : "user_kustomization_set"
  source_folder_validation_error = (
    local.source_folder == "" ? (local.allow_empty_plain ? "" : "${local.entry_label}.source_folder must be set, or allow_empty = true must be used for an intentional empty set.") : (
      length(local.source_folder_files) == 0 ? (local.allow_empty_plain ? "" : "${local.entry_label}.source_folder (${jsonencode(local.source_folder)}) does not exist, is not readable, or contains no *.tpl template files. Fix the path or set allow_empty = true only for an intentional empty set.") : (
        length(local.invalid_source_folder_files) > 0 ? "${local.entry_label}.source_folder contains unsafe template path(s): ${join(", ", [for file_path in local.invalid_source_folder_files : jsonencode(file_path)])}. Template paths may use only letters, digits, '.', '_', '-', and '/', and must not contain '..' path segments." : (
          length(local.kustomization_template_files) == 0 ? "${local.entry_label}.source_folder (${jsonencode(local.source_folder)}) must contain kustomization.yaml.tpl, kustomization.yml.tpl, or Kustomization.tpl so kubectl apply -k has a rendered entrypoint." : ""
        )
      )
    )
  )

  source_files_sha = join("", [
    for file_path in sort(tolist(local.source_folder_files)) :
    "${file_path}:${filesha1("${local.source_folder}/${file_path}")}"
  ])

  parameters_sha           = nonsensitive(sha256(jsonencode(var.template_parameters)))
  pre_commands_string_sha  = nonsensitive(sha256(var.pre_commands_string))
  post_commands_string_sha = nonsensitive(sha256(var.post_commands_string))
  apply_options_sha        = sha256(jsonencode(var.apply_options))
  apply_options_folder     = "${dirname(var.destination_folder)}/.kube-hetzner-apply-options"
  apply_options_file       = "${local.apply_options_folder}/${basename(var.destination_folder)}.sh"
}
