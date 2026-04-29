# Cilium Gateway API Example

This example enables Cilium's native Gateway API controller:

```hcl
cni_plugin                 = "cilium"
enable_kube_proxy         = false
cilium_gateway_api_enabled = true
ingress_controller         = "none"
```

The module installs the standard Gateway API CRDs, enables
`gatewayAPI.enabled` in Cilium, and enables cert-manager Gateway API support.

## What It Deploys

- A small echo Deployment and Service.
- A Cilium `Gateway` using `gatewayClassName: cilium`.
- An `HTTPRoute` that routes traffic to the echo Service.
- A cert-manager ACME `ClusterIssuer` showing the Gateway HTTP-01 solver path.

Set `gateway_hostname` to a DNS name that you control. After the Hetzner Cloud
LoadBalancer is created for the Gateway, point DNS at that LoadBalancer address
before switching the issuer from Let's Encrypt staging to production.

## Caveats

- Cilium Gateway API requires kube-proxy replacement, so `enable_kube_proxy`
  must stay `false`.
- Cilium Gateway API is a Cilium feature, not the Traefik Gateway provider.
- Cilium creates a Kubernetes `Service` of type `LoadBalancer` for Gateways by
  default; Hetzner CCM then creates the external Load Balancer.
- IPv6 and proxy-protocol behavior depends on Cilium, Hetzner CCM, and the
  Gateway Service annotations you choose. Validate source-IP behavior before
  using proxy protocol or dual-stack ingress in production.
- Cert-manager HTTP-01 requires the HTTP listener to be reachable from the
  public internet during ACME validation.

## Validate Locally

From a temporary copy of this example, replace the module `source` with the
local repository path and run:

```bash
terraform init -backend=false
terraform validate
```
