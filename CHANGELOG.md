# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### ⚠️ v3.0.0 Upgrade Notes

This branch is the v3 major-release line. Before upgrading from any `v2.x` release:

1. Pin and review:
   - Set module version to `3.0.0` (or your targeted v3 tag).
   - Read `MIGRATION.md` end-to-end.
2. Run safe upgrade flow:
   - `terraform init -upgrade`
   - `terraform plan`
   - Apply only after reviewing all resource actions.
3. If you use private-network NAT routers created before v2.19.0, check for primary IP replacement and perform state migration first (see migration notes).
4. Networking topology changed in v3 (shared managed node subnet). Prefer blue/green migration from `v2.x`; do not apply plans that unexpectedly destroy/recreate network subnets.

#### Version Requirements

- Minimum Terraform version: `1.10.1`
- Minimum hcloud provider version: `1.59.0`

### 🚀 New Features

- **Leap Micro Support (Stable Default OS)** - Added `os` selector for control plane, agent, and autoscaler nodepools (plus per-node agent overrides). New nodepools default to `leapmicro`; existing nodepools remain on MicroOS by default on upgrade to avoid recreation. New variables: `leapmicro_x86_snapshot_id`, `leapmicro_arm_snapshot_id`. Added packer template `packer-template/hcloud-leapmicro-snapshots.pkr.hcl` and automatic OS detection via the `kube-hetzner/os` server label.
- **Hetzner Robot Integration** - Manage dedicated Robot servers via vSwitch and Cloud Controller Manager. New variables: `robot_ccm_enabled`, `robot_user`, `robot_password`, `vswitch_id`, `vswitch_subnet_index` (#1916)
- **Audit Logging** - Kubernetes audit logs with configurable policy via `k3s_audit_policy_config` and log rotation settings (#1825)
- **Control Plane Endpoint** - New `control_plane_endpoint` variable for stable external API server endpoint (e.g., external load balancers) (#1911)
- **NAT Router Control Plane Access** - Automatic port 6443 forwarding on NAT router when `control_plane_lb_enable_public_interface` is false (#2015)
- **Smaller Networks** - New `subnet_amount` variable enables networks smaller than /16 (#1971)
- **Custom Subnet Ranges** - Added `subnet_ip_range` to agent_nodepools for manual CIDR assignment (#1903)
- **Autoscaler Swap/ZRAM** - Added `swap_size` and `zram_size` support for autoscaler node pools (#2008)
- **Autoscaler Resources** - New `cluster_autoscaler_replicas`, `cluster_autoscaler_resource_limits`, `cluster_autoscaler_resource_values` (#2025)
- **Agent Floating IP Family Selection** - Added `floating_ip_type` (`ipv4`/`ipv6`) to agent nodepools and node overrides, including IPv6-aware NetworkManager reconfiguration logic.
- **Flannel Backend** - New `flannel_backend` variable to override flannel backend (wireguard-native, host-gw, etc.)
- **Cilium XDP Acceleration** - New `cilium_loadbalancer_acceleration_mode` variable (native, best-effort, disabled)
- **Cilium Egress Gateway HA Reconciler** - New `cilium_egress_gateway_ha_enabled` option to deploy a lightweight controller that keeps labeled `CiliumEgressGatewayPolicy` objects pinned to a Ready egress node.
- **Cilium v3 Dual-Stack Defaults** - Cilium now renders IPv4/IPv6 Helm values from the configured cluster CIDRs and keeps kube-proxy replacement tied to `disable_kube_proxy` (#2170, #2178).
- **K3s v1.35 Support** - Added support for k3s v1.35 channel (#2029)
- **Packer Enhancements** - Configurable `kernel_type`, `sysctl_config_file`, and `timezone` for MicroOS snapshots (#2009, #2010)
- **Multiple Attached Volumes Per Node** - Added `attached_volumes` support for control plane and agent nodepools (including per-node overrides) to provision and mount multiple Hetzner Volumes per node.
- **NAT Router Customization** - Added NAT-router `extra_runcmd` and `use_private_bastion` support for private-network bastion hardening (#2165, #2166).
- **Per-Nodepool Snapshot Overrides** - Added `os_snapshot_id` overrides to control-plane and agent nodepools and node overrides (#2158).

### 🐛 Bug Fixes

- **Interface Rename Self-Heal** - Added a boot-time `kh-rename-interface.service` and stale udev MAC refresh so private NIC renames survive MAC changes and reboots (#2182).
- **User Kustomization Redeploys** - User kustomization uploads and deploys now rerun after first control-plane replacement (#2160).
- **Custom Ingress Mode** - `ingress_controller = "custom"` now skips managed ingress Service lookup/wait logic (#2173).
- **Autoscaler Without Public IPv4** - Autoscaler cloud-init now routes IPv4 through the private gateway when public IPv4 is disabled, while keeping public IPv6 routing when enabled (#2154).
- **Hetzner CCM Dual-Stack Address Family** - Hetzner CCM now keeps route reconciliation on the IPv4 pod CIDR and sets `HCLOUD_INSTANCES_ADDRESS_FAMILY` for IPv6/dual-stack clusters (#2170).
- **Cilium Egress Gateway Validation** - Enforces `disable_kube_proxy = true` when Cilium Egress Gateway is enabled, matching Cilium's kube-proxy replacement requirement (#2178).
- **Cilium Egress Gateway HA Reconciler** - Treats `CiliumEgressGatewayPolicy` as cluster-scoped when retargeting labeled policies (#2178).
- **Upgrade-Safe Ingress Namespace Defaults** - Restored legacy nginx default namespace (`nginx`) to avoid Helm ownership conflicts during upgrades from v2.19.x clusters.
- **CCM Ownership Compatibility** - Reverted Hetzner CCM management to the existing HelmChart manifest flow for `hetzner_ccm_use_helm`, avoiding release-name collisions with already-installed CCM chart instances.
- **Subnet Topology Compatibility** - Restored per-nodepool control-plane/agent subnet resources and nodepool subnet attachment while keeping auto-assigned private IPv4 behavior.
- **Audit Policy Bastion Connection** _(v2.19.1)_ - Fixed missing bastion SSH settings in `audit_policy` provisioner, enabling audit policy deployment for NAT router / private network setups (#2042)
- **Longhorn Hotfix Tag Guidance** - Clarified `longhorn_version` as chart version and documented `longhorn_merge_values` for targeted Longhorn image hotfix tags (e.g. manager/instance-manager) (#2054)
- **Traefik v34 Compatibility** - Fixed HTTP to HTTPS redirection config for Traefik Helm Chart v34+ (#2028)
- **NAT Router IP Drift** - Fixed infinite replacement cycle by migrating from deprecated `datacenter` to `location` (#2021)
- **SELinux YAML Parsing** - Fixed cloud-init SCHEMA_ERROR caused by improper YAML formatting of SELinux policy
- **SELinux Missing Rules** - Added rules for JuiceFS (sock_file write) and SigNoz (blk_file getattr)
- **RKE2 SELinux Apply Parity** - Wired RKE2 server/agent install flows to apply the `rke2-selinux` policy module when available and added safe post-install `restorecon` relabeling for RKE2 binaries.
- **LeapMicro SELinux Snapshot Matrix (k3s/rke2 x x86/arm)** - LeapMicro packer now builds distro-specific SELinux snapshots (`selinux_package_to_install`), labels snapshots with `kube-hetzner/k8s-distro` and architecture, and auto-selection now matches `kubernetes_distribution_type` to prevent k3s/rke2 SELinux RPM conflicts.
- **MicroOS Packer SELinux Scope** - Removed `rke2-selinux` preinstall from the MicroOS packer template; it now only preinstalls and locks `k3s-selinux`.
- **LeapMicro SELinux Policy De-duplication** - Moved `k8s_custom_policies` into a shared template consumed by both host and autoscaler cloud-init paths to prevent policy drift.
- **RKE2 SELinux Enforcing Guardrail** - Added an explicit enforcing-mode validation that fails provisioning if the `rke2` SELinux module is still not loaded.
- **Longhorn iSCSI SELinux Capability** - Added `iscsid_t` `dac_override` permission to the shared kube-hetzner SELinux module.
- **RKE2 TLS SAN Endpoint Parity** - `control_plane_config_rke2` now includes `local.kubeconfig_server_address` in `tls-san`, preserving SAN coverage for NAT-router/private-LB kubeconfig endpoints.
- **Hetzner CI LeapMicro Snapshot Gate** - Hetzner test prerequisites now accept LeapMicro snapshot secrets (with MicroOS fallback) instead of requiring MicroOS-only secrets.
- **Kured Version Null** - Fixed potential null value issues with `kured_version` logic (#2032)
- **Autoscaler Nodepool Parity/Validation** - Added autoscaler nodepool validation guards (unique names, integer min/max bounds, taint effect and swap/zram format checks) and aligned RKE2 autoscaled node labeling/taint rendering with the k3s autoscaler path.
- **RKE2 User Kustomizations** - Switched user kustomization apply path to distribution-aware `kubectl_cli`, fixing apply failures in RKE2 clusters.
- **extra_network_ids Attachment** - Wired `extra_network_ids` into host provisioning so additional Hetzner networks are actually attached to control-plane and agent nodes.
- **Connection Override Consistency** - Unified control-plane and agent `node_connection_overrides` resolution so provisioning and follow-up operations honor the same override key strategy (including suffixed node names).
- **RKE2 TLS SAN Parity (No LB)** - Added kubeconfig/control-plane advertised endpoints to RKE2 non-LB TLS SAN generation to prevent certificate mismatch on custom kubeconfig server addresses.

### 🔧 Changes

- **Default K3s Version** - Bumped from v1.31 to v1.33 (#2030)
- **Default System Upgrade Controller** - Bumped to v0.18.0
- **SELinux Policy Extraction** - Moved to dedicated template file for maintainability
- **terraform_data Migration** - Migrated from null_resource to terraform_data with automatic state migration (#1548)
- **remote-exec Refactor** - Improved provisioner compatibility with Terraform Stacks (#1893)
- **iSCSI Daemon Defaults** - `iscsid` is now enabled on all nodes by default, and the `enable_iscsid` input was removed.
- **Custom GPT Updated** - [KH Assistant](https://chatgpt.com/g/g-67df95cd1e0c8191baedfa3179061581-kh-assistant) updated with v2.19.0 features, improved knowledge base, and cost calculator
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

_Initial release of the v2.19 series. See v2.19.x release notes for upgrade guidance._

---

## [2.18.5] - 2026-01-15

_See [GitHub releases](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/releases) for earlier versions._
