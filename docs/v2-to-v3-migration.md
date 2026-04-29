# kube-hetzner v2 to v3 migration playbook

This playbook is the operational path for moving an existing kube-hetzner
cluster from any `v2.x` release to `v3.x`.

v3 is a major release. Treat the upgrade like an infrastructure migration, not a
routine patch bump. The goal is to make Terraform reject invalid configuration
before deployment and to keep any real infrastructure changes explicit.

## Who should use this

Use this playbook when:

- your module version is currently pinned to `2.x`;
- you want to move the same Terraform root to `3.x`;
- you need to rewrite removed or renamed inputs;
- you need to understand whether a `terraform plan` is safe.

For brand-new clusters, start from `kube.tf.example` instead.

## Golden rules

1. Do not run `terraform apply` until the v3 plan has been reviewed.
2. Back up state before changing the module version.
3. Fix input validation errors first; they are usually protecting you from a bad
   deploy.
4. Do not accept unexpected `destroy`, `replace`, or `forces replacement`
   actions.
5. If the plan wants to replace network, subnet, load balancer, control-plane,
   or NAT-router resources, stop and investigate.
6. Prefer a blue/green migration for clusters with custom network edits,
   external routes, private-only access, Robot/vSwitch coupling, or large
   multinetwork scale requirements.

## Release readiness checklist

Complete this before applying a v3 plan:

- State backup exists from `terraform state pull`.
- The module is pinned to the exact target v3 tag.
- Removed v2 inputs no longer appear in the Terraform root.
- Every inverted boolean was reviewed manually, especially public-IP,
  SELinux, kube-proxy, network-policy, placement-group, CSI, and load-balancer
  flags.
- `terraform fmt -recursive`, `terraform init -upgrade`, and
  `terraform validate` pass.
- If using OpenTofu, `tofu init -upgrade`, `tofu validate`, and `tofu plan`
  have been run in the real Terraform root.
- The saved plan has no unexpected delete/replace actions.
- Network, subnet, load balancer, NAT router, placement group, server, primary
  IP, and volume changes have a written explanation.
- Private-only, Robot/vSwitch, custom existing-network, external-overlay,
  autoscaler, Longhorn, RKE2, and multinetwork clusters have a rollback or
  blue/green path.

## Support levels

| Area | v3 support level | Guidance |
| --- | --- | --- |
| k3s on Leap Micro | Stable default | Best path for new clusters. |
| RKE2 on Leap Micro | Supported | Heavier, stricter path; keep SELinux snapshot selection explicit when pinning snapshots. |
| MicroOS | Legacy/upgrade support | Existing nodes are supported; new nodepools default to Leap Micro unless `os = "microos"` is set. |
| Terraform | Supported | Requires Terraform `>= 1.10.1`. |
| OpenTofu | Supported | Requires OpenTofu `>= 1.10.1`; run `tofu plan` before applying with OpenTofu. |
| Flannel or Calico single-network clusters | Supported | Keep all nodes on one reachable private network. |
| Cilium dual-stack | Supported | Preferred advanced CNI path. |
| Cilium multinetwork public overlay | Experimental preview | Gated by `enable_experimental_cilium_public_overlay`; do not use for production upgrades yet. |
| Flannel/Calico multinetwork scale | Unsupported | Separate Hetzner Networks are L3 islands; use one private Network or an external routed/VPN fabric. |
| Tailscale/ZeroTier/WARP | Supported external pattern | Use `preinstall_exec`, `node_connection_overrides`, `control_plane_endpoint`, and optional firewall tightening; kube-hetzner does not manage the provider lifecycle. |
| Robot/vSwitch | Advanced/special-case | Validate route exposure and migration plans manually. |
| Private-only clusters | Advanced/special-case | Prove SSH and join paths before applying. |
| Longhorn with attached volumes | Supported with caution | Review replacements and first-boot relabel/mount timing carefully. |

## Minimum versions

v3 requires:

- Terraform `>= 1.10.1` or OpenTofu `>= 1.10.1`
- hcloud provider `>= 1.62.0`

Terraform 1.9+ cross-object variable validation is used heavily in v3, and the
module requires a runtime compatible with Terraform/OpenTofu 1.10.1 or newer.
On Homebrew, install OpenTofu with `brew install opentofu`. OpenTofu users
should verify behavior with `tofu init -upgrade`, `tofu validate`, and
`tofu plan` before applying.

