# Plan 005: SMB CSI installs from a stable chart source; the dead NFS template is removed

> **Executor instructions**: step-by-step; verify; STOP binding; update plans/README.md.
>
> **Drift check**: `git diff --stat e506cc4..HEAD -- templates/csi-driver-smb.yaml.tpl templates/csi-driver-nfs.yaml.tpl variables.tf` — mismatch = STOP.

## Status
- **Priority**: P2 | **Effort**: S | **Risk**: LOW | **Depends on**: none | **Category**: migration
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
`templates/csi-driver-smb.yaml.tpl:9` points the HelmChart at `https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts` — a mutable branch: chart content can change under users without any module diff, and `csi_driver_smb_version` defaults to `"*"` on top. `templates/csi-driver-nfs.yaml.tpl` repeats the pattern and is referenced NOWHERE (dead scaffolding inviting future copy-paste of the fragile pattern).

## Current state
```yaml
# templates/csi-driver-smb.yaml.tpl:8-10
  chart: csi-driver-smb
  repo: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts
  version: "${version}"
```
Upstream publishes the same chart at the GitHub-Pages Helm repo `https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts` — CHECK for the canonical alternative: the project documents `helm repo add csi-driver-smb https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts` as its official repo. If NO tag/release-pinned repo exists upstream (verify by fetching `https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts/index.yaml` and reading its entries — network read-only allowed), pinning must come from the VERSION side: keep the repo but stop defaulting to `"*"`.
`variables.tf` (~2548): `csi_driver_smb_version` default `"*"`. Reference site of the version: `locals.tf` (`grep -n csi_driver_smb_version locals.tf`).

## Scope
**In scope**: `templates/csi-driver-smb.yaml.tpl`, delete `templates/csi-driver-nfs.yaml.tpl`, `variables.tf` (smb version default only), `kube.tf.example` (matching comment), `CHANGELOG.md` (🔧 + upgrade note if default changes).
**Out of scope**: enabling NFS support (park it — removal is the decision unless a reference exists); other chart templates.

## Steps
### Step 1
Verify NFS template is truly dead: `grep -rn 'csi-driver-nfs\|csi_driver_nfs' --include='*.tf' --include='*.tpl' --include='*.yaml' . | grep -v templates/csi-driver-nfs` → must be empty; then `git rm templates/csi-driver-nfs.yaml.tpl`.
**Verify**: grep empty; file gone; validate passes.
### Step 2
Pin the SMB default: fetch the chart index (read-only), pick the latest STABLE chart version, set it as the `csi_driver_smb_version` default (replacing `"*"`), and document in the variable description + kube.tf.example that `"*"` remains an allowed opt-in for floating. Changelog: upgrade note — users who relied on implicit latest now track a reviewed default (their plan will show the HelmChart version change once, applied by the existing kustomization trigger machinery).
**Verify**: `grep -n 'default.*\*' variables.tf | grep csi_driver_smb` → empty; fmt+validate pass.

## Done criteria
- [ ] NFS template deleted with zero dangling references; SMB default pinned; docs+changelog updated; fmt+validate; only in-scope files; README row updated.

## STOP conditions
- Any live reference to the NFS template exists → STOP (removal decision changes).
- Chart index unreachable in sandbox → pin to the version documented in the chart repo README at the pinned floor, and note the source in your report; if that too is unavailable, STOP.
