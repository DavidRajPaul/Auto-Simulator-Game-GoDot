#!/usr/bin/env python3
"""Generate the Chennai facade texture atlas used by every building (pure Pillow + raqm for Tamil).

Output (committed, deterministic):
  assets/textures/facade_atlas.png   1024×512, 8×4 cells of 128 px. RGB = colour, A = tint mask
                                     (255 = plaster, multiplied by the building's vertex colour;
                                     0 = keeps its own colour: glass, frames, signboards, shutters)
  assets/textures/facade_glow.png    512×256, same layout: what lights up at night

One cell = one window bay (~3.4 m) × one floor (3.2 m). Cell map (row, col):
  0: upper floors  0 grilled window + sunshade · 1 balcony · 2 twin windows · 3 ventilators + pipe
                   4 sliding window + AC unit · 5 office glass · 6 office strip window · 7 blank wall
  1: ground floor  0 house door + window · 1 compound wall + gate · 2 shutter (closed)
                   3–7 open shops with Tamil boards
  2: ground floor  0–7 open shops with English boards
  3: special       0 temple wall (kaavi stripes) · 1 temple ground + door · 2–3 roof terraces
                   4 heritage window (red oxide shutters) · 5 heritage veranda (thinnai) · 6–7 civic arches
Shop names are generic trades, never real brands.

Usage: python3 tools/art/make_facade_atlas.py
"""
from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "textures"
TAMIL_FONT = ROOT / "assets" / "fonts" / "baloo_thambi_2" / "BalooThambi2-Variable.ttf"
C = 128  # cell size px
COLS, ROWS = 8, 4

TAMIL_SHOPS = ["டீ கடை", "மளிகை", "ஜவுளி", "மருந்தகம்", "உணவகம்"]
ENGLISH_SHOPS = [("MEDICALS", "மருந்து"), ("MOBILES", "செல்போன்"), ("TEA STALL", "டீ"), ("TEXTILES", "ஜவுளி"),
                 ("HOTEL", "உணவகம்"), ("BAKERY", "பேக்கரி"), ("STORES", "ஸ்டோர்ஸ்"), ("TAILORS", "தையல்")]
BOARD_COLOURS = [(200, 30, 30), (20, 80, 170), (240, 190, 20), (30, 130, 60), (120, 20, 110), (230, 110, 20),
                 (15, 15, 15), (0, 140, 150)]

rng = random.Random(600004)
atlas = Image.new("RGBA", (C * COLS, C * ROWS), (0, 0, 0, 0))
glow = Image.new("RGB", (C * COLS, C * ROWS), (0, 0, 0))
d = ImageDraw.Draw(atlas)
g = ImageDraw.Draw(glow)


def font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(TAMIL_FONT), size, layout_engine=ImageFont.Layout.RAQM)
    f.set_variation_by_name(weight)
    return f


def cell(col: int, row: int) -> tuple[int, int]:
    return col * C, row * C


def rect(x0: int, y0: int, x1: int, y1: int, rgb: tuple, tint: bool = False, glow_rgb: tuple | None = None) -> None:
    d.rectangle([x0, y0, x1, y1], fill=(*rgb, 255 if tint else 0))
    if glow_rgb is not None:
        g.rectangle([x0, y0, x1, y1], fill=glow_rgb)


def plaster(col: int, row: int, base: int = 236, stains: bool = True) -> None:
    """Tintable plaster with monsoon streaks and a floor-slab band at the bottom."""
    x, y = cell(col, row)
    for yy in range(C):
        for xx in range(0, C, 2):
            n = base - rng.randint(0, 10)
            if stains:
                n -= int(14 * max(0.0, (yy - C * 0.55) / (C * 0.45)) * (0.6 + 0.4 * ((xx * 7 + yy) % 13) / 13))
            d.rectangle([x + xx, y + yy, x + xx + 1, y + yy], fill=(n, n, n - 3, 255))
    if stains:
        for _ in range(3):  # rain streaks below sills
            sx = x + rng.randint(8, C - 8)
            d.line([sx, y + rng.randint(60, 80), sx + rng.randint(-2, 2), y + C - 8], fill=(205, 205, 200, 255), width=2)
    rect(x, y + C - 7, x + C - 1, y + C - 1, (214, 212, 206), tint=True)  # slab band


