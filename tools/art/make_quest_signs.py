#!/usr/bin/env python3
"""Paints the name boards of named quest shops into one atlas: assets/textures/quest_signs.png.

Chennai shop boards are painted (or printed flex) panels: the name big in Tamil, the English name
under it, a trade picture on the left, a little line of what they sell, a border and the grime of a
few monsoons. Each board is one 1920 x 256 row (the 6.9 x 0.92 m board of QuestPlaceKit, 7.5 : 1);
QuestPlaces.SIGN_ROWS says which row a place uses. The names belong to the quest's own fictional
characters (never a real business). Tamil is shaped with Raqm (Baloo Thambi 2).

Run from the repo root: python3 tools/art/make_quest_signs.py, then
godot --headless --path . --import (Godot does not re-import a changed PNG when a scene runs).
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "textures" / "quest_signs.png"
TAMIL = ROOT / "assets" / "fonts" / "baloo_thambi_2" / "BalooThambi2-Variable.ttf"
LATIN = ROOT / "assets" / "fonts" / "ui" / "BricolageGrotesque.ttf"
W, H = 1920, 256
ATLAS = (2048, 1024)

# Row order = QuestPlaces.SIGN_ROWS. (tamil, english, tagline, board top, board bottom, ink, accent, icon)
SIGNS = [
    ("கண்ணன் டிகிரி காபி", "KANNAN DEGREE COFFEE", "Filter Coffee  •  Since 1985",
     "5a2a12", "3a1808", "ffe9b0", "e0a030", "coffee"),
    ("செல்வம் டெய்லர்ஸ்", "SELVAM TAILORS", "Gents & Ladies  •  Wedding Orders Taken",
     "1d3f8a", "122a60", "ffffff", "f2c94c", "tailor"),
    ("மோகனா புக் ஹவுஸ்", "MOHANA BOOK HOUSE", "Tamil & English  •  Old & New Books",
     "1e5b36", "113a22", "fff6d8", "e8c15a", "books"),
    ("முருகன் டீ ஸ்டால்", "MURUGAN TEA STALL", "Tea  •  Biscuits  •  Newspaper   NO COFFEE!",
     "b8321c", "7c1d0e", "fff3c4", "ffd23f", "tea"),
]


def rgb(h: str) -> tuple[int, int, int]:
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def font(path: Path, size: int, weight: int | None = None) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(path), size, layout_engine=ImageFont.Layout.RAQM)
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    return f


def fit(d: ImageDraw.ImageDraw, text: str, path: Path, max_w: float, max_h: float, weight: int | None) -> ImageFont.FreeTypeFont:
    size = int(max_h * 1.4)
    while size > 10:
        f = font(path, size, weight)
        l, t, r, b = d.textbbox((0, 0), text, font=f)
        if r - l <= max_w and b - t <= max_h:
            return f
        size -= 2
    return font(path, 10, weight)


def shadowed(img: Image.Image, xy: tuple[float, float], text: str, f: ImageFont.FreeTypeFont, ink: tuple, dark: tuple) -> None:
    """Sign-painter lettering: a hard drop shadow and a thin dark outline under the ink."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((xy[0] + 5, xy[1] + 5), text, font=f, fill=dark + (200,))
    d.text(xy, text, font=f, fill=ink + (255,), stroke_width=3, stroke_fill=dark + (255,))
    img.alpha_composite(layer)


# --- trade pictures (drawn in a 200 px box) --------------------------------------------------------

def icon_coffee(d: ImageDraw.ImageDraw, cx: int, cy: int, ink: tuple, accent: tuple) -> None:
    d.ellipse([cx - 70, cy + 34, cx + 70, cy + 62], fill=accent, outline=ink, width=4)       # davara rim
    d.polygon([(cx - 62, cy + 46), (cx + 62, cy + 46), (cx + 46, cy + 76), (cx - 46, cy + 76)], fill=accent, outline=ink)
    d.polygon([(cx - 34, cy - 40), (cx + 34, cy - 40), (cx + 26, cy + 50), (cx - 26, cy + 50)], fill=accent, outline=ink)
    d.ellipse([cx - 34, cy - 50, cx + 34, cy - 30], fill=(214, 170, 110), outline=ink, width=4)  # froth
    for k in (-18, 0, 18):                                                                     # steam
        pts = [(cx + k + 8 * math.sin(t / 6.0), cy - 56 - t) for t in range(0, 46, 3)]
        d.line(pts, fill=ink, width=5)


def icon_tailor(d: ImageDraw.ImageDraw, cx: int, cy: int, ink: tuple, accent: tuple) -> None:
    for s in (-1, 1):  # scissors: two blades crossing, two rings
        d.line([(cx - 60 * s, cy - 60), (cx + 40 * s, cy + 36)], fill=ink, width=12)
        d.ellipse([cx + 40 * s - 22, cy + 36 - 4, cx + 40 * s + 22, cy + 36 + 40], outline=accent, width=10)
    d.ellipse([cx - 7, cy - 18, cx + 7, cy - 4], fill=accent)
    d.arc([cx - 90, cy - 80, cx + 90, cy + 90], 200, 330, fill=accent, width=6)  # thread


def icon_books(d: ImageDraw.ImageDraw, cx: int, cy: int, ink: tuple, accent: tuple) -> None:
    for s in (-1, 1):  # open book
        d.polygon([(cx, cy - 34), (cx + 78 * s, cy - 54), (cx + 78 * s, cy + 46), (cx, cy + 62)], fill=ink, outline=accent)
        for k in range(4):
            y = cy - 30 + k * 18
            d.line([(cx + 12 * s, y), (cx + 64 * s, y - 14)], fill=accent, width=4)
    d.line([(cx, cy - 34), (cx, cy + 62)], fill=accent, width=5)


