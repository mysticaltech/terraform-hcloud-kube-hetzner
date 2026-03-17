# ArgoCD Example (Helm + `kubeconfig_data`)

This example shows how to configure both the `kubernetes` and `helm` providers from `module.kube-hetzner.kubeconfig_data`, then install ArgoCD using `helm_release`.

## What this example does

1. Creates a minimal kube-hetzner cluster.
2. Reads the module output `kubeconfig_data`.
3. Uses that output to configure:
   - `provider "kubernetes"`
   - `provider "helm"`
4. Installs ArgoCD from `https://argoproj.github.io/argo-helm`.

## Usage

Create `terraform.tfvars`:

```hcl
hcloud_token    = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
ssh_public_key  = file("~/.ssh/id_ed25519.pub")
ssh_private_key = file("~/.ssh/id_ed25519")
cluster_name    = "argocd-demo"
```

Run Terraform:

```sh
terraform init
terraform apply -target=module.kube-hetzner -auto-approve
terraform apply -auto-approve
```

The first apply creates the cluster and makes `kubeconfig_data` available.  
The second apply installs ArgoCD through Helm.

## Best practices

- Prefer separating infra and app deployments into different Terraform states.
- Pin Helm chart versions (`version = "..."`) to avoid surprise upgrades.
- Keep `hcloud_token` and `ssh_private_key` as sensitive inputs.
- Use ArgoCD as GitOps controller after bootstrap; avoid mixing manual in-cluster drift with Terraform-managed Helm releases.
