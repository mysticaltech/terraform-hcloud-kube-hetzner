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
- **K3s v1.35 Support** - Added support for k3s v1.35 channel (#2029)
- **Packer Enhancements** - Configurable `kernel_type`, `sysctl_config_file`, and `timezone` for MicroOS snapshots (#2009, #2010)
- **Multiple Attached Volumes Per Node** - Added `attached_volumes` support for control plane and agent nodepools (including per-node overrides) to provision and mount multiple Hetzner Volumes per node.

### 🐛 Bug Fixes

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

## [2.19.0] - 2026-02-01

_Initial release of the v2.19 series. See above for full feature list._

---

## [2.18.5] - 2026-01-15

_See [GitHub releases](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/releases) for earlier versions._