def icon_tea(d: ImageDraw.ImageDraw, cx: int, cy: int, ink: tuple, accent: tuple) -> None:
    d.polygon([(cx - 36, cy - 34), (cx + 36, cy - 34), (cx + 28, cy + 62), (cx - 28, cy + 62)], fill=(236, 236, 230), outline=ink)
    d.polygon([(cx - 33, cy - 12), (cx + 33, cy - 12), (cx + 28, cy + 58), (cx - 28, cy + 58)], fill=(196, 128, 64))
    for k in (-14, 6, 24):
        pts = [(cx + k + 8 * math.sin(t / 6.0), cy - 42 - t) for t in range(0, 40, 3)]
        d.line(pts, fill=ink, width=5)


ICONS = {"coffee": icon_coffee, "tailor": icon_tailor, "books": icon_books, "tea": icon_tea}


def board(tamil: str, english: str, tagline: str, top: str, bottom: str, ink_hex: str, accent_hex: str, icon: str, seed: int) -> Image.Image:
    rnd = random.Random(seed)
    ink, accent = rgb(ink_hex), rgb(accent_hex)
    a, b = rgb(top), rgb(bottom)
    img = Image.new("RGBA", (W, H))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        row = tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))
        for x in range(W):
            px[x, y] = row + (255,)
    d = ImageDraw.Draw(img)
    dark = tuple(max(0, int(c * 0.35)) for c in b)
    # Border: accent line inside a dark frame, round bolts in the corners.
    d.rectangle([0, 0, W - 1, H - 1], outline=dark, width=10)
    d.rectangle([16, 16, W - 17, H - 17], outline=accent, width=5)
    for x, y in ((30, 30), (W - 31, 30), (30, H - 31), (W - 31, H - 31)):
        d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=(150, 150, 150), outline=dark)
    # Trade picture in a disc on the left.
    d.ellipse([46, 28, 246, 228], fill=dark, outline=accent, width=6)
    ICONS[icon](d, 146, 128, ink, accent)
    if icon == "tea":  # A tea man's opinion of coffee: a small crossed-out cup on the right.
        cx, cy = W - 140, 128
        d.ellipse([cx - 82, cy - 82, cx + 82, cy + 82], fill=(255, 255, 255), outline=(200, 20, 20), width=10)
        d.polygon([(cx - 26, cy - 30), (cx + 26, cy - 30), (cx + 20, cy + 40), (cx - 20, cy + 40)], fill=(120, 72, 40))
        d.ellipse([cx - 48, cy + 26, cx + 48, cy + 50], fill=(190, 150, 70))
        d.line([(cx - 58, cy - 58), (cx + 58, cy + 58)], fill=(200, 20, 20), width=14)
    text_l, text_r = 280, W - (290 if icon == "tea" else 60)
    span = text_r - text_l
    big = fit(d, tamil, TAMIL, span, 104, 800)
    l, t, r, bb = d.textbbox((0, 0), tamil, font=big)
    shadowed(img, (text_l + (span - (r - l)) / 2 - l, 26 - t + (104 - (bb - t)) / 2), tamil, big, ink, dark)
    eng = fit(d, english, LATIN, span * 0.92, 50, 800)
    l, t, r, bb = d.textbbox((0, 0), english, font=eng)
    shadowed(img, (text_l + (span - (r - l)) / 2 - l, 142 - t), english, eng, accent, dark)
    small = fit(d, tagline, LATIN, span * 0.8, 26, 600)
    l, t, r, bb = d.textbbox((0, 0), tagline, font=small)
    d.text((text_l + (span - (r - l)) / 2 - l, 206 - t), tagline, font=small, fill=ink)
    # Weather: a faint grain, rust streaks under the bolts, a sun-faded top edge.
    grime = Image.new("L", (W, H), 0)
    g = ImageDraw.Draw(grime)
    for _ in range(1400):
        x, y = rnd.randrange(W), rnd.randrange(H)
        g.point((x, y), fill=rnd.randrange(20, 70))
    for x in (30, W - 31):
        g.line([(x, 38), (x + rnd.randrange(-3, 4), 38 + rnd.randrange(30, 70))], fill=60, width=4)
    grime = grime.filter(ImageFilter.GaussianBlur(1.2))
    shade = Image.new("RGBA", (W, H), (40, 28, 18, 0))
    shade.putalpha(grime)
    img.alpha_composite(shade)
    fade = Image.new("RGBA", (W, H), (255, 255, 255, 0))
    fd = ImageDraw.Draw(fade)
    for y in range(40):
        fd.line([(0, y), (W, y)], fill=(255, 255, 255, int(22 * (1 - y / 40))))
    img.alpha_composite(fade)
    return img


def main() -> None:
    atlas = Image.new("RGB", ATLAS, (40, 40, 40))
    for i, spec in enumerate(SIGNS):
        atlas.paste(board(*spec, seed=17 + i).convert("RGB"), (0, i * H))
        # Bleed the last column into the unused strip so mips never pull in grey.
        edge = atlas.crop((W - 1, i * H, W, (i + 1) * H)).resize((ATLAS[0] - W, H))
        atlas.paste(edge, (W, i * H))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT)
    print("wrote", OUT.relative_to(ROOT), "rows:", len(SIGNS))


if __name__ == "__main__":
    main()