If you validate the module checkout itself with both Terraform and OpenTofu,
run OpenTofu in a temporary copy so its ignored lock file and provider cache do
not disturb Terraform's local state:

```bash
tmpdir="$(mktemp -d)"
rsync -a --exclude .git --exclude .terraform --exclude .terraform-tofu ./ "$tmpdir"/
(cd "$tmpdir" && tofu init -backend=false && tofu validate)
rm -rf "$tmpdir"
```

## Phase 0: capture current state

Run these commands from the Terraform root that deploys the cluster:

```bash
terraform version
terraform providers
terraform state pull > "terraform-state-before-kube-hetzner-v3-$(date +%Y%m%d%H%M%S).json"
cp kube.tf "kube.tf.before-v3.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
```

If your configuration is split across several `.tf` files, back up those files
too.

## Phase 1: inventory v2-only inputs

Run the migration assistant from a local kube-hetzner checkout first. It is
read-only: it scans a Terraform root, reports known v2 inputs, calls out
advanced topology signals, and can also review a saved plan JSON for destructive
actions.

```bash
uv run python /path/to/kube-hetzner/scripts/v2_to_v3_migration_assistant.py --root .
```

Search for known v2 inputs:

```bash
rg -n 'kubernetes_distribution_type|k3s_token|secrets_encryption|initial_k3s_channel|install_k3s_version|initial_rke2_channel|install_rke2_version|automatically_upgrade_k3s|sys_upgrade_controller_version|additional_k3s_environment|kubeapi_port|k3s_registries|k3s_kubelet_config|k3s_audit_policy_config|k3s_audit_log_path|k3s_audit_log_maxage|k3s_audit_log_maxbackup|k3s_audit_log_maxsize|k3s_exec_server_args|k3s_exec_agent_args|k3s_global_kubelet_args|k3s_control_plane_kubelet_args|k3s_agent_kubelet_args|k3s_autoscaler_kubelet_args|subnet_amount|placement_group_disable|block_icmp_ping_in|disable_hetzner_csi|load_balancer_disable_ipv6|load_balancer_disable_public_network|use_control_plane_lb|combine_load_balancers|control_plane_lb_type|control_plane_lb_enable_public_interface|control_plane_lb_enable_public_network|lb_hostname|robot_ccm_enabled|hetzner_ccm_use_helm|enable_hetzner_ccm_helm|cilium_loadbalancer_acceleration_mode|enable_wireguard|k8s_config_updates_use_kured_sentinel|keep_disk_agents|keep_disk_cp|use_private_bastion|disable_kube_proxy|disable_network_policy|disable_selinux|k3s_prefer_bundled_bin|placement_group_compat_idx|disable_ipv4|disable_ipv6|autoscaler_disable_ipv4|autoscaler_disable_ipv6|existing_network_id|enable_x86|enable_arm|k3s_encryption_at_rest|autoscaler_labels|autoscaler_taints|extra_kustomize_' .
```

Every match should either be migrated or intentionally removed.

## Phase 2: rewrite the module contract

Use `MIGRATION.md` as the canonical v2-to-v3 variable map. The high-risk edits
are the ones that invert meaning:

```hcl
# v2
disable_hetzner_csi       = true
placement_group_disable   = true
block_icmp_ping_in        = false
disable_kube_proxy        = true
disable_network_policy    = true
disable_selinux           = false
autoscaler_disable_ipv4   = true
autoscaler_disable_ipv6   = true

# v3
enable_hetzner_csi             = false
enable_placement_groups        = false
allow_inbound_icmp             = true
enable_kube_proxy              = false
enable_network_policy          = false
enable_selinux                 = true
autoscaler_enable_public_ipv4  = false
autoscaler_enable_public_ipv6  = false
```

Nodepool public IP flags also invert:

```hcl
# v2 nodepool
disable_ipv4 = true
disable_ipv6 = false

# v3 nodepool
enable_public_ipv4 = false
enable_public_ipv6 = true
```

Primary network selection changed:

```hcl
# v2
existing_network_id = ["1234567"]

# v3
existing_network = { id = 1234567 }
```

Architecture toggles changed:

```hcl
# v2
enable_x86 = true
enable_arm = false

# v3
enabled_architectures = ["x86"]
```

