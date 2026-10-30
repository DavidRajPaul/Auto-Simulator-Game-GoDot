#!/usr/bin/env python3
"""Data validation after the ordered expansion pipeline, before Git commit.

The graph, visuals, named streets and model placement must all cover Central/Ripon.
This checks deterministic map artifacts; Android collision and FPS still require playtesting.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CENTRAL = (13.0827, 80.2757)
RIPON = (13.0817545, 80.2716236)
ORIGIN = (13.049, 80.259)
M_LAT = 110540.0
M_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))


def xy(lat: float, lon: float) -> tuple[float, float]:
    return (lon - ORIGIN[1]) * M_LON, -(lat - ORIGIN[0]) * M_LAT


def segment_dist(x: float, z: float, a: list, b: list) -> float:
    dx, dz = float(b[0]) - float(a[0]), float(b[1]) - float(a[1])
    d2 = dx * dx + dz * dz
    t = max(0.0, min(1.0, ((x - float(a[0])) * dx + (z - float(a[1])) * dz) / d2)) if d2 else 0.0
    return math.hypot(x - (float(a[0]) + t * dx), z - (float(a[1]) + t * dz))


def run() -> None:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    graph = json.loads((WORLD / "road_graph.json").read_text())
    props = json.loads((WORLD / "city_props.json").read_text())["props"]
    signs = json.loads((WORLD / "street_signs.json").read_text())
    boards = json.loads((WORLD / "building_names.json").read_text())
    bounds = manifest["bounds"]
    assert len(graph["edges"]) > 0 and len(manifest["chunks"]) > 0, "Empty road network"
    assert len(signs) > 0 and len(boards) > 0, "No generated street or building names"
    assert any(str(e.get("n", "")).strip() for e in graph["edges"]), "Road names were lost"

    for name, geo in (("chennai_central", CENTRAL), ("ripon_building", RIPON)):
        x, z = xy(*geo)
        assert bounds[0] < x < bounds[2] and bounds[1] < z < bounds[3], (
            f"{name} lies outside generated playable map bounds: {bounds}")
        assert any(p["model"] == name and abs(p["x"] - x) < 2.0
                   and abs(p["z"] - z) < 2.0 and not p.get("skyline", False)
                   for p in props), f"{name} absent from physical city props"

        nearby = float("inf")
        for e in graph["edges"]:
            pts = e["pts"]
            for i in range(1, len(pts)):
                nearby = min(nearby, segment_dist(x, z, pts[i - 1], pts[i]))
        assert nearby < 220.0, f"{name}: no drivable road within 220 m; nearest {nearby:.0f} m"
        print(f"{name}: world=({x:.1f}, {z:.1f}), closest road {nearby:.1f} m")
    print(f"Verified {len(manifest['chunks'])} chunks; {len(graph['edges'])} edges; "
          f"{len(signs)} signs; {len(boards)} building boards; "
          f"{sum(1 for p in props if p.get('generated_safety_barrier'))} new roadside barriers")


if __name__ == "__main__":
    run()
