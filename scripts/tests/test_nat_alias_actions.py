#!/usr/bin/env python3
"""Provider-free rendering and fake-API regressions for the two-router handoff.

Run: uv run scripts/tests/test_nat_alias_actions.py
No live API requests or system configuration changes are made.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from render_harness import REPO_ROOT, TerraformScratch, base_render_vars


FAKE_CURL = r'''#!/bin/bash
set -eu
args=" $* "
[[ "$args" == *" --connect-timeout 5 "* && "$args" == *" --max-time 15 "* ]] || exit 90
[[ "$args" != *" --retry "* ]] || exit 91
for arg in "$@"; do
  case "$arg" in http*) url="$arg" ;; esac
done
printf '%s\n' "$url" >> "$COMMAND_LOG"
action() {
  printf '{"action":{"id":%s,"status":"%s","error":null}}\n' "$1" "$2"
}
case "$url" in
  *metadata/instance-id) echo 100 ;;
  *servers\?*)
    echo '{"servers":[{"id":200,"private_net":[{"network":12345,"ip":"10.0.0.3"}]}]}'
    ;;
  */servers/200/actions/change_alias_ips)
    case "$SCENARIO" in
      peer_http_error) exit 22 ;;
      peer_error) action 1 error ;;
      peer_malformed) echo '{}' ;;
      peer_invalid_id) echo '{"action":{"id":"not-an-id","status":"success"}}' ;;
      peer_success_with_error) echo '{"action":{"id":1,"status":"success","error":{"message":"fake-token-do-not-print"}}}' ;;
      peer_running|peer_poll_error|deadline) action 1 running ;;
      *) touch "$TEST_ROOT/cleared"; action 1 success ;;
    esac
    ;;
  */actions/1)
    case "$SCENARIO" in
      peer_poll_error) exit 28 ;;
      *) touch "$TEST_ROOT/cleared"; action 1 success ;;
    esac
    ;;
  */servers/100/actions/change_alias_ips)
    # A premature assignment is rejected, as when the VIP is still assigned.
    [ -f "$TEST_ROOT/cleared" ] || exit 22
    case "$SCENARIO" in
      own_http_error) exit 22 ;;
      own_error) action 2 error ;;
      own_running) action 2 running ;;
      *) action 2 success ;;
    esac
    ;;
  */actions/2) action 2 success ;;
  */servers/100)
    case "$SCENARIO" in
      readback_http_error) exit 28 ;;
      readback_missing) echo '{"server":{"private_net":[{"network":12345,"alias_ips":[]}]}}' ;;
      readback_wrong_network) echo '{"server":{"private_net":[{"network":54321,"alias_ips":["10.0.0.1"]}]}}' ;;
      *) echo '{"server":{"private_net":[{"network":12345,"alias_ips":["10.0.0.1"]}]}}' ;;
    esac
    ;;
  *) exit 92 ;;
esac
'''


class NatAliasActionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.render_temp = tempfile.TemporaryDirectory()
        scratch = TerraformScratch(Path(cls.render_temp.name), base_render_vars())
        document = scratch.render_yaml(REPO_ROOT / "templates/nat-router-cloudinit.yaml.tpl")
        cls.scripts = {
            "cloudinit": next(
                entry["content"]
                for entry in document["write_files"]
                if entry["path"] == "/usr/local/bin/hcloud-alias-failover.sh"
            )
        }
        reconcile = scratch.render_string(REPO_ROOT / "templates/nat-router-reconcile.sh.tpl")
        match = re.search(
            r"cat > /usr/local/bin/hcloud-alias-failover.sh <<'EOF'\n(.*?)\nEOF",
            reconcile,
            re.S,
        )
        assert match is not None
        cls.scripts["reconcile"] = match.group(1) + "\n"

    @classmethod
    def tearDownClass(cls):
        cls.render_temp.cleanup()

    def run_scenario(self, script, scenario):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            curl = bin_dir / "curl"
            curl.write_text(FAKE_CURL)
            curl.chmod(0o755)
            ip = bin_dir / "ip"
            ip.write_text(
                '#!/bin/sh\n'
                '[ "$SCENARIO" != "not_master" ] || exit 0\n'
                'if [ "$SCENARIO" = "demoted" ] && [ -f "$TEST_ROOT/cleared" ]; then exit 0; fi\n'
                'echo "2: eth1 inet 10.0.0.1/32 scope global eth1"\n'
            )
            ip.chmod(0o755)
            sleep = bin_dir / "sleep"
            sleep.write_text("#!/bin/sh\nexit 0\n")
            sleep.chmod(0o755)
            env_file = root / "hcloud.env"
            env_file.write_text('export HCLOUD_TOKEN="fake-token-do-not-print"\n')
            executable = script.replace("/etc/keepalived/hcloud.env", str(env_file))
            if scenario == "deadline":
                executable = executable.replace("deadline=$((SECONDS + 60))", "deadline=$SECONDS")
            log = root / "commands.log"
            env = {
                "PATH": f"{bin_dir}:/usr/bin:/bin",
                "HOME": str(root),
                "SCENARIO": scenario,
                "COMMAND_LOG": str(log),
                "TEST_ROOT": str(root),
            }
            result = subprocess.run(
                ["bash"], input=executable, text=True, capture_output=True, env=env, check=False
            )
            self.assertNotIn("fake-token-do-not-print", result.stdout + result.stderr)
            return result, log.read_text().splitlines() if log.exists() else []

    def assert_scenario(self, scenario, success, assignment=True):
        for name, script in self.scripts.items():
            with self.subTest(template=name, scenario=scenario):
                result, requests = self.run_scenario(script, scenario)
                self.assertEqual(result.returncode == 0, success, result.stderr)
                self.assertEqual(
                    any("/servers/100/actions/change_alias_ips" in url for url in requests),
                    assignment,
                )
                self.assertEqual(result.stdout, "")
                if scenario == "peer_running":
                    self.assertLess(
                        requests.index("https://api.hetzner.cloud/v1/actions/1"),
                        requests.index("https://api.hetzner.cloud/v1/servers/100/actions/change_alias_ips"),
                    )

    def test_rendered_bash_and_helpers_match(self):
        helpers = []
        for script in self.scripts.values():
            result = subprocess.run(["bash", "-n"], input=script, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            helper = re.search(r"api_request\(\) \{.*?return 1\n\}", script, re.S)
            self.assertIsNotNone(helper)
            helpers.append(helper.group(0))
        self.assertEqual(helpers[0], helpers[1])

    def test_immediate_success(self):
        self.assert_scenario("success", True)

    def test_waits_for_peer_release(self):
        self.assert_scenario("peer_running", True)

    def test_waits_for_own_assignment(self):
        self.assert_scenario("own_running", True)

    def test_peer_http_failure_stops_assignment(self):
        self.assert_scenario("peer_http_error", False, assignment=False)

    def test_peer_action_failure_stops_assignment(self):
        self.assert_scenario("peer_error", False, assignment=False)

    def test_malformed_action_stops_assignment(self):
        self.assert_scenario("peer_malformed", False, assignment=False)

    def test_invalid_action_id_stops_assignment(self):
        self.assert_scenario("peer_invalid_id", False, assignment=False)

    def test_success_with_action_error_stops_assignment(self):
        self.assert_scenario("peer_success_with_error", False, assignment=False)

    def test_non_master_does_not_mutate_aliases(self):
        self.assert_scenario("not_master", False, assignment=False)
        for script in self.scripts.values():
            _, requests = self.run_scenario(script, "not_master")
            self.assertFalse(any("change_alias_ips" in url for url in requests))

    def test_demotion_during_release_stops_assignment(self):
        self.assert_scenario("demoted", False, assignment=False)

    def test_action_lookup_failure_stops_assignment(self):
        self.assert_scenario("peer_poll_error", False, assignment=False)

    def test_expired_action_deadline_stops_assignment(self):
        self.assert_scenario("deadline", False, assignment=False)

    def test_own_http_failure_is_not_success(self):
        self.assert_scenario("own_http_error", False)

    def test_own_action_failure_is_not_success(self):
        self.assert_scenario("own_error", False)

    def test_missing_alias_is_not_success(self):
        self.assert_scenario("readback_missing", False)

    def test_alias_on_wrong_network_is_not_success(self):
        self.assert_scenario("readback_wrong_network", False)

    def test_readback_http_failure_is_not_success(self):
        self.assert_scenario("readback_http_error", False)


if __name__ == "__main__":
    unittest.main()
