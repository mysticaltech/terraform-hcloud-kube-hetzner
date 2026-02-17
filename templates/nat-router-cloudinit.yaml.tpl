#cloud-config
package_reboot_if_required: false
package_update: true
package_upgrade: true
packages: 
- fail2ban
%{ if enable_redundancy ~}
- jq
- keepalived
%{ endif ~}

write_files:
  - path: /etc/network/interfaces
    content: |
      auto eth0
      iface eth0 inet dhcp
          post-up echo 1 > /proc/sys/net/ipv4/ip_forward
          post-up iptables -t nat -A POSTROUTING -s '${ private_network_ipv4_range }' ! -d '${ private_network_ipv4_range }' -o eth0 -j MASQUERADE
%{ if enable_cp_lb_port_forward ~}
          post-up iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 6443 -j DNAT --to-destination ${ cp_lb_private_ip }:6443
          post-up iptables -t nat -A POSTROUTING -d ${ cp_lb_private_ip } -p tcp --dport 6443 -j MASQUERADE
%{ endif ~}
    append: true

  # Disable ssh password authentication
  - content: |
      Port ${ ssh_port }
      PasswordAuthentication no
      X11Forwarding no
      MaxAuthTries ${ ssh_max_auth_tries }
      AllowTcpForwarding yes
      AllowAgentForwarding yes
      AuthorizedKeysFile .ssh/authorized_keys
%{ if enable_sudo ~}
      PermitRootLogin no
%{ endif ~}
    path: /etc/ssh/sshd_config.d/kube-hetzner.conf
  - path: /etc/fail2ban/jail.d/sshd.local
    content: |
      [sshd]
      enabled = true
      port = ssh
      logpath = %(sshd_log)s
      maxretry = 5
      bantime = 86400

%{ if enable_redundancy ~}
  # We might run into race condition of keepalived starting and the private subnet ip being attached to the interface
  # in that case, keepalived would go into fault state if we don't wait for it
  - path: /usr/local/bin/wait-for-ip.sh
    permissions: '0700'
    content: |
      #!/bin/bash
      TARGET_IP="${ my_private_ip }"

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
  - path: /etc/systemd/system/wait-for-private-ip.service
    content: |
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
  - path: /etc/systemd/system/keepalived.service.d/override.conf
    content: |
      [Unit]
      # Require the specific IP wait service
      Requires=wait-for-private-ip.service
      After=wait-for-private-ip.service
  - path: /etc/keepalived/keepalived.conf.tmpl
    content: |
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
          priority ${ priority }
          advert_int 1
          nopreempt
          unicast_src_ip ${ my_private_ip }
          unicast_peer {
            ${ peer_private_ip }
          }
          virtual_ipaddress {
            ${ vip } dev __NAT_PRIVATE_IFACE__
          }
          authentication {
            auth_type PASS
            auth_pass ${ vip_auth_pass }
          }

          track_script {
            check_internet
          }

          # Call Hetzner API for alias IP change
          notify_master "/usr/local/bin/hcloud-alias-failover.sh"
      }
  - path: /usr/local/bin/check_wan.sh
    owner: keepalived_script:keepalived_script
    defer: true
    permissions: '0744'
    content: |
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

  - path: /usr/local/bin/hcloud-alias-failover.sh
    owner: keepalived_script:keepalived_script
    defer: true
    permissions: '0700'
    content: |
      #!/bin/bash
      set -euo pipefail

      # Load environment variables, including HCLOUD_TOKEN
      ENV_FILE="/etc/keepalived/hcloud.env"
      if [ -f "$ENV_FILE" ]
      then
        source "$ENV_FILE"
      else
        exit 1
      fi

      NET_ID="${ network_id }"
      VIP="${ vip }"
      PEER_IP="${ peer_private_ip }"

      # Get own hcloud server id by calling metadata service
      MY_ID=$(curl -f -s http://169.254.169.254/hetzner/v1/metadata/instance-id)

      if [ -z "$MY_ID" ]
      then
        exit 1
      fi

      # Get peer id by server list filtered by role=nat_router and provided peer IP
      PEER_ID=$(curl -f -s -H "Authorization: Bearer $HCLOUD_TOKEN" \
        "https://api.hetzner.cloud/v1/servers?label_selector=role=nat_router" | \
        jq -r --arg peer_ip "$PEER_IP" --arg net_id "$NET_ID" '.servers[] | select(any(.private_net[]; .ip == $peer_ip and (.network | tostring) == $net_id)) | .id' | head -n 1)

      if [ -z "$PEER_ID" ] || [ "$PEER_ID" = "null" ]
      then
        exit 1
      fi

      # Remove from Peer
      curl -f -s -X POST "https://api.hetzner.cloud/v1/servers/$PEER_ID/actions/change_alias_ips" \
        -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" \
        -d "{\"network\": $NET_ID, \"alias_ips\": []}"

      # Assign to Me
      curl -f -s -X POST "https://api.hetzner.cloud/v1/servers/$MY_ID/actions/change_alias_ips" \
        -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" \
        -d "{\"network\": $NET_ID, \"alias_ips\": [\"$VIP\"]}"

  - path: /etc/keepalived/hcloud.env
    owner: keepalived_script:keepalived_script
    permissions: '0600'
    defer: true
    content: |
      export HCLOUD_TOKEN="${ hcloud_token }"
%{ endif ~}

users:
  - name: nat-router
    groups:
%{ if enable_sudo ~}
      - sudo
%{ endif ~}
%{ if enable_sudo ~}
    sudo:
      - ALL=(ALL) NOPASSWD:ALL
%{ endif ~}
# Add ssh authorized keys
    ssh_authorized_keys:
%{ for key in sshAuthorizedKeys ~}
      - ${key}
%{ endfor ~}
%{ if enable_redundancy ~}
  - name: keepalived_script
%{ endif ~}

# Apply DNS config
%{ if has_dns_servers ~}
manage_resolv_conf: true
resolv_conf:
  nameservers:
%{ for dns_server in dns_servers ~}
    - ${dns_server}
%{ endfor ~}
%{ endif ~}


runcmd:
  - [systemctl, 'enable', 'fail2ban']
  - [systemctl, 'restart', 'sshd']
  - [systemctl, 'restart', 'networking']
%{ if enable_redundancy ~}
  - [systemctl, 'enable', 'keepalived']
  - [systemctl, 'restart', 'keepalived']
%{ endif ~}
