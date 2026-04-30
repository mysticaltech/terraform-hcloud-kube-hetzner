---
name: test-changes
description: Use after making changes to run Terraform/OpenTofu formatting, validation, and plans against the test environment
---

# Test Terraform Changes

## Overview

Run the standard validation suite for Terraform/OpenTofu changes against the test environment.

## Usage

```
/test-changes
```

## Test Environment

- **Module code:** `/Volumes/MysticalTech/Code/kube-hetzner`
- **Test cluster:** `/Users/karim/Code/kube-test`

## Workflow

```dot
digraph test_flow {
    rankdir=TB;
    node [shape=box];

    fmt [label="1. terraform fmt -recursive"];
    no_null [label="2. forbid null_resource"];
    init_local [label="3. terraform init -backend=false"];
    validate [label="4. terraform validate"];
    tofu [label="5. OpenTofu temp-copy validate"];
    example [label="6. kube.tf.example parse check"];
    init [label="7. terraform init -upgrade"];
    plan [label="8. terraform plan"];
    review [label="9. Review plan output"];

    fmt -> no_null;
    no_null -> init_local;
    init_local -> validate;
    validate -> tofu;
    tofu -> example;
    example -> init;
    init -> plan;
    plan -> review;
}
```

## Step 1: Format Check

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
terraform fmt -recursive
```

**Must pass before proceeding.**

## Step 2: Forbid null_resource Usage

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
if rg -n 'resource[[:space:]]+"null_resource"|provider[[:space:]]+"null"|hashicorp/null' -g '*.tf' -g '*.tf.json' .; then
  echo "Use terraform_data instead of null_resource/hashicorp/null. Moved blocks from old null_resource addresses are allowed for state migration."
  exit 1
fi
```

**Must pass before proceeding.** Any operational placeholder resource should use
the built-in `terraform_data` resource. Keep `moved` blocks that reference old
`null_resource` addresses because they preserve upgrade/state migration safety.

## Step 3: Initialize Local Providers

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
terraform init -backend=false
```

**Must pass before proceeding.**

## Step 4: Validate Module

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
terraform validate -no-color
```

**Must pass before proceeding.**

## Step 5: Validate OpenTofu Compatibility

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
tmpdir="$(mktemp -d)"
rsync -a --exclude .git --exclude .terraform --exclude .terraform-tofu ./ "$tmpdir"/
(cd "$tmpdir" && tofu init -backend=false -input=false && tofu validate -no-color)
rm -rf "$tmpdir"
```

**Must pass before proceeding.** OpenTofu is officially supported and should
catch the same module-contract validation errors as Terraform during plan. Use
a temporary copy when validating both CLIs so OpenTofu cannot rewrite the
ignored `.terraform.lock.hcl` or local plugin cache in the main Terraform
checkout. Cross-variable contract failures are enforced by
`terraform_data.validation_contract`, so invalid-combination tests should assert
`terraform plan`, not only `terraform validate`.

## Step 6: Validate `kube.tf.example` Parseability

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
tmpdir="$(mktemp -d)"
cp kube.tf.example "$tmpdir/main.tf"
perl -0pi -e 's#source = "kube-hetzner/kube-hetzner/hcloud"#source = "/Volumes/MysticalTech/Code/kube-hetzner"#' "$tmpdir/main.tf"
(cd "$tmpdir" && terraform fmt -check main.tf && terraform init -backend=false && terraform validate)
```

**Must pass before proceeding.**

## Step 6.5: Validate Large Tailscale Examples

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
uv run scripts/validate_tailscale_large_scale_examples.py
```

**Must pass when Tailscale node transport, multinetwork, autoscaler, placement
group, or example docs change.** This checks the +100-node and
10,000-total-node reference topology math without creating real 10k
infrastructure.

The v3 smoke matrix also covers public join endpoint family handling: IPv6-only
control-plane public joins must remain valid, and public joins without a real
public API host must fail before deployment. The helper retries transient
provider-download failures during `terraform init`.

## Step 6.6: Validate v3 Final-Polish Surfaces

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
uv run scripts/validate_v3_final_polish_examples.py
```

**Must pass when topology docs, `cilium_gateway_api_enabled`,
`embedded_registry_mirror`, endpoint outputs, Cloudflare/Tailscale examples, or
skills change.**
This keeps the v3 topology chooser, Gateway API example, registry mirror
snippets, Cloudflare external-access boundary, and validation gates in sync.

## Step 6.7: Run v3 Blast-Radius Plan Matrix

```bash
cd /Volumes/MysticalTech/Code/kube-hetzner
uv run scripts/smoke_v3_plan_matrix.py
```

