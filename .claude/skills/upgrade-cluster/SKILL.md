---
name: upgrade-cluster
description: Use when upgrading or hardening an existing kube-hetzner cluster, including module version bumps, provider lockfile refreshes, K3s channel/version upgrades, immutable node replacement, system-upgrade-controller changes, or live cluster rollout validation
---

# Upgrade Kube-Hetzner Cluster

Safely upgrade an existing kube-hetzner-managed cluster with Terraform/OpenTofu and Kubernetes runtime proof.

## Use When

- A user asks to upgrade a live kube-hetzner cluster.
- A module version bump must be applied to an existing cluster.
- K3s should move to a newer channel or explicit version.
- Provider/module state must be reconciled without recreating live nodes.
- The user asks whether the cluster is HA before or during an upgrade.
- The user wants to replace nodes because of suspected compromise, malware, bad host state, server type deprecation, or architecture/capacity migration.

## Hard Rules

- Do not print or commit secrets. Never commit kubeconfigs, `*.tfstate`, `*.tfvars`, local env files, plan files, or `.terraform/`.
- Use the IaC runner already used by the target root. Examples below use `terraform`; substitute `tofu` only if the target root already uses OpenTofu.
- Never let a module refactor recreate live servers, networks, load balancers, volumes, or primary IPs by accident. If a plan shows replacement/destruction, stop and root-cause it.
- Upgrade module convergence and K3s versions as separate phases.
- Upgrade K3s one minor at a time unless the operator has explicit upstream proof that skipping minors is safe for that exact version span.
- If host compromise or malware is in scope, prefer immutable node replacement over in-place package updates or reboots. Updates patch software; fresh nodes remove old-host persistence.
- Respect kube-hetzner nodepool lifecycle rules: only add/remove nodepools at the end of each list, set old pools to `count = 0` before retiring them, do not rename a non-zero pool, and keep the first control-plane nodepool at count >= 1 unless the module/root has deliberately modeled a safe replacement topology.
- Do not use `k3s server --cluster-reset` during healthy quorum replacement. It is a lost-quorum disaster recovery tool, not a normal control-plane migration primitive.
- Treat operator firewall access as temporary. If access is opened for maintenance, close it and prove closure before reporting done.
- Keep final proof concrete: Terraform convergence, node versions, upgrade plans complete, workloads healthy, API ready, ingress/LB healthy, and app readiness healthy.

## Inputs To Establish

- Terraform root path and backend type.
- Current module source/version and target module version/commit.
- Current K3s node versions and target channel/version.
- Kubeconfig/API access path.
- Cluster topology: control-plane count, etcd membership, agent pools, autoscaler pools, ingress/load balancer.
- HA risks: singleton StatefulSets, attached volumes, PodDisruptionBudgets, critical workloads without replicas.
- Stateful data safety: CSI/Longhorn/PV attachment, backup/snapshot path, app-specific flush commands, and post-move data integrity checks.
- Threat model: ordinary upgrade/patching vs distrust of existing hosts. This changes the correct workflow.
- Health checks: Kubernetes API readiness, ingress/load-balancer health, and at least one application-level readiness URL or command.
- Maintenance constraints and rollback expectations.
- Temporary access model: SSH/Kubernetes API firewall source rules, VPN/bastion access, or control-plane LB exposure.

## Preflight

```bash
cd <terraform-root>
git status --short --branch
git pull origin <default-branch>

# Confirm local secret/state files are ignored or outside git.
git ls-files | rg '(^|/)(.*kubeconfig.*|.*\.tfstate(\.backup)?|\.terraform/|.*\.tfvars|.*\.auto\.tfvars|\.terraform\.local\.env)$' || true

# Backup state without printing it. Prefer a directory outside the repo.
RUN_DIR="${KUBE_HETZNER_UPGRADE_RUN_DIR:-${TMPDIR:-/tmp}/kube-hetzner-upgrade-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$RUN_DIR"
terraform state pull > "$RUN_DIR/terraform.tfstate.before.json"

kubectl --kubeconfig <kubeconfig> get nodes -o wide
kubectl --kubeconfig <kubeconfig> get deploy,sts,pdb -A
kubectl --kubeconfig <kubeconfig> get pods -A -o wide
kubectl --kubeconfig <kubeconfig> get --raw='/readyz?verbose'
```

If there are singleton stateful workloads or strict PDBs, decide upgrade behavior before any apply:

- `system_upgrade_use_drain = true`: safer for replicated stateless workloads, but can stall or move singleton stateful workloads.
- `system_upgrade_use_drain = false`: cordons instead of draining; useful when a drain would cause worse downtime or volume attach churn. Existing pods remain until the node service restarts.
- `system_upgrade_enable_eviction = false`: only relevant when draining; can unstick upgrades blocked by PDBs, but may delete pods directly.

