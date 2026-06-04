# Immutable Node Replacement Reference

Use this reference when a kube-hetzner cluster must replace hosts rather than merely patch them. This is the correct path when the threat model includes possible host compromise, malware, corrupted node state, architecture migration, retired server types, or exhausted Hetzner capacity for the current type.

## Core Security Model

- In-place OS upgrades and reboots patch known software state. They do not prove that a previously compromised host is clean.
- Immutable replacement removes old-host persistence by creating fresh servers from trusted images and rejoining the cluster.
- Node replacement does not prove credentials were not exfiltrated before replacement. For a confirmed incident, follow with credential rotation, workload redeploy from trusted artifacts, image/provenance review, and audit-log review.
- Keep temporary operator access narrow and short-lived. Open SSH/API firewall access only for the maintenance window, then close it in a separate final Terraform apply and prove it is closed.

## Safety Preflight

Establish current truth before editing Terraform:

```bash
cd <terraform-root>
git status --short --branch

RUN_DIR="${KUBE_HETZNER_REPLACE_RUN_DIR:-${TMPDIR:-/tmp}/kh-node-replace-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$RUN_DIR"

terraform state pull > "$RUN_DIR/terraform.tfstate.before.json"
terraform plan -input=false -parallelism=1 -detailed-exitcode

kubectl --kubeconfig <kubeconfig> get nodes -o wide
kubectl --kubeconfig <kubeconfig> get pods -A -o wide
kubectl --kubeconfig <kubeconfig> get deploy,sts,pdb,pvc -A
kubectl --kubeconfig <kubeconfig> get volumeattachments
kubectl --kubeconfig <kubeconfig> get --raw='/readyz?verbose'
hcloud server list -o columns=id,name,status,type,location,ipv4
```

Capture these facts in notes:

- control-plane and etcd member count
- worker count, locations, architectures, and server types
- ingress/load-balancer target set
- singleton StatefulSets and their nodes
- PVC/PV/storage class/volume IDs and volume locations
- application readiness URL or command
- current firewall exposure for SSH and Kubernetes API

## Hetzner Capacity And Type Selection

Do not assume a server type is still placeable because it exists in docs or because old nodes of that type are running. Verify availability, then let a real create/apply be the capacity proof.

```bash
hcloud server-type describe <candidate-type>
hcloud datacenter describe <datacenter>
hcloud location describe <location>
```

Operational rules:

- If Terraform/HCloud returns `resource_unavailable`, stop hammering that exact type/datacenter. Pick another available current-generation type or location within the same network region.
- Respect storage locality. Hetzner CSI volumes are location-bound; a singleton using a volume in `fsn1` cannot move to a worker in another location without a migration plan.
- Prefer current-generation types over deprecated types. Keep architecture migration explicit because workloads/images may be architecture-sensitive.
- For mixed architecture clusters, verify critical images are multi-arch before moving workloads.

## Terraform Plan Shape

Kube-hetzner nodepool lists are stateful. Treat list order as infrastructure identity.

- Append replacement nodepools at the end of `control_plane_nodepools` or `agent_nodepools`.
- Do not remove middle-of-list nodepools. Set retired pools to `count = 0` unless they are safely removable from the end.
- Rename a nodepool only when its count is `0`.
- Drain and cordon nodes before reducing a pool count.
- Split changes into small plans:
  - add fresh workers
  - move stateful workloads
  - remove old workers
  - add fresh control planes
  - remove old control planes one at a time
  - close firewall access
- If a plan shows unexpected destruction/replacement beyond the intended nodepool phase, stop and root-cause before applying.

For the first control-plane nodepool:

- The upstream module documents the first control-plane nodepool minimum as `1` after initial create.
- The first server has cluster-init semantics. Do not blindly recreate the old first server with `cluster-init` in an existing healthy cluster.
- If the old first server type is unavailable, add clean control-plane voters first. Retire the old pool only with a root/module shape that has been planned and proven. If needed, keep a minimal placeholder rather than forcing unsafe state churn.

