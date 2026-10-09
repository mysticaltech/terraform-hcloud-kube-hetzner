set -e

export DEBIAN_FRONTEND=noninteractive
if ! dpkg -s fail2ban python3-systemd >/dev/null 2>&1; then
  apt-get update
  apt-get install -y fail2ban python3-systemd
fi

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/kube-hetzner.conf <<'EOF'
Port ${ssh_port}
PasswordAuthentication no
X11Forwarding no
MaxAuthTries ${ssh_max_auth_tries}
AllowTcpForwarding yes
AllowAgentForwarding yes
AuthorizedKeysFile .ssh/authorized_keys
%{if enable_sudo~}
PermitRootLogin no
%{endif~}
EOF

%{if has_dns_servers~}
cat > /etc/resolv.conf <<'EOF'
# Managed by kube-hetzner
%{for dns_server in dns_servers~}
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
    -e "\\#iptables -t nat -A POSTROUTING -s '${private_network_ipv4_range}'#d" \
    -e "/iptables -t nat -A PREROUTING -i eth0 -p tcp --dport [0-9]+ -j DNAT --to-destination/d" \
    -e "/iptables -t nat -A POSTROUTING -d [0-9.]+ -p tcp --dport [0-9]+ -j MASQUERADE/d" \
    /etc/network/interfaces
fi

cat > /usr/local/sbin/kube-hetzner-nat-router-rules <<'EOF'
#!/bin/sh
set -eu

PRIVATE_RANGE='${private_network_ipv4_range}'
CP_LB_PRIVATE_IP='${cp_lb_private_ip}'
KUBEAPI_PORT='${kubernetes_api_port}'
ENABLE_CP_LB_PORT_FORWARD='${enable_cp_lb_port_forward}'

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

%{if enable_redundancy~}
if ! dpkg -s jq keepalived >/dev/null 2>&1; then
  apt-get update
  apt-get install -y jq keepalived
fi
id -u keepalived_script >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin keepalived_script

mkdir -p /etc/keepalived /etc/systemd/system/keepalived.service.d
cat > /usr/local/bin/wait-for-ip.sh <<'EOF'
#!/bin/bash
TARGET_IP="${my_private_ip}"

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
    priority ${priority}
    advert_int 1
    nopreempt
    unicast_src_ip ${my_private_ip}
    unicast_peer {
      ${peer_private_ip}
    }
    virtual_ipaddress {
      ${nat_gateway_ip} dev __NAT_PRIVATE_IFACE__
    }
    authentication {
      auth_type PASS
      auth_pass ${vip_auth_pass}
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

NET_ID="${network_id}"
VIP="${nat_gateway_ip}"
PEER_IP="${peer_private_ip}"
CLUSTER_NAME="${cluster_name}"

api_request() {
  curl -f -s --connect-timeout 5 --max-time 15 "$@"
}

assert_local_master() {
  ip -o -4 addr show | awk -v vip="$VIP" \
    '{split($4, address, "/"); if (address[1] == vip) found=1} END {exit !found}'
}

# API acceptance is not completion. Do not race the peer's release action.
wait_for_action() {
  local response="$1" action_id status deadline remaining request_timeout
  action_id=$(printf '%s' "$response" | jq -er '.action.id | numbers | select(. > 0 and . <= 9007199254740991 and floor == .)' 2>/dev/null) || return 1
  deadline=$((SECONDS + 60))
  while true; do
    # Always inspect a received response, even when the last GET used the remaining budget.
    status=$(printf '%s' "$response" | jq -er --argjson action_id "$action_id" '
      .action | select(type == "object" and .id == $action_id and (.id | type) == "number" and .id <= 9007199254740991
        and (.status | type) == "string" and has("error") and .error == null)
      | .status' 2>/dev/null) || return 1
    case "$status" in
      success) return 0 ;;
      running) ;;
      *) return 1 ;;
    esac
    remaining=$((deadline - SECONDS))
    [ "$remaining" -gt 0 ] || break
    sleep 1
    remaining=$((deadline - SECONDS))
    [ "$remaining" -gt 0 ] || break
    request_timeout=15
    if [ "$remaining" -lt "$request_timeout" ]; then request_timeout=$remaining; fi
    response=$(api_request --max-time "$request_timeout" -H "Authorization: Bearer $HCLOUD_TOKEN" \
      "https://api.hetzner.cloud/v1/actions/$action_id") || return 1
  done
  echo "NAT alias action did not complete before the deadline." >&2
  return 1
}

MY_ID=$(api_request http://169.254.169.254/hetzner/v1/metadata/instance-id)

if [ -z "$MY_ID" ]
then
  exit 1
fi

PEER_ID=$(api_request -H "Authorization: Bearer $HCLOUD_TOKEN" \
  "https://api.hetzner.cloud/v1/servers?label_selector=role=nat_router,cluster=$CLUSTER_NAME" | \
  jq -r --arg peer_ip "$PEER_IP" --arg net_id "$NET_ID" '.servers[] | select(any(.private_net[]; .ip == $peer_ip and (.network | tostring) == $net_id)) | .id' | head -n 1)

if [ -z "$PEER_ID" ] || [ "$PEER_ID" = "null" ]
then
  exit 1
fi

assert_local_master
ACTION=$(api_request -X POST "https://api.hetzner.cloud/v1/servers/$PEER_ID/actions/change_alias_ips" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" \
  -d "{\"network\": $NET_ID, \"alias_ips\": []}")
wait_for_action "$ACTION"

assert_local_master
ACTION=$(api_request -X POST "https://api.hetzner.cloud/v1/servers/$MY_ID/actions/change_alias_ips" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" \
  -d "{\"network\": $NET_ID, \"alias_ips\": [\"$VIP\"]}")
wait_for_action "$ACTION"

SERVER=$(api_request -H "Authorization: Bearer $HCLOUD_TOKEN" \
  "https://api.hetzner.cloud/v1/servers/$MY_ID")
printf '%s' "$SERVER" | jq -e --arg net_id "$NET_ID" --arg vip "$VIP" \
  'def ipv4: type == "string"
    and test("^(0|[1-9][0-9]{0,2})(\\.(0|[1-9][0-9]{0,2})){3}$")
    and (split(".") | all(.[]; tonumber <= 255));
  .server | select(type == "object") | .private_net | select(type == "array")
  | select(all(.[]; type == "object" and (.network | type) == "number"
      and (.alias_ips | type == "array" and all(.[]; ipv4))))
  | any(.[]; (.network | tostring) == $net_id and any(.alias_ips[]; . == $vip))' >/dev/null 2>&1
EOF
chown keepalived_script:keepalived_script /usr/local/bin/hcloud-alias-failover.sh
chmod 0700 /usr/local/bin/hcloud-alias-failover.sh

cat > /etc/keepalived/hcloud.env <<'EOF'
export HCLOUD_TOKEN="${hcloud_token}"
EOF
chown keepalived_script:keepalived_script /etc/keepalived/hcloud.env
chmod 0600 /etc/keepalived/hcloud.env

systemctl daemon-reload
systemctl enable wait-for-private-ip.service
systemctl enable keepalived
systemctl restart keepalived
%{endif~}

systemctl restart ssh || systemctl restart sshd || true
