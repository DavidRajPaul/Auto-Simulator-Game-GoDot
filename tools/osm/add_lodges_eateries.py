"""Mansions, PGs, hotels and restaurants on the road-front plots that are still empty.

Owner (Nov 7): "find out all the empty places in the map and add few mansions and PGs and some
hotels and restaurants". Chennai's bachelor "mansions" (lodges with rooms by the month), ladies'
/ gents' PGs and working women's hostels, budget hotels and messes / restaurants stand on the
road front with big name boards.

This pass rasters (1 m) everything already on the ground — roads, footpaths, buildings, water,
parks, beach, compounds, landmarks, props, bus stops, quest stops and all street dress — keeps a
kerb strip free, and walks every road's both sides looking for a plot that fits each kind. It
spreads them out (MIN_GAP_M between any two, per-kind quotas) and gives every one a name board
on its street wall (BuildingBoards: a fascia for restaurants, a high panel with Tamil above for
mansions, PGs and hotels). Names are invented, never a real business.

Writes buildings with "f": 3 into data/world/chunks and appends the boards (tagged "lodge") to
data/world/building_names.json; it removes its own earlier output first, so it can re-run.
Run after fill_empty_lots.py and build_building_names.py, and after the dressing passes
(barricades, carts, medians, road works) so it keeps clear of them:
    python3 tools/osm/add_lodges_eateries.py
"""
from __future__ import annotations

import json
import math
import random
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0
CELL_M = 1.0
KERB_M = 3.5
GAP_M = 1.5
MIN_GAP_M = 40.0
SETBACK_M = 12
SEED = 71107
TAG = "lodge"
ROAD_CLASSES = ("primary", "secondary", "tertiary", "residential", "living_street", "unclassified")
# kind: (quota, (front w), (depth), (height), building "k", board kind, board style)
KINDS = {
    "mansion": (50, (10.0, 14.0), (10.0, 14.0), (11.0, 15.0), "", "panel", 8),
    "pg": (50, (9.0, 12.0), (10.0, 13.0), (9.0, 12.5), "", "panel", 1),
    "hotel": (32, (14.0, 18.0), (12.0, 15.0), (15.0, 22.0), "", "panel", 5),
    "restaurant": (65, (10.0, 14.0), (9.0, 12.0), (4.5, 8.0), "shop", "shop", 0),
}
NAMES = {
    "mansion": [("Sri Murugan Mansion", "ஸ்ரீ முருகன் மேன்ஷன்"), ("Balaji Mansion", "பாலாஜி மேன்ஷன்"),
                ("Kumaran Mansion", "குமரன் மேன்ஷன்"), ("Sri Venkateswara Mansion", "ஸ்ரீ வெங்கடேஸ்வரா மேன்ஷன்"),
                ("Annai Mansion", "அன்னை மேன்ஷன்"), ("Thirumalai Mansion", "திருமலை மேன்ஷன்"),
                ("Kaveri Mansion", "காவேரி மேன்ஷன்"), ("Sakthi Mansion", "சக்தி மேன்ஷன்"),
                ("Raja Mansion", "ராஜா மேன்ஷன்"), ("New Star Mansion", "நியூ ஸ்டார் மேன்ஷன்")],
    "pg": [("Sri Sai Ladies PG", "ஸ்ரீ சாய் லேடீஸ் பிஜி"), ("Comfort Gents PG", "கம்ஃபோர்ட் ஜென்ட்ஸ் பிஜி"),
           ("Annai Working Women's Hostel", "அன்னை பணிபுரியும் மகளிர் விடுதி"), ("Green Nest PG", "கிரீன் நெஸ்ட் பிஜி"),
           ("Shanthi Ladies Hostel", "சாந்தி மகளிர் விடுதி"), ("Home Stay Gents PG", "ஹோம் ஸ்டே ஜென்ட்ஸ் பிஜி"),
           ("Sree Durga Ladies PG", "ஸ்ரீ துர்கா லேடீஸ் பிஜி"), ("Students Nest PG", "ஸ்டூடன்ட்ஸ் நெஸ்ட் பிஜி")],
    "hotel": [("Hotel Vaigai Residency", "ஹோட்டல் வைகை ரெசிடென்சி"), ("Hotel Kaveri Grand", "ஹோட்டல் காவேரி கிராண்ட்"),
              ("Hotel Ponni Inn", "ஹோட்டல் பொன்னி இன்"), ("Hotel Sri Durga Residency", "ஹோட்டல் ஸ்ரீ துர்கா ரெசிடென்சி"),
              ("Hotel Mylai Comforts", "ஹோட்டல் மயிலை கம்ஃபோர்ட்ஸ்"), ("Hotel Arun Residency", "ஹோட்டல் அருண் ரெசிடென்சி"),
              ("Hotel Marina Stay", "ஹோட்டல் மெரினா ஸ்டே"), ("Hotel Thamarai Inn", "ஹோட்டல் தாமரை இன்")],
    "restaurant": [("Ammayi Mess", "அம்மாயி மெஸ்"), ("Kumar Biryani Centre", "குமார் பிரியாணி சென்டர்"),
                   ("Sri Krishna Veg Restaurant", "ஸ்ரீ கிருஷ்ணா சைவ உணவகம்"), ("Muthu Military Hotel", "முத்து மிலிட்டரி ஹோட்டல்"),
                   ("Selvam Biryani", "செல்வம் பிரியாணி"), ("Annai Mess", "அன்னை மெஸ்"),
                   ("Ganga Veg Restaurant", "கங்கா சைவ உணவகம்"), ("Kongu Kitchen", "கொங்கு கிச்சன்"),
                   ("Madras Kaapi Club", "மெட்ராஸ் காபி கிளப்"), ("Meenakshi Tiffin Centre", "மீனாட்சி டிபன் சென்டர்"),
                   ("Royal Chettinad Mess", "ராயல் செட்டிநாடு மெஸ்"), ("Marina Fish Restaurant", "மெரினா மீன் உணவகம்")],
}


