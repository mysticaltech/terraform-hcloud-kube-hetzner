# Day-2 Operations

Routine access, scaling, and cluster-management procedures live here. For incident diagnosis, certificate recovery, and broken nodes, use [Troubleshooting](troubleshooting.md).

[Documentation index](index.md)

## Security

### MicroOS / Leap Micro Hardening
- **Immutable base OS:** Leap Micro and MicroOS use transactional updates and read-only system partitions by default, reducing host drift and limiting persistence for unauthorized changes.
- **Reduced host surface:** Cluster nodes are treated as appliance-style Kubernetes hosts; operational changes should flow through Terraform and Kubernetes manifests rather than ad-hoc host mutation.
- **SELinux integration:** The module includes SELinux handling for K3s/RKE2 bootstrap paths, with explicit controls and troubleshooting guidance for strict environments.

### Network Isolation
- **Default deny posture for cluster ingress:** Firewall rules are explicit and can be narrowed to trusted source ranges (`myipv4`/allowlists) for SSH and Kubernetes API exposure.
- **Private cluster topology support:** You can run with private networking and NAT routing patterns to minimize directly exposed node interfaces.
- **Load balancer boundary controls:** Control plane and ingress load balancer exposure can be restricted and combined with firewall source controls to reduce public attack surface.

#### Handoff an existing firewall attachment

Kube-hetzner manages effective server firewall IDs through `hcloud_server.firewall_ids`. Do not leave a standalone `hcloud_firewall_attachment` managing the same server/firewall relationship.

1. Back up state: `terraform state pull > terraform-state-before-firewall-handoff.json`.
2. Add the firewall ID to the appropriate module `extra_firewall_ids` scope, but do not apply yet.
3. Remove only the old attachment resource from Terraform state: `terraform state rm '<old_hcloud_firewall_attachment_address>'`. This is state-only; it does not detach the remote Firewall.
4. Remove the old resource block, run `terraform plan`, and verify the module retains the same firewall ID without a detach.
5. Apply only after the plan shows one owner and no unrelated replacement.

If one attachment resource owns multiple servers or uses label selectors, split the ownership first. Hetzner allows five Firewalls per server; kube-hetzner's own Firewall consumes one slot, leaving four unique extras across global, nodepool, and node scopes.

### RKE2 Security Posture
- **CNCF-conformant distribution option:** RKE2 is supported as a first-class Kubernetes distribution choice in this module.
- **Compliance-oriented operation:** RKE2 is designed for hardened, regulated environments and supports CIS-focused deployment patterns.
- **Certification visibility:** For current security certifications/compliance mappings, reference the upstream RKE2 documentation and release notes as authoritative sources.

## Connecting to the cluster

View cluster details:
```sh
terraform output kubeconfig
terraform output -json kubeconfig | jq
```

### Connect via SSH

```sh
ssh root@<control-plane-ip> -i /path/to/private_key -o StrictHostKeyChecking=no
```

