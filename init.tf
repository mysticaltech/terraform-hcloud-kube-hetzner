resource "hcloud_load_balancer" "cluster" {
  count = local.has_external_load_balancer ? 0 : 1
  name  = local.load_balancer_name

  load_balancer_type = var.load_balancer_type
  location           = var.load_balancer_location
  labels             = local.labels
  delete_protection  = var.enable_delete_protection.load_balancer

  algorithm {
    type = var.load_balancer_algorithm_type
  }

  lifecycle {
    ignore_changes = [
      location,
      # Ignore changes to hcloud-ccm/service-uid label that is managed by the CCM.
      labels["hcloud-ccm/service-uid"],
    ]
  }
}

resource "hcloud_load_balancer_network" "cluster" {
  count = local.has_external_load_balancer ? 0 : 1

  load_balancer_id = hcloud_load_balancer.cluster.*.id[0]
  # Use -2 to get the last usable IP in the subnet
  ip = cidrhost(
    (
      length(hcloud_network_subnet.agent) > 0
      ? hcloud_network_subnet.agent.*.ip_range[0]
      : hcloud_network_subnet.control_plane.*.ip_range[0]
    )
  , -2)
  subnet_id = (
    length(hcloud_network_subnet.agent) > 0
    ? hcloud_network_subnet.agent.*.id[0]
    : hcloud_network_subnet.control_plane.*.id[0]
  )
  enable_public_interface = true

  lifecycle {
    create_before_destroy = false
    ignore_changes = [
      ip,
      enable_public_interface
    ]
  }
}

resource "hcloud_load_balancer_target" "cluster" {
  count = local.has_external_load_balancer ? 0 : 1

  depends_on       = [hcloud_load_balancer_network.cluster]
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.cluster.*.id[0]
  label_selector = join(",", concat(
    [for k, v in local.labels : "${k}=${v}"],
    [
      # Build label selector from lb_target_groups (respects allow_loadbalancer_target_on_control_plane)
      # Results in either: role in (control_plane_node,agent_node) or role in (agent_node)
      for key in keys(merge(local.lb_target_groups...)) :
      "${key} in (${
        join(",", compact([
          for labels in local.lb_target_groups :
          try(labels[key], "")
        ]))
      })"
    ]
  ))
  use_private_ip = true
}

locals {
  first_control_plane_ip = coalesce(
    module.control_planes[keys(module.control_planes)[0]].ipv4_address,
    module.control_planes[keys(module.control_planes)[0]].ipv6_address,
    module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
  )
}

resource "terraform_data" "first_control_plane" {
  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port
    timeout        = "10m" # Extended timeout to handle network migrations during upgrades

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Generating k3s master config file
  provisioner "file" {
    content = yamlencode(
      merge(
        {
          node-name                   = module.control_planes[keys(module.control_planes)[0]].name
          token                       = local.k3s_token
          cluster-init                = true
          disable-cloud-controller    = true
          disable-kube-proxy          = var.disable_kube_proxy
          disable                     = local.disable_extras
          kubelet-arg                 = local.kubelet_arg
          kube-controller-manager-arg = local.kube_controller_manager_arg
          flannel-iface               = local.flannel_iface
          node-ip                     = module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
          advertise-address           = module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
          node-taint                  = local.control_plane_nodes[keys(module.control_planes)[0]].taints
          node-label                  = local.control_plane_nodes[keys(module.control_planes)[0]].labels
          cluster-cidr                = var.cluster_ipv4_cidr
          service-cidr                = var.service_ipv4_cidr
          cluster-dns                 = local.cluster_dns_ipv4
        },
        lookup(local.cni_k3s_settings, var.cni_plugin, {}),
        var.use_control_plane_lb ? {
          tls-san = concat(
            compact([
              hcloud_load_balancer.control_plane.*.ipv4[0],
              hcloud_load_balancer_network.control_plane.*.ip[0],
              var.kubeconfig_server_address != "" ? var.kubeconfig_server_address : null,
              !var.control_plane_lb_enable_public_interface && var.nat_router != null ? hcloud_server.nat_router[0].ipv4_address : null
            ]),
            var.additional_tls_sans
          )
          } : {
          tls-san = concat([local.first_control_plane_ip], var.additional_tls_sans)
        },
        local.etcd_s3_snapshots,
        var.control_planes_custom_config,
        (local.control_plane_nodes[keys(module.control_planes)[0]].selinux == true ? { selinux = true } : {}),
        local.prefer_bundled_bin_config
      )
    )

    destination = "/tmp/config.yaml"
  }

  # Install k3s server
  provisioner "remote-exec" {
    inline = local.install_k3s_server
  }

  # Upon reboot start k3s and wait for it to be ready to receive commands
  provisioner "remote-exec" {
    inline = [
      "systemctl start k3s",
      # prepare the needed directories
      "mkdir -p /var/post_install /var/user_kustomize",
      # wait for k3s to become ready
      <<-EOT
      timeout 120 bash <<EOF
        until systemctl status k3s > /dev/null; do
          systemctl start k3s
          echo "Waiting for the k3s server to start..."
          sleep 2
        done
        until [ -e /etc/rancher/k3s/k3s.yaml ]; do
          echo "Waiting for kubectl config..."
          sleep 2
        done
        until [[ "\$(kubectl get --raw='/readyz' 2> /dev/null)" == "ok" ]]; do
          echo "Waiting for the cluster to become ready..."
          sleep 2
        done
      EOF
      EOT
    ]
  }

  depends_on = [
    hcloud_network_subnet.control_plane
  ]
}
moved {
  from = null_resource.first_control_plane
  to   = terraform_data.first_control_plane
}

