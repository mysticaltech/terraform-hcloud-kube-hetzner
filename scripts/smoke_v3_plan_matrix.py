#!/usr/bin/env python3
"""Run v3 blast-radius Terraform plan smoke scenarios.

This script intentionally uses disposable Terraform roots and never applies.
It needs a real Hetzner token because successful plans read provider data
sources such as images, locations, and server types.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HCLOUD_TOKEN_ENV = "TF_VAR_hcloud_token"
DEFAULT_TAILSCALE_KEY = "tskey-auth-smoke000000000000000000000000000000000000000000000000000000000000"
TRANSIENT_PLAN_ERRORS = (
    "TLS handshake timeout",
    "timeout error:",
    "connection reset by peer",
    "temporary failure",
)


@dataclass(frozen=True)
class Scenario:
    name: str
    extra_module_hcl: str
    expect_success: bool
    expect_output: tuple[str, ...] = ()
    control_plane_nodepools_hcl: str | None = None
    agent_nodepools_hcl: str | None = None
    skip_reason: str | None = None
    ingress_controller: str = "none"


BASE_CONTROL_PLANE_NODEPOOLS_HCL = """
control_plane_nodepools = [
  {
    name        = "control-plane"
    server_type = "cx23"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 1
  }
]
"""


BASE_AGENT_NODEPOOLS_HCL = """
agent_nodepools = [
  {
    name        = "agent"
    server_type = "cx23"
    location    = "nbg1"
    labels      = []
    taints      = []
    count       = 1
  }
]
"""


def load_dotenv_token() -> str | None:
    """Best-effort local convenience for Karim's kube-test root."""
    env_path = ROOT.parent / "kube-test" / ".env"
    if not env_path.exists():
        return None
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == DEFAULT_HCLOUD_TOKEN_ENV:
            return value.strip().strip('"').strip("'")
    return None


def base_hcl(module_source: Path, scenario: Scenario) -> str:
    control_plane_nodepools_hcl = scenario.control_plane_nodepools_hcl or BASE_CONTROL_PLANE_NODEPOOLS_HCL
    agent_nodepools_hcl = scenario.agent_nodepools_hcl or BASE_AGENT_NODEPOOLS_HCL
    return textwrap.dedent(
        f"""
        terraform {{
          required_version = ">= 1.10.1"

          required_providers {{
            hcloud = {{
              source  = "hetznercloud/hcloud"
              version = ">= 1.62.0"
            }}
          }}
        }}

        provider "hcloud" {{
          token = var.hcloud_token
        }}

        module "kube_hetzner" {{
          source = "{module_source.as_posix()}"

          providers = {{
            hcloud = hcloud
          }}

          hcloud_token    = var.hcloud_token
          ssh_public_key  = file("/Users/karim/.ssh/id_ed25519.pub")
          ssh_private_key = file("/Users/karim/.ssh/id_ed25519")

          cluster_name       = var.cluster_name
          network_region     = "eu-central"
          ingress_controller = "{scenario.ingress_controller}"

          # Pin addon versions so smoke plans do not spend GitHub unauthenticated
          # release API quota while still exercising the same module graph.
          hetzner_ccm_version = "v1.33.3"
          hetzner_csi_version = "v2.17.0"
          kured_version       = "1.21.0"

        {textwrap.indent(control_plane_nodepools_hcl.strip(), "  ")}

        {textwrap.indent(agent_nodepools_hcl.strip(), "  ")}

        {textwrap.indent(scenario.extra_module_hcl.strip(), "  ")}
        }}

        variable "hcloud_token" {{
          type      = string
          sensitive = true
        }}

        variable "tailscale_auth_key" {{
          type      = string
          sensitive = true
          default   = "{DEFAULT_TAILSCALE_KEY}"
        }}

        variable "cluster_name" {{
          type    = string
          default = "kh-v3-smoke"
        }}
        """
    ).strip() + "\n"


def discover_external_network_id(env: dict[str, str]) -> str | None:
    explicit = env.get("SMOKE_HCLOUD_EXTERNAL_NETWORK_ID")
    if explicit:
        return explicit

    cli_env = env.copy()
    cli_env["HCLOUD_TOKEN"] = env[DEFAULT_HCLOUD_TOKEN_ENV]
    result = run(["hcloud", "network", "list", "-o", "columns=id", "-o", "noheader"], cwd=ROOT, env=cli_env)
    if result.returncode != 0:
        return None

    for line in result.stdout.splitlines():
        parts = line.strip().split()
        if parts:
            return parts[0]
    return None


