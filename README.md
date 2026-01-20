<!-- PROJECT LOGO -->
<br />
<p align="center">
  <a href="https://github.com/mysticaltech/kube-hetzner">
    <img src="https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/raw/master/.images/kube-hetzner-logo.png" alt="Logo" width="112" height="112">
  </a>

  <h2 align="center">Kube-Hetzner</h2>

  <p align="center">
    A highly optimized, easy-to-use, auto-upgradable, HA-default & Load-Balanced, Kubernetes cluster powered by k3s-on-MicroOS and deployed for peanuts on <a href="https://hetzner.com" target="_blank">Hetzner Cloud</a> 🤑
  </p>
  <hr />
    <p align="center">
    🔥 Introducing <a href="https://chatgpt.com/g/g-67df95cd1e0c8191baedfa3179061581-kh-assistant" target="_blank">KH Assistant</a>, our Custom-GPT kube.tf generator to get you going fast, just tell it what you need! 🚀 (Updated: 28th July 2025)
  </p>
  <hr />
</p>

- [About The Project](#about-the-project)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [CNI](#cni)
- [Scaling Nodes](#scaling-nodes)
- [Autoscaling Node Pools](#autoscaling-node-pools)
- [High Availability](#high-availability)
- [Automatic Upgrade](#automatic-upgrade)
- [Customizing the Cluster Components](#customizing-the-cluster-components)
- [Adding Hetzner Robot / Dedicated Servers](#adding-hetzner-robot--dedicated-servers)
- [Adding Extras](#adding-extras)
- [Examples](#examples)
- [Debugging](#debugging)
- [Takedown](#takedown)
- [Upgrading the Module](#upgrading-the-module)
- [Contributing](#contributing)
- [Acknowledgements](#acknowledgements)

---

## About The Project

[Hetzner Cloud](https://hetzner.com) is a good cloud provider that offers very affordable prices for cloud instances, with data center locations in both Europe and the US.

This project aims to create a highly optimized Kubernetes installation that is easy to maintain, secure, and automatically upgrades both the nodes and Kubernetes. We aimed for functionality as close as possible to GKE's Auto-Pilot. _Please note that we are not affiliates of Hetzner, but we do strive to be an optimal solution for deploying and maintaining Kubernetes clusters on Hetzner Cloud._

To achieve this, we built up on the shoulders of giants by choosing [openSUSE MicroOS](https://en.opensuse.org/Portal:MicroOS) as the base operating system and [k3s](https://k3s.io/) as the k8s engine.

![Product Name Screen Shot][product-screenshot]

**Why OpenSUSE MicroOS (and not Ubuntu)?**

- Optimized container OS that is fully locked down, most of the filesystem is read-only!
- Hardened by default with an automatic ban for abusive IPs on SSH for instance.
- Evergreen release, your node will stay valid forever, as it piggybacks into OpenSUSE Tumbleweed's rolling release!
- Automatic updates by default and automatic rollbacks if something breaks, thanks to its use of BTRFS snapshots.
- Supports [Kured](https://github.com/kubereboot/kured) to properly drain and reboot nodes in an HA fashion.

**Why k3s?**

- Certified Kubernetes Distribution, it is automatically synced to k8s source.
- Fast deployment, as it is a single binary and can be deployed with a single command.
- Comes with batteries included, with its in-cluster [helm-controller](https://github.com/k3s-io/helm-controller).
- Easy automatic updates, via the [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller).

### Features

- [x] **Maintenance-free** with auto-upgrades to the latest version of MicroOS and k3s.
- [x] **Multi-architecture support**, choose any Hetzner cloud instances, including the cheaper CAX ARM instances.
- [x] Proper use of the **Hetzner private network** to minimize latency.
- [x] Choose between **Flannel, Calico, or Cilium** as CNI.
- [x] Optional **Wireguard** encryption of the Kube network for added security.
- [x] **Traefik**, **Nginx** or **HAProxy** as ingress controller attached to a Hetzner load balancer with Proxy Protocol turned on.
- [x] **Automatic HA** with the default setting of three control-plane nodes and two agent nodes.
- [x] **Autoscaling** nodes via the [kubernetes autoscaler](https://github.com/kubernetes/autoscaler).
- [x] **Super-HA** with Nodepools for both control-plane and agent nodes that can be in different locations.
- [x] Possibility to have a **single node cluster** with a proper ingress controller.
- [x] Can use Klipper as an **on-metal LB** or the **Hetzner LB**.
- [x] Ability to **add nodes and nodepools** when the cluster is running.
- [x] Possibility to toggle **Longhorn** and **Hetzner CSI**.
- [x] Encryption at rest fully functional in both **Longhorn** and **Hetzner CSI**.
- [x] Optional use of **Floating IPs** for use via Cilium's Egress Gateway.
- [x] Proper IPv6 support for inbound/outbound traffic.
- [x] **Flexible configuration options** via variables and an extra Kustomization option.
- [x] Ability to add Hetzner "Robot" / Dedicated servers as nodes

_It uses Terraform to deploy as it's easy to use, and Hetzner has a great [Hetzner Terraform Provider](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs)._

<!-- GETTING STARTED -->

## Getting Started

Follow those simple steps, and your world's cheapest Kubernetes cluster will be up and running.

### ✔️ Prerequisites

First and foremost, you need to have a Hetzner Cloud account. You can sign up for free [here](https://hetzner.com/cloud/).

Then you'll need to have [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) or [tofu](https://opentofu.org/docs/intro/install/), [packer](https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli#installing-packer) (for the initial snapshot creation only, no longer needed once that's done), [kubectl](https://kubernetes.io/docs/tasks/tools/) cli and [hcloud](https://github.com/hetznercloud/cli) the Hetzner cli for convenience.  
The easiest way is to use the [homebrew](https://brew.sh/) package manager to install them (available on MacOS, Linux and Windows Linux Subsystem). The timeout command is also used, which is part of coreutils on MacOS.

|        **Tool**        |                              **Installation Command**                              |
|:----------------------:|:----------------------------------------------------------------------------------:|
| Homebrew (macOS/Linux) | brew install hashicorp/tap/terraform hashicorp/tap/packer kubectl hcloud           |
| Yay/Paru (Arch-based)  | yay -S terraform packer kubectl hcloud<br> paru -S terraform packer kubectl hcloud |
| APT (Debian-based)     | sudo apt install terraform packer kubectl                                          |
| DNF (Red Hat-based)    | sudo dnf install terraform packer kubectl                                          |
| Snap                   | sudo snap install terraform kubectl --classic && snap install packer               |
| Chocolatey (Windows)   | choco install terraform packer kubernetes-cli hcloud                               |

### 💡 [Do not skip] Creating your kube.tf file and the OpenSUSE MicroOS snapshot

1. Create a project in your [Hetzner Cloud Console](https://console.hetzner.cloud/), and go to **Security > API Tokens** of that project to grab the API key, it needs to be Read & Write. Take note of the key! ✅
2. Generate a passphrase-less ed25519 SSH key pair for your cluster; take note of the respective paths of your private and public keys. Or, see our detailed [SSH options](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/blob/master/docs/ssh.md). ✅
3. Now navigate to where you want to have your project live and execute the following command, which will help you get started with a **new folder** along with the required files, and will propose you to create a needed MicroOS snapshot. ✅

   ```sh
   tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"
   ```

   Or for fish shell:

   ```fish
   set tmp_script (mktemp); curl -sSL -o "{tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh; chmod +x "{tmp_script}"; bash "{tmp_script}"; rm "{tmp_script}"
   ```

   _Optionally, for future usage, save that command as an alias in your shell preferences, like so:_

   ```sh
   alias createkh='tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"'
   ```

   Or for fish shell:

   ```fish
   alias createkh='set tmp_script (mktemp); curl -sSL -o "{tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/create.sh; chmod +x "{tmp_script}"; bash "{tmp_script}"; rm "{tmp_script}"'
   ```

   _For the curious, here is what the script does:_

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

4. In that new project folder that gets created, you will find your `kube.tf` and it must be customized to suit your needs. ✅

   _A complete reference of all inputs, outputs, modules etc. can be found in the [terraform.md](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/blob/master/docs/terraform.md) file._

### 🎯 Installation

Now that you have your `kube.tf` file, along with the OS snapshot in Hetzner project, you can start the installation process:

```sh
cd <your-project-folder>
terraform init --upgrade
terraform validate
terraform apply -auto-approve
```

It will take around 5 minutes to complete, and then you should see a green output confirming a successful deployment.

_Once you start with Terraform, it's best not to change the state of the project manually via the Hetzner UI; otherwise, you may get an error when you try to run terraform again for that cluster (when trying to change the number of nodes for instance). If you want to inspect your Hetzner project, learn to use the hcloud cli._

## Usage

When your brand-new cluster is up and running, the sky is your limit! 🎉

You can view all kinds of details about the cluster by running `terraform output kubeconfig` or `terraform output -json kubeconfig | jq`.

To manage your cluster with `kubectl`, you can either use SSH to connect to a control plane node or connect to the Kube API directly.

### Connect via SSH

You can connect to one of the control plane nodes via SSH with `ssh root@<control-plane-ip> -i /path/to/private_key -o StrictHostKeyChecking=no`. Now you are able to use `kubectl` to manage your workloads right away. By default, the firewall allows SSH connections from everywhere. Best to change that to your own IP by configuring the `firewall_ssh_source` in your kube.tf file. If your IP changes, you can update it and re-apply without needing SSH access; see the details in the [SSH docs](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/blob/master/docs/ssh.md#firewall-ssh-source-and-changing-ips).

### Connect via Kube API

If you have access to the Kube API (depending on the value of your `firewall_kube_api_source` variable, best to have the value of your own IP and not open to the world), you can immediately kubectl into it (using the `clustername_kubeconfig.yaml` saved to the project's directory after the installation). By doing `kubectl --kubeconfig clustername_kubeconfig.yaml`, but for more convenience, either create a symlink from `~/.kube/config` to `clustername_kubeconfig.yaml` or add an export statement to your `~/.bashrc` or `~/.zshrc` file, as follows (you can get the path of `clustername_kubeconfig.yaml` by running `pwd`):

```sh
export KUBECONFIG=/<path-to>/clustername_kubeconfig.yaml
```

If chose to turn `create_kubeconfig` to false in your kube.tf (good practice), you can still create this file by running `terraform output --raw kubeconfig > clustername_kubeconfig.yaml` and then use it as described above.

_You can also use it in an automated flow, in which case `create_kubeconfig` should be set to false, and you can use the `kubeconfig` output variable to get the kubeconfig file in a structured data format._

## CNI

The default is Flannel, but you can also choose Calico or Cilium, by setting the `cni_plugin` variable in `kube.tf` to "calico" or "cilium".

### Cilium

As Cilium has a lot of interesting and powerful config possibilities, we give you the ability to configure Cilium with the helm `cilium_values` variable (see the cilium specific [helm values](https://github.com/cilium/cilium/blob/master/install/kubernetes/cilium/values.yaml)) before you deploy your cluster.

Cilium supports full kube-proxy replacement. Cilium runs by default in hybrid kube-proxy replacement mode. To achieve a completely kube-proxy-free cluster, set `disable_kube_proxy = true`.

It is also possible to enable Hubble using `cilium_hubble_enabled = true`. In order to access the Hubble UI, you need to port-forward the Hubble UI service to your local machine. By default, you can do this by running `kubectl port-forward -n kube-system service/hubble-ui 12000:80` and then opening `http://localhost:12000` in your browser.
However, it is recommended to use the [Cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli) and [Hubble Client](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli) and running the `cilium hubble ui` command.

## Scaling Nodes

Two things can be scaled: the number of nodepools or the number of nodes in these nodepools.

There are some limitations (to scaling down mainly) that you need to be aware of:

_Once the cluster is up; you can change any nodepool count and even set it to 0 (in the case of the first control-plane nodepool, the minimum is 1); you can also rename a nodepool (if the count is to 0), but should not remove a nodepool from the list after once the cluster is up. That is due to how subnets and IPs get allocated. The only nodepools you can remove are those at the end of each list of nodepools._

_However, you can freely add other nodepools at the end of each list. And for each nodepools, you can freely increase or decrease the node count (if you want to decrease a nodepool node count make sure you drain the nodes in question before, you can use `terraform show` to identify the node names at the end of the nodepool list, otherwise, if you do not drain the nodes before removing them, it could leave your cluster in a bad state). The only nodepool that needs to have always at least a count of 1 is the first control-plane nodepool._

_An advanced usecase is to replace the count of a nodepool by a map with each key representing a single node. In this case, you can add and remove individual nodes from a pool by adding and removing their entries in this map, and it allows you to set individual labels and other parameters on each node in the pool. See kube.tf.example for an example._

## Autoscaling Node Pools

We support autoscaling node pools powered by the Kubernetes [Cluster Autoscaler](https://github.com/kubernetes/autoscaler).

By adding at least one map to the array of `autoscaler_nodepools` the feature will be enabled. More on this in the corresponding section of kube.tf.example.

_Important to know, the nodes are booted based on a snapshot that is created from the initial control_plane. So please ensure that the disk of your chosen server type is at least the same size (or bigger) as the one of the first control_plane._

## High Availability

By default, we have three control planes and three agents configured, with automatic upgrades and reboots of the nodes.

If you want to remain HA (no downtime), it's essential to **keep a count of control planes nodes of at least three** (two minimum to maintain quorum when one goes down for automated upgrades and reboot), see [Rancher's doc on HA](https://rancher.com/docs/k3s/latest/en/installation/ha-embedded/).

Otherwise, it is essential to turn off automatic OS upgrades (k3s can continue to update without issue) for the control-plane nodes (when two or fewer control-plane nodes) and do the maintenance yourself.

## Automatic Upgrade

### The Default Setting

By default, MicroOS gets upgraded automatically on each node and reboot safely via [Kured](https://github.com/kubereboot/kured) installed in the cluster.

As for k3s, it also automatically upgrades thanks to Rancher's [system upgrade controller](https://github.com/rancher/system-upgrade-controller). By default, it will be set to the `initial_k3s_channel`, but you can also set it to `stable`, `latest`, or one more specific like `v1.23` if needed or specify a target version to upgrade to via the upgrade plan (this also allows for downgrades).

You can copy and modify the [one in the templates](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/blob/master/templates/plans.yaml.tpl) for that! More on the subject in [k3s upgrades](https://rancher.com/docs/k3s/latest/en/upgrades/basic/).

### Configuring update timeframes

Per default, a node that installed updates will reboot within the next few minutes and updates are installed roughly every 24 hours.
Kured can be instructed with specific timeframes for rebooting, to prevent too frequent drains and reboots.
All options from the [docs](https://kured.dev/docs/configuration/) are available for modification.

⚠️ Kured is also used to reboot nodes after configuration updates (`registries.yaml`, ...), so keep in mind that configuration changes can take some time to propagate!

### Turning Off Automatic Upgrades

_If you wish to turn off automatic MicroOS upgrades (Important if you are not launching an HA setup that requires at least 3 control-plane nodes), you need to set:_

```tf
automatically_upgrade_os = false
```

Alternatively ssh into each node and issue the following command:

```sh
systemctl --now disable transactional-update.timer
```

If you wish to turn off automatic k3s upgrades, you need to set:

```tf
automatically_upgrade_k3s = false
```

_Once disabled this way you selectively can enable the upgrade by setting the node label `k3s_update=true` and later disable it by removing the label or set it to `false` again._

```sh
# Enable upgrade for a node (use --all for all nodes)
kubectl label --overwrite node <node-name> k3s_upgrade=true

# Later disable upgrade by removing the label (use --all for all nodes)
kubectl label node <node-name> k3s_upgrade-
```

Alternatively, you can disable the k3s automatic upgrade without individually editing the labels on the nodes. Instead, you can just delete the two system controller upgrade plans with:

```sh
kubectl delete plan k3s-agent -n system-upgrade
kubectl delete plan k3s-server -n system-upgrade
```

Also, note that after turning off node upgrades, you will need to manually upgrade the nodes when needed. You can do so by SSH'ing into each node and running the following commands (and don't forget to drain the node before with `kubectl drain <node-name>`):

```sh
systemctl start transactional-update.service
reboot
```

### Individual Components Upgrade

Rarely needed, but can be handy in the long run. During the installation, we automatically download a backup of the kustomization to a `kustomization_backup.yaml` file. You will find it next to your `clustername_kubeconfig.yaml` at the root of your project.

1. First create a duplicate of that file and name it `kustomization.yaml`, keeping the original file intact, in case you need to restore the old config.
2. Edit the `kustomization.yaml` file; you want to go to the very bottom where you have the links to the different source files; grab the latest versions for each on GitHub, and replace. If present, remove any local reference to traefik_config.yaml, as Traefik is updated automatically by the system upgrade controller.
3. Apply the updated `kustomization.yaml` with `kubectl apply -k ./`.

## Customizing the Cluster Components

Most cluster components of Kube-Hetzner are deployed with the Rancher [Helm Chart](https://rancher.com/docs/k3s/latest/en/helm/) yaml definition and managed by the Helm Controller inside k3s.

By default, we strive to give you optimal defaults, but if you wish, you can customize them.

For Traefik, Nginx, HAProxy, Rancher, Cilium, Traefik, and Longhorn, for maximum flexibility, we give you the ability to configure them even better via helm values variables (e.g. `cilium_values`, see the advanced section in the kube.tf.example for more).

## Adding Hetzner Robot / Dedicated Servers

See the [guide on adding robot servers](docs/add-robot-server.md)

## Adding Extras

If you need to install additional Helm charts or Kubernetes manifests that are not provided by default, you can easily do so by using [Kustomize](https://kustomize.io). This is done by creating one or more `extra-manifests/kustomization.yaml.tpl` files beside your `kube.tf`.

If you'd like to use a different folder name, you can configure it using the `extra_kustomize_folder` variable. By default, it is set to `extra-manifests`. This can be useful when working with multiple environments, allowing you to deploy different manifests for each one.

These files need to be valid `Kustomization` manifests, additionally supporting terraform templating! (The templating parameters can be passed via the `extra_kustomize_parameters` variable (via a map) to the module).

All files in the `extra-manifests` directory and its subdirectories including the rendered versions of the `*.yaml.tpl` will be applied to k3s with `kubectl apply -k` (which will be executed after and independently of the basic cluster configuration).

See a working example in [examples/kustomization_user_deploy](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/tree/master/examples/kustomization_user_deploy).

_You can use the above to pass all kinds of Kubernetes YAML configs, including HelmChart and/or HelmChartConfig definitions (see the previous section if you do not know what those are in the context of k3s)._

_That said, you can also use pure Terraform and import the kube-hetzner module as part of a larger project, and then use things like the Terraform helm provider to add additional stuff, all up to you!_

## Examples

<details>

<summary>Custom post-install actions</summary>

After the initial bootstrapping of your Kubernetes cluster, you might want to deploy applications using the same terraform mechanism. For many scenarios it is sufficient to create a `kustomization.yaml.tpl` file (see [Adding Extras](#adding-extras)). All applied kustomizations will be applied at once by executing a single `kubectl apply -k` command.

However, some applications that e.g. provide custom CRDs (e.g. [ArgoCD](https://argoproj.github.io/cd/)) need a different deployment strategy: one has to deploy CRDs first, then wait for the deployment, before being able to install the actual application. In the ArgoCD case, not waiting for the CRD setup to finish will cause failures. Therefore, an additional mechanism is available to support these kind of deployments. Specify `extra_kustomize_deployment_commands` in your `kube.tf` file containing a series of commands to be executed, after the `Kustomization` step finished:

```tf
  extra_kustomize_deployment_commands = <<-EOT
    kubectl -n argocd wait --for condition=established --timeout=120s crd/appprojects.argoproj.io
    kubectl -n argocd wait --for condition=established --timeout=120s crd/applications.argoproj.io
    kubectl apply -f /var/user_kustomize/argocd-projects.yaml
    kubectl apply -f /var/user_kustomize/argocd-application-argocd.yaml
    ...
  EOT
```

</details>

<details>

<summary>Useful Cilium commands</summary>

With Kube-Hetzner, you have the possibility to use Cilium as a CNI. It's very powerful and has great observability features. Below you will find a few useful commands.

- Check the status of cilium with the following commands (get the cilium pod name first and replace it in the command):

```sh
kubectl -n kube-system exec --stdin --tty cilium-xxxx -- cilium status
kubectl -n kube-system exec --stdin --tty cilium-xxxx -- cilium status --verbose
```

- Monitor cluster traffic with:

```sh
kubectl -n kube-system exec --stdin --tty cilium-xxxx -- cilium monitor
```

- See the list of kube services with:

```sh
kubectl -n kube-system exec --stdin --tty cilium-xxxx -- cilium service list
```

_For more cilium commands, please refer to their corresponding [Documentation](https://docs.cilium.io/en/latest/cheatsheet)._

</details>

<details>
<summary>Cilium Egress Gateway (via Floating IPs)</summary>

[Cilium Egress Gateway](https://docs.cilium.io/en/stable/network/egress-gateway/) provides the ability to control outgoing traffic from POD.

Using Floating IPs makes it possible to get rid of the problem of changing the primary IPs when recreating a node in the cluster.

To implement the Cilium Egress Gateway feature, you need to define a separate nodepool with the setting `floating_ip = true` in the nodepool configuration parameter block.

Example nodepool configuration:

```tf
{
  name        = "egress",
  server_type = "cx23",
  location    = "nbg1",
  labels = [
    "node.kubernetes.io/role=egress"
  ],
  taints = [
    "node.kubernetes.io/role=egress:NoSchedule"
  ],
  floating_ip = true
  count = 1
},
```

Configure Cilium:

```tf
locals {
  cluster_ipv4_cidr = "10.42.0.0/16"
}

cluster_ipv4_cidr = local.cluster_ipv4_cidr

cilium_values = <<EOT
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

Deploy the K8S cluster infrastructure.

See the Cilium documentation for further steps (policy writing and testing): [Writing egress gateway policies](https://docs.cilium.io/en/stable/network/egress-gateway/)

There are 3 different ways to define egress policies related to the gateway node. You can specify the interface, the egress IP (Floating IP) or nothing, which pics the first IPv4 address of the the interface of the default route.

CiliumEgressGatewayPolicy example:

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

    # Specify the IP address used to SNAT traffic matched by the policy.
    # It must exist as an IP associated with a network interface on the instance.
    egressIP: { FLOATING_IP }
```

</details>

<details>

<summary>Ingress with TLS</summary>

_We advise you to use `Cert-Manager`, as it supports HA setups without requiring you to use the enterprise version of Traefik. The reason for that is that according to Traefik themselves, Traefik CE (community edition) is stateless, and it's not possible to run multiple instances of Traefik CE with LetsEncrypt enabled. Meaning, you cannot have your ingress be HA with Traefik if you use the community edition and have activated the LetsEncrypt resolver. You could however use Traefik EE (enterprise edition) to achieve that. Long story short, if you are going to use Traefik CE (like most of us), you should use Cert-Manager to generate the certificates. Source [here](https://doc.traefik.io/traefik/v2.0/providers/kubernetes-crd/)._

### Via Cert-Manager (recommended)

Create your issuers as described here <https://cert-manager.io/docs/configuration/acme/>.

Then in your Ingress definition, just mentioning the issuer as an annotation and giving a secret name will take care of instructing Cert-Manager to generate a certificate for it! You just have to configure your issuer(s) first with the method of your choice. Detailed instructions on how to configure `Cert-manager` with Traefik can be found at https://traefik.io/blog/secure-web-applications-with-traefik-proxy-cert-manager-and-lets-encrypt/.

Ingress example:

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

_⚠️ In case of using Ingress-Nginx as an ingress controller if you choose to use the HTTP challenge method you need to do an additional step of adding variable `lb_hostname = "cluster.example.org"` to your kube.tf. You must set it to an FQDN that points to your LB address._

_This is to circumvent this known issue [cert-manager/cert-manager/issues/466](https://github.com/cert-manager/cert-manager/issues/466). Otherwise, you can just use the DNS challenge, which does not require any additional tweaks to work._

</details>

<details>

<summary>Create or delete a snapshot</summary>

Apart from the installation script, you can always create or delete the OS snapshot manually.

To create a snapshot, run the following command:

```bash
export HCLOUD_TOKEN=<your-token>
packer build ./packer-template/hcloud-microos-snapshots.pkr.hcl
```

To delete a snapshot, first find it with:

```bash
hcloud image list
```

Then delete it with:

```bash
hcloud image delete <image-id>
```

</details>

<details>

<summary>Single-node cluster</summary>

Running a development cluster on a single node without any high availability is also possible.

When doing so, `automatically_upgrade_os` should be set to `false`, especially with attached volumes the automatic reboots won't work properly. In this case, we don't deploy an external load-balancer but use the default [k3s service load balancer](https://rancher.com/docs/k3s/latest/en/networking/#service-load-balancer) on the host itself and open up port 80 & 443 in the firewall (done automatically).

</details>

<details>

<summary>Use in Terraform cloud</summary>

You can use Kube-Hetzner on Terraform cloud just as you would from a local deployment:

1. Make sure you have the OS snapshot already created in your project (follow the installation script to achieve this).
2. Use the content of your public and private key to configure `ssh_public_key` and `ssh_private_key`. Make sure the private key is _not_ password protected. Since your private key is sensitive, it is recommended to add them as variables (make sure to mark the private key as a sensitive variable in Terraform Cloud!) and assign it in your `kube.tf`:

   ```tf
   ssh_public_key = var.ssh_public_key
   ssh_private_key = var.ssh_private_key
   ```

   _Note_: If you want to use a password protected private key, you will have to point `ssh_private_key` to a file containing this key. You must host this file in an environment that you control and a `ssh-agent` to decipher it for you. Hence, on Terraform Cloud, change the `execution mode` to `local` and run your own Terraform agent in this environment.

</details>

<details>

<summary>Configure add-ons with HelmChartConfig</summary>

For instance, to customize the Rancher install, if you choose to enable it, you can create and apply the following `HelmChartConfig`:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rancher
  namespace: kube-system
spec:
  valuesContent: |-
    **values.yaml content you want to customize**
```

The helm options for Rancher can be seen here <https://github.com/rancher/rancher/blob/release/v2.6/chart/values.yaml>.

The same goes for all add-ons, like Longhorn, Cert-manager, and Traefik.

</details>

<details>

<summary>Encryption at rest with HCloud CSI</summary>

The easiest way to get encrypted volumes working is actually to use the new encryption functionality of hcloud csi itself, see [hetznercloud/csi-driver](https://github.com/hetznercloud/csi-driver).

For this, you just need to create a secret containing the encryption key:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: encryption-secret
  namespace: kube-system
stringData:
  encryption-passphrase: foobar
```

And to create a new storage class:

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

<summary>Encryption at rest with Longhorn</summary>
To get started, use a cluster-wide key for all volumes like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-crypto
  namespace: longhorn-system
stringData:
  CRYPTO_KEY_VALUE: "I have nothing to hide."
  CRYPTO_KEY_PROVIDER: "secret"
  CRYPTO_KEY_CIPHER: "aes-xts-plain64"
  CRYPTO_KEY_HASH: "sha256"
  CRYPTO_KEY_SIZE: "256"
  CRYPTO_PBKDF: "argon2i"
```

And create a new storage class:

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
  staleReplicaTimeout: "2880" # 48 hours in minutes
  fromBackup: ""
  fsType: ext4
  encrypted: "true"
  # global secret that contains the encryption key that will be used for all volumes
  csi.storage.k8s.io/provisioner-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/provisioner-secret-namespace: "longhorn-system"
  csi.storage.k8s.io/node-publish-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/node-publish-secret-namespace: "longhorn-system"
  csi.storage.k8s.io/node-stage-secret-name: "longhorn-crypto"
  csi.storage.k8s.io/node-stage-secret-namespace: "longhorn-system"
```

For more details, see [Longhorn's documentation](https://longhorn.io/docs/1.4.0/advanced-resources/security/volume-encryption/).

</details>

<details>
<summary>Assign all pods in a namespace to either arm64 or amd64 nodes with admission controllers</summary>

To enable the [PodNodeSelector and optionally the PodTolerationRestriction](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#podnodeselector) api modules, set the following value:

```tf
k3s_exec_server_args = "--kube-apiserver-arg enable-admission-plugins=PodTolerationRestriction,PodNodeSelector"
```

Next, you can set default nodeSelector values per namespace. This lets you assign namespaces to specific nodes. Note though, that this is the default as well as the whitelist, so if a pod sets its own nodeSelector value that must be a subset of the default. Otherwise, the pod will not be scheduled.

Then set the according annotations on your namespaces:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/node-selector: kubernetes.io/arch=amd64
  name: this-runs-on-amd64
```

or with taints and tolerations:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/node-selector: kubernetes.io/arch=arm64
    scheduler.alpha.kubernetes.io/defaultTolerations: '[{ "operator" : "Equal", "effect" : "NoSchedule", "key" : "workload-type", "value" : "machine-learning" }]'
  name: this-runs-on-arm64
```

This can be helpful when you set up a mixed-architecture cluster, and there are many other use cases.

</details>

<details>

<summary>Backup and restore a cluster</summary>

K3s allows for automated etcd backups to S3. Etcd is the default storage backend on kube-hetzner, even for a single control plane cluster, hence this should work for all cluster deployments.

**For backup do:**

1. Fill the kube.tf config `etcd_s3_backup`, it will trigger a regular automated backup to S3.
2. Add the k3s_token as an output to your kube.tf

```tf
output "k3s_token" {
  value     = module.kube-hetzner.k3s_token
  sensitive = true
}
```

3. Make sure you can access the k3s_token via `terraform output k3s_token`.

**For restoration do:**

1. Before cluster creation, add the following to your kube.tf. Replace the local variables to match your values.

```tf
locals {
  # ...

  k3s_token = var.k3s_token  # this is secret information, hence it is passed as an environment variable

  # to get the corresponding etcd_version for a k3s version you need to
  # - start k3s or have it running
  # - run `curl -L --cacert /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert /var/lib/rancher/k3s/server/tls/etcd/server-client.crt --key /var/lib/rancher/k3s/server/tls/etcd/server-client.key https://127.0.0.1:2379/version`
  # for details see https://gist.github.com/superseb/0c06164eef5a097c66e810fe91a9d408
  etcd_version = "v3.5.9"

  etcd_snapshot_name = "name-of-the-snapshot(no-path,just-the-name)"
  etcd_s3_endpoint = "your-s3-endpoint(without-https://)"
  etcd_s3_bucket = "your-s3-bucket"
  etcd_s3_access_key = "your-s3-access-key"
  etcd_s3_secret_key = var.etcd_s3_secret_key  # this is secret information, hence it is passed as an environment variable

  # ...
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
  # ...

  k3s_token = local.k3s_token

  # ...

  postinstall_exec = compact([
    (
      local.etcd_snapshot_name == "" ? "" :
      <<-EOF
      export CLUSTERINIT=$(cat /etc/rancher/k3s/config.yaml | grep -i '"cluster-init": true')
      if [ -n "$CLUSTERINIT" ]; then
        echo indeed this is the first control plane node > /tmp/restorenotes
        k3s server \
          --cluster-reset \
          --etcd-s3 \
          --cluster-reset-restore-path=${local.etcd_snapshot_name} \
          --etcd-s3-endpoint=${local.etcd_s3_endpoint} \
          --etcd-s3-bucket=${local.etcd_s3_bucket} \
          --etcd-s3-access-key=${local.etcd_s3_access_key} \
          --etcd-s3-secret-key=${local.etcd_s3_secret_key}
        # renaming the k3s.yaml because it is used as a trigger for further downstream
        # changes. Better to let `k3s server` create it as expected.
        mv /etc/rancher/k3s/k3s.yaml /etc/rancher/k3s/k3s.backup.yaml

        # download etcd/etcdctl for adapting the kubernetes config before starting k3s
        ETCD_VER=${local.etcd_version}
        case "$(uname -m)" in
            aarch64) ETCD_ARCH="arm64" ;;
            x86_64) ETCD_ARCH="amd64" ;;
        esac;
        DOWNLOAD_URL=https://github.com/etcd-io/etcd/releases/download
        rm -f /tmp/etcd-$ETCD_VER-linux-$ETCD_ARCH.tar.gz
        curl -L $DOWNLOAD_URL/$ETCD_VER/etcd-$ETCD_VER-linux-$ETCD_ARCH.tar.gz -o /tmp/etcd-$ETCD_VER-linux-$ETCD_ARCH.tar.gz
        tar xzvf /tmp/etcd-$ETCD_VER-linux-$ETCD_ARCH.tar.gz -C /usr/local/bin --strip-components=1
        rm -f /tmp/etcd-$ETCD_VER-linux-$ETCD_ARCH.tar.gz

        etcd --version
        etcdctl version

        # start etcd server in the background
        nohup etcd --data-dir /var/lib/rancher/k3s/server/db/etcd &
        echo $! > save_pid.txt

        # delete traefik service so that no load-balancer is accidently changed
        etcdctl del /registry/services/specs/traefik/traefik
        etcdctl del /registry/services/endpoints/traefik/traefik

        # delete old nodes (they interfere with load balancer)
        # minions is the old name for "nodes"
        OLD_NODES=$(etcdctl get "" --prefix --keys-only | grep /registry/minions/ | cut -c 19-)
        for NODE in $OLD_NODES; do
          for KEY in $(etcdctl get "" --prefix --keys-only | grep $NODE); do
            etcdctl del $KEY
          done
        done

        kill -9 `cat save_pid.txt`
        rm save_pid.txt
      else
        echo this is not the first control plane node > /tmp/restorenotes
      fi
      EOF
    )
  ])
  # ...
}
```

2. Set the following sensible environment variables

   - `export TF_VAR_k3s_token="..."` (Be careful, this token is like an admin password to the entire cluster. You need to use the same k3s_token which you saved when creating the backup.)
   - `export etcd_s3_secret_key="..."`

3. Create the cluster as usual. You can also change the cluster-name and deploy it next to the original backed up cluster.

Awesome! You restored a whole cluster from a backup.

</details>
<details>
<summary>Deploy in a pre-constructed private network (for proxies etc)</summary>
If you want to deploy other machines on the private network before deploying the k3s cluster,
you can. One use-case is if you want to setup a proxy or a NAT router on the private network,
which is needed by the k3s cluster already at the time of construction.

It is important to get all the address ranges right in this case, although the
number of changes needed is minimal. If your network is created with 10.0.0.0/8,
and you use subnet 10.128.0.0/9 for your non-k3s business, then adapting
`network_ipv4_cidr = "10.0.0.0/9"` should be all you need.

For example

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
resource "hcloud_server" "your_proxy_server" {
  ...
}
resource "hcloud_server_network" "your_proxy_server" {
  depends_on = [
    hcloud_server.your_proxy_server
  ]
  server_id  = hcloud_server.your_proxy_server.id
  network_id = hcloud_network.k3s_proxied.id
  ip         = "10.128.0.1"
}
module "kube-hetzner" {
  ...
  existing_network_id = [hcloud_network.k3s_proxied.id]
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

NOTE: square brackets in existing_network_id! This must be a list of length 1.

</details>
<details>
<summary>Placement groups</summary>
Up until release v2.11.8, there was an implementation error in the placement group logic.

If you have fewer than 10 agents and 10 control-plane nodes, you can continue using the code as is.

If you have a single pool with a count >= 10, you could only work with global setting in kube.tf:

```tf
placement_group_disable = true
```

Now you can assign each nodepool to its own placement group, preferrably using named groups:

```tf
  agent_nodepools = [
    {
      ...
      placement_group = "special"
    },
  ]
```

You can also continue using the previous code-base like this:

```tf
  agent_nodepools = [
    {
      ...
      placement_group_compat_idx = 1
    },
  ]
```

Finally, if you want to have a node-pool with more than 10 nodes, you have to use the map-based node definition and assign individual nodes to groups:

```tf
  agent_nodepools = [
    {
      ...
      nodes = {
        "0" : {
          placement_group = "pg-1",
        },
        ...
        "30" : {
          placement_group = "pg-2",
        },
      }
    },
  ]
```

</details>
<details>
<summary>Migratings from count-based nodepools to map-based</summary>

Migrating from `count` to map-based `nodes` is easy, but it is crucial
that you set append_index_to_node_name to false, otherwise the nodes get
replaced. The default for newly added nodes is true, so you can
easily map between your nodes and your kube.tf file.

```tf
  agent_nodepools = [
    {
      name        = "agent-large",
      server_type = "cx33",
      location    = "nbg1",
      labels      = [],
      taints      = [],
      # count       = 2
      nodes = {
        "0" : {
          append_index_to_node_name = false,
          labels = ["my.extra.label=special"],
          placement_group = "agent-large-pg-1",
        },
        "1" : {
          append_index_to_node_name = false,
          server_type = "cx43",
          labels = ["my.extra.label=slightlybiggernode"]
          placement_group = "agent-large-pg-2",
        },
      }
    },
  ]
```

</details>
<details>
<summary>Use of delete protection</summary>

Use of delete protection feature in Hetzner Cloud on resources can be used to protect resources from deletion by putting a "lock" on them.

Please note, that this does not protect deletion from Terraform itself, as the Provider will lift the lock in that case. The resources will only be protected from deletion via the Hetzner Cloud Console or API.

There are following resources that support delete protection, which is set to `false` by default:

- Floating IPs
- Load Balancers
- Volumes (used by Longhorn)

Example scenario where you want to ensure you keep a floating IP that is whitelisted in some firewall so you don't lose access to certain resources or have to wait for the new IP being whitelisted.
This is how you can enable delete protection for floating IPs with _terraform.tfvars_:

```tf
enable_delete_protection = {
  floating_ip = true
}
```

</details>
<details>

<summary>Use only private ips in your cluster (Wireguard)</summary>

To use only private ips on your cluster, you need in your project:
1. A network already configured.
2. A machine with a public IP, with nat configured (see [Hetzner guide](https://community.hetzner.com/tutorials/how-to-set-up-nat-for-cloud-networks)).
3. Access to your network (you can use wireguard, see [Hetzner guide](https://docs.hetzner.com/cloud/apps/list/wireguard/)).
4. A route in your network, destination: `0.0.0.0/0` through the private ip of your machine with NAT.
5. Make sure the connexion to your vpn is established before launching terraform.

Recommended values:
- Network range: `10.0.0.0/8`
- Subnet for your wireguard and NAT machine: `10.128.0.0/16`

If you follow this values, in your kube.tf, please set:
- `existing_network_id = [YOURID]` (with the brackets)
- `network_ipv4_cidr = "10.0.0.0/9"`
- Add `disable_ipv4 = true` and  `disable_ipv6 = true` in all machines in all nodepools (control planes + agents).
- Add `autoscaler_disable_ipv4 = true` and `autoscaler_disable_ipv6 = true` to disable public ips on autoscaled nodes.

This setup is compatible with a load balancer for your control planes. However, you should consider setting
`control_plane_lb_enable_public_interface = false` to keep the IP private. Note that if you use this setting,
you'll need a way to access the Kubernetes API (such as through a VPN, bastion, or NAT router with port forwarding).
</details>
<details>

<summary>Use only private ips in your cluster (NAT Router)</summary>

Setup a purely private cluster where public internet traffic is limited to the
following paths:
- egress: entirely through the NAT router, using a single IP for all egress traffic.
- ssh: entirely through the bastion host, at the moment the same as the NAT router.
- control-plane (kubectl): through the control plane load balancer if it has a public interface, or through the NAT router (with automatic port forwarding to the private control plane LB) when `control_plane_lb_enable_public_interface = false`.
- regular ingress: through the agents load balancer only.

By seperating various roles, this decreases the attack surfaces a bit.

If you need highly available egress (often this is not necessary), this setup is not for you. This setup does not have any impact on the availability of ingress.

> ℹ️ **August 11 2025 DHCP change**: Hetzner removed the legacy Router option on private networks on this date. Beginning with this module version, every node attached to the Hetzner private network automatically persists a `0.0.0.0/0` route via the virtual gateway on its private interface, so NAT/VPN egress survives DHCP renewals and reboots without manual `ip route add` fixes.

</details>


<details>

<summary>Fix SELinux issues with udica</summary>

Rather than weakening SELinux modules for all workloads on your cluster, it's better to create a profile and apply it to a specific workload. The `udica` tool (pre-installed on MicroOS nodes) helps produce SELinux modules for running containers.

Here's how to use it:

1. Find the container ID for your problematic workload:
```sh
crictl ps
```

2. Generate a container inspection file:
```sh
crictl inspect <container-id> > container.json
```

3. Use udica to create an SELinux profile (with appropriate network access):
```sh
udica -j container.json myapp --full-network-access
```

4. Review the generated policy to understand its permissions and verify if they can be further restricted

5. Install the generated SELinux module:
```sh
semodule -i myapp.cil /usr/share/udica/templates/{base_container.cil,net_container.cil}
```

6. Apply the custom SELinux type to your deployment by adding `securityContext` with `seLinuxOptions`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-container
          image: my-image:latest
          securityContext:
            seLinuxOptions:
              type: myapp.process
```

This approach is much safer than weakening SELinux for all workloads in your cluster. Many Helm charts support the `securityContext` field as well.

_Thanks for the tip @carolosf._

</details>

## Debugging

First and foremost, it depends, but it's always good to have a quick look into Hetzner quickly without logging in to the UI. That is where the `hcloud` cli comes in.

- Activate it with `hcloud context create Kube-hetzner`; it will prompt for your Hetzner API token, paste that, and hit `enter`.
- To check the nodes, if they are running, use `hcloud server list`.
- To check the network, use `hcloud network describe k3s`.
- To look at the LB, use `hcloud loadbalancer describe k3s-traefik`.

Then for the rest, you'll often need to log in to your cluster via ssh, to do that, use:

```sh
ssh root@<control-plane-ip> -i /path/to/private_key -o StrictHostKeyChecking=no
```

Then, for control-plane nodes, use `journalctl -u k3s` to see the k3s logs, and for agents, use `journalctl -u k3s-agent` instead.

Inspect the value of the k3s config.yaml file with: `cat /etc/rancher/k3s/config.yaml`, see if it looks kosher.

Last but not least, to see when the previous reboot took place, you can use both `last reboot` and `uptime`.

## Takedown

If you want to take down the cluster, you can proceed as follows:

```sh
terraform destroy -auto-approve
```

If you see the destroy hanging, it's probably because of the Hetzner LB and the autoscaled nodes. You can use the following command to delete everything (dry run option is available don't worry, and it will only delete resources specific to your cluster):

```sh
tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/cleanup.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"
```

As a one time thing, for convenience, you can also save it as an alias in your shell config file, like so:

```sh
alias cleanupkh='tmp_script=$(mktemp) && curl -sSL -o "${tmp_script}" https://raw.githubusercontent.com/kube-hetzner/terraform-hcloud-kube-hetzner/master/scripts/cleanup.sh && chmod +x "${tmp_script}" && "${tmp_script}" && rm "${tmp_script}"'
```

_Careful, the above commands will delete everything, including volumes in your projects. You can always try with a dry run, it will give you that option._

## Upgrading the Module

Usually, you will want to upgrade the module in your project to the latest version. Just change the version attribute in your kube.tf and terraform apply. This will upgrade the module to the latest version.

When moving from 1.x to 2.x:

- Within your project folder, run the `createkh` installation command, see [Do Not Skip](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner#-do-not-skip-creating-your-kubetf-file-and-the-opensuse-microos-snapshot) section above. This will create the snapshot for you. Don't worry, it's non-destructive and will leave your kube.tf and terraform state alone, but will download the required other packer file.
- Then modify your kube.tf to use version >= 2.0, and remove `extra_packages_to_install` and `opensuse_microos_mirror_link` variables if used. This functionality has been moved to the packer snapshot definition, see [packer-template/hcloud-microos-snapshots.pkr.hlc](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/blob/master/packer-template/hcloud-microos-snapshots.pkr.hcl).
- Then run `terraform init -upgrade && terraform apply`.

<!-- CONTRIBUTING -->

## Contributing

🌱 This project currently installs openSUSE MicroOS via the Hetzner rescue mode, making things a few minutes slower. To help with that, you could **take a few minutes to send a support request to Hetzner, asking them to please add openSUSE MicroOS as a default image**, not just an ISO. The more requests they receive, the likelier they are to add support for it, and if they do, that will cut the deployment time by half. The official link to openSUSE MicroOS is <https://get.opensuse.org/microos>, and their `OpenStack Cloud` image has full support for Cloud-init, which would probably very much suit the Hetzner Ops team!

Code contributions are very much **welcome**.

1. Fork the Project
1. Create your Branch (`git checkout -b AmazingFeature`)
1. Develop your feature

   In your kube.tf, point the `source` of module to your local clone of the repo.

   Useful commands:

   ```sh
   # To cleanup a Hetzner project
   ../kube-hetzner/scripts/cleanup.sh

   # To build the Packer image
   packer build ../kube-hetzner/packer-template/hcloud-microos-snapshots.pkr.hcl
   ```

1. Update examples in `kube.tf.example` if required.
1. Commit your Changes (`git commit -m 'Add some AmazingFeature')
1. Push to the Branch (`git push origin AmazingFeature`)
1. Open a Pull Request targeting the `staging` branch.

<!-- ACKNOWLEDGEMENTS -->

## Acknowledgements

- [k-andy](https://github.com/StarpTech/k-andy) was the starting point for this project. It wouldn't have been possible without it.
- [Best-README-Template](https://github.com/othneildrew/Best-README-Template) made writing this readme a lot easier.
- [Hetzner Cloud](https://www.hetzner.com) for providing a solid infrastructure and terraform package.
- [Hashicorp](https://www.hashicorp.com) for the amazing terraform framework that makes all the magic happen.
- [Rancher](https://www.rancher.com) for k3s, an amazing Kube distribution that is the core engine of this project.
- [openSUSE](https://www.opensuse.org) for MicroOS, which is just next-level Container OS technology.

<!-- MARKDOWN LINKS & IMAGES -->

[product-screenshot]: https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/raw/master/.images/kubectl-pod-all-17022022.png
