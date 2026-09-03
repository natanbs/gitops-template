#!/usr/bin/env python3
"""secrets-vault-standard/align-plan.py — VS-004 path-alignment planner.

Consumes ExternalSecret YAML under an app path and emits a line-number-precise
migration plan so the orchestrator (align-fleet.sh) can rewrite only the
`key:`/`extract:` values without touching comments or formatting.

Output: TSV rows, one per reference:
  FILE<TAB>LINE<TAB>KIND(key|extract)<TAB>OLDKEY<TAB>PROPERTY<TAB>TARGET<TAB>NEWKEY<TAB>STATUS
STATUS is one of:
  CONFORM  already matches /<env>/<service>/<key> (newkey == oldkey)
  ALIGN    newkey computed (leading slash + >=3 segments)
  SKIP     cannot be auto-aligned (needs env/service context); newkey empty

None of the output is authoritative about Vault layout; it only reflects what
the ExternalSecret manifests declare. See align-fleet.sh for vault migration.
"""
import re
import sys
from pathlib import Path

M = re.compile(r"^\s*(?:-\s*)?(key|extract|remoteRef|property|target|name):\s*(\S*)\s*$")
PROP = re.compile(r"^\s*(?:-\s*)?property:\s*(\S+)\s*$")
NAME = re.compile(r"^\s*(?:-\s*)?name:\s*(\S+)\s*$")
KIND_ES = re.compile(r"^\s*kind:\s*ExternalSecret\s*$")


def canonical(path: str) -> str:
    segs = [s for s in path.strip().strip("/").split("/") if s]
    return "/" + "/".join(segs) if segs else ""


def align(key: str, prop: str, target: str) -> str:
    base = canonical(key)
    segs = [s for s in base.split("/") if s]
    if len(segs) >= 3:
        return base
    leaf = prop if (key and prop) else (target if target else "")
    for part in [p for p in leaf.split("/") if p]:
        if len(segs) >= 3:
            break
        segs.append(part)
    if len(segs) >= 3:
        return "/" + "/".join(segs)
    return ""


def plan_file(path: Path):
    lines = path.read_text().splitlines()
    rows = []
    pending = None  # "remoteRef" | "extract"
    in_target = False
    target = ""
    for lineno, raw in enumerate(lines, start=1):
        if KIND_ES.match(raw):
            target = ""
            in_target = False
        if not raw.strip():
            pending = None
            in_target = False
            continue
        m = M.match(raw)
        if not m:
            continue
        token, value = m.group(1), m.group(2)
        if token == "target":
            pending = None
            in_target = True
            continue
        if token == "name" and in_target and value:
            target = value.strip("\"'")
            in_target = False
            continue
        if token == "key" and value:
            kind = "extract" if pending == "extract" else "key"
            prop = ""
            if lineno < len(lines):
                pm = PROP.match(lines[lineno])
                if pm:
                    prop = pm.group(1)
            old = value.strip("\"'")
            new = align(old, prop, target)
            if new and new == canonical(old):
                status = "CONFORM"
            elif new:
                status = "ALIGN"
            else:
                status = "SKIP"
            prop = prop if prop else "-"
            target = target if target else "-"
            new = new if new else "-"
            rows.append(f"{path}\t{lineno}\t{kind}\t{old}\t{prop}\t{target}\t{new}\t{status}")
            pending = None
            continue
        if token == "remoteRef":
            pending = "remoteRef"
            in_target = False
            continue
        if token == "extract":
            pending = "extract"
            in_target = False
            continue
        if token == "property":
            continue
    return rows


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("usage: align-plan.py <app_path>\n")
        return 2
    root = Path(argv[0])
    if not root.is_dir():
        sys.stderr.write(f"align-plan: not a directory: {root}\n")
        return 2
    found = False
    for f in sorted(root.rglob("*")):
        if not (f.is_file() and f.suffix in (".yaml", ".yml")):
            continue
        text = f.read_text(errors="replace")
        if re.search(r"(?m)^\s*kind:\s*ExternalSecret\s*$", text) is None:
            continue
        found = True
        for row in plan_file(f):
            print(row)
    if not found:
        sys.stderr.write(f"align-plan: no ExternalSecret manifests under {root}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))