#!/usr/bin/env python3
"""Clear the ground where a procedural landmark model stands (tools/art/make_landmarks.py).

data/world/landmark_models.json lists each model's "clear" outline (world x, z). Chunk buildings
whose centroid lies inside one are removed (the San Thome Basilica footprint was drawn as a
kaavi-striped temple block; the Kapaleeshwarar compound held flats and shops standing in for its
shrines), and so are dress points inside it: trees, parked vehicles, stalls, shop people, kolams
and dogs. Idempotent. Run it after anything that rewrites chunks or dress files, then
classify_buildings.py -> build_plots.py -> build_landmark_compounds.py:
    python3 tools/osm/clear_landmark_sites.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
POINT_KEYS = ("trees", "parking", "stalls", "shop_people", "kolams", "dogs")


def inside(x: float, z: float, poly) -> bool:
    hit = False
    n = len(poly)
    for i in range(n):
        (x0, z0), (x1, z1) = poly[i - 1], poly[i]
        if (z0 > z) != (z1 > z) and x < x0 + (z - z0) * (x1 - x0) / (z1 - z0):
            hit = not hit
    return hit


def main() -> int:
    models = json.loads((WORLD / "landmark_models.json").read_text())["models"]
    polys = [m["clear"] for m in models if len(m.get("clear", [])) >= 3]
    size = float(json.loads((WORLD / "manifest.json").read_text())["chunk_size"])
    chunks = set()
    for poly in polys:
        xs = [p[0] for p in poly]
        zs = [p[1] for p in poly]
        for i in range(int(math.floor(min(xs) / size)), int(math.floor(max(xs) / size)) + 1):
            for j in range(int(math.floor(min(zs) / size)), int(math.floor(max(zs) / size)) + 1):
                chunks.add((i, j))
    gone_b = 0
    gone_d = 0
    for i, j in sorted(chunks):
        f = WORLD / "chunks" / f"c_{i}_{j}.json"
        if f.exists():
            d = json.loads(f.read_text())
            keep = []
            for b in d.get("blds", []):
                p = b["p"]
                n = len(p) // 2
                cx, cz = sum(p[0::2]) / n, sum(p[1::2]) / n
                if any(inside(cx, cz, poly) for poly in polys):
                    gone_b += 1
                else:
                    keep.append(b)
            if len(keep) != len(d.get("blds", [])):
                d["blds"] = keep
                f.write_text(json.dumps(d, separators=(",", ":")))
        f = WORLD / "dress" / f"c_{i}_{j}.json"
        if f.exists():
            d = json.loads(f.read_text())
            changed = False
            for key in POINT_KEYS:
                items = d.get(key, [])
                kept = [it for it in items if not any(inside(float(it[0]), float(it[1]), poly) for poly in polys)]
                if len(kept) != len(items):
                    gone_d += len(items) - len(kept)
                    d[key] = kept
                    changed = True
            if changed:
                f.write_text(json.dumps(d, separators=(",", ":")))
    print(f"landmark sites cleared: {gone_b} buildings, {gone_d} dress points")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
