#!/usr/bin/env bash

# Prefer the engine that actually initialized this root: an initialized
# .terraform/providers tree references registry.opentofu.org for tofu roots
# and registry.terraform.io for terraform roots. Running the other binary
# fails init on the lockfile. Fall back to tofu-then-terraform when the root
# is uninitialized or ambiguous.
terraform_command=""
if [ -d .terraform/providers/registry.opentofu.org ] && command -v tofu >/dev/null 2>&1; then
    terraform_command=tofu
elif [ -d .terraform/providers/registry.terraform.io ] && command -v terraform >/dev/null 2>&1; then
    terraform_command=terraform
elif command -v tofu >/dev/null 2>&1 ; then
    terraform_command=tofu
elif command -v terraform >/dev/null 2>&1 ; then
    terraform_command=terraform
else
    echo "terraform or tofu is not installed. Install it with 'brew tap hashicorp/tap && brew install hashicorp/tap/terraform' or 'brew install opentofu'."
    exit 1
fi
echo "Using ${terraform_command} (detected from this root's provider tree)." 

MAX_RETRIES=2
RETRY_WAIT_SECONDS=30
DESTROY_LOG=$(mktemp -t kube-hetzner-destroy.XXXXXX)
trap 'rm -f "$DESTROY_LOG"' EXIT

GUESSED_CLUSTER_NAME=$(sed -n 's/^[[:space:]]*cluster_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' kube.tf 2>/dev/null)

if [ -z "$CLUSTER_NAME" ]; then
  if [ -n "$GUESSED_CLUSTER_NAME" ]; then
    if [ -t 0 ]; then
      echo "Cluster name '$GUESSED_CLUSTER_NAME' has been detected in the kube.tf file."
      read -r -p "Enter the name of the cluster to check for orphans after destroy (default: $GUESSED_CLUSTER_NAME): " CLUSTER_NAME
      if [ -z "$CLUSTER_NAME" ]; then
        CLUSTER_NAME="$GUESSED_CLUSTER_NAME"
      fi
    else
      CLUSTER_NAME="$GUESSED_CLUSTER_NAME"
    fi
  elif [ -t 0 ]; then
    read -r -p "Enter the name of the cluster to check for orphans after destroy (leave empty to skip hcloud orphan report): " CLUSTER_NAME
  fi
fi

function has_auto_approve_arg() {
  local arg
  for arg in "$@"; do
    if [ "$arg" = "-auto-approve" ]; then
      return 0
    fi
  done
  return 1
}

function run_destroy() {
  : > "$DESTROY_LOG"
  "$terraform_command" destroy "$@" 2>&1 | tee "$DESTROY_LOG"
  return "${PIPESTATUS[0]}"
}

function run_retry_destroy() {
  : > "$DESTROY_LOG"
  if has_auto_approve_arg "$@"; then
    "$terraform_command" destroy "$@" 2>&1 | tee "$DESTROY_LOG"
  else
    "$terraform_command" destroy -auto-approve "$@" 2>&1 | tee "$DESTROY_LOG"
  fi
  return "${PIPESTATUS[0]}"
}

function destroy_started() {
  grep -Eiq 'Destroying\.\.\.|Still destroying|Destruction complete after|Destroy complete!' "$DESTROY_LOG"
}

function known_convergence_race() {
  grep -Eiq 'resource_already_detaching|load[_-]balancer[_-]network.*422|422.*load[_-]balancer[_-]network|((subnet|network).*(still in use|resource in use)|(still in use|resource in use).*(subnet|network))' "$DESTROY_LOG"
}

function collect_labeled_ids() {
  local resource="$1"
  hcloud "$resource" list --selector='provisioner=terraform' --selector="cluster=$CLUSTER_NAME" -o noheader -o 'columns=id'
}

function collect_exact_named_load_balancer_ids() {
  hcloud load-balancer list -o noheader -o 'columns=id,name' | awk -v cluster="$CLUSTER_NAME" '
    $2 == cluster ||
    $2 == cluster "-traefik" ||
    $2 == cluster "-nginx" ||
    $2 == cluster "-haproxy" { print $1 }
  '
}

