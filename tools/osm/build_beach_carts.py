"""Push-cart shops: rows of 5–6 on city kerbs, clusters on the Marina sand, singles by market stalls.

Owner's notes (Nov 7): Marina photos of painted carts; then "road side shops in Chennai will
mostly be 5–6 shops together in a line — atho shop, fried rice shop, pani puri shop, ice creams,
fish fry and everything. Some shops will be open and some closed based on timing."

* ROWS — up to TARGET_ROWS lines of 5–6 different carts on a straight kerb, ROW_SPACING apart,
  ranked towards markets, busy junctions and bus stops, at least ROW_GAP_M from the next row.
* BEACH — clusters along the landward edge of the Marina and Santhome–Besant Nagar sand (within
  LANDWARD_M of a road, never within SEA_CLEAR_M of the water), 3–5 m in, facing the road.
* MARKETS — next to ~MARKET_SHARE of the kerb stalls, one cart along the same kerb.

Each cart gets a SHOP type (what it sells), a name of that type and that type's opening hours
(± an hour; ~CLOSED_TODAY of them stay shut all day), and a cart build that suits the type.
Every cart keeps clear of roads, buildings, trees, poles, stalls, parked vehicles, barricades,
landmarks and the metro works, and only goes in chunks the streamer loads.

Output:
  dress "carts" = [[x, z, yaw, variant, name, ground y, open hour, close hour], …]
  data/world/carts.json  — the same list (CartSigns name boards)
  data/world/cart_shops.json — {"names": [[English, Tamil, type], …], "types": {type: [open, close, builds]}}
Variant indexes BeachCartKit.VARIANTS (BUILDS below mirrors its builds). Idempotent. Run after
fill_empty_lots.py and build_barricades.py, before build_medians.py / build_road_works.py:
    python3 tools/osm/build_beach_carts.py
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_street_signs import CELL, TriGrid, seg_dist  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0
# BeachCartKit.Build: 0 sign box, 1 tiffin, 2 push-cart, 3 kiosk, 4 covered, 5 fast food,
# 6 ice cream, 7 pani puri. BUILDS[i] = build of BeachCartKit.VARIANTS[i].
BUILDS = [0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5, 5, 6, 6, 6, 7, 7, 7]
SIGN_BOX, TIFFIN, PUSHCART, KIOSK, COVERED, FAST_FOOD, ICE_CREAM, PANI_PURI = range(8)

# type: (open h, close h (may pass 24), builds, beach weight, row weight)
SHOP_TYPES = {
    "fried_rice": (18, 24, [FAST_FOOD], 0.2, 1.6),
    "atho": (17, 23, [TIFFIN, FAST_FOOD], 0.1, 1.2),
    "pani_puri": (16, 22, [PANI_PURI], 0.6, 1.3),
    "ice_cream": (11, 23, [ICE_CREAM], 0.9, 1.0),
    "fish_fry": (16, 23, [SIGN_BOX, FAST_FOOD], 0.8, 0.8),
    "bajji": (15, 21, [PUSHCART, SIGN_BOX, TIFFIN], 0.8, 1.1),
    "tea": (5, 23, [KIOSK], 0.3, 1.4),
    "tiffin": (6, 11, [TIFFIN, SIGN_BOX], 0.3, 1.1),
    "kothu": (19, 25, [FAST_FOOD], 0.0, 0.7),
    "momos": (17, 23, [FAST_FOOD, KIOSK], 0.1, 0.5),
    "juice": (9, 22, [KIOSK, SIGN_BOX], 0.5, 1.0),
    "sugarcane": (10, 20, [KIOSK], 0.2, 0.5),
    "coconut": (8, 19, [PUSHCART], 0.6, 0.6),
    "kaalan": (17, 23, [PUSHCART, TIFFIN], 0.1, 0.6),
    "sundal": (15, 22, [PUSHCART, SIGN_BOX], 1.0, 0.3),
    "corn": (15, 22, [PUSHCART, SIGN_BOX], 0.8, 0.3),
    "spring_potato": (16, 22, [SIGN_BOX], 0.6, 0.3),
    "soda": (10, 22, [SIGN_BOX, KIOSK], 0.5, 0.4),
    "fruit": (9, 20, [PUSHCART], 0.4, 0.5),
}
# Invented Chennai cart names (never a real business): type -> [(English, Tamil)].
NAMES = {
    "fried_rice": [("SRI BALAJI FAST FOOD", "ஸ்ரீ பாலாஜி ஃபாஸ்ட் புட்"), ("HOT WOK FRIED RICE", "ஹாட் வோக் ஃப்ரைடு ரைஸ்"),
                   ("MURUGAN FAST FOOD", "முருகன் ஃபாஸ்ட் புட்"), ("CHILLI CHICKEN CORNER", "சில்லி சிக்கன் கார்னர்"),
                   ("NOODLES & FRIED RICE", "நூடுல்ஸ் ஃப்ரைடு ரைஸ்")],
    "atho": [("BURMA ATHO KADAI", "பர்மா அத்தோ கடை"), ("RANGOON ATHO & MOHINGA", "ரங்கூன் அத்தோ மொஹிங்கா"),
             ("SRI KUMARAN ATHO", "ஸ்ரீ குமரன் அத்தோ"), ("ROYAL BURMA ATHO", "ராயல் பர்மா அத்தோ")],
    "pani_puri": [("RAJU PANI PURI", "ராஜு பானி பூரி"), ("BOMBAY CHAAT", "பாம்பே சாட்"),
                  ("SHREE RAM PANI PURI", "ஸ்ரீ ராம் பானி பூரி"), ("PRIYA PANI PURI", "பிரியா பானி பூரி")],
    "ice_cream": [("COOL POINT ICE CREAM", "கூல் பாயிண்ட் ஐஸ்கிரீம்"), ("SNOW WHITE ICE CREAM", "ஸ்னோ ஒயிட் ஐஸ்கிரீம்"),
                  ("KANMANI KULFI", "கண்மணி குல்ஃபி"), ("GANESH ICE CREAM", "கணேஷ் ஐஸ்கிரீம்")],
    "fish_fry": [("THANGAM FISH FRY", "தங்கம் மீன் வறுவல்"), ("KASIMEDU FISH FRY", "காசிமேடு மீன் வறுவல்"),
                 ("MEENAVAN FISH FRY", "மீனவன் மீன் வறுவல்")],
    "bajji": [("LAKSHMI BAJJI STALL", "லட்சுமி பஜ்ஜி"), ("MYLAI BAJJI CORNER", "மயிலை பஜ்ஜி கார்னர்"),
              ("AMMA BAJJI BONDA", "அம்மா பஜ்ஜி போண்டா")],
    "tea": [("PANDIAN TEA STALL", "பாண்டியன் டீ கடை"), ("KUMAR TEA KADAI", "குமார் டீ கடை"),
            ("SRI VINAYAGA TEA STALL", "ஸ்ரீ விநாயகா டீ கடை"), ("ANNA TEA & SNACKS", "அண்ணா டீ ஸ்நாக்ஸ்")],
    "tiffin": [("ANBU TIFFIN SHOP", "அன்பு டிபன் கடை"), ("AK TIFFIN SHOP", "ஏகே டிபன் கடை"),
               ("AMMA IDLI KADAI", "அம்மா இட்லி கடை")],
    "kothu": [("MUTHU KOTHU PAROTTA", "முத்து கொத்து பரோட்டா"), ("NIGHT PAROTTA CENTRE", "நைட் பரோட்டா சென்டர்")],
    "momos": [("HOT MOMOS", "ஹாட் மோமோஸ்"), ("SHAWARMA POINT", "ஷவர்மா பாயிண்ட்")],
    "juice": [("JEEVA JUICE CORNER", "ஜீவா ஜூஸ் கார்னர்"), ("FRESH LIME SODA", "ஃப்ரெஷ் லைம் சோடா"),
              ("ROSE MILK CORNER", "ரோஸ் மில்க் கார்னர்")],
    "sugarcane": [("KARUMBU JUICE", "கரும்பு ஜூஸ்")],
    "coconut": [("MEENA ELANEER", "மீனா இளநீர்"), ("ELANEER KADAI", "இளநீர் கடை")],
    "kaalan": [("SELVAM KAALAN", "செல்வம் காளான்"), ("MUSHROOM KAALAN FRY", "காளான் வறுவல்")],
    "sundal": [("SRI MURUGAN SUNDAL", "முருகன் சுண்டல்"), ("VIJI SUNDAL & CORN", "விஜி சுண்டல் கார்ன்")],
    "corn": [("MARINA SWEET CORN", "மெரினா ஸ்வீட் கார்ன்")],
    "spring_potato": [("KANMANI SPRING POTATO", "கண்மணி ஸ்பிரிங் பொட்டேட்டோ"),
                      ("SUGANYA SPRING POTATO", "சுகன்யா ஸ்பிரிங் பொட்டேட்டோ")],
    "soda": [("RAJA LEMON SODA", "ராஜா லெமன் சோடா"), ("GOLI SODA KADAI", "கோலி சோடா கடை")],
    "fruit": [("SELVI MANGO SLICE", "செல்வி மாங்காய்"), ("FRUIT MIX CORNER", "ஃப்ரூட் மிக்ஸ் கார்னர்")],
}
NAME_LIST = [(en, ta, t) for t, rows in NAMES.items() for en, ta in rows]
NAMES_OF = {t: [i for i, n in enumerate(NAME_LIST) if n[2] == t] for t in NAMES}

CLOSED_TODAY = 0.1
COVERED_SHARE = 0.05
LANDWARD_M = 75.0  # Marina: the sand starts 50–60 m from Kamarajar Salai (promenade between)
EDGE_STEP_M = 0.5
CLUSTER = (5, 12)
SPACING = (2.2, 3.0)
GAP = (25.0, 90.0)
INTO_SAND = (3.0, 5.0)
MARKET_SHARE = 0.18
TARGET_ROWS = 170
ROW_SPACING = 2.35
ROW_GAP_M = 80.0
ROW_CLASSES = ("primary", "secondary", "tertiary", "residential", "unclassified", "living_street")
ROW_ZONES = ("mylapore", "t_nagar", "anna_salai", "triplicane", "egmore", "adyar", "nungambakkam")
SAND_Y = -0.08
SEA_CLEAR_M = 35.0
WALK_Y = 0.08
BARE_Y = -0.15


def main() -> int:
    rng = random.Random(1107)
    manifest = json.loads((WORLD / "manifest.json").read_text())
    areas = json.loads((WORLD / "areas.json").read_text())

    def poly_of(p):
        if p and isinstance(p[0], (int, float)):
            return Polygon(list(zip(p[0::2], p[1::2]))).buffer(0)
        return Polygon(p).buffer(0)

    beaches = [poly_of(p) for p in areas.get("beach", [])]
    sea = unary_union([poly_of(p) for p in areas.get("sea", []) + areas.get("water", [])])
    road, bld, walk = TriGrid(), TriGrid(), TriGrid()
    for ch in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for kind, part in d.get("surf", {}).items():
            base = kind.removesuffix("_up")
            target = road if base in ("road", "junction", "lane", "centre") else (walk if base == "walk" else None)
            if target is None:
                continue
            v, idx = part["v"], part["i"]
            pts = [(v[k], v[k + 1]) for k in range(0, len(v), 2)]
            for k in range(0, len(idx), 3):
                target.add(pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]])
        for b in d.get("blds", []):
            p = b["p"]
            poly = [(p[k], p[k + 1]) for k in range(0, len(p), 2)]
            for k in range(1, len(poly) - 1):
                bld.add(poly[0], poly[k], poly[k + 1])
    graph = json.loads((WORLD / "road_graph.json").read_text())
    seg_grid: dict = {}
    for e in graph["edges"]:
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                for j in range(int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 2):
                    seg_grid.setdefault((i, j), []).append((a, b))

    def nearest_road(x, z, reach):
        best = None
        cx, cz = int(x // CELL), int(z // CELL)
        r = int(reach // CELL) + 1
        for i in range(cx - r, cx + r + 1):
            for j in range(cz - r, cz + r + 1):
                for a, b in seg_grid.get((i, j), ()):
                    d = seg_dist(x, z, a, b)
                    if best is None or d < best[0]:
                        L2 = (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2
                        t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((x - a[0]) * (b[0] - a[0]) + (z - a[1]) * (b[1] - a[1])) / L2))
                        best = (d, (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
        return best if best is not None and best[0] <= reach else None

    # Everything already standing.
    busy: dict = {}  # 4 m cell -> [(x, z, radius)]
    dress = {}
    for path in sorted((WORLD / "dress").glob("c_*.json")):
        k = path.stem.split("_")
        d = json.loads(path.read_text())
        d.pop("carts", None)
        dress[(int(k[1]), int(k[2]))] = (path, d)
        for kind, rad in (("trees", 1.2), ("poles", 0.8), ("xfmr", 1.6), ("stalls", 2.4), ("parking", 2.4), ("barricades", 1.6), ("beach_fence", 1.6)):
            for it in d.get(kind, []):
                busy.setdefault((int(it[0] // 4), int(it[1] // 4)), []).append((float(it[0]), float(it[1]), rad))
        for m in d.get("medians", []):  # never in the strip between two carriageways
            for i in range(1, len(m) - 2, 3):
                busy.setdefault((int(m[i] // 4), int(m[i + 1] // 4)), []).append((float(m[i]), float(m[i + 1]), float(m[i + 2]) * 0.5 + 1.5))
    keep_out = [Point(l["x"], l["z"]).buffer(18.0) for l in manifest.get("landmarks", [])]
    works_file = WORLD / "road_works.json"
    if works_file.exists():
        for s in json.loads(works_file.read_text()).get("sites", []):
            keep_out.append(Point(s["c"]).buffer(max(s["len"], s["wid"]) * 0.6 + 4.0))
    stops_data = json.loads((WORLD / "bus_stops.json").read_text())
    stops = [(float(s["x"]), float(s["z"])) for s in stops_data.get("stops", [])]
    for x, z in stops:
        keep_out.append(Point(x, z).buffer(6.0))
    keep_out = unary_union(keep_out)
    loadable = {tuple(c) for c in manifest["chunks"]}

    def free(x, z, r=1.25) -> bool:
        for i in (int(x // 4) - 1, int(x // 4), int(x // 4) + 1):
            for j in (int(z // 4) - 1, int(z // 4), int(z // 4) + 1):
                for q in busy.get((i, j), ()):
                    if math.dist((q[0], q[1]), (x, z)) < q[2] + r:
                        return False
        return True

    def ok_spot(x, z, yaw, road_clear=1.2) -> bool:
        if (math.floor(x / CHUNK), math.floor(z / CHUNK)) not in loadable:
            return False
        ax, az = math.cos(yaw), -math.sin(yaw)  # cart's local +X (its width)
        for t in (-1.0, 0.0, 1.0):
            px, pz = x + ax * t, z + az * t
            if road.hit(px, pz, road_clear) or bld.hit(px, pz, 0.6):
                return False
        return not keep_out.contains(Point(x, z)) and free(x, z)

    carts: list = []

    def shop(kind_weights: dict, exclude=()) -> str:
        options = [(t, w) for t, w in kind_weights.items() if w > 0 and t not in exclude]
        total = sum(w for _t, w in options)
        r = rng.random() * total
        for t, w in options:
            r -= w
            if r <= 0:
                return t
        return options[-1][0]

    def put(x, z, yaw, shop_type, ground):
        open_h, close_h, builds, _bw, _rw = SHOP_TYPES[shop_type]
        if rng.random() < COVERED_SHARE:
            build = COVERED
        else:
            build = rng.choice(builds)
        variant = rng.choice([i for i, b in enumerate(BUILDS) if b == build])
        name = rng.choice(NAMES_OF[shop_type])
        if build == COVERED or rng.random() < CLOSED_TODAY:
            o = c = 0  # shut all day
        else:
            o = max(0, open_h + rng.randint(-1, 1))
            c = max(o + 3, close_h + rng.randint(-1, 1))
        carts.append([round(x, 2), round(z, 2), round(yaw, 3), variant, name, ground, o, c])
        busy.setdefault((int(x // 4), int(z // 4)), []).append((x, z, 1.1))

    beach_weights = {t: v[3] for t, v in SHOP_TYPES.items()}
    row_weights = {t: v[4] for t, v in SHOP_TYPES.items()}

    # --- kerb rows of 5–6 -----------------------------------------------------------------
    zones = [z for z in manifest["zones"] if z["id"] in ROW_ZONES]
    degree: dict = {}
    for e in graph["edges"]:
        degree[e["a"]] = degree.get(e["a"], 0) + 1
        degree[e["b"]] = degree.get(e["b"], 0) + 1
    busy_nodes = [graph["nodes"][n] for n, k in degree.items() if k >= 3]
    node_grid: dict = {}
    for p in busy_nodes:
        node_grid.setdefault((int(p[0] // 60), int(p[-1] // 60)), []).append((p[0], p[-1]))
    stop_grid: dict = {}
    for x, z in stops:
        stop_grid.setdefault((int(x // 80), int(z // 80)), []).append((x, z))

    def near(grid, cell, x, z, r) -> bool:
        cx, cz = int(x // cell), int(z // cell)
        return any(math.dist(q, (x, z)) < r for i in (cx - 1, cx, cx + 1) for j in (cz - 1, cz, cz + 1) for q in grid.get((i, j), ()))

    candidates = []
    for e in graph["edges"]:
        if e["c"] not in ROW_CLASSES:
            continue
        half = float(e["w"]) * 0.5
        for a, b in zip(e["pts"], e["pts"][1:]):
            L = math.dist(a, b)
            if L < 18.0:
                continue
            mx, mz = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            score = rng.random()
            if any(math.dist((mx, mz), (z["x"], z["z"])) < float(z["r"]) for z in zones):
                score += 1.5
            if near(node_grid, 60, mx, mz, 60.0):
                score += 1.0
            if near(stop_grid, 80, mx, mz, 80.0):
                score += 0.8
            if e["c"] in ("primary", "secondary"):
                score += 0.4
            candidates.append((score, a, b, L, half))
    candidates.sort(key=lambda c: -c[0])
    rows_at: list = []
    row_n = 0
    for score, a, b, L, half in candidates:
        if row_n >= TARGET_ROWS:
            break
        mx, mz = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        if any(math.dist((mx, mz), q) < ROW_GAP_M for q in rows_at):
            continue
        ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        n = rng.choice((5, 5, 6, 6, 6))
        if (n - 1) * ROW_SPACING + 2.0 > L:
            n = 5
        placed = False
        side = rng.choice((1, -1))
        for sgn in (side, -side):
            nx, nz = uz * sgn, -ux * sgn  # (uz, -ux) is the left of a→b
            for extra in (0.9, 1.4, 2.0, 2.6, 3.2):
                spots = []
                for k in range(n):
                    t = (k - (n - 1) / 2) * ROW_SPACING
                    spots.append((mx + ux * t + nx * (half + extra), mz + uz * t + nz * (half + extra)))
                yaw = math.atan2(-nx, -nz)  # +Z faces the road
                if all(ok_spot(x, z, yaw, 0.45) for x, z in spots):
                    kinds = []
                    for x, z in spots:
                        t = shop(row_weights, exclude=kinds)
                        kinds.append(t)
                        put(x, z, yaw, t, WALK_Y if walk.hit(x, z, 0.0) else BARE_Y)
                    rows_at.append((mx, mz))
                    row_n += 1
                    placed = True
                    break
            if placed:
                break
    row_carts = len(carts)

    # --- beach clusters ---------------------------------------------------------------------
    for poly in beaches:
        rings = [poly.exterior] if poly.geom_type == "Polygon" else [g.exterior for g in poly.geoms]
        for ring in rings:
            L = ring.length
            s = rng.uniform(0.0, GAP[1])
            while s < L:
                count = rng.randint(*CLUSTER)
                placed_here = 0
                while placed_here < count and s < L:
                    p = ring.interpolate(s)
                    q = ring.interpolate(min(s + EDGE_STEP_M, L))
                    tx, tz = q.x - p.x, q.y - p.y
                    tl = math.hypot(tx, tz) or 1.0
                    nx, nz = -tz / tl, tx / tl
                    if not poly.contains(Point(p.x + nx * 2.0, p.y + nz * 2.0)):
                        nx, nz = -nx, -nz
                    into = rng.uniform(*INTO_SAND)
                    x, z = p.x + nx * into, p.y + nz * into
                    near_road = nearest_road(p.x, p.y, LANDWARD_M)
                    if near_road is None or not poly.contains(Point(x, z)) or sea.distance(Point(x, z)) < SEA_CLEAR_M:
                        s += SPACING[1]
                        if near_road is None:
                            break
                        continue
                    yaw = math.atan2(near_road[1][0] - x, near_road[1][1] - z)
                    if ok_spot(x, z, yaw):
                        put(x, z, yaw, shop(beach_weights), SAND_Y)
                        placed_here += 1
                    s += rng.uniform(*SPACING)
                s += rng.uniform(*GAP)
    beach_carts = len(carts) - row_carts

    # --- beside market stalls -----------------------------------------------------------------
    for key, (path, d) in dress.items():
        for st in d.get("stalls", []):
            if rng.random() > MARKET_SHARE:
                continue
            x0, z0, yaw = float(st[0]), float(st[1]), float(st[2])
            ax, az = math.cos(yaw), -math.sin(yaw)
            cell = busy.get((int(x0 // 4), int(z0 // 4)), [])
            mine = [q for q in cell if abs(q[0] - x0) < 1e-3 and abs(q[1] - z0) < 1e-3]
            for q in mine:
                cell.remove(q)
            for side in (1.0, -1.0):
                x, z = x0 + ax * 2.7 * side, z0 + az * 2.7 * side
                if ok_spot(x, z, yaw, 0.45):
                    put(x, z, yaw, shop(row_weights), WALK_Y if walk.hit(x, z, 0.0) else BARE_Y)
                    break
            cell.extend(mine)
    market_carts = len(carts) - row_carts - beach_carts

    shops = {"names": [list(n) for n in NAME_LIST],
             "types": {t: [v[0], v[1], v[2]] for t, v in SHOP_TYPES.items()}}
    (WORLD / "cart_shops.json").write_text(json.dumps(shops, ensure_ascii=False, indent=1))
    (WORLD / "carts.json").write_text(json.dumps(carts, separators=(",", ":")))
    per_chunk: dict = {}
    for c in carts:
        per_chunk.setdefault((math.floor(c[0] / CHUNK), math.floor(c[1] / CHUNK)), []).append(c)
    for key, (path, d) in dress.items():
        had = "carts" in json.loads(path.read_text())
        if key in per_chunk:
            d["carts"] = per_chunk.pop(key)
        elif not had:
            continue
        path.write_text(json.dumps(d, separators=(",", ":")))
    for key, items in per_chunk.items():
        (WORLD / "dress" / f"c_{key[0]}_{key[1]}.json").write_text(json.dumps({"carts": items}, separators=(",", ":")))
    types = {}
    for c in carts:
        t = NAME_LIST[c[4]][2]
        types[t] = types.get(t, 0) + 1
    shut = sum(1 for c in carts if c[6] == c[7])
    print(f"Carts: {len(carts)} — {row_n} kerb rows ({row_carts} carts), {beach_carts} on the beach, "
          f"{market_carts} by market stalls; {shut} shut all day")
    print("  by shop: " + ", ".join(f"{t} {n}" for t, n in sorted(types.items(), key=lambda kv: -kv[1])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
