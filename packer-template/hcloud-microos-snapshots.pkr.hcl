/*
 * Creates a MicroOS snapshot for Kube-Hetzner
 */
packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.5"
      source  = "github.com/hetznercloud/hcloud"
    }
  }
}

variable "hcloud_token" {
  type      = string
  default   = env("HCLOUD_TOKEN")
  sensitive = true
}

# We download the OpenSUSE MicroOS x86 image from an automatically selected mirror.
variable "opensuse_microos_x86_mirror_link" {
  type    = string
  default = "https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-ContainerHost-OpenStack-Cloud.qcow2"
}

# We download the OpenSUSE MicroOS ARM image from an automatically selected mirror.
variable "opensuse_microos_arm_mirror_link" {
  type    = string
  default = "https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-MicroOS.aarch64-ContainerHost-OpenStack-Cloud.qcow2"
}

# If you need to add other packages to the OS, do it here in the default value, like ["vim", "curl", "wget"]
# When looking for packages, you need to search for OpenSUSE Tumbleweed packages, as MicroOS is based on Tumbleweed.
variable "packages_to_install" {
  type    = list(string)
  default = []
}

# Choose which kernel to use: "default" for the rolling release kernel or "longterm" for LTS kernel
variable "kernel_type" {
  type    = string
  default = "default"
  validation {
    condition     = contains(["longterm", "default"], var.kernel_type)
    error_message = "The kernel_type must be either longterm or default."
  }
}

locals {
  # Only install kernel-longterm if selected; kernel-default is already in the base image
  kernel_package_list = var.kernel_type == "longterm" ? ["kernel-longterm"] : []

  needed_packages = join(" ", concat(local.kernel_package_list, ["restorecond", "policycoreutils", "policycoreutils-python-utils", "setools-console", "audit", "bind-utils", "wireguard-tools", "fuse", "open-iscsi", "nfs-client", "xfsprogs", "cryptsetup", "lvm2", "git", "cifs-utils", "bash-completion", "mtr", "tcpdump", "udica", "qemu-guest-agent"], var.packages_to_install))

  # Add local variables for inline shell commands
  download_image = "wget --timeout=5 --waitretry=5 --tries=5 --retry-connrefused --inet4-only "

  write_image = <<-EOT
    set -ex
    echo 'MicroOS image loaded, writing to disk... '
    qemu-img convert -p -f qcow2 -O host_device $(ls -a | grep -ie '^opensuse.*microos.*qcow2$') /dev/sda
    echo 'done. Rebooting...'
    sleep 1 && udevadm settle && reboot
  EOT

  # Kernel switching commands: remove kernel-default and lock it when using longterm
  # This ensures GRUB always boots the longterm kernel without complex configuration
  kernel_switch_commands = var.kernel_type == "longterm" ? join("\n", [
    "zypper rm -y kernel-default",
    "zypper addlock kernel-default",
    "grub2-mkconfig -o /boot/grub2/grub.cfg"
  ]) : "true"

  install_packages = <<-EOT
    set -ex
    echo "First reboot successful, installing needed packages..."
    transactional-update --continue pkg install -y ${local.needed_packages}
    transactional-update --continue shell <<- EOF
    setenforce 0
    rpm --import https://rpm.rancher.io/public.key
    zypper install -y https://github.com/k3s-io/k3s-selinux/releases/download/v1.6.stable.1/k3s-selinux-1.6-1.sle.noarch.rpm
    zypper addlock k3s-selinux
    restorecon -Rv /etc/selinux/targeted/policy
    restorecon -Rv /var/lib
    setenforce 1
    ${local.kernel_switch_commands}
    EOF
    sleep 1 && udevadm settle && reboot
  EOT

  clean_up = <<-EOT
    set -ex
    echo "Second reboot successful, cleaning-up..."
    rm -rf /etc/ssh/ssh_host_*
    echo "Make sure to use NetworkManager"
    touch /etc/NetworkManager/NetworkManager.conf
    sleep 1 && udevadm settle
  EOT
}

# Source for the MicroOS x86 snapshot
source "hcloud" "microos-x86-snapshot" {
  image       = "ubuntu-24.04"
  rescue      = "linux64"
  location    = "nbg1"
  server_type = "cx23" # disk size of >= 40GiB is needed to install the MicroOS image
  snapshot_labels = {
    microos-snapshot = "yes"
    creator          = "kube-hetzner"
  }
  snapshot_name = "OpenSUSE MicroOS x86 by Kube-Hetzner"
  ssh_username  = "root"
  token         = var.hcloud_token
}

# Source for the MicroOS ARM snapshot
source "hcloud" "microos-arm-snapshot" {
  image       = "ubuntu-24.04"
  rescue      = "linux64"
  location    = "nbg1"
  server_type = "cax11" # disk size of >= 40GiB is needed to install the MicroOS image
  snapshot_labels = {
    microos-snapshot = "yes"
    creator          = "kube-hetzner"
  }
  snapshot_name = "OpenSUSE MicroOS ARM by Kube-Hetzner"
  ssh_username  = "root"
  token         = var.hcloud_token
}

# Build the MicroOS x86 snapshot
build {
  sources = ["source.hcloud.microos-x86-snapshot"]

  # Download the MicroOS x86 image
  provisioner "shell" {
    inline = ["${local.download_image}${var.opensuse_microos_x86_mirror_link}"]
  }

  # Write the MicroOS x86 image to disk
  provisioner "shell" {
    inline            = [local.write_image]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS x86 and do house-keeping
  provisioner "shell" {
    pause_before      = "5s"
    inline            = [local.install_packages]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS x86 and do house-keeping
  provisioner "shell" {
    pause_before = "5s"
    inline       = [local.clean_up]
  }
}

# Build the MicroOS ARM snapshot
build {
  sources = ["source.hcloud.microos-arm-snapshot"]

  # Download the MicroOS ARM image
  provisioner "shell" {
    inline = ["${local.download_image}${var.opensuse_microos_arm_mirror_link}"]
  }

  # Write the MicroOS ARM image to disk
  provisioner "shell" {
    inline            = [local.write_image]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS ARM and do house-keeping
  provisioner "shell" {
    pause_before      = "5s"
    inline            = [local.install_packages]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS ARM and do house-keeping
  provisioner "shell" {
    pause_before = "5s"
    inline       = [local.clean_up]
  }
}
