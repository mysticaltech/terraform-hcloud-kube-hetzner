Kube-Hetzner requires you to have a recent version of OpenSSH (>=6.5) installed on your client, and the use of a key-pair generated with either of the following algorithms:

- ssh-ed25519 (preferred, and most simple to use without passphrase)
- rsa-sha2-512
- rsa-sha2-256

If your key-pair is of the `ssh-ed25519` sort (useful command `ssh-keygen -t ed25519`), and without of passphrase, you do not need to do anything else. Just set `public_key` and `private_key` to their respective path values in your kube.tf file.

---

Otherwise, for a key-pair with passphrase or a device like a Yubikey, make sure you have an SSH agent running and your key is loaded with:

```bash
eval ssh-agent $SHELL
ssh-add ~/.ssh/my_private-key_id
```

Verify it is loaded with:

```bash
ssh-add -l
```

Then set `private_key = null` in your kube.tf file, as it will be read from the ssh-agent automatically.

---

## Firewall SSH source and changing IPs

SSH access is controlled by the Hetzner Cloud firewall, and the module configures it via the `firewall_ssh_source` input. This is a list of CIDR blocks that are allowed to connect to the nodes over SSH (for a single IPv4 address, use a `/32`, for IPv6 a `/128`).

If your IP changes, you are not locked out permanently:

- Update `firewall_ssh_source` in your `kube.tf` (or the corresponding variable in Terraform Cloud).
- Run `terraform plan` and `terraform apply`.

Terraform updates the firewall through the Hetzner API, so SSH access is not required to make this change. If you need access immediately, you can temporarily add a wider CIDR (for example `0.0.0.0/0` and/or `::/0`), apply, and then tighten it again once you are connected. A static IP or a VPN with a fixed egress IP also avoids future changes.
