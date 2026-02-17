module "control_planes" {
  source = "./modules/host"

  providers = {
    hcloud = hcloud,
  }

  for_each = local.control_plane_nodes

  name                             = "${var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""}${each.value.nodepool_name}"
  connection_host                  = lookup(var.node_connection_overrides, "${var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""}${each.value.nodepool_name}", "")
  os_snapshot_id                   = local.snapshot_id_by_os[each.value.os][substr(each.value.server_type, 0, 3) == "cax" ? "arm" : "x86"]
  os                               = each.value.os
  base_domain                      = var.base_domain
  ssh_keys                         = length(var.ssh_hcloud_key_label) > 0 ? concat([local.hcloud_ssh_key_id], data.hcloud_ssh_keys.keys_by_selector[0].ssh_keys.*.id) : [local.hcloud_ssh_key_id]
  ssh_port                         = var.ssh_port
  ssh_public_key                   = var.ssh_public_key
  ssh_private_key                  = var.ssh_private_key
  ssh_additional_public_keys       = length(var.ssh_hcloud_key_label) > 0 ? concat(var.ssh_additional_public_keys, data.hcloud_ssh_keys.keys_by_selector[0].ssh_keys.*.public_key) : var.ssh_additional_public_keys
  firewall_ids                     = each.value.disable_ipv4 && each.value.disable_ipv6 ? [] : [hcloud_firewall.k3s.id] # Cannot attach a firewall when public interfaces are disabled
  placement_group_id               = var.placement_group_disable ? null : (each.value.placement_group == null ? hcloud_placement_group.control_plane[each.value.placement_group_compat_idx].id : hcloud_placement_group.control_plane_named[each.value.placement_group].id)
  location                         = each.value.location
  server_type                      = each.value.server_type
  backups                          = each.value.backups
  ipv4_subnet_id                   = hcloud_network_subnet.control_plane[[for i, v in var.control_plane_nodepools : i if v.name == each.value.nodepool_name][0]].id
  dns_servers                      = var.dns_servers
  k3s_registries                   = var.k3s_registries
  k3s_registries_update_script     = local.k3s_registries_update_script
  k3s_kubelet_config               = var.k3s_kubelet_config
  k3s_kubelet_config_update_script = local.k3s_kubelet_config_update_script
  k3s_audit_policy_config          = var.k3s_audit_policy_config
  k3s_audit_policy_update_script   = local.k3s_audit_policy_update_script
  cloudinit_write_files_common     = local.cloudinit_write_files_common
  cloudinit_runcmd_common          = local.cloudinit_runcmd_common
  cloudinit_write_files_extra      = each.value.extra_write_files
  cloudinit_runcmd_extra           = each.value.extra_runcmd
  swap_size                        = each.value.swap_size
  zram_size                        = each.value.zram_size
  keep_disk_size                   = var.keep_disk_cp
  timeouts                         = var.timeouts
  disable_ipv4                     = each.value.disable_ipv4
  disable_ipv6                     = each.value.disable_ipv6
  ssh_bastion                      = local.ssh_bastion
  network_id                       = data.hcloud_network.k3s.id

  # We leave some room so 100 eventual Hetzner LBs that can be created perfectly safely
  # It leaves the subnet with 254 x 254 - 100 = 64416 IPs to use, so probably enough.
  private_ipv4 = cidrhost(hcloud_network_subnet.control_plane[[for i, v in var.control_plane_nodepools : i if v.name == each.value.nodepool_name][0]].ip_range, each.value.index + (local.network_size >= 16 ? 101 : floor(pow(local.subnet_size, 2) * 0.4)))

  labels = merge(local.labels, local.labels_control_plane_node, { "kube-hetzner/os" = each.value.os })

  automatically_upgrade_os = var.automatically_upgrade_os

  network_gw_ipv4 = local.network_gw_ipv4

  depends_on = [
    hcloud_network_subnet.control_plane,
    hcloud_placement_group.control_plane,
    hcloud_server.nat_router,
    terraform_data.nat_router_await_cloud_init,
  ]
}

resource "hcloud_load_balancer" "control_plane" {
  count = var.use_control_plane_lb ? 1 : 0
  name  = "${var.cluster_name}-control-plane"

  load_balancer_type = var.control_plane_lb_type
  location           = var.load_balancer_location
  labels             = merge(local.labels, local.labels_control_plane_lb)
  delete_protection  = var.enable_delete_protection.load_balancer

  lifecycle {
    ignore_changes = [location]
  }
}