function collect_prefixed_name_ids() {
  local resource="$1"
  hcloud "$resource" list -o noheader -o 'columns=id,name' | awk -v prefix="$CLUSTER_NAME-" '
    index($2, prefix) == 1 { print $1 }
  '
}

function collect_exact_name_ids() {
  local resource="$1"
  hcloud "$resource" list -o noheader -o 'columns=id,name' | awk -v name="$CLUSTER_NAME" '
    $2 == name { print $1 }
  '
}

function collect_primary_ip_ids() {
  hcloud primary-ip list -o noheader -o 'columns=id,name' | awk -v cluster="$CLUSTER_NAME" '
    function has_prefix_suffix(value, prefix, suffix) {
      return index(value, prefix) == 1 &&
        length(value) > length(prefix) + length(suffix) &&
        substr(value, length(value) - length(suffix) + 1) == suffix
    }
    {
      name = $2
      matched = 0
      if (has_prefix_suffix(name, cluster "-agent-", "-ipv4")) matched = 1
      if (has_prefix_suffix(name, cluster "-agent-", "-ipv6")) matched = 1
      if (has_prefix_suffix(name, cluster "-cp-", "-ipv4")) matched = 1
      if (has_prefix_suffix(name, cluster "-cp-", "-ipv6")) matched = 1
      if (name == cluster "-nat-router-ipv4") matched = 1
      if (name == cluster "-nat-router-ipv6") matched = 1
      if (has_prefix_suffix(name, cluster "-nat-router-", "-ipv4")) matched = 1
      if (has_prefix_suffix(name, cluster "-nat-router-", "-ipv6")) matched = 1
      if (matched) {
        print $1
      }
    }
  '
}

function read_unique_ids() {
  awk 'NF && !seen[$1]++ { print $1 }'
}

function print_delete_command() {
  local label="$1"
  local command="$2"
  shift 2

  if [ "$#" -eq 0 ]; then
    return 1
  fi

  echo "$label: $*"
  printf '  %s' "$command"
  local id
  for id in "$@"; do
    printf ' %s' "$id"
  done
  printf '\n'
  return 0
}

function print_volume_commands() {
  if [ "$#" -eq 0 ]; then
    return 1
  fi

  echo "terraform-labeled volumes: $*"
  printf '  for id in'
  local id
  for id in "$@"; do
    printf ' %s' "$id"
  done
  printf "; do hcloud volume detach \"\$id\"; done\n"
  printf '  hcloud volume delete'
  for id in "$@"; do
    printf ' %s' "$id"
  done
  printf '\n'
  return 0
}

function print_manual_unattached_volumes() {
  local unattached_volumes=()
  local line
  while IFS='' read -r line; do
    if [ -n "$line" ]; then
      unattached_volumes+=( "$line" )
    fi
  done < <(hcloud volume list -o noheader -o 'columns=id,name,server' | awk '$3 == "" || $3 == "-" || $3 == "<none>" { print }')

  if [ "${#unattached_volumes[@]}" -eq 0 ]; then
    return
  fi

  echo "unattached volumes for manual review (CSI-created PV volumes are not cluster-labeled):"
  for line in "${unattached_volumes[@]}"; do
    echo "  $line"
  done
}