If operator access is normally closed, open it through the target root's local, ignored variables only. Keep source CIDRs narrow, usually `/32` or `/128`, and plan/apply the open/close firewall deltas separately from node changes.

## Phase 1: Module Convergence

Update only module/provider settings first. Do not change the K3s channel in the same plan unless unavoidable.

```bash
cd <terraform-root>
terraform init -upgrade -input=false
terraform fmt -check -diff
terraform validate
terraform plan -input=false -parallelism=1 -out=module-upgrade.tfplan
```

Review the plan before applying.

Proceed only if the plan is explainable and does not unexpectedly destroy or replace live infrastructure.

```bash
terraform apply -input=false -parallelism=1 module-upgrade.tfplan
terraform plan -input=false -parallelism=1 -detailed-exitcode
```

If the module changed resource ownership or addresses:

- Back up state again.
- Prefer `terraform import`, `terraform state mv`, or module-supported moved blocks over recreation.
- Migrate one live resource at a time.
- Re-run `terraform plan` after every state operation.
- Do not apply broad plans while state addresses are still ambiguous.

## Phase 2: K3s Upgrade

Determine current and target minors:

```bash
kubectl --kubeconfig <kubeconfig> get nodes -o wide
```

For each minor step:

1. Update `initial_k3s_channel` or `install_k3s_version`.
2. Keep upgrade drain/eviction settings aligned with the HA risk assessment.
3. Plan and apply serially.
4. Wait for system-upgrade plans and nodes.
5. Run runtime checks before proceeding to the next minor.

```bash
terraform fmt -check -diff
terraform validate
terraform plan -input=false -parallelism=1 -out=k3s-<target-minor>.tfplan
terraform apply -input=false -parallelism=1 k3s-<target-minor>.tfplan

kubectl --kubeconfig <kubeconfig> -n system-upgrade get plans,jobs,pods -o wide
kubectl --kubeconfig <kubeconfig> get nodes -o wide
kubectl --kubeconfig <kubeconfig> get deploy,sts -A
kubectl --kubeconfig <kubeconfig> get --raw='/readyz?verbose'
```

Treat these as stop conditions:

- A node is not `Ready`.
- Server or agent upgrade plans are not complete after a reasonable wait.
- Terraform shows unexpected drift.
- Public ingress or application readiness fails repeatedly.
- A singleton stateful workload is stuck on volume attach/detach or unavailable.

## Phase 3: Immutable Node Replacement

Use this phase instead of in-place patching when old hosts are distrusted or when server types/architectures must be replaced cleanly.

For the full field-proven workflow, read [references/immutable-node-replacement.md](references/immutable-node-replacement.md). It covers nodepool plan shape, Hetzner capacity checks, load-balancer target proof, etcd snapshots/membership, attached-volume StatefulSet moves, Redis/Dragonfly-compatible verification, and final firewall closure.

### Capacity And Plan Shape

Before editing nodepools, verify replacement capacity and avoid deprecated/unavailable types:

```bash
hcloud server-type describe <candidate-type>
hcloud datacenter describe <candidate-datacenter-or-location>
```

Prefer appending a new nodepool with a new name and setting the old pool to `count = 0` after evacuation. Do not remove middle-of-list pools. Kube-hetzner allocates nodepool subnets/IPs by list position, so FILO discipline prevents accidental address churn.

### Stateful Workloads And Volumes

For each singleton StatefulSet or attached-volume workload:

1. Identify PVCs, PVs, storage class, volume affinity/location, and current node.
2. Take an application-consistent backup or snapshot before moving the pod.
3. Run the app-specific flush command if one exists, for example a Redis-compatible `SAVE`.
4. Scale the StatefulSet down, wait for CSI/Longhorn detach, then scale it up on a fresh node.
5. Verify with application-level integrity checks, not only Kubernetes readiness.

Example skeleton:

```bash
kubectl --kubeconfig <kubeconfig> -n <ns> get sts,pvc,pv -o wide
kubectl --kubeconfig <kubeconfig> -n <ns> exec <pod> -- <app-flush-or-backup-command>
kubectl --kubeconfig <kubeconfig> -n <ns> scale sts/<name> --replicas=0
kubectl --kubeconfig <kubeconfig> get volumeattachments
kubectl --kubeconfig <kubeconfig> -n <ns> scale sts/<name> --replicas=1
kubectl --kubeconfig <kubeconfig> -n <ns> exec <pod> -- <app-integrity-check>
```

### Worker Replacement

