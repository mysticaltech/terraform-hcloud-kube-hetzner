# /// script
# dependencies = ["python-hcl2==8.1.0"]
# ///
"""Credential-free config/endpoint state proxies; never apply or contact a cluster.

Run with --cli terraform/tofu. --baseline-ref additionally compares full configs
and SAN ordering with that Git revision. Synthetic state is not live upgrade proof.
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

from test_ssh_connection_routing import attributes, output_expression


def attribute_value(attribute):
    source = "locals {\n" + attribute + "\n}"
    node = next(hcl2.parses_to_tree(source).find_data("attribute"))
    return source[node.children[-1].meta.start_pos:node.children[-1].meta.end_pos]


def config(repo, distribution):
    cp_source = (repo / "control_planes.tf").read_text()
    names = {"control_plane_ips", "rke2-config", "k3s-config"}
    if "control_plane_default_endpoint_ips =" in cp_source:
        names.add("control_plane_default_endpoint_ips")
    expressions = list(attributes(repo, "control_planes.tf", names).values())
    init = (repo / "init.tf").read_text()
    # Parse the small locals block, not unrelated shell interpolations in init.tf.
    match = re.search(r"locals \{\s*first_control_plane_ip\s*=.*?\n\}", init, re.S)
    assert match
    expressions.append(match.group()[len("locals {"):-1])
    expressions.extend(attributes(repo, "kubeconfig.tf", {"kubeconfig_server_address"}).values())
    endpoint = attributes(repo, "locals.tf", {"control_plane_endpoint_host"})
    expressions.extend(endpoint.values())
    if "local.rke2_ingress_config" in cp_source:
        expressions.extend(attributes(repo, "locals.tf", {
            "rke2_ingress_config", "rke2_initial_version", "rke2_channel_release_manifest",
        }).values())

    # Extract both bootstrap SAN branches and advertise addresses exactly.
    for role, marker in (("k3s", 'resource "terraform_data" "first_control_plane"'),
                         ("rke2", 'resource "terraform_data" "control_plane_setup_rke2"')):
        section = init[init.index(marker):]
        start = section.index("        var.enable_control_plane_load_balancer ? {")
        end = section.index("        local.etcd_s3_snapshots,", start)
        expressions.append(f"{role}_bootstrap_sans = " + section[start:end].strip().rstrip(","))
        advertise = re.search(r"advertise-address\s*= ([^\n]+)", section).group(1)
        expressions.append(f"{role}_bootstrap_advertise = {advertise}")
        pattern = (r'content = (var.enable_system_upgrade_controller \? templatefile\(\s*'
                   rf'"\$\{{path.module\}}/templates/{"plans" if role == "k3s" else "plans_rke2"}.yaml.tpl",'
                   r'.*?\)\s*: "")')
        suc = re.search(pattern, init, re.S)
        assert suc, role
        expressions.append(f"{role}_suc = " + suc.group(1))

    host_ip = output_expression(repo, "private_ipv4_address")
    host_ip = host_ip.replace("hcloud_server.server", "node")
    ssh_ip = '""'
    if 'output "private_ssh_ipv4_address"' in (repo / "modules/host/out.tf").read_text():
        selector = attribute_value(attributes(repo, "modules/host/locals.tf", {"private_ssh_host"})["private_ssh_host"])
        ssh_ip = output_expression(repo, "private_ssh_ipv4_address").replace("local.private_ssh_host", f"({selector})")
        ssh_ip = ssh_ip.replace("hcloud_server.server", "node")
    expressions.append("nodes = { for key, node in var.case.servers : key => merge(node, {"
                       " private_ipv4_address = " + host_ip + ","
                       " private_ssh_ipv4_address = " + ssh_ip + " }) }")
    expressions = "\n".join(expressions).replace("module.control_planes", "local.nodes")
    expressions = expressions.replace("hcloud_load_balancer_network.control_plane", "local.lbnet")
    expressions = expressions.replace("hcloud_load_balancer.control_plane", "local.lb")
    expressions = expressions.replace("hcloud_server.nat_router", "var.case.routers")
    expressions = expressions.replace("var.", "var.case.").replace("var.case.case.", "var.case.")
    expressions = expressions.replace("path.module", json.dumps(str(repo)))

    resource_name = "control_plane_config_rke2" if distribution == "rke2" else "control_plane_config"
    resource = next(node for node in hcl2.parses_to_tree(cp_source).find_data("block")
                    if cp_source[node.meta.start_pos:node.meta.end_pos].startswith(
                        f'resource "terraform_data" "{resource_name}"'))
    trigger = next(node for node in resource.find_data("attribute")
                   if str(node.children[0].children[0]) == "triggers_replace")
    triggers = cp_source[trigger.meta.start_pos:trigger.meta.end_pos].replace("module.control_planes", "local.nodes")

    # The host module does not export network: keep try(module.network) behavior.
    expressions = expressions.replace("merge(node, {", 'merge({for attr, entry in node : attr => entry if attr != "network"}, {')
    return '''variable "case" {}
locals {
  lb = [{ ipv4 = "192.0.2.20" }]
  lbnet = [{ ip = "10.0.0.20" }]
  control_plane_override_base_names = { for key, node in local.nodes : key => key }
  tailscale_control_plane_magicdns_hosts = { for key, node in local.nodes : key => "${node.name}.example.ts.net" }
  tailscale_use_tailnet_for_terraform = var.case.use_tailnet
  node_transport_tailscale_enabled = var.case.tailnet_enabled
  tailscale_first_control_plane_host = local.tailscale_control_plane_magicdns_hosts.cp0
  control_plane_nodes = {for key, node in local.nodes : key => {labels = [], taints = [], selinux = false}}
  cluster_token = "public-test-fixture"
  disable_extras = []
  disable_rke2_extras = []
  kubelet_arg = []
  kube_apiserver_arg = []
  kube_controller_manager_arg = []
  flannel_iface = "eth1"
  cluster_cidr = "10.42.0.0/16"
  service_cidr = "10.43.0.0/16"
  cluster_dns = "10.43.0.10"
  rke2_cni = "cilium"
  multinetwork_overlay_enabled = false
  multinetwork_transport_ipv4_enabled = true
  multinetwork_transport_ipv6_enabled = true
  control_plane_public_overlay_node_ip_by_node = {for key, node in local.nodes : key => node.ipv4_address}
  secrets_encryption_config_file = "/fixture/encryption.yaml"
  secrets_encryption_config = "fixture-encryption-config"
  desired_cni_values = "fixture-cni-values"
  control_plane_effective_kubelet_args_by_node = {for key, node in local.nodes : key => []}
  control_plane_node_ip_by_node = {for key, node in local.nodes : key => node.private_ipv4_address}
  control_plane_external_ipv4_by_node = {}
  rke2_control_plane_join_endpoint_by_node = {for key, node in local.nodes : key => "https://10.0.0.10:9345"}
  k3s_control_plane_join_endpoint_by_node = {for key, node in local.nodes : key => "https://10.0.0.10:6443"}
  cni_k3s_settings = {}
  embedded_registry_mirror_server_config = {}
  disable_default_registry_endpoint_config = {}
  etcd_s3_snapshots = {}
  prefer_bundled_bin_config = {}
''' + expressions + '''
}
output "contracts" { value = {
  endpoint = local.kubeconfig_server_address
  ssh = local.first_control_plane_ip
  configs = local.''' + distribution + '''-config
  bootstrap = local.''' + distribution + '''_bootstrap_sans
  advertise = local.''' + distribution + '''_bootstrap_advertise
  suc = local.''' + distribution + '''_suc
} }
resource "terraform_data" "control_plane_config" {
  for_each = local.nodes
''' + triggers + '''
}
resource "terraform_data" "suc" {
  triggers_replace = { rendered = sha256(local.''' + distribution + '''_suc) }
}
'''


def scenarios():
    servers = {f"cp{i}": {"name": f"cp{i}", "id": str(i + 10),
               "ipv4_address": f"192.0.2.{i + 10}", "ipv6_address": f"2001:db8::{i + 10}",
               "network": [{"network_id": 2, "ip": f"10.0.0.{i + 10}"}]} for i in range(3)}
    base = {"servers": servers, "network_id": 2, "ssh_use_private_network": False,
            "node_connection_overrides": {}, "use_tailnet": False, "tailnet_enabled": False,
            "kubeconfig_server_address": "", "control_plane_endpoint": None,
            "tailscale_node_transport": {"kubernetes": {"kubeconfig_endpoint": "first_control_plane_tailnet"}},
            "enable_control_plane_load_balancer": False, "control_plane_load_balancer_enable_public_network": True,
            "nat_router": None, "routers": [{"ipv4_address": "192.0.2.1"}],
            "additional_tls_sans": ["extra.example"], "enable_kube_proxy": True,
            "enable_secrets_encryption": False, "enable_selinux": False, "kubernetes_api_port": 6443,
            "control_planes_custom_config": {}, "cni_plugin": "cilium",
            "enable_system_upgrade_controller": True, "k3s_channel": "stable", "rke2_channel": "stable",
            "k3s_version": "", "rke2_version": "", "system_upgrade_enable_eviction": True,
            "system_upgrade_use_drain": True, "system_upgrade_schedule_window": None}
    cases = [
        ("no-lb", {}, "192.0.2.10", True),
        ("single-control-plane", {"single": True}, "192.0.2.10", True),
        ("public-only", {"no_private": True}, "192.0.2.10", False),
        ("public-lb", {"enable_control_plane_load_balancer": True}, "192.0.2.20", True),
        ("private-lb", {"enable_control_plane_load_balancer": True,
                        "control_plane_load_balancer_enable_public_network": False}, "10.0.0.20", True),
        ("private-lb-nat", {"enable_control_plane_load_balancer": True,
                            "control_plane_load_balancer_enable_public_network": False,
                            "nat_router": {}}, "192.0.2.1", True),
        ("custom-client", {"kubeconfig_server_address": "api.example"}, "api.example", True),
        ("custom-join", {"control_plane_endpoint": "https://join.example:6443"}, "192.0.2.10", True),
        ("public-disabled", {"no_public": True}, "10.0.0.10", False),
        ("ipv6-public", {"no_ipv4": True}, "2001:db8::10", True),
        ("tailnet-client-and-ssh", {"tailnet_enabled": True, "use_tailnet": True}, "cp0.example.ts.net", False),
        ("tailnet-bootstrap", {"tailnet_enabled": True}, "cp0.example.ts.net", True),
        ("custom-client-before-tailnet", {"tailnet_enabled": True, "use_tailnet": True,
                                         "kubeconfig_server_address": "api.example"}, "api.example", False),
        ("tailnet-existing-default", {"tailnet_enabled": True, "use_tailnet": True,
                                     "tailscale_node_transport": {"kubernetes": {"kubeconfig_endpoint": "existing_default"}}}, "cp0.example.ts.net", False),
        ("override-before-tailnet", {"use_tailnet": True,
                                    "node_connection_overrides": {"cp0": "override.example"}}, "override.example", False),
        ("multi-attachment", {"extra_network": True}, "192.0.2.10", True),
    ]
    for name, update, endpoint, ssh_changes in cases:
        case = copy.deepcopy(base)
        case.update(update)
        if case.get("single"):
            case["servers"] = {"cp0": case["servers"]["cp0"]}
        for i, server in enumerate(case["servers"].values()):
            if case.get("no_public") or case.get("no_ipv4"):
                server["ipv4_address"] = ""
            if case.get("no_public"):
                server["ipv6_address"] = ""
            if case.get("extra_network"):
                server["network"].insert(0, {"network_id": 1, "ip": f"10.1.0.{i + 10}"})
            if case.get("no_private"):
                server["network"] = []
        yield name, case, endpoint, ssh_changes


def synthetic_state(plan, cli):
    resources = []
    for resource in plan["planned_values"]["root_module"]["resources"]:
        trigger = resource["values"]["triggers_replace"]
        resources.append({"mode": "managed", "type": "terraform_data", "name": resource["name"],
                          "provider": 'provider["terraform.io/builtin/terraform"]',
                          "instances": [{"schema_version": 0,
                          **({"index_key": resource["index"]} if "index" in resource else {}),
                          "attributes": {"id": "synthetic-only", "input": None, "output": None,
                          "triggers_replace": {"value": trigger,
                          "type": ["object", {key: "string" for key in trigger}]}}}]})
    return {"version": 4, "terraform_version": "1.15.0" if cli == "terraform" else "1.11.6",
            "serial": 1, "lineage": "kh-ssh-endpoint-proxy", "outputs": {}, "resources": resources}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", choices=("terraform", "tofu"), default="terraform")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--baseline-ref")
    parser.add_argument("--distribution", choices=("all", "k3s", "rke2"), default="all")
    args = parser.parse_args()
    repo = args.repo.resolve()
    env = {key: entry for key, entry in os.environ.items() if key in {"PATH", "HOME", "TMPDIR"}}
    env.update(TF_CLI_CONFIG_FILE="/dev/null", TF_IN_AUTOMATION="1")
    with tempfile.TemporaryDirectory(prefix="kh-ssh-endpoint-", dir="/tmp") as directory:
        root = Path(directory)
        baseline = root / "baseline"
        if args.baseline_ref:
            for filename in ("control_planes.tf", "init.tf", "kubeconfig.tf", "locals.tf", "modules/host/out.tf", "modules/host/locals.tf",
                             "templates/plans.yaml.tpl", "templates/plans_rke2.yaml.tpl"):
                target = baseline / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(subprocess.check_output(["git", "show", f"{args.baseline_ref}:{filename}"],
                                                          cwd=repo, text=True))

        def run(*command):
            result = subprocess.run([args.cli, *command], cwd=root, env=env, text=True, capture_output=True)
            assert result.returncode == 0, (command, result.stdout, result.stderr)
            return result.stdout

        def plan(source, case, state=None):
            (root / "main.tf").write_text(source)
            (root / "case.auto.tfvars.json").write_text(json.dumps({"case": case}))
            statefile = root / "terraform.tfstate"
            if state is None:
                statefile.unlink(missing_ok=True)
            else:
                statefile.write_text(json.dumps(state))
            run("fmt")
            run("init", "-backend=false", "-input=false")
            run("validate", "-no-color")
            run("plan", "-refresh=false", "-input=false", "-no-color", "-out=plan")
            return json.loads(run("show", "-json", "plan"))

        count = 0
        distributions = ("k3s", "rke2") if args.distribution == "all" else (args.distribution,)
        for distribution in distributions:
            source = config(repo, distribution)
            original = config(baseline, distribution) if args.baseline_ref else source
            for name, case, endpoint, ssh_changes in scenarios():
                before = plan(original, case)
                current = plan(source, case)
                old = before["planned_values"]["outputs"]["contracts"]["value"]
                now = current["planned_values"]["outputs"]["contracts"]["value"]
                assert old == now, (distribution, name, "baseline drift", old, now)
                case["ssh_use_private_network"] = True
                after = plan(source, case, synthetic_state(before, args.cli))
                new = after["planned_values"]["outputs"]["contracts"]["value"]
                assert old["endpoint"] == new["endpoint"] == endpoint, (
                    distribution, name, "endpoint changed", old["endpoint"], new["endpoint"], endpoint)
                assert (old["ssh"] != new["ssh"]) == ssh_changes, (name, old["ssh"], new["ssh"])
                for key in ("configs", "bootstrap", "advertise", "suc"):
                    assert old[key] == new[key], (distribution, name, key, old[key], new[key])
                changes = after["resource_changes"]
                assert len(changes) == len(case["servers"]) + 1
                assert all(change["change"]["actions"] == ["no-op"] for change in changes), changes
                print(f"PASS {args.cli} {distribution}/{name}: baseline config/SANs, endpoint, SUC; {len(changes)} state proxies no-op")
                count += 1
        print(f"PASS {args.cli}: {count} SSH-toggle cases, production control-plane triggers + SUC proxies; no live upgrade claim")


if __name__ == "__main__":
    main()