Primary network assignment is now represented by omission/null. Do not set
`network_id = 0` in v3:

```hcl
agent_nodepools = [
  {
    name        = "default"
    server_type = "cx32"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 3
    # network_id omitted/null means the primary kube-hetzner Network.
  },
  {
    name        = "external-network"
    server_type = "cx32"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 3
    network_id  = 1234567
  }
]
```

Control-plane nodepools no longer accept `network_id`; control planes always
stay on the primary kube-hetzner Network.

New v3 clusters default to one subnet per control-plane and agent nodepool. That
matches the released v2 subnet topology, so leave
`network_subnet_mode = "per_nodepool"` for normal in-place v2 upgrades.

`network_subnet_mode = "shared"` is an optional compact topology for new
clusters or intentional topology changes. Do not use it during an in-place v2
upgrade unless subnet replacements are expected and acceptable.

## Phase 3: migrate user kustomizations

Replace the old `extra_kustomize_*` inputs with `user_kustomizations`.

```hcl
# v2
extra_kustomize_folder              = "extra-manifests"
extra_kustomize_parameters          = { target_namespace = "argocd" }
extra_kustomize_deployment_commands = "kubectl -n argocd get pods"

# v3
user_kustomizations = {
  "1" = {
    source_folder        = "extra-manifests"
    kustomize_parameters = { target_namespace = "argocd" }
    pre_commands         = ""
    post_commands        = "kubectl -n argocd get pods"
  }
}
```

## Phase 4: handle removed inputs

Remove these inputs completely:

- `enable_iscsid`: v3 enables `iscsid` where needed.
- `k3s_encryption_at_rest`: use `enable_secrets_encryption`.
- `hetzner_ccm_use_helm` / `enable_hetzner_ccm_helm`: remove this setting.
  v3 always installs Hetzner CCM through the HelmChart manifest and migrates
  away from the old raw-manifest CCM path.
- `autoscaler_labels`: use `autoscaler_nodepools[*].labels`.
- `autoscaler_taints`: use `autoscaler_nodepools[*].taints`.

## Phase 5: update the version and initialize

Pin the module to the target v3 tag:

```hcl
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "3.0.0"
}
```

Then run:

```bash
terraform fmt -recursive
terraform init -upgrade
terraform validate
```

Fix validation failures before planning. v3 intentionally uses variable
validation as the first safety layer.

## Phase 6: create and inspect a plan

```bash
terraform plan -out=v3-upgrade.tfplan
terraform show v3-upgrade.tfplan
```

For machine-readable review:

```bash
terraform show -json v3-upgrade.tfplan > v3-upgrade-plan.json
uv run python /path/to/kube-hetzner/scripts/v2_to_v3_migration_assistant.py --root . --plan-json v3-upgrade-plan.json
```

Stop if the plan contains unexpected replacements or destroys:

```bash
terraform show -json v3-upgrade.tfplan \
  | jq -r '.resource_changes[] | select(any(.change.actions[]; . == "delete" or . == "replace")) | "\(.address): \(.change.actions | join(","))"'
```

Known areas requiring extra suspicion:

- `hcloud_network`
- `hcloud_network_subnet`
- `hcloud_server`
- `hcloud_load_balancer`
- `hcloud_load_balancer_network`
- `hcloud_primary_ip`
- `hcloud_placement_group`
- `hcloud_volume`

Do not approve a plan because it is "probably fine." Make every replacement
intentional.

### Quick diagnostics for failed plans

When `terraform validate` or `terraform plan` fails, do not work around the
validation first. Read the error message and inspect the relevant inputs:

```bash
terraform validate
terraform plan -out=v3-upgrade.tfplan
rg -n 'network_id|existing_network|multinetwork_mode|control_plane_endpoint|nat_router|use_private_nat_router_bastion|enable_public_ipv4|enable_public_ipv6|autoscaler|placement_group|attached_volumes|user_kustomizations' .
```

If a plan was created, list risky actions directly:

```bash
terraform show -json v3-upgrade.tfplan \
  | jq -r '.resource_changes[] | select(any(.change.actions[]; . == "delete" or . == "replace")) | "\(.address): \(.change.actions | join(","))"'
```

For join or reachability failures after a partial apply, check the planned
endpoint and the node connection path first:

