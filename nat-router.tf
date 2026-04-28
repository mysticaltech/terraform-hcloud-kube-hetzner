locals {
  nat_gateway_ip = var.nat_router != null ? cidrhost(hcloud_network_subnet.nat_router[0].ip_range, 1) : ""

  nat_router_ip = (
    var.nat_router != null && var.nat_router.enable_redundancy ?
    {
      0 = cidrhost(hcloud_network_subnet.nat_router[0].ip_range, 2),
      1 = cidrhost(hcloud_network_subnet.nat_router[0].ip_range, 3)
    } :
    {
      0 = local.nat_gateway_ip
    }
  )

  nat_router_name_basename = "nat-router"
  nat_router_name          = "${var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""}${local.nat_router_name_basename}"
  nat_router_connection_host = {
    for index in range(var.nat_router != null ? (try(var.nat_router.enable_redundancy, false) ? 2 : 1) : 0) :
    index => var.use_private_nat_router_bastion ? local.nat_router_ip[index] : hcloud_server.nat_router[index].ipv4_address
  }

  nat_router_fail2ban_script = <<-EOT
set -e

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

if ! dpkg -s fail2ban python3-systemd >/dev/null 2>&1; then
  as_root apt-get update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban python3-systemd
fi

as_root mkdir -p /etc/fail2ban/jail.d
as_root tee /etc/fail2ban/jail.d/sshd.local >/dev/null <<'EOF'
[sshd]
enabled = true
port = ${var.ssh_port}
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
maxretry = 5
bantime = 86400
EOF

as_root systemctl enable --now fail2ban
as_root systemctl restart fail2ban
EOT

  nat_router_extra_runcmd_script = <<-EOT
set -e

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    bash -s
  else
    sudo -n bash -s
  fi
}

%{for index, command in try(var.nat_router.extra_runcmd, [])~}
as_root <<'KH_NAT_EXTRA_RUNCMD_${index}'
${command}
KH_NAT_EXTRA_RUNCMD_${index}

%{endfor~}
EOT
}

resource "random_string" "nat_router" {
  count = var.nat_router != null && var.nat_router.enable_redundancy ? 2 : 0

  length  = 3
  lower   = true
  special = false
  numeric = false
  upper   = false

  keepers = {
    # Re-create when the stable name prefix changes.
    name = local.nat_router_name
  }
}

resource "random_password" "nat_router_vip_auth_pass" {
  count   = var.nat_router != null && var.nat_router.enable_redundancy ? 1 : 0
  length  = 8
  special = false
}

data "cloudinit_config" "nat_router_config" {
  count = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/templates/nat-router-cloudinit.yaml.tpl",
      {
        hostname                   = var.nat_router.enable_redundancy ? "nat-router-${count.index}" : "nat-router"
        dns_servers                = var.dns_servers
        has_dns_servers            = local.has_dns_servers
        sshAuthorizedKeys          = local.ssh_authorized_keys
        enable_sudo                = var.nat_router.enable_sudo
        enable_redundancy          = var.nat_router.enable_redundancy
        priority                   = count.index == 0 ? 150 : 100
        my_private_ip              = local.nat_router_ip[count.index]
        peer_private_ip            = var.nat_router.enable_redundancy ? local.nat_router_ip[(count.index == 0 ? 1 : 0)] : null
        hcloud_token               = var.nat_router_hcloud_token
        network_id                 = data.hcloud_network.k3s.id
        vip                        = local.nat_gateway_ip
        vip_auth_pass              = var.nat_router.enable_redundancy ? random_password.nat_router_vip_auth_pass[0].result : ""
        private_network_ipv4_range = data.hcloud_network.k3s.ip_range
        ssh_port                   = var.ssh_port
        ssh_max_auth_tries         = var.ssh_max_auth_tries
        enable_cp_lb_port_forward  = var.enable_control_plane_load_balancer && !var.control_plane_load_balancer_enable_public_network
        cp_lb_private_ip           = try(hcloud_load_balancer_network.control_plane[0].ip, "")
        kubernetes_api_port        = var.kubernetes_api_port
      }
    )
  }
}

