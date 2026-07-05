# Advisor Plans — v3/staging improvement round

Written by the improve-skill advisor session of 2026-07-05 against commit `e506cc4`. Source audit: 30 findings across 4 parallel category audits, vetted by direct code reads (10/10 spot-checks confirmed); selection delegated by maintainer ("I trust your judgement"). Executors: Codex gpt-5.5 xhigh workers in isolated worktrees; the advisor reviews every diff.

## Execution order & dependencies

| Wave | Plans | Rationale |
|---|---|---|
| 1 | 001 (render harness), 009 (CI sweeper), 010 (spike) | Disjoint files; 001 becomes the verification gate the later plans cite |
| 2 | 002, 003, 004, 005, 006 | Independent S-effort fixes; disjoint files; parallel-safe |
| 3 | 007 (shell-safety; needs 001), 008 (versions; needs 001 + 004) | Heavier, harness-verified |

Dependency edges: 007→001, 008→001, 008→004 (same data sources — 004 lands first).

## Status

| Plan | Title | Status |
|---|---|---|
| 001 | Render harness + negative contract tests | DONE |
| 002 | Kubeconfig structural rewrite | DONE |
| 003 | Sensitive backup file | DONE |
| 004 | Gate disabled-addon fetches | DONE |
| 005 | Pin CSI chart sources / remove dead NFS template | DONE |
| 006 | ssh_port validation | DONE |
| 007 | Shell-safe user inputs | DONE |
| 008 | Deterministic addon versions | DONE |
| 009 | CI orphan sweeper | DONE |
| 011 | Ingress LB single ownership (design) | TODO |
| 010 | Stable node keys (design spike) | DONE — plans/010-report.md |

## Considered and rejected / deferred (do not re-audit)

- **ARCH-01..05** (first-CP config dedup, addon registry, values-merger registry, nodepool normalization, locals.tf split): real, HIGH-leverage long-term, but refactoring a 3.2k-line locals file before the render harness (001) exists repeats the live-gate failure mode. Revisit as a program once 001 is green in CI.
- **DIRECTION-01 (Tailscale live-proof)**: maintainer-level decision (credentials + cost); README wording softening is bundled into no plan — raise at release review.
- **DIRECTION-03 (Calico graduation)**: HIGH-risk CNI mechanics; needs its own design round.
- **DIRECTION-02 (destroy-time LB cleanup)**: already implemented and live-proven during the same session (staging `e506cc4` parentage).
- **DOCS-01/02, DX-01, DEPS-01/03, TEST-02**: valid; deferred this round to keep the batch reviewable. DOCS fixes are safe candidates for any idle cycle.
- **CORRECTNESS-02** → became spike 010 (breaking-change class).
- **Cloudflare Zero Trust**: rejected as a NODE TRANSPORT (all node-to-node traffic would relay through Cloudflare's edge — unacceptable latency for etcd/CNI vs Tailscale's direct WireGuard paths). Accepted as a future ACCESS-PLANE direction: cloudflared tunnel + Access for kube-API/SSH with zero public ports; the node_transport_mode enum seam remains open if ever revisited.
