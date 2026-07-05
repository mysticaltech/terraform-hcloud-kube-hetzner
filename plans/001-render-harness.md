# Plan 001: A hermetic render-test harness + negative contract tests exist and run in CI

> **Executor instructions**: Follow step by step. Run every verification command and confirm the expected result before the next step. On any STOP condition, stop and report. Update your row in `plans/README.md` when done.
>
> **Drift check (run first)**: `git diff --stat e506cc4..HEAD -- locals.tf validation-contract.tf scripts/ tests/ .github/workflows/lint_pr.yaml` — if in-scope files changed, compare "Current state" excerpts to live code; mismatch = STOP.

## Status
- **Priority**: P1 | **Effort**: M | **Risk**: MED | **Depends on**: none | **Category**: tests
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
This module's failure mode is proven: `terraform fmt` + `validate` + 3 live CI presets all pass while rendered artifacts are broken. A single live-gate cycle found 12 such defects (mis-indented cilium Helm values, `%{~}` strip-markers splicing LB annotations out of nginx/traefik/haproxy values, unterminated shell heredocs bricking the NAT router's sshd, dead `==` comparisons on optional() lists). Each cost a live cluster to discover. A hermetic harness that renders the critical templates with representative inputs and asserts structure — plus negative tests proving the validation-contract preconditions actually fire — converts this whole defect class from "live-apply discovery" to "CI failure in seconds".

