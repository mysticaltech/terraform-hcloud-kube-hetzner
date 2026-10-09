# Upgrades and Migration

Use this guide for module, Kubernetes, and transactional OS upgrades. For a v2 to v3 migration, the compatibility contract in [`MIGRATION.md`](../MIGRATION.md) takes precedence over the general in-major procedures below.

[Documentation index](index.md)

## v2 -> v3 migration

For `v2.x` -> `v3.x`, start with [`MIGRATION.md`](../MIGRATION.md), the contract/variable map, and [`docs/v2-to-v3-migration.md`](v2-to-v3-migration.md), the guided walkthrough. The live release evidence includes a `v2.21.0` -> `v3` in-place upgrade with 0 destroy/replace of hcloud infrastructure for the standard path; read the guide before planning and apply only after every planned resource action is understood.
Production operators should read the [`Production in-place upgrades: safety model`](../MIGRATION.md#production-in-place-upgrades-safety-model) before applying.

> **Fastest path:** if you use Claude Code or a compatible agent, run the [`/migrate-v2-to-v3` skill](#ai-assisted-migration) from a checkout of this repo — it applies the rename map, runs the protected-infrastructure plan gate, and reviews the plan with you before anything is applied.

From a local kube-hetzner checkout, audit the Terraform root, then run:

```bash
uv run python /path/to/kube-hetzner/scripts/v2_to_v3_migration_assistant.py --root .
terraform init -upgrade
terraform plan
```

Only apply after reviewing all planned resource actions. Release-gate evidence is recorded in [`docs/v3-release-evidence.md`](v3-release-evidence.md).

## v3 Readiness Checklist

Before applying a v3 upgrade, confirm:

- Current state is backed up with `terraform state pull`.
- Removed v2 inputs are gone and renamed booleans with inverted meaning are reviewed.
- Addon version policy is reviewed: unset addon version variables use deterministic module defaults, while `latest` opts back into upstream floating behavior.
- In-place v2 upgrades keep the default `network_subnet_mode = "per_nodepool"` unless subnet resource changes are intentional.
- `terraform validate` or `tofu validate` passes before planning.
- `terraform plan` has no unexpected `delete`, `replace`, or `forces replacement` actions.
- Network, subnet, load balancer, NAT router, placement group, server, and volume changes are intentional.
- Private-only, Robot/vSwitch, external-network, Tailscale/overlay, Longhorn, and autoscaler clusters have a rollback or blue/green plan.

---

## AI-assisted migration

This repo ships [agent skills](https://docs.claude.com/en/docs/claude-code/skills) under `.claude/skills/` for Claude Code, Codex, Cursor, and any skills-capable agent. Install them in one command:

```bash
npx skills add kube-hetzner/terraform-hcloud-kube-hetzner
```

**`/kh-assistant`** is the flagship: a kube-hetzner expert with live repo knowledge that answers configuration and debugging questions and recommends the right specialized skill for the job. `/migrate-v2-to-v3` guides the whole v2 -> v3 upgrade with protected-infrastructure plan gates; `/upgrade-cluster` and `/debug-node` cover live upgrades and rescue-mode node debugging.

Usage sketch:

```text
/migrate-v2-to-v3 <terraform-root>
/upgrade-cluster <terraform-root>
/debug-node
```

| Skill | Purpose |
|-------|---------|
| `/migrate-v2-to-v3 <terraform-root>` | Guided v2 to v3 migration and plan review |
| `/kh-assistant` | Interactive help for configuration and debugging |
| `/upgrade-cluster <terraform-root>` | Safety-first workflow for live module and Kubernetes cluster upgrades |
| `/debug-node` | Rescue-mode workflow for unreachable Hetzner nodes, SSH failures, cloud-init failures, or provisioning hangs |
| `/review-pr <num>` | Security-focused PR review |
| `/test-changes` | Run terraform fmt, validate, plan |

**PRs to improve these skills are welcome!** See `.claude/skills/` for the skill definitions.

## In-major Kubernetes and OS upgrades

### OS Upgrades (Leap Micro / MicroOS)

Handled by [Kured](https://github.com/kubereboot/kured)—safe, HA-aware reboots. Configure timeframes via [Kured options](https://kured.dev/docs/configuration/).
Set `enable_kured = false` only when reboot orchestration is managed externally;
`automatically_upgrade_os` controls the host update timer, not Kured deployment.

### K3s Upgrades

Managed by [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller). Customize the [upgrade plan template](../templates/plans.yaml.tpl).
Set `enable_system_upgrade_controller = false` only when the controller and plans
are managed externally; `automatically_upgrade_kubernetes` controls upgrade
activity, not system-upgrade-controller deployment.

### Disable Automatic Upgrades

```tf
# Disable OS upgrades (required for <3 control planes)
automatically_upgrade_os = false

# Disable k3s upgrades
automatically_upgrade_kubernetes = false
```

<details>
<summary><strong>Manual upgrade commands</strong></summary>

**Selective k3s upgrade:**
```sh
kubectl label --overwrite node <node-name> k3s_upgrade=true
kubectl label node <node-name> k3s_upgrade-  # disable
```

**Or delete upgrade plans:**
```sh
kubectl delete plan k3s-agent -n system-upgrade
kubectl delete plan k3s-server -n system-upgrade
```

**Manual OS upgrade:**
```sh
kubectl drain <node-name>
ssh root@<node-ip>
systemctl start transactional-update.service
reboot
```
</details>

### Component Upgrades

Use the `kustomization_backup.yaml` file created during installation:

1. Copy to `kustomization.yaml`
2. Update source URLs to latest versions
3. Apply: `kubectl apply -k ./`

### RKE2 bundled Gateway API CRDs

RKE2 v1.37 introduces an independent `rke2-gateway-api-crd` Helm chart. When the module's resolved initial version is v1.37+, KH disables that chart in both server configuration writers so it cannot adopt KH-managed Gateway CRDs or override `gateway_api_version`. This also applies when KH Gateway providers are disabled. Older initial versions retain their previous YAML; automatic Kubernetes upgrades do not recompute that initial-version guard. Explicit `control_planes_custom_config.disable` overrides replace the module's list, so retaining bundled CRDs is an intentional operator-owned choice.

For an existing cluster that already installed the bundled chart, **stop before applying the new configuration and verify an ownership handover**. Do not delete Gateway CRDs: that deletes the Gateway and Route resources they contain.

1. Back up the CRDs and all Gateway API resources. Record each CRD's UID, served/stored versions, bundle-version annotation and Helm owner, plus resource counts. Inspect the actual chart release and its server manifest on every control plane.
2. Select a single lifecycle owner and a bundle supported by the chosen Gateway controller. If handing ownership to KH, explicitly pin a compatible `gateway_api_version` that preserves the installed schema; do not allow the derived older bundle to overwrite newer CRDs. Check the upstream safe-upgrades admission policy rather than removing it merely to force a downgrade.
3. Verify retention in the **installed Helm release manifest**, not just live annotations. The exact v1.37.0 chart `rke2-gateway-api-crd-1.6.101` marks its ten standard CRDs `helm.sh/resource-policy: keep`. The three optional experimental `gateway.networking.x-k8s.io` CRDs and its admission policy/binding lack that annotation; uninstalling an experimental-enabled release can delete those CRDs and their resources. Package defaults leave experimental CRDs disabled, but do not infer the installed release's values. Another chart version or a modified release needs its own inspection. Do not blindly uninstall the chart or publish a generic uninstall command.
4. Perform the reviewed handover and serial server-config rollout in a maintenance window. Confirm the bundled chart is no longer reconciling, the intended owner/version remains, all recorded CRD UIDs and Gateway/Route objects survive, and controller status and traffic are healthy before continuing.

This is a required operator review boundary, not an automated migration. Neither a provider-free plan nor the packaged `keep` annotation proves a live handover. See the [RKE2 v1.37 release notes](https://docs.rke2.io/release-notes/v1.37.X) and [exact standalone chart package](https://rke2-charts.rancher.io/assets/rke2-gateway-api-crd/rke2-gateway-api-crd-1.6.101.tgz).

---

## Module version upgrades

Update `version` in your kube.tf and run `terraform apply`.

### Migrating from 1.x to 2.x

1. Run `createkh` to get new packer template
2. Update version to `>= 2.0`
3. Remove `extra_packages_to_install` and `opensuse_microos_mirror_link` (moved to packer)
4. Run `terraform init -upgrade && terraform apply`
