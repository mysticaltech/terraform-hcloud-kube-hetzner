---
name: kh-assistant
description: Use when users need help with kube-hetzner configuration, debugging, or questions - acts as an intelligent assistant with live repo access
---

# KH Assistant

Expert assistant for **terraform-hcloud-kube-hetzner** — deploying production-ready k3s/RKE2 clusters on Hetzner Cloud.

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
| `MIGRATION.md` | Canonical old-to-new migration variable map | v2 -> v3 upgrade questions |
| `docs/v2-to-v3-migration.md` | v2 -> v3 operator playbook | Existing-cluster major upgrades |
| `docs/v3-topology-recommendations.md` | v3 topology chooser and "what not to choose" rules | New designs, multinetwork, Gateway API, registry mirror |
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
| **Supported OS only** | New nodes default to Leap Micro; MicroOS is legacy/upgrade support. Never suggest Ubuntu, Debian, or other generic OS images. |
| **Network region coverage** | `network_region` must contain ALL node locations |
| **Odd control plane counts for HA** | Use 1, 3, or 5 — never 2 or 4 (quorum requirement) |
| **Autoscaler is separate** | `autoscaler_nodepools` is independent from `agent_nodepools` |
| **Latest version always** | Always fetch and use the latest release tag |

### Common Mistakes to Prevent

| Mistake | Correct |
|---------|---------|
| Empty control_plane_nodepools | At least one with count >= 1 |
| 2 control planes for "HA" | Use 3 (odd number for quorum) |
| Suggesting Ubuntu/Debian | Use Leap Micro by default; MicroOS only for legacy/explicit nodepools |
| Location not in network_region | network_region must cover all locations |
| Confusing autoscaler with agents | Autoscaler pools are completely separate |
| Using old version | Always check latest release first |
| Raw Hetzner private multinetwork for >100 nodes | Use `node_transport_mode = "tailscale"` or the experimental Cilium public overlay; Hetzner private Networks do not route to each other |
| Treating external Tailscale hooks as node transport | Use `node_transport_mode = "tailscale"` for cluster transport; use `node_connection_overrides` only for user-owned operator access |
| Treating Cloudflare Mesh/WARP as supported node transport | Use Tailscale for kube-hetzner-managed secure node transport; Cloudflare Access/Tunnel is external operator/app access only |
| Assuming one Hetzner Network can exceed 100 nodes | Shard across multiple Hetzner Networks and count all attachments, including control planes, static agents, autoscaler `max_nodes`, NAT routers, and load balancers |
| Promising static 10k placement spread in one project | Hetzner spread groups are 10 servers each and 50 groups per project; use autoscaler/network shards or split across projects/clusters |
| Confusing Cilium Gateway API with Traefik Gateway provider | Use `cilium_gateway_api_enabled` for Cilium, `traefik_provider_kubernetes_gateway_enabled` for Traefik |
| Enabling Cilium Gateway API with kube-proxy | Requires `cni_plugin = "cilium"` and `enable_kube_proxy = false` |
| Enabling embedded registry mirror on low-trust nodes | Use only for equal-trust clusters; warn about credential sharing and tag poisoning |

### v3 Topology Shortcuts

| Need | Recommendation |
|------|----------------|
| Small dev | Single control plane, one small agent pool, no ingress unless needed |
| Normal HA | 3 control planes, 2+ agents, one primary Hetzner Network |
| Private-only | NAT router and private control-plane LB on the primary Network |
| Secure API/SSH | `node_transport_mode = "tailscale"` and close public API/SSH firewall sources |
| Cloudflare-protected operator/app access | User-managed Cloudflare Access/Tunnel in front of kube API, SSH, Rancher, Grafana, or ingress; keep node transport as Hetzner private or Tailscale |
| +100 Cloud nodes | Tailscale node transport plus one external Hetzner Network shard per 100-node budget |
| 10k reference | Autoscaler-first Tailscale multinetwork; point to `examples/tailscale-node-transport/massive-10000-nodes.tf.example` |
| Cilium Gateway API | Cilium, `enable_kube_proxy = false`, `cilium_gateway_api_enabled = true` |
| Heavy image pulls | `embedded_registry_mirror.enabled = true` only on trusted clusters |

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
| `cloud-init failed` | Leap Micro/MicroOS snapshot missing, wrong region, wrong architecture, or wrong distro label | Recreate snapshots with packer in the correct region/architecture and k3s/RKE2 SELinux variant |

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
   - Required: hcloud_token, SSH keys
   - Requested features
   - Helpful comments

