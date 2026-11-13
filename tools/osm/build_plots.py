#!/usr/bin/env python3
"""Plots: the paved ground round every building and the compound wall on its street side.

Before this pass a building stood on bare earth that ran to the kerb. A Chennai plot does not:
shops are paved to the road, flats and houses sit behind a compound wall with a gate, and the
forecourt inside is cement. This writes data/world/plots/c_<i>_<j>.json per 250 m chunk:

    "pave":  {"paver": {"v": [x, z, ...], "i": [...]}, "cement": {...}}   pre-triangulated
    "walls": [[x0, z0, x1, z1, height, thickness, type, seed, zone], ...]  street-side compound walls
    "gates": [[... same fields as a wall ...]]                               one per walled front

Paving = each footprint grown by an apron, plus the strip from every street-facing wall ("fw",
from classify_buildings.py) out to the real road surface. It is drawn just under the road layer,
so roads and footpaths cover its edge. Walls stand parallel to a street front, at least
WALL_KERB_M behind the real road surface (rastered from the osm2streets polygons, never
"graph width / 2"), and are cut wherever anything already stands: trees, poles, parked vehicles,
stalls, carts, transformers, bus stops, signs, signal posts, props, auto stands, service
points, landmarks, quest places, water, parks, other buildings, other walls.

type / seed / zone let the game paint the wall in its building's colour
(BuildingStyles.paint). Needs numpy, pillow, scipy, shapely, mapbox-earcut.

Run after classify_buildings.py (it needs "t" and "fw") and after every dressing pass:
    python3 tools/osm/build_plots.py
"""
from __future__ import annotations

import json
import math
import re
import shutil
import sys
from collections import Counter
from pathlib import Path

import mapbox_earcut as earcut
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import CHUNK_SIZE_M  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
OUT = WORLD / "plots"
MISSIONS = ROOT / "data" / "missions"

PAVER_TYPES = {"sh", "sr", "ht", "bk", "ml", "cn", "of", "hp"}     # open paved frontage, no wall
CEMENT_TYPES = {"fl", "hs", "tn", "sc", "gv", "ch", "mq", "tp", "ah"}
WALL_SETBACK = {"fl": 4.0, "hs": 3.0, "tn": 5.0, "sc": 6.0, "gv": 6.0, "ch": 6.0, "mq": 5.0, "tp": 4.0}
WALL_HEIGHT = {"fl": 1.7, "hs": 1.6, "tn": 1.5, "sc": 2.0, "gv": 2.0, "ch": 1.6, "mq": 1.8, "tp": 2.1}
APRON_M = {"ah": 1.2, "hs": 2.0}
APRON_DEFAULT_M = 2.5
FRONT_REACH_M = 24.0     # a front further than this from the road keeps its bare ground
WALL_KERB_M = 2.6        # clear strip between the road surface and a wall (walkers, poles, trees)
WALL_MIN_SETBACK_M = 1.4 # closer than this the building itself is the street edge: no wall
WALL_THICK_M = 0.23
GATE_THICK_M = 0.1
WALL_SIDE_M = 1.2        # how far a wall runs past the ends of its front
GATE_M = 3.2
MIN_FRONT_M = 5.0
MIN_RUN_M = 1.5
ZONE_IDS = ["", "marina", "mylapore", "anna_salai", "t_nagar"]
CELL = 1.0
SURF_KINDS = ("road", "junction", "walk", "lane", "centre")


class Grid:
    """1 m raster over the whole map."""

    def __init__(self, bounds: list) -> None:
        self.x0, self.z0 = bounds[0] - 60.0, bounds[1] - 60.0
        self.w = int((bounds[2] - bounds[0] + 120.0) / CELL)
        self.h = int((bounds[3] - bounds[1] + 120.0) / CELL)

    def image(self) -> tuple[Image.Image, ImageDraw.ImageDraw]:
        im = Image.new("L", (self.w, self.h), 0)
        return im, ImageDraw.Draw(im)

    def px(self, x: float, z: float) -> tuple[float, float]:
        return (x - self.x0) / CELL, (z - self.z0) / CELL

    def at(self, arr: np.ndarray, x: float, z: float) -> float:
        i, j = int((x - self.x0) / CELL), int((z - self.z0) / CELL)
        if 0 <= i < self.w and 0 <= j < self.h:
            return float(arr[j, i])
        return 0.0


def seed_of(b: dict) -> int:
    """The seed WorldChunkStreamer._typed_building derives, so a wall takes its building's paint."""
    p = b["p"]
    return abs(int(b.get("s", 0)) * 7919 + int(p[0] * 3.0) + int(p[1] * 5.0)) & 0x7FFFFFFF


