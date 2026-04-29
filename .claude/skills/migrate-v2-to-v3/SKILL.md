---
name: migrate-v2-to-v3
description: Use when migrating an existing kube-hetzner Terraform root from module v2.x to v3.x
---

# Migrate kube-hetzner v2 to v3

## Purpose

Safely migrate an existing kube-hetzner cluster from `v2.x` to `v3.x`.

This skill is for real user Terraform roots, not for brand-new clusters. It
prioritizes preserving infrastructure and making Terraform validation failures
actionable.

## Canonical References

Read these before editing:

1. `docs/v2-to-v3-migration.md` - operational migration playbook
2. `MIGRATION.md` - canonical old-to-new variable map
3. `CHANGELOG.md` - v3 upgrade notes and release context
4. `variables.tf` - exact v3 input contract and validation rules
5. `kube.tf.example` - current v3 configuration example
6. `scripts/v2_to_v3_migration_assistant.py` - static config and plan audit

## Safety Rules

- Never run `terraform apply` unless the user explicitly asks after plan review.
- Always back up state before changing the module version.
- Never ignore `destroy`, `replace`, or `forces replacement` in a v3 upgrade
  plan.
- Treat replacements for `hcloud_network`, `hcloud_network_subnet`,
  `hcloud_server`, `hcloud_load_balancer`, `hcloud_primary_ip`,
  `hcloud_placement_group`, or `hcloud_volume` as blockers until explained.
- Do not "fix" a v3 validation error by bypassing validation. Fix the
  configuration.
- For custom network, private-only, Robot/vSwitch, or multinetwork clusters,
  prefer recommending blue/green if the in-place plan is not clearly safe.

## Required Inputs

Determine:

- Terraform root path, default `/Users/karim/Code/kube-test` when working on
  Karim's test cluster.
- Current module source/version.
- Target v3 tag.
- Whether this is a live production cluster.
- Whether it uses NAT router, private-only nodes, Robot/vSwitch,
  autoscaler, Cilium, Longhorn, or external networks.

## Workflow

### 1. Inspect Current Root

From the user's Terraform root:

```bash
terraform version
terraform providers
rg -n 'module "kube-hetzner"|source\\s*=|version\\s*=' .
```

Find v2-only inputs:

```bash
uv run python /path/to/kube-hetzner/scripts/v2_to_v3_migration_assistant.py --root .
rg -n 'kubernetes_distribution_type|k3s_token|secrets_encryption|initial_k3s_channel|install_k3s_version|initial_rke2_channel|install_rke2_version|automatically_upgrade_k3s|sys_upgrade_controller_version|additional_k3s_environment|kubeapi_port|k3s_registries|k3s_kubelet_config|k3s_audit_policy_config|k3s_audit_log_path|k3s_audit_log_maxage|k3s_audit_log_maxbackup|k3s_audit_log_maxsize|k3s_exec_server_args|k3s_exec_agent_args|k3s_global_kubelet_args|k3s_control_plane_kubelet_args|k3s_agent_kubelet_args|k3s_autoscaler_kubelet_args|subnet_amount|placement_group_disable|block_icmp_ping_in|disable_hetzner_csi|load_balancer_disable_ipv6|load_balancer_disable_public_network|use_control_plane_lb|combine_load_balancers|control_plane_lb_type|control_plane_lb_enable_public_interface|control_plane_lb_enable_public_network|lb_hostname|robot_ccm_enabled|hetzner_ccm_use_helm|enable_hetzner_ccm_helm|cilium_loadbalancer_acceleration_mode|enable_wireguard|k8s_config_updates_use_kured_sentinel|keep_disk_agents|keep_disk_cp|use_private_bastion|disable_kube_proxy|disable_network_policy|disable_selinux|k3s_prefer_bundled_bin|placement_group_compat_idx|disable_ipv4|disable_ipv6|autoscaler_disable_ipv4|autoscaler_disable_ipv6|existing_network_id|enable_x86|enable_arm|k3s_encryption_at_rest|autoscaler_labels|autoscaler_taints|extra_kustomize_' .
```

The assistant is the primary first-pass report. The `rg` command is a manual
cross-check when a root uses unusual formatting, Terragrunt, generated HCL, or
split tfvars.

### 2. Back Up

```bash
terraform state pull > "terraform-state-before-kube-hetzner-v3-$(date +%Y%m%d%H%M%S).json"
find . -maxdepth 1 -name '*.tf' -print
```

If editing user config directly, preserve a copy of touched `.tf` files.

### 3. Rewrite Configuration

Use `MIGRATION.md` for the complete map. Critical transformations:

