#!/usr/bin/env python3
"""Hermetic render assertions for kube-hetzner's high-risk templates."""

from __future__ import annotations

import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
LOCALS_TF = REPO_ROOT / "locals.tf"
AGENTS_TF = REPO_ROOT / "agents.tf"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
RENDER_SSH_AUTHORIZED_KEY = (
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKubeHetznerRenderHarness render-comment"
)

HELM_VALUE_LOCALS = [
    "cilium_values_default",
    "longhorn_values_default",
    "csi_driver_smb_values_default",
    "hetzner_csi_values_default",
    "nginx_values_default",
    "hetzner_ccm_values_default",
    "haproxy_values_default",
    "traefik_values_default",
    "rancher_values_default",
    "cert_manager_values_default",
]

INGRESS_ASSERTIONS = {
    "nginx_values_default": ("controller", "service", "annotations"),
    "haproxy_values_default": ("controller", "service", "annotations"),
    "traefik_values_default": ("service", "annotations"),
}

LB_ANNOTATION_KEYS = (
    "load-balancer.hetzner.cloud/name",
    "load-balancer.hetzner.cloud/id",
)
ADDON_DEFAULT_VERSION_RE = re.compile(r'^\s*([a-z0-9_]+)\s*=\s*"([^"]+)"\s*$')
CONCRETE_ADDON_VERSION_RE = re.compile(r"^v?[0-9]+(?:\.[0-9]+){1,3}(?:[-+][0-9A-Za-z.-]+)?$")
FLOATING_ADDON_VERSION_SENTINELS = {"", "*", "latest"}


class HarnessFailure(Exception):
    """Raised when a render check fails."""


def strip_ansi(value: str) -> str:
    return ANSI_RE.sub("", value)


def hcl_json(value: Any) -> str:
    return (
        json.dumps(value, indent=2, sort_keys=True)
        .replace("${", "$${")
        .replace("%{", "%%{")
    )


def hcl_value(value: Any) -> str:
    return (
        json.dumps(value, separators=(",", ":"), sort_keys=True)
        .replace("${", "$${")
        .replace("%{", "%%{")
    )


def hcl_string(value: Path | str) -> str:
    return json.dumps(str(value))


def print_pass(name: str, detail: str) -> None:
    print(f"PASS {name}: {detail}")


def print_skip(name: str, detail: str) -> None:
    print(f"SKIP {name}: {detail}")


def fail(name: str, detail: str) -> None:
    raise HarnessFailure(f"FAIL {name}: {detail}")


def extract_heredoc(local_name: str) -> str:
    """Extract one explicitly named heredoc body from locals.tf.

    This intentionally does not attempt general HCL parsing. The harness owns a
    small allowlist of high-risk locals and follows only their heredoc markers.
    """

    lines = LOCALS_TF.read_text(encoding="utf-8").splitlines(keepends=True)
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not (stripped.startswith(f"{local_name} ") and "<<" in stripped):
            continue

        marker = stripped.split("<<", 1)[1].strip()
        if marker.startswith("-"):
            marker = marker[1:].strip()
        if not marker:
            fail(local_name, "heredoc marker is empty")

        body: list[str] = []
        for candidate in lines[index + 1 :]:
            if candidate.strip() == marker:
                return "".join(body)
            body.append(candidate)
        fail(local_name, f"unterminated heredoc marker {marker!r}")

    fail(local_name, "named heredoc not found")


def discover_local_scripts() -> dict[str, str]:
    scripts: dict[str, str] = {}
    lines = LOCALS_TF.read_text(encoding="utf-8").splitlines()
    for line in lines:
        stripped = line.strip()
        if "_script" not in stripped or "<<" not in stripped or "=" not in stripped:
            continue
        name = stripped.split("=", 1)[0].strip()
        if name.endswith("script"):
            scripts[name] = extract_heredoc(name)
    return scripts


def extract_addon_default_versions() -> dict[str, str]:
    versions: dict[str, str] = {}
    lines = LOCALS_TF.read_text(encoding="utf-8").splitlines()
    in_block = False
    found_block = False
    for line in lines:
        stripped = line.strip()
        if not in_block:
            if stripped == "addon_default_versions = {":
                in_block = True
                found_block = True
            continue

        if stripped == "}":
            in_block = False
            break
        if stripped == "" or stripped.startswith("#"):
            continue

        match = ADDON_DEFAULT_VERSION_RE.match(line)
        if match is None:
            fail("addon_default_versions", f"unparseable matrix entry: {stripped}")
        key, value = match.groups()
        if key in versions:
            fail("addon_default_versions", f"duplicate matrix key: {key}")
        versions[key] = value

    if not found_block:
        fail("addon_default_versions", "matrix local was not found")
    if in_block:
        fail("addon_default_versions", "matrix local is unterminated")
    if not versions:
        fail("addon_default_versions", "matrix local has no entries")
    return versions


def assert_addon_default_versions() -> None:
    versions = extract_addon_default_versions()
    invalid = [
        f"{name}={version!r}"
        for name, version in sorted(versions.items())
        if version.lower() in FLOATING_ADDON_VERSION_SENTINELS
        or CONCRETE_ADDON_VERSION_RE.fullmatch(version) is None
    ]
    if invalid:
        fail("addon_default_versions", f"non-concrete defaults: {', '.join(invalid)}")
    print_pass("addon_default_versions", f"{len(versions)} concrete addon defaults are pinned")


