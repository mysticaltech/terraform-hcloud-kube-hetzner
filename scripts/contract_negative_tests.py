#!/usr/bin/env python3
"""Negative plan tests for validation-contract preconditions."""

from __future__ import annotations

import os
import re
import atexit
import shutil
import socket
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = REPO_ROOT / "tests/render-fixtures"
BASELINE = FIXTURE_DIR / "baseline.tfvars.fixture"
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
MIN_EXECUTED_CASES = 3
# A real HCloud token (read access suffices) is required to evaluate contracts
# that depend on data sources (e.g. the server-type RAM map). Without one the
# suite skips politely; WITH one, executed-case minimums are enforced.
HCLOUD_TOKEN = os.environ.get("HCLOUD_TOKEN", "").strip()
TOKEN_MODE = len(HCLOUD_TOKEN) == 64
PLUGIN_CACHE_DIR = Path.home() / ".terraform.d/plugin-cache"
CLI_CONFIG_FILE = FIXTURE_DIR / ".terraform/contract-negative-tests.tfrc"
# Short path: macOS AF_UNIX sun_path is limited to 104 bytes and the default
# macOS tempdir (/var/folders/...) exceeds it, which broke provider RPC sockets.
TERRAFORM_TMP_DIR = Path("/tmp") / f"kh-cnt-{os.getpid()}"
atexit.register(lambda: shutil.rmtree(TERRAFORM_TMP_DIR, ignore_errors=True))


@dataclass(frozen=True)
class Case:
    name: str
    var_file: Path
    target: str
    expected_substring: str


CASES = [
    Case(
        name="bad-ingress-annotations",
        var_file=FIXTURE_DIR / "bad-ingress-annotations.tfvars.fixture",
        target="module.sut.terraform_data.helm_values_yaml_contract",
        expected_substring="annotation",
    ),
    Case(
        name="bad-yaml-values",
        var_file=FIXTURE_DIR / "bad-yaml-values.tfvars.fixture",
        target="module.sut.terraform_data.helm_values_yaml_contract",
        expected_substring="not valid YAML",
    ),
    Case(
        name="bad-node-annotation-key",
        var_file=FIXTURE_DIR / "bad-node-annotation-key.tfvars.fixture",
        target="module.sut.terraform_data.validation_contract",
        expected_substring="agent_nodepools annotations keys must be valid Kubernetes qualified names",
    ),
    Case(
        name="bad-agent-node-annotation-key",
        var_file=FIXTURE_DIR / "bad-agent-node-annotation-key.tfvars.fixture",
        target="module.sut.terraform_data.validation_contract",
        expected_substring="agent_nodepools annotations keys must be valid Kubernetes qualified names",
    ),
    Case(
        name="bad-node-annotation-value",
        var_file=FIXTURE_DIR / "bad-node-annotation-value.tfvars.fixture",
        target="module.sut.terraform_data.validation_contract",
        expected_substring="agent_nodepools annotations values must be single-line strings",
    ),
    Case(
        name="rke2-overreserved",
        var_file=FIXTURE_DIR / "rke2-overreserved.tfvars.fixture",
        target="module.sut.terraform_data.validation_contract",
        expected_substring="reserved memory must not exceed 50%",
    ),
    Case(
        name="nat-without-cp-lb",
        var_file=FIXTURE_DIR / "nat-without-cp-lb.tfvars.fixture",
        target="module.sut.terraform_data.validation_contract",
        expected_substring="When nat_router is enabled",
    ),
]


def strip_ansi(value: str) -> str:
    return ANSI_RE.sub("", value)