def triangulate(geom) -> tuple[list, list]:
    verts: list = []
    idx: list = []
    polys = [geom] if geom.geom_type == "Polygon" else [g for g in getattr(geom, "geoms", []) if g.geom_type == "Polygon"]
    for poly in polys:
        if poly.is_empty or poly.area < 1.0:
            continue
        rings = [np.asarray(poly.exterior.coords)[:-1]] + [np.asarray(r.coords)[:-1] for r in poly.interiors]
        rings = [r for r in rings if len(r) >= 3]
        if not rings:
            continue
        pts = np.concatenate(rings).astype(np.float64)
        ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
        tri = earcut.triangulate_float64(pts, ends)
        base = len(verts) // 2
        verts.extend(round(float(v), 2) for xy in pts for v in xy)
        idx.extend(int(t) + base for t in tri)
    return verts, idx


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    grid = Grid(manifest["bounds"])
    files = sorted((WORLD / "chunks").glob("c_*.json"))
    buildings: list = []

    # --- rasters: the real road surface, footprints, everything a wall must not cross ---------
    surf_im, surf_d = grid.image()
    bld_im, bld_d = grid.image()
    keep_im, keep_d = grid.image()
    for f in files:
        d = json.loads(f.read_text())
        for kind, part in d.get("surf", {}).items():
            if kind.removesuffix("_up") not in SURF_KINDS:
                continue
            v, tri = part["v"], part["i"]
            for t in range(0, len(tri), 3):
                surf_d.polygon([grid.px(v[2 * tri[t + k]], v[2 * tri[t + k] + 1]) for k in range(3)], fill=1)
        for b in d.get("blds", []):
            p = b["p"]
            pts = [(p[i], p[i + 1]) for i in range(0, len(p), 2)]
            if len(pts) >= 3:
                bld_d.polygon([grid.px(*q) for q in pts], fill=1)
                buildings.append((b, pts))

    def disc(x: float, z: float, r: float) -> None:
        cx, cz = grid.px(x, z)
        keep_d.ellipse([cx - r / CELL, cz - r / CELL, cx + r / CELL, cz + r / CELL], fill=1)

    radii = {"poles": 0.7, "trees": 1.1, "parking": 1.7, "stalls": 2.3, "barricades": 1.3, "carts": 2.3,
             "beach_fence": 1.2, "xfmr": 2.8}
    for f in sorted((WORLD / "dress").glob("c_*.json")):
        for key, items in json.loads(f.read_text()).items():
            if key in radii:
                for it in items:
                    disc(float(it[0]), float(it[1]), radii[key])
    areas = json.loads((WORLD / "areas.json").read_text())
    area_polys = []
    for polys in areas.values():
        for poly in polys:
            if len(poly) >= 3:
                keep_d.polygon([grid.px(x, z) for x, z in poly], fill=1)
                area_polys.append(Polygon(poly).buffer(0))
    for p in json.loads((WORLD / "city_props.json").read_text()).get("props", []):
        disc(p["x"], p["z"], math.hypot(*p.get("block", [3, 3])) + 1.5)
    for s in json.loads((WORLD / "bus_stops.json").read_text()).get("stops", []):
        disc(s["x"], s["z"], 4.5)
    for s in json.loads((WORLD / "street_signs.json").read_text()):
        disc(s[0], s[1], 0.9)
    for posts in json.loads((WORLD / "signal_posts.json").read_text()).values():
        for s in posts:
            disc(s[0], s[1], 0.9)
    for c in json.loads((WORLD / "carts.json").read_text()):
        disc(c[0], c[1], 2.3)
    works = json.loads((WORLD / "road_works.json").read_text())
    for site in works.get("sites", []):
        disc(site["c"][0], site["c"][1], site["len"] * 0.5 + 6.0)
    for key, r in (("auto_stands", 14.0), ("services", 16.0), ("landmarks", 30.0)):
        for p in manifest.get(key, []):
            disc(p["x"], p["z"], r)
            if "road_x" in p:
                disc(p["road_x"], p["road_z"], r)
    for f in MISSIONS.rglob("*.tres"):
        for m in re.finditer(r"Vector3\(([-\d.]+), [-\d.]+, ([-\d.]+)\)", f.read_text()):
            disc(float(m.group(1)), float(m.group(2)), 7.0)
    wall_im, wall_d = grid.image()   # walls that already stand, so two never run side by side
    compounds = json.loads((WORLD / "compounds.json").read_text()).get("chunks", {}) if (WORLD / "compounds.json").exists() else {}
    for segs in compounds.values():
        for s in segs:
            wall_d.line([grid.px(s[0], s[1]), grid.px(s[2], s[3])], fill=1, width=2)

    surf = np.asarray(surf_im) > 0
    dist_road = ndimage.distance_transform_edt(~surf).astype(np.float32) * CELL
    blocked = (np.asarray(keep_im) > 0) | (np.asarray(bld_im) > 0) | (dist_road < 1.8)
    walls_px = wall_im.load()
    print(f"rasters ready: {len(buildings)} buildings, {int(surf.sum())} m² of road and footpath", flush=True)

    # --- per building: paving polygon, walls, gates ------------------------------------------
    chunks: dict = {}
    paving: list = []   # (polygon, class)
    stats: Counter = Counter()

    def chunk_of(x: float, z: float) -> str:
        return f"{math.floor(x / CHUNK_SIZE_M)},{math.floor(z / CHUNK_SIZE_M)}"

    def free(x: float, z: float) -> bool:
        i, j = int((x - grid.x0) / CELL), int((z - grid.z0) / CELL)
        if not (0 <= i < grid.w and 0 <= j < grid.h):
            return False
        return not blocked[j, i] and not walls_px[i, j]

    def runs(p0: tuple, p1: tuple) -> list:
        """The stretches of p0 → p1 where a wall may stand."""
        L = math.dist(p0, p1)
        n = max(1, int(L / 0.5))
        out, start = [], None
        for k in range(n + 1):
            t = k / n
            ok = free(p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
            if ok and start is None:
                start = t
            if (not ok or k == n) and start is not None:
                end = t if ok else (k - 1) / n
                if (end - start) * L >= MIN_RUN_M:
                    out.append(((p0[0] + (p1[0] - p0[0]) * start, p0[1] + (p1[1] - p0[1]) * start),
                                (p0[0] + (p1[0] - p0[0]) * end, p0[1] + (p1[1] - p0[1]) * end)))
                start = None
        return out

    pending_marks: list = []

    def add_wall(a: tuple, c: tuple, h: float, t: str, seed: int, zone: int) -> None:
        for q0, q1 in runs(a, c):
            # Cut at chunk borders so mesh and collision never vanish with a neighbour.
            L = math.dist(q0, q1)
            cuts = [0.0, 1.0]
            for axis in (0, 1):
                lo, hi = sorted((q0[axis], q1[axis]))
                g = math.floor(lo / CHUNK_SIZE_M) + 1
                while g * CHUNK_SIZE_M < hi:
                    cuts.append((g * CHUNK_SIZE_M - q0[axis]) / (q1[axis] - q0[axis]))
                    g += 1
            cuts.sort()
            for t0, t1 in zip(cuts, cuts[1:]):
                if (t1 - t0) * L < 0.3:
                    continue
                s0 = (q0[0] + (q1[0] - q0[0]) * t0, q0[1] + (q1[1] - q0[1]) * t0)
                s1 = (q0[0] + (q1[0] - q0[0]) * t1, q0[1] + (q1[1] - q0[1]) * t1)
                mid = ((s0[0] + s1[0]) * 0.5, (s0[1] + s1[1]) * 0.5)
                chunks.setdefault(chunk_of(*mid), {"walls": [], "gates": []})["walls"].append(
                    [round(float(s0[0]), 2), round(float(s0[1]), 2), round(float(s1[0]), 2), round(float(s1[1]), 2), h, WALL_THICK_M, t, seed, zone])
                stats["wall_m"] += (t1 - t0) * L
            pending_marks.append((q0, q1))
            stats["walls"] += 1

    for b, pts in buildings:
        t = b.get("t", "")
        if t not in PAVER_TYPES and t not in CEMENT_TYPES:
            continue
        n = len(pts)
        area2 = sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(n))
        sign = 1.0 if area2 > 0 else -1.0
        foot = Polygon(pts).buffer(0)
        if foot.is_empty:
            continue
        parts = [foot.buffer(APRON_M.get(t, APRON_DEFAULT_M), join_style=2, mitre_limit=2.0)]
        seed = seed_of(b)
        zone = ZONE_IDS.index(b.get("z", "")) if b.get("z", "") in ZONE_IDS else 0
        fronts = {int(w[0]) for w in b.get("fw", [])}
        pending_marks.clear()
        for i in sorted(fronts):
            a, c = pts[i - 1], pts[i]
            ex, ez = c[0] - a[0], c[1] - a[1]
            L = math.hypot(ex, ez)
            if L < 2.4:
                continue
            ux, uz = ex / L, ez / L
            nx, nz = uz * sign, -ux * sign
            d = min(grid.at(dist_road, a[0] + ex * f + nx * 0.6, a[1] + ez * f + nz * 0.6) for f in (0.1, 0.3, 0.5, 0.7, 0.9)) + 0.6
            if d > FRONT_REACH_M:
                continue
            reach = d + 1.2
            parts.append(Polygon([(a[0] - ux, a[1] - uz), (c[0] + ux, c[1] + uz),
                                  (c[0] + ux + nx * reach, c[1] + uz + nz * reach), (a[0] - ux + nx * reach, a[1] - uz + nz * reach)]))
            if t not in WALL_SETBACK or L < MIN_FRONT_M:
                continue
            s = min(d - WALL_KERB_M, WALL_SETBACK[t])
            if s < WALL_MIN_SETBACK_M:
                continue
            h = WALL_HEIGHT[t]
            side_a = 0.0 if (i - 1) % n in fronts else WALL_SIDE_M
            side_c = 0.0 if (i + 1) % n in fronts else WALL_SIDE_M
            w0 = (a[0] + nx * s - ux * side_a, a[1] + nz * s - uz * side_a)
            w1 = (c[0] + nx * s + ux * side_c, c[1] + nz * s + uz * side_c)
            wl = math.dist(w0, w1)
            wx, wz = (w1[0] - w0[0]) / wl, (w1[1] - w0[1]) / wl
            gate_w = GATE_M if wl >= 8.0 else 2.6
            centre = wl * (0.5 + ((seed % 7) - 3) * 0.04)
            g0 = (w0[0] + wx * (centre - gate_w * 0.5), w0[1] + wz * (centre - gate_w * 0.5))
            g1 = (w0[0] + wx * (centre + gate_w * 0.5), w0[1] + wz * (centre + gate_w * 0.5))
            before = stats["walls"]
            add_wall(w0, g0, h, t, seed, zone)
            add_wall(g1, w1, h, t, seed, zone)
            # A gate only where the wall actually reached it on at least one side and the gap is clear.
            if stats["walls"] > before and len(runs(g0, g1)) == 1 and math.dist(*runs(g0, g1)[0]) > gate_w - 0.6:
                mid = ((g0[0] + g1[0]) * 0.5, (g0[1] + g1[1]) * 0.5)
                chunks.setdefault(chunk_of(*mid), {"walls": [], "gates": []})["gates"].append(
                    [round(float(g0[0]), 2), round(float(g0[1]), 2), round(float(g1[0]), 2), round(float(g1[1]), 2), h, GATE_THICK_M, t, seed, zone])
                pending_marks.append((g0, g1))
                stats["gates"] += 1
            # Returns from the wall's ends back to the building line.
            if side_a > 0.0:
                add_wall(w0, (a[0] - ux * side_a, a[1] - uz * side_a), h, t, seed, zone)
            if side_c > 0.0:
                add_wall(w1, (c[0] + ux * side_c, c[1] + uz * side_c), h, t, seed, zone)
        for q0, q1 in pending_marks:   # marked after the building is done: its own walls may meet
            wall_d.line([grid.px(*q0), grid.px(*q1)], fill=1, width=3)
        paving.append((unary_union(parts) if len(parts) > 1 else parts[0], "paver" if t in PAVER_TYPES else "cement"))

    print(f"walls: {stats['walls']} runs, {stats['wall_m'] / 1000.0:.1f} km, {stats['gates']} gates", flush=True)

    # --- paving per chunk ---------------------------------------------------------------------
    keep_out = unary_union(area_polys) if area_polys else None
    tree = STRtree([p for p, _ in paving])
    tri_count = 0
    keys = set(chunks)
    for f in files:
        i, j = (int(v) for v in f.stem.split("_")[1:])
        keys.add(f"{i},{j}")
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    written = 0
    for key in sorted(keys):
        i, j = (int(v) for v in key.split(","))
        tile = box(i * CHUNK_SIZE_M, j * CHUNK_SIZE_M, (i + 1) * CHUNK_SIZE_M, (j + 1) * CHUNK_SIZE_M)
        by_class: dict = {"paver": [], "cement": []}
        for k in tree.query(tile):
            by_class[paving[k][1]].append(paving[k][0])
        out = chunks.get(key, {"walls": [], "gates": []})
        pave: dict = {}
        paver = unary_union(by_class["paver"]) if by_class["paver"] else None
        for cls in ("paver", "cement"):
            if not by_class[cls]:
                continue
            geom = paver if cls == "paver" else unary_union(by_class[cls])
            if cls == "cement" and paver is not None:
                geom = geom.difference(paver)
            if keep_out is not None:
                geom = geom.difference(keep_out)
            geom = geom.intersection(tile).simplify(0.25)
            v, idx = triangulate(geom)
            if idx:
                pave[cls] = {"v": v, "i": idx}
                tri_count += len(idx) // 3
        if pave:
            out["pave"] = pave
        if out.get("pave") or out["walls"] or out["gates"]:
            (OUT / f"c_{i}_{j}.json").write_text(json.dumps(out, separators=(",", ":")))
            written += 1
    size = sum(f.stat().st_size for f in OUT.glob("*.json")) / 1e6
    print(f"paving: {tri_count} triangles; wrote {written} files, {size:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
