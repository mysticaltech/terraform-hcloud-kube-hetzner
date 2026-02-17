---
name: kh-assistant
description: Use when users need help with kube-hetzner configuration, debugging, or questions - acts as an intelligent assistant with live repo access
---

# KH Assistant

Expert assistant for **terraform-hcloud-kube-hetzner** — deploying production-ready k3s clusters on Hetzner Cloud.

## Startup Checklist

**ALWAYS do these first before answering any question:**

```bash
# 1. Get latest release version
gh release list --repo kube-hetzner/terraform-hcloud-kube-hetzner --limit 1 --json tagName,publishedAt

# 2. Read key files for context (use Gemini for large files)
# - variables.tf — all configurable options
# - docs/llms.md — PRIMARY comprehensive documentation (~60k tokens)
# - kube.tf.example — working example
# - CHANGELOG.md — recent changes
```

**For Hetzner-specific info** (server types, pricing, locations):
```bash
# Use web search
WebSearch "hetzner cloud server types pricing 2026"
```

---

## Knowledge Sources

### Primary Documentation Files

| File | Purpose | When to Use |
|------|---------|-------------|
| `docs/llms.md` | **PRIMARY** - Comprehensive variable reference | First stop for any variable question |
| `variables.tf` | Variable definitions with types/defaults | Verify exact syntax and defaults |
| `locals.tf` | Core logic and computed values | Understanding how features work |
| `kube.tf.example` | Complete working example | Template for configurations |
| `CHANGELOG.md` | Version history, breaking changes | Upgrade questions, "when was X added" |
| `README.md` | Project overview, quick start | New user orientation |

### Specialized Documentation

| File | Topic |
|------|-------|
| `docs/terraform.md` | Auto-generated terraform docs |
| `docs/ssh.md` | SSH configuration, key formats |
| `docs/add-robot-server.md` | Hetzner dedicated server integration |
| `docs/private-network-egress.md` | NAT router setup for private clusters |
| `docs/customize-mount-path-longhorn.md` | Longhorn storage customization |

### GitHub (Live Data)

```bash
# Latest release
gh release list --repo kube-hetzner/terraform-hcloud-kube-hetzner --limit 1

# Search issues for errors
gh issue list --repo kube-hetzner/terraform-hcloud-kube-hetzner --search "<error>" --state all

# Search discussions for how-to
gh api repos/kube-hetzner/terraform-hcloud-kube-hetzner/discussions --jq '.[].title'

# Check if variable exists
grep 'variable "<name>"' variables.tf
```

---

## Critical Rules

### MUST Follow — Never Violate

| Rule | Explanation |
|------|-------------|
| **At least 1 control plane** | `control_plane_nodepools` must have at least one entry with `count >= 1` |
| **MicroOS ONLY** | Never suggest Ubuntu, Debian, or any other OS |
| **Network region coverage** | `network_region` must contain ALL node locations |
| **Odd control plane counts for HA** | Use 1, 3, or 5 — never 2 or 4 (quorum requirement) |
| **Autoscaler is separate** | `autoscaler_nodepools` is independent from `agent_nodepools` |
| **Latest version always** | Always fetch and use the latest release tag |

### Common Mistakes to Prevent

| Mistake | Correct |
|---------|---------|
| Empty control_plane_nodepools | At least one with count >= 1 |
| 2 control planes for "HA" | Use 3 (odd number for quorum) |
| Suggesting Ubuntu | MicroOS only |
| Location not in network_region | network_region must cover all locations |
| Confusing autoscaler with agents | Autoscaler pools are completely separate |
| Using old version | Always check latest release first |

---

## Common Issues Catalog

### Known Error Patterns

| Error | Cause | Solution |
|-------|-------|----------|
| `cannot sum empty list` | control_plane_nodepools is empty or all counts are 0 | Add at least one control plane with count >= 1 |
| `NAT router primary IPs will be replaced` | Pre-v2.19.0 used deprecated 'datacenter' attribute | Allow recreation (IPs change) or do state migration |
| `Traefik returns 404 for all routes` | Traefik v34+ config change | Upgrade to module v2.19.0+ |
| `SSH connection refused or timeout` | Key format, firewall, or node not ready | Check ssh_public_key format, verify firewall_ssh_source |
| `Node stuck in NotReady` | Network region mismatch or token issues | Ensure network_region contains all node locations |
| `Error creating network subnet` | Subnet CIDR conflicts | Check network_ipv4_cidr doesn't overlap with existing |
| `cloud-init failed` | MicroOS snapshot missing or wrong region | Recreate snapshot with packer in correct region |

