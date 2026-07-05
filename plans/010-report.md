# Plan 010 report: stable node keys

## Executive summary

The churn reproduces. Static inspection and a plan-only address-set fixture both show that existing control-plane and agent pools are rekeyed when a nodepool is inserted before them. The current key shape embeds the list index:

- Control-plane count nodes: `format("%s-%s-%s", pool_index, node_index, nodepool_obj.name)` in `locals.tf:926-929`.
- Control-plane map nodes: `format("%s-%s-%s", pool_index, node_key, nodepool_obj.name)` in `locals.tf:963-966`.
- Agent count nodes: `format("%s-%s-%s", pool_index, node_index, nodepool_obj.name)` in `locals.tf:1024-1028`.
- Agent map nodes: `format("%s-%s-%s", pool_index, node_key, nodepool_obj.name)` in `locals.tf:1067-1071`.

The strongest path is not a blind v3 key migration. The migration blast radius is large, and per-user historical pool order is required to map old addresses safely. Recommended sequencing:

1. v3.0: add an explicit append-only nodepool order contract and docs. This makes the current sharp edge loud without moving state.
2. v3.x: ship a dry-run migration/audit helper that computes old-index -> stable-name mappings from user-supplied current order and state.
3. v4.0: switch static nodes and per-nodepool subnets to stable name-based keys, with generated `moved` blocks or generated `terraform state mv` commands and mandatory live upgrade gates.

## Drift and runtime checks

- Drift command: `git diff --stat e506cc4..HEAD -- locals.tf control_planes.tf agents.tf main.tf`
- Result: empty output. The plan's drift STOP condition did not trigger.
- `HCLOUD_TOKEN`: absent. I did not print any token value.
- Full-module cloud plans were therefore not attempted; evidence below uses the plan-approved address-set technique with a local `terraform_data` fixture and no cloud provider.

## Inventory

### Index-bearing node keys

`local.control_plane_nodes` is the merge of two maps whose keys begin with `pool_index`:

- `local.control_plane_nodes_from_integer_counts`: `"<pool_index>-<node_index>-<pool_name>"`; list insertion changes every later pool's node key.
- `local.control_plane_nodes_from_maps_for_counts`: `"<pool_index>-<node_key>-<pool_name>"`; explicit node keys are stable only inside a pool, not across pool reorder.

`local.agent_nodes` has the same shape for agent pools. The unique-name validation in `variables.tf:983-991` and `variables.tf:1238-1246` prevents name collisions but does not protect the address key, because the key still starts with list position.

### Control-plane blast radius

Every `for_each = local.control_plane_nodes` consumer inherits the index-bearing key:

- `hcloud_primary_ip.control_planes_ipv4` and `hcloud_primary_ip.control_planes_ipv6` at `control_planes.tf:1-24`.
- `module.control_planes` at `control_planes.tf:33-61`.
- Floating IP resource/data/assignment/configuration at `control_planes.tf:106-149`.
- Distribution config and install `terraform_data`: `control_plane_config_rke2`, `control_plane_config`, `audit_policy`, `authentication_config`, `control_planes_rke2`, and `control_planes` at `control_planes.tf:489-810`.
- Tailscale bootstrap `terraform_data.tailscale_control_planes` at `tailscale.tf:1-31`.
- Attached volume locals and resources: keys are `"<node_key>-<volume_idx>"` in `control_planes.tf:350-365`, then consumed by `hcloud_volume.attached_control_plane_volume` and `terraform_data.configure_attached_control_plane_volume` at `control_planes.tf:813-835`.

There are also singleton resources that are not themselves node-keyed but are affected by key ordering. `init.tf` repeatedly selects `keys(module.control_planes)[0]` for first-control-plane setup (`init.tf:75-179`, `init.tf:226-323`). If a new lexicographically-first key appears, the selected bootstrap node can change.

### Agent blast radius

Every `for_each = local.agent_nodes` consumer inherits the index-bearing key:

- `hcloud_primary_ip.agents_ipv4` and `hcloud_primary_ip.agents_ipv6` at `agents.tf:1-24`.
- `module.agents` at `agents.tf:33-61`.
- Agent config and install `terraform_data.agent_config` and `terraform_data.agents` at `agents.tf:223-344`.
- Longhorn volumes and configuration at `agents.tf:346-445`.
- Attached volume locals and resources: keys are `"<node_key>-<volume_idx>"` in `agents.tf:205-220`, then consumed by `hcloud_volume.attached_agent_volume` and `terraform_data.configure_attached_agent_volume` at `agents.tf:448-470`.
- Agent floating IP resources/data/assignment/rdns/configuration at `agents.tf:542-590`.
- Tailscale bootstrap `terraform_data.tailscale_agents` at `tailscale.tf:34-63`.

