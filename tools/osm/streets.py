"""Real road surfaces from A/B Street's osm2streets output (Apache-2.0), for build_world.py.

Reads data/osm/streets/*.geojson.gz (made by run_osm2streets.py in CI) and turns the lane
polygons, junction polygons, kerb corners and the essential lane markings into per-chunk,
pre-triangulated flat meshes. Also reports per-OSM-way driving lanes/width so the AI road
graph lines up with the drawn lanes.

Surface kinds (the game picks colour + layer height per kind, see WorldChunkStreamer.gd):
  road      driving / bus / bike lane polygons
  junction  intersection polygons
  walk      sidewalks, shared-use paths, kerb corners
  centre    centre lines (dashed or solid)
  lane      lane separators
  arrow     turn arrows painted on the lanes
"""
from __future__ import annotations

import gzip
import json
from collections import defaultdict
from pathlib import Path
from typing import Callable

try:
    import mapbox_earcut as earcut  # pip install mapbox-earcut
    import numpy as np
except ImportError:  # pragma: no cover - CI installs these
    earcut = None
    np = None

STREETS = Path(__file__).resolve().parents[2] / "data" / "osm" / "streets"

LANE_KIND = {"Driving": "road", "Bus": "road", "Biking": "road", "Construction": "road",
             "Sidewalk": "walk", "SharedUse": "walk", "Footway": "walk"}
# Lane arrows are ~540k tiny polygons — too heavy as geometry; they come back as decals in the art pass.
MARKING_KIND = {"center line": "centre", "lane separator": "lane"}
DRIVABLE = ("Driving", "Bus")


def available() -> bool:
    return earcut is not None and (STREETS / "lanes.geojson.gz").exists()


def _load(name: str) -> list[dict]:
    p = STREETS / f"{name}.geojson.gz"
    if not p.exists():
        return []
    with gzip.open(p, "rt", encoding="utf-8") as f:
        return json.load(f)["features"]


def _polygons(geom: dict) -> list[list[list[float]]]:
    """GeoJSON Polygon / MultiPolygon → list of polygons, each a list of rings (lon, lat)."""
    if geom["type"] == "Polygon":
        return [geom["coordinates"]]
    if geom["type"] == "MultiPolygon":
        return list(geom["coordinates"])
    return []


def way_lanes() -> dict[int, dict]:
    """OSM way id → {"fwd": n, "back": n, "width": driving width m} from osm2streets lanes."""
    roads: dict[int, dict] = defaultdict(lambda: {"fwd": 0, "back": 0, "width": 0.0, "ways": set()})
    for f in _load("lanes"):
        p = f["properties"]
        if p.get("type") not in DRIVABLE:
            continue
        r = roads[int(p["road"])]
        r["ways"].update(p.get("osm_way_ids", []))
        r["width"] += float(p.get("width", 3.0))
        if p.get("direction") == "Backward":
            r["back"] += 1
        else:
            r["fwd"] += 1  # "Forward" and "Both" (centre turn lanes count once)
    out: dict[int, dict] = {}
    for r in roads.values():
        for w in r["ways"]:
            best = out.get(w)
            if best is None or r["width"] > best["width"]:
                out[w] = {"fwd": r["fwd"], "back": r["back"], "width": r["width"]}
    return out


