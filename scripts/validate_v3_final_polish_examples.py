#!/usr/bin/env python3
"""Validate the v3 topology/Gateway/registry documentation surfaces."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(errors: list[str], condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def contains(relative: str, needle: str) -> bool:
    return needle in read(relative)


def main() -> int:
    errors: list[str] = []

    variables = read("variables.tf")
    locals_tf = read("locals.tf")
    init_tf = read("init.tf")
    control_planes = read("control_planes.tf")
    agents = read("agents.tf")
    autoscaler = read("autoscaler-agents.tf")
    outputs = read("output.tf")
    README = read("README.md")
    kube_example = read("kube.tf.example")
    llms = read("docs/llms.md")
    topology = read("docs/v3-topology-recommendations.md")
    changelog = read("CHANGELOG.md")
    smoke_matrix = read("scripts/smoke_v3_plan_matrix.py")

    require(errors, 'variable "cilium_gateway_api_enabled"' in variables, "variables.tf must define cilium_gateway_api_enabled")
    require(errors, 'cni_plugin == "cilium" && !var.enable_kube_proxy' in variables, "Cilium Gateway API must validate Cilium plus kube-proxy replacement")
    require(errors, "1.19.3" in variables, "variables.tf should default Cilium to the current v3 Gateway-capable line")
    require(errors, 'variable "embedded_registry_mirror"' in variables, "variables.tf must define embedded_registry_mirror")
    require(errors, "embedded_registry_mirror.registries must not contain duplicates" in variables, "embedded registry mirror must reject duplicate registries")
    require(errors, "advertise_node_private_routes = true" in variables, "embedded registry mirror must enforce Tailscale route advertisement for multinetwork")

    require(errors, "gatewayAPI:" in locals_tf and "enabled: true" in locals_tf, "locals.tf must enable Cilium gatewayAPI when requested")
    require(errors, "gateway_api_crds_version" in locals_tf and "v1.4.1" in locals_tf and "v1.2.0" in locals_tf, "locals.tf must map Gateway API CRD version by Cilium line")
    require(errors, "registries_config_effective" in locals_tf, "locals.tf must build an effective registries.yaml")
    require(errors, '"embedded-registry" = true' in locals_tf, "locals.tf must set embedded-registry on server config")
    require(errors, '"disable-default-registry-endpoint" = true' in locals_tf, "locals.tf must support disabling default registry endpoints")
    require(errors, "public_endpoint_ipv6_candidate" in locals_tf, "locals.tf must decouple public join endpoint address family from Cilium multinetwork transport")
    require(errors, "public Kubernetes join endpoint without control_plane_endpoint" in variables, "variables.tf must reject public join endpoints without a public API host")

    require(errors, "gateway_api_standard_crds_manifest" in init_tf, "init.tf must include Gateway API CRDs in addon hash/rendering")
    require(errors, "00-gateway-api-standard-crds.yaml" in init_tf, "init.tf must preload Gateway API CRDs for RKE2 first bootstrap")
    require(errors, "00-gateway-api-standard-crds.yaml" in control_planes, "control_planes.tf must preload Gateway API CRDs for later RKE2 control planes")
    require(errors, "registries_config_effective" in control_planes, "control_planes.tf must use effective registries config")
    require(errors, "registries_config_effective" in agents, "agents.tf must use effective registries config")
    require(errors, "registries_config_effective" in autoscaler, "autoscaler-agents.tf must use effective registries config")

    for output_name in [
        "effective_kubeconfig_endpoint",
        "effective_node_join_endpoint",
        "node_transport_mode",
        "tailscale_control_plane_magicdns_hosts",
        "tailscale_agent_magicdns_hosts",
    ]:
        require(errors, f'output "{output_name}"' in outputs, f"output.tf missing {output_name}")
    require(errors, "local.first_control_plane_ip" not in outputs, "output.tf public IPv4 outputs must not fall back to Terraform SSH connection targets")

    for rel in [
        "docs/v3-topology-recommendations.md",
        "examples/cilium-gateway-api/README.md",
        "examples/cilium-gateway-api/main.tf",
        "examples/cilium-gateway-api/extra-manifests/kustomization.yaml.tpl",
        "examples/cilium-gateway-api/extra-manifests/issuer.yaml.tpl",
        "examples/cilium-gateway-api/extra-manifests/echo.yaml.tpl",
        "examples/cilium-gateway-api/extra-manifests/gateway.yaml.tpl",
        "examples/cilium-gateway-api/extra-manifests/http-route.yaml.tpl",
    ]:
        require(errors, (ROOT / rel).exists(), f"missing {rel}")

    example_main = read("examples/cilium-gateway-api/main.tf")
    for pattern, description in [
        (r'cni_plugin\s*=\s*"cilium"', 'cni_plugin = "cilium"'),
        (r"enable_kube_proxy\s*=\s*false", "enable_kube_proxy = false"),
        (r"cilium_gateway_api_enabled\s*=\s*true", "cilium_gateway_api_enabled = true"),
        (r'ingress_controller\s*=\s*"none"', 'ingress_controller = "none"'),
        (r"enable_cert_manager\s*=\s*true", "enable_cert_manager = true"),
        (r"user_kustomizations", "user_kustomizations"),
    ]:
        require(errors, re.search(pattern, example_main) is not None, f"examples/cilium-gateway-api/main.tf missing {description}")

    gateway_yaml = read("examples/cilium-gateway-api/extra-manifests/gateway.yaml.tpl")
    route_yaml = read("examples/cilium-gateway-api/extra-manifests/http-route.yaml.tpl")
    issuer_yaml = read("examples/cilium-gateway-api/extra-manifests/issuer.yaml.tpl")
    require(errors, "gatewayClassName: cilium" in gateway_yaml, "Gateway example must use Cilium GatewayClass")
    require(errors, "kind: HTTPRoute" in route_yaml, "Gateway example must include an HTTPRoute")
    require(errors, "gatewayHTTPRoute" in issuer_yaml, "Gateway example must include cert-manager Gateway HTTP-01 solver")

    for doc_name, body in {
        "README.md": README,
        "kube.tf.example": kube_example,
        "docs/llms.md": llms,
        "docs/v3-topology-recommendations.md": topology,
        "CHANGELOG.md": changelog,
    }.items():
        for needle in ["cilium_gateway_api_enabled", "embedded_registry_mirror"]:
            require(errors, needle in body, f"{doc_name} must mention {needle}")

    require(errors, "examples/cilium-gateway-api" in README, "README must link the Cilium Gateway API example")
    require(errors, "docs/v3-topology-recommendations.md" in README, "README must link v3 topology recommendations")
    require(errors, "no public-network/IP-query-server" in topology or "public-network/IP-query-server" in topology, "topology docs must reject public-network/IP-query-server scale story")
    require(errors, "Talos" in topology, "topology docs must explain the no-Talos-pivot boundary")

    for rel in [
        ".claude/skills/kh-assistant/SKILL.md",
        ".claude/skills/sync-docs/SKILL.md",
        ".claude/skills/test-changes/SKILL.md",
        ".claude/skills/migrate-v2-to-v3/SKILL.md",
        ".claude/skills/prepare-release/SKILL.md",
    ]:
        body = read(rel)
        for needle in ["cilium_gateway_api_enabled", "embedded_registry_mirror"]:
            require(errors, needle in body, f"{rel} must mention {needle}")

    for rel in [
        ".claude/skills/test-changes/SKILL.md",
        ".claude/skills/prepare-release/SKILL.md",
        "tests/README.md",
    ]:
        require(errors, "smoke_v3_plan_matrix.py" in read(rel), f"{rel} must mention smoke_v3_plan_matrix.py")
    for needle in ["run_init_with_retry", "public-join-ipv6-only-valid", "public-join-private-control-plane-invalid"]:
        require(errors, needle in smoke_matrix, f"scripts/smoke_v3_plan_matrix.py must include {needle}")

    live_null_resource = []
    for path in ROOT.rglob("*.tf"):
        if ".terraform" in path.parts or ".terraform-tofu" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        if re.search(r'resource\s+"null_resource"|provider\s+"null"|hashicorp/null', text):
            live_null_resource.append(path.relative_to(ROOT).as_posix())
    require(errors, not live_null_resource, f"live null_resource/hashicorp/null usage found: {', '.join(live_null_resource)}")

    if errors:
        print("v3 final polish validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("v3 final polish validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
