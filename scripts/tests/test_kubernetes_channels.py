# /// script
# dependencies = ["python-hcl2==7.3.1"]
# ///
"""Provider-free channel plans using production HCL and upgrade templates.

Run with uv run scripts/tests/test_kubernetes_channels.py --cli terraform
or --cli tofu. --repo allows testing an original PR head without modifying it.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

import hcl2


def source_nodes(repo, filename, kind):
    source = (repo / filename).read_text()
    if filename == "locals.tf":
        # Limit parsing to the reviewed release section, not unrelated shell heredocs.
        start = source.index("  k3s_channel_release_manifest = {")
        end = source.index("  required_kubernetes_artifact_architectures =", start)
        source = "locals {\n" + source[start:end] + "\n}"
    for node in hcl2.parses(source).find_data(kind):
        yield str(node.children[0].children[0]), source[node.meta.start_pos:node.meta.end_pos]


def configuration(repo):
    variables = [text for kind, text in source_nodes(repo, "variables.tf", "block")
                 if kind == "variable" and any(text.startswith(f'variable "{name}"')
                     for name in ("k3s_channel", "k3s_version", "rke2_channel", "rke2_version"))]
    conditions = [text for kind, text in source_nodes(repo, "validation-contract.tf", "block")
                  if kind == "precondition" and any(f'"When {d}_version is empty' in text
                                                   for d in ("k3s", "rke2"))]
    names = {f"{d}_{suffix}" for d in ("k3s", "rke2") for suffix in
             ("channel_release_manifest", "release_sha256_manifest", "initial_version", "reviewed_sha256")}
    # Preserve expression spelling, including quoted tuple elements, via AST positions.
    locals_source = [text for name, text in source_nodes(repo, "locals.tf", "attribute") if name in names]
    assert len(variables) == 4 and len(conditions) == 2 and len(locals_source) == 8
    outputs = {}
    for distro, template in (("k3s", "plans.yaml.tpl"), ("rke2", "plans_rke2.yaml.tpl")):
        outputs[distro] = {
            "version": f"${{local.{distro}_initial_version}}",
            "digests": f"${{local.{distro}_reviewed_sha256}}",
            "plans": '${templatefile(' + json.dumps(str(repo / "templates" / template)) + ', {'
                     f'channel = var.{distro}_channel, version = var.{distro}_version, '
                     'drain = false, disable_eviction = false, upgrade_window = null})}',
        }
    return ("\n".join(variables) + '\nlocals {\n' + "\n".join(locals_source) +
            '\n}\nresource "terraform_data" "channels" {\n lifecycle {\n' +
            "\n".join(conditions) + "\n}\n}\n", {"output": {"channels": {"value": outputs}}})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", choices=("terraform", "tofu"), default="terraform")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    repo = args.repo.resolve()
    env = {key: value for key, value in os.environ.items() if key in {"PATH", "HOME", "TMPDIR"}}
    env.update(TF_CLI_CONFIG_FILE="/dev/null", TF_IN_AUTOMATION="1")
    with tempfile.TemporaryDirectory(prefix="kh-channel-", dir="/tmp") as directory:
        root = Path(directory)
        source, outputs = configuration(repo)
        (root / "main.tf").write_text(source)
        (root / "outputs.tf.json").write_text(json.dumps(outputs))

        def run(*command):
            return subprocess.run([args.cli, *command], cwd=root, env=env, text=True, capture_output=True)

        def checked(*command):
            result = run(*command)
            assert result.returncode == 0, result.stdout + result.stderr
            return result.stdout

        checked("fmt")
        checked("init", "-backend=false", "-input=false")
        checked("validate", "-no-color")

        def plan(values, error=None):
            result = run("plan", "-refresh=false", "-input=false", "-no-color", "-out=plan",
                         *(f"-var={key}={value}" for key, value in values.items()))
            if error:
                assert result.returncode != 0 and error in result.stdout + result.stderr, result.stdout + result.stderr
                return None
            assert result.returncode == 0, result.stdout + result.stderr
            data = json.loads(checked("show", "-json", "plan"))
            assert all("delete" not in change["change"]["actions"] for change in data["resource_changes"])
            return data["planned_values"]["outputs"]["channels"]["value"]

        defaults = plan({})
        assert defaults["k3s"]["version"] == "v1.36.3+k3s1"
        assert defaults["rke2"]["version"] == "v1.32.5+rke2r1"
        assert defaults["k3s"]["plans"].count("channels/stable") == 2
        assert defaults["rke2"]["plans"].count("version: v1.32.5+rke2r1") == 2
        assert plan({"rke2_channel": "v1.36"}) == defaults
        print(f"PASS {args.cli}: defaults unchanged; RKE2 exact default still overrides channel")

        minor_channels = {
            "k3s": {"v1.36": "v1.36.3+k3s1", "v1.37": "v1.37.0+k3s1"},
            "rke2": {"v1.36": "v1.36.3+rke2r1", "v1.37": "v1.37.0+rke2r1"},
        }
        for distro, minors in minor_channels.items():
            release = minors["v1.36"]
            for channel in ("stable", "latest", "testing", *minors):
                result = plan({f"{distro}_channel": channel, f"{distro}_version": ""})[distro]
                assert result["plans"].count(f"channel: https://update.{distro}.io/v1-release/channels/{channel}") == 2
                if channel in minors:
                    pinned = minors[channel]
                    assert result["version"] == pinned
                    assert set(result["digests"]) == {"amd64", "arm64"}
                    assert all(len(digest) == 64 for digest in result["digests"].values())
                    exact = plan({f"{distro}_channel": channel, f"{distro}_version": pinned})[distro]
                    assert exact["version"] == pinned and exact["digests"] == result["digests"]
                    assert exact["plans"].count(f"version: {pinned}") == 2
                    assert "channel: https://" not in exact["plans"]
            plan({f"{distro}_channel": "v1.38", f"{distro}_version": ""}, "Invalid value for variable")
            plan({f"{distro}_channel": "v1.35", f"{distro}_version": ""}, f"When {distro}_version is empty")
            custom = plan({f"{distro}_channel": "v1.35", f"{distro}_version": release})[distro]
            assert custom["version"] == release and custom["plans"].count(f"version: {release}") == 2
            print(f"PASS {args.cli} {distro}: supported channels, pinned bootstrap/digests, exact precedence, unsupported channels")
        preserved = plan({"k3s_channel": "v1.33", "k3s_version": ""})["k3s"]
        assert preserved["version"] == "v1.33.13+k3s2"
        assert preserved["plans"].count("channels/v1.33") == 2
        print(f"PASS {args.cli}: K3s v1.33 preservation channel; 23 provider-free plan cases")


if __name__ == "__main__":
    main()