# Needed for rancher setup
resource "random_password" "rancher_bootstrap" {
  count   = length(var.rancher_bootstrap_password) == 0 ? 1 : 0
  length  = 48
  special = false
}

resource "terraform_data" "kube_system_secrets" {
  triggers_replace = {
    secrets_sha = sha256(yamlencode(local.kube_system_secrets))
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/kube_system_secrets.yaml.tpl",
      {
        kube_system_secrets = local.kube_system_secrets,
    })
    destination = "/var/post_install/kube_system_secrets.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      set -ex
      # Retry logic to handle temporary network connectivity issues during upgrades
      MAX_ATTEMPTS=30
      RETRY_INTERVAL=10
      for attempt in $(seq 1 $MAX_ATTEMPTS); do
        echo "Attempt $attempt: Checking kubectl connectivity..."
        if [ "$(kubectl get --raw='/readyz' 2>/dev/null)" = "ok" ]; then
          echo "kubectl connectivity established, deploying secrets..."

          kubectl apply -f /var/post_install/kube_system_secrets.yaml

          echo "Secrets deployed successfully"
          break
        else
          echo "kubectl not ready yet, waiting $RETRY_INTERVAL seconds..."
          sleep $RETRY_INTERVAL
        fi
        
        if [ $attempt -eq $MAX_ATTEMPTS ]; then
          echo "Failed to establish kubectl connectivity after $MAX_ATTEMPTS attempts"
          exit 1
        fi
      done

      rm /var/post_install/kube_system_secrets.yaml

      EOT
    ]
  }

  depends_on = [
    hcloud_load_balancer.cluster,
    terraform_data.control_planes,
  ]
}
moved {
  from = null_resource.kube_system_secrets
  to   = terraform_data.kube_system_secrets
}

