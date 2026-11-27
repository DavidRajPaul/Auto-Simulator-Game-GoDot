#!/usr/bin/env python3
"""Sets kerb trees back from the road so their crowns stop filling the driver's view.

Nov 27 owner report: "the leaves and branches occupy the road and it is annoying. Place the trees a
bit away from the road so they don't block the driving view, and at the same time don't get cut off
(by the buildings)". The dressing put trunks at the kerb, so a 5 m crown hung 3-4 m over the
carriageway at windscreen height.

For every broadleaf dress tree (codes 0, 2, 3, 4; palms and median trees are left alone: a palm's
crown is high above the auto and median palms belong in the median), with crown radius
R = CROWN_M x scale:
* the trunk must stand at least ROAD_SHARE x R from the drawn carriageway (the crown hangs over the
  road by at most (1 - ROAD_SHARE) x R, about a metre), and
* at least BUILDING_SHARE x R from any building, so the crown doesn't vanish into a wall.
A tree that breaks either rule moves straight back from its nearest carriageway point to the first
spot that keeps both and stays clear of poles, transformers, parked vehicles, stalls, carts and
compound walls. If no spot within MOVE_MAX_M works, it is shrunk (never below MIN_SCALE) to fit the
best spot on that line, and if even that fails it is removed (the owner is fine with fewer pavement
trees, Nov 2026). Tree count never grows.

Run after build_plots.py and place_street_life.py (it reads plots walls); re-run after anything that
rewrites the dress files: python3 tools/osm/set_back_trees.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_street_dressing import ROAD_RES, WORLD  # noqa: E402

BROADLEAF = {0, 2, 3, 4}
CROWN_M = 5.0          # typical crown radius at scale 1 (trees.json radius 3.7-6.6 m, median ~5)
ROAD_SHARE = 0.78      # trunk at least this share of the crown radius from the carriageway
BUILDING_SHARE = 0.35  # ... and this share from a building wall
MOVE_MAX_M = 6.0
STEP_M = 0.25
MIN_SCALE = 0.55
ITEM_CLEAR_M = 1.4     # from poles, transformers, parked vehicles, stalls, carts
WALL_CLEAR_M = 0.7     # from compound walls
MEDIAN_SEED = 900000


MARGIN_M = 24.0
CARRIAGEWAY = ("road", "lane", "junction", "centre", "road_up", "lane_up", "junction_up", "centre_up")
_chunks: dict = {}


def chunk_data(i: int, j: int) -> dict | None:
    if (i, j) not in _chunks:
        f = WORLD / "chunks" / f"c_{i}_{j}.json"
        _chunks[(i, j)] = json.loads(f.read_text()) if f.exists() else None
        if len(_chunks) > 40:
            _chunks.pop(next(iter(_chunks)))
    return _chunks[(i, j)]


class Tile:
    """Carriageway and building rasters (ROAD_RES) of one chunk plus a margin, with distances."""

    def __init__(self, ci: int, cj: int, size: float):
        self.ox, self.oz = ci * size - MARGIN_M, cj * size - MARGIN_M
        n = int((size + 2 * MARGIN_M) / ROAD_RES)
        road_img = Image.new("L", (n, n), 0)
        bld_img = Image.new("L", (n, n), 0)
        dr, db = ImageDraw.Draw(road_img), ImageDraw.Draw(bld_img)
        for i in (ci - 1, ci, ci + 1):
            for j in (cj - 1, cj, cj + 1):
                d = chunk_data(i, j)
                if d is None:
                    continue
                for kind, part in d.get("surf", {}).items():
                    if kind not in CARRIAGEWAY:
                        continue
                    v, idx = part["v"], part["i"]
                    for t in range(0, len(idx) - 2, 3):
                        dr.polygon([self.px(v[2 * idx[t + k]], v[2 * idx[t + k] + 1]) for k in range(3)], fill=1)
                for b in d.get("blds", []):
                    p = b["p"]
                    db.polygon([self.px(p[2 * k], p[2 * k + 1]) for k in range(len(p) // 2)], fill=1)
        self.road = np.asarray(road_img, dtype=bool)
        self.bld = np.asarray(bld_img, dtype=bool)
        if self.road.any():
            dist, idx = distance_transform_edt(~self.road, return_indices=True)
            self.d_road = dist * ROAD_RES
            self.near_i, self.near_j = idx[0], idx[1]
        else:
            self.d_road = np.full(self.road.shape, 1e9)
            self.near_i, self.near_j = np.indices(self.road.shape)
        self.d_bld = distance_transform_edt(~self.bld) * ROAD_RES if self.bld.any() else np.full(self.bld.shape, 1e9)
        self.n = n

    def px(self, x: float, z: float) -> tuple[float, float]:
        return ((x - self.ox) / ROAD_RES, (z - self.oz) / ROAD_RES)

    def cell(self, x: float, z: float):
        i, j = int((z - self.oz) / ROAD_RES), int((x - self.ox) / ROAD_RES)
        return (i, j) if 0 <= i < self.n and 0 <= j < self.n else None


def seg_dist(px, pz, x0, z0, x1, z1):
    dx, dz = x1 - x0, z1 - z0
    t = max(0.0, min(1.0, ((px - x0) * dx + (pz - z0) * dz) / (dx * dx + dz * dz + 1e-9)))
    return math.hypot(px - x0 - t * dx, pz - z0 - t * dz)


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    size = float(manifest["chunk_size"])
    dress = {}
    for c in manifest["chunks"]:
        f = WORLD / "dress" / f"c_{c[0]}_{c[1]}.json"
        if f.exists():
            dress[(c[0], c[1])] = json.loads(f.read_text())

    # Things a trunk must keep off, bucketed by chunk.
    items: dict[tuple[int, int], list[tuple[float, float]]] = {}
    walls: dict[tuple[int, int], list[list[float]]] = {}
    for k, d in dress.items():
        pts = items.setdefault(k, [])
        for key in ("poles", "parking", "stalls", "carts", "barricades", "lamps", "booths"):
            for it in d.get(key, []):
                if isinstance(it, list) and len(it) >= 2 and isinstance(it[0], (int, float)):
                    pts.append((float(it[0]), float(it[1])))
        for it in d.get("xfmr", []):
            if isinstance(it, list) and len(it) >= 2:
                pts.append((float(it[0]), float(it[1])))
        pf = WORLD / "plots" / f"c_{k[0]}_{k[1]}.json"
        if pf.exists():
            walls[k] = [wl[:4] for wl in json.loads(pf.read_text()).get("walls", [])]
    lm = WORLD / "landmark_compounds.json"
    if lm.exists():
        for key, segs in json.loads(lm.read_text()).get("walls", {}).items():
            i, j = (int(v) for v in key.split(","))
            walls.setdefault((i, j), []).extend([s[1:5] for s in segs])

    def free(x, z, moved_from):
        k = (int(math.floor(x / size)), int(math.floor(z / size)))
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                kk = (k[0] + di, k[1] + dj)
                for px, pz in items.get(kk, []):
                    if math.hypot(px - x, pz - z) < ITEM_CLEAR_M:
                        return False
                for wl in walls.get(kk, []):
                    if seg_dist(x, z, *wl) < WALL_CLEAR_M:
                        return False
        return True

    kept = moved = shrunk = removed = 0
    out: dict[tuple[int, int], list] = {k: [] for k in dress}
    for k, d in dress.items():
        tile = None
        for t in d.get("trees", []):
            x, z, code, scale = float(t[0]), float(t[1]), int(t[2]), float(t[3])
            seed = int(t[4]) if len(t) > 4 else 0
            if code not in BROADLEAF or seed >= MEDIAN_SEED:
                out[k].append(t)
                kept += 1
                continue
            if tile is None:
                tile = Tile(k[0], k[1], size)
            cell, road, bld, d_road, d_bld = tile.cell, tile.road, tile.bld, tile.d_road, tile.d_bld
            c0 = cell(x, z)
            if c0 is None:
                out[k].append(t)
                kept += 1
                continue
            r = CROWN_M * scale
            if d_road[c0] >= ROAD_SHARE * r and d_bld[c0] >= BUILDING_SHARE * r:
                out[k].append(t)
                kept += 1
                continue
            # Straight back from the nearest carriageway cell.
            ni, nj = tile.near_i[c0], tile.near_j[c0]
            rx, rz = tile.ox + (nj + 0.5) * ROAD_RES, tile.oz + (ni + 0.5) * ROAD_RES
            dx, dz = x - rx, z - rz
            n = math.hypot(dx, dz)
            if n < 0.05:
                removed += 1
                continue
            dx, dz = dx / n, dz / n
            best = None  # (fit scale, x, z)
            placed = None
            s = 0.0
            while s <= MOVE_MAX_M:
                px, pz = x + dx * s, z + dz * s
                c1 = cell(px, pz)
                if c1 is None or bld[c1] or road[c1]:
                    break
                if free(px, pz, (x, z)):
                    if d_road[c1] >= ROAD_SHARE * r and d_bld[c1] >= BUILDING_SHARE * r:
                        placed = (px, pz)
                        break
                    fit = min(d_road[c1] / (ROAD_SHARE * CROWN_M), d_bld[c1] / (BUILDING_SHARE * CROWN_M))
                    if best is None or fit > best[0]:
                        best = (fit, px, pz)
                s += STEP_M
            new = None
            if placed is not None:
                new = [round(placed[0], 2), round(placed[1], 2), code, scale] + list(t[4:])
                moved += 1 if s > 0 else 0
            elif best is not None and best[0] >= MIN_SCALE:
                new = [round(best[1], 2), round(best[2], 2), code, round(min(scale, best[0]), 2)] + list(t[4:])
                shrunk += 1
            if new is None:
                removed += 1
                continue
            nk = (int(math.floor(new[0] / size)), int(math.floor(new[1] / size)))
            out[nk if nk in out else k].append(new)
    for k, d in dress.items():
        if d.get("trees", []) == out[k]:
            continue
        d["trees"] = out[k]
        (WORLD / "dress" / f"c_{k[0]}_{k[1]}.json").write_text(json.dumps(d, separators=(",", ":")))
    print(f"trees: {kept} already clear, {moved} set back, {shrunk} set back and made smaller, {removed} removed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
