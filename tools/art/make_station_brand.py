#!/usr/bin/env python3
"""Draw the fictional "NAMMA GAS" autogas brand into the gas station's logo texture slot.

The source model carried a real fuel brand's logo; the game uses no real brands, so the same
texture (same layout: wordmark band at the top, emblem below, transparent background) is
redrawn with an original mark: an orange LPG flame inside a green ring, and NAMMA GAS in the
game's Baloo Thambi 2 font (SIL OFL). `--flip` matches the source texture's orientation.
Usage: python3 tools/art/make_station_brand.py <out.png> [--flip]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "assets" / "fonts" / "baloo_thambi_2" / "BalooThambi2-Variable.ttf"
GREEN = (16, 128, 72, 255)
ORANGE = (245, 130, 20, 255)
YELLOW = (255, 205, 40, 255)
WHITE = (255, 255, 255, 255)


def main(out: str, flip: bool) -> int:
    S = 2048
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Wordmark band (top of the texture, where the old brand name was).
    font = ImageFont.truetype(str(FONT), 300)
    try:
        font.set_variation_by_axes([800])
    except Exception:  # noqa: BLE001
        pass
    text = "NAMMA GAS"
    w = d.textlength(text, font=font)
    d.text(((S - w) / 2, 70), text, font=font, fill=GREEN, stroke_width=10, stroke_fill=WHITE)
    small = ImageFont.truetype(str(FONT), 120)
    sub = "AUTOGAS · LPG"
    d.text(((S - d.textlength(sub, font=small)) / 2, 420), sub, font=small, fill=ORANGE)
    # Emblem (centre where the old globe was): green ring, white disc, orange/yellow flame.
    cx, cy, r = S // 2, int(S * 0.62), int(S * 0.27)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=GREEN)
    d.ellipse((cx - r + 70, cy - r + 70, cx + r - 70, cy + r - 70), fill=WHITE)
    flame = [(cx, cy - int(r * 0.72)), (cx + int(r * 0.42), cy - int(r * 0.05)), (cx + int(r * 0.36), cy + int(r * 0.38)),
             (cx, cy + int(r * 0.6)), (cx - int(r * 0.36), cy + int(r * 0.38)), (cx - int(r * 0.42), cy - int(r * 0.05))]
    d.polygon(flame, fill=ORANGE)
    inner = [(cx, cy - int(r * 0.22)), (cx + int(r * 0.2), cy + int(r * 0.18)), (cx, cy + int(r * 0.45)), (cx - int(r * 0.2), cy + int(r * 0.18))]
    d.polygon(inner, fill=YELLOW)
    if flip:
        im = im.transpose(Image.FLIP_TOP_BOTTOM)  # the model samples this texture upside down
    im.save(out)
    print("brand texture:", out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], "--flip" in sys.argv))
