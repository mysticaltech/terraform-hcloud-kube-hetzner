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
2. Rename/remove v2-only inputs listed below.
3. Pin the module to your target v3 tag.
4. Reinitialize providers and modules:
   ```bash
   terraform init -upgrade
   ```
5. Validate and review the plan before applying:
   ```bash
   terraform validate
   terraform plan
   ```
6. Apply only after you understand every `replace`/`destroy` action.

Stop immediately if Terraform proposes unexpected replacements for networks,
subnets, load balancers, servers, primary IPs, placement groups, or volumes.

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
| `hetzner_ccm_use_helm` | `enable_hetzner_ccm_helm` |
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
- `autoscaler_labels` / `autoscaler_taints`: use
  `autoscaler_nodepools[*].labels` and `autoscaler_nodepools[*].taints`.

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
against current provider/network limits before upgrade. For clusters that need to
span several Hetzner Networks, v3 adds the opt-in Cilium-only
`multinetwork_mode = "cilium_public_overlay"` topology.

### 6) Networking behavior update

Per-nodepool managed cloud subnets are preserved for both control-plane and agent pools to stay upgrade-compatible with existing `v2.x` clusters.

Node private IPv4 addresses are now assigned automatically by Hetzner within the attached subnet (instead of manual `cidrhost(...)` calculations in Terraform).

For standard `v2.19.x` clusters, no manual state migration is expected for this change.

If your `terraform plan` still proposes subnet replacements, first check for:
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
- Autoscaler nodepools can use external networks only with
  `multinetwork_mode = "cilium_public_overlay"`, where the module renders one
  autoscaler Deployment per effective Network.
- Control planes stay on the primary module network and no longer accept a
  `network_id` field.
- Agent and autoscaler nodepools use the primary module network when
  `network_id` is omitted or null. Set a positive Hetzner Network ID only for an
  external network, and keep autoscaler external networks on the Cilium public
  overlay path.
- In default mode, control planes may attach to external agent networks for
  compatibility with the existing private-network behavior.
- In `multinetwork_mode = "cilium_public_overlay"`, control-plane fanout is
  disabled and Cilium uses public IPv4/IPv6 transport with WireGuard encryption
  for pod-to-pod reachability across Hetzner Network islands.
- A public join path is required for multinetwork setups:
  - set `control_plane_endpoint`, or
  - enable a public control-plane LB.

First v3 multinetwork release is intentionally Cilium-only. Do not use it with
Flannel or Calico; Terraform validation rejects that combination.

## Post-upgrade verification checklist

- `terraform validate` succeeds.
- `terraform plan` shows no unexpected replacements for core networking and control-plane resources.
- Control plane quorum and nodepool sizing still match your HA expectations.
