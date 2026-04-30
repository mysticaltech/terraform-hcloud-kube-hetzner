# Tailscale Node Transport for v3

This example shows the supported v3 path for using Tailscale as kube-hetzner's
node transport. It is useful in two shapes:

- A normal single-network cluster where you want Terraform, kubeconfig, and
  operator SSH to use a private Tailnet path while public Kubernetes API/SSH
  firewall rules stay closed.
- A scale-out cluster that spans multiple Hetzner Cloud Networks without
  exposing Kubernetes node transport on public interfaces.

`node_transport_mode = "tailscale"` installs and joins Tailscale on every node
while Kubernetes keeps Hetzner private node IPs. Tailscale is the encrypted L3
transport and access path; it is not the CNI.

Cloudflare Zero Trust can still be useful beside this pattern as an external
Access/Tunnel layer for human-facing endpoints. Keep the responsibility split
clean: Tailscale carries kube-hetzner node transport; Cloudflare protects
selected API, SSH, Rancher, Grafana, or ingress hostnames outside this module.
Cloudflare Mesh/WARP is not a supported kube-hetzner node transport in v3.

## When to Use This

- You want to close public API and SSH firewall rules but still let Terraform
  and operators reach nodes through MagicDNS.
- You want kubeconfig to point at the first control plane's Tailnet endpoint.
- You need more than one Hetzner Cloud Network because a single Network's
  attachment limit is not enough.
- Agent or autoscaler nodepools may use `network_id` to spread nodes across
  existing Hetzner private Networks.
- You want Flannel to remain the CNI while Tailscale provides secure
  cross-network node reachability when needed.
- You accept that Tailnet ACLs, tags, auth keys/OAuth clients, and route
  approvals are still owned by your Tailscale admin policy.

## Minimal Single-Network Cluster

```hcl
node_transport_mode = "tailscale"

firewall_kube_api_source = null
firewall_ssh_source      = null

tailscale_auth_key = var.tailscale_auth_key

# Optional: split key policy by role. Shared auth keys must be reusable. This is
# recommended when autoscaler nodes should use a reusable, pre-approved, tagged,
# ephemeral key while static nodes use durable tagged keys.
# tailscale_control_plane_auth_key = var.tailscale_control_plane_auth_key
# tailscale_agent_auth_key         = var.tailscale_agent_auth_key
# tailscale_autoscaler_auth_key    = var.tailscale_autoscaler_auth_key

tailscale_node_transport = {
  # cloud_init brings Tailscale up before Terraform tries Tailnet SSH.
  bootstrap_mode  = "cloud_init"
  magicdns_domain = "example-tailnet.ts.net"

  auth = {
    mode = "auth_key"
    # Optional; configure Tailnet tagOwners/autoApprovers before enabling tags.
    # advertise_tags_control_plane = ["tag:kube-hetzner-control-plane"]
    # advertise_tags_agent         = ["tag:kube-hetzner-agent"]
    # advertise_tags_autoscaler    = ["tag:kube-hetzner-autoscaler"]
  }

  routing = {
    # In a single Hetzner Network, Kubernetes already has private node-to-node
    # reachability. This avoids Tailnet route approval work for the simple case.
    advertise_node_private_routes = false
    advertise_additional_routes   = []
  }
}

agent_nodepools = [
  {
    name        = "agents"
    server_type = "cx23"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 2
  }
]
```

## Multinetwork Scale-Out

When any agent or autoscaler nodepool uses an external `network_id`, keep
`advertise_node_private_routes = true` and make sure Tailnet policy auto-approves
the relevant private routes.

