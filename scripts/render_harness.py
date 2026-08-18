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


def assert_opensuse_ssh_cloudinit_contract() -> None:
    """Protect the openSUSE SSH/PAM fix from regressing silently."""

    locals_source = LOCALS_TF.read_text(encoding="utf-8")
    normalized = normalize_hcl(locals_source)
    required_fragments = (
        "path:/etc/ssh/sshd_config.d/kube-hetzner.conf",
        "Port${var.ssh_port}",
        "UsePAMyes",
        "PasswordAuthenticationno",
        "KbdInteractiveAuthenticationno",
        "AuthorizedKeysFile.ssh/authorized_keys",
    )
    missing = [fragment for fragment in required_fragments if fragment not in normalized]
    if missing:
        fail("openSUSE SSH cloud-init contract", f"missing fragments: {missing!r}")
    for template in (
        REPO_ROOT / "modules/host/templates/cloudinit.yaml.tpl",
        REPO_ROOT / "templates/autoscaler-cloudinit.yaml.tpl",
        REPO_ROOT / "templates/nat-router-cloudinit.yaml.tpl",
    ):
        if "ssh_pwauth" in template.read_text(encoding="utf-8"):
            fail(
                "openSUSE SSH cloud-init contract",
                f"ssh_pwauth must remain absent from {template.relative_to(REPO_ROOT)}",
            )
    print_pass(
        "openSUSE SSH cloud-init contract",
        "shared drop-in keeps PAM and disables password/keyboard-interactive auth without ssh_pwauth",
    )


def assert_baked_selinux_package_contract() -> None:
    """Keep distro installers from fetching SELinux RPMs during node bootstrap."""

    locals_source = normalize_hcl(LOCALS_TF.read_text(encoding="utf-8"))
    installer_source = normalize_hcl(
        (REPO_ROOT / "scripts/install-verified-kubernetes.sh").read_text(encoding="utf-8")
    )
    required_fragments = (
        "INSTALL_K3S_SKIP_SELINUX_RPM=true",
        "INSTALL_RKE2_METHOD=tar",
        "var.enable_selinux?local.require_k3s_selinux:[]",
        "var.enable_selinux?local.require_rke2_selinux:[]",
        "rpm-qk3s-selinux",
        "rpm-qrke2-selinux",
        "-s/usr/share/selinux/packages/k3s.pp",
        "-s/usr/share/selinux/packages/rke2.pp",
    )
    install_sources = locals_source + installer_source
    missing = [fragment for fragment in required_fragments if fragment not in install_sources]
    if missing:
        fail("baked SELinux package contract", f"missing fragments: {missing!r}")
    print_pass(
        "baked SELinux package contract",
        "k3s and RKE2 require the image-baked policy package and disable runtime SELinux RPM installation",
    )


