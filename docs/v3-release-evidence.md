# v3 Release Evidence Matrix

Scope: 2026-07-04/05 v3 release evidence from the live Hetzner project. Module source was the staging worktree unless noted. This file records release-gate evidence that ordinary `fmt`, `validate`, and static plan checks did not cover.

## Live Scenario Matrix

| Date | Scenario | Staging commit | Method | Result | Key observations |
| --- | --- | --- | --- | --- | --- |
| 2026-07-04/05 | k3s + Leap Micro fresh cluster: 1 control plane, 1 agent, Cilium, Traefik | e666a65 | Local Terraform apply from a live root with module source pointed at the staging worktree; Kubernetes/node readiness inspection after apply | PASS after Cilium fix | 45 resources; all nodes Ready on `openSUSE Leap Micro 6.2`; first attempt at `db0e905^` failed on Cilium values YAML bug, fixed by `5639cf9`. |
| 2026-07-04/05 | RKE2 + Leap Micro fresh cluster: 1 control plane, 1 agent | 8c6e411 | Local Terraform apply from a live root with staging module source; Kubernetes system pod and node OS inspection | PASS | 46 resources; both nodes Ready on Leap Micro 6.2; `kube-scheduler` Running; `kube-reserved=512Mi` live-confirmed on `cx23`; earlier attempts exposed reservation bugs fixed by `cfe9ab6` and `8c6e411`. |
| 2026-07-04/05 | v2.21.0 to v3 in-place upgrade: live 37-resource v2.21 cluster, MicroOS, Cilium, nginx | 8c6e411 | Switched live root module source to staging worktree, pinned `k3s_channel = "v1.33"`, reviewed plan, applied, then inspected cluster health and node OS | PASS | Plan had 0 destroy/replace of hcloud infrastructure; 4 in-place updates to firewall rules/server labels; 6 `terraform_data` re-runs; 12 new v3 resources; cluster healthy after apply; Cilium Running; nodes stayed MicroOS with no recreation; migration effort was source switch plus `k3s_channel = "v1.33"` pin. |
| 2026-07-04/05 | Autoscaler: 1 control plane, 1 agent, Cluster Autoscaler pool min 1 | 72e1c54^ (`db0e905` era) | Local Terraform apply from a live root with staging module source; verified autoscaler Deployment and autoscaler-created node readiness | PASS | 47 resources; autoscaler-created node joined Ready on Leap Micro 6.2; Cluster Autoscaler deployment healthy. |
| 2026-07-04/05 | NAT router: private-only nodes, control-plane load balancer, k3s + Leap Micro | 72e1c54^ (`4311e98`) | Local Terraform apply from a live root with staging module source; router `sshd -t`; node readiness; private-node image-pull egress proof through NAT | PASS after heredoc fix | 59-resource topology; router `sshd -t` valid; both private nodes Ready on Leap Micro; egress via NAT proven by image pulls; before `4311e98`, every fresh NAT router bricked `sshd` about 2.5 minutes after boot. |

## Official CI Matrix

| Date | Run | Staging commit | Method | Result | default Terraform/OpenTofu | nginx Terraform/OpenTofu | rke2 Terraform/OpenTofu | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-07-04/05 | 28718815894 | 136acfc^ | `Test in Hetzner` workflow, `workflow_dispatch` on staging | PARTIAL | PASS/PASS | FAIL/FAIL | FAIL/FAIL | RKE2 failed from k3s-flavored Leap snapshot because per-distro secrets were missing; nginx failed from 67-character server names. |
| 2026-07-04/05 | 28719712912 + 28719694176 raced | 136acfc..2d0060d | `Test in Hetzner` workflow, overlapping `workflow_dispatch` runs on staging | PARTIAL | PASS/PASS/PASS plus one quota loss | FAIL x4 | PASS x4 | RKE2 fixed by per-distro snapshots; nginx failures root-caused to load-balancer annotations spliced by strip-markers; quota losses came from 12 parallel clusters; `max-parallel: 2` added in `2d0060d`. |
| 2026-07-04/05 | 28723492149 (record run) | 5aafc86 | ✅/✅ | ✅/✅ | ✅/✅ | FULL GREEN 6/6 — serialized (max-parallel 2), per-distro Leap snapshots, honest OS assertion; locks the v3 CI record |