def window(x: int, y: int, w: int, h: int, lit: bool, grill: bool = True, frame: tuple = (105, 70, 40)) -> None:
    rect(x - 3, y - 3, x + w + 3, y + h + 3, frame)
    glass = (38, 48, 58) if not lit else (60, 58, 50)
    rect(x, y, x + w, y + h, glass, glow_rgb=(255, 196, 120) if lit else (0, 0, 0))
    d.line([x + w // 2, y, x + w // 2, y + h], fill=(*frame, 0), width=2)  # mullion
    if grill:
        for gx in range(x + 5, x + w, 7):
            d.line([gx, y, gx, y + h], fill=(25, 25, 25, 0), width=1)
    # sunshade (chajja) with its shadow
    rect(x - 10, y - 12, x + w + 10, y - 6, (226, 224, 218), tint=True)
    d.rectangle([x - 8, y - 5, x + w + 8, y - 3], fill=(150, 150, 146, 255))


def board(x: int, y: int, w: int, h: int, colour: tuple, text: str, sub: str = "", size: int = 22) -> None:
    rect(x, y, x + w, y + h, colour, glow_rgb=tuple(min(255, int(c * 0.9) + 40) for c in colour))
    light = sum(colour) > 420
    ink = (20, 20, 20) if light else (255, 248, 230)
    f = font(size)
    tw = d.textlength(text, font=f)
    while tw > w - 6 and size > 10:
        size -= 1
        f = font(size)
        tw = d.textlength(text, font=f)
    ty = y + (h - size) // 2 - (5 if sub else 3)
    d.text((x + (w - tw) / 2, ty), text, font=f, fill=(*ink, 0))
    if sub:
        fs = font(11, "SemiBold")
        sw = d.textlength(sub, font=fs)
        d.text((x + (w - sw) / 2, y + h - 15), sub, font=fs, fill=(*ink, 0))


def shop(col: int, row: int, colour: tuple, text: str, sub: str = "") -> None:
    x, y = cell(col, row)
    plaster(col, row, stains=False)
    board(x + 2, y + 6, C - 5, 34, colour, text, sub, size=24 if not sub else 19)
    # rolled-up shutter box, dark lit interior with shelves of goods
    rect(x + 6, y + 42, x + C - 7, y + 48, (120, 120, 118))
    rect(x + 8, y + 48, x + C - 9, y + C - 9, (40, 34, 30), glow_rgb=(170, 140, 90))
    for sy in range(y + 58, y + C - 14, 14):
        rect(x + 12, sy, x + C - 13, sy + 2, (90, 70, 50))
        for sx in range(x + 14, x + C - 16, 9):
            c = BOARD_COLOURS[rng.randrange(len(BOARD_COLOURS))]
            rect(sx, sy - 8, sx + 6, sy - 1, tuple(int(v * 0.75) for v in c), glow_rgb=tuple(int(v * 0.6) for v in c))
    rect(x + 6, y + C - 9, x + C - 7, y + C - 1, (170, 165, 155))  # step


def kaavi(col: int, row: int) -> None:
    """Temple compound wall: vertical red-ochre and white stripes."""
    x, y = cell(col, row)
    for i in range(8):
        rect(x + i * 16, y, x + i * 16 + 15, y + C - 1, (178, 46, 30) if i % 2 == 0 else (245, 240, 228))


# --- Row 0: upper floors ------------------------------------------------------------------------
plaster(0, 0)
x, y = cell(0, 0)
window(x + 36, y + 30, 56, 56, lit=True)

plaster(1, 0)
x, y = cell(1, 0)
rect(x + 40, y + 22, x + 88, y + 108, (95, 60, 35))
rect(x + 44, y + 26, x + 84, y + 104, (45, 52, 60), glow_rgb=(240, 180, 110))
rect(x + 4, y + 78, x + C - 5, y + 82, (60, 60, 62))   # balcony rail
for bx in range(x + 8, x + C - 6, 8):
    d.line([bx, y + 82, bx, y + 112], fill=(60, 60, 62, 0), width=2)
rect(x + 2, y + 112, x + C - 3, y + 118, (210, 208, 202), tint=True)
d.ellipse([x + 12, y + 60, x + 30, y + 78], fill=(40, 120, 50, 0))  # potted plant

plaster(2, 0)
x, y = cell(2, 0)
window(x + 16, y + 36, 38, 46, lit=False)
window(x + 74, y + 36, 38, 46, lit=True)

plaster(3, 0)
x, y = cell(3, 0)
for i in range(3):
    rect(x + 48, y + 34 + i * 12, x + 80, y + 40 + i * 12, (70, 70, 72))
rect(x + 108, y, x + 113, y + C - 1, (120, 115, 105))  # drain pipe
window(x + 50, y + 80, 28, 24, lit=False, grill=False)

plaster(4, 0)
x, y = cell(4, 0)
rect(x + 26, y + 26, x + 102, y + 76, (150, 155, 160))
rect(x + 30, y + 30, x + 64, y + 72, (60, 85, 110), glow_rgb=(255, 210, 150))
rect(x + 66, y + 30, x + 98, y + 72, (55, 80, 104))
rect(x + 40, y + 84, x + 88, y + 106, (236, 236, 232))  # AC outdoor unit
d.ellipse([x + 46, y + 86, x + 64, y + 104], fill=(120, 120, 120, 0))

x, y = cell(5, 0)
rect(x, y, x + C - 1, y + C - 1, (60, 98, 118))
for gx in range(0, C, 32):
    rect(x + gx, y, x + gx + 2, y + C - 1, (180, 190, 195))
rect(x, y + C - 16, x + C - 1, y + C - 1, (175, 180, 182))  # spandrel
for gx in range(0, C, 32):
    if rng.random() < 0.55:
        g.rectangle([x + gx + 3, y + 2, x + gx + 30, y + C - 18], fill=(235, 235, 220))
for yy in range(y, y + C - 16, 4):
    d.line([x, yy, x + C - 1, yy], fill=(70, 108, 128, 0))

plaster(6, 0, stains=False)
x, y = cell(6, 0)
rect(x, y + 40, x + C - 1, y + 84, (70, 90, 105), glow_rgb=(230, 225, 205))
for gx in range(0, C, 21):
    rect(x + gx, y + 40, x + gx + 2, y + 84, (190, 195, 198))

plaster(7, 0)
x, y = cell(7, 0)
rect(x + 18, y, x + 23, y + C - 1, (125, 120, 110))
d.line([x + 70, y + 30, x + 84, y + 55, x + 78, y + 80], fill=(185, 185, 180, 255), width=1)  # crack

# --- Row 1: ground floors -----------------------------------------------------------------------
plaster(0, 1)
x, y = cell(0, 1)
rect(x + 14, y + 30, x + 54, y + C - 8, (110, 60, 30))     # wooden door
rect(x + 18, y + 34, x + 50, y + 70, (130, 75, 40))
d.ellipse([x + 44, y + 80, x + 48, y + 84], fill=(220, 190, 80, 0))
window(x + 72, y + 40, 40, 44, lit=True)
for kx in range(x + 16, x + 54, 6):  # kolam at the doorstep
    d.point([kx, y + C - 4], fill=(250, 250, 250, 0))

plaster(1, 1)
x, y = cell(1, 1)
rect(x, y + 64, x + C - 1, y + C - 1, (228, 226, 220), tint=True)  # compound wall
rect(x, y + 60, x + C - 1, y + 66, (200, 198, 190), tint=True)
rect(x + 40, y + 52, x + 88, y + C - 1, (40, 40, 42))             # iron gate
for gx in range(x + 44, x + 88, 6):
    d.line([gx, y + 56, gx, y + C - 2], fill=(90, 90, 92, 0), width=2)

plaster(2, 1, stains=False)
x, y = cell(2, 1)
board(x + 2, y + 6, C - 5, 34, BOARD_COLOURS[2], "கடை")
rect(x + 6, y + 42, x + C - 7, y + C - 2, (150, 150, 148))       # closed rolling shutter
for sy in range(y + 44, y + C - 2, 5):
    d.line([x + 6, sy, x + C - 7, sy], fill=(110, 110, 108, 0))
d.rectangle([x + 58, y + C - 14, x + 70, y + C - 8], fill=(60, 60, 60, 0))  # padlock

for i, name in enumerate(TAMIL_SHOPS):
    shop(3 + i, 1, BOARD_COLOURS[i], name)

# --- Row 2: shops with English + Tamil boards ---------------------------------------------------
for i, (en, _ta) in enumerate(ENGLISH_SHOPS):
    # Tamil sub-lines are illegible at 128 px per bay; the Tamil-only boards are in row 1.
    shop(i, 2, BOARD_COLOURS[(i + 3) % len(BOARD_COLOURS)], en)

# --- Row 3: temples, roofs, heritage, civic -----------------------------------------------------
kaavi(0, 3)
kaavi(1, 3)
x, y = cell(1, 3)
rect(x + 44, y + 40, x + 84, y + C - 1, (90, 50, 25))
d.pieslice([x + 44, y + 22, x + 84, y + 60], 180, 360, fill=(90, 50, 25, 0))
for c_, row_ in ((2, 3), (3, 3)):
    plaster(c_, row_, base=200)
    x, y = cell(c_, row_)
    for _ in range(6):  # tar patches and moss on the terrace
        px, py = x + rng.randint(5, C - 30), y + rng.randint(5, C - 30)
        d.ellipse([px, py, px + rng.randint(12, 30), py + rng.randint(8, 22)], fill=(170, 168, 160, 255))
x, y = cell(3, 3)
d.ellipse([x + 70, y + 20, x + 112, y + 62], fill=(30, 30, 32, 0))  # black Sintex water tank
d.ellipse([x + 80, y + 30, x + 102, y + 52], fill=(55, 55, 58, 0))

plaster(4, 3)
x, y = cell(4, 3)
rect(x + 34, y + 24, x + 94, y + 100, (150, 60, 40))  # red-oxide wooden shutters
d.pieslice([x + 34, y + 4, x + 94, y + 46], 180, 360, fill=(150, 60, 40, 0))
for lx in range(x + 38, x + 92, 5):
    d.line([lx, y + 30, lx, y + 96], fill=(120, 45, 30, 0))
rect(x + 62, y + 24, x + 65, y + 100, (90, 35, 20))
g.rectangle([x + 40, y + 30, x + 60, y + 96], fill=(220, 160, 90))

plaster(5, 3)
x, y = cell(5, 3)
rect(x, y + C - 30, x + C - 1, y + C - 1, (160, 80, 55))  # thinnai (raised veranda seat)
for px in (x + 10, x + 110):
    rect(px, y + 10, px + 10, y + C - 30, (235, 232, 224), tint=True)
rect(x + 44, y + 30, x + 84, y + C - 30, (100, 55, 28))

for c_ in (6, 7):
    plaster(c_, 3, base=226)
    x, y = cell(c_, 3)
    top = y + 20 if c_ == 6 else y + 14
    bottom = y + 96 if c_ == 6 else y + C - 1
    rect(x + 32, top + 24, x + 96, bottom, (60, 60, 64) if c_ == 6 else (70, 45, 30), glow_rgb=(240, 190, 120))
    d.pieslice([x + 32, top, x + 96, top + 50], 180, 360, fill=(60, 60, 64, 0) if c_ == 6 else (70, 45, 30, 0))
    d.arc([x + 28, top - 4, x + 100, top + 54], 180, 360, fill=(200, 120, 90, 0), width=5)  # sandstone arch

OUT.mkdir(parents=True, exist_ok=True)
atlas.filter(ImageFilter.SMOOTH)
atlas.save(OUT / "facade_atlas.png", optimize=True)
glow.resize((glow.width // 2, glow.height // 2), Image.LANCZOS).save(OUT / "facade_glow.png", optimize=True)
print("wrote", OUT / "facade_atlas.png", atlas.size, "and facade_glow.png")
