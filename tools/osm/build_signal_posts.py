"""Traffic-signal post spots on the kerb, never in the carriageway.

The signal posts used to stand at the junction node plus a fixed +3.5 m world-x offset, so on
most junctions they landed in a lane (or in the middle of the crossing street). This pass uses
the same real-surface test as build_street_signs.py: for every junction that can get a signal
(≥ 3 roads, ≥ 2 of them trunk / primary / secondary and ≥ 6 m wide — keep in sync with
ChennaiTrafficManager.SIGNAL_ROADS / SIGNAL_MIN_WIDTH_M) and every big road leading into it, it
walks back up the approach (4–20 m from the junction) and out to the LEFT kerb of the traffic
coming in (India drives on the left), and keeps the first spot that is clear of every road,
junction and flyover triangle and every building, preferring a footpath ("walk") triangle.

Output: data/world/signal_posts.json = {"<node id>": [[x, z, yaw], …]} — yaw turns the lamp
face (local +Z) towards the traffic waiting at that approach.
Re-run after an OSM rebuild:  python3 tools/osm/build_signal_posts.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_street_signs import BLD_CLEAR, CELL, ROAD_CLEAR, TriGrid, seg_dist  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
SIGNAL_ROADS = ("trunk", "primary", "secondary")
SIGNAL_MIN_WIDTH_M = 6.0
ALONG = (4.0, 6.0, 8.0, 10.0, 13.0, 16.0, 20.0)
OUT_EXTRA = (0.8, 1.4, 2.0, 2.8, 3.6, 4.6, 5.8, 7.0)


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
            for k in range(1, len(poly) - 1):
                bld.add(poly[0], poly[k], poly[k + 1])

    graph = json.loads((WORLD / "road_graph.json").read_text())
    edges = graph["edges"]
    node_edges: dict = {}
    for ei, e in enumerate(edges):
        node_edges.setdefault(e["a"], []).append(ei)
        node_edges.setdefault(e["b"], []).append(ei)

    seg_grid: dict = {}
    for e in edges:
        hw = float(e["w"]) * 0.5 + 0.6
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                for j in range(int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 2):
                    seg_grid.setdefault((i, j), []).append((a, b, hw))

    def in_graph_road(x, z) -> bool:
        return any(seg_dist(x, z, a, b) < hw for a, b, hw in seg_grid.get((int(x // CELL), int(z // CELL)), ()))

    def sample(pts, s):
        for i in range(1, len(pts)):
            seg = math.dist(pts[i - 1], pts[i])
            if s <= seg or i == len(pts) - 1:
                t = min(max(s / max(seg, 1e-6), 0.0), 1.0)
                a, b = pts[i - 1], pts[i]
                return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
                        (b[0] - a[0]) / max(seg, 1e-6), (b[1] - a[1]) / max(seg, 1e-6))
            s -= seg
        return pts[-1][0], pts[-1][1], 1.0, 0.0

    def big(e) -> bool:
        return e["c"] in SIGNAL_ROADS and float(e["w"]) >= SIGNAL_MIN_WIDTH_M

    out: dict = {}
    nodes_total = posts_total = missing = 0
    for ni, eis in node_edges.items():
        if len(eis) < 3 or sum(1 for ei in eis if big(edges[ei])) < 2:
            continue
        nodes_total += 1
        poses = []
        for ei in eis:
            e = edges[ei]
            if not big(e):
                continue
            pts = e["pts"] if e["a"] == ni else list(reversed(e["pts"]))  # running AWAY from the junction
            length = sum(math.dist(pts[i - 1], pts[i]) for i in range(1, len(pts)))
            half = float(e["w"]) * 0.5
            best = None
            for s in ALONG:
                if s > length - 3.0:
                    break
                x, z, dx, dz = sample(pts, s)
                # Incoming traffic travels (-dx, -dz); its left is (-dz, dx).
                lx, lz = -dz, dx
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
                missing += 1
                continue
            if any(math.dist(p[:2], best[:2]) < 6.0 for p in poses):
                continue
            poses.append([round(best[0], 2), round(best[1], 2), round(best[2], 3)])
        if poses:
            out[str(ni)] = poses
            posts_total += len(poses)

    (WORLD / "signal_posts.json").write_text(json.dumps(out, separators=(",", ":")))
    print(f"Signal posts: {posts_total} posts at {len(out)}/{nodes_total} signal junctions "
          f"({missing} approaches had no clear kerb)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
