# External Tailscale Overlay Pattern for v3

This example keeps Tailscale outside of `kube-hetzner` core logic and uses
generic kube-hetzner inputs. Tailscale is supported as a blessed external
overlay pattern, not as a provider-specific `enable_tailscale` switch.

## Goals

- Optionally install the Tailscale client on nodes via `preinstall_exec`.
- Route Terraform SSH/provisioners through Tailnet IPs using
  `node_connection_overrides`.
- Optionally expose kube API via an external Tailnet endpoint using
  `control_plane_endpoint`.
- Keep Tailscale Kubernetes features in the post-bootstrap add-on layer.

## Boundary

kube-hetzner does not manage your tailnet, ACLs, auth keys, MagicDNS, route
approvals, subnet routers, Tailscale Services, or Tailscale Kubernetes
Operator installation. Tailscale is supported as an external operator-access
overlay, not as the cluster CNI or the v3 multinetwork scale fabric. For large
Hetzner Cloud multinetwork clusters, use `multinetwork_mode =
"cilium_public_overlay"`.

Avoid putting long-lived Tailscale auth keys directly in Terraform strings.
`preinstall_exec` commands and server user-data can appear in Terraform/provider
state or cloud-init logs. Prefer an external bootstrap, or short-lived one-use
preauth keys that are rotated/revoked immediately after nodes join.

## Supported kube-hetzner primitives

- `preinstall_exec` and `postinstall_exec`: user-owned bootstrap hooks.
- `node_connection_overrides`: node name to Tailnet IP/hostname for Terraform
  SSH and provisioners.
- `control_plane_endpoint`: stable kube API endpoint reachable over the overlay.
- `use_private_nat_router_bastion`: use the NAT router private IP as the SSH
  bastion once the operator can already reach the private network.
- `firewall_ssh_source` and `firewall_kube_api_source`: tighten public ingress
  after overlay access is proven.

## Example module inputs

```tf
module "kube-hetzner" {
  source = "kube-hetzner/kube-hetzner/hcloud"
  # version = "3.0.0"

  # ... regular kube-hetzner configuration ...

  preinstall_exec = [
    "curl -fsSL https://tailscale.com/install.sh | sh",
    # Use only a short-lived one-use key if you automate this through Terraform.
    # "tailscale up --auth-key=${var.tailscale_auth_key} --ssh --hostname=$(hostname)",
  ]

  # Optional: override kube API endpoint used by agents/secondary control planes
  control_plane_endpoint = var.control_plane_endpoint

  # Optional: once Tailnet IPs are known, route Terraform SSH through them
  # Keys must match final node names.
  node_connection_overrides = var.node_connection_overrides
}
```

## Typical rollout

1. Apply once with `node_connection_overrides = {}` to bootstrap nodes and install/join the overlay.
2. Discover Tailnet addresses for each node and populate `node_connection_overrides`.
3. Apply again so Terraform shifts SSH/provisioning traffic to Tailnet addresses.
4. Optionally tighten `firewall_ssh_source` and `firewall_kube_api_source`.
5. Optionally deploy the Tailscale Kubernetes Operator after the cluster is
   healthy if you want Tailscale Services, workload ingress/egress, subnet
   routers, or kube API proxying.

## Post-bootstrap Kubernetes Operator

Install the Tailscale Kubernetes Operator with Helm, ArgoCD, or
`user_kustomizations` after kube-hetzner has produced a working cluster.
Keep OAuth client credentials and tailnet policy management outside the
kube-hetzner module. This preserves a clean responsibility split: kube-hetzner
creates the cluster and exposes generic hooks; Tailscale owns tailnet identity,
ACLs, route approval, and Kubernetes proxy features.
