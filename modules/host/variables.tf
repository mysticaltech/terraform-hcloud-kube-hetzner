variable "name" {
  description = "Host name"
  type        = string
}
variable "microos_snapshot_id" {
  description = "MicroOS snapshot ID to be used. Per default empty, an initial snapshot will be created"
  type        = string
  default     = ""
}
variable "base_domain" {
  description = "Base domain used for reverse dns"
  type        = string
}

variable "ssh_port" {
  description = "SSH port"
  type        = number
}

variable "ssh_public_key" {
  description = "SSH public Key"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private Key"
  type        = string
}

variable "ssh_additional_public_keys" {
  description = "Additional SSH public Keys. Use them to grant other team members root access to your cluster nodes"
  type        = list(string)
  default     = []
}

variable "ssh_keys" {
  description = "List of SSH key IDs"
  type        = list(string)
  nullable    = true
}

variable "firewall_ids" {
  description = "Set of firewall IDs"
  type        = set(number)
  nullable    = true
}

variable "placement_group_id" {
  description = "Placement group ID"
  type        = number
  nullable    = true
}

variable "labels" {
  description = "Labels"
  type        = map(any)
  nullable    = true
}

variable "location" {
  description = "The server location"
  type        = string
}

variable "ipv4_subnet_id" {
  description = "The subnet id"
  type        = string
}

variable "private_ipv4" {
  description = "Private IP for the server"
  type        = string
}

variable "server_type" {
  description = "The server type"
  type        = string
}

variable "backups" {
  description = "Enable automatic backups via Hetzner"
  type        = bool
  default     = false
}

variable "packages_to_install" {
  description = "Packages to install"
  type        = list(string)
  default     = []
}

variable "dns_servers" {
  type        = list(string)
  description = "IP Addresses to use for the DNS Servers, set to an empty list to use the ones provided by Hetzner"
}

variable "automatically_upgrade_os" {
  type    = bool
  default = true
}

variable "k3s_registries" {
  default = ""
  type    = string
}

variable "k3s_registries_update_script" {
  default = ""
  type    = string
}

variable "cloudinit_write_files_common" {
  default = ""
  type    = string
}

variable "cloudinit_runcmd_common" {
  default = ""
  type    = string
}

variable "swap_size" {
  default = ""
  type    = string

  validation {
    condition     = can(regex("^$|[1-9][0-9]{0,3}(G|M)$", var.swap_size))
    error_message = "Invalid swap size. Examples: 512M, 1G"
  }
}

variable "zram_size" {
  default = ""
  type    = string

  validation {
    condition     = can(regex("^$|[1-9][0-9]{0,3}(G|M)$", var.zram_size))
    error_message = "Invalid zram size. Examples: 512M, 1G"
  }
}

variable "keep_disk_size" {
  type        = bool
  default     = false
  description = "Whether to keep OS disks of nodes the same size when upgrading a node"
}

variable "disable_ipv4" {
  type        = bool
  default     = false
  description = "Whether to disable ipv4 on the server. If you disable ipv4 and ipv6 make sure you have an access to your private network."
}

variable "disable_ipv6" {
  type        = bool
  default     = false
  description = "Whether to disable ipv4 on the server. If you disable ipv4 and ipv6 make sure you have an access to your private network."
}

variable "network_id" {
  type        = number
  default     = null
  description = "The network id to attach the server to."
}

variable "ssh_bastion" {
  type = object({

    bastion_host        = string
    bastion_port        = number
    bastion_user        = string
    bastion_private_key = string
  })
}

variable "network_gw_ipv4" {
  type        = string
  description = "Default IPv4 gateway address for the node's primary network interface"
}