### Network and subnet blast radius

`local.nodepool_network_refs` embeds node keys in data-source keys:

- `"control-plane:${node_key}" => node.network_id`
- `"agent:${node_key}" => node.network_id`
- `"autoscaler:${index}" => ...`

That map is consumed by `data.hcloud_network.additional_nodepool_networks` at `main.tf:31-33`. Data-source state is less important than managed resources, but the same key churn affects plan graph shape.

Per-nodepool subnets are count-indexed:

- `hcloud_network_subnet.control_plane[count.index]` uses `length(var.control_plane_nodepools)` at `main.tf:37-42`.
- `hcloud_network_subnet.agent[count.index]` uses `length(var.agent_nodepools)` and `var.agent_nodepools[count.index].subnet_ip_range` at `main.tf:45-50`.
- Control-plane servers select subnets by scanning the current nodepool list for `each.value.nodepool_name` at `control_planes.tf:61`.
- Agent servers do the same at `agents.tf:61`.

This means a list insertion changes which subnet address a stable pool name resolves to. Agent custom `subnet_ip_range` is directly attached to `count.index`, so the same count address can change its semantic nodepool and its configured CIDR.

Load-balancer network singletons depend on subnet `[0]` (`control_planes.tf:222-228`, `init.tf:23-40`). They are not nodepool-keyed, but their behavior can shift when the semantic meaning of subnet `[0]` shifts.

Placement groups are related but not the primary key defect. Compatibility placement groups are count-indexed (`placement_groups.tf:61-76`), but their index count is driven by `placement_group_index` and group sizing rather than raw list position. Reordering pools can still change shared placement-group composition when users rely on defaults, so migration tests should include placement groups.

## Evidence: plan-only address churn

Because `HCLOUD_TOKEN` was absent, I used a local scratch Terraform root with `terraform_data` resources and the same key formulas. It ran `terraform init -backend=false` and two `terraform plan -refresh=false` commands: one baseline and one with a new pool inserted before existing pools. No apply and no cloud provider were used.

Commands:

```bash
terraform init -backend=false -input=false
terraform plan -input=false -refresh=false -out=baseline.tfplan -var-file=baseline.tfvars
terraform show -json baseline.tfplan > baseline.plan.json
terraform plan -input=false -refresh=false -out=pool-inserted.tfplan -var-file=pool-inserted.tfvars
terraform show -json pool-inserted.tfplan > pool-inserted.plan.json
jq -r '.resource_changes[].address' baseline.plan.json | sort > baseline.addresses
jq -r '.resource_changes[].address' pool-inserted.plan.json | sort > pool-inserted.addresses
comm -23 baseline.addresses pool-inserted.addresses
comm -13 baseline.addresses pool-inserted.addresses
```

Baseline planned address count: `15`.
Pool-inserted planned address count: `21`.

Addresses present in baseline but absent after insertion, which would be destroy-side addresses for an already-applied state:

```text
terraform_data.agent_attached_volume["1-0-workers-b-0"]
terraform_data.agent_longhorn_volume["0-0-workers-a"]
terraform_data.agent_primary_ip["0-0-workers-a"]
terraform_data.agent_primary_ip["1-0-workers-b"]
terraform_data.agent_server["0-0-workers-a"]
terraform_data.agent_server["1-0-workers-b"]
terraform_data.control_plane_attached_volume["0-0-cp-a-0"]
terraform_data.control_plane_primary_ip["0-0-cp-a"]
terraform_data.control_plane_primary_ip["1-0-cp-b"]
terraform_data.control_plane_server["0-0-cp-a"]
terraform_data.control_plane_server["1-0-cp-b"]
```

New addresses after insertion:

