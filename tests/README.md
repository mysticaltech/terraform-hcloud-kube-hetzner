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

For native fake-input autoscaler snapshot plans, use the disposable-copy runner:

```bash
uv run scripts/tests/test_autoscaler_snapshots.py --cli terraform
uv run scripts/tests/test_autoscaler_snapshots.py --cli tofu
```

The runner pins HCloud **1.62.0 only in a disposable test copy** and executes all
21 original plan-only scenarios, including default lookup-based numeric IDs,
latest OS/distro/architecture selectors, dormant pools, no-match and pin/label
negative contracts. It does not narrow the module's runtime provider range.

A separate HCloud **1.70.0** copy executes 13 supported full-module scenarios:
the default numeric-ID assertions with an explicit production input pin, plus
12 latest, architecture/distro, dormant/inactive pool, Leap and MicroOS pin,
version and backup contracts. It retains their assertions. The eight MicroOS
collection scenarios still execute in the complete 1.62 matrix; they are not
counted as current-provider passes. Terraform 1.15 cannot override the 1.70
`hcloud_images.images` nested-type collection ([upstream #38369](https://github.com/hashicorp/terraform/issues/38369)).
The same conservative coverage partition is used for OpenTofu.
Only in this current-provider copy, the ineffective optional-only ID is removed
from the image mock defaults and backup override: OpenTofu rejects such
non-computed overrides, while Terraform leaves the ID null.

Two additional 1.70 plans use the actual production Leap and MicroOS query blocks
copied verbatim to check status/architecture/selector shapes and the optional-ID
mock boundary. Schema checks verify both provider regimes. This is not a claim
that the unmodified 21-case lookup matrix passes under 1.70: its
`hcloud_image.id` is optional-only, so mocks/overrides cannot supply an
unconfigured API-returned ID. The real provider Read populates the ID from the
API; these tests never call it or model API filtering/returned image ordering.
The availability assertion uses exact cardinality and membership, independent of
the provider's list (1.62) or set (1.70) representation.

Initialization may download provider packages, but plans mock all external
providers and require no HCloud credential. The runner removes ambient cloud and
Terraform variable/credential environment settings, copies tracked working files
only, and leaves the checkout and its lockfile untouched. Use `--output-dir` with
a new directory to retain versions, schemas and JSON plan-test receipts, or
`--cli-config` for a test-only filesystem mirror. Missing packages or changed
schemas fail explicitly; no test failures/skips are counted as passes.

These checks do not establish live scale-up, real API filtering, image boot,
existing-state upgrades or replacement-policy acceptance. The
server inventory/type mocks use generated empty lists to avoid Terraform's
upstream nested-type override bug (#38369); size-aware behavior is not under test.

For offline Cilium migration-warning regressions and the k3s/RKE2,
kube-proxy, routing and WireGuard render matrix, run:

```bash
uv run scripts/tests/test_cilium_intake.py
```

These checks use provider-free Terraform renders. They do not certify live
MTU behavior or an in-place kube-proxy ownership transition.

For HAProxy transport-peer rendering and native TLS/PROXY protocol regressions:

```bash
uv run scripts/tests/test_haproxy_proxy_protocol.py
```

This requires native `haproxy` and `openssl`, plus `terraform`. It uses
only ephemeral IPv4/IPv6 loopback listeners and generated test certificates,
not containers or Kubernetes. It checks that adding an exact trusted peer
accepts PROXY-prefixed TLS but rejects ordinary TLS from the same source.

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
