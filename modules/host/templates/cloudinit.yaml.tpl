#cloud-config

write_files:

${cloudinit_write_files_common}
%{~ if length(cloudinit_write_files_extra) > 0 ~}
${yamlencode(cloudinit_write_files_extra)}
%{~ endif ~}

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

    # Remove any old modules (best-effort).
    for mod in k8s_custom_policies k8s_comprehensive; do
        semodule -r "$mod" 2>/dev/null || true
    done

    # Compile and install the policy.
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
    ConditionPathExists=!/var/lib/kube-hetzner/k8s-selinux-policy.applied

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/bin/apply-k8s-selinux-policy.sh

    [Install]
    WantedBy=sysinit.target
%{ endif ~}

- path: /usr/local/bin/fetch-keys.sh
  owner: root:root
  permissions: '0755'
  content: |
    #!/bin/sh
    set -eu
    user="$${1:-root}"
    [ "$user" = "root" ] || exit 0
    if [ -f /root/.ssh/authorized_keys ]; then
      cat /root/.ssh/authorized_keys
    fi

- path: /etc/ssh/sshd_config.d/40-kube-hetzner-authorized-keys-command.conf
  owner: root:root
  permissions: '0644'
  content: |
    AuthorizedKeysCommand /usr/local/bin/fetch-keys.sh
    AuthorizedKeysCommandUser root

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

runcmd:

${cloudinit_runcmd_common}

%{ if os == "leapmicro" ~}
# Enable and run SELinux policy service
- systemctl daemon-reload
- systemctl enable k8s-selinux-policy.service
- systemctl start k8s-selinux-policy.service
%{ endif ~}

# Configure default routes based on public ip availability
%{if private_network_only~}
# Private-only setup: detect the private interface dynamically
- |
  route_dev() {
    awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
  }
  PRIV_IF=$(ip -4 route get '${network_gw_ipv4}' 2>/dev/null | route_dev)
  if [ -z "$PRIV_IF" ]; then
    PRIV_IF=$(ip -4 route show scope link 2>/dev/null | route_dev)
  fi
  if [ -n "$PRIV_IF" ]; then
    ip route replace default via '${network_gw_ipv4}' dev "$PRIV_IF" metric 100
  else
    echo "WARN: could not determine private interface for default route" >&2
  fi
%{else~}
# Standard setup: detect public interface dynamically (ARM uses enp7s0, x86 uses eth0)
- |
  route_dev() {
    awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
  }
  PUB_IF=$(ip -4 route get 172.31.1.1 2>/dev/null | route_dev)
  # Verify we didn't accidentally pick the private interface (can happen if network_ipv4_cidr overlaps 172.31.0.0/16)
  PRIV_IF=$(ip -4 route get '${network_gw_ipv4}' 2>/dev/null | route_dev)
  if [ -n "$PRIV_IF" ] && [ "$PUB_IF" = "$PRIV_IF" ]; then
    echo "WARN: detected interface $PUB_IF matches private interface, clearing to trigger fallback" >&2
    PUB_IF=""
  fi
  if [ -z "$PUB_IF" ]; then
    echo "WARN: could not detect public interface, falling back to eth0" >&2
    PUB_IF="eth0"
  fi
  ip route replace default via 172.31.1.1 dev "$PUB_IF" metric 100
  ip -6 route replace default via fe80::1 dev "$PUB_IF" metric 100
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
%{~ if length(cloudinit_runcmd_extra) > 0 ~}
${yamlencode(cloudinit_runcmd_extra)}
%{~ endif ~}