```text
terraform_data.agent_attached_volume["2-0-workers-b-0"]
terraform_data.agent_longhorn_volume["1-0-workers-a"]
terraform_data.agent_primary_ip["0-0-workers-new"]
terraform_data.agent_primary_ip["1-0-workers-a"]
terraform_data.agent_primary_ip["2-0-workers-b"]
terraform_data.agent_server["0-0-workers-new"]
terraform_data.agent_server["1-0-workers-a"]
terraform_data.agent_server["2-0-workers-b"]
terraform_data.agent_subnet[2]
terraform_data.control_plane_attached_volume["1-0-cp-a-0"]
terraform_data.control_plane_primary_ip["0-0-cp-new"]
terraform_data.control_plane_primary_ip["1-0-cp-a"]
terraform_data.control_plane_primary_ip["2-0-cp-b"]
terraform_data.control_plane_server["0-0-cp-new"]
terraform_data.control_plane_server["1-0-cp-a"]
terraform_data.control_plane_server["2-0-cp-b"]
terraform_data.control_plane_subnet[2]
```

Same-address subnet entries also changed semantic ownership:

```text
terraform_data.agent_subnet[0]
  baseline={"ip_range":"10.42.0.0/24","nodepool_name":"workers-a"}
  inserted={"ip_range":"10.0.0.0/24","nodepool_name":"workers-new"}
terraform_data.agent_subnet[1]
  baseline={"ip_range":"10.43.0.0/24","nodepool_name":"workers-b"}
  inserted={"ip_range":"10.42.0.0/24","nodepool_name":"workers-a"}
terraform_data.control_plane_subnet[0]
  baseline={"ip_range":"10.0.15.0/24","nodepool_name":"cp-a"}
  inserted={"ip_range":"10.0.15.0/24","nodepool_name":"cp-new"}
terraform_data.control_plane_subnet[1]
  baseline={"ip_range":"10.0.14.0/24","nodepool_name":"cp-b"}
  inserted={"ip_range":"10.0.14.0/24","nodepool_name":"cp-a"}
```

That proves the defect class: list insertion before existing pools changes node resource addresses and shifts count-index subnet meaning.

## Terraform migration facts

HashiCorp's Terraform refactoring docs state that `moved` blocks update state addresses without destroying the remote object, and that at least one side using an instance key makes Terraform treat the move as a specific resource instance move. The same docs explicitly say `moved` can switch between keys and show a for_each key rename from `["small"]` to `["tiny"]`, plus count-index to for_each-key moves. Source: [HashiCorp Developer: Refactor modules](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring).

Important limit: a module may only make `moved` statements about its own objects and objects in its child modules, and moved references are resolved relative to where the block is defined. Source: [HashiCorp Developer: Refactor modules](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring).

