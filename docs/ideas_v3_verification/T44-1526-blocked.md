# T44 / Discussion #1526 Blocker Note

Status: blocked pending design confirmation.

## Blocker
Depends on multi-network architecture from #1729.

## Detail
Route exposure controls for vSwitch/extra networks depend on the unresolved multi-network model and cannot be implemented safely first.

## Proposed Next Implementation Steps
1. Finalize compatibility constraints and migration strategy.
2. Implement minimal-safe code changes behind backward-compatible defaults.
3. Validate with terraform fmt, terraform validate, terraform init -upgrade, and terraform plan against upgrade scenarios.