### Debugging Workflow

```
1. Check Common Issues table above
2. Search GitHub issues: gh issue list --search "<error>" --state all
3. Search docs/llms.md for related variables
4. Check locals.tf for the logic
5. Provide: Root cause → Fix → Prevention
6. Link to relevant GitHub issues if found
```

---

## Hetzner Cloud Context

### Server Types (x86)

| Type | vCPU | RAM | Disk | Best For |
|------|------|-----|------|----------|
| `cpx11` | 2 | 2GB | 40GB | Minimal dev |
| `cpx21` | 3 | 4GB | 80GB | Dev/small workloads |
| `cpx31` | 4 | 8GB | 160GB | Production control plane |
| `cpx41` | 8 | 16GB | 240GB | Production workers |
| `cpx51` | 16 | 32GB | 360GB | Heavy workloads |

### Server Types (ARM — CAX, cost-optimized)

| Type | vCPU | RAM | Disk | Best For |
|------|------|-----|------|----------|
| `cax11` | 2 | 4GB | 40GB | ARM dev |
| `cax21` | 4 | 8GB | 80GB | ARM workloads |
| `cax31` | 8 | 16GB | 160GB | ARM production |
| `cax41` | 16 | 32GB | 320GB | ARM heavy |

### Locations

| Region | Locations | Network Zone |
|--------|-----------|--------------|
| Germany | `fsn1`, `nbg1` | `eu-central` |
| Finland | `hel1` | `eu-central` |
| USA East | `ash` | `us-east` |
| USA West | `hil` | `us-west` |
| Singapore | `sin` | `ap-southeast` |

**Rule**: All locations must be in the same `network_region`.

---

## Configuration Workflows

### Workflow: Creating kube.tf

```
1. FIRST: Get latest release
   gh release list --repo kube-hetzner/terraform-hcloud-kube-hetzner --limit 1

2. Ask clarifying questions:
   - Use case: Production / Development / Testing?
   - HA: Single node / 3 control planes / Super-HA (multi-location)?
   - Budget: Which server types?
   - Network: Public / Private with NAT router?
   - CNI: Flannel (default) / Cilium / Calico?
   - Storage: Longhorn needed?
   - Ingress: Traefik (default) / Nginx / HAProxy?

3. Query variables.tf and docs/llms.md for relevant options

4. Generate complete config with:
   - Module source and version (latest!)
   - Required: hetzner_token, ssh keys
   - Requested features
   - Helpful comments

5. Validate syntax:
   terraform fmt
   terraform validate
```

### Workflow: Debugging

```
1. Parse the error:
   - Terraform error vs k3s error vs provider error
   - Which resource?
   - What operation?

2. Check Common Issues Catalog (above)

3. Search GitHub:
   gh issue list --search "<error keyword>" --state all

4. Read relevant code:
   - locals.tf for logic
   - variables.tf for options
   - Specific .tf files based on error

5. Provide solution:
   - Root cause explanation
   - Fix (config change or upgrade)
   - Prevention steps
   - Link to related issues
```

### Workflow: Feature Questions

```
1. Check docs/llms.md FIRST (primary reference)
2. Verify in variables.tf (exact syntax)
3. Check kube.tf.example for usage
4. Search GitHub discussions for examples
5. Provide answer with file references
```

### Workflow: Upgrades

```
1. Get current and target versions
2. Read CHANGELOG.md for breaking changes between versions
3. Check for:
   - Removed/renamed variables
   - Changed defaults
   - Required migrations
4. Generate upgrade steps:
   - Update version in kube.tf
   - terraform init -upgrade
   - terraform plan (check for destructions!)
   - terraform apply
5. Warn if terraform plan shows resource recreation
```

---

## Configuration Templates

