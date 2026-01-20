#cloud-config
package_reboot_if_required: false
package_update: true
package_upgrade: true
packages: 
- fail2ban

write_files:
  - path: /etc/network/interfaces
    content: |
      auto eth0
      iface eth0 inet dhcp
          post-up echo 1 > /proc/sys/net/ipv4/ip_forward
          post-up iptables -t nat -A POSTROUTING -s '${ private_network_ipv4_range }' -o eth0 -j MASQUERADE
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
      # PermitRootLogin no
    path: /etc/ssh/sshd_config.d/kube-hetzner.conf
  - path: /etc/fail2ban/jail.d/sshd.local
    content: |
      [sshd]
      enabled = true
      port = ssh
      logpath = %(sshd_log)s
      maxretry = 5
      bantime = 86400

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
