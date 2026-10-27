"""Name boards for Chennai buildings, from real OpenStreetMap places.

Input : data/osm/chennai_pois.json.gz (tools/osm/fetch_pois.py, run in CI) + the world chunks
        (building footprints) + road_graph.json.
Output: data/world/building_names.json — one board per entry:
            [x, z, yaw, width, y, kind, text_en, text_ta, style]
          kind  "shop"  = fascia across a ground-floor front, above the awnings
                "panel" = name panel high on a named building (towers, colleges, hospitals …)
          yaw   the board faces +Z rotated by yaw (= the facade's outward normal, toward the street)
          style index into BuildingBoards.STYLES (board / text colours)
        data/osm/building_names_review.csv — real name → game name, one row per OSM place.

Naming policy
  • Public places keep their real name: government offices, temples / churches / mosques,
    schools, colleges, libraries, police, post offices, stations, museums, monuments, parks,
    and hospitals that are not a commercial chain.
  • Businesses get a Chennai-flavoured parody that keeps the category ("Kanchi Kalyan Silks",
    "Biryani Thalaivar", "Namma Kooturavu Bank"). No real brand names, no logos.
  • The review CSV is also an override file: edit a row's game_name (or set it to "-" to drop
    the board) and re-run — edits are kept, keyed by OSM id.

Run:  python3 tools/osm/build_building_names.py
"""
from __future__ import annotations

import csv
import gzip
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
POIS = ROOT / "data" / "osm" / "chennai_pois.json.gz"
OUT = WORLD / "building_names.json"
REVIEW = ROOT / "data" / "osm" / "building_names_review.csv"

ORIGIN = (13.049, 80.259)
M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))
CELL = 40.0
FLOOR_M = 3.2
NODE_SNAP_M = 14.0      # a shop node must sit inside, or this close to, a footprint
MIN_EDGE_M = 3.0
MAX_ROAD_M = 28.0       # facade must face a road this close (else no board — back alleys)


def project(lat: float, lon: float) -> tuple[float, float]:
    return ((lon - ORIGIN[1]) * M_PER_DEG_LON, -(lat - ORIGIN[0]) * M_PER_DEG_LAT)


# --- classification ---------------------------------------------------------------------------

PUBLIC = {
    "amenity": {"place_of_worship", "school", "college", "university", "library", "police", "post_office",
                "bus_station", "townhall", "courthouse", "fire_station", "community_centre", "hospital",
                "arts_centre", "kindergarten", "public_building", "theatre", "social_facility", "blood_bank"},
    "tourism": {"museum", "attraction", "gallery"},
    "historic": None,  # any
    "office": {"government", "diplomatic", "educational_institution", "ngo", "association", "religion"},
    "leisure": {"stadium", "sports_centre"},
    "building": {"college", "school", "university", "hospital", "temple", "church", "mosque", "government",
                 "public", "train_station", "civic", "religious", "cathedral", "chapel", "transportation"},
}
SKIP = {
    "amenity": {"fuel", "parking", "atm", "bench", "toilets", "drinking_water", "parking_entrance", "taxi",
                "bicycle_parking", "waste_basket", "vending_machine", "charging_station", "shelter", "fountain",
                "motorcycle_parking", "car_wash", "bus_stop", "clock", "telephone", "recycling"},
    "tourism": {"artwork", "viewpoint", "information", "picnic_site"},
    "historic": {"memorial", "wayside_shrine", "boundary_stone"},
    "leisure": {"park", "garden", "playground", "pitch", "swimming_pool", "nature_reserve", "track"},
}
PUBLIC_WORDS = re.compile(r"\b(temple|kovil|koil|church|mosque|masjid|dargah|college|school|university|hospital|"
                          r"station|government|govt|corporation|police|court|library|museum|institute|"
                          r"secretariat|collectorate|post office|polytechnic|cathedral|basilica|mutt|math)\b", re.I)
KEYS = ("shop", "amenity", "office", "tourism", "healthcare", "craft", "leisure", "historic", "building")


