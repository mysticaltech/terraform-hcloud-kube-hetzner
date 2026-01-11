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

resource "random_string" "identity_file" {
  length  = 20
  lower   = true
  special = false
  numeric = true
  upper   = false
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
  image              = var.microos_snapshot_id
  server_type        = var.server_type
  location           = var.location
  ssh_keys           = var.ssh_keys
  firewall_ids       = var.firewall_ids
  placement_group_id = var.placement_group_id
  backups            = var.backups
  user_data          = data.cloudinit_config.config.rendered
  keep_disk          = var.keep_disk_size
  public_net {
    ipv4_enabled = !var.disable_ipv4
    ipv6_enabled = !var.disable_ipv6
  }

  network {
    network_id = var.network_id
    ip         = var.private_ipv4
    alias_ips  = []
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

  }

  # Prepare ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      install -b -m 600 /dev/null /tmp/${random_string.identity_file.id}
      echo "${local.ssh_client_identity}" | sed 's/\r$//' > /tmp/${random_string.identity_file.id}
    EOT
  }

  # Wait for MicroOS to reboot and be ready.
  provisioner "local-exec" {
    command = <<-EOT
      timeout 600 bash <<EOF
          until ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} ${local.ssh_proxy_jump} -o ConnectTimeout=10 -p ${var.ssh_port} root@${coalesce(self.ipv4_address, self.ipv6_address, try(one(self.network).ip, null))} true 2> /dev/null
          do
            echo "Waiting for MicroOS to become available..."
            sleep 3
          done
      EOF
    EOT
  }

  # Cleanup ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      rm /tmp/${random_string.identity_file.id}
    EOT
  }


  provisioner "remote-exec" {
    inline = var.automatically_upgrade_os ? [
      <<-EOT
      echo "Automatic OS updates are enabled"
      EOT
      ] : [
      <<-EOT
      echo "Automatic OS updates are disabled"
      systemctl --now disable transactional-update.timer
      EOT
    ]
  }

}

resource "null_resource" "registries" {
  triggers = {
    registries = var.k3s_registries
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = coalesce(hcloud_server.server.ipv4_address, hcloud_server.server.ipv6_address, try(one(hcloud_server.server.network).ip, null))
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
        swap_size                    = var.swap_size
        private_network_only         = (var.disable_ipv4 && var.disable_ipv6)
        network_gw_ipv4              = var.network_gw_ipv4
      }
    )
  }
}

resource "null_resource" "zram" {
  triggers = {
    zram_size = var.zram_size
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = coalesce(hcloud_server.server.ipv4_address, hcloud_server.server.ipv6_address, try(one(hcloud_server.server.network).ip, null))
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

# Resource to toggle transactional-update.timer based on automatically_upgrade_os setting
resource "null_resource" "os_upgrade_toggle" {
  triggers = {
    os_upgrade_state = var.automatically_upgrade_os ? "enabled" : "disabled"
    server_id        = hcloud_server.server.id
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = coalesce(hcloud_server.server.ipv4_address, hcloud_server.server.ipv6_address, try(one(hcloud_server.server.network).ip, null))
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
    null_resource.registries
  ]
}
