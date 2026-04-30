# v3 Release Smoke Task Board

Status: smoke gates in progress.

## Tasks

- [x] S1 Inventory branch, PR, credentials, and blast-radius surfaces.
- [x] S2 Static root gates: fmt, terraform-docs, null-resource grep, Terraform validate, OpenTofu validate, diff check.
- [x] S3 Example gates: `kube.tf.example`, Cilium Gateway API, Tailscale node transport, large-scale Tailscale references.
- [x] S4 Plan matrix: Gateway API valid/invalid, embedded registry mirror valid/invalid, Tailscale transport constraints, kube-test root.
- [x] S5 Final tightening from smoke failures.
- [ ] S6 Commit, push, and update the open PR.
- [ ] S7 External reviews: Gemini, Codex CLI, Atlas/ChatGPT extended thinking.
- [ ] S8 Integrate verified review findings and rerun affected checks.

## Blast Radius

- Cilium Gateway API variables, CRD rendering, Cilium values, cert-manager Gateway support, and example manifests.
- Embedded registry mirror variables, generated `registries.yaml`, server/agent/autoscaler config paths, and validation rules.
- Tailscale node transport interactions with multinetwork, route advertisement, kubeconfig/join endpoint outputs, and examples.
- Release docs and skills that teach v3 topology, migration, and validation gates.
