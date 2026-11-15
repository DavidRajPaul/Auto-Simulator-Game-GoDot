#!/usr/bin/env python3
"""Sign atlas for the police assistance booths at Chennai junctions (scripts/world/TrafficPolice.gd).

Layout (2048 x 2048, the GDScript reads the same numbers - TrafficPolice.sign_rect):
  * per station i (tools/osm/police_stations.py): column i % 2, row i / 2, each cell 768 x 256:
      top half    = English station strip on purple: "R-1 MAMBALAM" / "POLICE ASSISTANCE BOOTH"
      bottom half = Tamil strip on purple: "R-1 மாம்பலம் காவல் சேவை மையம்"
  * shared, column at x 1536: header strip (512 x 128) "GREATER CHENNAI CITY POLICE" on red,
    and the red panel (512 x 256) with a round badge and "சென்னை மாநகர காவல்".
Red-over-purple is the livery of Greater Chennai Police booths (owner's reference photos). The
badge is a plain ring with a star, not the police seal. Text: Rubik Bold (Latin), Baloo Thambi 2
Bold (Tamil, shaped with Raqm).

    python3 tools/art/make_police_signs.py   # then godot --headless --import
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "osm"))
from police_stations import STATIONS  # noqa: E402

OUT = ROOT / "assets" / "textures" / "police_signs.png"
RED = (214, 28, 34)
PURPLE = (52, 31, 110)
WHITE = (250, 250, 248)
GOLD = (245, 196, 40)
CELL_W, CELL_H = 768, 256


def font(path: str, size: int, weight: int):
    f = ImageFont.truetype(str(ROOT / path), size, layout_engine=ImageFont.Layout.RAQM)
    f.set_variation_by_axes([weight])
    return f


def latin(size: int):
    return font("assets/fonts/ui/Rubik.ttf", size, 700)


def tamil(size: int):
    return font("assets/fonts/baloo_thambi_2/BalooThambi2-Variable.ttf", size, 700)


def fit(draw: ImageDraw.ImageDraw, text: str, make, size: int, max_w: int):
    while size > 10:
        f = make(size)
        if draw.textlength(text, font=f) <= max_w:
            return f
        size -= 2
    return make(size)


def centred(draw, box, text, make, size, colour):
    x0, y0, x1, y1 = box
    f = fit(draw, text, make, size, x1 - x0 - 24)
    l, t, r, b = draw.textbbox((0, 0), text, font=f)
    draw.text(((x0 + x1 - (r - l)) / 2 - l, (y0 + y1 - (b - t)) / 2 - t), text, font=f, fill=colour)


def badge(draw, cx, cy, r):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD, outline=PURPLE, width=6)
    draw.ellipse([cx - r * 0.72, cy - r * 0.72, cx + r * 0.72, cy + r * 0.72], fill=RED)
    import math
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r * (0.55 if k % 2 == 0 else 0.23)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    draw.polygon(pts, fill=WHITE)


def main() -> int:
    img = Image.new("RGB", (2048, 2048), PURPLE)
    d = ImageDraw.Draw(img)
    for i, (code, en, ta, _la, _lo) in enumerate(STATIONS):
        x0, y0 = (i % 2) * CELL_W, (i // 2) * CELL_H
        # English strip: two lines on purple with a thin white rule.
        d.rectangle([x0, y0, x0 + CELL_W - 1, y0 + 127], fill=PURPLE)
        centred(d, (x0, y0 + 6, x0 + CELL_W, y0 + 66), f"{code} {en}", latin, 52, WHITE)
        centred(d, (x0, y0 + 66, x0 + CELL_W, y0 + 124), "POLICE ASSISTANCE BOOTH", latin, 46, WHITE)
        d.rectangle([x0 + 8, y0 + 2, x0 + CELL_W - 9, y0 + 125], outline=WHITE, width=3)
        # Tamil strip.
        d.rectangle([x0, y0 + 128, x0 + CELL_W - 1, y0 + 255], fill=PURPLE)
        centred(d, (x0, y0 + 136, x0 + CELL_W, y0 + 250), f"{code} {ta} காவல் சேவை மையம்", tamil, 58, WHITE)
        d.rectangle([x0 + 8, y0 + 130, x0 + CELL_W - 9, y0 + 253], outline=WHITE, width=3)
    # Shared header: red, white bold capitals.
    hx = 1536
    d.rectangle([hx, 0, 2047, 127], fill=RED)
    centred(d, (hx, 4, 2048, 64), "GREATER CHENNAI", latin, 54, WHITE)
    centred(d, (hx, 64, 2048, 124), "CITY POLICE", latin, 54, WHITE)
    # Shared red panel with the badge over "சென்னை மாநகர காவல்".
    d.rectangle([hx, 128, 2047, 383], fill=RED)
    badge(d, hx + 256, 128 + 82, 70)
    centred(d, (hx, 128 + 160, 2048, 128 + 250), "சென்னை மாநகர காவல்", tamil, 64, WHITE)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(STATIONS)} stations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
