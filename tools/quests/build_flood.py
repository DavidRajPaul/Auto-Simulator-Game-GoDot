"""Monsoon flood for a quest: water standing on the real drawn roads round the quest's places.

Writes data/missions/floods/<quest>.json, read by scripts/world/QuestFlood.gd:
  origin [x, z], cell (m), nx, nz, road_y, depth_cm (nx*nz ints, row-major by z), wet (0..100).
A grid vertex is wet where it is on (or within a step of) a drawn carriageway, junction or
footpath (chunk "surf" triangles, rasterised at 0.5 m), inside the flood area (circles round the
quest places that fade out over their last FADE_M, so the flood has no straight edge). Depth is a
shallow sheet with gentle value-noise dips, plus deep basins (the flooded junction to avoid).
Depths stay under the auto's stall depth (VehicleStats.water_stall_depth_m 0.28) except in a basin.

Owner request (Nov 28): "it is raining but it does not look like a serious situation … add a
realistic flood". Rebuild: python3 tools/quests/build_sq17_story.py (calls build()).
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
CHUNK_M = 250.0
RASTER = 2  # pixels per metre
FADE_M = 22.0
ROAD_Y = 0.06
PAVED = ("road", "junction", "walk", "lane", "centre")


def _value_noise(x, z, scale, seed):
    """Smooth 0..1 noise from a hashed lattice (bilinear, smoothstepped)."""
    gx, gz = x / scale, z / scale
    x0, z0 = np.floor(gx), np.floor(gz)
    fx, fz = gx - x0, gz - z0
    fx, fz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)

    def h(i, j):
        v = np.sin(i * 127.1 + j * 311.7 + seed * 74.7) * 43758.5453
        return v - np.floor(v)

    a, b = h(x0, z0), h(x0 + 1, z0)
    c, d = h(x0, z0 + 1), h(x0 + 1, z0 + 1)
    return (a * (1 - fx) + b * fx) * (1 - fz) + (c * (1 - fx) + d * fx) * fz


def _paved_mask(x0, z0, x1, z1):
    w, h = int((x1 - x0) * RASTER), int((z1 - z0) * RASTER)
    img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(img)
    for i in range(math.floor(x0 / CHUNK_M), math.floor(x1 / CHUNK_M) + 1):
        for j in range(math.floor(z0 / CHUNK_M), math.floor(z1 / CHUNK_M) + 1):
            path = os.path.join(ROOT, "data", "world", "chunks", f"c_{i}_{j}.json")
            if not os.path.exists(path):
                continue
            surf = json.load(open(path)).get("surf", {})
            for kind in PAVED:
                part = surf.get(kind)
                if not part:
                    continue
                v, idx = part["v"], part["i"]
                for t in range(0, len(idx) - 2, 3):
                    tri = [((v[2 * k] - x0) * RASTER, (v[2 * k + 1] - z0) * RASTER) for k in idx[t:t + 3]]
                    draw.polygon(tri, fill=255)
    return np.asarray(img) > 0


def build(quest_id, areas, basins, base_m=0.11, cell=1.5):
    """areas: [(x, z, radius)], basins: [(x, z, radius, depth_m)]."""
    x0 = min(a[0] - a[2] for a in areas)
    x1 = max(a[0] + a[2] for a in areas)
    z0 = min(a[1] - a[2] for a in areas)
    z1 = max(a[1] + a[2] for a in areas)
    x0, z0 = math.floor(x0 / cell) * cell, math.floor(z0 / cell) * cell
    nx, nz = int((x1 - x0) / cell) + 2, int((z1 - z0) / cell) + 2
    x1, z1 = x0 + (nx - 1) * cell, z0 + (nz - 1) * cell
    mask = _paved_mask(x0, z0, x1 + 1, z1 + 1)
    dist_px = ndimage.distance_transform_edt(~mask)
    gx, gz = np.meshgrid(x0 + np.arange(nx) * cell, z0 + np.arange(nz) * cell)
    px = np.clip(((gx - x0) * RASTER).astype(int), 0, mask.shape[1] - 1)
    pz = np.clip(((gz - z0) * RASTER).astype(int), 0, mask.shape[0] - 1)
    off_road_m = dist_px[pz, px] / RASTER
    # Water spreads a little past the paving (gutters, the foot of compound walls), then thins out.
    on_road = np.clip(1.0 - (off_road_m - 0.8) / 1.6, 0.0, 1.0)
    reach = np.zeros_like(gx)
    for ax, az, r in areas:
        d = np.hypot(gx - ax, gz - az)
        t = np.clip((r - d) / FADE_M, 0.0, 1.0)
        reach = np.maximum(reach, t * t * (3 - 2 * t))
    # A ragged outer edge: noise eats into the fade band so it isn't a circle.
    reach = np.clip(reach * 1.25 - _value_noise(gx, gz, 9.0, 3) * 0.35, 0.0, 1.0)
    depth = base_m * (0.65 + 0.7 * _value_noise(gx, gz, 26.0, 1)) * np.clip(reach * 1.6, 0.0, 1.0)
    depth = np.minimum(depth, 0.2)
    for bx, bz, r, dm in basins:
        d = np.hypot(gx - bx, gz - bz)
        t = np.clip(1.0 - d / r, 0.0, 1.0)
        depth = np.maximum(depth, dm * (t * t * (3 - 2 * t)) + base_m * 0.9 * (d < r * 1.3))
    wet = np.clip(on_road * np.clip(reach * 2.0, 0.0, 1.0), 0.0, 1.0)
    for bx, bz, r, dm in basins:  # A basin floods the footpaths and kerbs as well.
        d = np.hypot(gx - bx, gz - bz)
        wet = np.maximum(wet, np.clip((r * 1.1 - d) / 4.0, 0.0, 1.0) * np.clip(1.0 - (off_road_m - 3.0) / 3.0, 0.0, 1.0))
    depth = np.where(wet > 0.0, depth, 0.0)
    out = {
        "quest": quest_id,
        "origin": [round(x0, 2), round(z0, 2)],
        "cell": cell,
        "nx": nx,
        "nz": nz,
        "road_y": ROAD_Y,
        "depth_cm": [int(round(v * 100)) for v in depth.ravel()],
        "wet": [int(round(v * 100)) for v in wet.ravel()],
    }
    path = os.path.join(ROOT, "data", "missions", "floods", quest_id + ".json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    wet_cells = int((wet > 0.05).sum())
    print(f"flood {quest_id}: {nx}x{nz} grid, {wet_cells} wet vertices ({wet_cells * cell * cell:.0f} m2), "
          f"deepest {depth.max():.2f} m -> {os.path.relpath(path, ROOT)}")
    return path