```hcl
tailscale_node_transport = {
  bootstrap_mode  = "cloud_init"
  magicdns_domain = "example-tailnet.ts.net"

  auth = {
    mode = "auth_key"
    # Optional; configure Tailnet tagOwners/autoApprovers before enabling tags.
    # advertise_tags_control_plane = ["tag:kube-hetzner-control-plane"]
    # advertise_tags_agent         = ["tag:kube-hetzner-agent"]
    # advertise_tags_autoscaler    = ["tag:kube-hetzner-autoscaler"]
  }

  routing = {
    advertise_node_private_routes = true
  }
}

agent_nodepools = [
  {
    name        = "agents-primary"
    server_type = "cx23"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 50
  },
  {
    name        = "agents-secondary"
    server_type = "cx23"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 50
    network_id  = 11959154
  },
]

autoscaler_nodepools = [
  {
    name        = "autoscaled-primary"
    server_type = "cx23"
    location    = "nbg1"
    min_nodes   = 0
    max_nodes   = 50
  },
  {
    name        = "autoscaled-secondary"
    server_type = "cx23"
    location    = "nbg1"
    min_nodes   = 0
    max_nodes   = 50
    network_id  = 11959154
  },
]
```

## Large-Scale Reference Topologies

Hetzner Cloud Networks cap attached resources per Network, separate Networks do
not route to each other, and spread Placement Groups cap both the number of
servers per group and the number of groups per project. Tailscale is the
transport that lets nodepools live on separate Hetzner Networks without making
Kubernetes node transport public.

- [`large-scale-200.tf.example`](./large-scale-200.tf.example) is the concrete
  +100-node static example: 3 control planes plus 97 primary agents on the
  primary Network, and 100 agents on one external Network. Both Networks sit at
  exactly 100 attachments. Static count-based nodepools leave
  `placement_group` unset so kube-hetzner auto-shards spread groups every 10
  servers.
- [`massive-10000-nodes.tf.example`](./massive-10000-nodes.tf.example) is a
  10,000-total-node reference: 3 control planes, 7 static system agents, 90
  autoscaled workers on the primary Network, and 99 external Network shards
  with 100 autoscaled workers each. It is deliberately autoscaler-first because
  static Terraform state for 10,000 server resources and 1,000 placement groups
  is not a sane single-project shape.

Exposure model for these examples:

- Kubernetes API and SSH are not exposed publicly:
  `firewall_kube_api_source = null` and `firewall_ssh_source = null`.
- No public web entrypoint is created: `ingress_controller = "none"`.
- Nodes keep public IPv4/IPv6 by default for Tailscale bootstrap, package
  downloads, and direct WireGuard connectivity. The opened public surface is
  Tailscale UDP/41641, not Kubernetes API, SSH, or HTTP/S.
- A no-public-IP variant requires a private egress/bootstrap design for every
  Hetzner Network and usually `tailscale_node_transport.bootstrap_mode =
  "external"`. The module NAT router only covers the primary Network and is not
  the turnkey answer for external Network shards.
- Autoscaler-created nodes are not assigned Hetzner Placement Groups by
  kube-hetzner today. If strict physical spread is a hard requirement for every
  worker, split across smaller clusters/projects or add explicit autoscaler
  placement-group support before going to production.

Before editing the large-scale examples, run:

```bash
uv run scripts/validate_tailscale_large_scale_examples.py
```

This checks the example files' node math, per-Network attachment counts,
placement-group counts, and public-exposure defaults. It intentionally proves
the reference topology only; it does not claim a live 10,000-node E2E.

For trusted large clusters, you can add the embedded registry mirror to reduce
duplicate image pulls across nodes:

```hcl
embedded_registry_mirror = {
  enabled                  = true
  registries               = ["docker.io", "registry.k8s.io", "ghcr.io", "quay.io"]
  disable_default_endpoint = false
}
```

Keep `tailscale_node_transport.routing.advertise_node_private_routes = true`
when any nodepool uses an external `network_id`; the registry mirror peer ports
need the same cross-Network private reachability as Kubernetes node traffic.

## OAuth Mode

OAuth mode uses one Tailscale OAuth client secret and asks Tailscale to create
role-specific auth keys from the advertised tags.

```hcl
tailscale_oauth_client_secret = var.tailscale_oauth_client_secret

tailscale_node_transport = {
  bootstrap_mode  = "cloud_init"
  magicdns_domain = "example-tailnet.ts.net"

  auth = {
    mode = "oauth_client_secret"

    advertise_tags_control_plane = ["tag:kube-hetzner-control-plane"]
    advertise_tags_agent         = ["tag:kube-hetzner-agent"]
    advertise_tags_autoscaler    = ["tag:kube-hetzner-autoscaler"]

    oauth_static_nodes_ephemeral = false
    oauth_autoscaler_ephemeral   = true
    oauth_preauthorized          = true
  }
}
```

