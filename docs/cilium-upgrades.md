# Cilium upgrade diagnostics

Review the [v2-to-v3 datapath warning](../MIGRATION.md#cilium-datapath-migration)
before changing kube-proxy ownership on an existing cluster. These diagnostics
do not constitute a validated in-place datapath migration procedure.

## Device MTU is not route MTU

The module's standard Cilium Helm `MTU: 1450` is the base device MTU, not a
promise that encrypted pod traffic can carry 1450-byte IP packets. Cilium
calculates workload device and route MTUs separately. For a 1450 base,
WireGuard plus IPv4 tunneling yields a 1320 route MTU; WireGuard without
tunneling yields 1370. A pod veth showing 1450 alone is not evidence that
the route MTU is wrong. This arithmetic was checked against the 1.17.18 and
1.19.3 implementations, not a live cluster. Check the calculation and effective routes for your
deployed Cilium version rather than treating these numbers as universal.

Do not subtract these overheads again from the module default: Cilium will
subtract them from the reduced base too. Nor is automatic detection always
equivalent: the original [MTU fix, PR #847](https://github.com/mysticaltech/terraform-hcloud-kube-hetzner/pull/847)
pinned the private-network base because detection selected the public
interface. Explicit Tailscale, public-overlay and Robot MTU paths have
different budgets and must be assessed separately.

For a suspected blackhole, collect the actual merged Helm values and Cilium
version, device MTUs, and `ip route get <destination>` both on the source
node and inside the affected pod. Compare ordinary pod-to-pod traffic with
host-to-pod and any nested bridge/network namespace. Check route MTUs and
capture ICMP fragmentation-needed/packet-too-big messages privately at both
ends. Reducing the Helm MTU may mitigate one path but does not establish why
the original path failed. Recheck existing and newly created pods separately.

Upstream implementation references:
- [Cilium 1.17.18 device and route MTU calculation](https://github.com/cilium/cilium/blob/v1.17.18/pkg/mtu/mtu.go)
- [Cilium 1.19.3 device and route MTU calculation](https://github.com/cilium/cilium/blob/v1.19.3/pkg/mtu/mtu.go)
- [Cilium CNI route setup](https://github.com/cilium/cilium/blob/v1.17.18/plugins/cilium-cni/cmd/cmd.go)

## Use the smallest underlay

The base MTU must fit the smallest node-to-node underlay used by the cluster,
including nodes joined outside Terraform. Hetzner's [vSwitch guidance](https://docs.hetzner.com/robot/dedicated-server/network/vswitch/)
limits the VLAN interface MTU to 1400. A manually joined Robot node can therefore
need a smaller Cilium base even when Robot CCM is disabled. The module cannot
discover that node or its path MTU from your Terraform inputs.

If the smallest underlay is confirmed to be 1400, set the base through the
existing values merge (inside your module block):

```hcl
cilium_merge_values = <<-EOT
  MTU: 1400
EOT
```

This is an explicit cluster-wide override, not a new default. Keep any other
merge values you already use. Do not use 1400 blindly for Tailscale, public
overlay or paths with additional encapsulation; measure their own budgets.
For Cilium 1.17.18/1.19.3 with WireGuard and IPv4 tunneling, a 1400 base yields a 1270
route MTU, not 1400. Do not subtract tunnel/encryption overhead a second time.

Inspect the effective Helm values and Cilium configuration after the change.
Existing pod interfaces and routes can retain their old MTU: recreate workloads
gradually using their normal rollout/disruption controls, then check both old
and newly created pods. A successful Helm update alone is not convergence proof.

On every participating node, collect fragmentation/reassembly counters before
and after the same bounded cross-node workload:

```sh
nstat -az | grep -E 'Ip(Frag|Reasm)'
```

Compare counter deltas, not lifetime totals. If they rise, use a short private
capture on the relevant underlay interface to identify the fragmented flow;
unrelated traffic can increment these counters too. Check both directions across
Cloud and Robot nodes, the actual pod route MTU, and tests within that MTU.
`ping: sendmsg: Message too large` with DF set is a local route-MTU rejection,
not proof that a packet was sent and blackholed. The reporter's corrected
[hybrid-cluster measurements](https://github.com/mysticaltech/terraform-hcloud-kube-hetzner/issues/2286#issuecomment-5617941361)
illustrate this distinction and the need to replace old pod interfaces.

## K3s agents and kube-proxy

K3s v1.33.13+k3s2 agents read the server's `DisableKubeProxy` setting during
startup. The absence of `--disable-kube-proxy` in `k3s agent --help` does not
make replacement unsupported on agent nodes. Do not pass that server-only
flag to an agent.

When an existing agent still holds port 10256 after a mode change, verify
that all servers have loaded the intended configuration, whether config
restarts were deferred to Kured, and when each agent last started. The module
does not automatically restart static agents merely because
`enable_kube_proxy` changed. Disabling Cilium's health listener only hides the
port collision; it does not establish that kube-proxy has stopped. A fresh
cluster and an in-place transition need separate acceptance tests.

Upstream implementation references:
- [K3s kube-proxy startup](https://github.com/k3s-io/k3s/blob/v1.33.13%2Bk3s2/pkg/daemons/agent/agent.go)
- [Server-provided kube-proxy configuration](https://github.com/k3s-io/k3s/blob/v1.33.13%2Bk3s2/pkg/agent/config/config.go)

For acceptance, verify every control plane and agent, including Robot and
autoscaler nodes where present: kube-proxy process/listener ownership, Cilium
health, NodePort/ClusterIP reachability, masquerading and connectivity.
HAProxy PROXY-protocol trust failures are a separate investigation; a TLS
failure alone does not identify the Cilium datapath as its cause.