# This is where all the setup of Kubernetes components happen
resource "terraform_data" "kustomization" {
  triggers_replace = {
    # Redeploy helm charts when the underlying values change
    helm_values_yaml = join("---\n", [
      local.traefik_values,
      local.nginx_values,
      local.haproxy_values,
      local.calico_values,
      local.cilium_values,
      local.longhorn_values,
      local.csi_driver_smb_values,
      local.cert_manager_values,
      local.rancher_values,
      local.hetzner_csi_values,
      local.hetzner_ccm_values,

    ])
    # Redeploy when versions of addons need to be updated
    versions = join("\n", [
      coalesce(var.initial_k3s_channel, "N/A"),
      coalesce(var.install_k3s_version, "N/A"),
      coalesce(var.cluster_autoscaler_version, "N/A"),
      coalesce(var.hetzner_ccm_version, "N/A"),
      coalesce(var.hetzner_csi_version, "N/A"),
      coalesce(var.kured_version, "N/A"),
      coalesce(var.calico_version, "N/A"),
      coalesce(var.cilium_version, "N/A"),
      coalesce(var.traefik_version, "N/A"),
      coalesce(var.nginx_version, "N/A"),
      coalesce(var.haproxy_version, "N/A"),
      coalesce(var.cert_manager_version, "N/A"),
      coalesce(var.csi_driver_smb_version, "N/A"),
      coalesce(var.longhorn_version, "N/A"),
      coalesce(var.rancher_version, "N/A"),
      coalesce(var.sys_upgrade_controller_version, "N/A"),
    ])
    options = join("\n", [
      for option, value in local.kured_options : "${option}=${value}"
    ])
    ccm_use_helm = var.hetzner_ccm_use_helm
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.first_control_plane_ip
    port           = var.ssh_port
    timeout        = "10m" # Extended timeout to handle network migrations during upgrades

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Upload kustomization.yaml, containing Hetzner CSI & CSM, as well as kured.
  provisioner "file" {
    content     = local.kustomization_backup_yaml
    destination = "/var/post_install/kustomization.yaml"
  }

  # Upload the flannel RBAC fix
  provisioner "file" {
    content     = file("${path.module}/kustomize/flannel-rbac.yaml")
    destination = "/var/post_install/flannel-rbac.yaml"
  }

  # Upload traefik ingress controller config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/traefik_ingress.yaml.tpl",
      {
        version          = var.traefik_version
        values           = indent(4, local.traefik_values)
        target_namespace = local.ingress_controller_namespace
    })
    destination = "/var/post_install/traefik_ingress.yaml"
  }

  # Upload nginx ingress controller config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/nginx_ingress.yaml.tpl",
      {
        version          = var.nginx_version
        values           = indent(4, local.nginx_values)
        target_namespace = local.ingress_controller_namespace
    })
    destination = "/var/post_install/nginx_ingress.yaml"
  }

  # Upload haproxy ingress controller config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/haproxy_ingress.yaml.tpl",
      {
        version          = var.haproxy_version
        values           = indent(4, local.haproxy_values)
        target_namespace = local.ingress_controller_namespace
    })
    destination = "/var/post_install/haproxy_ingress.yaml"
  }

  # Upload the CCM patch config using the legacy deployment
  provisioner "file" {
    content = var.hetzner_ccm_use_helm ? "" : templatefile(
      "${path.module}/templates/ccm.yaml.tpl",
      {
        cluster_cidr_ipv4   = var.cluster_ipv4_cidr
        default_lb_location = var.load_balancer_location
        using_klipper_lb    = local.using_klipper_lb
    })
    destination = "/var/post_install/ccm.yaml"
  }

  # Upload the CCM patch config using helm
  provisioner "file" {
    content = var.hetzner_ccm_use_helm ? templatefile(
      "${path.module}/templates/hcloud-ccm-helm.yaml.tpl",
      {
        values              = indent(4, local.hetzner_ccm_values)
        version             = coalesce(local.ccm_version, "*")
        using_klipper_lb    = local.using_klipper_lb
        default_lb_location = var.load_balancer_location
      }
    ) : ""
    destination = "/var/post_install/hcloud-ccm-helm.yaml"
  }

  # Upload the calico patch config, for the kustomization of the calico manifest
  # This method is a stub which could be replaced by a more practical helm implementation
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/calico.yaml.tpl",
      {
        values = trimspace(local.calico_values)
    })
    destination = "/var/post_install/calico.yaml"
  }

  # Upload the cilium install file
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/cilium.yaml.tpl",
      {
        values  = indent(4, local.cilium_values)
        version = var.cilium_version
    })
    destination = "/var/post_install/cilium.yaml"
  }

  # Upload the system upgrade controller plans config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/plans.yaml.tpl",
      {
        channel          = var.initial_k3s_channel
        version          = var.install_k3s_version
        disable_eviction = !var.system_upgrade_enable_eviction
        drain            = var.system_upgrade_use_drain
        upgrade_window   = var.system_upgrade_schedule_window
    })
    destination = "/var/post_install/plans.yaml"
  }

  # Upload the Longhorn config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/longhorn.yaml.tpl",
      {
        longhorn_namespace  = var.longhorn_namespace
        longhorn_repository = var.longhorn_repository
        version             = var.longhorn_version
        bootstrap           = var.longhorn_helmchart_bootstrap
        values              = indent(4, local.longhorn_values)
    })
    destination = "/var/post_install/longhorn.yaml"
  }

  # Upload the csi-driver config (ignored if csi is disabled)
  provisioner "file" {
    content = var.disable_hetzner_csi ? "" : templatefile(
      "${path.module}/templates/hcloud-csi.yaml.tpl",
      {
        version = coalesce(local.csi_version, "*")
        values  = indent(4, local.hetzner_csi_values)
      }
    )
    destination = "/var/post_install/hcloud-csi.yaml"
  }

  # Upload the csi-driver-smb config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/csi-driver-smb.yaml.tpl",
      {
        version   = var.csi_driver_smb_version
        bootstrap = var.csi_driver_smb_helmchart_bootstrap
        values    = indent(4, local.csi_driver_smb_values)
    })
    destination = "/var/post_install/csi-driver-smb.yaml"
  }

  # Upload the cert-manager config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/cert_manager.yaml.tpl",
      {
        version   = var.cert_manager_version
        bootstrap = var.cert_manager_helmchart_bootstrap
        values    = indent(4, local.cert_manager_values)
    })
    destination = "/var/post_install/cert_manager.yaml"
  }

  # Upload the Rancher config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/rancher.yaml.tpl",
      {
        rancher_install_channel = var.rancher_install_channel
        version                 = var.rancher_version
        bootstrap               = var.rancher_helmchart_bootstrap
        values                  = indent(4, local.rancher_values)
    })
    destination = "/var/post_install/rancher.yaml"
  }

  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/kured.yaml.tpl",
      {
        options = local.kured_options
      }
    )
    destination = "/var/post_install/kured.yaml"
  }

  # Deploy our post-installation kustomization
  provisioner "remote-exec" {
    inline = concat([
      "set -ex",

      # This ugly hack is here, because terraform serializes the
      # embedded yaml files with "- |2", when there is more than
      # one yamldocument in the embedded file. Kustomize does not understand
      # that syntax and tries to parse the blocks content as a file, resulting
      # in weird errors. so gnu sed with funny escaping is used to
      # replace lines like "- |3" by "- |" (yaml block syntax).
      # due to indendation this should not changes the embedded
      # manifests themselves
      "sed -i 's/^- |[0-9]\\+$/- |/g' /var/post_install/kustomization.yaml",

      # Wait for k3s to become ready (we check one more time) because in some edge cases,
      # the cluster had become unvailable for a few seconds, at this very instant.
      <<-EOT
      timeout 360 bash <<EOF
        until [[ "\$(kubectl get --raw='/readyz' 2> /dev/null)" == "ok" ]]; do
          echo "Waiting for the cluster to become ready..."
          sleep 2
        done
      EOF
      EOT
      ]
      ,
      var.hetzner_ccm_use_helm ? [
        "echo 'Remove legacy ccm manifests if they exist'",
        "kubectl delete serviceaccount,deployment -n kube-system --field-selector 'metadata.name=hcloud-cloud-controller-manager' --selector='app.kubernetes.io/managed-by!=Helm'",
        "kubectl delete clusterrolebinding -n kube-system --field-selector 'metadata.name=system:hcloud-cloud-controller-manager' --selector='app.kubernetes.io/managed-by!=Helm'",
        ] : [
        "echo 'Uninstall helm ccm manifests if they exist'",
        "kubectl delete --ignore-not-found -n kube-system helmchart.helm.cattle.io/hcloud-cloud-controller-manager",
      ],
      [
        # Ready, set, go for the kustomization
        "kubectl apply -k /var/post_install",
        "echo 'Waiting for the system-upgrade-controller deployment to become available...'",
        "kubectl -n system-upgrade wait --for=condition=available --timeout=900s deployment/system-upgrade-controller",
        "sleep 7", # important as the system upgrade controller CRDs sometimes don't get ready right away, especially with Cilium.
        "kubectl -n system-upgrade apply -f /var/post_install/plans.yaml",
        # Wait for system namespace deployments to become available
        "for ns in kube-system ${var.enable_cert_manager ? "cert-manager" : ""} ${var.enable_longhorn ? var.longhorn_namespace : ""} ${local.ingress_controller_namespace} system-upgrade; do [ -n \"$ns\" ] && kubectl get ns $ns &>/dev/null && kubectl -n $ns wait deployment --all --for=condition=Available --timeout=300s || true; done",
        # Wait for helm install jobs to complete (only in namespaces that have jobs)
        "for ns in kube-system ${var.enable_longhorn ? var.longhorn_namespace : ""}; do [ -n \"$ns\" ] && kubectl get ns $ns &>/dev/null && kubectl -n $ns get job -o name 2>/dev/null | grep -q . && kubectl -n $ns wait job --all --for=condition=Complete --timeout=300s || true; done"
      ],
      local.has_external_load_balancer ? [] : [
        <<-EOT
      timeout 360 bash <<EOF
      until [ -n "\$(kubectl get -n ${local.ingress_controller_namespace} service/${lookup(local.ingress_controller_service_names, var.ingress_controller)} --output=jsonpath='{.status.loadBalancer.ingress[0].${var.lb_hostname != "" ? "hostname" : "ip"}}' 2> /dev/null)" ]; do
          echo "Waiting for load-balancer to get an IP..."
          sleep 2
      done
      EOF
      EOT
    ])
  }

  depends_on = [
    hcloud_load_balancer.cluster,
    terraform_data.control_planes,
    random_password.rancher_bootstrap,
    hcloud_volume.longhorn_volume,
    terraform_data.kube_system_secrets
  ]
}
moved {
  from = null_resource.kustomization
  to   = terraform_data.kustomization
}
