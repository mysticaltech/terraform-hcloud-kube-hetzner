# /// script
# dependencies = ["python-hcl2==7.3.1", "PyYAML==6.0.3"]
# ///
"""Provider-free Traefik plans and optional upstream Helm schema regressions.

Run with uv run scripts/tests/test_traefik_service_type.py --cli terraform
or --cli tofu. Supply --charts-dir with local traefik-<version>.tgz archives
to additionally validate schemas and rendered Services without cluster access.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import hcl2

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_harness as render


CHART_VERSIONS = ("34.5.0", "39.0.8", "40.0.0", "41.0.1", "41.6.0")


def version_configuration(repo: Path) -> str:
    source = (repo / "locals.tf").read_text()
    start = source.index("  addon_default_versions = {")
    end = source.index("  kured_manifest_body", start)
    source = "locals {\n" + source[start:end] + "\n}"
    names = {"addon_default_versions", "addon_version_inputs", "traefik_version",
             "traefik_service_type_in_spec"}
    attributes = []
    for node in hcl2.parses(source).find_data("attribute"):
        name = str(node.children[0].children[0])
        if name in names:
            attributes.append(source[node.meta.start_pos:node.meta.end_pos])
    assert len(attributes) in (3, 4), "Could not isolate production chart-version locals"
    inputs = hcl2.loads(source)["locals"][0]["addon_version_inputs"]
    variables = '\n'.join(f'variable "{name}_version" {{\n type = string\n default = null\n}}'
                          for name in inputs)
    # The fallback permits a regression run against the original buggy source.
    switch = "local.traefik_service_type_in_spec" if len(attributes) == 4 else "true"
    return variables + '\nlocals {\n' + '\n'.join(attributes) + '\n' + (
        'traefik_render_vars = merge(local.render_vars, {\n'
        ' local = merge(local.render_vars.local, {\n'
        f'  traefik_service_type_in_spec = {switch}\n'
        ' })\n})\n}\n'
    )


def run_helm(chart: Path, values: str, root: Path, env: dict[str, str]) -> str:
    path = root / "helm-values.yaml"
    path.write_text(values)
    result = subprocess.run(
        ["helm", "template", "traefik", str(chart), "--namespace", "traefik",
         "--kube-version", "1.32.0", "--show-only", "templates/service.yaml",
         "--values", str(path)],
        env=env, text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout


def check_helm(chart: Path, values: str, modern: bool, root: Path,
               env: dict[str, str]) -> None:
    import yaml

    class UniqueKeysLoader(yaml.SafeLoader):
        pass

    def unique_mapping(loader, node, deep=False):
        result = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=deep)
            assert key not in result, f"Duplicate YAML key: {key}"
            result[key] = loader.construct_object(value_node, deep=deep)
        return result

    UniqueKeysLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
                                    unique_mapping)

    def service(manifest):
        documents = list(yaml.load_all(manifest, Loader=UniqueKeysLoader))
        services = [document for document in documents
                    if isinstance(document, dict) and document.get("kind") == "Service"]
        assert len(services) == 1, services
        return services[0]

    initial = service(run_helm(chart, values, root, env))
    assert initial["spec"]["type"] == "LoadBalancer", initial
    for service_type in ("ClusterIP", "NodePort"):
        document = yaml.safe_load(values)
        target = document["service"]["spec"] if modern else document["service"]
        target["type"] = service_type
        changed = service(run_helm(chart, yaml.safe_dump(document), root, env))
        assert changed["spec"]["type"] == service_type, changed
        assert changed["metadata"] == initial["metadata"]
        assert changed["spec"]["ports"] == initial["spec"]["ports"]
    if modern:
        # The old key is schema-valid but ignored: a default-LB test alone misses it.
        document = yaml.safe_load(values)
        document["service"]["type"] = "ClusterIP"
        ignored = service(run_helm(chart, yaml.safe_dump(document), root, env))
        assert ignored["spec"]["type"] == "LoadBalancer", ignored
    print(f"PASS {chart.name}: Helm schema, unique keys, LB/ClusterIP/NodePort semantics")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", choices=("terraform", "tofu"), default="terraform")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--charts-dir", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    render.LOCALS_TF = repo / "locals.tf"
    fixture = render.base_render_vars()
    # Match normal module defaults, letting each chart choose its supported image.
    fixture["var"].update(traefik_image_tag="", traefik_pod_disruption_budget=False,
                          traefik_provider_kubernetes_gateway_enabled=False)
    env = {key: value for key, value in os.environ.items()
           if key in {"PATH", "HOME", "TMPDIR"}}
    env.update(TF_CLI_CONFIG_FILE="/dev/null", TF_IN_AUTOMATION="1")
    with tempfile.TemporaryDirectory(prefix="kh-traefik-", dir="/tmp") as directory:
        root = Path(directory)
        scratch = render.TerraformScratch(root, fixture)
        template = scratch.write_template("traefik", render.extract_heredoc("traefik_values_default"))
        main_tf = root / "main.tf"
        main_tf.write_text(main_tf.read_text() + version_configuration(repo))
        (root / "outputs.tf.json").write_text(json.dumps({"output": {
            "version": {"value": "${local.traefik_version}"},
            "values": {"value": '${templatefile(' + json.dumps(str(template)) +
                       ', local.traefik_render_vars)}'},
            "decoded": {"value": '${yamldecode(templatefile(' + json.dumps(str(template)) +
                        ', local.traefik_render_vars))}'},
        }}))

        def checked(*command, expression=None):
            result = subprocess.run([args.cli, *command], cwd=root, env=env,
                                    input=expression, text=True, capture_output=True)
            assert result.returncode == 0, result.stdout + result.stderr
            return result.stdout

        checked("fmt")
        checked("init", "-backend=false", "-input=false")
        checked("validate", "-no-color")
        cases = [(None, "41.0.1"), ("", "41.0.1"), ("  ", "41.0.1"),
                 ("latest", "*"), ("*", "*"), (" v39.0.8 ", "v39.0.8"),
                 ("v40.0.0", "v40.0.0"), ("40.0.0-rc.1", "40.0.0-rc.1")]
        cases.extend((version, version) for version in CHART_VERSIONS)
        rendered = {}
        for requested, resolved in cases:
            (root / "terraform.tfvars.json").write_text(json.dumps({"traefik_version": requested}))
            checked("plan", "-refresh=false", "-input=false", "-no-color", "-out=plan")
            plan = json.loads(checked("show", "-json", "plan"))
            assert not plan.get("resource_changes"), "Provider-free regression must not create resources"
            outputs = plan["planned_values"]["outputs"]
            assert outputs["version"]["value"] == resolved
            modern = resolved == "*" or int(resolved.lstrip("v").split(".")[0]) >= 40
            service = outputs["decoded"]["value"]["service"]
            if modern:
                assert "type" not in service, f"{requested!r}: obsolete service.type is present"
                assert service["spec"]["type"] == "LoadBalancer"
            else:
                assert service["type"] == "LoadBalancer"
                assert "type" not in service.get("spec", {}), f"{requested!r}: duplicate type path"
            assert service["enabled"] is True
            assert service["annotations"]["load-balancer.hetzner.cloud/name"] == "render-harness-nginx"
            rendered[resolved] = outputs["values"]["value"]
        print(f"PASS {args.cli}: {len(cases)} credential-free plans; legacy/modern/default/floating paths")
        examples = {}
        for filename in ("kube.tf.example", "docs/llms.md"):
            match = re.search(r'traefik_values\s*=\s*<<-EOT\n(.*?)\n\s*EOT',
                              (repo / filename).read_text(), re.DOTALL)
            assert match is not None, f"Missing documented Traefik heredoc: {filename}"
            body = match.group(1)
            encoded = checked("console", expression=f'jsonencode(yamldecode({render.hcl_string(body)}))\n')
            service = json.loads(json.loads(encoded.strip()))["service"]
            assert "type" not in service and service["spec"]["type"] == "LoadBalancer", filename
            examples[filename] = body
        print(f"PASS {args.cli}: both documented override examples use the default chart's Service schema")
        if args.charts_dir:
            for version in CHART_VERSIONS:
                chart = args.charts_dir / f"traefik-{version}.tgz"
                assert chart.is_file(), f"Missing official chart: {chart}"
                check_helm(chart, rendered[version], int(version.split('.')[0]) >= 40, root, env)
            for filename, body in examples.items():
                check_helm(args.charts_dir / "traefik-41.0.1.tgz", body, True, root, env)
                print(f"PASS {filename}: documented override passes default-chart Helm regression")
        else:
            print("SKIP Helm schema/Service regressions: supply --charts-dir with official chart archives")


if __name__ == "__main__":
    main()
