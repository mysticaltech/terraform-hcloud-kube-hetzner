# Migration advice when updating the module

# 2.18.3 -> 2.19.0

## User Kustomization
The extra_kustomization-feature has been moved to a module so that multiple extra_kustomizations can be run in sequential steps.
A new variable `user_kustomizations` is now in use, which contains the previous extra_kustomize_* vars.

### Affects
If you are using Helm charts from the `extra-manifests` folder or if you are using any of the following variables: `extra_kustomize_deployment_commands`, `extra_kustomize_parameters` or `extra_kustomize_folder`.

### Steps

1. Create a new variable `user_kustomizations`, see below and the kube.tf.example.

```
user_kustomizations = {
    "1" = {
    source_folder        = "extra-manifests" # Place here the source-folder defined previously in `var.extra_kustomize_folder`. If `var.extra_kustomize_folder` was previously undefined, leave as "extra-manifests".

    kustomize_parameters = {} # Replace with contents of `var.extra_kustomize_parameters`. If `var.extra_kustomize_parameters` was previously undefined, remove the line or keep the default {}.

    pre_commands         = ""

    post_commands        = "" # Replace with contents of `var.extra_kustomize_deployment_commands`. If `var.extra_kustomize_deployment_commands` was previously undefined, remove the line or keep the default "".

    }
}
```

2. After placing the variables, remove the variables `extra_kustomize_deployment_commands`, `extra_kustomize_parameters` and `extra_kustomize_folder` from kube.tf.
