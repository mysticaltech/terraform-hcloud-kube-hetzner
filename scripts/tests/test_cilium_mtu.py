# /// script
# dependencies = ["python-hcl2==7.3.1"]
# ///
"""Provider-free Cilium underlay MTU plans using production HCL.

Run with uv run scripts/tests/test_cilium_mtu.py --cli terraform (or tofu).
--repo can reproduce a baseline without modifying that source checkout.
These test the MTU expressions and Robot input type/default, not full-module
validation contracts, upgrades or live datapath behavior.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

import hcl2


def configuration(repo):
    source = (repo / "locals.tf").read_text()
    start = source.index("  cilium_routing_mode_effective")
    end = source.index("\n\n", start)
    source = "locals {\n" + source[start:end] + "\n}"
    names = {"cilium_mtu_base", "cilium_mtu_effective"}
    expressions = [source[node.meta.start_pos:node.meta.end_pos]
                   for node in hcl2.parses(source).find_data("attribute")
                   if str(node.children[0].children[0]) in names]
    assert any(text.startswith("cilium_mtu_effective") for text in expressions)
    variables = (repo / "variables.tf").read_text()
    start = variables.index('variable "extra_robot_nodes" {')
    end = variables.index('\nvariable "', start + 1)
    variable_source = variables[start:end]
    attributes = [variable_source[node.meta.start_pos:node.meta.end_pos]
                  for node in hcl2.parses(variable_source).find_data("attribute")
                  if str(node.children[0].children[0]) in {"type", "default"}]
    assert len(attributes) == 2
    robot_variable = 'variable "extra_robot_nodes" {\n' + "\n".join(attributes) + "\n}"
    return robot_variable + "\nlocals {\n" + "\n".join(expressions) + "\n}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", choices=("terraform", "tofu"), default="terraform")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    env = {key: value for key, value in os.environ.items()
           if key in {"PATH", "HOME", "TMPDIR"}}
    env.update(TF_CLI_CONFIG_FILE="/dev/null", TF_IN_AUTOMATION="1")

    def robot(mtu=None):
        node = {"host": "192.0.2.10", "private_ipv4": "10.0.2.10", "vlan_id": 4000}
        if mtu is not None:
            node["mtu"] = mtu
        return node

    cases = (
        ("cloud-only", {}, 1450),
        ("Robot default without CCM", {"extra_robot_nodes": [robot()]}, 1350),
        ("explicit vSwitch MTU without CCM", {"extra_robot_nodes": [robot(1400)]}, 1400),
        ("smallest declared underlay", {"extra_robot_nodes": [robot(1400), robot(1300)]}, 1300),
        ("larger Robot cannot raise base", {"extra_robot_nodes": [robot(9000)]}, 1450),
        ("CCM alone unchanged", {"robot_ccm": True}, 1350),
        ("CCM with Robot unchanged", {"robot_ccm": True, "extra_robot_nodes": [robot(1400)]}, 1350),
        ("Robot smaller than CCM base", {"robot_ccm": True, "extra_robot_nodes": [robot(1300)]}, 1300),
        ("Tailscale alone unchanged", {"tailscale": True}, 1180),
        ("Tailscale smaller than Robot", {"tailscale": True, "extra_robot_nodes": [robot()]}, 1180),
        ("overlay alone unchanged", {"overlay": True}, 1280),
        ("overlay smaller than Robot", {"overlay": True, "extra_robot_nodes": [robot()]}, 1280),
        ("Flannel values unchanged", {"cni_plugin": "flannel", "extra_robot_nodes": [robot()]}, 1450),
        ("Calico values unchanged", {"cni_plugin": "calico", "extra_robot_nodes": [robot()]}, 1450),
    )
    with tempfile.TemporaryDirectory(prefix="kh-cilium-mtu-", dir="/tmp") as directory:
        root = Path(directory)
        (root / "main.tf").write_text(configuration(args.repo.resolve()))
        (root / "fixtures.tf.json").write_text(json.dumps({
            "variable": {
                "cni_plugin": {"type": "string", "default": "cilium"},
                "robot_ccm": {"type": "bool", "default": False},
                "tailscale": {"type": "bool", "default": False},
                "overlay": {"type": "bool", "default": False},
                "multinetwork_cilium_mtu": {"default": 1280},
                "tailscale_node_transport": {"default": {"kubernetes": {"cni_mtu": 1180}}},
            },
            "locals": {
                "use_robot_ccm": "${var.robot_ccm}",
                "node_transport_tailscale_enabled": "${var.tailscale}",
                "multinetwork_overlay_enabled": "${var.overlay}",
            },
            "output": {"mtu": {"value": "${local.cilium_mtu_effective}"}},
        }))

        def checked(*command):
            result = subprocess.run([args.cli, *command], cwd=root, env=env,
                                    text=True, capture_output=True)
            assert result.returncode == 0, result.stdout + result.stderr
            return result.stdout

        checked("fmt")
        checked("init", "-backend=false", "-input=false")
        checked("validate", "-no-color")
        for name, values, expected in cases:
            (root / "case.tfvars.json").write_text(json.dumps(values))
            checked("plan", "-refresh=false", "-input=false", "-no-color",
                    "-var-file=case.tfvars.json", "-out=plan")
            data = json.loads(checked("show", "-json", "plan"))
            actual = data["planned_values"]["outputs"]["mtu"]["value"]
            assert actual == expected, f"{name}: expected {expected}, got {actual}"
            assert not data.get("resource_changes"), "MTU fixture must remain provider-free"
            print(f"PASS {args.cli}: {name} -> {actual}")


if __name__ == "__main__":
    main()
