# Migration advice when updating the module

## v2.x -> v3.x

This is a major upgrade line. Use a staged upgrade and verify plans carefully.
For the full operator workflow, use
[`docs/v2-to-v3-migration.md`](docs/v2-to-v3-migration.md).

### Recommended upgrade flow

1. Back up current state:
   ```bash
   terraform state pull > "terraform-state-before-kube-hetzner-v3-$(date +%Y%m%d%H%M%S).json"
   ```
2. Run the read-only migration assistant from a local kube-hetzner checkout:
   ```bash
   uv run python /path/to/kube-hetzner/scripts/v2_to_v3_migration_assistant.py --root .
   ```
3. Rename/remove v2-only inputs listed below.
4. Decide your k3s upgrade policy before the first v3 apply:
   - v2 defaulted `k3s_channel` to `v1.33`.
   - v3 defaults `k3s_channel` to `stable`, and
     `automatically_upgrade_kubernetes` still defaults to `true`.
   - Either pin `k3s_version`, set `k3s_channel = "v1.33"` to keep the v2
     minor channel intentionally, or consciously accept following `stable`.
5. Decide your addon version policy before the first v3 apply:
   - Unset addon version variables use the reviewed module defaults.
   - Set a concrete version to pin explicitly.
   - Set `latest` only when you intentionally want upstream latest release or
     latest Helm chart behavior.
6. Pin the module to your target v3 tag.
7. Reinitialize providers and modules:
   ```bash
   terraform init -upgrade
   ```
8. Validate and review the plan before applying:
   ```bash
   terraform validate
   terraform plan
   ```
9. Apply only after you understand every `replace`/`destroy` action.

Stop immediately if Terraform proposes unexpected replacements for networks,
subnets, load balancers, servers, primary IPs, placement groups, volumes, or
firewalls.

### Production in-place upgrades: safety model

#### What is verified

[`docs/v3-release-evidence.md`](docs/v3-release-evidence.md) records one live
standard `v2.21.0` -> `v3` in-place upgrade: a 37-resource MicroOS cluster with
Cilium and nginx, upgraded by switching the live root to the staging module,
pinning `k3s_channel = "v1.33"`, reviewing the plan, applying, then checking
cluster health and node OS. That evidence supports this narrow claim: the
standard path upgraded in place with 0 destroyed/replaced hcloud infrastructure
resources, no node recreation, Cilium running, and a healthy cluster after
apply. It does not prove every topology listed below.

Here, "standard" means module-managed networking, the default
`network_subnet_mode = "per_nodepool"` subnet layout, no custom
`subnet_ip_range` overrides, no manual network/subnet/server edits made outside
Terraform, and no topology redesign in the same first v3 apply. The high-risk
topology list in the readiness checklist still applies: private-only,
Robot/vSwitch, existing-network, external-network, Tailscale/overlay,
Longhorn/volume-heavy, autoscaler, and multinetwork clusters need extra review
or blue/green.

#### What to expect during the first apply

With the protected plan gate below clean, the first v3 apply is expected not to
recreate servers, replace core hcloud infrastructure, or reboot nodes. It is not
just Terraform bookkeeping:

- `terraform_data.initial_readiness` SSHes to every existing control-plane and
  agent node and waits for systemd readiness.
- `terraform_data.ssh_authorized_keys` reconciles
  `/root/.ssh/authorized_keys` on every node.
- k3s/RKE2 kustomization and addon payloads may re-render and apply once as
  trigger state migrates.
- k3s/RKE2 service restarts are possible if config-update provisioners detect
  changed config, unless `kubernetes_config_updates_use_kured_sentinel = true`
  is used to signal Kured instead. Node workloads are expected to keep running
  on a clean standard upgrade, but verify nodes, system pods, and workload
  health after apply.

#### No-destroy plan gate

After saving a plan with `terraform plan -out=v3-upgrade.tfplan`, run this
protected-infrastructure gate:

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

