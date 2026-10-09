# Kubernetes installation supply chain

kube-hetzner treats initial K3s and RKE2 bootstrap as a root code-execution boundary. Nodes do not execute `get.k3s.io` or `get.rke2.io`, and they do not accept a payload solely because it matches a checksum downloaded beside that payload.

## Trust model

The module embeds `scripts/install-verified-kubernetes.sh` into each HCloud, autoscaler, Robot, and generated external-node install command. That launcher:

1. downloads the official installer from an immutable upstream Git commit;
2. verifies the installer against a SHA-256 pinned in the launcher;
3. downloads the exact release payload selected by Terraform;
4. verifies the payload against a digest carried by the module release or operator configuration, falling back for backward-compatible custom exact versions to one strictly selected digest from that exact official release's checksum publication;
5. only then invokes the pinned installer in no-download/local-artifact mode.

K3s receives an already verified `/usr/local/bin/k3s` and runs its installer with `INSTALL_K3S_SKIP_DOWNLOAD=true`, `INSTALL_K3S_SKIP_START=true`, and `INSTALL_K3S_SKIP_SELINUX_RPM=true`. The launcher resets upstream installer-control variables so inherited `/etc/environment` or preinstall values cannot redirect the service to a different binary or install location. RKE2 receives a verified tarball through `INSTALL_RKE2_ARTIFACT_PATH` with `INSTALL_RKE2_METHOD=tar`. The image-baked `k3s-selinux`/`rke2-selinux` preflight remains mandatory on module-managed nodes when SELinux is enabled.

The installer pins are:

| Distribution | Official source commit | Installer SHA-256 |
| --- | --- | --- |
| K3s | [`k3s-io/k3s@2d0f82fa2f933cd227fe38e1482558ce4769f464`](https://github.com/k3s-io/k3s/commit/2d0f82fa2f933cd227fe38e1482558ce4769f464) | `ed01f89fd977bf20ac1516bbebf8370bf3ddbaa55dac8aba610956a4c78cc00b` |
| RKE2 | [`rancher/rke2@c4f306e6c5fa18dfb447bf6b8a0423f2da68c939`](https://github.com/rancher/rke2/commit/c4f306e6c5fa18dfb447bf6b8a0423f2da68c939) | `42983c86d1da64a92061d83afb57630cedd69241989f1b0673f3db6c3d92ee6b` |

Reviewed channel payload pins come from the official K3s and RKE2 GitHub release assets/checksum publications and are embedded when this module is released, under a different change-control boundary from the runtime download. Explicit `*_artifact_sha256` values provide the same independent boundary for custom exact versions. To preserve minor-release compatibility, a custom exact version without a configured architecture digest uses one exact filename match from that release's official checksum publication; malformed, duplicate, wrong-filename, and all-zero entries fail closed.

## Channels and exact versions

For initial bootstrap, `stable`, `latest`, `testing`, `v1.36` and `v1.37` (both distributions), and the K3s `v1.33` preservation channel resolve to exact releases in the module's reviewed manifest. They are snapshots, not mutable runtime lookups. With an empty exact version and automated upgrades enabled, System Upgrade Controller plans follow the live channel after bootstrap. Selecting `v1.36` or `v1.37` follows that minor's patch releases, not newer Kubernetes minors.

For RKE2 channel following, explicitly set `rke2_version = ""`; changing the channel alone does not override its default exact-version pin.

An exact `k3s_version` or `rke2_version` already present in the manifest needs no extra input. For another official release, independent pins are optional but recommended for each architecture used by the cluster:

```hcl
k3s_version = "v1.36.4+k3s1"
k3s_artifact_sha256 = {
  amd64 = "<reviewed official payload SHA-256>"
  arm64 = "<reviewed official payload SHA-256>"
}
```

Use `rke2_artifact_sha256` for RKE2. CAX node types require `arm64`; other HCloud types and Robot agents require `amd64`. A configured digest is selected per architecture; an omitted architecture uses the exact official release checksum fallback. Dormant autoscaler pools preserve their existing semantics and add no architecture requirement.

The sensitive `join_script_external` output uses the same verified K3s path and starts `k3s-agent` after installation. Terraform cannot infer an unmanaged node's CPU architecture, so the helper selects the configured `amd64` or `arm64` digest at runtime, or uses the exact official release checksum fallback when that architecture is omitted. On an SELinux-enabled external host, install `k3s-selinux` first; the helper fails before download if the policy is absent, then loads the policy and labels the verified binary before starting the agent.

When reviewing a new independent pin, use the exact official release tag and asset name, compare the downloaded artifact with the official release publication, and commit the expected digest in operator configuration or the module manifest. The compatibility fallback verifies transport integrity and release consistency, but it is not independent of the release authority because the payload and checksum are fetched together.

## Upgrade compatibility

Existing custom exact K3s/RKE2 version configurations continue to plan without a new required input and do not recreate running nodes or HCloud resources. Operators following a channel receive the channel snapshot reviewed with their module version for new-node bootstrap; upgrading the module advances that reviewed snapshot. Before adding or replacing a node after the live channel has advanced substantially, update the module first so the replacement's reviewed bootstrap release remains within Kubernetes version-skew policy for the running cluster. Adding an independent digest map changes only bootstrap verification for future or replaced nodes.
