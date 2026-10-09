# /// script
# dependencies = ["python-hcl2==8.1.0"]
# ///
"""Plan-only snapshot contracts in disposable copies with explicit test schemas.

1.62 runs the full lookup-sensitive matrix. 1.70 checks supported contracts
with an explicit ID, plus actual query shapes and the optional-ID mock boundary.
Neither check performs a provider API read or establishes live acceptance.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import hcl2


REPO = Path(__file__).resolve().parents[2]
FIXTURE = Path("tests/autoscaler-snapshots.tftest.hcl")
REGIMES = {"lookup-matrix": "1.62.0", "current-contracts": "1.70.0"}
CURRENT_COLLECTION_CASES = {
    "microos_missing_os_label", "latest_microos",
    "legacy_microos_rejected", "wrong_os_microos_rejected", "wrong_distro_microos_rejected",
    "missing_microos_rejected", "legacy_microos_id_mode_preserved", "microos_backup_rejected",
}


def block(source, prefix):
    matches = [node for node in hcl2.parses_to_tree(source).find_data("block")
               if source[node.meta.start_pos:node.meta.end_pos].startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(f"Expected one source block: {prefix}")
    node = matches[0]
    return node.meta.start_pos, node.meta.end_pos


def run_names(source):
    return [json.loads(name) for run in hcl2.loads(source)["run"] for name in run]


def without_mock_id(source):
    matches = [node for node in hcl2.parses_to_tree(source).find_data("object_elem")
               if source[node.children[0].meta.start_pos:node.children[0].meta.end_pos].strip() == "id"]
    if len(matches) != 1:
        raise ValueError("Expected exactly one mock ID field")
    start, end = matches[0].meta.start_pos, matches[0].meta.end_pos
    if source[end:end + 1] != ",":
        raise ValueError("Review the mock ID field separator after fixture changes")
    end += 1
    while source[end:end + 1] in (" ", "\t"):
        end += 1
    return source[:start] + source[end:]


def command(cli, args, cwd, env, log):
    result = subprocess.run([cli, *args], cwd=cwd, env=env, text=True,
                            capture_output=True)
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"{cli} {' '.join(args)} failed; see {log}\n"
                           + result.stdout + result.stderr)
    return result.stdout


def matrix(cli, cwd, env, filename, expected):
    output = command(cli, ["test", f"-filter={filename}", "-json"], cwd, env,
                     cwd / "test.jsonl")
    rows = [json.loads(line) for line in output.splitlines() if line.strip()]
    summary = next(row["test_summary"] for row in rows if row.get("type") == "test_summary")
    if summary["passed"] != expected or any(summary.get(key, 0) for key in
                                           ("failed", "errored", "skipped")):
        raise RuntimeError(f"Incomplete matrix: {summary}")
    print(f"PASS: {cwd.name}: {expected} plans, no failures or skips", flush=True)
    return summary


def copy_module(destination, version):
    # Copy tracked working bytes, never ignored operational files or provider state.
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=REPO).decode().split("\0")
    for name in filter(None, files):
        source, target = REPO / name, destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target, follow_symlinks=False)
    versions = destination / "versions.tf"
    original = versions.read_text()
    old = 'version = ">= 1.62.0"'
    if original.count(old) != 1:
        raise ValueError("Review the test-only HCloud constraint substitution")
    versions.write_text(original.replace(old, f'version = "= {version}"'))


def current_fixture(source):
    start, end = block(source, 'mock_data "hcloud_image"')
    source = source[:start] + without_mock_id(source[start:end]) + source[end:]
    names = run_names(source)
    if len(names) != 21 or not CURRENT_COLLECTION_CASES.issubset(names):
        raise ValueError("Review the current-provider coverage partition after fixture changes")
    blocks = []
    for name in names:
        if name in CURRENT_COLLECTION_CASES:
            continue
        start, end = block(source, f'run "{name}"')
        original = source[start:end]
        if name == "default_id":
            # Optional-only IDs cannot model the API response. Preserve assertions
            # with a real production input pin; do not add a production fallback.
            original = original.replace('run "default_id" {', '''run "current_explicit_id" {
  variables { leapmicro_x86_snapshot_id = "200" }''', 1)
        elif name == "leapmicro_backup_rejected":
            original = without_mock_id(original)
        blocks.append(original)
    first, _ = block(source, f'run "{names[0]}"')
    return source[:first] + "\n\n".join(blocks) + "\n"


def schema(cli, cwd, env, version):
    info = json.loads(command(cli, ["version", "-json"], cwd, env, cwd / "versions.json"))
    selections = info["provider_selections"]
    address = next(key for key in selections if key.endswith("/hetznercloud/hcloud"))
    if selections[address] != version:
        raise RuntimeError(f"Unexpected HCloud resolution: {selections}")
    data = json.loads(command(cli, ["providers", "schema", "-json"], cwd, env,
                              cwd / "schema.json"))
    sources = data["provider_schemas"][address]["data_source_schemas"]
    attrs = sources["hcloud_image"]["block"]["attributes"]
    computed, collection = (True, "list") if version == "1.62.0" else (False, "set")
    if not attrs["id"].get("optional") or attrs["id"].get("computed", False) != computed:
        raise RuntimeError("HCloud image ID mock boundary changed; review the fixture regime")
    if attrs["with_status"]["type"] != [collection, "string"]:
        raise RuntimeError("HCloud status collection schema changed; review the contract")
    images = sources["hcloud_images"]["block"]["attributes"]["images"]
    if version == "1.70.0":
        nested = images["nested_type"]
        image_id = nested["attributes"]["id"]
        if nested["nesting_mode"] != "list" or image_id.get("type") != "number" or not image_id.get("computed"):
            raise RuntimeError("HCloud image-list mock boundary changed; review the contract")
    return {"cli_version": info["terraform_version"], "providers": selections,
            "image_id": attrs["id"], "with_status": attrs["with_status"]["type"],
            "images": images}


def boundary_root(destination):
    source = (REPO / "data.tf").read_text()
    start, end = block(source, 'data "hcloud_image" "leapmicro_x86_snapshot"')
    micro_start, micro_end = block(source, 'data "hcloud_images" "microos_x86_snapshots"')
    # Inputs are deterministic scaffolding; the query block is actual source.
    (destination / "main.tf").write_text('''terraform {
  required_providers {
    hcloud = { source = "hetznercloud/hcloud", version = "= 1.70.0" }
  }
}
variable "enabled_architectures" { default = ["x86"] }
variable "leapmicro_x86_snapshot_id" { default = "" }
variable "microos_x86_snapshot_id" { default = "" }
variable "cluster_autoscaler_snapshot_selection" { default = "latest" }
locals {
  os_arch_requirements = { leapmicro = { x86 = true }, microos = { x86 = true } }
  first_nodepool_os = "leapmicro"
  autoscaler_snapshot_architectures = ["x86"]
  kubernetes_distribution = "k3s"
}
''' + source[start:end] + "\n" + source[micro_start:micro_end] + "\n")
    tests = destination / "tests"
    tests.mkdir()
    (tests / "boundary.tftest.hcl").write_text('''mock_provider "hcloud" {
  mock_data "hcloud_image" {
    defaults = { type = "snapshot", architecture = "x86" }
  }
}
run "optional_id_is_not_an_api_response" {
  command = plan
  assert {
    condition = data.hcloud_image.leapmicro_x86_snapshot[0].id == null
    error_message = "An optional-only unconfigured ID is not a mock API response."
  }
  assert {
    condition = length(data.hcloud_image.leapmicro_x86_snapshot[0].with_status) == 1 && contains(data.hcloud_image.leapmicro_x86_snapshot[0].with_status, "available") && data.hcloud_image.leapmicro_x86_snapshot[0].with_architecture == "x86" && data.hcloud_image.leapmicro_x86_snapshot[0].with_selector == "leapmicro-snapshot=yes,kube-hetzner/os=leapmicro,kube-hetzner/k8s-distro=k3s"
    error_message = "The actual production query must retain status, architecture and OS/distro."
  }
}
run "microos_query_shape" {
  command = plan
  assert {
    condition = length(data.hcloud_images.microos_x86_snapshots[0].with_status) == 1 && contains(data.hcloud_images.microos_x86_snapshots[0].with_status, "available") && length(data.hcloud_images.microos_x86_snapshots[0].with_architecture) == 1 && contains(data.hcloud_images.microos_x86_snapshots[0].with_architecture, "x86") && data.hcloud_images.microos_x86_snapshots[0].with_selector == "microos-snapshot=yes" && data.hcloud_images.microos_x86_snapshots[0].most_recent
    error_message = "The actual MicroOS query must retain status, architecture, selector and recency."
  }
  assert {
    condition = length(data.hcloud_images.microos_x86_snapshots[0].images) == 0
    error_message = "A generated empty mock collection is not evidence of returned API images."
  }
}
''')


def run(args, output):
    home = output / "home"
    home.mkdir()
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "LANG": "C.UTF-8",
           "TF_IN_AUTOMATION": "1", "CHECKPOINT_DISABLE": "1",
           "TF_CLI_CONFIG_FILE": str(args.cli_config.resolve()), "TMPDIR": str(output)}
    receipt = {"regimes": {}, "limits": [
        "No live API read, image filtering/boot, upgrade or replacement-policy acceptance.",
        "1.70 selector-lookup ID remains unmodellable by provider mocks; real Read sets the API ID.",
        "1.70 full-module probe uses an explicit-ID variant and excludes eight MicroOS collection cases.",
        "1.70 mocks omit non-computed ID defaults/overrides; OpenTofu rejects them rather than leaving null.",
        "Terraform 1.15 nested_type collection overrides are unsupported (upstream #38369).",
    ]}
    for name, version in REGIMES.items():
        destination = output / name
        destination.mkdir()
        copy_module(destination, version)
        if name == "current-contracts":
            fixture = destination / FIXTURE
            fixture.write_text(current_fixture(fixture.read_text()))
        command(args.cli, ["fmt", "-check", str(FIXTURE)], destination, env,
                destination / "fmt.log")
        command(args.cli, ["init", "-backend=false", "-input=false", "-no-color"],
                destination, env, destination / "init.log")
        details = schema(args.cli, destination, env, version)
        details["summary"] = matrix(args.cli, destination, env, FIXTURE,
                                     21 if name == "lookup-matrix" else 13)
        details["runs"] = run_names((destination / FIXTURE).read_text())
        if name == "current-contracts":
            details["excluded_collection_runs"] = sorted(CURRENT_COLLECTION_CASES)
        receipt["regimes"][name] = details
    boundary = output / "current-query-boundary"
    boundary.mkdir()
    boundary_root(boundary)
    command(args.cli, ["fmt"], boundary, env, boundary / "fmt.log")
    command(args.cli, ["init", "-backend=false", "-input=false", "-no-color"],
            boundary, env, boundary / "init.log")
    receipt["current_query_boundary"] = matrix(args.cli, boundary, env,
                                                "tests/boundary.tftest.hcl", 2)
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Receipt: {output / 'receipt.json'}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", choices=("terraform", "tofu"), default="terraform")
    parser.add_argument("--cli-config", type=Path, default=Path("/dev/null"),
                        help="Optional test-only provider mirror config; no credential-bearing config")
    parser.add_argument("--output-dir", type=Path,
                        help="Retain disposable copies/logs in a new directory (must not exist)")
    args = parser.parse_args()
    if args.output_dir:
        output = args.output_dir.resolve()
        output.mkdir(parents=True, exist_ok=False)
        run(args, output)
    else:
        with tempfile.TemporaryDirectory(prefix="kh-snapshot-tests-") as directory:
            run(args, Path(directory))


if __name__ == "__main__":
    main()
