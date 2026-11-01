#!/usr/bin/env python3
"""Builds data/world/water.json: low-poly water surfaces, banks and bridge railings.

Run after build_world.py (it reads data/world/areas.json and road_graph.json).

Oct 31 device test: the Buckingham-canal crossing on Venkatesa Agraharam Road was blocked by an
invisible wall. The game built a solid kerb on EVERY edge of every water polygon, straight
across the 11 roads that cross water on bridges, and a MultiMesh count reset then erased the
kerb's visuals while its collision stayed. Water itself was a flat blue sheet.

Output (all x/z in world metres):
  "surface": {"v": [x, z, ...], "d": [shore distance m per vertex], "i": [triangle indices]}
      each water polygon filled with a ~GRID_M triangle lattice (interior points + densified
      boundary, Delaunay), so the shader can ripple vertices into low-poly facets and shade
      shallow -> deep / foam by distance from the bank.
  "banks": [[ax, az, bx, bz, kind], ...]  kind 0 = canal parapet, 1 = temple-tank wall
      every water edge EXCEPT where a road carriageway (+ BANK_GAP_M) crosses it.
  "rails": [[ax, az, bx, bz], ...]  bridge parapets along both sides of each road over water,
      run on past each bank by RAIL_OVERRUN_M so nobody drives off the end of a bridge.
  "steps": [[x0, z0, x1, z1, ...] per tank]  inner ghat outline for temple tanks.
Usage: python3 tools/osm/build_water.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from scipy.spatial import Delaunay
from shapely.geometry import LineString, MultiLineString, Point, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
GRID_M = 4.0
BANK_GAP_M = 1.2      # bank stays clear this far beyond each side of a crossing carriageway
RAIL_SIDE_M = 0.35    # rail sits just outside the carriageway edge
BANK_SIDE_M = 0.6     # bank beside a road stands this far outside the carriageway
RAIL_OVERRUN_M = 3.0  # rails continue onto land past each bank
TANK_COMPACTNESS = 0.45  # 4*pi*A/P^2 above this = pond / temple tank, below = canal
GHAT_INSET_M = 5.0


def _r(v: float) -> float:
    return round(float(v), 2)


def fill(poly: Polygon) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Lattice-triangulate `poly`: vertices (N, 2), shore distance (N,), triangles (M, 3)."""
    pts: list[tuple[float, float]] = []
    ring = poly.exterior
    n = max(3, int(math.ceil(ring.length / GRID_M)))
    for k in range(n):
        p = ring.interpolate(k / n, normalized=True)
        pts.append((p.x, p.y))
    minx, miny, maxx, maxy = poly.bounds
    inner = poly.buffer(-GRID_M * 0.45)
    for row, y in enumerate(np.arange(miny + GRID_M * 0.5, maxy, GRID_M * 0.866)):
        off = GRID_M * 0.5 if row % 2 else 0.0  # staggered rows -> near-equilateral facets
        for x in np.arange(minx + off, maxx, GRID_M):
            if inner.contains(Point(x, y)):
                pts.append((x, y))
    v = np.array(pts)
    tri = Delaunay(v).simplices
    keep = [t for t in tri if poly.contains(Point(v[t].mean(0)))]
    d = np.array([poly.exterior.distance(Point(p)) for p in v])
    return v, d, np.array(keep, dtype=int)


def _is_bridge(line: LineString, width: float, w: Polygon) -> bool:
    """True when the road crosses open water (water on both sides of the carriageway along the
    crossing), False when it only grazes or runs along the water's edge."""
    inter = line.intersection(w)
    if inter.is_empty or inter.length < 1.0:
        return False
    for seg in getattr(inter, "geoms", [inter]):
        if seg.geom_type != "LineString":
            continue
        mid = seg.interpolate(0.5, normalized=True)
        if w.exterior.distance(mid) > width * 0.5 + 1.5:
            return True
    return False


