## Page describes how to use longhorn custom mount path
<hr>
In order to use nvme and extarnal disks with longhorn, you need to mount extarnal disk to another location under `/var/` folder.
This gives more storage capacity across cluster, if you didint disable defualt longhorn disks off course.


> ⚠️ Note: You can set any mount path but only within `/var/` folder

### How set mount for your external disk differs to  ``/var/`` folder ?

1. You must anable longhorn in you module
2. Set helm values
```yamllonghorn_values = <<EOT
defaultSettings:
  nodeDrainPolicy: allow-if-replica-is-stopped
  defaultDataPath: /var/longhorn # This important, this path automatically creates Longhorn it will be default storage class woth points to nvme disks
persistence:
  defaultFsType: ext4
  defaultClassReplicaCount: 3
  defaultClass: true
  EOT
```
3. Nodes where you want to have customized mount path set following 
```terraform
agent_nodepools = [
//
{ //omit code
      labels = ["role=monitoring", "storage=ssd"], # Lable we use to filter nodes
      longhorn_volume_size = 50
      longhorn_mount_path = "/var/lib/longhorn" # This path you need to use further
}
]
```
3. Apply changes in result your disks will be mounted to /var/lib/longhorn

### How to configure Longhorn? 
1. You need to patch longhorn nodes
2. Create one more storage class

   
Here is example how you can achieve it
```terraform
data "kubernetes_nodes" "ssd_nodes" {
 metadata {
   labels = {
     "storage" = "ssd"
   }
 }
}

# Patch nodes only with this label
resource "null_resource" "longhorn_patch_external_disk" {
 for_each = {
   for node in data.kubernetes_nodes.ssd_nodes.nodes : node.metadata[0].name => node.metadata[0].name
 }
 triggers = {
   always_run = timestamp()  
 }
 provisioner "local-exec" {
   command = <<-EOT
     KUBECONFIG=${var.kubeconfig_path} kubectl -n longhorn-system patch nodes.longhorn.io ${each.key} --type merge -p '{
       "spec": {
         "disks": {
           "external-ssd": {
             "path": "/var/lib/longhorn", # Path you set in nodepools variable
             "allowScheduling": true,
             "tags": ["ssd"] 
           }
         }
       }
     }'
   EOT
 }
}

resource "kubernetes_manifest" "longhorn_ssd_replica" {
 manifest = {
   apiVersion = "storage.k8s.io/v1"
   kind       = "StorageClass"
   metadata = {
     name = "longhorn-ssd-replica"
   }
   provisioner = "driver.longhorn.io"
   parameters = {
     numberOfReplicas    = "1"
     staleReplicaTimeout = "30"
     diskSelector        = "ssd"

     fromBackup          = ""
   }
   reclaimPolicy        = "Delete"
   allowVolumeExpansion = true
   volumeBindingMode    = "Immediate"
 }
 depends_on = [null_resource.longhorn_patch_external_disk]
}
```
