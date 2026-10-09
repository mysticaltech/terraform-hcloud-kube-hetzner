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
- Drain nodes before removing: `kubectl drain <node-name>`
- Only remove nodepools from the **end** of the list
- Rename nodepools only when count is **0**

**Advanced:** Replace `count` with a `nodes` map for individual node control—see `kube.tf.example`.

### Autoscaling

Enable with `autoscaler_nodepools`. Powered by [Cluster Autoscaler](https://github.com/kubernetes/autoscaler).

> ⚠️ Autoscaled nodes use the effective autoscaler OS snapshot. Ensure it fits every pool's server disk.
> Longhorn storage should stay on static agent nodepools. Autoscaled Longhorn volumes require a write-capable Hetzner token in node user-data and leave detached volumes behind on scale-down.

Cluster Autoscaler will not scale down nodes that run pods with local storage unless explicitly configured to do so. For disposable local data, add `--skip-nodes-with-local-storage=false` to `cluster_autoscaler_extra_args` or annotate individual pods with `cluster-autoscaler.kubernetes.io/safe-to-evict: "true"`.

Hetzner Cloud limits server `user_data` to 32 KiB. Kube-hetzner compresses its large autoscaler cloud-init payloads and rejects an oversized rendered node configuration during `terraform plan`. The v3.2 release canary measured 29,520 bytes before user customizations, so keep custom payloads small and treat the plan guard as a hard API limit. If that guard fails, reduce custom `agent_nodes_custom_config`, `kubelet_config`, `registries_config`, node annotations, or extra bootstrap commands instead of bypassing the limit.

#### Snapshot selection and rollback

`cluster_autoscaler_snapshot_selection = "id"` is the default: keep the selected snapshot while the autoscaler uses its numeric ID, or re-apply the autoscaler configuration before retiring it. With opt-in `"latest"`, each server create selects the newest available snapshot matching `<os>-snapshot=yes,kube-hetzner/os=<os>,kube-hetzner/k8s-distro=<distro>` and the server's actual architecture. The current Packer templates produce these labels for MicroOS and Leap Micro, with `selinux_package_to_install` selecting `k3s` or `rke2`. No additional Terraform/provider version is required; the pinned official autoscaler `v1.33.3` supports this selector contract. Verify custom autoscaler builds separately.

Only configured autoscaler architectures participate, including pools with `min_nodes = max_nodes = 0`. Do not set global `*_snapshot_id` pins for those OS/architecture pairs in `"latest"` mode; static-only architectures can remain pinned. Static nodes still use numeric plan-time IDs. A MicroOS legacy or partially labeled image cannot satisfy the selector.

Publish matching labels only after testing a new image: `"latest"` lets it reach new autoscaled nodes without a Terraform apply gate. Multiple matching snapshots are expected; the API's `created` time, not the `built-at` or `build-id` label, controls selection. Equal creation times have no guaranteed tie-breaker. Keep a known-good matching snapshot for each architecture. Deleting an older image is safe for future selector-based creates only while another compatible match remains; no match fails scale-up, and deletion during a create can still race the API request.

To roll back future creates, exclude the bad image from the selector (for example, remove its `<os>-snapshot=yes` label) and verify the newest remaining match for each architecture. This does not change or repair existing nodes, and an in-flight create may already have selected the bad image. Handle those nodes separately. Switching back to `"id"` pins the current plan-time selection, not automatically the previous good image; inspect the full plan before applying. Static nodes retain numeric IDs, and existing static servers ignore image changes rather than rebuilding automatically. Labels express operator intent, not image provenance: restrict snapshot/label write access in the HCloud project.

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
