#!/usr/bin/env python3
"""What each building IS and which of its walls face a street.

OSM tags 98 % of the footprints in our box as plain building=yes, so the city used to draw
every one of them as the same flat block. Real Chennai streets read from what stands on them:
shop rows with boards on every main road, silk and jewellery showrooms in T. Nagar, flats on
stilt parking in the residential streets, old tiled houses round the Mylapore tank and in
Triplicane, housing-board tenements and fishing hamlets behind the Marina. This pass works
that out from data we already have and writes it into every building in data/world/chunks:

    "t":  building type (see TYPES)
    "fw": [[wall index, road rank], ...]  the walls that look onto a street with nothing in
          between. Wall i runs from point i-1 to point i (the order WorldChunkStreamer walks
          them). Rank: 4 primary/trunk, 3 secondary, 2 tertiary, 1 lane. Bazaar streets +1.

Inputs: the chunks themselves (footprint, height, zone, OSM kind), data/world/road_graph.json
(road class, name, width), data/world/areas.json (beach) and data/osm/chennai_pois.json.gz
(schools, hospitals, places of worship, banks, hotels, cinemas, malls).

It only adds those two keys, so it can re-run any time. Run it LAST in a map rebuild (after
fill_empty_lots.py and add_lodges_eateries.py, which add buildings):
    python3 tools/osm/classify_buildings.py
The game still draws a chunk that lacks the keys (it falls back to the old look).
"""
from __future__ import annotations

import gzip
import json
import math
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import MAP_SCALE, ORIGIN  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
POIS = ROOT / "data" / "osm" / "chennai_pois.json.gz"
M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))

# Type codes (kept short: 50k buildings carry one).
TYPES = {
    "sh": "shop row: shops below, homes or offices above",
    "sr": "showroom: silks / jewellery / furniture, cladding and a giant board",
    "of": "office block",
    "fl": "flats on stilt parking, balconies",
    "hs": "independent house",
    "ah": "old tiled house (agraharam / Triplicane)",
    "kp": "small dwelling (fishing hamlet, back lane)",
    "tn": "housing-board tenement block",
    "sc": "school / college", "hp": "hospital / clinic", "ch": "church", "mq": "mosque",
    "tp": "temple", "bk": "bank", "ht": "hotel / lodge", "cn": "cinema", "ml": "mall",
    "gv": "government / civic", "sd": "shed",
}
CLASS_RANK = {"motorway": 4, "trunk": 4, "primary": 4, "secondary": 3, "tertiary": 2}
# Streets that are shops end to end whatever their road class.
BAZAARS = ("ranganathan", "usman", "thyagaraya", "pondy bazaar", "panagal", "luz church", "mada street",
           "kutchery", "triplicane high", "pycrofts", "bharathi salai", "royapettah high", "ritchie",
           "ellis", "wallajah", "general patters", "whites road", "woods road", "north usman",
           "south usman", "burkit", "doraiswamy", "g.n. chetty", "gn chetty", "venkatanarayana",
           "cathedral", "radhakrishnan", "ttk", "eldams", "c.p. ramaswamy", "cp ramaswamy", "r.k. mutt",
           "ramakrishna mutt", "santhome high", "dr. besant", "besant road", "peters road", "lloyds",
           "avvai shanmugam", "nungambakkam high", "kodambakkam high", "anna salai", "mount road")
