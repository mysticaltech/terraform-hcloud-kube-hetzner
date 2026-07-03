# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 🐛 Bug Fixes

- **Traefik Gateway API CRDs** - Install the Kubernetes Gateway API standard CRDs before Traefik when `traefik_provider_kubernetes_gateway_enabled` is enabled, preventing Helm install failures for `GatewayClass` and `Gateway` resources (#2211).
- **Agent Startup Race on Fresh Deploys** - Agent nodes now start only after the kustomization that deploys the Hetzner CCM, fixing consistent `exit 124` timeouts on fresh single-apply deployments. The agent start is also observable now: on failure it dumps `systemctl status` and journal output instead of failing silently (#2215, #2220).
- **User Kustomization Failures No Longer Masked** - A failed `kubectl apply -k` in the user kustomization deploy now fails the apply loudly instead of being masked by trailing `extra_kustomize_deployment_commands` (#2225).
- **Packer Snapshot Build Overrides** - The MicroOS snapshot template now exposes `x86_server_type`, `x86_location`, `arm_server_type`, and `arm_location` packer variables, so builds can be pointed at available server types/locations with `-var` instead of editing the template when Hetzner capacity shifts (#2214).

---

## [2.20.0] - 2026-06-02

### ⚠️ Upgrade Notes

- **Cluster Autoscaler Config File** - Autoscaler nodepools now mount the generated Hetzner cluster config through a Secret-backed file to avoid Kubernetes annotation size failures on large configurations. If `autoscaler_nodepools` is enabled and you override `cluster_autoscaler_version`, use `v1.33.0` or newer. The module default remains compatible.

### 🚀 New Features

- **Autoscaler DRA Permissions** - Added read-only Cluster Autoscaler RBAC for Kubernetes Dynamic Resource Allocation resources (`deviceclasses`, `resourceclaims`, `resourceslices`) (#2202).

### 🐛 Bug Fixes

- **Control Plane LB Health Check** - Fixed the Hetzner control-plane load balancer health check to use HTTP protocol with TLS enabled for the Kubernetes `/readyz` endpoint, avoiding invalid `https` protocol validation failures (#2188, #2199, #2200, #2205).
- **Terraform 1.11 Null Validation Compatibility** - Fixed null-safe NAT router and flannel backend validation paths so Terraform 1.11 can initialize and validate default configurations without `nat_router` or `flannel_backend` set (#2197).
- **Subnet Validation Contract** - Preserved hard validation for `subnet_amount` and `network_ipv4_cidr` cross-variable constraints without using Terraform variable validations that fail during module initialization under Terraform 1.11.
- **NAT Router Primary IP Drift** - Removed the deprecated fixed `assignee_type` argument from NAT router primary IP resources to avoid provider warnings and future drift (#2201).
- **MicroOS Snapshot Lookup** - Made default MicroOS snapshot lookup architecture-aware so ARM autoscaler pools do not depend on x86-only snapshot data sources (#2206).
- **Autoscaler Large Configs** - Moved large autoscaler cluster config JSON out of the Deployment environment and into a mounted Secret file, and switched apply to server-side field management to avoid annotation size limits (#2194, #2195).
- **Kured on Tainted Nodes** - Added a universal toleration to Kured so OS reboot management still runs on tainted nodes (#2196).
- **Kustomize Release Assets** - Upload Kured, system-upgrade-controller, and non-Helm CCM release manifests locally before running Kustomize, avoiding remote-base build failures on nodes without sufficient network access (#2186).

### 📚 Documentation

- Clarified Cluster Autoscaler scale-down behavior for pods using local storage and the safe overrides available for intentional eviction (#2187).
- Clarified that `ingress_controller = "nginx"` installs Kubernetes ingress-nginx, not the F5 NGINX Ingress Controller; use `ingress_controller = "none"` when installing F5 independently (#2204).
- Fixed the `kube.tf.example` HA control-plane example so every nodepool name is unique and the example validates as a root Terraform configuration.

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

- **Default K3s Version** - Bumped from v1.31 to v1.33 (#2030)
- **Default System Upgrade Controller** - Bumped to v0.18.0
- **SELinux Policy Extraction** - Moved to dedicated template file for maintainability
- **terraform_data Migration** - Migrated from null_resource to terraform_data with automatic state migration (#1548)
- **remote-exec Refactor** - Improved provisioner compatibility with Terraform Stacks (#1893)
- **Custom GPT Updated** - [KH Assistant](https://chatgpt.com/g/g-67df95cd1e0c8191baedfa3179061581-kh-assistant) updated with v2.19.0 features, improved knowledge base, and cost calculator

---

## [2.18.5] - 2026-01-15

_See [GitHub releases](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/releases) for earlier versions._
