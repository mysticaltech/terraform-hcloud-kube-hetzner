# Plan 006: ssh_port rejects 0 and non-integers at input time

> **Executor instructions**: step-by-step; verify; STOP binding; update plans/README.md.
>
> **Drift check**: `git diff --stat e506cc4..HEAD -- variables.tf` — mismatch at the ssh_port block = STOP.

## Status
- **Priority**: P2 | **Effort**: S | **Risk**: LOW | **Depends on**: none | **Category**: bug
- **Planned at**: commit `e506cc4`, 2026-07-05

## Why this matters
`ssh_port` currently validates `>= 0 && <= 65535` with `type = number` — port 0 and fractional values pass input validation and fail later inside SSH connections, the NAT router's sshd `Port` line, or fail2ban config, at apply time with opaque errors.

## Current state
`variables.tf:116-125`:
```hcl
variable "ssh_port" {
  ...
  validation {
    condition     = var.ssh_port >= 0 && var.ssh_port <= 65535
    error_message = "The SSH port must use a valid range from 0 to 65535."
  }
```
This validation is self-contained (references only its own variable) — safe to strengthen in place per the repo's TF-1.11 constraint (cross-variable rules go to validation-contract.tf; this one does NOT need moving).

## Scope
**In scope**: the `ssh_port` variable block in `variables.tf`; `CHANGELOG.md` one 🔧 line. **Out of scope**: everything else, including other port variables (report, don't touch, if you notice the same weakness elsewhere).

## Steps
### Step 1
Condition → `var.ssh_port >= 1 && var.ssh_port <= 65535 && floor(var.ssh_port) == var.ssh_port`; error message updated to "must be an integer between 1 and 65535".
**Verify**: fmt+validate pass; scratch provider-free console check: expression with 0, 22.5 → false; 22, 65535 → true (paste evidence).

## Done criteria
- [ ] New condition in place; console evidence; fmt+validate; changelog line; only in-scope files; README row updated.

## STOP conditions
- Any in-repo config (tests/presets, examples) sets ssh_port outside the new range → STOP and report before merging a breaking tightening.