## Current state
- `validation-contract.tf` — all cross-object rules as `terraform_data` preconditions. Two recent ones to cover: the helm-values YAML contract (`helm_values_yaml_contract`, requires every rendered `*_values` doc to `yamldecode`) and the LB-adoption contract (`ingress LB annotation` preconditions near line ~1122+, requiring `load-balancer.hetzner.cloud/name` or `/id` at the chart's annotation path when a Hetzner LB ingress is selected).
- `locals.tf` (~3200 lines) — Helm values heredocs (`nginx_values_default` ~2216, `traefik_values_default` ~2366, `haproxy_values_default` ~2317, cilium ~1990-2060), provisioner shell scripts, cloud-init fragments.
- `templates/*.tpl` — cloud-init (host, autoscaler, NAT router), addon manifests, `nat-router-reconcile.sh.tpl` (base64-shipped shell).
- `scripts/smoke_v3_plan_matrix.py` — plan-only smoke, requires HCloud token, hardcodes `/Users/karim/.ssh` paths (lines ~74, ~118); NOT hermetic.
- `scripts/validate_v3_final_polish_examples.py` — string-presence checks only.
- `.github/workflows/lint_pr.yaml` — fmt/validate matrix (TF 1.10.5/1.14.9/1.15.0 + tofu), tfsec, null-provider ban. Add the harness here.
- Proven verification technique from the live gate (reuse it): render heredocs standalone via a provider-free scratch module + `terraform console` + `yamldecode`; and for full-module negative tests, `terraform plan` against a fixtures root with an intentionally-broken input must FAIL with the contract's error string.
- Convention: cross-variable checks live in validation-contract.tf, NOT variable validations (Terraform 1.11 init-time constraint). Python scripts in `scripts/` are stdlib-only, run with `python3`.

## Commands you will need
| Purpose | Command | Expected |
|---|---|---|
| Fmt | `terraform fmt -check -recursive` | exit 0 |
| Validate | `rm -rf .terraform .terraform.lock.hcl && terraform init -backend=false -input=false && terraform validate` | "Success!" |
| Harness (you create) | `python3 scripts/render_harness.py` | exit 0, per-check PASS lines |
| Negative tests (you create) | `python3 scripts/contract_negative_tests.py` | exit 0, each case reports "failed as expected" |

## Scope
**In scope**: `scripts/render_harness.py` (create), `scripts/contract_negative_tests.py` (create), `tests/render-fixtures/` (create), `.github/workflows/lint_pr.yaml` (add one job), `tests/README.md` (document), `CHANGELOG.md` (one line under v3 Unreleased / 🔧 Changes).
**Out of scope**: any change to `locals.tf`, `validation-contract.tf`, or any `.tf`/`.tpl` under test — the harness OBSERVES, it must not "fix" what it finds (report instead); `.github/workflows/hetzner-test.yaml`; `docs/terraform.md` (generated).

## Steps
### Step 1: Build the render harness
Create `scripts/render_harness.py` (stdlib only). It must, in a temp dir (`tempfile.mkdtemp`, never the repo):
1. Extract named heredoc templates from `locals.tf` by delimiting marker comments — do NOT regex-parse HCL; instead generate a provider-free scratch `.tf` that `templatestring`/re-declares the heredoc content with representative variable stubs. Practical approach (proven in this repo): copy each `*_values_default` heredoc body into the scratch module as a `templatefile`-style local with a fixed map of representative inputs (two input sets: defaults, and `using_klipper_lb=false` + each ingress selected), run `terraform console` to evaluate, `yamldecode` the result in Python (`json` via `terraform console` emitting `jsonencode(yamldecode(local.x))`).
2. Assert STRUCTURE, not snapshots: for nginx — `controller.service.annotations["load-balancer.hetzner.cloud/name"]` non-empty; traefik — `service.annotations[...]`; haproxy — `controller.service.annotations[...]`; cilium — `routingMode` present at document root and `k8sServicePort` present; every doc yamldecodes.
3. Shell syntax checks: `bash -n` every rendered `.sh.tpl` under `templates/` (render with representative vars via the same scratch-console technique; `templates/nat-router-reconcile.sh.tpl` is the exemplar) and every heredoc-embedded script marked in locals if extractable — if a script cannot be rendered standalone, list it as SKIPPED (don't fail).
4. Cloud-init YAML checks: render `modules/host/templates/cloudinit.yaml.tpl` and `templates/autoscaler-cloudinit.yaml.tpl` NAT `templates/nat-router-cloudinit.yaml.tpl` with representative inputs and `yaml`-parse them (stdlib has no yaml — use `terraform console` + `yamldecode` + `jsonencode` like above).
**Verify**: `python3 scripts/render_harness.py` → exit 0, ≥8 PASS lines, 0 FAIL.

### Step 2: Negative contract tests
Create `tests/render-fixtures/` containing a minimal root module that sources the repo module (`source = "../.."`) with a valid baseline tfvars, plus per-case override files that MUST fail plan:
- case `bad-ingress-annotations`: use a `nginx_merge_values`/`*_merge_values` override that removes the LB annotations → expect plan failure containing "annotation".
- case `bad-yaml-values`: a merge-values override injecting structurally-invalid YAML → expect the yamldecode contract error.
- case `rke2-overreserved`: `kubernetes_distribution="rke2"` + control-plane `kubelet_args` reserving >50% of a cx23 → expect the reservation guard error.
- case `nat-without-cp-lb`: `nat_router` set without `enable_control_plane_load_balancer` → expect the existing NAT/LB contract error (exact string from validation-contract.tf ~394).
Create `scripts/contract_negative_tests.py`: for each case run `terraform plan` (init once with `-backend=false`; NO cloud credentials must be needed — if a case requires a real token to reach the failing precondition, mark SKIP with reason instead of faking). Assert non-zero exit AND the expected error substring.
**Verify**: `python3 scripts/contract_negative_tests.py` → each case "failed as expected" or explicit SKIP(reason); overall exit 0.

### Step 3: Wire into CI + docs
Add a `render-harness` job to `.github/workflows/lint_pr.yaml` (ubuntu-latest, hashicorp/setup-terraform, run both scripts). Document both scripts in `tests/README.md` (what they cover, how to add a case). Changelog line.
**Verify**: `ruby -ryaml -e 'YAML.load_file(".github/workflows/lint_pr.yaml")' || python3 -c "import yaml"...` — if neither available: `grep -c 'render-harness' .github/workflows/lint_pr.yaml` → ≥2. Then full fmt+validate commands → pass.

## Test plan
The scripts ARE the tests. Additionally prove the harness catches the historical bugs: temporarily (in the temp dir only, never the repo) re-introduce the cilium `  routingMode` two-space indent into the scratch copy and confirm the harness FAILS on it; state this check's result in your report.

## Done criteria
- [ ] `python3 scripts/render_harness.py` exit 0 with 0 FAIL
- [ ] `python3 scripts/contract_negative_tests.py` exit 0, ≥3 executed (non-SKIP) cases
- [ ] fmt + validate commands pass
- [ ] `git status` shows only in-scope files
- [ ] plans/README.md row updated

## STOP conditions
- `terraform console` cannot evaluate provider-free scratch expressions in your sandbox → STOP, report the exact error.
- A negative case FAILS TO FAIL (plan succeeds) → that is a real contract gap: STOP and report it as a finding, do not weaken the case.
- Any assertion requires modifying module code to pass → STOP (out of scope).

## Maintenance note
Every future `*_values_default` or template gains a harness entry; the negative suite grows one case per new validation-contract precondition. Reviewers: reject PRs adding contracts without cases.
