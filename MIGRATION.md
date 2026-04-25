# Migration advice when updating the module

## v2.x -> v3.x

This is a major upgrade line. Use a staged upgrade and verify plans carefully.

### Recommended upgrade flow

1. Pin the module to your target v3 tag.
2. Reinitialize providers and modules:
   ```bash
   terraform init -upgrade
   ```
3. Review the plan before applying:
   ```bash
   terraform plan
   ```
4. Apply only after you understand every `replace`/`destroy` action.

## Migration items

### 1) User kustomization variables

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

### 2) NAT router primary IP drift (older clusters)

If your NAT router was created before v2.19.0, Terraform may propose replacing NAT router primary IPs.

If you want to keep existing IPs, migrate state:

```bash
terraform state rm 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv4[0]'
terraform state rm 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv6[0]'

terraform import 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv4[0]' <ipv4-id>
terraform import 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv6[0]' <ipv6-id>
```

Then run `terraform plan` again and verify stability.

### 3) Autoscaler stability tuning (recommended)

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

### 4) Network scale note

Hetzner Cloud network constraints still apply. Validate expected cluster size against current provider/network limits before upgrade.

### 5) Networking behavior update

Per-nodepool managed cloud subnets are preserved for both control-plane and agent pools to stay upgrade-compatible with existing `v2.x` clusters.

Node private IPv4 addresses are now assigned automatically by Hetzner within the attached subnet (instead of manual `cidrhost(...)` calculations in Terraform).

For standard `v2.19.x` clusters, no manual state migration is expected for this change.

If your `terraform plan` still proposes subnet replacements, first check for:
- custom `subnet_ip_range` overrides
- manual network/subnet edits made outside Terraform
- nodepool topology changes done at the same time as the module upgrade

Resolve those first, then re-run `terraform plan`.

### 6) `enable_iscsid` input removal

`enable_iscsid` was removed. kube-hetzner now enables `iscsid` on all nodes by default.

Migration step:
1. Remove `enable_iscsid` from your `kube.tf` configuration.

### 7) Multinetwork groundwork (`network_id`)

`network_id` is now wired for node provisioning (instead of being a no-op).

Current behavior:
- Agent nodepools can use external networks via `network_id`.
- Control planes stay on the primary module network (`network_id = 0`) and are auto-attached to external agent networks.
- A public join path is required for multinetwork setups:
  - set `control_plane_endpoint`, or
  - enable a public control-plane LB.

Current limitation:
- Cluster autoscaler is still single-network (`HCLOUD_NETWORK`) and is not supported with multinetwork primary networks.

## Post-upgrade verification checklist

- `terraform validate` succeeds.
- `terraform plan` shows no unexpected replacements for core networking and control-plane resources.
- Control plane quorum and nodepool sizing still match your HA expectations.
