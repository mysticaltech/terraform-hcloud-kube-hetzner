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
2. `docs/v3-release-evidence.md` - live v2.21 -> v3 upgrade evidence
3. `MIGRATION.md` - canonical old-to-new variable map
4. `CHANGELOG.md` - v3 upgrade notes and release context
5. `variables.tf` - exact v3 input contract and validation rules
6. `kube.tf.example` - current v3 configuration example
7. `scripts/v2_to_v3_migration_assistant.py` - static config and plan audit
8. `plans/010-report.md` - index-keyed nodepool ordering risk
9. `plans/011-ingress-lb-single-ownership.md` - ingress LB destroy race

## Safety Rules

- Never run `terraform apply` unless the user explicitly asks after plan review.
- Always back up state before changing the module version.
- Never ignore `destroy`, `replace`, or `forces replacement` in a v3 upgrade
  plan.
- Do not allow a silent K3s channel policy change. `MIGRATION.md` documents
  that v2 defaulted `k3s_channel` to `v1.33`; v3 defaults it to `stable` while
  automatic Kubernetes upgrades remain default-on. The user must choose before
  the first v3 apply.
- Treat replacements for `hcloud_network`, `hcloud_network_subnet`,
  `hcloud_server`, `hcloud_load_balancer`, `hcloud_primary_ip`,
  `hcloud_placement_group`, `hcloud_volume`, or `hcloud_firewall` as blockers
  until explained.
- Never reorder or insert control-plane or agent nodepools mid-list during or
  after migration. Node resource addresses are index-keyed; append only unless
  the user is intentionally planning a state migration or blue/green rebuild.
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
- K3s version/channel intent: pin `k3s_version`, set
  `k3s_channel = "v1.33"`, or consciously accept v3 `stable`.
- Whether nodes have out-of-band root SSH keys outside
  `ssh_public_key`/`ssh_additional_public_keys`.
- Whether Terraform can SSH to every existing node for
  `terraform_data.initial_readiness`, including private-only, NAT, and bastion
  topologies.
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
- Do not reorder or insert existing nodepools while rewriting. Append new
  nodepools only. If the user wants to change list order, stop and treat that
  as a separate state-migration or blue/green design problem.

### 4. Decide First-Apply Intent

Resolve these before the first v3 apply:

- Kubernetes channel policy. `MIGRATION.md` documents the silent default change:
  v2 used `k3s_channel = "v1.33"`, v3 uses `k3s_channel = "stable"`, and
  `automatically_upgrade_kubernetes` remains default-on. Make the user choose
  exactly one:
  - pin `k3s_version`
  - set `k3s_channel = "v1.33"` to preserve the v2 minor channel
  - consciously accept following `stable`
- Addon version policy. v2 unset/floating addon versions resolved
  upstream-latest. v3 unset addon versions use kube-hetzner's reviewed
  deterministic default matrix. The upgrade plan may show one-time addon
  version changes. Keeping floating behavior requires explicitly setting
  `latest`.
- SSH authorized keys policy. On the first v3 apply,
  `terraform_data.ssh_authorized_keys` reconciles
  `/root/.ssh/authorized_keys`. The default preserves unknown out-of-band keys
  while revoking module-managed keys removed from `ssh_public_key` or
  `ssh_additional_public_keys`. Set `ssh_authorized_keys_exclusive = true` only
  when the user wants strict replacement with exactly the module-managed keys.
- Node reachability. `terraform_data.initial_readiness` SSHes to every existing
  control-plane and agent node. Private-only, NAT, and bastion-only operators
  must have Terraform reachability to all nodes before applying.

The proven 2026-07-04/05 standard live upgrade needed only the module source
switch plus `k3s_channel = "v1.33"` for the first v3 plan.

### 5. Initialize And Validate

```bash
terraform fmt -recursive
terraform init -upgrade
terraform validate -no-color
tmpdir="$(mktemp -d)"
rsync -a --exclude .git --exclude .terraform --exclude .terraform-tofu ./ "$tmpdir"/
(cd "$tmpdir" && tofu init -backend=false -input=false && tofu validate -no-color)
rm -rf "$tmpdir"
```

`terraform validate` checks that the module loads. v3 cross-variable migration
guards are enforced by `terraform_data.validation_contract`, so the saved
`terraform plan` is the required proof for invalid combinations and replacement
risk.

If validation fails, read the variable and validation block in `variables.tf`
before changing config.

