---
name: debug-node
description: Use when a Hetzner node is unreachable, SSH fails, cloud-init seems broken, or provisioning hangs. Boots into rescue mode via hcloud CLI to inspect filesystem, logs, SSH keys, sshd config, and cloud-init state without needing SSH access to the node itself.
---

# Debug Hetzner Node via Rescue Console

## Overview

When a Hetzner Cloud server is unreachable (SSH hangs, provisioning stuck, cloud-init failure), this skill uses Hetzner's **rescue mode** to mount the node's filesystem and inspect everything from the outside — no working SSH required.

## Usage

```
/debug-node
```

When invoked, ask for:
1. The server name or IP (can be found from `hcloud server list`)
2. What symptom they're seeing (SSH timeout, provisioning hang, etc.)

## Prerequisites

- `hcloud` CLI installed and configured with a valid token
- The server must exist in Hetzner Cloud

```bash
hcloud server list
```

## Leap Micro Filesystem Model

Leap Micro uses a **transactional-update** system on btrfs. This is the mental model for everything below.

| Layer | Writable? | Persists reboot? | Persists Hetzner snapshot? |
|-------|-----------|------------------|---------------------------|
| `/usr` (snapshot) | No (read-only) | Yes | Yes |
| `/etc` via `transactional-update shell` | Yes (new snapshot) | Yes (after reboot) | Yes |
| `/etc` via direct edit on running system | Yes (volatile overlay) | **No** | **No** |
| `/var` (separate subvolume) | Yes | Yes | Yes |

**Rule:** Any `/etc` change that must survive MUST go through `transactional-update --continue shell`.

**Packer build phases:**
1. **Rescue mode:** Write qcow2 to disk, reboot
2. **`install_packages`:** Inside `transactional-update` — changes **persist**
3. **`clean_up`:** Volatile overlay — `/etc` changes are **lost** in the Hetzner snapshot

## Step 1: Identify the Server

```bash
hcloud server list -o columns=id,name,status,ipv4 | grep <pattern>
```

## Step 2: Enable Rescue Mode & Reboot

```bash
hcloud server enable-rescue <SERVER_ID> --type linux64
hcloud server reboot <SERVER_ID>
sleep 30
```

Save the rescue root password from the output (usually key auth works, but just in case).

## Step 3: SSH into Rescue

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@<SERVER_IP>
```

## Step 4: Mount the Filesystem

### Leap Micro / MicroOS (btrfs)

```bash
# Mount btrfs top-level
mount -o subvolid=5 /dev/sda3 /mnt

# List snapshots — highest number is active
ls /mnt/@/.snapshots/
```

Layout:
```
/mnt/@/.snapshots/N/snapshot/    latest active snapshot — /etc lives here
/mnt/@/root/                     /root home (/root/.ssh/authorized_keys)
/mnt/@/var/                      /var (logs, cloud-init state, journal)
```

**Key:** `/etc` is inside the snapshot. `/var` and `/root` are separate subvolumes at `@/var` and `@/root`.

### Ubuntu / Debian (ext4)

```bash
mount /dev/sda1 /mnt
```

## Step 5: Diagnostic Checklist

Set this once and use throughout:
```bash
SNAP=/mnt/@/.snapshots/N/snapshot   # replace N with highest snapshot number
```

### 5a. Cloud-Init Status

Start here — most provisioning failures trace back to cloud-init.

```bash
cat /mnt/@/var/lib/cloud/data/result.json
cat /mnt/@/var/lib/cloud/data/status.json
cat /mnt/@/var/lib/cloud/instance/datasource

# What Terraform actually sent
cat /mnt/@/var/lib/cloud/instance/user-data.txt
zcat /mnt/@/var/lib/cloud/instance/user-data.txt.i 2>/dev/null

