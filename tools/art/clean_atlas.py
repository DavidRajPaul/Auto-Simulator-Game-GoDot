#!/usr/bin/env python3
"""Clean the cut-outs in the UI atlases (controls_v2, hud_v2, rewards).

The painted art was keyed out of a generated background, which left:
  • fake-transparency checkerboard blocks (≈ 8 px) under tiles, around the mini-map ring and in
    the stunt burst,
  • dark semi-transparent halos and drop-shadow smears around icons,
  • stray specks between cells,
  • dark RGB under transparent pixels, which shows up as a dark rim once the texture is filtered.

Per cell it:
  1. builds the solid mask (alpha ≥ SOLID) and opens it with a disk of radius OPEN_R, which
     erases anything thinner than ~2·OPEN_R px (checker blocks, dashes, smears) but keeps bodies;
  2. keeps opened components bigger than MIN_AREA as seeds, then reconstructs them inside the
     original soft mask (alpha ≥ SOFT), so real thin parts attached to a body (needles, horn
     sound lines, sparkles near the body) come back untouched while detached junk does not;
  3. clears every pixel outside that, feathers the cut edge by 1 px, and bleeds edge colours
     into the transparent area (no dark fringes when mip-mapped / filtered);
  4. keeps a clear margin to the cell border so neighbours never bleed into each other.
Cells listed in KEEP_SPARKLES also keep small bright, saturated islands (stars/sparkles).

Usage:  python3 tools/art/clean_atlas.py            (writes the atlases in place; originals are in git)
        python3 tools/art/clean_atlas.py --preview  (writes before/after sheets to /tmp)
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage.morphology import disk

ROOT = Path(__file__).resolve().parents[2]
SOLID = 150
SOFT = 40
OPEN_R = 4
OUTLINE_W = 6
MIN_AREA = 160
MARGIN = 3

# atlas -> list of (x, y, w, h) cells
def grid(w: int, h: int, cell_w: int, cell_h: int) -> list[tuple[int, int, int, int]]:
    return [(x, y, cell_w, cell_h) for y in range(0, h, cell_h) for x in range(0, w, cell_w)]


ATLASES = {
    "assets/ui/controls_v2.png": grid(1536, 768, 192, 192),
    "assets/ui/rewards.png": grid(1024, 1024, 256, 256),
    # TouchHUD.HUD_REGIONS
    "assets/ui/hud_v2.png": [(0, 0, 512, 512), (512, 0, 384, 384), (896, 0, 512, 512), (1408, 0, 512, 512),
                             (0, 512, 128, 512), (128, 512, 512, 256), (640, 512, 512, 256), (1152, 512, 128, 128),
                             (1280, 512, 128, 128), (1408, 512, 128, 128), (128, 784, 640, 120), (768, 784, 640, 120),
                             (1408, 784, 640, 120)],
}
# Cells whose small bright islands are intentional sparkles (rewards: coin, coin pile, gift, badges).
KEEP_SPARKLES = {"assets/ui/rewards.png": {0, 2, 9, 12, 13, 14, 15}}
# Coloured icons wrapped in a baked dark glow band: peel dark pixels > OUTLINE_W from the colour
# (keeps the black outline). Not the all-dark cells (half / empty star).
PEEL_HALO = {"assets/ui/rewards.png": {0, 1, 2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}}
# Cells redrawn from scratch (baked checkerboard inside the colours): atlas -> {cell: painter}.
# Per-cell opening radius overrides (bigger = removes thicker junk; check thin parts survive).
OPEN_OVERRIDE = {"assets/ui/controls_v2.png": {16: 7, 17: 7, 18: 6, 19: 6, 20: 6, 21: 6}, "assets/ui/hud_v2.png": {8: 7}}
REDRAW = {"assets/ui/hud_v2.png": {3: "burst"}}


def paint_burst(w: int, h: int) -> np.ndarray:
    """Comic stunt burst: 16 tapered rays (yellow → orange) behind a glossy 12-point star."""
    from PIL import ImageDraw, ImageFilter
    import math
    big = 4
    W, H = w * big, h * big
    cx, cy = W / 2, H / 2
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for k in range(16):
        a = k * math.tau / 16 + 0.1
        r0, r1 = W * 0.18, W * (0.47 if k % 2 == 0 else 0.38)
        spread = 0.11
        pts = [(cx + math.cos(a - spread) * r0, cy + math.sin(a - spread) * r0), (cx + math.cos(a) * r1, cy + math.sin(a) * r1),
               (cx + math.cos(a + spread) * r0, cy + math.sin(a + spread) * r0)]
        d.polygon(pts, fill=(255, 140, 20, 255) if k % 2 == 0 else (255, 190, 40, 255), outline=(120, 40, 10, 255), width=big * 3)
    star = []
    for k in range(24):
        a = k * math.tau / 24 - math.pi / 2
        r = W * (0.27 if k % 2 == 0 else 0.17)
        star.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    d.polygon(star, fill=(255, 205, 50, 255), outline=(130, 50, 10, 255), width=big * 4)
    shine = [(x * 0.62 + cx * 0.38 - W * 0.02, y * 0.62 + cy * 0.38 - H * 0.03) for x, y in star]
    d.polygon(shine, fill=(255, 236, 140, 255))
    img = img.filter(ImageFilter.GaussianBlur(big * 0.4)).resize((w, h), Image.LANCZOS)
    return np.array(img)


def clean_cell(rgba: np.ndarray, keep_sparkles: bool, peel: bool = False, open_r: int = OPEN_R) -> np.ndarray:
    a = rgba[..., 3].astype(np.float32)
    solid = a >= SOLID
    opened = ndi.binary_opening(solid, structure=disk(open_r))
    lab, n = ndi.label(opened)
    if n == 0:
        return rgba
    sizes = ndi.sum(opened, lab, range(1, n + 1))
    seeds = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= MIN_AREA])
    soft = a >= SOFT
    # The opened bodies, grown back by 1 px into the soft edge. No full geodesic reconstruction:
    # the checker columns are fused to the bodies and would come straight back.
    keep = ndi.binary_dilation(seeds, iterations=1) & soft
    if peel:
        lum = rgba[..., :3].astype(np.float32).mean(-1)
        rgbf = rgba[..., :3].astype(np.float32)
        colour = keep & ((lum >= 95) | ((rgbf.max(-1) - rgbf.min(-1)) > 95))
        if colour.any():
            dist = ndi.distance_transform_edt(~colour)
            keep &= ~((lum < 95) & (dist > OUTLINE_W))
    if keep_sparkles:
        rgb = rgba[..., :3].astype(np.float32)
        mx, mn = rgb.max(-1), rgb.min(-1)
        bright = (mx > 170) & ((mx - mn) > 50) & solid
        lab2, n2 = ndi.label(bright)
        for i in range(1, n2 + 1):
            comp = lab2 == i
            if 6 <= comp.sum() <= 1500:
                keep |= ndi.binary_dilation(comp, iterations=2) & soft
    # Halo trim: drop the faint dark glow ring that hugs bodies (alpha < 140 and dark).
    lum = rgba[..., :3].astype(np.float32).mean(-1)
    halo = (a < 140) & (lum < 70) & ~ndi.binary_erosion(keep, iterations=2)
    keep &= ~halo
    out = rgba.copy()
    alpha = np.where(keep, a, 0.0)
    # 1 px feather on the cut edge.
    edge = keep & ~ndi.binary_erosion(keep)
    alpha[edge] = np.minimum(alpha[edge], 200)
    h, w = alpha.shape
    alpha[:MARGIN, :] = 0
    alpha[h - MARGIN:, :] = 0
    alpha[:, :MARGIN] = 0
    alpha[:, w - MARGIN:] = 0
    out[..., 3] = alpha.astype(np.uint8)
    # Colour bleed: transparent pixels take the colour of the nearest kept pixel.
    vis = alpha > 0
    if vis.any():
        _, (iy, ix) = ndi.distance_transform_edt(~vis, return_indices=True)
        for c in range(3):
            ch = out[..., c]
            out[..., c] = np.where(vis, ch, ch[iy, ix])
    return out


def run(preview: bool) -> int:
    for rel, cells in ATLASES.items():
        path = ROOT / rel
        img = np.array(Image.open(path).convert("RGBA"))
        before = img.copy()
        sparkle = KEEP_SPARKLES.get(rel, set())
        peel = PEEL_HALO.get(rel, set())
        redraw = REDRAW.get(rel, {})
        for i, (x, y, w, h) in enumerate(cells):
            if redraw.get(i) == "burst":
                img[y:y + h, x:x + w] = paint_burst(w, h)
                continue
            if rel == "assets/ui/hud_v2.png" and i == 8:
                # Rider pin: a checkered "beam" was painted under the pin. Below the head keep only
                # the blue pin body and its navy outline.
                cell = img[y:y + h, x:x + w]
                rows = np.arange(h)[:, None] >= int(h * 0.55)
                rgbi = cell[..., :3].astype(int)
                blueish = rgbi[..., 2] >= rgbi[..., 0] + 10
                cell[..., 3] = np.where(rows & ~blueish, 0, cell[..., 3])
            r = OPEN_OVERRIDE.get(rel, {}).get(i, OPEN_R)
            img[y:y + h, x:x + w] = clean_cell(img[y:y + h, x:x + w], i in sparkle, i in peel, r)
        removed = int(((before[..., 3] > 0) & (img[..., 3] == 0)).sum())
        print(f"{rel}: {len(cells)} cells, {removed} stray / halo pixels removed")
        if preview:
            for tag, arr in (("before", before), ("after", img)):
                im = Image.fromarray(arr)
                bg = Image.new("RGBA", im.size, (255, 0, 255, 255))
                bg.alpha_composite(im)
                bg.convert("RGB").save(f"/tmp/claude-0/clean_{Path(rel).stem}_{tag}.png")
        else:
            Image.fromarray(img).save(path, optimize=True)
    return 0


if __name__ == "__main__":
    sys.exit(run("--preview" in sys.argv))
