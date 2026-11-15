#!/usr/bin/env python3
"""Police assistance booths on the kerb at big Chennai junctions (Nov 15 owner report: "remove the
traffic police and his umbrella podium from the middle of the roads and place it in the sides …
make sure the names match the area").

A booth goes where TrafficPolice used to stand a podium: junctions where >= 3 roads meet and >= 2
arms are trunk / primary / secondary roads >= 6 m wide, >= 150 m apart. It stands on the nearest
free kerb corner, its front (sign side) to the junction, the constable's spot (OFFICER_M in
front of it) on the kerb too. Each booth carries the code and name of the police station whose
area it is in (tools/osm/police_stations.py, nearest station), like the real "R-1 MAMBALAM
POLICE ASSISTANCE BOOTH".

Output: dress "booths" = [[x, z, yaw, station], ...] (body merged into the chunk mesh + collider by
WorldChunkStreamer._booths; local +Z = front) and data/world/police_booths.json (TrafficPolice:
signs and the constable). Run after build_street_lights.py, before build_plots.py. Idempotent.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_street_dressing import ROAD_RES, road_raster  # noqa: E402
from build_world import project  # noqa: E402
from police_stations import STATIONS  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0
BIG = ("trunk", "primary", "secondary")
MIN_WIDTH_M = 6.0
MIN_SPACING_M = 150.0
BOOTH_W, BOOTH_D = 2.3, 1.8  # with the plinth
OFFICER_M = 1.7
KEEP = {"trees": 1.3, "poles": 0.9, "lamps": 0.9, "parking": 1.6, "stalls": 1.8, "carts": 1.8,
        "xfmr": 2.6, "barricades": 1.0, "beach_fence": 1.0}


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    graph = json.loads((WORLD / "road_graph.json").read_text())
    road, (rox, roz) = road_raster(manifest)

    def road_at(x: float, z: float) -> bool:
        i, j = int((x - rox) / ROAD_RES), int((z - roz) / ROAD_RES)
        return 0 <= j < road.shape[0] and 0 <= i < road.shape[1] and bool(road[j, i])

    nodes = graph["nodes"]
    node_edges: dict = {}
    for ei, e in enumerate(graph["edges"]):
        for n in (e["a"], e["b"]):
            node_edges.setdefault(n, []).append(ei)
    # Same junction rule as the old podiums (TrafficPolice), in the same node order.
    junctions: list = []
    for ni in range(len(nodes)):
        eis = node_edges.get(ni, [])
        if len(eis) < 3:
            continue
        big = sum(1 for ei in eis if graph["edges"][ei]["c"] in BIG and float(graph["edges"][ei]["w"]) >= MIN_WIDTH_M)
        if big < 2:
            continue
        p = nodes[ni]
        if all(math.dist((p[0], p[-1]), (nodes[o][0], nodes[o][-1])) >= MIN_SPACING_M for o in junctions):
            junctions.append(ni)

    blds: dict = {}
    things: dict = {}
    islands: list = []
    dress: dict = {}
    for ch in manifest["chunks"]:
        key = (int(ch[0]), int(ch[1]))
        d = json.loads((WORLD / "chunks" / f"c_{key[0]}_{key[1]}.json").read_text())
        for b in d.get("blds", []):
            p = b["p"]
            poly = [(p[k], p[k + 1]) for k in range(0, len(p), 2)]
            xs, zs = [q[0] for q in poly], [q[1] for q in poly]
            for i in range(int(min(xs) // 20), int(max(xs) // 20) + 1):
                for j in range(int(min(zs) // 20), int(max(zs) // 20) + 1):
                    blds.setdefault((i, j), []).append(poly)
        dp = WORLD / "dress" / f"c_{key[0]}_{key[1]}.json"
        dd = json.loads(dp.read_text()) if dp.exists() else {}
        dd.pop("booths", None)
        dress[key] = dd
        for k, r in KEEP.items():
            for it in dd.get(k, []):
                x, z = float(it[0]), float(it[1])
                things.setdefault((int(x // 20), int(z // 20)), []).append((x, z, r))
        for it in dd.get("islands", []):
            islands.append([(float(it[k]), float(it[k + 1])) for k in range(4, len(it) - 1, 2)])

    def inside(x: float, z: float, poly: list) -> bool:
        c = False
        j = len(poly) - 1
        for i in range(len(poly)):
            if (poly[i][1] > z) != (poly[j][1] > z) and x < (poly[j][0] - poly[i][0]) * (z - poly[i][1]) / (poly[j][1] - poly[i][1]) + poly[i][0]:
                c = not c
            j = i
        return c

    def clear(x: float, z: float) -> bool:
        if road_at(x, z):
            return False
        gi, gj = int(x // 20), int(z // 20)
        for i in (gi - 1, gi, gi + 1):
            for j in (gj - 1, gj, gj + 1):
                for tx, tz, tr in things.get((i, j), ()):
                    if math.hypot(tx - x, tz - z) < tr:
                        return False
        for poly in blds.get((gi, gj), ()):
            if inside(x, z, poly):
                return False
        return not any(inside(x, z, isl) for isl in islands)

    stations = [(code, en, ta, *project(la, lo)) for code, en, ta, la, lo in STATIONS]
    booths: list = []
    missed = 0
    for ni in junctions:
        nx, nz = nodes[ni][0], nodes[ni][-1]
        best = None
        for r10 in range(70, 300, 10):
            r = r10 / 10.0
            for a10 in range(0, 360, 10):
                a = math.radians(a10)
                cx, cz = nx + math.cos(a) * r, nz + math.sin(a) * r
                fx, fz = (nx - cx) / r, (nz - cz) / r  # front: towards the junction
                sx, sz = fz, -fx
                ok = True
                for u in (-0.5, -0.17, 0.17, 0.5):
                    for v in (-0.5, 0.0, 0.5):
                        px = cx + sx * u * (BOOTH_W + 0.6) + fx * v * (BOOTH_D + 0.6)
                        pz = cz + sz * u * (BOOTH_W + 0.6) + fz * v * (BOOTH_D + 0.6)
                        if not clear(px, pz):
                            ok = False
                            break
                    if not ok:
                        break
                # The constable stands on the kerb in front, and the road is right there.
                ox, oz = cx + fx * OFFICER_M, cz + fz * OFFICER_M
                if not ok or not clear(ox, oz) or not any(road_at(cx + fx * k, cz + fz * k) for k in (2.6, 3.2, 3.8, 4.6)):
                    continue
                best = (cx, cz, math.atan2(fx, fz))
                break
            if best:
                break
        if best is None:
            missed += 1
            continue
        cx, cz, yaw = best
        si = min(range(len(stations)), key=lambda i: math.hypot(stations[i][3] - cx, stations[i][4] - cz))
        booths.append([round(cx, 2), round(cz, 2), round(yaw, 3), si, ni])
        things.setdefault((int(cx // 20), int(cz // 20)), []).append((cx, cz, 3.0))
    for b in booths:
        key = (math.floor(b[0] / CHUNK), math.floor(b[1] / CHUNK))
        dress.setdefault(key, {}).setdefault("booths", []).append(b[:4])
    for key, dd in dress.items():
        (WORLD / "dress" / f"c_{key[0]}_{key[1]}.json").write_text(json.dumps(dd, separators=(",", ":")))
    (WORLD / "police_booths.json").write_text(json.dumps({
        "_note": "made by tools/osm/build_police_booths.py: [x, z, yaw, station, junction node]",
        "stations": [[c, en, ta] for c, en, ta, _x, _z in stations],
        "booths": booths}, ensure_ascii=False, separators=(",", ":")))
    used: dict = {}
    for b in booths:
        used[stations[b[3]][0]] = used.get(stations[b[3]][0], 0) + 1
    print(f"police booths: {len(booths)} of {len(junctions)} junctions ({missed} with no free kerb); by station {used}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
