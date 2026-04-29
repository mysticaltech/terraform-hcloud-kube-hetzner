# v3 Tailscale Node Transport Plan

## Decision

v3 supports Tailscale as an opt-in Kubernetes node transport:

```hcl
node_transport_mode = "tailscale"
```

This is both a secure single-network access path and the production path for
private multinetwork scale. It is deliberately different from the older
external-overlay operator-access pattern.

## Core Model

- Kubernetes keeps Hetzner private node IPs.
- Hetzner CCM, CSI, and Load Balancers continue to see provider-owned node
  addresses rather than Tailnet `100.64.0.0/10` addresses.
- Tailscale carries encrypted L3 traffic between otherwise separate Hetzner
  private Networks.
- Every node can advertise its own Hetzner private `/32` route. This defaults
  to enabled for transport safety and is required when external `network_id`
  nodepools are used; single-primary-network clusters may disable it.
- Every node accepts Tailnet routes by default.
- Subnet-route SNAT is disabled with `--snat-subnet-routes=false` so CNI and
  Kubernetes node traffic preserve the real Hetzner source node IP.
- Tailnet ACLs must auto-approve the advertised node-private routes for the node
  tags used by the module.

## Supported Matrix

| Distribution | CNI | Status |
| --- | --- | --- |
| k3s | Flannel VXLAN | First supported path |
| k3s | Cilium | Experimental gate: `tailscale_node_transport.enable_experimental_cilium = true` |
| k3s | Calico | Rejected until live-tested |
| RKE2 | Cilium | Experimental gate: `enable_experimental_rke2 = true` and `enable_experimental_cilium = true` |
| RKE2 | Flannel/Calico | Rejected for this release |

## Public API

```hcl
node_transport_mode = "hetzner_private" # hetzner_private | tailscale

tailscale_auth_key = var.tailscale_auth_key

# Optional role-specific auth keys. Any shared auth key must be reusable;
# a single-use auth key only registers the first node that consumes it.
tailscale_control_plane_auth_key = var.tailscale_control_plane_auth_key
tailscale_agent_auth_key         = var.tailscale_agent_auth_key
tailscale_autoscaler_auth_key    = var.tailscale_autoscaler_auth_key

tailscale_node_transport = {
  bootstrap_mode  = "cloud_init" # remote_exec | cloud_init | external
  version         = "latest"
  magicdns_domain = "example-tailnet.ts.net"

  auth = {
    mode = "auth_key" # auth_key | oauth_client_secret | external

    # Optional in auth_key mode; required in oauth_client_secret mode.
    # Configure Tailnet tagOwners/autoApprovers before enabling tags.
    advertise_tags_control_plane = []
    advertise_tags_agent         = []
    advertise_tags_autoscaler    = []

    # OAuth-only auth-key parameters.
    oauth_static_nodes_ephemeral = false
    oauth_autoscaler_ephemeral   = true
    oauth_preauthorized          = true
  }

  ssh = {
    use_tailnet_for_terraform = true
    enable_tailscale_ssh      = false
  }

  routing = {
    advertise_node_private_routes = true
    advertise_additional_routes = []
  }

  kubernetes = {
    cni_mtu             = 1280
    kubeconfig_endpoint = "first_control_plane_tailnet"
  }

  enable_experimental_cilium = false
  enable_experimental_rke2   = false
}
```

## Plan-Time Guardrails

Terraform/OpenTofu validation rejects:

- Missing `magicdns_domain` in Tailscale mode.
- Missing shared or role-specific auth values, unless `auth.mode = "external"`.
- Public world-open Kubernetes API or SSH firewall rules.
- Module-managed control-plane Load Balancers.
- `multinetwork_mode = "cilium_public_overlay"` combined with Tailscale mode.
- Calico in Tailscale mode.
- Cilium without `enable_experimental_cilium = true`.
- RKE2 without both experimental Tailscale gates and Cilium.
- Flannel `host-gw`.
- Tailnet reserved CIDR overlap with cluster, service, or Hetzner Network CIDRs.
- Autoscaler nodepools in Tailscale mode unless `bootstrap_mode = "cloud_init"`.
- Managed Tailscale bootstrap when nodes have no public IPv4, public IPv6, or
  usable primary-network NAT-router egress. External Hetzner Networks need
  their own public egress for module-managed bootstrap.
- `routing.advertise_node_private_routes = false` when any agent or autoscaler
  nodepool uses an external `network_id`.
- `nat_router` combined with external-network agent/autoscaler nodepools,
  because the module NAT router only serves the primary Hetzner Network.
- Managed ingress combinations that require private Hetzner Load Balancers to
  span separate Hetzner Networks.

## Bootstrap Modes

`remote_exec`:
Terraform SSHes to static nodes through their initial public/private path,
installs Tailscale, joins the tailnet, then later provisioners can use MagicDNS
if configured. This mode does not support autoscaler-created nodes.

`cloud_init`:
Tailscale bootstrap is rendered before Kubernetes bootstrap. Required for
autoscaler nodepools because Terraform cannot remote-exec into nodes that do
not exist yet.

`external`:
The operator guarantees Tailscale is already installed, authenticated, and
reachable. kube-hetzner validates assumptions but does not manage Tailscale
installation/authentication.

## Load Balancers

Tailscale does not let Hetzner private Load Balancers target nodes across
separate private Networks. Private Hetzner Load Balancers remain valid for
single-primary-network Tailscale clusters. With external `network_id`
nodepools, managed Hetzner load-balancer targets need public node IPs, or the
cluster should use Klipper/MetalLB, `ingress_controller = "none"`/`custom`, a
user-managed load balancer, or a post-bootstrap Tailscale Kubernetes Operator
pattern.

## Autoscaler

Autoscaler support is part of the design:

- one autoscaler Deployment per effective `network_id`;
- `HCLOUD_NETWORK` points at the target private Network;
- autoscaler cloud-init runs Tailscale before Kubernetes joins;
- auth-key mode may use a role-specific `tailscale_autoscaler_auth_key`;
- OAuth mode defaults autoscaler-created nodes to ephemeral devices.

## Documentation And Testing Tasks

1. Keep `README.md`, `kube.tf.example`, `docs/llms.md`, `docs/terraform.md`,
   `CHANGELOG.md`, `MIGRATION.md`, and examples aligned with this contract.
2. Keep `.claude/skills/kh-assistant` and `.claude/skills/migrate-v2-to-v3`
   aware of Tailscale node transport vs external overlay access.
3. Static validate defaults, Tailscale success, Tailscale invalid firewall,
   unsupported CNI, autoscaler bootstrap, and OpenTofu scenarios.
4. Live proof before final release should include node readiness, CNI health,
   cross-network pod traffic, `tailscale status`, `tailscale netcheck`,
   approved routes, autoscaler scale-up/down, and hcloud cleanup.

References:

- <https://tailscale.com/kb/1019/subnets>
- <https://tailscale.com/docs/reference/troubleshooting/network-configuration/disable-subnet-route-masquerading>
- <https://tailscale.com/kb/1215/oauth-clients>
