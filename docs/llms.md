**An Intricate Guide to Configuring the `kube-hetzner` Terraform Module for k3s on Hetzner Cloud**

**Preamble: Understanding the Landscape**

Before diving into the specifics of the configuration file, it's crucial to understand the core components and philosophies at play:

* **Terraform:** An Infrastructure as Code (IaC) tool that allows you to define and provision data center infrastructure using a declarative configuration language. It manages the lifecycle of your resources.
* **Hetzner Cloud (hcloud):** The IaaS provider where your Kubernetes cluster will reside. Terraform will interact with the Hetzner Cloud API to create servers, networks, load balancers, etc.
* **k3s:** A lightweight, certified Kubernetes distribution. It's designed to be lean and easy to install, making it ideal for edge, IoT, CI, and, as in this case, relatively straightforward cloud deployments. The `kube-hetzner` module specifically targets k3s.
* **`kube-hetzner/kube-hetzner/hcloud` Module:** A community-maintained Terraform module that abstracts away the complexity of setting up a k3s cluster on Hetzner Cloud. It provides a set of configurable inputs to define your desired cluster topology and features.
* **Declarative Configuration:** You *declare* the desired state of your infrastructure, and Terraform, with the help of the module, figures out how to achieve that state.
* **Idempotency:** Applying the same Terraform configuration multiple times should result in the same state, without unintended side effects (though some module operations might have nuances).

This guide will walk through the provided Terraform configuration, explaining the purpose, implications, and interdependencies of each setting.

---

**Section 1: `locals` Block - Foundational Variables**

```terraform
locals {
  # You have the choice of setting your Hetzner API token here or define the TF_VAR_hcloud_token env
  # within your shell, such as: export TF_VAR_hcloud_token=xxxxxxxxxxx
  # If you choose to define it in the shell, this can be left as is.

  # Your Hetzner token can be found in your Project > Security > API Token (Read & Write is required).
  hcloud_token = "xxxxxxxxxxx"
}
```