5. Validate syntax:
   terraform fmt -recursive
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
2. If this is v2.x -> v3.x, use the /migrate-v2-to-v3 skill workflow
3. Read CHANGELOG.md, MIGRATION.md, and docs/v2-to-v3-migration.md
4. Check for:
   - Removed/renamed variables
   - Changed defaults
   - Required migrations
   - Inverted boolean semantics
   - State migration requirements
   - Network/subnet/LB/server replacement risk
5. Generate upgrade steps:
   - Update version in kube.tf
   - terraform init -upgrade
   - terraform validate
   - terraform plan (check for destructions!)
   - terraform apply
6. Warn if terraform plan shows resource recreation
```

### Workflow: v2 -> v3 Migrations

Use `.claude/skills/migrate-v2-to-v3/SKILL.md` for the exact workflow.

Core rules:
- Back up state before editing.
- Rewrite v2-only inputs using `MIGRATION.md`.
- Invert positive/negative booleans carefully.
- Remove `network_id = 0`; omitted/null means the primary Network in v3.
- Remove control-plane `network_id`; control planes stay on the primary Network.
- For secure Tailnet access or private multinetwork scale, prefer `node_transport_mode = "tailscale"`. For v2-to-v3 upgrades, introduce large multinetwork scale in a separate audited plan after the base upgrade. Tailscale mode keeps Kubernetes node IPs on Hetzner private addresses and can advertise node-private `/32` routes with Tailscale subnet-route SNAT disabled.
- Do not suggest Calico with Tailscale node transport yet. Flannel is first supported; Cilium is still explicitly experimental in this transport mode.
- For Cloudflare, recommend only the external Access/Tunnel pattern for kube API, SSH, Rancher, Grafana, or ingress. Do not suggest Cloudflare Mesh/WARP as kube-hetzner node transport and do not invent Cloudflare provider inputs.
- Run `terraform fmt -recursive`, `terraform init -upgrade`, `terraform validate`, and `terraform plan -out=v3-upgrade.tfplan`.
- Do not apply when the plan has unexplained replacements or destroys.

---

## Configuration Templates

### Minimal Development (Single Node)

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"  # Always fetch latest!

  hcloud_token = var.hcloud_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cpx21"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  agent_nodepools = [
    {
      name        = "worker"
      server_type = "cpx21"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 0
    }
  ]

  # Single node: disable auto OS upgrades
  automatically_upgrade_os = false
}
```

### Production HA (3 Control Planes + Workers)

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"

  hcloud_token = var.hcloud_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cpx31"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 3  # Odd number for quorum!
    }
  ]

  agent_nodepools = [
    {
      name        = "worker"
      server_type = "cpx41"
      location    = "fsn1"
      labels      = []
      taints      = []
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

  hcloud_token = var.hcloud_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  enable_control_plane_load_balancer = true

  nat_router = {
    server_type = "cax21"
    location    = "nbg1"
  }

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cpx31"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 3
      # Disable public IPs
      enable_public_ipv4 = false
      enable_public_ipv6 = false
    }
  ]

  agent_nodepools = [
    {
      name        = "worker"
      server_type = "cpx41"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 3
      enable_public_ipv4 = false
      enable_public_ipv6 = false
    }
  ]

  # Optional: keep control plane LB private too
  control_plane_load_balancer_enable_public_network = false
}
```

### Tailscale Node Transport

Use this when a user wants a single-network cluster with private Tailnet
Terraform/kubeconfig/SSH access, or a private cluster spanning multiple Hetzner
Cloud Networks. Do not use the older external-overlay pattern for Kubernetes
node transport.

```tf
node_transport_mode = "tailscale"

firewall_kube_api_source = null
firewall_ssh_source      = null

tailscale_auth_key = var.tailscale_auth_key
# tailscale_autoscaler_auth_key = var.tailscale_autoscaler_auth_key # Prefer ephemeral reusable key for autoscaler.

