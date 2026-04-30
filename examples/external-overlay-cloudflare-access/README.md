# Cloudflare Zero Trust Access/Tunnel Pattern for v3

This example documents the supported v3 boundary for Cloudflare:
Cloudflare Zero Trust is an external operator and application access layer, not
kube-hetzner's Kubernetes node transport.

Use `node_transport_mode = "tailscale"` when you want kube-hetzner to manage
secure node transport for single-network hardening or multinetwork scale-out.
Use Cloudflare Access/Tunnel when you want to protect the Kubernetes API, SSH,
Rancher, Grafana, or ingress hostnames through Cloudflare-managed policy.

## Goals

- Keep Cloudflare account resources, policies, DNS, tunnels, WARP enrollment,
  service tokens, and Access applications outside kube-hetzner.
- Let users put Cloudflare Access/Tunnel in front of operator or application
  entrypoints without adding Cloudflare provider requirements to the module.
- Avoid a Cloudflare Mesh/WARP node-transport support promise in v3.

## Boundary

kube-hetzner does not manage Cloudflare resources in v3:

- No Cloudflare Terraform provider is required by this module.
- No Cloudflare API token, tunnel token, or Access service token variable is
  added to the module.
- No `node_transport_mode = "cloudflare"` exists.
- Cloudflare Mesh/WARP is not a supported Kubernetes node transport.

This is intentional. Cloudflare Access/Tunnel is excellent for controlled
operator and application access, but using Cloudflare Mesh/WARP as the cluster
node transport would create a second full overlay stack to test and support.
Tailscale is the supported managed transport for that job.

## Recommended Patterns

### Kubernetes API Access

Use a Cloudflare Tunnel or WARP/private-route setup that you manage outside this
module, then access the API with a local helper such as:

```bash
cloudflared access tcp --hostname kube-api.example.com --url localhost:16443
```

Use a kubeconfig context that points at the local helper address, for example
`https://127.0.0.1:16443`.

Do not set `control_plane_endpoint` to a Cloudflare Access-protected hostname
unless every joining control-plane and agent node can reach and authenticate to
that hostname. `control_plane_endpoint` is a node join endpoint too, not only a
human kubeconfig URL.

### SSH Access

Use Cloudflare's SSH Access patterns outside this module. After the path is
proven, you may pass reachable hostnames or overlay addresses into:

```hcl
node_connection_overrides = {
  "k3s-control-plane" = "ssh-cp.example.com"
  "k3s-agent-0"       = "ssh-agent-0.example.com"
}
```

The map keys must match final kube-hetzner node names. Keep
`firewall_ssh_source` restricted or closed only after Terraform access through
Cloudflare is proven.

### Rancher, Grafana, And Ingress

For web applications, publish the application hostname through a Cloudflare
Tunnel or public Cloudflare-proxied DNS record that you own outside
kube-hetzner, then protect it with Cloudflare Access policy.

If Cloudflare terminates TLS before a kube-hetzner ingress controller, configure
trusted forwarded headers or proxy protocol for your chosen ingress controller.
Do not treat Cloudflare as a replacement for Kubernetes NetworkPolicy, RBAC, or
application authentication.

## Combining With Tailscale

The clean large-cluster shape is:

```hcl
node_transport_mode       = "tailscale"
firewall_kube_api_source  = null
firewall_ssh_source       = null

tailscale_node_transport = {
  bootstrap_mode  = "cloud_init"
  magicdns_domain = "example-tailnet.ts.net"
}
```

Then use Cloudflare Access/Tunnel only for selected human-facing endpoints.
Tailscale carries node transport; Cloudflare protects chosen entrypoints.

## Not Supported In v3

- Cloudflare Mesh/WARP as kube-hetzner-managed node transport.
- Cloudflare-managed Kubernetes node joins.
- Module-managed Cloudflare DNS records, tunnels, Access applications, or
  policies.
- Storing Cloudflare long-lived secrets in kube-hetzner variables.

Those can still be managed by an outer Terraform root, a separate Cloudflare
module, or manual Cloudflare dashboard/API workflows.

## Cloudflare References

- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
- [Cloudflare private networks with Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/private-net/)
- [Cloudflare Access policies](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/)