def normalize_hcl(source: str) -> str:
    """Normalize formatting for narrow source-level contract assertions."""

    return re.sub(r"\s+", "", source)


def assert_agent_private_ipv4_contract(scratch: "TerraformScratch") -> None:
    """Protect v2 identity, external-network opt-out, and shared uniqueness."""

    agents_source = normalize_hcl(AGENTS_TF.read_text(encoding="utf-8"))
    locals_source = normalize_hcl(LOCALS_TF.read_text(encoding="utf-8"))
    required_agent_fragments = (
        "private_ipv4=each.value.network_id==0?cidrhost(",
        "hcloud_network_subnet.agent[local.use_per_nodepool_subnets?"
        "[fori,vinvar.agent_nodepools:iifv.name==each.value.nodepool_name][0]:0].ip_range",
        "(local.use_per_nodepool_subnets?each.value.index:"
        "local.shared_agent_private_ipv4_index_by_node[each.key])+"
        "(local.network_size>=16?101:floor(pow(local.subnet_size,2)*0.4))",
        "):null",
    )
    missing_agent = [fragment for fragment in required_agent_fragments if fragment not in agents_source]
    if missing_agent:
        fail("agent private IPv4 source contract", f"missing fragments: {missing_agent!r}")

    required_local_fragments = (
        "agent_node_keys_in_pool_order=flatten([",
        "forpool_index,nodepool_objinvar.agent_nodepools:concat(",
        "fornode_indexinrange(coalesce(nodepool_obj.count,0)):",
        "fornode_indexinrange(max(concat([0],[forkinkeys(coalesce(nodepool_obj.nodes,{})):floor(tonumber(k))])...)+1):[",
        "fornode_keyinkeys(coalesce(nodepool_obj.nodes,{})):",
        "iffloor(tonumber(node_key))==node_index",
        "primary_agent_node_keys_in_pool_order=[",
        "iflocal.agent_nodes[node_key].network_id==0",
        "shared_agent_private_ipv4_index_by_node={forindex,node_keyinlocal.primary_agent_node_keys_in_pool_order:node_key=>index}",
    )
    missing_locals = [fragment for fragment in required_local_fragments if fragment not in locals_source]
    if missing_locals:
        fail("agent private IPv4 source contract", f"missing local fragments: {missing_locals!r}")

    # Exercise the same pool-major/count-or-numeric-map ordering shape as the
    # production local. Lexical map order would place "10" before "2", and an
    # external-network node must not consume a shared-primary address.
    pools = [
        {"name": "pool-a", "count": 2, "network_id": 0, "nodes": {}},
        {
            "name": "pool-b",
            "count": 0,
            "network_id": 0,
            "nodes": {
                "10": {"network_id": 0},
                "2": {"network_id": 0},
                "1.5": {"network_id": 0},
                "3": {"network_id": 123},
            },
        },
    ]
    ordered_nodes_expression = (
        f"flatten([for pool_index, pool in {hcl_value(pools)} : concat("
        "[for node_index in range(pool.count) : { key = format(\"%s-%s-%s\", pool_index, node_index, pool.name), network_id = pool.network_id }],"
        "flatten([for node_index in range(max(concat([0], [for k in keys(pool.nodes) : floor(tonumber(k))])...) + 1) : [for node_key in keys(pool.nodes) : "
        "{ key = format(\"%s-%s-%s\", pool_index, node_key, pool.name), network_id = pool.nodes[node_key].network_id } "
        "if floor(tonumber(node_key)) == node_index]])"
        ")] )"
    )
    encoded_primary_nodes = scratch.console(
        f"jsonencode([for node in {ordered_nodes_expression} : node if node.network_id == 0])"
    )
    primary_nodes = json.loads(json.loads(encoded_primary_nodes))
    primary_keys = [node["key"] for node in primary_nodes]
    expected_primary_keys = ["0-0-pool-a", "0-1-pool-a", "1-1.5-pool-b", "1-2-pool-b", "1-10-pool-b"]
    if primary_keys != expected_primary_keys:
        fail("agent shared private IPv4", f"unexpected primary-node order: {primary_keys!r}")

    shared_indexes = {node_key: index for index, node_key in enumerate(primary_keys)}
    if shared_indexes != {
        "0-0-pool-a": 0,
        "0-1-pool-a": 1,
        "1-1.5-pool-b": 2,
        "1-2-pool-b": 3,
        "1-10-pool-b": 4,
    }:
        fail("agent shared private IPv4", f"unexpected global indexes: {shared_indexes!r}")

    encoded_shared_ips = scratch.console(
        'jsonencode([for index in range(5) : cidrhost("10.0.0.0/16", index + 101)])'
    )
    shared_ips = json.loads(json.loads(encoded_shared_ips))
    if shared_ips != ["10.0.0.101", "10.0.0.102", "10.0.0.103", "10.0.0.104", "10.0.0.105"]:
        fail("agent shared private IPv4", f"unexpected shared addresses: {shared_ips!r}")
    if len(shared_ips) != len(set(shared_ips)):
        fail("agent shared private IPv4", f"duplicate shared addresses: {shared_ips!r}")

    # v2.21.0 used the node's pool-local index plus the same host offset in
    # that pool's subnet. These representative pools protect that no-op math.
    encoded_per_pool_ips = scratch.console(
        'jsonencode([cidrhost("10.0.0.0/16", 0 + 101), '
        'cidrhost("10.1.0.0/16", 0 + 101), cidrhost("10.1.0.0/16", 7 + 101)])'
    )
    per_pool_ips = json.loads(json.loads(encoded_per_pool_ips))
    if per_pool_ips != ["10.0.0.101", "10.1.0.101", "10.1.0.108"]:
        fail("agent v2 private IPv4 identity", f"unexpected per-pool addresses: {per_pool_ips!r}")

    print_pass(
        "agent private IPv4 contract",
        "v2 per-pool offsets are preserved; shared primary-agent offsets are unique across pools; external agents remain unpinned",
    )