resource "terraform_data" "nat_router_connection_contract" {
  count = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  input = {
    ssh_port                = var.ssh_port
    enable_sudo             = var.nat_router.enable_sudo
    ssh_authorized_keys_sha = sha256(join("\n", local.ssh_authorized_keys))
  }
}

resource "hcloud_network_route" "nat_route_public_internet" {
  count       = var.nat_router != null ? 1 : 0
  network_id  = data.hcloud_network.k3s.id
  destination = "0.0.0.0/0"
  gateway     = local.nat_gateway_ip
}

resource "hcloud_primary_ip" "nat_router_primary_ipv4" {
  # explicitly declare the ipv4 address, such that the address
  # is stable against possible replacements of the nat router
  count         = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0
  type          = "ipv4"
  name          = var.nat_router.enable_redundancy ? "${local.nat_router_name}-${random_string.nat_router[count.index].id}-ipv4" : "${var.cluster_name}-nat-router-ipv4"
  location      = var.nat_router.enable_redundancy && count.index == 1 ? var.nat_router.standby_location : var.nat_router.location
  auto_delete   = false
  assignee_type = "server"

  # Prevent recreation when user changes location after initial creation
  lifecycle {
    ignore_changes = [location]
  }
}

resource "hcloud_primary_ip" "nat_router_primary_ipv6" {
  # explicitly declare the ipv6 address, such that the address
  # is stable against possible replacements of the nat router
  count         = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0
  type          = "ipv6"
  name          = var.nat_router.enable_redundancy ? "${local.nat_router_name}-${random_string.nat_router[count.index].id}-ipv6" : "${var.cluster_name}-nat-router-ipv6"
  location      = var.nat_router.enable_redundancy && count.index == 1 ? var.nat_router.standby_location : var.nat_router.location
  auto_delete   = false
  assignee_type = "server"

  # Prevent recreation when user changes location after initial creation
  lifecycle {
    ignore_changes = [location]
  }
}

resource "hcloud_server" "nat_router" {
  count        = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0
  name         = var.nat_router.enable_redundancy ? "${local.nat_router_name}-${random_string.nat_router[count.index].id}" : "${var.cluster_name}-nat-router"
  image        = "debian-12"
  server_type  = var.nat_router.server_type
  location     = var.nat_router.enable_redundancy && count.index == 1 ? var.nat_router.standby_location : var.nat_router.location
  ssh_keys     = length(var.ssh_hcloud_key_label) > 0 ? concat([local.hcloud_ssh_key_id], data.hcloud_ssh_keys.keys_by_selector[0].ssh_keys.*.id) : [local.hcloud_ssh_key_id]
  firewall_ids = [hcloud_firewall.k3s.id]
  user_data    = data.cloudinit_config.nat_router_config[count.index].rendered
  keep_disk    = false
  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.nat_router_primary_ipv4[count.index].id
    ipv6_enabled = true
    ipv6         = hcloud_primary_ip.nat_router_primary_ipv6[count.index].id
  }

  network {
    network_id = data.hcloud_network.k3s.id
    ip         = local.nat_router_ip[count.index]
    alias_ips  = []
  }

  labels = merge(
    {
      role = "nat_router"
    },
    try(var.nat_router.labels, {}),
  )

  lifecycle {
    # Keepalived manages alias IPs during failover.
    # Cloud-init is creation-only; upgrade fixes for existing routers must run through terraform_data provisioners.
    ignore_changes = [image, network, ssh_keys, user_data]
    replace_triggered_by = [
      terraform_data.nat_router_connection_contract[count.index],
    ]
  }

}

