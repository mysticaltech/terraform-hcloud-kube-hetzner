#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
"""Validate the large-scale Tailscale example topology math.

This is a lightweight preflight for examples that are intentionally too large
to live-test casually. It does not replace Terraform validation; it checks that
the documented +100-node and 10,000-node reference layouts still match the
actual example HCL and stay inside the Hetzner limits they claim to respect.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


NETWORK_ATTACHMENT_LIMIT = 100
PLACEMENT_GROUP_SERVER_LIMIT = 10
PLACEMENT_GROUP_PROJECT_LIMIT = 50


@dataclass(frozen=True)
class ExampleCheck:
    name: str
    total_nodes: int
    network_attachments: dict[str, int]
    placement_groups: int
    exposure: dict[str, bool]
    notes: tuple[str, ...]


class CheckError(ValueError):
    pass


def active_hcl(text: str) -> str:
    lines: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(("#", "//")):
            continue
        lines.append(line)
    return "\n".join(lines)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CheckError(message)


def require_match(pattern: str, text: str, message: str, flags: int = re.S) -> re.Match[str]:
    match = re.search(pattern, text, flags)
    if match is None:
        raise CheckError(message)
    return match


def require_assignment(text: str, name: str, value: str) -> None:
    require(
        re.search(rf"(?m)^\s*{re.escape(name)}\s*=\s*{re.escape(value)}\s*$", text) is not None,
        f"Expected active assignment {name} = {value}.",
    )


def extract_named_block_count(text: str, name: str) -> int:
    block = require_match(
        rf'\{{(?:(?!\n\s*\}}).)*name\s*=\s*"{re.escape(name)}"(?P<body>.*?)(?:\n\s*\}},|\n\s*\}})',
        text,
        f'Missing nodepool block named "{name}".',
    )
    count = require_match(
        r"(?m)^\s*count\s*=\s*(?P<count>\d+)\s*$",
        block.group("body"),
        f'Missing count in nodepool "{name}".',
    )
    return int(count.group("count"))


def extract_assignment_int(text: str, pattern: str, message: str) -> int:
    match = require_match(pattern, text, message)
    return int(match.group("value"))


def placement_groups_for_static_counts(*counts: int) -> int:
    return sum(math.ceil(count / PLACEMENT_GROUP_SERVER_LIMIT) for count in counts if count > 0)


def validate_secure_tailscale_exposure(text: str, example_name: str) -> dict[str, bool]:
    require_assignment(text, "node_transport_mode", '"tailscale"')
    require_assignment(text, "firewall_kube_api_source", "null")
    require_assignment(text, "firewall_ssh_source", "null")
    require_assignment(text, "ingress_controller", '"none"')
    require_assignment(text, "bootstrap_mode", '"cloud_init"')
    require_assignment(text, "advertise_node_private_routes", "true")
    require(
        re.search(r"(?m)^\s*enable_control_plane_load_balancer\s*=\s*true\s*$", text) is None,
        f"{example_name} must not enable a module-managed public control-plane load balancer.",
    )
    require(
        re.search(r"(?m)^\s*nat_router\s*=", text) is None,
        f"{example_name} must not use the module NAT router for external-network scale.",
    )
    return {
        "tailscale_transport": True,
        "public_kubernetes_api_closed": True,
        "public_ssh_closed": True,
        "managed_public_ingress_disabled": True,
    }


def validate_200_example(path: Path) -> ExampleCheck:
    text = active_hcl(path.read_text(encoding="utf-8"))
    exposure = validate_secure_tailscale_exposure(text, path.name)

    control_planes = extract_named_block_count(text, "control-plane")
    primary_agents = extract_named_block_count(text, "agents-primary")
    secondary_agents = extract_named_block_count(text, "agents-secondary")

    require(
        re.search(r'name\s*=\s*"agents-secondary".*?network_id\s*=\s*var\.secondary_network_id', text, re.S)
        is not None,
        "agents-secondary must be pinned to var.secondary_network_id.",
    )
    require(
        re.search(r'name\s*=\s*"agents-primary".*?network_scope\s*=\s*"primary"', text, re.S)
        is not None,
        'agents-primary must set network_scope = "primary".',
    )
    require(
        re.search(r'name\s*=\s*"agents-secondary".*?network_scope\s*=\s*"external"', text, re.S)
        is not None,
        'agents-secondary must set network_scope = "external".',
    )
    require(
        re.search(r"(?m)^\s*placement_group\s*=", text) is None,
        "200-node static example must leave placement_group unset so auto-sharding is active.",
    )

    network_attachments = {
        "primary": control_planes + primary_agents,
        "secondary": secondary_agents,
    }
    require(
        all(value <= NETWORK_ATTACHMENT_LIMIT for value in network_attachments.values()),
        f"200-node example exceeds {NETWORK_ATTACHMENT_LIMIT} attachments on at least one Network: {network_attachments}",
    )

    placement_groups = placement_groups_for_static_counts(control_planes, primary_agents, secondary_agents)
    require(
        placement_groups == 21,
        f"200-node example should use 21 auto-sharded placement groups, got {placement_groups}.",
    )
    require(
        placement_groups <= PLACEMENT_GROUP_PROJECT_LIMIT,
        f"200-node example exceeds the {PLACEMENT_GROUP_PROJECT_LIMIT}-placement-group project limit.",
    )

    return ExampleCheck(
        name=path.name,
        total_nodes=control_planes + primary_agents + secondary_agents,
        network_attachments=network_attachments,
        placement_groups=placement_groups,
        exposure=exposure,
        notes=("static +100-node example", "placement groups auto-shard every 10 static servers"),
    )


def validate_10000_example(path: Path) -> ExampleCheck:
    text = active_hcl(path.read_text(encoding="utf-8"))
    exposure = validate_secure_tailscale_exposure(text, path.name)

    require_assignment(text, "network_subnet_mode", '"shared"')
    control_planes = extract_named_block_count(text, "control-plane")
    system_agents = extract_named_block_count(text, "system-primary")
    primary_autoscaler_max = extract_assignment_int(
        text,
        r'name\s*=\s*"primary".*?max_nodes\s*=\s*(?P<value>\d+)',
        'Missing primary autoscaler shard max_nodes.',
    )
    external_network_count = extract_assignment_int(
        text,
        r"length\(var\.external_network_ids\)\s*==\s*(?P<value>\d+)",
        "Missing external_network_ids exact-length validation.",
    )
    external_autoscaler_max = extract_assignment_int(
        text,
        r"for\s+index,\s*network_id\s+in\s+var\.external_network_ids\s*:.*?max_nodes\s*=\s*(?P<value>\d+)",
        "Missing external autoscaler shard max_nodes.",
    )

    require(
        re.search(r"(?m)^\s*network_id\s*=\s*shard\.network_id\s*$", text) is not None,
        "Autoscaler nodepool must pass shard.network_id to the module.",
    )
    require(
        re.search(r"(?m)^\s*network_scope\s*=\s*shard\.network_scope\s*$", text) is not None,
        "Autoscaler nodepool must pass shard.network_scope to the module.",
    )
    require(
        re.search(r'name\s*=\s*"primary".*?network_scope\s*=\s*"primary"', text, re.S) is not None,
        'Primary autoscaler shard must set network_scope = "primary".',
    )
    require(
        re.search(r'format\("external-%03d", index \+ 1\).*?network_scope\s*=\s*"external"', text, re.S)
        is not None,
        'External autoscaler shards must set network_scope = "external".',
    )
    require(
        re.search(r"(?m)^\s*min_nodes\s*=\s*0\s*$", text) is not None,
        "10k reference should start autoscaler shards at min_nodes = 0.",
    )

    primary_attachments = control_planes + system_agents + primary_autoscaler_max
    external_attachments = external_autoscaler_max
    network_attachments = {
        "primary": primary_attachments,
        "each_external": external_attachments,
    }
    require(
        primary_attachments == NETWORK_ATTACHMENT_LIMIT,
        f"10k primary Network should be exactly {NETWORK_ATTACHMENT_LIMIT} attachments, got {primary_attachments}.",
    )
    require(
        external_attachments == NETWORK_ATTACHMENT_LIMIT,
        f"10k external Network shards should be exactly {NETWORK_ATTACHMENT_LIMIT} attachments, got {external_attachments}.",
    )

    total_nodes = primary_attachments + external_network_count * external_autoscaler_max
    require(total_nodes == 10_000, f"10k reference should total 10,000 nodes, got {total_nodes}.")

    placement_groups = placement_groups_for_static_counts(control_planes, system_agents)
    require(
        placement_groups <= PLACEMENT_GROUP_PROJECT_LIMIT,
        f"10k static placement groups exceed the {PLACEMENT_GROUP_PROJECT_LIMIT}-group project limit.",
    )
    require(
        math.ceil(total_nodes / PLACEMENT_GROUP_SERVER_LIMIT) > PLACEMENT_GROUP_PROJECT_LIMIT,
        "10k reference should remain autoscaler-first; a fully static single-project placement layout would be misleading.",
    )

    return ExampleCheck(
        name=path.name,
        total_nodes=total_nodes,
        network_attachments=network_attachments,
        placement_groups=placement_groups,
        exposure=exposure,
        notes=(
            f"{external_network_count} external Network shards",
            "autoscaler-first reference, not a live-tested 10k claim",
            "autoscaler-created nodes are not assigned Hetzner placement groups by kube-hetzner today",
        ),
    )


def run(repo_root: Path) -> list[ExampleCheck]:
    examples_dir = repo_root / "examples" / "tailscale-node-transport"
    checks = [
        validate_200_example(examples_dir / "large-scale-200.tf.example"),
        validate_10000_example(examples_dir / "massive-10000-nodes.tf.example"),
    ]
    return checks


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Path to the kube-hetzner repository root.",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    args = parser.parse_args(argv)

    try:
        checks = run(args.repo_root)
    except CheckError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps([asdict(check) for check in checks], indent=2, sort_keys=True))
    else:
        for check in checks:
            attachments = ", ".join(f"{name}={value}" for name, value in check.network_attachments.items())
            notes = "; ".join(check.notes)
            print(
                f"PASS {check.name}: total_nodes={check.total_nodes}, "
                f"network_attachments=({attachments}), placement_groups={check.placement_groups}; {notes}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