def scenarios(external_network_id: str | None) -> list[Scenario]:
    external_network_hcl = external_network_id or "0"
    external_network_skip = None if external_network_id else "No existing HCloud Network ID available for external-network plan smoke."

    return [
        Scenario(
            name="default-k3s-cilium",
            extra_module_hcl="",
            expect_success=True,
        ),
        Scenario(
            name="cilium-gateway-api-valid",
            extra_module_hcl="""
            cni_plugin                 = "cilium"
            enable_kube_proxy          = false
            cilium_gateway_api_enabled = true
            enable_cert_manager        = true
            """,
            expect_success=True,
            expect_output=("data.http.gateway_api_standard_crds",),
        ),
        Scenario(
            name="cilium-gateway-api-invalid-flannel",
            extra_module_hcl="""
            cni_plugin                 = "flannel"
            enable_kube_proxy          = true
            cilium_gateway_api_enabled = true
            """,
            expect_success=False,
            expect_output=("cilium_gateway_api_enabled requires",),
        ),
        Scenario(
            name="cilium-gateway-api-invalid-kube-proxy",
            extra_module_hcl="""
            cni_plugin                 = "cilium"
            enable_kube_proxy          = true
            cilium_gateway_api_enabled = true
            """,
            expect_success=False,
            expect_output=("cilium_gateway_api_enabled", "enable_kube_proxy"),
        ),
        Scenario(
            name="gateway-api-invalid-dual-controllers",
            extra_module_hcl="""
            cni_plugin                                  = "cilium"
            enable_kube_proxy                           = false
            cilium_gateway_api_enabled                  = true
            traefik_provider_kubernetes_gateway_enabled = true
            """,
            expect_success=False,
            expect_output=(
                "Choose either traefik_provider_kubernetes_gateway_enabled or",
                "cilium_gateway_api_enabled, not both",
            ),
            ingress_controller="traefik",
        ),
        Scenario(
            name="public-join-ipv6-only-valid",
            extra_module_hcl="",
            expect_success=True,
            control_plane_nodepools_hcl="""
            control_plane_nodepools = [
              {
                name               = "control-plane"
                server_type        = "cx23"
                location           = "nbg1"
                labels             = []
                taints             = []
                count              = 1
                enable_public_ipv4 = false
                enable_public_ipv6 = true
              }
            ]
            """,
            agent_nodepools_hcl="""
            agent_nodepools = [
              {
                name               = "agent"
                server_type        = "cx23"
                location           = "nbg1"
                labels             = []
                taints             = []
                count              = 1
                join_endpoint_type = "public"
              }
            ]
            """,
        ),
        Scenario(
            name="public-join-private-control-plane-invalid",
            extra_module_hcl="""
            enable_control_plane_load_balancer              = true
            control_plane_load_balancer_enable_public_network = false
            nat_router = {
              server_type = "cx23"
              location    = "nbg1"
            }
            """,
            expect_success=False,
            expect_output=("A public Kubernetes join endpoint without control_plane_endpoint",),
            control_plane_nodepools_hcl="""
            control_plane_nodepools = [
              {
                name               = "control-plane"
                server_type        = "cx23"
                location           = "nbg1"
                labels             = []
                taints             = []
                count              = 1
                enable_public_ipv4 = false
                enable_public_ipv6 = false
              }
            ]
            """,
            agent_nodepools_hcl="""
            agent_nodepools = [
              {
                name               = "agent"
                server_type        = "cx23"
                location           = "nbg1"
                labels             = []
                taints             = []
                count              = 1
                join_endpoint_type = "public"
              }
            ]
            """,
        ),
        Scenario(
            name="embedded-registry-k3s-valid",
            extra_module_hcl="""
            embedded_registry_mirror = {
              enabled    = true
              registries = ["docker.io", "ghcr.io"]
            }

            registries_config = yamlencode({
              mirrors = {
                "ghcr.io" = {
                  endpoint = ["https://ghcr.io"]
                }
              }
            })
            """,
            expect_success=True,
            expect_output=("terraform_data.registries", "ghcr.io"),
        ),
        Scenario(
            name="embedded-registry-rke2-valid",
            extra_module_hcl="""
            kubernetes_distribution = "rke2"
            cni_plugin              = "cilium"

            embedded_registry_mirror = {
              enabled                  = true
              registries               = ["docker.io", "registry.k8s.io", "quay.io"]
              disable_default_endpoint = true
            }
            """,
            expect_success=True,
            expect_output=("terraform_data.registries", "docker.io"),
        ),
        Scenario(
            name="embedded-registry-invalid-duplicates",
            extra_module_hcl="""
            embedded_registry_mirror = {
              enabled    = true
              registries = ["docker.io", "Docker.IO"]
            }
            """,
            expect_success=False,
            expect_output=("embedded_registry_mirror.registries must not contain duplicates",),
        ),
        Scenario(
            name="embedded-registry-invalid-empty",
            extra_module_hcl="""
            embedded_registry_mirror = {
              enabled    = true
              registries = []
            }
            """,
            expect_success=False,
            expect_output=("embedded_registry_mirror.registries must contain at least one registry",),
        ),
        Scenario(
            name="tailscale-registry-multinetwork-valid",
            extra_module_hcl="""
            cni_plugin                = "flannel"
            node_transport_mode       = "tailscale"
            firewall_kube_api_source  = null
            firewall_ssh_source       = null
            tailscale_auth_key        = var.tailscale_auth_key

            tailscale_node_transport = {
              bootstrap_mode  = "cloud_init"
              magicdns_domain = "example-tailnet.ts.net"
              routing = {
                advertise_node_private_routes = true
              }
            }

            embedded_registry_mirror = {
              enabled    = true
              registries = ["docker.io"]
            }
            """,
            expect_success=True,
            expect_output=("terraform_data.registries", "additional_nodepool_networks"),
            agent_nodepools_hcl="""
            agent_nodepools = [
              {
                name        = "agent"
                server_type = "cx23"
                location    = "nbg1"
                labels      = []
                taints      = []
                count       = 1
                network_id  = %s
              }
            ]
            """ % external_network_hcl,
            skip_reason=external_network_skip,
        ),
        Scenario(
            name="rke2-tailscale-registry-multinetwork-valid",
            extra_module_hcl="""
            kubernetes_distribution = "rke2"
            cni_plugin              = "cilium"
            node_transport_mode     = "tailscale"
            firewall_kube_api_source = null
            firewall_ssh_source      = null
            tailscale_auth_key       = var.tailscale_auth_key

            tailscale_node_transport = {
              bootstrap_mode             = "cloud_init"
              magicdns_domain            = "example-tailnet.ts.net"
              enable_experimental_rke2   = true
              enable_experimental_cilium = true
              routing = {
                advertise_node_private_routes = true
              }
            }

            embedded_registry_mirror = {
              enabled    = true
              registries = ["docker.io"]
            }
            """,
            expect_success=True,
            expect_output=("terraform_data.registries", "additional_nodepool_networks"),
            skip_reason=external_network_skip,
            agent_nodepools_hcl="""
            agent_nodepools = [
              {
                name        = "agent"
                server_type = "cx23"
                location    = "nbg1"
                labels      = []
                taints      = []
                count       = 1
                network_id  = %s
              }
            ]
            """ % external_network_hcl,
        ),
        Scenario(
            name="tailscale-registry-multinetwork-invalid-no-routes",
            extra_module_hcl="""
            cni_plugin                = "flannel"
            node_transport_mode       = "tailscale"
            firewall_kube_api_source  = null
            firewall_ssh_source       = null
            tailscale_auth_key        = var.tailscale_auth_key

            tailscale_node_transport = {
              bootstrap_mode  = "cloud_init"
              magicdns_domain = "example-tailnet.ts.net"
              routing = {
                advertise_node_private_routes = false
              }
            }

            embedded_registry_mirror = {
              enabled    = true
              registries = ["docker.io"]
            }
            """,
            expect_success=False,
            expect_output=("advertise_node_private_routes",),
            agent_nodepools_hcl="""
            agent_nodepools = [
              {
                name        = "agent"
                server_type = "cx23"
                location    = "nbg1"
                labels      = []
                taints      = []
                count       = 1
                network_id  = %s
              }
            ]
            """ % external_network_hcl,
            skip_reason=external_network_skip,
        ),
    ]