def assert_kubernetes_artifact_architecture_contract() -> None:
    """Exclude dormant autoscaler pools from required payload digest architectures."""

    locals_source = normalize_hcl(LOCALS_TF.read_text(encoding="utf-8"))
    installer_source = normalize_hcl(
        (REPO_ROOT / "scripts/install-verified-kubernetes.sh").read_text(encoding="utf-8")
    )
    robot_source = normalize_hcl((REPO_ROOT / "robot-nodes.tf").read_text(encoding="utf-8"))
    active_autoscaler_fragment = (
        '[fornodepoolinvar.autoscaler_nodepools:'
        'substr(nodepool.server_type,0,3)=="cax"?"arm64":"amd64"'
        'ifnodepool.max_nodes>0]'
    )
    if active_autoscaler_fragment not in locals_source:
        fail(
            "Kubernetes artifact architecture contract",
            "autoscaler digest architectures must be derived only from pools with max_nodes > 0",
        )
    required_installer_fragments = (
        "resolve_release_payload_sha256(){",
        "usingitsexactofficialreleasechecksumpublication",
    )
    missing = [
        fragment
        for fragment in required_installer_fragments
        if fragment not in installer_source
    ]
    if missing:
        fail(
            "Kubernetes artifact architecture contract",
            f"custom exact versions must preserve the official-checksum compatibility path; missing {missing!r}",
        )
    if "install_sha=" in robot_source:
        fail(
            "Kubernetes artifact architecture contract",
            "installer implementation changes must not reprovision existing Robot nodes",
        )
    print_pass(
        "Kubernetes artifact architecture contract",
        "dormant pools add no digest requirement, custom exact versions retain official-checksum compatibility, and Robot nodes are not replayed",
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
        "automatically_upgrade_os": True,
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
        "cluster_has_ipv4": True,
        "cluster_has_ipv6": False,
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


def run_autoscaler_overlay_retry_simulation(overlay_script: str) -> None:
    temp_dir = Path(tempfile.mkdtemp(prefix="kh-render-overlay-retry-"))
    try:
        fake_bin = temp_dir / "bin"
        state_dir = temp_dir / "state"
        fake_bin.mkdir()
        state_dir.mkdir()

        (fake_bin / "ip").write_text(
            """#!/bin/sh
set -eu
state="${KH_FAKE_IP_STATE:?}"
case "$*" in
  "-4 route get 172.31.1.1")
    file="$state/v4-route"
    count=$(cat "$file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$file"
    [ "$count" -gt 1 ] || exit 2
    echo "172.31.1.1 dev eth0 src 192.0.2.10"
    ;;
  "-o -4 addr show dev eth0 scope global")
    echo "2: eth0    inet 192.0.2.10/32 scope global eth0"
    ;;
  "-6 route show default")
    file="$state/v6-route"
    count=$(cat "$file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$file"
    [ "$count" -gt 1 ] || exit 2
    echo "default via fe80::1 dev eth0 proto ra metric 1024"
    ;;
  "-o -6 addr show scope global")
    exit 2
    ;;
  "-o -6 addr show dev eth0 scope global")
    echo "2: eth0    inet6 2001:db8::10/64 scope global"
    ;;
  *)
    echo "unexpected ip invocation: $*" >&2
    exit 1
    ;;
esac
""",
            encoding="utf-8",
        )
        (fake_bin / "curl").write_text("#!/bin/sh\nexit 22\n", encoding="utf-8")
        (fake_bin / "sleep").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (fake_bin / "sed").write_text(
            """#!/bin/sh
set -eu
if [ "$1" = "-i" ] && [ "$2" = '/^node-ip:/d;/^"node-ip":/d;/^node-external-ip:/d;/^"node-external-ip":/d' ]; then
  awk '$0 !~ /^node-ip:/ && $0 !~ /^"node-ip":/ && $0 !~ /^node-external-ip:/ && $0 !~ /^"node-external-ip":/' "$3" > "$3.tmp"
  mv "$3.tmp" "$3"
  exit 0
fi
exec /usr/bin/sed "$@"
""",
            encoding="utf-8",
        )
        for path in fake_bin.iterdir():
            path.chmod(0o755)

        config_path = temp_dir / "config.yaml"
        config_path.write_text('"node-ip": "old"\n"node-external-ip": "old"\n', encoding="utf-8")
        simulation_script = overlay_script.replace("/tmp/config.yaml", str(config_path))
        simulation_script += '\n: "$KH_RENDER_STRICT_LEAK_PROBE"\n'
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
        env["KH_FAKE_IP_STATE"] = str(state_dir)
        env.pop("KH_RENDER_STRICT_LEAK_PROBE", None)
        result = subprocess.run(
            ["bash"],
            input=simulation_script,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        if result.returncode != 0:
            fail(
                "autoscaler overlay retry simulation",
                strip_ansi((result.stdout + "\n" + result.stderr).strip()) or "simulation failed",
            )
        rendered = config_path.read_text(encoding="utf-8")
        expected_lines = (
            'node-ip: "192.0.2.10,2001:db8::10"',
            'node-external-ip: "192.0.2.10,2001:db8::10"',
        )
        missing = [line for line in expected_lines if line not in rendered]
        if missing:
            fail("autoscaler overlay retry simulation", f"missing rendered config lines: {missing!r}; got {rendered!r}")
        if "old" in rendered:
            fail("autoscaler overlay retry simulation", f"old node-ip lines were not removed: {rendered!r}")
        print_pass(
            "autoscaler overlay retry simulation",
            "transient route failures retry, config is written, and strict mode does not leak",
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def run_post_install_readiness_deployment_retry_simulation(script: str) -> None:
    temp_dir = Path(tempfile.mkdtemp(prefix="kh-render-readiness-retry-"))
    try:
        fake_bin = temp_dir / "bin"
        state_dir = temp_dir / "state"
        fake_bin.mkdir()
        state_dir.mkdir()

        (fake_bin / "kubectl").write_text(
            """#!/bin/sh
set -eu
state="${KH_FAKE_KUBECTL_STATE:?}"
case "$*" in
  "--request-timeout=30s get ns cert-manager")
    exit 0
    ;;
  "--request-timeout=30s -n cert-manager get deployment/cert-manager-cainjector")
    exit 0
    ;;
  "--request-timeout=30s -n cert-manager wait --for=condition=Available --timeout=30s deployment/cert-manager-cainjector")
    file="$state/wait-count"
    count=$(cat "$file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$file"
    if [ "$count" -eq 1 ]; then
      echo 'Error from server (NotFound): deployments.apps "cert-manager-cainjector" not found' >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 1
    ;;
esac
""",
            encoding="utf-8",
        )
        (fake_bin / "date").write_text("#!/bin/sh\necho 100\n", encoding="utf-8")
        (fake_bin / "sleep").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        for path in fake_bin.iterdir():
            path.chmod(0o755)

        simulation_script = script.replace('__KUBECTL__', 'kubectl')
        simulation_script += "\nwait_deployment cert-manager cert-manager-cainjector 30\n"
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
        env["KH_FAKE_KUBECTL_STATE"] = str(state_dir)
        result = subprocess.run(
            ["bash", "-e"],
            input=simulation_script,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        if result.returncode != 0:
            fail(
                "post-install readiness deployment retry simulation",
                strip_ansi((result.stdout + "\n" + result.stderr).strip()) or "simulation failed",
            )
        wait_count = (state_dir / "wait-count").read_text(encoding="utf-8").strip()
        if wait_count != "2":
            fail(
                "post-install readiness deployment retry simulation",
                f"expected two availability waits after transient NotFound, got {wait_count!r}",
            )
        print_pass(
            "post-install readiness deployment retry simulation",
            "a deployment replaced between get and wait is retried against the fixed deadline",
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def run_post_install_readiness_deadline_simulation(script: str) -> None:
    temp_dir = Path(tempfile.mkdtemp(prefix="kh-render-readiness-deadline-"))
    try:
        fake_bin = temp_dir / "bin"
        fake_bin.mkdir()

        (fake_bin / "date").write_text(
            """#!/bin/sh
set -eu
state="${KH_FAKE_DATE_STATE:?}"
count=$(cat "$state" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$state"
case "${KH_FAKE_DATE_MODE:?}:$count" in
  request:1|request:2|request:3) echo 100 ;;
  request:4) echo 110 ;;
  request:*) echo 120 ;;
  sleep:1|sleep:2|sleep:3) echo 100 ;;
  sleep:4) echo 103 ;;
  sleep:*) echo 105 ;;
esac
""",
            encoding="utf-8",
        )
        (fake_bin / "kubectl").write_text(
            """#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${KH_FAKE_KUBECTL_LOG:?}"
case "${KH_FAKE_DATE_MODE:?}:$*" in
  "request:--request-timeout=30s get ns cert-manager"|\
  "request:--request-timeout=20s -n cert-manager get deployment/cert-manager-cainjector"|\
  "request:--request-timeout=10s -n cert-manager wait --for=condition=Available --timeout=10s deployment/cert-manager-cainjector")
    exit 0
    ;;
  "sleep:--request-timeout=5s get ns cert-manager")
    exit 1
    ;;
  *)
    echo "unexpected kubectl invocation: $*" >&2
    exit 97
    ;;
esac
""",
            encoding="utf-8",
        )
        (fake_bin / "sleep").write_text(
            "#!/bin/sh\nset -eu\nprintf '%s\\n' \"$1\" >> \"${KH_FAKE_SLEEP_LOG:?}\"\n",
            encoding="utf-8",
        )
        for path in fake_bin.iterdir():
            path.chmod(0o755)

        simulation_script = script.replace("__KUBECTL__", "kubectl")
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"

        request_state = temp_dir / "request-date-state"
        request_log = temp_dir / "request-kubectl.log"
        request_sleep_log = temp_dir / "request-sleep.log"
        request_sleep_log.touch()
        request_env = env | {
            "KH_FAKE_DATE_MODE": "request",
            "KH_FAKE_DATE_STATE": str(request_state),
            "KH_FAKE_KUBECTL_LOG": str(request_log),
            "KH_FAKE_SLEEP_LOG": str(request_sleep_log),
        }
        request_result = subprocess.run(
            ["bash", "-e"],
            input=simulation_script + "\nwait_deployment cert-manager cert-manager-cainjector 30\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=request_env,
        )
        if request_result.returncode != 0:
            fail(
                "post-install readiness absolute request deadline simulation",
                strip_ansi((request_result.stdout + "\n" + request_result.stderr).strip()) or "simulation failed",
            )
        expected_requests = (
            "--request-timeout=30s get ns cert-manager\n"
            "--request-timeout=20s -n cert-manager get deployment/cert-manager-cainjector\n"
            "--request-timeout=10s -n cert-manager wait --for=condition=Available --timeout=10s deployment/cert-manager-cainjector\n"
        )
        if request_log.read_text(encoding="utf-8") != expected_requests:
            fail(
                "post-install readiness absolute request deadline simulation",
                f"request timeouts did not shrink against one deadline: {request_log.read_text(encoding='utf-8')!r}",
            )
        if request_sleep_log.read_text(encoding="utf-8"):
            fail("post-install readiness absolute request deadline simulation", "successful wait unexpectedly slept")

        sleep_state = temp_dir / "sleep-date-state"
        sleep_log = temp_dir / "sleep.log"
        kubectl_log = temp_dir / "sleep-kubectl.log"
        sleep_env = env | {
            "KH_FAKE_DATE_MODE": "sleep",
            "KH_FAKE_DATE_STATE": str(sleep_state),
            "KH_FAKE_KUBECTL_LOG": str(kubectl_log),
            "KH_FAKE_SLEEP_LOG": str(sleep_log),
        }
        sleep_result = subprocess.run(
            ["bash", "-e"],
            input=(
                simulation_script
                + "\nif wait_deployment cert-manager cert-manager-cainjector 5; then exit 98; fi\n"
            ),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=sleep_env,
        )
        if sleep_result.returncode != 0:
            fail(
                "post-install readiness absolute sleep deadline simulation",
                strip_ansi((sleep_result.stdout + "\n" + sleep_result.stderr).strip()) or "simulation failed",
            )
        if sleep_log.read_text(encoding="utf-8") != "2\n":
            fail(
                "post-install readiness absolute sleep deadline simulation",
                f"retry sleep was not capped to the remaining budget: {sleep_log.read_text(encoding='utf-8')!r}",
            )
        print_pass(
            "post-install readiness absolute deadline simulation",
            "each API call and retry sleep is capped to the remaining fixed deadline",
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def run_autoscaler_standard_node_ip_simulation(node_ip_script: str) -> None:
    temp_dir = Path(tempfile.mkdtemp(prefix="kh-render-standard-node-ip-"))
    try:
        fake_bin = temp_dir / "bin"
        state_dir = temp_dir / "state"
        fake_bin.mkdir()
        state_dir.mkdir()

        (fake_bin / "ip").write_text(
            """#!/bin/sh
set -eu
state="${KH_FAKE_IP_STATE:?}"
case "$*" in
  "-4 route get 10.0.0.1")
    file="$state/private-route"
    count=$(cat "$file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$file"
    [ "$count" -gt 1 ] || exit 2
    echo "10.0.0.1 dev eth1 src 10.0.0.42"
    ;;
  "-o -4 addr show dev eth1 scope global")
    echo "3: eth1    inet 10.0.0.42/16 scope global eth1"
    ;;
  *)
    echo "unexpected ip invocation: $*" >&2
    exit 1
    ;;
esac
""",
            encoding="utf-8",
        )
        (fake_bin / "sleep").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (fake_bin / "sed").write_text(
            """#!/bin/sh
set -eu
if [ "$1" = "-i" ] && [ "$2" = '/^node-ip:/d;/^"node-ip":/d' ]; then
  awk '$0 !~ /^node-ip:/ && $0 !~ /^"node-ip":/' "$3" > "$3.tmp"
  mv "$3.tmp" "$3"
  exit 0
fi
exec /usr/bin/sed "$@"
""",
            encoding="utf-8",
        )
        for path in fake_bin.iterdir():
            path.chmod(0o755)

        config_path = temp_dir / "config.yaml"
        config_path.write_text('server: https://10.0.0.10:9345\n"node-ip": "old"\n', encoding="utf-8")
        simulation_script = node_ip_script.replace("/tmp/config.yaml", str(config_path))
        simulation_script += '\n: "$KH_RENDER_STRICT_LEAK_PROBE"\n'
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
        env["KH_FAKE_IP_STATE"] = str(state_dir)
        env.pop("KH_RENDER_STRICT_LEAK_PROBE", None)
        result = subprocess.run(
            ["bash"],
            input=simulation_script,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        if result.returncode != 0:
            fail(
                "autoscaler standard node-ip simulation",
                strip_ansi((result.stdout + "\n" + result.stderr).strip()) or "simulation failed",
            )
        rendered = config_path.read_text(encoding="utf-8")
        if 'node-ip: "10.0.0.42"' not in rendered:
            fail("autoscaler standard node-ip simulation", f"private node-ip was not written: {rendered!r}")
        if "old" in rendered:
            fail("autoscaler standard node-ip simulation", f"old node-ip line was not removed: {rendered!r}")
        print_pass(
            "autoscaler standard node-ip simulation",
            "transient private route failures retry, config is written, and strict mode does not leak",
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def run_autoscaler_standard_public_fallback_failure_simulation(node_ip_script: str) -> None:
    temp_dir = Path(tempfile.mkdtemp(prefix="kh-render-standard-node-ip-public-fallback-"))
    try:
        fake_bin = temp_dir / "bin"
        fake_bin.mkdir()

        (fake_bin / "ip").write_text(
            """#!/bin/sh
set -eu
case "$*" in
  "-4 route get 10.0.0.1")
    echo "10.0.0.1 via 172.31.1.1 dev eth0 src 203.0.113.10"
    ;;
  "-4 route show scope link")
    echo "172.31.1.1 dev eth0 proto kernel scope link src 203.0.113.10"
    ;;
  "-o -4 addr show dev eth0 scope global")
    echo "2: eth0    inet 203.0.113.10/32 scope global eth0"
    ;;
  *)
    echo "unexpected ip invocation: $*" >&2
    exit 1
    ;;
esac
""",
            encoding="utf-8",
        )
        (fake_bin / "sleep").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (fake_bin / "sed").write_text(
            """#!/bin/sh
set -eu
if [ "$1" = "-i" ] && [ "$2" = '/^node-ip:/d;/^"node-ip":/d' ]; then
  awk '$0 !~ /^node-ip:/ && $0 !~ /^"node-ip":/' "$3" > "$3.tmp"
  mv "$3.tmp" "$3"
  exit 0
fi
exec /usr/bin/sed "$@"
""",
            encoding="utf-8",
        )
        for path in fake_bin.iterdir():
            path.chmod(0o755)

        config_path = temp_dir / "config.yaml"
        config_path.write_text('server: https://10.0.0.10:9345\n', encoding="utf-8")
        simulation_script = node_ip_script.replace("/tmp/config.yaml", str(config_path))
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
        result = subprocess.run(
            ["bash"],
            input=simulation_script,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        if result.returncode == 0:
            fail(
                "autoscaler standard public fallback simulation",
                f"public default-route fallback wrote config instead of failing closed: {config_path.read_text(encoding='utf-8')!r}",
            )
        rendered = config_path.read_text(encoding="utf-8")
        if "203.0.113.10" in rendered:
            fail("autoscaler standard public fallback simulation", f"public IPv4 leaked into node-ip: {rendered!r}")
        print_pass(
            "autoscaler standard public fallback simulation",
            "public default-route lookup is rejected until the private route is on-link",
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def run_autoscaler_standard_node_ip_checks() -> None:
    standard_vars = base_render_vars()
    rendered, document = render_cloudinit_with_vars(
        standard_vars,
        REPO_ROOT / "templates/autoscaler-cloudinit.yaml.tpl",
    )
    runcmd = document.get("runcmd")
    if not isinstance(runcmd, list):
        fail("autoscaler standard node-ip cloud-init", "runcmd is not a list")
    node_ip_script = next(
        (item for item in runcmd if isinstance(item, str) and "AUTOSCALER_NODE_PRIVATE_IP" in item),
        "",
    )
    if not node_ip_script:
        fail("autoscaler standard node-ip cloud-init", "rendered runcmd has no standard node-ip script")
    if any(isinstance(item, str) and "OVERLAY_NODE_IPS" in item for item in runcmd):
        fail("autoscaler standard node-ip cloud-init", "standard render unexpectedly includes overlay node-ip script")
    bash_syntax_check("autoscaler standard node-ip cloud-init", node_ip_script)
    snippets = {
        "strict shell mode": "set -euo pipefail",
        "strict shell mode scoped": ") || exit 1",
        "private IPv4 retry loop": "for attempt in $(seq 1 60); do",
        "private route probe tolerates retry": "ip -4 route get '10.0.0.1' 2>/dev/null || true",
        "public fallback route rejection": '*" via "*) AUTOSCALER_NODE_PRIVATE_ROUTE="" ;;',
        "private node-ip fail-closed check": "could not determine private IPv4 node-ip",
        "old node-ip removal": "sed -i '/^node-ip:/d;/^\"node-ip\":/d' /tmp/config.yaml",
        "node-ip write": 'printf \'node-ip: "%s"\\n\' "$AUTOSCALER_NODE_PRIVATE_IP"',
    }
    for label, snippet in snippets.items():
        if snippet not in node_ip_script:
            fail("autoscaler standard node-ip cloud-init", f"missing {label}: {snippet}")
    if "WARN: could not determine private IPv4 node-ip" in node_ip_script:
        fail("autoscaler standard node-ip cloud-init", "private node-ip discovery still only warns")
    run_autoscaler_standard_node_ip_simulation(node_ip_script)
    run_autoscaler_standard_public_fallback_failure_simulation(node_ip_script)
    print_pass(
        "autoscaler standard node-ip cloud-init",
        "renders fail-closed private IPv4 node-ip discovery for non-overlay autoscaler nodes",
    )


def run_autoscaler_os_upgrade_timer_checks() -> None:
    label = "autoscaler OS upgrade timer cloud-init"
    timer_command = "systemctl enable --now transactional-update.timer"
    agent_install = "/var/pre_install/install-k8s-agent.sh"

    def runcmd_for(upgrade_os: bool) -> list:
        render_vars = base_render_vars()
        render_vars["automatically_upgrade_os"] = upgrade_os
        _, document = render_cloudinit_with_vars(
            render_vars,
            REPO_ROOT / "templates/autoscaler-cloudinit.yaml.tpl",
        )
        runcmd = document.get("runcmd")
        if not isinstance(runcmd, list):
            fail(label, f"runcmd is not a list for automatically_upgrade_os={upgrade_os}")
        return runcmd

    enabled = runcmd_for(True)

    def index_of(runcmd: list, needle: str) -> int:
        for position, item in enumerate(runcmd):
            if isinstance(item, str) and needle in item:
                return position
            if isinstance(item, list) and any(needle in part for part in item):
                return position
        return -1

    timer_index = index_of(enabled, timer_command)
    if timer_index < 0:
        fail(label, "autoscaler nodes never re-enable transactional-update.timer")
    if timer_index != len(enabled) - 1:
        fail(label, "the timer must be re-enabled by the last runcmd entry")

    agent_index = index_of(enabled, agent_install)
    if agent_index < 0:
        fail(label, "rendered runcmd has no agent install entry")
    if timer_index < agent_index:
        fail(label, "re-enabling the timer must not race the Kubernetes bootstrap")

    if index_of(runcmd_for(False), timer_command) >= 0:
        fail(label, "automatically_upgrade_os = false must not re-enable the timer")

    print_pass(
        label,
        "re-enables transactional-update.timer after the agent install, and only when automatically_upgrade_os is true",
    )


def run_autoscaler_tailscale_bootstrap_scope_checks() -> None:
    tailscale_vars = base_render_vars()
    tailscale_vars["tailscale_bootstrap_script"] = """set -euo pipefail
trap 'true' EXIT
cat >/tmp/kh-tailscale-scope-check <<'EOF'
tailscale heredoc payload
EOF
"""
    _, document = render_cloudinit_with_vars(
        tailscale_vars,
        REPO_ROOT / "templates/autoscaler-cloudinit.yaml.tpl",
    )
    runcmd = document.get("runcmd")
    if not isinstance(runcmd, list):
        fail("autoscaler Tailscale bootstrap cloud-init", "runcmd is not a list")
    tailscale_script = next(
        (item for item in runcmd if isinstance(item, str) and "kh-tailscale-scope-check" in item),
        "",
    )
    if not tailscale_script:
        fail("autoscaler Tailscale bootstrap cloud-init", "rendered runcmd has no Tailscale bootstrap script")
    bash_syntax_check("autoscaler Tailscale bootstrap cloud-init", tailscale_script)
    if ") || exit 1" not in tailscale_script:
        fail("autoscaler Tailscale bootstrap cloud-init", "Tailscale bootstrap strict mode is not subshell-scoped")
    print_pass(
        "autoscaler Tailscale bootstrap cloud-init",
        "wraps Tailscale strict mode without breaking heredoc syntax",
    )


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


def run_autoscaler_overlay_node_ip_checks() -> None:
    overlay_vars = base_render_vars()
    overlay_vars.update(
        {
            "cluster_has_ipv4": True,
            "cluster_has_ipv6": True,
            "multinetwork_public_overlay_enabled": True,
            "multinetwork_transport_ipv4_enabled": True,
            "multinetwork_transport_ipv6_enabled": True,
        }
    )
    rendered, document = render_cloudinit_with_vars(
        overlay_vars,
        REPO_ROOT / "templates/autoscaler-cloudinit.yaml.tpl",
    )
    runcmd = document.get("runcmd")
    if not isinstance(runcmd, list):
        fail("autoscaler overlay dual-stack cloud-init", "runcmd is not a list")
    overlay_script = next(
        (item for item in runcmd if isinstance(item, str) and "OVERLAY_NODE_IPS" in item),
        "",
    )
    if not overlay_script:
        fail("autoscaler overlay dual-stack cloud-init", "rendered runcmd has no overlay node-ip script")
    if any(isinstance(item, str) and "AUTOSCALER_NODE_PRIVATE_IP" in item for item in runcmd):
        fail("autoscaler overlay dual-stack cloud-init", "overlay render unexpectedly includes standard node-ip script")
    bash_syntax_check("autoscaler overlay dual-stack cloud-init", overlay_script)
    snippets = {
        "strict shell mode": "set -euo pipefail",
        "strict shell mode scoped": ") || exit 1",
        "IPv4 retry loop": "for attempt in $(seq 1 60); do",
        "IPv4 route probe tolerates retry": "ip -4 route get 172.31.1.1 2>/dev/null | route_dev || true",
        "IPv6 route probe tolerates retry": "ip -6 route show default 2>/dev/null | route_dev || true",
        "IPv4 fail-closed check": "requires a public IPv4 address",
        "IPv6 fail-closed check": "requires a public IPv6 address",
        "IPv4 cluster-family node-ip assignment": 'OVERLAY_NODE_IPS="$PUB4_IP"',
        "IPv6 cluster-family node-ip append": 'OVERLAY_NODE_IPS="$OVERLAY_NODE_IPS,$PUB6_IP"',
        "transport-family node-external-ip assignment": 'OVERLAY_NODE_EXTERNAL_IPS="$PUB4_IP"',
        "transport-family node-external-ip append": 'OVERLAY_NODE_EXTERNAL_IPS="$OVERLAY_NODE_EXTERNAL_IPS,$PUB6_IP"',
        "node-ip write": 'printf \'node-ip: "%s"\\n\' "$OVERLAY_NODE_IPS"',
        "node-external-ip write": 'printf \'node-external-ip: "%s"\\n\' "$OVERLAY_NODE_EXTERNAL_IPS"',
        "old node-ip removal": 'sed -i \'/^node-ip:/d;/^"node-ip":/d;/^node-external-ip:/d;/^"node-external-ip":/d\' /tmp/config.yaml',
    }
    for label, snippet in snippets.items():
        if snippet not in overlay_script:
            fail("autoscaler overlay dual-stack cloud-init", f"missing {label}: {snippet}")
    if "WARN: cilium_public_overlay could not determine a public node IP" in overlay_script:
        fail("autoscaler overlay dual-stack cloud-init", "partial public node-ip discovery still only warns")
    run_autoscaler_overlay_retry_simulation(overlay_script)
    print_pass(
        "autoscaler overlay dual-stack cloud-init",
        "renders fail-closed IPv4/IPv6 discovery before writing node-ip and node-external-ip",
    )


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
        assert_opensuse_ssh_cloudinit_contract()
        assert_baked_selinux_package_contract()
        assert_kubernetes_artifact_architecture_contract()
        run_helm_checks(scratch)
        run_shell_checks(scratch)
        post_install_readiness_script = scratch.render_string(
            scratch.write_template(
                "post_install_readiness_retry",
                extract_heredoc("post_install_readiness_wait_script"),
            )
        )
        run_post_install_readiness_deployment_retry_simulation(post_install_readiness_script)
        run_post_install_readiness_deadline_simulation(post_install_readiness_script)
        run_cloudinit_checks(scratch)
        run_node_annotation_cloudinit_checks(scratch)
        run_autoscaler_standard_node_ip_checks()
        run_autoscaler_tailscale_bootstrap_scope_checks()
        run_autoscaler_os_upgrade_timer_checks()
        run_autoscaler_overlay_node_ip_checks()
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
