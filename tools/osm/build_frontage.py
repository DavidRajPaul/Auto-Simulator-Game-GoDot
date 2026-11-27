#!/usr/bin/env python3
"""A continuous wall of buildings along Anna Salai, right behind the footpath.

Nov 27 owner report (with aerial photos of Anna Salai round the LIC Building): "look how
compacted the buildings are. The roads will be wide, but just after the roads there will be
buildings. There will be no empty spaces." The OSM footprints there are sparse and the infill
(build_world "f": 1, fill_empty_lots "f": 2) stands back from the kerb in loose squares, so the
corridor read as gaps and car parks.

This pass walks both sides of every FRONTAGE_ROADS carriageway, finds where the drawn road and
footpath end, and lines that edge with attached lots ("f": 4): 6.5-15 m wide, 11-22 m deep,
heights from the Anna Salai zone (mostly 3-6 floors, some taller). A lot never covers a road,
footpath, water, park, a real OSM building, a lodge, a landmark model's site, a quest stop, a
bus stop, a city prop, a service bay or an auto stand; infill squares in the way are removed, and
so are trees / parked vehicles / stalls / plot and compound walls / name boards standing on a
new lot. Lots are attached: each starts where the last ended, so the street front is unbroken
except at side roads and real buildings. Deterministic and idempotent (previous "f": 4 lots
are removed first). Run after add_lodges_eateries.py and before classify_buildings.py:
    python3 tools/osm/build_frontage.py
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
FRONTAGE_ROADS = ("Anna Salai (Mount Road)", "Anna Salai")
CELL = 0.5
SEED = 270011
STEP = 0.5            # station spacing along the carriageway
MAX_REACH = 32.0      # how far out from the centre line the street (road + footpath) may reach
FRONT_GAP = 0.4       # building front this far behind the footpath edge
WIDTHS = (6.5, 15.0)
DEPTHS = (11.0, 22.0)
MIN_DEPTH = 7.0
STREET = ("road", "walk", "junction", "lane", "centre", "road_up", "walk_up", "junction_up", "lane_up", "centre_up")
POINT_KEYS = ("trees", "parking", "stalls", "shop_people", "kolams", "dogs")
# Kerb fixtures a lot must stand clear of (dress key -> keep-out radius, m).
FIXTURES = {"booths": 3.5, "poles": 0.9, "lamps": 0.9, "xfmr": 3.5, "barricades": 1.0, "carts": 2.5, "beach_fence": 1.0}
# World files whose points (lists [x, z, ...] or dicts with x / z) are kerb things to keep clear of.
FIXTURE_FILES = ("signal_posts.json", "street_signs.json", "police_booths.json", "carts.json", "road_works.json",
                 "roundabouts.json", "sound_spots.json")
ZONE = "anna_salai"


def load(path: Path):
    return json.loads(path.read_text())


def main() -> int:
    graph = load(WORLD / "road_graph.json")
    edges = [e for e in graph["edges"] if e.get("n") in FRONTAGE_ROADS and len(e["pts"]) >= 2]
    xs = [p[0] for e in edges for p in e["pts"]]
    zs = [p[1] for e in edges for p in e["pts"]]
    ox, oz = min(xs) - 80.0, min(zs) - 80.0
    w, h = int((max(xs) + 80.0 - ox) / CELL) + 1, int((max(zs) + 80.0 - oz) / CELL) + 1
    px = lambda x, z: ((x - ox) / CELL, (z - oz) / CELL)  # noqa: E731
    size = float(load(WORLD / "manifest.json")["chunk_size"])
    c0 = (int(math.floor(ox / size)), int(math.floor(oz / size)))
    c1 = (int(math.floor((ox + w * CELL) / size)), int(math.floor((oz + h * CELL) / size)))

    street_img = Image.new("1", (w, h), 0)
    block_img = Image.new("1", (w, h), 0)
    ds, db = ImageDraw.Draw(street_img), ImageDraw.Draw(block_img)
    chunks: dict[Path, dict] = {}
    removed_prev = 0
    for i in range(c0[0], c1[0] + 1):
        for j in range(c0[1], c1[1] + 1):
            f = WORLD / "chunks" / f"c_{i}_{j}.json"
            if not f.exists():
                continue
            d = load(f)
            before = len(d.get("blds", []))
            d["blds"] = [b for b in d.get("blds", []) if b.get("f") != 4]
            removed_prev += before - len(d["blds"])
            chunks[f] = d
            for kind, part in d.get("surf", {}).items():
                if kind not in STREET:
                    continue
                v, idx = part["v"], part["i"]
                for t in range(0, len(idx) - 2, 3):
                    ds.polygon([px(v[2 * idx[t + k]], v[2 * idx[t + k] + 1]) for k in range(3)], fill=1)
            for b in d["blds"]:
                if b.get("f") in (1, 2):
                    continue  # infill gives way to the street front
                p = b["p"]
                db.polygon([px(p[k], p[k + 1]) for k in range(0, len(p), 2)], fill=1)
    areas = load(WORLD / "areas.json")
    for kind in ("water", "sea", "beach", "park"):
        for poly in areas.get(kind, []):
            if len(poly) >= 3:
                db.polygon([px(float(q[0]), float(q[1])) for q in poly], fill=1)
    for model in load(WORLD / "landmark_models.json").get("models", []):
        for key in ("clear", "clear_fill"):
            if len(model.get(key, [])) >= 3:
                db.polygon([px(float(q[0]), float(q[1])) for q in model[key]], fill=1)

    def dot(x: float, z: float, r: float) -> None:
        a, b = px(x, z)
        db.ellipse([a - r / CELL, b - r / CELL, a + r / CELL, b + r / CELL], fill=1)

    manifest = load(WORLD / "manifest.json")
    for lm in manifest["landmarks"]:
        if lm["kind"] not in ("model", "park"):
            dot(lm["x"], lm["z"], 20.0)
    for s in manifest.get("auto_stands", []) + manifest.get("services", []):
        dot(s["x"], s["z"], 12.0)
    for p in load(WORLD / "city_props.json").get("props", []):
        dot(float(p["x"]), float(p["z"]), 16.0 if p.get("model") == "slum_cluster" else 4.0)
    stops = load(WORLD / "bus_stops.json")
    for s in stops.get("stops", []) if isinstance(stops, dict) else stops:
        dot(float(s["x"]), float(s["z"]), 6.0)
    for f in sorted((ROOT / "data/missions/side_quests").glob("sq_*.tres")):
        for a, b in re.findall(r"Vector3\((-?[\d.]+), 0, (-?[\d.]+)\)", f.read_text()):
            dot(float(a), float(b), 11.0)
    def points(obj):
        if isinstance(obj, dict):
            if "x" in obj and "z" in obj and isinstance(obj["x"], (int, float)):
                yield float(obj["x"]), float(obj["z"])
            for v in obj.values():
                yield from points(v)
        elif isinstance(obj, list):
            if len(obj) >= 2 and all(isinstance(v, (int, float)) for v in obj[:2]) and abs(obj[0]) < 5000 and abs(obj[1]) < 5000:
                yield float(obj[0]), float(obj[1])
            else:
                for v in obj:
                    yield from points(v)

    for name in FIXTURE_FILES:
        f = WORLD / name
        if f.exists():
            for x, z in points(load(f)):
                if ox <= x <= ox + w * CELL and oz <= z <= oz + h * CELL:
                    dot(x, z, 1.5)
    for i in range(c0[0], c1[0] + 1):
        for j in range(c0[1], c1[1] + 1):
            f = WORLD / "dress" / f"c_{i}_{j}.json"
            if f.exists():
                d = load(f)
                for key, r in FIXTURES.items():
                    for it in d.get(key, []):
                        if isinstance(it, list) and len(it) >= 2 and isinstance(it[0], (int, float)):
                            dot(float(it[0]), float(it[1]), r)
    lc = load(WORLD / "landmark_compounds.json")
    for segs in list(lc.get("walls", {}).values()) + list(lc.get("gates", {}).values()):
        for s in segs:
            db.line([px(s[1], s[2]), px(s[3], s[4])], fill=1, width=3)
    street = np.array(street_img, dtype=bool)
    blocked = np.array(block_img, dtype=bool) | street

    def cell(x: float, z: float):
        a, b = int((x - ox) / CELL), int((z - oz) / CELL)
        return (b, a) if 0 <= a < w and 0 <= b < h else None

    def is_street(x: float, z: float) -> bool:
        c = cell(x, z)
        return c is not None and bool(street[c])

    def quad_cells(q):
        """(row slice, col slice, local mask) of a lot: rastered in a small window, not the map."""
        pts = [px(*p) for p in q]
        a0 = max(0, int(min(p[0] for p in pts)) - 1)
        a1 = min(w, int(max(p[0] for p in pts)) + 2)
        b0 = max(0, int(min(p[1] for p in pts)) - 1)
        b1 = min(h, int(max(p[1] for p in pts)) + 2)
        img = Image.new("1", (max(1, a1 - a0), max(1, b1 - b0)), 0)
        ImageDraw.Draw(img).polygon([(p[0] - a0, p[1] - b0) for p in pts], fill=1)
        return slice(b0, b1), slice(a0, a1), np.array(img, dtype=bool)

    # Stations along every carriageway: centre point, unit direction, normal.
    lots = []
    rng = random.Random(SEED)
    for e in sorted(edges, key=lambda e: (round(e["pts"][0][0], 1), round(e["pts"][0][1], 1))):
        pts = e["pts"]
        stations = []
        for a, b in zip(pts, pts[1:]):
            seg = math.dist(a, b)
            if seg < 0.1:
                continue
            ux, uz = (b[0] - a[0]) / seg, (b[1] - a[1]) / seg
            for k in range(int(seg / STEP)):
                t = k * STEP
                stations.append((a[0] + ux * t, a[1] + uz * t, ux, uz))
        for side in (-1.0, 1.0):
            front = []
            for x, z, ux, uz in stations:
                nx, nz = -uz * side, ux * side
                d = None
                if is_street(x, z) or is_street(x + nx * 2.0, z + nz * 2.0):
                    t = 0.5
                    while t < MAX_REACH:
                        if not is_street(x + nx * t, z + nz * t):
                            # Must stay off the street for a while (not a median gap).
                            if all(not is_street(x + nx * (t + s), z + nz * (t + s)) for s in (1.0, 3.0, 6.0)):
                                d = t
                            break
                        t += 0.5
                front.append(None if d is None else (x + nx * (d + FRONT_GAP), z + nz * (d + FRONT_GAP), nx, nz))
            k = 0
            while k < len(front):
                if front[k] is None:
                    k += 1
                    continue
                width = rng.uniform(*WIDTHS)
                n_st = max(2, int(width / STEP))
                j = min(k + n_st, len(front) - 1)
                # The lot ends early at a gap (side road) or a jump in the street edge.
                end = k
                while end + 1 <= j and front[end + 1] is not None and \
                        math.dist(front[end + 1][:2], front[end][:2]) < STEP * 3.0:
                    end += 1
                if (end - k) * STEP < 4.0:
                    k = end + 1
                    continue
                a, b = front[k], front[end]
                fx, fz = b[0] - a[0], b[1] - a[1]
                fl = math.hypot(fx, fz)
                nx, nz = (a[2] + b[2]) / 2, (a[3] + b[3]) / 2
                nl = math.hypot(nx, nz) or 1.0
                nx, nz = nx / nl, nz / nl
                placed = False
                depth = rng.uniform(*DEPTHS)
                while depth >= MIN_DEPTH:
                    q = [(a[0], a[1]), (b[0], b[1]), (b[0] + nx * depth, b[1] + nz * depth), (a[0] + nx * depth, a[1] + nz * depth)]
                    rs, cs, mask = quad_cells(q)
                    if not (mask & blocked[rs, cs]).any():
                        blocked[rs, cs] |= mask
                        lots.append((q, fl))
                        placed = True
                        break
                    depth -= 2.0
                k = end + 1 if placed else k + 2

    # Write the lots, removing infill they overlap.
    def tri_area(q):
        return sum(q[i - 1][0] * q[i][1] - q[i][0] * q[i - 1][1] for i in range(len(q))) / 2.0

    lot_masks_img = Image.new("1", (w, h), 0)
    dl = ImageDraw.Draw(lot_masks_img)
    for q, _ in lots:
        dl.polygon([px(*p) for p in q], fill=1)
    lot_mask = np.array(lot_masks_img, dtype=bool)

    def on_lot(x: float, z: float) -> bool:
        c = cell(x, z)
        return c is not None and bool(lot_mask[c])

    gone_fill = []
    for f, d in chunks.items():
        kept = []
        for b in d["blds"]:
            p = b["p"]
            if b.get("f") in (1, 2):
                n = len(p) // 2
                cx, cz = sum(p[0::2]) / n, sum(p[1::2]) / n
                hits = sum(on_lot(p[2 * m], p[2 * m + 1]) for m in range(n)) + on_lot(cx, cz)
                if hits:
                    gone_fill.append(p)
                    continue
            kept.append(b)
        d["blds"] = kept
    heights_rng = random.Random(SEED + 1)
    added = 0
    for q, fl in lots:
        if tri_area(q) > 0:  # same winding as the shipped footprints
            q = [q[0], q[3], q[2], q[1]]
        cx = sum(p[0] for p in q) / 4
        cz = sum(p[1] for p in q) / 4
        r = heights_rng.random()
        floors = 3 + int(heights_rng.random() * 3) if r < 0.6 else (6 + int(heights_rng.random() * 3) if r < 0.9 else 9 + int(heights_rng.random() * 3))
        bld = {"p": [round(v, 2) for p in q for v in p], "h": round(floors * 3.2 + heights_rng.uniform(0.2, 1.2), 2), "k": "",
               "z": ZONE, "s": heights_rng.randrange(9973), "f": 4}
        f = WORLD / "chunks" / f"c_{int(math.floor(cx / size))}_{int(math.floor(cz / size))}.json"
        if f not in chunks:
            continue
        chunks[f]["blds"].append(bld)
        added += 1
    for f, d in chunks.items():
        f.write_text(json.dumps(d, separators=(",", ":")))

    # Things standing on the new lots: dress points, plot and compound walls, name boards.
    dress_gone = walls_gone = boards_gone = 0
    for i in range(c0[0], c1[0] + 1):
        for j in range(c0[1], c1[1] + 1):
            f = WORLD / "dress" / f"c_{i}_{j}.json"
            if f.exists():
                d = load(f)
                changed = False
                for key in POINT_KEYS:
                    items = d.get(key, [])
                    kept = [it for it in items if not on_lot(float(it[0]), float(it[1]))]
                    if len(kept) != len(items):
                        dress_gone += len(items) - len(kept)
                        d[key] = kept
                        changed = True
                if changed:
                    f.write_text(json.dumps(d, separators=(",", ":")))
            f = WORLD / "plots" / f"c_{i}_{j}.json"
            if f.exists():
                d = load(f)
                changed = False
                for key in ("walls", "gates"):
                    segs = d.get(key, [])
                    kept = [s for s in segs if not (on_lot(s[0], s[1]) or on_lot(s[2], s[3]) or on_lot((s[0] + s[2]) / 2, (s[1] + s[3]) / 2))]
                    if len(kept) != len(segs):
                        walls_gone += len(segs) - len(kept)
                        d[key] = kept
                        changed = True
                if changed:
                    f.write_text(json.dumps(d, separators=(",", ":")))
    comp = load(WORLD / "compounds.json")
    for key, segs in comp.get("chunks", {}).items():
        kept = [s for s in segs if not (on_lot(s[0], s[1]) or on_lot(s[2], s[3]))]
        walls_gone += len(segs) - len(kept)
        comp["chunks"][key] = kept
    (WORLD / "compounds.json").write_text(json.dumps(comp, separators=(",", ":")))
    names = load(WORLD / "building_names.json")
    gone_cells = Image.new("1", (w, h), 0)
    dg = ImageDraw.Draw(gone_cells)
    for p in gone_fill:
        dg.polygon([px(p[k], p[k + 1]) for k in range(0, len(p), 2)], fill=1)
    gone_mask = np.array(gone_cells, dtype=bool)
    kept = []
    for n in names:
        c = cell(float(n[0]), float(n[1]))
        near = c is not None and (gone_mask[max(0, c[0] - 4):c[0] + 5, max(0, c[1] - 4):c[1] + 5].any())
        if near or on_lot(float(n[0]), float(n[1])):
            boards_gone += 1
        else:
            kept.append(n)
    (WORLD / "building_names.json").write_text(json.dumps(kept, separators=(",", ":")))
    print(f"Anna Salai frontage: {added} lots (replacing {len(gone_fill)} infill blocks, {removed_prev} old lots); "
          f"cleared {dress_gone} dress points, {walls_gone} walls, {boards_gone} name boards")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
