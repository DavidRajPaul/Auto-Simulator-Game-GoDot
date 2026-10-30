#!/usr/bin/env python3
"""Repository-wide required asset preflight. Works without installing Godot.

A required file must exist as actual bytes in the repository. Godot's .import
sidecars are auto-generated metadata, NOT a substitute for a missing GLB.
Usage: python3 tools/assets/check_required_assets.py [--root PATH]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ASSET_REF = re.compile(r"""(?P<quote>["'])(?P<path>res://assets/[^"'\r\n]+?)(?P=quote)""")
SKIP_DIRS = {".git", ".godot", "build", "__pycache__", ".venv"}
SCAN_EXTENSIONS = {".gd", ".tscn", ".tres", ".godot", ".cfg"}
MODEL_SUFFIXES = {".glb", ".gltf", ".png", ".jpeg", ".jpg", ".webp",
                  ".svg", ".ogg", ".wav", ".mp3", ".ttf", ".otf", ".tres", ".tscn"}
REGISTRY = Path("tools/assets/required_assets.json")


def path_from_res(uri: str) -> str:
    if not uri.startswith("res://assets/"):
        raise ValueError(f"Not a project asset reference: {uri}")
    rel = uri.removeprefix("res://")
    p = Path(rel)
    if p.is_absolute() or ".." in p.parts:
        raise ValueError(f"Unsafe asset path: {uri}")
    return p.as_posix()


def audit(root: Path) -> tuple[dict[str, set[str]], list[str]]:
    registry = json.loads((root / REGISTRY).read_text(encoding="utf-8"))
    references: dict[str, set[str]] = {}

    def add(uri: str, origin: str) -> None:
        rel = path_from_res(uri)
        references.setdefault(rel, set()).add(origin)

    # Explicit paths from actual source and Godot scene files, not text comments.
    for source in root.rglob("*"):
        if not source.is_file() or any(part in SKIP_DIRS for part in source.relative_to(root).parts):
            continue
        if source.suffix not in SCAN_EXTENSIONS and source.name != "project.godot":
            continue
        if source.stat().st_size > 2_000_000:
            continue
        content = source.read_text(encoding="utf-8", errors="replace")
        for match in ASSET_REF.finditer(content):
            uri = match.group("path")
            # Ignore printf/GDScript template strings such as "res://assets/models/people/%s.glb".
            # Concrete instances are verified through their JSON metadata below.
            if any(x in uri for x in ("%s", "%d", "{", "}")):
                continue
            if Path(uri).suffix.lower() in MODEL_SUFFIXES:
                add(uri, str(source.relative_to(root)))

    # Runtime model paths are constructed dynamically from data/world/city_props.
    props_path = root / "data/world/city_props.json"
    if props_path.exists():
        props = json.loads(props_path.read_text(encoding="utf-8")).get("props", [])
        for i, p in enumerate(props):
            name = p["model"]
            uri = p.get("asset", f"res://assets/models/city/{name}.glb")
            add(uri, f"data/world/city_props.json:props[{i}]")

    # Runtime pedestrian model names come from people.json.
    people_path = root / "assets/models/people/people.json"
    if people_path.exists():
        people = json.loads(people_path.read_text(encoding="utf-8")).get("people", {})
        for id_ in people:
            add(f"res://assets/models/people/{id_}.glb", "assets/models/people/people.json")

    # Explicitly required art that currently has a generated fallback.
    # Optional art remains optional unless added to the registry.
    for item in registry["required"]:
        add(item["path"], "required_assets.json: " + item["purpose"])

    missing = {rel: origins for rel, origins in references.items()
               if not (root / rel).is_file()}
    warnings = []
    # Missing .glb.import is NOT fatal; Godot creates these during --import.
    for rel in references:
        if rel.endswith(".glb") and (root / rel).is_file() and not (root / (rel + ".import")).is_file():
            warnings.append(f"Godot will regenerate import metadata: {rel}.import")
    return missing, warnings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args()
    root = args.root.resolve()
    try:
        missing, warnings = audit(root)
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"ASSET AUDIT ERROR: {exc}", file=sys.stderr)
        return 2
    for message in warnings:
        print("INFO:", message)
    for name, sources in sorted(missing.items()):
        print(f"::error file={name}::Missing required asset: {name}")
        for source in sorted(sources):
            print("   referenced by:", source)
    if missing:
        print(f"FAILED: {len(missing)} required asset file(s) missing")
        return 1
    print("PASSED: every required asset file exists")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
