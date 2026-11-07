"""Marina / Santhome beach fence: a near-continuous row of barricades where the sand meets the city.

Owner (Nov 7 playtest): "Marina Beach must have barricades so that it does not allow any vehicles
inside at most places" — the auto could leave Kamarajar Salai / Santhome High Road and drive out
onto the sand. Real Marina is fenced off from the road with police and Corporation barricades.

For every beach polygon in data/world/areas.json this walks the boundary every STEP_M. Only the
land side is fenced: a boundary point more than SEA_M from the "sea" area and within LAND_M of a
road in road_graph.json (the Adyar / Cooum river-mouth sand far from any road is left open). At each point the barricade is pushed into the sand by the first INWARD_M offset that is
clear of roads, buildings, carts, the Lighthouse metro works and other barricades — so where a
real road crosses the line there is a gap (traffic must still use the road), everywhere else the
row is closed: STEP_M is shorter than a 2 m barricade, so there is no gap an auto (1.4 m) fits.

Output: dress "beach_fence" = [[x, z, yaw, type], …] (same layout as "barricades", drawn and made
solid by WorldChunkStreamer._barricades). A separate key, so build_barricades.py can be re-run
without wiping it. Idempotent:  python3 tools/osm/build_beach_fence.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_street_signs import BLD_CLEAR, CELL, TriGrid, seg_dist  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0
STEP_M = 1.9            # barricades are 2 m long: rows overlap a touch, no gaps
LAND_M = 150.0          # Marina's sand edge sits 10–125 m off Kamarajar Salai (service lane, promenade)
SEA_M = 12.0            # boundary this close to the sea area = the waterline, never fenced
INWARD_M = (0.8, 1.4, 2.2, 3.2, 4.5, 6.0, 8.0, 10.0)
CLEAR_ROAD = 0.6
CART_CLEAR = 2.2
SECTION_M = 120.0       # sections of one kind: mostly red/white water-filled (2 boxes each, cheap on the
                        # chunk mesh — ~2,800 of them), some police yellow/black and Corporation blue/white


def pseudo(*vals) -> float:
    h = 2166136261
    for v in vals:
        for ch in f"{v:.2f}":
            h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h / 0xFFFFFFFF


def inside(poly, x, z) -> bool:
    c = False
    n = len(poly)
    for i in range(n):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % n]
        if (az > z) != (bz > z) and x < (bx - ax) * (z - az) / (bz - az) + ax:
            c = not c
    return c


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    areas = json.loads((WORLD / "areas.json").read_text())
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
        hw = float(e["w"]) * 0.5 + 0.4
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                for j in range(int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 2):
                    seg_grid.setdefault((i, j), []).append((a, b, hw))

    def near_segs(x, z, r):
        ci, cj = int(x // CELL), int(z // CELL)
        k = int(r // CELL) + 1
        for i in range(ci - k, ci + k + 1):
            for j in range(cj - k, cj + k + 1):
                yield from seg_grid.get((i, j), ())

    def road_dist(x, z, r) -> float:
        return min((seg_dist(x, z, a, b) - hw for a, b, hw in near_segs(x, z, r)), default=1e9)

    # Things already standing on or by the sand.
    obstacles: dict = {}

    def add_obstacle(x, z, rad):
        obstacles.setdefault((int(x // 4), int(z // 4)), []).append((x, z, rad))

    for c in json.loads((WORLD / "carts.json").read_text()):
        add_obstacle(float(c[0]), float(c[1]), CART_CLEAR)
    dress_dir = WORLD / "dress"
    for path in dress_dir.glob("c_*.json"):
        d = json.loads(path.read_text())
        for key, rad in (("barricades", 1.9), ("stalls", 2.4), ("parking", 2.4), ("xfmr", 1.6), ("poles", 0.8), ("trees", 1.0)):
            for it in d.get(key, []):
                add_obstacle(float(it[0]), float(it[1]), rad)
    works = json.loads((WORLD / "road_works.json").read_text())
    sites = [(s["c"][0], s["c"][1], math.hypot(float(s["len"]), float(s["wid"])) * 0.5 + 4.0) for s in works.get("sites", [])]

    def busy(x, z) -> bool:
        for i in (int(x // 4) - 1, int(x // 4), int(x // 4) + 1):
            for j in (int(z // 4) - 1, int(z // 4), int(z // 4) + 1):
                for ox, oz, rad in obstacles.get((i, j), ()):
                    if math.hypot(ox - x, oz - z) < rad:
                        return True
        return any(math.hypot(sx - x, sz - z) < r for sx, sz, r in sites)

    def clear(x, z, yaw) -> bool:
        ax, az = math.sin(yaw), math.cos(yaw)
        for t in (-1.0, 0.0, 1.0):
            px, pz = x + ax * t, z + az * t
            if road.hit(px, pz, CLEAR_ROAD) or bld.hit(px, pz, BLD_CLEAR):
                return False
            if road_dist(px, pz, 12.0) < 0.2:
                return False
        return not busy(x, z)

    sea_edges = [(p[i], p[(i + 1) % len(p)]) for p in areas.get("sea", []) for i in range(len(p))]

    def sea_dist(x, z) -> float:
        return min((seg_dist(x, z, a, b) for a, b in sea_edges), default=1e9)

    placed: list = []
    land_m = 0.0
    fenced_m = 0.0
    gaps: list = []
    for poly in areas.get("beach", []):
        poly = [(float(p[0]), float(p[1])) for p in poly]
        n = len(poly)
        travelled = 0.0
        gap_from = None
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            L = math.dist(a, b)
            if L < 1e-6:
                continue
            dx, dz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            yaw = math.atan2(dx, dz)
            # Inward normal: whichever side of the edge is inside the polygon.
            nx, nz = dz, -dx
            mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
            if not inside(poly, mid[0] + nx * 0.5, mid[1] + nz * 0.5):
                nx, nz = -nx, -nz
            s = 0.0
            while s < L:
                x, z = a[0] + dx * s, a[1] + dz * s
                s += STEP_M
                travelled += STEP_M
                if sea_dist(x, z) < SEA_M or road_dist(x, z, LAND_M) > LAND_M:
                    continue  # the waterline, or river-mouth sand nowhere near a road
                land_m += STEP_M
                # Round a corner the previous barricade may already cover this point.
                ok = any(math.hypot(q[0] - (x + nx * off), q[1] - (z + nz * off)) < 1.6
                         for q in placed[-4:] for off in INWARD_M[:4])
                for off in () if ok else INWARD_M:
                    px, pz = x + nx * off, z + nz * off
                    if not inside(poly, px, pz):
                        continue  # a sharp corner: a deeper offset may still land on the sand
                    if clear(px, pz, yaw):
                        sec = int(travelled // SECTION_M)
                        r = pseudo(float(sec), float(i))
                        kind = 1 if r < 0.75 else (0 if r < 0.9 else 2)
                        placed.append([round(px, 2), round(pz, 2), round(yaw, 3), kind])
                        add_obstacle(px, pz, STEP_M * 0.9)
                        ok = True
                        break
                if ok:
                    fenced_m += STEP_M
                    if gap_from is not None:
                        gaps.append((gap_from, (x, z)))
                        gap_from = None
                elif gap_from is None:
                    gap_from = (x, z)

    # Only manifest chunks are ever streamed in; a barricade over sand-only ground goes to the
    # nearest one (meshes are in world space, so it still stands where it should).
    streamed = [tuple(c) for c in manifest["chunks"]]
    per_chunk: dict = {}
    for it in placed:
        key = (math.floor(it[0] / CHUNK), math.floor(it[1] / CHUNK))
        if key not in streamed:
            key = min(streamed, key=lambda c: math.hypot((c[0] + 0.5) * CHUNK - it[0], (c[1] + 0.5) * CHUNK - it[1]))
        per_chunk.setdefault(key, []).append(it)
    for path in sorted(dress_dir.glob("c_*.json")):
        k = path.stem.split("_")
        key = (int(k[1]), int(k[2]))
        d = json.loads(path.read_text())
        if key in per_chunk:
            d["beach_fence"] = per_chunk.pop(key)
        elif "beach_fence" in d:
            d.pop("beach_fence")
        else:
            continue
        path.write_text(json.dumps(d, separators=(",", ":")))
    for key, items in per_chunk.items():
        (dress_dir / f"c_{key[0]}_{key[1]}.json").write_text(json.dumps({"beach_fence": items}, separators=(",", ":")))
    long_gaps = sorted((math.dist(g[0], g[1]), g) for g in gaps)
    print(f"Beach fence: {len(placed)} barricades, {fenced_m:.0f} m of {land_m:.0f} m city-side edge "
          f"({100.0 * fenced_m / max(land_m, 1.0):.0f} %), {len(gaps)} gaps (road crossings)")
    for d, g in long_gaps[-8:]:
        print(f"  gap {d:5.1f} m  ({g[0][0]:.0f}, {g[0][1]:.0f}) → ({g[1][0]:.0f}, {g[1][1]:.0f})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