def primary(tags: dict) -> tuple[str, str]:
    for k in KEYS:
        if k in tags:
            return k, tags[k]
    return "", ""


def is_public(tags: dict, k: str, v: str, name: str) -> bool:
    branded = any(t in tags for t in ("brand", "brand:wikidata", "brand:en"))
    if k == "amenity" and v == "hospital":
        return not branded  # chain hospitals get a parody like any business
    if branded:
        return False
    allowed = PUBLIC.get(k, set())
    if k in PUBLIC and (allowed is None or v in allowed):
        return True
    if tags.get("operator:type") in ("government", "public", "religious"):
        return True
    return bool(PUBLIC_WORDS.search(name)) and k in ("building", "office", "amenity", "healthcare")


# --- parody names -----------------------------------------------------------------------------

STEMS = ["Kaveri", "Vaigai", "Marina", "Mylai", "Kapali", "Singara", "Thendral", "Kanchi", "Kumaran", "Murugan",
         "Lakshmi", "Saraswathi", "Ponni", "Poompuhar", "Thamarai", "Malligai", "Senthil", "Velan", "Annai",
         "Valli", "Selvam", "Tharangai", "Kongu", "Chola", "Pandian", "Pallavan", "Thiru", "Vetri", "Arasu",
         "Ilango", "Kamban", "Bharathi", "Anbu", "Kalai", "Mullai", "Neithal", "Kurinji", "Madras", "Namma",
         "Elliot's", "Adyar", "Triplicane", "Royapettah", "Egmore", "Santhome"]

CATS: list[tuple[set, list[str], int]] = [
    # (primary values, templates, style)  — {s} = stem, {S} = a second stem
    ({"restaurant", "fast_food", "food_court"},
     ["Biryani Thalaivar", "{s} Bhavan", "{s} Mess", "Hotel {s} Meals", "{s} Tiffin Centre", "{s} Biryani Point",
      "Chettinad {s} Kitchen", "{s} Parotta Kadai", "Machi Dosa Corner", "{s} Veg Restaurant", "Kaara Saaram",
      "Thalappa Kari Virundhu"], 0),
    ({"cafe", "ice_cream", "juice_bar"},
     ["{s} Filter Kaapi", "Kaapi Kadai", "{s} Tea Stall", "{s} Juice Centre", "Namma Kaapi", "{s} Cool Bar"], 1),
    ({"bank", "bureau_de_change", "money_lender", "financial"},
     ["Namma Kooturavu Bank", "{s} Grameena Bank", "Madras Makkal Bank", "{s} Mutual Bank", "Singara Savings Bank",
      "{s} Co-op Bank", "{s} Finance"], 2),
    ({"clothes", "fabric", "tailor", "boutique", "fashion", "textile", "saree"},
     ["Kanchi Kalyan Silks", "{s} Silks", "{s} Textiles", "{s} Readymades", "Sri {s} Sarees", "{s} Silk House",
      "{s} Fashions"], 3),
    ({"jewelry", "jewellery", "gold", "watches"},
     ["{s} Jewellers", "Sri {s} Thanga Maaligai", "{s} Gold Palace", "{s} & Sons Jewellers"], 4),
    ({"hotel", "guest_house", "hostel", "motel", "apartment"},
     ["Hotel {s} Residency", "{s} Grand", "{s} Lodge", "Hotel {s} Inn", "{s} Comforts"], 5),
    ({"supermarket", "convenience", "department_store", "mall", "general", "variety_store", "kiosk", "greengrocer"},
     ["{s} Super Market", "{s} Stores", "{s} Departmental Stores", "{s} Mall", "Annachi Kadai", "{s} Mart"], 6),
    ({"pharmacy", "chemist", "medical_supply"}, ["{s} Medicals", "{s} Pharmacy", "Sri {s} Medical Hall"], 7),
    ({"clinic", "doctors", "dentist", "laboratory", "hospital", "optician", "physiotherapist", "centre"},
     ["{s} Clinic", "{s} Diagnostics", "{s} Hospital", "{s} Dental Care", "{s} Health Centre", "{s} Eye Care",
      "{s} Scan Centre"], 7),
    ({"bakery", "confectionery", "pastry", "sweets"}, ["{s} Bakery", "{s} Sweets", "Sri {s} Sweets & Snacks", "{s} Iyengar Bakery"], 0),
    ({"electronics", "mobile_phone", "computer", "appliance", "hifi", "telecommunication"},
     ["{s} Mobiles", "{s} Electronics", "{s} Digital World", "{s} Computers"], 2),
    ({"cinema"}, ["{s} Cinemas", "{s} Theatre", "{s} Talkies"], 4),
    ({"car", "car_repair", "motorcycle", "car_parts", "tyres"}, ["{s} Motors", "{s} Auto Works", "{s} Two Wheelers", "{s} Tyres"], 6),
    ({"shoes", "bag", "leather"}, ["{s} Footwear", "{s} Bags & Shoes", "{s} Chappals"], 3),
    ({"company", "it", "yes", "insurance", "estate_agent", "lawyer", "consulting", "coworking", "telecommunication",
      "commercial", "office", "employment_agency", "travel_agent", "advertising_agency"},
     ["{s} Infotech", "{s} Insurance", "{s} Associates", "{s} Towers", "{s} Business Centre", "{s} Travels",
      "{s} Software", "{s} Enterprises"], 1),
    ({"apartments", "residential", "house", "dormitory"}, ["{s} Apartments", "{s} Enclave", "{s} Flats", "{s} Nest"], 8),
    ({"books", "stationery", "copyshop", "newsagent"}, ["{s} Book House", "{s} Xerox", "{s} Stationery"], 6),
    ({"hairdresser", "beauty", "cosmetics"}, ["{s} Saloon", "{s} Beauty Parlour", "{s} Hair Cuts"], 1),
    ({"hardware", "doityourself", "paint", "electrical", "furniture", "houseware", "trade"},
     ["{s} Hardwares", "{s} Furniture", "{s} Paints", "{s} Electricals"], 6),
    ({"events_venue", "marketplace", "wedding_hall"}, ["{s} Kalyana Mandapam", "{s} Mahal", "{s} Convention Hall"], 5),
    ({"fitness_centre", "sports_centre", "sports"}, ["{s} Fitness", "{s} Gym"], 2),
]
DEFAULT = (["{s} Traders", "{s} & Co", "{s} Enterprises", "Sri {s} Agencies"], 6)


