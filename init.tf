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
  count = local.has_external_load_balancer || local.multinetwork_overlay_enabled ? 0 : 1

  load_balancer_id = hcloud_load_balancer.cluster.*.id[0]
  # Use the last usable IP in the subnet. If control-plane LB is also enabled
  # on the shared subnet, reserve a distinct address to avoid collision.
  ip = cidrhost(
    (
      length(hcloud_network_subnet.agent) > 0
      ? hcloud_network_subnet.agent.*.ip_range[0]
      : hcloud_network_subnet.control_plane.*.ip_range[0]
    )
  , (var.enable_control_plane_load_balancer && length(hcloud_network_subnet.agent) == 0 ? -3 : -2))
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
  use_private_ip = !local.multinetwork_overlay_enabled
}

locals {
  first_control_plane_ip = local.control_plane_ips[keys(local.control_plane_ips)[0]]
}

resource "terraform_data" "first_control_plane" {
  count = local.kubernetes_distribution == "k3s" ? 1 : 0
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
          token                       = local.cluster_token
          cluster-init                = true
          disable-cloud-controller    = true
          disable-kube-proxy          = !var.enable_kube_proxy
          disable                     = local.disable_extras
          https-listen-port           = var.kubernetes_api_port
          kubelet-arg                 = local.kubelet_arg
          kube-apiserver-arg          = concat(local.kube_apiserver_arg, var.enable_secrets_encryption ? ["encryption-provider-config=${local.secrets_encryption_config_file}"] : [])
          kube-controller-manager-arg = local.kube_controller_manager_arg
          flannel-iface               = local.flannel_iface
          node-ip                     = module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
          advertise-address           = module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
          node-taint                  = local.control_plane_nodes[keys(module.control_planes)[0]].taints
          node-label                  = local.control_plane_nodes[keys(module.control_planes)[0]].labels
          cluster-cidr                = local.cluster_cidr
          service-cidr                = local.service_cidr
          cluster-dns                 = local.cluster_dns
        },
        local.multinetwork_overlay_enabled ? {
          node-external-ip = join(",", compact([local.multinetwork_transport_ipv4_enabled ? module.control_planes[keys(module.control_planes)[0]].ipv4_address : null, local.multinetwork_transport_ipv6_enabled ? module.control_planes[keys(module.control_planes)[0]].ipv6_address : null]))
        } : {},
        lookup(local.cni_k3s_settings, var.cni_plugin, {}),
        var.enable_control_plane_load_balancer ? {
          tls-san = concat(
            compact([
              hcloud_load_balancer.control_plane.*.ipv4[0],
              hcloud_load_balancer_network.control_plane.*.ip[0],
              local.kubeconfig_server_address != "" ? local.kubeconfig_server_address : null,
              local.control_plane_endpoint_host,
              !var.control_plane_load_balancer_enable_public_network && var.nat_router != null ? hcloud_server.nat_router[0].ipv4_address : null
            ]),
            var.additional_tls_sans
          )
          } : {
          tls-san = concat(
            compact([
              local.first_control_plane_ip,
              local.control_plane_endpoint_host,
              local.kubeconfig_server_address != "" ? local.kubeconfig_server_address : null,
              module.control_planes[keys(module.control_planes)[0]].private_ipv4_address != "" ? module.control_planes[keys(module.control_planes)[0]].private_ipv4_address : null,
              module.control_planes[keys(module.control_planes)[0]].ipv4_address != "" ? module.control_planes[keys(module.control_planes)[0]].ipv4_address : null,
              module.control_planes[keys(module.control_planes)[0]].ipv6_address != "" ? module.control_planes[keys(module.control_planes)[0]].ipv6_address : null,
              try(one(module.control_planes[keys(module.control_planes)[0]].network).ip, null)
            ]),
            var.additional_tls_sans
          )
        },
        local.etcd_s3_snapshots,
        var.control_planes_custom_config,
        (!var.enable_selinux ? { selinux = false } : (local.control_plane_nodes[keys(module.control_planes)[0]].selinux == true ? { selinux = true } : {})),
        local.prefer_bundled_bin_config
      )
    )

    destination = "/tmp/config.yaml"
  }

  provisioner "file" {
    content     = local.secrets_encryption_config
    destination = "/tmp/encryption-config.yaml"
  }

  provisioner "file" {
    content     = var.authentication_config
    destination = "/tmp/authentication_config.yaml"
  }

  provisioner "file" {
    content     = var.audit_policy_config
    destination = "/tmp/audit-policy.yaml"
  }

  # Install k3s server
  provisioner "remote-exec" {
    inline = concat(local.k8s_install_network_env_by_control_plane[keys(module.control_planes)[0]], local.install_k3s_server)
  }

  # Upon reboot start k3s and wait for it to be ready to receive commands
  provisioner "remote-exec" {
    inline = [
      local.bootstrap_control_plane_api_config_script,
      "systemctl enable --now iscsid",
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

moved {
  from = terraform_data.first_control_plane
  to   = terraform_data.first_control_plane[0]
}

resource "terraform_data" "control_plane_setup_rke2" {
  count = local.kubernetes_distribution == "rke2" ? 1 : 0

  triggers_replace = {
    control_plane_id = module.control_planes[keys(module.control_planes)[0]].id
    # Redeploy helm charts when the underlying values change
    helm_values_yaml = join("---\n", [
      local.desired_cni_values
    ])
    # Redeploy when versions of addons need to be updated
    versions = join("\n", [
      coalesce(local.desired_cni_version, "N/A"),
    ])
    encryption = sha1(local.secrets_encryption_config)
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

  # Create /var/lib/rancher/rke2/server/manifests directory
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /var/lib/rancher/rke2/server/manifests/",
    ]
  }

  # Generating rke2 master config file
  provisioner "file" {
    content = yamlencode(
      merge(
        {
          node-name                   = module.control_planes[keys(module.control_planes)[0]].name
          token                       = local.cluster_token
          disable-cloud-controller    = true
          disable-kube-proxy          = !var.enable_kube_proxy
          disable                     = local.disable_rke2_extras
          kubelet-arg                 = concat(local.kubelet_arg, var.global_kubelet_args, var.control_plane_kubelet_args, local.control_plane_nodes[keys(module.control_planes)[0]].kubelet_args)
          kube-apiserver-arg          = concat(local.kube_apiserver_arg, var.enable_secrets_encryption ? ["encryption-provider-config=${local.secrets_encryption_config_file}"] : [])
          kube-controller-manager-arg = local.kube_controller_manager_arg
          node-ip                     = module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
          advertise-address           = module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
          node-taint                  = local.control_plane_nodes[keys(module.control_planes)[0]].taints
          node-label                  = local.control_plane_nodes[keys(module.control_planes)[0]].labels
          write-kubeconfig-mode       = "0644" # needed for import into rancher
          selinux                     = false
          cluster-cidr                = local.cluster_cidr
          service-cidr                = local.service_cidr
          cluster-dns                 = local.cluster_dns
          cni                         = local.rke2_cni
        },
        local.multinetwork_overlay_enabled ? {
          node-external-ip = join(",", compact([local.multinetwork_transport_ipv4_enabled ? module.control_planes[keys(module.control_planes)[0]].ipv4_address : null, local.multinetwork_transport_ipv6_enabled ? module.control_planes[keys(module.control_planes)[0]].ipv6_address : null]))
        } : {},
        var.enable_control_plane_load_balancer ? {
          tls-san = concat(
            compact([
              hcloud_load_balancer.control_plane.*.ipv4[0],
              hcloud_load_balancer_network.control_plane.*.ip[0],
              local.kubeconfig_server_address != "" ? local.kubeconfig_server_address : null,
              local.control_plane_endpoint_host,
              !var.control_plane_load_balancer_enable_public_network && var.nat_router != null ? hcloud_server.nat_router[0].ipv4_address : null
            ]),
            var.additional_tls_sans
          )
          } : {
          tls-san = concat(
            compact([
              module.control_planes[keys(module.control_planes)[0]].private_ipv4_address != "" ? module.control_planes[keys(module.control_planes)[0]].private_ipv4_address : null,
              module.control_planes[keys(module.control_planes)[0]].ipv4_address != "" ? module.control_planes[keys(module.control_planes)[0]].ipv4_address : null,
              module.control_planes[keys(module.control_planes)[0]].ipv6_address != "" ? module.control_planes[keys(module.control_planes)[0]].ipv6_address : null,
              local.control_plane_endpoint_host,
              local.kubeconfig_server_address != "" ? local.kubeconfig_server_address : null,
              try(one(module.control_planes[keys(module.control_planes)[0]].network).ip, null)
            ]),
            var.additional_tls_sans
          )
        },
        local.etcd_s3_snapshots,
        var.control_planes_custom_config,
        (!var.enable_selinux ? { selinux = false } : (local.control_plane_nodes[keys(module.control_planes)[0]].selinux == true ? { selinux = true } : {})),
        local.prefer_bundled_bin_config
      )
    )

    destination = "/tmp/config.yaml"
  }

  provisioner "file" {
    content     = local.secrets_encryption_config
    destination = "/tmp/encryption-config.yaml"
  }

  # Upload the CNI install file.
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/${local.rke2_manifest_cni_plugin}.yaml.tpl",
      {
        values  = local.rke2_manifest_cni_plugin == "cilium" ? indent(4, trimspace(local.desired_cni_values)) : ""
        version = local.desired_cni_version
    })
    destination = "/var/lib/rancher/rke2/server/manifests/${local.rke2_manifest_cni_plugin}.yaml"
  }

  # Upload bundled RKE2 CNI HelmChartConfig overrides.
  provisioner "file" {
    content     = local.rke2_cni_config_manifest
    destination = "/var/lib/rancher/rke2/server/manifests/kube-hetzner-rke2-cni-config.yaml"
  }
}

