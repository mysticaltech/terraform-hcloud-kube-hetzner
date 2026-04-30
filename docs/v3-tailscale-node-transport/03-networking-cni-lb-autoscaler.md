# M4-M7 Networking, CNI, LB, CCM, And Autoscaler

## Decisions

- Tailscale transport means no control-plane fanout to every external agent
  Network.
- Nodes can advertise their own Hetzner private `/32` routes into Tailscale and
  accept routes from other node tags. This may be disabled for single-network
  clusters, but is required when external `network_id` nodepools are used.
- Tailscale subnet-route SNAT is disabled so CNI traffic keeps the real
  Hetzner node source IP.
- Flannel keeps using the Hetzner private interface; Tailscale is the routed
  underlay between Hetzner Network islands, not the Flannel interface.
- Cilium remains experimental in this mode until cross-network datapath testing
  proves the exact MTU/tunnel behavior.
- Hetzner CCM route reconciliation is disabled in Tailscale mode.
- Hetzner Load Balancers never target Tailnet IPs. Public LBs require eligible
  public IPv4 node targets; private LBs are same-Network only.
- Autoscaler cloud-init derives a unique Tailscale hostname from the actual
  HCloud/server hostname before `tailscale up`.

## Write Set

- `locals.tf`
- `variables.tf`
- `validation-locals.tf`
- `init.tf`
- `control_planes.tf`
- `autoscaler-agents.tf`
- `templates/autoscaler.yaml.tpl`
- `templates/autoscaler-cloudinit.yaml.tpl`
- `templates/hcloud-ccm-helm.yaml.tpl`

## Tests

- Static render per-network autoscaler deployments.
- Static validate attachment counts.
- Static validate public/private LB target eligibility.
- Live autoscaler scale-up/scale-down with Tailnet join.