def main() -> int:
    rng = random.Random(SEED)
    manifest = json.loads((WORLD / "manifest.json").read_text())
    x0, z0, x1, z1 = manifest["bounds"]
    width, height = int((x1 - x0) / CELL_M) + 2, int((z1 - z0) / CELL_M) + 2
    to_px = lambda x, z: ((x - x0) / CELL_M, (z - z0) / CELL_M)  # noqa: E731
    img = Image.new("1", (width, height), 0)
    draw = ImageDraw.Draw(img)
    chunks = {}
    removed = 0
    for path in sorted((WORLD / "chunks").glob("c_*.json")):
        d = json.loads(path.read_text())
        before = len(d.get("blds", []))
        kept = []
        for b in d.get("blds", []):
            if b.get("f") != 3:
                kept.append(b)
            elif "o" in b:  # a filler building this pass renamed: give it back its old self
                b.update(b.pop("o"))
                kept.append(b)
        d["blds"] = kept
        removed += before - len(d["blds"])
        chunks[path] = d
        for name in ("road", "walk", "junction"):
            part = d.get("surf", {}).get(name, {})
            v, i = part.get("v", []), part.get("i", [])
            for t in range(0, len(i), 3):
                draw.polygon([to_px(v[i[t + k] * 2], v[i[t + k] * 2 + 1]) for k in range(3)], fill=1)
        for b in d["blds"]:
            p = b["p"]
            draw.polygon([to_px(p[n], p[n + 1]) for n in range(0, len(p), 2)], fill=1)
    graph = json.loads((WORLD / "road_graph.json").read_text())
    for e in graph["edges"]:
        draw.line([to_px(*q) for q in e["pts"]], fill=1, width=int(float(e["w"]) / CELL_M) + 2)
    occupied = grow(np.array(img, dtype=bool), int(KERB_M / CELL_M))

    extra = Image.new("1", (width, height), 0)
    d2 = ImageDraw.Draw(extra)
    areas = json.loads((WORLD / "areas.json").read_text())
    for name in ("water", "sea", "beach", "park"):
        for poly in areas.get(name, []):
            pts = poly if poly and not isinstance(poly[0], (int, float)) else list(zip(poly[0::2], poly[1::2]))
            if len(pts) >= 3:
                d2.polygon([to_px(q[0], q[1]) for q in pts], fill=1)
    for walls in json.loads((WORLD / "compounds.json").read_text())["chunks"].values():
        for w in walls:
            d2.line([to_px(w[0], w[1]), to_px(w[2], w[3])], fill=1, width=3)

    def dot(x: float, z: float, r: float) -> None:
        px, pz = to_px(x, z)
        d2.ellipse([px - r / CELL_M, pz - r / CELL_M, px + r / CELL_M, pz + r / CELL_M], fill=1)

    for lm in manifest["landmarks"]:
        dot(lm["x"], lm["z"], 26.0)
    for s in manifest.get("auto_stands", []) + manifest.get("services", []):
        dot(s["x"], s["z"], 12.0)
    for p in json.loads((WORLD / "city_props.json").read_text()).get("props", []):
        dot(float(p["x"]), float(p["z"]), 16.0 if p.get("model") == "slum_cluster" else 4.5)
    stops = json.loads((WORLD / "bus_stops.json").read_text())
    for s in stops.get("stops", []):
        dot(float(s["x"]), float(s["z"]), 7.0)
    for f in sorted((ROOT / "data/missions/side_quests").glob("sq_*.tres")):
        for a, b in re.findall(r"Vector3\((-?[\d.]+), 0, (-?[\d.]+)\)", f.read_text()):
            dot(float(a), float(b), 11.0)
    works = WORLD / "road_works.json"
    if works.exists():
        for s in json.loads(works.read_text()).get("sites", []):
            dot(s["c"][0], s["c"][1], max(s["len"], s["wid"]) * 0.6 + 4.0)
    for path in sorted((WORLD / "dress").glob("c_*.json")):
        d = json.loads(path.read_text())
        for key, r in (("trees", 2.0), ("poles", 1.0), ("xfmr", 3.5), ("parking", 2.5), ("stalls", 2.5),
                       ("carts", 1.6), ("barricades", 1.4)):
            for q in d.get(key, []):
                dot(q[0], q[1], r)
        for m in d.get("medians", []):
            for i in range(1, len(m) - 2, 3):
                dot(m[i], m[i + 1], float(m[i + 2]) * 0.5 + 1.0)
    occupied |= np.array(extra, dtype=bool)
    loadable = {tuple(c) for c in manifest["chunks"]}
    zones = manifest["zones"]

    def zone_at(x: float, z: float) -> str:
        best, bd = "", 1e9
        for zz in zones:
            dist = math.hypot(x - zz["x"], z - zz["z"])
            if dist < zz["r"] and dist < bd:
                best, bd = zz["id"], dist
        return best

    def cells(cx, cz, ux, uz, hw, hd):
        a = np.arange(-hw, hw + 1.0, 1.0)
        b = np.arange(-hd, hd + 1.0, 1.0)
        aa, bb = np.meshgrid(a, b)
        xs = ((cx + aa * ux - bb * uz - x0) / CELL_M).astype(int).ravel()
        zs = ((cz + aa * uz + bb * ux - z0) / CELL_M).astype(int).ravel()
        if xs.min() < 0 or zs.min() < 0 or xs.max() >= width or zs.max() >= height:
            return None
        return zs, xs

    segments = []
    for e in graph["edges"]:
        if e["c"] not in ROAD_CLASSES:
            continue
        for a, b in zip(e["pts"], e["pts"][1:]):
            L = math.dist(a, b)
            if L >= 14.0:
                segments.append((a, b, L, float(e["w"]) * 0.5))
    rng.shuffle(segments)

    placed: list = []  # (x, z)
    counts = {k: 0 for k in KINDS}
    used_names = {k: 0 for k in KINDS}
    added: dict = {}
    boards: list = []
    for a, b, L, half in segments:
        if all(counts[k] >= KINDS[k][0] for k in KINDS):
            break
        ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        side = rng.choice((1.0, -1.0))
        nx, nz = -uz * side, ux * side  # away from the road on this side
        wanted = [k for k in KINDS if counts[k] < KINDS[k][0]]
        kind = rng.choice(wanted)
        quota, wr, dr, hr, bkind, board_kind, style = KINDS[kind]
        w, dep = rng.uniform(*wr), rng.uniform(*dr)
        if w > L - 2.0:
            continue
        t = rng.uniform(w * 0.5 + 1.0, L - w * 0.5 - 1.0)
        fx, fz = a[0] + ux * t, a[1] + uz * t
        if any(math.dist((fx, fz), q) < MIN_GAP_M for q in placed):
            continue
        # Front plot first; failing that, a plot set back up to SETBACK_M (a forecourt in front).
        at = None
        for back in range(0, SETBACK_M + 1, 2):
            offset = half + KERB_M + 0.5 + back
            cx, cz = fx + nx * (offset + dep * 0.5), fz + nz * (offset + dep * 0.5)
            key = (math.floor(cx / CHUNK), math.floor(cz / CHUNK))
            if key not in loadable or (zone_at(cx, cz) == "marina" and kind in ("pg", "mansion")):
                at = None
                break
            # cells() lays w along (ux, uz) and the depth across it.
            at = cells(cx, cz, ux, uz, w * 0.5 + GAP_M, dep * 0.5 + GAP_M)
            if at is not None and not occupied[at].any():
                break
            at = None
        if at is None:
            continue
        occupied[at] = True
        placed.append((fx, fz))
        counts[kind] += 1
        corners = [(cx + sx * w / 2 * ux - sz * dep / 2 * uz, cz + sx * w / 2 * uz + sz * dep / 2 * ux)
                   for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        signed = sum(corners[i][0] * corners[i - 1][1] - corners[i - 1][0] * corners[i][1] for i in range(4))
        if signed < 0:
            corners.reverse()
        h = round(rng.uniform(*hr), 2)
        added.setdefault(key, []).append({"p": [round(v, 2) for q in corners for v in q], "h": h, "k": bkind,
                                          "z": zone_at(cx, cz), "s": rng.randrange(9973), "f": 3})
        # Board on the street wall: centre of the front face, facing the road.
        en, ta = NAMES[kind][used_names[kind] % len(NAMES[kind])]
        used_names[kind] += 1
        wx, wz = cx - nx * (dep * 0.5) - nx * 0.1, cz - nz * (dep * 0.5) - nz * 0.1
        yaw = math.atan2(-nx, -nz)
        if board_kind == "panel":
            y = min(h - 1.0, max(3.0 * 2 + 0.6, h * 0.8))
            k_size = max(1.0, min(2.2, y / 9.0))
            bw = min(w * 0.8, 16.0, max(4.5, len(en) * 0.5 * k_size))
        else:
            y = min(3.35, h - 0.4)
            bw = min(w * 0.85, 7.5, max(3.0, len(en) * 0.32))
        boards.append([round(wx, 2), round(wz, 2), round(yaw, 3), round(bw, 2), round(y, 2), board_kind,
                       en, ta if board_kind == "panel" else "", style, TAG])

    built = sum(counts.values())

    # Most road fronts are already built up (fill_empty_lots), so top the quotas up by turning
    # filler buildings ("f": 2) that face a road into lodges / eateries ("o" keeps the original).
    road_segs: dict = {}
    for e in graph["edges"]:
        if e["c"] not in ROAD_CLASSES:
            continue
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // 40) - 1, int(max(a[0], b[0]) // 40) + 2):
                for j in range(int(min(a[1], b[1]) // 40) - 1, int(max(a[1], b[1]) // 40) + 2):
                    road_segs.setdefault((i, j), []).append((a, b, float(e["w"]) * 0.5))

    def road_gap(x, z):
        best = None
        for a, b, half in road_segs.get((int(x // 40), int(z // 40)), ()):
            L2 = (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2
            t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, ((x - a[0]) * (b[0] - a[0]) + (z - a[1]) * (b[1] - a[1])) / L2))
            d = math.dist((x, z), (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)) - half
            if best is None or d < best:
                best = d
        return best

    fillers = [(path, b) for path, d in chunks.items() for b in d["blds"] if b.get("f") == 2]
    rng.shuffle(fillers)
    converted = 0
    for path, b in fillers:
        wanted = [k for k in KINDS if counts[k] < KINDS[k][0]]
        if not wanted:
            break
        p = b["p"]
        poly = [(p[k], p[k + 1]) for k in range(0, len(p), 2)]
        area2 = sum(poly[i - 1][0] * poly[i][1] - poly[i][0] * poly[i - 1][1] for i in range(len(poly)))
        if not 90.0 <= abs(area2) * 0.5 <= 400.0:
            continue
        sign = 1.0 if area2 > 0 else -1.0
        front = None
        for i in range(len(poly)):
            a, c = poly[i - 1], poly[i]
            L = math.dist(a, c)
            if L < 8.0:
                continue
            nx, nz = (c[1] - a[1]) / L * sign, -(c[0] - a[0]) / L * sign  # outward
            mx, mz = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
            gap = road_gap(mx + nx * 0.5, mz + nz * 0.5)
            if gap is None or gap > 9.0 or gap > (road_gap(mx - nx * 0.5, mz - nz * 0.5) or 1e9):
                continue
            if front is None or gap < front[0]:
                front = (gap, a, c, L, nx, nz)
        if front is None:
            continue
        _gap, a, c, L, nx, nz = front
        mx, mz = (a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5
        if any(math.dist((mx, mz), q) < MIN_GAP_M for q in placed):
            continue
        kind = rng.choice(wanted)
        quota, wr, dr, hr, bkind, board_kind, style = KINDS[kind]
        b["o"] = {"h": b["h"], "k": b.get("k", ""), "f": 2}
        b["h"] = round(rng.uniform(*hr), 2)
        b["k"] = bkind
        b["f"] = 3
        placed.append((mx, mz))
        counts[kind] += 1
        converted += 1
        en, ta = NAMES[kind][used_names[kind] % len(NAMES[kind])]
        used_names[kind] += 1
        h = b["h"]
        if board_kind == "panel":
            y = min(h - 1.0, max(3.0 * 2 + 0.6, h * 0.8))
            bw = min(L * 0.8, 16.0, max(4.5, len(en) * 0.5 * max(1.0, min(2.2, y / 9.0))))
        else:
            y = min(3.35, h - 0.4)
            bw = min(L * 0.85, 7.5, max(3.0, len(en) * 0.32))
        boards.append([round(mx + nx * 0.1, 2), round(mz + nz * 0.1, 2), round(math.atan2(nx, nz), 3), round(bw, 2),
                       round(y, 2), board_kind, en, ta if board_kind == "panel" else "", style, TAG])

    for path, d in chunks.items():
        m = re.match(r"c_(-?\d+)_(-?\d+)", path.stem)
        key = (int(m[1]), int(m[2]))
        d["blds"] += added.get(key, [])
        path.write_text(json.dumps(d, separators=(",", ":")))
    names_file = WORLD / "building_names.json"
    spots = [s for s in json.loads(names_file.read_text()) if not (len(s) > 9 and s[9] == TAG)]
    spots += boards
    names_file.write_text(json.dumps(spots, ensure_ascii=False, separators=(",", ":")))
    print(f"Lodges & eateries: {sum(counts.values())} ({', '.join(f'{k} {v}' for k, v in counts.items())}) — "
          f"{built} new buildings on empty plots, {converted} road-front filler buildings named; "
          f"{removed} earlier new ones replaced")
    return 0


def grow(mask: np.ndarray, cells: int) -> np.ndarray:
    h, w = mask.shape
    s = np.zeros((h + 1, w + 1), dtype=np.int64)
    s[1:, 1:] = mask.cumsum(0).cumsum(1)
    r = cells
    y0 = np.clip(np.arange(h) - r, 0, h)[:, None]
    y1 = np.clip(np.arange(h) + r + 1, 0, h)[:, None]
    xa = np.clip(np.arange(w) - r, 0, w)[None, :]
    xb = np.clip(np.arange(w) + r + 1, 0, w)[None, :]
    return (s[y1, xb] - s[y0, xb] - s[y1, xa] + s[y0, xa]) > 0


if __name__ == "__main__":
    raise SystemExit(main())
