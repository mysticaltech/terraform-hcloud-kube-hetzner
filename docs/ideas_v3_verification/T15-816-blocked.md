# T15 / Discussion #816 Blocker Note

Status: blocked pending design confirmation.

## Blocker
Kustomization split and optional Ansible path need phased architecture.

## Detail
Refactoring terraform_data.kustomization and introducing Ansible day-2 workflow impacts bootstrap ordering and requires phased rollout/tests.

## Proposed Next Implementation Steps
1. Finalize compatibility constraints and migration strategy.
2. Implement minimal-safe code changes behind backward-compatible defaults.
3. Validate with terraform fmt, terraform validate, terraform init -upgrade, and terraform plan against upgrade scenarios.