**Must pass when Cilium Gateway API, embedded registry mirror, Tailscale node
transport, multinetwork validation, or endpoint-mode logic changes.** This
creates disposable Terraform roots and never applies, but it needs a real HCloud
token so successful plans can read provider data sources. It covers k3s and RKE2
Tailscale registry paths plus the single-Gateway-controller guard. Set
`SMOKE_HCLOUD_EXTERNAL_NETWORK_ID` if no existing HCloud Network is available
for the external-network Tailscale plan smoke.

## Step 7: Initialize Test Environment

```bash
cd /Users/karim/Code/kube-test
terraform init -upgrade
```

This picks up changes from the local module.

## Step 8: Plan Against Test Cluster

```bash
cd /Users/karim/Code/kube-test
terraform plan
```

### What to Look For

#### Good Signs
- Only expected resources change
- No unexpected additions/deletions
- Changes match your intended modifications

#### Red Flags (STOP!)

| Output | Meaning | Action |
|--------|---------|--------|
| `will be destroyed` | Resource recreation | **STOP** - Breaking change |
| `must be replaced` | Resource recreation | **STOP** - Breaking change |
| `forces replacement` | Resource recreation | **STOP** - Breaking change |
| Unexpected changes | Side effects | Investigate before proceeding |

### Breaking Change = MAJOR Release

If `terraform plan` shows ANY resource destruction on existing infrastructure:
1. **STOP** - This is NOT backward compatible
2. The change requires a MAJOR version bump
3. Migration guide is required
4. Consider alternative approaches first

## Step 9: Review Plan Output

### Checklist

- [ ] `terraform fmt -recursive` passes
- [ ] no live `null_resource`/`hashicorp/null` usage exists
- [ ] `terraform init -backend=false` passes
- [ ] `terraform validate` passes
- [ ] OpenTofu temp-copy validation passes
- [ ] `kube.tf.example` parses against the local checkout
- [ ] `uv run scripts/validate_tailscale_large_scale_examples.py` passes when large-scale/Tailscale/networking examples are touched
- [ ] `uv run scripts/validate_v3_final_polish_examples.py` passes when Gateway API/registry/topology/Cloudflare boundary docs are touched
- [ ] `uv run scripts/smoke_v3_plan_matrix.py` passes when Gateway API/registry/Tailscale plan behavior is touched
- [ ] Tailscale node-transport static cases pass/fail as expected when variables/networking are touched
- [ ] `terraform plan` shows expected changes only
- [ ] No resource destruction
- [ ] No unexpected side effects
- [ ] Changes are backward compatible

## Quick Reference

```bash
# Full test sequence
cd /Volumes/MysticalTech/Code/kube-hetzner && \
terraform fmt -recursive && \
if rg -n 'resource[[:space:]]+"null_resource"|provider[[:space:]]+"null"|hashicorp/null' -g '*.tf' -g '*.tf.json' .; then exit 1; fi && \
terraform init -backend=false && \
terraform validate && \
tmpdir="$(mktemp -d)" && \
rsync -a --exclude .git --exclude .terraform --exclude .terraform-tofu ./ "$tmpdir"/ && \
(cd "$tmpdir" && tofu init -backend=false && tofu validate) && \
rm -rf "$tmpdir" && \
tmpdir="$(mktemp -d)" && cp kube.tf.example "$tmpdir/main.tf" && \
perl -0pi -e 's#source = "kube-hetzner/kube-hetzner/hcloud"#source = "/Volumes/MysticalTech/Code/kube-hetzner"#' "$tmpdir/main.tf" && \
(cd "$tmpdir" && terraform fmt -check main.tf && terraform init -backend=false && terraform validate) && \
rm -rf "$tmpdir" && \
uv run scripts/validate_tailscale_large_scale_examples.py && \
uv run scripts/validate_v3_final_polish_examples.py && \
uv run scripts/smoke_v3_plan_matrix.py && \
cd /Users/karim/Code/kube-test && \
terraform init -upgrade && \
terraform plan
```

## Apply (Optional)

Only if plan looks correct and you want to test on actual infrastructure:

```bash
cd /Users/karim/Code/kube-test
terraform apply
```

**Caution:** This modifies real infrastructure. Only do this for thorough testing.

## Common Issues

### "Provider version constraints"
```bash
terraform init -upgrade
```

### "Module source has changed"
```bash
terraform init -upgrade
```

### "State lock"
Someone else may be running terraform. Wait or:
```bash
terraform force-unlock <lock-id>
```

### Validation errors
Check the error message - usually points to:
- Missing required variable
- Type mismatch
- Invalid reference

## AI-Assisted Review

For complex changes, get AI review:

```bash
# Codex for correctness
codex exec -m gpt-5.5 -s read-only -c model_reasoning_effort="xhigh" \
  "Review these terraform changes for issues: $(git diff)"

# Gemini for broad impact
gemini --model gemini-3.1-pro-preview -p \
  "@locals.tf @variables.tf Analyze impact of these changes: $(git diff)"
```
