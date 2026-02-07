# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 📋 v2.19.1 Patch Release

This is a patch release for v2.19.0. **If upgrading from v2.18.x**, please review the full release notes below including upgrade notes, new features, and breaking changes.

**Patch fix:**
- **Audit Policy Bastion Connection** - Fixed missing bastion SSH settings in `audit_policy` provisioner, enabling audit policy deployment for NAT router / private network setups (#2042) - thanks @CounterClops

---

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

## [2.19.0] - 2026-02-01

_Initial release of the v2.19 series. See above for full feature list._

---

## [2.18.5] - 2026-01-15

_See [GitHub releases](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/releases) for earlier versions._