```bash
terraform output
rg -n 'control_plane_endpoint|node_connection_overrides|firewall_ssh_source|firewall_kube_api_source|optional_bastion_host|nat_router' .
```

For Cilium multinetwork issues, verify the declared topology before debugging
Kubernetes:

```bash
rg -n 'cni_plugin|multinetwork_mode|multinetwork_transport_ip_family|network_id|enable_public_ipv4|enable_public_ipv6|control_plane_endpoint' .
```

## Phase 7: special cases

### High-risk topology scan

| Topology | Why it is risky | v3 recommendation |
| --- | --- | --- |
| Private-only nodes | SSH and Kubernetes join paths can be stranded if bastion, NAT, firewall, or endpoint settings disagree. | Prove access before applying; prefer blue/green if unsure. |
| Existing Hetzner Networks | Out-of-band routes/subnets can conflict with v3 validation and attachment accounting. | Use `existing_network = { id = ... }`; review subnets and route exposure. |
| Multiple Hetzner Networks | Networks are separate L3 islands and servers can attach to at most three Networks. | Treat `multinetwork_mode = "cilium_public_overlay"` as a lab-only preview until live datapath validation passes. |
| Robot/vSwitch | Route exposure can be provider-managed or manually managed depending on ownership. | Validate `expose_routes_to_vswitch` and existing Network ownership. |
| NAT router from old v2 clusters | Pre-v2.19 primary IP state can show replacement. | Import existing primary IPs if they must be preserved. |
| Autoscaler with external networks | Cluster Autoscaler needs per-network `HCLOUD_NETWORK` behavior. | Use external autoscaler `network_id` only with the experimental Cilium public-overlay preview. |
| Longhorn or attached volumes | Replacements or mount changes can affect stateful workloads. | Back up data and review every volume action. |
| External overlays such as Tailscale | Auth keys, ACLs, route approvals, DNS, and operator lifecycle live outside kube-hetzner. | Use generic hooks and keep provider lifecycle external. |

### NAT router primary IPs from old v2 clusters

Clusters created before v2.19.0 may show NAT router primary IP replacement. If
you need to preserve those IPs, migrate state as described in `MIGRATION.md`
before applying v3.

### Private-only clusters

Private-only nodes must have a working SSH and Kubernetes join path before
upgrade. Validate NAT router, bastion, `control_plane_endpoint`, and
control-plane load balancer settings together. v3 will reject many stranded
private-only combinations during plan.

### Robot/vSwitch clusters

If using `existing_network` with `vswitch_id`, v3 cannot manage
`expose_routes_to_vswitch` on that existing Network. Enable route exposure on the
existing Network manually or set:

```hcl
expose_routes_to_vswitch = false
```

### Multinetwork scale

v3 includes a lab-only large multinetwork Cloud preview through:

```hcl
enable_experimental_cilium_public_overlay = true
multinetwork_mode = "cilium_public_overlay"
cni_plugin        = "cilium"
```

This mode uses public node addresses plus Cilium WireGuard/tunnel overlay. It is
not a Flannel or Calico private-network feature, and it must not be used for
production upgrades until the live Cilium datapath test passes. External Network
IDs may be set on agent nodepools; autoscaler nodepools may also set external
Network IDs only in this mode, where kube-hetzner renders one autoscaler
Deployment per effective Network. Primary Network nodepools omit `network_id`.

### Placement groups

Hetzner spread Placement Groups are capped at 10 servers. v3 auto-shards
implicit count-based placement groups every 10 servers. Explicit named placement
groups still fail validation above 10; split them manually.

## Phase 8: apply

Apply only after all of these are true:

- `terraform validate` passes.
- The v3 plan has no unexpected replacements or destroys.
- Any NAT-router primary IP, network, subnet, or load-balancer changes are
  understood.
- You have a state backup.
- You have a rollback/restore plan.

Then:

```bash
terraform apply v3-upgrade.tfplan
```

After apply, verify:

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods
kubectl get storageclass
```

For Cilium clusters:

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
cilium status
```

## Migration report template

When helping someone migrate, produce a short report:

```markdown
## kube-hetzner v2 -> v3 migration report

- Source version:
- Target version:
- Terraform/OpenTofu version:
- hcloud provider version:
- Changed inputs:
- Removed inputs:
- Manual state actions:
- Plan result:
- Replacements/destroys:
- Blockers:
- Apply recommendation:
```