resource "hcloud_load_balancer_network" "control_plane" {
  count = var.use_control_plane_lb ? 1 : 0

  load_balancer_id        = hcloud_load_balancer.control_plane.*.id[0]
  subnet_id               = hcloud_network_subnet.control_plane.*.id[0]
  enable_public_interface = var.control_plane_lb_enable_public_interface
  ip                      = cidrhost(hcloud_network_subnet.control_plane.*.ip_range[0], -2)

  # Keep existing LB IPs stable on upgrade.
  lifecycle {
    ignore_changes = [ip]
  }
}

resource "hcloud_load_balancer_target" "control_plane" {
  count = var.use_control_plane_lb ? 1 : 0

  depends_on       = [hcloud_load_balancer_network.control_plane]
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.control_plane.*.id[0]
  label_selector   = join(",", [for k, v in merge(local.labels, local.labels_control_plane_node) : "${k}=${v}"])
  use_private_ip   = true
}

# TODO: Adjust me for RKE2
resource "hcloud_load_balancer_service" "control_plane" {
  count = var.use_control_plane_lb ? 1 : 0

  load_balancer_id = hcloud_load_balancer.control_plane.*.id[0]
  protocol         = "tcp"
  destination_port = "6443"
  listen_port      = "6443"
}

locals {
  control_plane_endpoint_host = var.control_plane_endpoint != null ? one(compact(regexall("^(?:https?://)?(?:.*@)?(?:\\[([a-fA-F0-9:]+)\\]|([^:/?#]+))", var.control_plane_endpoint)[0])) : null

  control_plane_ips = {
    for k, v in module.control_planes : k => coalesce(
      lookup(var.node_connection_overrides, v.name, null),
      v.ipv4_address,
      v.ipv6_address,
      v.private_ipv4_address
    )
  }
  # TODO: What about this?
  # cni_settings = local.kubernetes_distribution == "k3s" ? local.cni_k3s_settings : local.cni_rke2_settings
  rke2-config = { for k, v in local.control_plane_nodes : k => merge(
    {
      node-name = module.control_planes[k].name
      server = (
        length(module.control_planes) == 1 ? null :
        module.control_planes[k].private_ipv4_address == module.control_planes[keys(module.control_planes)[0]].private_ipv4_address ? null :
        "https://${var.use_control_plane_lb ? hcloud_load_balancer_network.control_plane.*.ip[0] : module.control_planes[keys(module.control_planes)[0]].private_ipv4_address}:9345"
      )
      token                       = local.k3s_token
      disable-cloud-controller    = true
      disable-kube-proxy          = var.disable_kube_proxy
      disable                     = local.disable_rke2_extras
      kubelet-arg                 = concat(local.kubelet_arg, var.k3s_global_kubelet_args, var.k3s_control_plane_kubelet_args, v.kubelet_args)
      kube-apiserver-arg          = local.kube_apiserver_arg
      kube-controller-manager-arg = local.kube_controller_manager_arg
      node-ip                     = module.control_planes[k].private_ipv4_address
      advertise-address           = module.control_planes[k].private_ipv4_address
      node-label                  = v.labels
      node-taint                  = v.taints
      # TODO: Fix this, currently it needs to be false
      # selinux                     = var.disable_selinux ? false : (v.selinux == true ? true : false)
      selinux               = false
      cluster-cidr          = var.cluster_ipv4_cidr
      service-cidr          = var.service_ipv4_cidr
      cluster-dns           = local.cluster_dns_ipv4
      write-kubeconfig-mode = "0644" # needed for import into rancher
      cni                   = "none"
    },
    var.use_control_plane_lb ? {
      tls-san = concat([
        hcloud_load_balancer.control_plane.*.ipv4[0],
        hcloud_load_balancer_network.control_plane.*.ip[0],
        var.kubeconfig_server_address != "" ? var.kubeconfig_server_address : null
      ], var.additional_tls_sans)
      } : {
      tls-san = concat(
        compact([
          module.control_planes[keys(module.control_planes)[0]].private_ipv4_address != "" ? module.control_planes[keys(module.control_planes)[0]].private_ipv4_address : null,
          module.control_planes[k].ipv4_address != "" ? module.control_planes[k].ipv4_address : null,
          module.control_planes[k].ipv6_address != "" ? module.control_planes[k].ipv6_address : null,
          try(one(module.control_planes[k].network).ip, null)
        ]),
      var.additional_tls_sans)
    },
    local.etcd_s3_snapshots,
    var.control_planes_custom_config
  ) }

  k3s-config = { for k, v in local.control_plane_nodes : k => merge(
    {
      node-name = module.control_planes[k].name
      server = length(module.control_planes) == 1 ? null : coalesce(
        var.control_plane_endpoint,
        "https://${
          var.use_control_plane_lb ? hcloud_load_balancer_network.control_plane.*.ip[0] :
          (
            module.control_planes[k].private_ipv4_address == module.control_planes[keys(module.control_planes)[0]].private_ipv4_address ?
            module.control_planes[keys(module.control_planes)[1]].private_ipv4_address :
            module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
          )
        }:6443"
      )
      token                    = local.k3s_token
      disable-cloud-controller = true
      disable-kube-proxy       = var.disable_kube_proxy
      disable                  = local.disable_extras
      # Kubelet arg precedence (last wins): local.kubelet_arg > v.kubelet_args > k3s_global_kubelet_args > k3s_control_plane_kubelet_args
      kubelet-arg                 = concat(local.kubelet_arg, v.kubelet_args, var.k3s_global_kubelet_args, var.k3s_control_plane_kubelet_args)
      kube-apiserver-arg          = local.kube_apiserver_arg
      kube-controller-manager-arg = local.kube_controller_manager_arg
      flannel-iface               = local.flannel_iface
      node-ip                     = module.control_planes[k].private_ipv4_address
      advertise-address           = module.control_planes[k].private_ipv4_address
      node-label                  = v.labels
      node-taint                  = v.taints
      selinux                     = var.disable_selinux ? false : (v.selinux == true ? true : false)
      cluster-cidr                = var.cluster_ipv4_cidr
      service-cidr                = var.service_ipv4_cidr
      cluster-dns                 = local.cluster_dns_ipv4
      write-kubeconfig-mode       = "0644" # needed for import into rancher
    },
    lookup(local.cni_k3s_settings, var.cni_plugin, {}),
    var.use_control_plane_lb ? {
      tls-san = concat(
        compact([
          hcloud_load_balancer.control_plane.*.ipv4[0],
          hcloud_load_balancer_network.control_plane.*.ip[0],
          var.kubeconfig_server_address != "" ? var.kubeconfig_server_address : null,
          local.control_plane_endpoint_host,
          !var.control_plane_lb_enable_public_interface && var.nat_router != null ? hcloud_server.nat_router[0].ipv4_address : null
        ]),
        var.additional_tls_sans
      )
      } : {
      tls-san = concat(
        compact([
          local.control_plane_endpoint_host,
          module.control_planes[k].ipv4_address != "" ? module.control_planes[k].ipv4_address : null,
          module.control_planes[k].ipv6_address != "" ? module.control_planes[k].ipv6_address : null,
          var.kubeconfig_server_address != "" ? var.kubeconfig_server_address : null,
          try(one(module.control_planes[k].network).ip, null)
        ]),
      var.additional_tls_sans)
    },
    local.etcd_s3_snapshots,
    var.control_planes_custom_config,
    local.prefer_bundled_bin_config
  ) }
}

