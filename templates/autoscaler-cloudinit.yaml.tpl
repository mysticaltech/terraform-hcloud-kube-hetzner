#cloud-config

write_files:

${cloudinit_write_files_common}

%{ if os == "leapmicro" ~}
- path: /usr/local/bin/apply-k8s-selinux-policy.sh
  permissions: '0755'
  content: |
    #!/bin/bash
    # Apply additional SELinux policy needed for core Kubernetes workloads on Leap Micro.
    set -euo pipefail

    LOG_FILE=/var/log/k8s-selinux.log
    echo "[$(date)] Starting K8s SELinux policy application" >> "$LOG_FILE"

    MARKER_FILE=/var/lib/kube-hetzner/k8s-selinux-policy.applied
    if [ -f "$MARKER_FILE" ] && semodule -l 2>/dev/null | awk '{print $1}' | grep -qx 'k8s_custom_policies'; then
        echo "[$(date)] SELinux policy already applied; skipping" >> "$LOG_FILE"
        exit 0
    fi

    # Shared policy written by cloudinit_write_files_common from templates/k8s-custom-policies.te.
    if [ ! -f /root/k8s_custom_policies.te ]; then
        echo "[$(date)] Missing /root/k8s_custom_policies.te; cannot apply SELinux policy" >> "$LOG_FILE"
        exit 1
    fi
    cp /root/k8s_custom_policies.te /tmp/k8s_custom_policies.te

    for mod in k8s_custom_policies k8s_comprehensive; do
        semodule -r "$mod" 2>/dev/null || true
    done

    if checkmodule -M -m -o /tmp/k8s_custom_policies.mod /tmp/k8s_custom_policies.te >>"$LOG_FILE" 2>&1; then
        if semodule_package -o /tmp/k8s_custom_policies.pp -m /tmp/k8s_custom_policies.mod >>"$LOG_FILE" 2>&1; then
            if semodule -i /tmp/k8s_custom_policies.pp >>"$LOG_FILE" 2>&1; then
                echo "[$(date)] SELinux policy applied successfully" >>"$LOG_FILE"
                mkdir -p "$(dirname "$MARKER_FILE")"
                printf '%s\n' "applied $(date -Iseconds)" > "$MARKER_FILE"
                rm -f /tmp/k8s_custom_policies.{te,mod,pp}
                exit 0
            fi
        fi
    fi

    echo "[$(date)] Failed to apply SELinux policy" >>"$LOG_FILE"
    exit 1

- path: /etc/systemd/system/k8s-selinux-policy.service
  permissions: '0644'
  content: |
    [Unit]
    Description=Apply K8s SELinux Policy for Leap Micro
    DefaultDependencies=no
    After=local-fs.target
    Before=k3s.service rke2-server.service rke2-agent.service network-pre.target
    ConditionSecurity=selinux

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/bin/apply-k8s-selinux-policy.sh

    [Install]
    WantedBy=sysinit.target
%{ endif ~}

- content: ${base64encode(k3s_config)}
  encoding: base64
  path: /tmp/config.yaml

# Distro-specific agent installation script rendered by the module.
- content: ${base64encode(install_k8s_agent_script)}
  encoding: base64
  path: /var/pre_install/install-k8s-agent.sh

# Apply DNS config
%{ if has_dns_servers ~}
manage_resolv_conf: true
resolv_conf:
  nameservers:
%{ for dns_server in dns_servers ~}
    - ${dns_server}
%{ endfor ~}
%{ endif ~}

# Add ssh authorized keys
ssh_authorized_keys:
%{ for key in sshAuthorizedKeys ~}
  - ${key}
%{ endfor ~}

# Allow root SSH login (required for provisioning)
disable_root: false
ssh_pwauth: false

# Resize /var, not /, as that's the last partition in MicroOS image.
growpart:
    devices: ["/var"]

# Make sure the hostname is set correctly
hostname: ${hostname}
preserve_hostname: true

