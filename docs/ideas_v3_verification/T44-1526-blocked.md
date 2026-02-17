# T44 / Discussion #1526 V3 Design Decision

Status: design locked for V3. Implementation is sequenced after #1729 because route/subnet exposure must follow the same multi-network model.

## Why this cannot be done safely as a standalone change
- The current module manages a single private network and fixed subnet allocation patterns.
- #1729 introduces the multi-network foundation needed for clusters beyond current practical limits.
- Adding global `expose_routes_to_vswitch`, `extra_subnets`, and `extra_routes` first would create a temporary API that must be broken later.

## V3 decision
1. Keep current behavior unchanged by default: the primary network still uses `expose_routes_to_vswitch = var.vswitch_id != null`.
2. Implement route/subnet exposure as per-network settings in the #1729 multi-network schema, not as loose top-level globals.
3. Preserve backward compatibility by treating legacy flat variables as primary-network aliases (with deprecation notes).
4. Manage extra routes with `hcloud_network_route` resources keyed by stable `for_each` IDs, instead of nested dynamic route blocks in `hcloud_network`, to minimize replacement risk.
5. Manage extra subnets with `hcloud_network_subnet` `for_each` resources using deterministic keys.

## Planned V3 shape (target)
```hcl
network_extensions = {
  primary = {
    expose_routes_to_vswitch = true
    extra_subnets = [
      {
        type         = "vswitch"
        network_zone = "eu-central"
        ip_range     = "10.10.0.0/24"
        vswitch_id   = 1234
      }
    ]
    extra_routes = [
      {
        destination = "10.50.0.0/16"
        gateway     = "10.0.0.2"
      }
    ]
  }
}
```

## Guardrails
- Validate that each extension key maps to an existing network key.
- Validate `extra_subnets` and `extra_routes` CIDRs do not overlap managed network CIDRs, pod CIDR, or service CIDR.
- Keep all new behavior opt-in; default configuration must produce no plan drift for existing users.
- Terraform-only implementation (no Ansible workflow added).

## Implementation order
1. Merge #1729 multi-network base model first.
2. Add extension variables and validation in `variables.tf`.
3. Build flattened route/subnet locals with stable keys in `locals.tf`.
4. Add `for_each` resources in `main.tf` (and supporting files where needed).
5. Update `README.md`, `docs/llms.md`, and `kube.tf.example` with examples and migration notes.

## Definition of done for T44
- `terraform fmt -recursive`
- `terraform validate`
- Upgrade test from current staging defaults shows no destructive changes.
- Opt-in config for extra routes/subnets shows additive plan only.
