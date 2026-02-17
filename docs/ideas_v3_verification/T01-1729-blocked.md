# T01 / Discussion #1729 Blocker Note

Status: blocked pending design confirmation.

## Blocker
Multi-network for_each requires migration-safe network/subnet redesign.

## Detail
Direct changes to hcloud_network and subnet topology can trigger destructive replacements; design must include upgrade-safe state migration strategy.

## Proposed Next Implementation Steps
1. Finalize compatibility constraints and migration strategy.
2. Implement minimal-safe code changes behind backward-compatible defaults.
3. Validate with terraform fmt, terraform validate, terraform init -upgrade, and terraform plan against upgrade scenarios.
