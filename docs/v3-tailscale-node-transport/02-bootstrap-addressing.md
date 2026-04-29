# M2-M3 Bootstrap, Addressing, And Kubeconfig

## Decisions

- Install Tailscale from official static binaries under `/usr/local` and manage
  `tailscaled` with a kube-hetzner-owned systemd unit. This avoids transactional
  package-manager ambiguity on Leap Micro and MicroOS.
- Bring Tailscale up before Kubernetes starts.
- Keep Kubernetes node IPs on Hetzner private addresses. Tailscale transports
  those private CIDRs across Hetzner Network islands; it does not become the
  Kubernetes node address.
- Keep control-plane etcd join traffic on the primary Hetzner Network for the
  first production implementation.
- Use the private control-plane endpoint for agents and autoscaler joins in
  Tailscale mode; the endpoint is reachable through approved Tailnet subnet
  routes.
- Use separate k3s API and RKE2 supervisor endpoint locals.

## Write Set

- `locals.tf`
- `control_planes.tf`
- `agents.tf`
- `autoscaler-agents.tf`
- `modules/host/main.tf`
- `modules/host/variables.tf`
- `modules/host/out.tf`
- `templates/autoscaler-cloudinit.yaml.tpl`
- `kubeconfig.tf`

## Tests

- Static render default config unchanged.
- Static render Tailscale remote-exec static nodes.
- Static render Tailscale cloud-init autoscaler nodes.
- Live k3s/Flannel Tailscale smoke before claiming support.