## Worker Replacement

Goal: fresh workers take traffic before old workers disappear.

1. Append a new `agent_nodepools` entry with enough capacity.
2. Apply the add-only plan.
3. Wait for new workers to become `Ready`.
4. Verify ingress controllers and critical workloads can run on the new pool.
5. Verify load-balancer targets include healthy new workers.

Useful checks:

```bash
kubectl --kubeconfig <kubeconfig> get nodes -o wide
kubectl --kubeconfig <kubeconfig> get pods -A -o wide
hcloud load-balancer describe <ingress-lb-name>
curl -sS -o /dev/null -w '%{http_code}\n' <app-readiness-url>
```

Then evacuate old workers:

```bash
kubectl --kubeconfig <kubeconfig> cordon <old-worker>
kubectl --kubeconfig <kubeconfig> drain <old-worker> --ignore-daemonsets --delete-emptydir-data
```

Adjust drain flags for the workload. For attached-volume singletons, handle the StatefulSet explicitly before draining the node. After evacuation, set the old worker pool to `count = 0`, apply, and verify old cloud servers are gone.

Final worker proof:

- old worker servers absent from `hcloud server list`
- no old worker node objects remain, or stale objects are deliberately deleted
- load balancer targets only fresh workers
- all target health checks are healthy
- application readiness succeeds repeatedly

## StatefulSet And Attached Volume Replacement

Do not trust generic rescheduling for singleton data stores. Treat data movement as its own phase.

Inventory:

```bash
kubectl --kubeconfig <kubeconfig> -n <ns> get sts,pod,pvc -o wide
kubectl --kubeconfig <kubeconfig> get pv <pv-name> -o yaml
kubectl --kubeconfig <kubeconfig> get volumeattachments
hcloud volume describe <volume-id>
```

Before movement:

1. Identify the node currently running the pod.
2. Identify PVC, PV, storage class, volume handle, volume location, and attachment.
3. Confirm at least one fresh worker exists in the same volume location.
4. Run an application-consistent flush/snapshot.
5. Export a local backup if practical and compute a checksum.

Redis/Dragonfly-compatible example:

```bash
kubectl --kubeconfig <kubeconfig> -n <ns> exec <pod> -- redis-cli SAVE
kubectl --kubeconfig <kubeconfig> -n <ns> exec <pod> -- tar -C /data -czf - . > "$RUN_DIR/<name>-data.tgz"
shasum -a 256 "$RUN_DIR/<name>-data.tgz"
```

Move:

```bash
kubectl --kubeconfig <kubeconfig> -n <ns> scale sts/<name> --replicas=0
kubectl --kubeconfig <kubeconfig> get volumeattachments
hcloud volume describe <volume-id>
kubectl --kubeconfig <kubeconfig> -n <ns> scale sts/<name> --replicas=1
kubectl --kubeconfig <kubeconfig> -n <ns> rollout status sts/<name>
```

Wait for detach before expecting attach to succeed elsewhere. If the pod is pending because a volume is still attached to the old node, do not force-delete infrastructure blindly; inspect `VolumeAttachment`, CSI controller logs, and the cloud volume attachment state.

Post-move verification must be application-specific. Kubernetes `Running` is not enough.

Redis/Dragonfly-compatible checks:

```bash
kubectl --kubeconfig <kubeconfig> -n <ns> exec <pod> -- redis-cli PING
kubectl --kubeconfig <kubeconfig> -n <ns> exec <pod> -- redis-cli DBSIZE
kubectl --kubeconfig <kubeconfig> -n <ns> exec <pod> -- redis-cli INFO keyspace
```

Interpretation:

- stable persistent DB/key counts should match expectations
- volatile DBs with TTL/session/cache data may drift during maintenance
- a successful pod restart without data checks is incomplete proof

## Control-Plane Replacement

Goal: never lose etcd quorum, and prove final membership contains only clean intended voters.

Preflight:

