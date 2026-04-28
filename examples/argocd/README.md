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

Create `terraform.tfvars` for non-secret values:

```hcl
cluster_name    = "argocd-demo"
```

Pass secrets and SSH key contents through environment variables so they are not
stored in a committed example file:

```sh
export TF_VAR_hcloud_token="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
export TF_VAR_ssh_private_key="$(cat ~/.ssh/id_ed25519)"
```

Run Terraform or OpenTofu:

```sh
terraform init -upgrade
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