resource "null_resource" "control_plane_config_rke2" {
  for_each = local.kubernetes_distribution == "rke2" ? local.control_plane_nodes : {}

  triggers = {
    control_plane_id = module.control_planes[each.key].id
    config           = sha1(yamlencode(local.rke2-config[each.key]))
    cni_values       = sha1(local.desired_cni_values)
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.control_plane_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  # Generating k8s server config file
  provisioner "file" {
    content     = yamlencode(local.rke2-config[each.key])
    destination = "/tmp/config.yaml"
  }

  # Create /var/lib/rancher/rke2/server/manifests directory
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /var/lib/rancher/rke2/server/manifests/",
    ]
  }

  # Upload the cilium install file
  provisioner "file" {
    content = templatefile(
      "${path.module}/templates/${var.cni_plugin}.yaml.tpl",
      {
        values  = indent(4, trimspace(local.desired_cni_values))
        version = local.desired_cni_version
    })
    destination = "/var/lib/rancher/rke2/server/manifests/${var.cni_plugin}.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k8s_config_update_script]
  }

  depends_on = [
    null_resource.first_control_plane_rke2,
    hcloud_network_subnet.control_plane
  ]
}

resource "terraform_data" "control_plane_config" {
  for_each = local.kubernetes_distribution == "k3s" ? local.control_plane_nodes : {}

  triggers_replace = {
    control_plane_id = module.control_planes[each.key].id
    config           = sha1(yamlencode(local.k3s-config[each.key]))
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.control_plane_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Generating k8s server config file
  provisioner "file" {
    content     = yamlencode(local.k3s-config[each.key])
    destination = "/tmp/config.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k3s_config_update_script]
  }

  depends_on = [
    terraform_data.first_control_plane,
    hcloud_network_subnet.control_plane
  ]
}
moved {
  from = null_resource.control_plane_config
  to   = terraform_data.control_plane_config
}

resource "terraform_data" "audit_policy" {
  for_each = local.control_plane_nodes

  triggers_replace = {
    control_plane_id = module.control_planes[each.key].id
    audit_policy     = sha1(var.k3s_audit_policy_config)
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.control_plane_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  provisioner "file" {
    content     = var.k3s_audit_policy_config
    destination = "/tmp/audit-policy.yaml"
  }

  provisioner "remote-exec" {
    inline = [local.k3s_audit_policy_update_script]
  }

  depends_on = [
    terraform_data.first_control_plane,
    hcloud_network_subnet.control_plane
  ]
}
moved {
  from = null_resource.audit_policy
  to   = terraform_data.audit_policy
}

resource "terraform_data" "authentication_config" {
  for_each = local.control_plane_nodes

  triggers_replace = {
    control_plane_id      = module.control_planes[each.key].id
    authentication_config = sha1(var.authentication_config)
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.control_plane_ips[each.key]
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

  provisioner "remote-exec" {
    inline = [local.k8s_authentication_config_update_script]
  }

  depends_on = [
    terraform_data.first_control_plane,
    hcloud_network_subnet.control_plane
  ]
}
moved {
  from = null_resource.authentication_config
  to   = terraform_data.authentication_config
}

resource "null_resource" "control_planes_rke2" {
  for_each = local.kubernetes_distribution == "rke2" ? local.control_plane_nodes : {}

  triggers = {
    control_plane_id = module.control_planes[each.key].id
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.control_plane_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key
  }

  # Install rke2 server
  provisioner "remote-exec" {
    inline = local.install_k8s_server
  }

  # Start the server and wait until it is ready.
  provisioner "remote-exec" {
    inline = [
      "systemctl start rke2-server",
      "systemctl enable rke2-server",
      "mkdir -p /var/post_install /var/user_kustomize",
      <<-EOT
      timeout 360 bash <<EOF
        until systemctl status rke2-server > /dev/null; do
          systemctl start rke2-server
          echo "Waiting for the rke2 server to start..."
          sleep 3
        done
      EOF
      EOT
    ]
  }

  depends_on = [
    null_resource.first_control_plane_rke2,
    null_resource.control_plane_config_rke2,
    terraform_data.authentication_config,
    hcloud_network_subnet.control_plane
  ]
}

resource "terraform_data" "control_planes" {
  for_each = local.kubernetes_distribution == "k3s" ? local.control_plane_nodes : {}

  triggers_replace = {
    control_plane_id = module.control_planes[each.key].id
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.control_plane_ips[each.key]
    port           = var.ssh_port

    bastion_host        = local.ssh_bastion.bastion_host
    bastion_port        = local.ssh_bastion.bastion_port
    bastion_user        = local.ssh_bastion.bastion_user
    bastion_private_key = local.ssh_bastion.bastion_private_key

  }

  # Install k3s server
  provisioner "remote-exec" {
    inline = local.install_k3s_server
  }

  # Start the server and wait until it is ready.
  provisioner "remote-exec" {
    inline = [
      "systemctl start k3s 2> /dev/null",
      "mkdir -p /var/post_install /var/user_kustomize",
      <<-EOT
      timeout 360 bash <<EOF
        until systemctl status k3s > /dev/null; do
          systemctl start k3s 2> /dev/null
          echo "Waiting for the k3s server to start..."
          sleep 3
        done
      EOF
      EOT
    ]
  }

  depends_on = [
    terraform_data.first_control_plane,
    terraform_data.control_plane_config,
    terraform_data.authentication_config,
    hcloud_network_subnet.control_plane
  ]
}
moved {
  from = null_resource.control_planes
  to   = terraform_data.control_planes
}
