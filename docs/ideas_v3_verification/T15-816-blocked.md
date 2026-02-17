# T15 / Discussion #816 V3 Design Decision

Status: approved with scoped implementation change.

## Decision
Refactor the monolithic `terraform_data.kustomization` flow into smaller Terraform-native stages.

Explicitly **out of scope** for V3:
- Any Ansible-based day-2 provisioning path.

This follows your direction: "ansible, no go".

## Why this refactor is still needed
Current `terraform_data.kustomization` combines many concerns in one resource:
- file uploads for multiple addons,
- CNI path handling,
- helmchart application and waits,
- system-upgrade plan rollout,
- mixed trigger domains.

That makes blast radius and debugging larger than necessary.

## V3 Terraform-Only Split Plan
### Stage 1: Core bootstrap artifacts
- Upload base kustomization and global required manifests.
- Keep core dependencies identical to current behavior.

### Stage 2: CNI-specific artifacts
- Handle Calico/Cilium artifact generation and uploads in dedicated resource(s).
- Isolate CNI trigger domain from unrelated addons.

### Stage 3: Core platform addons
- Hetzner CCM/CSI + system-upgrade prerequisites.
- Keep ordering explicit and deterministic.

### Stage 4: Optional addons
- Ingress, Longhorn, Cert-Manager, Rancher, SMB CSI.
- Trigger by their own values/version controls.

### Stage 5: Apply + readiness gates
- Consolidate apply/wait logic with strict ordering and bounded retries.

## Non-Goals
- No new external tooling/runtime dependency.
- No hidden behavior change to existing default install path.

## Migration and Compatibility Rules
1. Keep current semantics for existing configs.
2. Keep existing trigger intent (values/version/options) but distribute to narrower domains.
3. Preserve k3s/rke2 branching behavior.
4. Preserve current wait gates (deployment + job completion expectations).

## Acceptance Criteria
- Smaller Terraform resources with clear ownership boundaries.
- Same resulting cluster state for existing configurations.
- Improved plan readability (which stage changes and why).
- Terraform gates pass (`fmt`, `validate`, `init -upgrade`, `plan`, local token caveat documented).

