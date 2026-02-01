#cloud-config

write_files:

${cloudinit_write_files_common}

- content: ${base64encode(k3s_config)}
  encoding: base64
  path: /tmp/config.yaml

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

# Resize /var, not /, as that's the last partition in MicroOS image.
growpart:
    devices: ["/var"]

# Make sure the hostname is set correctly
hostname: ${hostname}
preserve_hostname: true

runcmd:

${cloudinit_runcmd_common}

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
