/*
 * Creates a Leap Micro snapshot for Kube-Hetzner
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

variable "leap_micro_version" {
  type        = string
  default     = "6.2"
  description = "OpenSUSE Leap Micro version."
}

variable "k3s_selinux_version" {
  type        = string
  default     = "v1.6.stable.1"
  description = "k3s-selinux release tag to install."
}

variable "k3s_selinux_package_name" {
  type        = string
  default     = ""
  description = "Optional k3s-selinux RPM filename override. If empty, derived from tag using slemicro package form."
}

variable "rke2_selinux_version" {
  type        = string
  default     = "v0.22.stable.1"
  description = "rke2-selinux release tag to install."
}

variable "rke2_selinux_package_name" {
  type        = string
  default     = ""
  description = "Optional rke2-selinux RPM filename override. If empty, derived from tag using slemicro package form."
}

variable "selinux_package_to_install" {
  type        = string
  default     = "k3s"
  description = "Which Kubernetes SELinux package variant to preinstall in the snapshot: k3s or rke2."
}

# We download the OpenSUSE Leap Micro x86 image from an automatically selected mirror.
variable "opensuse_leapmicro_x86_mirror_link" {
  type    = string
  default = ""
}

# We download the OpenSUSE Leap Micro ARM image from an automatically selected mirror.
variable "opensuse_leapmicro_arm_mirror_link" {
  type    = string
  default = ""
}

# If you need to add other packages to the OS, do it here in the default value, like ["vim", "curl", "wget"].
variable "packages_to_install" {
  type    = list(string)
  default = []
}

# Timezone to set on the snapshot (e.g., "Europe/Madrid", "UTC", "America/New_York").
variable "timezone" {
  type    = string
  default = "UTC"
}

# Path to a local file containing sysctl settings (one per line, e.g., "vm.swappiness = 10").
# These will be installed to /etc/sysctl.d/99-custom.conf
variable "sysctl_config_file" {
  type    = string
  default = ""
}

locals {
  opensuse_leapmicro_x86_mirror_link_computed = var.opensuse_leapmicro_x86_mirror_link != "" ? var.opensuse_leapmicro_x86_mirror_link : "https://download.opensuse.org/distribution/leap-micro/${var.leap_micro_version}/appliances/openSUSE-Leap-Micro.x86_64-Default-qcow.qcow2"
  opensuse_leapmicro_arm_mirror_link_computed = var.opensuse_leapmicro_arm_mirror_link != "" ? var.opensuse_leapmicro_arm_mirror_link : "https://download.opensuse.org/distribution/leap-micro/${var.leap_micro_version}/appliances/openSUSE-Leap-Micro.aarch64-Default-qcow.qcow2"

  # Keep this list minimal and known-good on Leap Micro (some MicroOS package names are not available).
  needed_packages = join(" ", concat(["restorecond", "policycoreutils", "policycoreutils-python-utils", "selinux-policy", "checkpolicy", "audit", "open-iscsi", "nfs-client", "xfsprogs", "cryptsetup", "lvm2", "git", "cifs-utils", "bash-completion", "udica", "qemu-guest-agent"], var.packages_to_install))

  # Read sysctl config if file path is provided, otherwise empty (base64 encoded for safe transfer)
  sysctl_config_content = var.sysctl_config_file != "" ? base64encode(file(var.sysctl_config_file)) : ""

  # Commands to write sysctl config if provided (decode base64)
  sysctl_commands = local.sysctl_config_content != "" ? "echo '${local.sysctl_config_content}' | base64 -d > /etc/sysctl.d/99-custom.conf" : ""

  # Keep output low; otherwise long downloads can overwhelm CI/log capture.
  download_image = "wget --progress=dot:giga -nv --timeout=5 --waitretry=5 --tries=5 --retry-connrefused --inet4-only "

  write_image = <<-EOT
    set -ex
    echo 'Leap Micro image loaded, writing to disk... '
    qemu-img convert -p -f qcow2 -O host_device $(ls -a | grep -ie '^opensuse.*leap-micro.*qcow2$') /dev/sda
    echo 'done. Rebooting...'
    sleep 1 && udevadm settle && reboot
  EOT

  install_packages = <<-EOT
    set -ex
    echo "First reboot successful, installing needed packages..."
    transactional-update --continue pkg install -y ${local.needed_packages}
    transactional-update --continue shell <<-'EOF'
    set -euo pipefail
    set -x

    setenforce 0 || true
    rpm --import https://rpm.rancher.io/public.key

    derive_rpm_version() {
      local tag="$1"
      echo "$tag" | sed -E 's/^v//; s/\.(stable|latest|testing)\..*$//'
    }

    install_k3s_selinux() {
      # k3s-selinux tag "v1.6.stable.1" => RPM "k3s-selinux-1.6-1.slemicro.noarch.rpm"
      K3S_TAG="${var.k3s_selinux_version}"
      K3S_RPM_VERSION="$(derive_rpm_version "$K3S_TAG")"
      if [ -z "$K3S_RPM_VERSION" ]; then
        echo "ERROR: failed to derive k3s-selinux RPM version from tag '$K3S_TAG'" >&2
        exit 1
      fi

      K3S_PACKAGE="${var.k3s_selinux_package_name}"
      if [ -z "$K3S_PACKAGE" ]; then
        K3S_PACKAGE="k3s-selinux-$K3S_RPM_VERSION-1.slemicro.noarch.rpm"
      fi

      K3S_URL="https://github.com/k3s-io/k3s-selinux/releases/download/$K3S_TAG/$K3S_PACKAGE"
      zypper --non-interactive install -y "$K3S_URL"
      rpm -q k3s-selinux
      zypper addlock k3s-selinux
    }

    install_rke2_selinux() {
      # rke2-selinux tag "v0.22.stable.1" => RPM "rke2-selinux-0.22-1.slemicro.noarch.rpm"
      RKE2_TAG="${var.rke2_selinux_version}"
      RKE2_RPM_VERSION="$(derive_rpm_version "$RKE2_TAG")"
      if [ -z "$RKE2_RPM_VERSION" ]; then
        echo "ERROR: failed to derive rke2-selinux RPM version from tag '$RKE2_TAG'" >&2
        exit 1
      fi

      RKE2_PACKAGE="${var.rke2_selinux_package_name}"
      if [ -z "$RKE2_PACKAGE" ]; then
        RKE2_PACKAGE="rke2-selinux-$RKE2_RPM_VERSION-1.slemicro.noarch.rpm"
      fi

      RKE2_URL="https://github.com/rancher/rke2-selinux/releases/download/$RKE2_TAG/$RKE2_PACKAGE"
      zypper --non-interactive install -y "$RKE2_URL"
      rpm -q rke2-selinux
      zypper addlock rke2-selinux
    }

    case "${var.selinux_package_to_install}" in
      k3s)
        install_k3s_selinux
        ;;
      rke2)
        install_rke2_selinux
        ;;
      *)
        echo "ERROR: invalid selinux_package_to_install='${var.selinux_package_to_install}', expected one of: k3s, rke2" >&2
        exit 1
        ;;
    esac

    restorecon -Rv /etc/selinux/targeted/policy
    restorecon -Rv /var/lib
    setenforce 1 || true

    ${local.sysctl_commands}
EOF
    sleep 1 && udevadm settle && reboot
  EOT

  clean_up = <<-EOT
    set -ex
    echo "Second reboot successful, cleaning-up..."
    case "${var.selinux_package_to_install}" in
      k3s)
        rpm -q k3s-selinux
        ;;
      rke2)
        rpm -q rke2-selinux
        ;;
      *)
        echo "ERROR: invalid selinux_package_to_install='${var.selinux_package_to_install}' during verification" >&2
        exit 1
        ;;
    esac
    rm -rf /etc/ssh/ssh_host_*
    echo "Make sure to use NetworkManager"
    touch /etc/NetworkManager/NetworkManager.conf
    echo "Setting timezone to '${var.timezone}'..."
    timedatectl set-timezone '${var.timezone}'
    echo "Running fstrim to reduce snapshot size..."
    fstrim -av || true
    sleep 1 && udevadm settle
  EOT
}

# Source for the Leap Micro x86 snapshot
source "hcloud" "leapmicro-x86-snapshot" {
  image       = "ubuntu-24.04"
  rescue      = "linux64"
  location    = "nbg1"
  server_type = "cx23" # disk size of >= 40GiB is needed to install the Leap Micro image
  snapshot_labels = {
    leapmicro-snapshot        = "yes"
    creator                   = "kube-hetzner"
    "kube-hetzner/os"         = "leapmicro"
    "kube-hetzner/arch"       = "x86"
    "kube-hetzner/k8s-distro" = var.selinux_package_to_install
  }
  snapshot_name = "OpenSUSE Leap Micro x86 ${upper(var.selinux_package_to_install)} by Kube-Hetzner"
  ssh_username  = "root"
  token         = var.hcloud_token
}

# Source for the Leap Micro ARM snapshot
source "hcloud" "leapmicro-arm-snapshot" {
  image       = "ubuntu-24.04"
  rescue      = "linux64"
  location    = "nbg1"
  server_type = "cax11" # disk size of >= 40GiB is needed to install the Leap Micro image
  snapshot_labels = {
    leapmicro-snapshot        = "yes"
    creator                   = "kube-hetzner"
    "kube-hetzner/os"         = "leapmicro"
    "kube-hetzner/arch"       = "arm"
    "kube-hetzner/k8s-distro" = var.selinux_package_to_install
  }
  snapshot_name = "OpenSUSE Leap Micro ARM ${upper(var.selinux_package_to_install)} by Kube-Hetzner"
  ssh_username  = "root"
  token         = var.hcloud_token
}

# Build the Leap Micro x86 snapshot
build {
  sources = ["source.hcloud.leapmicro-x86-snapshot"]

  provisioner "shell" {
    inline = ["${local.download_image}${local.opensuse_leapmicro_x86_mirror_link_computed}"]
  }

  provisioner "shell" {
    inline            = [local.write_image]
    expect_disconnect = true
  }

  provisioner "shell" {
    pause_before      = "5s"
    inline            = [local.install_packages]
    expect_disconnect = true
  }

  provisioner "shell" {
    pause_before = "5s"
    inline       = [local.clean_up]
  }
}

# Build the Leap Micro ARM snapshot
build {
  sources = ["source.hcloud.leapmicro-arm-snapshot"]

  provisioner "shell" {
    inline = ["${local.download_image}${local.opensuse_leapmicro_arm_mirror_link_computed}"]
  }

  provisioner "shell" {
    inline            = [local.write_image]
    expect_disconnect = true
  }

  provisioner "shell" {
    pause_before      = "5s"
    inline            = [local.install_packages]
    expect_disconnect = true
  }

  provisioner "shell" {
    pause_before = "5s"
    inline       = [local.clean_up]
  }
}