# Logs
tail -100 /mnt/@/var/log/cloud-init.log
tail -100 /mnt/@/var/log/cloud-init-output.log
```

**Expected:** `DataSourceHetzner`, no errors.
**Watch for:** `Skipping modules` — means cloud-init already ran for this instance-id.

Cloud-init facts on Hetzner + Leap Micro:
- Datasource: `DataSourceHetzner` (metadata API)
- Terraform's `cloudinit_config` → gzip+base64 multipart MIME → `user_data`
- `disable_root: false` prevents cloud-init from disabling root but does NOT unlock a locked account
- `ssh_authorized_keys` writes keys to `/root/.ssh/authorized_keys`

### 5b. SSH Keys

```bash
cat /mnt/@/root/.ssh/authorized_keys
```

Compare with your local pubkey. If missing, cloud-init failed to inject — check 5a logs.

### 5c. SSHD Configuration

Config loading order (first match wins):

```
1. /etc/ssh/sshd_config.d/40-kube-hetzner-authorized-keys-command.conf
2. /etc/ssh/sshd_config.d/50-cloud-init.conf
3. /etc/ssh/sshd_config.d/kube-hetzner.conf           (MaxAuthTries 2)
4. /usr/etc/ssh/sshd_config.d/40-suse-crypto-policies.conf
5. /usr/etc/ssh/sshd_config                            (UsePAM yes)
```

```bash
ls $SNAP/etc/ssh/sshd_config.d/
cat $SNAP/etc/ssh/sshd_config.d/*.conf
cat $SNAP/usr/etc/ssh/sshd_config
ls -la $SNAP/etc/ssh/ssh_host_*
```

### 5d. Account Status

```bash
grep '^root:' $SNAP/etc/shadow
```

| Pattern | Meaning | SSH pubkey works? |
|---------|---------|-------------------|
| `root:*:...` | Unlocked, no password | Yes |
| `root:!*:...` or `root:!:...` | Locked | **No** (PAM rejects with `UsePAM yes`) |

This is fixed in packer (`usermod -p '*' root` inside transactional-update) with a cloud-init `bootcmd` safety net. If you see a locked account on a fresh node, the packer snapshot needs rebuilding.

### 5e. Journal Logs

```bash
journalctl -D /mnt/@/var/log/journal/ -u sshd --no-pager | tail -50
journalctl -D /mnt/@/var/log/journal/ -u k3s --no-pager | tail -30
journalctl -D /mnt/@/var/log/journal/ -u rke2-server --no-pager | tail -30
journalctl -D /mnt/@/var/log/journal/ -u rke2-agent --no-pager | tail -30
```

### 5f. Network

```bash
ls $SNAP/etc/NetworkManager/system-connections/
cat $SNAP/etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null
```

### 5g. Kubernetes

```bash
cat $SNAP/etc/rancher/k3s/config.yaml 2>/dev/null
cat $SNAP/etc/rancher/rke2/config.yaml 2>/dev/null
cat /mnt/@/var/lib/rancher/k3s/server/token 2>/dev/null
```

### 5h. SELinux

```bash
cat $SNAP/etc/selinux/config
chroot $SNAP rpm -qa | grep -iE 'selinux|k3s|rke2'
tail -20 /mnt/@/var/log/audit/audit.log | grep denied
```

## Step 6: Apply a Fix

Edit files in the **active snapshot** (`$SNAP`), not in `@/` base.

```bash
# Unlock root account (if locked)
sed -i 's/^root:!*/root:*/' $SNAP/etc/shadow

# Fix authorized_keys
mkdir -p /mnt/@/root/.ssh
echo "ssh-ed25519 AAAA..." > /mnt/@/root/.ssh/authorized_keys
chmod 700 /mnt/@/root/.ssh && chmod 600 /mnt/@/root/.ssh/authorized_keys

# Regenerate host keys
mount --bind /proc $SNAP/proc && mount --bind /sys $SNAP/sys && mount --bind /dev $SNAP/dev
chroot $SNAP ssh-keygen -A
umount $SNAP/proc $SNAP/sys $SNAP/dev
```

**Note:** Rescue-mode edits are immediate fixes. The proper long-term fix belongs in the packer template or cloud-init.

## Step 7: Reboot to Normal

```bash
umount /mnt 2>/dev/null
exit
```

```bash
hcloud server disable-rescue <SERVER_ID>
hcloud server reboot <SERVER_ID>
sleep 60
ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 root@<SERVER_IP> 'echo ok'
```

## Common Diagnoses

| Symptom | Likely Cause | Check | Fix |
|---------|-------------|-------|-----|
| SSH timeout | Firewall or network | Hetzner firewall rules | Open port 22 |
| SSH "Connection refused" | sshd not running | Journal logs | Fix sshd config syntax |
| SSH key rejected | Keys not injected | `authorized_keys` empty | Check cloud-init logs |
| SSH "Too many auth failures" | Agent offers too many keys | `MaxAuthTries 2` | Use `-o IdentitiesOnly=yes` |
| SSH "unable to authenticate" | Root locked, or key mismatch | `/etc/shadow`, authorized_keys | Rebuild packer snapshot |
| Provisioner hangs "Still creating" | SSH can't connect | All above | Fix underlying SSH issue |
| Cloud-init skips modules | Already ran for instance-id | cloud-init.log | Clean `/var/lib/cloud/instance` |
| k3s/rke2 not starting | Config or SELinux | Journal + audit.log | Fix config or policy |
| `/etc` change vanished | Edited outside transactional-update | Check packer phase | Move change to phase 2 |

## Debugging SSH Manually

```bash
# Verbose with specific key (avoids agent key spray hitting MaxAuthTries 2)
ssh -vvv -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 root@<SERVER_IP>

# In -vvv output:
# "Offering public key: ..."              → key was offered
# "Server accepts key: ..."               → success path
# "Authentications that can continue: ..."  → key was REJECTED
# "Too many authentication failures"       → agent sent too many keys
```

## Pro Tips

1. **Mount with `subvolid=5`** — gets the real btrfs root, navigate to `@/.snapshots/N/snapshot/`
2. **Highest snapshot = active** — that's where `/etc` lives
3. **`/var` is separate** — logs and cloud-init are at `/mnt/@/var/`, not inside the snapshot
4. **Journal without a running system** — `journalctl -D /path/to/journal/`
5. **Use `-o IdentitiesOnly=yes`** — kube-hetzner sets `MaxAuthTries 2`
6. **Volatile overlay trap** — if rescue shows different content than the live system did, it was running on a volatile overlay that never got committed
7. **After fixing packer, rebuild snapshots** — verify build logs show changes inside the `transactional-update` output
8. **Rescue mode is non-destructive** — you're just reading/writing files on the disk
