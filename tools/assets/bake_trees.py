#!/usr/bin/env python3
"""Street trees: the owner's Tripo tree models -> two levels of detail for scripts/world/StreetTrees.gd.

Sources (committed, not exported): assets_src/models/trees/<name>_src.glb, unit-size Tripo
exports (one mesh, one 512 px colour texture; the coconut palm has 2048 px).

Per species (SPECIES below; `code` is the tree code in data/world/dress "trees"):
  assets/models/city/trees/<name>.glb      near: full model, real height, origin at the trunk base
                                            (tools/assets/bake_tree.mjs). Not simplified: every
                                            leaf card is its own UV island, so meshoptimizer
                                            stalls or shreds the cards (tried, Nov 2 2026).
All species share one far impostor atlas:
  assets/models/city/trees/tree_impostors.png  one row per species, VIEWS columns: the near model
                                            rendered unlit from VIEWS directions (orthographic,
                                            software raster here, no GPU needed)
  assets/models/city/trees/trees.json      height / crown radius / atlas row per species code

Run after changing a source or a SPECIES entry:
  (cd tools/assets && npm i) && python3 tools/assets/bake_trees.py
Needs: Node.js + tools/assets/node_modules, numpy, pillow, trimesh.
"""
from __future__ import annotations

import json
import math
import subprocess
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "models" / "trees"
OUT = ROOT / "assets" / "models" / "city" / "trees"
NODE_SCRIPT = ROOT / "tools" / "assets" / "bake_tree.mjs"

# code -> name, real height (m). Typical Chennai avenue sizes; the dressing data scales each
# tree by 0.8-1.25. Ashoka has two of the owner's variants (A: spreading, B: slim).
SPECIES = [
    {"code": 0, "name": "neem", "height": 10.0},
    {"code": 1, "name": "coconut_palm", "height": 8.0},
    {"code": 2, "name": "ashoka_a", "height": 8.5},
    {"code": 3, "name": "ashoka_b", "height": 10.0},
    {"code": 4, "name": "pungai", "height": 8.5},
]
VIEWS = 4          # impostor cards per tree, VIEWS directions 180/VIEWS degrees apart
CELL = 256         # atlas cell (px), square; the card is stretched to radius x height in game
SUPER = 3          # supersampling for the software raster


def render_view(mesh: trimesh.Trimesh, tex: np.ndarray, angle: float, radius: float, height: float) -> np.ndarray:
    """Unlit orthographic render of `mesh` looking along d = Y x a, where a = (cos, 0, sin)(angle)
    is screen-right. Window: a in [-radius, radius], y in [0, height]. Returns RGBA float CELL^2."""
    n = CELL * SUPER
    a = np.array([math.cos(angle), 0.0, math.sin(angle)])
    d = np.cross([0.0, 1.0, 0.0], a)
    v = mesh.vertices
    sx = (v @ a + radius) / (2.0 * radius) * n
    sy = (1.0 - v[:, 1] / height) * n
    depth = v @ d
    uv = mesh.visual.uv
    th, tw = tex.shape[:2]
    rgb = np.zeros((n, n, 3), np.float32)
    zbuf = np.full((n, n), np.inf, np.float32)
    for f in mesh.faces:
        x0, x1, x2 = sx[f]
        y0, y1, y2 = sy[f]
        minx = max(int(math.floor(min(x0, x1, x2))), 0)
        maxx = min(int(math.ceil(max(x0, x1, x2))), n - 1)
        miny = max(int(math.floor(min(y0, y1, y2))), 0)
        maxy = min(int(math.ceil(max(y0, y1, y2))), n - 1)
        if minx > maxx or miny > maxy:
            continue
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-9:
            continue
        px, py = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
        w0 = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / den
        w1 = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / den
        w2 = 1.0 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        z = w0 * depth[f[0]] + w1 * depth[f[1]] + w2 * depth[f[2]]
        iy, ix = py[inside].astype(int), px[inside].astype(int)
        zi = z[inside]
        closer = zi < zbuf[iy, ix]
        if not closer.any():
            continue
        iy, ix, zi = iy[closer], ix[closer], zi[closer]
        b0, b1, b2 = w0[inside][closer], w1[inside][closer], w2[inside][closer]
        u = b0 * uv[f[0], 0] + b1 * uv[f[1], 0] + b2 * uv[f[2], 0]
        t = b0 * uv[f[0], 1] + b1 * uv[f[1], 1] + b2 * uv[f[2], 1]
        # trimesh flips glTF V on load (OpenGL convention: v up), so the image row is (1 - v).
        tx = np.clip((u % 1.0) * tw, 0, tw - 1).astype(int)
        ty = np.clip((1.0 - (t % 1.0)) * th, 0, th - 1).astype(int)
        zbuf[iy, ix] = zi
        rgb[iy, ix] = tex[ty, tx, :3]
    alpha = np.isfinite(zbuf).astype(np.float32)
    # Box-filter down (premultiplied), so card edges get soft alpha for the mipmaps.
    pre = np.concatenate([rgb * alpha[..., None], alpha[..., None]], axis=2)
    pre = pre.reshape(CELL, SUPER, CELL, SUPER, 4).mean(axis=(1, 3))
    a_ = pre[..., 3:4]
    col = np.where(a_ > 0, pre[..., :3] / np.maximum(a_, 1e-6), 0.0)
    return np.concatenate([col, a_], axis=2)


def bleed(cell: np.ndarray, steps: int = 6) -> np.ndarray:
    """Copy colour into transparent pixels next to the crown so mipmaps don't fringe dark."""
    col = cell[..., :3].copy()
    filled = cell[..., 3] > 0.0
    for _ in range(steps):
        acc = np.zeros_like(col)
        cnt = np.zeros(filled.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(col * filled[..., None], dy, 0), dx, 1)
            cnt += np.roll(np.roll(filled.astype(np.float32), dy, 0), dx, 1)
        grow = (~filled) & (cnt > 0)
        col[grow] = acc[grow] / cnt[grow][:, None]
        filled = filled | grow
    return np.concatenate([col, cell[..., 3:4]], axis=2)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    atlas = np.zeros((CELL * len(SPECIES), CELL * VIEWS, 4), np.float32)
    meta: dict = {"views": VIEWS, "rows": len(SPECIES), "species": {}}
    for row, sp in enumerate(SPECIES):
        name = sp["name"]
        near = OUT / f"{name}.glb"
        res = subprocess.run(["node", str(NODE_SCRIPT), str(SRC / f"{name}_src.glb"), str(near), str(sp["height"])],
                             check=True, capture_output=True, text=True, cwd=NODE_SCRIPT.parent)
        stats = json.loads(res.stdout.strip().splitlines()[-1])
        mesh = trimesh.load(near, force="mesh", process=False)
        tex = np.asarray(mesh.visual.material.baseColorTexture.convert("RGBA"), np.float32) / 255.0
        radius = float(stats["radius"])
        for k in range(VIEWS):
            cell = bleed(render_view(mesh, tex, math.pi * k / VIEWS, radius, sp["height"]))
            atlas[row * CELL:(row + 1) * CELL, k * CELL:(k + 1) * CELL] = cell
        meta["species"][str(sp["code"])] = {"name": name, "height": sp["height"], "radius": radius, "row": row,
                                            "tris": int(stats["tris"])}
        print(f"{name}: {stats}")
    Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT / "tree_impostors.png", optimize=True)
    (OUT / "trees.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"atlas {atlas.shape[1]}x{atlas.shape[0]} -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
