<div align="center">

<!-- HERO SECTION -->
<img src="https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/raw/master/.images/kube-hetzner-logo.png" alt="Kube-Hetzner Logo" width="140" height="140">

# Kube-Hetzner

### Production-Ready Kubernetes on Hetzner Cloud

**HA by default • Auto-upgrading • Cost-optimized**

A highly optimized, easy-to-use, auto-upgradable Kubernetes cluster powered by k3s on openSUSE Leap Micro (default) / MicroOS (legacy)<br>deployed for peanuts on [Hetzner Cloud](https://hetzner.com)

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.10.1-844FBA?style=flat-square&logo=terraform)](https://terraform.io)&nbsp;&nbsp;
[![OpenTofu](https://img.shields.io/badge/OpenTofu-Compatible-FFDA18?style=flat-square&logo=opentofu)](https://opentofu.org)&nbsp;&nbsp;
[![HCloud Provider](https://img.shields.io/badge/hcloud-%3E%3D1.62.0-00ADEF?style=flat-square)](https://registry.terraform.io/providers/hetznercloud/hcloud/latest)&nbsp;&nbsp;
[![K3s](https://img.shields.io/badge/K3s-v1.35-FFC61C?style=flat-square&logo=k3s)](https://k3s.io)&nbsp;&nbsp;
[![License](https://img.shields.io/github/license/kube-hetzner/terraform-hcloud-kube-hetzner?style=flat-square&color=blue)](LICENSE)&nbsp;&nbsp;
[![GitHub Stars](https://img.shields.io/github/stars/kube-hetzner/terraform-hcloud-kube-hetzner?style=flat-square&logo=github)](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/stargazers)

---

<table>
<tr>
<td width="50%" valign="top">

**💖 Love this project?**<br>
<a href="https://github.com/sponsors/mysticaltech">Become a sponsor</a> to help fund<br>maintenance and new features!

</td>
<td width="50%" valign="top">

**🤖 KH Assistant**<br>
<a href="https://chatgpt.com/g/g-67df95cd1e0c8191baedfa3179061581-kh-assistant">Custom GPT</a> or <code>/kh-assistant</code> <a href="https://github.com/mysticaltech/terraform-hcloud-kube-hetzner/tree/master/.claude/skills/kh-assistant">skill</a><br>
AI-powered config generation & debugging!

</td>
</tr>
</table>

---

[Getting Started](#-getting-started) •
[Features](#-features) •
[Usage](#-usage) •
[Examples](#-examples) •
[Contributing](#-contributing)

</div>

---

## 📖 About The Project

[Hetzner Cloud](https://hetzner.com) offers exceptional value with data centers across Europe and the US. This project creates a **highly optimized Kubernetes installation** that's easy to maintain, secure, and automatically upgrades both nodes and Kubernetes—functionality similar to GKE's Auto-Pilot.

> *We are not Hetzner affiliates, but we strive to be the optimal solution for deploying Kubernetes on their platform.*

Built on the shoulders of giants:
- **[openSUSE Leap Micro](https://en.opensuse.org/Portal:LeapMicro)** — Stable, immutable container OS with transactional updates
- **[openSUSE MicroOS](https://en.opensuse.org/Portal:MicroOS)** — Rolling, immutable container OS (legacy/upgrade support)
- **[k3s](https://k3s.io/)** — Certified, lightweight Kubernetes distribution

<div align="center">
<img src="https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/raw/master/.images/kubectl-pod-all-17022022.png" alt="Kube-Hetzner Screenshot" width="700">
</div>

### Why Leap Micro over Ubuntu?

| Feature | Benefit |
|---------|---------|
| **Immutable filesystem** | Most of the OS is read-only—hardened by design |
| **Transactional updates** | Atomic upgrades with rollback |
| **Stable release cadence** | Predictable base OS for production |
| **BTRFS snapshots** | Automatic rollback if updates break something |
| **[Kured](https://github.com/kubereboot/kured) support** | Safe, HA-aware node reboots |

> MicroOS remains supported for upgrades/legacy nodes. If you want MicroOS for a new nodepool, set `os = "microos"` explicitly.

### Why k3s?

| Feature | Benefit |
|---------|---------|
| **Certified Kubernetes** | Automatically synced with upstream k8s |
| **Single binary** | Deploy with one command |
| **Batteries included** | Built-in [helm-controller](https://github.com/k3s-io/helm-controller) |
| **Easy upgrades** | Via [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller) |

---

## 🔄 Upgrading

Upgrading from `v2.x` to `v3.x`?

Review the operator playbook in
[`docs/v2-to-v3-migration.md`](docs/v2-to-v3-migration.md) and the variable map
in [`MIGRATION.md`](MIGRATION.md) first. From a local kube-hetzner checkout,
audit the Terraform root, then run:

```bash
uv run python /path/to/kube-hetzner/scripts/v2_to_v3_migration_assistant.py --root .
terraform init -upgrade
terraform plan
```

Only apply after reviewing all planned resource actions.

### v3 Support Levels

| Area | Support level | Notes |
| --- | --- | --- |
| k3s on Leap Micro | Stable default | Recommended path for new clusters. |
| RKE2 on Leap Micro | Supported | Heavier distribution, covered by v3 validation and CI presets. |
| MicroOS | Legacy/upgrade support | Existing clusters remain supported; new nodepools default to Leap Micro. |
| OpenTofu | Supported | Validate with `tofu init`, `tofu validate`, and `tofu plan` before applying. |
| Cilium dual-stack | Supported | Preferred advanced CNI path. |
| Cilium Gateway API | Supported opt-in | `cilium_gateway_api_enabled = true` installs standard Gateway API CRDs and enables Cilium Gateway API. Requires Cilium with kube-proxy replacement. |
| Tailscale node transport | Supported opt-in | `node_transport_mode = "tailscale"` provides secure Tailnet access for single-network clusters and private route transport for multinetwork scale while Kubernetes keeps Hetzner node IPs. |
| Embedded registry mirror | Supported opt-in | Enables k3s/RKE2's embedded Spegel mirror for trusted larger clusters. |
| Cilium multinetwork public overlay | Experimental preview | Gated by `enable_experimental_cilium_public_overlay`; not production-supported until live datapath validation passes. |
| Flannel/Cilium multinetwork scale over Hetzner Networks | Supported through Tailscale transport | Flannel is the first supported CNI; Cilium is gated as experimental until live datapath coverage promotes it. |
| Tailscale/ZeroTier/WARP operator access | Supported external pattern | Use generic hooks when you only want Terraform/operator access and do not want kube-hetzner to manage node transport. |
| Robot/vSwitch coupling | Advanced/special-case | Prefer blue/green migration and review route exposure carefully. |

### Which Topology Should I Use?

| Need | Recommended v3 topology |
| --- | --- |
| Small dev cluster | Single control plane, one agent pool, no ingress unless needed. |
| Normal HA | 3 control planes, 2+ agents, one primary Hetzner Network, public API LB restricted to your source CIDRs or an explicit secure endpoint. |
| Private-only | `nat_router` plus private control-plane LB on the primary Network. |
| Secure operator/API access | `node_transport_mode = "tailscale"` with public API/SSH firewall sources closed. |
| More than 100 Cloud nodes | Tailscale node transport plus external `network_id` shards, one Hetzner Network per 100-node budget. |
| Very large reference | Autoscaler-first Tailscale multinetwork; see the 200-node and 10k-node examples. |
| Cilium Gateway API | Cilium, `enable_kube_proxy = false`, `cilium_gateway_api_enabled = true`. |
| Heavy image-pull pressure | `embedded_registry_mirror.enabled = true` on trusted clusters. |

Full guide: [`docs/v3-topology-recommendations.md`](docs/v3-topology-recommendations.md).

Public node join endpoints require a real public API host: either
`control_plane_endpoint`, a public control-plane load balancer, or public
IPv4/IPv6 on the control-plane nodes. IPv6-only public joins are valid; private
control planes without one of those hosts are rejected during validation.

### v3 Readiness Checklist

Before applying a v3 upgrade, confirm:

- Current state is backed up with `terraform state pull`.
- Removed v2 inputs are gone and renamed booleans with inverted meaning are reviewed.
- In-place v2 upgrades keep the default `network_subnet_mode = "per_nodepool"` unless subnet resource changes are intentional.
- `terraform validate` or `tofu validate` passes before planning.
- `terraform plan` has no unexpected `delete`, `replace`, or `forces replacement` actions.
- Network, subnet, load balancer, NAT router, placement group, server, and volume changes are intentional.
- Private-only, Robot/vSwitch, external-network, Tailscale/overlay, Longhorn, and autoscaler clusters have a rollback or blue/green plan.

---

## ✨ Features

<table>
<tr>
<td width="50%" valign="top">

### 🚀 Core Platform
- [x] **Maintenance-free** — Auto-upgrades OS & k3s with rollback
- [x] **Multi-architecture** — Mix x86 and ARM (CAX) for cost savings
- [x] **Private networking** — Secure, low-latency node communication
- [x] **SELinux hardened** — Pre-configured security policies

### 🌐 Networking & CNI
- [x] **CNI flexibility** — Flannel, Calico, or Cilium
- [x] **Cilium XDP** — Hardware-level load balancing
- [x] **Cilium Gateway API** — Native Gateway API controller support
- [x] **WireGuard encryption** — Optional encrypted overlay
- [x] **Dual-stack** — Full IPv4 & IPv6 support
- [x] **Custom subnets** — Define CIDR blocks per nodepool
- [ ] **Cilium multinetwork scale** — Experimental public-overlay preview, not production-supported yet

### ⚖️ Load Balancing
- [x] **Ingress controllers** — Traefik, Nginx, or HAProxy
- [x] **Proxy Protocol** — Preserve client IPs
- [x] **Flexible LB** — Hetzner LB or Klipper

</td>
<td width="50%" valign="top">

### 🔄 High Availability
- [x] **HA by default** — 3 control-planes + 2 agents across AZs
- [x] **Super-HA** — Span multiple Hetzner locations
- [x] **Cluster autoscaler** — Automatic node scaling
- [x] **Embedded registry mirror** — Opt-in k3s/RKE2 Spegel mirror for trusted large clusters
- [x] **Single-node mode** — Perfect for development

### 💾 Storage
- [x] **Hetzner CSI** — Native block storage with encryption
- [x] **Longhorn** — Distributed storage with replication
- [x] **Custom mount paths** — Configurable storage locations

### 🔒 Security & Operations
- [x] **Audit logging** — Configurable retention policies
- [x] **Firewall rules** — Granular SSH/API access control
- [x] **NAT router** — Fully private clusters
- [x] **Plan-time validation** — Terraform/OpenTofu rejects invalid config combinations early
- [x] **190+ variables** — Fine-tune everything
- [x] **User kustomizations** — Ordered custom manifests with hooks

</td>
</tr>
</table>

---

## 🔐 Security

### MicroOS / Leap Micro Hardening
- **Immutable base OS:** Leap Micro and MicroOS use transactional updates and read-only system partitions by default, reducing host drift and limiting persistence for unauthorized changes.
- **Reduced host surface:** Cluster nodes are treated as appliance-style Kubernetes hosts; operational changes should flow through Terraform and Kubernetes manifests rather than ad-hoc host mutation.
- **SELinux integration:** The module includes SELinux handling for K3s/RKE2 bootstrap paths, with explicit controls and troubleshooting guidance for strict environments.

### Network Isolation
- **Default deny posture for cluster ingress:** Firewall rules are explicit and can be narrowed to trusted source ranges (`myipv4`/allowlists) for SSH and Kubernetes API exposure.
- **Private cluster topology support:** You can run with private networking and NAT routing patterns to minimize directly exposed node interfaces.
- **Load balancer boundary controls:** Control plane and ingress load balancer exposure can be restricted and combined with firewall source controls to reduce public attack surface.

### RKE2 Security Posture
- **CNCF-conformant distribution option:** RKE2 is supported as a first-class Kubernetes distribution choice in this module.
- **Compliance-oriented operation:** RKE2 is designed for hardened, regulated environments and supports CIS-focused deployment patterns.
- **Certification visibility:** For current security certifications/compliance mappings, reference the upstream RKE2 documentation and release notes as authoritative sources.

## 🏁 Getting Started

### Prerequisites

<table>
<tr>
<th>Platform</th>
<th>Installation Command</th>
</tr>
<tr>
<td><strong>Homebrew</strong> (macOS/Linux)</td>
<td><code>brew install opentofu hashicorp/tap/packer kubectl hcloud</code><br><small>Optional Terraform CLI: <code>brew install hashicorp/tap/terraform</code></small></td>
</tr>
<tr>
<td><strong>Arch Linux</strong></td>
<td><code>yay -S terraform packer kubectl hcloud</code></td>
</tr>
<tr>
<td><strong>Debian/Ubuntu</strong></td>
<td><code>sudo apt install terraform packer kubectl</code></td>
</tr>
<tr>
<td><strong>Fedora/RHEL</strong></td>
<td><code>sudo dnf install terraform packer kubectl</code></td>
</tr>
<tr>
<td><strong>Windows</strong></td>
<td><code>choco install terraform packer kubernetes-cli hcloud</code></td>
</tr>
</table>

> **Required tools:** [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) or [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.10.1 (`brew install opentofu`), [packer](https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli#installing-packer) (initial setup only), [kubectl](https://kubernetes.io/docs/tasks/tools/), [hcloud](https://github.com/hetznercloud/cli). The module requires `hetznercloud/hcloud` provider >= 1.62.0.

OpenTofu is officially supported. Pull requests are validated in CI with both Terraform and OpenTofu, including real Hetzner preset apply/health/destroy tests when Hetzner E2E is enabled.

### Plan-Time Validation

Kube-Hetzner uses Terraform/OpenTofu input validation as the module contract. Run `terraform plan` or `tofu plan` before every apply; invalid combinations fail before resources are created.

The validation layer checks pure configuration invariants: non-empty tokens and SSH keys, supported regions and locations, CIDR syntax and IP-family pairs, nodepool name/count rules, odd control-plane quorum, Hetzner network/subnet/placement-group limits, multi-network join requirements, autoscaler boundaries, Cilium-only options, load balancer dependencies, firewall source formats, Robot/vSwitch/NAT requirements, audit settings, YAML snippets, and attached volume definitions.

When validating the module itself with both CLIs in the same checkout, run OpenTofu in a temporary copy so its ignored lock file and plugin cache never disturb Terraform's local state:

```bash
tmpdir="$(mktemp -d)"
rsync -a --exclude .git --exclude .terraform --exclude .terraform-tofu ./ "$tmpdir"/
(cd "$tmpdir" && tofu init -backend=false && tofu validate)
rm -rf "$tmpdir"
```

Provider/runtime assertions still belong in resource preconditions, postconditions, or checks. If an invariant can be decided from module inputs, it should be enforced at this plan-time validation layer.

---

### ⚡ Quick Start

<table>
<tr>
<td>1️⃣</td>
<td><strong>Create a Hetzner project</strong> at <a href="https://console.hetzner.cloud/">console.hetzner.cloud</a> and grab an API token (Read & Write)</td>
</tr>
<tr>
<td>2️⃣</td>
<td><strong>Generate an SSH key pair</strong> (passphrase-less ed25519) — or see <a href="docs/ssh.md">SSH options</a></td>
</tr>
<tr>
<td>3️⃣</td>
<td><strong>Run the setup script</strong> — creates your project folder and OS snapshots (Leap Micro recommended):</td>
</tr>
</table>

```sh
tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"
```

<details>
<summary><strong>Fish shell version</strong></summary>

```fish
set tmp_script (mktemp); curl -sSL -o "{tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh; chmod +x "{tmp_script}"; bash "{tmp_script}"; rm "{tmp_script}"
```
</details>

<details>
<summary><strong>Save as alias for future use</strong></summary>

```sh
alias createkh='tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"'
```
</details>

<details>
<summary><strong>What the script does</strong></summary>

```sh
mkdir /path/to/your/new/folder
cd /path/to/your/new/folder
curl -sL https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/kube.tf.example -o kube.tf
curl -sL https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/packer-template/hcloud-leapmicro-snapshots.pkr.hcl -o hcloud-leapmicro-snapshots.pkr.hcl
curl -sL https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/packer-template/hcloud-microos-snapshots.pkr.hcl -o hcloud-microos-snapshots.pkr.hcl
export HCLOUD_TOKEN="your_hcloud_token"
packer init hcloud-leapmicro-snapshots.pkr.hcl
for distro in k3s rke2; do
  packer build -var "selinux_package_to_install=${distro}" hcloud-leapmicro-snapshots.pkr.hcl
done
# (optional legacy)
# packer init hcloud-microos-snapshots.pkr.hcl
# packer build hcloud-microos-snapshots.pkr.hcl
hcloud context create <project-name>
```
</details>

<table>
<tr>
<td>4️⃣</td>
<td><strong>Customize your <code>kube.tf</code></strong> — full reference in <a href="docs/terraform.md">terraform.md</a></td>
</tr>
</table>

---

### 🎯 Deploy

```sh
cd <your-project-folder>
terraform init --upgrade
terraform validate
terraform plan
terraform apply -auto-approve
```

OpenTofu works the same way:

```sh
tofu init --upgrade
tofu validate
tofu plan
tofu apply -auto-approve
```

**~5 minutes later:** Your cluster is ready! 🎉

> ⚠️ Once Terraform manages your cluster, avoid manual changes in the Hetzner UI. Use `hcloud` CLI to inspect resources.

---

## 🔧 Usage

View cluster details:
```sh
terraform output kubeconfig
terraform output -json kubeconfig | jq
```

### Connect via SSH

```sh
ssh root@<control-plane-ip> -i /path/to/private_key -o StrictHostKeyChecking=no
```

Restrict SSH access by configuring `firewall_ssh_source` in your kube.tf (default is `["myipv4"]`). For CI/CD runners, override it with your runner CIDRs. See [SSH docs](docs/ssh.md#firewall-ssh-source-and-changing-ips) for dynamic IP handling.

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

## 🌐 CNI Options

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

## 📈 Scaling

### Manual Scaling

Adjust `count` in any nodepool and run `terraform apply`. Constraints:

- First control-plane nodepool minimum: **1**
- Drain nodes before removing: `kubectl drain <node-name>`
- Only remove nodepools from the **end** of the list
- Rename nodepools only when count is **0**

**Advanced:** Replace `count` with a `nodes` map for individual node control—see `kube.tf.example`.

### Autoscaling

Enable with `autoscaler_nodepools`. Powered by [Cluster Autoscaler](https://github.com/kubernetes/autoscaler).

> ⚠️ Autoscaled nodes use a snapshot from the initial control plane. Ensure disk sizes match.
> Longhorn storage should stay on static agent nodepools. Autoscaled Longhorn volumes require a write-capable Hetzner token in node user-data and leave detached volumes behind on scale-down.

---

## 🛡️ High Availability

Default: **3 control-planes + 3 agents** with automatic upgrades.

| Control Planes | Recommendation |
|----------------|----------------|
| 3+ (odd numbers) | Full HA with quorum maintenance |
| 2 | Disable auto OS upgrades, manual maintenance |
| 1 | Development only, disable auto upgrades |

See [Rancher's HA documentation](https://rancher.com/docs/k3s/latest/en/installation/ha-embedded/).

---

## 🔄 Automatic Upgrades

### OS Upgrades (Leap Micro / MicroOS)

Handled by [Kured](https://github.com/kubereboot/kured)—safe, HA-aware reboots. Configure timeframes via [Kured options](https://kured.dev/docs/configuration/).

### K3s Upgrades

Managed by [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller). Customize the [upgrade plan template](templates/plans.yaml.tpl).

### Disable Automatic Upgrades

```tf
# Disable OS upgrades (required for <3 control planes)
automatically_upgrade_os = false

# Disable k3s upgrades
automatically_upgrade_kubernetes = false
```

<details>
<summary><strong>Manual upgrade commands</strong></summary>

**Selective k3s upgrade:**
```sh
kubectl label --overwrite node <node-name> k3s_upgrade=true
kubectl label node <node-name> k3s_upgrade-  # disable
```

**Or delete upgrade plans:**
```sh
kubectl delete plan k3s-agent -n system-upgrade
kubectl delete plan k3s-server -n system-upgrade
```

**Manual OS upgrade:**
```sh
kubectl drain <node-name>
ssh root@<node-ip>
systemctl start transactional-update.service
reboot
```
</details>

### Component Upgrades

Use the `kustomization_backup.yaml` file created during installation:

1. Copy to `kustomization.yaml`
2. Update source URLs to latest versions
3. Apply: `kubectl apply -k ./`

---

## ⚙️ Customization

Most components use [Helm Chart](https://rancher.com/docs/k3s/latest/en/helm/) definitions via k3s Helm Controller.

See `kube.tf.example` for examples.

---

## 🖥️ Dedicated Servers

Integrate Hetzner Robot servers via [the dedicated server guide](docs/add-robot-server.md).

---

## ➕ Adding Extras

Use [Kustomize](https://kustomize.io) for additional deployments:

1. Create a source folder (default: `extra-manifests`) with your `kustomization.yaml.tpl` and manifests.
2. Configure one or more ordered sets with `user_kustomizations`.
3. Each set supports template parameters, optional pre-commands, and post-commands.
4. Sets are applied sequentially with `kubectl apply -k`.

---

## 📚 Examples

Repository examples:

- [`examples/argocd`](examples/argocd/) — configure Kubernetes/Helm providers from `kubeconfig_data` and install ArgoCD.
- [`examples/tailscale-node-transport`](examples/tailscale-node-transport/) — opt-in Tailscale node transport for secure single-network clusters and private multinetwork scale-out.
- [`examples/cilium-gateway-api`](examples/cilium-gateway-api/) — Cilium Gateway API, Gateway, HTTPRoute, and cert-manager HTTP-01.
- [`examples/cilium-multinetwork`](examples/cilium-multinetwork/) — experimental Cilium-only public-overlay preview across multiple Hetzner Cloud Networks.
- [`examples/external-overlay-tailscale`](examples/external-overlay-tailscale/) — user-owned Tailscale operator access with `node_connection_overrides`.
- [`examples/kustomization_user_deploy`](examples/kustomization_user_deploy/) — ordered `user_kustomizations` sets.
- [`examples/tls`](examples/tls/) — basic Ingress TLS resources for Traefik and cert-manager.

<details>
<summary><strong>Custom post-install actions (ArgoCD, etc.)</strong></summary>

For CRD-dependent applications:

```tf
user_kustomizations = {
  "1" = {
    source_folder = "extra-manifests"
    kustomize_parameters = {
      target_namespace = "argocd"
    }
    pre_commands = ""
    post_commands = <<-EOT
      kubectl -n argocd wait --for condition=established --timeout=120s crd/appprojects.argoproj.io
      kubectl -n argocd wait --for condition=established --timeout=120s crd/applications.argoproj.io
      kubectl apply -f /var/user_kustomize/1/argocd-projects.yaml
      kubectl apply -f /var/user_kustomize/1/argocd-application-argocd.yaml
    EOT
  }
}
```
</details>

<details>
<summary><strong>Useful Cilium commands</strong></summary>

```sh
# Status
kubectl -n kube-system exec --stdin --tty cilium-xxxx -- cilium status --verbose

# Monitor traffic
kubectl -n kube-system exec --stdin --tty cilium-xxxx -- cilium monitor

# List services
kubectl -n kube-system exec --stdin --tty cilium-xxxx -- cilium service list
```

[Full Cilium cheatsheet](https://docs.cilium.io/en/latest/cheatsheet)
</details>

<details>
<summary><strong>Cilium Egress Gateway with Floating IPs</strong></summary>

Control outgoing traffic with static IPs:

```tf
{
  name        = "egress",
  server_type = "cx23",
  location    = "nbg1",
  labels      = ["node.kubernetes.io/role=egress"],
  taints      = ["node.kubernetes.io/role=egress:NoSchedule"],
  floating_ip = true,
  count       = 1
}
```

Configure Cilium:
```tf
locals {
  cluster_ipv4_cidr = "10.42.0.0/16"
}

cluster_ipv4_cidr = local.cluster_ipv4_cidr
enable_kube_proxy = false

cilium_values = <<-EOT
ipam:
  mode: kubernetes
k8s:
  requireIPv4PodCIDR: true
kubeProxyReplacement: true
routingMode: native
ipv4NativeRoutingCIDR: "10.0.0.0/8"
endpointRoutes:
  enabled: true
loadBalancer:
  acceleration: native
bpf:
  masquerade: true
egressGateway:
  enabled: true
MTU: 1450
EOT

Cilium Egress Gateway requires kube-proxy replacement, so keep `enable_kube_proxy = false` when enabling it.

# Optional: keep selected egress policies pinned to a Ready egress node automatically
cilium_egress_gateway_ha_enabled = true
```

Example policy:
```yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-sample
  labels:
    kube-hetzner.io/egress-ha: "true"
spec:
  selectors:
    - podSelector:
        matchLabels:
          org: empire
          class: mediabot
          io.kubernetes.pod.namespace: default
  destinationCIDRs:
    - "0.0.0.0/0"
  excludedCIDRs:
    - "10.0.0.0/8"
  egressGateway:
    nodeSelector:
      matchLabels:
        node.kubernetes.io/role: egress
    egressIP: { FLOATING_IP }
```

[Full Egress Gateway docs](https://docs.cilium.io/en/stable/network/egress-gateway/)
</details>

<details>
<summary><strong>Cilium Gateway API</strong></summary>

Cilium can own Gateway API directly:

```tf
cni_plugin                 = "cilium"
enable_kube_proxy         = false
cilium_gateway_api_enabled = true
```

When enabled, kube-hetzner installs the standard Gateway API CRDs for the
selected Cilium line, enables `gatewayAPI.enabled` in Cilium values, and enables
cert-manager Gateway API support. This is separate from Traefik's Kubernetes
Gateway provider. Choose one Gateway API controller per cluster; v3 rejects
enabling Cilium Gateway API and Traefik's Gateway provider at the same time.

Use [`examples/cilium-gateway-api`](examples/cilium-gateway-api/) for a working
GatewayClass/Gateway/HTTPRoute/cert-manager HTTP-01 starting point.

</details>

<details>
<summary><strong>Embedded Registry Mirror</strong></summary>

k3s and RKE2 can use their embedded Spegel registry mirror to share images
between trusted cluster nodes:

```tf
embedded_registry_mirror = {
  enabled                  = true
  registries               = ["docker.io", "registry.k8s.io", "ghcr.io", "quay.io"]
  disable_default_endpoint = false
}
```

kube-hetzner sets `embedded-registry: true` on server nodes and merges empty
mirror entries into the effective `registries.yaml`. Existing
`registries_config` entries and endpoints are preserved.

This is opt-in because the mirror assumes equal node trust. Images pulled with
credentials on one node may be shared with other nodes, and tags can be poisoned
by a node that can place images in containerd. Use digest-pinned images for
critical workloads. In Tailscale multinetwork clusters, advertised node-private
routes are required so the mirror can reach peers across Network shards.

</details>

<details>
<summary><strong>TLS with Cert-Manager (recommended)</strong></summary>

Cert-Manager handles HA certificate management (Traefik CE is stateless).

1. [Configure your issuer](https://cert-manager.io/docs/configuration/acme/)
2. Add annotations to Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  tls:
    - hosts:
        - "*.example.com"
      secretName: example-com-letsencrypt-tls
  rules:
    - host: "*.example.com"
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
```

[Full Traefik + Cert-Manager guide](https://traefik.io/blog/secure-web-applications-with-traefik-proxy-cert-manager-and-lets-encrypt/)

> **Ingress-Nginx with HTTP challenge:** Add `load_balancer_hostname = "cluster.example.org"` to work around [this known issue](https://github.com/cert-manager/cert-manager/issues/466).
</details>

<details>
<summary><strong>Managing snapshots</strong></summary>

**Create (recommended):**
```sh
export HCLOUD_TOKEN=<your-token>
for distro in k3s rke2; do
  packer build -var "selinux_package_to_install=${distro}" ./packer-template/hcloud-leapmicro-snapshots.pkr.hcl
done
```

**Create (legacy MicroOS):**
```sh
export HCLOUD_TOKEN=<your-token>
packer build ./packer-template/hcloud-microos-snapshots.pkr.hcl
```

**Delete:**
```sh
hcloud image list
hcloud image delete <image-id>
```
</details>

<details>
<summary><strong>Custom OS snapshots per nodepool</strong></summary>

Override the default OS snapshot on any nodepool or individual node with `os_snapshot_id`:

```tf
agent_nodepools = [
  {
    name        = "storage",
    server_type = "cx33",
    location    = "nbg1",
    labels      = ["node.kubernetes.io/server-usage=storage"],
    taints      = [],
    count       = 1
    os_snapshot_id = "348644983"  # Custom snapshot with LVM partitions
  },
]
```

Per-node override (in a `nodes` map):
```tf
nodes = {
  "0" : { os_snapshot_id = "348644983" },
  "1" : {},  # uses nodepool or global default
}
```

> **Caution:** You are responsible for ensuring the snapshot ID matches the correct `os` type (`leapmicro`/`microos`) and node architecture (x86 for `cx*`/`cpx*` servers, ARM for `cax*` servers). A mismatched snapshot will cause provisioning failures.

When not set, the module automatically selects the most recent snapshot matching the node's `os` and architecture.
</details>

<details>
<summary><strong>Single-node development cluster</strong></summary>

Set `automatically_upgrade_os = false` (attached volumes don't handle auto-reboots well).

Uses k3s [service load balancer](https://rancher.com/docs/k3s/latest/en/networking/#service-load-balancer) instead of external LB. Ports 80 & 443 open automatically.
</details>

<details>
<summary><strong>Terraform Cloud deployment</strong></summary>

1. Create a Leap Micro snapshot in your project first (or MicroOS if you explicitly use it)
2. Configure SSH keys as Terraform Cloud variables (mark private key as sensitive):

```tf
ssh_public_key  = var.ssh_public_key
ssh_private_key = var.ssh_private_key
```

> **Password-protected keys:** Requires `local` execution mode with your own agent.
</details>

<details>
<summary><strong>HelmChartConfig customization</strong></summary>

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rancher
  namespace: kube-system
spec:
  valuesContent: |-
    # Your values.yaml customizations here
```

Works for all add-ons: Longhorn, Cert-manager, Traefik, etc.
</details>

<details>
<summary><strong>Encryption at rest (HCloud CSI)</strong></summary>

Create secret:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: encryption-secret
  namespace: kube-system
stringData:
  encryption-passphrase: foobar
```

Create storage class:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hcloud-volumes-encrypted
provisioner: csi.hetzner.cloud
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  csi.storage.k8s.io/node-publish-secret-name: encryption-secret
  csi.storage.k8s.io/node-publish-secret-namespace: kube-system
```
</details>

<details>
<summary><strong>Encryption at rest (Longhorn)</strong></summary>

Create secret:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-crypto
  namespace: longhorn-system
stringData:
  CRYPTO_KEY_VALUE: "your-encryption-key"
  CRYPTO_KEY_PROVIDER: "secret"
  CRYPTO_KEY_CIPHER: "aes-xts-plain64"
  CRYPTO_KEY_HASH: "sha256"
  CRYPTO_KEY_SIZE: "256"
  CRYPTO_PBKDF: "argon2i"
```

Create storage class:
```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: longhorn-crypto-global
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  nodeSelector: "node-storage"
  numberOfReplicas: "1"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: ext4
  encrypted: "true"
  csi.storage.k8s.io/provisioner-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/provisioner-secret-namespace: "longhorn-system"
  csi.storage.k8s.io/node-publish-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/node-publish-secret-namespace: "longhorn-system"
  csi.storage.k8s.io/node-stage-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/node-stage-secret-namespace: "longhorn-system"
```

[Longhorn encryption docs](https://longhorn.io/docs/1.4.0/advanced-resources/security/volume-encryption/)
</details>

<details>
<summary><strong>Namespace-based architecture assignment</strong></summary>

Enable admission controllers:
```tf
control_plane_exec_args = "--kube-apiserver-arg enable-admission-plugins=PodTolerationRestriction,PodNodeSelector"
```

Assign namespace to architecture:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/node-selector: kubernetes.io/arch=amd64
  name: this-runs-on-amd64
```

With tolerations:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/node-selector: kubernetes.io/arch=arm64
    scheduler.alpha.kubernetes.io/defaultTolerations: '[{ "operator" : "Equal", "effect" : "NoSchedule", "key" : "workload-type", "value" : "machine-learning" }]'
  name: this-runs-on-arm64
```
</details>

<details>
<summary><strong>Backup and restore cluster (etcd S3)</strong></summary>

**Setup backup:**

1. Configure `etcd_s3_backup` in kube.tf
2. Add cluster_token output:

```tf
output "cluster_token" {
  value     = module.kube-hetzner.cluster_token
  sensitive = true
}
```

**Restore:**

1. Add restoration config to kube.tf:

```tf
locals {
  cluster_token = var.cluster_token
  etcd_version = "v3.5.9"
  etcd_snapshot_name = "name-of-the-snapshot"
  etcd_s3_endpoint = "your-s3-endpoint"
  etcd_s3_bucket = "your-s3-bucket"
  etcd_s3_access_key = "your-s3-access-key"
  etcd_s3_secret_key = var.etcd_s3_secret_key
}

variable "cluster_token" {
  sensitive = true
  type      = string
}

variable "etcd_s3_secret_key" {
  sensitive = true
  type      = string
}

module "kube-hetzner" {
  cluster_token = local.cluster_token

  postinstall_exec = compact([
    (
      local.etcd_snapshot_name == "" ? "" :
      <<-EOF
      export CLUSTERINIT=$(cat /etc/rancher/k3s/config.yaml | grep -i '"cluster-init": true')
      if [ -n "$CLUSTERINIT" ]; then
        k3s server \
          --cluster-reset \
          --etcd-s3 \
          --cluster-reset-restore-path=${local.etcd_snapshot_name} \
          --etcd-s3-endpoint=${local.etcd_s3_endpoint} \
          --etcd-s3-bucket=${local.etcd_s3_bucket} \
          --etcd-s3-access-key=${local.etcd_s3_access_key} \
          --etcd-s3-secret-key=${local.etcd_s3_secret_key}
        mv /etc/rancher/k3s/k3s.yaml /etc/rancher/k3s/k3s.backup.yaml

        ETCD_VER=${local.etcd_version}
        case "$(uname -m)" in
            aarch64) ETCD_ARCH="arm64" ;;
            x86_64) ETCD_ARCH="amd64" ;;
        esac;
        DOWNLOAD_URL=https://github.com/etcd-io/etcd/releases/download
        curl -L $DOWNLOAD_URL/$ETCD_VER/etcd-$ETCD_VER-linux-$ETCD_ARCH.tar.gz -o /tmp/etcd-$ETCD_VER-linux-$ETCD_ARCH.tar.gz
        tar xzvf /tmp/etcd-$ETCD_VER-linux-$ETCD_ARCH.tar.gz -C /usr/local/bin --strip-components=1

        nohup etcd --data-dir /var/lib/rancher/k3s/server/db/etcd &
        echo $! > save_pid.txt

        etcdctl del /registry/services/specs/traefik/traefik
        etcdctl del /registry/services/endpoints/traefik/traefik

        OLD_NODES=$(etcdctl get "" --prefix --keys-only | grep /registry/minions/ | cut -c 19-)
        for NODE in $OLD_NODES; do
          for KEY in $(etcdctl get "" --prefix --keys-only | grep $NODE); do
            etcdctl del $KEY
          done
        done

        kill -9 `cat save_pid.txt`
        rm save_pid.txt
      fi
      EOF
    )
  ])
}
```

2. Set environment variables:
```sh
export TF_VAR_cluster_token="..."
export TF_VAR_etcd_s3_secret_key="..."
```

3. Run `terraform apply`
</details>

<details>
<summary><strong>Pre-constructed private network (proxies)</strong></summary>

```tf
resource "hcloud_network" "k3s_proxied" {
  name     = "k3s-proxied"
  ip_range = "10.0.0.0/8"
}

resource "hcloud_network_subnet" "k3s_proxy" {
  network_id   = hcloud_network.k3s_proxied.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.128.0.0/9"
}

resource "hcloud_server" "your_proxy_server" { ... }

resource "hcloud_server_network" "your_proxy_server" {
  depends_on = [hcloud_server.your_proxy_server]
  server_id  = hcloud_server.your_proxy_server.id
  network_id = hcloud_network.k3s_proxied.id
  ip         = "10.128.0.1"
}

module "kube-hetzner" {
  existing_network = { id = hcloud_network.k3s_proxied.id }  # Note: object required!
  network_ipv4_cidr = "10.0.0.0/9"
  additional_kubernetes_install_environment = {
    "http_proxy" : "http://10.128.0.1:3128",
    "HTTP_PROXY" : "http://10.128.0.1:3128",
    "HTTPS_PROXY" : "http://10.128.0.1:3128",
    "CONTAINERD_HTTP_PROXY" : "http://10.128.0.1:3128",
    "CONTAINERD_HTTPS_PROXY" : "http://10.128.0.1:3128",
    "NO_PROXY" : "127.0.0.0/8,10.0.0.0/8,",
  }
}
```
</details>

<details>
<summary><strong>Tailscale node transport</strong></summary>

Tailscale node transport is useful even before a cluster outgrows one Hetzner
Network. In a normal single-network cluster it gives Terraform, kubeconfig, and
operator SSH a private Tailnet path, so you can close public Kubernetes API and
SSH firewall rules without introducing a separate bastion workflow. Kubernetes
still keeps Hetzner private node IPs, so Hetzner CCM, CSI, and Load Balancers
continue to see provider-owned addresses instead of Tailnet `100.64.0.0/10`
addresses.

For clusters that need more than one Hetzner Cloud Network, the same transport
becomes the production v3 scale-out path. Hetzner Networks still cap attached
resources per Network and do not route separate Networks together. Tailscale
fills that gap by advertising each node's own Hetzner private `/32` route into
the Tailnet and accepting those routes on every node.

Tailscale mode does not require exposing Kubernetes itself to the web. The
recommended large-cluster shape keeps public Kubernetes API and SSH firewall
rules closed, disables managed public ingress unless you explicitly need it,
and uses the Tailnet for operator/API/node transport. Nodes may still have
public IPv4/IPv6 enabled so they can bootstrap Tailscale and form direct
WireGuard paths; the public firewall opens Tailscale UDP/41641, not Kubernetes
API, SSH, or HTTP/S. A truly no-public-IP multinetwork topology needs private
egress and externally managed Tailscale bootstrap for every external Network;
the module NAT router covers only the primary kube-hetzner Network.

Minimal secure single-network shape:

```tf
node_transport_mode = "tailscale"

tailscale_auth_key = var.tailscale_auth_key

tailscale_node_transport = {
  # cloud_init brings Tailscale up before Terraform starts using SSH.
  bootstrap_mode  = "cloud_init"
  magicdns_domain = "example-tailnet.ts.net"
  auth = {
    mode = "auth_key"
  }
  routing = {
    # Single-network clusters already have Hetzner private reachability between
    # nodes, so route approval is optional. Leave this true for multinetwork.
    advertise_node_private_routes = false
  }
}

# Tailscale mode deliberately rejects public world-open API/SSH defaults.
firewall_kube_api_source = null
firewall_ssh_source      = null
```

Multinetwork scale-out adds external `network_id` values and requires approved
node-private routes:

```tf
node_transport_mode = "tailscale"

# Use a reusable shared key, or role-specific keys when autoscaler nodes should
# use a reusable ephemeral key while static nodes use durable tagged keys.
tailscale_auth_key = var.tailscale_auth_key
# tailscale_control_plane_auth_key = var.tailscale_control_plane_auth_key
# tailscale_agent_auth_key         = var.tailscale_agent_auth_key
# tailscale_autoscaler_auth_key    = var.tailscale_autoscaler_auth_key

tailscale_node_transport = {
  bootstrap_mode  = "cloud_init" # required when autoscaler_nodepools are used
  magicdns_domain = "example-tailnet.ts.net"
  auth = {
    mode = "auth_key"
    # Tagged nodes are recommended for production ACLs and route auto-approval,
    # but tags must be owned/permitted in your Tailnet policy before use.
    # advertise_tags_control_plane = ["tag:kube-hetzner-control-plane"]
    # advertise_tags_agent         = ["tag:kube-hetzner-agent"]
    # advertise_tags_autoscaler    = ["tag:kube-hetzner-autoscaler"]
  }
  routing = {
    advertise_node_private_routes = true
  }
}

agent_nodepools = [
  {
    name        = "agent-small-a"
    server_type = "cx23"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 50
    # network_id omitted/null means the primary kube-hetzner network.
  },
  {
    name        = "agent-small-b"
    server_type = "cx23"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 50
    network_id  = 11959154 # existing external private network id
  },
]

autoscaler_nodepools = [
  {
    name        = "autoscaled-a"
    server_type = "cx23"
    location    = "nbg1"
    min_nodes   = 0
    max_nodes   = 50
  },
  {
    name        = "autoscaled-b"
    server_type = "cx23"
    location    = "nbg1"
    min_nodes   = 0
    max_nodes   = 50
    network_id  = 11959154
  },
]
```

Large-scale reference layouts live in
[`examples/tailscale-node-transport`](./examples/tailscale-node-transport/):

- [`large-scale-200.tf.example`](./examples/tailscale-node-transport/large-scale-200.tf.example)
  shows 200 total nodes across two Hetzner Networks while keeping each Network
  at exactly 100 attachments.
- [`massive-10000-nodes.tf.example`](./examples/tailscale-node-transport/massive-10000-nodes.tf.example)
  shows the reference topology for 10,000 total nodes: 3 control planes, 7
  static system agents, 90 autoscaled primary workers, and 99 external
  100-node autoscaler shards. This is a quota/design reference, not a casual
  default; it requires Hetzner capacity approvals, Tailnet policy/device
  capacity, and production Kubernetes scale planning.

The important constraints are enforced during `terraform plan`:

- `node_transport_mode = "tailscale"` is mutually exclusive with
  `multinetwork_mode = "cilium_public_overlay"`.
- Control planes always stay on the primary kube-hetzner network and no longer
  accept `network_id`.
- Static agents and autoscaler nodepools may use `network_id` to spread across
  existing Hetzner private Networks.
- Control planes are not auto-attached to every external agent Network, avoiding
  Hetzner's 3-Networks-per-server limit.
- The module can advertise each node's Hetzner private `/32` route through
  Tailscale, accepts Tailnet routes on nodes, and disables Tailscale
  subnet-route SNAT so Kubernetes/CNI traffic keeps the real Hetzner node
  source IP.
- Single-network clusters may set
  `tailscale_node_transport.routing.advertise_node_private_routes = false` to
  avoid Tailnet route approvals. External `network_id` nodepools require the
  default `true`.
- For multinetwork clusters, Tailnet ACLs must auto-approve node-private routes
  for the users, groups, or node tags you use, or the cluster will wait for
  manual route approval. Tags are optional in `auth_key` mode, but they are the
  cleanest production ACL boundary once `tagOwners` and `autoApprovers` are
  configured.
- With `auth.mode = "auth_key"`, use a reusable `tailscale_auth_key` for one
  shared key, or role-specific keys (`tailscale_control_plane_auth_key`,
  `tailscale_agent_auth_key`, `tailscale_autoscaler_auth_key`). A single-use
  key only registers the first node. Prefer a reusable, pre-approved, tagged,
  ephemeral key for autoscaler nodes.
- With `auth.mode = "oauth_client_secret"`, the module passes role-specific
  OAuth auth-key parameters: static nodes default to durable devices and
  autoscaler-created nodes default to ephemeral devices.
- Tailscale mode rejects world-open `firewall_kube_api_source` and
  `firewall_ssh_source`; use `null` for no public API/SSH rule or restrict to
  explicit CIDRs.
- Public module-managed control-plane Load Balancers are rejected in Tailscale
  mode. Private control-plane Load Balancers remain available for single-network
  HA/API patterns; kubeconfig still defaults to the first control plane's
  Tailnet MagicDNS endpoint unless you set an explicit endpoint.
- `autoscaler_nodepools` require `tailscale_node_transport.bootstrap_mode =
  "cloud_init"` because autoscaler-created nodes cannot be configured by
  Terraform remote-exec before joining.
- The module NAT router can be combined with Tailscale only for
  single-primary-network private egress. It does not provide egress for
  external Hetzner Networks, so multinetwork Tailscale nodepools need their own
  public IPv4/IPv6 egress. Do not set `nat_router` for external-network
  Tailscale topologies in this release.
- Managed Hetzner private Load Balancers work for single-primary-network
  Tailscale clusters. They still cannot span external nodepool Networks; when
  using `network_id` scale-out, use public LB targets, Klipper, no/custom
  ingress, or an external load balancer.

The older `multinetwork_mode = "cilium_public_overlay"` path remains as a
gated lab preview for Cilium-only public transport experiments. Prefer
Tailscale node transport for real private multinetwork clusters.
</details>

<details>
<summary><strong>Placement groups</strong></summary>

Assign nodepools to placement groups:

```tf
agent_nodepools = [
  {
    ...
    placement_group = "special"
  },
]
```

Legacy compatibility:
```tf
placement_group_index = 1
```

Count-based nodepools without an explicit `placement_group` are automatically
sharded into spread groups of 10 servers. Hetzner projects also cap placement
groups at 50 total, so very large static clusters must either disable placement
groups, split across projects/clusters, or use autoscaler nodepools for burst
capacity. kube-hetzner does not currently assign Hetzner Placement Groups to
autoscaler-created nodes. If you set an explicit `placement_group`, split
groups manually:
```tf
agent_nodepools = [
  {
    nodes = {
      "0"  : { placement_group = "pg-1" },
      "30" : { placement_group = "pg-2" },
    }
  },
]
```

Disable globally: `enable_placement_groups = false`
</details>

<details>
<summary><strong>Migrating from count to map-based nodes</strong></summary>

Set `append_index_to_node_name = false` to avoid node replacement:

```tf
agent_nodepools = [
  {
    name        = "agent-large",
    server_type = "cx33",
    location    = "nbg1",
    labels      = [],
    taints      = [],
    nodes = {
      "0" : {
        append_index_to_node_name = false,
        labels = ["my.extra.label=special"],
        placement_group = "agent-large-pg-1",
      },
      "1" : {
        append_index_to_node_name = false,
        server_type = "cx43",
        labels = ["my.extra.label=slightlybiggernode"],
        placement_group = "agent-large-pg-2",
      },
    }
  },
]
```
</details>

<details>
<summary><strong>Delete protection</strong></summary>

Protect resources from accidental deletion via Hetzner Console/API:

```tf
enable_delete_protection = {
  floating_ip   = true
  load_balancer = true
  volume        = true
}
```

> Note: Terraform can still delete resources (provider lifts the lock).
</details>

<details>
<summary><strong>Private-only cluster (WireGuard)</strong></summary>

Requirements:
1. Pre-configured network
2. NAT gateway with public IP ([Hetzner guide](https://community.hetzner.com/tutorials/how-to-set-up-nat-for-cloud-networks))
3. WireGuard VPN access ([Hetzner guide](https://docs.hetzner.com/cloud/apps/list/wireguard/))
4. Route `0.0.0.0/0` through NAT gateway

Configuration:
```tf
existing_network = { id = 1234567 }
network_ipv4_cidr = "10.0.0.0/9"

# In all nodepools:
enable_public_ipv4 = false
enable_public_ipv6 = false

# For autoscaler:
autoscaler_enable_public_ipv4 = false
autoscaler_enable_public_ipv6 = false

# Optional private LB:
control_plane_load_balancer_enable_public_network = false
```
</details>

<details>
<summary><strong>Private-only cluster (NAT Router)</strong></summary>

Fully private setup with:
- **Egress:** Single NAT router IP
- **SSH:** Through bastion (NAT router)
- **Control plane:** Through LB or NAT router port forwarding
- **Ingress:** Through agents LB only

```tf
enable_control_plane_load_balancer = true

nat_router = {
  server_type = "cax21"
  location    = "nbg1"
}

# Optional: use the router's private IP for SSH bastion traffic when the
# operator already reaches the private network through Tailscale/WireGuard/etc.
# use_private_nat_router_bastion = true
```

> **August 11, 2025:** Hetzner removed legacy Router DHCP option. This module now automatically persists routes via the virtual gateway.
</details>

<details>
<summary><strong>External overlay access (Tailscale/ZeroTier/WARP)</strong></summary>

Use `node_transport_mode = "tailscale"` when Tailscale should be the official
Kubernetes node transport for a single-network or multinetwork cluster. This
external-overlay pattern is different: it is for operator access, custom
control-plane endpoints, or post-bootstrap Tailscale Kubernetes Operator
features that you manage outside kube-hetzner.

There is still no broad `enable_tailscale` switch. kube-hetzner manages only
the narrow node-transport contract above. It does not manage tailnet ACLs,
route approvals, Tailscale Services, workload ingress/egress policy, or the
Tailscale Kubernetes Operator lifecycle. Use your overlay setup in an outer
module or out-of-band bootstrap, then pass resulting endpoints back into
kube-hetzner.

The supported kube-hetzner primitives are:

- `preinstall_exec` / `postinstall_exec` for user-owned bootstrap hooks.
- `node_connection_overrides` for Terraform SSH/provisioners over Tailnet IPs.
- `control_plane_endpoint` for a stable external kube API endpoint.
- `use_private_nat_router_bastion` when a Tailscale/WireGuard/WARP path already reaches the private network.
- `firewall_ssh_source` / `firewall_kube_api_source` tightening after overlay access is proven.

```tf
# Bootstrap overlay client on each node (example commands only).
# Avoid long-lived auth keys here; command strings and cloud-init user-data can
# be visible in Terraform state/provider state or instance logs. Prefer an
# external bootstrap or short-lived, one-use preauth keys that are immediately
# rotated/revoked.
preinstall_exec = [
  "curl -fsSL https://tailscale.com/install.sh | sh",
  # "tailscale up --auth-key=${var.tailscale_auth_key} --ssh --hostname=$(hostname)",
]

# After overlay IPs are known, route Terraform SSH through them
# Keys must match final node names (with cluster prefix if enabled)
node_connection_overrides = {
  "k3s-control-plane" = "100.64.0.10"
  "k3s-agent-0"       = "100.64.0.11"
}

# Optional: use an external control-plane endpoint exposed through overlay
control_plane_endpoint = "https://cp.tailnet.example:6443"
```

Typical workflow:
1. Apply once to bootstrap nodes and install/join overlay agents.
2. Resolve overlay addresses and set `node_connection_overrides`.
3. Apply again and optionally tighten `firewall_ssh_source` / `firewall_kube_api_source`.
4. After Kubernetes is healthy, deploy the Tailscale Kubernetes Operator with
   Helm, ArgoCD, or `user_kustomizations` if you want Tailscale Services,
   workload ingress/egress, subnet routers, or kube API proxying.

For cluster node transport, prefer
[`examples/tailscale-node-transport/README.md`](examples/tailscale-node-transport/README.md).
For user-owned operator access, see
[`examples/external-overlay-tailscale/README.md`](examples/external-overlay-tailscale/README.md).
</details>

<details>
<summary><strong>Fix SELinux issues with udica</strong></summary>

Create targeted SELinux profiles instead of weakening cluster-wide security:

> **Troubleshooting note:** When using large attached volumes (for example large Longhorn disks), first boot can hit cloud-init/systemd timeouts while SELinux relabeling completes. If you hit this repeatedly, a practical workaround is to disable SELinux only on the affected nodepool(s) instead of disabling it cluster-wide.

```sh
# Find container
crictl ps

# Generate inspection
crictl inspect <container-id> > container.json

# Create profile
udica -j container.json myapp --full-network-access

# Install module
semodule -i myapp.cil /usr/share/udica/templates/{base_container.cil,net_container.cil}
```

Apply to deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: my-container
          securityContext:
            seLinuxOptions:
              type: myapp.process
```

*Thanks @carolosf*
</details>

---

## 🔍 Debugging

### Quick Status Check

```sh
hcloud context create Kube-hetzner  # First time only
hcloud server list                   # Check nodes
hcloud network describe k3s          # Check network
hcloud loadbalancer describe k3s-traefik  # Check LB
```

### SSH Troubleshooting

```sh
ssh root@<control-plane-ip> -i /path/to/private_key -o StrictHostKeyChecking=no

# View k3s logs
journalctl -u k3s          # Control plane
journalctl -u k3s-agent    # Agent nodes

# Check config
cat /etc/rancher/k3s/config.yaml

# Check uptime
last reboot
uptime
```

---

## 💣 Takedown

```sh
terraform destroy -auto-approve
```

**If destroy hangs** (LB or autoscaled nodes), use the cleanup script:

```sh
tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/cleanup.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"
```

> ⚠️ This deletes everything including volumes. Dry-run option available.

---

## ⬆️ Upgrading the Module

Update `version` in your kube.tf and run `terraform apply`.

### Migrating from 1.x to 2.x

1. Run `createkh` to get new packer template
2. Update version to `>= 2.0`
3. Remove `extra_packages_to_install` and `opensuse_microos_mirror_link` (moved to packer)
4. Run `terraform init -upgrade && terraform apply`

---

## 🤝 Contributing

**Help wanted!** Consider asking Hetzner to add MicroOS as a default image (not just ISO) at [get.opensuse.org/microos](https://get.opensuse.org/microos). More requests = faster deployments for everyone!

### Development Workflow

1. Fork the project
2. Create your branch: `git checkout -b AmazingFeature`
3. Point your kube.tf `source` to local clone
4. Useful commands:
	   ```sh
	   ../kube-hetzner/scripts/cleanup.sh
	   for distro in k3s rke2; do packer build -var "selinux_package_to_install=${distro}" ../kube-hetzner/packer-template/hcloud-leapmicro-snapshots.pkr.hcl; done
	   # (legacy)
	   # packer build ../kube-hetzner/packer-template/hcloud-microos-snapshots.pkr.hcl
	   ```
5. Update `kube.tf.example` if needed
6. Commit: `git commit -m 'Add AmazingFeature'`
7. Push: `git push origin AmazingFeature`
8. Open PR targeting `staging` branch

### Agent Skills

This project includes [agent skills](https://agentskills.io) in `.claude/skills/` — reusable workflows for any AI coding agent (Claude Code, Cursor, Windsurf, Codex, etc.):

| Skill | Purpose |
|-------|---------|
| `/kh-assistant` | Interactive help for configuration and debugging |
| `/fix-issue <num>` | Guided workflow for fixing GitHub issues |
| `/review-pr <num>` | Security-focused PR review |
| `/test-changes` | Run terraform fmt, validate, plan |
| `/migrate-v2-to-v3 <terraform-root>` | Guided v2 to v3 migration and plan review |

**PRs to improve these skills are welcome!** See `.claude/skills/` for the skill definitions.

---

## 💖 Support This Project

<div align="center">

If Kube-Hetzner saves you time and money, please consider supporting its development:

<a href="https://github.com/sponsors/mysticaltech">
<img src="https://img.shields.io/badge/Sponsor_on_GitHub-❤️-EA4AAA?style=for-the-badge&logo=github-sponsors" alt="Sponsor on GitHub">
</a>

<br><br>

Your sponsorship directly funds:

🐛 **Bug fixes** and issue response<br>
🚀 **New features** and improvements<br>
📚 **Documentation** maintenance<br>
🔒 **Security updates** and best practices

**Every contribution matters.** Thank you for keeping this project alive! 🙏

</div>

---

## 🙏 Acknowledgements

- **[k-andy](https://github.com/StarpTech/k-andy)** — The starting point for this project
- **[Best-README-Template](https://github.com/othneildrew/Best-README-Template)** — README inspiration
- **[Hetzner Cloud](https://www.hetzner.com)** — Outstanding infrastructure and Terraform provider
- **[HashiCorp](https://www.hashicorp.com)** — The amazing Terraform framework
- **[Rancher](https://www.rancher.com)** — k3s, the heart of this project
- **[openSUSE](https://www.opensuse.org)** — Leap Micro & MicroOS, next-level container OS

<div align="center">
<a href="https://www.hetzner.com"><img src="https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/raw/master/.images/hetzner-logo.svg" alt="Hetzner — Server · Cloud · Hosting" height="80"></a>
<br><br>
</div>

Thanks to **[Hetzner](https://www.hetzner.com)** for supporting this project with cloud credits.

---

<div align="center">

**[⬆ Back to Top](#kube-hetzner)**

Made with ❤️ by the Kube-Hetzner community

</div>