def stable(osm_id: int, salt: int = 0) -> int:
    x = (osm_id * 2654435761 + salt * 40503) & 0xFFFFFFFF
    x ^= x >> 15
    return (x * 2246822519) & 0xFFFFFFFF


BUILDING_T = (["{s} Complex", "{s} Towers", "{s} Plaza", "{s} Buildings", "{s} House", "{s} Arcade"], 8)


def parody(osm_id: int, k: str, v: str) -> tuple[str, int]:
    templates, style = BUILDING_T if k == "building" and v not in ("apartments", "residential", "house", "dormitory") else DEFAULT
    for vals, t, st in ([] if templates is BUILDING_T[0] else CATS):
        if v in vals:
            templates, style = t, st
            break
    t = templates[stable(osm_id, 1) % len(templates)]
    s = STEMS[stable(osm_id, 2) % len(STEMS)]
    return t.replace("{s}", s), style


def public_style(k: str, v: str, name: str, tags: dict | None = None) -> int:
    rel = (tags or {}).get("religion", "")
    if rel == "muslim" or v == "mosque" or re.search(r"mosque|masjid|dargah", name, re.I):
        return 5   # green, white lettering
    if rel == "christian" or v in ("church", "cathedral", "chapel") or re.search(r"church|cathedral|basilica", name, re.I):
        return 9
    if v == "place_of_worship" or v in ("temple", "church", "mosque") or re.search(r"temple|kovil|koil", name, re.I):
        return 10
    if k == "office" or v in ("police", "post_office", "townhall", "courthouse", "fire_station", "government"):
        return 11
    return 9


