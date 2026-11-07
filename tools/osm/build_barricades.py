"""Chennai roadside barricades: rows of traffic-police steel barricades and plastic barriers.

Chennai's junction corners and market streets are lined with them — yellow-and-black steel
police barricades, blue-and-white Corporation ones and red-and-white water-filled barriers —
keeping parked bikes and hawkers off the corner and pedestrians off the carriageway. This pass
puts rows of them on the kerb, never in a lane:

* JUNCTIONS — behind ~40 % of the signal posts (data/world/signal_posts.json), a row of three
  running back along the kerb from the post.
* MARKETS — along the main streets of the Mylapore and T. Nagar market zones, a row of two
  every MARKET_EVERY_M on each kerb.

Each barricade must sit clear of every road / junction triangle and every building (same test as
build_street_signs.py). Output: dress "barricades" = [[x, z, yaw, type], …] with type 0 = police
(yellow/black), 1 = water-filled (red/white), 2 = Corporation (blue/white); yaw runs along the
kerb. Idempotent. Run after build_signal_posts.py (and before build_road_works.py, which clears
the works footprint):  python3 tools/osm/build_barricades.py
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
UNIT_M = 2.15  # one barricade + gap
JUNCTION_SHARE = 0.4
MARKET_ZONES = ("mylapore", "t_nagar")
MARKET_CLASSES = ("primary", "secondary", "tertiary")
MARKET_EVERY_M = 55.0
CLEAR_ROAD = 0.45


def pseudo(*vals) -> float:
    """Stable 0..1 from numbers (same layout every run)."""
    h = 2166136261
    for v in vals:
        for ch in f"{v:.2f}":
            h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h / 0xFFFFFFFF


def kind_for(r: float) -> int:
    return 0 if r < 0.65 else (2 if r < 0.85 else 1)


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
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
    edges = graph["edges"]
    seg_grid: dict = {}
    for e in edges:
        hw = float(e["w"]) * 0.5 + 0.4
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                for j in range(int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 2):
                    seg_grid.setdefault((i, j), []).append((a, b, hw))

    def clear(x, z, yaw) -> bool:
        ax, az = math.sin(yaw), math.cos(yaw)
        for t in (-1.0, 0.0, 1.0):  # both ends and the middle of a 2 m barricade
            px, pz = x + ax * t, z + az * t
            if road.hit(px, pz, CLEAR_ROAD) or bld.hit(px, pz, BLD_CLEAR):
                return False
            if any(seg_dist(px, pz, a, b) < hw for a, b, hw in seg_grid.get((int(px // CELL), int(pz // CELL)), ())):
                return False
        return True

    placed: list = []
    taken: dict = {}

    def free_spot(x, z) -> bool:
        for i in (int(x // 4) - 1, int(x // 4), int(x // 4) + 1):
            for j in (int(z // 4) - 1, int(z // 4), int(z // 4) + 1):
                for q in taken.get((i, j), ()):
                    if math.dist(q, (x, z)) < 1.9:
                        return False
        return True

    def put(x, z, yaw, kind) -> bool:
        if not clear(x, z, yaw) or not free_spot(x, z):
            return False
        placed.append([round(x, 2), round(z, 2), round(yaw, 3), kind])
        taken.setdefault((int(x // 4), int(z // 4)), []).append((x, z))
        return True

    # Junction corners: behind the signal post, along the kerb, away from the junction.
    posts = json.loads((WORLD / "signal_posts.json").read_text())
    junction_rows = 0
    for node, spots in posts.items():
        for spot in spots:
            x, z, yaw = float(spot[0]), float(spot[1]), float(spot[2])
            r = pseudo(x, z)
            if r >= JUNCTION_SHARE:
                continue
            ax, az = math.sin(yaw), math.cos(yaw)  # away from the junction
            kind = kind_for(pseudo(z, x))
            n = 0
            for k in range(3):
                d = 2.4 + UNIT_M * k
                if put(x + ax * d, z + az * d, yaw, kind):
                    n += 1
            junction_rows += 1 if n else 0

    # Market streets: rows of two on each kerb.
    zones = [z for z in manifest["zones"] if z["id"] in MARKET_ZONES]
    market_rows = 0
    for e in edges:
        if e["c"] not in MARKET_CLASSES:
            continue
        pts = e["pts"]
        if not any(math.dist(pts[len(pts) // 2], (z["x"], z["z"])) < float(z["r"]) for z in zones):
            continue
        half = float(e["w"]) * 0.5
        travelled = 0.0
        next_at = MARKET_EVERY_M * (0.3 + 0.6 * pseudo(*pts[0]))
        for a, b in zip(pts, pts[1:]):
            L = math.dist(a, b)
            if L < 1e-6:
                continue
            dx, dz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            while next_at <= travelled + L:
                s = next_at - travelled
                next_at += MARKET_EVERY_M
                x, z = a[0] + dx * s, a[1] + dz * s
                yaw = math.atan2(dx, dz)
                for side in (1, -1):
                    lx, lz = dz * side, -dx * side
                    for extra in (0.9, 1.4, 2.0, 2.8, 3.6):
                        px, pz = x + lx * (half + extra), z + lz * (half + extra)
                        if clear(px, pz, yaw) and free_spot(px, pz):
                            kind = kind_for(pseudo(px, pz))
                            ok = put(px, pz, yaw, kind)
                            ok = put(px + dx * UNIT_M, pz + dz * UNIT_M, yaw, kind) or ok
                            market_rows += 1 if ok else 0
                            break
            travelled += L

    per_chunk: dict = {}
    for it in placed:
        per_chunk.setdefault((math.floor(it[0] / CHUNK), math.floor(it[1] / CHUNK)), []).append(it)
    dress_dir = WORLD / "dress"
    kept = 0
    for path in sorted(dress_dir.glob("c_*.json")):
        k = path.stem.split("_")
        key = (int(k[1]), int(k[2]))
        d = json.loads(path.read_text())
        if key not in per_chunk and "barricades" not in d:
            continue
        if key in per_chunk:
            # Keep off parked cars, stalls, transformers, poles and tree trunks already there.
            busy = [(float(it[0]), float(it[1]), 2.2 if kind in ("parking", "stalls") else 1.0)
                    for kind in ("parking", "stalls", "xfmr", "poles", "trees") for it in d.get(kind, [])]
            items = [b for b in per_chunk.pop(key)
                     if all(math.dist((b[0], b[1]), (q[0], q[1])) > q[2] for q in busy)]
            d["barricades"] = items
            kept += len(items)
        else:
            d.pop("barricades")
        path.write_text(json.dumps(d, separators=(",", ":")))
    for key, items in per_chunk.items():
        kept += len(items)
        (dress_dir / f"c_{key[0]}_{key[1]}.json").write_text(json.dumps({"barricades": items}, separators=(",", ":")))
    kinds = [sum(1 for it in placed if it[3] == k) for k in range(3)]
    print(f"Barricades: {kept} kept of {len(placed)} ({kinds[0]} police, {kinds[1]} water-filled, {kinds[2]} Corporation) — "
          f"{junction_rows} junction rows, {market_rows} market rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
