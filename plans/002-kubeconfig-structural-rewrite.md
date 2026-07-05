# Plan 002: Kubeconfig is rewritten structurally, never via global string replace

> **Executor instructions**: Follow step by step; verify each step; STOP conditions are binding. Update `plans/README.md` when done.
>
> **Drift check (run first)**: `git diff --stat e506cc4..HEAD -- kubeconfig.tf output.tf` — mismatch with excerpts = STOP.

## Status
- **Priority**: P1 | **Effort**: S | **Risk**: LOW | **Depends on**: none | **Category**: bug
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
`kubeconfig.tf` renames the cluster/context/user by running a **global** `replace(kubeconfig_text, "default", var.cluster_name)`. Any other occurrence of the substring `default` — inside base64 certificate blobs (the base64 alphabet can spell it), a future field, a comment — gets mutated too, corrupting the kubeconfig or its embedded credentials in a way that is miserable to debug. The rename must operate on the parsed structure.

## Current state
`kubeconfig.tf:51-62` today:
```hcl
  kubeconfig_external = replace(
    replace(
      ssh_sensitive_resource.kubeconfig.result,
      "https://127.0.0.1:${var.kubernetes_api_port}",
      local.kubeconfig_server
    ),
    "default",
    var.cluster_name
  )
  kubeconfig_parsed = yamldecode(local.kubeconfig_external)
  kubeconfig_data = {
    host                   = local.kubeconfig_parsed["clusters"][0]["cluster"]["server"]
```
`kubeconfig_data` continues extracting `client_certificate`/`client_key`/`cluster_ca_certificate` via `base64decode`. `output.tf` (~174) exposes `kubeconfig` (yaml text) and structured fields. k3s/rke2 emit a kubeconfig whose cluster, context, user are all literally named `default` and server is `https://127.0.0.1:<port>`.

## Commands you will need
| Purpose | Command | Expected |
|---|---|---|
| Fmt | `terraform fmt -check -recursive` | exit 0 |
| Validate | `rm -rf .terraform .terraform.lock.hcl && terraform init -backend=false -input=false && terraform validate` | Success |
| Console check | provider-free scratch dir + `terraform console` (see Step 2) | expected JSON |

## Scope
**In scope**: `kubeconfig.tf`, `CHANGELOG.md` (v3 Unreleased, 🐛 Bug Fixes, one line).
**Out of scope**: `output.tf` shapes (outputs must keep byte-identical STRUCTURE — same fields, same meaning), `ssh_sensitive_resource.kubeconfig` retrieval, anything else.

## Steps
### Step 1: Structural rewrite
Replace the global-replace pipeline with: `yamldecode` the RAW result first; then build the rewritten object by (a) setting `clusters[0].cluster.server = local.kubeconfig_server`, (b) renaming `clusters[0].name`, `users[0].name`, `contexts[0].name`, `contexts[0].context.cluster`, `contexts[0].context.user`, and `current-context` from `default` to `var.cluster_name` ONLY where the existing value equals `"default"` (leave non-default names untouched); then `kubeconfig_external = yamlencode(that_object)`. Keep `kubeconfig_parsed`/`kubeconfig_data` reading from the new object (drop the redundant re-decode if trivially safe). Preserve sensitivity: the source is a sensitive resource — do not add `nonsensitive()`.
**Verify**: validate command → Success.

### Step 2: Prove equivalence + the fixed bug
In a scratch dir OUTSIDE the repo, create a provider-free `main.tf` with a local `sample` holding a realistic k3s kubeconfig YAML string (cluster/context/user "default", server `https://127.0.0.1:6443`, and a fake base64 field CONTAINING the substring `ZGVmYXVsdA` plus literal `defaultXYZ` inside the cert data). Reimplement the new transformation expression there with `cluster_name = "mycluster"`. `terraform console`:
- names/current-context become `mycluster`; server rewritten;
- the cert-data blob is byte-identical to input (grep your console output for `defaultXYZ` still present).
**Verify**: both assertions hold; paste the console evidence in your report.

## Test plan
Console proof above is the test (this repo has no unit harness for .tf yet; if plans/001 landed first, ALSO add a harness entry asserting the kubeconfig transformation — check `scripts/render_harness.py` existence and extend it with this case).

## Done criteria
- [ ] `grep -n '"default"' kubeconfig.tf` shows only equality-guarded renames (no global replace of `"default"`)
- [ ] fmt + validate pass
- [ ] Console equivalence evidence in report
- [ ] Only in-scope files modified; plans/README.md updated

## STOP conditions
- The raw kubeconfig from `ssh_sensitive_resource` turns out NOT to be plain YAML at plan time (unknown/sensitive interplay breaks `yamldecode` ordering) → STOP, report the exact error; do not wrap in try().
- Output shapes would need to change → STOP.

## Maintenance note
Any future kubeconfig field additions come through the structured object; never reintroduce string surgery.
