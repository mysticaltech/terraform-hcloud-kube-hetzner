# Plan 009: A label-scoped, age-gated sweeper reclaims orphaned Hetzner CI resources

> **Executor instructions**: step-by-step; verify; STOP binding; update plans/README.md.
>
> **Drift check**: `git diff --stat e506cc4..HEAD -- .github/workflows/` — mismatch = STOP.

## Status
- **Priority**: P2 | **Effort**: M | **Risk**: MED (deletion automation!) | **Depends on**: none | **Category**: dx
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
Interrupted/cancelled "Test in Hetzner" jobs skip their destroy step and orphan complete clusters (billable servers + LBs + networks) — observed repeatedly during the v3 live gate; cleanup was manual API surgery each time. The workflow now queues instead of cancelling (mitigation), but crashes/timeouts still orphan. A conservative sweeper closes the loop.

## Current state
- `.github/workflows/hetzner-test.yaml` — env `HCLOUD_TOKEN` from environment `hetzner-test` secrets; `TEST_CLUSTER_NAME="kh-ci-..."` (~line 87); destroy is a best-effort final step gated on local state existing (~191-196).
- All CI resources are unambiguously named `kh-ci-*`; module-created servers also carry hcloud labels (see `locals.tf` `labels` merged into servers incl. `provisioner`/`cluster`); NETWORKS/LBs/SSH-keys/firewalls created by the module are named `<cluster_name>...` = `kh-ci-...`.
- Evidence doc records the gap: `docs/v3-release-evidence.md` (orphan cleanup manual).
- Workflow conventions: see existing yaml (ubuntu-latest, environment: hetzner-test, `if: vars.TEST_IN_HETZNER == '1'`).

## Scope
**In scope**: NEW `.github/workflows/hetzner-ci-sweeper.yaml`; `docs/v3-release-evidence.md` gap line update; `CHANGELOG.md` 🔧 line. **Out of scope**: hetzner-test.yaml itself; any non-`kh-ci-` resource, ever.

## Steps
### Step 1: Sweeper script inline in a new workflow
Triggers: `schedule` (cron every 6h) + `workflow_dispatch` with input `mode` (choice: `dry-run` default, `delete`). Job gated `if: vars.TEST_IN_HETZNER == '1'`, environment `hetzner-test`. Steps (bash + curl + jq, no external actions beyond checkout not even needed):
1. **Active-run guard**: query the GitHub API for in-progress/queued runs of workflow `hetzner-test.yaml` (`GITHUB_TOKEN` provided by default; `gh api repos/${{ github.repository }}/actions/workflows/hetzner-test.yaml/runs?status=in_progress` + `queued`). If ANY → exit 0 with notice "active run, skipping" (this rule exists because sweeping during an active run once deleted a live run's resources).
2. Enumerate servers, load_balancers, networks, firewalls, ssh_keys, primary_ips via Hetzner API; candidate = name matches `^kh-ci-` AND `created` older than **2 hours** (parse ISO date; primary_ips may lack created → treat unattached `kh-ci-*` ones as candidates regardless of age).
3. `dry-run` (default & all scheduled runs run dry first): print the candidate table; then in `delete` mode (dispatch-only) — delete servers first, wait 30s, then LBs, firewalls, ssh_keys, networks, primary_ips; every DELETE logged with HTTP code; 204/404 both OK.
4. Scheduled runs: after the dry-run listing, delete ONLY if candidates are older than **6 hours** (double age gate for unattended deletion).
**Verify**: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/hetzner-ci-sweeper.yaml'))"` (or ruby fallback) → parses; shellcheck the inline script if available (`shellcheck -` piping the run block) else `bash -n` a extracted copy.
### Step 2: Evidence + changelog
Update the orphan-cleanup gap line in `docs/v3-release-evidence.md` (now automated, dry-run-default); changelog line.

## Done criteria
- [ ] Workflow file parses; guard/age/dry-run logic present (`grep -c 'in_progress\|dry-run\|kh-ci-' .github/workflows/hetzner-ci-sweeper.yaml` ≥ 4); docs+changelog updated; only in-scope files; README row updated.

## STOP conditions
- Any deletion path that could match a non-`kh-ci-` name (review your jq filters twice; if a filter is name-substring rather than prefix-anchored → fix or STOP).
- No way to check active runs from the sweeper context → STOP (the guard is non-negotiable).
