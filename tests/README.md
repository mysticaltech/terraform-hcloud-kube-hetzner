# Hetzner Test Presets

These `.tfvars` files, together with `ci-kube.tf`, define reproducible real
deployment test scenarios (Terraform and OpenTofu). Run them manually from a
scratch directory against a test Hetzner project when validating changes;
tear down with `scripts/destroy.sh`.

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

## Render Harness

For hermetic rendered-template checks, run:

```bash
uv run scripts/render_harness.py
```

This uses a provider-free Terraform scratch module to render the current
`*_values_default` heredocs, critical cloud-init templates, `templates/*.sh.tpl`,
and extractable shell heredocs from `locals.tf`. It asserts rendered Helm values
yamldecode, ingress controller values keep Hetzner Load Balancer adoption
annotations at the chart-specific Service annotation path, Cilium values keep
`routingMode` and `k8sServicePort` at the document root, cloud-init templates
decode as YAML, rendered shell passes `bash -n`, and static-agent private IPv4
allocation preserves the v2 per-nodepool formula while remaining unique across
shared-subnet nodepools.

When adding a new `*_values_default` heredoc or high-risk rendered template, add
it to `scripts/render_harness.py` with a structure assertion instead of a large
snapshot. Prefer assertions for paths and invariants that have caused live-gate
failures.

For negative validation-contract checks, run:

```bash
python3 scripts/contract_negative_tests.py
```

The fixture root in `tests/render-fixtures/` sources this module with a compact
baseline and per-case var-file overlays. Each case must either fail `terraform
plan` with the expected contract substring or print an explicit `SKIP(reason)`
when the local environment cannot load provider-backed plans. Add one fixture
case for each new validation-contract precondition, and keep expected substrings
specific enough that a different validation failure cannot pass accidentally.
