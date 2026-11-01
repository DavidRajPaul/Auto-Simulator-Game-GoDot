#!/usr/bin/env python3
"""Street dressing for every world chunk: EB electric poles with sagging overhead wires, TNEB
distribution transformers, and roadside trees (rain trees, neem, Ashoka mast trees, copper-pod;
coconut palms mainly by the beach).

Transformers: Chennai's pole-mounted distribution transformers stand on a double-pole (DP)
structure in the EB pole line. A few poles (one per XFMR_SPACING metres at most, where the kerb
has room) become such a structure: "xfmr": [x, z, yaw, ox, oz] = the pole-line centre, the road
direction (as for poles) and the unit vector away from the road (the tank sits that way, clear
of the carriageway). The chunk streamer builds the poles, platform, AB switch, DO fuses,
lightning arresters, drop wires, LT box and earthing and merges the baked tank
(assets/models/city/eb_transformer.glb) into the chunk mesh.

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
XFMR_SPACING = 280.0   # m between transformer structures (dense residential Chennai: ~1 per 200-400 m)
XFMR_HALF_SPAN = 1.3   # the DP structure's poles stand this far either side of the centre
XFMR_OUT = 0.55        # tank centre this far behind the pole line (away from the road)
XFMR_CLASSES = ("primary", "secondary", "tertiary", "residential")
# Chennai's street trees are mostly rain trees, neem, Ashoka (mast) trees and copper-pod /
# gulmohar; coconut palms belong to the beach front and the odd temple/house compound.
# Palms: 30 % within BEACH_PALM_M of the sand, 5 % in Mylapore, 2 % everywhere else.
PALM_ZONES = {"mylapore": 0.05}
PALM_DEFAULT = 0.02
PALM_BEACH = 0.3
BEACH_PALM_M = 200.0
# Non-palm mix: 0 rain/neem, 2 mast, 3 copperpod, 4 pungai, 5 gulmohar.
# These are visual design weights, not surveyed species counts.
SPECIES = [(0, 0.30), (2, 0.18), (3, 0.15), (4, 0.27), (5, 0.10)]


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
    # Carriageway segments on a 40 m grid: transformer structures must stay off every road
    # (a pole at one road's kerb can still be inside the mouth of a side road).
    sgrid: dict = {}
    for e in graph["edges"]:
        pts = e["pts"]
        for i in range(1, len(pts)):
            sg = (pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], float(e["w"]) * 0.5)
            r = sg[4] + 2.0
            for gi in range(int((min(sg[0], sg[2]) - r) // 40), int((max(sg[0], sg[2]) + r) // 40) + 1):
                for gj in range(int((min(sg[1], sg[3]) - r) // 40), int((max(sg[1], sg[3]) + r) // 40) + 1):
                    sgrid.setdefault((gi, gj), []).append(sg)

    def road_gap(x: float, z: float) -> float:
        best = 1e9
        for ax, az, bx, bz, hw in sgrid.get((int(x // 40), int(z // 40)), []):
            dx, dz = bx - ax, bz - az
            L = dx * dx + dz * dz
            t = 0.0 if L == 0 else max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / L))
            best = min(best, math.hypot(x - (ax + dx * t), z - (az + dz * t)) - hw)
        return best

    rng = random.Random(600017)
    out: dict = {}

    def put(kind: str, x: float, z: float, item: list) -> None:
        key = (math.floor(x / size), math.floor(z / size))
        out.setdefault(key, {"poles": [], "wires": [], "trees": []})[kind].append(item)

    xfmr_cands: list = []  # (x, z, yaw, ox, oz, pole item) - picked after all poles exist

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
                item = [round(px, 2), round(pz, 2), round(yaw, 3)]
                put("poles", px, pz, item)
                if cls in XFMR_CLASSES:
                    xfmr_cands.append((px, pz, yaw, lx, lz, dx, dz, item))
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

    # Transformers: own RNG so the poles/trees above stay exactly as before.
    xr = random.Random(600028)
    xr.shuffle(xfmr_cands)
    picked: list = []
    pgrid: dict = {}
    for px, pz, yaw, ox, oz, dx, dz, item in xfmr_cands:
        cell = (int(px // XFMR_SPACING), int(pz // XFMR_SPACING))
        if any(math.hypot(px - q[0], pz - q[1]) < XFMR_SPACING
               for i in (-1, 0, 1) for j in (-1, 0, 1) for q in pgrid.get((cell[0] + i, cell[1] + j), [])):
            continue
        tx, tz = px + ox * XFMR_OUT, pz + oz * XFMR_OUT
        feet = [(px + dx * XFMR_HALF_SPAN, pz + dz * XFMR_HALF_SPAN), (px - dx * XFMR_HALF_SPAN, pz - dz * XFMR_HALF_SPAN)]
        if blocked(tx, tz, 1.0) or blocked(tx + ox * 0.6, tz + oz * 0.6, 0.4) or any(blocked(fx, fz, 0.35) for fx, fz in feet):
            continue
        # Pole line, both feet and the tank's road-side corners all clear of every carriageway.
        edge = [(px, pz)] + feet + [(px + ox * 0.03 + dx * s * 0.87, pz + oz * 0.03 + dz * s * 0.87) for s in (-1.0, 1.0)]
        if min(road_gap(x, z) for x, z in edge) < 0.25:
            continue
        key = (math.floor(px / size), math.floor(pz / size))
        out[key]["poles"].remove(item)  # the DP structure replaces this pole; its wires stay
        out[key].setdefault("xfmr", []).append([round(px, 2), round(pz, 2), round(yaw, 3), round(ox, 3), round(oz, 3)])
        pgrid.setdefault(cell, []).append((px, pz))
        picked.append((px, pz))

    OUT.mkdir(parents=True, exist_ok=True)
    for f in OUT.glob("c_*.json"):
        f.unlink()
    totals = {"poles": 0, "wires": 0, "trees": 0, "xfmr": 0}
    for (i, j), d in out.items():
        (OUT / f"c_{i}_{j}.json").write_text(json.dumps(d, separators=(",", ":")))
        for k in totals:
            totals[k] += len(d.get(k, []))
    print(f"{len(out)} chunks, {totals}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