## Tailnet Policy

The tailnet must allow node identities to talk to each other. When
`advertise_node_private_routes = true`, the tailnet must also auto-approve the
advertised node-private routes. In production, tagged nodes are the cleanest
policy boundary, but tags are opt-in for `auth_key` mode because a simple auth
key must be allowed to request the tag first. The `autoApprovers.routes` CIDRs
can be broader than the individual `/32` routes; keep them aligned with your
`network_ipv4_cidr`, `existing_network`, and external nodepool Networks.

```json
{
  "tagOwners": {
    "tag:kube-hetzner-control-plane": ["autogroup:admin"],
    "tag:kube-hetzner-agent": ["autogroup:admin"],
    "tag:kube-hetzner-autoscaler": ["autogroup:admin"]
  },
  "autoApprovers": {
    "routes": {
      "10.0.0.0/16": [
        "tag:kube-hetzner-control-plane",
        "tag:kube-hetzner-agent",
        "tag:kube-hetzner-autoscaler"
      ],
      "10.1.0.0/16": [
        "tag:kube-hetzner-agent",
        "tag:kube-hetzner-autoscaler"
      ]
    }
  },
  "grants": [
    {
      "src": [
        "tag:kube-hetzner-control-plane",
        "tag:kube-hetzner-agent",
        "tag:kube-hetzner-autoscaler"
      ],
      "dst": [
        "tag:kube-hetzner-control-plane:*",
        "tag:kube-hetzner-agent:*",
        "tag:kube-hetzner-autoscaler:*"
      ],
      "ip": ["*"]
    }
  ]
}
```

## Important Mechanics

- Kubernetes keeps Hetzner private node IPs. This avoids fighting Hetzner CCM,
  CSI, and Load Balancer node address reconciliation.
- The module passes `--snat-subnet-routes=false` when advertising node-private
  routes so CNI traffic preserves the real source node IP. Single-network
  clusters may disable node-private route advertisement.
- Flannel VXLAN is the first supported CNI. Cilium is gated by
  `tailscale_node_transport.enable_experimental_cilium = true` until live
  datapath coverage promotes it. Calico is rejected for now.
- Autoscaler nodepools require `bootstrap_mode = "cloud_init"` because
  Terraform cannot remote-exec into nodes that do not exist yet.
- The module NAT router is only a primary-network egress path. Do not combine
  it with external-network Tailscale nodepools in this release; those nodepools
  need their own egress path.
- Managed Hetzner private Load Balancers work for single-primary-network
  Tailscale clusters. They still cannot target private IPs across separate
  nodepool Networks. With external `network_id` nodepools, use public LB
  targets, Klipper/MetalLB, no/custom ingress, or your own load-balancing layer.
- `firewall_kube_api_source` and `firewall_ssh_source` must be `null` or
  restricted to explicit CIDRs. World-open public API/SSH is rejected.
- Public module-managed control-plane Load Balancers are rejected in Tailscale
  mode. Private control-plane Load Balancers remain available for
  single-network HA/API patterns, while kubeconfig defaults to the first control
  plane's Tailnet MagicDNS endpoint unless you set an explicit endpoint.

Useful Tailscale references:

- [Hetzner Cloud Network limits](https://docs.hetzner.com/cloud/networks/overview/)
- [Hetzner Placement Group limits](https://docs.hetzner.com/cloud/placement-groups/overview/)
- [Subnet routers](https://tailscale.com/kb/1019/subnets)
- [Disable subnet route masquerading](https://tailscale.com/docs/reference/troubleshooting/network-configuration/disable-subnet-route-masquerading)
- [Firewall ports and direct connections](https://tailscale.com/docs/reference/faq/firewall-ports)
- [Tailnet policy auto-approvers](https://tailscale.com/kb/1337/policy-syntax)
- [OAuth clients](https://tailscale.com/kb/1215/oauth-clients)
