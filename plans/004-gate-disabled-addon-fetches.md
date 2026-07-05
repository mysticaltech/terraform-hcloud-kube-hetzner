# Plan 004: Disabled addons perform zero HTTP fetches at plan/apply

> **Executor instructions**: step-by-step; verify; STOP conditions binding; update plans/README.md.
>
> **Drift check**: `git diff --stat e506cc4..HEAD -- data.tf init.tf locals.tf` — excerpt mismatch = STOP.

## Status
- **Priority**: P2 | **Effort**: S | **Risk**: LOW | **Depends on**: none | **Category**: perf
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
Clusters with `enable_kured=false` and/or `enable_system_upgrade_controller=false` still fetch the kured release metadata + manifest and both SUC manifests from GitHub on every plan — avoidable latency, rate-limit exposure, and a hard failure mode for offline/air-gapped plans on features the user disabled.

## Current state
`data.tf`: `kured_release` (~:31) is gated ONLY on `var.kured_version == null` (`count = var.kured_version == null ? 1 : 0`) — not on `enable_kured`. `kured_manifest` (~:46), `system_upgrade_controller_manifest` (~:60), `system_upgrade_controller_crd_manifest`/`crd` (~:74) have NO count gate. Consumers: `init.tf` file provisioners already conditionally use bodies (`var.enable_kured ? data.http.kured_manifest.response_body : ""` pattern in BOTH k3s and rke2 upload blocks) and trigger hashes reference them. Pattern to follow for gated data sources + safe indexing: `data.http.hetzner_csi_release` in the same file (`count` + `[0]` + `length()` guards, see locals.tf `csi_version`).

## Commands
Fmt/validate as in plan 002.

## Scope
**In scope**: `data.tf`, every reference site of the four data sources (`grep -rn 'kured_manifest\|kured_release\|system_upgrade_controller_manifest\|system_upgrade_controller_crd' *.tf`), `CHANGELOG.md` one 🔧 line.
**Out of scope**: behavior when the toggles are true (byte-identical rendered content required); the toggles' semantics; `docs/terraform.md`.

## Steps
### Step 1
Gate: `kured_release` count = `var.enable_kured && var.kured_version == null ? 1 : 0`; `kured_manifest` count on `var.enable_kured`; both SUC manifests count on `var.enable_system_upgrade_controller`. Introduce normalization locals (e.g. `kured_manifest_body = var.enable_kured ? data.http.kured_manifest[0].response_body : ""`) and switch ALL reference sites (uploads AND trigger hashes, k3s AND rke2 paths) to the locals so indexing lives in exactly one place.
**Verify**: `grep -rn 'data.http.kured_manifest\.' *.tf | grep -v '\[0\]'` → no matches; same for the SUC pair; fmt+validate pass.
### Step 2
CRITICAL upgrade check: trigger hashes that previously hashed the fetched body now hash `""` when disabled — for users who ALREADY disabled the toggles on v3, this changes the stored trigger value → one idempotent kustomization re-run (same class as the documented toggle-trigger change). State this explicitly in the changelog line. For enabled users the hash input must be UNCHANGED — verify by reasoning through each hash expression in your report.
**Verify**: written analysis in report; `grep -n 'enable_kured' CHANGELOG.md | head -2` shows the new line.

## Done criteria
- [ ] All four data sources count-gated; no ungated `[0]`-less references; fmt+validate pass; changelog updated; only in-scope files; README row updated.

## STOP conditions
- Any reference site is inside a `templatefile()` argument where replacing with a local changes rendering semantics → STOP and report the site.
