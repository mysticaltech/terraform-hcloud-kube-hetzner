#!/usr/bin/env bash

DRY_RUN=1

echo "Welcome to the Kube-Hetzner cluster deletion script!"
echo " "
echo "We advise you to first run 'terraform destroy' and execute that script when it starts hanging because of resources still attached to the network."
echo "In order to run this script need to have the hcloud CLI installed and configured with a context for the cluster you want to delete."
command -v hcloud >/dev/null 2>&1 || { echo "hcloud (Hetzner CLI) is not installed. Install it with 'brew install hcloud'."; exit 1; }
echo "You can do so by running 'hcloud context create <cluster_name>' and inputting your HCLOUD_TOKEN."
echo " "

if command -v tofu >/dev/null 2>&1 ; then
    terraform_command=tofu
elif command -v terraform >/dev/null 2>&1 ; then
    terraform_command=terraform
else
    echo "terraform or tofu is not installed. Install it with 'brew install terraform' or 'brew install opentofu'."
    exit 1
fi


# Try to guess the cluster name
GUESSED_CLUSTER_NAME=$(sed -n 's/^[[:space:]]*cluster_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' kube.tf 2>/dev/null)

if [ -n "$GUESSED_CLUSTER_NAME" ]; then
  echo "Cluster name '$GUESSED_CLUSTER_NAME' has been detected in the kube.tf file."
  read -p "Enter the name of the cluster to delete (default: $GUESSED_CLUSTER_NAME): " CLUSTER_NAME
  if [ -z "$CLUSTER_NAME" ]; then
    CLUSTER_NAME="$GUESSED_CLUSTER_NAME"
  fi
else
  read -p "Enter the name of the cluster to delete: " CLUSTER_NAME
fi

while true; do
  read -p "Do you want to perform a dry run? (yes/no): " dry_run_input
  case $dry_run_input in
    [Yy]* ) DRY_RUN=1; break;;
    [Nn]* ) DRY_RUN=0; break;;
    * ) echo "Please answer yes or no.";;
  esac
done

read -p "Do you want to delete volumes? (yes/no, default: no): " delete_volumes_input
DELETE_VOLUMES=0
if [[ "$delete_volumes_input" =~ ^([Yy]es|[Yy])$ ]]; then
  DELETE_VOLUMES=1
fi

read -p "Do you want to delete MicroOS snapshots? (yes/no, default: no): " delete_microos_snapshots_input
DELETE_MICROOS_SNAPSHOTS=0
if [[ "$delete_microos_snapshots_input" =~ ^([Yy]es|[Yy])$ ]]; then
  DELETE_MICROOS_SNAPSHOTS=1
fi

read -p "Do you want to delete Leap Micro snapshots? (yes/no, default: no): " delete_leapmicro_snapshots_input
DELETE_LEAPMICRO_SNAPSHOTS=0
if [[ "$delete_leapmicro_snapshots_input" =~ ^([Yy]es|[Yy])$ ]]; then
  DELETE_LEAPMICRO_SNAPSHOTS=1
fi

if (( DRY_RUN == 0 )); then
  echo "WARNING: STUFF WILL BE DELETED!"
else
  echo "Performing a dry run, nothing will be deleted."
fi

HCLOUD_SELECTOR=(--selector='provisioner=terraform' --selector="cluster=$CLUSTER_NAME")
HCLOUD_OUTPUT_OPTIONS=(-o noheader -o 'columns=id')

VOLUMES=()
while IFS='' read -r line; do VOLUMES+=("$line"); done < <(hcloud volume list "${HCLOUD_SELECTOR[@]}" "${HCLOUD_OUTPUT_OPTIONS[@]}")

SERVERS=()
while IFS='' read -r line; do SERVERS+=("$line"); done < <(hcloud server list "${HCLOUD_SELECTOR[@]}" "${HCLOUD_OUTPUT_OPTIONS[@]}")

PLACEMENT_GROUPS=()
while IFS='' read -r line; do PLACEMENT_GROUPS+=("$line"); done < <(hcloud placement-group list "${HCLOUD_SELECTOR[@]}" "${HCLOUD_OUTPUT_OPTIONS[@]}")

LOAD_BALANCERS=()
while IFS='' read -r line; do LOAD_BALANCERS+=("$line"); done < <(hcloud load-balancer list "${HCLOUD_SELECTOR[@]}" "${HCLOUD_OUTPUT_OPTIONS[@]}")

INGRESS_LB=$(hcloud load-balancer list -o noheader -o columns=id,name | grep "${CLUSTER_NAME}" | cut -d ' ' -f1 )