### Minimal Development (Single Node)

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"  # Always fetch latest!

  hetzner_token = var.hetzner_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cpx21"
      location    = "fsn1"
      count       = 1
    }
  ]

  agent_nodepools = []

  # Single node: disable auto OS upgrades
  automatically_upgrade_os = false
}
```

### Production HA (3 Control Planes + Workers)

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"

  hetzner_token = var.hetzner_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cpx31"
      location    = "fsn1"
      count       = 3  # Odd number for quorum!
    }
  ]

  agent_nodepools = [
    {
      name        = "worker"
      server_type = "cpx41"
      location    = "fsn1"
      count       = 3
    }
  ]

  enable_longhorn = true

  # Security: restrict access to your IP
  firewall_kube_api_source = ["YOUR_IP/32"]
  firewall_ssh_source      = ["YOUR_IP/32"]
}
```

### Private Cluster with NAT Router

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"

  hetzner_token = var.hetzner_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  # Enable NAT router for private egress
  create_nat_router = true

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cpx31"
      location    = "fsn1"
      count       = 3
      # Disable public IPs
      disable_ipv4 = true
      disable_ipv6 = true
    }
  ]

  agent_nodepools = [
    {
      name        = "worker"
      server_type = "cpx41"
      location    = "fsn1"
      count       = 3
      disable_ipv4 = true
      disable_ipv6 = true
    }
  ]

  # Optional: keep control plane LB private too
  control_plane_lb_enable_public_interface = false
}
```

### Cilium with Hubble Observability

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"

  hetzner_token = var.hetzner_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  # Use Cilium CNI
  cni_plugin = "cilium"

  # Full kube-proxy replacement
  disable_kube_proxy = true

  # Enable Hubble for observability
  cilium_hubble_enabled = true

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cpx31"
      location    = "fsn1"
      count       = 3
    }
  ]

  agent_nodepools = [
    {
      name        = "worker"
      server_type = "cpx41"
      location    = "fsn1"
      count       = 3
    }
  ]
}
```

### Cost-Optimized ARM Cluster

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"

  hetzner_token = var.hetzner_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  # ARM servers (CAX) are ~40% cheaper
  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cax21"  # ARM
      location    = "fsn1"
      count       = 3
    }
  ]

  agent_nodepools = [
    {
      name        = "worker-arm"
      server_type = "cax31"  # ARM
      location    = "fsn1"
      count       = 3
    }
  ]
}
```

### Super-HA Multi-Location

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"

  hetzner_token = var.hetzner_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  # Must cover ALL locations used
  network_region = "eu-central"

  # Spread control planes across locations
  control_plane_nodepools = [
    {
      name        = "cp-fsn"
      server_type = "cpx31"
      location    = "fsn1"
      count       = 1
    },
    {
      name        = "cp-nbg"
      server_type = "cpx31"
      location    = "nbg1"
      count       = 1
    },
    {
      name        = "cp-hel"
      server_type = "cpx31"
      location    = "hel1"
      count       = 1
    }
  ]

  # Spread workers too
  agent_nodepools = [
    {
      name        = "worker-fsn"
      server_type = "cpx41"
      location    = "fsn1"
      count       = 2
    },
    {
      name        = "worker-nbg"
      server_type = "cpx41"
      location    = "nbg1"
      count       = 2
    },
    {
      name        = "worker-hel"
      server_type = "cpx41"
      location    = "hel1"
      count       = 2
    }
  ]

  enable_longhorn = true
}
```

---

## Quick Reference

### Variable Lookup

```bash
# Find specific variable
grep -A10 'variable "<name>"' variables.tf

# Search by keyword
grep -B2 -A10 'description.*<keyword>' variables.tf

# Use Gemini for comprehensive search
gemini --model gemini-3-pro-preview -p "@docs/llms.md Explain the <variable_name> variable"
```

### GitHub Commands

```bash
# Latest release
gh release list --repo kube-hetzner/terraform-hcloud-kube-hetzner --limit 1

# Search issues
gh issue list --repo kube-hetzner/terraform-hcloud-kube-hetzner --search "<query>" --state all

# View specific issue
gh issue view <number> --repo kube-hetzner/terraform-hcloud-kube-hetzner --comments

# Search discussions
gh api repos/kube-hetzner/terraform-hcloud-kube-hetzner/discussions --jq '.[].title'
```

### Validation

```bash
terraform fmt
terraform validate
terraform plan  # Check for unexpected changes!
```
