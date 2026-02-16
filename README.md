<div align="center">

<!-- HERO SECTION -->
<img src="https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/raw/master/.images/kube-hetzner-logo.png" alt="Kube-Hetzner Logo" width="140" height="140">

# Kube-Hetzner

### Production-Ready Kubernetes on Hetzner Cloud

**HA by default • Auto-upgrading • Cost-optimized**

A highly optimized, easy-to-use, auto-upgradable Kubernetes cluster powered by k3s on MicroOS<br>deployed for peanuts on [Hetzner Cloud](https://hetzner.com)

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.10-844FBA?style=flat-square&logo=terraform)](https://terraform.io)&nbsp;&nbsp;
[![OpenTofu](https://img.shields.io/badge/OpenTofu-Compatible-FFDA18?style=flat-square&logo=opentofu)](https://opentofu.org)&nbsp;&nbsp;
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
- **[openSUSE MicroOS](https://en.opensuse.org/Portal:MicroOS)** — Immutable container OS with automatic updates
- **[k3s](https://k3s.io/)** — Certified, lightweight Kubernetes distribution

<div align="center">
<img src="https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/raw/master/.images/kubectl-pod-all-17022022.png" alt="Kube-Hetzner Screenshot" width="700">
</div>

### Why MicroOS over Ubuntu?

| Feature | Benefit |
|---------|---------|
| **Immutable filesystem** | Most of the OS is read-only—hardened by design |
| **Auto-ban abusive IPs** | SSH brute-force protection out of the box |
| **Rolling release** | Piggybacks on openSUSE Tumbleweed—always current |
| **BTRFS snapshots** | Automatic rollback if updates break something |
| **[Kured](https://github.com/kubereboot/kured) support** | Safe, HA-aware node reboots |

### Why k3s?

| Feature | Benefit |
|---------|---------|
| **Certified Kubernetes** | Automatically synced with upstream k8s |
| **Single binary** | Deploy with one command |
| **Batteries included** | Built-in [helm-controller](https://github.com/k3s-io/helm-controller) |
| **Easy upgrades** | Via [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller) |

---

## ✨ Features

<table>
<tr>
<td width="50%" valign="top">

### 🚀 Core Platform
- [x] **Maintenance-free** — Auto-upgrades MicroOS & k3s with rollback
- [x] **Multi-architecture** — Mix x86 and ARM (CAX) for cost savings
- [x] **Private networking** — Secure, low-latency node communication
- [x] **SELinux hardened** — Pre-configured security policies

### 🌐 Networking & CNI
- [x] **CNI flexibility** — Flannel, Calico, or Cilium
- [x] **Cilium XDP** — Hardware-level load balancing
- [x] **Wireguard encryption** — Optional encrypted overlay
- [x] **Dual-stack** — Full IPv4 & IPv6 support
- [x] **Custom subnets** — Define CIDR blocks per nodepool

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
- [x] **Single-node mode** — Perfect for development

### 💾 Storage
- [x] **Hetzner CSI** — Native block storage with encryption
- [x] **Longhorn** — Distributed storage with replication
- [x] **Custom mount paths** — Configurable storage locations

### 🔒 Security & Operations
- [x] **Audit logging** — Configurable retention policies
- [x] **Firewall rules** — Granular SSH/API access control
- [x] **NAT router** — Fully private clusters
- [x] **190+ variables** — Fine-tune everything
- [x] **Kustomization** — Extend with custom manifests

</td>
</tr>
</table>

---

## 🏁 Getting Started

### Prerequisites

<table>
<tr>
<th>Platform</th>
<th>Installation Command</th>
</tr>
<tr>
<td><strong>Homebrew</strong> (macOS/Linux)</td>
<td><code>brew install hashicorp/tap/terraform hashicorp/tap/packer kubectl hcloud</code></td>
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

> **Required tools:** [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) or [tofu](https://opentofu.org/docs/intro/install/), [packer](https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli#installing-packer) (initial setup only), [kubectl](https://kubernetes.io/docs/tasks/tools/), [hcloud](https://github.com/hetznercloud/cli)

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
<td><strong>Run the setup script</strong> — creates your project folder and MicroOS snapshot:</td>
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
curl -sL https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/packer-template/hcloud-microos-snapshots.pkr.hcl -o hcloud-microos-snapshots.pkr.hcl
export HCLOUD_TOKEN="your_hcloud_token"
packer init hcloud-microos-snapshots.pkr.hcl
packer build hcloud-microos-snapshots.pkr.hcl
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
terraform apply -auto-approve
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

Restrict SSH access by configuring `firewall_ssh_source` in your kube.tf. See [SSH docs](docs/ssh.md#firewall-ssh-source-and-changing-ips) for dynamic IP handling.

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
| Full kube-proxy replacement | `disable_kube_proxy = true` |
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

### OS Upgrades (MicroOS)

Handled by [Kured](https://github.com/kubereboot/kured)—safe, HA-aware reboots. Configure timeframes via [Kured options](https://kured.dev/docs/configuration/).

### K3s Upgrades

Managed by [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller). Customize the [upgrade plan template](templates/plans.yaml.tpl).

### Disable Automatic Upgrades

```tf
# Disable OS upgrades (required for <3 control planes)
automatically_upgrade_os = false

# Disable k3s upgrades
automatically_upgrade_k3s = false
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

Configure via helm values variables:
- `cilium_values`
- `traefik_values`
- `nginx_values`
- `longhorn_values`
- `rancher_values`

See `kube.tf.example` for examples.

---

## 🖥️ Dedicated Servers

Integrate Hetzner Robot servers via [the dedicated server guide](docs/add-robot-server.md).

---

## ➕ Adding Extras

Use [Kustomize](https://kustomize.io) for additional deployments:

1. Create `extra-manifests/kustomization.yaml.tpl`
2. Supports Terraform templating via `extra_kustomize_parameters`
3. Applied after cluster setup with `kubectl apply -k`

Change folder name with `extra_kustomize_folder`. See [example](examples/kustomization_user_deploy).

---

## 📚 Examples

<details>
<summary><strong>Custom post-install actions (ArgoCD, etc.)</strong></summary>

For CRD-dependent applications:

```tf
extra_kustomize_deployment_commands = <<-EOT
  kubectl -n argocd wait --for condition=established --timeout=120s crd/appprojects.argoproj.io
  kubectl -n argocd wait --for condition=established --timeout=120s crd/applications.argoproj.io
  kubectl apply -f /var/user_kustomize/argocd-projects.yaml
  kubectl apply -f /var/user_kustomize/argocd-application-argocd.yaml
EOT
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
```

Example policy:
```yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: egress-sample
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

> **Ingress-Nginx with HTTP challenge:** Add `lb_hostname = "cluster.example.org"` to work around [this known issue](https://github.com/cert-manager/cert-manager/issues/466).
</details>

<details>
<summary><strong>Managing snapshots</strong></summary>

**Create:**
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
<summary><strong>Single-node development cluster</strong></summary>

Set `automatically_upgrade_os = false` (attached volumes don't handle auto-reboots well).

Uses k3s [service load balancer](https://rancher.com/docs/k3s/latest/en/networking/#service-load-balancer) instead of external LB. Ports 80 & 443 open automatically.
</details>

<details>
<summary><strong>Terraform Cloud deployment</strong></summary>

1. Create MicroOS snapshot in your project first
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
k3s_exec_server_args = "--kube-apiserver-arg enable-admission-plugins=PodTolerationRestriction,PodNodeSelector"
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
2. Add k3s_token output:

```tf
output "k3s_token" {
  value     = module.kube-hetzner.k3s_token
  sensitive = true
}
```

**Restore:**

1. Add restoration config to kube.tf:

```tf
locals {
  k3s_token = var.k3s_token
  etcd_version = "v3.5.9"
  etcd_snapshot_name = "name-of-the-snapshot"
  etcd_s3_endpoint = "your-s3-endpoint"
  etcd_s3_bucket = "your-s3-bucket"
  etcd_s3_access_key = "your-s3-access-key"
  etcd_s3_secret_key = var.etcd_s3_secret_key
}

variable "k3s_token" {
  sensitive = true
  type      = string
}

variable "etcd_s3_secret_key" {
  sensitive = true
  type      = string
}

module "kube-hetzner" {
  k3s_token = local.k3s_token

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
export TF_VAR_k3s_token="..."
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
  existing_network_id = [hcloud_network.k3s_proxied.id]  # Note: brackets required!
  network_ipv4_cidr = "10.0.0.0/9"
  additional_k3s_environment = {
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
placement_group_compat_idx = 1
```

For >10 nodes, use map-based definition:
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

Disable globally: `placement_group_disable = true`
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
<summary><strong>Private-only cluster (Wireguard)</strong></summary>

Requirements:
1. Pre-configured network
2. NAT gateway with public IP ([Hetzner guide](https://community.hetzner.com/tutorials/how-to-set-up-nat-for-cloud-networks))
3. Wireguard VPN access ([Hetzner guide](https://docs.hetzner.com/cloud/apps/list/wireguard/))
4. Route `0.0.0.0/0` through NAT gateway

Configuration:
```tf
existing_network_id = [YOURID]
network_ipv4_cidr = "10.0.0.0/9"

# In all nodepools:
disable_ipv4 = true
disable_ipv6 = true

# For autoscaler:
autoscaler_disable_ipv4 = true
autoscaler_disable_ipv6 = true

# Optional private LB:
control_plane_lb_enable_public_interface = false
```
</details>

<details>
<summary><strong>Private-only cluster (NAT Router)</strong></summary>

Fully private setup with:
- **Egress:** Single NAT router IP
- **SSH:** Through bastion (NAT router)
- **Control plane:** Through LB or NAT router port forwarding
- **Ingress:** Through agents LB only

> **August 11, 2025:** Hetzner removed legacy Router DHCP option. This module now automatically persists routes via the virtual gateway.
</details>

<details>
<summary><strong>Fix SELinux issues with udica</strong></summary>

Create targeted SELinux profiles instead of weakening cluster-wide security:

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
   packer build ../kube-hetzner/packer-template/hcloud-microos-snapshots.pkr.hcl
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