def base_render_vars() -> dict[str, Any]:
    var_values = {
        "audit_log_path": "/var/log/kubernetes/audit.log",
        "audit_policy_config": "",
        "autoscaler_nodepools": [],
        "cilium_egress_gateway_enabled": False,
        "cilium_gateway_api_enabled": True,
        "cilium_hubble_enabled": True,
        "cilium_hubble_metrics_enabled": ["dns", "drop", "tcp", "flow", "icmp", "http"],
        "cilium_load_balancer_acceleration_mode": "best-effort",
        "enable_hetzner_csi": True,
        "enable_kube_proxy": False,
        "haproxy_additional_proxy_protocol_ips": ["192.0.2.0/24"],
        "haproxy_requests_cpu": "250m",
        "haproxy_requests_memory": "400Mi",
        "ingress_controller": "nginx",
        "kubernetes_api_port": 6443,
        "kubernetes_config_updates_use_kured_sentinel": False,
        "load_balancer_algorithm_type": "round_robin",
        "load_balancer_enable_ipv6": True,
        "load_balancer_enable_public_network": True,
        "load_balancer_health_check_interval": "15s",
        "load_balancer_health_check_retries": 3,
        "load_balancer_health_check_timeout": "10s",
        "load_balancer_hostname": "",
        "load_balancer_location": "nbg1",
        "load_balancer_type": "lb11",
        "longhorn_fstype": "ext4",
        "longhorn_replica_count": 1,
        "nat_router": {"extra_runcmd": ["echo render-harness"]},
        "rancher_bootstrap_password": "",
        "rancher_hostname": "",
        "traefik_additional_options": ["--log.level=INFO"],
        "traefik_additional_ports": [],
        "traefik_additional_trusted_ips": ["192.0.2.0/24"],
        "traefik_autoscaling": True,
        "traefik_image_tag": "v3.3.5",
        "traefik_pod_disruption_budget": True,
        "traefik_provider_kubernetes_gateway_enabled": True,
        "traefik_redirect_to_https": True,
        "traefik_resource_limits": True,
        "traefik_resource_values": {
            "requests": {"cpu": "100m", "memory": "50Mi"},
            "limits": {"cpu": "300m", "memory": "150Mi"},
        },
    }

    local_values = {
        "agent_service_name": "k3s-agent",
        "allow_scheduling_on_control_plane": False,
        "authentication_config_file": "/etc/rancher/k3s/authentication_config.yaml",
        "audit_policy_file": "/etc/rancher/k3s/audit-policy.yaml",
        "cilium_ipv4_native_routing_cidr": "10.244.0.0/16",
        "cilium_mtu_effective": 1450,
        "cilium_routing_mode_effective": "native",
        "cilium_wireguard_effective": False,
        "cluster_has_ipv4": True,
        "cluster_has_ipv6": False,
        "cluster_ipv6_cidr_effective": "fd00:10:244::/56",
        "combine_load_balancers_effective": False,
        "control_plane_nodes": {"0-0-cp": {"name": "cp"}},
        "control_plane_service_name": "k3s",
        "cross_network_transport_enabled": False,
        "gateway_api_crds_enabled": True,
        "hetzner_ccm_instances_address_family": "ipv4",
        "hetzner_ccm_networking_enabled": True,
        "hetzner_ccm_route_cluster_cidr": "10.244.0.0/16",
        "ingress_controller_namespace": "nginx",
        "ingress_load_balancer_destroy_cleanup_service_names": (
            "nginx-ingress-nginx-controller traefik haproxy-kubernetes-ingress"
        ),
        "ingress_max_replica_count": 3,
        "ingress_replica_count": 2,
        "kubernetes_distribution": "k3s",
        "kubectl_cli": "kubectl",
        "kured_reboot_sentinel": "/sentinel/reboot-required",
        "load_balancer_name": "render-harness-nginx",
        "multinetwork_overlay_enabled": False,
        "multinetwork_transport_ipv4_enabled": False,
        "multinetwork_transport_ipv6_enabled": False,
        "post_install_readiness_wait_deployment_commands": "true",
        "post_install_readiness_wait_helm_job_commands_300": "true",
        "post_install_readiness_wait_helm_job_commands_900": "true",
        "use_robot_ccm": False,
        "using_klipper_lb": False,
    }

    top_level = {
        "cloudinit_runcmd_common": "- echo render-harness-common",
        "cloudinit_runcmd_extra": [],
        "cloudinit_write_files_common": (
            "- path: /root/k8s_custom_policies.te\n"
            "  permissions: '0644'\n"
            "  content: |\n"
            "    module k8s_custom_policies 1.0;\n"
        ),
        "cloudinit_write_files_extra": [],
        "cluster_name": "render-harness",
        "cp_lb_private_ip": "10.0.0.10",
        "dns_servers": ["1.1.1.1", "2606:4700:4700::1111"],
        "enable_cp_lb_port_forward": True,
        "enable_redundancy": True,
        "enable_sudo": True,
        "has_dns_servers": True,
        "hcloud_token": "render-token",
        "hostname": "render-node-0",
        "install_k8s_agent_script": "#!/bin/bash\nset -e\necho install agent\n",
        "k3s_config": "server: https://10.0.0.10:6443\n",
        "kubernetes_api_port": 6443,
        "multinetwork_public_overlay_enabled": False,
        "multinetwork_transport_ipv4_enabled": False,
        "multinetwork_transport_ipv6_enabled": False,
        "my_private_ip": "10.0.0.2",
        "nat_gateway_ip": "10.0.0.1",
        "network_gw_ipv4": "10.0.0.1",
        "network_id": 12345,
        "os": "leapmicro",
        "peer_private_ip": "10.0.0.3",
        "private_ipv4_default_route": False,
        "private_network_ipv4_range": "10.0.0.0/16",
        "priority": 150,
        "public_ipv4_default_route": True,
        "public_ipv6_default_route": True,
        "sshAuthorizedKeysYaml": f'- "{RENDER_SSH_AUTHORIZED_KEY}"\n',
        "ssh_max_auth_tries": 3,
        "ssh_port": 22,
        "swap_size": "",
        "tailscale_bootstrap_script": "",
        "vip": "10.0.0.1",
        "vip_auth_pass": "renderpass",
        "zram_size": "",
    }

    return {
        **top_level,
        "hcloud_load_balancer": {"control_plane": [{"id": "123456"}]},
        "local": local_values,
        "resource": {"random_password": {"rancher_bootstrap": [{"result": "render-harness-password"}]}},
        "var": var_values,
    }


