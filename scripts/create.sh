#!/usr/bin/env bash

# Check if terraform, packer and hcloud CLIs are present
command -v ssh >/dev/null 2>&1 || {
    echo "openssh is not installed. Install it with 'brew install openssh'."
    exit 1
}

if command -v tofu >/dev/null 2>&1 ; then
    terraform_command=tofu
elif command -v terraform >/dev/null 2>&1 ; then
    terraform_command=terraform
else
    echo "terraform or tofu is not installed. Install it with 'brew tap hashicorp/tap && brew install hashicorp/tap/terraform' or 'brew install opentofu'."
    exit 1
fi

command -v packer >/dev/null 2>&1 || {
    echo "packer is not installed. Install it with 'brew install packer'."
    exit 1
}
command -v hcloud >/dev/null 2>&1 || {
    echo "hcloud (Hetzner CLI) is not installed. Install it with 'brew install hcloud'."
    exit 1
}

# Ask for the folder name
if [ -z "${folder_name}" ] ; then
    read -p "Enter the name of the folder you want to create (leave empty to use the current directory instead, useful for upgrades): " folder_name
fi

# Ask for the folder path only if folder_name is provided
if [ -n "$folder_name" -a -z "${folder_path}" ]; then
    read -p "Enter the path to create the folder in (default: current path): " folder_path
fi

# Set default path if not provided
if [ -z "$folder_path" ]; then
    folder_path="."
fi

# Create the folder if folder_name is provided
if [ -n "$folder_name" ]; then
    mkdir -p "${folder_path}/${folder_name}"
    folder_path="${folder_path}/${folder_name}"
fi

# Download the required files only if they don't exist
if [ ! -e "${folder_path}/kube.tf" ]; then
    curl -sL https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/main/kube.tf.example -o "${folder_path}/kube.tf"
else
    echo "kube.tf already exists. Skipping download."
fi

if [ ! -e "${folder_path}/hcloud-microos-snapshots.pkr.hcl" ]; then
    curl -sL https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/main/packer-template/hcloud-microos-snapshots.pkr.hcl -o "${folder_path}/hcloud-microos-snapshots.pkr.hcl"
else
    echo "hcloud-microos-snapshots.pkr.hcl already exists. Skipping download."
fi

# Leap Micro snapshots (recommended)
if [ ! -e "${folder_path}/hcloud-leapmicro-snapshots.pkr.hcl" ]; then
    curl -sL https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/main/packer-template/hcloud-leapmicro-snapshots.pkr.hcl -o "${folder_path}/hcloud-leapmicro-snapshots.pkr.hcl"
else
    echo "hcloud-leapmicro-snapshots.pkr.hcl already exists. Skipping download."
fi

# Ask which snapshots they want to create
if [ -z "${create_snapshots}" ] ; then
    echo " "
    echo "The snapshots are required and deployed using packer."
    echo "Leap Micro is the recommended default OS for new clusters. MicroOS is kept for legacy/upgrade scenarios."
    echo " "
    read -p "Which snapshots do you want to create now? (leapmicro/microos/both/none) [leapmicro]: " create_snapshots
fi

if [[ -z "$create_snapshots" ]]; then
    create_snapshots="leapmicro"
fi

if [[ "$create_snapshots" =~ ^([Yy]es|[Yy])$ ]]; then
    create_snapshots="leapmicro"
fi

if [[ "$create_snapshots" =~ ^([Nn]o|[Nn])$ ]]; then
    create_snapshots="none"
fi

if [[ "$create_snapshots" != "none" ]]; then
    if [[ -z "$HCLOUD_TOKEN" ]]; then
        read -p "Enter your HCLOUD_TOKEN: " hcloud_token
        export HCLOUD_TOKEN=$hcloud_token
    fi
fi

case "$create_snapshots" in
    leapmicro)
        echo "Running packer build for hcloud-leapmicro-snapshots.pkr.hcl"
        cd "${folder_path}" && packer init hcloud-leapmicro-snapshots.pkr.hcl && packer build hcloud-leapmicro-snapshots.pkr.hcl
        ;;
    microos)
        echo "Running packer build for hcloud-microos-snapshots.pkr.hcl"
        cd "${folder_path}" && packer init hcloud-microos-snapshots.pkr.hcl && packer build hcloud-microos-snapshots.pkr.hcl
        ;;
    both)
        echo "Running packer build for both Leap Micro and MicroOS snapshots"
        cd "${folder_path}" && \
          packer init hcloud-leapmicro-snapshots.pkr.hcl && packer build hcloud-leapmicro-snapshots.pkr.hcl && \
          packer init hcloud-microos-snapshots.pkr.hcl && packer build hcloud-microos-snapshots.pkr.hcl
        ;;
    none)
        echo " "
        echo "You can create the snapshots later by running:"
        echo "  packer build hcloud-leapmicro-snapshots.pkr.hcl"
        echo "  packer build hcloud-microos-snapshots.pkr.hcl"
        ;;
    *)
        echo "Invalid choice for create_snapshots: '$create_snapshots' (expected leapmicro/microos/both/none)"
        exit 1
        ;;
esac

# Output commands
echo " "
echo "Remember, don't skip the hcloud cli, to activate it run 'hcloud context create <project-name>'. It is ideal to quickly debug and allows targeted cleanup when needed!"
echo " "
echo "Before running '${terraform_command} apply', go through the kube.tf file and fill it with your desired values."
