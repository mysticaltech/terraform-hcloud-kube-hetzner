# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### ⚠️ v3.0.0 Upgrade Notes

This is the v3 major-release line. Before upgrading from any `v2.x` release:

1. Pin and review:
   - Set module version to `3.0.0` (or your targeted v3 tag).
   - Read `docs/v2-to-v3-migration.md` and `MIGRATION.md` end-to-end.
2. Run safe upgrade flow:
   - `terraform init -upgrade`
   - `terraform plan`
   - Apply only after reviewing all resource actions.
3. If you use private-network NAT routers created before v2.19.0, check for primary IP replacement and perform state migration first (see migration notes).
4. Networking behavior changed in v3: nodepool `network_id` is active and control-plane attachment behavior is explicit. Cilium public overlay remains an experimental preview gated by `enable_experimental_cilium_public_overlay` until live cross-network datapath validation passes. Prefer blue/green migration for custom/private/Robot/multinetwork topologies; do not apply plans that unexpectedly destroy or recreate network subnets.
5. New clusters and normal in-place v2 upgrades use `network_subnet_mode = "per_nodepool"`, matching the released v2 subnet topology. Optional `network_subnet_mode = "shared"` is for new clusters or intentional topology changes only.
6. Several public inputs were renamed or removed in v3 to clean up the module contract. See `MIGRATION.md` for the old-to-new variable map, especially the inverted positive booleans (`enable_hetzner_csi`, `enable_placement_groups`, `allow_inbound_icmp`, `enable_kube_proxy`, `enable_network_policy`, `enable_selinux`, nodepool `enable_public_ipv4`/`enable_public_ipv6`, autoscaler public-IP flags, and load-balancer enable flags).

#### Version Requirements

- Minimum Terraform/OpenTofu version: `1.10.1`
- Minimum hcloud provider version: `1.62.0`

### 💥 Breaking Changes

- **Public input cleanup** - Renamed Kubernetes distribution, install, audit, load-balancer, Robot, CCM, WireGuard, firewall, placement group, public-IP, kube-proxy, SELinux, and storage inputs to a consistent v3 contract. Removed obsolete inputs such as `enable_iscsid`, `extra_kustomize_*`, `autoscaler_labels`, `autoscaler_taints`, and the old CCM deployment-mode switch. See `MIGRATION.md`.
- **Hetzner CCM HelmChart only** - Removed the legacy raw-manifest Hetzner CCM path. v3 always renders the CCM HelmChart manifest and removes old non-Helm CCM objects during addon reconciliation.
- **Existing Network shape** - Replaced `existing_network_id` with `existing_network = { id = 1234567 }`; `network_id = 0` is no longer a valid user value, and omitted/null `network_id` means the primary kube-hetzner Network.
- **Nodepool network behavior** - Agent and autoscaler `network_id` values are now active. Control planes stay on the primary Network and do not accept `network_id`.
- **Subnet allocation modes** - New v3 clusters and normal in-place v2 upgrades use `network_subnet_mode = "per_nodepool"`, matching the released v2 subnet topology. Added optional `network_subnet_mode = "shared"` for compact new-cluster layouts that intentionally use one shared agent subnet and one shared control-plane subnet.
- **Minimum tool versions** - Terraform/OpenTofu `>= 1.10.1` and hcloud provider `>= 1.62.0` are required.
- **Default/architecture changes** - New nodes default to Leap Micro, architecture selection is consolidated into `enabled_architectures`, and default behavior moved to explicit positive booleans.

### 🚀 New Features