bootcmd:
  # Leap Micro/MicroOS health-checker can form a systemd ordering cycle with
  # cloud-final. Autoscaler nodes rely on cloud-final for Kubernetes bootstrap,
  # so mask it before the final cloud-init stage is scheduled.
  - [sh, -c, 'systemctl disable --now health-checker.service 2>/dev/null || true']
  - [sh, -c, 'systemctl mask health-checker.service 2>/dev/null || true']

runcmd:

${cloudinit_runcmd_common}

%{ if os == "leapmicro" ~}
# Enable and run SELinux policy service
- systemctl daemon-reload
- systemctl enable k8s-selinux-policy.service
- systemctl start k8s-selinux-policy.service
%{ endif ~}

# Configure default routes based on enabled public address families.
- |
  route_dev() {
    awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
  }

%{if private_ipv4_default_route~}
  # Public IPv4 is disabled, so IPv4 egress/API reachability must use the private network gateway.
  PRIV_IF=$(ip -4 route get '${network_gw_ipv4}' 2>/dev/null | route_dev)
  if [ -z "$PRIV_IF" ]; then
    PRIV_IF=$(ip -4 route show scope link 2>/dev/null | route_dev)
  fi
  if [ -n "$PRIV_IF" ]; then
    ip route replace default via '${network_gw_ipv4}' dev "$PRIV_IF" metric 100
  else
    echo "WARN: could not determine private interface for default route" >&2
  fi
%{endif~}

%{if public_ipv4_default_route~}
  # Standard public IPv4 setup: detect public interface dynamically (ARM uses enp7s0, x86 uses eth0).
  PUB4_IF=$(ip -4 route get 172.31.1.1 2>/dev/null | route_dev)
  # Verify we didn't accidentally pick the private interface (can happen if network_ipv4_cidr overlaps 172.31.0.0/16)
  PRIV_IF=$(ip -4 route get '${network_gw_ipv4}' 2>/dev/null | route_dev)
  if [ -n "$PRIV_IF" ] && [ "$PUB4_IF" = "$PRIV_IF" ]; then
    echo "WARN: detected interface $PUB4_IF matches private interface, clearing to trigger fallback" >&2
    PUB4_IF=""
  fi
  if [ -z "$PUB4_IF" ]; then
    echo "WARN: could not detect public interface, falling back to eth0" >&2
    PUB4_IF="eth0"
  fi
  ip -4 route replace default via 172.31.1.1 dev "$PUB4_IF" metric 100
%{endif~}

%{if public_ipv6_default_route~}
  PUB6_IF=$(ip -6 route show default 2>/dev/null | route_dev)
  if [ -z "$PUB6_IF" ]; then
    PUB6_IF=$(ip -o -6 addr show scope global 2>/dev/null | awk '$2 !~ /^(eth1|flannel|cilium|lxc|veth)/ {print $2; exit}')
  fi
  if [ -n "$PUB6_IF" ]; then
    ip -6 route replace default via fe80::1 dev "$PUB6_IF" metric 100
  else
    echo "WARN: could not determine public IPv6 interface for default route" >&2
  fi
%{endif~}

%{if multinetwork_public_overlay_enabled~}
- |
  route_dev() {
    awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
  }

  OVERLAY_NODE_IPS=""
