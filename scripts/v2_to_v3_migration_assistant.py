#!/usr/bin/env python3
"""Audit a kube-hetzner v2 Terraform root before a v3 upgrade.

The assistant is intentionally conservative: it reports required edits and
plan risks, but it does not rewrite HCL and it never applies Terraform plans.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Rule:
    name: str
    action: str
    target: str
    note: str


@dataclass(frozen=True)
class Finding:
    name: str
    action: str
    target: str
    note: str
    locations: tuple[str, ...]


@dataclass(frozen=True)
class TopologyWarning:
    name: str
    locations: tuple[str, ...]
    note: str


@dataclass(frozen=True)
class PlanRisk:
    address: str
    resource_type: str
    action: str
    actions: tuple[str, ...]
    blocker: bool


ONE_TO_ONE_RENAMES = {
    "kubernetes_distribution_type": "kubernetes_distribution",
    "k3s_token": "cluster_token",
    "secrets_encryption": "enable_secrets_encryption",
    "initial_k3s_channel": "k3s_channel",
    "install_k3s_version": "k3s_version",
    "initial_rke2_channel": "rke2_channel",
    "install_rke2_version": "rke2_version",
    "automatically_upgrade_k3s": "automatically_upgrade_kubernetes",
    "sys_upgrade_controller_version": "system_upgrade_controller_version",
    "additional_k3s_environment": "additional_kubernetes_install_environment",
    "kubeapi_port": "kubernetes_api_port",
    "k3s_registries": "registries_config",
    "k3s_kubelet_config": "kubelet_config",
    "k3s_audit_policy_config": "audit_policy_config",
    "k3s_audit_log_path": "audit_log_path",
    "k3s_audit_log_maxage": "audit_log_max_age",
    "k3s_audit_log_maxbackup": "audit_log_max_backups",
    "k3s_audit_log_maxsize": "audit_log_max_size",
    "k3s_exec_server_args": "control_plane_exec_args",
    "k3s_exec_agent_args": "agent_exec_args",
    "k3s_global_kubelet_args": "global_kubelet_args",
    "k3s_control_plane_kubelet_args": "control_plane_kubelet_args",
    "k3s_agent_kubelet_args": "agent_kubelet_args",
    "k3s_autoscaler_kubelet_args": "autoscaler_kubelet_args",
    "subnet_amount": "subnet_count",
    "use_control_plane_lb": "enable_control_plane_load_balancer",
    "combine_load_balancers": "reuse_control_plane_load_balancer",
    "control_plane_lb_type": "control_plane_load_balancer_type",
    "control_plane_lb_enable_public_interface": "control_plane_load_balancer_enable_public_network",
    "control_plane_lb_enable_public_network": "control_plane_load_balancer_enable_public_network",
    "lb_hostname": "load_balancer_hostname",
    "robot_ccm_enabled": "enable_robot_ccm",
    "cilium_loadbalancer_acceleration_mode": "cilium_load_balancer_acceleration_mode",
    "enable_wireguard": "enable_cni_wireguard_encryption",
    "k8s_config_updates_use_kured_sentinel": "kubernetes_config_updates_use_kured_sentinel",
    "keep_disk_agents": "keep_disk_agent_nodes",
    "keep_disk_cp": "keep_disk_control_plane_nodes",
    "use_private_bastion": "use_private_nat_router_bastion",
    "k3s_prefer_bundled_bin": "prefer_bundled_bin",
    "placement_group_compat_idx": "placement_group_index",
}

INVERTED_RENAMES = {
    "placement_group_disable": "enable_placement_groups",
    "block_icmp_ping_in": "allow_inbound_icmp",
    "disable_hetzner_csi": "enable_hetzner_csi",
    "load_balancer_disable_ipv6": "load_balancer_enable_ipv6",
    "load_balancer_disable_public_network": "load_balancer_enable_public_network",
    "disable_kube_proxy": "enable_kube_proxy",
    "disable_network_policy": "enable_network_policy",
    "disable_selinux": "enable_selinux",
    "disable_ipv4": "enable_public_ipv4",
    "disable_ipv6": "enable_public_ipv6",
    "autoscaler_disable_ipv4": "autoscaler_enable_public_ipv4",
    "autoscaler_disable_ipv6": "autoscaler_enable_public_ipv6",
}

SHAPE_CHANGES = {
    "existing_network_id": (
        "existing_network",
        "Convert list syntax such as existing_network_id = [\"123\"] to existing_network = { id = 123 }.",
    ),
    "enable_x86": (
        "enabled_architectures",
        "Replace enable_x86/enable_arm booleans with enabled_architectures, for example [\"x86\"] or [\"x86\", \"arm\"].",
    ),
    "enable_arm": (
        "enabled_architectures",
        "Replace enable_x86/enable_arm booleans with enabled_architectures, for example [\"x86\"] or [\"x86\", \"arm\"].",
    ),
    "extra_kustomize_folder": (
        "user_kustomizations",
        "Move source_folder into a user_kustomizations entry.",
    ),
    "extra_kustomize_parameters": (
        "user_kustomizations",
        "Move kustomize_parameters into a user_kustomizations entry.",
    ),
    "extra_kustomize_deployment_commands": (
        "user_kustomizations",
        "Move deployment commands to pre_commands or post_commands in a user_kustomizations entry.",
    ),
}

REMOVED_INPUTS = {
    "enable_iscsid": "Remove it; v3 enables iscsid where needed.",
    "k3s_encryption_at_rest": "Remove it; use enable_secrets_encryption.",
    "hetzner_ccm_use_helm": "Remove it; v3 always uses the CCM HelmChart path.",
    "enable_hetzner_ccm_helm": "Remove it; v3 always uses the CCM HelmChart path.",
    "autoscaler_labels": "Move labels into each autoscaler_nodepools entry.",
    "autoscaler_taints": "Move taints into each autoscaler_nodepools entry.",
}

TOPOLOGY_PATTERNS = {
    "nat_router": "NAT-router clusters need extra plan review, especially old primary IP state from pre-v2.19.0.",
    "use_private_bastion": "Private NAT-router bastion access must be rewritten to use_private_nat_router_bastion and tested before apply.",
    "vswitch_id": "Robot/vSwitch coupling is an advanced topology; validate route exposure and prefer blue/green if the plan is unclear.",
    "robot_ccm_enabled": "Robot CCM was renamed to enable_robot_ccm; also verify Robot credentials and route exposure.",
    "extra_robot_nodes": "Robot nodes require manual reachability review during the v3 upgrade.",
    "existing_network_id": "Existing Network shape changed; route exposure and subnet ownership need manual review.",
    "network_id": "network_id is active in v3. Omit/null means primary Network; positive IDs attach external Hetzner Networks.",
    "node_connection_overrides": "External overlays such as Tailscale are supported as operator-managed access, not core-managed lifecycle.",
    "enable_longhorn": "Longhorn and attached volumes require careful replacement review.",
    "longhorn_volume_size": "Longhorn node volumes require careful replacement review.",
    "autoscaler_nodepools": "Autoscaler nodepools need label/taint migration and per-network review when using external networks.",
    "multinetwork_mode": "Multinetwork scale is Cilium public overlay only in v3.",
}

CORE_BLOCKER_TYPES = {
    "hcloud_network",
    "hcloud_network_subnet",
    "hcloud_server",
    "hcloud_load_balancer",
    "hcloud_load_balancer_network",
    "hcloud_primary_ip",
    "hcloud_placement_group",
    "hcloud_volume",
}

SKIP_DIRS = {".git", ".terraform", ".terraform-tofu", ".terragrunt-cache"}
SCAN_SUFFIXES = {".tf", ".tfvars", ".hcl"}


def build_rules() -> dict[str, Rule]:
    rules: dict[str, Rule] = {}
    for name, target in ONE_TO_ONE_RENAMES.items():
        rules[name] = Rule(name, "rename", target, "Mechanical rename; keep the same value.")
    for name, target in INVERTED_RENAMES.items():
        rules[name] = Rule(name, "invert", target, "Rename and invert the boolean value.")
    for name, (target, note) in SHAPE_CHANGES.items():
        rules[name] = Rule(name, "reshape", target, note)
    for name, note in REMOVED_INPUTS.items():
        rules[name] = Rule(name, "remove", "-", note)
    return rules


def tf_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix not in SCAN_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        files.append(path)
    return sorted(files)


def active_line(line: str) -> str:
    stripped = line.strip()
    if stripped.startswith(("#", "//", "/*", "*")):
        return ""
    return line


def assignment_pattern(name: str) -> re.Pattern[str]:
    return re.compile(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])\s*=")


def collect_assignments(root: Path, names: set[str]) -> dict[str, list[str]]:
    patterns = {name: assignment_pattern(name) for name in names}
    locations: dict[str, list[str]] = {name: [] for name in names}
    for path in tf_files(root):
        rel = path.relative_to(root)
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            lines = path.read_text(errors="ignore").splitlines()
        for line_no, raw_line in enumerate(lines, start=1):
            line = active_line(raw_line)
            if not line:
                continue
            for name, pattern in patterns.items():
                if pattern.search(line):
                    locations[name].append(f"{rel}:{line_no}")
    return {name: locs for name, locs in locations.items() if locs}


def collect_findings(root: Path) -> list[Finding]:
    rules = build_rules()
    locations = collect_assignments(root, set(rules))
    findings: list[Finding] = []
    for name in sorted(locations):
        rule = rules[name]
        findings.append(
            Finding(
                name=rule.name,
                action=rule.action,
                target=rule.target,
                note=rule.note,
                locations=tuple(locations[name]),
            )
        )
    return findings


def collect_topology_warnings(root: Path) -> list[TopologyWarning]:
    locations = collect_assignments(root, set(TOPOLOGY_PATTERNS))
    warnings: list[TopologyWarning] = []
    for name in sorted(locations):
        warnings.append(TopologyWarning(name, tuple(locations[name]), TOPOLOGY_PATTERNS[name]))

    shared_subnet_locations = find_regex(
        root,
        re.compile(r"(?<![A-Za-z0-9_])network_subnet_mode(?![A-Za-z0-9_])\s*=\s*\"shared\""),
    )
    if shared_subnet_locations:
        warnings.append(
            TopologyWarning(
                "network_subnet_mode = shared",
                tuple(shared_subnet_locations),
                "Released v2 clusters used per-nodepool subnets. Shared mode is for new clusters or intentional topology changes; expect subnet resource changes on an in-place v2 upgrade.",
            )
        )

    network_zero = find_regex(root, re.compile(r"(?<![A-Za-z0-9_])network_id(?![A-Za-z0-9_])\s*=\s*0\b"))
    if network_zero:
        warnings.append(
            TopologyWarning(
                "network_id = 0",
                tuple(network_zero),
                "Remove network_id = 0; in v3 omitted/null means the primary kube-hetzner Network.",
            )
        )

    control_plane_network = find_control_plane_network_id(root)
    if control_plane_network:
        warnings.append(
            TopologyWarning(
                "control_plane_nodepools.network_id",
                tuple(control_plane_network),
                "Remove control-plane network_id; v3 keeps control planes on the primary Network.",
            )
        )

    return warnings


def find_regex(root: Path, pattern: re.Pattern[str]) -> list[str]:
    matches: list[str] = []
    for path in tf_files(root):
        rel = path.relative_to(root)
        for line_no, raw_line in enumerate(path.read_text(errors="ignore").splitlines(), start=1):
            line = active_line(raw_line)
            if line and pattern.search(line):
                matches.append(f"{rel}:{line_no}")
    return matches


def find_control_plane_network_id(root: Path) -> list[str]:
    matches: list[str] = []
    start_pattern = re.compile(r"(?<![A-Za-z0-9_])control_plane_nodepools(?![A-Za-z0-9_])\s*=")
    network_pattern = assignment_pattern("network_id")
    for path in tf_files(root):
        rel = path.relative_to(root)
        in_block = False
        depth = 0
        for line_no, raw_line in enumerate(path.read_text(errors="ignore").splitlines(), start=1):
            line = active_line(raw_line)
            if not line:
                continue
            if not in_block and start_pattern.search(line):
                in_block = True
                depth = bracket_delta(line)
            elif in_block:
                depth += bracket_delta(line)

            if in_block and network_pattern.search(line):
                matches.append(f"{rel}:{line_no}")

            if in_block and depth <= 0:
                in_block = False
    return matches


def bracket_delta(line: str) -> int:
    return line.count("[") + line.count("{") - line.count("]") - line.count("}")


def default_plan_json(root: Path) -> Path | None:
    candidate = root / "v3-upgrade-plan.json"
    return candidate if candidate.exists() else None


def classify_actions(actions: list[str]) -> str | None:
    action_set = set(actions)
    if "delete" in action_set and "create" in action_set:
        return "replace"
    if "delete" in action_set:
        return "delete"
    return None


def collect_plan_risks(plan_json: Path | None) -> list[PlanRisk]:
    if plan_json is None:
        return []
    data = json.loads(plan_json.read_text())
    risks: list[PlanRisk] = []
    for change in data.get("resource_changes", []):
        actions = list(change.get("change", {}).get("actions", []))
        action = classify_actions(actions)
        if action is None:
            continue
        resource_type = str(change.get("type", ""))
        risks.append(
            PlanRisk(
                address=str(change.get("address", "")),
                resource_type=resource_type,
                action=action,
                actions=tuple(actions),
                blocker=resource_type in CORE_BLOCKER_TYPES,
            )
        )
    return risks


def detect_module_lines(root: Path) -> list[str]:
    pattern = re.compile(r"\b(source|version)\s*=")
    lines: list[str] = []
    for path in tf_files(root):
        rel = path.relative_to(root)
        for line_no, raw_line in enumerate(path.read_text(errors="ignore").splitlines(), start=1):
            line = active_line(raw_line)
            if not line or not pattern.search(line):
                continue
            if "kube-hetzner" in line or "version" in line:
                lines.append(f"{rel}:{line_no}: {line.strip()}")
    return lines[:20]


def markdown_report(
    root: Path,
    findings: list[Finding],
    warnings: list[TopologyWarning],
    plan_risks: list[PlanRisk],
    plan_json: Path | None,
) -> str:
    blocker_count = sum(1 for risk in plan_risks if risk.blocker)
    manual_count = sum(1 for finding in findings if finding.action in {"invert", "reshape", "remove"})
    lines = [
        "# kube-hetzner v2 -> v3 migration assistant report",
        "",
        f"- Terraform root: `{root}`",
        f"- v2 input findings: {len(findings)}",
        f"- manual-review input findings: {manual_count}",
        f"- topology warnings: {len(warnings)}",
        f"- destructive plan actions: {len(plan_risks)}",
        f"- core-resource plan blockers: {blocker_count}",
    ]

    module_lines = detect_module_lines(root)
    if module_lines:
        lines.extend(["", "## Module/version hints"])
        lines.extend(f"- `{line}`" for line in module_lines)

    lines.extend(["", "## Input findings"])
    if findings:
        lines.append("| v2 input | action | v3 target | locations | note |")
        lines.append("| --- | --- | --- | --- | --- |")
        for finding in findings:
            locations = "<br>".join(f"`{location}`" for location in finding.locations)
            lines.append(
                f"| `{finding.name}` | {finding.action} | `{finding.target}` | {locations} | {finding.note} |"
            )
    else:
        lines.append("No known v2-only input assignments were found.")

    lines.extend(["", "## Topology warnings"])
    if warnings:
        lines.append("| signal | locations | note |")
        lines.append("| --- | --- | --- |")
        for warning in warnings:
            locations = "<br>".join(f"`{location}`" for location in warning.locations)
            lines.append(f"| `{warning.name}` | {locations} | {warning.note} |")
    else:
        lines.append("No advanced topology signals were found by the static scanner.")

    lines.extend(["", "## Plan risks"])
    if plan_json is None:
        lines.append("No plan JSON was provided. After planning, run:")
        lines.append("")
        lines.append("```bash")
        lines.append("terraform plan -out=v3-upgrade.tfplan")
        lines.append("terraform show -json v3-upgrade.tfplan > v3-upgrade-plan.json")
        lines.append("uv run python scripts/v2_to_v3_migration_assistant.py --root . --plan-json v3-upgrade-plan.json")
        lines.append("```")
    elif plan_risks:
        lines.append(f"Plan JSON: `{plan_json}`")
        lines.append("")
        lines.append("| address | type | action | blocker |")
        lines.append("| --- | --- | --- | --- |")
        for risk in plan_risks:
            lines.append(
                f"| `{risk.address}` | `{risk.resource_type}` | `{','.join(risk.actions)}` | {str(risk.blocker).lower()} |"
            )
    else:
        lines.append(f"Plan JSON: `{plan_json}`")
        lines.append("")
        lines.append("No delete/replace actions were found in the plan JSON.")

    lines.extend(["", "## Recommendation"])
    if blocker_count:
        lines.append("Do not apply. Explain or eliminate every core-resource blocker first.")
    elif findings:
        lines.append("Rewrite the reported inputs, run validation, then create and inspect a saved plan.")
    elif warnings:
        lines.append("The root has no obvious v2-only inputs, but the topology needs manual plan review before apply.")
    else:
        lines.append("The static scan is clean. Continue with validate and saved-plan review before applying.")

    return "\n".join(lines) + "\n"


def json_report(
    root: Path,
    findings: list[Finding],
    warnings: list[TopologyWarning],
    plan_risks: list[PlanRisk],
    plan_json: Path | None,
) -> str:
    payload: dict[str, Any] = {
        "root": str(root),
        "plan_json": str(plan_json) if plan_json else None,
        "findings": [asdict(finding) for finding in findings],
        "topology_warnings": [asdict(warning) for warning in warnings],
        "plan_risks": [asdict(risk) for risk in plan_risks],
        "summary": {
            "input_findings": len(findings),
            "manual_review_input_findings": sum(
                1 for finding in findings if finding.action in {"invert", "reshape", "remove"}
            ),
            "topology_warnings": len(warnings),
            "destructive_plan_actions": len(plan_risks),
            "core_resource_plan_blockers": sum(1 for risk in plan_risks if risk.blocker),
        },
    }
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit a kube-hetzner v2 Terraform root before upgrading to v3.",
    )
    parser.add_argument("--root", default=".", help="Terraform root to scan. Defaults to current directory.")
    parser.add_argument(
        "--plan-json",
        default=None,
        help="Optional terraform show -json output. Defaults to v3-upgrade-plan.json when present in --root.",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of Markdown.")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit non-zero when v2 inputs or core-resource plan blockers are found.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).expanduser().resolve()
    if not root.exists():
        print(f"Root does not exist: {root}", file=sys.stderr)
        return 2
    if not root.is_dir():
        print(f"Root is not a directory: {root}", file=sys.stderr)
        return 2

    plan_json = Path(args.plan_json).expanduser().resolve() if args.plan_json else default_plan_json(root)
    if plan_json is not None and not plan_json.exists():
        print(f"Plan JSON does not exist: {plan_json}", file=sys.stderr)
        return 2

    findings = collect_findings(root)
    warnings = collect_topology_warnings(root)
    plan_risks = collect_plan_risks(plan_json)

    if args.json:
        sys.stdout.write(json_report(root, findings, warnings, plan_risks, plan_json))
    else:
        sys.stdout.write(markdown_report(root, findings, warnings, plan_risks, plan_json))

    core_blockers = any(risk.blocker for risk in plan_risks)
    if args.strict and (findings or core_blockers):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
