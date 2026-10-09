#!/usr/bin/env python3
"""Credential-free command regression for the NAT bootstrap readiness gate.

Run: uv run scripts/tests/test_nat_cloudinit_readiness.py
This checks the 22.4 legacy path and 23.4/24.1 structured status policy,
not a live image's installed version, NAT egress, or a rolling migration.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PRIVATE_MESSAGE = "dummy-credential-do-not-print /private/operator/path"


def warning_status():
    # Shape emitted by upstream 23.4 and 24.1 status.py; LogExporter uses WARNING.
    stages = {
        key: {"start": 1.0, "finished": 2.0, "errors": [], "recoverable_errors": {}}
        for key in ("init-local", "init", "modules-config", "modules-final")
    }
    stages["modules-final"]["recoverable_errors"] = {"WARNING": [PRIVATE_MESSAGE]}
    return {
        "status": "done", "extended_status": "degraded done",
        "boot_status_code": "enabled-by-generator", "stage": None,
        "errors": [], "recoverable_errors": {"WARNING": [PRIVATE_MESSAGE]},
        "detail": PRIVATE_MESSAGE, "datasource": PRIVATE_MESSAGE, **stages,
    }


class NatCloudInitReadinessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / "nat-router.tf").read_text()
        block = source.split('resource "terraform_data" "nat_router_await_cloud_init" {', 1)[1]
        block = block.split('\nresource "terraform_data"', 1)[0]
        match = re.search(r'inline\s*=\s*\[<<-EOT\n(.*?)\n\s*EOT\n\s*\]', block, re.S)
        assert match is not None
        cls.command = textwrap.dedent(match.group(1))

    def run_status(self, wait_rc=2, payload=None, json_rc=2):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "python3").symlink_to(sys.executable)
            response = root / "status.json"
            response.write_text(payload if isinstance(payload, str) else json.dumps(payload))
            shim = root / "cloud-init"
            shim.write_text(
                '#!/bin/sh\n'
                'printf "%s\\n" "$*" >> "$REQUEST_LOG"\n'
                'printf "%s\\n" "$PRIVATE_MESSAGE" >&2\n'
                'case "$*" in\n'
                '  "status --wait") printf "%s\\n" "$PRIVATE_MESSAGE"; exit "$WAIT_RC" ;;\n'
                '  "status --format json") cat "$RESPONSE_FILE"; exit "$JSON_RC" ;;\n'
                '  *) exit 99 ;;\n'
                'esac\n'
            )
            shim.chmod(0o755)
            log = root / "requests"
            result = subprocess.run(
                ["sh", "-c", self.command],
                env={
                    "PATH": f"{root}:/usr/bin:/bin", "WAIT_RC": str(wait_rc),
                    "JSON_RC": str(json_rc), "REQUEST_LOG": str(log),
                    "PRIVATE_MESSAGE": PRIVATE_MESSAGE, "RESPONSE_FILE": str(response),
                },
                capture_output=True, text=True,
            )
            self.assertNotIn(PRIVATE_MESSAGE, result.stdout + result.stderr)
            self.assertNotIn(str(root), result.stdout + result.stderr)
            return result, log.read_text().splitlines()

    def assert_rejected(self, payload):
        result, requests = self.run_status(payload=payload)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(requests, ["status --wait", "status --format json"])
        self.assertRegex(result.stdout + result.stderr, r'NAT cloud-init status: (rejected|invalid_json_or_schema)')

    def test_legacy_success_does_not_require_json_or_new_schema(self):
        result, requests = self.run_status(wait_rc=0, payload="unsupported", json_rc=99)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(requests, ["status --wait"])
        self.assertEqual(result.stdout + result.stderr, "")

    def test_fatal_and_unknown_command_failures_propagate_without_json(self):
        for code in (1, 3, 127):
            with self.subTest(exit=code):
                result, requests = self.run_status(wait_rc=code, payload=warning_status())
                self.assertEqual(result.returncode, code)
                self.assertEqual(requests, ["status --wait"])
                self.assertEqual(result.stdout, "")
                self.assertIn(f"command_failed (exit={code})", result.stderr)

    def test_completed_warning_only_schema_is_accepted_with_counts_only(self):
        for boot in ("enabled-by-generator", "enabled-by-kernel-cmdline", "enabled-by-sysvinit"):
            with self.subTest(boot=boot):
                payload = warning_status()
                payload["boot_status_code"] = boot
                result, _ = self.run_status(payload=payload)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertEqual(result.stdout, "NAT cloud-init status: done_warning_only (errors=0 stage_errors=0 warnings=1)\n")

    def test_inconsistent_json_command_result_is_rejected(self):
        for code in (0, 1, 127):
            with self.subTest(exit=code):
                result, _ = self.run_status(payload=warning_status(), json_rc=code)
                self.assertEqual(result.returncode, 2)
                self.assertIn("inconsistent_response", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_fatal_errors_at_top_or_any_stage_are_rejected(self):
        for key in (None, "init-local", "init", "modules-config", "modules-final"):
            with self.subTest(stage=key):
                payload = warning_status()
                target = payload if key is None else payload[key]
                target["errors"] = [PRIVATE_MESSAGE]
                self.assert_rejected(payload)

    def test_error_unknown_and_mixed_recoverable_categories_are_rejected(self):
        for key in (None, "init-local", "init", "modules-config", "modules-final"):
            for category in ("ERROR", "CRITICAL", "WARN", "DEPRECATED", "unknown"):
                with self.subTest(stage=key, category=category):
                    payload = warning_status()
                    target = payload if key is None else payload[key]
                    target["recoverable_errors"][category] = [PRIVATE_MESSAGE]
                    self.assert_rejected(payload)

    def test_incomplete_disabled_unknown_and_inconsistent_status_is_rejected(self):
        for key, value in (
            ("status", "running"), ("status", "disabled"), ("status", "error"),
            ("status", PRIVATE_MESSAGE), ("extended_status", "done"),
            ("extended_status", "degraded running"), ("stage", "modules-final"),
            ("boot_status_code", "disabled-by-generator"), ("boot_status_code", "unknown"),
        ):
            with self.subTest(field=key, value=value):
                payload = warning_status()
                payload[key] = value
                self.assert_rejected(payload)
        for value in (None, 0, False, -1, 0.5, float("nan")):
            with self.subTest(finished=value):
                payload = warning_status()
                payload["modules-final"]["finished"] = value
                self.assert_rejected(payload)

    def test_malformed_schema_or_messages_cannot_pass_or_leak(self):
        for raw in ("not-json " + PRIVATE_MESSAGE, "[]", "null", "{}"):
            self.assert_rejected(raw)
        for key in ("errors", "recoverable_errors", "stage", "modules-final"):
            payload = warning_status()
            del payload[key]
            self.assert_rejected(payload)
        for errors in (None, "not-an-array", [1], [""]):
            payload = warning_status()
            payload["errors"] = errors
            self.assert_rejected(payload)
        for warnings in (None, "not-an-array", [1], [None], [""], [], {}):
            payload = warning_status()
            payload["recoverable_errors"] = {"WARNING": warnings}
            self.assert_rejected(payload)

    def test_warning_aggregate_must_match_stages(self):
        payload = warning_status()
        payload["modules-final"]["recoverable_errors"] = {}
        self.assert_rejected(payload)
        payload = warning_status()
        payload["recoverable_errors"]["WARNING"] = [PRIVATE_MESSAGE, PRIVATE_MESSAGE]
        self.assert_rejected(payload)

    def test_gate_still_precedes_node_modules(self):
        for filename in ("agents.tf", "control_planes.tf"):
            with self.subTest(source=filename):
                source = (ROOT / filename).read_text()
                module = source.split('source = "./modules/host"', 1)[1]
                dependencies = module.split("depends_on = [", 1)[1].split("]", 1)[0]
                self.assertIn("terraform_data.nat_router_await_cloud_init", dependencies)


if __name__ == "__main__":
    unittest.main()
