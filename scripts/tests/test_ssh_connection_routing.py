# /// script
# dependencies = ["python-hcl2==8.1.0"]
# ///
"""Credential-free SSH route plans using production HCL expressions.

Run with uv run scripts/tests/test_ssh_connection_routing.py --cli terraform
or --cli tofu. This does not prove private-network reachability or live upgrades.
"""

import argparse
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

import hcl2


def attributes(repo, filename, names):
    source = (repo / filename).read_text()
    found = {}
    for node in hcl2.parses_to_tree(source).find_data("attribute"):
        name = str(node.children[0].children[0])
        if name in names:
            assert name not in found, f"Ambiguous attribute: {filename}:{name}"
            found[name] = source[node.meta.start_pos:node.meta.end_pos]
    assert set(found) == set(names), (filename, names, found.keys())
    return found


def configuration(repo):
    expressions = []
    for filename, role in (("agents.tf", "agent"), ("control_planes.tf", "control_plane")):
        selected = attributes(repo, filename, {f"{role}_ips", f"{role}_initial_ips"})
        for expression in selected.values():
            expressions.append(expression.replace(f"module.{role}s", "local.nodes"))
        source = (repo / filename).read_text()
        assert "ssh_use_private_network       = var.ssh_use_private_network" in source

    selected = attributes(repo, "modules/host/locals.tf", {
        "private_connection_host", "default_connection_host", "map_connection_host",
        "suffix_connection_host", "provisioner_connection_host",
    })
    expressions.extend(expression.replace("hcloud_server.server", "var.case.server")
                       for expression in selected.values())
    # Read both autoscaler connection blocks rather than assuming they match.
    source = (repo / "autoscaler-agents.tf").read_text()
    source = source[source.index('resource "terraform_data" "autoscaled_nodes_registries"'):]
    hosts = []
    for node in hcl2.parses_to_tree(source).find_data("block"):
        text = source[node.meta.start_pos:node.meta.end_pos]
        if text.startswith('resource "terraform_data" "autoscaled_nodes_'):
            connection = next(child for child in node.find_data("block")
                              if str(child.children[0].children[0]) == "connection")
            host = next(child for child in connection.find_data("attribute")
                        if str(child.children[0].children[0]) == "host")
            value = source[host.children[-1].meta.start_pos:host.children[-1].meta.end_pos]
            hosts.append(value.replace("each.value", "var.case.server"))
    assert len(hosts) == 2
    expressions.extend(f"autoscaler_{index} = {value}" for index, value in enumerate(hosts))
    # Only rebind input variables; all production precedence expressions stay intact.
    expressions = [expression.replace("var.", "var.case.").replace("var.case.case.", "var.case.")
                   for expression in expressions]
    return '''variable "case" {}
locals {
  nodes = { n = var.case.node }
  name = var.case.node.name
  agent_override_base_names = { n = var.case.name }
  control_plane_override_base_names = { n = var.case.name }
  tailscale_agent_magicdns_hosts = { n = "${var.case.node.name}.${var.case.magicdns}" }
  tailscale_control_plane_magicdns_hosts = local.tailscale_agent_magicdns_hosts
  tailscale_use_tailnet_for_terraform = var.case.tailnet
  tailscale_magicdns_domain = var.case.magicdns
''' + "\n".join(expressions) + '''
}
output "routes" {
  value = {
    initial_agent = local.agent_initial_ips.n
    initial_control_plane = local.control_plane_initial_ips.n
    agent = local.agent_ips.n
    control_plane = local.control_plane_ips.n
    host = local.provisioner_connection_host
    autoscaler_0 = local.autoscaler_0
    autoscaler_1 = local.autoscaler_1
  }
}
'''


def check_consumers(repo):
    paths = {
        "agents.tf": "local.agent_ips[",
        "control_planes.tf": "local.control_plane_ips[",
        "init.tf": ("local.first_control_plane_ip", "self.input.ssh_host"),
        "autoscaler-agents.tf": ("local.first_control_plane_ip", "local.tailscale_use_tailnet_for_terraform"),
        "tailscale.tf": ("local.agent_initial_ips[", "local.control_plane_initial_ips["),
        "modules/host/main.tf": "local.provisioner_connection_host",
        "modules/user_kustomizations/main.tf": "var.ssh_connection.host",
        "modules/user_kustomization_set/main.tf": "var.ssh_connection.host",
        "nat-router.tf": "local.nat_router_connection_host[",
        "robot-nodes.tf": "each.value.host",
    }
    count = 0
    for filename, allowed in paths.items():
        source = (repo / filename).read_text()
        # Connection blocks have scalar attributes; isolate them from unrelated
        # templates whose valid HCL interpolation syntax exceeds this parser.
        blocks = re.findall(r"(?m)^\s*connection \{\n.*?^\s*\}", source, re.S)
        assert len(blocks) == len(re.findall(r"(?m)^\s*connection \{", source))
        for block in blocks:
            host = next(node for node in hcl2.parses_to_tree(block).find_data("attribute")
                        if str(node.children[0].children[0]) == "host")
            expression = block[host.children[-1].meta.start_pos:host.children[-1].meta.end_pos]
            prefixes = (allowed,) if isinstance(allowed, str) else allowed
            assert expression.startswith(prefixes), (filename, expression)
            count += 1
        for trigger in re.findall(r"triggers_replace\s*=\s*\{.*?\}", source, re.S):
            assert "ssh_use_private_network" not in trigger
    assert 'first_control_plane_ip = local.control_plane_ips[' in (repo / "init.tf").read_text()
    assert "local.first_control_plane_ip" in (repo / "kubeconfig.tf").read_text()
    assert "local.first_control_plane_ip" in (repo / "kustomization_user.tf").read_text()
    print(f"PASS source contract: {count} connection consumers; NAT/Robot routes remain independent")


