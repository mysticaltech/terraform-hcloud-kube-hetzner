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

    cat > /tmp/k8s_custom_policies.te <<'EOF'
    module k8s_custom_policies 1.0;

    require {
        type container_t;
        type cert_t;
        type proc_t;
        type sysfs_t;
        type kernel_t;
        type init_t;
        type security_t;
        type unreserved_port_t;
        type kubernetes_port_t;
        type http_port_t;
        type hplip_port_t;
        type node_t;
        class dir { read search open getattr };
        class file { read open getattr };
        class lnk_file { read getattr };
        class tcp_socket { name_bind name_connect accept listen read write };
        class node { tcp_recv tcp_send };
        class peer recv;
        class filesystem getattr;
    }

    allow container_t cert_t:dir { read search open getattr };
    allow container_t cert_t:file { read open getattr };
    allow container_t proc_t:file { read open getattr };
    allow container_t proc_t:dir { read search open getattr };
    allow container_t proc_t:lnk_file { read getattr };
    allow container_t proc_t:filesystem getattr;
    allow container_t sysfs_t:file { read open getattr };
    allow container_t sysfs_t:dir { read search open getattr };
    allow container_t sysfs_t:lnk_file { read getattr };
    allow container_t sysfs_t:filesystem getattr;
    allow container_t kubernetes_port_t:tcp_socket { name_bind name_connect accept listen };
    allow container_t hplip_port_t:tcp_socket { name_bind name_connect accept listen };
    allow container_t unreserved_port_t:tcp_socket { name_bind name_connect accept listen };
    allow container_t container_t:tcp_socket { name_connect accept };
    allow container_t container_t:peer recv;
    allow container_t node_t:node { tcp_recv tcp_send };
    allow container_t http_port_t:tcp_socket { name_bind name_connect accept listen };
    allow container_t kernel_t:tcp_socket { read write };
    allow container_t security_t:file { read open getattr };
    allow container_t init_t:dir { read search open getattr };
    allow container_t init_t:file { read open getattr };
    allow container_t init_t:lnk_file { read getattr };
    EOF

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
    ConditionPathExists=!/var/lib/kube-hetzner/k8s-selinux-policy.applied

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

# TODO: Extend this for rke2
- content: ${base64encode(install_k3s_agent_script)}
  encoding: base64
  path: /var/pre_install/install-k3s-agent.sh

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
  After=multi-user.target

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

# Start the install-k3s-agent service
- ['/bin/bash', '/var/pre_install/install-k3s-agent.sh']
