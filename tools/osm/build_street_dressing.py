#!/usr/bin/env python3
"""Street dressing for every world chunk: EB electric poles with sagging overhead wires, and
roadside trees (rain trees, neem, Ashoka mast trees, copper-pod; coconut palms mainly by the beach).

Placed along the real road graph on the kerb, kept out of junction mouths and building
footprints. Written per chunk to data/world/dress/c_<i>_<j>.json and merged by the chunk
streamer into the chunk's single building mesh (no extra draw calls).

Re-run after an OSM rebuild:  python3 tools/osm/build_street_dressing.py
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
OUT = WORLD / "dress"

POLE_STEP = {"primary": 34.0, "secondary": 34.0, "tertiary": 36.0, "residential": 38.0, "living_street": 40.0}
TREE_STEP = {"primary": 26.0, "secondary": 24.0, "tertiary": 22.0, "residential": 20.0, "living_street": 22.0}
JUNCTION_CLEAR = 11.0
POLE_KERB = 0.55
TREE_KERB = 1.7
# Chennai's street trees are mostly rain trees, neem, Ashoka (mast) trees and copper-pod /
# gulmohar; coconut palms belong to the beach front and the odd temple/house compound.
# Palms: 30 % within BEACH_PALM_M of the sand, 5 % in Mylapore, 2 % everywhere else.
PALM_ZONES = {"mylapore": 0.05}
PALM_DEFAULT = 0.02
PALM_BEACH = 0.3
BEACH_PALM_M = 200.0
# Non-palm species mix: 0 rain tree / neem, 2 Ashoka (mast tree), 3 copper-pod / gulmohar.
SPECIES = [(0, 0.55), (2, 0.25), (3, 0.20)]


def point_in(px, pz, poly) -> bool:
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / (zj - zi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    size = float(manifest["chunk_size"])
    zones = manifest["zones"]
    # Building footprints in a coarse grid for "is this spot inside a building" checks.
    grid: dict = {}
    for c in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{c[0]}_{c[1]}.json").read_text())
        for b in d.get("blds", []):
            p = b["p"]
            pts = [(p[i], p[i + 1]) for i in range(0, len(p), 2)]
            xs = [q[0] for q in pts]
            zs = [q[1] for q in pts]
            for i in range(int(min(xs) // 40), int(max(xs) // 40) + 1):
                for j in range(int(min(zs) // 40), int(max(zs) // 40) + 1):
                    grid.setdefault((i, j), []).append(pts)

    def blocked(x: float, z: float, r: float) -> bool:
        for poly in grid.get((int(x // 40), int(z // 40)), []):
            for dx, dz in ((0, 0), (r, 0), (-r, 0), (0, r), (0, -r)):
                if point_in(x + dx, z + dz, poly):
                    return True
        return False

    def zone_of(x: float, z: float) -> str:
        best, bd = "", 1e9
        for zz in zones:
            d = math.hypot(x - zz["x"], z - zz["z"])
            if d < zz["r"] and d < bd:
                best, bd = zz["id"], d
        return best

    areas = json.loads((WORLD / "areas.json").read_text())
    beach_pts = [p for poly in areas.get("beach", []) for p in poly]

    def near_beach(x: float, z: float) -> bool:
        return any(abs(x - p[0]) < BEACH_PALM_M and abs(z - p[1]) < BEACH_PALM_M and math.hypot(x - p[0], z - p[1]) < BEACH_PALM_M
                   for p in beach_pts)

    def species(x: float, z: float) -> int:
        chance = PALM_BEACH if near_beach(x, z) else PALM_ZONES.get(zone_of(x, z), PALM_DEFAULT)
        if rng.random() < chance:
            return 1
        r = rng.random()
        for kind, w in SPECIES:
            if r < w:
                return kind
            r -= w
        return 0

    graph = json.loads((WORLD / "road_graph.json").read_text())
    rng = random.Random(600017)
    out: dict = {}

    def put(kind: str, x: float, z: float, item: list) -> None:
        key = (math.floor(x / size), math.floor(z / size))
        out.setdefault(key, {"poles": [], "wires": [], "trees": []})[kind].append(item)

    for e in graph["edges"]:
        cls = e["c"]
        if cls not in POLE_STEP:
            continue
        pts = e["pts"]
        seg = [math.dist(pts[i - 1], pts[i]) for i in range(1, len(pts))]
        length = sum(seg)
        if length < 2 * JUNCTION_CLEAR + 4:
            continue
        half = float(e["w"]) * 0.5

        def at(s: float):
            for i, L in enumerate(seg):
                if s <= L or i == len(seg) - 1:
                    t = min(max(s / max(L, 1e-6), 0.0), 1.0)
                    a, b = pts[i], pts[i + 1]
                    dx, dz = (b[0] - a[0]) / max(L, 1e-6), (b[1] - a[1]) / max(L, 1e-6)
                    return a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, dx, dz
                s -= L
            return pts[-1][0], pts[-1][1], 1.0, 0.0

        # Poles on one side (EB lines usually run down one kerb), wires between neighbours.
        side = 1.0 if rng.random() < 0.5 else -1.0
        step = POLE_STEP[cls]
        prev = None
        s = JUNCTION_CLEAR
        while s <= length - JUNCTION_CLEAR:
            x, z, dx, dz = at(s)
            lx, lz = dz * side, -dx * side
            px, pz = x + lx * (half + POLE_KERB), z + lz * (half + POLE_KERB)
            if not blocked(px, pz, 0.3):
                yaw = math.atan2(dx, dz)
                put("poles", px, pz, [round(px, 2), round(pz, 2), round(yaw, 3)])
                if prev is not None and math.dist(prev, (px, pz)) < step * 1.6:
                    put("wires", px, pz, [round(prev[0], 2), round(prev[1], 2), round(px, 2), round(pz, 2)])
                prev = (px, pz)
            else:
                prev = None
            s += step * rng.uniform(0.9, 1.1)
        # Trees on the other kerb (and some on both on wide roads).
        tstep = TREE_STEP[cls]
        s = JUNCTION_CLEAR + rng.uniform(0, tstep)
        while s <= length - JUNCTION_CLEAR:
            x, z, dx, dz = at(s)
            tside = -side if (half < 6.0 or rng.random() < 0.7) else side
            lx, lz = dz * tside, -dx * tside
            off = half + TREE_KERB + rng.uniform(0.0, 0.8)
            tx, tz = x + lx * off, z + lz * off
            if rng.random() < 0.8 and not blocked(tx, tz, 1.4):
                put("trees", tx, tz, [round(tx, 2), round(tz, 2), species(tx, tz), round(rng.uniform(0.8, 1.25), 2),
                                      rng.randrange(1000)])
            s += tstep * rng.uniform(0.7, 1.3)

    OUT.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("c_*.json"):
        f.unlink()
    totals = {"poles": 0, "wires": 0, "trees": 0}
    for (i, j), d in out.items():
        (OUT / f"c_{i}_{j}.json").write_text(json.dumps(d, separators=(",", ":")))
        for k in totals:
            totals[k] += len(d[k])
    print(f"{len(out)} chunks, {totals}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