def cases():
    public = "192.0.2.10"
    private = "10.0.0.10"
    ipv6 = "2001:db8::10"
    node = {"name": "test-node-xyz", "ipv4_address": public, "ipv6_address": ipv6,
            "private_ipv4_address": private}
    base = {"node": node, "server": {**node, "network": [{"network_id": 2, "ip": private}]},
            "ssh_use_private_network": False, "node_connection_overrides": {},
            "name": "test-node", "network_id": 2, "connection_host": "",
            "connection_host_suffix": "", "tailnet": False, "magicdns": "example.ts.net"}
    route_names = ("initial_agent", "initial_control_plane", "agent", "control_plane",
                   "host", "autoscaler_0", "autoscaler_1")

    def case(name, update=None, node_update=None, expected=public, route_update=None):
        values = copy.deepcopy(base)
        values.update(update or {})
        values["node"].update(node_update or {})
        values["server"].update(node_update or {})
        if node_update and "private_ipv4_address" in node_update:
            values["server"]["network"] = []
        routes = dict.fromkeys(route_names, expected)
        routes.update(route_update or {})
        return name, values, routes

    yield case("default-public")
    yield case("prefer-private", {"ssh_use_private_network": True}, expected=private)
    yield case("ipv6-fallback", node_update={"ipv4_address": ""}, expected=ipv6)
    yield case("private-before-ipv6", {"ssh_use_private_network": True},
               node_update={"ipv4_address": ""}, expected=private)
    yield case("private-only-nat-fallback", node_update={"ipv4_address": "", "ipv6_address": ""},
               expected=private)
    yield case("no-private-fallback", {"ssh_use_private_network": True},
               node_update={"private_ipv4_address": ""})
    for name in ("test-node", "test-node-xyz"):
        yield case(f"override-{name}", {"ssh_use_private_network": True, "tailnet": True,
                   "node_connection_overrides": {name: "override.example"},
                   "connection_host_suffix": "example.ts.net"}, expected="override.example",
                   route_update={"autoscaler_0": "test-node-xyz.example.ts.net",
                                 "autoscaler_1": "test-node-xyz.example.ts.net"})
    yield case("actual-name-before-base", {"ssh_use_private_network": True,
               "node_connection_overrides": {"test-node": "base.example",
                                             "test-node-xyz": "actual.example"}},
               expected="actual.example", route_update={"autoscaler_0": private, "autoscaler_1": private})
    yield case("explicit-host-first", {"ssh_use_private_network": True,
               "connection_host": "explicit.example"}, expected=private,
               route_update={"host": "explicit.example"})
    yield case("tailscale-cloud-init", {"ssh_use_private_network": True, "tailnet": True,
               "connection_host_suffix": "example.ts.net"}, expected="test-node-xyz.example.ts.net",
               route_update={"initial_agent": private, "initial_control_plane": private})
    yield case("tailscale-remote-exec-bootstrap", {"ssh_use_private_network": True, "tailnet": True},
               expected="test-node-xyz.example.ts.net",
               route_update={"initial_agent": private, "initial_control_plane": private, "host": private})
    yield case("primary-network-before-extra", {"ssh_use_private_network": True,
               "server": {**base["server"], "network": [{"network_id": 1, "ip": "10.1.0.10"},
                                                          {"network_id": 2, "ip": private}]}},
               expected=private, route_update={"autoscaler_0": public, "autoscaler_1": public})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", choices=("terraform", "tofu"), default="terraform")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    check_consumers(args.repo.resolve())
    env = {key: value for key, value in os.environ.items() if key in {"PATH", "HOME", "TMPDIR"}}
    env.update(TF_CLI_CONFIG_FILE="/dev/null", TF_IN_AUTOMATION="1")
    with tempfile.TemporaryDirectory(prefix="kh-ssh-route-", dir="/tmp") as directory:
        root = Path(directory)
        (root / "main.tf").write_text(configuration(args.repo.resolve()))

        def run(*command):
            result = subprocess.run([args.cli, *command], cwd=root, env=env, text=True, capture_output=True)
            assert result.returncode == 0, result.stdout + result.stderr
            return result.stdout

        run("fmt")
        run("init", "-backend=false", "-input=false")
        run("validate", "-no-color")
        count = 0
        for name, values, expected in cases():
            (root / "case.auto.tfvars.json").write_text(json.dumps({"case": values}))
            run("plan", "-refresh=false", "-input=false", "-no-color", "-out=plan")
            plan = json.loads(run("show", "-json", "plan"))
            actual = plan["planned_values"]["outputs"]["routes"]["value"]
            assert actual == expected, (name, actual, expected)
            assert not plan.get("resource_changes"), "Routing fixture must not create infrastructure"
            print(f"PASS {args.cli}: {name}")
            count += 1
        print(f"PASS {args.cli}: {count} provider-free routing plans; no cluster access")


if __name__ == "__main__":
    main()