resource "hcloud_rdns" "nat_router_primary_ipv4" {
  count = (var.nat_router != null && var.base_domain != "") ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  primary_ip_id = hcloud_primary_ip.nat_router_primary_ipv4[count.index].id
  ip_address    = hcloud_primary_ip.nat_router_primary_ipv4[count.index].ip_address
  dns_ptr       = "${hcloud_server.nat_router[count.index].name}.${var.base_domain}"
}

resource "hcloud_rdns" "nat_router_primary_ipv6" {
  count = (var.nat_router != null && var.base_domain != "") ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  primary_ip_id = hcloud_primary_ip.nat_router_primary_ipv6[count.index].id
  ip_address    = hcloud_primary_ip.nat_router_primary_ipv6[count.index].ip_address
  dns_ptr       = "${hcloud_server.nat_router[count.index].name}.${var.base_domain}"
}

resource "terraform_data" "nat_router_await_cloud_init" {
  count = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  depends_on = [
    hcloud_network_route.nat_route_public_internet,
    hcloud_server.nat_router,
  ]

  triggers_replace = {
    server_id = hcloud_server.nat_router[count.index].id
    config    = data.cloudinit_config.nat_router_config[count.index].rendered
  }

  connection {
    user           = "nat-router"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.nat_router_connection_host[count.index]
    port           = var.ssh_port
  }

  provisioner "remote-exec" {
    inline = ["cloud-init status --wait > /dev/null || echo 'Ready to move on'"]
    # on_failure = continue # this will fail because the reboot 
  }
}
moved {
  from = null_resource.nat_router_await_cloud_init
  to   = terraform_data.nat_router_await_cloud_init
}

