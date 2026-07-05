# Plan 003: Kustomization backup can no longer leak the sensitive Rancher registration URL

> **Executor instructions**: step-by-step, verify each step, STOP conditions binding, update plans/README.md.
>
> **Drift check (run first)**: `git diff --stat e506cc4..HEAD -- kustomization_backup.tf locals.tf variables.tf` — excerpt mismatch = STOP.

## Status
- **Priority**: P1 | **Effort**: S | **Risk**: LOW | **Depends on**: none | **Category**: security
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
`rancher_registration_manifest_url` is declared `sensitive = true` (it embeds a registration token). When set, it is concatenated into `local.kustomization_backup_yaml` (locals.tf ~661: `var.rancher_registration_manifest_url != "" ? [var.rancher_registration_manifest_url] : []`) which `kustomization_backup.tf` writes with plain `local_file` to `${cluster_name}_kustomization_backup.yaml`. A registration credential lands in a world-default-perms-adjacent local file via a non-sensitive resource. If any user has set this variable, their token should be treated as exposed.

## Current state
`kustomization_backup.tf:1-6`:
```hcl
resource "local_file" "kustomization_backup" {
  count           = var.create_kustomization ? 1 : 0
  content         = local.kustomization_backup_yaml
  filename        = "${var.cluster_name}_kustomization_backup.yaml"
  file_permission = "600"
}
```
Convention exemplar: the module already uses `local_sensitive_file` elsewhere — `grep -rn 'local_sensitive_file' *.tf` to find it (kubeconfig file resource) and match it.

## Commands
Fmt/validate identical to plan 002's table.

## Scope
**In scope**: `kustomization_backup.tf`, `CHANGELOG.md` (v3 Unreleased 🐛/security line incl. rotation advice), `MIGRATION.md` (one warning line for users who set the variable: rotate the registration token).
**Out of scope**: `locals.tf` content of the backup; removing the URL from the backup (the backup's purpose includes it); output changes.

## Steps
### Step 1
Change the resource type to `local_sensitive_file` (same attributes; `file_permission` stays "600"). NOTE state impact: type change = destroy/create of the local file resource only — harmless (it's a local file); confirm `terraform validate` passes and mention the plan-level effect in your report.
**Verify**: `grep -n 'local_sensitive_file "kustomization_backup"' kustomization_backup.tf` → 1 match; fmt+validate pass.
### Step 2
Changelog + MIGRATION.md rotation note (one line each; changelog names the credential TYPE only — never any value).
**Verify**: `grep -c 'rotat' CHANGELOG.md MIGRATION.md` → ≥1 each.

## Done criteria
- [ ] No `local_file` for the backup remains; fmt+validate pass; only in-scope files touched; README row updated.

## STOP conditions
- `local_sensitive_file` unavailable in the pinned `hashicorp/local` provider floor (`versions.tf`) → STOP, report the floor.

## Maintenance note
Anything that may embed sensitive inputs and touches disk uses `local_sensitive_file` — reviewers watch for this in new backup/debug outputs.