def build_surfaces(project: Callable[[float, float], tuple[float, float]],
                   chunk_key: Callable[[float, float], tuple[int, int]]) -> tuple[dict, list]:
    """→ ({chunk: {kind: {"v": [x, z, ...], "i": [...]}}}, footprints for the occupancy raster).
    Footprints are (kind, [(x, z), ...]) outer rings in game metres."""
    chunks: dict[tuple[int, int], dict] = defaultdict(lambda: defaultdict(lambda: {"v": [], "i": []}))
    footprints: list[tuple[str, list[tuple[float, float]]]] = []
    stats: dict[str, int] = defaultdict(int)

    def add(kind: str, rings_ll: list[list[list[float]]], layer: int) -> None:
        rings = []
        for ring in rings_ll:
            pts = [project(lat, lon) for lon, lat in ring]
            if len(pts) > 1 and pts[0] == pts[-1]:
                pts = pts[:-1]
            if len(pts) >= 3:
                rings.append(pts)
        if not rings:
            return
        verts = [p for r in rings for p in r]
        ends, n = [], 0
        for r in rings:
            n += len(r)
            ends.append(n)
        tri = earcut.triangulate_float64(np.array(verts, dtype=np.float64).reshape(-1, 2), np.array(ends, dtype=np.uint32))
        if len(tri) == 0:
            return
        cx = sum(p[0] for p in rings[0]) / len(rings[0])
        cz = sum(p[1] for p in rings[0]) / len(rings[0])
        # Elevated roads (flyovers) are still drawn on the ground in the MVP, just a hair higher.
        bucket = chunks[chunk_key(cx, cz)][kind if layer <= 0 else kind + "_up"]
        base = len(bucket["v"]) // 2
        for x, z in verts:
            bucket["v"].extend((round(x, 2), round(z, 2)))
        bucket["i"].extend(int(t) + base for t in tri)
        if kind in ("road", "junction", "walk") and layer <= 0:
            footprints.append((kind, rings[0]))
        stats[kind] += 1

    for f in _load("lanes"):
        p = f["properties"]
        kind = LANE_KIND.get(p.get("type", ""))
        if kind is None:
            continue
        for poly in _polygons(f["geometry"]):
            add(kind, poly, int(p.get("layer", 0) or 0))
    for f in _load("plain"):
        p = f["properties"]
        if p.get("type") != "intersection":
            continue
        for poly in _polygons(f["geometry"]):
            add("junction", poly, 0)
    for f in _load("intersection_markings"):
        if f["properties"].get("type") == "sidewalk corner":
            for poly in _polygons(f["geometry"]):
                add("walk", poly, 0)
    for f in _load("lane_markings"):
        p = f["properties"]
        kind = MARKING_KIND.get(p.get("type", ""))
        if kind is None:
            continue
        for poly in _polygons(f["geometry"]):
            add(kind, poly, int(p.get("layer", 0) or 0))
    print("  osm2streets surfaces: " + ", ".join(f"{k} {v}" for k, v in sorted(stats.items())))
    return {k: {kind: dict(b) for kind, b in v.items()} for k, v in chunks.items()}, footprints


class Raster:
    """Coarse occupancy grid (default 2 m) over the map: roads, water, buildings.
    Used to keep real and filler buildings off the carriageway and off each other."""

    def __init__(self, bounds: tuple[float, float, float, float], cell: float = 2.0) -> None:
        self.x0, self.z0 = bounds[0] - 50.0, bounds[1] - 50.0
        self.cell = cell
        self.w = int((bounds[2] - bounds[0] + 100.0) / cell) + 1
        self.h = int((bounds[3] - bounds[1] + 100.0) / cell) + 1
        self.grid = bytearray(self.w * self.h)

    def _ij(self, x: float, z: float) -> tuple[int, int]:
        return int((x - self.x0) / self.cell), int((z - self.z0) / self.cell)

    def get(self, x: float, z: float) -> int:
        i, j = self._ij(x, z)
        if 0 <= i < self.w and 0 <= j < self.h:
            return self.grid[j * self.w + i]
        return 255

    def fill_polygon(self, poly: list[tuple[float, float]], value: int, grow: float = 0.0) -> None:
        """Scan-line fill of cells whose centre lies inside poly (optionally grown by `grow` m)."""
        if len(poly) < 3:
            return
        zs = [p[1] for p in poly]
        j0 = max(0, int((min(zs) - grow - self.z0) / self.cell))
        j1 = min(self.h - 1, int((max(zs) + grow - self.z0) / self.cell))
        n = len(poly)
        for j in range(j0, j1 + 1):
            zc = self.z0 + (j + 0.5) * self.cell
            xs = []
            for k in range(n):
                (xa, za), (xb, zb) = poly[k], poly[k - 1]
                if (za > zc) != (zb > zc):
                    xs.append(xa + (zc - za) * (xb - xa) / (zb - za))
            xs.sort()
            row = j * self.w
            for a, b in zip(xs[0::2], xs[1::2]):
                i0 = max(0, int((a - grow - self.x0) / self.cell))
                i1 = min(self.w - 1, int((b + grow - self.x0) / self.cell))
                for i in range(i0, i1 + 1):
                    if self.grid[row + i] < value:
                        self.grid[row + i] = value

    def fill_segment(self, a: tuple[float, float], b: tuple[float, float], half_width: float, value: int) -> None:
        dx, dz = b[0] - a[0], b[1] - a[1]
        ln = (dx * dx + dz * dz) ** 0.5
        if ln < 1e-6:
            return
        nx, nz = -dz / ln * half_width, dx / ln * half_width
        self.fill_polygon([(a[0] + nx, a[1] + nz), (b[0] + nx, b[1] + nz), (b[0] - nx, b[1] - nz), (a[0] - nx, a[1] - nz)], value)

    def any_at_least(self, pts: list[tuple[float, float]], value: int) -> bool:
        return any(self.get(x, z) >= value for x, z in pts)
