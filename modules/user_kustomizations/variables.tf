variable "ssh_connection" {
  type = object({
    user           = string
    private_key    = string
    agent_identity = string
    host           = string
    port           = string

    bastion_host        = string
    bastion_port        = number
    bastion_user        = string
    bastion_private_key = string
  })
  sensitive = true
}

variable "kustomizations_map" {
  type = map(object({
    source_folder        = optional(string, "")
    kustomize_parameters = optional(map(any), {})
    pre_commands         = optional(string, "")
    post_commands        = optional(string, "")
  }))
  default     = {}
  description = "Map of kustomization entries, where key is the order number."
  sensitive   = true

  validation {
    condition = alltrue([
      for key in keys(var.kustomizations_map) :
      can(regex("^[0-9]+$", key)) && tonumber(key) > 0
    ])
    error_message = "All keys in kustomizations_map must be numeric strings (e.g., '1', '2')."
  }
}

variable "kubectl_cli" {
  type        = string
  description = "Kubectl command used to apply user kustomizations (distribution-aware)."
}
