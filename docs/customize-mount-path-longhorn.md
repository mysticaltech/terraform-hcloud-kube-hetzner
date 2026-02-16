## How to use a custom mount path for Longhorn
<hr>

In order to use NVMe and external disks with Longhorn, you may need to mount an external disk to a location other than the default under the `/var/` folder. This can provide more storage capacity across the cluster, especially if you haven't disabled the default Longhorn disks.

> ⚠️ Note: You can set any mount path, but it must be within the `/var/` folder.

### How to set a custom mount path for your external disk?

1.  You must enable Longhorn in your module.
    ```terraform
    enable_longhorn = true
    ```

2.  Set the Helm values for Longhorn. The `defaultDataPath` is important as this path is automatically created by Longhorn and will be the default storage class pointing to your primary disks (e.g., NVMe).
    ```yaml
    longhorn_values = <<-EOT
    defaultSettings:
      nodeDrainPolicy: allow-if-replica-is-stopped
      defaultDataPath: /var/longhorn
    persistence:
      defaultFsType: ext4
      defaultClassReplicaCount: 3
      defaultClass: true
    EOT
    ```

3.  In the `agent_nodepools` where you want to have a customized mount path, set the `longhorn_mount_path` variable. It's a good practice to define this path as a local variable to ensure consistency.

    ```terraform
    locals {
      custom_longhorn_path = "/var/lib/longhorn"
    }

    agent_nodepools = [
      {
        # ... other nodepool configuration
        labels               = ["role=monitoring", "storage=ssd"], # Label we use to filter nodes
        longhorn_volume_size = 50,
        longhorn_mount_path  = local.custom_longhorn_path # This is the custom path
      }
    ]
    ```

4.  Apply the changes. As a result, your external disks will be mounted to the path defined in `local.custom_longhorn_path`.

### How to configure Longhorn to use the new path?

After setting the custom mount path, you need to configure Longhorn to recognize and use it. This typically involves:
1.  Patching the Longhorn nodes to add the new disk.
2.  Creating a new StorageClass that uses the new disk.

Here is an example of how you can achieve this with Terraform:

```terraform
# Find the nodes with the 'ssd' storage label
data "kubernetes_nodes" "ssd_nodes" {
  metadata {
    labels = {
      "storage" = "ssd"
    }
  }
}

# Patch the selected Longhorn nodes to add the new disk
# IMPORTANT: The "path" value below must match the 'longhorn_mount_path' for the nodes
# selected by the 'storage=ssd' label.
resource "terraform_data" "longhorn_patch_external_disk" {
  for_each = {
    for node in data.kubernetes_nodes.ssd_nodes.nodes : node.metadata[0].name => node.metadata[0].name
  }
  provisioner "local-exec" {
    command = <<-EOT
      KUBECONFIG=${var.kubeconfig_path} kubectl -n longhorn-system patch nodes.longhorn.io ${each.key} --type merge -p '{
        "spec": {
          "disks": {
            "external-ssd": {
              "path": "${local.custom_longhorn_path}",
              "allowScheduling": true,
              "tags": ["ssd"]
            }
          }
        }
      }'
    EOT
  }
}

# Create a new StorageClass for the SSD-backed Longhorn storage
resource "kubernetes_manifest" "longhorn_ssd_storageclass" {
  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "longhorn-ssd"
    }
    provisioner = "driver.longhorn.io"
    parameters = {
      numberOfReplicas    = "3"
      staleReplicaTimeout = "30"
      diskSelector        = "ssd"
      fromBackup          = ""
    }
    reclaimPolicy        = "Delete"
    allowVolumeExpansion = true
    volumeBindingMode    = "Immediate"
  }

  depends_on = [terraform_data.longhorn_patch_external_disk]
}