resource "terraform_data" "first_control_plane_rke2" {
  count = local.kubernetes_distribution == "rke2" ? 1 : 0

  triggers_replace = {
    control_plane_id = module.control_planes[keys(module.control_planes)[0]].id
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
    content     = var.authentication_config
    destination = "/tmp/authentication_config.yaml"
  }

  provisioner "file" {
    content     = var.audit_policy_config
    destination = "/tmp/audit-policy.yaml"
  }

  # Install rke2 server
  provisioner "remote-exec" {
    inline = concat(local.k8s_install_network_env_by_control_plane[keys(module.control_planes)[0]], local.install_k8s_server)
  }

  # Upon reboot start k3s and wait for it to be ready to receive commands
  provisioner "remote-exec" {
    inline = [
      local.bootstrap_control_plane_api_config_script,
      # "systemctl enable rke2-server",
      "systemctl enable --now iscsid",
      "systemctl start rke2-server",
      # prepare the needed directories
      "mkdir -p /var/post_install /var/user_kustomize",
      # wait for rke2-server to become ready
      <<-EOT
      timeout 120 bash <<EOF
        until systemctl status rke2-server > /dev/null; do
          systemctl start rke2-server
          echo "Waiting for the rke2-server server to start..."
          sleep 2
        done
        until [ -e /etc/rancher/rke2/rke2.yaml ]; do
          echo "Waiting for kubectl config..."
          sleep 2
        done
        until [[ "\$(${local.kubectl_cli} get --raw='/readyz' 2> /dev/null)" == "ok" ]]; do
          echo "Waiting for the cluster to become ready..."
          sleep 2
        done
      EOF
      EOT
    ]
  }

  depends_on = [
    hcloud_network_subnet.control_plane,
    terraform_data.control_plane_setup_rke2,
  ]
}
moved {
  from = null_resource.control_plane_setup_rke2
  to   = terraform_data.control_plane_setup_rke2
}

