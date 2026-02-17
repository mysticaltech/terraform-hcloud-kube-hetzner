# T16 / Discussion #1568 Blocker Note

Status: blocked pending design confirmation.

## Blocker
Calico operator migration needs conversion and upgrade plan.

## Detail
Switching to Tigera operator requires new CR templates, values mapping, and safe migration from existing calico.yaml patching flow.

## Proposed Next Implementation Steps
1. Finalize compatibility constraints and migration strategy.
2. Implement minimal-safe code changes behind backward-compatible defaults.
3. Validate with terraform fmt, terraform validate, terraform init -upgrade, and terraform plan against upgrade scenarios.