resource "terraform_data" "nat_router_config" {
  count = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  depends_on = [
    terraform_data.nat_router_await_cloud_init,
  ]

  triggers_replace = {
    server_id  = hcloud_server.nat_router[count.index].id
    config_sha = sha256(data.cloudinit_config.nat_router_config[count.index].rendered)
  }

  connection {
    user           = var.nat_router.enable_sudo ? "nat-router" : "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.nat_router_connection_host[count.index]
    port           = var.ssh_port
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      set -e

      as_root() {
        if [ "$(id -u)" -eq 0 ]; then
          bash -s
        else
          sudo -n bash -s
        fi
      }

      as_root <<'KH_NAT_RECONCILE'
      set -e

      export DEBIAN_FRONTEND=noninteractive
      if ! dpkg -s fail2ban python3-systemd >/dev/null 2>&1; then
        apt-get update
        apt-get install -y fail2ban python3-systemd
      fi

      mkdir -p /etc/ssh/sshd_config.d
      cat > /etc/ssh/sshd_config.d/kube-hetzner.conf <<'EOF'
      Port ${var.ssh_port}
      PasswordAuthentication no
      X11Forwarding no
      MaxAuthTries ${var.ssh_max_auth_tries}
      AllowTcpForwarding yes
      AllowAgentForwarding yes
      AuthorizedKeysFile .ssh/authorized_keys
      %{if var.nat_router.enable_sudo~}
      PermitRootLogin no
      %{endif~}
      EOF

      %{if local.has_dns_servers~}
      cat > /etc/resolv.conf <<'EOF'
      # Managed by kube-hetzner
      %{for dns_server in var.dns_servers~}
      nameserver ${dns_server}
      %{endfor~}
      EOF
      %{endif~}

      cat > /etc/sysctl.d/99-kube-hetzner-nat-router.conf <<'EOF'
      net.ipv4.ip_forward=1
      EOF
      sysctl -w net.ipv4.ip_forward=1 >/dev/null || true

      if [ -f /etc/network/interfaces ]; then
        sed -i -E \
          -e "\\#iptables -t nat -A POSTROUTING -s '${data.hcloud_network.k3s.ip_range}'#d" \
          -e "/iptables -t nat -A PREROUTING -i eth0 -p tcp --dport [0-9]+ -j DNAT --to-destination/d" \
          -e "/iptables -t nat -A POSTROUTING -d [0-9.]+ -p tcp --dport [0-9]+ -j MASQUERADE/d" \
          /etc/network/interfaces
      fi

      cat > /usr/local/sbin/kube-hetzner-nat-router-rules <<'EOF'
      #!/bin/sh
      set -eu

      PRIVATE_RANGE='${data.hcloud_network.k3s.ip_range}'
      CP_LB_PRIVATE_IP='${try(hcloud_load_balancer_network.control_plane[0].ip, "")}'
      KUBEAPI_PORT='${var.kubernetes_api_port}'
      ENABLE_CP_LB_PORT_FORWARD='${var.enable_control_plane_load_balancer && !var.control_plane_load_balancer_enable_public_network}'

      while iptables -t nat -C POSTROUTING -s "$PRIVATE_RANGE" ! -d "$PRIVATE_RANGE" -o eth0 -j MASQUERADE 2>/dev/null; do
        iptables -t nat -D POSTROUTING -s "$PRIVATE_RANGE" ! -d "$PRIVATE_RANGE" -o eth0 -j MASQUERADE || true
      done

      iptables-save -t nat 2>/dev/null | while IFS= read -r line; do
        case "$line" in
          *"kube-hetzner-masquerade"*|*"kube-hetzner-cp-lb-forward"*|*"kube-hetzner-cp-lb-masquerade"*)
            delete_rule=$(printf '%s\n' "$line" | sed 's/^-A /-D /')
            eval "iptables -t nat $delete_rule" || true
            ;;
          "-A PREROUTING "*"-i eth0 "*"-p tcp "*"--to-destination $CP_LB_PRIVATE_IP:"*)
            [ -n "$CP_LB_PRIVATE_IP" ] || continue
            delete_rule=$(printf '%s\n' "$line" | sed 's/^-A /-D /')
            eval "iptables -t nat $delete_rule" || true
            ;;
          "-A POSTROUTING "*"-d $CP_LB_PRIVATE_IP/"*"-p tcp "*"-j MASQUERADE")
            [ -n "$CP_LB_PRIVATE_IP" ] || continue
            delete_rule=$(printf '%s\n' "$line" | sed 's/^-A /-D /')
            eval "iptables -t nat $delete_rule" || true
            ;;
        esac
      done

      iptables -t nat -C POSTROUTING -s "$PRIVATE_RANGE" ! -d "$PRIVATE_RANGE" -o eth0 -m comment --comment kube-hetzner-masquerade -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -s "$PRIVATE_RANGE" ! -d "$PRIVATE_RANGE" -o eth0 -m comment --comment kube-hetzner-masquerade -j MASQUERADE

      if [ "$ENABLE_CP_LB_PORT_FORWARD" = "true" ] && [ -n "$CP_LB_PRIVATE_IP" ]; then
        iptables -t nat -C PREROUTING -i eth0 -p tcp --dport "$KUBEAPI_PORT" -m comment --comment kube-hetzner-cp-lb-forward -j DNAT --to-destination "$CP_LB_PRIVATE_IP:$KUBEAPI_PORT" 2>/dev/null \
          || iptables -t nat -A PREROUTING -i eth0 -p tcp --dport "$KUBEAPI_PORT" -m comment --comment kube-hetzner-cp-lb-forward -j DNAT --to-destination "$CP_LB_PRIVATE_IP:$KUBEAPI_PORT"
        iptables -t nat -C POSTROUTING -d "$CP_LB_PRIVATE_IP" -p tcp --dport "$KUBEAPI_PORT" -m comment --comment kube-hetzner-cp-lb-masquerade -j MASQUERADE 2>/dev/null \
          || iptables -t nat -A POSTROUTING -d "$CP_LB_PRIVATE_IP" -p tcp --dport "$KUBEAPI_PORT" -m comment --comment kube-hetzner-cp-lb-masquerade -j MASQUERADE
      fi
      EOF
      chmod 0755 /usr/local/sbin/kube-hetzner-nat-router-rules

      mkdir -p /etc/network/if-up.d
      cat > /etc/network/if-up.d/kube-hetzner-nat-router <<'EOF'
      #!/bin/sh
      [ "$${IFACE:-}" = "eth0" ] || exit 0
      /usr/local/sbin/kube-hetzner-nat-router-rules || true
      EOF
      chmod 0755 /etc/network/if-up.d/kube-hetzner-nat-router
      /usr/local/sbin/kube-hetzner-nat-router-rules

      %{if var.nat_router.enable_redundancy~}
      if ! dpkg -s jq keepalived >/dev/null 2>&1; then
        apt-get update
        apt-get install -y jq keepalived
      fi
      id -u keepalived_script >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin keepalived_script

      mkdir -p /etc/keepalived /etc/systemd/system/keepalived.service.d
      cat > /usr/local/bin/wait-for-ip.sh <<'EOF'
      #!/bin/bash
      TARGET_IP="${local.nat_router_ip[count.index]}"

      echo "Waiting for $TARGET_IP to appear on private interface..."
      while true; do
        INTERFACE=$(ip -o -4 addr show | awk -v target_ip="$TARGET_IP" '$4 ~ ("^" target_ip "/") {print $2; exit}')
        if [ -n "$INTERFACE" ]; then
          break
        fi
        sleep 1
      done

      sed "s/__NAT_PRIVATE_IFACE__/$INTERFACE/g" /etc/keepalived/keepalived.conf.tmpl > /etc/keepalived/keepalived.conf
      echo "Private interface is $INTERFACE, keepalived config rendered."
      EOF
      chmod 0700 /usr/local/bin/wait-for-ip.sh

      cat > /etc/systemd/system/wait-for-private-ip.service <<'EOF'
      [Unit]
      Description=Wait for Private Network IP
      After=network.target
      Before=keepalived.service

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/wait-for-ip.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
      EOF

      cat > /etc/systemd/system/keepalived.service.d/override.conf <<'EOF'
      [Unit]
      Requires=wait-for-private-ip.service
      After=wait-for-private-ip.service
      EOF

      cat > /etc/keepalived/keepalived.conf.tmpl <<'EOF'
      global_defs {
          enable_script_security
          script_user keepalived_script
          max_auto_priority
      }

      vrrp_script check_internet {
          script "/usr/local/bin/check_wan.sh"
          interval 2
          fall 3
          rise 3
      }

      vrrp_instance VI_NAT {
          state BACKUP
          interface __NAT_PRIVATE_IFACE__
          virtual_router_id 51
          priority ${count.index == 0 ? 150 : 100}
          advert_int 1
          nopreempt
          unicast_src_ip ${local.nat_router_ip[count.index]}
          unicast_peer {
            ${local.nat_router_ip[count.index == 0 ? 1 : 0]}
          }
          virtual_ipaddress {
            ${local.nat_gateway_ip} dev __NAT_PRIVATE_IFACE__
          }
          authentication {
            auth_type PASS
            auth_pass ${random_password.nat_router_vip_auth_pass[0].result}
          }

          track_script {
            check_internet
          }

          notify_master "/usr/local/bin/hcloud-alias-failover.sh"
      }
      EOF

      cat > /usr/local/bin/check_wan.sh <<'EOF'
      #!/bin/bash

      /usr/bin/ping -W 1 -c 1 8.8.8.8 >/dev/null 2>/dev/null
      GOOGLE_PING=$?
      /usr/bin/ping -W 1 -c 1 1.1.1.1 >/dev/null 2>/dev/null
      CF_PING=$?

      if [ $GOOGLE_PING -ne 0 ] && [ $CF_PING -ne 0 ]
      then
          exit 1
      else
          exit 0
      fi
      EOF
      chown keepalived_script:keepalived_script /usr/local/bin/check_wan.sh
      chmod 0744 /usr/local/bin/check_wan.sh

      cat > /usr/local/bin/hcloud-alias-failover.sh <<'EOF'
      #!/bin/bash
      set -euo pipefail

      ENV_FILE="/etc/keepalived/hcloud.env"
      if [ -f "$ENV_FILE" ]
      then
        source "$ENV_FILE"
      else
        exit 1
      fi

      NET_ID="${data.hcloud_network.k3s.id}"
      VIP="${local.nat_gateway_ip}"
      PEER_IP="${local.nat_router_ip[count.index == 0 ? 1 : 0]}"

      MY_ID=$(curl -f -s http://169.254.169.254/hetzner/v1/metadata/instance-id)

      if [ -z "$MY_ID" ]
      then
        exit 1
      fi

      PEER_ID=$(curl -f -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
        "https://api.hetzner.cloud/v1/servers?label_selector=role=nat_router" | \
        jq -r --arg peer_ip "$PEER_IP" --arg net_id "$NET_ID" '.servers[] | select(any(.private_net[]; .ip == $peer_ip and (.network | tostring) == $net_id)) | .id' | head -n 1)

      if [ -z "$PEER_ID" ] || [ "$PEER_ID" = "null" ]
      then
        exit 1
      fi

      curl -f -s -X POST "https://api.hetzner.cloud/v1/servers/$PEER_ID/actions/change_alias_ips" \
        -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" \
        -d "{\"network\": $NET_ID, \"alias_ips\": []}"

      curl -f -s -X POST "https://api.hetzner.cloud/v1/servers/$MY_ID/actions/change_alias_ips" \
        -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" \
        -d "{\"network\": $NET_ID, \"alias_ips\": [\"$VIP\"]}"
      EOF
      chown keepalived_script:keepalived_script /usr/local/bin/hcloud-alias-failover.sh
      chmod 0700 /usr/local/bin/hcloud-alias-failover.sh

      cat > /etc/keepalived/hcloud.env <<'EOF'
      export HCLOUD_TOKEN="${var.nat_router_hcloud_token}"
      EOF
      chown keepalived_script:keepalived_script /etc/keepalived/hcloud.env
      chmod 0600 /etc/keepalived/hcloud.env

      systemctl daemon-reload
      systemctl enable wait-for-private-ip.service
      systemctl enable keepalived
      systemctl restart keepalived
      %{endif~}

      systemctl restart ssh || systemctl restart sshd || true
      KH_NAT_RECONCILE
      EOT
    ]
  }
}

