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

## Post-upgrade verification checklist

- `terraform validate` succeeds.
- `terraform plan` shows no unexpected replacements for core networking and control-plane resources.
- Control plane quorum and nodepool sizing still match your HA expectations.
