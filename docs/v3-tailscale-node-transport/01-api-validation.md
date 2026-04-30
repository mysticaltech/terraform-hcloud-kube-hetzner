# M1 API And Cross-Variable Validation

## Decisions

- Add `node_transport_mode = "hetzner_private" | "tailscale"`.
- Add `tailscale_node_transport` for non-secret transport settings.
- Add separate sensitive auth variables so credentials are not hidden inside a
  large object:
  - `tailscale_auth_key`
  - `tailscale_control_plane_auth_key`
  - `tailscale_agent_auth_key`
  - `tailscale_autoscaler_auth_key`
  - `tailscale_oauth_client_secret`
- Keep `multinetwork_mode = "cilium_public_overlay"` as experimental only until
  removed or fully proven.

## Write Set

- `variables.tf`
- `validation-locals.tf`
- `locals.tf`
- `docs/terraform.md` after generation

## Validation Rules

- Tailscale mode requires a MagicDNS domain.
- Tailscale mode requires supported bootstrap/auth combinations.
- Auth-key mode accepts one shared key or role-specific keys. Autoscaler
  nodepools require a shared key or `tailscale_autoscaler_auth_key`.
- OAuth mode supports role-specific ephemeral/preauthorized auth-key
  parameters; static nodes default durable, autoscaler nodes default ephemeral.
- Autoscaler nodepools require `bootstrap_mode = "cloud_init"`.
- CNI/distribution support is explicit; Calico is blocked until its child plan
  proves node autodetection.
- Tailnet CIDR collision checks must cover module-known CIDR starts.
- Tailscale mode may use private Hetzner Load Balancers in single-primary-network
  clusters, but must reject private LB target assumptions across external
  `network_id` nodepools.

## Tests

- Terraform validate default config.
- Terraform validate Tailscale missing auth fails.
- Terraform validate unsupported CNI fails.
- Terraform validate autoscaler without cloud-init fails.
- OpenTofu validates the same module contract.
