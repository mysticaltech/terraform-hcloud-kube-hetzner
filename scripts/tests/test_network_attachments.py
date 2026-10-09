# /// script
# dependencies = ["python-hcl2==7.3.1"]
# ///
"""Credential-free plans for the production Network attachment count.

Run with uv run scripts/tests/test_network_attachments.py --cli terraform
or --cli tofu. --ref evaluates an exact local Git ref without checking it out.
Only production variable types/defaults, dependent locals and the attachment
precondition are copied; this is not full-module or live cloud acceptance.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

import hcl2


ROOT_LOCAL = "validation_network_attachment_count_by_network"
LIMIT_ERROR = "at most 100 attached resources"


def source(repo, filename, ref):
    if ref:
        return subprocess.check_output(
            ["git", "show", f"{ref}:{filename}"], cwd=repo, text=True
        )
    return (repo / filename).read_text()


def references(node, namespace):
    result = set()
    for term in node.find_data("get_attr_expr_term"):
        base, attribute = term.children
        if (base.data == "expr_term" and base.children[0].data == "identifier"
                and str(base.children[0].children[0]) == namespace):
            result.add(str(attribute.children[0].children[0]))
    return result


def configuration(repo, ref):
    locals_source = source(repo, "validation-locals.tf", ref)
    locals_ast = hcl2.parses(locals_source)
    attributes = {str(node.children[0].children[0]): node
                  for node in locals_ast.find_data("attribute")}
    needed = set()
    pending = {ROOT_LOCAL}
    variables = set()
    while pending:
        name = pending.pop()
        if name in needed:
            continue
        node = attributes[name]
        needed.add(name)
        variables.update(references(node, "var"))
        pending.update(references(node, "local") - needed)
    local_blocks = [locals_source[node.meta.start_pos:node.meta.end_pos]
                    for name, node in attributes.items() if name in needed]

    # Include flags/version even when deliberately ignored by the hard limit.
    variables.update(("cluster_autoscaler_extra_args", "cluster_autoscaler_version", "network_region"))
    variable_source = source(repo, "variables.tf", ref)
    variable_blocks = []
    for node in hcl2.parses(variable_source).find_data("block"):
        if str(node.children[0].children[0]) != "variable":
            continue
        text = variable_source[node.meta.start_pos:node.meta.end_pos]
        name = next(iter(hcl2.loads(text)["variable"][0]))
        if name in variables:
            definitions = [variable_source[attr.meta.start_pos:attr.meta.end_pos]
                           for attr in node.find_data("attribute")
                           if str(attr.children[0].children[0]) in {"type", "default"}]
            variable_blocks.append(f'variable "{name}" {{\n' + "\n".join(definitions) + "\n}")
    assert len(variable_blocks) == len(variables), "Missing production input schema"

    contract_source = source(repo, "validation-contract.tf", ref)
    contracts = [contract_source[node.meta.start_pos:node.meta.end_pos]
                 for node in hcl2.parses(contract_source).find_data("block")
                 if str(node.children[0].children[0]) == "precondition"
                 and ROOT_LOCAL in contract_source[node.meta.start_pos:node.meta.end_pos]]
    assert len(contracts) == 1, "Expected exactly one production attachment precondition"
    provider = ''
    if any("provider::semvers::" in text for text in local_blocks):
        provider = ('terraform {\n required_providers {\n semvers = {\n'
                    'source = "anapsix/semvers"\n version = ">= 0.7.1"\n }\n }\n }\n')
    return (provider + "\n".join(variable_blocks) + "\nlocals {\n" +
            "\n".join(local_blocks) + '\n}\nresource "terraform_data" "attachments" {\n'
            'lifecycle {\n' + contracts[0] + '\n}\n}\n'
            'output "attachments" { value = local.' + ROOT_LOCAL + ' }\n')


def static_pool(count=1, **values):
    return {"name": "static", "server_type": "cx23", "location": "nbg1",
            "labels": [], "taints": [], "count": count, **values}


def autoscaler_pool(max_nodes, **values):
    return {"name": "autoscaled", "server_type": "cx23", "location": "nbg1",
            "min_nodes": 0, "max_nodes": max_nodes, **values}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", choices=("terraform", "tofu"), default="terraform")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--ref")
    args = parser.parse_args()
    repo = args.repo.resolve()
    env = {key: value for key, value in os.environ.items() if key in {"PATH", "HOME"}}
    env.update(TF_CLI_CONFIG_FILE="/dev/null", TF_IN_AUTOMATION="1")
    scratch = repo / ".terraform" / "network-attachment-tests"
    scratch.mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = str(scratch)
    with tempfile.TemporaryDirectory(prefix="case-", dir=scratch) as directory:
        root = Path(directory)
        (root / "main.tf").write_text(configuration(repo, args.ref))

        def run(*command):
            return subprocess.run([args.cli, *command], cwd=root, env=env, text=True, capture_output=True)

        def checked(*command):
            result = run(*command)
            assert result.returncode == 0, result.stdout + result.stderr
            return result.stdout

        checked("fmt")
        checked("init", "-backend=false", "-input=false", "-no-color")
        checked("validate", "-no-color")
        base = {"control_plane_nodepools": [static_pool()],
                "agent_nodepools": [static_pool()],
                "autoscaler_nodepools": [autoscaler_pool(97)]}
        cases = 0

        def plan(name, values, expected, over_limit=False):
            nonlocal cases
            (root / "case.tfvars.json").write_text(json.dumps({**base, **values}))
            result = run("plan", "-refresh=false", "-input=false", "-no-color", "-out=plan",
                         "-var-file=case.tfvars.json")
            output = result.stdout + result.stderr
            if over_limit:
                assert result.returncode != 0 and LIMIT_ERROR in output, f"{name}: {output}"
            else:
                assert result.returncode == 0, f"{name}: {output}"
                data = json.loads(checked("show", "-json", "plan"))
                actual = data["planned_values"]["outputs"]["attachments"]["value"]
                assert actual == expected, f"{name}: {actual} != {expected}"
                assert all("delete" not in change["change"]["actions"]
                           for change in data["resource_changes"]), name
            cases += 1

        plan("exact-100", {}, {"0": 100})
        plan("101-rejected", {"autoscaler_nodepools": [autoscaler_pool(98)]}, None, True)
        flag_sets = [[], ["--max-nodes-total=99"], ["--max-nodes-total=0"],
                     ["--max-nodes-total=-1"], ["--max-nodes-total=invalid"],
                     ["--max-nodes-total=1.5"], ["--max-nodes-total"],
                     ["--max-nodes-total", "99"], ["--max_nodes_total=99"],
                     ["-max-nodes-total=99"], ["--", "--max-nodes-total=99"],
                     ["--max-nodes-total=1", "--max-nodes-total=99"],
                     ["--max-nodes-total=99", "--max-nodes-total=0"],
                     ["--max-nodes-total=99", "--max-nodes-total", "500"],
                     ["--max-nodes-total=1", "--enforce-node-group-min-size=true"],
                     ["--max-nodes-total=1", "--enforce-node-group-min-size=false"],
                     ["--max-nodes-total=99", "--enforce-node-group-min-size", "false"]]
        for version in ("v1.33.3", "v1.34.5", "v1.35.0", "v1.36.1", "malformed"):
            for index, flags in enumerate(flag_sets):
                values = {"agent_nodepools": [static_pool(3)],
                          "autoscaler_nodepools": [autoscaler_pool(100)],
                          "cluster_autoscaler_version": version,
                          "cluster_autoscaler_extra_args": flags}
                plan(f"flags-{version}-{index}-105-rejected", values, None, True)
        plan("pool-bound-still-passes", {"autoscaler_nodepools": [autoscaler_pool(50)],
             "cluster_autoscaler_extra_args": ["--max-nodes-total=1000"]}, {"0": 53})
        plan("fallback-pools-are-additive", {"autoscaler_nodepools": [autoscaler_pool(49),
             autoscaler_pool(49, name="fallback")], "cluster_autoscaler_version": "v1.35.0",
             "cluster_autoscaler_extra_args": ["--max-nodes-total=99"]}, None, True)
        plan("min-nodes-do-not-hide-maxima", {"autoscaler_nodepools": [autoscaler_pool(98, min_nodes=1)],
             "cluster_autoscaler_version": "v1.35.0",
             "cluster_autoscaler_extra_args": ["--max-nodes-total=1",
                                                "--enforce-node-group-min-size=true"]}, None, True)
        nat = {"server_type": "cx23", "location": "nbg1"}
        plan("nat-and-two-load-balancers", {"control_plane_nodepools": [static_pool(3)],
             "agent_nodepools": [], "autoscaler_nodepools": [autoscaler_pool(94)],
             "enable_control_plane_load_balancer": True, "nat_router": nat}, {"0": 100})
        plan("nat-redundancy-counted", {"control_plane_nodepools": [static_pool(3)],
             "agent_nodepools": [], "autoscaler_nodepools": [autoscaler_pool(94)],
             "enable_control_plane_load_balancer": True,
             "nat_router": {**nat, "enable_redundancy": True, "standby_location": "fsn1"}}, None, True)
        plan("named-static-nodes-counted", {"control_plane_nodepools": [static_pool(0, nodes={"a": {}, "b": {}})],
             "agent_nodepools": [static_pool(0, nodes={"a": {}, "b": {}, "c": {}})],
             "autoscaler_nodepools": [autoscaler_pool(94)]}, {"0": 100})
        plan("combined-load-balancer-counted-once", {"enable_control_plane_load_balancer": True,
             "reuse_control_plane_load_balancer": True}, {"0": 100})
        plan("tailscale-external-pools", {"node_transport_mode": "tailscale", "ingress_controller": "none",
             "autoscaler_nodepools": [autoscaler_pool(98), autoscaler_pool(100, name="external",
             network_scope="external", network_id=123)]}, {"0": 100, "123": 100})
        plan("external-network-over-limit", {"node_transport_mode": "tailscale", "ingress_controller": "none",
             "autoscaler_nodepools": [autoscaler_pool(101, network_scope="external", network_id=123)]}, None, True)
        plan("private-control-plane-fanout", {"autoscaler_nodepools": [],
             "agent_nodepools": [static_pool(99, network_scope="external", network_id=123)]}, {"0": 2, "123": 100})
        plan("extra-network-static-fanout", {"extra_network_ids": [123], "autoscaler_nodepools": [],
             "agent_nodepools": [static_pool(99)]}, None, True)
        plan("named-agent-network-override", {"node_transport_mode": "tailscale", "ingress_controller": "none",
             "autoscaler_nodepools": [], "agent_nodepools": [static_pool(1, network_scope="external", network_id=123,
             nodes={"primary": {"network_scope": "primary", "network_id": None}, "inherited": {}})]},
             {"0": 2, "123": 2})
        print(f"PASS {args.cli}: {cases} production attachment plans; no HCloud credentials or calls")


if __name__ == "__main__":
    main()