`firewall_ssh_source` defaults to `["0.0.0.0/0", "::/0"]` so initial access is not locked out. Restrict it to `myipv4` or trusted CIDRs as soon as SSH access is proven. For CI/CD runners, include the runner CIDRs. See [SSH docs](ssh.md#firewall-ssh-source-and-changing-ips) for dynamic IP handling.

### Connect via Kube API

```sh
kubectl --kubeconfig clustername_kubeconfig.yaml get nodes
```

Or set it as your default:
```sh
export KUBECONFIG=/<path-to>/clustername_kubeconfig.yaml
```

> **Tip:** If `create_kubeconfig = false`, generate it manually: `terraform output --raw kubeconfig > clustername_kubeconfig.yaml`

---

## CNI Options

Default is **Flannel**. Switch by setting `cni_plugin` to `"calico"` or `"cilium"`.

### Cilium Configuration

Customize via `cilium_values` with [Cilium helm values](https://github.com/cilium/cilium/blob/master/install/kubernetes/cilium/values.yaml).

| Feature | Variable |
|---------|----------|
| Full kube-proxy replacement | `enable_kube_proxy = false` |
| Hubble observability | `cilium_hubble_enabled = true` |

Access Hubble UI:
```sh
kubectl port-forward -n kube-system service/hubble-ui 12000:80
# or with Cilium CLI:
cilium hubble ui
```

---

## Scaling

### Manual Scaling

Adjust `count` in any nodepool and run `terraform apply`. Constraints:

- First control-plane nodepool minimum: **1**
- Drain the exact nodes selected by the plan before removing them: `kubectl drain <node-name> --ignore-daemonsets`
- Only remove nodepools from the **end** of the list
- Rename nodepools only when count is **0**

**Advanced:** Replace `count` with a `nodes` map for individual node control—see `kube.tf.example`.

### Resizing or Retiring Longhorn Agents

Terraform does not automatically cordon, drain, or evacuate Longhorn replicas before agent deletion or a `server_type` update. The hcloud provider powers off a running server before changing its type, even when the plan says **update in place**. A pool-wide type change can interrupt several storage nodes together. `terraform apply -parallelism=1` limits concurrent Terraform operations but does not wait for Kubernetes readiness, workload recovery, or Longhorn replica health between nodes. Kubernetes upgrade drain settings and Kured do not wrap these Terraform operations.

Resizing is limited to the same CPU architecture and a target plan whose disk can hold the server's current disk. `keep_disk = true` avoids enlarging the disk during an upscale; it does not shrink an already enlarged disk, preserve it after server deletion, or enable an Arm/x86 transition. See the [Hetzner rescale constraints](https://docs.hetzner.com/cloud/servers/faq/) and [provider resize implementation](https://github.com/hetznercloud/terraform-provider-hcloud/blob/v1.70.0/internal/server/resource.go).

For permanent retirement or an incompatible hardware move, use an operator-controlled migration:

1. Verify independent, restorable backups. Add the replacement storage pool at the end of the list without changing the old pool's positions or names. Apply that addition separately and wait for its Kubernetes nodes and Longhorn disks to be ready and schedulable, with enough capacity and suitable replica placement to evacuate the old nodes.
2. Review a plan for a **single** old node's removal. Count-based pools remove the highest index first; match the planned server ID/name to the Kubernetes node, rather than choosing an arbitrary node to drain. Keep emptied middle pools at `count = 0`. Stop if unrelated servers, networks, or volumes would be removed or replaced.
3. Cordon that node, disable its Longhorn scheduling, and request replica eviction in the Longhorn UI. Wait until all its replicas and backing images have moved off every disk, affected volumes have their required healthy replicas elsewhere, and workloads have a viable destination. The [Longhorn graceful removal guide](https://longhorn.io/docs/1.12.1/nodes-and-volumes/nodes/graceful-node-removal/) describes the checks. Insufficient capacity, anti-affinity constraints, or faulted volumes are reasons to stop, not skip eviction.
4. Drain the node with the Kubernetes eviction API, for example `kubectl drain <node-name> --ignore-daemonsets --timeout=10m`. If it fails or times out, **do not apply the removal**. Resolve the blocking workload/PDB or storage condition first. Do not use `--disable-eviction` to bypass PDBs; `--force` permits unmanaged pods but does not bypass PDBs. Deleting `emptyDir` data requires a separate, deliberate decision. A successful drain alone does not copy local-path data or prove Longhorn disk evacuation.
5. Only after those gates, deliberately disable applicable delete protection while the resources still exist in the configuration, apply that protection change separately, and re-plan the single-node removal. The module-managed Hetzner Volume for that removed agent key is deleted too; migrate the data before allowing this. Apply the reviewed removal, then clean up any stale Kubernetes Node and Longhorn Node metadata after the server is gone, following Longhorn's prerequisites. Wait for workload recovery and required Longhorn replica health before starting another node.

Longhorn's default `block-if-contains-last-replica` drain policy blocks when the last healthy replica would be disrupted; it is not automatic evacuation. `block-for-eviction-if-contains-last-replica` evacuates replicas without a healthy counterpart, not every replica. `block-for-eviction` evacuates all replicas, but still needs viable destinations. Inspect the actual setting and placement, not just the configured replica count. See [Longhorn drain policies](https://longhorn.io/docs/1.12.1/references/settings/#node-drain-policy).

For an in-place resize, drain only the node being changed, resize it, verify it returns Ready with its expected storage mounted, then uncordon it and wait for workload and replica recovery before proceeding. An existing `nodes` map can express per-node `server_type` overrides while leaving other nodes unchanged. Do not convert a count-based pool to a map blindly: node names and other derived configuration can change, so first verify the resulting plan. This remains a manual maintenance procedure, not a module-managed rolling resize.

Two existing deletion safeguards are independent: `delete_protection = true` on an agent pool protects its servers; `enable_delete_protection = { volume = true }` protects managed Hetzner Volumes. Current hcloud provider deletion paths do not automatically lift those protections ([upstream tracking issue](https://github.com/hetznercloud/terraform-provider-hcloud/issues/1206)). Server protection alone does not protect its volume, and neither option blocks resize poweroff or makes a whole apply/destroy atomic. The provider can detach a protected volume before its deletion is rejected. The provider version matters because the module specifies a minimum, not an exact pin.

Managed Longhorn Volumes follow the agent resource key. Removing that key or removing its dedicated-volume configuration plans volume deletion; a same-key server replacement does not necessarily replace the Volume, so inspect both resources. A preserved or externally managed disk is not a guarantee that Longhorn will reuse its replicas on a different node identity. Stable storage ownership and automatic drain/resize orchestration are not implemented; [issue #2299](https://github.com/mysticaltech/terraform-hcloud-kube-hetzner/issues/2299) tracks this gap.

### Autoscaling

Enable with `autoscaler_nodepools`. Powered by [Cluster Autoscaler](https://github.com/kubernetes/autoscaler).

> ⚠️ Autoscaled nodes use a snapshot from the initial control plane. Ensure disk sizes match.
> Longhorn storage should stay on static agent nodepools. Autoscaled Longhorn volumes require a write-capable Hetzner token in node user-data and leave detached volumes behind on scale-down.

Cluster Autoscaler will not scale down nodes that run pods with local storage unless explicitly configured to do so. For disposable local data, add `--skip-nodes-with-local-storage=false` to `cluster_autoscaler_extra_args` or annotate individual pods with `cluster-autoscaler.kubernetes.io/safe-to-evict: "true"`.

Hetzner Cloud limits server `user_data` to 32 KiB. Kube-hetzner compresses its large autoscaler cloud-init payloads and rejects an oversized rendered node configuration during `terraform plan`. The v3.2 release canary measured 29,520 bytes before user customizations, so keep custom payloads small and treat the plan guard as a hard API limit. If that guard fails, reduce custom `agent_nodes_custom_config`, `kubelet_config`, `registries_config`, node annotations, or extra bootstrap commands instead of bypassing the limit.

#### Repair existing autoscaler update services

New autoscaler nodes restore `health-checker.service` after first boot and match `transactional-update.timer` to `automatically_upgrade_os`. Existing static nodes are repaired automatically on the next apply, including a persistent post-cloud-init repair for legacy payloads that mask the checker again on every boot. Existing autoscaler nodes retain their original cloud-init, so repair them in place one at a time over SSH:

```sh
systemctl unmask health-checker.service
systemctl enable health-checker.service
systemctl is-enabled --quiet health-checker.service

# automatically_upgrade_os = true
systemctl enable --now transactional-update.timer
systemctl is-enabled --quiet transactional-update.timer
systemctl is-active --quiet transactional-update.timer

# automatically_upgrade_os = false: use this instead of the three timer commands above
systemctl disable --now transactional-update.timer
```

Do not start `health-checker.service` manually during the same boot; enabling it restores the next-boot rollback check without evaluating an already-running system as a fresh boot. Autoscaler servers can be selected in HCloud by `hcloud/node-group=<cluster-prefix><pool-name>`.

## Upgrade Repairs

### Repair an existing Hetzner metadata route

The v3.2 metadata fix runs during cloud-init on new and replaced nodes. It changes only a directly connected public-gateway path; private-only nodes and indirect routes remain untouched. On an existing affected node, first confirm the failure:

```sh
ip route get 169.254.169.254
curl --fail --max-time 5 http://169.254.169.254/hetzner/v1/metadata/instance-id
```

If the selected `/32` route points directly at the private gateway and metadata fails, either repair the active public NetworkManager profile to persist `169.254.169.254/32` through `172.31.1.1` with metric `100`, then `nmcli device reapply` and rerun both checks, or replace nodes one at a time after draining them. Do not force this route on NAT/private-only nodes or when `172.31.1.1` is reached through another gateway.

### Migrate an existing K3s Calico IPPool

`calico_values` is a K3s-only strategic-merge patch. Applying or changing it rolls the cluster-wide `calico-node` DaemonSet, so use a maintenance window and verify every Calico pod and node network before continuing. The patch does not mutate an existing IPPool CIDR. Follow Calico's controlled IPPool migration: create the replacement pool, disable allocation from the old pool, move workloads gradually, verify routing and policy, and remove the old pool only after no workload IPs use it. Never delete the active default pool as a shortcut. RKE2 uses its bundled Calico chart and ignores `calico_values`.

### Rotate Secrets encryption keys

Kube-hetzner rejects in-place replacement or disablement of its Terraform-managed one-key EncryptionConfiguration because either can make existing Secrets unreadable. This release does not provide an ownership handoff or multi-key rotation input. Keep the original Terraform state and key. If rotation is required, the supported path is a new cluster with a new key followed by a controlled workload and Secret migration; do not manually replace the file and then continue applying the same configuration.

---

## High Availability

| Control Planes | Recommendation |
|----------------|----------------|
| 3+ (odd numbers) | Full HA with quorum maintenance |
| 2 | Disable auto OS upgrades, manual maintenance |
| 1 | Development only, disable auto upgrades |

See [Rancher's HA documentation](https://rancher.com/docs/k3s/latest/en/installation/ha-embedded/).

---

## Dedicated Servers

Integrate Hetzner Robot servers via [the dedicated server guide](add-robot-server.md).

---

## Adding Extras

Use [Kustomize](https://kustomize.io) for additional deployments:

1. Create a source folder (default: `extra-manifests`) with your `kustomization.yaml.tpl` and manifests.
2. Configure one or more ordered sets with `user_kustomizations`.
3. Each set supports template parameters, optional pre-commands, and post-commands.
4. Sets are applied sequentially with `kubectl apply -k`.