```bash
kubectl --kubeconfig <kubeconfig> get nodes -o wide
kubectl --kubeconfig <kubeconfig> get nodes -l node-role.kubernetes.io/etcd=true -o wide
kubectl --kubeconfig <kubeconfig> get --raw='/db/info' || true
```

Take an etcd snapshot from a healthy control-plane node before membership changes:

```bash
SNAP="pre-control-plane-replace-$(date -u +%Y%m%dT%H%M%SZ)"
ssh root@<healthy-control-plane-ip> "k3s etcd-snapshot save --name $SNAP"
ssh root@<healthy-control-plane-ip> "ls -lh /var/lib/rancher/k3s/server/db/snapshots | tail"
scp root@<healthy-control-plane-ip>:/var/lib/rancher/k3s/server/db/snapshots/${SNAP}* "$RUN_DIR/"
shasum -a 256 "$RUN_DIR"/${SNAP}*
```

Replacement sequence:

1. Add fresh control planes first.
2. Wait for each to become `Ready`.
3. Verify each joins as an etcd/control-plane node.
4. Remove one old control-plane server.
5. Delete the stale Kubernetes Node object if it remains.
6. Verify `/db/info` no longer lists the old etcd member.
7. Repeat one old voter at a time.

Useful checks:

```bash
kubectl --kubeconfig <kubeconfig> get nodes -o wide
kubectl --kubeconfig <kubeconfig> get --raw='/db/info' || true
kubectl --kubeconfig <kubeconfig> get --raw='/readyz?verbose'
```

If `/db/info` is unavailable through the client path, inspect membership from a healthy control-plane node with the local K3s tooling available in that cluster. Do not proceed to the next old voter until membership is understood.

Quorum rules:

- Use odd etcd counts whenever possible.
- Add new voters before deleting old voters.
- Remove one old voter at a time.
- Keep a current snapshot outside the node being removed.
- `k3s server --cluster-reset` is only for lost-quorum disaster recovery. It is not a normal replacement step while quorum is healthy.

Final control-plane proof:

- exactly the intended fresh control-plane nodes are `Ready`
- `/db/info` or equivalent etcd-member check lists only the intended fresh voters
- API `/readyz` succeeds
- no old control-plane servers remain in HCloud
- final Terraform plan has no unexpected changes

## Load Balancer Target Proof

For clusters using a Hetzner load balancer, target health is separate from pod health.

```bash
hcloud load-balancer describe <load-balancer-name>
```

Verify:

- target servers are the fresh worker servers
- there are no old worker targets
- every service/listen port reports healthy
- label-selector targets resolve to the intended fresh servers
- app readiness over the public ingress still returns success

If the load balancer still targets old workers, inspect labels and the cloud-controller-manager reconciliation state before deleting more nodes.

## Firewall Closure

If temporary operator access was opened with local variables, remove it and apply closure separately.

```bash
rm -f <operator-access-local-tfvars> <open-plan-file>
terraform plan -input=false -parallelism=1 -out=operator-close.tfplan
terraform apply -input=false -parallelism=1 operator-close.tfplan
rm -f operator-close.tfplan
terraform plan -input=false -parallelism=1 -detailed-exitcode
```

Verify with the cloud firewall, not just Terraform:

```bash
hcloud firewall describe <cluster-firewall-name>
```

Expected proof:

- no temporary SSH source CIDR remains
- no temporary Kubernetes API source CIDR remains
- public `kubectl` from the closed source fails or times out, unless the API is deliberately exposed through a control-plane load balancer
- public application ingress still works

## Final Report Checklist

Report concrete evidence:

- before/after server inventory: names, types, locations, versions
- old servers gone from HCloud
- fresh workers/control planes Ready
- final etcd membership
- etcd snapshot name, size, and checksum if copied locally
- StatefulSet backup path/checksum if taken
- stateful application integrity checks
- load-balancer target list and health
- final app readiness result
- final Terraform `plan -detailed-exitcode`
- firewall closure proof
- remaining incident boundary: whether secret rotation or trusted redeploy is still required