%{if multinetwork_transport_ipv4_enabled~}
  PUB4_IF=$(ip -4 route get 172.31.1.1 2>/dev/null | route_dev)
  PUB4_IP=$(curl -fsS --max-time 2 http://169.254.169.254/hetzner/v1/metadata/public-ipv4 2>/dev/null || true)
  if [ -z "$PUB4_IP" ] && [ -n "$PUB4_IF" ]; then
    PUB4_IP=$(ip -o -4 addr show dev "$PUB4_IF" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}')
  fi
  if [ -n "$PUB4_IP" ]; then
    OVERLAY_NODE_IPS="$PUB4_IP"
  fi
%{endif~}
%{if multinetwork_transport_ipv6_enabled~}
  PUB6_IF=$(ip -6 route show default 2>/dev/null | route_dev)
  if [ -z "$PUB6_IF" ]; then
    PUB6_IF=$(ip -o -6 addr show scope global 2>/dev/null | awk '$2 !~ /^(eth1|flannel|cilium|lxc|veth)/ {print $2; exit}')
  fi
  PUB6_IP=""
  if [ -n "$PUB6_IF" ]; then
    PUB6_IP=$(ip -o -6 addr show dev "$PUB6_IF" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}')
  fi
  if [ -n "$PUB6_IP" ]; then
    if [ -n "$OVERLAY_NODE_IPS" ]; then
      OVERLAY_NODE_IPS="$OVERLAY_NODE_IPS,$PUB6_IP"
    else
      OVERLAY_NODE_IPS="$PUB6_IP"
    fi
  fi
%{endif~}

  if [ -n "$OVERLAY_NODE_IPS" ]; then
    sed -i '/^node-ip:/d;/^node-external-ip:/d' /tmp/config.yaml
    {
      printf 'node-ip: "%s"\n' "$OVERLAY_NODE_IPS"
      printf 'node-external-ip: "%s"\n' "$OVERLAY_NODE_IPS"
    } >> /tmp/config.yaml
  else
    echo "WARN: cilium_public_overlay could not determine a public node IP" >&2
  fi
%{endif~}

%{if swap_size != ""~}
- |
  btrfs subvolume create /var/lib/swap 2>/dev/null || true
  chmod 700 /var/lib/swap
  truncate -s 0 /var/lib/swap/swapfile
  chattr +C /var/lib/swap/swapfile
  fallocate -l ${swap_size} /var/lib/swap/swapfile
  chmod 600 /var/lib/swap/swapfile
  mkswap /var/lib/swap/swapfile
  swapon /var/lib/swap/swapfile
  if ! grep -q -F "/var/lib/swap/swapfile" /etc/fstab; then
    echo "/var/lib/swap/swapfile none swap defaults 0 0" | tee -a /etc/fstab
  fi
  cat <<'  EOF' > /etc/systemd/system/swapon-late.service
  [Unit]
  Description=Activate all swap devices later
  After=default.target

  [Service]
  Type=oneshot
  ExecStart=/sbin/swapon -a

  [Install]
  WantedBy=default.target
    EOF
  systemctl daemon-reload
  systemctl enable swapon-late.service
%{endif~}

%{if zram_size != ""~}
- |
  cat <<'  EOF' > /usr/local/bin/k3s-swapoff
  #!/bin/bash

  # Switching off swap
  swapoff /dev/zram0

  rmmod zram
    EOF
  chmod +x /usr/local/bin/k3s-swapoff

  cat <<'  EOF' > /usr/local/bin/k3s-swapon
  #!/bin/bash

  # load the dependency module
  modprobe zram

  # initialize the device with zstd compression algorithm
  echo zstd > /sys/block/zram0/comp_algorithm;
  echo ZRAM_SIZE_PLACEHOLDER > /sys/block/zram0/disksize

  # Creating the swap filesystem
  mkswap /dev/zram0

  # Switch the swaps on
  swapon -p 100 /dev/zram0
    EOF
  sed -i 's/ZRAM_SIZE_PLACEHOLDER/${zram_size}/' /usr/local/bin/k3s-swapon
  chmod +x /usr/local/bin/k3s-swapon

  cat <<'  EOF' > /etc/systemd/system/zram.service
  [Unit]
  Description=Swap with zram

  [Service]
  Type=oneshot
  RemainAfterExit=true
  ExecStart=/usr/local/bin/k3s-swapon
  ExecStop=/usr/local/bin/k3s-swapoff

  [Install]
  WantedBy=multi-user.target
    EOF
  systemctl daemon-reload
  systemctl enable --now zram.service
%{endif~}

# Start the Kubernetes agent install script
- ['/bin/bash', '/var/pre_install/install-k8s-agent.sh']
