"""Attach real OpenStreetMap street names (English `name` + Tamil `name:ta`) to road_graph.json.

The osm2streets geometry pass drops way tags, so every graph edge came out unnamed. This matches
each edge back to the named OSM highway it was built from: sample the edge's segment midpoints,
find the nearest named OSM segment (within the road's half-width + 9 m and roughly parallel), and
take the majority vote. Writes "n" (English) and "nt" (Tamil, when OSM has it) per edge.

Run after build_world.py (it calls this at the end), or on its own:
    python3 tools/osm/attach_road_names.py
"""
from __future__ import annotations

import gzip
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import MAP_SCALE, ORIGIN  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "osm" / "chennai_mvp.osm.json.gz"
GRAPH = ROOT / "data" / "world" / "road_graph.json"
M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))
CELL = 40.0
MAX_EXTRA_M = 9.0
MIN_PARALLEL = 0.8  # |cos| between edge segment and OSM segment


def project(lat: float, lon: float) -> tuple[float, float]:
    return ((lon - ORIGIN[1]) * M_PER_DEG_LON * MAP_SCALE, -(lat - ORIGIN[0]) * M_PER_DEG_LAT * MAP_SCALE)


def seg_dist(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def main() -> int:
    with gzip.open(RAW, "rt", encoding="utf-8") as f:
        elements = json.load(f)["elements"]
    nodes = {e["id"]: (e["lat"], e["lon"]) for e in elements if e["type"] == "node"}
    grid: dict[tuple[int, int], list] = defaultdict(list)
    named = 0
    for w in elements:
        tags = w.get("tags", {})
        if w["type"] != "way" or "highway" not in tags:
            continue
        en, ta = tags.get("name", ""), tags.get("name:ta", "")
        if not en and not ta:
            continue
        if not en:
            en = tags.get("name:en", "")
        named += 1
        if "geometry" in w:  # Overpass `out geom`
            pts = [project(g["lat"], g["lon"]) for g in w["geometry"] if g]
        else:
            pts = [project(*nodes[n]) for n in w.get("nodes", []) if n in nodes]
        for a, b in zip(pts, pts[1:]):
            seg = (a, b, en, ta)
            x0, x1 = sorted((a[0], b[0]))
            z0, z1 = sorted((a[1], b[1]))
            for i in range(int(math.floor(x0 / CELL)), int(math.floor(x1 / CELL)) + 1):
                for j in range(int(math.floor(z0 / CELL)), int(math.floor(z1 / CELL)) + 1):
                    grid[(i, j)].append(seg)

    graph = json.loads(GRAPH.read_text())
    hit = 0
    for e in graph["edges"]:
        votes: Counter = Counter()
        pts = e["pts"]
        limit = float(e.get("w", 7.0)) * 0.5 + MAX_EXTRA_M
        for a, b in zip(pts, pts[1:]):
            mx, mz = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            ex, ez = b[0] - a[0], b[1] - a[1]
            el = math.hypot(ex, ez)
            if el < 0.5:
                continue
            best, best_d = None, limit
            ci, cj = int(math.floor(mx / CELL)), int(math.floor(mz / CELL))
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    for (sa, sb, en, ta) in grid.get((ci + di, cj + dj), ()):
                        sx, sz = sb[0] - sa[0], sb[1] - sa[1]
                        sl = math.hypot(sx, sz)
                        if sl < 0.1 or abs((ex * sx + ez * sz) / (el * sl)) < MIN_PARALLEL:
                            continue
                        d = seg_dist(mx, mz, sa[0], sa[1], sb[0], sb[1])
                        if d < best_d:
                            best, best_d = (en, ta), d
            if best is not None:
                votes[best] += el
        if votes:
            (en, ta), _ = votes.most_common(1)[0]
            if en:
                e["n"] = en
            if ta:
                e["nt"] = ta
            hit += 1
        else:
            e["n"] = e.get("n", "")  # keep whatever build_world.py already found
    GRAPH.write_text(json.dumps(graph, separators=(",", ":"), ensure_ascii=False))
    names = {e["n"] for e in graph["edges"] if e.get("n")}
    print(f"Road names: {named} named OSM ways → {hit}/{len(graph['edges'])} edges named, "
          f"{len(names)} distinct streets, {sum(1 for e in graph['edges'] if e.get('nt'))} with Tamil names")
    return 0


if __name__ == "__main__":
    sys.exit(main())
