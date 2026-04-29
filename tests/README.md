# Hetzner Test Presets

These `.tfvars` files are used by `.github/workflows/hetzner-test.yaml` to run a
matrix of real deployment tests with both Terraform and OpenTofu.

- `default.tfvars`: baseline defaults
- `nginx_ingress.tfvars`: deploy with NGINX ingress controller
- `rke2.tfvars`: deploy with RKE2 distribution

For the large Tailscale node-transport reference examples, run:

```bash
uv run scripts/validate_tailscale_large_scale_examples.py
```

That preflight validates the documented +100-node and 10,000-total-node
topology math without creating real 10k infrastructure.

For v3 topology chooser, Cilium Gateway API, embedded registry mirror, endpoint
outputs, and skill/doc sync, run:

```bash
uv run scripts/validate_v3_final_polish_examples.py
```

For the v3 blast-radius disposable plan matrix, run:

```bash
uv run scripts/smoke_v3_plan_matrix.py
```

This never applies, but it needs a real HCloud token so successful plans can
read provider data sources. It covers default k3s+Cilium, Cilium Gateway API
valid/invalid cases, public join endpoint IPv6 and no-public-host guards,
embedded registry mirror valid/invalid cases, k3s/RKE2 Tailscale multinetwork
registry constraints, and the single-Gateway-controller guard. It retries
transient provider-download failures during `terraform init` and transient plan
timeouts. Set
`SMOKE_HCLOUD_EXTERNAL_NETWORK_ID` if the account has no existing Network for
the external-network Tailscale plan smoke.
