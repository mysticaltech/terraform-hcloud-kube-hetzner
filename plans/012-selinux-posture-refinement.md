# Plan 012: SELinux posture refinement
- **Priority**: P3 | **Effort**: M | **Risk**: MED | **Category**: security | **Status**: PARTIAL DONE

Verdict from the 2026-07 review and maintainer confirmation: v3 SELinux is
fundamentally right. Enforcement stays on by default, distro policy RPMs are
baked into Leap images, per-pool escape hatches exist, and the custom rules are
empirically calibrated from real workload denials accumulated over years.

## Done for v3 staging

1. Provenance documentation is done in `docs/selinux.md`. It records the
   v2 inline-policy history, the extraction point, the v3 Leap policy origin,
   traceable issue/PR references, and explicitly marks genuinely untraceable
   pre-extraction accretion.
2. CI AVC visibility is done as a report-only live-gate step in
   `.github/workflows/hetzner-test.yaml`. It prints
   `SELINUX AVC DENIALS (node X): N` plus raw denial lines from live nodes, but
   it never fails the job.

## Deferred post-v3.0

1. Do not unify `templates/kube-hetzner-selinux.te` and
   `templates/k8s-custom-policies.te` before v3.0. The current split has a
   small deliberate overlap, and unifying the files would churn rendered
   user_data near release for low immediate benefit.
2. Do not promote AVC reporting to a hard CI gate yet. Observe real CI data
   first, then decide whether a zero-AVC assertion is stable enough for every
   preset.
3. Keep any narrowing of
   `container_t unreserved_port_t:tcp_socket { name_bind ... }` post-v3.0 and
   data-driven. It is the broadest rule, but it exists because Kubernetes
   workloads and hostNetwork pods bind arbitrary high ports.
