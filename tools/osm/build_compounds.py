#!/usr/bin/env python3
"""Generate compound segments, preserving every mapped access corridor.

--fetch refreshes the supplementary OSM barrier/path extract within config.BBOX.
Mapped walls/fences/hedges keep their source way id. Short party-wall infill between
neighbouring buildings is explicitly labelled inferred, never a surveyed boundary.
One shared building mesh/collider per chunk consumes the generated segments.
"""
from __future__ import annotations
import argparse
import json
import math
import urllib.parse
import urllib.request
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import nearest_points, unary_union
from shapely.strtree import STRtree
from shapely.prepared import prep
from config import BBOX, ORIGIN, CHUNK_SIZE_M
from place_city_props import project

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data/world"
SOURCE = ROOT / "data/osm/chennai_access.osm.json"
GAP_MAX_M = 5.0
WALL_HEIGHT_M = 1.65
WALL_THICKNESS_M = 0.22


def fetch():
    b = ",".join(str(x) for x in BBOX)
    query = f'[out:json][timeout:90];(way["barrier"]({b});node["barrier"]({b});way["highway"~"^(footway|path|pedestrian|service|steps|cycleway|track)$"]({b}););out geom;'
    data = {}
    for host in ("overpass-api.de", "overpass.kumi.systems", "overpass.private.coffee"):
        try:
            req = urllib.request.Request("https://" + host + "/api/interpreter?" + urllib.parse.urlencode({"data": query}),
                                         headers={"User-Agent": "NammaAuto/1.0 OSM compound import"})
            with urllib.request.urlopen(req, timeout=50) as response:
                data = json.load(response)
            if "elements" in data and not data.get("remark"):
                break
        except (OSError, ValueError) as error:
            print(f"{host}: {error}", flush=True)
    if "elements" not in data or data.get("remark"):
        raise RuntimeError("Incomplete Overpass response; keeping previous access extract")
    SOURCE.write_text(json.dumps(data, separators=(",", ":")) + "\n")


def lines(geometry):
    if geometry.geom_type == "LineString":
        yield geometry
    elif hasattr(geometry, "geoms"):
        for part in geometry.geoms:
            yield from lines(part)


def build():
    if not SOURCE.exists():
        raise RuntimeError("Run build_compounds.py --fetch before generating boundaries")
    access = json.loads(SOURCE.read_text())["elements"]
    graph = json.loads((WORLD / "road_graph.json").read_text())
    manifest = json.loads((WORLD / "manifest.json").read_text())
    areas = json.loads((WORLD / "areas.json").read_text())
    clear = [LineString(e["pts"]).buffer(float(e["w"]) / 2 + 2.0) for e in graph["edges"] if len(e["pts"]) > 1]
    for e in access:
        tags = e.get("tags", {})
        coords = [project(p["lat"], p["lon"]) for p in e.get("geometry", [])]
        if tags.get("highway") and len(coords) >= 2:
            clear.append(LineString(coords).buffer(3.0 if tags["highway"] == "service" else 1.5))
        if e.get("type") == "node" and tags.get("barrier") in ("gate", "lift_gate", "entrance", "swing_gate", "bollard"):
            clear.append(Point(project(e["lat"], e["lon"])).buffer(2.5))
    for field in ("water", "sea", "beach", "parks", "park"):
        for poly in areas.get(field, []):
            clear.append(Polygon(poly).buffer(0.5))
    for field in ("auto_stands", "services", "landmarks"):
        clear.extend(Point(p["x"], p["z"]).buffer(30.0) for p in manifest.get(field, []))
    for p in json.loads((WORLD / "city_props.json").read_text()).get("props", []):
        radius = math.hypot(*p.get("block", [3, 3])) + 1.5
        clear.append(Point(p["x"], p["z"]).buffer(radius))
    excluded = unary_union(clear)
    prepared = prep(excluded)
    print("Access corridors prepared", flush=True)
    sx, sz = project(BBOX[0], BBOX[1])
    nx, nz = project(BBOX[2], BBOX[3])
    bounds = box(sx, nz, nx, sz)
    candidates = []
    for e in access:
        if e.get("tags", {}).get("barrier") not in ("wall", "fence", "hedge", "retaining_wall"):
            continue
        coords = [project(p["lat"], p["lon"]) for p in e.get("geometry", [])]
        if len(coords) >= 2:
            candidates.append((LineString(coords), "osm", e["id"]))
    buildings = []
    for path in sorted((WORLD / "chunks").glob("c_*.json")):
        for b in json.loads(path.read_text()).get("blds", []):
            flat = b["p"]
            poly = Polygon(list(zip(flat[::2], flat[1::2])))
            if poly.is_valid and poly.area > 4:
                buildings.append(poly)
    tree = STRtree(buildings)
    for i, a in enumerate(buildings):
        # Only a short separator between close plots, never enclosing guessed parcels.
        for j in tree.query(a.buffer(GAP_MAX_M)):
            if j <= i:
                continue
            b = buildings[j]
            d = a.distance(b)
            if not 1.3 < d < GAP_MAX_M:
                continue
            p, q = nearest_points(a, b)
            segment = LineString([p, q])
            if not prepared.intersects(segment.buffer(0.4)):
                candidates.append((segment, "inferred", 0))
    print(f"{len(candidates)} candidate boundaries", flush=True)
    chunks = {}
    counts = {"osm": 0, "inferred": 0}
    for line, source, way in candidates:
        clipped = line.intersection(bounds)
        if source == "osm":
            clipped = clipped.difference(excluded)
        for part in lines(clipped):
            pts = list(part.coords)
            for a, b in zip(pts, pts[1:]):
                seg = LineString([a, b])
                if seg.length < 0.6:
                    continue
                # Cut exactly at chunk borders, so collision never disappears with a neighbour.
                x0, z0, x1, z1 = seg.bounds
                for x in range(math.floor(x0 / CHUNK_SIZE_M), math.floor(x1 / CHUNK_SIZE_M) + 1):
                    for z in range(math.floor(z0 / CHUNK_SIZE_M), math.floor(z1 / CHUNK_SIZE_M) + 1):
                        tile = box(x * CHUNK_SIZE_M, z * CHUNK_SIZE_M, (x + 1) * CHUNK_SIZE_M, (z + 1) * CHUNK_SIZE_M)
                        for piece in lines(seg.intersection(tile)):
                            if piece.length < 0.1:
                                continue
                            pa, pb = piece.coords[0], piece.coords[-1]
                            chunks.setdefault(f"{x},{z}", []).append([*[round(v, 2) for v in (*pa, *pb)], WALL_HEIGHT_M, WALL_THICKNESS_M, source, way])
                            counts[source] += 1
    output = {"source": "OpenStreetMap contributors, ODbL; inferred segments are procedural", "counts": counts, "chunks": chunks}
    (WORLD / "compounds.json").write_text(json.dumps(output, separators=(",", ":")) + "\n")
    print(counts)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch", action="store_true")
    args = parser.parse_args()
    if args.fetch:
        fetch()
    build()
