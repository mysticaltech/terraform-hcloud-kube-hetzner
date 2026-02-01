# How to Install and Deploy Additional Resources with Terraform and Kube-Hetzner

Kube-Hetzner allows you to provide user-defined resources after the initial setup of the Kubernetes cluster. You can deploy additional resources using Kustomize scripts in the `extra-manifests` directory with the extension `.yaml.tpl`. These scripts are recursively copied onto the control plane and deployed with `kubectl apply -k`. The main entry point for these additional resources is the `kustomization.yaml.tpl` file. In this file, you need to list the names of other manifests without the `.tpl` extension in the resources section.

When you execute terraform apply, the manifests in the extra-manifests directory, including the rendered versions of the `*.yaml.tpl` files, will be automatically deployed to the cluster.

## Examples

Here are some examples of common use cases for deploying additional resources:

> **Note**: When trying out the demos, make sure that the files from the demo folders are located in the `extra-manifests` directory.

### Deploying Simple Resources

The easiest use case is to deploy simple resources to the cluster. Since the Kustomize resources are [Terraform template](https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/file) files, they can make use of parameters provided in the `extra_kustomize_parameters` map of the `kube.tf` file.

#### `kube.tf`

```
...
extra_kustomize_parameters = {
  my_config_key = "somestring"
}
...
```

The variable defined in `kube.tf` can be used in any `.yaml.tpl` manifest.

#### `configmap.tf`

```
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

In more complex use cases, you may want to deploy to multiple namespaces with a common base. Kustomize supports this behavior, and it can be since Kube-Hetzner is considering all subdirectories of `extra-manifests`.

For a full demo see the [multiple-namespaces](multiple-namespaces/) example.

### Using Letsencrypt with cert-manager

You can use letsencrypt issuer to issue tls certificate see [example](https://doc.traefik.io/traefik/user-guides/cert-manager/). You need to create a issuer type of `ClusterIssuer` to make is available in all namespaces, unlike in the traefik example. Also note that the `server` in the example is a stagging server, you would need a prod server to use in, well, production. The prod server link can be found at `https://letsencrypt.org/getting-started/`

For a full demo see the [letsencrypt](letsencrypt/)

## Debugging

To check the existing kustomization, you can run the following command:

```
$ terraform state list | grep kustom
  ...
  module.kube-hetzner.null_resource.kustomization
  module.kube-hetzner.null_resource.kustomization_user["demo-config-map.yaml.tpl"]
  module.kube-hetzner.null_resource.kustomization_user["demo-pod.yaml.tpl"]
  module.kube-hetzner.null_resource.kustomization_user["kustomization.yaml.tpl"]
  ...
```

If you want to rerun just the kustomization part, you can use the following command:

```
terraform apply -replace='module.kube-hetzner.null_resource.kustomization_user["kustomization.yaml.tpl"]' --auto-approve
```