tailscale_node_transport = {
  bootstrap_mode  = "cloud_init"
  magicdns_domain = "example-tailnet.ts.net"
  auth = {
    mode = "auth_key"
  }
  routing = {
    # Single-network clusters may set false; external network_id nodepools need true.
    advertise_node_private_routes = false
  }
}
```

Rules to mention:
- Tailnet ACLs must auto-approve advertised Hetzner node-private `/32` routes when external `network_id` nodepools are used.
- The module disables Tailscale subnet-route SNAT for node/CNI traffic.
- Flannel VXLAN is first supported; Cilium needs the experimental flag; Calico is rejected.
- Managed Hetzner private LBs are fine for single-primary-network clusters; external `network_id` nodepools need public LB targets or non-Hetzner/private alternatives.
- The module NAT router only gives egress to the primary Hetzner Network; external-network Tailscale nodepools need public egress or an external bootstrap path.
- Large examples live in `examples/tailscale-node-transport/large-scale-200.tf.example` and `examples/tailscale-node-transport/massive-10000-nodes.tf.example`.
- The 200-node static example is `3 control planes + 97 primary agents + 100 agents on one external Network`; both Networks are exactly at Hetzner's 100-attachment limit and placement groups auto-shard to 21 groups.
- The 10,000-total-node reference is `3 control planes + 7 static system agents + 90 primary autoscaled workers + 99 external Networks * 100 autoscaled workers`. It is a quota/design reference, not a casual default.
- The recommended large-cluster exposure model closes public Kubernetes API and SSH, uses no public managed web ingress unless explicitly requested, and relies on Tailnet access. Nodes may still keep public IPv4/IPv6 for Tailscale bootstrap and direct UDP/41641 WireGuard paths; true no-public-IP multinetwork needs private egress plus external Tailscale bootstrap for every external Network.

### Cloudflare Zero Trust External Access

Use this when a user wants Cloudflare policy in front of operator or
human-facing endpoints. Do not present Cloudflare as a kube-hetzner-managed node
transport.

Rules:
- Cloudflare Access/Tunnel can protect kube API, SSH, Rancher, Grafana, or ingress hostnames.
- Cloudflare account resources, DNS records, tunnels, Access policies, WARP enrollment, and service tokens are managed outside kube-hetzner.
- No `node_transport_mode = "cloudflare"` exists, and Cloudflare Mesh/WARP is not supported node transport in v3.
- For kubeconfig through Access, suggest `cloudflared access tcp` or user-owned WARP/private routing.
- Do not set `control_plane_endpoint` to a Cloudflare Access hostname unless every joining node can reach and authenticate to it.
- For secure node transport or +100 node multinetwork, use `node_transport_mode = "tailscale"`.

Reference docs:
- `examples/external-overlay-cloudflare-access/README.md`
- `docs/v3-topology-recommendations.md`

### Cilium with Hubble Observability

```tf
module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "<LATEST>"

  hcloud_token = var.hcloud_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  # Use Cilium CNI
  cni_plugin = "cilium"

  # Full kube-proxy replacement
  enable_kube_proxy = false

  # Enable Hubble for observability
  cilium_hubble_enabled = true

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cpx31"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 3
    }
  ]

  agent_nodepools = [
    {
      name        = "worker"
      server_type = "cpx41"
      location    = "fsn1"
      labels      = []
      taints      = []
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

  hcloud_token = var.hcloud_token

  ssh_public_key  = file("~/.ssh/id_ed25519.pub")
  ssh_private_key = file("~/.ssh/id_ed25519")

  network_region = "eu-central"

  # ARM servers (CAX) are ~40% cheaper
  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cax21"  # ARM
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 3
    }
  ]

  agent_nodepools = [
    {
      name        = "worker-arm"
      server_type = "cax31"  # ARM
      location    = "fsn1"
      labels      = []
      taints      = []
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

  hcloud_token = var.hcloud_token

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
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "cp-nbg"
      server_type = "cpx31"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "cp-hel"
      server_type = "cpx31"
      location    = "hel1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  # Spread workers too
  agent_nodepools = [
    {
      name        = "worker-fsn"
      server_type = "cpx41"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 2
    },
    {
      name        = "worker-nbg"
      server_type = "cpx41"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 2
    },
    {
      name        = "worker-hel"
      server_type = "cpx41"
      location    = "hel1"
      labels      = []
      taints      = []
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
rg -n 'variable "<name>"' variables.tf

# Search by keyword
rg -n -C 3 'description.*<keyword>' variables.tf

# Use Gemini for comprehensive search
gemini --model gemini-3.1-pro-preview -p "@docs/llms.md Explain the <variable_name> variable"
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
terraform fmt -recursive
terraform validate
terraform plan  # Check for unexpected changes!
```
