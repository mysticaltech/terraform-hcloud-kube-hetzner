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
timeout=0
previous=""
for arg in "$@"; do
  if [ "$previous" = "--max-time" ]; then timeout="$arg"; fi
  case "$arg" in http*) url="$arg" ;; esac
  previous="$arg"
done
[ "$timeout" -gt 0 ] && [ "$timeout" -le 15 ] || exit 93
[ "$SCENARIO" != "short_budget" ] || [[ "$url" != */actions/1 ]] || [ "$timeout" -eq 3 ] || exit 94
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
      peer_id_max) touch "$TEST_ROOT/cleared"; action 9007199254740991 success ;;
      peer_id_max_running|peer_poll_above_max) action 9007199254740991 running ;;
      peer_id_above_max) touch "$TEST_ROOT/cleared"; action 9007199254740992 success ;;
      peer_id_above_max_running) action 9007199254740992 running ;;
      peer_running|peer_poll_error|deadline|peer_boundary_*|poll_*|sleep_expiry|short_budget) action 1 running ;;
      *) touch "$TEST_ROOT/cleared"; action 1 success ;;
    esac
    ;;
  */actions/1)
    case "$SCENARIO" in
      peer_poll_error) exit 28 ;;
      poll_mismatched_id) action 999 success ;;
      poll_string_id) echo '{"action":{"id":"1","status":"success","error":null}}' ;;
      poll_boolean_id) echo '{"action":{"id":true,"status":"success","error":null}}' ;;
      poll_missing_error) echo '{"action":{"id":1,"status":"success"}}' ;;
      poll_invalid_error) echo '{"action":{"id":1,"status":"success","error":false}}' ;;
      poll_invalid_status) echo '{"action":{"id":1,"status":true,"error":null}}' ;;
      poll_unknown_status) action 1 unknown ;;
      poll_malformed) echo '{"action":[]}' ;;
      peer_boundary_*)
        echo "$BOUNDARY_TIME" > "$TEST_ROOT/clock"
        status="${SCENARIO#peer_boundary_}"
        [ "$status" != success ] || touch "$TEST_ROOT/cleared"
        action 1 "$status"
        ;;
      *) touch "$TEST_ROOT/cleared"; action 1 success ;;
    esac
    ;;
  */servers/100/actions/change_alias_ips)
    # A premature assignment is rejected, as when the VIP is still assigned.
    [ -f "$TEST_ROOT/cleared" ] || exit 22
    case "$SCENARIO" in
      own_http_error) exit 22 ;;
      own_error) action 2 error ;;
      own_id_max) action 9007199254740991 success ;;
      own_id_max_running|own_poll_above_max) action 9007199254740991 running ;;
      own_id_above_max) action 9007199254740992 success ;;
      own_id_above_max_running) action 9007199254740992 running ;;
      own_running|own_boundary_*|own_poll_mismatched_id) action 2 running ;;
      *) action 2 success ;;
    esac
    ;;
  */actions/9007199254740991)
    case "$SCENARIO" in
      peer_poll_above_max|own_poll_above_max) action 9007199254740992 success ;;
      *) touch "$TEST_ROOT/cleared"; action 9007199254740991 success ;;
    esac
    ;;
  */actions/2)
    case "$SCENARIO" in
      own_poll_mismatched_id) action 999 success ;;
      own_boundary_*)
        echo "$BOUNDARY_TIME" > "$TEST_ROOT/clock"
        action 2 "${SCENARIO#own_boundary_}"
        ;;
      *) action 2 success ;;
    esac
    ;;
  */servers/100)
    case "$SCENARIO" in
      readback_http_error) exit 28 ;;
      readback_missing) echo '{"server":{"private_net":[{"network":12345,"alias_ips":[]}]}}' ;;
      readback_wrong_network) echo '{"server":{"private_net":[{"network":54321,"alias_ips":["10.0.0.1"]}]}}' ;;
      readback_string_alias) echo '{"server":{"private_net":[{"network":12345,"alias_ips":"10.0.0.10"}]}}' ;;
      readback_substring_alias) echo '{"server":{"private_net":[{"network":12345,"alias_ips":["10.0.0.10"]}]}}' ;;
      readback_bad_element) echo '{"server":{"private_net":[{"network":12345,"alias_ips":["10.0.0.1",123]}]}}' ;;
      readback_invalid_ip) echo '{"server":{"private_net":[{"network":12345,"alias_ips":["10.0.0.1","999.0.0.2"]}]}}' ;;
      readback_empty_string) echo '{"server":{"private_net":[{"network":12345,"alias_ips":["10.0.0.1",""]}]}}' ;;
      readback_null_alias) echo '{"server":{"private_net":[{"network":12345,"alias_ips":null}]}}' ;;
      readback_object_networks) echo '{"server":{"private_net":{"network":12345,"alias_ips":["10.0.0.1"]}}}' ;;
      readback_string_network) echo '{"server":{"private_net":[{"network":"12345","alias_ips":["10.0.0.1"]}]}}' ;;
      readback_malformed) echo '{"server":null}' ;;
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

    def run_scenario(self, script, scenario, boundary_time=60):
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
            sleep.write_text(
                '#!/bin/sh\n'
                'case "$SCENARIO" in\n'
                '  sleep_expiry) echo 60 > "$TEST_ROOT/clock" ;;\n'
                '  short_budget) echo 57 > "$TEST_ROOT/clock" ;;\n'
                'esac\n'
            )
            sleep.chmod(0o755)
            env_file = root / "hcloud.env"
            env_file.write_text('export HCLOUD_TOKEN="fake-token-do-not-print"\n')
            executable = script.replace("/etc/keepalived/hcloud.env", str(env_file))
            if scenario == "deadline":
                executable = executable.replace("deadline=$((SECONDS + 60))", "deadline=$SECONDS")
            # Advance a deterministic clock from the fake GET/sleep, without a real minute-long wait.
            (root / "clock").write_text("0\n")
            executable = executable.replace("$SECONDS", "$(test_clock)").replace("SECONDS", "$(test_clock)")
            executable = 'test_clock() { cat "$TEST_ROOT/clock"; }\n' + executable
            log = root / "commands.log"
            env = {
                "PATH": f"{bin_dir}:/usr/bin:/bin",
                "HOME": str(root),
                "SCENARIO": scenario,
                "COMMAND_LOG": str(log),
                "TEST_ROOT": str(root),
                "BOUNDARY_TIME": str(boundary_time),
            }
            result = subprocess.run(
                ["bash"], input=executable, text=True, capture_output=True, env=env, check=False
            )
            self.assertNotIn("fake-token-do-not-print", result.stdout + result.stderr)
            return result, log.read_text().splitlines() if log.exists() else []

    def assert_scenario(self, scenario, success, assignment=True, boundary_time=60):
        for name, script in self.scripts.items():
            with self.subTest(template=name, scenario=scenario):
                result, requests = self.run_scenario(script, scenario, boundary_time)
                self.assertEqual(result.returncode == 0, success, result.stderr)
                self.assertEqual(
                    any("/servers/100/actions/change_alias_ips" in url for url in requests),
                    assignment,
                )
                self.assertEqual(result.stdout, "")
                for server_id in (100, 200):
                    self.assertLessEqual(
                        requests.count(f"https://api.hetzner.cloud/v1/servers/{server_id}/actions/change_alias_ips"), 1
                    )
                if "id_max_running" in scenario or "poll_above_max" in scenario:
                    self.assertEqual(requests.count("https://api.hetzner.cloud/v1/actions/9007199254740991"), 1)
                if "id_above_max" in scenario:
                    self.assertFalse(any("/v1/actions/" in url for url in requests))
                if scenario.startswith("own_") and "above_max" in scenario:
                    self.assertNotIn("https://api.hetzner.cloud/v1/servers/100", requests)
                if "boundary" in scenario:
                    action_id = 1 if scenario.startswith("peer_") else 2
                    self.assertEqual(requests.count(f"https://api.hetzner.cloud/v1/actions/{action_id}"), 1)
                if scenario in ("deadline", "sleep_expiry"):
                    self.assertFalse(any("/v1/actions/" in url for url in requests))
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

    def test_single_router_templates_are_byte_identical_to_baseline(self):
        variables = base_render_vars()
        variables["enable_redundancy"] = False
        with tempfile.TemporaryDirectory() as directory:
            scratch = TerraformScratch(Path(directory), variables)
            for filename in ("nat-router-cloudinit.yaml.tpl", "nat-router-reconcile.sh.tpl"):
                relative = f"templates/{filename}"
                baseline = subprocess.run(
                    ["git", "show", f"17e4746de8c49ffd9b6825643345d7231d48c9c4:{relative}"],
                    cwd=REPO_ROOT, capture_output=True, text=True, check=True,
                ).stdout
                previous = scratch.write_template(f"baseline-{filename}", baseline)
                with self.subTest(template=filename):
                    self.assertEqual(scratch.render_string(previous), scratch.render_string(REPO_ROOT / relative))

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

    def test_maximum_action_id_is_accepted(self):
        for scenario in ("peer_id_max", "own_id_max", "peer_id_max_running", "own_id_max_running"):
            self.assert_scenario(scenario, True)

    def test_out_of_range_initial_action_id_stops_advancement(self):
        for scenario in ("peer_id_above_max", "peer_id_above_max_running"):
            self.assert_scenario(scenario, False, assignment=False)
        for scenario in ("own_id_above_max", "own_id_above_max_running"):
            self.assert_scenario(scenario, False)

    def test_out_of_range_polled_action_id_stops_advancement(self):
        self.assert_scenario("peer_poll_above_max", False, assignment=False)
        self.assert_scenario("own_poll_above_max", False)

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

    def test_received_terminal_success_at_or_after_deadline_is_retained(self):
        for boundary in (60, 61):
            self.assert_scenario("peer_boundary_success", True, boundary_time=boundary)
            self.assert_scenario("own_boundary_success", True, boundary_time=boundary)

    def test_received_error_or_running_at_deadline_fails_without_another_poll(self):
        for status in ("error", "running"):
            self.assert_scenario(f"peer_boundary_{status}", False, assignment=False)
            self.assert_scenario(f"own_boundary_{status}", False)

    def test_sleep_cannot_start_a_poll_after_expiry(self):
        self.assert_scenario("sleep_expiry", False, assignment=False)

    def test_next_poll_is_bounded_by_remaining_budget(self):
        self.assert_scenario("short_budget", True)

    def test_polled_action_identity_and_types_are_required(self):
        for scenario in (
            "poll_mismatched_id", "poll_string_id", "poll_boolean_id", "poll_missing_error",
            "poll_invalid_error", "poll_invalid_status", "poll_unknown_status", "poll_malformed",
        ):
            self.assert_scenario(scenario, False, assignment=False)
        self.assert_scenario("own_poll_mismatched_id", False)

    def test_readback_requires_network_array_and_exact_valid_ip_strings(self):
        for scenario in (
            "readback_string_alias", "readback_substring_alias", "readback_bad_element",
            "readback_invalid_ip", "readback_empty_string", "readback_null_alias",
            "readback_object_networks", "readback_string_network", "readback_malformed",
        ):
            self.assert_scenario(scenario, False)

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
