# Backup and restore of sa cluster

Both `k3s` and `RKE2` allow for automated etcd backups to local and s3. etcd is the default storage backend on
kube-hetzner, even for a single control plane cluster, hence this should work for all cluster deployments.

## Enable backups

### Scheduled backups to s3

1. Fill the kube.tf config `etcd_s3_backup`, it will enable automated, scheduled backups to S3. See the example in the
   Restore section below.
2. Add the k3s_token as an output to your kube.tf
   ```tf
   output "k3s_token" {
     value     = module.kube-hetzner.k3s_token
     sensitive = true
   }
   ```
3. Make sure you can access the k3s_token via `terraform output k3s_token`.

### On-demand backups

You can also create on-demand backups. This is useful if you want to create a backup, e.g., before a major change.
To create a local backup, run the following command on one of your control plane nodes.

For RKE2:

Save backup on the node:

```bash
/opt/rke2/bin/rke2 etcd-snapshot save --name <name-of-the-snapshot>
```

Save backup on the node __and__ S3:

If you have configured `etcd_s3_backup` accordingly, you can use:

```bash
/opt/rke2/bin/rke2 etcd-snapshot save --name <name-of-the-snapshot> --etcd-s3
```

Else you can use:

```bash
/opt/rke2/bin/rke2 etcd-snapshot save --name <name-of-the-snapshot> \
--etcd-s3 \
--etcd-s3-endpoint=your-s3-endpoint(without-https://) \
--etcd-s3-bucket=your-s3-bucket \
--etcd-s3-folder=your-s3-folder \
--etcd-s3-access-key=your-s3-access-key \
--etcd-s3-secret-key=your-s3-secret-key
```

## Restore

1. Before cluster creation, add the following to your kube.tf. Replace the local variables to match your values.

For k3s:

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
  etcd_s3_endpoint   = "your-s3-endpoint(without-https://)"
  etcd_s3_bucket     = "your-s3-bucket"
  etcd_s3_access_key = "your-s3-access-key"
  etcd_s3_secret_key = var.etcd_s3_secret_key
  # this is secret information, hence it is passed as an environment variable

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

For RKE2:

```tf
locals {
  # ...

  k3s_token = var.k3s_token  # this is secret information, hence it is passed as an environment variable

  etcd_snapshot_name = "name-of-the-snapshot(no-path,just-the-name)"
  etcd_s3_endpoint   = "your-s3-endpoint(without-https://)"
  etcd_s3_bucket     = "your-s3-bucket"
  etcd_s3_folder     = "your-s3-folder"
  etcd_s3_access_key = "your-s3-access-key"
  etcd_s3_secret_key = var.etcd_s3_secret_key
  # this is secret information, hence it is passed as an environment variable

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
      export SERVER_EXISTS=$(cat /etc/rancher/rke2/config.yaml | grep -q '"server": "https:' && echo "yes" || echo "no")
      if [ "$SERVER_EXISTS" == "no" ]; then
        echo indeed this is the first control plane node > /tmp/restorenotes
        echo restoring etcd snapshot ${local.etcd_snapshot_name} > /tmp/restorenotes
        systemctl stop rke2-server
        /opt/rke2/bin/rke2 server \
          --cluster-reset \
          --cluster-reset-restore-path=${local.etcd_snapshot_name} \
          --etcd-s3 \
          --etcd-s3-endpoint=${local.etcd_s3_endpoint} \
          --etcd-s3-bucket=${local.etcd_s3_bucket} \
          --etcd-s3-folder=${local.etcd_s3_folder} \
          --etcd-s3-access-key=${local.etcd_s3_access_key} \
          --etcd-s3-secret-key=${local.etcd_s3_secret_key} \
          --token=${local.k3s_token}
        systemctl enable rke2-server
        systemctl start rke2-server
      
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

    - `export TF_VAR_k3s_token="..."` (Be careful, this token is like an admin password to the entire cluster. You need
      to use the same k3s_token which you saved when creating the backup.)
    - `export etcd_s3_secret_key="..."`

3. Create the cluster as usual. You can also change the cluster-name and deploy it next to the original backed up
   cluster.

Awesome! You restored a whole cluster from a backup.
