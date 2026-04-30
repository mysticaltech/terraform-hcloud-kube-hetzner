# How to Install and Deploy Additional Resources with Kube-Hetzner v3

Kube-Hetzner v3 deploys user resources through ordered `user_kustomizations`
sets. Each set points at a source folder containing Kustomize files with the
extension `.yaml.tpl` or `.yml.tpl`. The files are rendered, copied to the first
control plane, and applied with `kubectl apply -k`.

The main entry point for a set is `kustomization.yaml.tpl`. List rendered file
names without the `.tpl` suffix in the `resources` section.

When you run `terraform apply` or `tofu apply`, kube-hetzner deploys the
configured sets in numeric key order.

## Examples

Here are some examples of common use cases for deploying additional resources:

> **Note:** When trying out a demo, either copy that demo's files into
> `extra-manifests`, or point `source_folder` directly at the demo directory.

### Deploying Simple Resources

The easiest use case is to deploy simple resources to the cluster. Since the Kustomize resources are [Terraform template](https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/file) files, they can make use of parameters provided in the `kustomize_parameters` map of the `user_kustomizations`.

#### `kube.tf`

```hcl
user_kustomizations = {
  "1" = {
    source_folder = "extra-manifests"
    kustomize_parameters = {
      my_config_key = "somestring"
    }
    pre_commands  = ""
    post_commands = ""
  }
}
```

The variable defined in `kube.tf` can be used in any `.yaml.tpl` manifest.

#### `demo-config-map.yaml.tpl`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-config
data:
  someConfigKey: ${my_config_key}
```

For a full demo see the [simple-resources](simple-resources/) example.

### Deploying a Helm Chart

If you want to deploy a Helm chart to your cluster, you can use the [Helm Chart controller](https://docs.k3s.io/helm) included in K3s. The Helm Chart controller provides the CRDs `HelmChart` and `HelmChartConfig`.

For a full demo see the [helm-chart](helm-chart/) example.

### Multiple Namespaces

In more complex use cases, you may want to deploy to multiple namespaces with a
common base. Kustomize supports this behavior, and kube-hetzner copies
subdirectories below the configured `source_folder`.

For a full demo see the [multiple-namespaces](multiple-namespaces/) example.

### Using Letsencrypt with cert-manager

You can use a Let's Encrypt issuer to issue TLS certificates; see the
[Traefik/cert-manager example](https://doc.traefik.io/traefik/user-guides/cert-manager/).
Create a `ClusterIssuer` to make it available in all namespaces. Use the
staging ACME server while testing, then switch to the production directory URL.

For a full demo see the [letsencrypt](letsencrypt/)

## Debugging

To check the existing kustomization, you can run the following command:

```
$ terraform state list | grep kustom
  ...
  module.kube-hetzner.terraform_data.kustomization[0]
  module.kube-hetzner.module.user_kustomizations.terraform_data.kustomization_user_deploy
  module.kube-hetzner.module.user_kustomizations.module.user_kustomization_set["1"].terraform_data.install_scripts
  module.kube-hetzner.module.user_kustomizations.module.user_kustomization_set["1"].terraform_data.user_kustomization_template_files["kustomization.yaml.tpl"]
  ...
```

If you want to rerun just the kustomization part, you can use the following command:

```
terraform apply -replace='module.kube-hetzner.module.user_kustomizations.terraform_data.kustomization_user_deploy' --auto-approve
```