`terraform state mv` changes state bindings so existing remote objects bind to new resource instance addresses. It supports specific count instances and specific for_each string-key instances, but HashiCorp warns that collaborative users must prevent other plans between the configuration change and state move. Source: [HashiCorp Developer: terraform state mv](https://developer.hashicorp.com/terraform/cli/commands/state/mv).

## Options

### Option A: name-based keys with generated `moved` blocks

Design:

- Replace node keys with stable name-based keys, e.g. `format("%s:%s", nodepool_obj.name, node_index)` for count nodes and `format("%s:%s", nodepool_obj.name, node_key)` for explicit node maps.
- Change per-nodepool subnets from `count` to `for_each` keyed by nodepool name.
- Generate static `moved` blocks for every managed resource whose address includes the old node key:
  - `module.control_planes["old"] -> module.control_planes["new"]`
  - `module.agents["old"] -> module.agents["new"]`
  - root peer resources keyed by nodes, e.g. primary IPs, floating IPs, `terraform_data`, Longhorn volumes, attached volumes, and Tailscale resources.
  - subnet moves from `hcloud_network_subnet.*[old_index] -> hcloud_network_subnet.*["pool-name"]`.

User migration steps:

1. Record old control-plane and agent nodepool order before upgrading.
2. Run a helper that reads old order plus current tfvars and emits a `moved.auto.tf` file.
3. Upgrade to the v4 module code containing name-based keys.
4. Run `terraform plan`; expected output should show move operations, not destroy/create for stable pools.
5. Apply once; retain historical moved blocks for a long compatibility window.

Failure modes:

- Generic module-shipped moved blocks cannot know a user's historical pool order; the helper must generate static HCL.
- If the module is consumed from the registry, users cannot easily place generated moved blocks inside the child module. Root-level moved blocks can target child module addresses only for the caller's child module objects, but the module package cannot dynamically generate per-user moves. This makes a root-side helper possible but operationally delicate.
- Moved blocks cannot be generated with Terraform expressions or `for_each`; every old/new address pair must be literal HCL.
- Missing one peer resource move leaves a destroy/create next to otherwise moved module instances.
- Existing users who previously inserted/reordered pools may already have state whose old indices no longer match the original semantic pool order.

CI/live test needs:

- Stateful upgrade fixture with baseline state using old keys, then v4 config with generated moved blocks.
- Plan JSON assertion that existing servers, primary IPs, volumes, Longhorn volumes, floating IP assignments, and subnets have no delete/create actions.
- Live upgrade gate with at least two control-plane pools, two agent pools, custom agent subnets, attached volumes, Longhorn, and optional floating/primary IPs.
- Destroy gate after migration.

Docs burden:

- High. Needs a migration guide, helper examples for registry and source-checkout consumers, warnings about preserving the generated file until every workspace has applied, and troubleshooting for missing/renamed pools.

Assessment:

- Technically clean end-state, but too risky for v3 without a mature helper and live proof.

### Option B: name-based keys with documented `terraform state mv` script

Design:

- Same name-based key change as Option A.
- Instead of `moved` blocks, ship `scripts/generate-node-key-state-mv` that emits ordered `terraform state mv` commands for the caller's root module address.
- Use `terraform state mv -dry-run` and `terraform state pull` backup first.

User migration steps:

1. Pull and back up state.
2. Run helper with `--module-address 'module.kube_hetzner' --old-control-plane-order ... --old-agent-order ...`.
3. Review generated `terraform state mv` commands.
4. Stop concurrent Terraform activity and acquire state lock.
5. Run the generated moves.
6. Upgrade config to name-key module version.
7. Plan; expected result is no destroy/create for old pools.

Failure modes:

- Operational race: if anyone plans/applies between config change and state moves, Terraform can propose deletes. HashiCorp explicitly warns about this class for collaborative state moves.
- Harder for less-experienced users; quoting for for_each keys is shell-sensitive.
- Remote backend permissions and lock behavior vary.
- A failed partially-completed move run can leave state split across old and new addresses; the helper needs idempotent detection and a rollback story.

CI/live test needs:

- Script golden tests from realistic tfvars/state address lists.
- Dry-run parser tests.
- Upgrade simulation against local state with generated commands.
- Same live upgrade/destroy gate as Option A.

Docs burden:

- Very high. This is safest for module maintainers because it avoids per-user HCL generation inside the module package, but it pushes more operational responsibility to users.

Assessment:

- Viable as a power-user migration path, not a default v3 user experience.

### Option C: keep indexes and add an append-only order contract

Design:

- Keep all current addresses.
- Add user-pinned order lists and fail plan if current list order does not have the pinned list as a prefix.
- This rejects reorders and insertions anywhere except the end. It does not prevent a user from intentionally editing the pinned order to bypass the contract, but it makes accidental destructive churn loud.

Exact validation-contract sketch:

```hcl
variable "control_plane_nodepool_order" {
  description = "Optional append-only safety contract for index-keyed control_plane_nodepools. Set to the current ordered list of control-plane nodepool names, then only append new names."
  type        = list(string)
  default     = []
}

variable "agent_nodepool_order" {
  description = "Optional append-only safety contract for index-keyed agent_nodepools. Set to the current ordered list of agent nodepool names, then only append new names."
  type        = list(string)
  default     = []
}

locals {
  configured_control_plane_nodepool_names = [for np in var.control_plane_nodepools : np.name]
  configured_agent_nodepool_names         = [for np in var.agent_nodepools : np.name]

  control_plane_nodepool_order_contract_ok = (
    length(var.control_plane_nodepool_order) == 0 ||
    (
      length(var.control_plane_nodepool_order) <= length(local.configured_control_plane_nodepool_names) &&
      slice(local.configured_control_plane_nodepool_names, 0, length(var.control_plane_nodepool_order)) == var.control_plane_nodepool_order
    )
  )

  agent_nodepool_order_contract_ok = (
    length(var.agent_nodepool_order) == 0 ||
    (
      length(var.agent_nodepool_order) <= length(local.configured_agent_nodepool_names) &&
      slice(local.configured_agent_nodepool_names, 0, length(var.agent_nodepool_order)) == var.agent_nodepool_order
    )
  )
}

resource "terraform_data" "validation_contract" {
  input = true

  lifecycle {
    precondition {
      condition     = local.control_plane_nodepool_order_contract_ok
      error_message = "control_plane_nodepools are index-keyed in this release. Reordering existing pools or inserting before the end can destroy/recreate nodes. Keep control_plane_nodepool_order as the old prefix and only append new pools, or follow the documented state migration procedure."
    }

    precondition {
      condition     = local.agent_nodepool_order_contract_ok
      error_message = "agent_nodepools are index-keyed in this release. Reordering existing pools or inserting before the end can destroy/recreate nodes. Keep agent_nodepool_order as the old prefix and only append new pools, or follow the documented state migration procedure."
    }
  }
}
```

User migration steps:

1. Existing users set `control_plane_nodepool_order = [for current pools, in current order]` and `agent_nodepool_order = [...]`.
2. New pools are appended to the variable and to the corresponding nodepool list.
3. Reorder/insert-before-end attempts fail before resource changes.

Failure modes:

- Default `[]` cannot protect users who do not opt in.
- Making the lists required would itself be a breaking input change.
- Users can bypass the guard by editing the pinned order to match an unsafe reorder.
- It only prevents accidental churn; it does not deliver stable keys.

CI/live test needs:

- Validation tests that append passes, middle insertion fails, reorder fails, delete fails unless the user intentionally updates the order contract.
- A docs fixture showing how to pin the current order.

Docs burden:

- Moderate. This is mostly a safety contract and migration warning.

Assessment:

- Best bounded v3 mitigation. It is honest about the sharp edge and avoids state migration risk.

### Option D: hybrid freeze now, migrate keys in v4

Design:

- v3.0: implement Option C and document append-only ordering as the safe contract.
- v3.x: add a read-only helper that inventories current state and generates a migration preview:
  - old node key -> proposed stable key
  - peer resource addresses that must move
  - subnet count index -> pool name
  - warnings for missing pools, removed pools, duplicate state, custom subnet ranges, attached volumes, Longhorn, floating IPs, and first-control-plane assumptions
- v4.0: implement Option A or B after helper and live gates are proven.

User migration steps:

1. Pin order in v3.
2. Run helper in dry-run mode and commit its report to the user's upgrade notes.
3. Upgrade to v4 with generated `moved` blocks or run generated `terraform state mv` commands.
4. Apply once, then verify node/server identity, subnets, volumes, and cluster health.

Failure modes:

- Delays the real fix to v4.
- Requires maintaining both the freeze contract and migration helper.
- Users who ignore the v3 contract can still create harder-to-migrate state before v4.

CI/live test needs:

- All Option C tests now.
- Helper golden tests in v3.x.
- Full stateful upgrade and live apply/upgrade/destroy gates before v4 tag.

Docs burden:

- Highest overall, but split across releases and safer operationally.

Assessment:

- Recommended. It is the strongest defensible path for the v3 line.

## Recommendation

Choose Option D.

Do not migrate node keys in v3. The current bug is real, but the migration requires per-user historical order and touches servers, IPs, volumes, provisioner state, Tailscale bootstrap state, Longhorn, attached volumes, network data keys, and count-indexed subnets. A partial migration is more dangerous than the current documented sharp edge.

The v3 deliverable should be:

- `control_plane_nodepool_order` and `agent_nodepool_order` append-only validation contract.
- README/MIGRATION docs that explicitly say existing users must append nodepools only unless using the migration procedure.
- A local test fixture proving append passes and insert/reorder fails.

The v4 deliverable should be:

- Stable keys based on unique nodepool names plus stable node indexes/keys.
- Per-nodepool subnets keyed by nodepool name, not count index.
- A generated migration path, selected after prototyping both:
  - generated `moved` blocks for static HCL migrations where feasible;
  - generated `terraform state mv` scripts where root-module/module-package boundaries make generated moved blocks awkward.
- A mandatory live upgrade gate before release.

## Done criteria checklist

- [x] Drift check run; no heavy drift found.
- [x] Inventory covers index-bearing node maps, count-indexed subnets, and key consumers.
- [x] At least three options analyzed; four included.
- [x] `moved` block key-change support researched and cited.
- [x] `terraform state mv` support and operational warning researched and cited.
- [x] Churn reproduced with plan-only address-set evidence and no cloud apply.
- [x] Recommendation includes release sequencing and exact validation-contract sketch.
- [x] No module code changed.
- [x] `plans/README.md` left untouched per executor override.
