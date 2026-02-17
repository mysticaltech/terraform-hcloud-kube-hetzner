# T10 / Discussion #634 V3 Design Decision

Status: intentionally not implemented for V3.

## Decision
Do **not** freeze default Leap Micro snapshot IDs in module defaults.

## Reasoning
This repository's current operating model intentionally uses dynamic image discovery when snapshot IDs are not explicitly set by the user (`most_recent` lookup path).

Freezing defaults inside `variables.tf` would:
- make defaults stale between release cycles,
- create hidden maintenance coupling to out-of-band image promotion,
- increase drift risk across projects/regions,
- and can produce false confidence about image provenance when IDs are not continuously release-tested.

With your explicit direction ("microos version freezing, no"), we keep the same philosophy for Leap Micro defaults as well.

## V3 Policy
1. Keep `leapmicro_x86_snapshot_id` and `leapmicro_arm_snapshot_id` defaults empty.
2. Keep lookup fallback to most recent labeled snapshot for unset values.
3. Preserve user override path for deterministic/frozen environments (users set explicit IDs in their config).

## Optional Follow-up (non-breaking docs improvement)
- Add a stronger note in docs recommending explicit snapshot IDs for regulated/prod environments where deterministic rollout provenance is required.

## Acceptance Criteria
- No change to current runtime behavior for users relying on dynamic snapshot discovery.
- No forced image default pinning in module code.
- Deterministic users can still pin snapshot IDs explicitly.

