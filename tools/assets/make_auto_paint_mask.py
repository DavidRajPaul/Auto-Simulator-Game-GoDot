#!/usr/bin/env python3
"""Bakes the paint mask for the player auto (assets/models/vehicles/player_auto.glb).

Output: assets/models/vehicles/player_auto_paint_mask.png, same UV layout as the body texture.
  R = body paint  (the Chennai-yellow panels: texel hue 0.10-0.18, saturated, bright)
  G, B = 0 (the canopy is found in mesh space by the shader: its roof canvas samples a black
  texture region shared with other parts, so a UV mask cannot isolate it)
shaders/auto_paint.gdshader multiplies the target colour by each texel's brightness relative
to the stock colour, so panel shading, dirt and stickers survive and the wheels, chrome,
seat, lamps and chassis are never touched. This replaces "paint changes the whole model".

Usage: python3 tools/assets/make_auto_paint_mask.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
GLB = ROOT / "assets" / "models" / "vehicles" / "player_auto.glb"
OUT = ROOT / "assets" / "models" / "vehicles" / "player_auto_paint_mask.png"


def _hsv(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rm = nz & (mx == r)
    gm = nz & (mx == g) & ~rm
    bm = nz & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6.0
    h[gm] = (b - r)[gm] / d[gm] + 2.0
    h[bm] = (r - g)[bm] / d[bm] + 4.0
    return h / 6.0, s, mx


def main() -> int:
    scene = trimesh.load(GLB, force="scene")
    body = next(g for n, g in scene.geometry.items() if "lambert" in n)
    tex = np.asarray(body.visual.material.baseColorTexture.convert("RGB"), dtype=np.float32) / 255.0
    h_px, w_px = tex.shape[:2]
    hue, sat, val = _hsv(tex)

    yellow = (hue > 0.10) & (hue < 0.18) & (sat > 0.55) & (val > 0.45)

    r = Image.fromarray((yellow * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
    zero = Image.new("L", (w_px, h_px), 0)
    Image.merge("RGB", (r, zero, zero)).save(OUT, optimize=True)
    print(f"{OUT.relative_to(ROOT)}: body {int(yellow.sum())} texels; stock body rgb",
          np.round(tex[yellow].mean(0), 3).tolist())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