class TerraformScratch:
    def __init__(self, root: Path, render_vars: dict[str, Any]) -> None:
        self.root = root
        (root / "main.tf").write_text(
            "\n".join(
                [
                    'terraform { required_version = ">= 1.10.1" }',
                    "locals {",
                    "  render_vars = jsondecode(<<JSON",
                    hcl_json(render_vars),
                    "JSON",
                    "  )",
                    "}",
                    "",
                ]
            ),
            encoding="utf-8",
        )

    def write_template(self, name: str, body: str) -> Path:
        path = self.root / f"{name}.tftpl"
        path.write_text(body, encoding="utf-8")
        return path

    def console(self, expression: str) -> str:
        env = os.environ.copy()
        env["TF_IN_AUTOMATION"] = "1"
        env["TF_CLI_ARGS"] = "-no-color"
        try:
            result = subprocess.run(
                ["terraform", "console"],
                cwd=self.root,
                input=f"{expression}\n",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=300,
            )
        except subprocess.TimeoutExpired as exc:
            raise HarnessFailure(
                "FAIL terraform-console: timed out after 300s waiting for output. "
                "terraform console reads the expression from stdin; wrappers that "
                "do not forward stdin (e.g. hashicorp/setup-terraform with "
                "terraform_wrapper enabled) hang here forever.\n"
                f"expression: {expression}"
            ) from exc
        stdout = strip_ansi(result.stdout).strip()
        stderr = strip_ansi(result.stderr).strip()
        if result.returncode != 0:
            raise HarnessFailure(
                "FAIL terraform-console: provider-free scratch evaluation failed\n"
                f"expression: {expression}\nstdout:\n{stdout}\nstderr:\n{stderr}"
            )
        return stdout

    def render_string(self, template_path: Path) -> str:
        encoded = self.console(
            f"jsonencode(templatefile({hcl_string(template_path)}, local.render_vars))"
        )
        return json.loads(json.loads(encoded))

    def render_yaml(self, template_path: Path) -> Any:
        encoded = self.console(
            f"jsonencode(yamldecode(templatefile({hcl_string(template_path)}, local.render_vars)))"
        )
        return json.loads(json.loads(encoded))

    def decode_yaml_string(self, value: str) -> Any:
        encoded = self.console(f"jsonencode(yamldecode({hcl_string(value)}))")
        return json.loads(json.loads(encoded))

    def yamlencode(self, value: Any) -> str:
        encoded = self.console(f"jsonencode(yamlencode({hcl_value(value)}))")
        return json.loads(json.loads(encoded))


def nested_get(value: Any, path: tuple[str, ...]) -> Any:
    current = value
    for key in path:
        if not isinstance(current, dict) or key not in current:
            fail("structure", f"missing {'.'.join(path)}")
        current = current[key]
    return current


