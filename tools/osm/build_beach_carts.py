"""Push-cart shops along the Marina / Besant Nagar sand and beside market-street stalls.

From the owner's Marina photos (Nov 7): rows of painted carts — sign-box carts, tiffin carts on
spoked wheels, flat push-carts with wire racks, kiosks, carts shut under a tarp — stand on the
sand at the promenade's edge, facing the road, in clusters with gaps between. Smaller numbers
stand on market kerbs next to the existing stalls.

* BEACH — walk the landward edge of every beach polygon (the stretch within LANDWARD_M of a
  road), and lay clusters of CLUSTER carts 2.2–3 m apart, 3–5 m into the sand, turned to face
  the nearest road, with GAP metres between clusters.
* MARKETS — next to ~MARKET_SHARE of the kerb stalls, a cart along the same kerb.

Every cart keeps clear of roads, buildings, trees, poles, stalls, parked vehicles, barricades,
landmarks and the metro works. Output: dress "carts" = [[x, z, yaw, variant, name, ground y], …]
(variant / name index into BeachCartKit.VARIANTS / NAMES — keep BUILDS below in sync), and the
same list in data/world/carts.json for the name boards.
Idempotent. Run after build_barricades.py and before build_road_works.py:
    python3 tools/osm/build_beach_carts.py
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_street_signs import CELL, TriGrid, seg_dist  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0
# BeachCartKit.VARIANTS builds, in order: 0 sign box, 1 tiffin, 2 push-cart, 3 kiosk, 4 covered.
BUILDS = [0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4]
N_NAMES = 24
BEACH_WEIGHTS = {0: 0.34, 1: 0.24, 2: 0.18, 3: 0.14, 4: 0.10}
MARKET_WEIGHTS = {0: 0.25, 1: 0.35, 2: 0.3, 3: 0.1, 4: 0.0}
LANDWARD_M = 75.0  # Marina: the sand starts 50–60 m from Kamarajar Salai (promenade between)
EDGE_STEP_M = 0.5
CLUSTER = (5, 12)
SPACING = (2.2, 3.0)
GAP = (25.0, 90.0)
INTO_SAND = (3.0, 5.0)
MARKET_SHARE = 0.18
SAND_Y = -0.08
SEA_CLEAR_M = 35.0  # carts stand at the promenade edge, never down by the waterline
WALK_Y = 0.08


def pick_variant(rng: random.Random, weights: dict) -> int:
    r = rng.random()
    acc = 0.0
    for build, w in weights.items():
        acc += w
        if r <= acc:
            break
    choices = [i for i, b in enumerate(BUILDS) if b == build]
    return rng.choice(choices)


def main() -> int:
    rng = random.Random(1107)
    manifest = json.loads((WORLD / "manifest.json").read_text())
    areas = json.loads((WORLD / "areas.json").read_text())

    def poly_of(p):
        if p and isinstance(p[0], (int, float)):
            return Polygon(list(zip(p[0::2], p[1::2]))).buffer(0)
        return Polygon(p).buffer(0)

    beaches = [poly_of(p) for p in areas.get("beach", [])]
    sea = unary_union([poly_of(p) for p in areas.get("sea", []) + areas.get("water", [])])
    road, bld = TriGrid(), TriGrid()
    for ch in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for kind, part in d.get("surf", {}).items():
            if kind.removesuffix("_up") not in ("road", "junction", "lane", "centre"):
                continue
            v, idx = part["v"], part["i"]
            pts = [(v[k], v[k + 1]) for k in range(0, len(v), 2)]
            for k in range(0, len(idx), 3):
                road.add(pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]])
        for b in d.get("blds", []):
            p = b["p"]
            poly = [(p[k], p[k + 1]) for k in range(0, len(p), 2)]
            for k in range(1, len(poly) - 1):
                bld.add(poly[0], poly[k], poly[k + 1])
    graph = json.loads((WORLD / "road_graph.json").read_text())
    seg_grid: dict = {}
    for e in graph["edges"]:
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                for j in range(int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 2):
                    seg_grid.setdefault((i, j), []).append((a, b))

    def nearest_road(x, z, reach):
        best = None
        cx, cz = int(x // CELL), int(z // CELL)
        r = int(reach // CELL) + 1
        for i in range(cx - r, cx + r + 1):
            for j in range(cz - r, cz + r + 1):
                for a, b in seg_grid.get((i, j), ()):
                    d = seg_dist(x, z, a, b)
                    if best is None or d < best[0]:
                        L2 = (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2
                        t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((x - a[0]) * (b[0] - a[0]) + (z - a[1]) * (b[1] - a[1])) / L2))
                        best = (d, (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        return best if best is not None and best[0] <= reach else None

    # Everything already standing, per dress chunk.
    busy: dict = {}  # (cell 4 m) -> [(x, z, radius)]
    dress = {}
    for path in sorted((WORLD / "dress").glob("c_*.json")):
        k = path.stem.split("_")
        d = json.loads(path.read_text())
        d.pop("carts", None)
        dress[(int(k[1]), int(k[2]))] = (path, d)
        for kind, rad in (("trees", 1.2), ("poles", 0.8), ("xfmr", 1.6), ("stalls", 2.4), ("parking", 2.4), ("barricades", 1.6)):
            for it in d.get(kind, []):
                busy.setdefault((int(it[0] // 4), int(it[1] // 4)), []).append((float(it[0]), float(it[1]), rad))
    keep_out = [Point(l["x"], l["z"]).buffer(18.0) for l in manifest.get("landmarks", [])]
    works_file = WORLD / "road_works.json"
    if works_file.exists():
        for s in json.loads(works_file.read_text()).get("sites", []):
            keep_out.append(Point(s["c"]).buffer(max(s["len"], s["wid"]) * 0.6 + 4.0))
    keep_out = unary_union(keep_out)

    def free(x, z, r=1.25) -> bool:
        for i in (int(x // 4) - 1, int(x // 4), int(x // 4) + 1):
            for j in (int(z // 4) - 1, int(z // 4), int(z // 4) + 1):
                for q in busy.get((i, j), ()):
                    if math.dist((q[0], q[1]), (x, z)) < q[2] + r:
                        return False
        return True

    def ok_spot(x, z, yaw, road_clear=1.2) -> bool:
        ax, az = math.cos(yaw), -math.sin(yaw)  # cart's local +X (its width)
        for t in (-1.0, 0.0, 1.0):
            px, pz = x + ax * t, z + az * t
            if road.hit(px, pz, road_clear) or bld.hit(px, pz, 0.6):
                return False
        return not keep_out.contains(Point(x, z)) and free(x, z)

    carts: list = []

    def put(x, z, yaw, variant, ground):
        carts.append([round(x, 2), round(z, 2), round(yaw, 3), variant, rng.randrange(N_NAMES), ground])
        busy.setdefault((int(x // 4), int(z // 4)), []).append((x, z, 1.1))

    # --- beach clusters ---------------------------------------------------------------------
    beach_n = 0
    for poly in beaches:
        rings = [poly.exterior] if poly.geom_type == "Polygon" else [g.exterior for g in poly.geoms]
        for ring in rings:
            L = ring.length
            s = rng.uniform(0.0, GAP[1])
            while s < L:
                count = rng.randint(*CLUSTER)
                placed_here = 0
                while placed_here < count and s < L:
                    p = ring.interpolate(s)
                    q = ring.interpolate(min(s + EDGE_STEP_M, L))
                    tx, tz = q.x - p.x, q.y - p.y
                    tl = math.hypot(tx, tz) or 1.0
                    nx, nz = -tz / tl, tx / tl
                    if not poly.contains(Point(p.x + nx * 2.0, p.y + nz * 2.0)):
                        nx, nz = -nx, -nz
                    into = rng.uniform(*INTO_SAND)
                    x, z = p.x + nx * into, p.y + nz * into
                    near = nearest_road(p.x, p.y, LANDWARD_M)
                    if near is None or not poly.contains(Point(x, z)) or sea.distance(Point(x, z)) < SEA_CLEAR_M:
                        s += SPACING[1]
                        if near is None:
                            break  # left the promenade side: end this cluster
                        continue
                    yaw = math.atan2(near[1][0] - x, near[1][1] - z)  # +Z faces the road
                    if ok_spot(x, z, yaw):
                        put(x, z, yaw, pick_variant(rng, BEACH_WEIGHTS), SAND_Y)
                        placed_here += 1
                        beach_n += 1
                    s += rng.uniform(*SPACING)
                s += rng.uniform(*GAP)

    # --- beside market stalls -----------------------------------------------------------------
    market_n = 0
    for key, (path, d) in dress.items():
        for st in d.get("stalls", []):
            if rng.random() > MARKET_SHARE:
                continue
            x0, z0, yaw = float(st[0]), float(st[1]), float(st[2])
            ax, az = math.cos(yaw), -math.sin(yaw)
            # The stall itself is in `busy`; drop it while testing its neighbours.
            cell = busy.get((int(x0 // 4), int(z0 // 4)), [])
            mine = [q for q in cell if abs(q[0] - x0) < 1e-3 and abs(q[1] - z0) < 1e-3]
            for q in mine:
                cell.remove(q)
            for side in (1.0, -1.0):
                x, z = x0 + ax * 2.7 * side, z0 + az * 2.7 * side
                if ok_spot(x, z, yaw, 0.45):
                    put(x, z, yaw, pick_variant(rng, MARKET_WEIGHTS), WALK_Y)
                    market_n += 1
                    break
            cell.extend(mine)

    # Only chunks the streamer actually loads (manifest) — a beach-only chunk has none.
    loadable = {tuple(c) for c in manifest["chunks"]}
    dropped = len(carts)
    carts = [c for c in carts if (math.floor(c[0] / CHUNK), math.floor(c[1] / CHUNK)) in loadable]
    dropped -= len(carts)
    beach_n = sum(1 for c in carts if c[5] < 0)
    market_n = len(carts) - beach_n
    # One flat list for the shop-name boards (scripts/world/CartSigns.gd).
    (WORLD / "carts.json").write_text(json.dumps(carts, separators=(",", ":")))
    per_chunk: dict = {}
    for c in carts:
        per_chunk.setdefault((math.floor(c[0] / CHUNK), math.floor(c[1] / CHUNK)), []).append(c)
    for key, (path, d) in dress.items():
        had = "carts" in json.loads(path.read_text())
        if key in per_chunk:
            d["carts"] = per_chunk.pop(key)
        elif not had:
            continue
        path.write_text(json.dumps(d, separators=(",", ":")))
    for key, items in per_chunk.items():
        (WORLD / "dress" / f"c_{key[0]}_{key[1]}.json").write_text(json.dumps({"carts": items}, separators=(",", ":")))
    if dropped:
        print(f"  ({dropped} carts fell in chunks the streamer never loads — left out)")
    builds = [0] * 5
    for c in carts:
        builds[BUILDS[c[3]]] += 1
    print(f"Carts: {len(carts)} ({beach_n} on the beach, {market_n} by market stalls) — "
          f"{builds[0]} sign-box, {builds[1]} tiffin, {builds[2]} push-cart, {builds[3]} kiosk, {builds[4]} covered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
