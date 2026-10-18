#!/usr/bin/env python3
"""Build Namma Auto's streamed world from raw OSM data (pure stdlib, deterministic).

Input : data/osm/chennai_mvp.osm.json.gz   (from fetch_osm.py, © OpenStreetMap contributors, ODbL)
Output: data/world/manifest.json            map bounds, chunk list, zones, landmarks, auto stands
        data/world/road_graph.json          drivable graph for AI traffic + GPS (Phase 3)
        data/world/areas.json               sea, water, beach, park polygons (always loaded)
        data/world/chunks/c_<i>_<j>.json    road ribbons + building boxes per 250 m chunk

Coordinates: x = east, z = south (Godot -Z is north), metres, already scaled by MAP_SCALE.
"""
from __future__ import annotations

import gzip
import json
import math
import random
import sys
from collections import defaultdict
from pathlib import Path

from config import (AUTO_STANDS, BBOX, CHUNK_SIZE_M, DEFAULT_ZONE_STYLE, LANDMARKS, LANE_WIDTH_M,
                    MAP_SCALE, ORIGIN, ROAD_CLASSES, ZONES)

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "osm" / "chennai_mvp.osm.json.gz"
OUT = ROOT / "data" / "world"

M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))

SIDEWALK_M = 2.5
LANDMARK_CLEAR_M = 28.0
SEA_CLEAR_M = 35.0


# --- Geometry helpers -------------------------------------------------------------------------

def project(lat: float, lon: float) -> tuple[float, float]:
    x = (lon - ORIGIN[1]) * M_PER_DEG_LON * MAP_SCALE
    z = -(lat - ORIGIN[0]) * M_PER_DEG_LAT * MAP_SCALE
    return (x, z)


def real_dist(a_latlon: tuple[float, float], b_latlon: tuple[float, float]) -> float:
    return math.hypot((a_latlon[0] - b_latlon[0]) * M_PER_DEG_LAT, (a_latlon[1] - b_latlon[1]) * M_PER_DEG_LON)