def assert_lb_annotation(name: str, document: Any, path: tuple[str, ...]) -> None:
    annotations = nested_get(document, path)
    if not isinstance(annotations, dict):
        fail(name, f"{'.'.join(path)} is not a mapping")
    if not any(str(annotations.get(key, "")).strip() for key in LB_ANNOTATION_KEYS):
        fail(name, f"{'.'.join(path)} has no non-empty Hetzner LB adoption annotation")
    print_pass(name, f"{'.'.join(path)} contains a Hetzner LB adoption annotation")


def assert_cilium_shape(name: str, document: Any) -> None:
    if not isinstance(document, dict):
        fail(name, "decoded document is not a mapping")
    for key in ("routingMode", "k8sServicePort"):
        if key not in document:
            fail(name, f"missing root key {key}")
    print_pass(name, "root routingMode and k8sServicePort are present")


def bash_syntax_check(name: str, script: str) -> None:
    result = subprocess.run(
        ["bash", "-n"],
        input=script,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        fail(name, strip_ansi(result.stderr).strip() or "bash -n failed")
    print_pass(name, "bash -n accepted rendered shell")


def run_helm_checks(scratch: TerraformScratch) -> None:
    rendered: dict[str, Any] = {}
    for local_name in HELM_VALUE_LOCALS:
        body = extract_heredoc(local_name)
        path = scratch.write_template(local_name, body)
        if body.strip() == "":
            print_pass(local_name, "empty values document is allowed by the contract")
            continue
        document = scratch.render_yaml(path)
        rendered[local_name] = document
        print_pass(local_name, "yamldecode accepted rendered Helm values")

    for local_name, path in INGRESS_ASSERTIONS.items():
        assert_lb_annotation(local_name, rendered[local_name], path)

    assert_cilium_shape("cilium_values_default", rendered["cilium_values_default"])

    cilium_body = extract_heredoc("cilium_values_default")
    mutated = cilium_body.replace("\nroutingMode:", "\n  routingMode:", 1)
    if mutated == cilium_body:
        fail("cilium historical mutation", "could not inject routingMode indentation mutation")
    mutated_path = scratch.write_template("cilium_values_default_mutated", mutated)
    try:
        mutated_doc = scratch.render_yaml(mutated_path)
        assert_cilium_shape("cilium_values_default_mutated", mutated_doc)
    except HarnessFailure as exc:
        print_pass(
            "cilium historical mutation",
            f"temp-only routingMode indentation mutation failed as expected ({str(exc).splitlines()[0]})",
        )
    else:
        fail("cilium historical mutation", "mutated Cilium values unexpectedly passed")


def run_cloudinit_checks(scratch: TerraformScratch) -> None:
    templates = [
        REPO_ROOT / "modules/host/templates/cloudinit.yaml.tpl",
        REPO_ROOT / "templates/autoscaler-cloudinit.yaml.tpl",
        REPO_ROOT / "templates/nat-router-cloudinit.yaml.tpl",
    ]
    for template_path in templates:
        document = scratch.render_yaml(template_path)
        if not isinstance(document, dict):
            fail(str(template_path.relative_to(REPO_ROOT)), "decoded cloud-init is not a mapping")
        for key in ("write_files", "runcmd"):
            if key not in document:
                fail(str(template_path.relative_to(REPO_ROOT)), f"missing {key}")
        print_pass(str(template_path.relative_to(REPO_ROOT)), "yamldecode accepted cloud-init structure")

        if template_path.name == "nat-router-cloudinit.yaml.tpl":
            users = document.get("users")
            if not isinstance(users, list) or not users:
                fail(str(template_path.relative_to(REPO_ROOT)), "missing users[0]")
            keys = users[0].get("ssh_authorized_keys")
        else:
            keys = document.get("ssh_authorized_keys")
        if keys != [RENDER_SSH_AUTHORIZED_KEY]:
            fail(
                str(template_path.relative_to(REPO_ROOT)),
                f"authorized keys decoded to {keys!r}",
            )
        print_pass(
            str(template_path.relative_to(REPO_ROOT)),
            "authorized key list decodes to the expected single-line key",
        )


def node_annotation_write_files(scratch: TerraformScratch) -> list[dict[str, str]]:
    annotations = {
        "node.longhorn.io/default-disks-config": '[{"path":"/var/lib/longhorn","allowScheduling":true}]',
        "example.com/storage-tier": "fast local disk",
    }
    payload = "\n".join(
        f"{base64.b64encode(key.encode()).decode()} {base64.b64encode(value.encode()).decode()}"
        for key, value in sorted(annotations.items())
    )
    return [
        {
            "path": "/etc/kube-hetzner/node-annotations.b64",
            "owner": "root:root",
            "permissions": "0600",
            "encoding": "base64",
            "content": base64.b64encode(f"{payload}\n".encode()).decode(),
        },
        {
            "path": "/usr/local/bin/kh-annotate-node.sh",
            "owner": "root:root",
            "permissions": "0755",
            "content": scratch.render_string(
                scratch.write_template(
                    "node_annotations_apply_script_cloudinit",
                    extract_heredoc("node_annotations_apply_script"),
                )
            ),
        },
        {
            "path": "/etc/systemd/system/kh-annotate-node.service",
            "owner": "root:root",
            "permissions": "0644",
            "content": extract_heredoc("node_annotations_systemd_unit"),
        },
    ]


def render_cloudinit_with_vars(render_vars: dict[str, Any], template_path: Path) -> tuple[str, Any]:
    temp_dir = Path(tempfile.mkdtemp(prefix="kh-render-annotations-"))
    try:
        scratch = TerraformScratch(temp_dir, render_vars)
        return scratch.render_string(template_path), scratch.render_yaml(template_path)
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def assert_node_annotation_payload(name: str, document: Any, rendered: str) -> None:
    if not isinstance(document, dict):
        fail(name, "decoded cloud-init is not a mapping")

    write_files = document.get("write_files")
    if not isinstance(write_files, list):
        fail(name, "write_files is not a list")

    by_path = {
        entry.get("path"): entry
        for entry in write_files
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }
    for path in (
        "/etc/kube-hetzner/node-annotations.b64",
        "/usr/local/bin/kh-annotate-node.sh",
        "/etc/systemd/system/kh-annotate-node.service",
    ):
        if path not in by_path:
            fail(name, f"missing annotation write_files entry {path}")

    payload_entry = by_path["/etc/kube-hetzner/node-annotations.b64"]
    if payload_entry.get("encoding") != "base64":
        fail(name, "annotation payload file is not base64-encoded")
    payload = base64.b64decode(str(payload_entry["content"])).decode()
    decoded = {}
    for line in payload.splitlines():
        key_b64, value_b64 = line.split(" ", 1)
        decoded[base64.b64decode(key_b64).decode()] = base64.b64decode(value_b64).decode()

    if decoded != {
        "example.com/storage-tier": "fast local disk",
        "node.longhorn.io/default-disks-config": '[{"path":"/var/lib/longhorn","allowScheduling":true}]',
    }:
        fail(name, f"decoded annotation payload was {decoded!r}")

    script = str(by_path["/usr/local/bin/kh-annotate-node.sh"].get("content", ""))
    unit = str(by_path["/etc/systemd/system/kh-annotate-node.service"].get("content", ""))
    if "/var/lib/rancher/k3s/agent/kubelet.kubeconfig" not in script:
        fail(name, "script does not reference the k3s kubelet kubeconfig")
    if "/var/lib/rancher/rke2/agent/kubelet.kubeconfig" not in script:
        fail(name, "script does not reference the rke2 kubelet kubeconfig")
    if "--overwrite" not in script or 'node "$node_name"' not in script:
        fail(name, "script does not annotate the local node with overwrite")
    if "WantedBy=k3s.service k3s-agent.service rke2-server.service rke2-agent.service" not in unit:
        fail(name, "systemd unit is not wanted by the k3s/rke2 node services")

    runcmd = document.get("runcmd")
    if not isinstance(runcmd, list):
        fail(name, "runcmd is not a list")
    if "systemctl enable kh-annotate-node.service" not in runcmd:
        fail(name, "runcmd does not enable the annotation unit")
    if "systemctl enable --now kh-annotate-node.service" in runcmd:
        fail(name, "runcmd starts the annotation unit too early")

    for raw in (
        "node.longhorn.io/default-disks-config",
        '[{"path":"/var/lib/longhorn","allowScheduling":true}]',
    ):
        if raw in rendered:
            fail(name, f"raw annotation text leaked into rendered cloud-init: {raw}")

    print_pass(name, "annotation payload, script, unit, and enable-only runcmd render correctly")


def run_node_annotation_cloudinit_checks(scratch: TerraformScratch) -> None:
    templates = [
        REPO_ROOT / "modules/host/templates/cloudinit.yaml.tpl",
        REPO_ROOT / "templates/autoscaler-cloudinit.yaml.tpl",
    ]
    for template_path in templates:
        rendered, _ = render_cloudinit_with_vars(base_render_vars(), template_path)
        for forbidden in ("kh-annotate-node", "node-annotations.b64"):
            if forbidden in rendered:
                fail(
                    f"node annotations empty {template_path.relative_to(REPO_ROOT)}",
                    f"empty annotation map rendered {forbidden}",
                )
        print_pass(
            f"node annotations empty {template_path.relative_to(REPO_ROOT)}",
            "empty annotation map renders no annotation unit or payload",
        )

    write_files = node_annotation_write_files(scratch)
    runcmd = ["systemctl daemon-reload", "systemctl enable kh-annotate-node.service"]

    host_vars = base_render_vars()
    host_vars["cloudinit_write_files_extra"] = write_files
    host_vars["cloudinit_runcmd_extra"] = runcmd
    rendered, document = render_cloudinit_with_vars(
        host_vars,
        REPO_ROOT / "modules/host/templates/cloudinit.yaml.tpl",
    )
    assert_node_annotation_payload("node annotations host cloud-init", document, rendered)

    autoscaler_vars = base_render_vars()
    autoscaler_vars["cloudinit_write_files_common"] += scratch.yamlencode(write_files)
    autoscaler_vars["cloudinit_runcmd_common"] += scratch.yamlencode(runcmd)
    rendered, document = render_cloudinit_with_vars(
        autoscaler_vars,
        REPO_ROOT / "templates/autoscaler-cloudinit.yaml.tpl",
    )
    assert_node_annotation_payload("node annotations autoscaler cloud-init", document, rendered)


def split_yaml_documents(manifest: str) -> list[str]:
    documents: list[str] = []
    current: list[str] = []
    for line in manifest.splitlines():
        if line.strip() == "---":
            if any(candidate.strip() for candidate in current):
                documents.append("\n".join(current) + "\n")
            current = []
            continue
        current.append(line)
    if any(candidate.strip() for candidate in current):
        documents.append("\n".join(current) + "\n")
    return documents


def run_autoscaler_manifest_checks(scratch: TerraformScratch) -> None:
    extra_args = [
        "--scan-interval=10s",
        "--node-group-auto-discovery=label:kh=render # not yaml comment",
    ]
    render_vars = {
        "autoscaler_name": "cluster-autoscaler",
        "leader_election_resource_name": "cluster-autoscaler",
        "metrics_node_port": 30085,
        "cloudinit_config": "cmVuZGVy",
        "ca_image": "registry.k8s.io/autoscaling/cluster-autoscaler",
        "ca_version": "v1.32.0",
        "ca_replicas": 1,
        "ca_resource_limits": True,
        "ca_resources": {
            "limits": {"cpu": "100m", "memory": "300Mi"},
            "requests": {"cpu": "100m", "memory": "300Mi"},
        },
        "cluster_autoscaler_extra_args_yaml": scratch.yamlencode(extra_args),
        "cluster_autoscaler_tolerations": [],
        "cluster_autoscaler_log_level": 4,
        "cluster_autoscaler_log_to_stderr": True,
        "cluster_autoscaler_stderr_threshold": "INFO",
        "cluster_autoscaler_server_creation_timeout": "",
        "ssh_key": "123",
        "ipv4_subnet_id": "456",
        "snapshot_id": "789",
        "cluster_config": "e30=",
        "cluster_config_sha256": "abc123",
        "firewall_id": "321",
        "cluster_name": "render-",
        "node_pools": [
            {
                "min_nodes": 0,
                "max_nodes": 3,
                "server_type": "cpx21",
                "location": "nbg1",
                "name": "agent",
            }
        ],
        "enable_ipv4": True,
        "enable_ipv6": False,
    }

    path = scratch.write_template(
        "autoscaler_manifest",
        (REPO_ROOT / "templates/autoscaler.yaml.tpl").read_text(encoding="utf-8"),
    )
    (scratch.root / "autoscaler_manifest.tf").write_text(
        "\n".join(
            [
                "locals {",
                "  autoscaler_manifest_vars = jsondecode(<<JSON",
                hcl_json(render_vars),
                "JSON",
                "  )",
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    manifest = scratch.console(
        f"jsonencode(templatefile({hcl_string(path)}, local.autoscaler_manifest_vars))"
    )
    rendered = json.loads(json.loads(manifest))
    documents = [
        scratch.decode_yaml_string(document)
        for document in split_yaml_documents(rendered)
    ]
    deployment = next(
        (
            document
            for document in documents
            if isinstance(document, dict) and document.get("kind") == "Deployment"
        ),
        None,
    )
    if deployment is None:
        fail("autoscaler extra args", "rendered manifest has no Deployment document")
    containers = nested_get(
        deployment,
        ("spec", "template", "spec", "containers"),
    )
    if not isinstance(containers, list) or not containers:
        fail("autoscaler extra args", "Deployment has no containers")
    command = containers[0].get("command")
    if not isinstance(command, list):
        fail("autoscaler extra args", "Deployment container command is not a list")
    if command[-2:] != extra_args:
        fail("autoscaler extra args", f"decoded extra args tail was {command[-2:]!r}")
    print_pass("autoscaler extra args", "YAML-sensitive extra args decode as exact command list items")


def run_kubeconfig_checks(scratch: TerraformScratch) -> None:
    cert_blob = "ZGVmYXVsdAdefaultXYZ"
    kubeconfig_sample = """apiVersion: v1
kind: Config
clusters:
- name: default
  cluster:
    server: https://127.0.0.1:6443
    certificate-authority-data: ZGVmYXVsdAdefaultXYZ
contexts:
- name: default
  context:
    cluster: default
    user: default
current-context: default
users:
- name: default
  user:
    client-certificate-data: Y2xpZW50ZGVmYXVsdAdefaultXYZ
    client-key-data: a2V5ZGVmYXVsdAdefaultXYZ
"""
    (scratch.root / "kubeconfig_check.tf").write_text(
        "\n".join(
            [
                "locals {",
                f"  kubeconfig_check_sample = {hcl_string(kubeconfig_sample)}",
                '  kubeconfig_check_cluster_name = "mycluster"',
                '  kubeconfig_check_server = "https://203.0.113.10:6443"',
                "  kubeconfig_check_raw = yamldecode(local.kubeconfig_check_sample)",
                "  kubeconfig_check_rewritten = merge(local.kubeconfig_check_raw, {",
                "    clusters = [",
                "      for index, cluster in local.kubeconfig_check_raw[\"clusters\"] : index == 0 ? merge(cluster, {",
                "        name = cluster[\"name\"] == \"default\" ? local.kubeconfig_check_cluster_name : cluster[\"name\"]",
                "        cluster = merge(cluster[\"cluster\"], {",
                "          server = local.kubeconfig_check_server",
                "        })",
                "      }) : cluster",
                "    ]",
                "    contexts = [",
                "      for index, context in local.kubeconfig_check_raw[\"contexts\"] : index == 0 ? merge(context, {",
                "        name = context[\"name\"] == \"default\" ? local.kubeconfig_check_cluster_name : context[\"name\"]",
                "        context = merge(context[\"context\"], {",
                "          cluster = context[\"context\"][\"cluster\"] == \"default\" ? local.kubeconfig_check_cluster_name : context[\"context\"][\"cluster\"]",
                "          user    = context[\"context\"][\"user\"] == \"default\" ? local.kubeconfig_check_cluster_name : context[\"context\"][\"user\"]",
                "        })",
                "      }) : context",
                "    ]",
                "    users = [",
                "      for index, user in local.kubeconfig_check_raw[\"users\"] : index == 0 ? merge(user, {",
                "        name = user[\"name\"] == \"default\" ? local.kubeconfig_check_cluster_name : user[\"name\"]",
                "      }) : user",
                "    ]",
                "    \"current-context\" = local.kubeconfig_check_raw[\"current-context\"] == \"default\" ? local.kubeconfig_check_cluster_name : local.kubeconfig_check_raw[\"current-context\"]",
                "  })",
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )

    encoded = scratch.console("jsonencode(local.kubeconfig_check_rewritten)")
    rewritten = json.loads(json.loads(encoded))
    if rewritten["clusters"][0]["name"] != "mycluster":
        fail("kubeconfig structural rewrite", "cluster name was not rewritten")
    if rewritten["contexts"][0]["name"] != "mycluster":
        fail("kubeconfig structural rewrite", "context name was not rewritten")
    if rewritten["users"][0]["name"] != "mycluster":
        fail("kubeconfig structural rewrite", "user name was not rewritten")
    if rewritten["contexts"][0]["context"]["cluster"] != "mycluster":
        fail("kubeconfig structural rewrite", "context cluster reference was not rewritten")
    if rewritten["contexts"][0]["context"]["user"] != "mycluster":
        fail("kubeconfig structural rewrite", "context user reference was not rewritten")
    if rewritten["current-context"] != "mycluster":
        fail("kubeconfig structural rewrite", "current-context was not rewritten")
    if rewritten["clusters"][0]["cluster"]["server"] != "https://203.0.113.10:6443":
        fail("kubeconfig structural rewrite", "cluster server was not rewritten")
    if rewritten["clusters"][0]["cluster"]["certificate-authority-data"] != cert_blob:
        fail("kubeconfig structural rewrite", "certificate-authority-data was mutated")

    print_pass(
        "kubeconfig structural rewrite",
        "renamed only kubeconfig identity fields and preserved certificate data containing defaultXYZ",
    )


def run_shell_checks(scratch: TerraformScratch) -> None:
    for template_path in sorted((REPO_ROOT / "templates").glob("*.sh.tpl")):
        script = scratch.render_string(template_path)
        bash_syntax_check(str(template_path.relative_to(REPO_ROOT)), script)

    for name, body in sorted(discover_local_scripts().items()):
        path = scratch.write_template(name, body)
        try:
            script = scratch.render_string(path)
        except HarnessFailure as exc:
            print_skip(name, f"standalone render unavailable: {str(exc).splitlines()[0]}")
            continue
        bash_syntax_check(name, script)


def run_kustomization_path_checks(scratch: TerraformScratch) -> None:
    suffix = json.loads(
        json.loads(
            scratch.console(
                'jsonencode(replace("a.tpl.d/b.yaml.tpl", "/\\\\.tpl$/", ""))'
            )
        )
    )
    if suffix != "a.tpl.d/b.yaml":
        fail("kustomization tpl suffix strip", f"got {suffix!r}")

    paths = [
        "kustomization.yaml.tpl",
        "a.tpl.d/b.yaml.tpl",
        "evil$(touch x).tpl",
        "../escape.tpl",
        "safe/nested/resource.yml.tpl",
    ]
    invalid = json.loads(
        json.loads(
            scratch.console(
                "jsonencode(sort(["
                f"for file_path in {hcl_value(paths)} : file_path "
                'if !can(regex("^[A-Za-z0-9._/-]+$", file_path)) || contains(split("/", file_path), "..")'
                "]))"
            )
        )
    )
    if invalid != ["../escape.tpl", "evil$(touch x).tpl"]:
        fail("kustomization path validation", f"invalid paths were {invalid!r}")
    print_pass(
        "kustomization path validation",
        "suffix strip is trailing-only and unsafe template paths are detected",
    )


def main() -> int:
    if shutil.which("terraform") is None:
        print("FAIL terraform: terraform binary not found", file=sys.stderr)
        return 1
    if shutil.which("bash") is None:
        print("FAIL bash: bash binary not found", file=sys.stderr)
        return 1

    temp_dir = Path(tempfile.mkdtemp(prefix="kh-render-harness-"))
    try:
        scratch = TerraformScratch(temp_dir, base_render_vars())
        assert_addon_default_versions()
        assert_agent_private_ipv4_contract(scratch)
        run_helm_checks(scratch)
        run_shell_checks(scratch)
        run_cloudinit_checks(scratch)
        run_node_annotation_cloudinit_checks(scratch)
        run_autoscaler_manifest_checks(scratch)
        run_kubeconfig_checks(scratch)
        run_kustomization_path_checks(scratch)
    except HarnessFailure as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
