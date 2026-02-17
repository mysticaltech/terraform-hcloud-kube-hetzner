#!/usr/bin/env python3
"""Generate a lightweight MkDocs site from README.md and kube.tf.example."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
KUBE_EXAMPLE = ROOT / "kube.tf.example"
SITE_DOCS = ROOT / "site-docs"


def _extract_section(markdown: str, heading: str) -> str:
    pattern = re.compile(
        rf"^##+\s+{re.escape(heading)}\s*$([\s\S]*?)(?=^##+\s+|\Z)",
        re.MULTILINE,
    )
    match = pattern.search(markdown)
    return match.group(0).strip() if match else ""


def _extract_intro(markdown: str) -> str:
    lines = markdown.splitlines()
    cleaned: list[str] = []
    for line in lines:
        if line.startswith("# "):
            cleaned.append(line)
            continue
        if line.startswith("<") and line.endswith(">"):
            continue
        if line.strip().startswith("[!["):
            continue
        cleaned.append(line)
        if line.strip() == "---":
            break
    return "\n".join(cleaned).strip()


def _extract_configuration_keys(example: str) -> list[str]:
    keys: list[str] = []
    seen: set[str] = set()
    # Restrict extraction to top-level assignments in the example module block.
    patterns = [
        re.compile(r"^\s{2}#\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=", re.MULTILINE),
        re.compile(r"^\s{2}([a-zA-Z_][a-zA-Z0-9_]*)\s*=", re.MULTILINE),
    ]
    for pattern in patterns:
        for match in pattern.finditer(example):
            key = match.group(1)
            if key in {"module", "variable", "locals", "output", "resource", "data", "terraform"}:
                continue
            if key not in seen:
                seen.add(key)
                keys.append(key)
    return keys


def generate() -> None:
    SITE_DOCS.mkdir(parents=True, exist_ok=True)

    readme = README.read_text(encoding="utf-8")
    kube_example = KUBE_EXAMPLE.read_text(encoding="utf-8")

    intro = _extract_intro(readme)
    quick_start = _extract_section(readme, "Quick Start")
    architecture = _extract_section(readme, "Architecture")

    index_content = "\n\n".join(
        [
            "# kube-hetzner",
            "> Generated from `README.md` by `scripts/sync_docs_site.py`.",
            intro or "",
            quick_start or "",
            architecture or "",
        ]
    ).strip() + "\n"

    keys = _extract_configuration_keys(kube_example)
    rows = "\n".join([f"- `{key}`" for key in keys])
    config_content = (
        "# Configuration Reference\n\n"
        "> Generated from `kube.tf.example` by `scripts/sync_docs_site.py`.\n\n"
        "## Detected Configuration Keys\n\n"
        f"{rows}\n"
    )

    (SITE_DOCS / "index.md").write_text(index_content, encoding="utf-8")
    (SITE_DOCS / "configuration.md").write_text(config_content, encoding="utf-8")


if __name__ == "__main__":
    generate()
