#!/usr/bin/env python3
"""Replace the photo-based face on a Ready Player Me head texture with a painted, generic face.

Used for `man_casual` (source titled after a real actor): the CC BY licence covers the 3D model,
not the person's likeness, so the photographic face is painted over with neutral skin and simple
stylised features (eyes, brows, nose shading, lips, a moustache) that match the game's look.
Hair, ears, neck and the rest of the avatar are kept.

The RPM head texture is stored upside down (forehead at the bottom). Coordinates below are for a
1024 px texture and were picked from the source; they scale with the image size.
Usage: python3 tools/art/genericize_face.py <in.jpeg> <out.png>
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def ellipse_mask(size, box, feather):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return m.filter(ImageFilter.GaussianBlur(feather))


def main(src: str, dst: str) -> int:
    img = Image.open(src).convert("RGB")
    W, H = img.size
    k = W / 1024.0
    S = lambda *v: tuple(int(x * k) for x in v)  # noqa: E731
    arr = np.asarray(img).astype(np.float32)
    # Skin tone from the forehead and cheeks (median, so stray hair pixels don't matter).
    # Mid-tone pixels of the whole face (no beard/hair shadows, no specular highlights).
    region = arr[int(300 * k):int(900 * k), int(300 * k):int(730 * k)].reshape(-1, 3)
    lum = region.mean(1)
    sat = region.max(1) - region.min(1)
    pick = region[(lum > 110) & (lum < 190) & (sat > 25)]
    skin = np.median(pick if len(pick) > 100 else region, axis=0)
    # Smooth painted skin with a soft top-to-bottom shade and fine noise (no photo detail left).
    yy = np.linspace(0, 1, H)[:, None, None]
    rng = np.random.default_rng(7)
    noise = Image.fromarray((rng.normal(0, 1, (H // 8, W // 8)) * 20 + 128).clip(0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    paint = skin * (0.94 + 0.08 * yy) + (np.asarray(noise, np.float32)[..., None] - 128) * 0.06
    face = ellipse_mask((W, H), S(270, 300, 760, 900), 28 * k)
    a = np.asarray(face, np.float32)[..., None] / 255.0
    out = arr * (1 - a) + paint * a
    im = Image.fromarray(out.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im, "RGBA")
    dark = (35, 25, 22, 255)
    lip = tuple(int(c) for c in (skin * np.array([0.78, 0.55, 0.52])).clip(0, 255)) + (255,)
    shade = tuple(int(c) for c in (skin * 0.82)) + (110,)
    # Upside-down layout: brows (y≈745) above eyes (y≈680) above nose (≈575) above moustache/mouth.
    for cx in (420, 604):
        d.ellipse(S(cx - 38, 662, cx + 38, 700), fill=(245, 240, 232, 255))          # eye white
        d.ellipse(S(cx - 15, 666, cx + 15, 696), fill=(58, 38, 26, 255))             # iris
        d.ellipse(S(cx - 7, 674, cx + 7, 688), fill=(12, 10, 10, 255))               # pupil
        d.arc(S(cx - 42, 655, cx + 42, 705), 180, 360, fill=dark, width=max(2, int(5 * k)))  # upper lid
        d.rounded_rectangle(S(cx - 48, 735, cx + 48, 752), radius=int(8 * k), fill=(40, 30, 26, 235))  # brow
    d.ellipse(S(486, 560, 538, 600), fill=shade)                                     # nose shadow
    d.ellipse(S(470, 556, 492, 572), fill=(90, 60, 50, 140))                         # nostrils
    d.ellipse(S(532, 556, 554, 572), fill=(90, 60, 50, 140))
    d.rounded_rectangle(S(440, 512, 584, 540), radius=int(12 * k), fill=(30, 22, 20, 245))  # moustache
    d.ellipse(S(452, 470, 572, 500), fill=lip)                                       # lips
    d.line(S(456, 485, 568, 485), fill=(80, 40, 40, 255), width=max(1, int(3 * k)))
    im = im.filter(ImageFilter.GaussianBlur(0.6 * k))
    im.save(dst)
    print(f"generic face written: {dst} (skin {skin.round().tolist()})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