- Rename distribution-neutral inputs, e.g. `k3s_token` -> `cluster_token`.
- Invert negative booleans:
  - `disable_kube_proxy` -> `enable_kube_proxy`
  - `disable_network_policy` -> `enable_network_policy`
  - `disable_selinux` -> `enable_selinux`
  - nodepool `disable_ipv4/disable_ipv6` ->
    `enable_public_ipv4/enable_public_ipv6`
  - `autoscaler_disable_ipv4/disable_ipv6` ->
    `autoscaler_enable_public_ipv4/autoscaler_enable_public_ipv6`
- Replace `existing_network_id = ["123"]` with
  `existing_network = { id = 123 }`.
- Replace `enable_x86`/`enable_arm` with `enabled_architectures`.
- Remove control-plane `network_id`; control planes are primary-network only.
- Remove `network_id = 0`; primary network is omitted/null in v3.
- Keep the default `network_subnet_mode = "per_nodepool"` for normal in-place
  v2 upgrades; this matches released v2 subnet resources. Use
  `network_subnet_mode = "shared"` only for new clusters or intentional subnet
  topology changes.
- Replace `placement_group_compat_idx` with `placement_group_index`.
- Replace `extra_kustomize_*` with `user_kustomizations`.
- Remove `enable_iscsid`, `k3s_encryption_at_rest`, `autoscaler_labels`, and
  `autoscaler_taints`.
- Remove `hetzner_ccm_use_helm` / `enable_hetzner_ccm_helm`; v3 always
  installs Hetzner CCM through the HelmChart manifest.

### 4. Initialize And Validate

```bash
terraform fmt -recursive
terraform init -upgrade
terraform validate
tmpdir="$(mktemp -d)"
rsync -a --exclude .git --exclude .terraform --exclude .terraform-tofu ./ "$tmpdir"/
(cd "$tmpdir" && tofu init -backend=false && tofu validate)
rm -rf "$tmpdir"
```

If validation fails, read the variable and validation block in `variables.tf`
before changing config.

### 5. Plan

```bash
terraform plan -out=v3-upgrade.tfplan
terraform show v3-upgrade.tfplan
terraform show -json v3-upgrade.tfplan > v3-upgrade-plan.json
uv run python /path/to/kube-hetzner/scripts/v2_to_v3_migration_assistant.py --root . --plan-json v3-upgrade-plan.json
```

If `jq` is available, list destructive actions:

```bash
terraform show -json v3-upgrade.tfplan \
  | jq -r '.resource_changes[] | select(any(.change.actions[]; . == "delete" or . == "replace")) | "\(.address): \(.change.actions | join(","))"'
```

### 6. Interpret Special Cases

- NAT router primary IP replacement from pre-v2.19 clusters may require state
  migration before apply.
- `existing_network` plus `vswitch_id` cannot have module-managed
  `expose_routes_to_vswitch`; set it false or enable route exposure manually.
- Private-only clusters need a working NAT/bastion/control-plane join path.
- Multinetwork public overlay is a lab-only preview. It requires
  `multinetwork_mode = "cilium_public_overlay"`,
  `enable_experimental_cilium_public_overlay = true`, and
  `cni_plugin = "cilium"`; do not recommend it for production upgrades until the
  live datapath E2E passes.
- Tailscale node transport is the supported secure Tailnet access and private
  multinetwork path in v3. Use `node_transport_mode = "tailscale"` for
  single-network API/SSH hardening or Flannel-first multinetwork scale, but
  introduce large multinetwork scale in a separate audited plan after the base
  v2-to-v3 upgrade unless the operator is intentionally doing a blue/green
  migration.
- Tailscale mode keeps Kubernetes node IPs on Hetzner private addresses and
  can advertise node-private `/32` routes with Tailscale subnet-route SNAT
  disabled. Single-network clusters may disable route advertisement; external
  `network_id` nodepools require route advertisement and Tailnet auto-approval.
- External agent/autoscaler Network IDs must be positive Hetzner Network IDs.
  Omit/null means the primary Network.
- Do not add new optional v3 features such as `cilium_gateway_api_enabled`,
  `embedded_registry_mirror`, or new Tailscale multinetwork shards during the
  same first in-place v2-to-v3 apply unless the operator explicitly accepts a
  blue/green/topology-change migration. Upgrade cleanly first, then add those
  features in a separate reviewed plan.
- If adding Cilium Gateway API after migration, require `cni_plugin = "cilium"`
  and `enable_kube_proxy = false`.
- If adding embedded registry mirror after migration, warn that nodes are
  equal-trust registry peers and critical images should use digests.

### 7. Report

Return a migration report:

```markdown
## kube-hetzner v2 -> v3 migration report

- Terraform root:
- Source version:
- Target version:
- Terraform/OpenTofu version:
- hcloud provider version:
- Inputs changed:
- Inputs removed:
- Manual state actions:
- Validation result:
- Plan result:
- Replacements/destroys:
- Blockers:
- Recommendation:
```

## Apply Policy

Only run:

```bash
terraform apply v3-upgrade.tfplan
```

after explicit user approval and after the plan report has no unexplained
destructive actions.