moved {
  from = null_resource.first_control_plane_rke2
  to   = terraform_data.first_control_plane_rke2
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
        if [ "$(${local.kubectl_cli} get --raw='/readyz' 2>/dev/null)" = "ok" ]; then
          echo "kubectl connectivity established, deploying secrets..."

          ${local.kubectl_cli} apply -f /var/post_install/kube_system_secrets.yaml

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
    terraform_data.control_planes_rke2,
  ]
}
moved {
  from = null_resource.kube_system_secrets
  to   = terraform_data.kube_system_secrets
}

# This is where all the setup of Kubernetes components happen
resource "terraform_data" "kustomization" {
  count = local.kubernetes_distribution == "k3s" ? 1 : 0
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
      coalesce(var.k3s_channel, "N/A"),
      coalesce(var.k3s_version, "N/A"),
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
      coalesce(var.system_upgrade_controller_version, "N/A"),
    ])
    options = join("\n", [
      for option, value in local.kured_options : "${option}=${value}"
    ])
    cilium_egress_gateway_ha       = var.cilium_egress_gateway_ha_enabled
    system_upgrade_schedule_window = jsonencode(var.system_upgrade_schedule_window)
    system_upgrade_use_drain       = tostring(var.system_upgrade_use_drain)
    system_upgrade_enable_eviction = tostring(var.system_upgrade_enable_eviction)
    rendered_addons_sha = sha256(join("\n---kube-hetzner---\n", compact([
      local.kustomization_backup_yaml,
      data.http.kured_manifest.response_body,
      data.http.system_upgrade_controller_manifest.response_body,
      data.http.system_upgrade_controller_crd.response_body,
      templatefile(
        "${path.module}/templates/traefik_ingress.yaml.tpl",
        {
          version          = var.traefik_version
          values           = indent(4, local.traefik_values)
          target_namespace = local.ingress_controller_namespace
        }
      ),
      templatefile(
        "${path.module}/templates/nginx_ingress.yaml.tpl",
        {
          version          = var.nginx_version
          values           = indent(4, local.nginx_values)
          target_namespace = local.ingress_controller_namespace
        }
      ),
      templatefile(
        "${path.module}/templates/haproxy_ingress.yaml.tpl",
        {
          version          = var.haproxy_version
          values           = indent(4, local.haproxy_values)
          target_namespace = local.ingress_controller_namespace
        }
      ),
      templatefile(
        "${path.module}/templates/hcloud-ccm-helm.yaml.tpl",
        {
          values              = indent(4, local.hetzner_ccm_values)
          version             = coalesce(local.ccm_version, "*")
          using_klipper_lb    = local.using_klipper_lb
          default_lb_location = var.load_balancer_location
        }
      ),
      var.enable_load_balancer_monitoring ? templatefile(
        "${path.module}/templates/load_balancer_monitoring.yaml.tpl",
        {}
      ) : "",
      templatefile(
        "${path.module}/templates/calico.yaml.tpl",
        {
          values = local.calico_values
        }
      ),
      templatefile(
        "${path.module}/templates/cilium.yaml.tpl",
        {
          values  = indent(4, local.cilium_values)
          version = var.cilium_version
        }
      ),
      templatefile(
        "${path.module}/templates/cilium_egress_gateway_ha.yaml.tpl",
        {}
      ),
      templatefile(
        "${path.module}/templates/plans.yaml.tpl",
        {
          channel          = var.k3s_channel
          version          = var.k3s_version
          disable_eviction = !var.system_upgrade_enable_eviction
          drain            = var.system_upgrade_use_drain
          upgrade_window   = var.system_upgrade_schedule_window
        }
      ),
      templatefile(
        "${path.module}/templates/longhorn.yaml.tpl",
        {
          longhorn_namespace  = var.longhorn_namespace
          longhorn_repository = var.longhorn_repository
          version             = var.longhorn_version
          bootstrap           = var.longhorn_helmchart_bootstrap
          values              = indent(4, local.longhorn_values)
        }
      ),
      var.enable_hetzner_csi ? templatefile(
        "${path.module}/templates/hcloud-csi.yaml.tpl",
        {
          version = coalesce(local.csi_version, "*")
          values  = indent(4, local.hetzner_csi_values)
        }
      ) : "",
      templatefile(
        "${path.module}/templates/csi-driver-smb.yaml.tpl",
        {
          version   = var.csi_driver_smb_version
          bootstrap = var.csi_driver_smb_helmchart_bootstrap
          values    = indent(4, local.csi_driver_smb_values)
        }
      ),
      templatefile(
        "${path.module}/templates/cert_manager.yaml.tpl",
        {
          version   = var.cert_manager_version
          bootstrap = var.cert_manager_helmchart_bootstrap
          values    = indent(4, local.cert_manager_values)
        }
      ),
      templatefile(
        "${path.module}/templates/rancher.yaml.tpl",
        {
          rancher_install_channel = var.rancher_install_channel
          version                 = var.rancher_version
          bootstrap               = var.rancher_helmchart_bootstrap
          values                  = indent(4, local.rancher_values)
        }
      ),
      templatefile(
        "${path.module}/templates/kured.yaml.tpl",
        {
          options = local.kured_options
        }
      ),
    ])))
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

  # Upload remote addon manifests as local kustomize resources to avoid release-asset fetch issues on the control plane.
  provisioner "file" {
    content     = data.http.kured_manifest.response_body
    destination = "/var/post_install/kured-base.yaml"
  }

  provisioner "file" {
    content     = data.http.system_upgrade_controller_manifest.response_body
    destination = "/var/post_install/system-upgrade-controller.yaml"
  }

  provisioner "file" {
    content     = data.http.system_upgrade_controller_crd.response_body
    destination = "/var/post_install/system-upgrade-controller-crd.yaml"
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

  # Upload the Hetzner CCM HelmChart manifest.
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/hcloud-ccm-helm.yaml.tpl",
      {
        values              = indent(4, local.hetzner_ccm_values)
        version             = coalesce(local.ccm_version, "*")
        using_klipper_lb    = local.using_klipper_lb
        default_lb_location = var.load_balancer_location
      }
    )
    destination = "/var/post_install/hcloud-ccm-helm.yaml"
  }

  # Upload optional load balancer monitoring resources for Hetzner CCM
  provisioner "file" {
    content = var.enable_load_balancer_monitoring ? templatefile(
      "${path.module}/templates/load_balancer_monitoring.yaml.tpl",
      {}
    ) : ""
    destination = "/var/post_install/load_balancer_monitoring.yaml"
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

  # Upload the optional Cilium egress gateway HA controller
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/cilium_egress_gateway_ha.yaml.tpl",
      {}
    )
    destination = "/var/post_install/cilium_egress_gateway_ha.yaml"
  }

  # Upload the system upgrade controller plans config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/plans.yaml.tpl",
      {
        channel          = var.k3s_channel
        version          = var.k3s_version
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
    content = var.enable_hetzner_csi ? templatefile(
      "${path.module}/templates/hcloud-csi.yaml.tpl",
      {
        version = coalesce(local.csi_version, "*")
        values  = indent(4, local.hetzner_csi_values)
      }
    ) : ""
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
      local.cluster_has_ipv6 ? [] : [
        replace(local.ipv4_only_coredns_aaaa_filter_script, "__KUBECTL__", "kubectl")
      ],
      [
        "echo 'Remove legacy ccm manifests if they exist'",
        replace(local.legacy_hetzner_ccm_cleanup_script, "__KUBECTL__", "kubectl"),
      ],
      compact([
        var.ingress_controller == "traefik" ? "" : "kubectl delete helmchart -n kube-system traefik --ignore-not-found",
        var.ingress_controller == "nginx" ? "" : "kubectl delete helmchart -n kube-system nginx --ignore-not-found",
        var.ingress_controller == "haproxy" ? "" : "kubectl delete helmchart -n kube-system haproxy --ignore-not-found",
      ]),
      [
        # Ready, set, go for the kustomization
        "kubectl apply -k /var/post_install",
      ],
      local.cluster_has_ipv6 ? [] : [
        replace(local.ipv4_only_coredns_aaaa_filter_script, "__KUBECTL__", "kubectl")
      ],
      [
        "echo 'Waiting for the system-upgrade-controller deployment to become available...'",
        "kubectl -n system-upgrade wait --for=condition=available --timeout=900s deployment/system-upgrade-controller",
        "sleep 7", # important as the system upgrade controller CRDs sometimes don't get ready right away, especially with Cilium.
        "kubectl -n system-upgrade apply -f /var/post_install/plans.yaml",
        # Work around stale cainjector leader leases after interrupted cert-manager helm installs.
        "kubectl -n kube-system delete lease cert-manager-cainjector-leader-election --ignore-not-found || true",
        replace(local.post_install_readiness_wait_script, "__KUBECTL__", "kubectl")
      ],
      local.skip_ingress_lb_wait ? [] : [
        <<-EOT
      timeout 360 bash <<EOF
      until [ -n "\$(kubectl get -n ${local.ingress_controller_namespace} service/${lookup(local.ingress_controller_service_names, var.ingress_controller)} --output=jsonpath='{.status.loadBalancer.ingress[0].${var.load_balancer_hostname != "" ? "hostname" : "ip"}}' 2> /dev/null)" ]; do
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
resource "terraform_data" "rke2_kustomization" {
  count = local.kubernetes_distribution == "rke2" ? 1 : 0
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
      coalesce(var.rke2_channel, "N/A"),
      coalesce(var.rke2_version, "N/A"),
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
      coalesce(var.system_upgrade_controller_version, "N/A"),
    ])
    options = join("\n", [
      for option, value in local.kured_options : "${option}=${value}"
    ])
    cilium_egress_gateway_ha       = var.cilium_egress_gateway_ha_enabled
    system_upgrade_schedule_window = jsonencode(var.system_upgrade_schedule_window)
    system_upgrade_use_drain       = tostring(var.system_upgrade_use_drain)
    system_upgrade_enable_eviction = tostring(var.system_upgrade_enable_eviction)
    rendered_addons_sha = sha256(join("\n---kube-hetzner---\n", compact([
      local.kustomization_backup_yaml,
      data.http.kured_manifest.response_body,
      data.http.system_upgrade_controller_manifest.response_body,
      data.http.system_upgrade_controller_crd.response_body,
      templatefile(
        "${path.module}/templates/traefik_ingress.yaml.tpl",
        {
          version          = var.traefik_version
          values           = indent(4, local.traefik_values)
          target_namespace = local.ingress_controller_namespace
        }
      ),
      templatefile(
        "${path.module}/templates/nginx_ingress.yaml.tpl",
        {
          version          = var.nginx_version
          values           = indent(4, local.nginx_values)
          target_namespace = local.ingress_controller_namespace
        }
      ),
      templatefile(
        "${path.module}/templates/haproxy_ingress.yaml.tpl",
        {
          version          = var.haproxy_version
          values           = indent(4, local.haproxy_values)
          target_namespace = local.ingress_controller_namespace
        }
      ),
      templatefile(
        "${path.module}/templates/hcloud-ccm-helm.yaml.tpl",
        {
          values              = indent(4, local.hetzner_ccm_values)
          version             = coalesce(local.ccm_version, "*")
          using_klipper_lb    = local.using_klipper_lb
          default_lb_location = var.load_balancer_location
        }
      ),
      var.enable_load_balancer_monitoring ? templatefile(
        "${path.module}/templates/load_balancer_monitoring.yaml.tpl",
        {}
      ) : "",
      templatefile(
        "${path.module}/templates/calico.yaml.tpl",
        {
          values = local.calico_values
        }
      ),
      templatefile(
        "${path.module}/templates/cilium.yaml.tpl",
        {
          values  = indent(4, local.cilium_values)
          version = var.cilium_version
        }
      ),
      templatefile(
        "${path.module}/templates/cilium_egress_gateway_ha.yaml.tpl",
        {}
      ),
      templatefile(
        "${path.module}/templates/plans_rke2.yaml.tpl",
        {
          channel          = var.rke2_channel
          version          = var.rke2_version
          disable_eviction = !var.system_upgrade_enable_eviction
          drain            = var.system_upgrade_use_drain
          upgrade_window   = var.system_upgrade_schedule_window
        }
      ),
      templatefile(
        "${path.module}/templates/longhorn.yaml.tpl",
        {
          longhorn_namespace  = var.longhorn_namespace
          longhorn_repository = var.longhorn_repository
          version             = var.longhorn_version
          bootstrap           = var.longhorn_helmchart_bootstrap
          values              = indent(4, local.longhorn_values)
        }
      ),
      var.enable_hetzner_csi ? templatefile(
        "${path.module}/templates/hcloud-csi.yaml.tpl",
        {
          version = coalesce(local.csi_version, "*")
          values  = indent(4, local.hetzner_csi_values)
        }
      ) : "",
      templatefile(
        "${path.module}/templates/csi-driver-smb.yaml.tpl",
        {
          version   = var.csi_driver_smb_version
          bootstrap = var.csi_driver_smb_helmchart_bootstrap
          values    = indent(4, local.csi_driver_smb_values)
        }
      ),
      templatefile(
        "${path.module}/templates/cert_manager.yaml.tpl",
        {
          version   = var.cert_manager_version
          bootstrap = var.cert_manager_helmchart_bootstrap
          values    = indent(4, local.cert_manager_values)
        }
      ),
      templatefile(
        "${path.module}/templates/rancher.yaml.tpl",
        {
          rancher_install_channel = var.rancher_install_channel
          version                 = var.rancher_version
          bootstrap               = var.rancher_helmchart_bootstrap
          values                  = indent(4, local.rancher_values)
        }
      ),
      templatefile(
        "${path.module}/templates/kured.yaml.tpl",
        {
          options = local.kured_options
        }
      ),
    ])))
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

  # Upload kustomization.yaml, containing Hetzner CSI & CSM, as well as kured.
  provisioner "file" {
    content     = local.kustomization_backup_yaml
    destination = "/var/post_install/kustomization.yaml"
  }

  # Upload remote addon manifests as local kustomize resources to avoid release-asset fetch issues on the control plane.
  provisioner "file" {
    content     = data.http.kured_manifest.response_body
    destination = "/var/post_install/kured-base.yaml"
  }

  provisioner "file" {
    content     = data.http.system_upgrade_controller_manifest.response_body
    destination = "/var/post_install/system-upgrade-controller.yaml"
  }

  provisioner "file" {
    content     = data.http.system_upgrade_controller_crd.response_body
    destination = "/var/post_install/system-upgrade-controller-crd.yaml"
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

  # Upload the Hetzner CCM HelmChart manifest.
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/hcloud-ccm-helm.yaml.tpl",
      {
        values              = indent(4, local.hetzner_ccm_values)
        version             = coalesce(local.ccm_version, "*")
        using_klipper_lb    = local.using_klipper_lb
        default_lb_location = var.load_balancer_location

      }
    )
    destination = "/var/post_install/hcloud-ccm-helm.yaml"
  }

  # Upload optional load balancer monitoring resources for Hetzner CCM
  provisioner "file" {
    content = var.enable_load_balancer_monitoring ? templatefile(
      "${path.module}/templates/load_balancer_monitoring.yaml.tpl",
      {}
    ) : ""
    destination = "/var/post_install/load_balancer_monitoring.yaml"
  }

  # Upload the k3s Calico kustomization patch. RKE2 CNI manifests are handled
  # separately through /var/lib/rancher/rke2/server/manifests.
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/calico.yaml.tpl",
      {
        values = local.calico_values
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
    destination = "/tmp/rke2-cilium-config.yaml"
  }

  # Upload the optional Cilium egress gateway HA controller
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/cilium_egress_gateway_ha.yaml.tpl",
      {}
    )
    destination = "/var/post_install/cilium_egress_gateway_ha.yaml"
  }

  # Upload the system upgrade controller plans config
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/plans_rke2.yaml.tpl",
      {
        channel          = var.rke2_channel
        version          = var.rke2_version
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
    content = var.enable_hetzner_csi ? templatefile(
      "${path.module}/templates/hcloud-csi.yaml.tpl",
      {
        version = coalesce(local.csi_version, "*")
        values  = indent(4, local.hetzner_csi_values)
      }
    ) : ""
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
      # the cluster had become unavailable for a few seconds, at this very instant.
      <<-EOT
      timeout 360 bash <<EOF
        until [[ "\$(${local.kubectl_cli} get --raw='/readyz' 2> /dev/null)" == "ok" ]]; do
          echo "Waiting for the cluster to become ready..."
          sleep 2
        done
      EOF
      EOT
      ]
      ,
      local.cluster_has_ipv6 ? [] : [
        replace(local.ipv4_only_coredns_aaaa_filter_script, "__KUBECTL__", local.kubectl_cli)
      ],
      [
        "echo 'Remove legacy ccm manifests if they exist'",
        replace(local.legacy_hetzner_ccm_cleanup_script, "__KUBECTL__", local.kubectl_cli),
      ],
      compact([
        var.ingress_controller == "traefik" ? "" : "${local.kubectl_cli} delete helmchart -n kube-system traefik --ignore-not-found",
        var.ingress_controller == "nginx" ? "" : "${local.kubectl_cli} delete helmchart -n kube-system nginx --ignore-not-found",
        var.ingress_controller == "haproxy" ? "" : "${local.kubectl_cli} delete helmchart -n kube-system haproxy --ignore-not-found",
      ]),
      [
        # Ready, set, go for the kustomization
        "echo 'Deploying the kustomization.yaml...'",
        "echo 'Applying everything in /var/post_install...'",
        "${local.kubectl_cli} apply -k /var/post_install",
      ],
      local.cluster_has_ipv6 ? [] : [
        replace(local.ipv4_only_coredns_aaaa_filter_script, "__KUBECTL__", local.kubectl_cli)
      ],
      [
        # Work around stale cainjector leader leases after interrupted cert-manager helm installs.
        "${local.kubectl_cli} -n kube-system delete lease cert-manager-cainjector-leader-election --ignore-not-found || true",
        "echo 'Waiting for the system-upgrade-controller deployment to become available...'",
        "${local.kubectl_cli} -n system-upgrade wait --for=condition=available --timeout=360s deployment/system-upgrade-controller",
        "sleep 7", # important as the system upgrade controller CRDs sometimes don't get ready right away, especially with Cilium.
        "${local.kubectl_cli} -n system-upgrade apply -f /var/post_install/plans.yaml",
        replace(local.post_install_readiness_wait_script, "__KUBECTL__", local.kubectl_cli)
      ],
      local.skip_ingress_lb_wait ? [] : [
        <<-EOT
      timeout 360 bash <<EOF
      until [ -n "\$(${local.kubectl_cli} get -n ${local.ingress_controller_namespace} service/${lookup(local.ingress_controller_service_names, var.ingress_controller)} --output=jsonpath='{.status.loadBalancer.ingress[0].${var.load_balancer_hostname != "" ? "hostname" : "ip"}}' 2> /dev/null)" ]; do
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
    terraform_data.control_planes_rke2,
    random_password.rancher_bootstrap,
    hcloud_volume.longhorn_volume,
    terraform_data.kube_system_secrets
  ]
}
moved {
  from = null_resource.rke2_kustomization
  to   = terraform_data.rke2_kustomization
}

moved {
  from = null_resource.kustomization
  to   = terraform_data.kustomization
}

moved {
  from = terraform_data.kustomization
  to   = terraform_data.kustomization[0]
}
