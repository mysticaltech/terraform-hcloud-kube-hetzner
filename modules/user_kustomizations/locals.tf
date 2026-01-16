locals {

  destination_keys = [
    for key, mod in module.user_kustomization_set : key
  ]
  base_destination_folder = "/var/user_kustomize"
}
