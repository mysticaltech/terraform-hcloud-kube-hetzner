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

variable "source_folder" {
  type    = string
  default = ""
}

variable "destination_folder" {
  type    = string
  default = "/var/user_kustomize"

  validation {
    condition     = startswith(var.destination_folder, "/") && can(regex("^[^\\s]*$", var.destination_folder))
    error_message = "destination_folder must start with '/' and must not contain spaces."
  }
}

variable "template_parameters" {
  type      = map(any)
  default   = {}
  sensitive = true
}

variable "pre_commands_string" {
  type      = string
  default   = ""
  sensitive = true
}

variable "post_commands_string" {
  type      = string
  default   = ""
  sensitive = true
}
