#!/usr/bin/env python3
"""Fail when a template references a .Values path that values.yaml does not
declare. A strict generated schema (additionalProperties: false) silently
disables any feature whose key is missing from values.yaml — this audit is the
guard Authelia's chart lacked when its HPA metrics became dead code.

A reference resolves when every dot segment walks through the parsed values
tree; a path that lands in a free-form map (an empty {} or any non-mapping
leaf) is considered covered by that map.
"""
import re
import sys
from pathlib import Path

chart = Path(sys.argv[1] if len(sys.argv) > 1 else "charts/authup")
raw = (chart / "values.yaml").read_text()

try:
    import yaml
    values = yaml.safe_load(raw) or {}
    deep = True
except ImportError:
    # Degraded mode without PyYAML (CI runners ship it): top-level keys only.
    print("WARNING: PyYAML unavailable — checking top-level keys only", file=sys.stderr)
    values = {m.group(1): {} for m in re.finditer(r"^([a-zA-Z0-9_]+):", raw, re.M)}
    deep = False

refs = set()
pattern = re.compile(r"\.Values\.([a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)*)")
for tpl in chart.glob("templates/**/*"):
    if tpl.is_file():
        refs.update(pattern.findall(tpl.read_text()))

failures = []
for ref in sorted(refs):
    node = values
    for segment in ref.split("."):
        if isinstance(node, dict):
            if segment in node:
                node = node[segment]
            elif len(node) == 0 and (deep or node is not values):
                break  # free-form map covers its children
            else:
                failures.append(ref)
                break
        else:
            break  # non-mapping leaf covers deeper access (lists, scalars)

if failures:
    for ref in failures:
        print(f"MISSING values key referenced by templates: {ref}")
    sys.exit(1)
print(f"values coverage OK ({len(refs)} referenced paths)")
