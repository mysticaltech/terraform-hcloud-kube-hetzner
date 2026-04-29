# Cilium Multinetwork Preview Pattern for v3

This example shows the experimental v3 preview for clusters that need to span
more than one Hetzner Cloud Network. It is intentionally Cilium-only, but it is
not production-supported until the live cross-network Cilium datapath test
passes.

## Boundary

`multinetwork_mode = "cilium_public_overlay"` uses public node addresses for
Cilium tunnel/WireGuard peer reachability. Hetzner private Networks remain
separate attachment domains; kube-hetzner does not try to route every private
Network to every other private Network.

This mode is for Hetzner Cloud nodes. Robot/vSwitch exposure and private-only
multinetwork scale need a separately routed or VPN-backed topology.

## Example module inputs

```hcl
cni_plugin = "cilium"

enable_experimental_cilium_public_overlay = true
multinetwork_mode                         = "cilium_public_overlay"
multinetwork_transport_ip_family          = "ipv4" # ipv4 | ipv6 | dualstack

enable_control_plane_load_balancer                   = true
control_plane_load_balancer_enable_public_network    = true
load_balancer_enable_public_network                  = true
multinetwork_cilium_peer_ipv4_cidrs                  = ["0.0.0.0/0"] # tighten when possible

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
    max_nodes   = 25
  },
  {
    name        = "autoscaled-secondary"
    server_type = "cx23"
    location    = "nbg1"
    min_nodes   = 0
    max_nodes   = 25
    network_id  = 11959154
  },
]
```

## What Terraform validates

- `cni_plugin` must be `cilium`.
- Public node addresses must be enabled for the selected transport family.
- NAT router mode is rejected.
- Control planes stay on the primary kube-hetzner network.
- External agent/autoscaler `network_id` values are counted against Hetzner's
  100 attached-resource-per-Network limit.
- Cluster Autoscaler is split per effective Network so each Deployment gets the
  correct `HCLOUD_NETWORK`.
- Default spread placement groups are sharded every 10 servers.

Run `terraform plan` or `tofu plan` before every apply; this mode deliberately
fails early when the topology cannot work.
