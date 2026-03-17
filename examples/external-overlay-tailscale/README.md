# External Tailscale Overlay Pattern

This example keeps Tailscale outside of `kube-hetzner` core logic and uses
generic kube-hetzner inputs.

## Goals

- Install and join Tailscale on nodes via `preinstall_exec`.
- Route Terraform SSH/provisioners through Tailnet IPs using
  `node_connection_overrides`.
- Optionally expose kube API via an external Tailnet endpoint using
  `control_plane_endpoint`.

## Example module inputs

```tf
module "kube-hetzner" {
  source = "kube-hetzner/kube-hetzner/hcloud"

  # ... regular kube-hetzner configuration ...

  preinstall_exec = [
    "curl -fsSL https://tailscale.com/install.sh | sh",
    "tailscale up --auth-key=${var.tailscale_auth_key} --ssh",
  ]

  # Optional: override kube API endpoint used by agents/secondary control planes
  control_plane_endpoint = var.control_plane_endpoint

  # Optional: once Tailnet IPs are known, route Terraform SSH through them
  # Keys must match final node names.
  node_connection_overrides = var.node_connection_overrides
}
```

## Typical rollout

1. Apply once with `node_connection_overrides = {}` to bootstrap nodes.
2. Discover Tailnet addresses for each node and populate `node_connection_overrides`.
3. Apply again so Terraform shifts SSH/provisioning traffic to Tailnet addresses.
4. Optionally tighten `firewall_ssh_source` and `firewall_kube_api_source`.
