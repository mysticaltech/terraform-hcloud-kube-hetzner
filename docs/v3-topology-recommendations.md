# v3 Topology Recommendations

v3 keeps kube-hetzner's shape: Terraform/OpenTofu, Hetzner Cloud, Leap Micro,
k3s/RKE2, and optional Tailscale node transport. The goal is not to pivot to
Talos, Cluster API, or public-node discovery. The goal is to make the right
Hetzner topology obvious before `terraform plan`.

## Quick Chooser

| Scenario | Choose | Why | Avoid |
| --- | --- | --- | --- |
| Small dev or throwaway cluster | Single location, one control plane, one small agent pool, `ingress_controller = "none"` unless you need ingress | Fast, cheap, easy to destroy | HA, autoscaler, external Networks, and NAT unless the test needs them |
| Normal production HA | 3 control planes, 2+ agents, primary Hetzner Network, public control-plane LB or explicit secure `control_plane_endpoint` | Simple HA with predictable Terraform state and Hetzner private networking | External Network shards before you hit the single-Network attachment budget |
| Private-only NAT cluster | `nat_router` with private nodes and a private control-plane LB | Reduces public node exposure while keeping a simple private topology | External `network_id` shards; the module NAT router only covers the primary Network |
| Single-network Tailscale | `node_transport_mode = "tailscale"`, keep all nodepools on the primary Network, `firewall_kube_api_source = null`, `firewall_ssh_source = null` | Tailnet operator access and kubeconfig without public API/SSH rules | Disabling public IPs unless you already provide private egress and external Tailscale bootstrap |
| +100 Tailscale multinetwork | `node_transport_mode = "tailscale"`, one Hetzner Network per shard, `network_subnet_mode = "per_nodepool"`, route auto-approval in Tailnet policy | Hetzner Networks cap attached resources and do not route between Networks; Tailscale becomes the secure node transport | Cilium public overlay for production, or private Hetzner LBs that target nodes across disconnected Networks |
| 10k reference | Autoscaler-first Tailscale multinetwork, 100 nodes per Network shard, many external Network IDs, explicit quota planning | Terraform state stays smaller and each Network shard stays inside Hetzner's limits | One huge static Terraform server list, one project with too few placement groups, or a single Network |
| RKE2 | `kubernetes_distribution = "rke2"` on Leap Micro, with exact version pinning for conservative production | Heavier distribution, useful when RKE2 behavior is required | Assuming every k3s-only addon behavior maps 1:1; test the preset |
| Cilium dual-stack | `cni_plugin = "cilium"` plus dual-stack cluster/service CIDRs | Best advanced CNI path for IPv4/IPv6 | Flannel/Calico when you need Cilium-only features |
| Cilium Gateway API | `cni_plugin = "cilium"`, `enable_kube_proxy = false`, `cilium_gateway_api_enabled = true` | Native Cilium Gateway controller with standard Gateway API CRDs installed by the module | Traefik Gateway provider in the same mental bucket; it is a different controller |
| Robot/vSwitch | Robot nodepools plus vSwitch route exposure, planned as an advanced topology | Useful for large dedicated-node workers when you accept the networking constraints | Treating Robot/vSwitch as a drop-in Cloud Network replacement |
| Embedded registry mirror | `embedded_registry_mirror.enabled = true` for larger trusted clusters | Reduces duplicate image pulls by using k3s/RKE2's embedded Spegel mirror | Multi-tenant or low-trust node fleets; the mirror assumes equal node trust |

## What Not To Choose

- Do not pivot this module to Talos. Talos is excellent, but this module's v3
  contract is Leap Micro plus k3s/RKE2 with Terraform/OpenTofu-managed
  bootstrap.
- Do not adopt a public-network/IP-query-server scale story. kube-hetzner v3
  should not rely on every node discovering and trusting public addresses for
  production node transport.
- Do not claim Cilium public overlay as the production multinetwork story.
  It remains an experimental preview until live datapath coverage promotes it.
- Do not use Hetzner private Load Balancers as if they span unrelated external
  Networks. They do not make separate Hetzner Networks mutually reachable.
- Do not use a single Hetzner Network for more than its attachment limit. Split
  shards across Networks and keep control-plane fanout under Hetzner's per-server
  Network attachment limit.
- Do not put more than 10 static servers in a single spread Placement Group.
  kube-hetzner auto-shards default static placement groups; explicit named
  placement groups still need operator intent and quota awareness.

## Endpoint Modes

v3 exposes endpoint decisions through additive outputs:

- `effective_kubeconfig_endpoint`: the API endpoint written to the generated
  kubeconfig.