## Defects Found And Fixed By This Gate

These were invisible to ordinary `fmt`, `validate`, and static plan-only checks.

| Date | Staging commit | Method | Result | One-line description |
| --- | --- | --- | --- | --- |
| 2026-07-04/05 | 5639cf9 | Live k3s + Cilium apply failure, rendered values inspection, `yamldecode` contract hardening | FIXED | Fixed Cilium values indentation and added a `yamldecode` semantic contract so malformed rendered YAML fails before live apply. |
| 2026-07-04/05 | cfe9ab6 + 8c6e411 | Live RKE2 + Leap bootstrap failure on small `cx23` control plane, kubelet reservation review, follow-up apply | FIXED | Added size-aware kubelet reservations, avoided `jsonencode` optional-equality traps, and added safe fallbacks so RKE2 scheduler pods fit small control planes. |
| 2026-07-04/05 | 8c6e411 | CI/live OS assertions using Kubernetes node data | FIXED | Switched CI OS assertion to `nodeInfo.osImage`, verifying the node OS observed by Kubernetes rather than weaker host metadata. |
| 2026-07-04/05 | db0e905 | Live gate and changelog review | FIXED | Hardened Longhorn 1.5+ readiness lists, removed redundant `nonsensitive()` calls twice, added `>50%` reservation guard parsing, and added SSH revocation sidecar behavior. |
| 2026-07-04/05 | 136acfc | Hetzner CI failures and plan-name review | FIXED | Added per-distro Leap CI snapshots, shortened CI names, and added a 63-character server-name plan guard. |
| 2026-07-04/05 | 2d0060d | Hetzner CI quota/race review | FIXED | Added `max-parallel: 2` to avoid quota loss from too many concurrent Hetzner clusters. |
| 2026-07-04/05 | 4311e98 | Fresh NAT router live apply, delayed SSH failure reproduction, repo heredoc sweep | FIXED | Fixed the NAT heredoc bug that wrote script text into SSH config and bricked fresh routers, then swept repo heredocs for the same class. |
| 2026-07-04/05 | 72e1c54 | Hetzner CI nginx failures, rendered Helm values inspection, plan-time semantic assertion | FIXED | Fixed ingress load-balancer annotation splicing and added a semantic adoption contract for rendered ingress values. |

## Known Gaps And Not Covered

| Date | Staging commit | Method | Result | Gap |
| --- | --- | --- | --- | --- |
| 2026-07-04/05 | 72e1c54 | Not live-tested | NOT COVERED | Redundant NAT router mode (`enable_redundancy`) remains untested in live Hetzner. |
| 2026-07-04/05 | 72e1c54 | Not live-tested | NOT COVERED | Robot nodes remain untested. |
| 2026-07-04/05 | 72e1c54 | Not live-tested beyond preview constraints | NOT COVERED | Multinetwork remains an experimental preview, not release-grade live coverage. |
| 2026-07-04/05 | 72e1c54 | Workflow observation from canceled CI jobs | OPEN WORKFLOW GAP | Canceled CI jobs can orphan clusters; cleanup is manual today and should become a future workflow improvement. |
| 2026-07-04/05 | 72e1c54 / v2 master pending | Static pattern concern only; no explicit v2 live decision yet | PENDING DECISION | v2 master may carry the same ingress-annotation splice pattern; changing it on live v2 clusters needs an explicit behavior-risk decision. |
- `terraform destroy` could leave the CCM-adopted ingress load balancer alive and attached to the network (observed live: LB survived full cluster destruction, blocking network deletion for 20+ min as `context deadline exceeded`). The v3 line now restores fail-open destroy-time ingress Service cleanup before node/LB-network teardown -- FIXED in this commit by static trace and rendering; live re-destroy remains not rerun here.