function run_orphan_report() {
  if [ -z "$CLUSTER_NAME" ]; then
    echo "Skipping hcloud orphan report: cluster name could not be detected from kube.tf."
    return
  fi

  if ! command -v hcloud >/dev/null 2>&1; then
    echo "Skipping hcloud orphan report: hcloud CLI is not installed."
    return
  fi

  if [ -z "$HCLOUD_TOKEN" ] && ! hcloud context active >/dev/null 2>&1; then
    echo "Skipping hcloud orphan report: no active hcloud context and no HCLOUD_TOKEN set."
    return
  fi

  local hcloud_target
  hcloud_target=$(hcloud context active 2>/dev/null)
  if [ -z "$hcloud_target" ]; then
    hcloud_target="HCLOUD_TOKEN env"
  fi

  echo " "
  echo "Read-only hcloud orphan report for cluster '$CLUSTER_NAME' (auth: ${hcloud_target}):"
  echo "This script will not delete anything. Review matches before running any command."

  local found=0
  local servers=()
  local load_balancers=()
  local networks=()
  local firewalls=()
  local ssh_keys=()
  local placement_groups=()
  local primary_ips=()
  local floating_ips=()
  local volumes=()
  local line

  while IFS='' read -r line; do servers+=( "$line" ); done < <(
    {
      collect_labeled_ids server
      collect_prefixed_name_ids server
    } | read_unique_ids
  )
  while IFS='' read -r line; do load_balancers+=( "$line" ); done < <(
    {
      collect_labeled_ids load-balancer
      collect_exact_named_load_balancer_ids
    } | read_unique_ids
  )
  while IFS='' read -r line; do networks+=( "$line" ); done < <(
    {
      collect_labeled_ids network
      collect_exact_name_ids network
    } | read_unique_ids
  )
  while IFS='' read -r line; do firewalls+=( "$line" ); done < <(
    {
      collect_labeled_ids firewall
      collect_exact_name_ids firewall
    } | read_unique_ids
  )
  while IFS='' read -r line; do ssh_keys+=( "$line" ); done < <(
    {
      collect_labeled_ids ssh-key
      collect_exact_name_ids ssh-key
    } | read_unique_ids
  )
  while IFS='' read -r line; do placement_groups+=( "$line" ); done < <(
    {
      collect_labeled_ids placement-group
      collect_prefixed_name_ids placement-group
    } | read_unique_ids
  )
  while IFS='' read -r line; do primary_ips+=( "$line" ); done < <(collect_primary_ip_ids | read_unique_ids)
  while IFS='' read -r line; do floating_ips+=( "$line" ); done < <(collect_labeled_ids floating-ip | read_unique_ids)
  while IFS='' read -r line; do volumes+=( "$line" ); done < <(collect_labeled_ids volume | read_unique_ids)

  print_delete_command "servers" "hcloud server delete" "${servers[@]}" && found=1
  print_delete_command "load balancers" "hcloud load-balancer delete" "${load_balancers[@]}" && found=1
  print_delete_command "networks" "hcloud network delete" "${networks[@]}" && found=1
  print_delete_command "firewalls" "hcloud firewall delete" "${firewalls[@]}" && found=1
  print_delete_command "ssh keys" "hcloud ssh-key delete" "${ssh_keys[@]}" && found=1
  print_delete_command "placement groups" "hcloud placement-group delete" "${placement_groups[@]}" && found=1
  print_delete_command "primary IPs" "hcloud primary-ip delete" "${primary_ips[@]}" && found=1
  print_delete_command "floating IPs" "hcloud floating-ip delete" "${floating_ips[@]}" && found=1
  print_volume_commands "${volumes[@]}" && found=1
  print_manual_unattached_volumes

  if [ "$found" -eq 0 ]; then
    echo "No cluster-anchored or terraform-labeled orphan resources found."
  else
    echo "For forceful interactive cleanup with dry-run default, run scripts/cleanup.sh."
  fi
}

run_destroy "$@"
destroy_exit=$?

if [ "$destroy_exit" -ne 0 ]; then
  if ! destroy_started || ! known_convergence_race; then
    echo "Destroy failed before confirmed resource destruction or outside the known benign convergence races; stopping without retry."
  else
    retry=1
    while [ "$retry" -le "$MAX_RETRIES" ] && [ "$destroy_exit" -ne 0 ]; do
      echo "Known benign destroy convergence race: hcloud CCM and Terraform can both act on the adopted ingress LB during teardown; waiting ${RETRY_WAIT_SECONDS}s then retrying with -auto-approve."
      sleep "$RETRY_WAIT_SECONDS"
      run_retry_destroy "$@"
      destroy_exit=$?

      if [ "$destroy_exit" -ne 0 ] && ! known_convergence_race; then
        echo "Retry failed with an error that does not match the known benign convergence races; stopping."
        break
      fi

      retry=$((retry + 1))
    done
  fi
fi

run_orphan_report
exit "$destroy_exit"
