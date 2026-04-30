# M8-M10 Docs, Tests, And Release Gate

## Write Set

- `README.md`
- `kube.tf.example`
- `docs/llms.md`
- `docs/terraform.md`
- `CHANGELOG.md`
- `MIGRATION.md`
- `docs/v2-to-v3-migration.md`
- `.claude/skills/kh-assistant/SKILL.md`
- `.claude/skills/test-changes/SKILL.md`
- `.claude/skills/sync-docs/SKILL.md`
- `.claude/skills/prepare-release/SKILL.md`
- `.claude/skills/migrate-v2-to-v3/SKILL.md`
- `examples/tailscale-node-transport/README.md`

## Tests

- `terraform fmt -recursive`
- no live `null_resource` or `hashicorp/null`
- `terraform init -backend=false`
- `terraform validate`
- OpenTofu temp-copy validate
- `kube.tf.example` parse validation
- targeted Tailscale static plan matrix
- live Hetzner/Tailscale smoke tests with cleanup

