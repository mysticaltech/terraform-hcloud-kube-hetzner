resource "random_string" "server" {
  length  = 3
  lower   = true
  special = false
  numeric = false
  upper   = false

  keepers = {
    # We re-create the apart of the name changes.
    name = var.name
  }
}

variable "network" {
  type = object({
    network_id = number
    ip         = string
    alias_ips  = list(string)
  })
  default = null
}

resource "hcloud_server" "server" {
  name               = local.name
  image              = var.os_snapshot_id
  server_type        = var.server_type
  location           = var.location
  ssh_keys           = var.ssh_keys
  firewall_ids       = local.effective_firewall_ids
  placement_group_id = var.placement_group_id
  backups            = var.backups
  user_data          = data.cloudinit_config.config.rendered
  keep_disk          = var.keep_disk_size
  public_net {
    ipv4_enabled = !var.disable_ipv4
    ipv4         = var.disable_ipv4 ? null : var.primary_ipv4_id
    ipv6_enabled = !var.disable_ipv6
    ipv6         = var.disable_ipv6 ? null : var.primary_ipv6_id
  }

  dynamic "network" {
    for_each = var.private_ipv4 == null ? [1] : []
    content {
      network_id = var.network_id
      alias_ips  = []
    }
  }

  dynamic "network" {
    for_each = var.private_ipv4 == null ? [] : [1]
    content {
      network_id = var.network_id
      ip         = var.private_ipv4
      alias_ips  = []
    }
  }

  labels = var.labels

  # Prevent destroying the whole cluster if the user changes
  # any of the attributes that force to recreate the servers.
  lifecycle {
    ignore_changes = [
      location,
      ssh_keys,
      user_data,
      image,
    ]
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = coalesce(self.ipv4_address, self.ipv6_address, try(one(self.network).ip, null))
    port           = var.ssh_port

    bastion_host        = var.ssh_bastion.bastion_host
    bastion_port        = var.ssh_bastion.bastion_port
    bastion_user        = var.ssh_bastion.bastion_user
    bastion_private_key = var.ssh_bastion.bastion_private_key

    timeout = "10m"
  }

  provisioner "remote-exec" {
    inline = concat([
      "echo 'Waiting for system to become fully ready...'",

      # Wait until the system is fully booted and in a running state.
      "timeout 600 bash -c 'until systemctl is-system-running --quiet; do echo \"Waiting for system...\"; sleep 3; done'",

      "echo 'System is fully ready!'"
      ],
      var.automatically_upgrade_os ? [
        <<-EOT
        echo "Automatic OS updates are enabled"
        EOT
        ] : [
        <<-EOT
        echo "Automatic OS updates are disabled"
        systemctl --now disable transactional-update.timer
        EOT
    ])
  }

}

resource "hcloud_server_network" "extra_networks" {
  for_each = {
    for network_id in local.extra_network_ids : tostring(network_id) => network_id
  }

  server_id  = hcloud_server.server.id
  network_id = each.value
}

resource "terraform_data" "ssh_authorized_keys" {
  triggers_replace = {
    server_id           = hcloud_server.server.id
    ssh_public_key      = sha1(var.ssh_public_key)
    ssh_additional_keys = sha1(join("\n", var.ssh_additional_public_keys))
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.provisioner_connection_host
    port           = var.ssh_port

    bastion_host        = var.ssh_bastion.bastion_host
    bastion_port        = var.ssh_bastion.bastion_port
    bastion_user        = var.ssh_bastion.bastion_user
    bastion_private_key = var.ssh_bastion.bastion_private_key
  }

  provisioner "file" {
    content = format(
      "%s\n",
      join("\n", distinct(compact(concat(
        [trimspace(var.ssh_public_key)],
        [for key in var.ssh_additional_public_keys : trimspace(key)]
      ))))
    )
    destination = "/tmp/authorized_keys"
  }

  provisioner "remote-exec" {
    inline = [
      "install -d -m 0700 /root/.ssh",
      "install -m 0600 /tmp/authorized_keys /root/.ssh/authorized_keys",
      "chown root:root /root/.ssh /root/.ssh/authorized_keys",
      "rm -f /tmp/authorized_keys",
    ]
  }

  depends_on = [hcloud_server.server]
}

resource "terraform_data" "registries" {
  triggers_replace = {
    registries = var.k3s_registries
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.provisioner_connection_host
    port           = var.ssh_port

    bastion_host        = var.ssh_bastion.bastion_host
    bastion_port        = var.ssh_bastion.bastion_port
    bastion_user        = var.ssh_bastion.bastion_user
    bastion_private_key = var.ssh_bastion.bastion_private_key

  }

  provisioner "file" {
    content     = var.k3s_registries
    destination = "/tmp/registries.yaml"
  }

  provisioner "remote-exec" {
    inline = [var.k3s_registries_update_script]
  }

  depends_on = [hcloud_server.server]
}
moved {
  from = null_resource.registries
  to   = terraform_data.registries
}

resource "terraform_data" "kubelet_config" {
  count = var.k3s_kubelet_config != "" ? 1 : 0

  triggers_replace = {
    kubelet_config = var.k3s_kubelet_config
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.provisioner_connection_host
    port           = var.ssh_port

    bastion_host        = var.ssh_bastion.bastion_host
    bastion_port        = var.ssh_bastion.bastion_port
    bastion_user        = var.ssh_bastion.bastion_user
    bastion_private_key = var.ssh_bastion.bastion_private_key
  }

  provisioner "file" {
    content     = var.k3s_kubelet_config
    destination = "/tmp/kubelet-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [var.k3s_kubelet_config_update_script]
  }

  depends_on = [hcloud_server.server]
}
moved {
  from = null_resource.kubelet_config
  to   = terraform_data.kubelet_config
}