if [[ $INGRESS_LB != "" ]]; then
  LOAD_BALANCERS+=( "$INGRESS_LB" )
fi

FIREWALLS=()
while IFS='' read -r line; do FIREWALLS+=("$line"); done < <(hcloud firewall list "${HCLOUD_SELECTOR[@]}" "${HCLOUD_OUTPUT_OPTIONS[@]}")

NETWORKS=()
while IFS='' read -r line; do NETWORKS+=("$line"); done < <(hcloud network list "${HCLOUD_SELECTOR[@]}" "${HCLOUD_OUTPUT_OPTIONS[@]}")

SSH_KEYS=()
while IFS='' read -r line; do SSH_KEYS+=("$line"); done < <(hcloud ssh-key list "${HCLOUD_SELECTOR[@]}" "${HCLOUD_OUTPUT_OPTIONS[@]}")

function detach_volumes() {
  for ID in "${VOLUMES[@]}"; do
    echo "Detach volume: $ID"
    if (( DRY_RUN == 0 )); then
      hcloud volume detach "$ID"
    fi
  done
}

function delete_volumes() {
  for ID in "${VOLUMES[@]}"; do
    echo "Delete volume: $ID"
    if (( DRY_RUN == 0 )); then
      hcloud volume delete "$ID"
    fi
  done
}

function delete_servers() {
  for ID in "${SERVERS[@]}"; do
    echo "Delete server: $ID"
    if (( DRY_RUN == 0 )); then
      hcloud server delete "$ID"
    fi
  done
}

function delete_placement_groups() {
  for ID in "${PLACEMENT_GROUPS[@]}"; do
    echo "Delete placement-group: $ID"
    if (( DRY_RUN == 0 )); then
      hcloud placement-group delete "$ID"
    fi
  done
}

function delete_load_balancer() {
  for ID in "${LOAD_BALANCERS[@]}"; do
    echo "Delete load-balancer: $ID"
    if (( DRY_RUN == 0 )); then
      hcloud load-balancer delete "$ID"
    fi
  done
}

function delete_firewalls() {
  for ID in "${FIREWALLS[@]}"; do
    echo "Delete firewall: $ID"
    if (( DRY_RUN == 0 )); then
      hcloud firewall delete "$ID"
    fi
  done
}

function delete_networks() {
  for ID in "${NETWORKS[@]}"; do
    echo "Delete network: $ID"
    if (( DRY_RUN == 0 )); then
      hcloud network delete "$ID"
    fi
  done
}

function delete_ssh_keys() {
  for ID in "${SSH_KEYS[@]}"; do
    echo "Delete ssh-key: $ID"
    if (( DRY_RUN == 0 )); then
      hcloud ssh-key delete "$ID"
    fi
  done
}

function delete_autoscaled_nodes() {
  local servers=()
  while IFS='' read -r line; do servers+=("$line"); done < <(hcloud server list -o noheader -o 'columns=id,name' | grep "${CLUSTER_NAME}")

  for server_info in "${servers[@]}"; do
    local ID=$(echo "$server_info" | awk '{print $1}')
    local server_name=$(echo "$server_info" | awk '{print $2}')
    echo "Delete autoscaled server: $ID (Name: $server_name)"
    if (( DRY_RUN == 0 )); then
      hcloud server delete "$ID"
    fi
  done
}

function delete_snapshots_by_selector() {
  local selector="$1"
  local snapshots=()
  while IFS='' read -r line; do snapshots+=("$line"); done < <(hcloud image list --selector "$selector" -o noheader -o 'columns=id,name')

  for snapshot_info in "${snapshots[@]}"; do
    local ID=$(echo "$snapshot_info" | awk '{print $1}')
    local snapshot_name=$(echo "$snapshot_info" | awk '{print $2}')
    echo "Delete snapshot: $ID (Name: $snapshot_name)"
    if (( DRY_RUN == 0 )); then
      hcloud image delete "$ID"
    fi
  done
}

if (( DRY_RUN > 0 )); then
  echo "Dry run, nothing will be deleted!"
fi

detach_volumes
if (( DELETE_VOLUMES == 1 )); then
  delete_volumes
fi
delete_servers
delete_autoscaled_nodes
delete_placement_groups
delete_load_balancer
delete_networks
delete_firewalls
delete_ssh_keys


if (( DELETE_MICROOS_SNAPSHOTS == 1 )); then
  delete_snapshots_by_selector "microos-snapshot=yes"
fi

if (( DELETE_LEAPMICRO_SNAPSHOTS == 1 )); then
  delete_snapshots_by_selector "leapmicro-snapshot=yes"
fi
