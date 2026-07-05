# Plan 010 (design spike): Decide the path to reorder-proof node resource addresses

> **Executor instructions**: this is an INVESTIGATION plan — produce a design document, change NO module code. Output = `plans/010-report.md`. Update plans/README.md when done.
>
> **Drift check**: `git diff --stat e506cc4..HEAD -- locals.tf control_planes.tf agents.tf main.tf` — heavy drift = STOP.

## Status
- **Priority**: P3 | **Effort**: M (spike; the real fix is L/HIGH) | **Risk**: none (read-only) | **Depends on**: none | **Category**: tech-debt (design)
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
Node resource addresses embed the nodepool LIST INDEX: keys like `0-0-control-plane` (`format("%s-%s-%s", pool_index, node_index, name)` — `locals.tf:926` control planes, `:1024` agents; consumed as `for_each` keys in `control_planes.tf:40`, `agents.tf:40`; per-pool subnets are `count`-indexed in `main.tf:37`). Inserting/reordering a nodepool therefore replans OTHER pools' servers destructively even though names are validated unique. This is v2-inherited; fixing it is a breaking state migration — hence a spike, not a fix.

## Deliverable: `plans/010-report.md` answering
1. **Inventory**: every resource/module keyed by index-bearing addresses (grep `pool_index`, `count.index` around nodepools/subnets; list address patterns and blast radius).
2. **Options analysis** (≥3): (a) name-based keys + generated `moved` blocks emitted from a migration helper; (b) name-based keys + documented `terraform state mv` script shipped in `scripts/`; (c) keep indexes but add a validation-contract that FREEZES ordering (reject reorder/insert-not-at-end by comparing against a user-pinned `nodepool_order` list) — the "make the sharp edge loud" option; (d) hybrid: freeze now (v3.0), migrate keys in v4. For each: user migration steps, failure modes (moved-block limits across for_each map keys! verify: `moved` supports for_each key changes — research and cite), CI/live test needs, docs burden.
3. **Recommendation** with honest cost, sequencing (which release), and the exact validation-contract sketch if (c)/(d).
4. **Evidence**: reproduce the churn in a scratch plan (fixtures root + two tfvars: baseline, pool-inserted; show the destructive diff addresses) — plan-only, no apply, no cloud (init -backend=false; plan will fail at data sources without token → if so, demonstrate via `terraform plan -refresh=false` on an empty state as far as it goes, or via the address-set technique: generate plans and diff `terraform show -json` planned addresses; a token from env MAY be available — check `HCLOUD_TOKEN` presence, never print it).

## STOP conditions
- None besides drift — this plan changes no code. If you find the churn does NOT reproduce (keys stable under reorder), that's a major finding: report and stop.
