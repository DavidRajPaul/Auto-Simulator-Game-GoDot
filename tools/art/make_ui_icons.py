#!/usr/bin/env python3
"""Draw the driving-control icon atlas (white glyphs, tinted in-game) with Pillow.

Output: assets/ui/controls_atlas.png — 8×2 cells of 128 px (drawn at 4× and downsampled).
Cell order (index = row * 8 + col), mirrored in TouchHUD.ICONS:
  0 accelerator pedal   1 brake pedal      2 handbrake lever   3 bulb horn
  4 indicator left      5 indicator right  6 gear D            7 gear R
  8 kick-start          9 camera           10 wiper            11 handlebar
  12 pause              13 fuel pump       14 headlight        15 reset (circular arrow)
Usage: python3 tools/art/make_ui_icons.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "ui" / "controls_atlas.png"
FONT = ROOT / "assets" / "fonts" / "baloo_thambi_2" / "BalooThambi2-Variable.ttf"
S = 4            # supersampling
C = 128 * S      # cell size at drawing scale
W = (255, 255, 255, 255)
HALF = (255, 255, 255, 140)

img = Image.new("RGBA", (C * 8, C * 2), (0, 0, 0, 0))
d = ImageDraw.Draw(img)


def origin(i: int) -> tuple[int, int]:
    return (i % 8) * C, (i // 8) * C


def P(i: int, x: float, y: float) -> tuple[float, float]:
    ox, oy = origin(i)
    return ox + x * C, oy + y * C


def poly(i: int, pts: list[tuple[float, float]], fill=W) -> None:
    d.polygon([P(i, x, y) for x, y in pts], fill=fill)


def rrect(i: int, x0: float, y0: float, x1: float, y1: float, r: float, fill=W, outline=None, width: float = 0) -> None:
    d.rounded_rectangle([P(i, x0, y0), P(i, x1, y1)], radius=r * C, fill=fill,
                        outline=outline, width=int(width * C) if width else 0)


def line(i: int, pts: list[tuple[float, float]], width: float, fill=W) -> None:
    d.line([P(i, x, y) for x, y in pts], fill=fill, width=int(width * C), joint="curve")


def ellipse(i: int, x0: float, y0: float, x1: float, y1: float, fill=W, outline=None, width: float = 0) -> None:
    d.ellipse([P(i, x0, y0), P(i, x1, y1)], fill=fill, outline=outline, width=int(width * C) if width else 0)


def text(i: int, s: str, size: float, cx: float = 0.5, cy: float = 0.5) -> None:
    f = ImageFont.truetype(str(FONT), int(size * C))
    f.set_variation_by_name("ExtraBold")
    x, y = P(i, cx, cy)
    d.text((x, y), s, font=f, fill=W, anchor="mm")


# 0 accelerator: tall pedal with grip ridges
rrect(0, 0.3, 0.1, 0.7, 0.9, 0.08)
for k in range(6):
    y = 0.2 + k * 0.11
    rrect(0, 0.36, y, 0.64, y + 0.04, 0.02, fill=(0, 0, 0, 0))
# 1 brake: wide pedal
rrect(1, 0.14, 0.3, 0.86, 0.72, 0.1)
for k in range(5):
    x = 0.24 + k * 0.12
    rrect(1, x, 0.38, x + 0.05, 0.64, 0.02, fill=(0, 0, 0, 0))
# 2 handbrake lever with "P"
line(2, [(0.25, 0.8), (0.72, 0.3)], 0.12)
ellipse(2, 0.62, 0.18, 0.84, 0.4)
ellipse(2, 0.17, 0.72, 0.33, 0.88)
# 3 bulb horn: rubber bulb + trumpet bell
ellipse(3, 0.06, 0.34, 0.38, 0.66)
poly(3, [(0.34, 0.45), (0.62, 0.45), (0.92, 0.22), (0.92, 0.78), (0.62, 0.55), (0.34, 0.55)])
# 4 / 5 indicator arrows
poly(4, [(0.12, 0.5), (0.46, 0.18), (0.46, 0.36), (0.86, 0.36), (0.86, 0.64), (0.46, 0.64), (0.46, 0.82)])
poly(5, [(0.88, 0.5), (0.54, 0.18), (0.54, 0.36), (0.14, 0.36), (0.14, 0.64), (0.54, 0.64), (0.54, 0.82)])
# 6 / 7 gear letters in a lever knob ring
for i, ch in ((6, "D"), (7, "R")):
    ellipse(i, 0.12, 0.12, 0.88, 0.88, fill=None, outline=W, width=0.07)
    text(i, ch, 0.52, 0.5, 0.53)
# 8 kick-start: lever + boot
line(8, [(0.2, 0.25), (0.55, 0.55), (0.82, 0.55)], 0.1)
poly(8, [(0.5, 0.62), (0.86, 0.62), (0.9, 0.8), (0.4, 0.8)])
# 9 camera
rrect(9, 0.12, 0.3, 0.88, 0.78, 0.08)
poly(9, [(0.34, 0.3), (0.42, 0.18), (0.6, 0.18), (0.68, 0.3)])
ellipse(9, 0.36, 0.38, 0.64, 0.7, fill=(0, 0, 0, 0))
ellipse(9, 0.43, 0.45, 0.57, 0.62)
# 10 wiper: arc + blade
d.arc([P(10, 0.1, 0.3), P(10, 0.9, 1.1)], 200, 340, fill=W, width=int(0.06 * C))
line(10, [(0.5, 0.82), (0.24, 0.32)], 0.08)
ellipse(10, 0.44, 0.76, 0.56, 0.88)
# 11 handlebar (Bajaj RE, top view)
line(11, [(0.08, 0.6), (0.25, 0.45), (0.75, 0.45), (0.92, 0.6)], 0.09)
rrect(11, 0.04, 0.52, 0.2, 0.7, 0.05)
rrect(11, 0.8, 0.52, 0.96, 0.7, 0.05)
ellipse(11, 0.42, 0.36, 0.58, 0.54)
# 12 pause
rrect(12, 0.28, 0.2, 0.42, 0.8, 0.03)
rrect(12, 0.58, 0.2, 0.72, 0.8, 0.03)
# 13 fuel pump
rrect(13, 0.18, 0.16, 0.6, 0.86, 0.06)
rrect(13, 0.25, 0.24, 0.53, 0.44, 0.03, fill=(0, 0, 0, 0))
line(13, [(0.6, 0.36), (0.78, 0.36), (0.78, 0.72), (0.86, 0.72)], 0.06)
# 14 headlight with beams
d.pieslice([P(14, 0.08, 0.22), P(14, 0.6, 0.78)], 90, 270, fill=W)
for k in range(3):
    y = 0.32 + k * 0.18
    line(14, [(0.44, y), (0.9, y - 0.06)], 0.06)
# 15 reset: circular arrow
d.arc([P(15, 0.16, 0.16), P(15, 0.84, 0.84)], 40, 330, fill=W, width=int(0.1 * C))
a = math.radians(40)
cx, cy, r = 0.5, 0.5, 0.34
tip = (cx + r * math.cos(a), cy + r * math.sin(a))
poly(15, [(tip[0] + 0.12, tip[1] - 0.02), (tip[0] - 0.06, tip[1] - 0.1), (tip[0] - 0.02, tip[1] + 0.12)])

OUT.parent.mkdir(parents=True, exist_ok=True)
img.resize((img.width // S, img.height // S), Image.LANCZOS).save(OUT, optimize=True)
print("wrote", OUT)