Contract: no output means the protected-infrastructure gate passed. ANY output
is a stop condition: do not apply, and investigate the proposed destroy/replace
first. For subnet replacements, start with the
[`network_subnet_mode` diagnostics](#6-networking-behavior-update). This gate is
the hard no-destroy floor; still review every non-protected resource action in
the full plan.

#### Compatibility freeze table

| Concern | v3 default | To freeze v2 behavior |
| --- | --- | --- |
| k3s channel | `k3s_channel = "stable"`, `k3s_version = ""`, and `automatically_upgrade_kubernetes = true`. | Before the first v3 apply, set `k3s_channel = "v1.33"` to keep the v2 minor channel, or set an exact `k3s_version`. |
| Addon versions | `hetzner_ccm_version`, `hetzner_csi_version`, `traefik_version`, `nginx_version`, `haproxy_version`, `longhorn_version`, `csi_driver_smb_version`, `cert_manager_version`, `rancher_version`, `kured_version`, and `calico_version` default to `null`, which uses the reviewed module matrix. `latest` is opt-in where supported. Concrete defaults also exist for `cilium_version = "1.19.3"`, `cluster_autoscaler_version = "v1.33.3"`, and `system_upgrade_controller_version = "v0.18.0"`. | Set concrete version variables for addons that must stay exactly where they are; do not set `latest` or legacy `*` unless floating upstream behavior is intentional. |
| Gateway API CRDs | `gateway_api_version = ""` derives the CRD bundle from `cilium_version` when Gateway API is enabled. | Set `gateway_api_version` to a concrete release tag if you previously pinned Gateway API independently. |
| Network subnet layout | `network_subnet_mode = "per_nodepool"`, matching the v2-compatible layout. | Leave it unset or set `network_subnet_mode = "per_nodepool"`; never switch to `shared` during an in-place upgrade unless subnet changes are intentional. |
| Node transport | `node_transport_mode = "hetzner_private"`, the v2-style Hetzner private Network transport. | Leave it unset or set `node_transport_mode = "hetzner_private"`; introduce `tailscale` only in a separate reviewed plan or blue/green migration. |
| OS selection | Existing nodepool OS labels are preserved when known; existing unlabeled/mixed v2 nodepools fall back to MicroOS; brand-new nodepools default to Leap Micro. | Existing MicroOS nodes stay MicroOS when servers are not recreated. For new MicroOS pools, set `os = "microos"` on `control_plane_nodepools`, `agent_nodepools`, `autoscaler_nodepools`, or per-node `nodes[*]` entries. |
| SSH authorized keys | `ssh_authorized_keys_exclusive = false`; unknown out-of-band root keys are preserved while removed module-managed keys are revoked. | Leave `ssh_authorized_keys_exclusive = false` to preserve the v3 upgrade-safe behavior. Set `true` only when strict replacement with exactly module-managed keys is intended. |
| SELinux | `enable_selinux = true`; nodepool and node `selinux` options default to `true`. | Keep `enable_selinux = true` and per-pool `selinux = true` for the v2 default. If v2 used `disable_selinux = true`, invert that deliberately to `enable_selinux = false` or per-pool `selinux = false`. |
| Kubernetes config update restarts | `kubernetes_config_updates_use_kured_sentinel = false`, so changed k3s/RKE2 config restarts the relevant service immediately. | Carry forward the old `k8s_config_updates_use_kured_sentinel` intent under the new name `kubernetes_config_updates_use_kured_sentinel`. |

#### Rollback and abort paths

Before apply, nothing has changed in the cluster. Re-pin the module to the
previous `v2.x` tag, run `terraform init -upgrade`, and re-plan. The plan should
return to the previous no-op or known baseline; the state backup from step 1 is
the safety net if local state is damaged.

After a failed or partial apply, first prefer convergence: fix the reported
error, run a fresh `terraform plan -out=v3-upgrade.tfplan`, rerun the
protected-infrastructure gate, then apply the new reviewed plan. If the gate
passed before the failed apply, the expected v3 changes are node-local and
Terraform-state changes such as authorized-key reconciliation, rendered
kustomization/addon payloads, validation `terraform_data`, and possible
k3s/RKE2 config service restarts.

The escape hatch is restoring the pre-upgrade state backup and re-pinning the
module to the previous v2 tag, then re-running `terraform init -upgrade` and
`terraform plan`. That does not automatically undo node-local changes already
made by v3. Use the actual backup filename from step 1:

```bash
terraform state push terraform-state-before-kube-hetzner-v3-YYYYMMDDHHMMSS.json
terraform init -upgrade
terraform plan
```

Then check at least:

- `/root/.ssh/authorized_keys` on every node.
- `/etc/rancher/k3s/config.yaml`, `/etc/rancher/rke2/config.yaml`, and
  registry/encryption/audit/authentication files if those provisioners ran.
- `/var/post_install` rendered addon and kustomization payloads.
- k3s/RKE2 service status, node readiness, system pods, and critical workloads.

For high-risk topologies or any plan that is hard to explain, use blue/green
instead of in-place upgrade. Build a separate v3 cluster, migrate workloads and
traffic, and keep the v2 cluster intact until the v3 path is proven. The guided
playbook is [`docs/v2-to-v3-migration.md`](docs/v2-to-v3-migration.md).

### v3 readiness checklist

Before applying a v3 plan:

- Back up state with `terraform state pull`.
- Remove every v2-only input and review every renamed/inverted boolean.
- Review addon version intent: unset variables follow kube-hetzner's reviewed
  deterministic matrix; `latest` opts into upstream floating behavior.
- Run `terraform fmt -recursive`, `terraform init -upgrade`, and
  `terraform validate`.
- Save and inspect a plan with `terraform plan -out=v3-upgrade.tfplan`.
- Confirm there are no unexpected `delete`, `replace`, or `forces replacement`
  actions.
- Treat private-only, Robot/vSwitch, existing-network, external-network,
  Tailscale/overlay, Longhorn/volume-heavy, autoscaler, and multinetwork
  clusters as high-risk upgrade topologies.
- Out-of-band root SSH keys survive by default in v3: kube-hetzner preserves
  unknown existing `/root/.ssh/authorized_keys` lines while revoking
  module-managed keys removed from `ssh_public_key` or
  `ssh_additional_public_keys`. Set `ssh_authorized_keys_exclusive = true`
  only if you want strict replacement semantics with exactly the
  module-managed keys.
- If you set `rancher_registration_manifest_url`, rotate the Rancher registration token because older kustomization backup files may have written that credential to disk.
- Prefer blue/green migration when the plan is hard to explain.

### What the first v3 apply does to existing nodes

The first v3 apply is not purely local Terraform bookkeeping:

- `terraform_data.initial_readiness` SSHes to every existing control-plane and
  agent node and waits for systemd readiness. Private-only clusters, custom SSH
  endpoints, and bastion-only operators must have working Terraform reachability
  before applying.
- `terraform_data.ssh_authorized_keys` reconciles `/root/.ssh/authorized_keys`
  from `ssh_public_key` and `ssh_additional_public_keys`; see the companion
  authorized-keys reconciliation migration note before applying if nodes carry
  manual root keys.
- The module k3s/RKE2 kustomization may rerun once as v3 migrates trigger
  state and rendered addon payloads.
- Validation-only `terraform_data` resources can appear or churn in the plan.
  Treat them as plan-time contract/state migration noise unless they are paired
  with provisioners or unexpected infrastructure actions.

### v3 support levels

| Area | Support level | Notes |
| --- | --- | --- |
| k3s on Leap Micro | Stable default | Recommended for new clusters. |
| RKE2 on Leap Micro | Supported | Validate SELinux snapshot selection carefully when pinning snapshots. |
| MicroOS | Legacy/upgrade support | Existing nodes stay supported; new nodepools default to Leap Micro. |
| OpenTofu | Supported | Run `tofu validate` and `tofu plan` before applying with OpenTofu. |
| Addon version defaults | Reviewed deterministic defaults | Unset addon version variables use kube-hetzner's reviewed matrix; set `latest` only for intentional upstream floating behavior. |
| Cilium Gateway API | Supported opt-in | Add after the base migration with `cilium_gateway_api_enabled = true`, `cni_plugin = "cilium"`, and `enable_kube_proxy = false`. |
| Embedded registry mirror | Supported opt-in | Add after the base migration for trusted clusters; review the equal-node-trust security model first. |
| Cilium multinetwork public overlay | Experimental preview | Gated by `enable_experimental_cilium_public_overlay`; do not use for production upgrades yet. |
| Tailscale node transport | Supported opt-in | Use `node_transport_mode = "tailscale"` for secure single-network clusters or private multinetwork scale-out; Flannel is the first supported CNI. |
| Flannel private multinetwork scale | Supported through Tailscale transport | Use `node_transport_mode = "tailscale"` rather than raw Hetzner private Networks. |
| Calico multinetwork scale | Unsupported | Use one private Network or wait for a tested routed/VPN-backed Calico path. |
| Tailscale/ZeroTier/WARP operator access | Supported external pattern | Use generic hooks when the overlay is only for operator access or post-bootstrap features. |
| Robot/vSwitch/private-only | Advanced/special-case | Review reachability and route exposure manually. |

For new designs, start from the topology chooser in
[`docs/v3-topology-recommendations.md`](docs/v3-topology-recommendations.md).
During an in-place v2 upgrade, do not introduce Cilium Gateway API, embedded
registry mirror, or new Tailscale multinetwork shards in the same first v3
apply. Upgrade cleanly first, then add opt-in topology features in a separate
reviewed plan.

## Migration items

### 1) Public input renames and removals

v3 uses the major-version window to clean up confusing historical variable names.
Terraform will fail during `plan` if your configuration still uses removed v2
inputs.

Rename these inputs in your `kube.tf`:

| v2 input | v3 input |
| --- | --- |
| `kubernetes_distribution_type` | `kubernetes_distribution` |
| `k3s_token` | `cluster_token` |
| `secrets_encryption` | `enable_secrets_encryption` |
| `initial_k3s_channel` | `k3s_channel` |
| `install_k3s_version` | `k3s_version` |
| `gateway_api_version` | `gateway_api_version` (same name; default is now derived from `cilium_version` unless pinned) |
| `initial_rke2_channel` | `rke2_channel` |
| `install_rke2_version` | `rke2_version` |
| `automatically_upgrade_k3s` | `automatically_upgrade_kubernetes` |
| `sys_upgrade_controller_version` | `system_upgrade_controller_version` |
| `additional_k3s_environment` | `additional_kubernetes_install_environment` |
| `kubeapi_port` | `kubernetes_api_port` |
| `k3s_registries` | `registries_config` |
| `k3s_kubelet_config` | `kubelet_config` |
| `k3s_audit_policy_config` | `audit_policy_config` |
| `k3s_audit_log_path` | `audit_log_path` |
| `k3s_audit_log_maxage` | `audit_log_max_age` |
| `k3s_audit_log_maxbackup` | `audit_log_max_backups` |
| `k3s_audit_log_maxsize` | `audit_log_max_size` |
| `k3s_exec_server_args` | `control_plane_exec_args` |
| `k3s_exec_agent_args` | `agent_exec_args` |
| `k3s_global_kubelet_args` | `global_kubelet_args` |
| `k3s_control_plane_kubelet_args` | `control_plane_kubelet_args` |
| `k3s_agent_kubelet_args` | `agent_kubelet_args` |
| `k3s_autoscaler_kubelet_args` | `autoscaler_kubelet_args` |
| `subnet_amount` | `subnet_count` |
| `placement_group_disable` | `enable_placement_groups` |
| `block_icmp_ping_in` | `allow_inbound_icmp` |
| `disable_hetzner_csi` | `enable_hetzner_csi` |
| `load_balancer_disable_ipv6` | `load_balancer_enable_ipv6` |
| `load_balancer_disable_public_network` | `load_balancer_enable_public_network` |
| `use_control_plane_lb` | `enable_control_plane_load_balancer` |
| `combine_load_balancers` | `reuse_control_plane_load_balancer` |
| `control_plane_lb_type` | `control_plane_load_balancer_type` |
| `control_plane_lb_enable_public_interface` | `control_plane_load_balancer_enable_public_network` |
| `control_plane_lb_enable_public_network` | `control_plane_load_balancer_enable_public_network` |
| `lb_hostname` | `load_balancer_hostname` |
| `robot_ccm_enabled` | `enable_robot_ccm` |
| `cilium_loadbalancer_acceleration_mode` | `cilium_load_balancer_acceleration_mode` |
| `enable_wireguard` | `enable_cni_wireguard_encryption` |
| `k8s_config_updates_use_kured_sentinel` | `kubernetes_config_updates_use_kured_sentinel` |
| `keep_disk_agents` | `keep_disk_agent_nodes` |
| `keep_disk_cp` | `keep_disk_control_plane_nodes` |
| `use_private_bastion` | `use_private_nat_router_bastion` |
| `disable_kube_proxy` | `enable_kube_proxy` (invert value) |
| `disable_network_policy` | `enable_network_policy` (invert value) |
| `disable_selinux` | `enable_selinux` (invert value) |
| `k3s_prefer_bundled_bin` | `prefer_bundled_bin` |
| nodepool `placement_group_compat_idx` | nodepool `placement_group_index` |
| nodepool `disable_ipv4` | nodepool `enable_public_ipv4` (invert value) |
| nodepool `disable_ipv6` | nodepool `enable_public_ipv6` (invert value) |
| `autoscaler_disable_ipv4` | `autoscaler_enable_public_ipv4` (invert value) |
| `autoscaler_disable_ipv6` | `autoscaler_enable_public_ipv6` (invert value) |

For variables that changed from negative to positive names, invert the value:

```hcl
# v2
disable_hetzner_csi = true
placement_group_disable = true
block_icmp_ping_in = false
disable_kube_proxy = true
disable_selinux = false
autoscaler_disable_ipv4 = true

# v3
enable_hetzner_csi = false
enable_placement_groups = false
allow_inbound_icmp = true
enable_kube_proxy = false
enable_selinux = true
autoscaler_enable_public_ipv4 = false
```

Other shape changes:

```hcl
# v2
existing_network_id = ["1234567"]
enable_x86 = true
enable_arm = false

# v3
existing_network = { id = 1234567 }
enabled_architectures = ["x86"]
```

Removed inputs:

- `k3s_encryption_at_rest`: use `enable_secrets_encryption`.
- `hetzner_ccm_use_helm` / `enable_hetzner_ccm_helm`: v3 always installs
  Hetzner CCM through the HelmChart manifest and removes the old raw-manifest
  CCM path.
- `autoscaler_labels` / `autoscaler_taints`: use
  `autoscaler_nodepools[*].labels` and `autoscaler_nodepools[*].taints`.

  ```hcl
  # v2
  autoscaler_labels = ["role=worker"]
  autoscaler_taints = ["dedicated=gpu:NoSchedule"]

  # v3
  autoscaler_nodepools = [
    {
      name        = "workers"
      server_type = "cx32"
      location    = "fsn1"
      min_nodes   = 1
      max_nodes   = 3
      labels      = { role = "worker" }
      taints = [
        {
          key    = "dedicated"
          value  = "gpu"
          effect = "NoSchedule"
        }
      ]
    }
  ]
  ```

Internal Terraform state addresses for the generated cluster token are preserved;
only the public input/output names changed.

### 2) User kustomization variables

The old `extra_kustomize_*` inputs are replaced by `user_kustomizations`.

If your config still contains:
- `extra_kustomize_deployment_commands`
- `extra_kustomize_parameters`
- `extra_kustomize_folder`

Migrate to:

```hcl
user_kustomizations = {
  "1" = {
    source_folder        = "extra-manifests"
    kustomize_parameters = {}
    pre_commands         = ""
    post_commands        = ""
  }
}
```

Then remove the deprecated `extra_kustomize_*` variables from your `kube.tf`.

#### One-to-one migration hint

If you previously used:

```hcl
extra_kustomize_folder               = "extra-manifests"
extra_kustomize_parameters           = { target_namespace = "argocd" }
extra_kustomize_deployment_commands  = "kubectl -n argocd get pods"
```

Migrate to:

```hcl
user_kustomizations = {
  "1" = {
    source_folder        = "extra-manifests"
    kustomize_parameters = { target_namespace = "argocd" }
    pre_commands         = ""
    post_commands        = "kubectl -n argocd get pods"
  }
}
```

### 3) NAT router primary IP drift (older clusters)

If your NAT router was created before v2.19.0, Terraform may propose replacing NAT router primary IPs.

If you want to keep existing IPs, migrate state:

```bash
terraform state rm 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv4[0]'
terraform state rm 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv6[0]'

terraform import 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv4[0]' <ipv4-id>
terraform import 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv6[0]' <ipv6-id>
```

Then run `terraform plan` again and verify stability.

### 4) Autoscaler stability tuning (recommended)

For autoscaling clusters, set explicit autoscaler resources to avoid restart loops under pressure:

```hcl
cluster_autoscaler_replicas        = 2
cluster_autoscaler_resource_limits = true
cluster_autoscaler_resource_values = {
  requests = {
    cpu    = "100m"
    memory = "300Mi"
  }
  limits = {
    cpu    = "200m"
    memory = "500Mi"
  }
}
```

### 5) Network scale note

Hetzner Cloud network constraints still apply. Validate expected cluster size
against current provider/network limits before upgrade. v3 includes two
cross-network paths:

- `node_transport_mode = "tailscale"` is the supported opt-in private transport
  for secure single-network clusters and Flannel-first multinetwork scale-out.
- `multinetwork_mode = "cilium_public_overlay"` is a gated Cilium-only lab
  preview and is not production-supported until live cross-network datapath
  validation passes.

### 6) Networking behavior update

v3 defaults new clusters to `network_subnet_mode = "per_nodepool"`, which
creates one managed Hetzner Cloud subnet for each control-plane and agent
nodepool. This matches the released `v2.x` subnet topology and is the normal
in-place upgrade-safe path.

The optional compact mode is for new clusters or intentional topology changes:

```hcl
network_subnet_mode = "shared"
```

Shared mode keeps one shared agent subnet at the start of the network CIDR and
one shared control-plane subnet at the end of the network CIDR. Do not switch an
in-place v2 upgrade to `shared` unless subnet resource changes are intentional.

Node private IPv4 addresses are now assigned automatically by Hetzner within the attached subnet (instead of manual `cidrhost(...)` calculations in Terraform).

For standard `v2.19.x` clusters, no manual state migration is expected for this change.

If your `terraform plan` proposes subnet replacements, first check for:
- `network_subnet_mode = "shared"` on an in-place v2 upgrade
- custom `subnet_ip_range` overrides
- manual network/subnet edits made outside Terraform
- nodepool topology changes done at the same time as the module upgrade

Resolve those first, then re-run `terraform plan`.

### 7) `enable_iscsid` input removal

`enable_iscsid` was removed. kube-hetzner now enables `iscsid` on all nodes by default.

Migration step:
1. Remove `enable_iscsid` from your `kube.tf` configuration.

### 8) Multinetwork mode (`network_id`)

`network_id` is now wired for node provisioning (instead of being a no-op).

Current behavior:
- Agent nodepools can use external networks via `network_id`.
- Autoscaler nodepools can use external networks with
  `node_transport_mode = "tailscale"` or with the experimental
  `multinetwork_mode = "cilium_public_overlay"`. In both cases the module
  renders one autoscaler Deployment per effective Network.
- Control planes stay on the primary module network and no longer accept a
  `network_id` field.
- Agent and autoscaler nodepools use the primary module network when
  `network_id` is omitted or null. Set a positive Hetzner Network ID only for an
  external network, and use either Tailscale node transport or the Cilium public
  overlay preview for autoscaler external networks.
- In `node_transport_mode = "tailscale"`, active agent and autoscaler nodepools
  must also set `network_scope = "primary"` or `network_scope = "external"`.
  This makes the topology plan-known when `network_id` comes from a same-root
  `hcloud_network` resource.
- In default mode, control planes may attach to external agent networks for
  compatibility with the existing private-network behavior.
- In `node_transport_mode = "tailscale"`, control-plane fanout is disabled,
  Kubernetes keeps Hetzner private node IPs, and Tailscale can advertise each
  node's Hetzner private `/32` route with subnet-route SNAT disabled. Route
  advertisement can be disabled for single-primary-network clusters; it must
  stay enabled for `network_scope = "external"` nodepools.
- In `multinetwork_mode = "cilium_public_overlay"`, control-plane fanout is
  disabled and Cilium uses public IPv4/IPv6 transport with WireGuard encryption
  for pod-to-pod reachability across Hetzner Network islands.
- This public-overlay path is an experimental preview and requires
  `enable_experimental_cilium_public_overlay = true`; do not use it for
  production upgrades yet.
- A public join path is required for Cilium public-overlay multinetwork setups:
  - set `control_plane_endpoint`, or
  - enable a public control-plane LB.
- Tailscale node transport uses the private control-plane endpoint over the
  Tailnet route fabric instead.

Do not turn an existing v2 cluster into a large multinetwork cluster as part of
the same first v3 apply. Upgrade cleanly first, then introduce Tailscale
transport or new `network_scope = "external"` nodepools in a separate audited plan, or
use blue/green.

## Post-upgrade verification checklist

- `terraform validate` succeeds.
- `terraform plan` shows no unexpected replacements for core networking and control-plane resources.
- Control plane quorum and nodepool sizing still match your HA expectations.