- `effective_node_join_endpoint`: the endpoint used by nodes joining the
  cluster.
- `node_transport_mode`: `private`, `tailscale`, or future transport values.
- `tailscale_control_plane_magicdns_hosts` and
  `tailscale_agent_magicdns_hosts`: deterministic Tailnet hostnames when
  Tailscale node transport is enabled.

Common endpoint modes:

| Mode | How it works | Use when |
| --- | --- | --- |
| Direct public | kubeconfig points at a public control-plane node address | Small labs where public API rules are intentional |
| Public control-plane LB | kubeconfig and joins use a Hetzner public Load Balancer | HA clusters that intentionally expose the API to a narrow source CIDR |
| Private LB plus NAT | nodes are private and a NAT router forwards selected access | You want a private primary-Network topology without Tailscale |
| Explicit endpoint | `control_plane_endpoint` points at your own LB, DNS, proxy, or overlay endpoint | You own endpoint security outside kube-hetzner |
| Tailscale MagicDNS | kubeconfig points at the first control plane's Tailnet hostname | You want API/SSH through Tailnet and closed public Kubernetes rules |

Public join endpoints must resolve to a real API host. v3 accepts IPv4-only,
IPv6-only, and dual-stack public joins, but it rejects private-only control
planes unless `control_plane_endpoint` or a public control-plane Load Balancer
provides the public API host.

## Tailscale Multinetwork Rules

Hetzner Cloud Networks are separate L3 islands. A server can attach to only a
small number of Networks, and a single Network has a finite attachment budget.
For +100 node clusters, use one Network per shard and let Tailscale carry the
node-private routes:

```hcl
node_transport_mode = "tailscale"
firewall_kube_api_source = null
firewall_ssh_source      = null

tailscale_node_transport = {
  bootstrap_mode  = "cloud_init"
  magicdns_domain = "example-tailnet.ts.net"

  routing = {
    advertise_node_private_routes = true
  }
}
```

Tailnet policy must auto-approve the advertised private routes for the tags or
users used by the nodes. The module sets `--snat-subnet-routes=false` so CNI
traffic preserves the real node source IP.

Public IPs are still useful for Tailscale bootstrap, package installs, and
direct WireGuard paths. Closing public Kubernetes API/SSH rules is the security
boundary; removing public IPs entirely requires external per-Network egress and
Tailscale bootstrap.

## Cilium Gateway API

Use Cilium Gateway API when Cilium should own the Gateway controller:

```hcl
cni_plugin                 = "cilium"
enable_kube_proxy         = false
cilium_gateway_api_enabled = true
```

The module installs the standard Gateway API CRDs matching the selected Cilium
line, enables `gatewayAPI.enabled` in Cilium Helm values, and enables
cert-manager Gateway API support when any Gateway provider is active.

Do not confuse this with Traefik's Kubernetes Gateway provider:

```hcl
ingress_controller                         = "traefik"
traefik_provider_kubernetes_gateway_enabled = true
```

Both paths use Gateway API objects, but they are different controllers. Choose
one Gateway controller per cluster; v3 rejects enabling Cilium Gateway API and
Traefik's Gateway provider at the same time.

## Embedded Registry Mirror

For large trusted clusters, enable the k3s/RKE2 embedded registry mirror:

```hcl
embedded_registry_mirror = {
  enabled                  = true
  registries               = ["docker.io", "registry.k8s.io", "ghcr.io", "quay.io"]
  disable_default_endpoint = false
}
```

This writes empty mirror entries into the effective `registries.yaml` and sets
`embedded-registry: true` on server nodes. User-provided `registries_config`
entries are preserved and win over module-provided empty defaults.

Security model:

- All nodes in the cluster are trusted peers.
- Images pulled with credentials on one node may become available to other
  nodes.
- Tags can be poisoned by a node that can place images in its containerd store.
- Prefer digest-pinned images for critical workloads.
- In Tailscale multinetwork clusters, keep
  `tailscale_node_transport.routing.advertise_node_private_routes = true`
  because embedded registry peer traffic must cross Network shards.

## Release Validation

Before release or topology changes:

```bash
terraform fmt -recursive
terraform-docs markdown . > docs/terraform.md
terraform init -backend=false
terraform validate
tofu init -backend=false
tofu validate
uv run scripts/validate_tailscale_large_scale_examples.py
uv run scripts/validate_v3_final_polish_examples.py
git diff --check
```

Run OpenTofu in a temporary copy if you need to keep the Terraform lockfile and
plugin cache untouched in the main checkout.
