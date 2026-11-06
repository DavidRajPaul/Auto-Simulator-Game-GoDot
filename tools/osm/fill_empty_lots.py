#!/usr/bin/env python3
"""Fill the empty land of the generated city with buildings and roadside stalls.

OSM and build_fill_buildings leave wide bare plots behind the road-front row. This pass reads the
real drawn road and footpath surfaces, finds what is still empty, and adds rows of buildings
facing the road, then vegetable stalls, fancy stores, petti kadais and flower carts on the kerbs.

Keeps clear of roads, footpaths, water, parks, the beach, compounds, landmarks, quest stops, bus
stops, trees, poles and parked vehicles. Deterministic, and safe to run again: it first removes
what it added last time ("f": 2 buildings, "stalls" lists).
Run after build_street_dressing, build_roadside_parking, append_street_shops and build_bus_stops.
Usage: python3 tools/osm/fill_empty_lots.py
"""
from __future__ import annotations

import json
import math
import random
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from config import CHUNK_SIZE_M, DEFAULT_ZONE_STYLE, ZONES

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CELL_M = 1.0
ROAD_MARGIN_M = 4.0    # Kerb strip kept free for parked bikes, stalls and walkers.
BUILD_MARGIN_M = 1.6   # Lane between buildings.
MAX_ROWS = 22 # Tries, going deeper into the block.
MAX_CHUNK_BUILDINGS = 190
SWEEP_STEP_M = 7.0
SWEEP_SIZES = ((15.0, 13.0), (11.0, 10.0), (8.0, 8.0))  # Largest first, then what still fits.
MARINA_DENSITY = 0.3
SEED = 600004
# Stall kind -> [StreetStallKit types, how many, spacing, half length, half depth].
STALLS = {
    "vegetable": ([0, 1], 520, 28.0, 1.7, 1.1),
    "fancy": ([2, 3], 380, 34.0, 1.6, 1.0),
    "petti": ([4, 5], 460, 30.0, 1.3, 1.1),
    "flower": ([6], 180, 44.0, 1.4, 0.8),
}
STALL_MARKETS = {"mylapore": 3, "t_nagar": 4, "anna_salai": 2}  # Markets get stalls first.


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    x0, z0, x1, z1 = manifest["bounds"]
    width, height = int((x1 - x0) / CELL_M) + 2, int((z1 - z0) / CELL_M) + 2
    to_px = lambda x, z: ((x - x0) / CELL_M, (z - z0) / CELL_M)  # noqa: E731
    image = Image.new("1", (width, height), 0)
    draw = ImageDraw.Draw(image)

    carriage_img = Image.new("1", (width, height), 0)
    carriage = ImageDraw.Draw(carriage_img)
    chunks = {}
    for path in sorted((WORLD / "chunks").glob("c_*.json")):
        d = json.loads(path.read_text())
        before = len(d.get("blds", []))
        d["blds"] = [b for b in d.get("blds", []) if b.get("f") != 2]
        chunks[path] = (d, before != len(d["blds"]))
        for name in ("road", "walk", "junction"):
            v = d.get("surf", {}).get(name, {}).get("v", [])
            i = d.get("surf", {}).get(name, {}).get("i", [])
            for t in range(0, len(i), 3):
                tri = [to_px(v[i[t + k] * 2], v[i[t + k] * 2 + 1]) for k in range(3)]
                draw.polygon(tri, fill=1)
                if name != "walk":
                    carriage.polygon(tri, fill=1)
        for b in d["blds"]:
            p = b["p"]
            draw.polygon([to_px(p[n], p[n + 1]) for n in range(0, len(p), 2)], fill=1)
    graph = json.loads((WORLD / "road_graph.json").read_text())
    for e in graph["edges"]:
        draw.line([to_px(*q) for q in e["pts"]], fill=1, width=int(float(e["w"]) / CELL_M) + 2)
    occupied = np.array(image, dtype=bool)
    # Keep the kerb strip open: grow what is drawn so far by the road margin.
    occupied = grow(occupied, int(ROAD_MARGIN_M / CELL_M))

    extra = Image.new("1", (width, height), 0)
    d2 = ImageDraw.Draw(extra)
    areas = json.loads((WORLD / "areas.json").read_text())
    for name in ("water", "sea", "beach", "park"):
        for poly in areas.get(name, []):
            if len(poly) >= 3:
                d2.polygon([to_px(q[0], q[1]) for q in poly], fill=1)
    compounds = json.loads((WORLD / "compounds.json").read_text())["chunks"]
    for walls in compounds.values():
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
    for s in stops.get("stops", stops) if isinstance(stops, dict) else stops:
        dot(float(s["x"]), float(s["z"]), 7.0)
    quest_points = []
    for f in sorted((ROOT / "data/missions/side_quests").glob("sq_*.tres")):
        for a, b in re.findall(r"Vector3\((-?[\d.]+), 0, (-?[\d.]+)\)", f.read_text()):
            quest_points.append((float(a), float(b)))
            dot(float(a), float(b), 11.0)
    dress = {}
    for path in sorted((WORLD / "dress").glob("c_*.json")):
        d = json.loads(path.read_text())
        d.pop("stalls", None)
        dress[path] = d
        for q in d.get("trees", []):
            dot(q[0], q[1], 2.0)
        for q in d.get("poles", []):
            dot(q[0], q[1], 1.0)
        for q in d.get("xfmr", []):
            dot(q[0], q[1], 3.5)
        for q in d.get("parking", []):
            dot(q[0], q[1], 2.5)
    occupied |= np.array(extra, dtype=bool)

    rng = random.Random(SEED)
    zones = manifest["zones"]

    def zone_at(x: float, z: float) -> str:
        best, bd = "", 1e9
        for zz in zones:
            dist = math.hypot(x - zz["x"], z - zz["z"])
            if dist < zz["r"] and dist < bd:
                best, bd = zz["id"], dist
        return best

    def cells(cx: float, cz: float, ux: float, uz: float, hw: float, hd: float, step: float = 1.0):
        a = np.arange(-hw, hw + step, step)
        b = np.arange(-hd, hd + step, step)
        aa, bb = np.meshgrid(a, b)
        xs = ((cx + aa * ux - bb * uz - x0) / CELL_M).astype(int).ravel()
        zs = ((cz + aa * uz + bb * ux - z0) / CELL_M).astype(int).ravel()
        if xs.min() < 0 or zs.min() < 0 or xs.max() >= width or zs.max() >= height:
            return None
        return zs, xs

    def free(cx: float, cz: float, ux: float, uz: float, hw: float, hd: float) -> bool:
        at = cells(cx, cz, ux, uz, hw, hd)
        return at is not None and not occupied[at].any()

    def mark(cx: float, cz: float, ux: float, uz: float, hw: float, hd: float) -> None:
        at = cells(cx, cz, ux, uz, hw, hd)
        if at is not None:
            occupied[at] = True

    segments = []
    for e in graph["edges"]:
        for a, b in zip(e["pts"], e["pts"][1:]):
            length = math.dist(a, b)
            if length >= 6.0:
                segments.append((a, b, length, float(e["w"]) * 0.5, e["c"]))
    rng.shuffle(segments)

    added = {}
    per_chunk = {}
    count = 0
    for a, b, length, half, _cls in segments:
        ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        for side in (-1.0, 1.0):
            nx, nz = -uz * side, ux * side
            t = rng.uniform(1.0, 5.0)
            while t < length - 3.0:
                w = rng.uniform(9.0, 15.0)
                px, pz = a[0] + ux * (t + w / 2), a[1] + uz * (t + w / 2)
                offset = half + ROAD_MARGIN_M + 1.0
                placed = False
                for row in range(MAX_ROWS):
                    d = rng.uniform(8.0, 13.0)
                    cx, cz = px + nx * (offset + d / 2), pz + nz * (offset + d / 2)
                    zone = zone_at(cx, cz)
                    if zone == "marina" and rng.random() > MARINA_DENSITY:
                        offset += d + BUILD_MARGIN_M
                        continue
                    key = (math.floor(cx / CHUNK_SIZE_M), math.floor(cz / CHUNK_SIZE_M))
                    if per_chunk.get(key, 0) >= MAX_CHUNK_BUILDINGS or not free(cx, cz, ux, uz, w / 2 + BUILD_MARGIN_M, d / 2 + BUILD_MARGIN_M):
                        offset += 3.0
                        continue
                    mark(cx, cz, ux, uz, w / 2 + BUILD_MARGIN_M, d / 2 + BUILD_MARGIN_M)
                    style = ZONES.get(zone, DEFAULT_ZONE_STYLE)
                    corners = [(cx + sx * w / 2 * ux - sz * d / 2 * uz, cz + sx * w / 2 * uz + sz * d / 2 * ux)
                               for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                    signed = sum(corners[i][0] * corners[i - 1][1] - corners[i - 1][0] * corners[i][1] for i in range(4))
                    if signed < 0:
                        corners.reverse()
                    added.setdefault(key, []).append({
                        "p": [round(v, 2) for q in corners for v in q], "h": round(rng.uniform(*style["bld_height"]) * (0.8 if row else 1.0), 2),
                        "k": "", "z": zone, "s": rng.randrange(9973), "f": 2})
                    per_chunk[key] = per_chunk.get(key, 0) + 1
                    count += 1
                    placed = True
                    offset += d + BUILD_MARGIN_M
                t += w + (BUILD_MARGIN_M if placed else 3.0)
    # Second sweep: odd-shaped plots the road rows cannot reach, lined up with the local streets.
    longest = {}
    for a, b, length, _half, _cls in segments:
        key = (math.floor((a[0] + b[0]) * 0.5 / CHUNK_SIZE_M), math.floor((a[1] + b[1]) * 0.5 / CHUNK_SIZE_M))
        if length > longest.get(key, (0.0,))[0]:
            longest[key] = (length, (b[0] - a[0]) / length, (b[1] - a[1]) / length)
    for key, (_length, ux, uz) in sorted(longest.items()):
        for gx in np.arange(0.0, CHUNK_SIZE_M, SWEEP_STEP_M):
            for gz in np.arange(0.0, CHUNK_SIZE_M, SWEEP_STEP_M):
                if per_chunk.get(key, 0) >= MAX_CHUNK_BUILDINGS:
                    continue
                cx, cz = key[0] * CHUNK_SIZE_M + float(gx), key[1] * CHUNK_SIZE_M + float(gz)
                zone = zone_at(cx, cz)
                if zone == "marina" and rng.random() > MARINA_DENSITY * 0.5:
                    continue
                for w, d in SWEEP_SIZES:
                    if free(cx, cz, ux, uz, w / 2 + BUILD_MARGIN_M, d / 2 + BUILD_MARGIN_M):
                        mark(cx, cz, ux, uz, w / 2 + BUILD_MARGIN_M, d / 2 + BUILD_MARGIN_M)
                        style = ZONES.get(zone, DEFAULT_ZONE_STYLE)
                        corners = [(cx + sx * w / 2 * ux - sz * d / 2 * uz, cz + sx * w / 2 * uz + sz * d / 2 * ux)
                                   for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                        signed = sum(corners[i][0] * corners[i - 1][1] - corners[i - 1][0] * corners[i][1] for i in range(4))
                        if signed < 0:
                            corners.reverse()
                        added.setdefault(key, []).append({
                            "p": [round(v, 2) for q in corners for v in q], "h": round(rng.uniform(*style["bld_height"]) * 0.8, 2),
                            "k": "", "z": zone, "s": rng.randrange(9973), "f": 2})
                        per_chunk[key] = per_chunk.get(key, 0) + 1
                        count += 1
                        break
    for path, (d, _changed) in chunks.items():
        m = re.match(r"c_(-?\d+)_(-?\d+)", path.stem)
        key = (int(m[1]), int(m[2]))
        d["blds"] += added.get(key, [])
        path.write_text(json.dumps(d, separators=(",", ":")))

    # Kerb stalls: on a clear bit of kerb, facing the road, markets first.
    solid_img = Image.new("1", (width, height), 0)
    solid_draw = ImageDraw.Draw(solid_img)
    for d, _changed in chunks.values():
        for b in d["blds"]:
            p = b["p"]
            solid_draw.polygon([to_px(p[n], p[n + 1]) for n in range(0, len(p), 2)], fill=1)
    solid = np.array(solid_img, dtype=bool) | np.array(extra, dtype=bool) | np.array(carriage_img, dtype=bool)
    stall_total = {}
    stalls = {}
    placed_at = []
    for kind, (types, wanted, spacing, hw, hd) in STALLS.items():
        order = sorted(segments, key=lambda s: -STALL_MARKETS.get(zone_at(*s[0]), 1) + rng.random() * 2.0)
        mine = []
        for a, b, length, half, cls in order:
            if len(mine) >= wanted:
                break
            if cls in ("trunk", "motorway") or length < 8.0:
                continue
            ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
            side = rng.choice((-1.0, 1.0))
            nx, nz = -uz * side, ux * side
            mx, mz = a[0] + ux * length * 0.5, a[1] + uz * length * 0.5
            cx, cz = mx + nx * (half + 2.3 + hd), mz + nz * (half + 2.3 + hd)
            if zone_at(cx, cz) == "marina" and kind != "flower":
                continue
            if any(math.hypot(cx - q, cz - r) < spacing for q, r in mine):
                continue
            if any(math.hypot(cx - q, cz - r) < 12.0 for q, r in placed_at) or any(math.hypot(cx - q, cz - r) < 12.0 for q, r in quest_points):
                continue
            at = cells(cx, cz, ux, uz, hw, hd)
            if at is None or solid[at].any():
                continue
            mine.append((cx, cz))
            placed_at.append((cx, cz))
            yaw = math.atan2(-nx, -nz)  # +Z of the stall faces the road.
            key = (math.floor(cx / CHUNK_SIZE_M), math.floor(cz / CHUNK_SIZE_M))
            stalls.setdefault(key, []).append([round(cx, 2), round(cz, 2), round(yaw, 3), rng.choice(types)])
        stall_total[kind] = len(mine)
    for path, d in dress.items():
        m = re.match(r"c_(-?\d+)_(-?\d+)", path.stem)
        key = (int(m[1]), int(m[2]))
        if key in stalls:
            d["stalls"] = stalls[key]
        path.write_text(json.dumps(d, separators=(",", ":")))
    land = ~(np.array(extra, dtype=bool) | np.array(carriage_img, dtype=bool))
    print(f"buildings added: {count}; stalls: {stall_total}; land still open: {100.0 * (~occupied & land).sum() / land.sum():.1f} %")
    return 0


def grow(mask: np.ndarray, cells: int) -> np.ndarray:
    """Square dilation by `cells`, using running sums so it stays fast on a 7 km map."""
    h, w = mask.shape
    s = np.zeros((h + 1, w + 1), dtype=np.int64)
    s[1:, 1:] = mask.cumsum(0).cumsum(1)
    r = cells
    y0 = np.clip(np.arange(h) - r, 0, h)[:, None]
    y1 = np.clip(np.arange(h) + r + 1, 0, h)[:, None]
    x0 = np.clip(np.arange(w) - r, 0, w)[None, :]
    x1 = np.clip(np.arange(w) + r + 1, 0, w)[None, :]
    return (s[y1, x1] - s[y0, x1] - s[y1, x0] + s[y0, x0]) > 0


if __name__ == "__main__":
    raise SystemExit(main())
