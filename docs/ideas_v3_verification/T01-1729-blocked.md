# T01 / Discussion #1729 V3 Design Decision

Status: approved design for V3 implementation.

## Goal
Enable clusters to scale beyond the practical single-network ceiling by introducing multi-network topology while preserving upgrade safety for existing deployments.

## Why this is needed
Current architecture binds all control planes and agents to one Hetzner network (`data.hcloud_network.k3s.id`), and the module currently validates agent capacity with a hard cap of 100.

Key current constraints in code:
- Single network attachment path: `control_planes.tf`, `agents.tf`, `main.tf`
- Global agent cap check: `variables.tf` validation (`<= 100`)
- Single-network secret/config assumptions: `locals.tf`

Hetzner network attachment limits make "remove validation only" unsafe and insufficient.

## V3 Architectural Decision
### 1) Keep backward compatibility by preserving a primary network path
- Existing single-network inputs remain valid for all existing users.
- Existing resource addresses for primary network resources remain stable where possible.
- Multi-network is additive, not a forced migration.

### 2) Add explicit network topology model
Introduce a `networks` map (V3) with one required logical key `primary`, plus optional secondary networks.

Planned shape (conceptual):
- `networks[<key>].network_ipv4_cidr`
- `networks[<key>].existing_network_id` (optional)
- `networks[<key>].network_region` (optional override)
- `networks[<key>].expose_routes_to_vswitch` (optional, default false)

### 3) Add per-nodepool network placement
- Add `network_key` to `control_plane_nodepools` and `agent_nodepools` (default `"primary"`).
- Node resources derive `network_id`, `subnet_id`, and `private_ipv4` from their assigned `network_key`.

### 4) Replace global node-count thinking with per-network attachment budgets
- Deprecate global agent cap logic.
- Validate per network:
  - attached servers + load balancers <= provider network attachment ceiling
  - practical reserved headroom for LBs/endpoints is preserved
- Keep explicit validation errors with remediation guidance.

### 5) Join endpoint behavior for cross-network nodes
- Nodes outside the control-plane primary network must not assume direct private join path.
- Join path must align with #2044 behavior (`public`/`private` endpoint semantics).
- For cross-network placement, enforce public join endpoint or documented overlay requirements.

## Delicate Parts and Safety Rules
1. No destructive replacements for existing single-network clusters in default path.
2. Do not convert existing primary resource addresses in a way that forces recreation.
3. Introduce multi-network resources in additive phases, then migrate only with explicit operators steps.
4. Keep control plane LB semantics stable during transition.

## Phased Implementation Plan
### Phase A: Schema + validation (non-breaking)
- Add `networks` and nodepool `network_key` inputs.
- Keep all legacy behavior when `networks` is unset.
- Add per-network budget checks.

### Phase B: Additive resource graph
- Keep existing primary network resources for compatibility.
- Create secondary network/subnet resources for non-primary keys.
- Compute node/subnet selection maps by `network_key`.

### Phase C: Node placement wiring
- Route node modules to correct `network_id` and `private_ipv4` for each network key.
- Enforce join endpoint validation for cross-network pools.

### Phase D: Docs + upgrade guide
- Document topology patterns and limits.
- Add explicit migration strategy from single-network to multi-network.

## Acceptance Criteria
- Existing single-network configs produce no destructive replacements.
- Multi-network config can exceed 100 total nodes while respecting per-network limits.
- Validation messages are deterministic and actionable.
- Terraform gates pass (`fmt`, `validate`, `init -upgrade`, `plan`, with expected token caveat in local env).

## Explicit Non-Goals in this task
- No Ansible sidecar workflow.
- No hidden implicit migration of existing clusters.

