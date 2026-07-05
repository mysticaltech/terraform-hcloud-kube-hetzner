# Plan 007: User-supplied values cannot alter or break root shells and rendered YAML

> **Executor instructions**: step-by-step; verify; STOP binding; update plans/README.md.
>
> **Drift check**: `git diff --stat e506cc4..HEAD -- locals.tf variables.tf robot-nodes.tf modules/host/templates/cloudinit.yaml.tpl templates/nat-router-cloudinit.yaml.tpl templates/autoscaler.yaml.tpl modules/user_kustomization_set/` — mismatch = STOP.

## Status
- **Priority**: P1 | **Effort**: M | **Risk**: MED | **Depends on**: plans/001-render-harness.md (use it to verify renders) | **Category**: security
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
Multiple operator-supplied values flow raw into root shell commands and YAML documents during node bootstrap. Quotes/newlines/YAML syntax in them break bootstrap at best; at worst they alter root shell execution. The module's own history proves this class bites (live-gate: heredoc/indent bugs). Harden the input contracts and the rendering paths together.

## Current state (verified sites)
1. `locals.tf:205` — `additional_kubernetes_install_environment` rendered as `NAME="value"` lines into `/etc/environment` (sourced by root scripts); `variables.tf:2791` validation checks names but not value content (quotes/newlines).
2. `locals.tf:728` — install commands interpolate `*_version`/exec-arg variables into root shell strings; `robot-nodes.tf:13` — `INSTALL_K3S_EXEC='agent ${var.agent_exec_args}'`.
3. `modules/host/templates/cloudinit.yaml.tpl:103` + `templates/nat-router-cloudinit.yaml.tpl:217` — authorized keys emitted as raw `- ${key}` YAML items; key validation is prefix-only (`variables.tf:127,157`).
4. `templates/autoscaler.yaml.tpl:219` — autoscaler extra args as raw YAML list items.
5. `modules/user_kustomization_set/main.tf:88` — `mkdir -p $(dirname "${var.destination_folder}/${each.key}")` where `each.key` is a local FILENAME from `fileset()`; `main.tf:94` — `replace(path, ".tpl", "")` strips EVERY occurrence, not just the suffix (`a.tpl.d/b.yaml.tpl` → `a.d/b.yaml`, splitting mkdir-target from upload-target).

## Repo conventions
Self-contained validations live on the variable; anything cross-object → `validation-contract.tf` preconditions. Base64-through-shell is the established safe-transport pattern (see `nat-router.tf` reconcile: `printf '%s' '<b64>' | base64 -d | as_root`, and `modules/user_kustomization_set/templates/apply-options.sh.tpl` sidecar). Prefer `yamlencode` for YAML lists.

## Commands
Fmt/validate as plan 002; `python3 scripts/render_harness.py` (exists if 001 done — MUST pass after every step).

## Scope
**In scope**: the five site groups above + their variable validations + `CHANGELOG.md` (one 🔧/security summary line) + new harness cases in `scripts/render_harness.py`. **Out of scope**: any behavioral change for values that are currently valid AND safe (single-line keys, token-shaped args must render byte-identically); packer templates (separate concern); NAT reconcile script (already hardened).

## Steps
### Step 1: SSH keys — validate + yamlencode
Strengthen `ssh_public_key`/`ssh_additional_public_keys` validation: single line (no `\n`), matches `^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh.com) [A-Za-z0-9+/=]+( [^\r\n]*)?$`. Render the authorized-keys lists in BOTH cloud-init templates via a pre-encoded template input (pass `yamlencode(list)` from the caller or indent-safe `%{for}` over validated single-line values — pick ONE approach, apply to both, keep rendered output for currently-valid keys identical apart from safe quoting).
**Verify**: harness passes; scratch-render a key list containing a legit `ssh-ed25519 AAAA... comment` → output parses and matches expectations.
### Step 2: install env/exec args
`additional_kubernetes_install_environment`: extend validation — values must not contain `"`双quotes, backslashes, newlines, `$`, backticks; document the restriction in the description. Exec-args variables (`control_plane_exec_args`/`agent_exec_args`/robot equivalents — locate all with `grep -n 'exec_args' variables.tf`): validate as a single line without `'` quotes or newlines (they're embedded in single-quoted shell context — confirm each embedding context before choosing forbidden chars; adjust per-site so the forbidden set provably closes the escape).
**Verify**: fmt+validate; provider-free console: a value with an embedded newline → validation false; typical flags string → true.
### Step 3: autoscaler args YAML
Emit `templates/autoscaler.yaml.tpl` extra-args via `yamlencode`-style safe rendering (same technique as Step 1's choice).
**Verify**: harness cloud-init/manifest checks pass.
### Step 4: kustomization filenames
In `modules/user_kustomization_set`: (a) add a validation (contract precondition in the module or root validation-locals per convention) that every discovered template path matches `^[A-Za-z0-9._/-]+$` and contains no `..` segment — clear error names the offending file; (b) fix suffix-strip: `replace(...)` → trim only a trailing `.tpl`: use `endswith()` + `substr()` (or regex `replace(path, "/\\.tpl$/", "")` — Terraform replace supports regex with `/.../` delimiters; verify in console); (c) mkdir line: with (a) enforced, `each.key` is shell-safe by construction — still quote it: `mkdir -p "$(dirname "${var.destination_folder}/${each.key}")"` stays, note in code comment that safety derives from the path validation.
**Verify**: console: `replace("a.tpl.d/b.yaml.tpl", "/\\.tpl$/", "")` → `a.tpl.d/b.yaml`; validation rejects `evil$(touch x).tpl` and `../escape.tpl`; harness + fmt + validate pass.
### Step 5: changelog + harness cases
One changelog line (security hardening of input contracts; note any newly-rejected inputs as intentional). Add harness cases: authorized-keys render, autoscaler args render, tpl-strip behavior.

## Done criteria
- [ ] All five site groups hardened; harness (incl. 3 new cases) passes; fmt+validate; changelog; only in-scope files; README row updated.

## STOP conditions
- Any existing test preset/example in-repo violates a new validation → STOP and report (the contract may be too tight).
- The `%{for}`→yamlencode change produces a DIFFERENT rendered doc for currently-valid inputs (beyond quoting) → STOP.
- Terraform regex-replace semantics differ from expectation in console → STOP with evidence.
