#!/usr/bin/env python3
"""Build Namma Auto's streamed world from raw OSM data (pure stdlib, deterministic).

Input : data/osm/chennai_mvp.osm.json.gz   (from fetch_osm.py, © OpenStreetMap contributors, ODbL)
        data/osm/streets/*.geojson.gz       (optional, from run_osm2streets.py: real lane geometry)
Output: data/world/manifest.json            map bounds, chunk list, zones, landmarks, auto stands
        data/world/road_graph.json          drivable graph for AI traffic + GPS (Phase 3)
        data/world/areas.json               sea, water, beach, park polygons (always loaded)
        data/world/chunks/c_<i>_<j>.json    per 250 m chunk:
            "surf"  pre-triangulated osm2streets lanes / junctions / sidewalks / markings
                    (falls back to "roads" centre-line ribbons when osm2streets data is missing)
            "blds"  building footprints (real OSM outlines + procedural fill) with heights

Coordinates: x = east, z = south (Godot -Z is north), metres, scaled by MAP_SCALE (1.0 = real size).
Needs: pip install mapbox-earcut numpy (only for the osm2streets surfaces).
"""
from __future__ import annotations

import gzip
import json
import math
import random
import sys
from collections import defaultdict
from pathlib import Path

import streets
from config import (AUTO_STANDS, FLOOD_SPOTS, SERVICES, BBOX, CHUNK_SIZE_M, DEFAULT_ZONE_STYLE, LANDMARKS, LANE_WIDTH_M,
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


def build_roads(elements: list[dict], lane_info: dict[int, dict]) -> tuple[list[dict], dict]:
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
        # Chennai carriageways are rarely narrower than this, whatever the lane tag says.
        width = max(width, 5.5 if is_oneway else 6.0)
        if is_link:
            width, lanes_total = max(5.0, width * 0.6), max(1, lanes_total // 2)
        lanes_fwd = lanes_back = None
        info = lane_info.get(e["id"])
        if info and info["fwd"] + info["back"] > 0:
            # Match the lanes osm2streets actually draws (Forward = OSM way direction).
            f, b = (info["back"], info["fwd"]) if oneway == "-1" else (info["fwd"], info["back"])
            if is_oneway or (f > 0 and b > 0):
                width = max(4.5, info["width"])
                lanes_fwd, lanes_back = max(1, f + (b if is_oneway else 0)), (0 if is_oneway else b)
                lanes_total = lanes_fwd + lanes_back
        ways.append({"id": e["id"], "cls": cls, "name": tags.get("name", ""), "nodes": nodes, "latlon": latlon,
                     "oneway": is_oneway, "lanes_total": lanes_total, "width": min(width, 24.0),
                     "lf": lanes_fwd, "lb": lanes_back})

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
                    if w["lf"] is not None:
                        lanes_fwd, lanes_back = w["lf"], w["lb"]
                    else:
                        lanes_fwd = w["lanes_total"] if w["oneway"] else max(1, w["lanes_total"] // 2)
                        lanes_back = 0 if w["oneway"] else lanes_fwd
                    edges.append({"a": ids[0], "b": ids[-1], "pts": pts, "len": length, "cls": w["cls"],
                                  "name": w["name"], "oneway": w["oneway"], "width": w["width"],
                                  "lanes_fwd": lanes_fwd, "lanes_back": lanes_back})
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
    _make_strongly_connected(edges)
    return edges, {n: node_pos[n] for n in best if n in node_pos}


def _strong_components(edges: list[dict]) -> dict[int, int]:
    """Kosaraju (iterative) over the directed drivable graph → node → component id."""
    adj, radj = defaultdict(list), defaultdict(list)
    nodes: set[int] = set()
    for e in edges:
        nodes.update((e["a"], e["b"]))
        if e["lanes_fwd"] > 0:
            adj[e["a"]].append(e["b"])
            radj[e["b"]].append(e["a"])
        if e["lanes_back"] > 0:
            adj[e["b"]].append(e["a"])
            radj[e["a"]].append(e["b"])
    order, seen = [], set()
    for s in nodes:
        if s in seen:
            continue
        seen.add(s)
        stack = [(s, 0)]
        while stack:
            v, i = stack.pop()
            if i < len(adj[v]):
                stack.append((v, i + 1))
                w = adj[v][i]
                if w not in seen:
                    seen.add(w)
                    stack.append((w, 0))
            else:
                order.append(v)
    comp: dict[int, int] = {}
    for c, s in enumerate(reversed(order)):
        if s in comp:
            continue
        comp[s] = c
        stack = [s]
        while stack:
            v = stack.pop()
            for w in radj[v]:
                if w not in comp:
                    comp[w] = c
                    stack.append(w)
    return comp


def _make_strongly_connected(edges: list[dict]) -> None:
    """One-way streets clipped at the map edge create traps you can enter but never leave.
    Open those one-ways in both directions until every junction can reach every other."""
    for _ in range(6):
        comp = _strong_components(edges)
        main = max(set(comp.values()), key=list(comp.values()).count)
        changed = 0
        for e in edges:
            if (comp[e["a"]] != main or comp[e["b"]] != main) and e["lanes_back"] == 0:
                e["lanes_back"] = e["lanes_fwd"]
                e["oneway"] = False
                changed += 1
        if changed == 0:
            return
        print(f"  opened {changed} boundary one-ways both ways")


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


# Raster occupancy values (higher wins).
R_WALK, R_PARK, R_BUILDING, R_ROAD, R_WATER = 1, 2, 3, 4, 5
LEVEL_M = 3.2
# OSM building=* → kind used for colour/shape in the game.
BUILDING_KIND = {"temple": "temple", "shrine": "temple", "church": "temple", "mosque": "temple",
                 "commercial": "shop", "retail": "shop", "office": "office", "hotel": "office",
                 "hospital": "office", "school": "civic", "college": "civic", "public": "civic",
                 "civic": "civic", "train_station": "civic", "transportation": "civic", "palace": "civic",
                 "roof": "shed", "garage": "shed", "pavilion": "shed", "greenhouse": "shed", "construction": "shed"}


def make_raster(edges: list[dict], areas: dict, footprints: list) -> streets.Raster:
    xs = [p[0] for e in edges for p in e["pts"]]
    zs = [p[1] for e in edges for p in e["pts"]]
    r = streets.Raster((min(xs), min(zs), max(xs), max(zs)))
    for kind, poly in footprints:
        r.fill_polygon(poly, R_WALK if kind == "walk" else R_ROAD)
    for e in edges:  # graph carriageways too (and the only roads when osm2streets is missing)
        for a, b in zip(e["pts"], e["pts"][1:]):
            r.fill_segment(a, b, e["width"] / 2.0, R_ROAD)
            if not footprints:
                r.fill_segment(a, b, e["width"] / 2.0 + SIDEWALK_M, R_WALK)
    for poly in areas["water"]:
        r.fill_polygon([tuple(p) for p in poly], R_WATER)
    for poly in areas["beach"] + areas["park"]:
        r.fill_polygon([tuple(p) for p in poly], R_PARK)
    return r


def _height_for(tags: dict, area: float, zone: str | None, rng: random.Random) -> float:
    for key in ("height", "building:height"):
        try:
            return max(2.5, min(150.0, float(str(tags[key]).split()[0])))
        except (KeyError, ValueError):
            pass
    try:
        levels = float(str(tags["building:levels"]).split(";")[0])
        return max(1.0, min(40.0, levels)) * LEVEL_M + 0.6
    except (KeyError, ValueError):
        pass
    kind = BUILDING_KIND.get(tags.get("building", ""), "")
    if kind == "shed":
        return rng.uniform(3.0, 4.5)
    lo, hi = (ZONES[zone] if zone else DEFAULT_ZONE_STYLE)["bld_height"]
    # Chennai rule of thumb: tiny plots are 1–2 floor houses, big footprints are blocks.
    if area < 60.0:
        floors = rng.choice((1, 1, 2, 2, 3))
    elif area < 250.0:
        floors = rng.choice((2, 2, 3, 3, 4))
    elif area < 1200.0:
        floors = rng.randint(3, 6)
    else:
        floors = rng.randint(3, 10)
    return max(3.2, min(hi * 1.3, max(lo * 0.6, floors * LEVEL_M + 0.6)))


def build_real_buildings(elements: list[dict], raster: streets.Raster, clear_pts: list[tuple[float, float, float]]) -> list[dict]:
    """Real OSM footprints, extruded. Dropped if they sit on a carriageway or in water."""
    rng = random.Random(600004)
    inv_lat = 1.0 / (M_PER_DEG_LAT * MAP_SCALE)
    inv_lon = 1.0 / (M_PER_DEG_LON * MAP_SCALE)
    out, dropped = [], 0
    for e in elements:
        tags = e.get("tags", {})
        geom = e.get("geometry") or []
        if e.get("type") != "way" or "building" not in tags or len(geom) < 4:
            continue
        if tags.get("building") in ("no", "ruins") or str(tags.get("layer", "0")).startswith("-"):
            continue
        pts = [project(g["lat"], g["lon"]) for g in geom]
        if pts[0] == pts[-1]:
            pts = pts[:-1]
        if len(pts) >= 4:
            pts = simplify(pts + [pts[0]], 0.3)[:-1]
        if len(pts) < 3:
            continue
        area = poly_area(pts)
        if area < 12.0:
            continue
        cx, cz = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
        on_road = sum(1 for x, z in pts if raster.get(x, z) == R_ROAD)
        if raster.get(cx, cz) in (R_ROAD, R_WATER) or on_road * 2 > len(pts):
            dropped += 1
            continue
        if any(math.hypot(cx - x, cz - z) < r for x, z, r in clear_pts):
            dropped += 1
            continue
        zid = zone_of(ORIGIN[0] - cz * inv_lat, ORIGIN[1] + cx * inv_lon)
        h = _height_for(tags, area, zid, rng)
        # Wind counter-clockwise seen from above (+y) so walls face outwards.
        signed = sum(pts[i][0] * pts[i - 1][1] - pts[i - 1][0] * pts[i][1] for i in range(len(pts)))
        if signed < 0:
            pts.reverse()
        raster.fill_polygon(pts, R_BUILDING, grow=0.5)
        out.append({"p": [v for x, z in pts for v in (r2(x), r2(z))], "h": r2(h),
                    "k": BUILDING_KIND.get(tags.get("building", ""), "shop" if "shop" in tags else ""),
                    "z": zid or "", "s": e["id"] % 9973, "cx": cx, "cz": cz})
    print(f"  real buildings: {len(out)} kept, {dropped} dropped (on roads / landmarks)")
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


def build_fill_buildings(edges: list[dict], areas: dict, raster: streets.Raster, clear_pts: list) -> list[dict]:
    """Procedural boxes along graph roads where OSM has no mapped buildings yet."""
    rng = random.Random(600004)  # Mylapore PIN — deterministic city
    inv_lat = 1.0 / (M_PER_DEG_LAT * MAP_SCALE)
    inv_lon = 1.0 / (M_PER_DEG_LON * MAP_SCALE)
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
                    zid = zone_of(ORIGIN[0] - pz * inv_lat, ORIGIN[1] + px * inv_lon)
                    style = ZONES[zid] if zid else DEFAULT_ZONE_STYLE
                    w = rng.uniform(8.0, 15.0)
                    if rng.random() > style["bld_density"]:
                        t += w
                        continue
                    d = rng.uniform(8.0, 14.0)
                    h = rng.uniform(*style["bld_height"])
                    off = hw + SIDEWALK_M + 0.5 + d / 2.0
                    cx, cz = px + dx * (w / 2.0) + nx * off, pz + dz * (w / 2.0) + nz * off
                    corners = [(cx + dx * sx * w / 2 + nx * sz * d / 2, cz + dz * sx * w / 2 + nz * sz * d / 2)
                               for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                    probe = corners + [(cx, cz)] + [((p[0] + q[0]) / 2, (p[1] + q[1]) / 2) for p, q in zip(corners, corners[1:] + corners[:1])]
                    ok = all(raster.get(x, z) == 0 for x, z in probe)
                    ok = ok and cx < coast_x_at(areas["sea"], cz) - SEA_CLEAR_M
                    ok = ok and all(math.hypot(cx - x, cz - z) > r + math.hypot(w, d) / 2 for x, z, r in clear_pts)
                    if ok:
                        signed = sum(corners[i][0] * corners[i - 1][1] - corners[i - 1][0] * corners[i][1] for i in range(4))
                        if signed < 0:
                            corners.reverse()
                        raster.fill_polygon(corners, R_BUILDING, grow=1.0)
                        out.append({"p": [v for x, z in corners for v in (r2(x), r2(z))], "h": r2(h), "k": "",
                                    "z": zid or "", "s": rng.randrange(9973), "cx": cx, "cz": cz, "f": 1})
                    t += w + rng.uniform(0.5, 3.0)
    print(f"  fill buildings: {len(out)}")
    return out


def nearest_road_point(edges: list[dict], x: float, z: float, side: float = 0.25) -> tuple[float, float, float, float]:
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
                # Left of heading (dx, dz) is (dz, -dx): India drives on the left.
                best = (d, qx + (dz / ln) * e["width"] * side, qz - (dx / ln) * e["width"] * side, dx / ln, dz / ln)
    return best[1], best[2], best[3], best[4]


def main() -> int:
    elements = load_raw()
    use_streets = streets.available()
    if not use_streets:
        print("  osm2streets data or mapbox-earcut missing → centre-line road ribbons only")
    edges, nodes = build_roads(elements, streets.way_lanes() if use_streets else {})
    areas = build_areas(elements)
    key = lambda x, z: (int(math.floor(x / CHUNK_SIZE_M)), int(math.floor(z / CHUNK_SIZE_M)))  # noqa: E731
    surfaces, footprints = streets.build_surfaces(project, key) if use_streets else ({}, [])
    landmarks = []
    for l in LANDMARKS:
        x, z = project(l["lat"], l["lon"])
        yaw = 0.0
        if l["kind"] in ("flyover", "bridge"):
            # Sits on the road it carries.
            x, z, dx, dz = nearest_road_point(edges, x, z, side=0.0)
            yaw = math.atan2(-dx, -dz)
        elif l["kind"] == "tower":
            # Roadside: snap to the nearest road, then step back off the carriageway.
            rx, rz, dx, dz = nearest_road_point(edges, x, z, side=0.0)
            ox, oz = x - rx, z - rz
            n = math.hypot(ox, oz) or 1.0
            x, z = rx + ox / n * 26.0, rz + oz / n * 26.0
        landmarks.append({"id": l["id"], "name": l["name"], "kind": l["kind"], "x": r2(x), "z": r2(z), "yaw": round(yaw, 3)})
    services = []
    for sv in SERVICES:
        x, z = project(sv["lat"], sv["lon"])
        rx, rz, dx, dz = nearest_road_point(edges, x, z, side=0.0)
        # Park bay just off the kerb on the side the real location is on.
        nx, nz = dz, -dx  # left of travel
        side = 1.0 if (x - rx) * nx + (z - rz) * nz >= 0 else -1.0
        w = next((e["width"] for e in edges if any(math.hypot(px - rx, pz - rz) < 0.5 for px, pz in e["pts"][:1])), 9.0)
        off = w / 2.0 + 6.0
        services.append({"id": sv["id"], "name": sv["name"], "kind": sv["kind"],
                         "x": r2(rx + nx * side * off), "z": r2(rz + nz * side * off),
                         "road_x": r2(rx), "road_z": r2(rz), "yaw": round(math.atan2(-dx, -dz), 3)})
    floods = []
    for fl in FLOOD_SPOTS:
        x, z, _dx, _dz = nearest_road_point(edges, *project(fl["lat"], fl["lon"]), side=0.0)
        floods.append({"id": fl["id"], "name": fl["name"], "x": r2(x), "z": r2(z), "depth": fl["depth"], "r": fl["r"]})
    # Keep buildings off landmark placeholders and service bays.
    clear_r = {"lighthouse": 14.0, "gopuram": 22.0, "tower": 16.0, "heritage": 22.0}
    clear_pts = [(l["x"], l["z"], clear_r[l["kind"]]) for l in landmarks if l["kind"] in clear_r]
    clear_pts += [(s_["x"], s_["z"], 9.0) for s_ in services]
    raster = make_raster(edges, areas, footprints)
    buildings = build_real_buildings(elements, raster, clear_pts)
    buildings += build_fill_buildings(edges, areas, raster, clear_pts)

    # Chunk road surfaces and buildings.
    chunks: dict[tuple[int, int], dict] = defaultdict(dict)
    for k, surf in surfaces.items():
        chunks[k]["surf"] = surf
    for e in edges if not use_streets else ():  # centre-line ribbons only without osm2streets
        piece: list[tuple[float, float]] = [e["pts"][0]]
        cur = None
        for a, b in zip(e["pts"], e["pts"][1:]):
            k = key((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            if cur is not None and k != cur:
                chunks[cur].setdefault("roads", []).append({"pts": [[r2(x), r2(z)] for x, z in piece], "w": r2(e["width"]), "c": e["cls"]})
                piece = [a]
            cur = k
            piece.append(b)
        if cur is not None:
            chunks[cur].setdefault("roads", []).append({"pts": [[r2(x), r2(z)] for x, z in piece], "w": r2(e["width"]), "c": e["cls"]})
    for b in buildings:
        chunks[key(b.pop("cx"), b.pop("cz"))].setdefault("blds", []).append(b)

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
        "version_world": 2, "road_source": "osm2streets" if use_streets else "centreline",
        "map_scale": MAP_SCALE, "chunk_size": CHUNK_SIZE_M, "origin_latlon": list(ORIGIN),
        "bounds": [r2(min(xs)), r2(min(zs)), r2(max(xs)), r2(max(zs))],
        "chunks": sorted([list(k) for k in chunks]),
        "zones": zones, "landmarks": landmarks, "auto_stands": stands, "services": services, "flood_spots": floods,
        "stats": {"edges": len(graph["edges"]), "nodes": len(graph["nodes"]), "buildings": len(buildings),
                  "real_buildings": sum(1 for b in buildings if not b.get("f")),
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
