#!/usr/bin/env python3
"""Finds free ground for the baked Chennai landmark models and writes data/world/city_props.json.

  water_tower   TWAD overhead tanks: one near each neighbourhood, on open ground clear of
                buildings and roads.
  slum_cluster  canal-side settlements: along the Buckingham Canal / Cooum banks, long side
                parallel to the water, canal wall facing it.
  chennai_central  Chennai Central at its real position (just north of the playable map),
                seen on the skyline from the north end of Kamarajar Salai and Napier Bridge.

Reads only generated world data (chunks, road graph, areas) - re-run after an OSM rebuild.
Usage: python3 tools/osm/place_city_props.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
OUT = WORLD / "city_props.json"

# Real Chennai Central (13.0827 N, 80.2757 E) through the build_world projection.
ORIGIN = (13.049, 80.259)
M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))


def project(lat: float, lon: float) -> tuple[float, float]:
    return ((lon - ORIGIN[1]) * M_PER_DEG_LON, -(lat - ORIGIN[0]) * M_PER_DEG_LAT)


def load():
    manifest = json.loads((WORLD / "manifest.json").read_text())
    blds = []
    for c in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{c[0]}_{c[1]}.json").read_text())
        for b in d.get("blds", []):
            p = b["p"]
            pts = [(p[i], p[i + 1]) for i in range(0, len(p), 2)]
            xs = [q[0] for q in pts]
            zs = [q[1] for q in pts]
            blds.append((min(xs), min(zs), max(xs), max(zs), pts))
    graph = json.loads((WORLD / "road_graph.json").read_text())
    segs = []
    for e in graph["edges"]:
        pts = e["pts"]
        for i in range(1, len(pts)):
            segs.append((pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], float(e["w"]) * 0.5))
    areas = json.loads((WORLD / "areas.json").read_text())
    return manifest, blds, segs, areas


class Grid:
    def __init__(self, items, box, cell=50.0):
        self.cell = cell
        self.g: dict = {}
        for it in items:
            x0, z0, x1, z1 = box(it)
            for i in range(int(math.floor(x0 / cell)), int(math.floor(x1 / cell)) + 1):
                for j in range(int(math.floor(z0 / cell)), int(math.floor(z1 / cell)) + 1):
                    self.g.setdefault((i, j), []).append(it)

    def near(self, x0, z0, x1, z1):
        seen = set()
        for i in range(int(math.floor(x0 / self.cell)), int(math.floor(x1 / self.cell)) + 1):
            for j in range(int(math.floor(z0 / self.cell)), int(math.floor(z1 / self.cell)) + 1):
                for it in self.g.get((i, j), []):
                    if id(it) not in seen:
                        seen.add(id(it))
                        yield it


def seg_dist(px, pz, s) -> float:
    ax, az, bx, bz, _ = s
    dx, dz = bx - ax, bz - az
    L = dx * dx + dz * dz
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L))
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))


def point_in(px, pz, poly) -> bool:
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / (zj - zi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def rect_corners(cx, cz, yaw, hx, hz):
    c, s = math.cos(yaw), math.sin(yaw)
    out = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1), (0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
        lx, lz = sx * hx, sz * hz
        out.append((cx + lx * c + lz * s, cz - lx * s + lz * c))
    return out


def free(cx, cz, yaw, hx, hz, bgrid, sgrid, water, road_gap=3.0) -> bool:
    r = math.hypot(hx, hz)
    for b in bgrid.near(cx - r, cz - r, cx + r, cz + r):
        if b[2] < cx - r or b[0] > cx + r or b[3] < cz - r or b[1] > cz + r:
            continue
        for (px, pz) in rect_corners(cx, cz, yaw, hx, hz):
            if point_in(px, pz, b[4]):
                return False
        for (bx, bz) in b[4]:
            # building corner inside our rectangle
            c, s = math.cos(-yaw), math.sin(-yaw)
            lx = (bx - cx) * c + (bz - cz) * s
            lz = -(bx - cx) * s + (bz - cz) * c
            if abs(lx) < hx and abs(lz) < hz:
                return False
    for sg in sgrid.near(cx - r - 20, cz - r - 20, cx + r + 20, cz + r + 20):
        for (px, pz) in rect_corners(cx, cz, yaw, hx, hz):
            if seg_dist(px, pz, sg) < sg[4] + road_gap:
                return False
    for poly in water:
        for (px, pz) in rect_corners(cx, cz, yaw, hx, hz):
            if point_in(px, pz, poly):
                return False
    return True


def main() -> int:
    manifest, blds, segs, areas = load()
    bgrid = Grid(blds, lambda b: (b[0], b[1], b[2], b[3]))
    sgrid = Grid(segs, lambda s: (min(s[0], s[2]) - s[4], min(s[1], s[3]) - s[4], max(s[0], s[2]) + s[4], max(s[1], s[3]) + s[4]))
    water = [[(p[0], p[1]) for p in poly] for poly in areas.get("water", []) + areas.get("sea", []) + areas.get("beach", [])]
    marks = [(float(l["x"]), float(l["z"])) for l in manifest.get("landmarks", [])]
    marks += [(float(s["x"]), float(s["z"])) for s in manifest.get("auto_stands", [])]

    def clear_of_marks(px: float, pz: float, r: float) -> bool:
        return all(math.hypot(px - mx, pz - mz) > r for mx, mz in marks)
    meta = json.loads((ROOT / "assets" / "models" / "city" / "city_models.json").read_text())
    props = []
    cx, cz = project(13.0827, 80.2757)
    props.append({"model": "chennai_central", "x": round(cx, 1), "z": round(cz, 1), "yaw": round(math.pi * 0.5, 3),
                  "skyline": True})
    # Water towers: near each zone centre, spiralling out to the first free spot.
    wt = meta["water_tower"]["size_m"]
    for z in manifest["zones"]:
        placed = False
        for ring in range(20, 80):
            rr = ring * 12.0
            for k in range(int(2 * math.pi * rr / 12.0) + 1):
                a = k * 12.0 / rr
                px, pz = z["x"] + math.cos(a) * rr, z["z"] + math.sin(a) * rr
                if clear_of_marks(px, pz, 150.0) and free(px, pz, 0.0, wt[0] * 0.5 + 2.0, wt[2] * 0.5 + 2.0, bgrid, sgrid, water, 4.0):
                    props.append({"model": "water_tower", "x": round(px, 1), "z": round(pz, 1), "yaw": round(a, 3),
                                  "zone": z["id"]})
                    placed = True
                    break
            if placed:
                break
    # Slums: walk the long canal/river polygons, try spots just off the bank on the land side.
    sl = meta["slum_cluster"]["size_m"]
    hx, hz = sl[0] * 0.5, sl[2] * 0.5
    placed = []
    for poly in sorted(areas.get("water", []), key=lambda p: -len(p)):
        if len(poly) < 8:
            continue
        for i in range(0, len(poly)):
            if len(placed) >= 10:
                break
            ax, az = poly[i - 1]
            bx, bz = poly[i]
            L = math.hypot(bx - ax, bz - az)
            if L < 12.0:
                continue
            mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
            nx, nz = (bz - az) / L, -(bx - ax) / L
            for sign in (1.0, -1.0):
                px, pz = mx + nx * sign * (hz + 3.0), mz + nz * sign * (hz + 3.0)
                if point_in(px, pz, poly):
                    continue
                if any(math.hypot(px - q[0], pz - q[1]) < 250.0 for q in placed):
                    continue
                # Long side along the bank; the model's canal wall (+Z side) faces the water.
                yaw = math.atan2(-sign * nx, -sign * nz)
                if clear_of_marks(px, pz, 150.0) and free(px, pz, yaw, hx, hz, bgrid, sgrid, water, 2.0):
                    props.append({"model": "slum_cluster", "x": round(px, 1), "z": round(pz, 1), "yaw": round(yaw, 3)})
                    placed.append((px, pz))
                    break
    OUT.write_text(json.dumps({"_note": "made by tools/osm/place_city_props.py", "props": props}, indent=1))
    for p in props:
        print(p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