def main() -> int:
    areas = json.loads((WORLD / "areas.json").read_text())
    graph = json.loads((WORLD / "road_graph.json").read_text())
    water = [Polygon(p).buffer(0) for p in areas.get("water", []) if len(p) >= 3]
    roads = [(LineString(e["pts"]), float(e["w"]), e.get("n", "")) for e in graph["edges"] if len(e["pts"]) >= 2]

    sv: list[float] = []
    sd: list[float] = []
    si: list[int] = []
    banks: list[list[float]] = []
    rails: list[list[float]] = []
    steps: list[list[float]] = []
    crossings: list[str] = []
    # Roads that run ALONG a bank (OSM tank outlines often reach into the street) push the water
    # back from the carriageway, so the bank wall stands beside the road, not on it. Roads that
    # CROSS water (water on both sides of the carriageway) are bridges and keep the water.
    shrunk = []
    for w in water:
        if w.is_empty:
            continue
        along = []
        for line, width, _name in roads:
            if not line.intersects(w.buffer(width * 0.5 + 0.5)):
                continue
            if _is_bridge(line, width, w):
                continue
            along.append(line.buffer(width * 0.5 + BANK_SIDE_M, cap_style=2))
        if along:
            w = w.difference(unary_union(along))
        for part in getattr(w, "geoms", [w]):
            if part.geom_type == "Polygon" and part.area > 4.0:
                shrunk.append(part)
    water = shrunk
    for w in water:
        if w.is_empty or w.geom_type != "Polygon":
            continue
        v, d, t = fill(w)
        base = len(sv) // 2
        for (x, z), dd in zip(v, d):
            sv += [_r(x), _r(z)]
            sd.append(_r(dd))
        si += (t + base).reshape(-1).tolist()
        compact = 4.0 * math.pi * w.area / (w.length ** 2)
        kind = 1 if compact > TANK_COMPACTNESS else 0
        # Carriageways over this water: no bank across them, parapets along them.
        cuts = []
        for line, width, name in roads:
            if not line.intersects(w) or not _is_bridge(line, width, w):
                continue
            crossings.append(name or "(unnamed)")
            cuts.append(line.buffer(width * 0.5 + BANK_GAP_M, cap_style=2))
            span = line.intersection(w.buffer(RAIL_OVERRUN_M))
            for side in (-1.0, 1.0):
                off = line.offset_curve(side * (width * 0.5 + RAIL_SIDE_M))
                part = off.intersection(w.buffer(RAIL_OVERRUN_M)) if not span.is_empty else off
                for seg in getattr(part, "geoms", [part]):
                    if seg.geom_type != "LineString" or seg.length < 0.5:
                        continue
                    c = list(seg.coords)
                    for a, b in zip(c, c[1:]):
                        rails.append([_r(a[0]), _r(a[1]), _r(b[0]), _r(b[1])])
        edge = w.exterior if not cuts else w.exterior.difference(unary_union(cuts))
        for seg in getattr(edge, "geoms", [edge]):
            if seg.is_empty or seg.geom_type not in ("LineString", "LinearRing"):
                continue
            c = list(seg.coords)
            for a, b in zip(c, c[1:]):
                if math.dist(a, b) > 0.05:
                    banks.append([_r(a[0]), _r(a[1]), _r(b[0]), _r(b[1]), kind])
        if kind == 1:
            ghat = w.buffer(-GHAT_INSET_M, join_style=2)
            if not ghat.is_empty and ghat.geom_type == "Polygon":
                ring: list[float] = []
                for x, z in list(ghat.exterior.coords)[:-1]:
                    ring += [_r(x), _r(z)]
                steps.append(ring)

    out = {"_note": "made by tools/osm/build_water.py from areas.json + road_graph.json",
           "surface": {"v": sv, "d": sd, "i": si}, "banks": banks, "rails": rails, "steps": steps}
    (WORLD / "water.json").write_text(json.dumps(out, separators=(",", ":")))
    print(f"water.json: {len(sd)} verts, {len(si) // 3} tris, {len(banks)} bank segments, "
          f"{len(rails)} rail segments, {len(steps)} tanks; crossings: {sorted(set(crossings))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
