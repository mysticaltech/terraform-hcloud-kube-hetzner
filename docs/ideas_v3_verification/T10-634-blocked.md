# T10 / Discussion #634 Blocker Note

Status: blocked pending design confirmation.

## Blocker
Release-pinned Leap Micro snapshot defaults require tested IDs per release.

## Detail
The repository does not contain canonical tested snapshot IDs; values must come from release automation or maintainer-provided test matrix.

## Proposed Next Implementation Steps
1. Finalize compatibility constraints and migration strategy.
2. Implement minimal-safe code changes behind backward-compatible defaults.
3. Validate with terraform fmt, terraform validate, terraform init -upgrade, and terraform plan against upgrade scenarios.