### 6. Plan

```bash
terraform plan -out=v3-upgrade.tfplan
terraform show v3-upgrade.tfplan
terraform show -json v3-upgrade.tfplan > v3-upgrade-plan.json
uv run python /path/to/kube-hetzner/scripts/v2_to_v3_migration_assistant.py --root . --plan-json v3-upgrade-plan.json
```

If `jq` is available, list destructive actions:

```bash
terraform show -json v3-upgrade.tfplan \
  | jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | "\(.address): \(.change.actions | join(","))"'
```

For live v2 -> v3 migrations, run the protected-infrastructure gate. Terraform
replacements show up as action lists containing `delete`. The gate prints only
blocking resources; any output is a stop condition:

```bash
terraform show -json v3-upgrade.tfplan \
  | jq -r '
      .resource_changes[]?
      | select(.type as $type | [
          "hcloud_server",
          "hcloud_network",
          "hcloud_network_subnet",
          "hcloud_load_balancer",
          "hcloud_volume",
          "hcloud_primary_ip",
          "hcloud_placement_group",
          "hcloud_firewall"
        ] | index($type))
      | select(.change.actions | index("delete"))
      | "\(.address): \(.type) \(.change.actions | join(","))"
    '
```

After the v2 renames, the plan must show zero destroy/replace actions for
`hcloud_server`, `hcloud_network`, `hcloud_network_subnet`,
`hcloud_load_balancer`, `hcloud_volume`, `hcloud_primary_ip`,
`hcloud_placement_group`, and `hcloud_firewall`. Stop and diagnose before apply
if any of those types are listed.

Do not panic-abort a healthy first v3 plan for these expected actions:

- one idempotent k3s/RKE2 kustomization re-run from trigger-key additions
- new `terraform_data` resources for readiness, SSH authorized-key reconcile,
  validators, and destroy cleanup
- in-place server label updates such as `kube-hetzner/os`
- firewall rule updates

### 7. Interpret Special Cases

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
- Tailscale node transport is statically validated and plan-matrix covered, but
  live Hetzner/Tailscale E2E remains pending. Use
  `node_transport_mode = "tailscale"` for evaluation and separate audited
  plans; do not certify production topologies from static checks alone.
- Tailscale mode keeps Kubernetes node IPs on Hetzner private addresses and
  can advertise node-private `/32` routes with Tailscale subnet-route SNAT
  disabled. Single-network clusters may disable route advertisement; external
  `network_scope = "external"` nodepools require route advertisement and Tailnet
  auto-approval.
- External agent/autoscaler Network IDs must be positive Hetzner Network IDs.
  Omit/null means the primary Network. In Tailscale mode, active
  agent/autoscaler nodepools must also set `network_scope = "primary"` or
  `network_scope = "external"` so same-root external Network IDs validate
  during `terraform plan`.
- Do not add new optional v3 features such as `cilium_gateway_api_enabled`,
  `embedded_registry_mirror`, new Tailscale multinetwork shards, or external
  Cloudflare Access/Tunnel routing during the same first in-place v2-to-v3
  apply unless the operator explicitly accepts a blue/green/topology-change
  migration. Upgrade cleanly first, then add those features in a separate
  reviewed plan.
- Cloudflare Access/Tunnel is an external access pattern only. Do not invent
  Cloudflare provider inputs, and do not recommend Cloudflare Mesh/WARP as
  kube-hetzner node transport during a migration.
- If the user later destroys the cluster, one `terraform destroy` retry may be
  needed because the ingress load balancer can race between CCM deletion and
  Terraform network detach. Never manually delete the network first; let
  Terraform own the teardown and retry after the detach settles.
- If adding Cilium Gateway API after migration, require `cni_plugin = "cilium"`
  and `enable_kube_proxy = false`.
- If adding embedded registry mirror after migration, warn that nodes are
  equal-trust registry peers and critical images should use digests.

### 8. Report

Return a migration report:

```markdown
## kube-hetzner v2 -> v3 migration report

- Terraform root:
- Source version:
- Target version:
- Terraform/OpenTofu version:
- hcloud provider version:
- K3s channel/version intent:
- Addon version intent:
- SSH authorized_keys policy:
- Inputs changed:
- Inputs removed:
- Manual state actions:
- Validation result:
- Plan result:
- Protected hcloud delete/replace gate:
- Replacements/destroys:
- Expected first-apply actions:
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