# Old quarters where tiled houses survive (lat, lon, radius m).
OLD_QUARTERS = [(13.0335, 80.2690, 650.0), (13.0585, 80.2760, 700.0), (13.0460, 80.2690, 350.0)]
POI_TYPE = {
    ("amenity", "school"): "sc", ("amenity", "college"): "sc", ("amenity", "university"): "sc",
    ("amenity", "kindergarten"): "sc", ("amenity", "library"): "gv",
    ("amenity", "hospital"): "hp", ("amenity", "clinic"): "hp",
    ("amenity", "bank"): "bk", ("tourism", "hotel"): "ht", ("tourism", "guest_house"): "ht",
    ("tourism", "hostel"): "ht", ("amenity", "cinema"): "cn", ("shop", "mall"): "ml",
    ("shop", "department_store"): "sr", ("shop", "clothes"): "sr", ("shop", "jewelry"): "sr",
    ("shop", "furniture"): "sr", ("shop", "electronics"): "sr", ("shop", "car"): "sr",
    ("office", "government"): "gv", ("amenity", "police"): "gv", ("amenity", "post_office"): "gv",
    ("amenity", "courthouse"): "gv", ("amenity", "townhall"): "gv", ("amenity", "fire_station"): "gv",
}
RELIGION_TYPE = {"christian": "ch", "muslim": "mq", "hindu": "tp", "jain": "tp", "sikh": "tp", "buddhist": "tp"}
KIND_TYPE = {"temple": "tp", "office": "of", "civic": "gv", "shed": "sd", "shop": "sh"}

FRONT_MAX_M = 26.0   # a wall further than this from a carriageway edge does not face it
MIN_WALL_M = 3.0
CELL = 1.0           # occupancy raster for the "nothing in between" test
GRID = 60.0          # spatial hash for road segments


def project(lat: float, lon: float) -> tuple[float, float]:
    return ((lon - ORIGIN[1]) * M_PER_DEG_LON * MAP_SCALE, -(lat - ORIGIN[0]) * M_PER_DEG_LAT * MAP_SCALE)


def hash01(seed: int, salt: int) -> float:
    """Deterministic 0..1 from the building seed (no RNG state, so re-runs never drift)."""
    v = (seed * 2654435761 + salt * 40503 + 12345) & 0xFFFFFFFF
    v ^= v >> 15
    v = (v * 2246822519) & 0xFFFFFFFF
    v ^= v >> 13
    return (v & 0xFFFF) / 65536.0


def load_roads() -> tuple[dict, list]:
    g = json.loads((WORLD / "road_graph.json").read_text())
    segs = []  # (ax, az, bx, bz, half width, rank)
    for e in g["edges"]:
        name = str(e.get("n", "")).lower()
        rank = CLASS_RANK.get(e.get("c", ""), 1)
        if any(b in name for b in BAZAARS):
            rank = min(5, max(rank, 2) + 1)
        half = float(e.get("w", 3.3)) * max(1, int(e.get("lf", 1)) + int(e.get("lb", 0))) * 0.5
        pts = e["pts"]
        for i in range(len(pts) - 1):
            segs.append((pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], half, rank))
    grid: dict = {}
    for k, s in enumerate(segs):
        x0, x1 = sorted((s[0], s[2]))
        z0, z1 = sorted((s[1], s[3]))
        for gx in range(int(math.floor(x0 / GRID)), int(math.floor(x1 / GRID)) + 1):
            for gz in range(int(math.floor(z0 / GRID)), int(math.floor(z1 / GRID)) + 1):
                grid.setdefault((gx, gz), []).append(k)
    return grid, segs


def nearest_on_seg(px: float, pz: float, s: tuple) -> tuple[float, float]:
    ax, az, bx, bz = s[0], s[1], s[2], s[3]
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L2))
    return ax + dx * t, az + dz * t


def footprint_distance(x: float, z: float, p: list) -> float:
    """0 inside the footprint, else the distance to its nearest wall."""
    n = len(p) // 2
    inside = False
    best = 1e9
    for i in range(n):
        ax, az, bx, bz = p[2 * i - 2], p[2 * i - 1], p[2 * i], p[2 * i + 1]
        if (az > z) != (bz > z) and x < (bx - ax) * (z - az) / (bz - az) + ax:
            inside = not inside
        qx, qz = nearest_on_seg(x, z, (ax, az, bx, bz))
        best = min(best, math.hypot(qx - x, qz - z))
    return 0.0 if inside else best