1. Append a fresh `agent_nodepools` entry with available server types, enough capacity, and the same labels/taints semantics required by workloads.
2. Plan/apply with only the new workers added.
3. Wait for new workers to be `Ready`.
4. Verify ingress/load-balancer targets include healthy new workers.
5. Move or reschedule stateful workloads deliberately.
6. Cordon and drain old workers with flags appropriate to the workloads.
7. Scale the old worker pool to `count = 0`, apply, and verify the cloud servers are gone.
8. Verify final load-balancer targets reference only fresh workers.

Do not rely on Kubernetes rescheduling alone for attached-volume singletons; explicitly manage detach/attach and verify the data plane.

### Control-Plane Replacement

Maintain etcd quorum at every step.

1. Confirm an odd healthy etcd/control-plane count before starting.
2. Take an etcd snapshot from a healthy control-plane node and copy or verify it outside the node being replaced.
3. Add fresh control-plane voters before removing old voters.
4. Remove only one old control-plane server at a time.
5. Delete the matching Kubernetes Node object after server removal if it remains.
6. Verify etcd membership after each removal.

Example skeleton:

```bash
ssh root@<healthy-control-plane> "k3s etcd-snapshot save --name pre-cp-replace-$(date -u +%Y%m%dT%H%M%SZ)"
kubectl --kubeconfig <kubeconfig> get nodes -l node-role.kubernetes.io/etcd=true -o wide
kubectl --kubeconfig <kubeconfig> get --raw='/db/info' || true
```

If the old first control-plane server type cannot be recreated, do not keep hammering Terraform against exhausted capacity. Append a new control-plane pool with available capacity, join clean voters, then retire the old pool according to the root/module constraints. If the root cannot safely model first-pool `count = 0`, keep a small non-serving placeholder or use state surgery only after proving the exact resource-address impact.

### Secret And Incident Boundary

Immutable replacement reduces old-host persistence risk. It does not prove secrets were not exfiltrated before replacement. If the incident is confirmed rather than precautionary, report that credential rotation, image provenance review, and workload redeploy from trusted artifacts remain required.

## Live Health Checks

Use checks appropriate for the cluster. Examples:

```bash
# API readiness
kubectl --kubeconfig <kubeconfig> get --raw='/readyz?verbose'

# Workload readiness
kubectl --kubeconfig <kubeconfig> get deploy,sts,pods -A -o wide

# Ingress/LB readiness, if hcloud is configured
hcloud load-balancer describe <load-balancer-name>

# Application readiness, if available
for i in 1 2 3 4 5; do
  curl -sS -o /dev/null -w "$i %{http_code}\n" <readiness-url>
  sleep 2
done
```

Old `system-upgrade` pods may show `Unknown` after node restarts while their jobs are `Complete`. Treat that as cleanup noise only if the plans are complete, all nodes are ready, and workloads are healthy.

## Firewall Closure Proof

If SSH/API access was opened for the run, close it in its own final Terraform plan after cluster health is proven.

```bash
# Remove local ignored access tfvars/env overrides first, then:
terraform plan -input=false -parallelism=1 -out=operator-close.tfplan
terraform apply -input=false -parallelism=1 operator-close.tfplan
rm -f operator-close.tfplan
terraform plan -input=false -parallelism=1 -detailed-exitcode
```

Then verify:

- Cloud firewall rules no longer include temporary SSH/API source CIDRs.
- Public `kubectl` from the closed source fails or times out, unless the cluster intentionally exposes the API through a control-plane LB.
- Public ingress/application readiness still succeeds.

## Final Report

Report:

- Module version/source before and after.
- K3s version/channel before and after.
- HA assessment: control plane/etcd count, agent pools, ingress replicas, application replicas, and singleton stateful risks.
- Terraform proof: `fmt`, `validate`, final `plan -detailed-exitcode` result.
- Kubernetes proof: node versions, upgrade plans complete, API readyz, deployments/statefulsets ready.
- Ingress/app proof: load balancer target health and application readiness.
- Immutable replacement proof, if used: old servers gone, replacement nodes Ready, etcd membership contains only intended voters, stateful data integrity checks passed, and firewall access is closed again.
- Any incident during the upgrade and the corrective setting or action.
- Remaining risks and the exact condition that would make them safe.

## Git Hygiene

Before committing:

```bash
git status --short
git ls-files | rg '(^|/)(.*kubeconfig.*|.*\.tfstate(\.backup)?|\.terraform/|.*\.tfvars|.*\.auto\.tfvars|\.terraform\.local\.env)$' || true
git diff --cached --check
```

If a secret-bearing local file is tracked, remove it from the index with `git rm --cached <path>`, add an ignore rule, and keep the local file only if it is still operationally needed.