def run(command: list[str], extra_env: dict | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    ensure_cli_config()
    env["TF_IN_AUTOMATION"] = "1"
    env["TF_CLI_ARGS"] = "-no-color"
    env["TF_CLI_CONFIG_FILE"] = str(CLI_CONFIG_FILE)
    env["TMPDIR"] = str(TERRAFORM_TMP_DIR)
    env["TMP"] = str(TERRAFORM_TMP_DIR)
    env["TEMP"] = str(TERRAFORM_TMP_DIR)
    env.pop("TF_PLUGIN_CACHE_DIR", None)
    return subprocess.run(
        command,
        cwd=FIXTURE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )


def ensure_cli_config() -> None:
    CLI_CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    TERRAFORM_TMP_DIR.mkdir(parents=True, exist_ok=True)
    provider_mirror = PLUGIN_CACHE_DIR / "registry.terraform.io"
    if not provider_mirror.exists():
        CLI_CONFIG_FILE.write_text("disable_checkpoint = true\n", encoding="utf-8")
        return

    CLI_CONFIG_FILE.write_text(
        "\n".join(
            [
                "disable_checkpoint = true",
                "provider_installation {",
                "  filesystem_mirror {",
                f"    path    = {json_string(PLUGIN_CACHE_DIR)}",
                '    include = ["registry.terraform.io/*/*"]',
                "  }",
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def json_string(path: Path) -> str:
    return '"' + str(path).replace("\\", "\\\\").replace('"', '\\"') + '"'


def combined_output(result: subprocess.CompletedProcess[str]) -> str:
    return strip_ansi(result.stdout + "\n" + result.stderr)


def provider_reachability_blocked(output: str) -> bool:
    lowered = output.lower()
    provider_terms = (
        "hcloud",
        "hetzner",
        "data.hcloud_",
        "server_types",
        "servers",
    )
    blocker_terms = (
        "token",
        "credential",
        "authenticate",
        "authorization",
        "unauthorized",
        "forbidden",
        "could not resolve host",
        "connection refused",
        "timeout",
        "no route to host",
        "failed to query",
        "error making request",
    )
    return any(term in lowered for term in provider_terms) and any(
        term in lowered for term in blocker_terms
    )


def provider_rpc_sockets_available() -> bool:
    test_dir = TERRAFORM_TMP_DIR
    test_dir.mkdir(parents=True, exist_ok=True)
    test_path = test_dir / f"kh-tf-provider-rpc-{os.getpid()}.sock"
    try:
        try:
            test_path.unlink()
        except FileNotFoundError:
            pass
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.bind(str(test_path))
        finally:
            sock.close()
        return True
    except OSError:
        return False
    finally:
        try:
            test_path.unlink()
        except FileNotFoundError:
            pass


def init_fixture() -> bool:
    result = run(["terraform", "init", "-backend=false", "-input=false"])
    if result.returncode == 0:
        print("PASS init: terraform init -backend=false completed")
        return True
    output = combined_output(result).strip()
    print("FAIL init: terraform init -backend=false failed")
    print(output)
    return False


def run_case(case: Case) -> str:
    plan_env = dict(os.environ)
    plan_env["TF_VAR_hcloud_token"] = HCLOUD_TOKEN if TOKEN_MODE else "0" * 64
    result = run(
        [
            "terraform",
            "plan",
            "-input=false",
            "-lock=false",
            "-refresh=false",
            "-no-color",
            f"-var-file={BASELINE.name}",
            f"-var-file={case.var_file.name}",
            f"-target={case.target}",
        ],
        extra_env={"TF_VAR_hcloud_token": plan_env["TF_VAR_hcloud_token"]},
    )
    output = combined_output(result)

    if result.returncode == 0:
        print(f"FAIL {case.name}: plan succeeded but this case must fail")
        return "failed"

    if case.expected_substring in output:
        print(f"PASS {case.name}: failed as expected ({case.expected_substring})")
        return "executed"

    if provider_reachability_blocked(output):
        first_line = next((line.strip() for line in output.splitlines() if line.strip()), "provider access blocked")
        if TOKEN_MODE:
            print(f"FAIL {case.name}: contract error absent and API path failed despite token ({first_line})")
            return "failed"
        print(f"SKIP {case.name}: needs a real HCLOUD_TOKEN to evaluate data-dependent contracts ({first_line})")
        return "skipped"

    print(f"FAIL {case.name}: expected substring {case.expected_substring!r} not found")
    print(output.strip())
    return "failed"


def main() -> int:
    if shutil.which("terraform") is None:
        print("FAIL terraform: terraform binary not found", file=sys.stderr)
        return 1
    missing = [path for path in [BASELINE, *(case.var_file for case in CASES)] if not path.exists()]
    if missing:
        for path in missing:
            print(f"FAIL fixture: missing {path.relative_to(REPO_ROOT)}", file=sys.stderr)
        return 1

    if not init_fixture():
        return 1

    if not provider_rpc_sockets_available():
        for case in CASES:
            print(
                f"SKIP {case.name}: Terraform provider RPC sockets cannot bind in this sandbox; "
                "provider-backed plan cannot load schemas here"
            )
        print(f"SKIP summary: 0 executed cases, {len(CASES)} skipped due sandbox socket policy")
        return 0

    executed = 0
    skipped = 0
    failed = 0
    for case in CASES:
        status = run_case(case)
        if status == "executed":
            executed += 1
        elif status == "skipped":
            skipped += 1
        else:
            failed += 1

    if executed < MIN_EXECUTED_CASES:
        print(
            f"FAIL summary: {executed} executed cases, {skipped} skipped; "
            f"need at least {MIN_EXECUTED_CASES} executed cases"
        )
        failed += 1
    else:
        print(f"PASS summary: {executed} executed cases, {skipped} skipped")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
