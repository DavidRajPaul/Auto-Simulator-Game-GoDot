#!/usr/bin/env python3
"""Audit generated Chennai building chunks after the OSM Import workflow.

Usage: python3 tools/osm/audit_city_density.py
Read-only; prints building counts by zone and flags invalid footprints.
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text(encoding="utf-8"))
    counts: Counter[str] = Counter()
    fill: Counter[str] = Counter()
    invalid = 0
    total = 0
    for xy in manifest["chunks"]:
        x, z = int(xy[0]), int(xy[1])
        path = WORLD / "chunks" / f"c_{x}_{z}.json"
        if not path.exists():
            print(f"ERROR missing chunk: {path.relative_to(ROOT)}")
            return 1
        chunk = json.loads(path.read_text(encoding="utf-8"))
        for b in chunk.get("blds", []):
            total += 1
            zone = str(b.get("z") or "other")
            counts[zone] += 1
            if b.get("f"):
                fill[zone] += 1
            pts = b.get("p", [])
            if len(pts) < 6 or len(pts) % 2 or float(b.get("h", 0)) <= 0:
                invalid += 1
    print(f"Generated Chennai building audit: {total} building records")
    for zone in sorted(counts):
        print(f"  {zone}: {counts[zone]} total, {fill[zone]} procedural infill")
    print(f"  malformed footprints/heights: {invalid}")
    return 1 if invalid or not total else 0


if __name__ == "__main__":
    raise SystemExit(main())
