variable "default_values" {
  type    = string
  default = ""
}

variable "override_values" {
  type    = string
  default = ""
}

variable "merge_values" {
  type    = string
  default = ""
}

locals {
  base_values = var.override_values != "" ? var.override_values : var.default_values
  final_values = var.merge_values != "" ? yamlencode(
    provider::deepmerge::mergo(
      yamldecode(local.base_values),
      yamldecode(var.merge_values)
    )
  ) : local.base_values
}

output "values" {
  value = local.final_values
}
