#!/usr/bin/env python3
"""Builds data/world/bus_stops.json: real MTC bus stops on the game map, on the right kerb.

Source: data/osm/mtc_bus_stops.geojson + data/osm/mtc_route_stops.json.gz, from Reclaim
Chennai's MTC bus map (github.com/magesh-V/mtc-bus-map, web/data, Chennai One network snapshot
of 17 Oct 2026; data from CUMTA / MTC via Chennai One, geometry from OpenStreetMap, ODbL).

For every stop inside the map:
  * snap it to the nearest drivable road edge (within SNAP_M), skipping edge ends (junctions);
  * the side of the road the stop is on picks the travel direction whose LEFT kerb it is
    (India drives on the left; one-way roads keep their only direction);
  * the shelter stands on the footpath SHELTER_BACK_M behind that kerb, facing the road, and is
    pushed along the road (or dropped) so it never stands inside a building footprint;
  * stops of the same name within MERGE_M on the same edge and direction are merged.
Each stop lists the real route numbers that serve it, and "routes" maps every route to its
destination (last stop of its first working), for the destination boards on the buses.

Output: {"stops": [{"x","z","yaw","name","routes":[..],"edge","dir","s"}...], "routes": {..}}
  yaw: shelter front faces the road (rotation about +Y, the shelter's front is +Z).
  edge/dir/s: road graph edge index, travel direction (+1 a->b, -1 b->a) and the stop's
  distance from node a, for TrafficVehicleAI (buses pull in and dwell).
Usage: python3 tools/osm/build_bus_stops.py   (after build_world.py)
"""
from __future__ import annotations

import gzip
import json
import math
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree

from config import ORIGIN

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
SRC_STOPS = ROOT / "data" / "osm" / "mtc_bus_stops.geojson"
SRC_ROUTES = ROOT / "data" / "osm" / "mtc_route_stops.json.gz"
M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))
SNAP_M = 28.0
END_CLEAR_M = 14.0
MERGE_M = 35.0
SHELTER_BACK_M = 1.9   # shelter centre behind the kerb line (it is ~2 m deep)
SHELTER_HALF = (3.1, 1.0)  # half length along the road, half depth
BUS_CLASSES = {"primary", "secondary", "tertiary", "trunk", "primary_link", "secondary_link",
               "tertiary_link", "trunk_link", "unclassified", "residential"}


def project(lat: float, lon: float) -> tuple[float, float]:
    return (lon - ORIGIN[1]) * M_PER_DEG_LON, -(lat - ORIGIN[0]) * M_PER_DEG_LAT


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    x0, z0, x1, z1 = manifest["bounds"]
    graph = json.loads((WORLD / "road_graph.json").read_text())
    edges = graph["edges"]
    lines = []
    idx = []
    for i, e in enumerate(edges):
        if e.get("c") in BUS_CLASSES and len(e["pts"]) >= 2:
            lines.append(LineString(e["pts"]))
            idx.append(i)
    tree = STRtree(lines)
    blds = []
    for f in (WORLD / "chunks").glob("c_*.json"):
        for b in json.loads(f.read_text()).get("blds", []):
            p = b["p"]
            if len(p) >= 6:
                blds.append(Polygon(list(zip(p[0::2], p[1::2]))).buffer(0))
    btree = STRtree(blds)
    routes_raw = json.loads(gzip.decompress(SRC_ROUTES.read_bytes()))
    dest = {}
    for code, r in routes_raw.items():
        d = r.get("d") or []
        if d:
            dest[str(r.get("sn") or code)] = str(d[0].get("e", "")).title()
    stops = []
    for feat in json.loads(SRC_STOPS.read_text())["features"]:
        lon, lat = feat["geometry"]["coordinates"]
        x, z = project(lat, lon)
        if not (x0 + 60 < x < x1 - 60 and z0 + 60 < z < z1 - 60):
            continue
        p = Point(x, z)
        near = tree.query(p.buffer(SNAP_M))
        if len(near) == 0:
            continue
        k = min(near, key=lambda j: lines[j].distance(p))
        line = lines[k]
        if line.distance(p) > SNAP_M:
            continue
        e = edges[idx[k]]
        s = line.project(p)
        if line.length < END_CLEAR_M * 2 + 8:
            continue
        s = min(max(s, END_CLEAR_M), line.length - END_CLEAR_M)
        a = line.interpolate(max(s - 1.0, 0.0))
        b = line.interpolate(min(s + 1.0, line.length))
        tx, tz = b.x - a.x, b.y - a.y
        tl = math.hypot(tx, tz) or 1.0
        tx, tz = tx / tl, tz / tl
        c = line.interpolate(s)
        # Left of travel a->b is (tz, -tx) in x/z (matches RoadGraph: left = (fwd.z, -fwd.x)).
        side = (p.x - c.x) * tz + (p.y - c.y) * (-tx)
        one_way = int(e["lf"]) == 0 or int(e["lb"]) == 0
        if one_way:
            d = 1 if int(e["lf"]) > 0 else -1
        else:
            d = 1 if side >= 0 else -1
        lx, lz = tz * d, -tx * d  # left of the bus's travel direction
        off = float(e["w"]) * 0.5 + SHELTER_BACK_M
        name = str(feat["properties"].get("Stop Name", "")).strip()
        routes = [r.strip() for r in str(feat["properties"].get("route name", "")).split(",") if r.strip()]
        placed = None
        for shift in (0.0, 6.0, -6.0, 12.0, -12.0):
            ss = min(max(s + shift, END_CLEAR_M), line.length - END_CLEAR_M)
            cc = line.interpolate(ss)
            sx, sz = cc.x + lx * off, cc.y + lz * off
            fx, fz = tx * d, tz * d
            corners = [(sx + fx * u * SHELTER_HALF[0] + lx * v * SHELTER_HALF[1], sz + fz * u * SHELTER_HALF[0] + lz * v * SHELTER_HALF[1]) for u, v in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            foot = Polygon(corners)
            if not any(blds[j].intersects(foot) for j in btree.query(foot)):
                placed = (ss, sx, sz)
                break
        if placed is None:
            continue
        ss, sx, sz = placed
        # Shelter front (+Z) faces the road: towards -left.
        yaw = math.atan2(-lx, -lz)
        stops.append({"x": round(sx, 2), "z": round(sz, 2), "yaw": round(yaw, 4), "name": name.title(),
                      "routes": routes, "edge": idx[k], "dir": d,
                      "s": round(ss, 2)})
    # Merge duplicates (both platforms of one stop name on one side, or repeated records).
    merged = []
    for st in sorted(stops, key=lambda q: -len(q["routes"])):
        dup = next((m for m in merged if m["edge"] == st["edge"] and m["dir"] == st["dir"] and abs(m["s"] - st["s"]) < MERGE_M), None)
        if dup is None:
            merged.append(st)
        else:
            dup["routes"] = sorted(set(dup["routes"]) | set(st["routes"]))
    used = sorted({r for m in merged for r in m["routes"]})
    out = {"_note": "made by tools/osm/build_bus_stops.py; stops & routes: CUMTA/MTC via Chennai One "
                    "(Reclaim Chennai MTC bus map), ODbL", "stops": merged,
           "routes": {r: dest.get(r, "") for r in used}}
    (WORLD / "bus_stops.json").write_text(json.dumps(out, separators=(",", ":"), ensure_ascii=False))
    print(f"bus_stops.json: {len(merged)} stops ({len(stops)} before merging), {len(used)} routes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
