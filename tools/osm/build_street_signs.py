"""Street-name board spots that never stand in the road.

The first version placed boards at "graph road width / 2 + 1 m", but the real osm2streets
carriageway (data/world/chunks/*.json "surf": road / junction / *_up) is often wider than the
graph's width tag, so many boards ended up in a traffic lane. This pass places every board
against the REAL surface: for each junction (≥ 3 roads) and each named street leaving it, it
searches along the street (6–24 m from the junction) and out from the centre line on the left
kerb, and keeps the first spot that is

  • not inside any road / junction / flyover triangle, with 0.9 m clearance,
  • not inside a building footprint (0.6 m clearance),
  • preferably on a sidewalk ("walk") triangle — real GCC boards stand on the footpath.

Output: data/world/street_signs.json = [[x, z, yaw, "name", "name_ta"], …] (yaw faces traffic
turning in). Re-run after an OSM rebuild:  python3 tools/osm/build_street_signs.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CELL = 20.0
ROAD_CLEAR = 0.9
BLD_CLEAR = 0.6
ALONG = (6.0, 8.0, 10.0, 13.0, 16.0, 20.0, 24.0)
OUT_EXTRA = (0.6, 1.2, 1.8, 2.6, 3.4, 4.4, 5.6, 7.0)
MIN_SPACING = 18.0  # two boards for the same street closer than this → keep one


def tri_contains(px, pz, a, b, c) -> bool:
    d1 = (px - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (pz - b[1])
    d2 = (px - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (pz - c[1])
    d3 = (px - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (pz - a[1])
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def seg_dist(px, pz, a, b) -> float:
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - a[0]) * dx + (pz - a[1]) * dz) / l2))
    return math.hypot(px - (a[0] + t * dx), pz - (a[1] + t * dz))


class TriGrid:
    def __init__(self) -> None:
        self.cells: dict = {}

    def add(self, a, b, c) -> None:
        xs, zs = (a[0], b[0], c[0]), (a[1], b[1], c[1])
        for i in range(int(min(xs) // CELL), int(max(xs) // CELL) + 1):
            for j in range(int(min(zs) // CELL), int(max(zs) // CELL) + 1):
                self.cells.setdefault((i, j), []).append((a, b, c))

    def near(self, x, z, r):
        seen = set()
        for i in range(int((x - r) // CELL), int((x + r) // CELL) + 1):
            for j in range(int((z - r) // CELL), int((z + r) // CELL) + 1):
                for t in self.cells.get((i, j), ()):
                    if id(t) not in seen:
                        seen.add(id(t))
                        yield t

    def hit(self, x, z, clear) -> bool:
        for a, b, c in self.near(x, z, clear + 0.5):
            if tri_contains(x, z, a, b, c):
                return True
            if clear > 0 and min(seg_dist(x, z, a, b), seg_dist(x, z, b, c), seg_dist(x, z, c, a)) < clear:
                return True
        return False


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    road, walk, bld = TriGrid(), TriGrid(), TriGrid()
    for ch in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for kind, part in d.get("surf", {}).items():
            base = kind.removesuffix("_up")
            target = road if base in ("road", "junction", "lane", "centre") else (walk if base == "walk" else None)
            if target is None:
                continue
            v, idx = part["v"], part["i"]
            pts = [(v[k], v[k + 1]) for k in range(0, len(v), 2)]
            for k in range(0, len(idx), 3):
                target.add(pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]])
        for b in d.get("blds", []):
            p = b["p"]
            poly = [(p[k], p[k + 1]) for k in range(0, len(p), 2)]
            for k in range(1, len(poly) - 1):  # fan triangulation is fine for a containment test
                bld.add(poly[0], poly[k], poly[k + 1])

    graph = json.loads((WORLD / "road_graph.json").read_text())
    nodes = graph["nodes"]
    node_edges: dict = {}
    for ei, e in enumerate(graph["edges"]):
        node_edges.setdefault(e["a"], []).append(ei)
        node_edges.setdefault(e["b"], []).append(ei)

    # Second safety net: clear of every graph road by half its width + 0.5 m (catches gaps in the
    # osm2streets surface mesh).
    seg_grid: dict = {}
    for e in graph["edges"]:
        hw = float(e["w"]) * 0.5 + 0.5
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                for j in range(int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 2):
                    seg_grid.setdefault((i, j), []).append((a, b, hw))

    def in_graph_road(x, z) -> bool:
        return any(seg_dist(x, z, a, b) < hw for a, b, hw in seg_grid.get((int(x // CELL), int(z // CELL)), ()))

    def sample(e, s):
        pts = e["pts"]
        for i in range(1, len(pts)):
            L = math.dist(pts[i - 1], pts[i])
            if s <= L or i == len(pts) - 1:
                t = min(max(s / max(L, 1e-6), 0.0), 1.0)
                a, b = pts[i - 1], pts[i]
                return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
                        (b[0] - a[0]) / max(L, 1e-6), (b[1] - a[1]) / max(L, 1e-6))
            s -= L
        return pts[-1][0], pts[-1][1], 1.0, 0.0

    out, placed, skipped = [], {}, 0
    for ni, eis in node_edges.items():
        if len(eis) < 3:
            continue
        seen = set()
        for ei in eis:
            e = graph["edges"][ei]
            name = e.get("n", "")
            if not name or name in seen:
                continue
            seen.add(name)
            pts = e["pts"] if e["a"] == ni else list(reversed(e["pts"]))
            length = sum(math.dist(pts[i - 1], pts[i]) for i in range(1, len(pts)))
            ee = {"pts": pts}
            half = float(e["w"]) * 0.5
            best = None
            for s in ALONG:
                if s > length - 4.0:
                    break
                x, z, dx, dz = sample(ee, s)
                lx, lz = dz, -dx  # left of travel direction (India drives on the left)
                for extra in OUT_EXTRA:
                    px, pz = x + lx * (half + extra), z + lz * (half + extra)
                    if road.hit(px, pz, ROAD_CLEAR) or bld.hit(px, pz, BLD_CLEAR) or in_graph_road(px, pz):
                        continue
                    on_walk = walk.hit(px, pz, 0.0)
                    if best is None or (on_walk and not best[3]):
                        best = (px, pz, math.atan2(dx, dz), on_walk)
                    if on_walk:
                        break
                if best is not None and best[3]:
                    break
            if best is None:
                skipped += 1
                continue
            if any(math.dist(q, best[:2]) < MIN_SPACING for q in placed.get(name, [])):
                continue
            placed.setdefault(name, []).append(best[:2])
            out.append([round(best[0], 2), round(best[1], 2), round(best[2], 3), name, e.get("nt", "")])

    (WORLD / "street_signs.json").write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    print(f"Street signs: {len(out)} boards placed on footpaths / verges, {skipped} spots skipped (no clear kerb)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