def classify(chunks_dir: Path = WORLD / "chunks", write: bool = True) -> Counter:
    files = sorted(chunks_dir.glob("c_*.json"))
    data = {f: json.loads(f.read_text()) for f in files}
    blds = [(f, i, b) for f, d in data.items() for i, b in enumerate(d.get("blds", []))]

    # Occupancy raster of every footprint, to test that a wall really sees the road.
    xs = [v for _, _, b in blds for v in b["p"][0::2]]
    zs = [v for _, _, b in blds for v in b["p"][1::2]]
    ox, oz = math.floor(min(xs)) - 40.0, math.floor(min(zs)) - 40.0
    W, H = int((max(xs) - ox + 80.0) / CELL), int((max(zs) - oz + 80.0) / CELL)
    img = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(img)
    for _, _, b in blds:
        p = b["p"]
        draw.polygon([((p[i] - ox) / CELL, (p[i + 1] - oz) / CELL) for i in range(0, len(p), 2)], fill=1)
    occ = np.asarray(img)

    def blocked(x0: float, z0: float, x1: float, z1: float) -> bool:
        n = max(2, int(math.hypot(x1 - x0, z1 - z0) / 1.5))
        for k in range(1, n):
            t = k / n
            cx, cz = int((x0 + (x1 - x0) * t - ox) / CELL), int((z0 + (z1 - z0) * t - oz) / CELL)
            if 0 <= cx < W and 0 <= cz < H and occ[cz, cx]:
                return True
        return False

    grid, segs = load_roads()
    areas = json.loads((WORLD / "areas.json").read_text())
    beach_pts = [pt for poly in areas.get("beach", []) for pt in poly]
    old = [(project(la, lo), r) for la, lo, r in OLD_QUARTERS]

    # POIs → the footprint they sit in (or the nearest centroid within 18 m).
    cents = []
    for _, _, b in blds:
        p = b["p"]
        n = len(p) // 2
        cents.append((sum(p[0::2]) / n, sum(p[1::2]) / n))
    cgrid: dict = {}
    for k, (cx, cz) in enumerate(cents):
        cgrid.setdefault((int(cx // 40), int(cz // 40)), []).append(k)
    poi_type: dict = {}
    if POIS.exists():
        for e in json.loads(gzip.open(POIS).read())["elements"]:
            tags = e.get("tags", {})
            lat = e.get("lat", (e.get("center") or {}).get("lat"))
            lon = e.get("lon", (e.get("center") or {}).get("lon"))
            if lat is None:
                continue
            t = None
            if tags.get("amenity") == "place_of_worship":
                t = RELIGION_TYPE.get(tags.get("religion", ""), None)
            for key in ("amenity", "shop", "tourism", "office"):
                t = t or POI_TYPE.get((key, tags.get(key, "")))
            if t is None:
                continue
            x, z = project(lat, lon)
            # The footprint the POI stands in; failing that one whose wall is within 5 m.
            best, best_d = -1, 5.0
            for gx in (-2, -1, 0, 1, 2):
                for gz in (-2, -1, 0, 1, 2):
                    for k in cgrid.get((int(x // 40) + gx, int(z // 40) + gz), []):
                        d = footprint_distance(x, z, blds[k][2]["p"])
                        if d < best_d:
                            best, best_d = k, d
            if best < 0:
                continue
            # A shrine, church or mosque is a low building of its own, not five floors of offices.
            if t in ("tp", "ch", "mq") and float(blds[best][2]["h"]) > 14.0:
                continue
            poi_type.setdefault(best, t)

    counts: Counter = Counter()
    fronts = 0
    for k, (_, _, b) in enumerate(blds):
        p = b["p"]
        pts = [(p[i], p[i + 1]) for i in range(0, len(p), 2)]
        n = len(pts)
        area2 = sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(n))
        sign = 1.0 if area2 > 0 else -1.0
        area = abs(area2) * 0.5
        fw = []
        for i in range(n):
            (ax, az), (bx, bz) = pts[i - 1], pts[i]
            ex, ez = bx - ax, bz - az
            L = math.hypot(ex, ez)
            if L < MIN_WALL_M:
                continue
            nx, nz = ez / L * sign, -ex / L * sign
            mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
            best_rank, best_d = 0, 1e9
            for gx in range(int((mx - 45) // GRID), int((mx + 45) // GRID) + 1):
                for gz in range(int((mz - 45) // GRID), int((mz + 45) // GRID) + 1):
                    for si in grid.get((gx, gz), []):
                        s = segs[si]
                        qx, qz = nearest_on_seg(mx, mz, s)
                        dx, dz = qx - mx, qz - mz
                        d = math.hypot(dx, dz)
                        edge_d = d - s[4]
                        if edge_d > FRONT_MAX_M or d < 0.01 or (dx * nx + dz * nz) / d < 0.55:
                            continue
                        # Prefer the nearer road; a main road wins a near tie.
                        if edge_d - s[5] * 1.5 < best_d - best_rank * 1.5:
                            if not blocked(mx + nx * 1.2, mz + nz * 1.2, qx, qz):
                                best_rank, best_d = s[5], edge_d
            if best_rank:
                fw.append((i, best_rank, L))
        fw.sort(key=lambda w: (-w[1], -w[2]))
        fw = fw[:4]
        rank = fw[0][1] if fw else 0
        front_len = fw[0][2] if fw else 0.0
        cx, cz = cents[k]
        h = float(b["h"])
        seed = int(b.get("s", 0)) + int(cx * 3.1) + int(cz * 1.7)
        zone = b.get("z", "")
        in_old = any(math.hypot(cx - c[0], cz - c[1]) < r for c, r in old)
        near_beach = any(abs(cx - bx_) < 260 and abs(cz - bz_) < 260 for bx_, bz_ in beach_pts[::6]) if beach_pts else False
        # Longest side / shortest side of the bounding box along the longest wall.
        longest = max((math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]) for i in range(n)), default=1.0)
        slender = longest * longest / max(area, 1.0)

        t = KIND_TYPE.get(b.get("k", ""))
        if t is None or t == "sh":
            t = poi_type.get(k, t)
        if t is None and b.get("f") == 3:
            t = "ht"
        if t is None:
            r1, r2, r3 = hash01(seed, 1), hash01(seed, 2), hash01(seed, 3)
            commercial = rank >= 3 or (rank == 2 and r1 < 0.55)
            if commercial:
                big = h >= 11.0 and front_len >= 13.0
                if big and (zone == "t_nagar" or r2 < 0.3):
                    t = "sr"
                elif zone == "anna_salai" and h >= 17.0 and r2 < 0.6:
                    t = "of"
                elif h >= 24.0:
                    t = "of"
                else:
                    t = "sh"
            elif area < 42.0 or (near_beach and area < 110.0 and h <= 8.0):
                t = "kp"
            elif area >= 420.0 and slender >= 2.6 and h >= 8.5 and (near_beach or r2 < 0.5):
                t = "tn"
            elif in_old and h <= 8.5 and area < 190.0 and r1 < 0.5:
                t = "ah"
            elif h >= 8.6 and area >= 105.0:
                t = "fl"
            else:
                t = "hs"
        b["t"] = t
        if fw:
            b["fw"] = [[w[0], w[1]] for w in fw]
            fronts += 1
        else:
            b.pop("fw", None)
        counts[t] += 1

    if write:
        for f, d in data.items():
            f.write_text(json.dumps(d, separators=(",", ":")))
    print("classified", len(blds), "buildings;", fronts, "face a street")
    for t, c in counts.most_common():
        print(f"  {t} {c:6d}  {TYPES[t]}")
    return counts


if __name__ == "__main__":
    classify()
