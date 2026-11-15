#!/usr/bin/env python3
"""Street light poles along Chennai's roads (Nov 15 owner report: "there does not seem to be street
light posts … the light from the street lights must be very photo realistic").

How Chennai lights its roads, and what this pass places:
  * divided arterials (Anna Salai, Kamarajar Salai, Radhakrishnan Salai …): tall double-arm LED
    poles down the centre median, one every MEDIAN_SPACING_M        -> type 1
  * undivided main roads (trunk / primary / secondary): single-arm poles on the kerb, staggered
    from side to side every KERB_SPACING_M                          -> type 0
  * smaller streets: a lamp bracket on each concrete EB pole (the city hangs its LED fittings on
    the TNEB poles)                                     -> type 2

Every pole stands off the DRAWN carriageway (flyover decks included), off buildings and clear of
trees, EB poles, parked vehicles, stalls, carts and transformers.

Output: dress "lamps" = [[x, z, yaw, type, reach], ...]. yaw is the arm's direction for types 0 / 2
(towards the road) and the road's direction for type 1 (arms go out both sides). reach = arm length
in metres. Drawn by WorldChunkStreamer._lamps (pole + arm + fitting, merged into the chunk mesh and
collider) and lit at night by scripts/world/StreetLights.gd. Idempotent.
Run after build_road_works.py / build_roundabouts.py, before build_police_booths.py and build_plots.py.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_street_dressing import ROAD_RES, road_raster, road_tris  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0
MEDIAN_SPACING_M = 32.0
KERB_SPACING_M = 30.0
JUNCTION_CLEAR_M = 9.0
MAIN = ("trunk", "primary", "secondary")
BRACKET_CLASSES = ("tertiary", "residential", "unclassified", "living_street", "service")
# Clearance (m) a new pole keeps from what already stands on the kerb.
KEEP = {"trees": 1.6, "poles": 2.2, "parking": 1.6, "stalls": 2.0, "carts": 2.0, "xfmr": 3.0,
        "barricades": 1.0}
TYPE_KERB, TYPE_MEDIAN, TYPE_BRACKET = 0, 1, 2


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    graph = json.loads((WORLD / "road_graph.json").read_text())
    road, (rox, roz) = road_raster(manifest)
    exact = road_tris(manifest)  # the raster can miss a sliver at a road edge

    def on_road(x: float, z: float, r: float = 0.0) -> bool:
        i0, j0 = int((x - r - rox) / ROAD_RES), int((z - r - roz) / ROAD_RES)
        i1, j1 = int((x + r - rox) / ROAD_RES) + 1, int((z + r - roz) / ROAD_RES) + 1
        if i1 <= 0 or j1 <= 0 or i0 >= road.shape[1] or j0 >= road.shape[0]:
            return False
        return bool(road[max(j0, 0):j1, max(i0, 0):i1].any())

    # Buildings and kerb things in a 20 m grid.
    blds: dict = {}
    things: dict = {}
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
        dd.pop("lamps", None)
        dress[key] = dd
        for k, r in KEEP.items():
            for it in dd.get(k, []):
                x, z = float(it[0]), float(it[1])
                things.setdefault((int(x // 20), int(z // 20)), []).append((x, z, r))

    def inside(x: float, z: float, poly: list) -> bool:
        c = False
        j = len(poly) - 1
        for i in range(len(poly)):
            if (poly[i][1] > z) != (poly[j][1] > z) and x < (poly[j][0] - poly[i][0]) * (z - poly[i][1]) / (poly[j][1] - poly[i][1]) + poly[i][0]:
                c = not c
            j = i
        return c

    def blocked(x: float, z: float, r: float) -> bool:
        gi, gj = int(x // 20), int(z // 20)
        for i in (gi - 1, gi, gi + 1):
            for j in (gj - 1, gj, gj + 1):
                for tx, tz, tr in things.get((i, j), ()):
                    if math.hypot(tx - x, tz - z) < tr + r:
                        return True
        for dx, dz in ((0, 0), (r, 0), (-r, 0), (0, r), (0, -r)):
            for poly in blds.get((int((x + dx) // 20), int((z + dz) // 20)), ()):
                if inside(x + dx, z + dz, poly):
                    return True
        return False

    lamps: list = []

    def add(x: float, z: float, yaw: float, kind: int, reach: float) -> None:
        if exact.hit(x, z, 0.2):
            return
        lamps.append([round(x, 2), round(z, 2), round(yaw, 3), kind, round(reach, 2)])
        things.setdefault((int(x // 20), int(z // 20)), []).append((x, z, 2.0))

    def walk(pts: list, spacing: float, start: float):
        """Points every `spacing` m along a polyline: (x, z, ux, uz)."""
        seg = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
        total = sum(seg)
        s = start
        while s < total - JUNCTION_CLEAR_M:
            along = s
            for i, L in enumerate(seg):
                if along <= L or i == len(seg) - 1:
                    t = 0.0 if L < 1e-6 else min(1.0, along / L)
                    a, b = pts[i], pts[i + 1]
                    yield a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, (b[0] - a[0]) / max(L, 1e-6), (b[1] - a[1]) / max(L, 1e-6)
                    break
                along -= L
            s += spacing

    # 1. Double-arm LED poles down the medians of divided roads.
    median_n = 0
    for key, dd in dress.items():
        for med in dd.get("medians", []):
            pts = [(med[k], med[k + 1]) for k in range(1, len(med) - 2, 3)]
            widths = [med[k + 2] for k in range(1, len(med) - 2, 3)]
            if len(pts) < 2 or sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)) < 30.0:
                continue
            for x, z, ux, uz in walk(pts, MEDIAN_SPACING_M, MEDIAN_SPACING_M * 0.5):
                if min(widths) < 0.5:
                    continue
                # Slide along the median past a palm or a gap in it.
                for shift in (0.0, 3.0, -3.0, 6.0, -6.0):
                    px, pz = x + ux * shift, z + uz * shift
                    if not on_road(px, pz, 0.15) and not blocked(px, pz, 0.3):
                        add(px, pz, math.atan2(ux, uz), TYPE_MEDIAN, 2.2)
                        median_n += 1
                        break

    # 2. Single-arm kerb poles along undivided main roads (divided ones are lit from the median).
    median_pts = [(l[0], l[1]) for l in lamps]
    mgrid: dict = {}
    for x, z in median_pts:
        mgrid.setdefault((int(x // 40), int(z // 40)), []).append((x, z))

    def near_median_lamp(x: float, z: float, r: float) -> bool:
        gi, gj = int(x // 40), int(z // 40)
        return any(math.hypot(px - x, pz - z) < r for i in (gi - 1, gi, gi + 1) for j in (gj - 1, gj, gj + 1)
                   for px, pz in mgrid.get((i, j), ()))

    kerb_n = 0
    for ei, e in enumerate(graph["edges"]):
        if e["c"] not in MAIN:
            continue
        pts = e["pts"]
        half = float(e["w"]) * 0.5
        side = 1 if ei % 2 == 0 else -1
        for x, z, ux, uz in walk(pts, KERB_SPACING_M, JUNCTION_CLEAR_M + (ei * 7.3) % KERB_SPACING_M):
            if near_median_lamp(x, z, 30.0):
                continue  # this road is lit from its median
            nx, nz = uz * side, -ux * side
            spot = None
            for extra in (0.6, 1.1, 1.6, 2.2, 2.8, 3.5):
                px, pz = x + nx * (half + extra), z + nz * (half + extra)
                if not on_road(px, pz, 0.35):
                    spot = (px, pz, half + extra)
                    break
            side = -side  # staggered: next pole on the other kerb
            if spot is None or blocked(spot[0], spot[1], 0.3):
                continue
            # The arm reaches back over the carriageway (towards the centre line).
            reach = max(1.2, min(3.0, (spot[2] - 0.3) * 0.45))
            add(spot[0], spot[1], math.atan2(-nx, -nz), TYPE_KERB, reach)
            kerb_n += 1

    # 3. LED brackets on every other EB pole along smaller streets.
    egrid: dict = {}
    for ei, e in enumerate(graph["edges"]):
        if e["c"] not in BRACKET_CLASSES:
            continue
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // 30) - 1, int(max(a[0], b[0]) // 30) + 2):
                for j in range(int(min(a[1], b[1]) // 30) - 1, int(max(a[1], b[1]) // 30) + 2):
                    egrid.setdefault((i, j), []).append((a, b))

    def nearest_road(x: float, z: float):
        best = None
        for a, b in egrid.get((int(x // 30), int(z // 30)), ()):
            L2 = (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2
            t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((x - a[0]) * (b[0] - a[0]) + (z - a[1]) * (b[1] - a[1])) / L2))
            q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            d = math.dist((x, z), q)
            if best is None or d < best[0]:
                best = (d, q)
        return best

    bracket_n = 0
    for key in sorted(dress):
        for k, pole in enumerate(dress[key].get("poles", [])):
            x, z = float(pole[0]), float(pole[1])
            near = nearest_road(x, z)
            if near is None or near[0] > 12.0 or near_median_lamp(x, z, 25.0):
                continue
            dx, dz = near[1][0] - x, near[1][1] - z
            if exact.hit(x, z, 0.2):
                continue
            lamps.append([round(x, 2), round(z, 2), round(math.atan2(dx, dz), 3), TYPE_BRACKET,
                          round(max(0.8, min(1.6, near[0] * 0.35)), 2)])
            bracket_n += 1

    out: dict = {}
    for l in lamps:
        out.setdefault((math.floor(l[0] / CHUNK), math.floor(l[1] / CHUNK)), []).append(l)
    for key, dd in dress.items():
        if key in out:
            dd["lamps"] = out[key]
        (WORLD / "dress" / f"c_{key[0]}_{key[1]}.json").write_text(json.dumps(dd, separators=(",", ":")))
    print(f"street lights: {median_n} median double-arm, {kerb_n} kerb single-arm, {bracket_n} EB-pole brackets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
