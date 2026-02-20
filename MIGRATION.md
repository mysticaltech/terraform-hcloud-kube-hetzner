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

### 5) Shared-subnet networking (breaking change)

v3 consolidates managed node private IPv4 allocation into a shared cloud subnet (`hcloud_network_subnet.control_plane`) instead of keeping separate managed agent/control-plane subnets.

For clusters created on `v2.x`, this is not a transparent in-place topology change. A direct `terraform apply` can propose disruptive subnet replacement/detach actions.

Recommended approach:

1. Prefer blue/green migration:
   - Stand up a fresh v3 cluster.
   - Migrate workloads/stateful data.
   - Decommission the old cluster after validation.
2. If attempting in-place upgrade, treat it as advanced/manual migration:
   - Review every subnet/network action in `terraform plan`.
   - Expect maintenance windows and potential downtime.
   - Do not apply if plan contains unexpected subnet destroys/recreates.

## Post-upgrade verification checklist

- `terraform validate` succeeds.
- `terraform plan` shows no unexpected replacements for core networking and control-plane resources.
- Control plane quorum and nodepool sizing still match your HA expectations.
