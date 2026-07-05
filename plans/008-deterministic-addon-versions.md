# Plan 008: Default addon versions are deterministic per module commit

> **Executor instructions**: step-by-step; verify; STOP binding; update plans/README.md.
>
> **Drift check**: `git diff --stat e506cc4..HEAD -- data.tf variables.tf locals.tf` — mismatch on cited blocks = STOP.

## Status
- **Priority**: P2 | **Effort**: M | **Risk**: MED | **Depends on**: plans/001-render-harness.md (verification), plans/004-gate-disabled-addon-fetches.md (touches the same data sources — land 004 first) | **Category**: migration
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
With `hetzner_ccm_version`/`hetzner_csi_version`/`kured_version` unset, the module resolves GitHub `releases/latest` at plan time (`data.tf:1,16,31`), and `longhorn_version`/`csi_driver_smb_version`/`cert_manager_version`/`rancher_version` default to `"*"` (chart-controller floating). The same module commit therefore installs different software on different days: release evidence is non-replayable, upstream breaking releases reach users without any module diff, and CI green today proves nothing about tomorrow. A reviewed default-version matrix makes installs reproducible while keeping explicit floating as an opt-in.

## Current state
- `data.tf:1-45`: three `data "http"` blocks hitting `api.github.com/repos/<x>/releases/latest`, each `count`-gated on `var.<x>_version == null`.
- `locals.tf` consumes e.g. `csi_version = length(data.http.hetzner_csi_release) == 0 ? var.hetzner_csi_version : jsondecode(...).tag_name` (locals.tf ~21; same pattern for ccm/kured).
- `variables.tf`: `hetzner_ccm_version`/`hetzner_csi_version`/`kured_version` default `null`; `longhorn_version` (~2473) default `"*"`; also `csi_driver_smb_version` (may already be pinned by plan 005 — check), `cert_manager_version`, `rancher_version`, `sys/system_upgrade_controller_version` (already pinned — leave), `cluster_autoscaler_version` (check current default), `calico_version` (locals ~1957 uses latest when empty — in scope), traefik/nginx/haproxy chart versions (check defaults; pin if floating).
- Live version resolution evidence available from this repo's own CI (the presets applied specific versions — check recent workflow logs if accessible, else resolve from the GitHub APIs read-only).

## Scope
**In scope**: `variables.tf` defaults + descriptions for every floating addon version; `data.tf` (the latest-release data sources become opt-in: gate on explicit sentinel `var.x_version == "latest"` instead of `null`; `null`/unset now means "module default"); a new `locals` version-matrix block (single place listing the reviewed defaults, commented with date); `CHANGELOG.md` (⚠️ upgrade note + 🔧); `MIGRATION.md` note; `kube.tf.example` comments; new harness case pinning-sanity.
**Out of scope**: the update AUTOMATION workflow (record as a follow-up idea in the plan report — a version-refresh workflow is its own plan); SUC version (already pinned); packer inputs (plan 012 territory... not in this batch).

## Steps
### Step 1: Build the matrix
Resolve current stable versions read-only (GitHub API/chart indexes). Add `locals { addon_default_versions = { hetzner_ccm = "vX", hetzner_csi = "vX", kured = "X", longhorn = "X", cert_manager = "vX", rancher = "X", calico = "vX", ... } }` with a dated comment. 
### Step 2: Rewire defaults
For each: variable default stays `null`; the consuming local becomes `coalesce(var.x_version == "latest" ? <latest-datasource-path> : var.x_version, local.addon_default_versions.x)` — precise form per site; the `releases/latest` data sources' count now keys on `== "latest"`. Descriptions document the three modes (unset→module default; explicit version; "latest"→float).
**Verify per site**: fmt+validate; grep proves no consumer still keys on `null` for latest-fetch.
### Step 3: Docs + changelog
⚠️ upgrade note: previously-floating users get the pinned defaults on next apply (one reviewed version change, possibly a chart upgrade); to keep floating set `"latest"`. kube.tf.example + MIGRATION.md wording.
### Step 4: Harness case
Add a check asserting every entry in `addon_default_versions` is a concrete semverish string (no "*"/"latest"/empty).

## Done criteria
- [ ] `grep -n 'default.*"\*"' variables.tf` → no addon-version matches; latest-fetch only on explicit "latest"; matrix local exists; harness passes; fmt+validate; changelog+migration+example updated; README row updated.

## STOP conditions
- A chart pinned today is YANKED/unavailable upstream at its index → pick previous stable, note it.
- Any consumer needs `null` to mean something else (three-state ambiguity you cannot resolve locally) → STOP with the site.
