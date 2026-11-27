#!/usr/bin/env python3
"""Compound walls, railings and gates round Chennai's landmarks -> data/world/landmark_compounds.json.

Nov 27 owner report: "most of the places like the lighthouse or Vivekananda House are not
surrounded with compounds". What the real places look like (Nov 2026 research):

* Marina Lighthouse: on the beach side of Kamarajar Salai where it meets Santhome High Road and
  Dr Radhakrishnan Salai; a fenced garden with a museum and public amenities round the tower.
  -> white plinth with railings, an arched gate to the road.
* Vivekanandar Illam (Ice House): Kamarajar Salai is the only road to the site, which holds the
  Illam, a cultural centre and an outhouse; boards stand either side of the gate.
  -> cream plinth and pillars with black railings, an arched gate on Kamarajar Salai. The landmark
  itself now stands on the land side of the road, facing the sea, as the real one does (it used to
  sit on the beach side).
* Kapaleeshwarar Temple: two entrances, each under a gopuram (east and west, the west one facing
  the tank); the precinct is walled in like every big Tamil temple, in kaavi red-and-white stripes.
  -> a 4.2 m striped wall with openings on the east and west.
* San Thome Basilica: a low white wall with black iron railings round the churchyard and a gate
  to Santhome High Road (owner photos, Nov 27). Never kaavi: the stripes are for Hindu temples.
* LIC Building (Anna Salai): an office compound wall with a gate to the road.
* Panagal Park: a corporation park with green railings on a low plinth and openings on each side.
* Senate House (Nov 27 owner photos + research): it stands in the University's Chepauk campus on
  Kamarajar Salai, seen across its lawn from the road; cream-capped gate piers and black iron
  railings in front. -> "saracenic": red-brick piers banded in cream with little white domed
  finials, black spear railings; a "saracenic" gate (tall domed piers, a striped arch) to the road.
  The infill between the hall and the road is cleared (landmark_models.json "clear_fill").
* Chepauk Palace (Wikipedia, Madras Musings): the Nawab's palace was walled in; its main entrance
  was a Tripolia gate, a triple arch, on Wallajah Road, and its gate pillars carried terracotta
  reliefs. -> "palace_red": a red-brick wall with white crenellated coping and domed piers; a
  "tripolia" gate.
Decoration (Nov 27): every railing pier now has a finial (ball, urn or cap by style) and the
arched gates carry lamps.

How a site is fitted: each landmark has a rectangle (centre, size, yaw), or for a park its mapped
outline. Every side is pulled inwards until it stays clear of the drawn carriageway and footpath,
then the wall is cut wherever it would cross a building, a road, water or a gate opening. Output,
per 250 m chunk: walls [style, x0, z0, x1, z1] and gates [style, x0, z0, x1, z1]. The game merges
them into the chunk's one building mesh and collider (WorldChunkStreamer._landmark_wall), so they
cost no draw calls. Trees standing inside a landmark's own footprint are removed from the dress
files. Run after build_plots.py: python3 tools/osm/build_landmark_compounds.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data/world"
RES = 0.5          # raster metres per cell
STEP = 0.5         # wall sampling step along a side
ROAD_CLEAR_M = 1.5  # keep this far from the carriageway
MAX_PULL = 0.45
PARK_NEAR_M = 30.0  # a park landmark is fenced only along its own mapped outline    # a side may move in by at most this share of the site's half size
WALLS_AVOID_MODELS = ("senate_house", "chepauk_humayun_mahal", "chepauk_kalas_mahal")
CARRIAGEWAY = ("road", "lane", "junction", "centre", "road_up", "lane_up", "junction_up", "centre_up")

# Sites. "rect": centre x, z, width (local x), depth (local z), yaw (radians, local +z = front).
# Gates: (side, offset along the side from its middle in metres, width). Sides: front (+z), back,
# left (-x), right (+x). "keep_out": rectangles (cx, cz, w, d, yaw) the landmark model itself
# stands on (no trees there).
SITES = [
    {"id": "marina_lighthouse", "style": "rail_white", "gate": "arch_white",
     # Front (gate) faces Kamarajar Salai to the west; the west wall stops short of the round
     # building beside the tower, and the gate sits south of it, opposite the open lawn.
     "rect": (2246.3, 1018.0, 46.0, 43.5, -math.pi / 2.0), "gates": [("front", -12.0, 6.0)],
     "keep_out": [(2244.8, 1017.0, 16.0, 16.0, 0.0)]},
    {"id": "vivekananda_house", "style": "rail_cream", "gate": "arch_cream",
     "rect": (2314.0, -6.0, 38.0, 34.0, None), "gates": [("front", 0.0, 6.0)],
     "keep_out": [(2311.95, -5.97, 18.0, 29.0, 0.0)]},
    # The temple fills the Mylapore block between the Mada streets, on the street grid's 15 deg
    # (tools/art/make_landmarks.py KAPALI_COMPOUND_UV); the openings are the two gopurams, which
    # stand in the wall line, so the "gopuram" gate draws no piers of its own.
    {"id": "kapaleeshwarar", "style": "kaavi", "gate": "gopuram",
     "rect": (1181.13, 1690.81, 85.0, 95.0, -math.radians(15.0)), "gates": [("right", -7.5, 25.0), ("left", 3.0, 17.0)],
     "keep_out": []},
    # San Thome Basilica (model: tools/art/make_landmarks.py): a white wall with black iron
    # railings round the churchyard, the gate on Santhome High Road to the west (owner photos).
    {"id": "santhome_basilica", "style": "rail_black", "gate": "church",
     "rect": (2034.0, 1699.57, 96.0, 50.0, -math.radians(14.2)), "gates": [("left", 1.0, 8.0)],
     "keep_out": [(2036.0, 1702.0, 70.0, 38.0, -math.radians(14.2))]},
    # LIC on its real footprint (Nov 27): the slab's long side is on Anna Salai.
    {"id": "lic_building", "style": "wall_grey", "gate": "plain",
     "rect": (769.1, -1680.3, 60.0, 34.0, None), "gates": [("front", 0.0, 7.0), ("left", 0.0, 6.0)],
     "keep_out": [(769.1, -1680.3, 50.0, 21.0, 0.7)]},
    # The mapped Panagal Park (OSM way 209513246) is ~200 m west of the old marker (fixed Nov 27).
    {"id": "panagal_park", "style": "rail_green", "gate": "park", "park": True, "gates_every_m": 45.0, "gate_w": 3.5,
     "anchor": (-2805.0, 845.0)},
    # Senate House: front (+z) on the Kamarajar Salai kerb (owner: seen from the road), local x
    # along the hall (north), as the model.
    {"id": "senate_house", "style": "saracenic", "gate": "saracenic", "anchor": (2594.3, -1778.55),
     "rect": (2611.0, -1775.4, 100.0, 84.0, 1.385), "gates": [("front", 0.0, 8.0), ("front", -34.0, 4.0)],
     "keep_out": []},
    # Chepauk Palace: both mahals, front (+z) north to Wallajah Road on the blocks' 13.7 deg grid.
    {"id": "chepauk_palace", "style": "palace_red", "gate": "tripolia", "anchor": (2458.0, -1610.0),
     "rect": (2455.0, -1612.0, 112.0, 208.0, 2.903), "gates": [("front", 0.0, 11.0), ("right", 30.0, 11.0), ("left", -20.0, 11.0), ("back", 0.0, 11.0)],
     "keep_out": []},
]


def load(path: Path):
    return json.loads(path.read_text())


class Window:
    """Rasters of the drawn surfaces, buildings and water round one site."""

    def __init__(self, cx: float, cz: float, half: float, chunk_size: float):
        self.ox, self.oz = cx - half, cz - half
        self.n = int(2 * half / RES)
        road = Image.new("L", (self.n, self.n), 0)
        walk = Image.new("L", (self.n, self.n), 0)
        bld = Image.new("L", (self.n, self.n), 0)
        water = Image.new("L", (self.n, self.n), 0)
        dr, dw, db, dwat = (ImageDraw.Draw(i) for i in (road, walk, bld, water))
        c0 = (int(math.floor(self.ox / chunk_size)), int(math.floor(self.oz / chunk_size)))
        c1 = (int(math.floor((self.ox + 2 * half) / chunk_size)), int(math.floor((self.oz + 2 * half) / chunk_size)))
        for i in range(c0[0], c1[0] + 1):
            for j in range(c0[1], c1[1] + 1):
                f = WORLD / "chunks" / f"c_{i}_{j}.json"
                if not f.exists():
                    continue
                d = load(f)
                for kind, part in d.get("surf", {}).items():
                    target = dr if kind in CARRIAGEWAY else (dw if kind.removesuffix("_up") == "walk" else None)
                    if target is None:
                        continue
                    v, idx = part["v"], part["i"]
                    for t in range(0, len(idx) - 2, 3):
                        target.polygon([self.px(v[2 * idx[t + k]], v[2 * idx[t + k] + 1]) for k in range(3)], fill=1)
                for b in d.get("blds", []):
                    p = b["p"]
                    db.polygon([self.px(p[2 * k], p[2 * k + 1]) for k in range(len(p) // 2)], fill=1)
        # The procedural landmark models (landmark_models.json) stand where their footprints were.
        # (Not the temple and basilica: their outlines are whole precincts these walls go round.)
        for model in load(WORLD / "landmark_models.json").get("models", []):
            if model["id"] in WALLS_AVOID_MODELS and len(model.get("clear", [])) >= 3:
                db.polygon([self.px(float(q[0]), float(q[1])) for q in model["clear"]], fill=1)
        areas = load(WORLD / "areas.json")
        for kind in ("water", "sea"):
            for poly in areas.get(kind, []):
                if len(poly) >= 3:
                    dwat.polygon([self.px(float(p[0]), float(p[1])) for p in poly], fill=1)
        grow = int(ROAD_CLEAR_M / RES) * 2 + 1
        self.road = np.asarray(road.filter(ImageFilter.MaxFilter(grow)), dtype=bool)
        self.walk = np.asarray(walk, dtype=bool)
        self.bld = np.asarray(bld.filter(ImageFilter.MaxFilter(3)), dtype=bool)
        self.water = np.asarray(water, dtype=bool)

    def px(self, x: float, z: float) -> tuple[float, float]:
        return ((x - self.ox) / RES, (z - self.oz) / RES)

    def cell(self, x: float, z: float) -> tuple[int, int] | None:
        i, j = int((x - self.ox) / RES), int((z - self.oz) / RES)
        return (j, i) if 0 <= i < self.n and 0 <= j < self.n else None

    def street(self, x: float, z: float) -> bool:
        c = self.cell(x, z)
        return c is not None and bool(self.road[c] or self.walk[c])

    def blocked(self, x: float, z: float) -> bool:
        c = self.cell(x, z)
        return c is None or bool(self.road[c] or self.walk[c] or self.bld[c] or self.water[c])

    def nearest_street_dir(self, x: float, z: float) -> tuple[float, float]:
        """Unit vector from (x, z) to the nearest carriageway cell."""
        ys, xs = np.nonzero(self.road)
        if len(xs) == 0:
            return (0.0, 1.0)
        wx = self.ox + (xs + 0.5) * RES
        wz = self.oz + (ys + 0.5) * RES
        k = int(np.argmin((wx - x) ** 2 + (wz - z) ** 2))
        dx, dz = wx[k] - x, wz[k] - z
        n = math.hypot(dx, dz) or 1.0
        return (dx / n, dz / n)


def rect_frame(cx, cz, yaw):
    """Local (x, z) -> world, with local +z = front."""
    c, s = math.cos(yaw), math.sin(yaw)
    return lambda lx, lz: (cx + lx * c + lz * s, cz - lx * s + lz * c)


def blocked_share(win, frame, a, b):
    n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / STEP))
    hits = 0
    for k in range(n + 1):
        t = k / n
        x, z = frame(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        hits += 1 if win.street(x, z) else 0
    return hits / (n + 1)


def fit_rect(site, win):
    cx, cz, w, d, yaw = site["rect"]
    if yaw is None:
        fx, fz = win.nearest_street_dir(cx, cz)
        yaw = math.atan2(fx, fz)  # local +z points at the street
    frame = rect_frame(cx, cz, yaw)
    hw, hd = w / 2.0, d / 2.0
    ext = {"left": -hw, "right": hw, "back": -hd, "front": hd}
    for side in ("front", "back", "left", "right"):
        limit = (hd if side in ("front", "back") else hw) * MAX_PULL
        sign = 1.0 if side in ("front", "right") else -1.0
        pulled = 0.0
        while pulled <= limit:
            if side in ("front", "back"):
                a, b = (ext["left"], ext[side]), (ext["right"], ext[side])
            else:
                a, b = (ext[side], ext["back"]), (ext[side], ext["front"])
            if blocked_share(win, frame, a, b) <= 0.08:
                break
            ext[side] -= sign * STEP
            pulled += STEP
    return frame, ext, yaw


def side_line(ext, side):
    if side == "front":
        return (ext["left"], ext["front"]), (ext["right"], ext["front"])
    if side == "back":
        return (ext["right"], ext["back"]), (ext["left"], ext["back"])
    if side == "left":
        return (ext["left"], ext["back"]), (ext["left"], ext["front"])
    return (ext["right"], ext["front"]), (ext["right"], ext["back"])


def runs(win, points, gate_mask):
    """Consecutive clear samples -> wall segments; clear gate samples -> gate segments."""
    walls, gates = [], []
    cur, cur_gate = [], []

    def close(run, out):
        if len(run) >= 3:
            out.append((run[0], run[-1]))
        run.clear()

    for p, g in zip(points, gate_mask):
        c = win.cell(*p)
        if g:
            close(cur, walls)
            # A gate never stands in a building (Nov 27: a pulled-in front put Chepauk's
            # Tripolia inside Humayun Mahal's facade).
            if c is not None and not win.street(*p) and not win.water[c] and not win.bld[c]:
                cur_gate.append(p)
            else:
                close(cur_gate, gates)
        else:
            close(cur_gate, gates)
            if win.blocked(*p):
                close(cur, walls)
            else:
                cur.append(p)
    close(cur, walls)
    close(cur_gate, gates)
    return walls, gates


def rect_site(site, win):
    frame, ext, yaw = fit_rect(site, win)
    walls, gates = [], []
    for side in ("front", "right", "back", "left"):
        a, b = side_line(ext, side)
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(2, int(length / STEP))
        local = [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n + 1)]
        mid = length / 2.0
        mask = []
        for k in range(n + 1):
            along = length * k / n - mid
            mask.append(any(s == side and abs(along - off) <= gw / 2.0 for s, off, gw in site["gates"]))
        pts = [frame(*p) for p in local]
        w, g = runs(win, pts, mask)
        walls += w
        gates += g
    return walls, gates, yaw


def park_site(site, win, outline):
    walls, gates = [], []
    ring = outline + outline[:1]
    total = 0.0
    pts, mask = [], []
    for a, b in zip(ring, ring[1:]):
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(length / STEP))
        for k in range(n):
            t = k / n
            p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            # Inset 0.6 m into the park so the railing stands on the park side of the kerb.
            pts.append(p)
            mask.append((total + length * t) % site["gates_every_m"] < site["gate_w"])
        total += length
    cx = sum(p[0] for p in outline) / len(outline)
    cz = sum(p[1] for p in outline) / len(outline)
    inset = []
    for x, z in pts:
        dx, dz = cx - x, cz - z
        n = math.hypot(dx, dz) or 1.0
        inset.append((x + dx / n * 0.6, z + dz / n * 0.6))
    # Split at corners so every wall run is straight.
    w, g = runs(win, inset, mask)
    for (a, b) in w:
        walls += straight(a, b, inset)
    gates += g
    return walls, gates


def straight(a, b, pts):
    """Break a run a..b along the sampled outline into straight pieces (≤ 0.25 m off)."""
    i0, i1 = pts.index(a), pts.index(b)
    seg = pts[i0:i1 + 1]
    out = []
    start = 0
    for k in range(2, len(seg)):
        (x0, z0), (x1, z1) = seg[start], seg[k]
        L = math.hypot(x1 - x0, z1 - z0) or 1.0
        off = max(abs((x - x0) * (z1 - z0) - (z - z0) * (x1 - x0)) / L for x, z in seg[start:k + 1])
        if off > 0.25:
            out.append((seg[start], seg[k - 1]))
            start = k - 1
    out.append((seg[start], seg[-1]))
    return [o for o in out if math.hypot(o[1][0] - o[0][0], o[1][1] - o[0][1]) >= 0.8]


def chunk_of(a, b, size):
    mx, mz = (a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0
    return f"{int(math.floor(mx / size))},{int(math.floor(mz / size))}"


def in_rect(x, z, r):
    cx, cz, w, d, yaw = r
    c, s = math.cos(yaw), math.sin(yaw)
    lx = (x - cx) * c - (z - cz) * s
    lz = (x - cx) * s + (z - cz) * c
    return abs(lx) <= w / 2.0 and abs(lz) <= d / 2.0


def clear_trees(keep_outs, size):
    """Drop dress trees standing where a landmark model stands (the Vivekananda House move)."""
    removed = 0
    for r in keep_outs:
        cx, cz, w, d, _ = r
        reach = math.hypot(w, d) / 2.0
        for i in range(int(math.floor((cx - reach) / size)), int(math.floor((cx + reach) / size)) + 1):
            for j in range(int(math.floor((cz - reach) / size)), int(math.floor((cz + reach) / size)) + 1):
                f = WORLD / "dress" / f"c_{i}_{j}.json"
                if not f.exists():
                    continue
                d = load(f)
                trees = d.get("trees", [])
                kept = [t for t in trees if not in_rect(t[0], t[1], r)]
                if len(kept) != len(trees):
                    removed += len(trees) - len(kept)
                    d["trees"] = kept
                    f.write_text(json.dumps(d, separators=(",", ":")))
    return removed


def main() -> int:
    manifest = load(WORLD / "manifest.json")
    size = float(manifest["chunk_size"])
    landmarks = {l["id"]: l for l in manifest["landmarks"]}
    areas = load(WORLD / "areas.json")
    out_walls: dict[str, list] = {}
    out_gates: dict[str, list] = {}
    sites_out = []
    keep_outs = []
    for site in SITES:
        lm = landmarks.get(site["id"])
        if lm is None and site.get("park"):
            continue
        if site.get("park"):
            parks = [[(float(p[0]), float(p[1])) for p in poly] for poly in areas.get("park", []) if len(poly) >= 3]
            if not parks:
                continue
            x, z = site["anchor"] if site.get("anchor") else (float(lm["x"]), float(lm["z"]))
            outline = min(parks, key=lambda poly: min(math.hypot(px - x, pz - z) for px, pz in poly))
            inside = False
            for k in range(len(outline)):
                (x0, z0), (x1, z1) = outline[k - 1], outline[k]
                if (z0 > z) != (z1 > z) and x < x0 + (z - z0) * (x1 - x0) / (z1 - z0):
                    inside = not inside
            if not inside and min(math.hypot(px - x, pz - z) for px, pz in outline) > PARK_NEAR_M:
                print(f"{site['id']}: no mapped park outline within {PARK_NEAR_M:.0f} m, skipped")
                continue
            xs = [p[0] for p in outline]
            zs = [p[1] for p in outline]
            half = max(max(xs) - min(xs), max(zs) - min(zs)) / 2.0 + 20.0
            win = Window((min(xs) + max(xs)) / 2.0, (min(zs) + max(zs)) / 2.0, half, size)
            walls, gates = park_site(site, win, outline)
            yaw = 0.0
        else:
            cx, cz = site["rect"][0], site["rect"][1]
            # Wide enough to find the street the front gate should face.
            win = Window(cx, cz, max(site["rect"][2], site["rect"][3]) + 60.0, size)
            walls, gates, yaw = rect_site(site, win)
        for a, b in walls:
            out_walls.setdefault(chunk_of(a, b, size), []).append([site["style"], round(a[0], 2), round(a[1], 2), round(b[0], 2), round(b[1], 2)])
        for a, b in gates:
            out_gates.setdefault(chunk_of(a, b, size), []).append([site["gate"], round(a[0], 2), round(a[1], 2), round(b[0], 2), round(b[1], 2)])
        length = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in walls)
        sites_out.append({"id": site["id"], "style": site["style"], "walls": len(walls), "gates": len(gates),
                          "wall_m": round(length, 1), "yaw": round(yaw, 3)})
        keep_outs += site.get("keep_out", [])
        print(f"{site['id']}: {len(walls)} wall runs ({length:.0f} m), {len(gates)} gates")
    removed = clear_trees(keep_outs, size)
    print(f"trees removed from landmark footprints: {removed}")
    out = {"_note": "Generated by tools/osm/build_landmark_compounds.py. walls / gates per chunk: [style, x0, z0, x1, z1].",
           "sites": sites_out, "walls": out_walls, "gates": out_gates}
    (WORLD / "landmark_compounds.json").write_text(json.dumps(out, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