def seg_point_dist(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def simplify(pts: list[tuple[float, float]], tol: float) -> list[tuple[float, float]]:
    """Douglas–Peucker."""
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    idx, dmax = 0, -1.0
    for i in range(1, len(pts) - 1):
        d = seg_point_dist(pts[i][0], pts[i][1], a[0], a[1], b[0], b[1])
        if d > dmax:
            idx, dmax = i, d
    if dmax <= tol:
        return [a, b]
    return simplify(pts[: idx + 1], tol)[:-1] + simplify(pts[idx:], tol)


def point_in_poly(x: float, z: float, poly: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def poly_area(poly: list[tuple[float, float]]) -> float:
    return abs(sum(poly[i][0] * poly[i - 1][1] - poly[i - 1][0] * poly[i][1] for i in range(len(poly)))) / 2.0


def r2(v: float) -> float:
    return round(v, 2)


class SegmentGrid:
    """Spatial hash of road segments for fast clearance queries."""

    def __init__(self, cell: float = 40.0) -> None:
        self.cell = cell
        self.cells: dict[tuple[int, int], list[tuple[float, float, float, float, float]]] = defaultdict(list)

    def add(self, a: tuple[float, float], b: tuple[float, float], half_width: float) -> None:
        minx, maxx = min(a[0], b[0]) - half_width, max(a[0], b[0]) + half_width
        minz, maxz = min(a[1], b[1]) - half_width, max(a[1], b[1]) + half_width
        for i in range(int(math.floor(minx / self.cell)), int(math.floor(maxx / self.cell)) + 1):
            for j in range(int(math.floor(minz / self.cell)), int(math.floor(maxz / self.cell)) + 1):
                self.cells[(i, j)].append((a[0], a[1], b[0], b[1], half_width))

    def clear(self, x: float, z: float, margin: float) -> bool:
        i, j = int(math.floor(x / self.cell)), int(math.floor(z / self.cell))
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                for ax, az, bx, bz, hw in self.cells.get((i + di, j + dj), ()):
                    if seg_point_dist(x, z, ax, az, bx, bz) < hw + margin:
                        return False
        return True


# --- Pipeline ---------------------------------------------------------------------------------

def zone_of(lat: float, lon: float) -> str | None:
    best, best_d = None, 1e18
    for zid, z in ZONES.items():
        d = real_dist((lat, lon), z["center"])
        if d <= z["radius"] and d < best_d:
            best, best_d = zid, d
    return best


def load_raw() -> list[dict]:
    if not RAW.exists():
        sys.exit(f"Missing {RAW}. Run the 'OSM Import' GitHub workflow (or tools/osm/fetch_osm.py) first.")
    with gzip.open(RAW, "rt", encoding="utf-8") as f:
        return json.load(f)["elements"]


def build_roads(elements: list[dict]) -> tuple[list[dict], dict]:
    ways = []
    for e in elements:
        if e.get("type") != "way" or "highway" not in e.get("tags", {}):
            continue
        tags = e["tags"]
        hw = tags["highway"]
        is_link = hw.endswith("_link")
        cls = hw[:-5] if is_link else hw
        if cls not in ROAD_CLASSES or tags.get("area") == "yes" or tags.get("access") in ("private", "no"):
            continue
        geom = e.get("geometry") or []
        if len(geom) < 2 or len(geom) != len(e.get("nodes", [])):
            continue
        default_w, default_lanes, keep_everywhere = ROAD_CLASSES[cls]
        if not keep_everywhere and not any(zone_of(g["lat"], g["lon"]) for g in geom):
            continue
        oneway = tags.get("oneway", "no")
        nodes, latlon = list(e["nodes"]), [(g["lat"], g["lon"]) for g in geom]
        if oneway == "-1":
            nodes.reverse()
            latlon.reverse()
        is_oneway = oneway in ("yes", "1", "-1", "true") or tags.get("junction") == "roundabout"
        try:
            lanes_total = int(str(tags.get("lanes", "")).split(";")[0])
        except ValueError:
            lanes_total = 0
        if lanes_total <= 0:
            lanes_total = default_lanes * (1 if is_oneway else 2)
        lanes_total = max(1, min(lanes_total, 8))
        width = lanes_total * LANE_WIDTH_M if "lanes" in tags else default_w
        if is_link:
            width, lanes_total = max(5.0, width * 0.6), max(1, lanes_total // 2)
        ways.append({"id": e["id"], "cls": cls, "name": tags.get("name", ""), "nodes": nodes, "latlon": latlon,
                     "oneway": is_oneway, "lanes_total": lanes_total, "width": min(width, 24.0)})

    # Split ways into graph edges at shared nodes.
    use = defaultdict(int)
    for w in ways:
        for k, n in enumerate(w["nodes"]):
            use[n] += 2 if k in (0, len(w["nodes"]) - 1) else 1
    node_pos: dict[int, tuple[float, float]] = {}
    edges = []
    for w in ways:
        start = 0
        for k in range(1, len(w["nodes"])):
            if use[w["nodes"][k]] >= 2 or k == len(w["nodes"]) - 1:
                ids = w["nodes"][start:k + 1]
                pts = [project(*w["latlon"][m]) for m in range(start, k + 1)]
                for nid, p in ((ids[0], pts[0]), (ids[-1], pts[-1])):
                    node_pos[nid] = p
                pts = simplify(pts, 0.6)
                length = sum(math.dist(pts[m], pts[m + 1]) for m in range(len(pts) - 1))
                if length > 0.5 and ids[0] != ids[-1]:
                    lanes_fwd = w["lanes_total"] if w["oneway"] else max(1, w["lanes_total"] // 2)
                    edges.append({"a": ids[0], "b": ids[-1], "pts": pts, "len": length, "cls": w["cls"],
                                  "name": w["name"], "oneway": w["oneway"], "width": w["width"],
                                  "lanes_fwd": lanes_fwd, "lanes_back": 0 if w["oneway"] else lanes_fwd})
                start = k

    # Keep the largest connected component (undirected).
    adj = defaultdict(set)
    for e in edges:
        adj[e["a"]].add(e["b"])
        adj[e["b"]].add(e["a"])
    seen: set[int] = set()
    best: set[int] = set()
    for n in adj:
        if n in seen:
            continue
        comp, stack = set(), [n]
        while stack:
            c = stack.pop()
            if c in comp:
                continue
            comp.add(c)
            stack.extend(adj[c] - comp)
        seen |= comp
        if len(comp) > len(best):
            best = comp
    edges = [e for e in edges if e["a"] in best]
    return edges, {n: node_pos[n] for n in best if n in node_pos}


def build_areas(elements: list[dict]) -> dict:
    out = {"water": [], "beach": [], "park": [], "sea": []}
    coast_pts: list[tuple[float, float]] = []
    for e in elements:
        tags = e.get("tags", {})
        geom = e.get("geometry") or []
        if e.get("type") != "way" or len(geom) < 2:
            continue
        pts = [project(g["lat"], g["lon"]) for g in geom]
        if tags.get("natural") == "coastline":
            coast_pts.extend(pts)
            continue
        kind = "water" if tags.get("natural") == "water" else "beach" if tags.get("natural") == "beach" \
            else "park" if tags.get("leisure") == "park" else None
        if kind is None or len(pts) < 4 or pts[0] != pts[-1]:
            continue
        poly = simplify(pts[:-1] + [pts[0]], 0.8)[:-1]
        if len(poly) >= 3 and poly_area(poly) > 60.0:
            out[kind].append([[r2(x), r2(z)] for x, z in poly])
    if coast_pts:
        # The Marina coast runs north–south: order by z, simplify, close the polygon out to the east edge.
        coast = simplify(sorted(set(coast_pts), key=lambda p: p[1]), 2.0)
        east = project(BBOX[0], BBOX[3])[0] + 600.0
        zmin, zmax = coast[0][1] - 300.0, coast[-1][1] + 300.0
        sea = [(coast[0][0], zmin)] + coast + [(coast[-1][0], zmax), (east, zmax), (east, zmin)]
        out["sea"].append([[r2(x), r2(z)] for x, z in sea])
    return out


def coast_x_at(sea_polys: list, z: float) -> float:
    """x of the coastline at a given z (inf if there is no sea)."""
    if not sea_polys:
        return math.inf
    coast = sea_polys[0][1:-3]
    for (x1, z1), (x2, z2) in zip(coast, coast[1:]):
        if z1 <= z <= z2 and z2 > z1:
            return x1 + (x2 - x1) * (z - z1) / (z2 - z1)
    return coast[0][0] if z < coast[0][1] else coast[-1][0]


def build_buildings(edges: list[dict], areas: dict, landmarks: list[dict]) -> list[dict]:
    rng = random.Random(600004)  # Mylapore PIN — deterministic city
    grid = SegmentGrid()
    for e in edges:
        for a, b in zip(e["pts"], e["pts"][1:]):
            grid.add(a, b, e["width"] / 2.0)
    occupied: dict[tuple[int, int], list[tuple[float, float, float]]] = defaultdict(list)
    blocked_polys = areas["water"] + areas["beach"] + areas["park"]
    inv_scale_lat = 1.0 / (M_PER_DEG_LAT * MAP_SCALE)
    inv_scale_lon = 1.0 / (M_PER_DEG_LON * MAP_SCALE)

    def free(x: float, z: float, r: float) -> bool:
        ci, cj = int(x // 30), int(z // 30)
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                for ox, oz, orad in occupied.get((ci + di, cj + dj), ()):
                    if math.hypot(x - ox, z - oz) < r + orad:
                        return False
        return True

    out = []
    for e in edges:
        hw = e["width"] / 2.0
        for side in (-1, 1):
            for a, b in zip(e["pts"], e["pts"][1:]):
                seg_len = math.dist(a, b)
                if seg_len < 8.0:
                    continue
                dx, dz = (b[0] - a[0]) / seg_len, (b[1] - a[1]) / seg_len
                nx, nz = -dz * side, dx * side  # outward normal for this side
                t = rng.uniform(2.0, 6.0)
                while t < seg_len - 4.0:
                    px, pz = a[0] + dx * t, a[1] + dz * t
                    lat, lon = ORIGIN[0] - pz * inv_scale_lat, ORIGIN[1] + px * inv_scale_lon
                    zid = zone_of(lat, lon)
                    style = ZONES[zid] if zid else DEFAULT_ZONE_STYLE
                    w = rng.uniform(9.0, 17.0)
                    if rng.random() > style["bld_density"]:
                        t += w
                        continue
                    d = rng.uniform(8.0, 15.0)
                    h = rng.uniform(*style["bld_height"])
                    off = hw + SIDEWALK_M + d / 2.0
                    cx, cz = px + dx * (w / 2.0) + nx * off, pz + dz * (w / 2.0) + nz * off
                    radius = math.hypot(w, d) / 2.0
                    corners = [(cx + dx * sx * w / 2 + nx * sz * d / 2, cz + dz * sx * w / 2 + nz * sz * d / 2)
                               for sx in (-1, 1) for sz in (-1, 1)]
                    ok = all(grid.clear(x, z, 1.0) for x, z in corners + [(cx, cz)])
                    ok = ok and free(cx, cz, radius * 0.8)
                    ok = ok and cx < coast_x_at(areas["sea"], cz) - SEA_CLEAR_M
                    ok = ok and not any(point_in_poly(cx, cz, p) for p in blocked_polys)
                    ok = ok and all(math.hypot(cx - l["x"], cz - l["z"]) > LANDMARK_CLEAR_M + radius for l in landmarks)
                    if ok:
                        occupied[(int(cx // 30), int(cz // 30))].append((cx, cz, radius * 0.8))
                        yaw = math.atan2(-dx, -dz)  # building faces along the road
                        out.append({"x": r2(cx), "z": r2(cz), "w": r2(w), "d": r2(d), "h": r2(h),
                                    "yaw": round(yaw, 3), "zone": zid or ""})
                    t += w + rng.uniform(0.5, 3.0)
    return out


def nearest_road_point(edges: list[dict], x: float, z: float) -> tuple[float, float, float, float]:
    """Closest point on the road network, plus the road direction there."""
    best = (math.inf, x, z, 0.0, -1.0)
    for e in edges:
        for a, b in zip(e["pts"], e["pts"][1:]):
            dx, dz = b[0] - a[0], b[1] - a[1]
            l2 = dx * dx + dz * dz
            if l2 == 0:
                continue
            t = max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
            qx, qz = a[0] + t * dx, a[1] + t * dz
            d = math.hypot(x - qx, z - qz)
            if d < best[0]:
                ln = math.sqrt(l2)
                # Spawn on the left carriageway (India drives on the left).
                best = (d, qx - (dz / ln) * e["width"] * 0.25, qz + (dx / ln) * e["width"] * 0.25, dx / ln, dz / ln)
    return best[1], best[2], best[3], best[4]


def main() -> int:
    elements = load_raw()
    edges, nodes = build_roads(elements)
    areas = build_areas(elements)
    landmarks = []
    for l in LANDMARKS:
        x, z = project(l["lat"], l["lon"])
        landmarks.append({"id": l["id"], "name": l["name"], "kind": l["kind"], "x": r2(x), "z": r2(z)})
    buildings = build_buildings(edges, areas, landmarks)

    # Chunk road ribbons and buildings.
    chunks: dict[tuple[int, int], dict] = defaultdict(lambda: {"roads": [], "buildings": []})
    key = lambda x, z: (int(math.floor(x / CHUNK_SIZE_M)), int(math.floor(z / CHUNK_SIZE_M)))  # noqa: E731
    for e in edges:
        piece: list[tuple[float, float]] = [e["pts"][0]]
        cur = None
        for a, b in zip(e["pts"], e["pts"][1:]):
            k = key((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            if cur is not None and k != cur:
                chunks[cur]["roads"].append({"pts": [[r2(x), r2(z)] for x, z in piece], "w": r2(e["width"]), "c": e["cls"]})
                piece = [a]
            cur = k
            piece.append(b)
        if cur is not None:
            chunks[cur]["roads"].append({"pts": [[r2(x), r2(z)] for x, z in piece], "w": r2(e["width"]), "c": e["cls"]})
    for b in buildings:
        chunks[key(b["x"], b["z"])]["buildings"].append(b)

    # Road graph (node ids renumbered compactly).
    ids = {nid: i for i, nid in enumerate(sorted(nodes))}
    graph = {
        "nodes": [[r2(nodes[n][0]), r2(nodes[n][1])] for n in sorted(nodes)],
        "edges": [{"a": ids[e["a"]], "b": ids[e["b"]], "pts": [[r2(x), r2(z)] for x, z in e["pts"]],
                   "w": r2(e["width"]), "lf": e["lanes_fwd"], "lb": e["lanes_back"], "c": e["cls"], "n": e["name"]}
                  for e in edges],
    }

    stands = []
    for s in AUTO_STANDS:
        x, z = project(s["lat"], s["lon"])
        sx, sz, dx, dz = nearest_road_point(edges, x, z)
        stands.append({"id": s["id"], "name": s["name"], "x": r2(sx), "z": r2(sz), "yaw": round(math.atan2(-dx, -dz), 3)})

    xs = [p[0] for p in nodes.values()]
    zs = [p[1] for p in nodes.values()]
    zones = []
    for zid, zc in ZONES.items():
        x, z = project(*zc["center"])
        zones.append({"id": zid, "name": zc["name"], "x": r2(x), "z": r2(z), "r": r2(zc["radius"] * MAP_SCALE)})
    manifest = {
        "version": 1, "attribution": "Map data © OpenStreetMap contributors (ODbL)",
        "map_scale": MAP_SCALE, "chunk_size": CHUNK_SIZE_M, "origin_latlon": list(ORIGIN),
        "bounds": [r2(min(xs)), r2(min(zs)), r2(max(xs)), r2(max(zs))],
        "chunks": sorted([list(k) for k in chunks]),
        "zones": zones, "landmarks": landmarks, "auto_stands": stands,
        "stats": {"edges": len(graph["edges"]), "nodes": len(graph["nodes"]), "buildings": len(buildings),
                  "chunks": len(chunks)},
    }

    (OUT / "chunks").mkdir(parents=True, exist_ok=True)
    for old in (OUT / "chunks").glob("c_*.json"):
        old.unlink()
    for (i, j), c in chunks.items():
        (OUT / "chunks" / f"c_{i}_{j}.json").write_text(json.dumps(c, separators=(",", ":")))
    (OUT / "road_graph.json").write_text(json.dumps(graph, separators=(",", ":")))
    (OUT / "areas.json").write_text(json.dumps(areas, separators=(",", ":")))
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))
    span = (manifest["bounds"][2] - manifest["bounds"][0], manifest["bounds"][3] - manifest["bounds"][1])
    print(f"World: {span[0]:.0f} m × {span[1]:.0f} m | {manifest['stats']} | "
          f"water {len(areas['water'])} beach {len(areas['beach'])} park {len(areas['park'])} sea {len(areas['sea'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