* **Purpose:** The `locals` block defines local variables within your Terraform configuration. These are not exposed as input variables to the module but are used internally within this root configuration file.
* **`hcloud_token`:**
  * **Significance:** This is arguably the most critical piece of sensitive information. It's the API token that grants Terraform programmatic access to your Hetzner Cloud account to create, modify, and delete resources.
  * **Permissions:** As noted, the token *must* have "Read & Write" permissions. A read-only token would allow Terraform to plan but fail during the apply phase when attempting to create resources.
  * **Security Considerations:**
    * **Hardcoding (as shown):** `hcloud_token = "xxxxxxxxxxx"` is convenient for quick tests but is a **significant security risk** if this file is committed to version control (e.g., Git) or shared.
    * **Environment Variable (Recommended):** The comment `export TF_VAR_hcloud_token=xxxxxxxxxxx` highlights the best practice. Terraform automatically picks up environment variables prefixed with `TF_VAR_`. So, `TF_VAR_hcloud_token` will populate a Terraform variable named `hcloud_token` (which we'll see defined later). This keeps the sensitive token out of your configuration files.
    * **Other Secret Management:** For more advanced setups, tools like HashiCorp Vault, AWS Secrets Manager, or Azure Key Vault could be used, with Terraform fetching the token at runtime.
  * **Interaction:** This `local.hcloud_token` is used as a fallback if the `var.hcloud_token` (populated by the environment variable or a `terraform.tfvars` file) is not set. The module instantiation later uses a conditional: `var.hcloud_token != "" ? var.hcloud_token : local.hcloud_token`.

---

**Section 2: `module "kube-hetzner"` Block - The Core Orchestration**

This block is where the magic happens. It instantiates the `kube-hetzner` module, passing it all the necessary configurations.

```terraform
module "kube-hetzner" {
  providers = {
    hcloud = hcloud
  }
  hcloud_token = var.hcloud_token != "" ? var.hcloud_token : local.hcloud_token
```

* **`module "kube-hetzner"`:** This declares an instance of a Terraform module. The name "kube-hetzner" here is arbitrary for this instance; you could call it "my_cluster" if you wished, though consistency with the module name is common.
* **`providers` Block:**
  * **Purpose:** Terraform modules can define their own provider requirements. When a module uses a provider (like `hcloud`), the calling configuration (this root module) needs to explicitly pass that provider configuration to the child module.
  * **`hcloud = hcloud`:** This line tells the `kube-hetzner` module to use the `hcloud` provider configuration defined in *this* root `main.tf` file (which we'll see at the end). This ensures that the module and the root configuration are using the same Hetzner account and settings.
* **`hcloud_token = var.hcloud_token != "" ? var.hcloud_token : local.hcloud_token`:**
  * **Purpose:** This is an input variable for the `kube-hetzner` module itself. The module needs the Hetzner API token to function.
  * **Logic:** This is a ternary conditional operator.
    * `var.hcloud_token != ""`: It checks if the input variable `hcloud_token` (defined at the root level, typically populated by `TF_VAR_hcloud_token`) is not an empty string.
    * `? var.hcloud_token`: If true (the environment variable is set), use its value.
    * `: local.hcloud_token`: If false (the environment variable is not set or is empty), fall back to using the `hcloud_token` defined in the `locals` block at the top of this file.
  * **Benefit:** This provides flexibility in how the token is supplied, prioritizing environment variables for better security practices.

```terraform
  # Then fill or edit the below values. Only the first values starting with a * are obligatory; the rest can remain with their default values, or you
  # could adapt them to your needs.

  # * source can be specified in multiple ways:
  # 1. For normal use, (the official version published on the Terraform Registry), use
  source = "kube-hetzner/kube-hetzner/hcloud"
  #    When using the terraform registry as source, you can optionally specify a version number.
  #    See https://registry.terraform.io/modules/kube-hetzner/kube-hetzner/hcloud for the available versions
  # version = "2.15.3"
  # 2. For local dev, path to the git repo
  # source = "../../kube-hetzner/"
  # 3. If you want to use the latest master branch (see https://developer.hashicorp.com/terraform/language/modules/sources#github), use
  # source = "github.com/kube-hetzner/terraform-hcloud-kube-hetzner"
```

* **`source` (Obligatory):**
  * **Purpose:** This tells Terraform where to find the `kube-hetzner` module code.
  * **Option 1 (Terraform Registry - Recommended for Users):** `kube-hetzner/kube-hetzner/hcloud`
    * This is the standard way to use published modules. Terraform will download it from the public Terraform Registry.
    * **`version`:** It's highly recommended to pin the module version (e.g., `version = "2.15.3"`). This ensures:
      * **Reproducibility:** Your infrastructure builds are consistent over time.
      * **Stability:** Prevents unexpected changes or breakages if a new, incompatible version of the module is released.
      * **Controlled Upgrades:** You can consciously decide when to upgrade the module version after reviewing its changelog.
  * **Option 2 (Local Path - For Module Developers/Contributors):** `source = "../../kube-hetzner/"`
    * Used when you have a local copy of the module's source code, typically for development or testing modifications to the module itself. The path is relative to this `main.tf` file.
  * **Option 3 (Direct Git Repository - For Bleeding Edge/Specific Commits):** `source = "github.com/kube-hetzner/terraform-hcloud-kube-hetzner"`
    * Pulls the module directly from the `master` branch of the GitHub repository. This is generally **not recommended for production** as `master` can be unstable.
    * You can also specify a specific branch, tag, or commit hash using the `ref` query parameter (e.g., `source = "github.com/kube-hetzner/terraform-hcloud-kube-hetzner?ref=v2.15.3"`).

```terraform
  # Note that some values, notably "location" and "public_key" have no effect after initializing the cluster.
  # This is to keep Terraform from re-provisioning all nodes at once, which would lose data. If you want to update
  # those, you should instead change the value here and manually re-provision each node. Grep for "lifecycle".
```

* **Important Note on Immutability:**
  * This comment highlights a critical aspect of how this module (and often Terraform resources in general) handles certain changes.
  * **`location` and `public_key`:** For existing server nodes, changing these attributes in the Terraform configuration *after* the initial `terraform apply` will not automatically trigger a change on the Hetzner Cloud server itself through a simple `terraform apply`.
  * **Reasoning (Data Preservation):** If Terraform were to change the location of a server, it would mean destroying the old server and creating a new one, leading to data loss. Similarly, changing the primary SSH key might involve complex OS-level operations or re-provisioning.
  * **Module's Approach (`lifecycle` block):** The module likely uses Terraform's `lifecycle` meta-argument, specifically `ignore_changes`, on these attributes for the server resources. This tells Terraform to create the resource with the initial value but then ignore any subsequent changes to that attribute in the configuration for plan/apply purposes.
  * **Manual Intervention Required:** If you *need* to change these, you must:
    1. Update the value in your Terraform configuration.
    2. Manually re-provision the affected node(s). This could involve:
       * Cordoning and draining the node in Kubernetes.
       * Using `terraform taint <resource_address>` to mark the specific server resource for recreation on the next `apply`.
       * Manually deleting the server in Hetzner Cloud and letting Terraform recreate it.
    * This is a deliberate design choice to prevent accidental data loss or full cluster rebuilds for minor changes to sensitive, foundational attributes.

```terraform
  # Customize the SSH port (by default 22)
  # ssh_port = 2222
```

* **`ssh_port` (Optional):**
  * **Default:** `22`
  * **Purpose:** Allows you to specify a custom SSH port for the nodes created by the module. The module will configure the SSH daemon on the nodes to listen on this port and adjust firewall rules accordingly.
  * **Use Case:** Security through obscurity (minor benefit) or if port 22 is blocked/used by something else in your environment.
  * **Implication:** You'll need to specify this custom port when SSHing into the nodes (e.g., `ssh -p 2222 user@node_ip`).

```terraform
  # * Your ssh public key
  ssh_public_key = file("~/.ssh/id_ed25519.pub")
  # * Your private key must be "ssh_private_key = null" when you want to use ssh-agent for a Yubikey-like device authentication or an SSH key-pair with a passphrase.
  # For more details on SSH see https://github.com/kube-hetzner/kube-hetzner/blob/master/docs/ssh.md
  ssh_private_key = file("~/.ssh/id_ed25519")
  # You can add additional SSH public Keys to grant other team members root access to your cluster nodes.
  # ssh_additional_public_keys = []
```

* **`ssh_public_key` (Obligatory):**
  * **Purpose:** The content of your SSH public key. This key will be added to the `authorized_keys` file on all created nodes, allowing you to SSH into them as the root user (or the default user configured by the OS image).
  * **`file("~/.ssh/id_ed25519.pub")`:** The `file()` function reads the content of the specified file. `~` is expanded to your home directory. Ensure this path is correct.
  * **Security:** This is the primary means of accessing your nodes. Protect your corresponding private key.
* **`ssh_private_key` (Obligatory, but can be `null`):**
  * **Purpose:** The content of your SSH private key. This is used by Terraform's provisioners (if the module uses them for direct SSH commands during setup) or by tools like Ansible if integrated. It's also used for generating the kubeconfig if it needs to SSH into a node to fetch it.
  * **`file("~/.ssh/id_ed25519")`:** Reads the private key content.
  * **`ssh_private_key = null` (Conditional Usage):**
    * **When to use `null`:** If your private key is passphrase-protected, or if you're using an SSH agent (e.g., with a YubiKey or `ssh-add`), you *must* set this to `null`. Terraform cannot directly use a passphrase-protected key without the passphrase.
    * **SSH Agent Reliance:** When `null`, Terraform (and underlying tools used by the module) will attempt to use an already configured SSH agent to authenticate. Ensure your key is added to the agent (`ssh-add ~/.ssh/your_private_key`).
  * **Security:** Hardcoding the private key content via `file()` is less secure if the `.tf` file is shared. Using `null` with an SSH agent is generally preferred for keys with passphrases.
* **`ssh_additional_public_keys` (Optional):**
  * **Default:** `[]` (empty list)
  * **Purpose:** A list of strings, where each string is the content of an additional SSH public key. These keys will also be added to `authorized_keys` on the nodes.
  * **Use Case:** Granting SSH access to other team members or automated systems without sharing your primary private key.
  * **Format:** `ssh_additional_public_keys = [file("~/.ssh/teammate1.pub"), "ssh-rsa AAAAB3NzaC1yc2EAAA... user@host"]`

```terraform
  # You can also add additional SSH public Keys which are saved in the hetzner cloud by a label.
  # See https://docs.hetzner.com/cloud/#label-selector
  # ssh_hcloud_key_label = "role=admin"
```

* **`ssh_hcloud_key_label` (Optional):**
  * **Purpose:** Instead of providing raw public key content, you can specify a label. The module will then find SSH keys already uploaded to your Hetzner Cloud project that match this label and add them to the nodes.
  * **Hetzner Cloud Feature:** This leverages Hetzner's ability to store and label SSH keys.
  * **Use Case:** Managing a central repository of SSH keys in Hetzner Cloud and assigning them to servers based on roles or teams.
  * **Format:** A string representing the label selector (e.g., `"team=devops"`, `"environment=production,role=admin"`).

```terraform
  # If you use SSH agent and have issues with SSH connecting to your nodes, you can increase the number of auth tries (default is 2)
  # ssh_max_auth_tries = 10
```

* **`ssh_max_auth_tries` (Optional):**
  * **Default:** `2` (or a small number set by the underlying SSH client/library).
  * **Purpose:** Controls the `MaxAuthTries` setting for SSH connections made by Terraform/module scripts.
  * **Use Case:** If you have many keys loaded in your SSH agent, the server might close the connection before the correct key is tried. Increasing this value gives the SSH client more attempts to offer different keys.
  * **Caution:** Setting this too high could theoretically make brute-force attacks slightly easier if other security measures are weak, but the primary defense is strong key management.

```terraform
  # If you want to use an ssh key that is already registered within hetzner cloud, you can pass its id.
  # If no id is passed, a new ssh key will be registered within hetzner cloud.
  # It is important that exactly this key is passed via `ssh_public_key` & `ssh_private_key` variables.
  # hcloud_ssh_key_id = ""
```

* **`hcloud_ssh_key_id` (Optional):**
  * **Purpose:** Allows you to use an SSH key that is *already registered* in your Hetzner Cloud project by specifying its unique ID.
  * **Behavior:**
    * **If ID provided:** The module will associate this existing Hetzner SSH key resource with the created servers. It will *not* create a new SSH key resource in Hetzner Cloud based on `ssh_public_key`.
    * **If ID not provided (or empty string):** The module will create a *new* SSH key resource in Hetzner Cloud using the content from `ssh_public_key` and associate that new key with the servers.
  * **Crucial Constraint:** The comment "It is important that exactly this key is passed via `ssh_public_key` & `ssh_private_key` variables" is vital. Even if using an existing Hetzner key ID, the module might still need the raw public key content for other purposes (e.g., configuring `authorized_keys` directly if Hetzner's association method isn't solely relied upon, or for consistency). The private key is needed if SSH connections are made by provisioners. This ensures the keys Terraform *thinks* it's using match the key Hetzner *knows* about.

```terraform
  # These can be customized, or left with the default values
  # * For Hetzner locations see https://docs.hetzner.com/general/others/data-centers-and-connection/
  network_region = "eu-central" # change to `us-east` if location is ash
```

* **`network_region` (Obligatory, though has a default in the module):**
  * **Default (in module, not shown here):** Likely "eu-central".
  * **Purpose:** Specifies the broad geographical region for your Hetzner Cloud private network. All servers and load balancers within the same private network must reside in locations that belong to this network region.
  * **Hetzner Regions:**
    * `eu-central`: Encompasses European locations like Falkenstein (`fsn1` - currently unavailable due to high demand), Nuremberg (`nbg1`), Helsinki (`hel1`).
    * `us-east`: Encompasses Ashburn, VA (`ash`).
    * `us-west`: Encompasses Hillsboro, OR (`hil`). (Check if supported by module if you intend to use it)
  * **Constraint:** The `location` specified in your `control_plane_nodepools` and `agent_nodepools` *must* be compatible with this `network_region`. You cannot have a server in `fsn1` (Europe) in a network defined for `us-east`.

```terraform
  # If you want to create the private network before calling this module,
  # you can do so and pass its id here. For example if you want to use a proxy
  # which only listens on your private network. Advanced use case.
  #
  # NOTE1: make sure to adapt network_ipv4_cidr, cluster_ipv4_cidr, and service_ipv4_cidr accordingly.
  #        If your network is created with 10.0.0.0/8, and you use subnet 10.128.0.0/9 for your
  #        non-k3s business, then adapting `network_ipv4_cidr = "10.0.0.0/9"` should be all you need.
  #
  # NOTE2: square brackets! This must be a list of length 1.
  #
  # existing_network_id = [hcloud_network.your_network.id]
```

* **`existing_network_id` (Optional, Advanced):**
  * **Default:** Not set, meaning the module will create and manage its own Hetzner Cloud private network.
  * **Purpose:** Allows you to use a pre-existing Hetzner Cloud private network for your Kubernetes cluster.
  * **Format:** A list containing a single element: the ID of the existing Hetzner network (e.g., `[1234567]`). The comment `[hcloud_network.your_network.id]` shows how you'd reference a network created in the same Terraform configuration but outside this module.
  * **Use Case:** Integrating the Kubernetes cluster into a larger, existing infrastructure on Hetzner Cloud where other services already reside on a specific private network.
  * **Critical Considerations (NOTE1):** If you use an existing network, you are responsible for ensuring that the IP address ranges used by this module (`network_ipv4_cidr`, `cluster_ipv4_cidr`, `service_ipv4_cidr`) do not conflict with other subnets or IP ranges already in use on that existing network. You might need to adjust these CIDR parameters in the module configuration to fit within an available portion of your existing network's IP space. The example given (using `10.0.0.0/9` for k3s within a larger `10.0.0.0/8` network) illustrates this.

```terraform
  # If you must change the network CIDR you can do so below, but it is highly advised against.
  # network_ipv4_cidr = "10.0.0.0/8"
```

* **`network_ipv4_cidr` (Optional, Advanced):**
  * **Default (in module):** Typically `10.0.0.0/8`.
  * **Purpose:** Defines the overall IP address range for the Hetzner Cloud private network that the module will create (if `existing_network_id` is not used). All other internal Kubernetes CIDRs (for pods, services, and node subnets) will be carved out of this range.
  * **Warning:** "highly advised against" changing this unless you have a very specific reason (e.g., conflict with on-premises networks if using VPN/interconnect, or needing a smaller/different range for a very specific setup). Changing it requires careful planning of all sub-CIDRs.
  * **Impact:** If changed, `cluster_ipv4_cidr` and `service_ipv4_cidr` must be sub-ranges within this new `network_ipv4_cidr`.

```terraform
  # The amount of subnets into which the network will be split. Must be a power of 2.
  # subnet_amount = 256
```

* **`subnet_amount` (Number, Optional):**
  * **Default:** `256`.
  * **Purpose:** Determines into how many subnets the `network_ipv4_cidr` is divided.
  * **Constraint:** Must be a power of 2. Each nodepool (control plane and agent) and potentially the NAT router takes one subnet. Ensure this is large enough for your planned number of nodepools.

```terraform
  # Using the default configuration you can only create a maximum of 42 agent-nodepools.
  # This is due to the creation of a subnet for each nodepool with CIDRs being in the shape of 10.[nodepool-index].0.0/16 which collides with k3s' cluster and service IP ranges (defaults below).
  # Furthermore the maximum number of nodepools (controlplane and agent) is 50, due to a hard limit of 50 subnets per network, see https://docs.hetzner.com/cloud/networks/faq/.
  # So to be able to create a maximum of 50 nodepools in total, the values below have to be changed to something outside that range, e.g. `10.200.0.0/16` and `10.201.0.0/16` for cluster and service respectively.
```

* **Explanation of Nodepool Subnet Allocation and Limits:**
  * **Subnet per Nodepool:** The module creates a dedicated subnet within the Hetzner private network for each nodepool (both control plane and agent). This provides network isolation at the Hetzner level and allows for distinct IP ranges per nodepool.
  * **Default Subnetting Scheme:** The module uses a scheme like `10.[nodepool-index].0.0/16` for these subnets. For example, the first nodepool might get `10.1.0.0/16`, the second `10.2.0.0/16`, and so on.
  * **Collision Issue:** The default k3s cluster CIDR (`10.42.0.0/16`) and service CIDR (`10.43.0.0/16`) would collide if a nodepool index reached 42 or 43 using this scheme. This limits the number of *agent* nodepools to 42 if defaults are kept.
  * **Hetzner Subnet Limit:** Hetzner Cloud has a hard limit of 50 subnets per private network. This is the ultimate cap on the total number of nodepools (control plane + agent).
  * **Solution for >42 Nodepools:** To exceed 42 nodepools (up to the 50 limit), you *must* change `cluster_ipv4_cidr` and `service_ipv4_cidr` to ranges that won't collide with the `10.[0-49].0.0/16` nodepool subnet ranges. The example `10.200.0.0/16` and `10.201.0.0/16` achieves this.

```terraform
  # If you must change the cluster CIDR you can do so below, but it is highly advised against.
  # Never change this value after you already initialized a cluster. Complete cluster redeploy needed!
  # The cluster CIDR must be a part of the network CIDR!
  # cluster_ipv4_cidr = "10.42.0.0/16"
```

* **`cluster_ipv4_cidr` (Optional, Advanced):**
  * **Default (in module):** `10.42.0.0/16` (a common default for k3s/Kubernetes).
  * **Purpose:** This is the IP address range from which Kubernetes assigns IP addresses to Pods running within the cluster.
  * **Critical Warning:** "Never change this value after you already initialized a cluster." Doing so would require a complete cluster redeployment because all existing Pods and network configurations would become invalid.
  * **Constraint:** Must be a sub-range of `network_ipv4_cidr`.
  * **Interdependency:** As explained above, may need to be changed if you require more than 42 nodepools.

```terraform
  # If you must change the service CIDR you can do so below, but it is highly advised against.
  # Never change this value after you already initialized a cluster. Complete cluster redeploy needed!
  # The service CIDR must be a part of the network CIDR!
  # service_ipv4_cidr = "10.43.0.0/16"
```

* **`service_ipv4_cidr` (Optional, Advanced):**
  * **Default (in module):** `10.43.0.0/16` (a common default for k3s/Kubernetes).
  * **Purpose:** This is the IP address range from which Kubernetes assigns virtual IP addresses to Services (e.g., ClusterIP services).
  * **Critical Warning:** Same as `cluster_ipv4_cidr` – do not change post-initialization without a full redeploy.
  * **Constraint:** Must be a sub-range of `network_ipv4_cidr`.
  * **Interdependency:** May need to be changed if you require more than 42 nodepools.

```terraform
  # If you must change the service IPv4 address of core-dns you can do so below, but it is highly advised against.
  # Never change this value after you already initialized a cluster. Complete cluster redeploy needed!
  # The service IPv4 address must be part of the service CIDR!
  # cluster_dns_ipv4 = "10.43.0.10"
```

* **`cluster_dns_ipv4` (Optional, Advanced):**
  * **Default (in module):** `10.43.0.10`.
  * **Purpose:** Specifies the static IP address for the CoreDNS service (or KubeDNS) within the cluster. Pods use this IP to resolve internal and external domain names.
  * **Critical Warning:** Same as above – do not change post-initialization.
  * **Constraint:** This IP address *must* fall within the `service_ipv4_cidr` range. Typically, it's one of the first few usable IPs in that range (e.g., `.10`).

The subsequent sections on `control_plane_nodepools` and `agent_nodepools` are extensive. I will break them down carefully.

---

**Section 2.1: `control_plane_nodepools` - The Brains of the Operation**

```terraform
  # For the control planes, at least three nodes are the minimum for HA. Otherwise, you need to turn off the automatic upgrades (see README).
  # **It must always be an ODD number, never even!** Search the internet for "split-brain problem with etcd" or see https://rancher.com/docs/k3s/latest/en/installation/ha-embedded/
  # For instance, one is ok (non-HA), two is not ok, and three is ok (becomes HA). It does not matter if they are in the same nodepool or not! So they can be in different locations and of various types.

  # Of course, you can choose any number of nodepools you want, with the location you want. The only constraint on the location is that you need to stay in the same network region, Europe, or the US.
  # For the server type, the minimum instance supported is cx23. If you want to use arm64 use cax11; see https://www.hetzner.com/cloud.

  # IMPORTANT: Before you create your cluster, you can do anything you want with the nodepools, but you need at least one of each, control plane and agent.
  # Once the cluster is up and running, you can change nodepool count and even set it to 0 (in the case of the first control-plane nodepool, the minimum is 1).
  # You can also rename it (if the count is 0), but do not remove a nodepool from the list.

  # You can safely add or remove nodepools at the end of each list. That is due to how subnets and IPs get allocated (FILO).
  # The maximum number of nodepools you can create combined for both lists is 50 (see above).
  # Also, before decreasing the count of any nodepools to 0, it's essential to drain and cordon the nodes in question. Otherwise, it will leave your cluster in a bad state.

  # Before initializing the cluster, you can change all parameters and add or remove any nodepools. You need at least one nodepool of each kind, control plane, and agent.
  # ⚠️ The nodepool names are entirely arbitrary, but all lowercase, no special characters or underscore (dashes are allowed), and they must be unique.

  # If you want to have a single node cluster, have one control plane nodepools with a count of 1, and one agent nodepool with a count of 0.

  # Please note that changing labels and taints after the first run will have no effect. If needed, you can do that through Kubernetes directly.

  # Multi-architecture clusters are OK for most use cases, as container underlying images tend to be multi-architecture too.

  # * Example below:

  control_plane_nodepools = [
    {
      name        = "control-plane-nbg1",
      server_type = "cx23",
      location    = "nbg1",
      labels      = [],
      taints      = [],
      count       = 1
      # swap_size   = "2G" # remember to add the suffix, examples: 512M, 1G
      # zram_size   = "2G" # remember to add the suffix, examples: 512M, 1G
      # kubelet_args = ["kube-reserved=cpu=250m,memory=1500Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"]

      # Fine-grained control over placement groups (nodes in the same group are spread over different physical servers, 10 nodes per placement group max):
      # placement_group = "default"

      # Enable automatic backups via Hetzner (default: false)
      # backups = true

      # To disable public ips (default: false)
      # WARNING: If both values are set to "true", your server will only be accessible via a private network. Make sure you have followed
      # the instructions regarding this type of setup in README.md: "Use only private IPs in your cluster".
      # disable_ipv4 = true
      # disable_ipv6 = true
    },
    // ... more control plane nodepool examples ...
  ]
```

* **`control_plane_nodepools` (Obligatory, list of maps):**
  * **Purpose:** Defines one or more groups of control plane nodes. Control plane nodes run the Kubernetes master components (API server, scheduler, controller manager) and, in k3s with an embedded database, `etcd` (or the k3s default, SQLite for single-node, or embedded etcd for HA).
  * **Structure:** A list of maps, where each map defines a distinct nodepool.
  * **High Availability (HA) Critical Logic:**
    * **Minimum for HA:** 3 control plane nodes.
    * **Odd Number:** Always use an odd number (1, 3, 5, etc.) for etcd quorum to prevent split-brain scenarios. 2 nodes are worse than 1 for HA.
    * **Impact of Non-HA (1 control plane):** If you have only one control plane node, features like `automatically_upgrade_os` and `automatically_upgrade_k3s` (if not managed carefully) can lead to downtime. The module's README and comments often advise disabling automatic upgrades for single control plane setups.
    * **Distribution:** HA control plane nodes can be in the same nodepool definition (e.g., `count = 3` in one map) or spread across multiple nodepool definitions (e.g., three maps, each with `count = 1`, potentially in different `location`s for better fault tolerance).
  * **Minimum Requirements (Initial Cluster Create):**
    * At least one control plane nodepool with `count >= 1`.
    * (Typically) At least one agent nodepool with `count >= 1`, *unless* you are creating a single-node cluster where the control plane also acts as a worker (see below).
  * **Lifecycle of Nodepools:**
    * **Adding/Removing Nodepools:** You can safely add new nodepool definitions to the *end* of the list or remove nodepool definitions from the *end* of the list. This is due to how the module allocates subnets (FILO - First In, Last Out, or rather, sequentially). Modifying nodepools in the middle of the list can cause existing nodepools to be re-evaluated for their subnet, potentially leading to disruption.
    * **Changing `count`:**
      * **Increasing:** Generally safe. New nodes will be provisioned.
      * **Decreasing (to > 0):** Terraform will select nodes to remove. Ensure workloads are drained from these nodes (`kubectl drain`) before applying, to prevent data loss or service interruption.
      * **Decreasing to `0`:** The nodepool becomes effectively dormant. Its subnet remains. Before doing this, *all nodes in that pool must be drained and cordoned*.
    * **Renaming:** A nodepool can be renamed *only if its `count` is 0*. Otherwise, Terraform will see it as destroying the old and creating a new one.
    * **Removing from List:** Do not remove a nodepool definition from the list if it still has active nodes or if you intend to use it again. Set its `count` to 0 first.
  * **Single-Node Cluster:**
    * One control plane nodepool with `count = 1`.
    * One (or more) agent nodepools with `count = 0`.
    * The module typically automatically allows scheduling on the control plane in this scenario (or you'd set `allow_scheduling_on_control_plane = true`).
  * **Multi-Architecture:** Mixing x86 (`cx` series) and ARM (`cax` series) nodes is generally fine. Kubernetes and container runtimes handle this, and many container images are multi-arch.
  * **Nodepool Attributes (per map):**
    * **`name` (String, Obligatory):**
      * A unique, arbitrary name for this nodepool.
      * Constraints: Lowercase, no special characters except dashes (`-`).
      * Used for naming resources in Hetzner and for Kubernetes node labels/names.
    * **`server_type` (String, Obligatory):**
      * Hetzner server type:
        * x86: e.g. `cx23` (2 vCPU, 4GB RAM, 40GB SSD), `cx33` (4 vCPU, 8GB RAM, 80GB SSD), `cx43` (8 vCPU, 16GB RAM, 160GB SSD).
        * ARM: e.g. `cax11` (2 vCPU, 4GB RAM, 40GB SSD), `cax21` (4 vCPU, 8GB RAM, 80GB SSD).
      * Minimum for control plane: `cx23` is often cited. More demanding setups (e.g., with Cilium CNI, Rancher) might require more RAM (e.g., `cx33`/`cx43` or `cax21`/`cax31`).
    * **`location` (String, Obligatory):**
      * Hetzner location (e.g., `fsn1`, `nbg1`, `hel1`, `ash`).
      * Must be within the `network_region` defined earlier.
      * For HA, distributing control plane nodes across different locations (within the same region) improves fault tolerance against a single location outage.
    * **`labels` (List of Strings, Optional):**
      * Default: `[]`.
      * Kubernetes labels to apply to nodes in this pool. Format: `["key1=value1", "key2=value2"]`.
      * **Lifecycle Note:** "changing labels and taints after the first run will have no effect." The module likely applies these only at node creation. Subsequent changes must be done via `kubectl label node ...`.
    * **`taints` (List of Strings, Optional):**
      * Default: `[]`.
      * Kubernetes taints to apply to nodes in this pool. Format: `["key=value:Effect"]` (e.g., `"dedicated=control-plane:NoSchedule"`).
      * Taints prevent pods from being scheduled on these nodes unless the pods have a corresponding toleration. Control planes often have taints to prevent regular workloads from running on them.
      * **Lifecycle Note:** Same as labels – apply via `kubectl taint node ...` after initial creation if changes are needed.
    * **`count` (Number, Obligatory):**
      * Number of server instances to create in this specific nodepool.
    * **`swap_size` (String, Optional):**
      * Examples: `"512M"`, `"2G"`, `"4G"`.
      * Configures a swap file of the specified size on the nodes.
      * **K3s/Kubernetes Consideration:** Kubernetes traditionally doesn't work well with swap. However, recent versions of k3s/kubelet can support it if the `NodeSwap` feature gate is enabled and kubelet is configured correctly. The comment `Make sure you set "feature-gates=NodeSwap=true" if want to use swap_size` (seen later under `k3s_global_kubelet_args`) is relevant here. Use with caution and understanding of its implications on performance and scheduling.
    * **`zram_size` (String, Optional):**
      * Examples: `"512M"`, `"1G"`.
      * Configures zRAM (compressed RAM block device, often used for swap) on the nodes.
      * Can be an alternative or supplement to traditional disk-based swap, offering faster swap at the cost of CPU for compression/decompression.
    * **`kubelet_args` (List of Strings, Optional):**
      * Allows passing additional arguments directly to the `kubelet` process running on nodes in this specific pool.
      * Example: `["kube-reserved=cpu=250m,memory=1500Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"]`
      * This is for fine-grained resource reservation for Kubernetes system components (`kube-reserved`) and OS system components (`system-reserved`), ensuring they have enough resources and don't get starved by user pods.
      * **Note:** There are also global `k3s_global_kubelet_args`, `k3s_control_plane_kubelet_args`, etc., defined later. These nodepool-specific `kubelet_args` likely supplement or override those for this pool.
    * **`placement_group` (String, Optional):**
      * Default: The module might create a default placement group or assign nodes to one.
      * Purpose: Hetzner Placement Groups ensure that servers within the same group are located on different physical host systems (spread strategy). This improves fault tolerance against hardware failures on a single host.
      * Value: Name of the placement group. If you specify the same name for multiple nodes/nodepools, they'll try to be in that group.
      * Limit: Hetzner placement groups have limits (e.g., 10 servers per spread placement group). The module might manage creating multiple groups if a nodepool `count` exceeds this.
    * **`backups` (Boolean, Optional):**
      * Default: `false`.
      * If `true`, enables Hetzner's automated server backup service for nodes in this pool. This incurs additional cost per server.
    * **`disable_ipv4` (Boolean, Optional) / `disable_ipv6` (Boolean, Optional):**
      * Default: `false` for both.
      * If `true`, disables the public IPv4 or IPv6 interface on the server, respectively.
      * **Warning:** If both are `true`, the server will *only* have a private IP address and will only be accessible via the Hetzner private network (e.g., from another server in the same network, or via a VPN/bastion host connected to that network). This is an advanced setup requiring careful network planning. The comment refers to a `README.md` section "Use only private IPs in your cluster" for guidance.

The example shows three control plane nodepools, each with one node, in different locations (`fsn1`, `nbg1`, `hel1`). This is a common pattern for a 3-node HA control plane, maximizing fault tolerance across Hetzner locations (within the same `network_region`).

---

**Section 2.2: `agent_nodepools` - The Workhorses**

```terraform
  agent_nodepools = [
    {
      name        = "agent-small",
      server_type = "cx23",
      location    = "nbg1",
      labels      = [],
      taints      = [],
      count       = 1
      # swap_size   = "2G"
      # zram_size   = "2G"
      # kubelet_args = ["kube-reserved=cpu=50m,memory=300Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"]
      # placement_group = "default"
      # backups = true
    },
    {
      name        = "agent-large",
      server_type = "cx33",
      location    = "nbg1",
      labels      = [],
      taints      = [],
      count       = 1
      # placement_group = "default"
      # backups = true
    },
    {
      name        = "storage",
      server_type = "cx33",
      location    = "nbg1",
      labels      = [
        "node.kubernetes.io/server-usage=storage" # Example label
      ],
      taints      = [], # Could add taints to only allow storage workloads
      count       = 1
      # In the case of using Longhorn, you can use Hetzner volumes instead of using the node's own storage by specifying a value from 10 to 10240 (in GB)
      # It will create one volume per node in the nodepool, and configure Longhorn to use them.
      # Something worth noting is that Volume storage is slower than node storage, which is achieved by not mentioning longhorn_volume_size or setting it to 0.
      # So for something like DBs, you definitely want node storage, for other things like backups, volume storage is fine, and cheaper.
      # longhorn_volume_size = 20 # In GB
      # backups = true
    },
    # Egress nodepool useful to route egress traffic using Hetzner Floating IPs
    # used with Cilium's Egress Gateway feature
    {
      name        = "egress",
      server_type = "cx23",
      location    = "nbg1",
      labels = [
        "node.kubernetes.io/role=egress"
      ],
      taints = [
        "node.kubernetes.io/role=egress:NoSchedule" # Ensures only egress gateway pods run here
      ],
      floating_ip = true # Special attribute for this module
      # Optionally associate a reverse DNS entry with the floating IP(s).
      # floating_ip_rns = "my.domain.com"
      count = 1
    },
    # Arm based nodes
    {
      name        = "agent-arm-small",
      server_type = "cax11", # ARM server type
      location    = "nbg1",
      labels      = [],
      taints      = [],
      count       = 1
    },
    # For fine-grained control over the nodes in a node pool, replace the count variable with a nodes map.
    # In this case, the node-pool variables are defaults which can be overridden on a per-node basis.
    # Each key in the nodes map refers to a single node and must be an integer string ("1", "123", ...).
    {
      name        = "agent-arm-medium",
      server_type = "cax21", # Default server_type for this pool
      location    = "nbg1",  # Default location
      labels      = [],
      taints      = [],
      nodes = { # Overrides 'count' and allows per-node customization
        "1" : { # Node identified as "1" within this pool
          location = "fsn1" # Override location for this specific node
          labels = [
            "testing-labels=a1",
          ]
        },
        "20" : { # Node identified as "20"
          labels = [
            "testing-labels=b1",
          ]
          # server_type could also be overridden here if needed
        }
      }
    },
  ]
```

* **`agent_nodepools` (Obligatory, list of maps):**
  * **Purpose:** Defines groups of agent (worker) nodes. These nodes run your actual application Pods.
  * **Structure and Lifecycle:** Similar to `control_plane_nodepools` (list of maps, rules for adding/removing/renaming apply).
  * **Minimum Requirement (Initial Cluster Create):** Typically, at least one agent nodepool with `count >= 1` is needed, unless it's a single-node cluster where the control plane also acts as a worker (in which case, agent nodepool counts can be 0).
  * **Nodepool Attributes (per map):** Most attributes are the same as for `control_plane_nodepools` (`name`, `server_type`, `location`, `labels`, `taints`, `count`, `swap_size`, `zram_size`, `kubelet_args`, `placement_group`, `backups`, `disable_ipv4`/`ipv6`).
  * **Specific Agent Nodepool Attributes/Examples:**
    * **`longhorn_volume_size` (Number, Optional, specific to agent nodepools if Longhorn is enabled):**
      * If `enable_longhorn = true` (a global module setting), this attribute can be added to an agent nodepool definition.
      * **Purpose:** Instructs the module to create a Hetzner Cloud Volume of the specified size (in GB, e.g., `20` for 20GB) for *each node* in this pool. Longhorn will then be configured to use these dedicated Hetzner Volumes for its storage replicas instead of using the node's local disk.
      * **Trade-offs:**
        * **Hetzner Volumes:** Network-attached, potentially slower than local NVMe/SSD storage on the node, but can be larger, are independently manageable, and might be cheaper for bulk storage. Good for less I/O-intensive workloads or where data persistence independent of the node's lifecycle is paramount.
        * **Node Local Storage (if `longhorn_volume_size` is not set or 0):** Longhorn uses a directory on the node's filesystem. Faster I/O, but storage is tied to the node's disk.
      * **Recommendation:** The comment wisely suggests local storage for databases (high I/O) and Hetzner Volumes for backups or less critical storage.
    * **`floating_ip` (Boolean, Optional, specific to egress nodepool example):**
      * Default: `false`.
      * If `true`, the module will provision a Hetzner Floating IP and associate it with the node(s) in this pool. If `count > 1`, how the floating IP is managed across multiple nodes needs clarification from module docs (e.g., active/passive, or one FIP per node).
      * **Use Case (Egress Gateway):** As shown in the "egress" nodepool example, this is used with Cilium's Egress Gateway feature. This allows you to have a stable, predictable public IP address for outbound traffic originating from your cluster, which can be useful for whitelisting with external services.
      * The `labels` and `taints` on the "egress" pool ensure that only specific egress gateway pods (which would have tolerations for the taint) are scheduled there.
    * **`floating_ip_rns` (String, Optional):**
      * If `floating_ip = true`, this allows you to set a reverse DNS (PTR record) for the provisioned floating IP.
      * Use Case: Email servers or services where reverse DNS is important for reputation.
    * **`nodes` (Map of Maps, Optional, replaces `count`):**
      * **Purpose:** Provides fine-grained control over individual nodes within a single nodepool definition, overriding the nodepool-level defaults for `location`, `labels`, `taints`, `server_type`, etc., on a per-node basis.
      * **Structure:**
        * The top-level nodepool definition provides the defaults.
        * The `nodes` map's keys are arbitrary string identifiers for each node (e.g., `"1"`, `"20"`). These are not server IDs but logical identifiers within this Terraform definition.
        * Each value in the `nodes` map is another map specifying the attributes to override for that particular node.
      * **Example Breakdown (`agent-arm-medium`):**
        * Default `server_type`: `cax21`
        * Default `location`: `nbg1`
        * Node `"1"`: Overrides `location` to `fsn1` and adds specific `labels`. It will use the default `cax21` server type.
        * Node `"20"`: Uses default `location` (`nbg1`) and `server_type` (`cax21`) but has its own specific `labels`.
      * **Benefit:** Useful when you need slight variations for a few nodes within a larger, mostly homogeneous pool, without creating many separate small nodepool definitions.

---

**Section 2.3: Custom K3s Configuration Arguments**

```terraform
  # Add additional configuration options for control planes here.
  # E.g to enable monitoring for etcd, proxy etc:
  # control_planes_custom_config = {
  #  etcd-expose-metrics = true,
  #  kube-controller-manager-arg = "bind-address=0.0.0.0",
  #  kube-proxy-arg ="metrics-bind-address=0.0.0.0",
  #  kube-scheduler-arg = "bind-address=0.0.0.0",
  # }

  # Add additional configuration options for agent nodes and autoscaler nodes here.
  # E.g to enable monitoring for proxy:
  # agent_nodes_custom_config = {
  #  kube-proxy-arg ="metrics-bind-address=0.0.0.0",
  # }
```

* **`control_planes_custom_config` (Map, Optional):**
  * **Purpose:** Allows passing custom configuration parameters that will be translated into the k3s server configuration file (typically `/etc/rancher/k3s/config.yaml` or passed as CLI args to the k3s server process) specifically for control plane nodes.
  * **Format:** A map where keys are k3s configuration options (often matching CLI flags without the leading `--` or `config.yaml` keys) and values are their settings.
  * **Example Usage:**
    * `etcd-expose-metrics = true`: Enables Prometheus metrics endpoint for the embedded etcd.
    * `kube-controller-manager-arg = "bind-address=0.0.0.0"`: Makes the controller manager's metrics/health endpoint listen on all interfaces (use with caution, consider firewall implications). Similar for `kube-proxy-arg` and `kube-scheduler-arg`.
  * **Reference:** Consult the [k3s server configuration options documentation](https://rancher.com/docs/k3s/latest/en/installation/configuration/#configuration-file) for available keys.
* **`agent_nodes_custom_config` (Map, Optional):**
  * **Purpose:** Similar to `control_planes_custom_config`, but applies to k3s agent configuration on agent nodes and nodes created by the cluster autoscaler.
  * **Example Usage:** `kube-proxy-arg ="metrics-bind-address=0.0.0.0"` enables kube-proxy metrics on agent nodes.
  * **Reference:** Consult the [k3s agent configuration options documentation](https://rancher.com/docs/k3s/latest/en/installation/configuration/#agent-configuration-file).

---

**Section 2.4: Network Security & CNI Options**

```terraform
  # You can enable encrypted wireguard for the CNI by setting this to "true". Default is "false".
  # FYI, Hetzner says "Traffic between cloud servers inside a Network is private and isolated, but not automatically encrypted."
  # Source: https://docs.hetzner.com/cloud/networks/faq/#is-traffic-inside-hetzner-cloud-networks-encrypted
  # It works with all CNIs that we support.
  # Just note, that if Cilium with cilium_values, the responsibility of enabling of disabling Wireguard falls on you.
  # enable_wireguard = true
```

* **`enable_wireguard` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** Enables WireGuard encryption for inter-node CNI (Container Network Interface) traffic. This encrypts pod-to-pod communication that traverses different nodes.
  * **Context:** Hetzner private networks provide isolation but not encryption-in-transit by default. Enabling WireGuard adds this layer of security.
  * **CNI Compatibility:** The comment states it works with supported CNIs (Flannel, Calico, Cilium).
  * **Cilium Specifics:** If you are using `cni_plugin = "cilium"` and also providing custom `cilium_values`, you become responsible for enabling/configuring WireGuard within those `cilium_values` yourself, as your custom values would likely override the module's default Cilium WireGuard setup.
  * **Performance:** WireGuard is generally efficient, but encryption always has some performance overhead.

```terraform
  # Override the flannel backend used by k3s. When set, this takes precedence over enable_wireguard.
  # Valid values: vxlan, host-gw, wireguard-native.
  # flannel_backend = "vxlan"
```

* **`flannel_backend` (String, Optional):**
  * **Default:** `null` (defaults to `vxlan`, or `wireguard-native` if `enable_wireguard = true`).
  * **Purpose:** Explicitly configures the backend for the Flannel CNI.
  * **Robot Node Context:** For clusters involving Hetzner Robot nodes connected via vSwitch, `wireguard-native` is recommended to avoid MTU issues often seen with VXLAN in that topology.

**Section 2.5: Load Balancer Configuration**

```terraform
  # * LB location and type, the latter will depend on how much load you want it to handle, see https://www.hetzner.com/cloud/load-balancer
  load_balancer_type     = "lb11"
  load_balancer_location = "nbg1"

  # Disable IPv6 for the load balancer, the default is false.
  # load_balancer_disable_ipv6 = true

  # Disables the public network of the load balancer. (default: false).
  # load_balancer_disable_public_network = true

  # Specifies the algorithm type of the load balancer. (default: round_robin).
  # load_balancer_algorithm_type = "least_connections"

  # Specifies the interval at which a health check is performed. Minimum is 3s (default: 15s).
  # load_balancer_health_check_interval = "5s"

  # Specifies the timeout of a single health check. Must not be greater than the health check interval. Minimum is 1s (default: 10s).
  # load_balancer_health_check_timeout = "3s"

  # Specifies the number of times a health check is retried before a target is marked as unhealthy. (default: 3)
  # load_balancer_health_check_retries = 3
```

* **Purpose:** This section configures the Hetzner Cloud Load Balancer that will typically sit in front of your agent nodes to distribute incoming traffic to services exposed via an Ingress controller (like Traefik, Nginx) or services of type `LoadBalancer`.
* **`load_balancer_type` (String, Obligatory):**
  * **Default (in module, if any, but usually required here):** `lb11` is shown as an example.
  * **Values:** Hetzner offers various LB types (e.g., `lb11`, `lb21`, `lb31`) with different capacities for connections, requests per second, and included traffic. Choose based on expected load. `lb11` is the smallest/cheapest.
  * **Reference:** The comment points to the Hetzner Cloud Load Balancer documentation.
* **`load_balancer_location` (String, Obligatory):**
  * **Purpose:** Specifies the Hetzner location where the Load Balancer instance will be provisioned.
  * **Best Practice:** Choose a location where you have agent nodes to minimize latency between the LB and its backend targets. It must be within the same `network_region` as your nodes.
* **`load_balancer_disable_ipv6` (Boolean, Optional):**
  * **Default:** `false` (meaning IPv6 is enabled on the LB).
  * **Purpose:** If `true`, the Load Balancer will not be assigned a public IPv6 address and will not listen for traffic on IPv6.
* **`load_balancer_disable_public_network` (Boolean, Optional):**
  * **Default:** `false` (meaning the LB has a public interface).
  * **Purpose:** If `true`, the Load Balancer will only have a private IP address and will only be accessible from within the Hetzner private network.
  * **Use Case:** For internal load balancing scenarios where you don't want to expose the LB to the public internet directly. External access would then require a VPN, bastion, or another proxy fronting this internal LB.
* **`load_balancer_algorithm_type` (String, Optional):**
  * **Default:** `"round_robin"`.
  * **Purpose:** Defines the algorithm used by the Load Balancer to distribute traffic to its backend targets (your agent nodes).
  * **Values:**
    * `"round_robin"`: Distributes connections sequentially to each target.
    * `"least_connections"`: Sends new connections to the target that currently has the fewest active connections.
* **`load_balancer_health_check_interval` (String, Optional):**
  * **Default:** `"15s"`. Minimum: `"3s"`.
  * **Purpose:** How often the Load Balancer performs health checks on its backend targets.
  * **Format:** String with a time unit suffix (e.g., `"5s"`, `"1m"`).
* **`load_balancer_health_check_timeout` (String, Optional):**
  * **Default:** `"10s"`. Minimum: `"1s"`.
  * **Purpose:** The maximum time the Load Balancer will wait for a response from a target during a health check before considering it a failure.
  * **Constraint:** Must not be greater than `load_balancer_health_check_interval`.
* **`load_balancer_health_check_retries` (Number, Optional):**
  * **Default:** `3`.
  * **Purpose:** The number of consecutive health check failures required before a target is marked as unhealthy and removed from the load balancing pool.

---

**Section 2.6: Optional Cluster Enhancements & Identifiers**

```terraform
  ### The following values are entirely optional (and can be removed from this if unused)

  # You can refine a base domain name to be use in this form of nodename.base_domain for setting the reverse dns inside Hetzner
  # base_domain = "mycluster.example.com"
```

* **`base_domain` (String, Optional):**
  * **Purpose:** If set, the module may attempt to configure reverse DNS (PTR records) for your nodes' public IP addresses using a pattern like `nodename.your_base_domain`. For example, if a node is named `agent-pool1-node1` and `base_domain` is `k8s.example.com`, its reverse DNS might be set to `agent-pool1-node1.k8s.example.com`.
  * **Requirement:** You must own/control the `base_domain` and have appropriate DNS setup for this to be meaningful and verifiable. Hetzner's ability to set PTR records might also depend on whether the IP is from a range they allow custom PTR for.
  * **Impact:** Primarily affects how your server IPs are identified in reverse DNS lookups, which can be relevant for email sending or some logging/auditing systems.

---

**Section 2.7: Cluster Autoscaler Configuration**

```terraform
  # Cluster Autoscaler
  # Providing at least one map for the array enables the cluster autoscaler feature, default is disabled.
  # ⚠️ Based on how the autoscaler works with this project, you can only choose either x86 instances or ARM server types for ALL autoscaler nodepools.
  # If you are curious, it's ok to have a multi-architecture cluster, as most underlying container images are multi-architecture too.
  #
  # ⚠️ Setting labels and taints will only work on cluster-autoscaler images versions released after > 20 October 2023. Or images built from master after that date.
  #
  # * Example below:
  # autoscaler_nodepools = [
  #  {
  #    name        = "autoscaled-small"
  #    server_type = "cx33"
  #    location    = "nbg1"
  #    min_nodes   = 0
  #    max_nodes   = 5
  #    labels      = { # Note: This is a map, not a list of strings like other labels
  #      "node.kubernetes.io/role": "peak-workloads"
  #    }
  #    taints      = [ # List of maps for taints
  #      {
  #       key= "node.kubernetes.io/role"
  #       value= "peak-workloads"
  #       effect= "NoExecute" # or NoSchedule, PreferNoSchedule
  #      }
  #    ]
  #    # kubelet_args = ["kube-reserved=cpu=250m,memory=1500Mi,ephemeral-storage=1Gi", "system-reserved=cpu=250m,memory=300Mi"]
  #    # swap_size = "2G"
  #    # zram_size = "2G"
  #  }
  # ]
  #
  # To disable public ips on your autoscaled nodes, uncomment the following lines:
  # autoscaler_disable_ipv4 = true
  # autoscaler_disable_ipv6 = true
```

* **`autoscaler_nodepools` (List of Maps, Optional):**
  * **Default:** Not set (or empty list), meaning Cluster Autoscaler is disabled.
  * **Purpose:** Enables and configures the Kubernetes Cluster Autoscaler for Hetzner Cloud. The Cluster Autoscaler automatically adjusts the number of nodes in specified nodepools based on pod scheduling demands (e.g., pending pods that cannot be scheduled due to resource shortages) or underutilization.
  * **Enabling:** Simply defining at least one map in this list will trigger the deployment of the Cluster Autoscaler components in your cluster.
  * **Architecture Constraint (⚠️):** "you can only choose either x86 instances or ARM server types for ALL autoscaler nodepools." This implies a limitation in how the module or the Hetzner cloud provider for Cluster Autoscaler handles mixed-architecture autoscaling groups. You must commit to one architecture (e.g., all `cx` series or all `cax` series) for the pools managed by the autoscaler.
  * **Labels/Taints Versioning (⚠️):** The ability to set `labels` and `taints` directly in the `autoscaler_nodepools` definition depends on using a sufficiently new version of the Cluster Autoscaler image.
  * **Nodepool Attributes (per map within `autoscaler_nodepools`):**
    * **`name` (String, Obligatory):** A unique name for this autoscaled nodepool.
    * **`server_type` (String, Obligatory):** The Hetzner server type for nodes created in this pool (e.g., `cx33`, `cax21`). Must adhere to the single-architecture constraint mentioned above.
    * **`location` (String, Obligatory):** Hetzner location for nodes in this pool.
    * **`min_nodes` (Number, Obligatory):** The minimum number of nodes this pool can scale down to. Can be `0`.
    * **`max_nodes` (Number, Obligatory):** The maximum number of nodes this pool can scale up to.
    * **`labels` (Map of Strings, Optional):**
      * Kubernetes labels to apply to nodes provisioned by the autoscaler in this pool.
      * **Format Difference:** Note that this `labels` attribute is a *map* (`key: value`), unlike the `labels` in `control_plane_nodepools` and `agent_nodepools` which are lists of strings (`["key=value"]`). This is likely due to how the Cluster Autoscaler itself expects these definitions.
    * **`taints` (List of Maps, Optional):**
      * Kubernetes taints to apply to nodes provisioned by the autoscaler in this pool.
      * **Format:** Each element in the list is a map with `key`, `value`, and `effect` (e.g., `NoSchedule`, `NoExecute`, `PreferNoSchedule`).
    * **`kubelet_args` (List of Strings, Optional):** Same purpose as in other nodepools, for passing custom arguments to kubelet on autoscaled nodes.
    * **`swap_size` (String, Optional):**
      * Examples: `"512M"`, `"2G"`, `"4G"`.
      * Configures a swap file of the specified size on autoscaled nodes.
      * **K3s/Kubernetes Consideration:** Kubernetes traditionally doesn't work well with swap. However, recent versions of k3s/kubelet can support it if the `NodeSwap` feature gate is enabled. Make sure you set `"feature-gates=NodeSwap=true"` in `k3s_global_kubelet_args` or `k3s_autoscaler_kubelet_args`.
      * When set, nodes will automatically receive the `node.kubernetes.io/server-swap=enabled` label.
    * **`zram_size` (String, Optional):**
      * Examples: `"512M"`, `"1G"`.
      * Configures zRAM (compressed RAM block device used for swap) on autoscaled nodes.
      * Uses zstd compression algorithm for optimal performance.
      * When set, nodes will automatically receive the `node.kubernetes.io/server-swap=enabled` label.
* **`autoscaler_disable_ipv4` / `autoscaler_disable_ipv6` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** If `true`, disables public IPv4/IPv6 on nodes created by the Cluster Autoscaler. Similar implications as for regular nodepools (private network only access if both are true).

```terraform
  # ⚠️ Deprecated, will be removed after a new Cluster Autoscaler version has been released which support the new way of setting labels and taints. See above.
  # Add extra labels on nodes started by the Cluster Autoscaler
  # This argument is not used if autoscaler_nodepools is not set, because the Cluster Autoscaler is installed only if autoscaler_nodepools is set
  # autoscaler_labels = [
  #   "node.kubernetes.io/role=peak-workloads"
  # ]

  # Add extra taints on nodes started by the Cluster Autoscaler
  # This argument is not used if autoscaler_nodepools is not set, because the Cluster Autoscaler is installed only if autoscaler_nodepools is set
  # autoscaler_taints = [
  #   "node.kubernetes.io/role=specific-workloads:NoExecute"
  # ]
```

* **`autoscaler_labels` / `autoscaler_taints` (List of Strings, Optional, Deprecated):**
  * **Status:** Marked as deprecated. These were older ways to apply labels/taints globally to all nodes created by the Cluster Autoscaler.
  * **Superseded by:** The per-nodepool `labels` (map) and `taints` (list of maps) within the `autoscaler_nodepools` definition offer more granular control and are the preferred method with newer Cluster Autoscaler versions.
  * **Logic:** If `autoscaler_nodepools` is not defined (i.e., autoscaler is disabled), these deprecated variables have no effect.

```terraform
  # Configuration of the Cluster Autoscaler binary
  #
  # These arguments and variables are not used if autoscaler_nodepools is not set, because the Cluster Autoscaler is installed only if autoscaler_nodepools is set.
  #
  # Image and version of Kubernetes Cluster Autoscaler for Hetzner Cloud:
  #   - cluster_autoscaler_image: Image of Kubernetes Cluster Autoscaler for Hetzner Cloud to be used.
  #       The default is the official image from the Kubernetes project: registry.k8s.io/autoscaling/cluster-autoscaler
  #   - cluster_autoscaler_version: Version of Kubernetes Cluster Autoscaler for Hetzner Cloud. Should be aligned with Kubernetes version.
  #       Available versions for the official image can be found at https://explore.ggcr.dev/?repo=registry.k8s.io%2Fautoscaling%2Fcluster-autoscaler
  #
  # Logging related arguments are managed using separate variables:
  #   - cluster_autoscaler_log_level: Controls the verbosity of logs (--v), the value is from 0 to 5, default is 4, for max debug info set it to 5.
  #   - cluster_autoscaler_log_to_stderr: Determines whether to log to stderr (--logtostderr).
  #   - cluster_autoscaler_stderr_threshold: Sets the threshold for logs that go to stderr (--stderrthreshold).
  #
  # Server/node creation timeout variable:
  #   - cluster_autoscaler_server_creation_timeout: Sets the timeout (in minutes) until which a newly created server/node has to become available before giving up and destroying it (defaults to 15, unit is minutes)
  #
  # Example:
  #
  # cluster_autoscaler_image = "registry.k8s.io/autoscaling/cluster-autoscaler"
  # cluster_autoscaler_version = "v1.30.3"
  # cluster_autoscaler_log_level = 4
  # cluster_autoscaler_log_to_stderr = true
  # cluster_autoscaler_stderr_threshold = "INFO"
  # cluster_autoscaler_server_creation_timeout = 15
```

* **Cluster Autoscaler Binary Configuration (Conditional on `autoscaler_nodepools` being set):**
  * **`cluster_autoscaler_image` (String, Optional):**
    * **Default:** `registry.k8s.io/autoscaling/cluster-autoscaler` (the official Kubernetes project image).
    * **Purpose:** Allows specifying a custom container image for the Cluster Autoscaler deployment. Useful for air-gapped environments, private registries, or custom builds.
  * **`cluster_autoscaler_version` (String, Optional):**
    * **Default:** The module likely picks a recent, compatible version.
    * **Purpose:** Specifies the version tag for the `cluster_autoscaler_image`.
    * **Recommendation:** Should generally be aligned with your Kubernetes cluster version (i.e., `install_k3s_version`). Mismatches can lead to incompatibility. The link provided helps find available official versions.
  * **`cluster_autoscaler_log_level` (Number, Optional):**
    * **Default:** `4`.
    * **Purpose:** Controls the verbosity of the Cluster Autoscaler logs (passed as the `--v` flag). Higher numbers mean more detailed logs. `5` is typically for maximum debug output.
  * **`cluster_autoscaler_log_to_stderr` (Boolean, Optional):**
    * **Default:** Likely `true`.
    * **Purpose:** Corresponds to the `--logtostderr` flag. If `true`, logs go to standard error.
  * **`cluster_autoscaler_stderr_threshold` (String, Optional):**
    * **Default:** Likely `"INFO"` or `"ERROR"`.
    * **Purpose:** Corresponds to the `--stderrthreshold` flag. Sets the minimum severity level for logs that are written to stderr (e.g., "INFO", "WARNING", "ERROR").
  * **`cluster_autoscaler_server_creation_timeout` (Number, Optional):**
    * **Default:** `15` (minutes).
    * **Purpose:** The maximum time (in minutes) the Cluster Autoscaler will wait for a newly provisioned node to become ready and join the cluster. If the timeout is exceeded, the autoscaler may assume the node provisioning failed and attempt to delete it and try again.
  * **`cluster_autoscaler_replicas` (Number, Optional):**
    * **Default:** `1`.
    * **Purpose:** Sets the replica count for the Cluster Autoscaler deployment. Increase to >1 for high availability (leader election is supported).
  * **`cluster_autoscaler_resource_limits` (Boolean, Optional):**
    * **Default:** `true`.
    * **Purpose:** Whether to apply resource requests/limits to the autoscaler pod.
  * **`cluster_autoscaler_resource_values` (Map, Optional):**
    * **Purpose:** Customizes the specific CPU and memory requests/limits for the autoscaler pod.

```terraform
  # Additional Cluster Autoscaler binary configuration
  #
  # cluster_autoscaler_extra_args can be used for additional arguments. The default is an empty array.
  #
  # Please note that following arguments are managed by terraform-hcloud-kube-hetzner or the variables above and should not be set manually:
  #   - --v=${var.cluster_autoscaler_log_level}
  #   - --logtostderr=${var.cluster_autoscaler_log_to_stderr}
  #   - --stderrthreshold=${var.cluster_autoscaler_stderr_threshold}
  #   - --cloud-provider=hetzner
  #   - --nodes ... (this defines the min/max/name for each autoscaled nodepool)
  #
  # See the Cluster Autoscaler FAQ for the full list of arguments: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-are-the-parameters-to-ca
  #
  # Example:
  #
  # cluster_autoscaler_extra_args = [
  #   "--ignore-daemonsets-utilization=true",
  #   "--enforce-node-group-min-size=true",
  # ]
```

* **`cluster_autoscaler_extra_args` (List of Strings, Optional):**
  * **Default:** `[]` (empty list).
  * **Purpose:** Allows passing arbitrary additional command-line arguments to the Cluster Autoscaler binary.
  * **Usage:** For advanced tuning or enabling features not directly exposed by other variables in this module.
  * **Managed Arguments (Do Not Set Manually):** The comment lists arguments that the module *already manages* based on other variables (like log levels, cloud provider, node group definitions). You should not try to set these via `cluster_autoscaler_extra_args` as it could conflict with the module's logic.
  * **Reference:** The Cluster Autoscaler FAQ link is the definitive source for all available CLI arguments.
  * **Example Args:**
    * `"--ignore-daemonsets-utilization=true"`: Tells the autoscaler to ignore resource requests from DaemonSet pods when calculating node utilization for scale-down decisions. Useful if DaemonSets reserve significant resources but aren't always actively using them.
    * `"--enforce-node-group-min-size=true"`: Ensures the autoscaler respects the `min_nodes` setting even if there are no pending pods, preventing it from scaling below the minimum due to other conditions.

---

**Section 2.8: Resource Protection and Backup Options**

```terraform
  # Enable delete protection on compatible resources to prevent accidental deletion from the Hetzner Cloud Console.
  # This does not protect deletion from Terraform itself.
  # enable_delete_protection = {
  #   floating_ip   = true
  #   load_balancer = true
  #   volume        = true # Applies to volumes created for Longhorn via longhorn_volume_size
  # }
```

* **`enable_delete_protection` (Map of Booleans, Optional):**
  * **Purpose:** Enables Hetzner Cloud's "delete protection" feature on specific resource types created by this module.
  * **Mechanism:** When delete protection is enabled on a resource in Hetzner Cloud, it cannot be deleted directly from the Hetzner Cloud Console (UI or hcloud CLI) until the protection is first disabled.
  * **Terraform Interaction:** This protection does *not* prevent `terraform destroy` from deleting the resources. Terraform will typically first disable the protection and then delete the resource.
  * **Scope:**
    * `floating_ip = true`: Protects Hetzner Floating IPs (e.g., for egress nodepools).
    * `load_balancer = true`: Protects the Hetzner Load Balancer.
    * `volume = true`: Protects Hetzner Volumes (e.g., those created if `longhorn_volume_size` is used in an agent nodepool).
  * **Benefit:** Adds an extra safety layer against accidental manual deletions in the Hetzner console.

```terraform
  # Enable etcd snapshot backups to S3 storage.
  # Just provide a map with the needed settings (according to your S3 storage provider) and backups to S3 will
  # be enabled (with the default settings for etcd snapshots).
  # Cloudflare's R2 offers 10GB, 10 million reads and 1 million writes per month for free.
  # For proper context, have a look at https://docs.k3s.io/datastore/backup-restore.
  # You also can use additional parameters from https://docs.k3s.io/cli/etcd-snapshot, such as `etc-s3-folder`
  # etcd_s3_backup = {
  #   etcd-s3-endpoint        = "xxxx.r2.cloudflarestorage.com"
  #   etcd-s3-access-key      = "<access-key>"
  #   etcd-s3-secret-key      = "<secret-key>"
  #   etcd-s3-bucket          = "k3s-etcd-snapshots"
  #   etcd-s3-region          = "<your-s3-bucket-region|usually required for aws>"
  #   # etcd-s3-folder        = "my-cluster-backups" # Optional: subfolder within the bucket
  #   # etcd-snapshot-schedule-cron = "0 */12 * * *" # Optional: cron for snapshot frequency, default is every 12 hours
  #   # etcd-snapshot-retention = 5 # Optional: number of snapshots to retain, default is 5
  # }
```

* **`etcd_s3_backup` (Map of Strings, Optional):**
  * **Purpose:** Configures k3s's built-in capability to automatically take snapshots of its etcd datastore (or internal SQLite database if not HA) and upload them to an S3-compatible object storage service. This is crucial for disaster recovery.
  * **Enabling:** Simply providing this map with the necessary S3 details enables the feature.
  * **k3s Feature:** Leverages k3s's `--etcd-s3-*` server arguments.
  * **Parameters (within the map):**
    * `etcd-s3-endpoint` (String, Obligatory if enabling): The S3 API endpoint URL of your storage provider (e.g., AWS S3, MinIO, Cloudflare R2).
    * `etcd-s3-access-key` (String, Obligatory if enabling): Your S3 access key ID.
    * `etcd-s3-secret-key` (String, Obligatory if enabling, Sensitive): Your S3 secret access key. **Store this securely, e.g., using Terraform Cloud variables, Vault, or environment variables if possible, rather than hardcoding.**
    * `etcd-s3-bucket` (String, Obligatory if enabling): The name of the S3 bucket where snapshots will be stored.
    * `etcd-s3-region` (String, Optional but often required): The S3 region for your bucket (e.g., `us-east-1` for AWS). Some S3 providers might not require this if the endpoint is region-specific.
    * `etcd-s3-folder` (String, Optional): A subfolder path within the bucket to store snapshots.
    * `etcd-snapshot-schedule-cron` (String, Optional): A cron expression defining how often snapshots are taken. Default in k3s is typically `0 */12 * * *` (every 12 hours at minute 0).
    * `etcd-snapshot-retention` (Number, Optional): The number of snapshots to retain in S3. Older ones are deleted. Default in k3s is typically `5`.
  * **Reference:** The k3s documentation links are essential for understanding all available etcd snapshot options.

---

**Section 2.9: Storage Integrations (CSI - Container Storage Interface)**

```terraform
  # To enable Hetzner Storage Box support, you can enable csi-driver-smb, default is "false".
  # enable_csi_driver_smb = true
  # If you want to specify the version for csi-driver-smb, set it below - otherwise it'll use the latest version available.
  # See https://github.com/kubernetes-csi/csi-driver-smb/releases for the available versions.
  # csi_driver_smb_version = "v1.16.0"
```

* **`enable_csi_driver_smb` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** If `true`, deploys the [Kubernetes CSI driver for SMB](https://github.com/kubernetes-csi/csi-driver-smb). This allows your Kubernetes cluster to provision and use PersistentVolumes (PVs) backed by SMB/CIFS shares.
  * **Hetzner Storage Box Context:** Hetzner Storage Boxes can be accessed via SMB/CIFS, making this driver relevant if you want to use Storage Box as persistent storage for your Kubernetes workloads.
  * **Mechanism:** The module will likely deploy the CSI driver components (controller, node plugins) as pods within your cluster.
* **`csi_driver_smb_version` (String, Optional):**
  * **Default:** The module likely picks the latest stable version of the driver.
  * **Purpose:** Allows you to pin the `csi-driver-smb` to a specific version. Useful for stability or if you need a particular feature/fix from a specific version. The GitHub releases link provides available versions.

```terraform
  # To enable iscid without setting enable_longhorn = true, set enable_iscsid = true. You will need this if
  # you install your own version of longhorn outside of this module.
  # Default is false. If enable_longhorn=true, this variable is ignored and iscsid is enabled anyway.
  # enable_iscsid = true
```

* **`enable_iscsid` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** Ensures that the iSCSI daemon (`iscsid` or `open-iscsi`) and related tools are installed and running on your cluster nodes.
  * **Relevance:** iSCSI is a protocol used by some storage solutions (like Longhorn, and potentially others you might install manually) to connect to block storage devices over a network.
  * **Logic:**
    * If `enable_longhorn = true` (a global module setting for Longhorn), `iscsid` is automatically enabled by the module because Longhorn requires it. This `enable_iscsid` variable is then ignored.
    * If you are *not* using the module's Longhorn integration (`enable_longhorn = false`) but plan to install Longhorn (or another iSCSI-dependent storage solution) *manually*, you would set `enable_iscsid = true` here to ensure the necessary OS-level iSCSI support is present.

```terraform
  # To use local storage on the nodes, you can enable Longhorn, default is "false".
  # See a full recap on how to configure agent nodepools for longhorn here https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/discussions/373#discussioncomment-3983159
  # Also see Longhorn best practices here https://gist.github.com/ifeulner/d311b2868f6c00e649f33a72166c2e5b
  # enable_longhorn = true
```

* **`enable_longhorn` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** If `true`, deploys [Longhorn](https://longhorn.io/), a cloud-native distributed block storage system for Kubernetes. Longhorn creates replicated PersistentVolumes using the local disk space on your agent nodes (or dedicated Hetzner Volumes if `longhorn_volume_size` is configured on agent nodepools).
  * **Benefits:** Provides resilient, replicated storage for stateful applications, snapshotting, backups, etc.
  * **Impact:** Deploys Longhorn components (manager, engine, UI) as pods in your cluster. It will also typically set up a default StorageClass for Longhorn.
  * **Dependencies:** As mentioned, enabling Longhorn implicitly enables `iscsid`.
  * **Configuration:** Can be further customized via `longhorn_replica_count`, `longhorn_fstype`, and the advanced `longhorn_values` block.

```terraform
  # By default, longhorn is pulled from https://charts.longhorn.io.
  # If you need a version of longhorn which assures compatibility with rancher you can set this variable to https://charts.rancher.io.
  # longhorn_repository = "https://charts.rancher.io"
```

* **`longhorn_repository` (String, Optional):**
  * **Default:** `"https://charts.longhorn.io"` (the official Longhorn Helm chart repository).
  * **Purpose:** Specifies the Helm chart repository URL from which to install Longhorn.
  * **Rancher Compatibility:** Rancher sometimes bundles or recommends specific versions/sources of Longhorn charts for optimal compatibility with its management platform. If using Rancher, you might need to set this to `"https://charts.rancher.io"` or another Rancher-provided URL.

```terraform
  # The namespace for longhorn deployment, default is "longhorn-system".
  # longhorn_namespace = "longhorn-system"
```

* **`longhorn_namespace` (String, Optional):**
  * **Default:** `"longhorn-system"`.
  * **Purpose:** Specifies the Kubernetes namespace into which Longhorn components will be deployed.

```terraform
  # The file system type for Longhorn, if enabled (ext4 is the default, otherwise you can choose xfs).
  # longhorn_fstype = "xfs"
```

* **`longhorn_fstype` (String, Optional):**
  * **Default:** `"ext4"`.
  * **Purpose:** When Longhorn formats the underlying storage (either local disk paths or Hetzner Volumes) for its replicas, this setting determines the filesystem type it will use.
  * **Options:** `"ext4"` or `"xfs"`. Both are robust Linux filesystems. `xfs` is sometimes preferred for large volumes or specific workloads, but `ext4` is a solid default.

```terraform
  # how many replica volumes should longhorn create (default is 3).
  # longhorn_replica_count = 1
```

* **`longhorn_replica_count` (Number, Optional):**
  * **Default:** `3`.
  * **Purpose:** Sets the default number of replicas Longhorn will create for each PersistentVolume. For a volume to be highly available, it needs replicas on different nodes.
  * **Considerations:**
    * `3` replicas: Tolerates failure of 2 nodes (or the storage on them) hosting replicas for a given volume, provided the replicas are on distinct nodes. Requires at least 3 agent nodes with Longhorn-enabled storage.
    * `1` replica: No data redundancy. If the node hosting the replica fails, the data is lost (unless restored from a backup). Suitable for development, testing, or data that can be easily regenerated. Requires at least 1 agent node.
    * **Cost/Performance:** More replicas mean more disk space used and potentially more network traffic for replication, but higher availability.

```terraform
  # When you enable Longhorn, you can go with the default settings and just modify the above two variables OR you can add a longhorn_values variable
  # with all needed helm values, see towards the end of the file in the advanced section.
  # If that file is present, the system will use it during the deploy, if not it will use the default values with the two variable above that can be customized.
  # After the cluster is deployed, you can always use HelmChartConfig definition to tweak the configuration.
```

* **Longhorn Customization Path:**
  * **Simple:** Use `enable_longhorn`, `longhorn_replica_count`, `longhorn_fstype`.
  * **Advanced:** Provide a `longhorn_values` block (discussed later) with custom Helm values to override any aspect of the Longhorn chart. If `longhorn_values` is provided, it takes precedence.
  * **Post-Deploy:** Kubernetes `HelmChartConfig` Custom Resource (if k3s supports/deploys it) can be used to modify Helm release values after the initial deployment by Terraform.

```terraform
  # Also, you can choose to use a Hetzner volume with Longhorn. By default, it will use the nodes own storage space, but if you add an attribute of
  # longhorn_volume_size (⚠️ not a variable, just a possible agent nodepool attribute) with a value between 10 and 10240 GB to your agent nodepool definition, it will create and use the volume in question.
  # See the agent nodepool section for an example of how to do that.
```

* **Reiteration of `longhorn_volume_size`:** This just re-emphasizes the agent nodepool attribute `longhorn_volume_size` for using Hetzner Volumes with Longhorn, as discussed in the `agent_nodepools` section.

```terraform
  # To disable Hetzner CSI storage, you can set the following to "true", default is "false".
  # disable_hetzner_csi = true
```

* **`disable_hetzner_csi` (Boolean, Optional):**
  * **Default:** `false` (meaning the Hetzner CSI driver *is* deployed by default).
  * **Purpose:** The [Hetzner Cloud CSI driver](https://github.com/hetznercloud/csi-driver) allows Kubernetes to dynamically provision PersistentVolumes backed by Hetzner Cloud Volumes. It's the standard way to use Hetzner's native block storage with Kubernetes.
  * **If `true`:** The module will *not* deploy the Hetzner Cloud CSI driver.
  * **Use Case for Disabling:**
    * You plan to use *only* Longhorn (or another storage solution) and don't want Hetzner Volumes managed via CSI.
    * You want to install and manage a specific version or configuration of the Hetzner CSI driver manually, outside of this module.

```terraform
  # If you want to use a specific Hetzner CCM and CSI version, set them below; otherwise, leave them as-is for the latest versions.
  # See https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases for the available versions.
  # hetzner_ccm_version = ""
```

* **`hetzner_ccm_version` (String, Optional):**
  * **Default:** The module likely picks the latest stable version.
  * **Purpose:** Allows pinning the [Hetzner Cloud Controller Manager (CCM)](https://github.com/hetznercloud/hcloud-cloud-controller-manager) to a specific version.
  * **CCM Role:** The CCM is responsible for integrating Kubernetes with Hetzner Cloud specifics, such as:
    * Setting node addresses.
    * Managing Hetzner Load Balancers for services of type `LoadBalancer`.
    * Potentially other cloud-specific integrations.
  * **Reference:** The GitHub releases link provides available versions.

```terraform
  # By default, new installations use Helm to install Hetzner CCM. You can use the legacy deployment method (using `kubectl apply`) by setting `hetzner_ccm_use_helm = false`.
  hetzner_ccm_use_helm = true
```

* **`hetzner_ccm_use_helm` (Boolean, Optional):**
  * **Default:** `true`.
  * **Purpose:** Controls the deployment method for the Hetzner CCM.
    * `true`: The module uses Helm to install and manage the CCM. This is generally the modern, preferred way.
    * `false`: The module uses a legacy method, likely applying raw Kubernetes YAML manifests (`kubectl apply -f ...`). This might be for compatibility with older module versions or specific needs.

```terraform
  # To enable Hetzner CCM compatibility and connection with dedicated Robot servers, set the `robot_ccm_enabled` to "true", default is "false".
  robot_ccm_enabled = true
```

* **`robot_ccm_enabled` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** Enables the integration of Hetzner Robot dedicated servers via the Cloud Controller Manager (CCM). This is only activated if `robot_user` and `robot_password` are also provided.
    * `true`: The HCCM is configured to allow connections to Robot Nodes.
    * `false`: The HCCM won't handle connections to Robot Nodes

```terraform
  # Hetzner Cloud vSwitch ID. If defined, a subnet will be created in the IP-range defined by vswitch_subnet_index.
  # vswitch_id = 12345

  # Subnet index (0-255) for vSwitch.
  # vswitch_subnet_index = 201
```

* **`vswitch_id` (Number, Optional):**
  * **Default:** `null`.
  * **Purpose:** Links a Hetzner vSwitch to the private network. Required for hybrid setups with Robot servers.
* **`vswitch_subnet_index` (Number, Optional):**
  * **Default:** `201`.
  * **Purpose:** Defines which subnet index (within the `subnet_amount` range) is assigned to the vSwitch connection.

```terraform
  # See https://github.com/hetznercloud/csi-driver/releases for the available versions.
  # hetzner_csi_version = ""
```

* **`hetzner_csi_version` (String, Optional):**
  * **Default:** The module likely picks the latest stable version.
  * **Purpose:** Allows pinning the Hetzner Cloud CSI driver to a specific version (if `disable_hetzner_csi` is `false`).
  * **Reference:** The GitHub releases link provides available versions.

---

Excellent! Let's continue our meticulous dissection.

---

**Section 2.10: Kured - Automated Node Reboot Management**

```terraform
  # If you want to specify the Kured version, set it below - otherwise it'll use the latest version available.
  # See https://github.com/kubereboot/kured/releases for the available versions.
  # kured_version = ""
```

* **`kured_version` (String, Optional):**
  * **Default:** The module likely deploys the latest stable version of Kured.
  * **Purpose:** Allows you to specify a particular version of [Kured (KUbernetes REboot Daemon)](https://github.com/kubereboot/kured).
  * **Kured's Role:** Kured runs as a DaemonSet in your cluster. It watches for a "sentinel" file (e.g., `/var/run/reboot-required` on Debian/Ubuntu systems) that indicates a node needs to be rebooted (typically after OS package upgrades). When detected, Kured will:
    1. Cordon the node (mark it unschedulable).
    2. Drain the node (gracefully evict pods).
    3. Execute the reboot command.
    4. After reboot, it uncordons the node (or relies on other mechanisms to confirm health).
  * **Benefit:** Automates the reboot process for OS updates, which is crucial for maintaining security and stability, especially when `automatically_upgrade_os` is enabled.
  * **Reference:** The GitHub releases link helps find specific Kured versions.

---

**Section 2.11: Ingress Controller Configuration**

```terraform
  # Default is "traefik".
  # If you want to enable the Nginx (https://kubernetes.github.io/ingress-nginx/) or HAProxy ingress controller instead of Traefik, you can set this to "nginx" or "haproxy".
  # By the default we load optimal Traefik, Nginx or HAProxy ingress controller config for Hetzner, however you may need to tweak it to your needs, so to do,
  # we allow you to add a traefik_values, nginx_values or haproxy_values, see towards the end of this file in the advanced section.
  # After the cluster is deployed, you can always use HelmChartConfig definition to tweak the configuration.
  # If you want to disable both controllers set this to "none"
  # ingress_controller = "nginx"
  # Namespace in which to deploy the ingress controllers. Defaults to the ingress_controller variable, eg (haproxy, nginx, traefik)
  # ingress_target_namespace = ""
```

* **`ingress_controller` (String, Optional):**
  * **Default:** `"traefik"`.
  * **Purpose:** Specifies which Ingress controller to deploy in the cluster. An Ingress controller is responsible for fulfilling Ingress resources, which define rules for routing external HTTP/S traffic to services within the cluster.
  * **Options:**
    * `"traefik"`: Deploys [Traefik Proxy](https://traefik.io/traefik/). Known for its ease of use and dynamic configuration.
    * `"nginx"`: Deploys the [Ingress-NGINX controller](https://kubernetes.github.io/ingress-nginx/), a popular and robust choice based on NGINX.
    * `"haproxy"`: Deploys an Ingress controller based on [HAProxy](https://www.haproxy.org/), known for high performance and reliability.
    * `"none"`: Disables the automatic deployment of any Ingress controller by this module. You would then be responsible for installing one manually if needed.
  * **Module's Role:** The module typically deploys the chosen controller using its Helm chart and applies some Hetzner-specific optimal configurations (e.g., annotations for the Hetzner Load Balancer).
  * **Customization:** Further customization is possible via `traefik_values`, `nginx_values`, or `haproxy_values` blocks (discussed later).
* **`ingress_target_namespace` (String, Optional):**
  * **Default:** The value of `ingress_controller` (e.g., if `ingress_controller = "nginx"`, the default namespace is `"nginx"`).
  * **Purpose:** Specifies the Kubernetes namespace into which the chosen Ingress controller components will be deployed.

```terraform
  # You can change the number of replicas for selected ingress controller here. The default 0 means autoselecting based on number of agent nodes (1 node = 1 replica, 2 nodes = 2 replicas, 3+ nodes = 3 replicas)
  # ingress_replica_count = 1
```

* **`ingress_replica_count` (Number, Optional):**
  * **Default:** `0`.
  * **Purpose:** Controls the number of replicas (pods) for the deployed Ingress controller.
  * **Default Logic (`0`):**
    * 1 agent node -> 1 Ingress controller replica.
    * 2 agent nodes -> 2 Ingress controller replicas.
    * 3+ agent nodes -> 3 Ingress controller replicas.
    * This provides a sensible default for HA and load distribution across agent nodes.
  * **Manual Override:** Setting a specific number (e.g., `1`, `2`, `3`) overrides this auto-selection logic.
  * **Considerations:** More replicas provide higher availability and can handle more traffic, but also consume more resources. The Ingress controller pods are typically deployed as a DaemonSet (one per node) or a Deployment with a replica count, and their service is exposed via the Hetzner Load Balancer.

```terraform
  # Use the klipperLB (similar to metalLB), instead of the default Hetzner one, that has an advantage of dropping the cost of the setup.
  # Automatically "true" in the case of single node cluster (as it does not make sense to use the Hetzner LB in that situation).
  # It can work with any ingress controller that you choose to deploy.
  # Please note that because the klipperLB points to all nodes, we automatically allow scheduling on the control plane when it is active.
  # enable_klipper_metal_lb = true
```

* **`enable_klipper_metal_lb` (Boolean, Optional):**
  * **Default:** `false` (unless it's a single-node cluster, then it's automatically `true`).
  * **Purpose:** If `true`, deploys [Klipper LoadBalancer](https://github.com/k3s-io/klipper-lb) (which is k3s's embedded service load balancer, similar in concept to MetalLB for bare-metal clusters).
  * **Mechanism:** Klipper LB allows services of type `LoadBalancer` to get an IP address from a pool of the nodes' own IP addresses. For external access, this typically means one of the node's public IPs is used by the Ingress controller's service.
  * **Advantage (Cost):** Avoids the need for a dedicated (and paid) Hetzner Cloud Load Balancer. Traffic goes directly to one of the nodes.
  * **Disadvantage:**
    * Less sophisticated load balancing than a dedicated cloud LB.
    * If the node whose IP is being used goes down, traffic to that IP stops until Kubernetes/Klipper reassigns it (if configured for HA with multiple nodes advertising).
    * HA with Klipper LB usually involves BGP or ARP announcements, which might have complexities in a cloud environment if not handled carefully by the implementation.
  * **Single-Node Cluster:** Automatically enabled because a dedicated Hetzner LB for a single node is redundant and costly.
  * **Scheduling Implication:** "we automatically allow scheduling on the control plane when it is active." If Klipper LB is used, and you have control plane nodes, they might also participate in serving traffic directly. This means the taint that usually prevents workloads on control planes might be removed or adjusted by the module.

```terraform
  # If you want to configure additional arguments for traefik, enter them here as a list and in the form of traefik CLI arguments; see https://doc.traefik.io/traefik/reference/static-configuration/cli/
  # They are the options that go into the additionalArguments section of the Traefik helm values file.
  # We already add "providers.kubernetesingress.ingressendpoint.publishedservice" by default so that Traefik works automatically with services such as External-DNS and ArgoCD.
  # Example:
  # traefik_additional_options = ["--log.level=DEBUG", "--tracing=true"]
```

* **`traefik_additional_options` (List of Strings, Optional, specific to `ingress_controller = "traefik"`):**
  * **Purpose:** Allows passing additional static configuration arguments directly to the Traefik Proxy binary. These are typically arguments you would find in Traefik's static configuration (e.g., `traefik.yml` or CLI flags).
  * **Mechanism:** These options are usually injected into the `additionalArguments` section of the Traefik Helm chart values.
  * **Default Added Option:** The module already adds `"--providers.kubernetesingress.ingressendpoint.publishedservice=true"` (or an equivalent Helm value). This is important for Traefik to correctly report its endpoint IP address in Ingress object statuses, which is then used by tools like ExternalDNS (to create DNS records) and ArgoCD (to determine application health/sync status).
  * **Example:** `["--log.level=DEBUG", "--tracing.jaeger=true", "--tracing.jaeger.samplingServerURL=http://jaeger-agent.observability:5778/sampling"]`
  * **Reference:** The Traefik static configuration CLI reference is the definitive source.

```terraform
  # By default traefik image tag is an empty string which uses latest image tag.
  # The default is "".
  # traefik_image_tag = "v3.0.0-beta5"
```

* **`traefik_image_tag` (String, Optional, specific to `ingress_controller = "traefik"`):**
  * **Default:** `""` (empty string), which usually means the Traefik Helm chart will use its default version tag (often the latest stable release).
  * **Purpose:** Allows you to pin the Traefik Proxy container image to a specific version tag (e.g., `"v2.10.5"`, `"v3.0.0"`).
  * **Benefit:** Ensures version stability and allows controlled upgrades of Traefik.

```terraform
  # By default traefik is configured to redirect http traffic to https, you can set this to "false" to disable the redirection.
  # The default is true.
  # traefik_redirect_to_https = false
```

* **`traefik_redirect_to_https` (Boolean, Optional, specific to `ingress_controller = "traefik"`):**
  * **Default:** `true`.
  * **Purpose:** Controls whether the default Traefik configuration includes a global middleware to redirect all HTTP traffic to HTTPS.
    * `true`: HTTP requests to the `web` entrypoint are redirected to the `websecure` entrypoint.
    * `false`: No automatic redirection. You would need to configure HTTPS redirection per Ingress route or handle it at the application level.

```terraform
  # Enable or disable Horizontal Pod Autoscaler for traefik.
  # The default is true.
  # traefik_autoscaling = false
```

* **`traefik_autoscaling` (Boolean, Optional, specific to `ingress_controller = "traefik"`):**
  * **Default:** `true`.
  * **Purpose:** If `true`, the module configures a Horizontal Pod Autoscaler (HPA) for the Traefik deployment. The HPA will automatically scale the number of Traefik pods up or down based on CPU utilization (or other metrics if configured in custom `traefik_values`).
  * **Benefit:** Allows Traefik to handle varying loads more efficiently.
  * **Note:** This interacts with `ingress_replica_count`. If HPA is enabled, `ingress_replica_count` might set the initial/minimum replica count for the HPA.

```terraform
  # Enable or disable pod disruption budget for traefik. Values are maxUnavailable: 33% and minAvailable: 1.
  # The default is true.
  # traefik_pod_disruption_budget = false
```

* **`traefik_pod_disruption_budget` (Boolean, Optional, specific to `ingress_controller = "traefik"`):**
  * **Default:** `true`.
  * **Purpose:** If `true`, creates a PodDisruptionBudget (PDB) for the Traefik deployment.
  * **PDB Role:** A PDB limits the number of pods of a replicated application that can be voluntarily disrupted at the same time (e.g., during node maintenance, upgrades, or when `kubectl drain` is used).
  * **Default Values:** The comment "maxUnavailable: 33% and minAvailable: 1" suggests the PDB is configured to allow at most 33% of Traefik pods to be unavailable, while ensuring at least 1 pod remains available.
  * **Benefit:** Improves the availability of Traefik during planned cluster operations.

```terraform
  # Enable or disable default resource requests and limits for traefik. Values requested are 100m & 50Mi and limits 300m & 150Mi.
  # The default is true.
  # traefik_resource_limits = false
```

* **`traefik_resource_limits` (Boolean, Optional, specific to `ingress_controller = "traefik"`):**
  * **Default:** `true`.
  * **Purpose:** If `true`, the Traefik pods are configured with default CPU and memory requests and limits.
  * **Default Values Mentioned:**
    * Requests: CPU `100m` (0.1 core), Memory `50Mi`. This is what Kubernetes guarantees the pod will have.
    * Limits: CPU `300m` (0.3 core), Memory `150Mi`. The pod cannot exceed these limits.
  * **Benefit:** Helps with resource management and scheduling. Prevents Traefik from consuming excessive resources or being starved.
  * **If `false`:** Traefik pods might run without specific requests/limits, relying on defaults or potentially being less predictable in resource consumption.

```terraform
  # If you want to configure additional ports for traefik, enter them here as a list of objects with name, port, and exposedPort properties.
  # Example:
  # traefik_additional_ports = [{name = "example", port = 1234, exposedPort = 1234}]
```

* **`traefik_additional_ports` (List of Maps, Optional, specific to `ingress_controller = "traefik"`):**
  * **Purpose:** Allows defining additional ports (entrypoints in Traefik terminology) for the Traefik service beyond the standard `web` (HTTP) and `websecure` (HTTPS) ports.
  * **Structure:** A list of maps, where each map defines a port:
    * `name` (String): A unique name for this entrypoint (e.g., "tcp-echo", "metrics").
    * `port` (Number): The port number Traefik will listen on internally for this entrypoint.
    * `exposedPort` (Number): The port number on the Traefik service (and thus on the Hetzner Load Balancer) that will map to the internal `port`. Often these are the same.
    * You might also need to specify `protocol` (e.g., `TCP`, `UDP`) if not HTTP/S, depending on how the Traefik Helm chart handles this.
  * **Use Case:** Exposing non-HTTP services (e.g., TCP or UDP applications, metrics endpoints on custom ports) through Traefik.

```terraform
  # If you want to configure additional trusted IPs for traefik, enter them here as a list of IPs (strings).
  # Example for Cloudflare:
  # traefik_additional_trusted_ips = [
  #   "173.245.48.0/20",
  #   // ... more Cloudflare IP ranges ...
  # ]
```

* **`traefik_additional_trusted_ips` (List of Strings, Optional, specific to `ingress_controller = "traefik"`):**
  * **Purpose:** Configures Traefik's `forwardedHeaders.trustedIPs` (or equivalent proxy protocol settings). When Traefik is behind another proxy (like Cloudflare, or even the Hetzner Load Balancer if it's configured to use proxy protocol), the client's real IP address is often sent in headers like `X-Forwarded-For`. Traefik needs to be told which upstream proxy IPs are "trusted" to correctly parse these headers and use the real client IP.
  * **Format:** A list of IP addresses or CIDR ranges.
  * **Cloudflare Example:** The provided list contains Cloudflare's public IP ranges. If Cloudflare is proxying traffic to your Traefik instance, adding these IPs tells Traefik to trust the `X-Forwarded-For` (and similar) headers set by Cloudflare.
  * **Hetzner LB:** If the Hetzner LB is configured with `uses-proxyprotocol = "true"`, Traefik also needs to be configured to understand proxy protocol, and the LB's private network IP range might need to be trusted. The module might handle some of this automatically.

---

**Section 2.12: Kubernetes Core Components & Features**

```terraform
  # If you want to disable the metric server set this to "false". Default is "true".
  # enable_metrics_server = false
```

* **`enable_metrics_server` (Boolean, Optional):**
  * **Default:** `true`.
  * **Purpose:** If `true`, deploys the [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server) into the cluster.
  * **Metrics Server Role:** Aggregates resource usage data (CPU, memory) from Kubelets on each node and exposes it through the Kubernetes Metrics API. This API is used by:
    * `kubectl top node` and `kubectl top pod` commands.
    * Horizontal Pod Autoscaler (HPA) to make scaling decisions based on CPU/memory utilization.
  * **If `false`:** `kubectl top` commands will not work, and HPAs relying on standard CPU/memory metrics will not function.

```terraform
  # If you want to enable the k3s built-in local-storage controller set this to "true". Default is "false".
  # Warning: When enabled together with the Hetzner CSI, there will be two default storage classes: "local-path" and "hcloud-volumes"!
  #   Even if patched to remove the "default" label, the local-path storage class will be reset as default on each reboot of
  #   the node where the controller runs.
  #   This is not a problem if you explicitly define which storageclass to use in your PVCs.
  #   Workaround if you don't want two default storage classes: leave this to false and add the local-path-provisioner helm chart
  #   as an extra (https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner#adding-extras).
  # enable_local_storage = false
```

* **`enable_local_storage` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** If `true`, enables k3s's built-in local path provisioner. This provisioner creates a StorageClass (typically named `local-path`) that can dynamically provision PersistentVolumes using local directory paths on the nodes.
  * **Use Case:** Simple single-node persistent storage without needing an external CSI driver or distributed storage system like Longhorn. Data is tied to the specific node.
  * **Warning (Multiple Default StorageClasses):**
    * If both this and the Hetzner CSI driver are enabled (which is default for Hetzner CSI), you'll have two StorageClasses marked as `default`: `local-path` and `hcloud-volumes`.
    * When a PersistentVolumeClaim (PVC) is created without specifying a `storageClassName`, Kubernetes uses the default StorageClass. Having multiple defaults can lead to ambiguity or unintended provisioning.
    * The comment notes that k3s might reset `local-path` as default on reboots, making it hard to permanently un-default it.
  * **Recommendation:**
    * If you need dynamic local storage and want to avoid the multiple-default issue, the comment suggests leaving `enable_local_storage = false` and instead deploying the `local-path-provisioner` via its Helm chart using the module's "extra manifests" feature. This gives more control over its configuration, including whether it's marked as default.
    * Alternatively, always explicitly specify `storageClassName` in your PVCs.

```terraform
  # If you want to allow non-control-plane workloads to run on the control-plane nodes, set this to "true". The default is "false".
  # True by default for single node clusters, and when enable_klipper_metal_lb is true. In those cases, the value below will be ignored.
  # allow_scheduling_on_control_plane = true
```

* **`allow_scheduling_on_control_plane` (Boolean, Optional):**
  * **Default:** `false` (for multi-node clusters without Klipper LB).
  * **Purpose:** Controls whether regular application pods can be scheduled on control plane nodes.
    * `false`: Control plane nodes typically have taints (e.g., `node-role.kubernetes.io/master:NoSchedule` or `node-role.kubernetes.io/control-plane:NoSchedule`) that prevent most pods from running on them. This reserves control plane resources for critical Kubernetes components.
    * `true`: These taints are removed or modified, allowing user workloads to run on control plane nodes.
  * **Automatic `true` Scenarios:**
    * **Single-Node Clusters:** If you have only one control plane node and no (or zero-count) agent nodepools, this is effectively `true` because the control plane *must* also run workloads.
    * **`enable_klipper_metal_lb = true`:** As mentioned earlier, if Klipper LB is used, control plane nodes might participate in serving traffic, so scheduling is often allowed on them.
  * **Manual Setting:** You might set this to `true` in resource-constrained environments or for specific small clusters where you want to utilize all nodes for workloads.

```terraform
  # If you want to disable the automatic upgrade of k3s, you can set below to "false".
  # Ideally, keep it on, to always have the latest Kubernetes version, but lock the initial_k3s_channel to a kube major version,
  # of your choice, like v1.25 or v1.26. That way you get the best of both worlds without the breaking changes risk.
  # For production use, always use an HA setup with at least 3 control-plane nodes and 2 agents, and keep this on for maximum security.

  # The default is "true" (in HA setup i.e. at least 3 control plane nodes & 2 agents, just keep it enabled since it works flawlessly).
  # automatically_upgrade_k3s = false
```

* **`automatically_upgrade_k3s` (Boolean, Optional):**
  * **Default:** `true` (especially in HA setups).
  * **Purpose:** Controls whether k3s versions are automatically upgraded on the nodes using Rancher's System Upgrade Controller.
    * `true`: The System Upgrade Controller will monitor for new k3s versions (based on `initial_k3s_channel` or `install_k3s_version` if it defines a channel) and apply them according to a plan (e.g., upgrading control planes one by one, then agents).
    * `false`: Disables automatic k3s upgrades. You would be responsible for manually upgrading k3s versions.
  * **Recommendation:**
    * **HA Setup:** Generally safe and recommended to keep `true` for security patches and new features. Pinning `initial_k3s_channel` to a specific minor version (e.g., `"v1.29"`) provides stability by only getting patch releases for that minor version.
    * **Non-HA Setup:** Can be risky if an upgrade fails on the single control plane. Often recommended to set to `false` or manage very carefully.
  * **Mechanism:** Uses the [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller), which is deployed into the cluster.

```terraform
  # By default nodes are drained before k3s upgrade, which will delete and transfer all pods to other nodes.
  # Set this to false to cordon nodes instead, which just prevents scheduling new pods on the node during upgrade
  # and keeps all pods running. This may be useful if you have pods which are known to be slow to start e.g.
  # because they have to mount volumes with many files which require to get the right security context applied.
  system_upgrade_use_drain = true
```

* **`system_upgrade_use_drain` (Boolean, Optional, relevant if `automatically_upgrade_k3s = true`):**
  * **Default:** `true`.
  * **Purpose:** Controls the behavior of the System Upgrade Controller when upgrading a node.
    * `true`: The node is cordoned and then drained (`kubectl drain`). Draining evicts all pods gracefully, allowing them to be rescheduled on other available nodes. This is the safest approach to ensure no workload interruption if pods can be moved.
    * `false`: The node is only cordoned. Existing pods continue to run on the node during the k3s upgrade process. New pods won't be scheduled there.
  * **Use Case for `false`:** If you have stateful applications or pods that are very slow to restart or have complex dependencies that make draining problematic or lengthy. However, this means those pods will experience a brief outage when the k3s service restarts on that node during the upgrade.

```terraform
  # During k3s via system-upgrade-manager pods are evicted by default.
  # On small clusters this can lead to hanging upgrades and indefinitely unschedulable nodes,
  # in that case, set this to false to immediately delete pods before upgrading.
  # NOTE: Turning this flag off might lead to downtimes of services (which may be acceptable for your use case)
  # NOTE: This flag takes effect only when system_upgrade_use_drain is set to true.
  # system_upgrade_enable_eviction = false
```

* **`system_upgrade_enable_eviction` (Boolean, Optional, relevant if `automatically_upgrade_k3s = true` and `system_upgrade_use_drain = true`):**
  * **Default:** `true` (implied, as pods are evicted during drain by default).
  * **Purpose:** Fine-tunes the pod removal process during a `drain` operation initiated by the System Upgrade Controller.
    * `true` (Default behavior of `kubectl drain`): Uses the Kubernetes eviction API. This respects PodDisruptionBudgets (PDBs). If evicting a pod would violate a PDB (e.g., not enough replicas of an application would remain), the eviction might be delayed or fail.
    * `false`: Pods are deleted more forcefully/immediately (likely `kubectl delete pod --force --grace-period=0` or similar, bypassing PDB checks).
  * **Use Case for `false`:**
    * **Small Clusters:** In very small clusters (e.g., 2 nodes), if a PDB requires, say, 2 replicas of an app to be always available, draining one node might be impossible if the app only has 2 pods. This can stall the upgrade. Setting `system_upgrade_enable_eviction = false` would force pod deletion, allowing the upgrade to proceed but causing a brief downtime for that app.
  * **Warning:** Setting to `false` can lead to temporary service outages if PDBs are not respected.

```terraform
  # The default is "true" (in HA setup it works wonderfully well, with automatic roll-back to the previous snapshot in case of an issue).
  # IMPORTANT! For non-HA clusters i.e. when the number of control-plane nodes is < 3, you have to turn it off.
  # automatically_upgrade_os = false
```

* **`automatically_upgrade_os` (Boolean, Optional):**
  * **Default:** `true` (for HA setups).
  * **Purpose:** Controls whether the underlying operating system packages on the nodes are automatically upgraded.
    * `true`: The module likely configures unattended upgrades (e.g., `unattended-upgrades` package on Debian/Ubuntu) or a similar mechanism to automatically install OS security patches and updates. Kured then handles the reboots if required.
    * `false`: Disables automatic OS upgrades. You would be responsible for manually updating the OS on each node.
  * **Critical Constraint for Non-HA:** "For non-HA clusters ... you have to turn it off." If you have a single control plane, an automatic OS upgrade that requires a reboot (and is handled by Kured) will cause downtime for the entire Kubernetes API.
  * **Rollback Mention:** The comment "automatic roll-back to the previous snapshot" likely refers to features of the underlying OS or bootloader (e.g., transactional updates with `btrfs` snapshots as used by openSUSE MicroOS, which this module uses as the base OS image). If an OS upgrade fails, the system might be able to roll back to a pre-upgrade state.

```terraform
  # If you need more control over kured and the reboot behaviour, you can pass additional options to kured.
  # For example limiting reboots to certain timeframes. For all options see: https://kured.dev/docs/configuration/
  # By default, the kured lock does not expire and is only released once a node successfully reboots. You can add the option
  # "lock-ttl" : "30m", if you have a single node which sometimes gets stuck. Note however, that in that case, kured continuous
  # draining the next node because the lock was released. You may end up with all nodes drained and your cluster completely down.
  # The default options are: `--reboot-command=/usr/bin/systemctl reboot --pre-reboot-node-labels=kured=rebooting --post-reboot-node-labels=kured=done --period=5m`
  # Defaults can be overridden by using the same key.
  # kured_options = {
  #   "reboot-days": "su", # Example: only reboot on Sunday
  #   "start-time": "3am",
  #   "end-time": "8am",
  #   "time-zone": "Local", # Or a specific IANA timezone like "Europe/Berlin"
  #   "lock-ttl" : "30m",
  # }
```

* **`kured_options` (Map of Strings, Optional):**
  * **Purpose:** Allows passing additional command-line arguments to the Kured daemon to customize its behavior.
  * **Format:** A map where keys are Kured CLI option names (without leading `--`) and values are their settings.
  * **Default Kured Options (Managed by Module):** The comment lists some default arguments the module likely passes to Kured:
    * `--reboot-command=/usr/bin/systemctl reboot`: The command Kured uses to reboot the node.
    * `--pre-reboot-node-labels=kured=rebooting`: A label Kured adds to the node *before* rebooting.
    * `--post-reboot-node-labels=kured=done`: A label Kured adds *after* a successful reboot (or that it expects to be present).
    * `--period=5m`: How often Kured checks for the reboot-required sentinel.
  * **Overriding Defaults:** You can override these by providing the same key in your `kured_options` map.
  * **Example Customizations:**
    * `"reboot-days": "su"`: Restrict reboots to only occur on Sundays.
    * `"start-time": "3am"`, `"end-time": "8am"`: Define a maintenance window for reboots.
    * `"time-zone": "Local"` or `"Europe/Berlin"`: Specify the timezone for the maintenance window.
    * `"lock-ttl": "30m"`: Sets a Time-To-Live for Kured's distributed lock. Kured uses a lock (often a ConfigMap or Lease) to ensure only one node reboots at a time. If a node gets stuck during reboot and doesn't release the lock, this TTL would eventually expire the lock, allowing Kured to proceed with another node. **Warning:** As the comment notes, if the stuck node *doesn't* actually reboot, and the lock expires, Kured might start draining another node, potentially leading to multiple nodes being down if the issue is systemic. Use with caution.
  * **Reference:** The Kured documentation is the definitive source for all its configuration options.




**Section 2.13: k3s Versioning and Naming**

```terraform
  # Allows you to specify the k3s version. If defined, supersedes initial_k3s_channel.
  # See https://github.com/k3s-io/k3s/releases for the available versions.
  # install_k3s_version = "v1.30.2+k3s2"
```

* **`install_k3s_version` (String, Optional):**
  * **Purpose:** Allows you to specify an exact k3s version to install on all nodes.
  * **Format:** Should match a k3s release tag from their GitHub releases (e.g., `"v1.30.2+k3s2"`). The `+k3sX` suffix indicates a k3s-specific build/patch of that Kubernetes version.
  * **Precedence:** If both `install_k3s_version` and `initial_k3s_channel` are set, `install_k3s_version` takes precedence for the *initial* installation.
  * **Upgrades:** If `automatically_upgrade_k3s = true`, the System Upgrade Controller will still look for newer versions within the channel defined by `initial_k3s_channel` (or the channel this specific version belongs to) unless the `install_k3s_version` itself points to a specific channel behavior (less common for exact versions).
  * **Benefit:** Guarantees a specific k3s version is installed, useful for consistency, testing, or avoiding issues with very new/unstable releases from a channel.

```terraform
  # Allows you to specify either stable, latest, testing or supported minor versions.
  # see https://rancher.com/docs/k3s/latest/en/upgrades/basic/ and https://update.k3s.io/v1-release/channels
  # ⚠️ If you are going to use Rancher addons for instance, it's always a good idea to fix the kube version to one minor version below the latest stable,
  #     e.g. v1.29 instead of the stable v1.30.
  # The default is "v1.30".
  # initial_k3s_channel = "stable"
```

* **`initial_k3s_channel` (String, Optional):**
  * **Default (in module):** `"v1.30"` (or another recent stable minor version channel).
  * **Purpose:** Specifies the k3s release channel from which to install k3s initially and, if `automatically_upgrade_k3s = true`, from which to pull subsequent upgrades.
  * **Channel Options:**
    * `"stable"`: Points to the latest stable k3s release.
    * `"latest"`: Points to the most recent k3s release, which might include release candidates or newer patches than "stable".
    * `"testing"`: For pre-release versions. Not for production.
    * Minor version channels (e.g., `"v1.30"`, `"v1.29"`): Installs the latest patch release within that specific Kubernetes minor version. This is **highly recommended for production** as it provides stability by avoiding automatic major/minor version jumps, while still allowing for security patches.
  * **Rancher Compatibility (⚠️):** Rancher often has specific Kubernetes version compatibility requirements. It's crucial to choose an `initial_k3s_channel` (or `install_k3s_version`) that is supported by the version of Rancher you intend to use (if `enable_rancher = true`). The advice to use one minor version below the absolute latest stable is good practice for broader addon compatibility.
  * **Reference:** The k3s documentation links explain channels in detail.

```terraform
  # Allows to specify the version of the System Upgrade Controller for automated upgrades of k3s
  # See https://github.com/rancher/system-upgrade-controller/releases for the available versions.
  # sys_upgrade_controller_version = "v0.14.2"
```

* **`sys_upgrade_controller_version` (String, Optional, relevant if `automatically_upgrade_k3s = true`):**
  * **Default:** The module likely picks a recent, compatible version of the System Upgrade Controller.
  * **Purpose:** Allows you to pin the version of the Rancher System Upgrade Controller that is deployed to manage k3s upgrades.
  * **Benefit:** Version pinning for stability or if you need a specific feature/fix from a particular controller version.

```terraform
  # The cluster name, by default "k3s"
  # cluster_name = ""
```

* **`cluster_name` (String, Optional):**
  * **Default (in module):** `"k3s"`.
  * **Purpose:** Sets a name for your Kubernetes cluster. This name might be used in:
    * The generated kubeconfig context name.
    * Naming of some cloud resources created by the module (e.g., prefixing firewall names, network names).
    * Internal k3s cluster identification.
  * **If `""` (empty string) is provided:** The module will use its default, likely "k3s".

```terraform
  # Whether to use the cluster name in the node name, in the form of {cluster_name}-{nodepool_name}, the default is "true".
  # use_cluster_name_in_node_name = false
```

* **`use_cluster_name_in_node_name` (Boolean, Optional):**
  * **Default:** `true`.
  * **Purpose:** Controls the naming convention for the Hetzner server instances (and thus Kubernetes node names).
    * `true`: Node names will be prefixed with the `cluster_name`, e.g., `k3s-cp-nbg1-1`, `mycluster-agent-small-1`.
    * `false`: Node names will likely just use the nodepool name and an index, e.g., `cp-nbg1-1`, `agent-small-1`.
  * **Benefit of `true`:** Helps differentiate nodes if you manage multiple clusters within the same Hetzner project.

---

**Section 2.14: Advanced k3s Configuration (Registries, Environment, Pre-install)**

```terraform
  # Extra k3s registries. This is useful if you have private registries and you want to pull images without additional secrets.
  # Or if you want to proxy registries for various reasons like rate-limiting.
  # It will create the registries.yaml file, more info here https://docs.k3s.io/installation/private-registry.
  # Note that you do not need to get this right from the first time, you can update it when you want during the life of your cluster.
  # The default is blank.
  /* k3s_registries = <<-EOT
    mirrors:
      hub.my_registry.com:
        endpoint:
          - "hub.my_registry.com"
    configs:
      hub.my_registry.com:
        auth:
          username: username
          password: password
  EOT */
```

* **`k3s_registries` (String, Optional, Heredoc or File Content):**
  * **Default:** Blank/not set.
  * **Purpose:** Allows you to configure k3s's containerd (its container runtime) with custom image registry settings. This is typically done by creating a `registries.yaml` file on each node (e.g., in `/etc/rancher/k3s/registries.yaml`).
  * **Format:** The value should be a string containing the YAML content for `registries.yaml`. The example uses a Terraform heredoc (`<<-EOT ... EOT`) for multi-line string input.
  * **Use Cases:**
    * **Private Registries:** Configure authentication (username/password, certs) for pulling images from private container registries.
    * **Registry Mirrors/Proxies:** Define mirrors for public registries (like Docker Hub) to reduce reliance on them, overcome rate limits, or use a local caching proxy.
    * **Insecure Registries:** Configure containerd to allow pulling from registries that use self-signed certificates or HTTP (not recommended for production without other security measures).
  * **Lifecycle:** "you can update it when you want during the life of your cluster." The module will likely re-apply this configuration to the nodes if changed. Containerd would then need to be restarted or reconfigured to pick up the changes.
  * **Reference:** The k3s private registry documentation is key.

```terraform
  # Additional environment variables for the host OS on which k3s runs. See for example https://docs.k3s.io/advanced#configuring-an-http-proxy .
  # additional_k3s_environment = {
  #   "CONTAINERD_HTTP_PROXY" : "http://your.proxy:port",
  #   "CONTAINERD_HTTPS_PROXY" : "http://your.proxy:port",
  #   "NO_PROXY" : "127.0.0.0/8,10.0.0.0/8,", # Note the trailing comma for NO_PROXY
  # }
```

* **`additional_k3s_environment` (Map of Strings, Optional):**
  * **Purpose:** Allows setting additional environment variables that will be available to the k3s server and agent processes when they start. This is often done by writing to `/etc/default/k3s` or `/etc/systemd/system/k3s.service.d/override.conf` (or similar for k3s-agent).
  * **Use Case (HTTP Proxy):** The primary example is configuring k3s and containerd to use an HTTP/S proxy for outbound connections (e.g., for pulling images or communicating with external services if the nodes are in a restricted network).
    * `CONTAINERD_HTTP_PROXY` / `CONTAINERD_HTTPS_PROXY`: For containerd image pulls.
    * `HTTP_PROXY` / `HTTPS_PROXY`: Might be needed for k3s itself or other components.
    * `NO_PROXY`: A comma-separated list of IP addresses, CIDRs, or domain names that should *not* go through the proxy (e.g., internal cluster IPs, local addresses, Hetzner metadata services). The trailing comma is often significant.
  * **Other Uses:** Setting any other environment variables required by k3s or its components.

```terraform
  # Additional commands to execute on the host OS before the k3s install, for example fetching and installing certs.
  # preinstall_exec = [
  #   "curl https://somewhere.over.the.rainbow/ca.crt > /root/ca.crt",
  #   "trust anchor --store /root/ca.crt", # Command for openSUSE/SLE to add CA to trust store
  # ]
```

* **`preinstall_exec` (List of Strings, Optional):**
  * **Purpose:** A list of shell commands that will be executed on each node *before* the k3s installation script is run.
  * **Mechanism:** The module likely uses Terraform provisioners (`remote-exec`) or cloud-init user data to execute these commands.
  * **Use Cases:**
    * **Installing Custom CA Certificates:** As in the example, fetching a custom CA certificate and adding it to the system's trust store. This is necessary if k3s needs to communicate with internal services that use certificates signed by this custom CA (e.g., a private image registry, an internal authentication provider). The `trust anchor` command is specific to systems using `update-ca-certificates` with a certain backend; other distros might use `update-ca-certificates` directly or other commands.
    * Installing prerequisite packages not included in the base OS image.
    * Performing other OS-level customizations needed before k3s starts.
  * **Caution:** Keep these commands idempotent (safe to run multiple times without unintended side effects) if possible, as Terraform might re-run provisioners under certain conditions.

```terraform
  # Structured authentication configuration. Multiple authentication providers support requires v1.30+ of
  # kubernetes.
  # https://kubernetes.io/docs/reference/access-authn-authz/authentication/#using-authentication-configuration
  #
  # authentication_config = <<-EOT
  #   apiVersion: apiserver.config.k8s.io/v1beta1
  #   kind: AuthenticationConfiguration
  #   jwt:
  #   - issuer:
  #       url: "https://token.actions.githubusercontent.com"
  #       audiences:
  #       - "https://github.com/octo-org"
  #     claimMappings:
  #       username:
  #         claim: sub
  #         prefix: "gh:"
  #       groups:
  #         claim: repository_owner
  #         prefix: "gh:"
  #     claimValidationRules:
  #     - claim: repository
  #       requiredValue: "octo-org/octo-repo"
  #     # ... more rules ...
  #   - issuer: # Example for a second OIDC provider
  #       url: "https://your.oidc.issuer"
  #       audiences:
  #       - "oidc_client_id"
  #     # ... claim mappings for second provider ...
  #   EOT
```

* **`authentication_config` (String, Optional, Heredoc or File Content):**
  * **Purpose:** Allows configuring the Kubernetes API server with an `AuthenticationConfiguration` object. This is a more structured and flexible way to define authentication methods, especially for multiple OIDC providers or JWT issuers, compared to older flat CLI flags.
  * **Kubernetes Feature:** This is a standard Kubernetes API server feature, generally available from v1.19+ for OIDC and enhanced for multiple JWT issuers in v1.30+. k3s passes these configurations to its embedded API server.
  * **Format:** The value should be a string containing the YAML content for the `AuthenticationConfiguration` object.
  * **Use Case (Example - GitHub Actions OIDC):** The example shows how to configure the API server to trust OIDC tokens issued by GitHub Actions. This allows GitHub Actions workflows to authenticate to the Kubernetes cluster to deploy applications, manage resources, etc., without needing long-lived static credentials.
    * `issuer`: The OIDC provider's URL and expected audiences.
    * `claimMappings`: How to map claims from the OIDC token to Kubernetes usernames and groups.
    * `claimValidationRules`: Additional rules to validate specific claims in the token (e.g., ensuring the token is from a specific GitHub repository).
  * **Multiple Providers:** The structure allows defining multiple `jwt` issuers or other authentication mechanisms.
  * **Reference:** The Kubernetes authentication documentation link is crucial.

---

**Section 2.15: k3s Server and Agent Execution Arguments**

```terraform
  # Additional flags to pass to the k3s server command (the control plane).
  # k3s_exec_server_args = "--kube-apiserver-arg enable-admission-plugins=PodTolerationRestriction,PodNodeSelector"
```

* **`k3s_exec_server_args` (String or List of Strings, Optional):**
  * **Purpose:** Allows passing additional command-line arguments directly to the `k3s server` process that runs on control plane nodes.
  * **Format:** Can be a single string with space-separated arguments, or a list of strings where each element is an argument.
  * **Example:** `--kube-apiserver-arg enable-admission-plugins=PodTolerationRestriction,PodNodeSelector`
    * `--kube-apiserver-arg`: This is a k3s-specific flag that allows you to pass arguments through to the underlying `kube-apiserver` binary that k3s embeds.
    * `enable-admission-plugins=...`: Enables specific Kubernetes admission controllers.
      * `PodTolerationRestriction`: Can restrict which tolerations pods can have based on namespace annotations.
      * `PodNodeSelector`: Can enforce or default node selectors for pods based on namespace annotations.
  * **Reference:** Consult the k3s server CLI options (`k3s server --help`) and the Kubernetes `kube-apiserver` documentation for available arguments.

```terraform
  # Additional flags to pass to the k3s agent command (every agents nodes, including autoscaler nodepools).
  # k3s_exec_agent_args = "--kubelet-arg kube-reserved=cpu=100m,memory=200Mi,ephemeral-storage=1Gi"
```

* **`k3s_exec_agent_args` (String or List of Strings, Optional):**
  * **Purpose:** Allows passing additional command-line arguments directly to the `k3s agent` process that runs on agent nodes (and nodes created by the Cluster Autoscaler).
  * **Example:** `--kubelet-arg kube-reserved=cpu=100m,memory=200Mi,ephemeral-storage=1Gi`
    * `--kubelet-arg`: A k3s-specific flag to pass arguments through to the underlying `kubelet` binary.
    * `kube-reserved=...`: Reserves specified resources for Kubernetes system components on the agent node.
  * **Reference:** Consult k3s agent CLI options (`k3s agent --help`) and Kubernetes `kubelet` documentation.

```terraform
  # The vars below here passes it to the k3s config.yaml. This way it persist across reboots
  # Make sure you set "feature-gates=NodeSwap=true" if want to use swap_size
  # Note: CloudDualStackNodeIPs was removed in K8s 1.32 (always enabled now)
  # see https://github.com/k3s-io/k3s/issues/8811#issuecomment-1856974516
  # k3s_global_kubelet_args = ["kube-reserved=cpu=100m,ephemeral-storage=1Gi", "system-reserved=cpu=memory=200Mi", "image-gc-high-threshold=50", "image-gc-low-threshold=40"]
  # k3s_control_plane_kubelet_args = []
  # k3s_agent_kubelet_args = []
  # k3s_autoscaler_kubelet_args = []
```

* **Kubelet Arguments via `config.yaml` (Persistent):**
  * **Purpose:** These variables allow configuring kubelet arguments by writing them into the k3s `config.yaml` file (e.g., `/etc/rancher/k3s/config.yaml`). Arguments set this way are persistent across k3s restarts and reboots, which is generally preferred over transient CLI args for kubelet settings.
  * **`k3s_global_kubelet_args` (List of Strings, Optional):**
    * Kubelet arguments to apply to *all* nodes (control plane, agent, autoscaled).
    * Example:
      * `"kube-reserved=cpu=100m,ephemeral-storage=1Gi"`
      * `"system-reserved=cpu=memory=200Mi"`
      * `"image-gc-high-threshold=50"`: Kubelet will start garbage collecting unused container images when disk usage for images exceeds 50%.
      * `"image-gc-low-threshold=40"`: Kubelet will stop garbage collecting images once disk usage drops below 40%.
      * `"feature-gates=NodeSwap=true"`: As per the comment, this is crucial if you intend to use the `swap_size` attribute on nodepools. `NodeSwap` enables kubelet's experimental swap support. Note: `CloudDualStackNodeIPs` was removed in K8s 1.32 (always enabled now).
  * **`k3s_control_plane_kubelet_args` (List of Strings, Optional):**
    * Kubelet arguments specific to control plane nodes. These would be merged with or override `k3s_global_kubelet_args`.
  * **`k3s_agent_kubelet_args` (List of Strings, Optional):**
    * Kubelet arguments specific to regular agent nodes (defined in `agent_nodepools`).
  * **`k3s_autoscaler_kubelet_args` (List of Strings, Optional):**
    * Kubelet arguments specific to nodes created by the Cluster Autoscaler (defined in `autoscaler_nodepools`).
  * **Nodepool-Specific `kubelet_args`:** Recall that individual nodepool definitions (e.g., within `control_plane_nodepools` or `agent_nodepools`) can also have a `kubelet_args` attribute. The order of precedence (global -> type-specific -> nodepool-specific) would need to be confirmed from the module's implementation, but typically more specific settings override general ones.
    
    
    

**Section 2.16: Firewall and Security Settings**

```terraform
  # If you want to allow all outbound traffic you can set this to "false". Default is "true".
  # restrict_outbound_traffic = false
```

* **`restrict_outbound_traffic` (Boolean, Optional):**
  * **Default:** `true`.
  * **Purpose:** Controls the default outbound traffic policy for the Hetzner Firewall associated with the cluster nodes.
    * `true`: The module configures the firewall to restrict outbound traffic. It will likely allow essential outbound traffic (e.g., for DNS, NTP, pulling images from common registries, k3s communication, Hetzner metadata) but might block other arbitrary outbound connections by default. You would then need to add `extra_firewall_rules` for any other specific outbound access your workloads require.
    * `false`: The firewall is configured to allow all outbound traffic from the nodes. This is simpler but less secure.
  * **Security Implication:** Restricting outbound traffic (`true`) is a good security practice (defense in depth) as it can limit the ability of a compromised pod/node to exfiltrate data or connect to malicious external command-and-control servers.

```terraform
  # Allow access to the Kube API from the specified networks. The default is ["0.0.0.0/0", "::/0"].
  # Allowed values: null (disable Kube API rule entirely) or a list of allowed networks with CIDR notation.
  # For maximum security, it's best to disable it completely by setting it to null. However, in that case, to get access to the kube api,
  # you would have to connect to any control plane node via SSH, as you can run kubectl from within these.
  # Please be advised that this setting has no effect on the load balancer when the use_control_plane_lb variable is set to true. This is
  # because firewall rules cannot be applied to load balancers yet.
  # firewall_kube_api_source = null
```

* **`firewall_kube_api_source` (List of Strings or `null`, Optional):**
  * **Default (in module):** `["0.0.0.0/0", "::/0"]` (Allow from anywhere on IPv4 and IPv6).
  * **Purpose:** Defines the source IP CIDR ranges allowed to access the Kubernetes API server (typically on port 6443) through the Hetzner Firewall.
  * **Values:**
    * List of CIDRs (e.g., `["YOUR_HOME_IP/32", "YOUR_OFFICE_IP_RANGE/24"]`): Only allows access from these specified IPs. **This is highly recommended for security.**
    * `null`: Disables the firewall rule for the Kube API entirely. This means the Kube API server port (6443) would *not* be opened on the Hetzner Firewall for direct public access to the control plane nodes.
  * **Accessing API if `null`:** If set to `null`, you would need alternative methods to access the API:
    * SSH into a control plane node and run `kubectl` locally from there (as it can access the API via localhost or the private network).
    * Set up a VPN into the Hetzner private network.
    * Use an SSH tunnel (`ssh -L local_port:localhost:6443 user@control_plane_ip`) and point your local `kubectl` to `https://localhost:local_port`.
  * **`use_control_plane_lb = true` Implication:** If you are using a dedicated Hetzner Load Balancer in front of your control plane nodes (`use_control_plane_lb = true`), this `firewall_kube_api_source` setting (which applies to the *nodes'* firewall) has no direct effect on the accessibility of the API *through that load balancer*. Hetzner LBs currently do not support applying firewall rules directly to themselves. Access to the LB would be open, and security would rely on Kubernetes RBAC and authentication.
  * **Security Best Practice:** Restrict this to the minimum necessary IPs or use `null` and access via SSH/VPN.

```terraform
  # Allow SSH access from the specified networks. Default: ["0.0.0.0/0", "::/0"]
  # Allowed values: null (disable SSH rule entirely) or a list of allowed networks with CIDR notation.
  # Ideally you would set your IP there. And if it changes after cluster deploy, you can always update this variable and apply again.
  # firewall_ssh_source = ["1.2.3.4/32"]
```

* **`firewall_ssh_source` (List of Strings or `null`, Optional):**
  * **Default (in module):** `["0.0.0.0/0", "::/0"]` (Allow SSH from anywhere).
  * **Purpose:** Defines the source IP CIDR ranges allowed to access the SSH port (default 22, or custom `ssh_port`) on the cluster nodes through the Hetzner Firewall.
  * **Values:**
    * List of CIDRs (e.g., `["YOUR_HOME_IP/32"]`): **Highly recommended.**
    * `null`: Disables the SSH firewall rule. This would make nodes inaccessible via public SSH unless you have another access path (e.g., Hetzner's web console, private network access from another server). Not generally recommended unless you have a very specific setup.
  * **Dynamic IP:** If your access IP changes, you can update this variable and re-run `terraform apply` to update the firewall rule.
  * **Security Best Practice:** Always restrict SSH access to known, trusted IP addresses.

```terraform
  # By default, SELinux is enabled in enforcing mode on all nodes. For container-specific SELinux issues,
  # consider using the pre-installed 'udica' tool to create custom, targeted SELinux policies instead of
  # disabling SELinux globally. See the "Fix SELinux issues with udica" example in the README for details.
  # disable_selinux = false
```

* **`disable_selinux` (Boolean, Optional):**
  * **Default:** `false` (meaning SELinux is *enabled* in enforcing mode).
  * **Background:** The base OS image used by this module (openSUSE MicroOS) comes with SELinux enabled and enforcing by default. SELinux is a security module that provides mandatory access control (MAC).
  * **Purpose:**
    * `false`: Keeps SELinux enabled. This is generally better for security but can sometimes cause issues if containers are not SELinux-aware or if their default SELinux policies are too restrictive for their needs.
    * `true`: Disables SELinux (likely sets it to permissive or fully disabled) on the nodes. This can make it easier to get problematic containers running but reduces the overall security posture.
  * **Troubleshooting SELinux Issues:**
    * The comment recommends using `udica` (a tool pre-installed on MicroOS) to generate custom, targeted SELinux policies for containers that are having permission issues, rather than disabling SELinux globally. This allows you to grant only the necessary permissions.
    * Checking audit logs (`ausearch -m avc -ts recent`) is crucial for diagnosing SELinux denials.
  * **Recommendation:** Keep SELinux enabled (`disable_selinux = false`) and learn to work with it (e.g., using `udica`, understanding context labels) for better security. Disable it only as a last resort or for temporary debugging.

```terraform
  # Adding extra firewall rules, like opening a port
  # More info on the format here https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/firewall
  # extra_firewall_rules = [
  #   {
  #     description = "For Postgres"
  #     direction       = "in"
  #     protocol        = "tcp"
  #     port            = "5432"
  #     source_ips      = ["0.0.0.0/0", "::/0"] # Be more restrictive in production!
  #     destination_ips = [] # Won't be used for "in" rules on all nodes
  #   },
  #   {
  #     description = "To Allow ArgoCD access to resources via SSH"
  #     direction       = "out"
  #     protocol        = "tcp"
  #     port            = "22"
  #     source_ips      = [] # Won't be used for "out" rules from all nodes
  #     destination_ips = ["0.0.0.0/0", "::/0"] # Allow outbound SSH to anywhere
  #   }
  # ]
```

* **`extra_firewall_rules` (List of Maps, Optional):**
  * **Purpose:** Allows you to define additional custom rules for the Hetzner Firewall that protects your cluster nodes. This is used for opening specific ports for applications running in your cluster or allowing specific outbound connections.
  * **Structure:** A list of maps, where each map defines a firewall rule. The attributes within each map correspond to the arguments of the `hcloud_firewall` resource's rule block.
  * **Rule Attributes:**
    * `description` (String, Optional): A human-readable description for the rule.
    * `direction` (String, Obligatory): `"in"` for inbound traffic to your nodes, or `"out"` for outbound traffic from your nodes.
    * `protocol` (String, Obligatory): Traffic protocol (e.g., `"tcp"`, `"udp"`, `"icmp"`).
    * `port` (String, Optional): Port number or range (e.g., `"5432"`, `"8000-8080"`). Required for TCP/UDP.
    * `source_ips` (List of Strings, Obligatory for `direction = "in"`): Source IP CIDRs allowed for inbound rules.
    * `destination_ips` (List of Strings, Obligatory for `direction = "out"`): Destination IP CIDRs allowed for outbound rules.
  * **Example 1 (Inbound Postgres):** Opens TCP port 5432 from any source. **Warning:** `["0.0.0.0/0", "::/0"]` for `source_ips` is insecure for production databases; restrict it to known IPs.
  * **Example 2 (Outbound SSH for ArgoCD):** Allows nodes to make outbound SSH connections (TCP port 22) to any destination. This might be needed if ArgoCD (or another tool) needs to clone Git repositories via SSH from within the cluster.
  * **Reference:** The Hetzner provider documentation for the `hcloud_firewall` resource is the definitive guide for rule syntax.

---

**Section 2.17: CNI (Container Network Interface) Plugin Configuration**

```terraform
  # If you want to configure a different CNI for k3s, use this flag
  # possible values: flannel (Default), calico, and cilium
  # As for Cilium, we allow infinite configurations via helm values, please check the CNI section of the readme over at https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/#cni.
  # Also, see the cilium_values at towards the end of this file, in the advanced section.
  # ⚠️ Depending on your setup, sometimes you need your control-planes to have more than
  # 2GB of RAM if you are going to use Cilium, otherwise the pods will not start.
  # cni_plugin = "cilium"
```

* **`cni_plugin` (String, Optional):**
  * **Default (in k3s, if not overridden by module):** Flannel (via VXLAN). The module might also default to Flannel.
  * **Purpose:** Specifies the CNI plugin to be installed and used by k3s for pod networking. The CNI plugin is responsible for allocating IP addresses to pods, connecting them to the network, and enforcing network policies (if supported).
  * **Options Provided by Module:**
    * `"flannel"`: A simple and widely used CNI plugin. Good for basic pod networking. k3s bundles it.
    * `"calico"`: A popular CNI known for its robust network policy enforcement and scalability. Can operate in IP-in-IP, VXLAN, or BGP modes (BGP mode is more for on-prem/bare-metal).
    * `"cilium"`: A powerful CNI based on eBPF. Offers advanced networking features (e.g., efficient load balancing, fine-grained network policies, Hubble observability, service mesh capabilities, transparent encryption, egress gateway).
  * **k3s Integration:** k3s can be started with CNI disabled (`--flannel-backend=none` or similar flags) allowing an external CNI like Calico or Cilium to be installed. This module handles that process.
  * **Cilium RAM Warning (⚠️):** Cilium, especially with all features enabled, can be more resource-intensive than Flannel. The comment warns that control plane nodes might need more than 2GB of RAM (e.g., `cx23` might be tight, consider `cx33`/`cx43` or higher) for Cilium pods to run reliably.
  * **Cilium Customization:** The module allows extensive Cilium configuration via the `cilium_values` block (discussed later).

```terraform
  # You can choose the version of Cilium that you want. By default we keep the version up to date and configure Cilium with compatible settings according to the version.
  # See https://github.com/cilium/cilium/releases for the available versions.
  # cilium_version = "v1.14.0"
```

* **`cilium_version` (String, Optional, relevant if `cni_plugin = "cilium"`):**
  * **Default:** The module likely picks a recent, stable version of Cilium.
  * **Purpose:** Allows pinning the Cilium installation to a specific version.
  * **Benefit:** Version stability, access to specific features/fixes.
  * **Compatibility:** The module's default Cilium configurations (if `cilium_values` is not used) are likely tailored to be compatible with the Cilium version it defaults to or the one you specify. Major changes in Cilium versions can alter Helm chart values or feature availability.

```terraform
  # Set native-routing mode ("native") or tunneling mode ("tunnel"). Default: tunnel
  # cilium_routing_mode = "native"
```

* **`cilium_routing_mode` (String, Optional, relevant if `cni_plugin = "cilium"`):**
  * **Default (in module, if not overridden by `cilium_values`):** `"tunnel"` (likely VXLAN or Geneve).
  * **Purpose:** Configures Cilium's routing mode for inter-node pod traffic.
    * `"tunnel"`: Pod traffic between nodes is encapsulated in an overlay tunnel (e.g., VXLAN). This is often simpler to set up as it doesn't require direct L2/L3 reachability for pod IPs between nodes beyond the tunnel endpoints.
    * `"native"` (Direct Routing): Pod IPs are directly routable on the underlying network. This requires the Hetzner private network (and its subnets for each node) to be configured to route traffic destined for pod CIDRs to the correct nodes. This can offer better performance by avoiding encapsulation overhead.
  * **Hetzner Context for Native Routing:** For native routing to work with Hetzner Cloud, the module (or Cilium itself, if configured appropriately) needs to manage routes within the Hetzner private network to ensure that traffic for a pod on Node B, originating from Node A, is correctly routed by Hetzner's network infrastructure to Node B. This often involves Cilium interacting with the cloud provider's routing tables or using features like Hetzner's "Routes" on their private networks.

```terraform
  # Used when Cilium is configured in native routing mode. The CNI assumes that the underlying network stack will forward packets to this destination without the need to apply SNAT. Default: value of "cluster_ipv4_cidr"
  # cilium_ipv4_native_routing_cidr = "10.0.0.0/8"
```

* **`cilium_ipv4_native_routing_cidr` (String, Optional, relevant if `cni_plugin = "cilium"` and `cilium_routing_mode = "native"`):**
  * **Default (in module):** The value of `cluster_ipv4_cidr` (e.g., `"10.42.0.0/16"`).
  * **Purpose:** In Cilium's native routing mode, this tells Cilium which broader IP range encompasses all possible pod IPs across the cluster. Cilium uses this to understand which traffic should be routed directly versus potentially needing SNAT (Source Network Address Translation) for outbound traffic to destinations outside this CIDR.
  * **Typical Setting:** Often set to the overall network CIDR (e.g., `network_ipv4_cidr` like `"10.0.0.0/8"`) if all pod traffic within that larger network should be natively routed. If set to just `cluster_ipv4_cidr`, it implies only traffic within the pod CIDR itself is considered "native" by this specific Cilium setting. The exact behavior depends on Cilium's internal logic for this parameter.

```terraform
  # Enables egress gateway to redirect and SNAT the traffic that leaves the cluster. Default: false
  # cilium_egress_gateway_enabled = true
```

* **`cilium_egress_gateway_enabled` (Boolean, Optional, relevant if `cni_plugin = "cilium"`):**
  * **Default:** `false`.
  * **Purpose:** If `true`, enables Cilium's Egress Gateway feature.
  * **Egress Gateway Role:** Allows you to route outbound traffic from specific pods (or all cluster outbound traffic) through a dedicated set of "egress" nodes. These egress nodes then SNAT the traffic, so all outbound connections appear to originate from the IP address(es) of these egress nodes.
  * **Use Case:**
    * Providing a stable, predictable source IP for outbound traffic for whitelisting with external services.
    * Applying common network policies or monitoring to all egress traffic.
  * **Integration:** Often used with the "egress" `agent_nodepool` example shown earlier, which had `floating_ip = true`. The floating IP(s) on the egress nodes become the source IP(s) for the SNAT'd traffic.

```terraform
  # Enables Hubble Observability to collect and visualize network traffic. Default: false
  # cilium_hubble_enabled = true
```

* **`cilium_hubble_enabled` (Boolean, Optional, relevant if `cni_plugin = "cilium"`):**
  * **Default:** `false`.
  * **Purpose:** If `true`, deploys [Hubble](https://cilium.io/blog/2019/11/19/announcing-hubble/), Cilium's network observability platform.
  * **Hubble Features:**
    * Provides deep visibility into network traffic flows between pods, services, and external entities.
    * Offers a UI (Hubble UI) and CLI for exploring traffic, service dependencies, and network policy effects.
    * Can export flow logs and metrics.
  * **Impact:** Deploys Hubble components (e.g., Hubble Relay, Hubble UI pods) into the cluster.

```terraform
  # Configures the list of Hubble metrics to collect.
  # cilium_hubble_metrics_enabled = [
  #   "policy:sourceContext=app|workload-name|pod|reserved-identity;destinationContext=app|workload-name|pod|dns|reserved-identity;labelsContext=source_namespace,destination_namespace"
  # ]
```

* **`cilium_hubble_metrics_enabled` (List of Strings, Optional, relevant if `cilium_hubble_enabled = true`):**
  * **Purpose:** Specifies which types of metrics Hubble should collect and expose (typically for Prometheus consumption).
  * **Format:** A list of strings, where each string defines a metric configuration. The example shows a complex metric definition for policy-related traffic, broken down by various source/destination contexts (app, workload, pod, identity) and labeled by namespaces.
  * **Reference:** Consult the Hubble documentation for available metric types and configuration syntax.

```terraform
  # Set the Cilium LoadBalancer & NodePort XDP Acceleration. Default: "best-effort".
  # The setting "native" enforces XDP Acceleration on ports and "disabled" disables the acceleration, "best-effort" enables the XDP Acceleration if the interface supports it.
  # See [Cilium XDP documentation](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#loadbalancer-nodeport-xdp-acceleration).
  # For Robot nodes connected over vSwitch, the XDP acceleration may not work on the Robot node and the setting therefore recommended to be set to "best-effort" or "disabled".
  # cilium_loadbalancer_acceleration_mode = "best-effort"
```

* **`cilium_loadbalancer_acceleration_mode` (String, Optional, relevant if `cni_plugin = "cilium"`):**
  * **Default:** `"best-effort"`.
  * **Purpose:** Specifies the Loadbalancer Acceleration mode for Cilium (loadBalancer.acceleration). 

```terraform
  # You can choose the version of Calico that you want. By default, the latest is used.
  # More info on available versions can be found at https://github.com/projectcalico/calico/releases
  # Please note that if you are getting 403s from Github, it's also useful to set the version manually. However there is rarely a need for that!
  # calico_version = "v3.27.2"
```

* **`calico_version` (String, Optional, relevant if `cni_plugin = "calico"`):**
  * **Default:** The module likely picks the latest stable version of Calico.
  * **Purpose:** Allows pinning the Calico installation to a specific version.
  * **GitHub 403s Note:** Sometimes, automated scripts fetching "latest" release information from GitHub can hit rate limits or encounter temporary issues. Pinning to a specific version can bypass such problems.

```terraform
  # If you want to disable the k3s kube-proxy, use this flag. The default is "false".
  # Ensure that your CNI is capable of handling all the functionalities typically covered by kube-proxy.
  # disable_kube_proxy = true
```

* **`disable_kube_proxy` (Boolean, Optional):**
  * **Default:** `false` (k3s's embedded kube-proxy is enabled).
  * **Purpose:**
    * `false`: k3s runs its own kube-proxy component (usually a stripped-down version based on iptables or ipvs) on each node. Kube-proxy is responsible for implementing Kubernetes Services (ClusterIP, NodePort, LoadBalancer) by managing network rules (iptables, ipvs) on the nodes.
    * `true`: Disables k3s's internal kube-proxy.
  * **Requirement if `true`:** If you disable k3s's kube-proxy, your chosen CNI plugin *must* be capable of providing this service routing functionality itself.
    * **Cilium:** Can replace kube-proxy entirely using eBPF for service handling (often more efficient). This is a common reason to set `disable_kube_proxy = true` when using Cilium.
    * **Calico:** Can also work without kube-proxy in some configurations, but this needs careful setup.
    * **Flannel:** Typically relies on kube-proxy for service implementation.
  * **Benefit of Disabling (with capable CNI):** Can lead to better performance, simpler network path, and reduced overhead by having a single component (the CNI) manage all aspects of pod and service networking.

```terraform
  # If you want to disable the k3s default network policy controller, use this flag!
  # Both Calico and Cilium cni_plugin values override this value to true automatically, the default is "false".
  # disable_network_policy = true
```

* **`disable_network_policy` (Boolean, Optional):**
  * **Default:** `false` (k3s's default network policy controller is enabled if no other CNI provides it).
  * **Purpose:**
    * `false`: If the chosen CNI (like Flannel) doesn't have its own network policy enforcement, k3s might enable a basic network policy controller.
    * `true`: Disables k3s's own network policy controller.
  * **Automatic Override:** "Both Calico and Cilium cni_plugin values override this value to true automatically." This is because Calico and Cilium provide their own, more advanced network policy engines. When they are selected as the `cni_plugin`, the module ensures k3s's default (and potentially conflicting or redundant) network policy controller is disabled.

Locked and loaded! Let's continue the detailed exploration.

---

**Section 2.18: Miscellaneous Operational Settings**

```terraform
  # If you want to disable the automatic use of placement group "spread". See https://docs.hetzner.com/cloud/placement-groups/overview/
  # We advise to not touch that setting, unless you have a specific purpose.
  # The default is "false", meaning it's enabled by default.
  # placement_group_disable = true
```

* **`placement_group_disable` (Boolean, Optional):**
  * **Default:** `false` (meaning Hetzner Placement Groups with a "spread" strategy are *enabled* and used by the module by default).
  * **Purpose:** Controls whether the module attempts to use Hetzner Placement Groups for your cluster nodes.
    * `false`: The module will likely create one or more placement groups (with "spread" strategy, meaning servers in the group are on different physical hosts) and assign your nodes to them. This improves resilience against single physical host failures.
    * `true`: Disables the module's automatic use of placement groups. Servers will be provisioned without explicit placement group assignment, relying on Hetzner's default allocation.
  * **Recommendation:** "We advise to not touch that setting, unless you have a specific purpose." Using placement groups is generally a good practice for HA. You might disable it if you are hitting Hetzner limits on placement groups per project, or for very specific testing scenarios.
  * **Interaction with Nodepool `placement_group`:** If a nodepool definition has its own `placement_group = "group_name"` attribute, that would likely take precedence for that specific nodepool, allowing for more granular control even if global placement groups are enabled.

```terraform
  # By default, we allow ICMP ping in to the nodes, to check for liveness for instance. If you do not want to allow that, you can. Just set this flag to true (false by default).
  # block_icmp_ping_in = true
```

* **`block_icmp_ping_in` (Boolean, Optional):**
  * **Default:** `false` (meaning ICMP ping requests *are allowed* to the nodes by the Hetzner Firewall).
  * **Purpose:** Controls whether the Hetzner Firewall rule for ICMP (specifically echo-request, "ping") is configured to allow or block incoming pings to your cluster nodes.
    * `false`: Nodes will respond to pings. Useful for basic liveness checks and network troubleshooting.
    * `true`: Nodes will not respond to pings from external sources (blocked at the Hetzner Firewall level).
  * **Security Consideration:** Blocking ICMP can make it slightly harder for attackers to discover live hosts (though there are other methods). However, it also hinders legitimate network diagnostics. The security benefit is often considered minor compared to the operational inconvenience.

```terraform
  # You can enable cert-manager (installed by Helm behind the scenes) with the following flag, the default is "true".
  # enable_cert_manager = false
```

* **`enable_cert_manager` (Boolean, Optional):**
  * **Default:** `true`.
  * **Purpose:** If `true`, deploys [cert-manager](https://cert-manager.io/) into your Kubernetes cluster.
  * **cert-manager Role:** A powerful tool for automating the management and issuance of TLS certificates within Kubernetes. It can:
    * Issue certificates from various sources like Let's Encrypt (for publicly trusted certs), Venafi, or self-signed CAs.
    * Automatically renew certificates before they expire.
    * Store certificates as Kubernetes Secrets, ready to be used by Ingress controllers, web applications, etc.
  * **Mechanism:** The module installs cert-manager using its Helm chart.
  * **If `false`:** cert-manager is not deployed. You would need to manage TLS certificates manually or use a different solution.
  * **Interaction with Rancher:** If `enable_rancher = true`, Rancher often deploys its own instance or version of cert-manager, or has specific requirements. The module might handle this interaction (e.g., not deploying a separate cert-manager if Rancher is enabled and provides it).

```terraform
  # IP Addresses to use for the DNS Servers, the defaults are the ones provided by Hetzner https://docs.hetzner.com/dns-console/dns/general/recursive-name-servers/.
  # The number of different DNS servers is limited to 3 by Kubernetes itself.
  # It's always a good idea to have at least 1 IPv4 and 1 IPv6 DNS server for robustness.
  dns_servers = [
    "1.1.1.1", # Cloudflare Public DNS (IPv4)
    "8.8.8.8", # Google Public DNS (IPv4)
    "2606:4700:4700::1111", # Cloudflare Public DNS (IPv6)
  ]
```

* **`dns_servers` (List of Strings, Optional):**
  * **Default (in module):** Likely Hetzner's own recursive DNS servers (e.g., `185.12.64.1`, `185.12.64.2`, and their IPv6 equivalents).
  * **Purpose:** Specifies the upstream DNS servers that the nodes (and thus CoreDNS/kube-dns running in the cluster) will use for resolving external domain names. This configures the `/etc/resolv.conf` on the host nodes.
  * **Example Values:** The example shows public DNS servers from Cloudflare and Google.
  * **Kubernetes Limit:** "The number of different DNS servers is limited to 3 by Kubernetes itself" (actually, by the underlying Linux `resolv.conf` behavior, which typically only uses the first few).
  * **Recommendation:** Using a mix of reliable IPv4 and IPv6 DNS servers from different providers can improve DNS resolution robustness. Hetzner's own DNS servers are also a good choice as they are geographically close.

---

**Section 2.19: Control Plane Accessibility and Kubeconfig Options**

```terraform
  # When this is enabled, rather than the first node, all external traffic will be routed via a control-plane loadbalancer, allowing for high availability.
  # The default is false.
  # use_control_plane_lb = true
```

* **`use_control_plane_lb` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** Controls how the Kubernetes API server is exposed for external access, especially in an HA control plane setup.
    * `false` (Default): The kubeconfig generated by the module might point to the IP address of the *first* control plane node, or if `kubeconfig_server_address` is set, to that address. If that first node goes down (in an HA setup), you'd need to manually update your kubeconfig to point to another live control plane node.
    * `true`: The module provisions an additional Hetzner Cloud Load Balancer specifically for the control plane nodes (on port 6443). The generated kubeconfig will then point to the IP address of this control plane LB.
  * **Benefit of `true`:** Provides a single, highly available endpoint for the Kubernetes API server. If one control plane node fails, the LB will route traffic to the remaining healthy ones.
  * **Cost Implication:** Enabling this incurs the cost of an additional Hetzner Load Balancer.
  * **Firewall Note:** As mentioned under `firewall_kube_api_source`, Hetzner LBs don't currently support firewall rules directly. Access to the control plane LB's public IP would be open, relying on Kubernetes authentication/RBAC.

```terraform
  # When the above use_control_plane_lb is enabled, you can change the lb type for it, the default is "lb11".
  # control_plane_lb_type = "lb21"
```

* **`control_plane_lb_type` (String, Optional, relevant if `use_control_plane_lb = true`):**
  * **Default:** `"lb11"`.
  * **Purpose:** Allows you to specify the Hetzner Load Balancer type for the dedicated control plane load balancer.
  * **Consideration:** The API server traffic is usually not as high volume as application traffic, so `lb11` is often sufficient. Choose a larger type if you anticipate extremely high API load or have specific requirements.

```terraform
  # When the above use_control_plane_lb is enabled, you can change to disable the public interface for control plane load balancer, the default is true.
  # control_plane_lb_enable_public_interface = false
```

* **`control_plane_lb_enable_public_interface` (Boolean, Optional, relevant if `use_control_plane_lb = true`):**
  * **Default:** `true` (meaning the control plane LB has a public IP).
  * **Purpose:**
    * `true`: The control plane LB gets a public IP, making the Kube API accessible from the internet (subject to Kubernetes authN/authZ).
    * `false`: The control plane LB only gets a private IP within the Hetzner network. The Kube API would only be accessible from within that private network (e.g., via VPN, bastion, or other servers in the same network).
  * **Use Case for `false`:** Enhanced security by not exposing the Kube API directly to the public internet, even via an LB.
  * **Integration with NAT Router:** When both `control_plane_lb_enable_public_interface = false` and `nat_router` are configured, the NAT router automatically forwards port 6443 to the control plane LB's private IP. This allows external kubectl access via the NAT router's public IP while keeping the control plane LB private. The generated kubeconfig will automatically use the NAT router's public IP as the server address.

```terraform
  # Let's say you are not using the control plane LB solution above, and still want to have one hostname point to all your control-plane nodes.
  # You could create multiple A records of to let's say cp.cluster.my.org pointing to all of your control-plane nodes ips.
  # In which case, you need to define that hostname in the k3s TLS-SANs config to allow connection through it. It can be hostnames or IP addresses.
  # additional_tls_sans = ["cp.cluster.my.org"]
```

* **`additional_tls_sans` (List of Strings, Optional):**
  * **Purpose:** Allows you to add extra Subject Alternative Names (SANs) to the TLS certificate generated by k3s for its API server.
  * **Use Case (DNS Round Robin for API):** If you are *not* using `use_control_plane_lb = true` but want a single hostname for your API server (e.g., `cp.cluster.my.org`), you might create multiple A/AAAA DNS records for this hostname, each pointing to the public IP of one of your control plane nodes (DNS Round Robin).
    * For clients to connect to `https://cp.cluster.my.org:6443` without TLS certificate errors, this hostname *must* be listed as a SAN in the API server's certificate.
  * **Format:** A list of hostnames or IP addresses.
  * **Impact:** k3s will include these in its self-signed certificate for the API, or if integrating with an external CA, these SANs would be requested.

```terraform
  # If you create a hostname with multiple A records pointing to all of your
  # control-plane nodes ips, you may want to use that hostname in the generated
  # kubeconfig.
  # kubeconfig_server_address = "cp.cluster.my.org"
```

* **`kubeconfig_server_address` (String, Optional):**
  * **Purpose:** Allows you to explicitly set the server address (hostname or IP) that will be written into the `server:` field of the generated kubeconfig file.
  * **Default Behavior:** Without this, the kubeconfig will automatically point to:
    * The public IP of the control plane LB (if `use_control_plane_lb = true` and `control_plane_lb_enable_public_interface = true`).
    * The public IP of the NAT router (if `use_control_plane_lb = true`, `control_plane_lb_enable_public_interface = false`, and `nat_router` is configured).
    * The private IP of the control plane LB (if `use_control_plane_lb = true`, `control_plane_lb_enable_public_interface = false`, and no `nat_router`).
    * The IP of the first control plane node (if no CP LB).
  * **Use Case:** If you've set up DNS Round Robin for your control plane nodes (as described for `additional_tls_sans`) and want your kubeconfig to use that hostname (e.g., `cp.cluster.my.org`) instead of a direct IP, or if you have a custom ingress setup.
  * **Requirement:** If you use a hostname here, ensure it resolves correctly and is included in the API server's TLS certificate SANs (via `additional_tls_sans` or default k3s behavior).

```terraform
  # Optional external control plane endpoint URL (e.g. https://myapi.domain.com:6443).
  # Used as the k3s 'server' value for agents and secondary control planes.
  # control_plane_endpoint = "https://myapi.domain.com:6443"
```

* **`control_plane_endpoint` (String, Optional):**
  * **Default:** `null`.
  * **Purpose:** Specifies a custom external URL for the Kubernetes API server.
  * **Use Case:** When using an external load balancer (not managed by this module) or a specific DNS alias for your control plane, set this to ensure agents register correctly against that endpoint.

```terraform
  # K3S audit-policy.yaml contents. Used to configure Kubernetes audit logging.
  # k3s_audit_policy_config = <<-EOT
  #   apiVersion: audit.k8s.io/v1
  #   kind: Policy
  #   rules:
  #   - level: Metadata
  # EOT
  # k3s_audit_log_path = "/var/log/k3s-audit/audit.log"
  # k3s_audit_log_maxage = 30
  # k3s_audit_log_maxbackup = 10
  # k3s_audit_log_maxsize = 100
```

* **`k3s_audit_policy_config` (String, Optional):**
  * **Purpose:** Defines the Kubernetes Audit Policy. If provided, k3s is configured to log audit events matching these rules.
  * **Format:** YAML string content for the policy file.
* **`k3s_audit_log_*` variables:**
  * **Purpose:** Configure the rotation and retention of audit logs on control plane nodes.
  * `k3s_audit_log_path`: Path to audit log file (default: `/var/log/k3s-audit/audit.log`)
  * `k3s_audit_log_maxage`: Days to retain logs (default: `30`)
  * `k3s_audit_log_maxbackup`: Number of backup files to keep (default: `10`)
  * `k3s_audit_log_maxsize`: Max size in MB before rotation (default: `100`)

```terraform
  # lb_hostname Configuration:
  #
  # Purpose:
  # The lb_hostname setting optimizes communication between services within the Kubernetes cluster
  # when they use domain names instead of direct service names. By associating a domain name directly
  # with the Hetzner Load Balancer, this setting can help reduce potential communication delays.
  #
  # Scenario:
  # If Service B communicates with Service A using a domain (e.g., `a.mycluster.domain.com`) that points
  # to an external Load Balancer, there can be a slowdown in communication.
  #
  # Guidance:
  # - If your internal services use domain names pointing to an external LB, set lb_hostname to a domain
  #   like `mycluster.domain.com`.
  # - Create an A record pointing `mycluster.domain.com` to your LB's IP.
  # - Create a CNAME record for `a.mycluster.domain.com` (or xyz.com) pointing to `mycluster.domain.com`.
  #
  # Technical Note:
  # This setting sets the `load-balancer.hetzner.cloud/hostname` in the Hetzner LB definition, suitable for
  # HAProxy, Nginx and Traefik ingress controllers.
  #
  # Recommendation:
  # This setting is optional. If services communicate using direct service names, you can leave this unset.
  # For inter-namespace communication, use `.service_name` as per Kubernetes norms.
  #
  # Example:
  # lb_hostname = "mycluster.domain.com"
```

* **`lb_hostname` (String, Optional):**
  * **Purpose:** Sets the `load-balancer.hetzner.cloud/hostname` annotation on the Service object for your main Ingress controller (Traefik, Nginx, HAProxy).
  * **Hetzner CCM Behavior:** When the Hetzner Cloud Controller Manager (CCM) sees this annotation on a Service of type `LoadBalancer`, it attempts to associate the specified hostname with the provisioned Hetzner Load Balancer. This might involve creating/updating DNS records if you use Hetzner DNS, or it might just be informational for the LB itself.
  * **Scenario Explained:** The comment describes a scenario where internal cluster services communicate via external domain names that resolve to the main Hetzner LB. If Service B calls `a.mycluster.domain.com`, and this resolves to the LB IP, the traffic goes out to the LB and then back into the cluster to Service A. This can be inefficient ("hairpinning" or "NAT loopback" issues if not handled well).
  * **Optimization Goal:** By setting `lb_hostname`, the CCM might optimize this path, or it might simply ensure that if you CNAME your application hostnames (like `a.mycluster.domain.com`) to this `lb_hostname` (which itself points to the LB IP), the LB is aware of the primary domain it serves. The exact optimization depends on Hetzner CCM's capabilities.
  * **DNS Setup:** You are still responsible for:
    1. Creating an A/AAAA record for `lb_hostname` (e.g., `mycluster.domain.com`) pointing to the Hetzner Load Balancer's public IP.
    2. Creating CNAME records for your individual application services (e.g., `a.mycluster.domain.com` CNAME to `mycluster.domain.com`).
  * **Recommendation:** Optional. If your services primarily use internal Kubernetes service discovery (e.g., `service-a.namespace.svc.cluster.local`), this might not be necessary.

---

**Section 2.20: Rancher Integration**

```terraform
  # You can enable Rancher (installed by Helm behind the scenes) with the following flag, the default is "false".
  # ⚠️ Rancher often doesn't support the latest Kubernetes version. You will need to set initial_k3s_channel to a supported version.
  # When Rancher is enabled, it automatically installs cert-manager too, and it uses rancher's own self-signed certificates.
  # See for options https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster#3-choose-your-ssl-configuration
  # The easiest thing is to leave everything as is (using the default rancher self-signed certificate) and put Cloudflare in front of it.
  # As for the number of replicas, by default it is set to the number of control plane nodes.
  # You can customized all of the above by adding a rancher_values variable see at the end of this file in the advanced section.
  # After the cluster is deployed, you can always use HelmChartConfig definition to tweak the configuration.
  # IMPORTANT: Rancher's install is quite memory intensive, you will require at least 4GB if RAM, meaning cx23 server type (for your control plane).
  # ALSO, in order for Rancher to successfully deploy, you have to set the "rancher_hostname".
  # enable_rancher = true
```

* **`enable_rancher` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** If `true`, deploys [Rancher Manager](https://rancher.com/), a popular open-source platform for managing multiple Kubernetes clusters.
  * **Mechanism:** The module installs Rancher using its Helm chart.
  * **Key Considerations & Warnings:**
    * **Kubernetes Version Compatibility (⚠️):** Rancher has strict Kubernetes version compatibility. You *must* set `initial_k3s_channel` or `install_k3s_version` to a version supported by the Rancher version being installed. This often means using a slightly older, well-tested Kubernetes minor version.
    * **Cert-Manager:** Rancher typically bundles or requires its own instance of cert-manager. It often uses its own self-signed CA by default for its UI. The comment suggests that if `enable_rancher` is true, the module's `enable_cert_manager` might be implicitly handled or overridden.
    * **SSL Configuration:** Rancher offers options for SSL: Rancher-generated self-signed certs (default), Let's Encrypt, or bringing your own certs. The comment suggests the default self-signed cert is easiest if you put a proxy like Cloudflare (with its own valid cert) in front of Rancher.
    * **Replicas:** Rancher deployment replicas default to the number of control plane nodes for HA.
    * **Customization:** Advanced customization via `rancher_values` block (later).
    * **Resource Requirements (IMPORTANT):** Rancher is resource-intensive. Control plane nodes need significant RAM (at least 4GB, e.g., Hetzner `cx23`/`cx33` or higher). Insufficient resources will lead to installation failures or instability.
    * **`rancher_hostname` (REQUIRED):** You *must* set `rancher_hostname` if `enable_rancher = true`.

```terraform
  # If using Rancher you can set the Rancher hostname, it must be unique hostname even if you do not use it.
  # If not pointing the DNS, you can just port-forward locally via kubectl to get access to the dashboard.
  # If you already set the lb_hostname above and are using a Hetzner LB, you do not need to set this one, as it will be used by default.
  # But if you set this one explicitly, it will have preference over the lb_hostname in rancher settings.
  # rancher_hostname = "rancher.xyz.dev"
```

* **`rancher_hostname` (String, Conditional Obligatory if `enable_rancher = true`):**
  * **Purpose:** Sets the hostname that Rancher will be configured to use for its UI and API. This hostname is embedded in Rancher's configuration and its TLS certificates.
  * **Requirement:** Must be set if `enable_rancher = true`.
  * **DNS:** You need to create a DNS A/AAAA record for this hostname pointing to the IP address where Rancher is accessible (e.g., the Hetzner Load Balancer IP, or a node IP if using Klipper LB).
  * **Local Access (No DNS):** If you don't set up public DNS, you can still access the Rancher UI by port-forwarding the Rancher service locally using `kubectl port-forward svc/rancher -n cattle-system <local_port>:443` and then accessing `https://localhost:<local_port>` (after adding the hostname to your local `/etc/hosts` file pointing to `127.0.0.1`).
  * **Interaction with `lb_hostname`:**
    * If `lb_hostname` is set and `rancher_hostname` is *not*, Rancher will default to using `lb_hostname`.
    * If `rancher_hostname` is explicitly set, it takes precedence for Rancher's configuration, even if `lb_hostname` is also set.

```terraform
  # When Rancher is deployed, by default is uses the "latest" channel. But this can be customized.
  # The allowed values are "stable" or "latest".
  # rancher_install_channel = "stable"
```

* **`rancher_install_channel` (String, Optional, relevant if `enable_rancher = true`):**
  * **Default (in Rancher Helm chart):** Often `"latest"`.
  * **Purpose:** Specifies the Rancher release channel to use when installing Rancher via its Helm chart.
    * `"latest"`: Installs the most recent Rancher version, which might include newer features but could be less tested.
    * `"stable"`: Installs the version of Rancher marked as stable, generally recommended for production.
  * **Note:** This refers to the Rancher *application* version channel, distinct from the `initial_k3s_channel` for the Kubernetes version.

```terraform
  # Finally, you can specify a bootstrap-password for your rancher instance. Minimum 48 characters long!
  # If you leave empty, one will be generated for you.
  # (Can be used by another rancher2 provider to continue setup of rancher outside this module.)
  # rancher_bootstrap_password = ""
```

* **`rancher_bootstrap_password` (String, Optional, Sensitive, relevant if `enable_rancher = true`):**
  * **Purpose:** Sets the initial bootstrap password for the default `admin` user in Rancher.
  * **Default:** If left empty or not provided, Rancher (or the module) will generate a random password. This password can usually be retrieved from a Kubernetes secret or logs after installation.
  * **Minimum Length:** The comment "Minimum 48 characters long!" indicates a strong recommendation or requirement from Rancher or the module for security.
  * **Automation Use:** "Can be used by another rancher2 provider..." If you're automating further Rancher configuration using the `rancher2` Terraform provider, knowing or setting this bootstrap password allows that provider to authenticate to the newly installed Rancher instance.
  * **Security:** If setting this, treat it as highly sensitive.

```terraform
  # Separate from the above Rancher config (only use one or the other). You can import this cluster directly on an
  # an already active Rancher install. By clicking "import cluster" choosing "generic", giving it a name and pasting
  # the cluster registration url below. However, you can also ignore that and apply the url via kubectl as instructed
  # by Rancher in the wizard, and that would register your cluster too.
  # More information about the registration can be found here https://rancher.com/docs/rancher/v2.6/en/cluster-provisioning/registered-clusters/
  # rancher_registration_manifest_url = "https://rancher.xyz.dev/v3/import/xxxxxxxxxxxxxxxxxxYYYYYYYYYYYYYYYYYYYzzzzzzzzzzzzzzzzzzzzz.yaml"
```

* **`rancher_registration_manifest_url` (String, Optional):**
  * **Purpose:** Used to register this newly created k3s cluster with an *existing, separate* Rancher Manager instance. This is an alternative to `enable_rancher = true` (which installs Rancher *within* this cluster).
  * **Mechanism:**
    1. In your existing Rancher UI, you would go to "Import Cluster," choose "Generic," and Rancher will provide a registration command, often including a URL to a YAML manifest.
    2. You paste that manifest URL here.
    3. The module will then apply this manifest to your k3s cluster. The manifest typically deploys Rancher cluster agents, which connect back to your existing Rancher Manager and register the cluster.
  * **Alternative:** As the comment notes, you can also just run the `kubectl apply -f <url>` command manually after the cluster is up.



---

**Section 2.21: Kustomize and Post-Deployment Operations**

```terraform
  # Extra commands to be executed after the `kubectl apply -k` (useful for post-install actions, e.g. wait for CRD, apply additional manifests, etc.).
  # extra_kustomize_deployment_commands=""
```

* **`extra_kustomize_deployment_commands` (String or List of Strings, Optional):**
  * **Purpose:** Allows you to specify shell commands that will be executed *after* the module has run its main Kustomize deployment (which applies manifests for core components like CCM, CSI, Ingress, etc., based on your selections).
  * **Mechanism:** The module likely uses a `local-exec` or `remote-exec` provisioner (if commands need to run on a node) to execute these. If they are `kubectl` commands, they'd run from where Terraform is executed, using the generated kubeconfig.
  * **Use Cases:**
    * **Waiting for CRDs:** Some applications deployed via Helm or Kustomize install CustomResourceDefinitions (CRDs) first, and then CustomResources (CRs) that depend on those CRDs. There can be a race condition if the CRs are applied before the CRDs are fully registered. You could add a command here to wait for CRDs to become available (e.g., `kubectl wait --for condition=established crd/mycrd.example.com --timeout=120s`).
    * Applying additional Kubernetes manifests that depend on the core setup.
    * Running post-install scripts or triggering initial application setup jobs.
  * **Format:** Can be a single string with commands separated by `&&` or `\n`, or a list of individual command strings.

```terraform
  # Extra values that will be passed to the `extra-manifests/kustomization.yaml.tpl` if its present.
  # extra_kustomize_parameters={}
```

* **`extra_kustomize_parameters` (Map of Strings, Optional):**
  * **Purpose:** If you are using the module's "extra manifests" feature (where you can provide your own Kustomize setup in an `extra-manifests` directory), this map allows you to pass key-value parameters into a `kustomization.yaml.tpl` template file within that directory.
  * **Mechanism:** The module would process `extra-manifests/kustomization.yaml.tpl` as a template, substituting placeholders with values from this map, and then run `kustomize build` on the result.
  * **Use Case:** Parameterizing your custom Kustomize deployments based on Terraform inputs or computed values from the `kube-hetzner` module (e.g., passing in the cluster name, node IPs, etc., to your custom manifests).
  * **Reference:** The comment points to examples in the module's repository for how to use this feature.

```terraform
  # See working examples for extra manifests or a HelmChart in examples/kustomization_user_deploy/README.md
```

* **Documentation Pointer:** This directs users to example usage of the "extra manifests" feature, which is crucial for extending the module's capabilities with custom deployments.

---

**Section 2.22: Kubeconfig and Output Management**

```terraform
  # It is best practice to turn this off, but for backwards compatibility it is set to "true" by default.
  # See https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/issues/349
  # When "false". The kubeconfig file can instead be created by executing: "terraform output --raw kubeconfig > cluster_kubeconfig.yaml"
  # Always be careful to not commit this file!
  # create_kubeconfig = false
```

* **`create_kubeconfig` (Boolean, Optional):**
  * **Default (in module, historically):** `true`. The comment suggests this might be changing or that `false` is now best practice.
  * **Purpose:**
    * `true`: The module, after setting up the cluster, will attempt to write the generated kubeconfig content to a local file (e.g., `cluster_kubeconfig.yaml` in the current directory).
    * `false`: The module does *not* write the kubeconfig to a file. You *must* retrieve it using `terraform output --raw kubeconfig > cluster_kubeconfig.yaml`.
  * **Best Practice (`false`):**
    * Avoids accidentally committing the sensitive kubeconfig file to version control if it's automatically created in the project directory.
    * Makes the user more deliberate about handling the kubeconfig.
  * **Issue #349:** Refers to a discussion likely about the security implications and best practices around kubeconfig generation.

```terraform
  # Don't create the kustomize backup. This can be helpful for automation.
  # create_kustomization = false
```

* **`create_kustomization` (Boolean, Optional):**
  * **Default:** `true` (implied, as backups are usually made).
  * **Purpose:** The module internally uses Kustomize to generate and apply many of its Kubernetes manifests. It might create a backup of the generated Kustomize directory or files.
    * `true`: Creates this backup.
    * `false`: Skips creating the Kustomize backup.
  * **Use Case for `false`:** In CI/CD or fully automated environments, these backup files might be unnecessary clutter or could interfere with cleanup processes.

```terraform
  # Export the values.yaml files used for the deployment of traefik, longhorn, cert-manager, etc.
  # This can be helpful to use them for later deployments like with ArgoCD.
  # The default is false.
  # export_values = true
```

* **`export_values` (Boolean, Optional):**
  * **Default:** `false`.
  * **Purpose:** If `true`, the module will output or save the effective `values.yaml` files that were used for deploying Helm charts like Traefik, Longhorn, cert-manager, etc.
  * **Benefit:**
    * **Debugging:** Allows you to see exactly what configuration was passed to each Helm chart.
    * **GitOps/ArgoCD:** You can take these exported values files and commit them to a Git repository to manage these applications via ArgoCD or a similar GitOps tool, ensuring consistency between the Terraform-managed deployment and subsequent GitOps management. This facilitates a transition or co-existence strategy.

---

**Section 2.23: Base OS Image Configuration**

```terraform
  # MicroOS snapshot IDs to be used. Per default empty, the most recent image created using createkh will be used.
  # We recommend the default, but if you want to use specific IDs you can.
  # You can fetch the ids with the hcloud cli by running the "hcloud image list --selector 'microos-snapshot=yes'" command.
  # microos_x86_snapshot_id = "1234567"
  # microos_arm_snapshot_id = "1234567"
```

* **Background:** This module uses openSUSE MicroOS as the base operating system for the cluster nodes. MicroOS is a transactional, immutable-style OS designed for container workloads. The `createkh` tool (mentioned in the comment, part of the `kube-hetzner` project) is likely used to prepare and snapshot customized MicroOS images suitable for this module.
* **`microos_x86_snapshot_id` (String, Optional):**
  * **Default:** Empty string (module uses the most recent `createkh`-generated x86 snapshot).
  * **Purpose:** Allows you to specify the exact Hetzner snapshot ID for the openSUSE MicroOS image to be used for x86-based nodes (e.g., `cx` series).
* **`microos_arm_snapshot_id` (String, Optional):**
  * **Default:** Empty string (module uses the most recent `createkh`-generated ARM snapshot).
  * **Purpose:** Allows you to specify the exact Hetzner snapshot ID for the openSUSE MicroOS image to be used for ARM-based nodes (e.g., `cax` series).
* **Recommendation:** "We recommend the default". Using the default ensures you get the latest tested and prepared image from the module maintainers.
* **Use Case for Pinning:**
  * Ensuring absolute reproducibility if you need to rebuild a cluster exactly as it was.
  * If a new default snapshot introduces an issue, you can temporarily pin to a known good older snapshot ID.
* **Fetching IDs:** The `hcloud image list --selector 'microos-snapshot=yes'` command helps you find available snapshot IDs created by `createkh` in your Hetzner project.

---

**Section 2.24: ADVANCED - Custom Helm Values Overrides**

This section introduces the mechanism for providing detailed, custom Helm chart values for various components deployed by the module. The general pattern is:

* A variable named `component_values` (e.g., `cilium_values`, `traefik_values`).
* The value can be a multi-line heredoc string containing YAML, or loaded from a file using `file("component-values.yaml")`.
* These values will be merged with or override the module's default Helm values for that component.
* **Warning:** "We advise you to use the default values, and only change them if you know what you are doing!" Incorrect Helm values can easily break a component's deployment. Always refer to the official Helm chart documentation for the component in question.

```terraform
  ### ADVANCED - Custom helm values for packages above (search _values if you want to located where those are mentioned upper in this file)
  # ⚠️ Inside the _values variable below are examples, up to you to find out the best helm values possible, we do not provide support for customized helm values.
  # Please understand that the indentation is very important, inside the EOTs, as those are proper yaml helm values.
  # We advise you to use the default values, and only change them if you know what you are doing!

  # You can inline the values here in heredoc-style (as the examples below with the <<-EOT to EOT). Please note that the indentation inside the EOT is important.
  # Or you can create a thepackage-values.yaml file with the content and use it here with the following syntax:
  # thepackage_values = file("thepackage-values.yaml")

  # Cilium, all Cilium helm values can be found at https://github.com/cilium/cilium/blob/master/install/kubernetes/cilium/values.yaml
  # Be careful when maintaining your own cilium_values, as the choice of available settings depends on the Cilium version used. See also the cilium_version setting to fix a specific version.
  # The following is an example, please note that the current indentation inside the EOT is important.
  /*   cilium_values = <<-EOT
ipam:
  mode: kubernetes # Use Kubernetes host-scope IPAM
k8s:
  requireIPv4PodCIDR: true # Ensure pod CIDRs are available
kubeProxyReplacement: true # Cilium replaces kube-proxy
routingMode: native # Use native routing (direct routing)
ipv4NativeRoutingCIDR: "10.0.0.0/8" # Broader CIDR for native routing
endpointRoutes:
  enabled: true # Manage routes for local endpoints
loadBalancer:
  acceleration: native # Use eBPF for LB acceleration
bpf:
  masquerade: true # Enable eBPF-based masquerading (SNAT)
encryption:
  enabled: true # Enable transparent encryption
  type: wireguard # Use WireGuard for encryption
MTU: 1450 # Set MTU, important for tunnels/encapsulation
  EOT */
```

* **`cilium_values` (String, Optional, Heredoc/File Content):**
  * Provides custom Helm values for the Cilium deployment if `cni_plugin = "cilium"`.
  * The example shows various advanced Cilium settings:
    * `ipam.mode: kubernetes`: Cilium uses Kubernetes for IP address management.
    * `kubeProxyReplacement: true`: Cilium fully replaces kube-proxy functionality.
    * `routingMode: native`: Enables direct routing.
    * `encryption.enabled: true`, `encryption.type: wireguard`: Enables WireGuard encryption (overriding the simpler `enable_wireguard` flag if both are used, as `cilium_values` takes precedence for Cilium).
    * `MTU`: Setting the Maximum Transmission Unit is critical when using tunneling or encryption to avoid fragmentation.

```terraform
  # Cert manager, all cert-manager helm values can be found at https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml
  # The following is an example, please note that the current indentation inside the EOT is important.
  # For cert-manager versions < v1.15.0, you need to set installCRDs: true instead of crds.enabled and crds.keep.
  /*   cert_manager_values = <<-EOT
crds:
  enabled: true # Helm chart should manage CRDs (newer cert-manager versions)
  keep: true    # Do not delete CRDs when Helm chart is uninstalled
replicaCount: 3 # Number of replicas for the main cert-manager controller
webhook:
  replicaCount: 3 # Replicas for the webhook component
cainjector:
  replicaCount: 3 # Replicas for the CA injector component
  EOT */
```

* **`cert_manager_values` (String, Optional, Heredoc/File Content):**
  * Provides custom Helm values for the cert-manager deployment if `enable_cert_manager = true` (and not overridden by Rancher).
  * Example shows:
    * `crds.enabled: true`, `crds.keep: true`: Modern way to manage CRD installation with Helm. The comment about `installCRDs: true` for older versions is important.
    * Setting `replicaCount` for various cert-manager components for HA.

```terraform
  # csi-driver-smb, all csi-driver-smb helm values can be found at https://github.com/kubernetes-csi/csi-driver-smb/blob/master/charts/latest/csi-driver-smb/values.yaml
  # The following is an example, please note that the current indentation inside the EOT is important.
  /*   csi_driver_smb_values = <<-EOT
controller:
  name: csi-smb-controller
  replicas: 1
  runOnMaster: false # Do not run controller on master nodes (old terminology)
  runOnControlPlane: false # Prefer not to run controller on control plane nodes
  resources: # Resource requests/limits for controller components
    csiProvisioner:
      limits:
        memory: 300Mi
      requests:
        cpu: 10m
        memory: 20Mi
    # ... similar for livenessProbe and smb sidecar ...
  EOT */
```

* **`csi_driver_smb_values` (String, Optional, Heredoc/File Content):**
  * Provides custom Helm values for the CSI SMB driver if `enable_csi_driver_smb = true`.
  * Example shows configuring replica counts, node affinity (`runOnControlPlane`), and resource requests/limits for the driver's controller pod and its sidecars.

```terraform
  # Longhorn, all Longhorn helm values can be found at https://github.com/longhorn/longhorn/blob/master/chart/values.yaml
  # The following is an example, please note that the current indentation inside the EOT is important.
  /*   longhorn_values = <<-EOT
defaultSettings:
  defaultDataPath: /var/longhorn # Path on nodes where Longhorn stores data
persistence:
  defaultFsType: ext4 # Filesystem for Longhorn volumes
  defaultClassReplicaCount: 3 # Default replica count for new volumes
  defaultClass: true # Make Longhorn's StorageClass the default
  EOT */
```

* **`longhorn_values` (String, Optional, Heredoc/File Content):**
  * Provides custom Helm values for the Longhorn deployment if `enable_longhorn = true`.
  * Example shows setting default data path, filesystem type, replica count, and whether Longhorn's StorageClass should be the cluster-wide default.

```terraform
  # If you want to use a specific Traefik helm chart version, set it below; otherwise, leave them as-is for the latest versions.
  # See https://github.com/traefik/traefik-helm-chart/releases for the available versions.
  # traefik_version = ""
```

* **`traefik_version` (String, Optional, specific to `ingress_controller = "traefik"`):**
  * **Purpose:** Allows pinning the Traefik *Helm chart version* itself, distinct from `traefik_image_tag` which pins the container image version. Helm chart versions can change structure, available values, etc., independently of the application image version.

```terraform
  # Traefik, all Traefik helm values can be found at https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml
  # The following is an example, please note that the current indentation inside the EOT is important.
  /*   traefik_values = <<-EOT
deployment:
  replicas: 1 # Override default replica count logic
additionalArguments: [] # Can add global static config args here too
service:
  enabled: true
  type: LoadBalancer # Ensure service is of type LoadBalancer
  annotations: # Annotations for the Hetzner Load Balancer
    "load-balancer.hetzner.cloud/name": "k3s" # Name for the LB in Hetzner console
    "load-balancer.hetzner.cloud/use-private-ip": "true" # LB uses private IP to connect to nodes
    "load-balancer.hetzner.cloud/disable-private-ingress": "true" # Disallow private network access to LB itself? (Check Hetzner docs for exact meaning)
    "load-balancer.hetzner.cloud/location": "nbg1" # Override LB location
    "load-balancer.hetzner.cloud/type": "lb11" # Override LB type
    "load-balancer.hetzner.cloud/uses-proxyprotocol": "true" # Enable PROXY protocol from LB to Traefik

ports: # Configure Traefik entrypoints
  web:
    http:
      redirections: # Redirect HTTP (web) to HTTPS (websecure)
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

    proxyProtocol: # Configure PROXY protocol for web entrypoint
      trustedIPs:
        - 127.0.0.1/32 # Trust localhost
        - 10.0.0.0/8   # Trust private network IPs (e.g., from Hetzner LB)
    forwardedHeaders: # Configure trusted IPs for X-Forwarded-* headers
      trustedIPs:
        - 127.0.0.1/32
        - 10.0.0.0/8
  websecure: # Similar PROXY protocol and forwardedHeaders for HTTPS entrypoint
    proxyProtocol:
      trustedIPs:
        # ...
    forwardedHeaders:
      trustedIPs:
        # ...
  EOT */
```

* **`traefik_values` (String, Optional, Heredoc/File Content):**
  * Provides custom Helm values for Traefik if `ingress_controller = "traefik"`.
  * The example is rich:
    * Setting replica count.
    * Crucially, setting Hetzner Load Balancer annotations directly on the Traefik service. This allows fine-grained control over the LB created by the Hetzner CCM for Traefik (name, location, type, private IP usage, PROXY protocol). This might override or supplement the global `load_balancer_*` settings if they apply to the Ingress LB.
    * Configuring HTTP to HTTPS redirection.
    * Configuring PROXY protocol and trusted IPs for `X-Forwarded-*` headers, essential when Traefik is behind the Hetzner LB (especially if PROXY protocol is enabled on the LB).

```terraform
  # If you want to use a specific Nginx helm chart version, set it below; otherwise, leave them as-is for the latest versions.
  # See https://github.com/kubernetes/ingress-nginx?tab=readme-ov-file#supported-versions-table for the available versions.
  # nginx_version = ""
```

* **`nginx_version` (String, Optional, specific to `ingress_controller = "nginx"`):**
  * Pins the Ingress-NGINX *Helm chart version*.

```terraform
  # Nginx, all Nginx helm values can be found at https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml
  # You can also have a look at https://kubernetes.github.io/ingress-nginx/, to understand how it works, and all the options at your disposal.
  # The following is an example, please note that the current indentation inside the EOT is important.
  /*   nginx_values = <<-EOT
controller:
  watchIngressWithoutClass: "true" # Watch Ingresses without an ingressClassName
  kind: "DaemonSet" # Deploy controller as a DaemonSet (one pod per node)
  config: # Pass custom Nginx config options
    "use-forwarded-headers": "true" # Trust X-Forwarded-* headers
    "compute-full-forwarded-for": "true" # Ensure X-Forwarded-For is accurate
    "use-proxy-protocol": "true" # Enable PROXY protocol listener
  service:
    annotations: # Annotations for the Hetzner LB for Nginx service
      "load-balancer.hetzner.cloud/name": "k3s"
      # ... other Hetzner LB annotations similar to Traefik example ...
      "load-balancer.hetzner.cloud/uses-proxyprotocol": "true"
  EOT */
```

* **`nginx_values` (String, Optional, Heredoc/File Content):**
  * Provides custom Helm values for Ingress-NGINX if `ingress_controller = "nginx"`.
  * Example shows:
    * `watchIngressWithoutClass`: Useful if you have Ingress objects without `ingressClassName` specified.
    * `kind: "DaemonSet"`: Deploys Nginx controller pods on every (agent) node. Alternative is `Deployment`.
    * `config`: A map for passing Nginx-specific configurations (like `use-forwarded-headers`, `use-proxy-protocol`).
    * `service.annotations`: Similar to Traefik, for configuring the Hetzner LB for the Nginx service.

```terraform
  # If you want to use a specific HAProxy helm chart version, set it below; otherwise, leave them as-is for the latest versions.
  # haproxy_version = ""
```

* **`haproxy_version` (String, Optional, specific to `ingress_controller = "haproxy"`):**
  * Pins the HAProxy Ingress *Helm chart version*.

```terraform
  # If you want to configure additional proxy protocol trusted IPs for haproxy, enter them here as a list of IPs (strings).
  # Example for Cloudflare:
  # haproxy_additional_proxy_protocol_ips = [
  #   "173.245.48.0/20",
  #   // ... more Cloudflare IP ranges ...
  # ]
```

* **`haproxy_additional_proxy_protocol_ips` (List of Strings, Optional, specific to `ingress_controller = "haproxy"`):**
  * **Purpose:** Similar to `traefik_additional_trusted_ips`, this configures trusted source IPs for PROXY protocol when using HAProxy Ingress. If HAProxy receives PROXY protocol headers from these IPs, it will trust the client IP information within.
  * **Use Case:** When HAProxy is behind another proxy (like Cloudflare or the Hetzner LB using PROXY protocol).

```terraform
  # Configure CPU and memory requests for each HAProxy pod
  # haproxy_requests_cpu = "250m"
  # haproxy_requests_memory = "400Mi"
```

* **`haproxy_requests_cpu` / `haproxy_requests_memory` (String, Optional, specific to `ingress_controller = "haproxy"`):**
  * **Purpose:** Sets default CPU and memory *requests* for HAProxy Ingress controller pods.
  * **Note:** These are just requests. Limits might be set separately via `haproxy_values` if needed.

```terraform
  # Override values given to the HAProxy helm chart.
  # All HAProxy helm values can be found at https://github.com/haproxytech/helm-charts/blob/main/kubernetes-ingress/values.yaml
  # Default values can be found at https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner/blob/master/locals.tf
  /*   haproxy_values = <<-EOT
  EOT */
```

* **`haproxy_values` (String, Optional, Heredoc/File Content):**
  * Provides custom Helm values for HAProxy Ingress if `ingress_controller = "haproxy"`.
  * The example is empty, but you would populate it with HAProxy Ingress Helm chart values. The links point to the official chart values and potentially the module's own default values for HAProxy.

```terraform
  # Rancher, all Rancher helm values can be found at https://rancher.com/docs/rancher/v2.5/en/installation/install-rancher-on-k8s/chart-options/
  # The following is an example, please note that the current indentation inside the EOT is important.
  /*   rancher_values = <<-EOT
ingress:
  tls:
    source: "rancher" # Use Rancher's self-signed certs for Ingress
hostname: "rancher.example.com" # Must match rancher_hostname
replicas: 1 # Override default replica count
bootstrapPassword: "supermario" # Set bootstrap password (sensitive!)
  EOT */
```

* **`rancher_values` (String, Optional, Heredoc/File Content):**
  * Provides custom Helm values for the Rancher Manager deployment if `enable_rancher = true`.
  * Example shows:
    * `ingress.tls.source: "rancher"`: Tells Rancher's Ingress to use certificates managed by Rancher itself (often self-signed initially).
    * `hostname`: Must match the `rancher_hostname` variable.
    * `replicas`: Overrides the default replica count for Rancher pods.
    * `bootstrapPassword`: Sets the initial admin password (same as `rancher_bootstrap_password` variable, but this would be the Helm way to set it).
  * **Reference:** The Rancher chart options documentation is key.

```terraform
} # End of module "kube-hetzner"
```

---

**Section 3: Provider and Terraform Block**

```terraform
provider "hcloud" {
  token = var.hcloud_token != "" ? var.hcloud_token : local.hcloud_token
}

terraform {
  required_version = ">= 1.10.1"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.51.0"
    }
  }
}
```

* **`provider "hcloud"` Block:**
  * **Purpose:** Configures the Hetzner Cloud provider for Terraform. This is what allows Terraform to interact with the Hetzner API.
  * **`token`:** The Hetzner API token. The logic `var.hcloud_token != "" ? var.hcloud_token : local.hcloud_token` is the same as used for the module input: it prioritizes the `TF_VAR_hcloud_token` environment variable, falling back to the `local.hcloud_token` if the environment variable is not set. This provider block is what the `kube-hetzner` module instance inherits when we pass `hcloud = hcloud` in its `providers` map.
* **`terraform` Block:**
  * **`required_version`:** Specifies the minimum Terraform CLI version required to apply this configuration.
  * **`required_providers`:** Declares the providers needed by this root module and their source/version constraints.
    * `hcloud`: Specifies the official Hetzner Cloud provider from `hetznercloud/hcloud` on the Terraform Registry.
    * `version = ">= 1.51.0"`: Constrains to use version 1.51.0 or newer of the Hetzner provider. It's good practice to use a lower bound and periodically update to newer provider versions for new features and bug fixes.

---

**Section 4: Outputs**

```terraform
output "kubeconfig" {
  value     = module.kube-hetzner.kubeconfig
  sensitive = true
}

# (The original file only had kubeconfig output, but I added more common/useful ones in the "How-To" version)
# output "cluster_name" { value = module.kube-hetzner.cluster_name }
# output "control_plane_ips" { value = module.kube-hetzner.control_plane_ips }
# output "agent_node_ips" { value = module.kube-hetzner.agent_node_ips }
# output "load_balancer_ip" { value = module.kube-hetzner.load_balancer_ipv4 }
```

* **`output "kubeconfig"` Block:**
  * **Purpose:** Defines an output variable named `kubeconfig`. Output variables expose data from your Terraform configuration after it's applied.
  * **`value = module.kube-hetzner.kubeconfig`:** The value of this output is taken from an output named `kubeconfig` that is exposed by the `kube-hetzner` module itself. This is the generated Kubernetes configuration file content.
  * **`sensitive = true`:** Marks this output as sensitive. Terraform will not display its value in plain text in the console during `apply` or `output` commands unless explicitly requested (e.g., `terraform output --raw kubeconfig`). This is crucial because the kubeconfig contains credentials.
* **Other Potential Outputs (as shown in the "How-To" version):**
  * It's common to output other useful information like the cluster name, IP addresses of nodes, load balancer IPs, etc., by accessing corresponding outputs from the `kube-hetzner` module.

---

**Section 5: Input Variable Definition (for Root Module)**

```terraform
variable "hcloud_token" {
  sensitive = true
  default   = ""
}
```

* **`variable "hcloud_token"` Block:**
  * **Purpose:** Declares an input variable named `hcloud_token` for this root Terraform configuration.
  * **`sensitive = true`:** Marks this input variable as sensitive. If you were to set it via a `terraform.tfvars` file or command line (`-var="hcloud_token=..."`), Terraform would handle it with more care regarding logging.
  * **`default = ""`:** Provides a default value (empty string). This allows the logic `var.hcloud_token != "" ? var.hcloud_token : local.hcloud_token` to work correctly:
    * If `TF_VAR_hcloud_token` is set in the environment, `var.hcloud_token` gets that value.
    * If not, `var.hcloud_token` defaults to `""`, and the ternary operator then chooses `local.hcloud_token`.
  * This variable declaration is what allows `TF_VAR_hcloud_token` to populate `var.hcloud_token`.

```terraform
variable "robot_user" {
  sensitive = true
  default   = ""
}
```

* **`variable "robot_user"` Block:**
  * **Purpose:** Declares an input variable named `robot_user` for this root Terraform configuration. The value should be retrieved from the Hetzner Robot Webservice UI. This variable is required for connecting Robot Nodes to the cluster and is only used when `robot_ccm_enabled` is set to `true`.
  * **`sensitive = true`:** Marks this input variable as sensitive. If you were to set it via a `terraform.tfvars` file or command line (`-var="hcloud_token=..."`), Terraform would handle it with more care regarding logging.
  * **`default = ""`:** Provides a default value (empty string). This allows the logic `var.robot_user != "" ? var.robot_user : local.robot_user` to work correctly:
    * If `TF_VAR_robot_user` is set in the environment, `var.robot_user` gets that value.
    * If not, `var.robot_user` defaults to `""`, and the ternary operator then chooses `local.robot_user`.
  * This variable declaration is what allows `TF_VAR_robot_user` to populate `var.robot_user`.

```terraform
variable "robot_password" {
  sensitive = true
  default   = ""
}
```

* **`variable "robot_password"` Block:**
  * **Purpose:** Declares an input variable named `robot_password` for this root Terraform configuration. The value should be retrieved from the Hetzner Robot Webservice UI. This variable is required for connecting Robot Nodes to the cluster and is only used when `robot_ccm_enabled` is set to `true`.
  * **`sensitive = true`:** Marks this input variable as sensitive. If you were to set it via a `terraform.tfvars` file or command line (`-var="hcloud_token=..."`), Terraform would handle it with more care regarding logging.
  * **`default = ""`:** Provides a default value (empty string). This allows the logic `var.robot_password != "" ? var.robot_password : local.robot_password` to work correctly:
    * If `TF_VAR_robot_password` is set in the environment, `var.robot_password` gets that value.
    * If not, `var.robot_password` defaults to `""`, and the ternary operator then chooses `local.robot_password`.
  * This variable declaration is what allows `TF_VAR_robot_password` to populate `var.robot_password`.
---

**Conclusion of the Deep Dive**

We have now traversed the entirety of the provided Terraform configuration, dissecting each parameter, comment, and block of logic. This detailed explanation should provide a much deeper understanding of how the `kube-hetzner` module is configured and the implications of each choice.

The key takeaways are:

* **Modularity:** The power of Terraform modules to abstract complexity.
* **Declarative IaC:** Defining the "what," not the "how."
* **Configuration Nuances:** Many settings have interdependencies, lifecycle considerations, and security implications.
* **Provider Interaction:** The crucial role of the Hetzner Cloud provider and API token.
* **k3s Specifics:** How k3s features (CNI, storage, upgrades, etc.) are exposed and managed through the module.
* **Extensibility:** Options for custom Helm values, Kustomize overlays, and pre/post commands allow tailoring the deployment significantly.

This detailed walkthrough should serve as a comprehensive reference for anyone working with or seeking to understand this particular Terraform setup for deploying k3s on Hetzner Cloud.

---

**Additional Variables Added Since June 2024**

The following variables have been added to the `kube-hetzner` module since the initial documentation was created. These provide additional functionality and configuration options:

**NAT Router Configuration**

```terraform
  # Setup a NAT router, and automatically disable public ips on all control plane and agent nodes.
  # To use this, you must also set use_control_plane_lb = true, otherwise kubectl can never reach the cluster.
  # The NAT router will also function as a bastion. This makes securing the cluster easier, as all public traffic passes through a single strongly secured node.
  # It does however also introduce a single point of failure, so if you need high-availability on your egress, you should consider other configurations.
  # nat_router = {
  #   server_type = "cx33"
  #   location = "nbg1"
  # }
```

* **`nat_router` (Object, Optional):**
  * **Purpose:** Creates a dedicated NAT router server that acts as the single egress point for all cluster traffic. When enabled, all control plane and agent nodes are provisioned without public IPs.
  * **Requirements:** Must set `use_control_plane_lb = true` when using NAT router, as kubectl needs a public endpoint to reach the cluster.
  * **Benefits:**
    * Enhanced security by limiting public exposure to a single hardened node
    * Acts as a bastion host for SSH access to internal nodes
    * Simplifies firewall rules and security auditing
    * Automatically forwards Kubernetes API traffic (port 6443) when `control_plane_lb_enable_public_interface = false`
  * **Trade-offs:** Introduces a single point of failure for egress traffic
  * **Configuration:**
    * `server_type`: The Hetzner server type for the NAT router
    * `location`: The location where the NAT router should be deployed
    * `labels`: (Optional) Additional labels for the NAT router
    * `enable_sudo`: (Optional, default: false) Enable sudo access for the nat-router user
  * **Port Forwarding:** When the control plane LB has no public interface (`control_plane_lb_enable_public_interface = false`), the NAT router automatically configures iptables rules to forward incoming traffic on port 6443 to the control plane LB's private IP. This allows external kubectl access while keeping the control plane LB completely private.

**k3s Binary Configuration**

```terraform
  # Set to true if util-linux breaks on the OS (temporary regression fixed in util-linux v2.41.1).
  # k3s_prefer_bundled_bin = false
```

* **`k3s_prefer_bundled_bin` (Boolean, Optional):**
  * **Default:** `false`
  * **Purpose:** Forces k3s to use its bundled binaries instead of system binaries. This is a workaround for compatibility issues with certain OS utilities.
  * **Use Case:** Temporary fix for util-linux regression that affected k3s operation on certain MicroOS versions.

**Load Balancer Hostname Configuration**

```terraform
  # The lb_hostname setting optimizes communication between services within the Kubernetes cluster when they use domain names instead of direct service names.
  # By associating a domain name directly with the Hetzner Load Balancer, this setting can help reduce potential communication delays.
  # lb_hostname = "mycluster.example.com"
```

* **`lb_hostname` (String, Optional):**
  * **Purpose:** Associates a domain name directly with the Hetzner Load Balancer for optimized internal service communication.
  * **Technical Impact:** Sets the `load-balancer.hetzner.cloud/hostname` annotation in the LB definition.
  * **Use Case:** When services communicate using domain names (e.g., `a.mycluster.domain.com`) that point to the external LB, this can reduce communication delays.
  * **Setup:**
    1. Set `lb_hostname` to a domain like `mycluster.domain.com`
    2. Create an A record pointing to your LB's IP
    3. Create CNAME records for service subdomains pointing to the main domain
  * **Note:** Optional - only needed if services communicate via domain names instead of direct service names.

**Rancher Integration**

```terraform
  # You can enable Rancher (installed by Helm behind the scenes) with the following flag, the default is "false".
  # enable_rancher = true
  
  # If using Rancher you can set the Rancher hostname
  # rancher_hostname = "rancher.example.com"
  
  # Rancher install channel
  # rancher_install_channel = "stable"
  
  # Bootstrap password for Rancher (min 48 characters)
  # rancher_bootstrap_password = ""
  
  # Rancher registration manifest URL
  # rancher_registration_manifest_url = ""
```

* **`enable_rancher` (Boolean, Optional):**
  * **Default:** `false`
  * **Purpose:** Installs Rancher Manager for Kubernetes cluster management UI.
  * **Requirements:** 
    * Control plane nodes need at least 4GB RAM (cx21 or larger)
    * Must set `rancher_hostname`
    * May need to adjust `initial_k3s_channel` for compatibility
  * **Note:** Automatically installs cert-manager with self-signed certificates

* **`rancher_hostname` (String, Required if `enable_rancher = true`):**
  * **Purpose:** The hostname for accessing Rancher UI. Must be unique even if not used with DNS.
  * **Default:** Falls back to `lb_hostname` if set and using Hetzner LB

* **`rancher_install_channel` (String, Optional):**
  * **Default:** `"stable"`
  * **Options:** `"stable"` or `"latest"`
  * **Purpose:** Controls which Rancher release channel to use

* **`rancher_bootstrap_password` (String, Optional):**
  * **Purpose:** Initial admin password for Rancher (minimum 48 characters)
  * **Default:** Auto-generated if not specified

* **`rancher_registration_manifest_url` (String, Optional):**
  * **Purpose:** URL for importing this cluster into an existing Rancher installation
  * **Note:** Alternative to enabling Rancher directly - use one or the other

**Kustomization Control**

```terraform
  # Control kubeconfig and kustomization file generation
  # create_kubeconfig = false
  # create_kustomization = true
  # export_values = true
```

* **`create_kubeconfig` (Boolean, Optional):**
  * **Default:** `true` (for backward compatibility)
  * **Purpose:** Controls whether to create a kubeconfig file on disk
  * **Best Practice:** Set to `false` and use `terraform output --raw kubeconfig_data > cluster_kubeconfig.yaml` instead
  * **Security:** Prevents accidental commits of kubeconfig files

* **`create_kustomization` (Boolean, Optional):**
  * **Default:** `true`
  * **Purpose:** Controls creation of kustomization backup files
  * **Use Case:** Set to `false` for automation scenarios

* **`export_values` (Boolean, Optional):**
  * **Default:** `false`
  * **Purpose:** Exports values.yaml files for deployed components (traefik, longhorn, cert-manager, etc.)
  * **Use Case:** Useful for GitOps workflows with ArgoCD or similar tools

**Extra Kustomization Parameters**

```terraform
  # Extra commands and parameters for kustomization
  # extra_kustomize_deployment_commands = ["kubectl wait --for=condition=ready pod -l app=myapp -n mynamespace --timeout=300s"]
  # extra_kustomize_parameters = {
  #   myvar = "myvalue"
  # }
```

* **`extra_kustomize_deployment_commands` (List of Strings, Optional):**
  * **Purpose:** Commands to execute after `kubectl apply -k`
  * **Use Cases:** 
    * Wait for CRDs to be ready
    * Apply additional manifests
    * Post-install validation

* **`extra_kustomize_parameters` (Map, Optional):**
  * **Purpose:** Variables passed to `extra-manifests/kustomization.yaml.tpl`
  * **Use Case:** Template variables for custom kustomization overlays

**MicroOS Snapshot Control**

```terraform
  # Use specific MicroOS snapshot IDs
  # microos_x86_snapshot_id = "123456"
  # microos_arm_snapshot_id = "789012"
```

* **`microos_x86_snapshot_id` / `microos_arm_snapshot_id` (String, Optional):**
  * **Default:** Uses the most recent snapshot created with `createkh`
  * **Purpose:** Pin to specific MicroOS snapshot versions
  * **Discovery:** `hcloud image list --selector 'microos-snapshot=yes'`
  * **Use Case:** Ensure consistency across deployments or rollback to known-good images

**vSwitch Configuration**

```terraform
  # To connect the Hetzner Cloud network to Robot servers via vSwitch subnet, create the vSwitch and set its ID to the `vswitch_id` (number).
  # Note that the VLAN ID is not the same as vSwitch ID. The vSwitch-subnet is assigned to 10.201.0.0/16 by default, can be changed via var.vswitch_subnet_index.
  # The vSwitch subnet is not created when the value is null. Default: null
  # vswitch_id = null
```

* **`vswitch_id` (number, Optional):**
  * **Purpose:** Connects the Cloud network to a pre-existing Hetzner vSwitch by creating a vSwitch-type subnet. It also exposes Cloud network routes to the vSwitch.
  * **Requirements:** vSwitch must exist
  * **Use Case:** The connection is required if Hetzner Robot instances are connected to the Hetzner Cloud instances via private networking  

* **`vswitch_subnet_index` (number, Optional):**
  * **Purpose:** Defines the subnet range index to be used in the vSwitch subnet creation. Default: 201, which then converts to 10.201.0.0/16 by default.

**Additional Helm Values Customization**

The following variables allow deep customization of various components through Helm values:

```terraform
  # Custom Cilium values
  # cilium_values = <<-EOT
  # ipam:
  #   mode: kubernetes
  # EOT
  
  # Custom cert-manager values
  # cert_manager_values = <<-EOT
  # crds:
  #   enabled: true
  # EOT
  
  # Custom Hetzner CCM values
  # hetzner_ccm_values = <<-EOT
  # networking:
  #   enabled: true
  # EOT
  
  # Custom CSI driver SMB values
  # csi_driver_smb_values = <<-EOT
  # controller:
  #   replicas: 2
  # EOT
  
  # Custom Longhorn values
  # longhorn_values = <<-EOT
  # defaultSettings:
  #   defaultDataPath: /var/longhorn
  # EOT
  
  # Custom Rancher values
  # rancher_values = <<-EOT
  # hostname: rancher.example.com
  # replicas: 3
  # EOT
```

Each of these `*_values` variables:
* **Purpose:** Override default Helm chart values for the respective component
* **Format:** YAML string (heredoc syntax preserves formatting)
* **Reference:** See each component's Helm chart documentation for available options
* **Note:** Indentation within the heredoc is significant

**Ingress Controller Versions and Values**

```terraform
  # Specific ingress controller versions
  # traefik_version = "30.1.0"
  # nginx_version = "4.11.3"
  # haproxy_version = "1.41.0"
  
  # Custom Traefik values
  # traefik_values = <<-EOT
  # deployment:
  #   replicas: 3
  # EOT
  
  # Custom Nginx values
  # nginx_values = <<-EOT
  # controller:
  #   replicaCount: 3
  # EOT
  
  # Custom HAProxy configuration
  # haproxy_additional_proxy_protocol_ips = ["10.0.0.0/8", "172.16.0.0/12"]
  # haproxy_requests_cpu = "250m"
  # haproxy_requests_memory = "256Mi"
  # haproxy_values = <<-EOT
  # controller:
  #   replicaCount: 3
  # EOT
```

* **`traefik_version` / `nginx_version` / `haproxy_version` (String, Optional):**
  * **Purpose:** Pin to specific Helm chart versions for ingress controllers
  * **Default:** Latest available version
  * **Reference:** Check respective GitHub releases pages

* **`traefik_values` / `nginx_values` / `haproxy_values` (String, Optional):**
  * **Purpose:** Override default Helm values for ingress controllers
  * **Format:** YAML heredoc string

* **`haproxy_additional_proxy_protocol_ips` (List of Strings, Optional):**
  * **Purpose:** Additional trusted IPs for HAProxy proxy protocol
  * **Default:** Includes common private ranges

* **`haproxy_requests_cpu` / `haproxy_requests_memory` (String, Optional):**
  * **Purpose:** Resource requests for HAProxy pods
  * **Format:** Kubernetes resource notation (e.g., "250m", "256Mi")

---

This concludes the documentation of variables added to the `kube-hetzner` module since June 2024. These additions provide enhanced security options (NAT router), better integration capabilities (Rancher), more granular control over deployments (snapshot IDs, kubeconfig generation), and extensive customization options through Helm values overrides.
