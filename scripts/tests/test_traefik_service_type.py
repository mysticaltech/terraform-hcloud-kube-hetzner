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


DEFAULT_CHART_VERSION = "41.7.0"
CHART_VERSIONS = ("34.5.0", "39.0.8", "40.0.0", "41.0.1", "41.5.0", "41.6.0", DEFAULT_CHART_VERSION)


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
    variables += '\nvariable "traefik_image_tag" {\n type = string\n default = ""\n}\n'
    # The fallback permits a regression run against the original buggy source.
    switch = "local.traefik_service_type_in_spec" if len(attributes) == 4 else "true"
    return variables + '\nlocals {\n' + '\n'.join(attributes) + '\n' + (
        'traefik_render_vars = merge(local.render_vars, {\n'
        ' var = merge(local.render_vars.var, { traefik_image_tag = var.traefik_image_tag })\n'
        ' local = merge(local.render_vars.local, {\n'
        f'  traefik_service_type_in_spec = {switch}\n'
        ' })\n})\n}\n'
    )


def run_helm(chart: Path, values: str, root: Path, env: dict[str, str],
             *, service_only: bool = True, kube_version: str = "1.32.0") -> str:
    path = root / "helm-values.yaml"
    path.write_text(values)
    command = ["helm", "template", "traefik", str(chart), "--namespace", "traefik",
               "--kube-version", kube_version, "--values", str(path),
               "--api-versions", "policy/v1/PodDisruptionBudget"]
    if service_only:
        command.extend(["--show-only", "templates/service.yaml"])
    result = subprocess.run(
        command,
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


def check_security_default(charts: Path, rendered: dict[str, str], root: Path,
                           env: dict[str, str]) -> None:
    import yaml

    def without_version_labels(node):
        if isinstance(node, dict):
            return {key: without_version_labels(value) for key, value in node.items()
                    if key not in {"helm.sh/chart", "app.kubernetes.io/version"}}
        if isinstance(node, list):
            return [without_version_labels(value) for value in node]
        return node

    chart = charts / f"traefik-{DEFAULT_CHART_VERSION}.tgz"
    metadata = yaml.safe_load(subprocess.check_output(["helm", "show", "chart", str(chart)], env=env))
    assert metadata["version"] == DEFAULT_CHART_VERSION and metadata["appVersion"] == "v3.7.14"
    for kube_version in ("1.25.0", "1.37.0"):
        objects = {}
        for version, tag in (("41.0.1", "v3.7.5"), (DEFAULT_CHART_VERSION, "v3.7.14")):
            manifest = run_helm(charts / f"traefik-{version}.tgz", rendered[version], root, env,
                                service_only=False, kube_version=kube_version)
            documents = [doc for doc in yaml.safe_load_all(manifest) if doc]
            deployment = next(doc for doc in documents if doc["kind"] == "Deployment")
            containers = deployment["spec"]["template"]["spec"]["containers"]
            assert len(containers) == 1 and containers[0]["image"] == f"docker.io/traefik:{tag}"
            assert any(doc["kind"] == "PodDisruptionBudget" for doc in documents)
            # Compare every other field, not just the Service or a selected spec.
            containers[0]["image"] = "docker.io/traefik:VERSION"
            objects[version] = {f'{doc["kind"]}/{doc["metadata"]["name"]}': without_version_labels(doc)
                                for doc in documents}
        assert objects["41.0.1"] == objects[DEFAULT_CHART_VERSION], objects
        print(f"PASS Kubernetes {kube_version}: full default render changes only image/chart-version labels")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", choices=("terraform", "tofu"), default="terraform")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--charts-dir", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    render.LOCALS_TF = repo / "locals.tf"
    fixture = render.base_render_vars()
    # Match production Traefik defaults, including PDB, without the generic harness image pin.
    defaults = {name: body["default"] for block in hcl2.loads((repo / "variables.tf").read_text())["variable"]
                for name, body in block.items() if name.startswith("traefik_")}
    assert defaults["traefik_image_tag"] == "", "Custom charts must retain their image default"
    fixture["var"].update({name: value for name, value in defaults.items() if name in fixture["var"]})
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
        cases = [(None, DEFAULT_CHART_VERSION), ("", DEFAULT_CHART_VERSION), ("  ", DEFAULT_CHART_VERSION),
                 ("latest", "*"), ("*", "*"), (" v39.0.8 ", "v39.0.8"),
                 ("v40.0.0", "v40.0.0"), ("40.0.0-rc.1", "40.0.0-rc.1")]
        cases.extend((version, version) for version in CHART_VERSIONS)
        cases = [(requested, resolved, "") for requested, resolved in cases]
        cases.extend([(None, DEFAULT_CHART_VERSION, "v3.7.5"),
                      (None, DEFAULT_CHART_VERSION, "v3.7.14"),
                      ("41.0.1", "41.0.1", "v3.7.5"),
                      ("39.0.8", "39.0.8", "v3.3.5")])
        rendered = {}
        image_pins = []
        for requested, resolved, image_tag in cases:
            (root / "terraform.tfvars.json").write_text(json.dumps({"traefik_version": requested,
                                                                   "traefik_image_tag": image_tag}))
            checked("plan", "-refresh=false", "-input=false", "-no-color", "-out=plan")
            plan = json.loads(checked("show", "-json", "plan"))
            assert not plan.get("resource_changes"), "Provider-free regression must not create resources"
            outputs = plan["planned_values"]["outputs"]
            assert outputs["version"]["value"] == resolved
            assert outputs["decoded"]["value"]["image"]["tag"] == (image_tag or None)
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
            if image_tag:
                image_pins.append((resolved, image_tag, outputs["values"]["value"]))
            else:
                rendered[resolved] = outputs["values"]["value"]
        print(f"PASS {args.cli}: {len(cases)} credential-free plans; legacy/modern/default/floating paths and image pins")
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
                check_helm(args.charts_dir / f"traefik-{DEFAULT_CHART_VERSION}.tgz", body, True, root, env)
                print(f"PASS {filename}: documented override passes default-chart Helm regression")
            check_security_default(args.charts_dir, rendered, root, env)
            import yaml
            for version, tag, values in image_pins:
                manifest = run_helm(args.charts_dir / f"traefik-{version}.tgz", values, root, env,
                                    service_only=False)
                deployment = next(doc for doc in yaml.safe_load_all(manifest)
                                  if doc and doc["kind"] == "Deployment")
                assert deployment["spec"]["template"]["spec"]["containers"][0]["image"] == f"docker.io/traefik:{tag}"
            print("PASS Helm: explicit image pins preserved on current and earlier chart pins")
        else:
            print("SKIP Helm schema/Service regressions: supply --charts-dir with official chart archives")


if __name__ == "__main__":
    main()
