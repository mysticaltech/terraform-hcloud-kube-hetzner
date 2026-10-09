#!/usr/bin/env python3
"""Credential-free command regression for the NAT bootstrap readiness gate.

Run: uv run scripts/tests/test_nat_cloudinit_readiness.py
This checks command failure propagation, not NAT egress or a rolling migration.
"""

from __future__ import annotations

import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class NatCloudInitReadinessTests(unittest.TestCase):
    def test_cloudinit_failure_is_not_ready(self):
        source = (ROOT / "nat-router.tf").read_text()
        block = source.split('resource "terraform_data" "nat_router_await_cloud_init" {', 1)[1]
        block = block.split('\nresource "terraform_data"', 1)[0]
        match = re.search(r'inline\s*=\s*\[("[^\n]+")\]', block)
        self.assertIsNotNone(match)
        command = json.loads(match.group(1))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shim = root / "cloud-init"
            shim.write_text('#!/bin/sh\n[ "$*" = "status --wait" ] || exit 99\nexit "$STATUS"\n')
            shim.chmod(0o755)
            for status in (0, 1, 2):
                with self.subTest(cloud_init_exit=status):
                    result = subprocess.run(
                        ["sh", "-c", command],
                        env={"PATH": f"{root}:/usr/bin:/bin", "STATUS": str(status)},
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, status, result.stderr)
                    self.assertEqual(result.stdout, "")

    def test_gate_still_precedes_node_modules(self):
        for filename in ("agents.tf", "control_planes.tf"):
            with self.subTest(source=filename):
                source = (ROOT / filename).read_text()
                module = source.split('source = "./modules/host"', 1)[1]
                dependencies = module.split("depends_on = [", 1)[1].split("]", 1)[0]
                self.assertIn("terraform_data.nat_router_await_cloud_init", dependencies)


if __name__ == "__main__":
    unittest.main()
