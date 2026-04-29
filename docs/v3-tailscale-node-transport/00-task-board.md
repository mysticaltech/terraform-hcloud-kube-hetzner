# v3 Tailscale Node Transport Task Board

Status: static implementation and validation complete; live Hetzner/Tailscale
E2E remains pending credentials.

## Tasks

- [x] Create macro implementation plan.
- [x] Create child task plans before implementation.
- [x] M1 API and cross-variable validation.
- [x] M2 bootstrap, secrets, and transactional OS persistence.
- [x] M3 node address, join endpoint, and kubeconfig rendering.
- [x] M4 CNI support matrix wiring.
- [x] M5 autoscaler multinetwork bootstrap.
- [x] M6 Hetzner network capacity and placement validation.
- [x] M7 Load Balancers, CCM, and optional operator boundary.
- [x] M8 docs, examples, skills, and migration surfaces.
- [x] M9a static Terraform/OpenTofu/example/Tailscale validation matrix.
- [ ] M9b live Hetzner/Tailscale test matrix.
- [ ] M10 release-readiness gate.

## End State

`node_transport_mode = "tailscale"` is an opt-in v3 production transport for
secure single-network clusters and large clusters that need more than one
Hetzner Network without exposing Kubernetes/CNI peer traffic publicly.
Unsupported or unproven combinations fail at plan time. Supported combinations
pass Terraform, OpenTofu, static plan, and live Hetzner/Tailscale validation.
