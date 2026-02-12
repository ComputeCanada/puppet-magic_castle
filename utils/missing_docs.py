#!/usr/bin/env python3
"""Find class parameters missing from README parameter tables.

This scans README sections (## `class`) for parameter tables and compares them
with class parameter lists in site/profile/manifests/*.pp.
"""
from __future__ import annotations

import re
import sys

from pathlib import Path

README_PATH = Path("README.md")
MANIFESTS_DIR = Path("site/profile/manifests")


def readme_class_params(text: str) -> dict[str, set[str]]:
    pattern = re.compile(r"^## `([^`]+)`\n(.*?)(?=^## `|\Z)", re.M | re.S)
    class_docs: dict[str, set[str]] = {}
    for match in pattern.finditer(text):
        cls = match.group(1)
        body = match.group(2)
        vars_found: set[str] = set()
        for row in re.findall(r"^\|\s*`?([a-zA-Z0-9_:\-]+)`?\s*\|", body, flags=re.M):
            if row in {"Variable", ":--------------", ":-------------"}:
                continue
            vars_found.add(row)
        class_docs[cls] = vars_found
    return class_docs


def manifest_class_params(text: str) -> dict[str, set[str]]:
    class_re = re.compile(r"class\s+([a-zA-Z0-9_:]+)\s*(\(.*?\))?\s*\{", re.S)
    cls_params: dict[str, set[str]] = {}
    for match in class_re.finditer(text):
        cls = match.group(1)
        params_text = match.group(2)
        params: set[str] = set()
        if params_text:
            params_text = re.sub(r"#.*", "", params_text)
            inner = params_text[1:-1]
            for part in inner.split(","):
                part = part.strip()
                if not part:
                    continue
                m2 = re.search(r"\$([a-zA-Z0-9_]+)", part)
                if m2:
                    params.add(m2.group(1))
        cls_params[cls] = params
    return cls_params


def main() -> int:
    readme_text = README_PATH.read_text()
    readme_params = readme_class_params(readme_text)

    manifest_params: dict[str, set[str]] = {}
    for path in MANIFESTS_DIR.rglob("*.pp"):
        manifest_params.update(manifest_class_params(path.read_text()))

    missing: dict[str, list[str]] = {}
    for cls, params in manifest_params.items():
        if cls in readme_params:
            documented = readme_params.get(cls, set())
            missing_params = sorted(p for p in params if p not in documented)
            if missing_params:
                missing[cls] = missing_params

    for cls in sorted(missing):
        print(cls)
        for param in missing[cls]:
            print(f"  - {param}")

    return 1 if len(missing) > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