resource "terraform_data" "audit_policy" {
  count = var.k3s_audit_policy_config != "" ? 1 : 0

  triggers_replace = {
    audit_policy = var.k3s_audit_policy_config
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.provisioner_connection_host
    port           = var.ssh_port

    bastion_host        = var.ssh_bastion.bastion_host
    bastion_port        = var.ssh_bastion.bastion_port
    bastion_user        = var.ssh_bastion.bastion_user
    bastion_private_key = var.ssh_bastion.bastion_private_key
  }

  provisioner "file" {
    content     = var.k3s_audit_policy_config
    destination = "/tmp/audit-policy.yaml"
  }

  provisioner "remote-exec" {
    inline = [var.k3s_audit_policy_update_script]
  }

  depends_on = [hcloud_server.server]
}
moved {
  from = null_resource.audit_policy
  to   = terraform_data.audit_policy
}

resource "hcloud_rdns" "server" {
  count = (var.base_domain != "" && !var.disable_ipv4) ? 1 : 0

  server_id  = hcloud_server.server.id
  ip_address = coalesce(hcloud_server.server.ipv4_address, try(one(hcloud_server.server.network).ip, null))
  dns_ptr    = format("%s.%s", local.name, var.base_domain)
}

resource "hcloud_rdns" "server_ipv6" {
  count = (var.base_domain != "" && !var.disable_ipv6) ? 1 : 0

  server_id  = hcloud_server.server.id
  ip_address = hcloud_server.server.ipv6_address
  dns_ptr    = format("%s.%s", local.name, var.base_domain)
}


data "cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/templates/cloudinit.yaml.tpl",
      {
        hostname                     = local.name
        dns_servers                  = var.dns_servers
        has_dns_servers              = local.has_dns_servers
        sshAuthorizedKeys            = concat([var.ssh_public_key], var.ssh_additional_public_keys)
        cloudinit_write_files_common = var.cloudinit_write_files_common
        cloudinit_runcmd_common      = var.cloudinit_runcmd_common
        cloudinit_write_files_extra  = var.cloudinit_write_files_extra
        cloudinit_runcmd_extra       = var.cloudinit_runcmd_extra
        swap_size                    = var.swap_size
        os                           = var.os
        private_network_only         = (var.disable_ipv4 && var.disable_ipv6)
        network_gw_ipv4              = var.network_gw_ipv4
      }
    )
  }
}

resource "terraform_data" "zram" {
  triggers_replace = {
    zram_size = var.zram_size
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.provisioner_connection_host
    port           = var.ssh_port

    bastion_host        = var.ssh_bastion.bastion_host
    bastion_port        = var.ssh_bastion.bastion_port
    bastion_user        = var.ssh_bastion.bastion_user
    bastion_private_key = var.ssh_bastion.bastion_private_key

  }

  provisioner "file" {
    content     = <<-EOT
#!/bin/bash

# Switching off swap
swapoff /dev/zram0

rmmod zram
    EOT
    destination = "/usr/local/bin/k3s-swapoff"
  }

  provisioner "file" {
    content     = <<-EOT
#!/bin/bash

# get the amount of memory in the machine
# load the dependency module
modprobe zram

# initialize the device with zstd compression algorithm
echo zstd > /sys/block/zram0/comp_algorithm;
echo ${var.zram_size} > /sys/block/zram0/disksize

# Creating the swap filesystem
mkswap /dev/zram0

# Switch the swaps on
swapon -p 100 /dev/zram0
    EOT
    destination = "/usr/local/bin/k3s-swapon"
  }

  # Setup zram if it's enabled
  provisioner "file" {
    content     = <<-EOT
[Unit]
Description=Swap with zram
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/local/bin/k3s-swapon
ExecStop=/usr/local/bin/k3s-swapoff

[Install]
WantedBy=multi-user.target
    EOT
    destination = "/etc/systemd/system/zram.service"
  }

  provisioner "remote-exec" {
    inline = concat(var.zram_size != "" ? [
      "chmod +x /usr/local/bin/k3s-swapon",
      "chmod +x /usr/local/bin/k3s-swapoff",
      "systemctl disable --now zram.service",
      "systemctl enable --now zram.service",
      ] : [
      "systemctl disable --now zram.service",
    ])
  }

  depends_on = [hcloud_server.server]
}

moved {
  from = null_resource.zram
  to   = terraform_data.zram
}

# Resource to toggle transactional-update.timer based on automatically_upgrade_os setting
resource "terraform_data" "os_upgrade_toggle" {
  triggers_replace = {
    os_upgrade_state = var.automatically_upgrade_os ? "enabled" : "disabled"
    server_id        = hcloud_server.server.id
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.provisioner_connection_host
    port           = var.ssh_port

    bastion_host        = var.ssh_bastion.bastion_host
    bastion_port        = var.ssh_bastion.bastion_port
    bastion_user        = var.ssh_bastion.bastion_user
    bastion_private_key = var.ssh_bastion.bastion_private_key

  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      if [ "${var.automatically_upgrade_os}" = "true" ]; then
        echo "automatically_upgrade_os changed to true, enabling transactional-update.timer"
        systemctl enable --now transactional-update.timer || true
      else
        echo "automatically_upgrade_os changed to false, disabling transactional-update.timer"
        systemctl disable --now transactional-update.timer || true
      fi
      EOT
    ]
  }

  depends_on = [
    hcloud_server.server,
    terraform_data.registries
  ]
}

moved {
  from = null_resource.os_upgrade_toggle
  to   = terraform_data.os_upgrade_toggle
}