- **Leap Micro Support (Stable Default OS)** - Added `os` selector for control plane, agent, and autoscaler nodepools (plus per-node agent overrides). New nodepools default to `leapmicro`; existing nodepools remain on MicroOS by default on upgrade to avoid recreation. New variables: `leapmicro_x86_snapshot_id`, `leapmicro_arm_snapshot_id`. Added packer template `packer-template/hcloud-leapmicro-snapshots.pkr.hcl` and automatic OS detection via the `kube-hetzner/os` server label.
- **Agent Floating IP Family Selection** - Added `floating_ip_type` (`ipv4`/`ipv6`) to agent nodepools and node overrides, including IPv6-aware NetworkManager reconfiguration logic.
- **Cilium Egress Gateway HA Reconciler** - New `cilium_egress_gateway_ha_enabled` option to deploy a lightweight controller that keeps labeled `CiliumEgressGatewayPolicy` objects pinned to a Ready egress node.
- **Cilium v3 Dual-Stack Defaults** - Cilium now renders IPv4/IPv6 Helm values from the configured cluster CIDRs and keeps kube-proxy replacement tied to `enable_kube_proxy = false` (#2170, #2178).
- **Cilium Gateway API Support** - Added `cilium_gateway_api_enabled` to install standard Gateway API CRDs for the selected Cilium line, enable Cilium `gatewayAPI.enabled`, and wire cert-manager Gateway API support. Added `examples/cilium-gateway-api`.
- **Cilium Multinetwork Public Overlay Preview** - Added gated `multinetwork_mode = "cilium_public_overlay"` plumbing for Cilium-only clusters spanning multiple Hetzner Networks, including public IPv4/IPv6/dual-stack transport selection, WireGuard/tunnel defaults, public load-balancer targeting, control-plane fanout removal, and one Cluster Autoscaler Deployment per effective `network_id`. This path now requires `enable_experimental_cilium_public_overlay = true` and is not production-supported until the live datapath E2E passes.
- **Tailscale Node Transport** - Added opt-in `node_transport_mode = "tailscale"` for secure single-network clusters and supported private multinetwork scale-out. The module can bootstrap Tailscale, use MagicDNS for Terraform/kubeconfig access, optionally advertise each node's Hetzner private `/32` route with subnet-route SNAT disabled, keep Kubernetes node IPs on Hetzner private addresses, validate Tailnet/firewall/CNI/load-balancer constraints at plan time with explicit nodepool `network_scope`, and render autoscaler nodes with per-Network Tailscale bootstrap. Flannel is the first supported CNI; Cilium remains gated as experimental for this transport until live datapath coverage promotes it.
- **Embedded Registry Mirror** - Added `embedded_registry_mirror` for trusted large clusters, enabling k3s/RKE2's embedded Spegel mirror while preserving user `registries_config` entries.
- **Placement Group Auto-Sharding** - Count-based nodepools without an explicit `placement_group` now shard implicit Hetzner spread placement groups every 10 servers; explicit placement groups still fail validation above Hetzner's 10-server limit.
- **Large-Scale Tailscale Examples** - Added +100-node and 10,000-total-node Tailscale node-transport reference examples that account for Hetzner Network attachment limits, placement-group limits, autoscaler shards, and the public-IP/Tailnet exposure model.
- **Endpoint Introspection Outputs** - Added outputs for the effective kubeconfig API endpoint, node join endpoint, node transport mode, and Tailscale MagicDNS hostnames.
- **v3 Topology Recommendations** - Added `docs/v3-topology-recommendations.md` covering the recommended dev, HA, NAT, Tailscale, +100 node, 10k reference, RKE2, Cilium dual-stack, Gateway API, Robot/vSwitch, and registry mirror shapes.
- **Multiple Attached Volumes Per Node** - Added `attached_volumes` support for control plane and agent nodepools (including per-node overrides) to provision and mount multiple Hetzner Volumes per node.
- **NAT Router Customization** - Added NAT-router `extra_runcmd` and `use_private_nat_router_bastion` support for private-network bastion hardening (#2165, #2166).
- **External Overlay Access Hooks** - Added and documented the provider-agnostic `node_connection_overrides` pattern for Tailscale, ZeroTier, Cloudflare WARP, and similar overlays. Use this for user-owned operator access or post-bootstrap overlay features; use `node_transport_mode = "tailscale"` when Tailscale should be the official Kubernetes node transport.
- **Per-Nodepool Snapshot Overrides** - Added `os_snapshot_id` overrides to control-plane and agent nodepools and node overrides (#2158).
- **Plan-Time Configuration Guardrails** - Added Terraform/OpenTofu cross-variable validation for architecture toggles, network regions/CIDRs, nodepool topology, load balancers, autoscaler settings, CCM/Robot, Cilium-only features, firewall sources, and multi-volume attachments so invalid combinations fail during `terraform plan`.
- **Robot vSwitch Route Exposure Control** - Added `expose_routes_to_vswitch` to manage Hetzner Cloud route exposure to coupled Robot vSwitches when kube-hetzner creates the primary Network.
- **v2-to-v3 Migration Assistant** - Added a read-only audit script, project skill, and migration playbook for guided v2 configuration rewrites, plan review, and state-safety checks.
- **OpenTofu Support** - Documented OpenTofu as a supported engine and expanded Hetzner CI presets to run both Terraform and OpenTofu apply/health/destroy paths.

### 🐛 Bug Fixes

- **External Manifest Fetch Resilience** - Added retry blocks to GitHub and public-IP HTTP data sources so transient TLS handshake timeouts do not fail plans, applies, or destroys.
- **Autoscaler CA Root Loading** - Removed the `/etc/ssl/certs` hostPath mount from Cluster Autoscaler so RKE2/Leap Micro clusters use the image's bundled CA roots instead of hitting host certificate directory permission failures.
- **Terraform 1.15 Validation Compatibility** - Moved cross-variable and local-dependent module contract checks from input-variable validation blocks into a hard `terraform_data.validation_contract` precondition surface, preserving plan-time failures while allowing Terraform 1.15.0 to initialize and validate the module.
- **Tailscale Volume Provisioning Ordering** - Agent Longhorn and attached-volume configuration now waits for Tailscale agent bootstrap before using Tailnet MagicDNS SSH targets.
- **Tailscale Auth-Key Ergonomics** - `auth_key` mode no longer advertises kube-hetzner tags by default, so simple pre-auth keys work without Tailnet `tagOwners`; tagged nodes remain an explicit opt-in and OAuth mode now validates that tag-scoped auth is configured.
- **Tailscale Single-Network Ergonomics** - Tailscale mode now cleanly supports ordinary single-network clusters: node-private route advertisement can be disabled when no `network_scope = "external"` nodepools are used, private control-plane Load Balancers are allowed, and private managed ingress Load Balancers are rejected only for external-network scale-out.
- **Tailscale Same-Root Network Validation** - Tailscale static agent and autoscaler nodepools now use explicit `network_scope = "primary" | "external"` intent, so invalid same-root external Network configurations fail during `terraform plan` even when `network_id` is not known until apply.
- **Placement Group Disable/Limit Semantics** - `enable_placement_groups = false` now stops creating unused placement-group resources, and plan-time validation enforces Hetzner's 50-placement-group project limit before large static topologies hit provider errors.
- **Same-Root Tailscale External Networks** - In Tailscale transport mode, nodepool `network_id` values can come from Hetzner Network resources created in the same Terraform root because control planes no longer need apply-time fanout attachments to every external agent Network.
- **Cloud-Init Health-Checker Race** - Host and autoscaler cloud-init now masks Leap Micro/MicroOS `health-checker.service` before `cloud-final` to prevent a systemd ordering-cycle race that can skip first-boot Kubernetes bootstrap on autoscaled nodes.
- **Cilium Multinetwork Bootstrap** - Public-overlay clusters now allow restricted outbound Kubernetes API traffic and keep Hetzner CCM network-aware while route reconciliation stays disabled, so control planes can remain on their private node identity and external-network agents can join over the public overlay.
- **Cilium Default Bootstrap** - Cilium now enables eBPF masquerading only when kube-proxy replacement is enabled, matching Cilium's BPF NodePort dependency and preventing default Cilium clusters from CrashLooping on startup.
- **Interface Rename Self-Heal** - Added a boot-time `kh-rename-interface.service` and stale udev MAC refresh so private NIC renames survive MAC changes and reboots (#2182).
- **User Kustomization Redeploys** - User kustomization uploads and deploys now rerun after first control-plane replacement (#2160).
- **Custom Ingress Mode** - `ingress_controller = "custom"` now skips managed ingress Service lookup/wait logic (#2173).
- **Autoscaler Without Public IPv4** - Autoscaler cloud-init now routes IPv4 through the private gateway when public IPv4 is disabled, while keeping public IPv6 routing when enabled (#2154).
- **Hetzner CCM Dual-Stack Address Family** - Hetzner CCM now keeps route reconciliation on the IPv4 pod CIDR and sets `HCLOUD_INSTANCES_ADDRESS_FAMILY` for IPv6/dual-stack clusters (#2170).
- **Cilium Egress Gateway Validation** - Enforces `enable_kube_proxy = false` when Cilium Egress Gateway is enabled, matching Cilium's kube-proxy replacement requirement (#2178).
- **Cilium Egress Gateway HA Reconciler** - Treats `CiliumEgressGatewayPolicy` as cluster-scoped when retargeting labeled policies (#2178).
- **Upgrade-Safe Ingress Namespace Defaults** - Restored legacy nginx default namespace (`nginx`) to avoid Helm ownership conflicts during upgrades from v2.19.x clusters.
- **CCM Ownership Compatibility** - Keeps Hetzner CCM on the existing HelmChart manifest flow, avoiding release-name collisions with already-installed CCM chart instances.
- **CCM Helm Migration Cleanup** - v3 now removes the full legacy non-Helm Hetzner CCM RBAC surface before installing the Helm-managed CCM, while preserving Helm-owned CCM resources on later applies.
- **Upgrade-Safe Hetzner SSH Key State** - Preserves the v2-managed `hcloud_ssh_key.k3s` resource during v3 upgrades instead of auto-adopting the same key through a data source and planning key deletion.
- **Addon Manifest Fetch Stability** - Terraform now fetches kured and system-upgrade-controller release manifests and uploads them as local kustomize resources, avoiding control-plane kustomize failures on GitHub release-asset URLs.
- **Subnet Topology Compatibility** - Restored per-nodepool control-plane/agent subnet resources and nodepool subnet attachment while keeping auto-assigned private IPv4 behavior.
- **RKE2 SELinux Apply Parity** - Wired RKE2 server/agent install flows to apply the `rke2-selinux` policy module when available and added safe post-install `restorecon` relabeling for RKE2 binaries.
- **LeapMicro SELinux Snapshot Matrix (k3s/rke2 x x86/arm)** - LeapMicro packer now builds distro-specific SELinux snapshots (`selinux_package_to_install`), labels snapshots with `kube-hetzner/k8s-distro` and architecture, and auto-selection now matches `kubernetes_distribution` to prevent k3s/rke2 SELinux RPM conflicts.
- **MicroOS Packer SELinux Scope** - Removed `rke2-selinux` preinstall from the MicroOS packer template; it now only preinstalls and locks `k3s-selinux`.
- **LeapMicro SELinux Policy De-duplication** - Moved `k8s_custom_policies` into a shared template consumed by both host and autoscaler cloud-init paths to prevent policy drift.
- **RKE2 SELinux Enforcing Guardrail** - Added an explicit enforcing-mode validation that fails provisioning if the `rke2` SELinux module is still not loaded.
- **Longhorn iSCSI SELinux Capability** - Added `iscsid_t` `dac_override` permission to the shared kube-hetzner SELinux module.
- **RKE2 TLS SAN Endpoint Parity** - `control_plane_config_rke2` now includes `local.kubeconfig_server_address` in `tls-san`, preserving SAN coverage for NAT-router/private-LB kubeconfig endpoints.
- **Hetzner CI LeapMicro Snapshot Gate** - Hetzner test prerequisites now accept LeapMicro snapshot secrets (with MicroOS fallback) instead of requiring MicroOS-only secrets.
- **Autoscaler Nodepool Parity/Validation** - Added autoscaler nodepool validation guards (unique names, integer min/max bounds, taint effect and swap/zram format checks) and aligned RKE2 autoscaled node labeling/taint rendering with the k3s autoscaler path.
- **RKE2 User Kustomizations** - Switched user kustomization apply path to distribution-aware `kubectl_cli`, fixing apply failures in RKE2 clusters.
- **extra_network_ids Attachment** - Wired `extra_network_ids` into host provisioning so additional Hetzner networks are actually attached to control-plane and agent nodes.
- **Connection Override Consistency** - Unified control-plane and agent `node_connection_overrides` resolution so provisioning and follow-up operations honor the same override key strategy (including suffixed node names).
- **RKE2 TLS SAN Parity (No LB)** - Added kubeconfig/control-plane advertised endpoints to RKE2 non-LB TLS SAN generation to prevent certificate mismatch on custom kubeconfig server addresses.
- **Control Plane Bootstrap Config Files** - First-node k3s/RKE2 bootstrap now installs authentication and audit policy config files before starting the API server when the matching API-server args are enabled.
- **RKE2 First Bootstrap Parity** - RKE2 first bootstrap now respects `enable_selinux` and uses the effective kubeconfig/control-plane endpoints in its initial `tls-san` list, matching steady-state config.
- **Attached Volume Mount Safety** - Attached control-plane and agent volumes now rerun mount configuration on size changes, resize XFS via mount path, and persist fstab entries by filesystem UUID instead of mutable device paths.
- **K3s Channel Guardrail** - Default `k3s_channel` now uses the live `stable` channel, and plan-time validation rejects minor live channels unless an exact `k3s_version`/`rke2_version` is set, avoiding broken upstream minor-channel installer resolution.
- **API Port Consistency** - k3s first bootstrap now honors `kubernetes_api_port`, the control-plane LB health check/backend follows the configured listener port, IPv6 kubeconfig endpoints are bracketed correctly, and RKE2 now rejects unsupported non-6443 API port settings.
- **RKE2 Apply Parity** - RKE2 kustomization triggers now include CCM values and system-upgrade drain/eviction/window settings, readiness waits evaluate dynamically, deployment/job waits match k3s, and RKE2 secret deployment uses the shared file-based secret path instead of shell argv literals.
- **Node Route Robustness** - Host cloud-init now handles public-IPv6-only nodes by routing IPv4 through the private gateway while preserving public IPv6 routing, matching autoscaler behavior.
- **Leap Micro First-Boot Readiness** - Host provisioning now resets and tolerates the known non-critical `transactional-update.service` first-boot failure while still blocking on other failed systemd units.
- **Upgrade-Safe Detection/Provisioning** - Existing hyphenated nodepool names without random suffixes are detected correctly for OS defaults, NAT routers no longer recreate for image/user-data drift, and RKE2 autoscaler SSH keys use the normalized authorized-key list.
- **RKE2 Replacement/Reapply Safety** - RKE2 first-node bootstrap now retriggers on first control-plane replacement, and RKE2 addon application hashes the rendered kustomization payload so template/resource toggles are reapplied.
- **Per-Network Route/Floating IP Detection** - Install-time private-route repair and floating IP public-NIC detection now use each node's actual private network CIDR/gateway instead of the primary cluster network.
- **NAT Router Config Reconciliation** - Existing NAT routers now reconcile cloud-init-owned SSH, DNS, iptables, and keepalived config through Terraform provisioners while connection-critical SSH/user/key changes force router replacement.
- **Hetzner CI Presets** - CI preset tests now use a compact local-checkout fixture, sanitize preset-derived cluster names, and cover Terraform apply, Kubernetes health checks, and Terraform destroy for default, nginx, and RKE2 presets.
- **RKE2 Registry Bootstrap** - Initial cloud-init now writes `registries_config` to `/etc/rancher/rke2/registries.yaml` for RKE2 clusters instead of the k3s path, so custom registries are available before first RKE2 start.

### 🔧 Changes

- **Explicit Provider Constraints** - Pinned the previously implicit Kubernetes, Helm, Random, and CloudInit provider requirements and expanded CI validation across Terraform 1.10.5, 1.14.9, 1.15.0, and OpenTofu 1.11.6.
- **iSCSI Daemon Defaults** - `iscsid` is now enabled on all nodes by default, and the `enable_iscsid` input was removed.
- **Cilium Default Version** - Updated the default Cilium version to `1.19.3` so v3 defaults align with the current Gateway API-supported Cilium line.
- **Primary IP Provider Cleanup** - Removed now-unused `assignee_type = "server"` attributes from hcloud Primary IP resources and raised the hcloud provider minimum to `1.62.0`.
- **Cloudflare Zero Trust Support Boundary** - Documented Cloudflare Access/Tunnel as a user-managed external access pattern for kube API, SSH, Rancher, and ingress, while explicitly keeping Cloudflare Mesh/WARP out of the v3 node-transport support contract. Use Tailscale for supported secure node transport.
- **Release Attribution Robustness** - Release workflow now maps commits to associated PR authors (including squash merges) when generating contributor credits, so original implementers are preserved.

---

## [2.19.3] - 2026-04-25

### 📋 v2.19.3 Patch Release

This is a patch release for the v2.19 series focused on upgrade-safe reliability fixes.

**Patch fixes:**
- **Terraform Legacy Module Regression** - Removed the child-module GitHub provider configuration that prevented callers from using `count`, `for_each`, or `depends_on`; release lookups now use unauthenticated HTTP requests instead (#2155).
- **SSH Public Key Normalization** - Trimmed trailing whitespace from SSH public keys to avoid Hetzner provider apply inconsistencies when users pass keys with `file(...)`.
- **NAT Router Validation** - Made NAT router validations null-safe when `nat_router = null` (#2152, #2153).
- **Autoscaler ZRAM Bootstrap** - Fixed autoscaler nodes hanging in cloud-init when `zram_size` is configured (#2161, #2162).
- **NAT Router Fail2ban** - Fixed the Debian 12 SSH jail by applying journald/systemd backend support and starting/restarting fail2ban during NAT router provisioning (#2163).
- **MicroOS Snapshot Growth** - Reduced snapper timeline retention to avoid disk pressure on small nodes (#2167).
- **Longhorn Volume Reconfiguration** - Re-runs Longhorn volume setup on volume identity/size/path/fstype changes, grows filesystems correctly, and stores fstab entries by filesystem UUID instead of mutable Hetzner volume device IDs (#2174, #2180).
- **System Upgrade Plans** - Re-applies system-upgrade-controller Plans when `system_upgrade_use_drain` or `system_upgrade_enable_eviction` changes after initial provisioning (#2172).
- **Control Plane LB Health Check** - Added an explicit HTTPS `/readyz` health check for the control-plane load balancer while keeping the service TCP passthrough (#2176).
- **Hetzner CSI Values Docs** - Documented existing `hetzner_csi_values` support for custom CSI Helm values (#2168).
- **Longhorn RWX Guidance** - Documented the upstream Longhorn RWX/NFS 4.1 issue and the NFS 4.0 workaround (#2169).

---

## [2.19.2] - 2026-02-17

_See [GitHub release v2.19.2](https://github.com/mysticaltech/terraform-hcloud-kube-hetzner/releases/tag/v2.19.2)._

---

## [2.19.1] - 2026-02-02

### 📋 v2.19.1 Patch Release

This is a patch release for v2.19.0. **If upgrading from v2.18.x**, please review the full release notes below including upgrade notes, new features, and breaking changes.

**Patch fix:**
- **Audit Policy Bastion Connection** - Fixed missing bastion SSH settings in `audit_policy` provisioner, enabling audit policy deployment for NAT router / private network setups (#2042) - thanks @CounterClops

---

## [2.19.0] - 2026-02-01

### ⚠️ Upgrade Notes (from v2.18.x)

#### NAT Router Users (created before v2.19.0)

If you created a NAT router **before v2.19.0** (when the hcloud provider used the now-deprecated `datacenter` attribute), you may see Terraform wanting to recreate your NAT router primary IPs. This would result in new IP addresses.

**To check if you're affected**, run `terraform plan` and look for changes to:
- `hcloud_primary_ip.nat_router_primary_ipv4`
- `hcloud_primary_ip.nat_router_primary_ipv6`

**If Terraform shows replacement**, you have two options:

1. **Allow the recreation** (simplest, but IPs will change):
   ```bash
   terraform apply
   ```

2. **Migrate state manually** (preserves IPs):
   ```bash
   # Remove old state entries
   terraform state rm 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv4[0]'
   terraform state rm 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv6[0]'

   # Import with current IPs (get IDs from Hetzner Cloud Console)
   terraform import 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv4[0]' <ipv4-id>
   terraform import 'module.kube-hetzner.hcloud_primary_ip.nat_router_primary_ipv6[0]' <ipv6-id>

   terraform apply
   ```

#### Version Requirements

- Minimum Terraform version: `1.10.1`
- Minimum hcloud provider version: `1.59.0`

### 🚀 New Features

- **Hetzner Robot Integration** - Manage dedicated Robot servers via vSwitch and Cloud Controller Manager. New variables: `robot_ccm_enabled`, `robot_user`, `robot_password`, `vswitch_id`, `vswitch_subnet_index` (#1916)
- **Audit Logging** - Kubernetes audit logs with configurable policy via `k3s_audit_policy_config` and log rotation settings (#1825)
- **Control Plane Endpoint** - New `control_plane_endpoint` variable for stable external API server endpoint (e.g., external load balancers) (#1911)
- **NAT Router Control Plane Access** - Automatic port 6443 forwarding on NAT router when `control_plane_lb_enable_public_interface` is false (#2015)
- **Smaller Networks** - New `subnet_amount` variable enables networks smaller than /16 (#1971)
- **Custom Subnet Ranges** - Added `subnet_ip_range` to agent_nodepools for manual CIDR assignment (#1903)
- **Autoscaler Swap/ZRAM** - Added `swap_size` and `zram_size` support for autoscaler node pools (#2008)
- **Autoscaler Resources** - New `cluster_autoscaler_replicas`, `cluster_autoscaler_resource_limits`, `cluster_autoscaler_resource_values` (#2025)
- **Flannel Backend** - New `flannel_backend` variable to override flannel backend (wireguard-native, host-gw, etc.)
- **Cilium XDP Acceleration** - New `cilium_loadbalancer_acceleration_mode` variable (native, best-effort, disabled)
- **K3s v1.35 Support** - Added support for k3s v1.35 channel (#2029)
- **Packer Enhancements** - Configurable `kernel_type`, `sysctl_config_file`, and `timezone` for MicroOS snapshots (#2009, #2010)

### 🐛 Bug Fixes

- **Audit Policy Bastion Connection** _(v2.19.1)_ - Fixed missing bastion SSH settings in `audit_policy` provisioner, enabling audit policy deployment for NAT router / private network setups (#2042)
- **Longhorn Hotfix Tag Guidance** - Clarified `longhorn_version` as chart version and documented `longhorn_merge_values` for targeted Longhorn image hotfix tags (e.g. manager/instance-manager) (#2054)
- **Traefik v34 Compatibility** - Fixed HTTP to HTTPS redirection config for Traefik Helm Chart v34+ (#2028)
- **NAT Router IP Drift** - Fixed infinite replacement cycle by migrating from deprecated `datacenter` to `location` (#2021)
- **SELinux YAML Parsing** - Fixed cloud-init SCHEMA_ERROR caused by improper YAML formatting of SELinux policy
- **SELinux Missing Rules** - Added rules for JuiceFS (sock_file write) and SigNoz (blk_file getattr)
- **Kured Version Null** - Fixed potential null value issues with `kured_version` logic (#2032)

### 🔧 Changes

- **Default K3s Channel** - Bumped from the v1.33 minor channel to the upstream `stable` channel after upstream minor-channel resolution stopped being a reliable install-time contract (#2030)
- **Default System Upgrade Controller** - Bumped to v0.18.0
- **SELinux Policy Extraction** - Moved to dedicated template file for maintainability
- **terraform_data Migration** - Migrated from null_resource to terraform_data with automatic state migration (#1548)
- **remote-exec Refactor** - Improved provisioner compatibility with Terraform Stacks (#1893)
- **Custom GPT Updated** - [KH Assistant](https://chatgpt.com/g/g-67df95cd1e0c8191baedfa3179061581-kh-assistant) updated with v2.19.0 features, improved knowledge base, and cost calculator

---

## [2.18.5] - 2026-01-15

_See [GitHub releases](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/releases) for earlier versions._
