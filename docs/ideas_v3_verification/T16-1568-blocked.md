# T16 / Discussion #1568 V3 Design Decision

Status: approved for V3 implementation.

## Decision
Migrate Calico installation from legacy monolithic manifest patching to Tigera operator-based installation.

Your direction accepted: "calico operator, yes move to it if well supported".

## Why change
Current path relies on patching Calico's monolithic manifest via `calico_values` DaemonSet patch semantics. This is brittle and harder to evolve for modern Calico features.

## V3 Target Model
1. Use Tigera operator manifest as the install primitive.
2. Apply explicit CRs (at minimum `Installation`; optional `APIServer` depending on enabled features).
3. Keep CNI install sequencing integrated with existing Terraform/kustomize flow.

## Compatibility Strategy
### Stage 1: Dual-mode support (safe transition)
- Introduce install mode toggle (conceptually `calico_install_mode = manifest|operator`).
- Default to existing behavior for compatibility in transition window.
- Operator mode available for early adopters and V3 testing.

### Stage 2: V3 default shift
- Switch default to operator mode for V3 major line.
- Keep temporary fallback for migration recovery.

### Stage 3: legacy path deprecation
- Remove manifest patch path only after documented deprecation period.

## Value Mapping Plan
- Preserve existing high-signal knobs:
  - cluster CIDR wiring
  - wireguard setting intent
  - MTU and related networking defaults where applicable
- Introduce operator-specific values surface for advanced tuning.
- Keep current `calico_values` available during transition to avoid abrupt breakage.

## Terraform Integration Plan
1. Update CNI resource source from Calico monolith to Tigera operator resource.
2. Add generated operator CR template artifact(s) in post-install path.
3. Ensure kustomization apply ordering keeps CRDs/controllers ready before CR application.
4. Add explicit waits/guards for operator readiness.

## Risks and Mitigations
- Risk: behavior drift between manifest and operator defaults.
  - Mitigation: staged dual-mode rollout and side-by-side documentation.
- Risk: upgrade edge cases in existing clusters.
  - Mitigation: transition mode + clear rollback instructions.
- Risk: implicit value translation ambiguity.
  - Mitigation: explicit mapping table in docs and conservative defaults.

## Acceptance Criteria
- Operator mode deploys cleanly through existing Terraform flow.
- Existing clusters can upgrade without forced destructive infra changes.
- Fallback path exists during transition period.
- Terraform gates pass (`fmt`, `validate`, `init -upgrade`, `plan`, local token caveat documented).

