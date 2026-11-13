#!/usr/bin/env python3
"""Paint the tiling ground detail that roads, footpaths and plots share (numpy + Pillow).

Output (committed, deterministic): assets/textures/ground_detail.png, 1024 × 1024, four grey
detail maps packed into one texture so the street shader pays for a single lookup:
  R  asphalt     bitumen with stone aggregate showing through, pits            (one tile = 3.2 m)
  G  pavers      interlocking concrete blocks, each a slightly different grey  (one tile = 1.6 m)
  B  concrete    trowelled cement: soft blotches, hairline cracks, pin holes   (one tile = 4 m)
  A  wear map    low-frequency blotches (0.15–0.65) for fading and stains, with crisp repair
                 patches (0.92) and a trench scar (0.82) laid on top           (one tile = 53 m)
Every map wraps on all four edges (the noise is shaped in the frequency domain, shapes are
drawn with wrap-around). Detail maps average 0.5, so vertex colours keep their tone.

The street shader (shaders/street_surface.gdshader) multiplies a surface's vertex colour by its
map; the wear map is sampled a second time, rotated, so nothing repeats along a road.

Usage: python3 tools/art/make_ground_detail.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "textures" / "ground_detail.png"
N = 1024
rng = np.random.default_rng(600004)


def fbm(falloff: float, low_cut: float = 0.0, high_cut: float = 1e9) -> np.ndarray:
    """Tileable noise: white noise shaped as 1 / f^falloff. Returns 0..1."""
    f = np.fft.fft2(rng.standard_normal((N, N)))
    fy = np.fft.fftfreq(N)[:, None] * N
    fx = np.fft.fftfreq(N)[None, :] * N
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    gain = 1.0 / np.power(r, falloff)
    gain[(r < low_cut) | (r > high_cut)] = 0.0
    out = np.real(np.fft.ifft2(f * gain))
    lo, hi = np.percentile(out, [0.5, 99.5])
    return np.clip((out - lo) / (hi - lo), 0.0, 1.0)


def centre(a: np.ndarray, contrast: float) -> np.ndarray:
    """Re-centre on 0.5 with the given spread."""
    return np.clip(0.5 + (a - a.mean()) / (a.std() + 1e-6) * contrast, 0.0, 1.0)


def wrap_draw(draw_fn) -> np.ndarray:
    """Draw on a 3 × 3 canvas and fold it back, so shapes crossing an edge wrap."""
    im = Image.new("L", (N * 3, N * 3), 0)
    d = ImageDraw.Draw(im)
    draw_fn(d, N)
    a = np.asarray(im, dtype=np.float32) / 255.0
    return np.max([a[j * N:(j + 1) * N, i * N:(i + 1) * N] for j in range(3) for i in range(3)], axis=0)


def asphalt() -> np.ndarray:
    base = fbm(1.2, 3) * 0.5 + fbm(0.5, 40) * 0.5          # binder tone + fine grain
    stones = rng.random((N, N))
    light = (stones > 0.955).astype(np.float32)            # aggregate worn bright
    dark = (stones < 0.03).astype(np.float32)              # pits
    blur = lambda a, r: np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0
    return centre(base + blur(light, 0.9) * 1.6 - blur(dark, 1.1) * 1.4, 0.16)


def pavers() -> np.ndarray:
    bw, bh = N // 8, N // 16                                # 20 × 10 cm blocks at 1.6 m per tile
    tone = np.zeros((N, N), dtype=np.float32)
    joint = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(joint)
    zig = 7
    for row in range(16):
        off = (bw // 2) if row % 2 else 0
        y0 = row * bh
        for col in range(9):
            x0 = col * bw + off - bw
            tone_v = 0.5 + rng.uniform(-0.13, 0.13)
            xs = np.arange(max(0, x0), min(N, x0 + bw))
            if len(xs):
                tone[y0:y0 + bh, xs] = tone_v
            # zigzag end joint of this block (the interlock), wrapped
            pts = [(x0 + (zig if k % 2 else -zig) * 0.5, y0 + bh * k / 4) for k in range(5)]
            for shift in (-N, 0, N):
                d.line([(x + shift, y) for x, y in pts], fill=255, width=3)
        d.line([(0, y0), (N, y0)], fill=255, width=3)
    j = np.asarray(joint.filter(ImageFilter.GaussianBlur(1.0)), dtype=np.float32) / 255.0
    grain = fbm(0.6, 30)
    out = tone + (grain - 0.5) * 0.16 - j * 0.34
    return np.clip(0.5 + (out - out.mean()), 0.0, 1.0)


def concrete() -> np.ndarray:
    base = fbm(1.7, 2) * 0.6 + fbm(0.7, 30) * 0.4

    def cracks(d: ImageDraw.ImageDraw, n: int) -> None:
        for _ in range(9):
            x, y = rng.uniform(n, 2 * n), rng.uniform(n, 2 * n)
            ang = rng.uniform(0, np.pi * 2)
            pts = [(x, y)]
            for _ in range(int(rng.uniform(12, 40))):
                ang += rng.uniform(-0.5, 0.5)
                x, y = x + np.cos(ang) * 14, y + np.sin(ang) * 14
                pts.append((x, y))
            d.line(pts, fill=255, width=2)

    c = np.asarray(Image.fromarray((wrap_draw(cracks) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255.0
    pins = (rng.random((N, N)) < 0.004).astype(np.float32)
    return np.clip(centre(base, 0.11) - c * 0.3 - pins * 0.2, 0.0, 1.0)


def wear() -> np.ndarray:
    base = 0.15 + fbm(2.2, 1, 40) * 0.5

    def patches(d: ImageDraw.ImageDraw, n: int) -> None:
        for _ in range(11):                                  # repair patches: squared-off, never neat
            cx, cy = rng.uniform(n, 2 * n), rng.uniform(n, 2 * n)
            w, h = rng.uniform(18, 70), rng.uniform(14, 44)   # 1–3.6 m at 53 m per tile
            a = rng.uniform(0, np.pi)
            ca, sa = np.cos(a), np.sin(a)
            d.polygon([(cx + ca * sx * w - sa * sy * h, cy + sa * sx * w + ca * sy * h) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))], fill=235)

    def trench(d: ImageDraw.ImageDraw, n: int) -> None:
        y = n * 1.37                                          # one cable trench cut across the tile
        d.line([(0, y), (3 * n, y + n * 0.9)], fill=209, width=9)

    p = wrap_draw(patches)
    t = wrap_draw(trench)
    out = base.copy()
    out[t > 0.5] = 0.82
    out[p > 0.5] = 0.92
    return np.clip(out, 0.0, 1.0)


def build() -> Image.Image:
    maps = [asphalt(), pavers(), concrete(), wear()]
    return Image.merge("RGBA", [Image.fromarray((m * 255.0 + 0.5).astype(np.uint8), "L") for m in maps])


if __name__ == "__main__":
    im = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    im.save(OUT, optimize=True)
    print("wrote", OUT, im.size, "means", [round(float(np.asarray(c).mean()) / 255.0, 3) for c in im.split()])