def clean_en(tags: dict) -> str:
    for key in ("name:en", "name", "official_name:en", "alt_name:en"):
        n = tags.get(key, "")
        if n and n.isascii():
            n = re.sub(r"\s+", " ", n).strip()
            n = re.sub(r"\s*[-,(]\s*Chennai\)?$", "", n, flags=re.I).strip(" ,-")
            return n if len(n) >= 3 else ""
    return ""


# --- geometry ---------------------------------------------------------------------------------

def point_in(px, pz, poly) -> bool:
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / ((zj - zi) or 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def seg_dist(px, pz, a, b) -> float:
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - a[0]) * dx + (pz - a[1]) * dz) / l2))
    return math.hypot(px - (a[0] + t * dx), pz - (a[1] + t * dz))


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    blds = []  # (poly, h, area)
    bgrid: dict = {}
    for ch in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for b in d.get("blds", []):
            p = b["p"]
            poly = [(p[k], p[k + 1]) for k in range(0, len(p), 2)]
            if len(poly) < 3:
                continue
            area2 = sum(poly[i - 1][0] * poly[i][1] - poly[i][0] * poly[i - 1][1] for i in range(len(poly)))
            bi = len(blds)
            blds.append((poly, float(b["h"]), area2))
            xs, zs = [q[0] for q in poly], [q[1] for q in poly]
            for i in range(int(min(xs) // CELL), int(max(xs) // CELL) + 1):
                for j in range(int(min(zs) // CELL), int(max(zs) // CELL) + 1):
                    bgrid.setdefault((i, j), []).append(bi)

    graph = json.loads((WORLD / "road_graph.json").read_text())
    rgrid: dict = {}
    for e in graph["edges"]:
        hw = float(e["w"]) * 0.5
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                for j in range(int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 2):
                    rgrid.setdefault((i, j), []).append((a, b, hw))

    def road_dist(x, z) -> float:
        best = 1e9
        for a, b, hw in rgrid.get((int(x // CELL), int(z // CELL)), ()):
            best = min(best, seg_dist(x, z, a, b) - hw)
        return best

    def find_building(x, z, snap):
        best, bd = None, snap
        for bi in bgrid.get((int(x // CELL), int(z // CELL)), ()):
            poly = blds[bi][0]
            if point_in(x, z, poly):
                return bi, 0.0
            d = min(seg_dist(x, z, poly[i - 1], poly[i]) for i in range(len(poly)))
            if d < bd:
                best, bd = bi, d
        return (best, bd) if best is not None else (None, None)

    overrides: dict = {}
    if REVIEW.exists():
        with REVIEW.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                overrides[row["osm_id"]] = row.get("game_name", "")

    data = json.load(gzip.open(POIS))
    els = sorted(data["elements"], key=lambda e: (e["type"] != "way", e["id"]))  # ways first: they own buildings
    used_panel: set = set()
    edge_slots: dict = {}  # (bi, edge) -> list of (t0, t1) used along the edge
    boards, review = [], []
    stats = {"public": 0, "parody": 0, "no_building": 0, "no_street": 0, "skipped": 0, "dropped": 0}

    for el in els:
        tags = el.get("tags", {})
        k, v = primary(tags)
        real = clean_en(tags)
        if not k or not real or (k in SKIP and v in SKIP[k]) or re.search(r"\bbooth\b|\bkiosk\b", real, re.I):
            stats["skipped"] += 1
            continue
        lat = el.get("lat", el.get("center", {}).get("lat"))
        lon = el.get("lon", el.get("center", {}).get("lon"))
        if lat is None:
            stats["skipped"] += 1
            continue
        x, z = project(lat, lon)
        pub = is_public(tags, k, v, real)
        if pub:
            game, style, ta = real, public_style(k, v, real, tags), tags.get("name:ta", "")
        else:
            (game, style), ta = parody(el["id"], k, v), ""
        oid = f"{el['type'][0]}{el['id']}"
        if oid in overrides and overrides[oid] not in ("",):
            if overrides[oid] != game:
                ta = ""
            game = overrides[oid]
        row = {"osm_id": oid, "category": f"{k}={v}", "real_name": real, "game_name": game,
               "policy": "real (public)" if pub else "parody (business)", "x": round(x, 1), "z": round(z, 1), "placed": "no"}
        review.append(row)
        if game == "-":
            stats["dropped"] += 1
            continue
        bi, dist = find_building(x, z, 30.0 if el["type"] != "node" else NODE_SNAP_M)
        if bi is None:
            stats["no_building"] += 1
            continue
        poly, h, area2 = blds[bi]
        sign = 1.0 if area2 > 0 else -1.0
        panel = el["type"] != "node" and (pub or h > 12.0) and dist == 0.0
        if panel and bi in used_panel:
            panel = False
        # Choose the street-facing facade: outward edge whose front is closest to a road, nudged
        # toward the edge nearest the place itself (shops in a long block).
        best = None
        for i in range(len(poly)):
            a, c = poly[i - 1], poly[i]
            L = math.dist(a, c)
            if L < MIN_EDGE_M:
                continue
            nx, nz = (c[1] - a[1]) / L * sign, -(c[0] - a[0]) / L * sign
            mx, mz = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
            rd = road_dist(mx + nx * 1.5, mz + nz * 1.5)
            if rd > MAX_ROAD_M or rd > road_dist(mx - nx * 1.5, mz - nz * 1.5) + 0.5:
                continue  # faces away from the street
            score = rd + 0.6 * seg_dist(x, z, a, c)
            if best is None or score < best[0]:
                best = (score, i, a, c, L, nx, nz)
        if best is None:
            stats["no_street"] += 1
            continue
        _, ei, a, c, L, nx, nz = best
        if panel:
            y = min(h - 1.0, max(FLOOR_M * 2 + 0.6, h * 0.8)) if h > 9.0 else min(h - 0.5, FLOOR_M + 1.0)
            k_size = max(1.0, min(2.2, y / 9.0))  # bigger lettering higher up (BuildingBoards matches)
            width = min(L * 0.8, 16.0, max(4.5, len(game) * 0.5 * k_size))
            t_mid = 0.5
            used_panel.add(bi)
            kind = "panel"
        else:
            width = min(L * 0.85, 6.5, max(2.6, len(game) * 0.3))
            # Place along the edge near the shop's own position, without overlapping a neighbour.
            dx, dz = c[0] - a[0], c[1] - a[1]
            t_pt = max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / (L * L)))
            half = width * 0.5 / L
            slots = edge_slots.setdefault((bi, ei), [])
            t_mid = None
            for cand in sorted({t_pt, 0.5, *(s[1] + half + 0.02 for s in slots), *(s[0] - half - 0.02 for s in slots)},
                               key=lambda t: abs(t - t_pt)):
                t = max(half, min(1.0 - half, cand))
                if all(t + half <= s[0] or t - half >= s[1] for s in slots):
                    t_mid = t
                    break
            if t_mid is None:
                stats["no_street"] += 1
                continue
            slots.append((t_mid - half, t_mid + half))
            y = min(3.35, h - 0.4)
            kind = "shop"
        px = a[0] + (c[0] - a[0]) * t_mid + nx * 0.1
        pz = a[1] + (c[1] - a[1]) * t_mid + nz * 0.1
        boards.append([round(px, 2), round(pz, 2), round(math.atan2(nx, nz), 3), round(width, 2), round(y, 2),
                       kind, game, ta, style])
        row["placed"] = kind
        stats["public" if pub else "parody"] += 1

    OUT.write_text(json.dumps(boards, ensure_ascii=False, separators=(",", ":")))
    with REVIEW.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(review[0].keys()))
        w.writeheader()
        w.writerows(sorted(review, key=lambda r: (r["policy"], r["category"], r["real_name"])))
    print(f"Building boards: {len(boards)} placed ({stats['public']} real public names, {stats['parody']} parody "
          f"business names); not placed: {stats['no_building']} no footprint, {stats['no_street']} no street-facing "
          f"wall, {stats['skipped']} skipped kinds, {stats['dropped']} dropped by review")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
