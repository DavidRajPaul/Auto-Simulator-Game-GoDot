#!/usr/bin/env python3
"""Street life that a Chennai street never goes without: kolams, dogs, festival flags.

Nov 13 2026, owner: "I need the Chennai to be more lively just like the real Chennai".
Adds three keys to every dress file (all merged into the chunk's ONE building mesh at
runtime by WorldChunkStreamer._street_life: no nodes, no draw calls):

* "kolams":  [x, z, yaw, pattern, y]  rice-flour kolam on the ground outside a house gate
             (y = -99: take the drawn ground from the chunk's height raster; else paved plot)
* "dogs":    [x, z, yaw, coat, pose]  a street dog lying or sitting beside a kerb stall
* "bunting": [x0, z0, x1, z1, seed]   festival flag strings along the EB wires near temples
             and churches

Run LAST in a map rebuild, after tools/osm/build_plots.py (it reads the plot gates). It
removes its own keys first, so it can re-run.
Usage: python3 tools/osm/place_street_life.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0

KOLAM_TYPES = {"hs": 0.75, "ah": 0.85, "kp": 0.6, "tn": 0.45, "fl": 0.35, "tp": 1.0}
# Building types with a shop front on their street walls, and how many figure models exist
# (tools/assets/bake_shop_people.py).
SHOP_TYPES = {"sh", "sr", "ht", "bk", "ml"}
SHOP_MODELS = 8
SHOP_BAY_M = 7.0
KOLAM_OUT_M = 1.5          # kolam centre in front of the gate
DOG_SHARE = 0.4            # of kerb stalls
BUNTING_REACH_M = 160.0    # wires this close to a temple / church get flags


def h01(*vals: float) -> float:
    """Deterministic hash in [0, 1) of a few numbers."""
    h = 2166136261
    for v in vals:
        h ^= int(round(v * 100.0)) & 0xFFFFFFFF
        h = (h * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return (h & 0xFFFFFF) / float(0x1000000)


def in_tri(p, a, b, c) -> bool:
    d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
    d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
    d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def on_pave(p, pave: dict) -> bool:
    for part in pave.values():
        v, ix = part["v"], part["i"]
        for t in range(0, len(ix) - 2, 3):
            a, b, c = (v[ix[t] * 2], v[ix[t] * 2 + 1]), (v[ix[t + 1] * 2], v[ix[t + 1] * 2 + 1]), (v[ix[t + 2] * 2], v[ix[t + 2] * 2 + 1])
            if min(a[0], b[0], c[0]) - 0.1 <= p[0] <= max(a[0], b[0], c[0]) + 0.1 and min(a[1], b[1], c[1]) - 0.1 <= p[1] <= max(a[1], b[1], c[1]) + 0.1:
                if in_tri(p, a, b, c):
                    return True
    return False


def main() -> None:
    spots = json.loads((WORLD / "sound_spots.json").read_text())
    holy = [tuple(p) for p in spots.get("temples", []) + spots.get("churches", [])]
    totals = {"kolams": 0, "dogs": 0, "bunting": 0, "shop_people": 0}
    for dress_path in sorted((WORLD / "dress").glob("c_*.json")):
        key = dress_path.stem
        dress = json.loads(dress_path.read_text())
        for k in totals:
            dress.pop(k, None)
        chunk_path = WORLD / "chunks" / f"{key}.json"
        plot_path = WORLD / "plots" / f"{key}.json"
        blds = json.loads(chunk_path.read_text()).get("blds", []) if chunk_path.exists() else []
        plot = json.loads(plot_path.read_text()) if plot_path.exists() else {}
        polys = []
        shops = []
        for b in blds:
            pts = b["p"]
            ring = [(pts[i], pts[i + 1]) for i in range(0, len(pts), 2)]
            if len(ring) >= 3:
                poly = Polygon(ring)
                if poly.is_valid and poly.area > 1.0:
                    polys.append(poly)
                    if b.get("t") in SHOP_TYPES:
                        shops.append((ring, poly, b.get("fw", [])))
        tree = STRtree(polys) if polys else None
        occupied = [Point(float(s[0]), float(s[1])).buffer(1.6) for s in dress.get("stalls", []) + dress.get("carts", [])]
        occupied += [Point(float(p[0]), float(p[1])).buffer(0.6) for p in dress.get("poles", []) + dress.get("trees", [])]
        occupied += [Point(float(p[0]), float(p[1])).buffer(1.2) for p in dress.get("parking", [])]

        def clear(p: Point) -> bool:
            if tree is not None and len(tree.query(p.buffer(0.7), predicate="intersects")) > 0:
                return False
            return not any(o.contains(p) for o in occupied)

        # Kolams outside house gates, on the street side.
        kolams = []
        for g in plot.get("gates", []):
            share = KOLAM_TYPES.get(str(g[6]))
            if share is None or h01(g[7], 3.0) >= share:
                continue
            x0, z0, x1, z1 = (float(v) for v in g[:4])
            mx, mz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
            dx, dz = x1 - x0, z1 - z0
            ln = math.hypot(dx, dz)
            if ln < 0.5:
                continue
            nx, nz = -dz / ln, dx / ln
            best = None
            for sgn in (1.0, -1.0):
                p = Point(mx + nx * sgn * KOLAM_OUT_M, mz + nz * sgn * KOLAM_OUT_M)
                if tree is None:
                    continue
                near = tree.query_nearest(p)
                dist = min(polys[int(i)].distance(p) for i in (near if hasattr(near, "__len__") else [near]))
                if clear(p) and (best is None or dist > best[0]):
                    best = (dist, p, sgn)
            if best is None or best[0] < 1.5:
                continue
            p, sgn = best[1], best[2]
            yaw = math.atan2(nx * sgn, nz * sgn)
            y = 0.012 if on_pave((p.x, p.y), plot.get("pave", {})) else -99.0
            kolams.append([round(p.x, 2), round(p.y, 2), round(yaw, 3), int(h01(g[7], 5.0) * 4), y])
        # Street dogs beside kerb stalls (stall +Z faces the road; the dog lies to one side).
        dogs = []
        for s in dress.get("stalls", []):
            x, z, yaw = float(s[0]), float(s[1]), float(s[2])
            if h01(x, z, 7.0) >= DOG_SHARE:
                continue
            side = 1.0 if h01(x, z, 8.0) < 0.5 else -1.0
            lx, lz = side * 2.2, -0.2
            px = x + lx * math.cos(yaw) + lz * math.sin(yaw)
            pz = z - lx * math.sin(yaw) + lz * math.cos(yaw)
            p = Point(px, pz)
            if tree is not None and len(tree.query(p.buffer(0.6), predicate="intersects")) > 0:
                continue
            dogs.append([round(px, 2), round(pz, 2), round(yaw + (h01(x, z, 9.0) - 0.5) * 2.4, 3),
                int(h01(x, z, 10.0) * 4), 0 if h01(x, z, 11.0) < 0.7 else 1])
        # Festival flags on the wires near temples and churches.
        bunting = []
        for w in dress.get("wires", []):
            mx, mz = (float(w[0]) + float(w[2])) * 0.5, (float(w[1]) + float(w[3])) * 0.5
            if any(math.hypot(mx - hx, mz - hz) < BUNTING_REACH_M for hx, hz in holy):
                bunting.append([float(w[0]), float(w[1]), float(w[2]), float(w[3]), int(h01(mx, mz, 12.0) * 1000)])
        # A shopkeeper at every shop front, and one or two customers facing the shop:
        # [x, z, yaw, model, kind] (kind 0 shopkeeper, 1 customer, 2 stall vendor).
        people = []
        for ring, poly, fw in shops:
            for wall in fw:
                i = int(wall[0])
                (ax, az), (bx, bz) = ring[i % len(ring)], ring[(i + 1) % len(ring)]
                ln = math.hypot(bx - ax, bz - az)
                if ln < 3.0:
                    continue
                tx, tz = (bx - ax) / ln, (bz - az) / ln
                nx, nz = -tz, tx
                if poly.contains(Point((ax + bx) * 0.5 + nx * 0.6, (az + bz) * 0.5 + nz * 0.6)):
                    nx, nz = -nx, -nz
                bays = max(1, int(round(ln / SHOP_BAY_M)))
                for k in range(bays):
                    c = (k + 0.5) / bays * ln
                    cx, cz = ax + tx * c, az + tz * c
                    out_yaw = math.atan2(nx, nz)
                    spots = [(0.35 * (h01(cx, cz, 20.0) - 0.5), 0.8, out_yaw, 0)]
                    for q in range(1 + int(h01(cx, cz, 21.0) * 2.2)):
                        side = (h01(cx, cz, 22.0 + q) - 0.5) * 2.6
                        spots.append((side, 1.55 + 0.6 * h01(cx, cz, 25.0 + q), out_yaw + math.pi + (h01(cx, cz, 28.0 + q) - 0.5) * 0.9, 1))
                    for (along, out, yaw, kind) in spots:
                        p = Point(cx + tx * along + nx * out, cz + tz * along + nz * out)
                        if not clear(p) or any(p.distance(Point(q[0], q[1])) < 0.6 for q in people[-6:]):
                            continue
                        people.append([round(p.x, 2), round(p.y, 2), round(yaw, 2), int(h01(p.x, p.y, 31.0) * SHOP_MODELS), kind])
        for st in dress.get("stalls", []):
            x, z, yaw = float(st[0]), float(st[1]), float(st[2])
            lx, lz = 0.35, -0.55
            people.append([round(x + lx * math.cos(yaw) + lz * math.sin(yaw), 2), round(z - lx * math.sin(yaw) + lz * math.cos(yaw), 2),
                round(yaw, 2), int(h01(x, z, 32.0) * SHOP_MODELS), 2])
        if people:
            dress["shop_people"] = people
        totals["shop_people"] += len(people)
        if kolams:
            dress["kolams"] = kolams
        if dogs:
            dress["dogs"] = dogs
        if bunting:
            dress["bunting"] = bunting
        totals["kolams"] += len(kolams)
        totals["dogs"] += len(dogs)
        totals["bunting"] += len(bunting)
        dress_path.write_text(json.dumps(dress, separators=(",", ":")))
    print("street life:", totals)


if __name__ == "__main__":
    main()