def run(command: list[str], cwd: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def should_retry_transient(output: str) -> bool:
    return any(marker in output for marker in TRANSIENT_PLAN_ERRORS)


def scenario_matches_filter(name: str, filters: list[str]) -> bool:
    return not filters or any(part in name for part in filters)


def run_init_with_retry(root: Path, env: dict[str, str], attempts: int = 3) -> subprocess.CompletedProcess[str]:
    init: subprocess.CompletedProcess[str] | None = None
    for _ in range(attempts):
        init = run(["terraform", "init", "-backend=false", "-no-color"], cwd=root, env=env)
        if init.returncode == 0 or not should_retry_transient(init.stdout):
            return init
    assert init is not None
    return init


def run_plan_with_retry(root: Path, env: dict[str, str], attempts: int = 2) -> subprocess.CompletedProcess[str]:
    plan: subprocess.CompletedProcess[str] | None = None
    for _ in range(attempts):
        plan = run(
            ["terraform", "plan", "-refresh=false", "-lock=false", "-input=false", "-no-color", "-detailed-exitcode"],
            cwd=root,
            env=env,
        )
        if plan.returncode in (0, 2) or not should_retry_transient(plan.stdout):
            return plan
    assert plan is not None
    return plan


def excerpt(output: str, limit: int = 6000) -> str:
    if len(output) <= limit:
        return output
    head = output[: limit // 2]
    tail = output[-limit // 2 :]
    return f"{head}\n... output truncated by smoke helper ...\n{tail}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-source", type=Path, default=ROOT)
    parser.add_argument("--filter", action="append", default=[], help="Run only scenarios whose name contains this text.")
    parser.add_argument("--keep-tmp", action="store_true")
    args = parser.parse_args()

    token = os.environ.get(DEFAULT_HCLOUD_TOKEN_ENV) or load_dotenv_token()
    if not token:
        print(f"{DEFAULT_HCLOUD_TOKEN_ENV} is required. Source ../kube-test/.env or export it explicitly.", file=sys.stderr)
        return 2

    env = os.environ.copy()
    env[DEFAULT_HCLOUD_TOKEN_ENV] = token

    external_network_id = discover_external_network_id(env)
    selected = [scenario for scenario in scenarios(external_network_id) if scenario_matches_filter(scenario.name, args.filter)]
    if not selected:
        print("No smoke scenarios matched the requested filter.", file=sys.stderr)
        return 2

    failures: list[str] = []
    temp_roots: list[Path] = []
    for scenario in selected:
        root = Path(tempfile.mkdtemp(prefix=f"kh-{scenario.name}-"))
        temp_roots.append(root)
        if scenario.skip_reason:
            print(f"SKIP {scenario.name}: {scenario.skip_reason}", flush=True)
            continue
        (root / "main.tf").write_text(base_hcl(args.module_source.resolve(), scenario), encoding="utf-8")

        init = run_init_with_retry(root, env)
        if init.returncode != 0:
            failures.append(f"{scenario.name}: terraform init failed\n{excerpt(init.stdout)}")
            print(f"FAIL {scenario.name}: init failed", flush=True)
            continue

        plan = run_plan_with_retry(root, env)
        output = plan.stdout
        success = plan.returncode in (0, 2)

        if success != scenario.expect_success:
            failures.append(
                f"{scenario.name}: expected success={scenario.expect_success}, got returncode={plan.returncode}\n{excerpt(output)}"
            )
            print(f"FAIL {scenario.name}: unexpected {'success' if success else 'failure'}", flush=True)
            continue

        missing = [needle for needle in scenario.expect_output if needle not in output]
        if missing:
            failures.append(f"{scenario.name}: missing expected output {missing}\n{excerpt(output)}")
            print(f"FAIL {scenario.name}: missing expected output", flush=True)
            continue

        print(f"PASS {scenario.name}", flush=True)

    if not args.keep_tmp:
        for root in temp_roots:
            shutil.rmtree(root, ignore_errors=True)
    else:
        for root in temp_roots:
            print(f"kept {root}")

    if failures:
        print("\nv3 smoke plan matrix failed:")
        for failure in failures:
            print(f"\n--- {failure}")
        return 1

    print("v3 smoke plan matrix passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