resource "terraform_data" "nat_router_fail2ban" {
  count = var.nat_router != null ? (var.nat_router.enable_redundancy ? 2 : 1) : 0

  depends_on = [
    terraform_data.nat_router_config,
  ]

  triggers_replace = {
    server_id  = hcloud_server.nat_router[count.index].id
    config_sha = sha256(local.nat_router_fail2ban_script)
  }

  connection {
    user           = var.nat_router.enable_sudo ? "nat-router" : "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.nat_router_connection_host[count.index]
    port           = var.ssh_port
  }

  provisioner "remote-exec" {
    inline = [
      local.nat_router_fail2ban_script,
    ]
  }
}

resource "terraform_data" "nat_router_extra_runcmd" {
  count = var.nat_router != null && length(try(var.nat_router.extra_runcmd, [])) > 0 ? (try(var.nat_router.enable_redundancy, false) ? 2 : 1) : 0

  depends_on = [
    terraform_data.nat_router_fail2ban,
  ]

  triggers_replace = {
    server_id    = hcloud_server.nat_router[count.index].id
    commands_sha = sha256(jsonencode(try(var.nat_router.extra_runcmd, [])))
  }

  connection {
    user           = var.nat_router.enable_sudo ? "nat-router" : "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = local.nat_router_connection_host[count.index]
    port           = var.ssh_port
  }

  provisioner "remote-exec" {
    inline = [
      local.nat_router_extra_runcmd_script,
    ]
  }
}
