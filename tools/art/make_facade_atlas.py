#!/usr/bin/env python3
"""Paint the Chennai facade atlas used by every building (Pillow + numpy, raqm for Tamil).

Output (committed, deterministic):
  assets/textures/facade_atlas.png   2048×2048, 8×8 cells of 256 px. RGB = colour, A = tint mask
                                     (255 = plaster, multiplied by the building's vertex colour;
                                     0 = keeps its own colour: glass, frames, signboards, shutters)
  assets/textures/facade_glow.png    1024×1024, same layout: what lights up at night

One cell = one window bay (~3.4 m) × one floor (3.2 m), painted at 2× and scaled down. What makes
the cells read as Chennai rather than "a city": lime-washed plaster with black monsoon mildew
running down from every sunshade and parapet, MS window grilles, sarees drying on balcony
rails, PVC drain pipes, stilt-floor parking, perforated staircase jaali, shop boards in Tamil
first and English second, hanging sachet strips and flower garlands, clay weathering tiles on
the terrace, and the hoardings (silks, jewellers, Aadi sale, TNPSC coaching, flats for sale).

Cell map (row, col). Rows 0–3 keep the meaning they had in the 8×4 atlas:
  0 upper floors   0 grilled window + sunshade · 1 balcony · 2 twin windows · 3 ventilators + pipe
                   4 sliding window + AC · 5 office glass · 6 office strip window · 7 PLAIN plaster
  1 ground floor   0 house door + window · 1 compound wall run / gate leaf / stencilled panel
                   2 shutter (closed) · 3–7 shops
  2 ground floor   0–7 shops
  3 special        0 temple wall (kaavi) · 1 temple door · 2 cement terrace · 3 terrace + tank
                   4 heritage window · 5 thinnai veranda · 6–7 civic arches
  4 upper floors   0 balcony with washing · 1 box-grille window, old flat · 2 staircase jaali
                   3 party wall (mildew, brick) · 4 painted wall advert · 5 showroom cladding
                   6 showroom glass · 7 tenement window
  5 ground floor   0 stilt parking, two-wheelers · 1 stilt parking, car · 2 portico + grille gate
                   3 textile showroom · 4 jewellery showroom · 5 bank + ATM · 6 clinic entrance
                   7 small dwelling door
  6 hoardings      painted 2 : 1 and squeezed into a square cell (stretch them back on a 2 : 1 quad)
                   0 silks · 1 jewellers · 2 Aadi sale · 3 coaching · 4 hospital · 5 wedding hall
                   6 flats for sale · 7 paints
  7 roofs + more   0 Mangalore tiles · 1 corrugated sheet (tintable) · 2 clay weathering tiles
                   3 thatch · 4 church wall · 5 mosque wall · 6 school wall · 7 hospital wall
Every name is a generic trade, never a real business or brand.

The centre-left of cell (7, 0) is PLAIN plaster: every vertex-painted prop in the chunk mesh
(poles, tanks, stalls, carts) samples the single point WorldChunkStreamer.PLAIN_UV there, so
that spot must stay flat and near white.

Usage: python3 tools/art/make_facade_atlas.py
"""
from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "textures"
TAMIL_FONT = ROOT / "assets" / "fonts" / "baloo_thambi_2" / "BalooThambi2-Variable.ttf"
C = 256          # cell size in the atlas
S = 2            # supersampling while painting
P = C * S
COLS, ROWS = 8, 8
PLAIN = (236, 236, 233)

rng = random.Random(600004)
nrng = np.random.default_rng(600004)

WOOD = (112, 72, 42)
WOOD_DARK = (78, 48, 28)
ALU = (176, 180, 184)
GREEN_FRAME = (40, 92, 70)
BLUE_FRAME = (44, 78, 128)
GRILLE = (26, 26, 28)
PIPE = (196, 194, 186)
STEEL = (150, 152, 154)
BOARD_COLOURS = [(196, 28, 30), (22, 78, 168), (242, 190, 22), (28, 128, 62), (118, 24, 108), (232, 108, 20),
                 (18, 18, 20), (0, 138, 150), (250, 246, 232), (150, 20, 40)]
CLOTH = [(214, 40, 60), (240, 170, 30), (30, 120, 190), (40, 150, 90), (200, 60, 150), (250, 250, 245),
         (120, 60, 170), (240, 110, 40), (30, 60, 130), (255, 215, 60)]


def font(size: float, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(TAMIL_FONT), max(6, int(size * S)), layout_engine=ImageFont.Layout.RAQM)
    f.set_variation_by_name(weight)
    return f


def tile_noise(cells: int, size: int = P) -> np.ndarray:
    """Smooth 0..1 noise that wraps left-right (bays repeat along a wall)."""
    small = nrng.random((cells + 1, cells))
    small = np.concatenate([small, small[:, :1]], axis=1)
    im = Image.fromarray((small * 255).astype(np.uint8), "L").resize((size + size // cells, size), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32)[:, :size] / 255.0


class Cell:
    """One atlas cell painted at 2×. Coordinates are in cell pixels (0..256), y down."""

    def __init__(self) -> None:
        self.im = Image.new("RGBA", (P, P), (*PLAIN, 255))
        self.gl = Image.new("RGB", (P, P), (0, 0, 0))
        self.mul = Image.new("L", (P, P), 255)   # shadows, grime and streaks, multiplied in at the end
        self.d = ImageDraw.Draw(self.im)
        self.g = ImageDraw.Draw(self.gl)

    @staticmethod
    def box(x0: float, y0: float, x1: float, y1: float) -> list:
        return [int(round(x0 * S)), int(round(y0 * S)), int(round(x1 * S)) - 1, int(round(y1 * S)) - 1]

    def rect(self, x0: float, y0: float, x1: float, y1: float, rgb: tuple, tint: bool = False,
             glow: tuple | None = None) -> None:
        if x1 <= x0 or y1 <= y0:
            return
        self.d.rectangle(self.box(x0, y0, x1, y1), fill=(*rgb, 255 if tint else 0))
        if glow is not None:
            self.g.rectangle(self.box(x0, y0, x1, y1), fill=glow)

    def ellipse(self, x0: float, y0: float, x1: float, y1: float, rgb: tuple, tint: bool = False,
                glow: tuple | None = None) -> None:
        self.d.ellipse(self.box(x0, y0, x1, y1), fill=(*rgb, 255 if tint else 0))
        if glow is not None:
            self.g.ellipse(self.box(x0, y0, x1, y1), fill=glow)

    def line(self, pts: list, rgb: tuple, width: float = 1.0, tint: bool = False) -> None:
        self.d.line([(x * S, y * S) for x, y in pts], fill=(*rgb, 255 if tint else 0), width=max(1, int(round(width * S))))

    def poly(self, pts: list, rgb: tuple, tint: bool = False, glow: tuple | None = None) -> None:
        self.d.polygon([(x * S, y * S) for x, y in pts], fill=(*rgb, 255 if tint else 0))
        if glow is not None:
            self.g.polygon([(x * S, y * S) for x, y in pts], fill=glow)

    def gradient(self, x0: float, y0: float, x1: float, y1: float, top: tuple, bottom: tuple, tint: bool = False,
                 glow: tuple | None = None) -> None:
        n = max(1, int((y1 - y0) * S))
        for k in range(n):
            t = k / max(1, n - 1)
            rgb = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
            self.d.rectangle([int(x0 * S), int(y0 * S) + k, int(x1 * S) - 1, int(y0 * S) + k], fill=(*rgb, 255 if tint else 0))
        if glow is not None:
            self.g.rectangle(self.box(x0, y0, x1, y1), fill=glow)

    # --- soft darkening ---------------------------------------------------------------------

    def shade(self, x0: float, y0: float, x1: float, y1: float, dark: float, blur: float) -> None:
        layer = Image.new("L", (P, P), 255)
        ImageDraw.Draw(layer).rectangle(self.box(x0, y0, x1, y1), fill=int(255 * (1.0 - dark)))
        self.mul = ImageChops.multiply(self.mul, layer.filter(ImageFilter.GaussianBlur(blur * S)))

    def streaks(self, items: list, blur: float = 1.6) -> None:
        """Monsoon mildew: tapered runs down the wall. items = (x, y top, length, width, darkness)."""
        layer = Image.new("L", (P, P), 255)
        ld = ImageDraw.Draw(layer)
        for x, y, length, width, dark in items:
            v = int(255 * (1.0 - dark))
            wob = rng.uniform(-2.0, 2.0)
            ld.polygon([((x - width) * S, y * S), ((x + width) * S, y * S),
                        ((x + wob + width * 0.25) * S, (y + length) * S), ((x + wob - width * 0.25) * S, (y + length) * S)], fill=v)
        self.mul = ImageChops.multiply(self.mul, layer.filter(ImageFilter.GaussianBlur(blur * S)))

    def blotches(self, n: int, dark: float, x0: float = 0, y0: float = 0, x1: float = C, y1: float = C,
                 size: tuple = (10, 34)) -> None:
        layer = Image.new("L", (P, P), 255)
        ld = ImageDraw.Draw(layer)
        for _ in range(n):
            w, h = rng.uniform(*size), rng.uniform(*size) * 0.7
            x, y = rng.uniform(x0, x1 - w), rng.uniform(y0, y1 - h)
            ld.ellipse(self.box(x, y, x + w, y + h), fill=int(255 * (1.0 - dark * rng.uniform(0.5, 1.0))))
        self.mul = ImageChops.multiply(self.mul, layer.filter(ImageFilter.GaussianBlur(5 * S)))

    # --- materials ---------------------------------------------------------------------------

    def plaster(self, base: int = 236, wear: float = 1.0, x0: float = 0, y0: float = 0, x1: float = C, y1: float = C,
                tint: bool = True, warm: tuple = (0, 0, -3)) -> None:
        v = base + (tile_noise(5) - 0.5) * 12.0 * wear + (tile_noise(23) - 0.5) * 8.0 * wear \
            + (nrng.random((P, P), dtype=np.float32) - 0.5) * 7.0
        v = np.clip(v, 0, 255)
        rgb = np.stack([np.clip(v + warm[0], 0, 255), np.clip(v + warm[1], 0, 255), np.clip(v + warm[2], 0, 255),
                        np.full_like(v, 255.0 if tint else 0.0)], axis=-1).astype(np.uint8)
        b = self.box(x0, y0, x1, y1)
        patch = Image.fromarray(rgb, "RGBA").crop((b[0], b[1], b[2] + 1, b[3] + 1))
        self.im.paste(patch, (b[0], b[1]))

    def floor_band(self) -> None:
        """The slab line between floors: a light projecting band with the shadow it throws."""
        self.rect(0, C - 9, C, C - 2, (226, 225, 220), tint=True)
        self.rect(0, C - 2, C, C, (188, 187, 182), tint=True)
        self.shade(0, 0, C, 5, 0.22, 3.0)

    def weather(self, amount: float = 1.0) -> None:
        """Upper-floor ageing: damp along the slab above, a few long runs, patchy fading."""
        self.shade(0, -6, C, 10, 0.16 * amount, 7.0)
        self.streaks([(rng.uniform(6, C - 6), 0, rng.uniform(40, 150), rng.uniform(1.5, 4.0), rng.uniform(0.10, 0.24) * amount)
                      for _ in range(int(5 * amount))], blur=2.2)
        self.blotches(int(3 * amount), 0.07 * amount)

    def splashback(self, amount: float = 1.0) -> None:
        """Ground floors: road dust and rain splash climbing the first half metre."""
        self.shade(0, C - 30, C, C + 10, 0.26 * amount, 12.0)
        self.blotches(int(4 * amount), 0.10 * amount, y0=C - 70, size=(14, 40))

    # --- parts -------------------------------------------------------------------------------

    def sunshade(self, x0: float, x1: float, y: float, runs: bool = True) -> None:
        """Concrete chajja over an opening, the shadow under it and the black runs off its ends."""
        self.shade(x0 - 2, y + 4, x1 + 2, y + 20, 0.34, 4.0)
        self.rect(x0, y - 4, x1, y + 4, (232, 231, 226), tint=True)
        self.rect(x0, y + 3, x1, y + 5, (168, 167, 162), tint=True)
        if runs:
            self.streaks([(x0 + 2, y + 5, rng.uniform(50, 110), 2.6, 0.30), (x1 - 2, y + 5, rng.uniform(50, 110), 2.6, 0.30),
                          (rng.uniform(x0 + 8, x1 - 8), y + 5, rng.uniform(16, 40), 1.6, 0.16)])

    def glass(self, x0: float, y0: float, x1: float, y1: float, lit: bool, curtain: tuple | None = None,
              tone: tuple = (34, 44, 56)) -> None:
        top = tone
        bottom = tuple(min(255, c + 22) for c in tone)
        self.gradient(x0, y0, x1, y1, top, bottom, glow=(214, 160, 96) if lit else None)
        if curtain is not None:
            half = (x0 + x1) * 0.5 + rng.uniform(-6, 6)
            self.rect(x0, y0, half, y1, tuple(int(c * 0.55) for c in curtain), glow=tuple(int(c * 0.8) for c in curtain) if lit else None)
            for fx in np.arange(x0 + 3, half, 5):
                self.line([(fx, y0), (fx, y1)], tuple(int(c * 0.42) for c in curtain), 1.0)
        # sky catching the top corner of the pane
        self.poly([(x0, y0), (x0 + (x1 - x0) * 0.45, y0), (x0, y0 + (y1 - y0) * 0.5)], tuple(min(255, c + 30) for c in tone))

    def grille(self, x0: float, y0: float, x1: float, y1: float, style: str = "bars") -> None:
        if style == "bars":
            for gx in np.arange(x0 + 5, x1 - 2, 7.5):
                self.line([(gx, y0), (gx, y1)], GRILLE, 1.2)
            for gy in (y0 + (y1 - y0) * 0.33, y0 + (y1 - y0) * 0.66):
                self.line([(x0, gy), (x1, gy)], GRILLE, 1.4)
        elif style == "diamond":
            step = 13.0
            for k in np.arange(-(y1 - y0), (x1 - x0), step):
                a = (max(x0, x0 + k), y0 + max(0.0, -k))
                b = (min(x1, x0 + k + (y1 - y0)), y0 + min(y1 - y0, (x1 - x0) - k))
                self.line([a, b], GRILLE, 1.0)
                self.line([(x0 + x1 - a[0], a[1]), (x0 + x1 - b[0], b[1])], GRILLE, 1.0)
        elif style == "sun":
            # rising-sun grille: rays from the middle of the sill, cut off at the frame
            cx, cy = (x0 + x1) * 0.5, y1
            for k in range(9):
                ang = math.pi * (k + 0.5) / 9.0
                dx, dy = -math.cos(ang), -math.sin(ang)
                t = min((x1 - x0) * 0.5 / max(abs(dx), 1e-3), (y1 - y0) / max(abs(dy), 1e-3))
                self.line([(cx, cy), (cx + dx * t, cy + dy * t)], GRILLE, 1.0)
            self.d.arc(self.box(cx - 14, cy - 14, cx + 14, cy + 14), 180, 360, fill=(*GRILLE, 0), width=S)
        self.d.rectangle(self.box(x0, y0, x1, y1), outline=(*GRILLE, 0), width=S)

    def window(self, x: float, y: float, w: float, h: float, lit: bool = False, frame: tuple = WOOD, panes: int = 2,
               grille: str | None = "bars", shade: bool = True, curtain: tuple | None = None, sill: bool = True) -> None:
        if shade:
            self.sunshade(x - 13, x + w + 13, y - 12)
        self.shade(x - 4, y - 3, x + w + 4, y + h + 5, 0.12, 2.0)
        self.rect(x - 4, y - 4, x + w + 4, y + h + 4, frame)
        self.glass(x, y, x + w, y + h, lit, curtain)
        for k in range(1, panes):
            mx = x + w * k / panes
            self.rect(mx - 1.5, y, mx + 1.5, y + h, frame)
        if grille:
            self.grille(x, y, x + w, y + h, grille)
        if sill:
            self.rect(x - 8, y + h + 4, x + w + 8, y + h + 9, (228, 227, 222), tint=True)
            self.shade(x - 8, y + h + 9, x + w + 8, y + h + 15, 0.2, 2.5)
            self.streaks([(x - 5, y + h + 9, rng.uniform(20, 50), 2.0, 0.2), (x + w + 5, y + h + 9, rng.uniform(20, 50), 2.0, 0.2)])

    def pipe(self, x: float, y0: float = 0, y1: float = C, rgb: tuple = PIPE, w: float = 5.0) -> None:
        self.shade(x + w * 0.5, y0, x + w * 1.6, y1, 0.22, 1.5)
        self.rect(x - w * 0.5, y0, x + w * 0.5, y1, rgb)
        self.rect(x - w * 0.5, y0, x - w * 0.2, y1, tuple(min(255, c + 22) for c in rgb))
        for cy in np.arange(y0 + 30, y1, 78):
            self.rect(x - w * 0.5 - 1.5, cy, x + w * 0.5 + 1.5, cy + 3, (120, 120, 118))
        self.streaks([(x, y0, y1 - y0, w * 0.9, 0.10)], blur=3.0)

    def ac_unit(self, x: float, y: float) -> None:
        self.shade(x - 1, y + 26, x + 46, y + 34, 0.3, 2.5)
        self.rect(x, y, x + 44, y + 28, (232, 232, 226))
        self.rect(x, y + 24, x + 44, y + 28, (200, 200, 194))
        self.ellipse(x + 5, y + 3, x + 27, y + 25, (92, 94, 96))
        self.ellipse(x + 12, y + 10, x + 20, y + 18, (168, 170, 170))
        for ly in np.arange(y + 5, y + 23, 4):
            self.line([(x + 31, ly), (x + 41, ly)], (150, 150, 146), 1.0)
        self.streaks([(x + 20, y + 28, rng.uniform(30, 70), 3.0, 0.24)])
        self.line([(x + 44, y + 12), (x + 52, y + 12), (x + 52, y - 30)], (60, 60, 62), 1.6)

    def washing(self, x0: float, x1: float, y: float, drop: tuple = (26, 52)) -> None:
        """Clothes over a rail: saree lengths with a contrast border, towels, a lungi."""
        x = x0
        while x < x1 - 10:
            w = rng.uniform(13, 30)
            col = CLOTH[rng.randrange(len(CLOTH))]
            length = rng.uniform(*drop)
            self.rect(x, y, min(x + w, x1), y + length, col)
            if w > 20:  # saree: border and a few motifs
                edge = CLOTH[rng.randrange(len(CLOTH))]
                self.rect(x, y + length - 6, min(x + w, x1), y + length, edge)
                self.rect(x, y, x + 3, y + length, edge)
            else:
                for sy in np.arange(y + 5, y + length - 3, 7):
                    self.line([(x, sy), (min(x + w, x1), sy)], tuple(int(c * 0.72) for c in col), 1.0)
            self.shade(x + w - 1, y, x + w + 3, y + length, 0.2, 1.2)
            x += w + rng.uniform(1, 6)

    def plant(self, x: float, y: float, r: float = 11.0) -> None:
        self.rect(x - r * 0.55, y, x + r * 0.55, y + r * 0.9, (150, 78, 50))
        for _ in range(9):
            a, d = rng.uniform(0, math.tau), rng.uniform(0, r * 0.7)
            px, py = x + math.cos(a) * d, y - r * 0.6 + math.sin(a) * d * 0.7
            g_ = rng.randint(96, 150)
            self.ellipse(px - r * 0.42, py - r * 0.36, px + r * 0.42, py + r * 0.36, (34, g_, 48))

    def text(self, x: float, y: float, w: float, h: float, s: str, rgb: tuple, weight: str = "Bold",
             stroke: tuple | None = None, on: "ImageDraw.ImageDraw | None" = None, scale: float = 1.0) -> None:
        """Fit `s` into the box, centred."""
        d = on or self.d
        size = h
        while size > 5:
            f = font(size * scale, weight)
            l, t, r, b = d.textbbox((0, 0), s, font=f)
            if (r - l) <= w * S * scale and (b - t) <= h * S * scale:
                break
            size -= 1
        px = x * S * scale + (w * S * scale - (r - l)) / 2 - l
        py = y * S * scale + (h * S * scale - (b - t)) / 2 - t
        fill = (*rgb, 0) if d is self.d else rgb
        if stroke is not None:
            d.text((px, py), s, font=f, fill=fill, stroke_width=max(1, int(size * 0.07 * S * scale)),
                   stroke_fill=(*stroke, 0) if d is self.d else stroke)
        else:
            d.text((px, py), s, font=f, fill=fill)

    def name_board(self, x0: float, y0: float, x1: float, y1: float, colour: tuple, tamil: str, english: str = "",
                   accent: tuple | None = None) -> None:
        """Flex name board: Tamil large on top, English below, a coloured side panel and frame."""
        light = sum(colour) > 430
        ink = (22, 22, 24) if light else (255, 250, 232)
        accent = accent or ((196, 28, 30) if light else (250, 204, 40))
        lit = tuple(min(255, int(c * 0.85) + 45) for c in colour)
        self.shade(x0, y1, x1, y1 + 9, 0.3, 3.0)
        self.gradient(x0, y0, x1, y1, tuple(min(255, c + 16) for c in colour), tuple(int(c * 0.86) for c in colour), glow=lit)
        self.rect(x0, y0, x0 + 7, y1, accent, glow=accent)
        self.rect(x1 - 7, y0, x1, y1, accent, glow=accent)
        self.d.rectangle(self.box(x0, y0, x1, y1), outline=(*tuple(int(c * 0.5) for c in colour), 0), width=S)
        hh = y1 - y0
        if english:
            self.text(x0 + 10, y0 + hh * 0.04, x1 - x0 - 20, hh * 0.56, tamil, ink, "ExtraBold")
            self.text(x0 + 10, y0 + hh * 0.62, x1 - x0 - 20, hh * 0.30, english, accent if not light else (30, 60, 150), "Bold")
        else:
            self.text(x0 + 10, y0 + hh * 0.1, x1 - x0 - 20, hh * 0.8, tamil, ink, "ExtraBold")

    # --- finish ------------------------------------------------------------------------------

    def done(self) -> tuple[Image.Image, Image.Image]:
        r, g_, b, a = self.im.split()
        rgb = [ImageChops.multiply(ch, self.mul) for ch in (r, g_, b)]
        # Channel by channel: alpha here is the tint mask, and an RGBA resize would premultiply by it.
        out = Image.merge("RGBA", [ch.resize((C, C), Image.LANCZOS) for ch in (*rgb, a)])
        return out, self.gl.resize((C, C), Image.LANCZOS)


# === Cells =========================================================================================

def upper_base(wear: float = 1.0) -> Cell:
    c = Cell()
    c.plaster(wear=wear)
    c.weather(wear)
    c.floor_band()
    return c


def c_window_grille() -> Cell:
    c = upper_base()
    c.window(72, 70, 112, 104, lit=True, frame=WOOD, panes=3, grille="bars", curtain=(210, 150, 60))
    return c


def c_balcony(washing: bool = False) -> Cell:
    c = upper_base(1.1 if washing else 0.9)
    # door and window behind
    c.sunshade(20, 236, 30)
    c.rect(48, 52, 112, 214, WOOD_DARK)
    c.glass(53, 57, 107, 150, lit=not washing, curtain=(200, 90, 70) if washing else (90, 130, 180))
    c.rect(53, 152, 107, 212, WOOD)
    c.window(136, 78, 72, 78, lit=washing, frame=WOOD, panes=2, grille="bars", shade=False, sill=False)
    # slab and MS railing
    c.shade(4, 214, 252, 232, 0.28, 4.0)
    c.rect(4, 206, 252, 216, (226, 225, 220), tint=True)
    c.rect(4, 214, 252, 217, (170, 169, 164), tint=True)
    rail = (36, 36, 40) if not washing else (70, 46, 34)
    c.rect(6, 150, 250, 154, rail)
    for bx in np.arange(8, 250, 9):
        c.line([(bx, 154), (bx, 206)], rail, 1.6)
    c.rect(6, 178, 250, 180, rail)
    if washing:
        c.washing(10, 246, 152)
        c.rect(206, 190, 232, 206, (30, 90, 170))   # plastic water drum
        c.rect(206, 188, 232, 191, (20, 60, 130))
    else:
        c.plant(26, 186, 13)
        c.plant(228, 190, 10)
        c.plant(204, 192, 8)
    c.streaks([(6, 217, 34, 3.0, 0.3), (250, 217, 34, 3.0, 0.3), (120, 217, 26, 2.0, 0.18)])
    return c


def c_twin_windows() -> Cell:
    c = upper_base()
    c.window(30, 74, 78, 92, lit=False, frame=GREEN_FRAME, panes=2, grille="diamond")
    c.window(150, 74, 78, 92, lit=True, frame=GREEN_FRAME, panes=2, grille="diamond", curtain=(230, 200, 120))
    return c


def c_ventilators() -> Cell:
    c = upper_base(1.3)
    # bathroom ventilator louvres and the pipes that come with them
    for vx in (60, 150):
        c.rect(vx - 3, 58, vx + 51, 106, (222, 221, 216), tint=True)
        for k in range(5):
            c.rect(vx, 62 + k * 9, vx + 48, 67 + k * 9, (84, 88, 92))
            c.rect(vx, 67 + k * 9, vx + 48, 69 + k * 9, (40, 42, 44))
        c.streaks([(vx + 6, 106, 80, 3.0, 0.3), (vx + 40, 106, 60, 3.0, 0.26)])
    c.pipe(120, 0, C, PIPE, 6.0)
    c.pipe(132, 0, C, (150, 96, 70), 4.0)
    c.window(176, 150, 46, 46, lit=False, frame=ALU, panes=1, grille="bars", shade=False)
    return c


def c_sliding_ac() -> Cell:
    c = upper_base(0.8)
    c.sunshade(40, 216, 44)
    c.rect(52, 58, 204, 150, ALU)
    c.glass(57, 63, 127, 145, lit=True, tone=(52, 78, 104), curtain=(236, 232, 214))
    c.glass(131, 63, 199, 145, lit=False, tone=(46, 70, 96))
    c.rect(127, 58, 131, 150, ALU)
    c.grille(57, 63, 199, 145, "bars")
    c.rect(44, 150, 212, 156, (228, 227, 222), tint=True)
    c.ac_unit(92, 176)
    return c


def c_office_glass() -> Cell:
    c = Cell()
    c.gradient(0, 0, C, C, (58, 104, 128), (86, 132, 150))
    for gy in np.arange(0, C - 34, 8):
        c.line([(0, gy), (C, gy)], (66, 112, 134), 1.0)
    for gx in range(0, C, 64):
        if rng.random() < 0.55:
            c.g.rectangle(c.box(gx + 6, 4, gx + 60, C - 38), fill=(236, 236, 220))
        c.poly([(gx + 6, C - 40), (gx + 34, 6), (gx + 46, 6), (gx + 18, C - 40)], (98, 146, 166))
        c.rect(gx, 0, gx + 5, C, (188, 196, 200))
    c.rect(0, C - 34, C, C, (170, 176, 180))
    c.rect(0, C - 34, C, C - 31, (210, 214, 216))
    c.shade(0, C - 4, C, C + 4, 0.25, 2.0)
    return c


def c_office_strip() -> Cell:
    c = Cell()
    c.plaster(232, 0.6)
    c.weather(0.6)
    c.shade(0, 150, C, 166, 0.3, 4.0)
    c.rect(0, 76, C, 158, (60, 64, 68))
    for gx in range(0, C, 43):
        c.glass(gx + 3, 80, gx + 40, 154, lit=rng.random() < 0.6, tone=(60, 88, 108))
    c.rect(0, 68, C, 78, (226, 225, 220), tint=True)
    c.rect(0, 156, C, 164, (226, 225, 220), tint=True)
    c.streaks([(x, 164, rng.uniform(30, 70), 2.0, 0.2) for x in (20, 90, 140, 230)])
    c.floor_band()
    return c


def c_plain() -> Cell:
    """PLAIN_CELL: flat near-white round (0.3, 0.5) for every vertex-painted prop; a wall elsewhere."""
    c = Cell()
    c.plaster(wear=0.8)
    c.weather(0.8)
    c.pipe(200, 0, C, PIPE, 6.0)
    c.line([(170, 30), (182, 76), (176, 120), (186, 160)], (176, 176, 170), 1.0, tint=True)
    c.floor_band()
    # The clean patch. Painted last so no streak or blotch reaches it.
    c.im.paste((*PLAIN, 255), c.box(30, 84, 126, 172))
    c.mul.paste(255, c.box(30, 84, 126, 172))
    return c


# --- ground floors -----------------------------------------------------------------------------

def ground_base(wear: float = 1.0) -> Cell:
    c = Cell()
    c.plaster(wear=wear)
    c.splashback(wear)
    return c


def kolam(c: Cell, cx: float, y: float, r: float = 16.0) -> None:
    for k in range(4):
        a = math.pi * k / 4
        c.line([(cx - math.cos(a) * r, y - math.sin(a) * r * 0.3), (cx + math.cos(a) * r, y + math.sin(a) * r * 0.3)], (250, 250, 246), 1.0)
    c.d.ellipse(c.box(cx - r, y - r * 0.3, cx + r, y + r * 0.3), outline=(250, 250, 246, 0), width=S)


def c_house_ground() -> Cell:
    c = ground_base()
    c.sunshade(18, 110, 42)
    c.rect(28, 56, 100, 246, WOOD_DARK)
    c.rect(34, 62, 94, 240, WOOD)
    for py in (70, 152):
        c.rect(40, py, 62, py + 70, (126, 82, 48))
        c.rect(66, py, 88, py + 70, (126, 82, 48))
    c.ellipse(86, 150, 92, 156, (220, 190, 80))
    c.rect(34, 48, 94, 56, (60, 110, 60))   # mango-leaf thoranam
    for lx in np.arange(36, 94, 6):
        c.poly([(lx, 56), (lx + 5, 56), (lx + 2.5, 66)], (58, 130, 52))
    c.rect(22, 246, 106, 256, (150, 148, 142))
    c.window(144, 86, 80, 88, lit=True, frame=WOOD, panes=2, grille="sun", curtain=(180, 60, 60))
    kolam(c, 64, 251, 20)
    return c


def c_compound_gate() -> Cell:
    """Compound walls and gates (WorldChunkStreamer._compound_wall / _compound_gate), three parts:
    top half      a wall run, tiles left-right: coping, lime wash, monsoon runs, splash-back
    bottom left   one gate leaf (mirrored for the pair): painted steel sheet with spear tops
    bottom right  a wall panel with the stencil every Chennai wall carries, and torn posters
    """
    c = Cell()
    H = C // 2
    # --- wall run -----------------------------------------------------------------------------
    c.plaster(232, 1.7)
    c.rect(0, 0, C, 9, (224, 223, 217), tint=True)              # coping
    c.rect(0, 9, C, 12, (150, 149, 144), tint=True)
    c.shade(0, 10, C, 26, 0.3, 5.0)
    c.streaks([(rng.uniform(4, C - 4), 11, rng.uniform(24, 100), rng.uniform(1.6, 4.5), rng.uniform(0.2, 0.42)) for _ in range(15)], blur=2.4)
    c.blotches(6, 0.14, y1=H, size=(18, 50))
    c.shade(0, H - 26, C, H + 4, 0.34, 9.0)                     # splash-back and dust at the foot
    for jx in (0, 127.5):                                       # a pier every 1.7 m
        c.rect(jx - 6, 0, jx + 6, H, (236, 235, 230), tint=True)
        c.shade(jx + 6, 10, jx + 11, H, 0.2, 2.0)
    c.line([(60, 40), (66, 70), (58, 96), (64, 122)], (150, 148, 142), 1.0, tint=True)   # hairline crack
    # --- gate leaf ----------------------------------------------------------------------------
    steel = (38, 44, 50)
    c.rect(0, H, H, C, (30, 30, 32))
    c.gradient(4, H + 16, H - 2, C - 6, (58, 66, 74), (40, 46, 52))
    for gx in np.arange(4, H - 2, 15.5):                        # pressed-sheet ribs
        c.rect(gx, H + 16, gx + 2, C - 6, (78, 88, 96))
        c.rect(gx + 2, H + 16, gx + 3.5, C - 6, (26, 30, 34))
    for gy in (H + 16, H + 66, C - 12):                         # frame rails
        c.rect(2, gy, H - 1, gy + 6, steel)
    c.rect(2, H + 10, 8, C - 4, steel)
    c.rect(H - 7, H + 10, H - 1, C - 4, steel)
    for gx in np.arange(8, H - 4, 10):                          # spear tops, gilt
        c.rect(gx + 1.5, H + 3, gx + 3.5, H + 16, steel)
        c.poly([(gx - 0.5, H + 8), (gx + 5.5, H + 8), (gx + 2.5, H)], (204, 166, 60))
    c.rect(30, H + 30, 104, H + 60, (250, 250, 246))            # the plate on every gate
    c.text(32, H + 31, 70, 13, "NO PARKING", (190, 24, 30), "ExtraBold")
    c.text(32, H + 44, 70, 13, "IN FRONT OF GATE", (190, 24, 30), "Bold")
    c.rect(H - 16, H + 76, H - 9, H + 88, (190, 190, 186))      # latch
    c.streaks([(rng.uniform(10, H - 10), H + 16, rng.uniform(30, 80), 2.0, 0.22) for _ in range(5)])
    c.shade(0, C - 14, H, C + 4, 0.3, 5.0)
    # --- stencilled wall panel ----------------------------------------------------------------
    c.rect(H, H, C, H + 9, (224, 223, 217), tint=True)
    c.rect(H, H + 9, C, H + 12, (150, 149, 144), tint=True)
    c.shade(H, H + 10, C, H + 26, 0.3, 5.0)
    c.text(H + 8, H + 26, H - 16, 22, "STICK NO BILLS", (30, 44, 110), "ExtraBold")
    for k, (px, py, pw, ph, col) in enumerate([(H + 10, H + 58, 44, 50, (236, 208, 60)), (H + 60, H + 54, 50, 36, (228, 226, 216)),
                                                (H + 66, H + 92, 46, 26, (214, 90, 70))]):
        c.rect(px, py, px + pw, py + ph, col)                    # posters, half torn off
        for ly in np.arange(py + 6, py + ph - 4, 6):
            c.line([(px + 4, ly), (px + pw - 4 - (k * 7) % 12, ly)], tuple(int(v * 0.45) for v in col), 1.2)
        c.poly([(px + pw - 14, py), (px + pw, py), (px + pw, py + 16)], (226, 225, 220), tint=True)
    c.streaks([(rng.uniform(H + 4, C - 4), H + 11, rng.uniform(30, 100), rng.uniform(1.6, 4.0), rng.uniform(0.2, 0.4)) for _ in range(8)], blur=2.4)
    c.shade(H, C - 26, C, C + 4, 0.34, 9.0)
    return c


def c_shutter_closed() -> Cell:
    c = ground_base(0.6)
    c.name_board(4, 6, 252, 62, BOARD_COLOURS[2], "கடை", "STORES")
    c.rect(0, 62, 12, C, (226, 225, 220), tint=True)
    c.rect(244, 62, C, C, (226, 225, 220), tint=True)
    c.rect(12, 62, 244, 74, (120, 122, 124))
    c.gradient(14, 74, 242, 246, (164, 166, 168), (140, 142, 144))
    for sy in np.arange(76, 246, 7):
        c.line([(14, sy), (242, sy)], (112, 114, 116), 1.0)
        c.line([(14, sy + 1.5), (242, sy + 1.5)], (184, 186, 188), 1.0)
    c.text(40, 120, 176, 30, "TO LET", (40, 60, 150), "ExtraBold")
    c.text(40, 152, 176, 22, "வாடகைக்கு", (170, 30, 30), "Bold")
    c.rect(120, 236, 136, 246, (50, 50, 52))
    c.rect(12, 246, 244, C, (150, 148, 142))
    c.shade(12, 74, 244, 96, 0.25, 6.0)
    return c


def shelves(c: Cell, x0: float, y0: float, x1: float, y1: float, rows: int, pale: bool = False) -> None:
    hh = (y1 - y0) / rows
    for r in range(rows):
        by = y0 + (r + 1) * hh
        c.rect(x0, by - 3, x1, by, (96, 74, 52))
        x = x0 + 2
        while x < x1 - 6:
            w = rng.uniform(6, 13)
            col = (rng.randint(215, 250),) * 3 if pale and rng.random() < 0.6 else BOARD_COLOURS[rng.randrange(8)]
            col = tuple(int(v * 0.82) for v in col)
            c.rect(x, by - 3 - hh * rng.uniform(0.5, 0.8), min(x + w, x1 - 1), by - 3, col, glow=tuple(int(v * 0.55) for v in col))
            x += w + 1.5


def strands(c: Cell, x0: float, x1: float, y0: float, length: tuple, colours: list, step: float = 9.0, bead: float = 3.2) -> None:
    """Things that hang from a shop front: sachet strips, garlands, plastic toys."""
    for x in np.arange(x0, x1, step):
        n = int(rng.uniform(*length) / (bead * 1.6))
        col = colours[rng.randrange(len(colours))]
        for k in range(n):
            if rng.random() < 0.25:
                col = colours[rng.randrange(len(colours))]
            y = y0 + k * bead * 1.6
            c.rect(x - bead * 0.5, y, x + bead * 0.5, y + bead * 1.4, col, glow=tuple(int(v * 0.6) for v in col))


def counter(c: Cell, x0: float, x1: float, y0: float, y1: float, rgb: tuple = STEEL, glassy: bool = False) -> None:
    c.gradient(x0, y0, x1, y1, tuple(min(255, v + 26) for v in rgb), tuple(int(v * 0.74) for v in rgb))
    c.rect(x0, y0, x1, y0 + 4, tuple(min(255, v + 46) for v in rgb))
    if glassy:
        c.rect(x0 + 4, y0 + 8, x1 - 4, y1 - 8, (70, 96, 112), glow=(150, 190, 210))


def shop(tamil: str, english: str, colour: tuple, trade: str) -> Cell:
    c = ground_base(0.5)
    c.name_board(3, 5, 253, 62, colour, tamil, english)
    c.rect(0, 62, 11, C, (228, 227, 222), tint=True)
    c.rect(245, 62, C, C, (228, 227, 222), tint=True)
    c.rect(11, 62, 245, 73, (128, 130, 132))                    # rolled shutter box
    for sy in (65, 68, 71):
        c.line([(11, sy), (245, sy)], (98, 100, 102), 1.0)
    c.gradient(13, 73, 243, 242, (30, 26, 24), (64, 52, 42), glow=(73, 61, 40))   # the lit interior
    c.rect(100, 76, 156, 80, (240, 240, 230), glow=(255, 255, 240))            # tube light
    x0, x1, y0, y1 = 16, 240, 82, 240
    if trade == "tea":
        shelves(c, x0, y0, x1, 150, 2)
        counter(c, x0, x1, 176, y1, (154, 110, 70))
        for jx in np.arange(24, 150, 24):                       # biscuit jars
            c.rect(jx, 150, jx + 17, 176, (196, 206, 210), glow=(150, 150, 130))
            c.rect(jx + 2, 158, jx + 15, 174, (204, 150, 84))
            c.rect(jx + 1, 146, jx + 16, 151, (200, 40, 40))
        c.rect(170, 136, 200, 176, STEEL)                       # tea boiler
        c.ellipse(170, 128, 200, 144, (190, 192, 194))
        for bx in np.arange(206, 238, 6):                       # bananas hanging
            c.poly([(bx, 84), (bx + 5, 84), (bx + 7, 112), (bx + 2, 112)], (236, 202, 48), glow=(150, 130, 30))
    elif trade == "maligai":
        shelves(c, x0, y0 + 26, x1, 178, 3)
        strands(c, x0 + 4, x1, 82, (22, 46), [(230, 40, 50), (250, 200, 30), (30, 110, 200), (40, 160, 80), (250, 250, 250)], 8.0, 3.4)
        for sx in np.arange(20, 220, 44):                       # open sacks of rice and dal
            c.poly([(sx, y1), (sx + 4, 196), (sx + 36, 196), (sx + 40, y1)], (196, 172, 128))
            c.ellipse(sx + 4, 188, sx + 36, 204, [(244, 240, 226), (226, 176, 60), (176, 90, 50), (120, 150, 70)][int(sx) % 4])
    elif trade == "textile":
        for k, dx in enumerate(np.arange(x0 + 2, x1 - 22, 25)):  # sarees hung full length
            col = CLOTH[(k * 3 + 1) % len(CLOTH)]
            edge = CLOTH[(k * 5 + 4) % len(CLOTH)]
            c.gradient(dx, 84, dx + 21, 196, col, tuple(int(v * 0.7) for v in col), glow=tuple(int(v * 0.6) for v in col))
            c.rect(dx, 84, dx + 4, 196, edge)
            c.rect(dx, 186, dx + 21, 196, edge)
        counter(c, x0, x1, 200, y1, (120, 80, 50))
        for bx in np.arange(x0 + 6, x1 - 30, 34):
            for k in range(3):
                c.rect(bx, 198 - k * 6 - 6, bx + 28, 198 - k * 6, CLOTH[(int(bx) + k * 2) % len(CLOTH)])
    elif trade == "medical":
        c.gradient(13, 73, 243, 242, (200, 206, 204), (150, 158, 156), glow=(92, 96, 94))
        shelves(c, x0, y0, x1, 188, 4, pale=True)
        counter(c, x0, x1, 192, y1, (236, 238, 238), glassy=True)
        c.rect(112, 198, 144, 230, (250, 250, 250))
        c.rect(124, 201, 132, 227, (24, 150, 80), glow=(40, 220, 120))
        c.rect(115, 210, 141, 218, (24, 150, 80), glow=(40, 220, 120))
    elif trade == "hotel":
        c.gradient(13, 73, 243, 242, (120, 96, 70), (90, 70, 52), glow=(88, 71, 46))
        c.rect(x0, 84, 104, 132, (250, 246, 230))               # menu board
        for k in range(5):
            c.line([(x0 + 6, 92 + k * 8), (98, 92 + k * 8)], (150, 40, 40), 1.4)
        counter(c, x0, 110, 170, y1, STEEL, glassy=True)        # sweets and vadai in the glass case
        for bx in np.arange(x0 + 8, 100, 12):
            c.ellipse(bx, 190, bx + 9, 199, [(226, 150, 50), (240, 220, 160), (150, 90, 50)][int(bx) % 3])
        for tx in (132, 188):                                   # tables with banana leaves
            c.rect(tx, 190, tx + 44, 196, (150, 110, 70))
            c.rect(tx + 4, 196, tx + 8, y1, (110, 80, 50))
            c.rect(tx + 36, 196, tx + 40, y1, (110, 80, 50))
            c.rect(tx + 6, 186, tx + 38, 190, (60, 150, 70))
    elif trade == "mobile":
        c.gradient(13, 73, 243, 242, (40, 50, 80), (26, 30, 50), glow=(50, 63, 96))
        for r in range(2):
            for k, px in enumerate(np.arange(x0 + 4, x1 - 30, 38)):
                col = BOARD_COLOURS[(k + r * 3) % 8]
                c.rect(px, 86 + r * 50, px + 32, 130 + r * 50, col, glow=tuple(int(v * 0.8) for v in col))
                c.rect(px + 10, 92 + r * 50, px + 22, 124 + r * 50, (20, 20, 24))
                c.rect(px + 11, 94 + r * 50, px + 21, 120 + r * 50, (120, 190, 240), glow=(150, 210, 255))
        counter(c, x0, x1, 192, y1, (40, 44, 60), glassy=True)
    elif trade == "bakery":
        c.gradient(13, 73, 243, 242, (120, 90, 70), (96, 70, 54), glow=(96, 79, 54))
        shelves(c, x0, y0, x1, 150, 2)
        counter(c, x0, x1, 158, y1, (230, 222, 206), glassy=True)
        for r in range(2):
            for bx in np.arange(x0 + 8, x1 - 16, 18):
                col = [(250, 190, 200), (120, 70, 40), (250, 240, 210), (230, 170, 70)][(int(bx) + r) % 4]
                c.rect(bx, 176 + r * 28, bx + 13, 186 + r * 28, col, glow=tuple(int(v * 0.7) for v in col))
                c.ellipse(bx + 4, 172 + r * 28, bx + 9, 177 + r * 28, (200, 30, 40))
    elif trade == "xerox":
        c.gradient(13, 73, 243, 242, (190, 196, 200), (140, 146, 150), glow=(92, 94, 96))
        c.rect(x0 + 6, 150, x0 + 86, y1, (226, 228, 230))       # the copier
        c.rect(x0 + 6, 142, x0 + 86, 154, (60, 64, 70))
        c.rect(x0 + 14, 170, x0 + 78, 176, (40, 44, 50))
        c.rect(x0 + 70, 156, x0 + 82, 162, (60, 200, 120), glow=(60, 240, 140))
        c.rect(120, 96, 234, 150, (250, 250, 246))
        c.text(122, 98, 110, 18, "COLOUR PRINT", (190, 30, 30), "Bold")
        c.text(122, 116, 110, 16, "LAMINATION", (30, 60, 150), "Bold")
        c.text(122, 132, 110, 16, "SPIRAL BINDING", (30, 110, 60), "Bold")
        counter(c, 112, x1, 186, y1, (150, 120, 90))
    elif trade == "flower":
        c.gradient(13, 73, 243, 242, (50, 44, 34), (70, 58, 40), glow=(79, 67, 42))
        strands(c, x0 + 4, x1, 82, (60, 110), [(250, 150, 20), (250, 210, 40), (250, 250, 246), (220, 40, 70), (250, 150, 20)], 9.0, 4.4)
        counter(c, x0, x1, 198, y1, (120, 90, 60))
        for bx in np.arange(x0 + 4, x1 - 30, 38):               # baskets of loose jasmine and marigold
            c.ellipse(bx, 184, bx + 32, 206, [(250, 250, 244), (250, 160, 30), (230, 60, 90)][int(bx) % 3])
            c.rect(bx, 196, bx + 32, 204, (150, 110, 60))
    elif trade == "juice":
        c.gradient(13, 73, 243, 242, (60, 70, 50), (50, 56, 40), glow=(84, 88, 54))
        for bx in np.arange(x0 + 4, x1 - 10, 16):               # fruit hung in net bags
            col = [(250, 150, 30), (250, 214, 50), (120, 180, 60), (220, 50, 50)][int(bx) % 4]
            c.line([(bx + 6, 82), (bx + 6, 96)], (220, 220, 210), 1.0)
            for k in range(3):
                c.ellipse(bx, 94 + k * 11, bx + 13, 107 + k * 11, col, glow=tuple(int(v * 0.6) for v in col))
        counter(c, x0, x1, 168, y1, STEEL)
        for k, bx in enumerate(np.arange(x0 + 8, x1 - 30, 22)):  # the pile on the counter
            col = [(250, 150, 30), (120, 180, 60), (250, 214, 50), (200, 40, 60)][k % 4]
            c.ellipse(bx, 150 - (k % 2) * 8, bx + 20, 170 - (k % 2) * 8, col, glow=tuple(int(v * 0.6) for v in col))
        c.rect(196, 126, 220, 168, (226, 228, 230))             # mixer
        c.rect(200, 108, 216, 128, (150, 200, 220))
    elif trade == "hardware":
        shelves(c, x0, y0, 150, 190, 4)
        for k, px in enumerate(np.arange(158, x1 - 4, 9)):       # PVC pipes stood on end
            c.rect(px, 84 + (k % 3) * 8, px + 6, y1, [(210, 208, 200), (60, 110, 180), (150, 150, 150)][k % 3])
        for bx in np.arange(x0 + 2, 146, 24):                   # paint drums
            c.rect(bx, 204, bx + 20, y1, BOARD_COLOURS[int(bx) % 8])
            c.rect(bx, 204, bx + 20, 208, (220, 220, 220))
    elif trade == "tailor":
        strands(c, x0 + 6, x1, 82, (40, 70), CLOTH, 20.0, 12.0)
        counter(c, x0, x1, 190, y1, (110, 78, 50))
        c.rect(96, 160, 160, 190, (24, 24, 26))                 # sewing machine
        c.rect(96, 150, 112, 164, (24, 24, 26))
        c.ellipse(150, 152, 172, 174, (40, 40, 44))
        c.rect(100, 172, 150, 176, (210, 180, 60))
    elif trade == "fancy":
        strands(c, x0 + 3, x1, 82, (30, 90), [(250, 60, 120), (60, 200, 230), (250, 220, 60), (150, 230, 90), (250, 140, 40), (180, 90, 230)], 7.0, 4.0)
        shelves(c, x0, 176, x1, y1, 2)
    else:
        shelves(c, x0, y0, x1, y1 - 4, 5)
    c.shade(13, 73, 243, 100, 0.34, 8.0)                        # depth under the lintel
    c.rect(11, 242, 245, C, (160, 156, 148))                    # step
    c.shade(11, 240, 245, 246, 0.3, 1.5)
    return c


SHOPS = [  # (Tamil, English, board colour index, trade) → cells (3..7, 1) then (0..7, 2)
    ("டீ கடை", "TEA STALL", 0, "tea"), ("மளிகை கடை", "PROVISION STORE", 3, "maligai"),
    ("ஜவுளி கடை", "TEXTILES", 4, "textile"), ("மருந்தகம்", "MEDICALS", 8, "medical"),
    ("சைவ உணவகம்", "VEG HOTEL", 9, "hotel"),
    ("செல்போன் கடை", "MOBILES", 1, "mobile"), ("பேக்கரி", "BAKERY & SWEETS", 5, "bakery"),
    ("ஜெராக்ஸ்", "XEROX", 2, "xerox"), ("பூக்கடை", "FLOWERS", 3, "flower"),
    ("பழரசக் கடை", "JUICE SHOP", 5, "juice"), ("ஹார்டுவேர்ஸ்", "HARDWARES & PAINTS", 6, "hardware"),
    ("தையலகம்", "TAILORS", 7, "tailor"), ("ஃபேன்சி ஸ்டோர்", "FANCY STORE", 4, "fancy"),
]


# --- row 3: temples, terraces, heritage, civic ---------------------------------------------------

def c_kaavi(door: bool) -> Cell:
    c = Cell()
    for i in range(8):
        col = (176, 44, 30) if i % 2 == 0 else (244, 239, 226)
        c.gradient(i * 32, 0, i * 32 + 32, C, col, tuple(int(v * 0.9) for v in col))
    c.weather(0.9)
    c.splashback(0.8)
    if door:
        c.rect(84, 96, 172, C, (212, 176, 96))
        c.poly([(84, 96), (128, 50), (172, 96)], (212, 176, 96))
        c.rect(94, 106, 162, C, (86, 48, 24))
        for bx in (104, 128, 152):
            for by in np.arange(120, 246, 22):
                c.ellipse(bx - 3, by, bx + 3, by + 6, (214, 176, 70))
        c.rect(126, 106, 130, C, (56, 30, 14))
        strands(c, 92, 166, 98, (10, 18), [(250, 150, 20), (250, 214, 50)], 6.0, 3.0)
    return c


def c_terrace(tank: bool) -> Cell:
    c = Cell()
    c.plaster(198, 1.6)
    for gx in np.arange(0, C, 64):   # expansion joints in the screed
        c.line([(gx, 0), (gx, C)], (168, 166, 160), 1.0, tint=True)
        c.line([(0, gx), (C, gx)], (168, 166, 160), 1.0, tint=True)
    c.blotches(16, 0.28, size=(16, 60))
    if tank:
        c.ellipse(150, 44, 226, 120, (26, 26, 28))
        c.ellipse(168, 62, 208, 102, (50, 50, 54))
    return c


def c_heritage_window() -> Cell:
    c = upper_base(1.4)
    c.shade(60, 30, 196, 214, 0.14, 3.0)
    c.rect(64, 60, 192, 208, (150, 58, 40))
    c.d.pieslice(c.box(64, 12, 192, 108), 180, 360, fill=(150, 58, 40, 0))
    c.d.pieslice(c.box(74, 24, 182, 100), 180, 360, fill=(46, 56, 64, 0))
    for k in range(7):
        a = math.pi * (k + 1) / 8
        c.line([(128, 62), (128 - math.cos(a) * 54, 62 - math.sin(a) * 38)], (150, 58, 40), 2.0)
    for lx in np.arange(70, 190, 6):
        c.line([(lx, 66), (lx, 204)], (118, 44, 30), 1.2)
    c.rect(126, 60, 131, 208, (92, 34, 20))
    c.g.rectangle(c.box(74, 70, 122, 200), fill=(220, 160, 90))
    c.rect(54, 208, 202, 216, (228, 227, 222), tint=True)
    c.streaks([(58, 216, 34, 2.5, 0.3), (198, 216, 34, 2.5, 0.3)])
    return c


def c_thinnai() -> Cell:
    c = ground_base(1.2)
    c.shade(0, 0, C, 30, 0.3, 10.0)                     # under the tiled eave
    c.rect(0, 196, C, C, (158, 62, 46))                 # red-oxide thinnai
    c.rect(0, 196, C, 202, (186, 84, 64))
    for px in (14, 222):                                # round wooden pillars
        c.gradient(px, 20, px + 20, 196, (124, 80, 46), (86, 54, 30))
        c.rect(px - 4, 14, px + 24, 24, WOOD_DARK)
        c.rect(px - 4, 190, px + 24, 198, (120, 112, 100))
    c.rect(86, 52, 170, 196, WOOD_DARK)
    c.rect(92, 58, 126, 192, WOOD)
    c.rect(130, 58, 164, 192, WOOD)
    for by in np.arange(70, 190, 26):
        for bx in (100, 118, 138, 156):
            c.ellipse(bx - 2.5, by, bx + 2.5, by + 5, (214, 176, 70))
    c.rect(86, 42, 170, 52, (60, 110, 60))
    c.window(190, 86, 26, 60, lit=True, frame=WOOD_DARK, panes=1, grille="bars", shade=False, sill=False)
    kolam(c, 128, 240, 26)
    return c


def c_civic(ground: bool) -> Cell:
    c = Cell()
    c.plaster(228, 0.9)
    c.weather(0.9)
    top = 44 if ground else 56
    bottom = C - 2 if ground else 204
    stone = (196, 118, 88)
    c.shade(58, top, 198, bottom, 0.14, 3.0)
    c.d.pieslice(c.box(56, top - 8, 200, top + 110), 180, 360, fill=(*stone, 0))
    c.rect(56, top + 50, 200, bottom, stone)
    c.d.pieslice(c.box(68, top + 6, 188, top + 100), 180, 360, fill=((60, 60, 64, 0) if not ground else (70, 45, 30, 0)))
    inner = (60, 60, 64) if not ground else (70, 45, 30)
    c.rect(68, top + 52, 188, bottom, inner, glow=(240, 190, 120))
    if ground:
        c.rect(126, top + 52, 130, bottom, (40, 24, 14))
    else:
        c.rect(126, top + 10, 130, bottom, stone)
        c.rect(68, top + 110, 188, top + 114, stone)
        c.rect(50, bottom, 206, bottom + 8, (228, 227, 222), tint=True)
    for px in (20, 222):                                 # pilasters
        c.rect(px, 0, px + 14, C, (238, 237, 232), tint=True)
        c.shade(px + 14, 0, px + 20, C, 0.14, 2.0)
    if ground:
        c.splashback(0.8)
    else:
        c.floor_band()
    return c


# --- row 4: more upper floors -------------------------------------------------------------------

def c_box_grille() -> Cell:
    c = upper_base(1.6)
    c.sunshade(40, 216, 52)
    c.rect(56, 66, 200, 168, BLUE_FRAME)
    c.glass(61, 71, 126, 163, lit=False, curtain=(220, 120, 150))
    c.glass(130, 71, 195, 163, lit=True, curtain=(240, 220, 150))
    # the projecting box grille with things kept on it
    c.d.rectangle(c.box(48, 62, 208, 180), outline=(*GRILLE, 0), width=S)
    for gx in np.arange(48, 208, 8):
        c.line([(gx, 62), (gx, 180)], GRILLE, 1.0)
    for gy in (100, 140):
        c.line([(48, gy), (208, gy)], GRILLE, 1.2)
    c.rect(48, 176, 208, 181, GRILLE)
    c.plant(74, 164, 9)
    c.rect(150, 158, 176, 176, (190, 60, 50))            # plastic pot
    c.streaks([(50, 181, 60, 3.0, 0.34), (206, 181, 70, 3.0, 0.34), (130, 181, 40, 2.4, 0.22)])
    c.ac_unit(196, 196)
    c.pipe(22, 0, C, PIPE, 5.0)
    return c


def c_jaali() -> Cell:
    """Staircase bay: the perforated concrete screen every Chennai flat has."""
    c = upper_base(1.2)
    c.rect(72, 10, 184, 240, (214, 213, 208), tint=True)
    for gy in np.arange(18, 232, 19):
        for gx in np.arange(80, 178, 19):
            c.rect(gx, gy, gx + 12, gy + 12, (44, 46, 50))
            c.poly([(gx, gy), (gx + 12, gy), (gx + 9, gy + 3), (gx + 3, gy + 3)], (24, 24, 26))
    c.shade(184, 10, 192, 240, 0.2, 2.0)
    c.streaks([(74, 240, 12, 2.0, 0.3), (182, 240, 12, 2.0, 0.3)] + [(rng.uniform(80, 176), 10, rng.uniform(60, 200), 2.0, 0.14) for _ in range(4)])
    c.rect(206, 110, 240, 150, (120, 124, 128))          # EB meter box and conduit
    c.rect(210, 114, 236, 130, (40, 44, 48))
    c.line([(223, 150), (223, C)], (70, 70, 72), 2.0)
    return c


def c_party_wall() -> Cell:
    """Blind side wall: heavy mildew from the parapet, a patch where the plaster has come off."""
    c = Cell()
    c.plaster(228, 1.8)
    c.shade(0, -10, C, 40, 0.2, 14.0)
    c.streaks([(rng.uniform(4, C - 4), 0, rng.uniform(80, 250), rng.uniform(2.0, 6.0), rng.uniform(0.16, 0.36)) for _ in range(13)], blur=3.0)
    c.blotches(7, 0.16, size=(20, 60))
    bx, by = 150, 150                                    # exposed brick
    c.poly([(bx, by), (bx + 60, by - 8), (bx + 74, by + 30), (bx + 40, by + 52), (bx - 6, by + 36)], (150, 74, 50))
    for ry in np.arange(by - 6, by + 52, 7):
        c.line([(bx - 6, ry), (bx + 74, ry)], (196, 180, 160), 1.0)
    for k, ry in enumerate(np.arange(by - 6, by + 52, 7)):
        for rx in np.arange(bx - 6 + (k % 2) * 8, bx + 74, 16):
            c.line([(rx, ry), (rx, ry + 7)], (196, 180, 160), 1.0)
    mask = Image.new("L", (P, P), 0)
    ImageDraw.Draw(mask).polygon([(x * S, y * S) for x, y in [(bx, by), (bx + 60, by - 8), (bx + 74, by + 30), (bx + 40, by + 52), (bx - 6, by + 36)]], fill=255)
    keep = c.im.copy()
    c.plaster(228, 1.8)
    c.im = Image.composite(keep, c.im, mask.filter(ImageFilter.GaussianBlur(1.0)))
    c.d = ImageDraw.Draw(c.im)
    c.line([(40, 60), (52, 110), (46, 170), (60, 230)], (170, 168, 162), 1.0, tint=True)
    c.floor_band()
    return c


def c_wall_advert() -> Cell:
    """Hand-painted advert on a side wall: blue and yellow, weathering with the plaster."""
    c = Cell()
    c.plaster(230, 1.4)
    c.gradient(8, 34, 248, 226, (30, 74, 160), (24, 60, 136))
    c.rect(8, 34, 248, 46, (250, 204, 36))
    c.rect(8, 214, 248, 226, (250, 204, 36))
    c.text(16, 52, 224, 84, "சிமெண்ட்", (250, 214, 40), "ExtraBold", stroke=(150, 20, 20))
    c.text(16, 140, 224, 36, "CEMENT", (250, 250, 246), "ExtraBold")
    c.text(16, 180, 224, 26, "உறுதி · நம்பிக்கை", (250, 250, 246), "Bold")
    c.weather(1.6)
    c.blotches(8, 0.2)
    c.floor_band()
    return c


def c_cladding() -> Cell:
    """Showroom ACP panels: tintable, with the joints and a little dust in them."""
    c = Cell()
    c.im.paste((240, 240, 238, 255), [0, 0, P, P])
    for gx in (0, 128):
        for gy in (0, 128):
            c.gradient(gx + 2, gy + 2, gx + 126, gy + 126, (246, 246, 244), (224, 224, 222), tint=True)
    for gp in (0, 128):
        c.rect(gp - 1.5, 0, gp + 1.5, C, (120, 122, 126), tint=True)
        c.rect(0, gp - 1.5, C, gp + 1.5, (120, 122, 126), tint=True)
    c.streaks([(x, y, rng.uniform(20, 60), 2.0, 0.14) for x in (40, 96, 170, 220) for y in (2, 130)])
    return c


def c_showroom_glass() -> Cell:
    c = Cell()
    c.gradient(0, 0, C, C, (40, 70, 92), (74, 110, 128))
    for gx in range(0, C, 64):
        c.poly([(gx + 8, C), (gx + 40, 0), (gx + 54, 0), (gx + 22, C)], (88, 128, 148))
        c.rect(gx, 0, gx + 4, C, (30, 32, 36))
        if rng.random() < 0.7:
            c.g.rectangle(c.box(gx + 5, 4, gx + 63, C - 6), fill=(250, 236, 200))
    c.rect(0, C - 6, C, C, (30, 32, 36))
    c.rect(0, 124, C, 128, (30, 32, 36))
    return c


def c_tenement() -> Cell:
    """Housing-board block: small steel window, weather-beaten lime wash, a line of washing."""
    c = upper_base(2.0)
    c.window(40, 84, 62, 70, lit=True, frame=(70, 96, 110), panes=2, grille="bars")
    c.rect(146, 60, 206, 214, (70, 96, 110))             # door on the access corridor
    c.rect(151, 65, 201, 210, (96, 126, 140))
    c.rect(196, 132, 200, 142, (30, 30, 32))
    c.line([(8, 190), (140, 184)], (60, 60, 60), 1.0)
    c.washing(12, 136, 188, (16, 34))
    c.blotches(6, 0.2)
    return c


# --- row 5: more ground floors ------------------------------------------------------------------

def stilt(car: bool) -> Cell:
    """Stilt-floor parking under the flats: columns, a dark bay, two-wheelers or a covered car."""
    c = Cell()
    c.plaster(wear=0.8)
    c.gradient(0, 34, C, C, (30, 30, 32), (72, 70, 66), glow=(60, 54, 40))
    c.gradient(0, 208, C, C, (104, 102, 96), (132, 130, 124))          # the floor catching light
    c.rect(0, 0, C, 36, (230, 229, 224), tint=True)                     # beam
    c.shade(0, 34, C, 62, 0.4, 9.0)
    c.rect(118, 44, 138, 50, (236, 236, 226), glow=(255, 255, 236))     # tube light
    for px in (0, 226):                                                 # columns
        c.rect(px, 30, px + 30, C, (232, 231, 226), tint=True)
        c.shade(px + 30 if px == 0 else px - 6, 36, px + 36 if px == 0 else px, C, 0.3, 3.0)
        c.rect(px, 214, px + 30, C, (40, 40, 42))                       # yellow/black column guard
        for k in range(3):
            c.poly([(px + k * 12 - 4, C), (px + k * 12 + 4, C), (px + k * 12 + 16, 214), (px + k * 12 + 8, 214)], (240, 196, 30))
    if car:
        c.poly([(52, 240), (56, 196), (84, 168), (170, 168), (198, 196), (204, 240)], (176, 180, 186))  # car under a cover
        c.poly([(84, 168), (170, 168), (160, 150), (96, 150)], (190, 194, 200))
        for fx in np.arange(64, 200, 14):
            c.line([(fx, 176), (fx - 3, 238)], (150, 154, 160), 1.0)
        c.ellipse(64, 226, 90, 250, (22, 22, 24))
        c.ellipse(166, 226, 192, 250, (22, 22, 24))
    else:
        for k, bx in enumerate((44, 96, 150)):                          # scooters and a bike, nose in
            col = [(200, 40, 40), (40, 60, 90), (230, 230, 226)][k]
            c.ellipse(bx + 4, 220, bx + 28, 252, (20, 20, 22))
            c.rect(bx, 182, bx + 32, 232, col)
            c.ellipse(bx + 2, 170, bx + 30, 194, col)
            c.rect(bx + 10, 176, bx + 22, 186, (240, 236, 200), glow=(120, 110, 60))
            c.rect(bx - 6, 164, bx + 38, 168, (30, 30, 32))
            c.rect(bx + 8, 150, bx + 24, 164, (36, 36, 40))
        c.rect(200, 190, 220, 244, (40, 90, 170))                       # water cans
    # It is a shaded bay, not a showroom: everything inside sits in deep shadow.
    c.shade(30, 50, 226, 262, 0.74, 7.0)
    c.shade(0, 244, C, C + 8, 0.25, 4.0)
    return c


def c_portico() -> Cell:
    c = ground_base(0.9)
    c.shade(0, 0, C, 40, 0.26, 12.0)
    c.rect(0, 60, 16, C, (230, 229, 224), tint=True)
    c.rect(240, 60, C, C, (230, 229, 224), tint=True)
    c.rect(16, 66, 240, 246, (26, 28, 30))
    c.gradient(22, 72, 234, 246, (60, 52, 44), (96, 84, 70), glow=(150, 120, 80))
    c.rect(150, 96, 214, 246, WOOD_DARK)                 # front door inside
    c.rect(156, 102, 208, 242, WOOD)
    c.ellipse(34, 180, 110, 246, (30, 30, 34))           # scooter parked in the portico
    c.rect(48, 150, 96, 214, (40, 110, 160))
    c.rect(40, 140, 104, 146, (30, 30, 32))
    c.grille(16, 66, 240, 246, "bars")                   # the collapsible grille gate
    for gx in np.arange(16, 240, 16):
        c.line([(gx, 66), (gx + 8, 156), (gx, 246)], GRILLE, 1.0)
    c.rect(16, 60, 240, 68, (228, 227, 222), tint=True)
    c.rect(0, 246, C, C, (150, 148, 142))
    kolam(c, 128, 251, 22)
    c.rect(196, 24, 244, 50, (30, 60, 130))              # house name plate
    c.text(198, 26, 44, 20, "இல்லம்", (250, 250, 246), "Bold")
    return c


def showroom_front(kind: str) -> Cell:
    c = Cell()
    c.plaster(wear=0.3)
    gold = kind == "jewel"
    c.rect(0, 0, C, 40, (40, 20, 24) if gold else (24, 30, 60))
    c.rect(0, 36, C, 40, (214, 170, 60))
    c.gradient(8, 44, 248, 244, (250, 240, 214), (232, 214, 170), glow=(255, 240, 200))
    if gold:
        c.text(12, 4, 232, 30, "தங்கம் · வெள்ளி · வைரம்", (240, 200, 90), "Bold")
        for sx in np.arange(20, 240, 56):                # velvet busts with necklaces
            c.rect(sx, 150, sx + 40, 244, (120, 20, 40))
            c.ellipse(sx + 4, 100, sx + 36, 170, (120, 20, 40))
            for k in range(3):
                c.d.arc(c.box(sx + 8, 112 + k * 10, sx + 32, 150 + k * 12), 0, 180, fill=(236, 190, 60, 0), width=S * 2)
            c.g.ellipse(c.box(sx + 8, 120, sx + 32, 160), fill=(255, 220, 120))
        for sx in np.arange(16, 240, 20):
            c.ellipse(sx, 56, sx + 10, 66, (240, 200, 80), glow=(255, 230, 140))
    else:
        c.text(12, 4, 232, 30, "பட்டு · ரெடிமேட்ஸ்", (250, 250, 240), "Bold")
        for k, sx in enumerate(np.arange(18, 230, 54)):  # mannequins in sarees
            col = CLOTH[(k * 3) % len(CLOTH)]
            edge = CLOTH[(k * 3 + 5) % len(CLOTH)]
            c.ellipse(sx + 12, 62, sx + 28, 82, (206, 160, 124))
            c.poly([(sx + 4, 90), (sx + 36, 90), (sx + 44, 244), (sx - 4, 244)], col, glow=tuple(int(v * 0.5) for v in col))
            c.poly([(sx + 4, 90), (sx + 16, 90), (sx + 40, 200), (sx + 30, 204)], edge)
            c.rect(sx - 4, 232, sx + 44, 244, edge)
    for gx in (8, 126, 244):
        c.rect(gx - 3, 44, gx + 3, 246, (36, 38, 42))
    c.rect(0, 244, C, C, (190, 186, 176))
    return c


def c_bank() -> Cell:
    c = ground_base(0.4)
    c.name_board(3, 5, 253, 62, (18, 60, 130), "வங்கி", "BANK · ATM", accent=(240, 180, 30))
    c.rect(0, 62, 10, C, (230, 229, 224), tint=True)
    c.rect(246, 62, C, C, (230, 229, 224), tint=True)
    c.gradient(10, 62, 150, 246, (70, 100, 120), (110, 140, 156), glow=(220, 230, 235))   # glass front
    for gx in (10, 80, 150):
        c.rect(gx - 2, 62, gx + 2, 246, ALU)
    c.rect(10, 150, 150, 154, ALU)
    c.rect(96, 190, 100, 214, (220, 220, 220))
    c.rect(158, 70, 240, 246, (26, 56, 120))             # ATM cabin
    c.rect(166, 80, 232, 104, (250, 250, 246), glow=(250, 250, 246))
    c.text(168, 82, 62, 20, "ATM", (26, 56, 120), "ExtraBold")
    c.gradient(170, 112, 228, 246, (90, 120, 140), (130, 156, 170), glow=(200, 220, 230))
    c.rect(11, 246, 245, C, (170, 166, 158))
    return c


def c_clinic() -> Cell:
    c = ground_base(0.5)
    c.name_board(3, 5, 253, 62, (250, 250, 246), "மருத்துவமனை", "CLINIC · 24 HRS", accent=(200, 30, 40))
    c.rect(0, 62, C, C, (240, 242, 240), tint=True)
    c.rect(0, 150, C, 162, (40, 120, 190))
    c.gradient(70, 76, 186, 246, (90, 124, 140), (140, 170, 180), glow=(220, 236, 240))
    c.rect(126, 76, 130, 246, ALU)
    c.rect(66, 72, 190, 78, ALU)
    c.rect(20, 92, 54, 126, (250, 250, 250))
    c.rect(32, 96, 42, 122, (210, 30, 40), glow=(255, 60, 60))
    c.rect(24, 104, 50, 114, (210, 30, 40), glow=(255, 60, 60))
    c.rect(60, 246, 196, C, (170, 166, 158))             # ramp
    c.splashback(0.5)
    return c


def c_small_door() -> Cell:
    """Back-lane / fishing hamlet front: a bright wall, a curtain in the doorway, pots outside."""
    c = ground_base(1.6)
    c.rect(34, 70, 110, 246, (40, 96, 150))
    c.rect(40, 76, 104, 246, (24, 26, 30))
    c.poly([(40, 76), (104, 76), (96, 190), (48, 200)], (214, 60, 90))   # door curtain tied back
    for fx in np.arange(46, 100, 7):
        c.line([(fx, 78), (fx - 2, 190)], (170, 40, 70), 1.0)
    c.window(150, 96, 60, 56, lit=True, frame=(40, 96, 150), panes=2, grille="bars", shade=False)
    for k, px in enumerate((132, 160, 190, 218)):        # plastic kudams (water pots)
        col = [(240, 120, 30), (30, 130, 200), (230, 50, 60), (250, 200, 40)][k]
        c.ellipse(px, 214, px + 26, 250, col)
        c.rect(px + 7, 204, px + 19, 218, col)
        c.ellipse(px + 4, 200, px + 22, 208, tuple(int(v * 0.8) for v in col))
    c.rect(24, 246, 120, C, (150, 148, 142))
    kolam(c, 72, 251, 18)
    c.blotches(8, 0.2)
    return c


# --- row 6: hoardings (painted 2 : 1, squeezed) ---------------------------------------------------

def hoarding(bg_top: tuple, bg_bottom: tuple, border: tuple, tamil: str, english: str, ink: tuple, ink2: tuple,
             motif: str = "", strap: str = "") -> Cell:
    W = P * 2
    im = Image.new("RGB", (W, P), bg_top)
    d = ImageDraw.Draw(im)
    for y in range(P):
        t = y / (P - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(bg_top[i] + (bg_bottom[i] - bg_top[i]) * t) for i in range(3)))
    d.rectangle([0, 0, W - 1, P - 1], outline=(40, 40, 44), width=5 * S)
    d.rectangle([7 * S, 7 * S, W - 1 - 7 * S, P - 1 - 7 * S], outline=border, width=4 * S)
    tx0, tw = 26 * S, W - 52 * S
    if motif == "saree":
        for k in range(9):
            col = CLOTH[(k * 3) % len(CLOTH)]
            d.polygon([(W - (190 - k * 18) * S, 24 * S), (W - (174 - k * 18) * S, 24 * S), (W - (150 - k * 20) * S, P - 24 * S),
                       (W - (178 - k * 20) * S, P - 24 * S)], fill=col)
        tw = W - 250 * S
    elif motif == "necklace":
        for k in range(4):
            d.arc([W - 190 * S, (20 + k * 22) * S, W - 40 * S, (150 + k * 26) * S], 0, 180, fill=(250, 210, 90), width=5 * S)
            for a in range(0, 181, 20):
                ex = W - 115 * S + math.cos(math.radians(a)) * 75 * S
                ey = (85 + k * 24) * S + math.sin(math.radians(a)) * (65 + k * 2) * S
                d.ellipse([ex - 5 * S, ey - 5 * S, ex + 5 * S, ey + 5 * S], fill=(255, 236, 150))
        tw = W - 250 * S
    elif motif == "burst":
        cx, cy = W - 120 * S, P // 2
        pts = []
        for k in range(28):
            r = (96 if k % 2 == 0 else 70) * S
            pts.append((cx + math.cos(k * math.tau / 28) * r, cy + math.sin(k * math.tau / 28) * r))
        d.polygon(pts, fill=(250, 220, 30))
        f = font(46, "ExtraBold")
        d.text((cx, cy - 22 * S), "50%", font=f, fill=(200, 20, 30), anchor="mm")
        d.text((cx, cy + 26 * S), "OFF", font=font(30, "ExtraBold"), fill=(200, 20, 30), anchor="mm")
        tw = W - 270 * S
    elif motif == "flats":
        for k, (bx, bh) in enumerate(((60, 150), (112, 190), (164, 130))):
            x0 = W - (230 - bx) * S
            d.rectangle([x0, P - (bh + 20) * S, x0 + 44 * S, P - 20 * S], fill=(250, 250, 246))
            for wy in range(P - (bh + 8) * S, P - 34 * S, 18 * S):
                for wx in (6, 26):
                    d.rectangle([x0 + wx * S, wy, x0 + (wx + 12) * S, wy + 10 * S], fill=(60, 110, 150))
        tw = W - 260 * S
    elif motif == "plus":
        cx, cy = 86 * S, P // 2
        d.ellipse([cx - 62 * S, cy - 62 * S, cx + 62 * S, cy + 62 * S], fill=(250, 250, 250))
        d.rectangle([cx - 14 * S, cy - 44 * S, cx + 14 * S, cy + 44 * S], fill=(210, 30, 40))
        d.rectangle([cx - 44 * S, cy - 14 * S, cx + 44 * S, cy + 14 * S], fill=(210, 30, 40))
        tx0, tw = 170 * S, W - 196 * S
    elif motif == "rainbow":
        for k, col in enumerate([(230, 40, 50), (250, 150, 30), (250, 220, 40), (50, 170, 80), (40, 110, 200), (130, 60, 170)]):
            d.rectangle([W - (200 - k * 28) * S, 20 * S, W - (174 - k * 28) * S, P - 20 * S], fill=col)
        tw = W - 250 * S
    elif motif == "mandapam":
        for bx in (40, W // S - 60):                        # plantain trees either side of the arch
            d.rectangle([bx * S, 70 * S, (bx + 12) * S, P - 20 * S], fill=(120, 170, 70))
            for k in range(5):
                a = math.radians(-150 + k * 30)
                d.line([((bx + 6) * S, 74 * S), ((bx + 6) * S + math.cos(a) * 60 * S, 74 * S + math.sin(a) * 50 * S)], fill=(40, 140, 60), width=9 * S)
        tx0, tw = 110 * S, W - 220 * S
    cell = Cell()
    hh = P - 40 * S
    lines = [(tamil, 0.50, "ExtraBold", ink), (english, 0.24, "Bold", ink2)] + ([(strap, 0.16, "SemiBold", ink)] if strap else [])
    y = 24 * S
    for s, frac, weight, col in lines:
        box_h = hh * frac
        size = box_h / S
        while size > 6:
            f = font(size, weight)
            l, t, r, b = d.textbbox((0, 0), s, font=f)
            if (r - l) <= tw and (b - t) <= box_h:
                break
            size -= 1
        d.text((tx0 + (tw - (r - l)) / 2 - l, y + (box_h - (b - t)) / 2 - t), s, font=f, fill=col,
               stroke_width=int(size * 0.05 * S), stroke_fill=tuple(int(v * 0.3) for v in bg_bottom))
        y += box_h + 5 * S
    sq = im.resize((P, P), Image.LANCZOS)
    cell.im = Image.merge("RGBA", (*sq.split(), Image.new("L", (P, P), 0)))
    cell.d = ImageDraw.Draw(cell.im)
    cell.gl = sq.point(lambda v: int(v * 0.8))
    cell.g = ImageDraw.Draw(cell.gl)
    cell.streaks([(rng.uniform(10, C - 10), 0, rng.uniform(40, 160), 3.0, 0.12) for _ in range(5)], blur=3.0)
    return cell


HOARDINGS = [
    ((120, 16, 40), (70, 8, 26), (230, 186, 70), "பட்டு மாளிகை", "SILK SAREES", (250, 214, 110), (250, 246, 230), "saree", "கல்யாண பட்டு · ரெடிமேட்ஸ்"),
    ((30, 14, 16), (80, 12, 20), (236, 190, 70), "தங்க மாளிகை", "JEWELLERS", (250, 210, 90), (250, 246, 230), "necklace", "தங்கம் · வைரம் · வெள்ளி"),
    ((250, 200, 20), (240, 130, 20), (200, 20, 30), "ஆடி தள்ளுபடி", "AADI SALE", (190, 16, 30), (20, 40, 120), "burst", "ஃபர்னிச்சர் · டிவி · ஃப்ரிட்ஜ்"),
    ((250, 250, 246), (226, 232, 240), (20, 60, 150), "TNPSC பயிற்சி மையம்", "IAS · BANK · NEET COACHING", (190, 20, 30), (20, 60, 150), "", "புதிய வகுப்புகள் ஆரம்பம்"),
    ((250, 252, 250), (220, 240, 232), (20, 140, 90), "பல்நோக்கு மருத்துவமனை", "MULTI SPECIALITY HOSPITAL", (14, 110, 70), (200, 30, 40), "plus", "24 மணி நேர சேவை"),
    ((250, 220, 230), (250, 190, 90), (150, 20, 80), "திருமண மண்டபம்", "KALYANA MANDAPAM · A/C", (150, 16, 70), (90, 40, 10), "mandapam", ""),
    ((20, 90, 80), (10, 50, 60), (250, 220, 120), "வீடுகள் விற்பனைக்கு", "2 & 3 BHK FLATS FOR SALE", (250, 230, 150), (250, 250, 246), "flats", "உடனடி குடியேற்றம்"),
    ((250, 250, 250), (236, 236, 240), (40, 40, 44), "வண்ணங்கள்", "PAINTS & HARDWARES", (30, 60, 150), (200, 30, 40), "rainbow", "உங்கள் வீட்டுக்கு புது நிறம்"),
]


# --- row 7: roofs and institutions ----------------------------------------------------------------

def c_mangalore() -> Cell:
    c = Cell()
    c.im.paste((150, 70, 44, 0), [0, 0, P, P])
    rows, cols = 10, 12
    hh, ww = C / rows, C / cols
    for r in range(rows):
        for k in range(cols + 1):
            x = k * ww - (ww / 2 if r % 2 else 0)
            v = rng.uniform(0.82, 1.1)
            col = tuple(int(min(255, ch * v)) for ch in (176, 84, 52))
            c.d.pieslice(c.box(x, r * hh - hh * 0.2, x + ww, r * hh + hh * 1.5), 0, 180, fill=(*col, 0))
            c.d.arc(c.box(x, r * hh - hh * 0.2, x + ww, r * hh + hh * 1.5), 0, 180, fill=(96, 44, 28, 0), width=S)
        c.shade(0, r * hh - 1, C, r * hh + 4, 0.3, 1.5)
    c.blotches(14, 0.3, size=(14, 50))
    return c


def c_sheet() -> Cell:
    c = Cell()
    c.im.paste((226, 228, 230, 255), [0, 0, P, P])
    for gx in np.arange(0, C, 16):
        c.gradient(gx, 0, gx + 8, C, (246, 247, 248), (240, 241, 242), tint=True)
        c.rect(gx + 8, 0, gx + 16, C, (196, 198, 202), tint=True)
        c.rect(gx + 14.5, 0, gx + 16, C, (160, 162, 166), tint=True)
    for gy in (64, 192):                                 # sheet laps and J-bolts
        c.shade(0, gy, C, gy + 4, 0.3, 1.5)
        for gx in np.arange(4, C, 32):
            c.ellipse(gx - 2, gy - 8, gx + 2, gy - 4, (90, 90, 92), tint=True)
    c.streaks([(rng.uniform(0, C), rng.choice((0, 66, 194)), rng.uniform(30, 60), 3.0, 0.2) for _ in range(12)], blur=2.5)
    c.blotches(8, 0.14)
    return c


def c_weathering_tiles() -> Cell:
    """Terrace laid with clay weathering tiles, black with years of monsoon in the low spots."""
    c = Cell()
    c.im.paste((176, 96, 66, 0), [0, 0, P, P])
    n = 8
    t = C / n
    for r in range(n):
        for k in range(n):
            v = rng.uniform(0.84, 1.08)
            col = tuple(int(min(255, ch * v)) for ch in (186, 104, 72))
            c.rect(k * t + 1, r * t + 1, (k + 1) * t - 1, (r + 1) * t - 1, col)
    for k in range(n + 1):
        c.rect(k * t - 1, 0, k * t + 1, C, (150, 140, 128))
        c.rect(0, k * t - 1, C, k * t + 1, (150, 140, 128))
    c.blotches(18, 0.42, size=(18, 70))
    return c


def c_thatch() -> Cell:
    c = Cell()
    c.im.paste((150, 124, 80, 0), [0, 0, P, P])
    for _ in range(2600):
        x, y = rng.uniform(0, C), rng.uniform(0, C)
        v = rng.uniform(0.6, 1.15)
        c.line([(x, y), (x + rng.uniform(-3, 3), y + rng.uniform(10, 26))], tuple(int(min(255, ch * v)) for ch in (170, 140, 90)), 1.0)
    for gy in np.arange(0, C, 43):
        c.shade(0, gy, C, gy + 5, 0.34, 2.0)
    return c


def c_church() -> Cell:
    c = Cell()
    c.plaster(238, 0.8)
    c.weather(1.0)
    c.d.polygon([(96 * S, 214 * S), (96 * S, 96 * S), (128 * S, 36 * S), (160 * S, 96 * S), (160 * S, 214 * S)], fill=(206, 200, 186, 255))
    c.d.polygon([(104 * S, 206 * S), (104 * S, 100 * S), (128 * S, 54 * S), (152 * S, 100 * S), (152 * S, 206 * S)], fill=(40, 50, 90, 0))
    c.g.polygon([(104 * S, 206 * S), (104 * S, 100 * S), (128 * S, 54 * S), (152 * S, 100 * S), (152 * S, 206 * S)], fill=(250, 200, 120))
    for k, col in enumerate([(200, 40, 50), (240, 190, 40), (40, 110, 190), (50, 150, 90)]):   # stained glass
        c.rect(106 + (k % 2) * 23, 104 + (k // 2) * 50, 127 + (k % 2) * 23, 150 + (k // 2) * 50, col, glow=col)
    c.rect(126, 56, 130, 206, (30, 30, 34))
    c.rect(104, 150, 152, 154, (30, 30, 34))
    for px in (18, 224):
        c.rect(px, 0, px + 14, C, (244, 243, 238), tint=True)
        c.shade(px + 14, 0, px + 20, C, 0.14, 2.0)
    c.floor_band()
    return c


def c_mosque() -> Cell:
    c = Cell()
    c.plaster(240, 0.6)
    c.weather(0.6)
    green = (30, 120, 80)
    c.rect(0, 0, C, 16, green)
    c.rect(0, 232, C, 246, green)
    c.d.pieslice(c.box(78, 40, 178, 150), 180, 360, fill=(*green, 0))
    c.poly([(128, 22), (146, 50), (110, 50)], green)
    c.rect(78, 94, 178, 220, green)
    c.d.pieslice(c.box(88, 54, 168, 140), 180, 360, fill=(36, 46, 52, 0))
    c.rect(88, 96, 168, 220, (36, 46, 52), glow=(230, 220, 160))
    for gy in np.arange(100, 220, 12):                   # jaali in the arch
        for gx in np.arange(92, 166, 12):
            c.d.ellipse(c.box(gx, gy, gx + 8, gy + 8), outline=(230, 232, 226, 0), width=S)
    c.floor_band()
    return c


def c_school() -> Cell:
    c = Cell()
    c.plaster(238, 1.0)
    c.weather(1.0)
    c.shade(0, 150, C, 164, 0.25, 4.0)
    c.rect(0, 60, C, 68, (228, 227, 222), tint=True)     # continuous sunshade over the classroom windows
    for gx in (14, 98, 182):
        c.rect(gx - 3, 74, gx + 63, 160, (40, 92, 70))
        c.glass(gx, 77, gx + 60, 157, lit=False)
        c.rect(gx + 28, 77, gx + 32, 157, (40, 92, 70))
        c.grille(gx, 77, gx + 60, 157, "bars")
    c.streaks([(x, 68, rng.uniform(20, 60), 2.4, 0.26) for x in (6, 88, 170, 250)])
    c.floor_band()
    return c


def c_hospital() -> Cell:
    c = Cell()
    c.plaster(242, 0.5)
    c.weather(0.5)
    c.rect(0, 176, C, 196, (40, 120, 190))
    c.rect(0, 70, C, 160, ALU)
    for gx in np.arange(4, C, 63):
        c.glass(gx, 74, gx + 58, 156, lit=rng.random() < 0.7, tone=(70, 110, 130))
    c.rect(0, 62, C, 70, (232, 231, 226), tint=True)
    c.ac_unit(30, 204)
    c.ac_unit(170, 204)
    c.floor_band()
    return c


# === Assemble ======================================================================================

def build() -> tuple[Image.Image, Image.Image]:
    atlas = Image.new("RGBA", (C * COLS, C * ROWS), (*PLAIN, 255))
    glow = Image.new("RGB", (C * COLS, C * ROWS), (0, 0, 0))

    def put(col: int, row: int, cell: Cell) -> None:
        im, gl = cell.done()
        atlas.paste(im, (col * C, row * C))
        glow.paste(gl, (col * C, row * C))

    put(0, 0, c_window_grille())
    put(1, 0, c_balcony())
    put(2, 0, c_twin_windows())
    put(3, 0, c_ventilators())
    put(4, 0, c_sliding_ac())
    put(5, 0, c_office_glass())
    put(6, 0, c_office_strip())
    put(7, 0, c_plain())
    put(0, 1, c_house_ground())
    put(1, 1, c_compound_gate())
    put(2, 1, c_shutter_closed())
    for i, (ta, en, bc, trade) in enumerate(SHOPS):
        col, row = (3 + i, 1) if i < 5 else (i - 5, 2)
        put(col, row, shop(ta, en, BOARD_COLOURS[bc], trade))
    put(0, 3, c_kaavi(False))
    put(1, 3, c_kaavi(True))
    put(2, 3, c_terrace(False))
    put(3, 3, c_terrace(True))
    put(4, 3, c_heritage_window())
    put(5, 3, c_thinnai())
    put(6, 3, c_civic(False))
    put(7, 3, c_civic(True))
    put(0, 4, c_balcony(washing=True))
    put(1, 4, c_box_grille())
    put(2, 4, c_jaali())
    put(3, 4, c_party_wall())
    put(4, 4, c_wall_advert())
    put(5, 4, c_cladding())
    put(6, 4, c_showroom_glass())
    put(7, 4, c_tenement())
    put(0, 5, stilt(False))
    put(1, 5, stilt(True))
    put(2, 5, c_portico())
    put(3, 5, showroom_front("silk"))
    put(4, 5, showroom_front("jewel"))
    put(5, 5, c_bank())
    put(6, 5, c_clinic())
    put(7, 5, c_small_door())
    for i, spec in enumerate(HOARDINGS):
        put(i, 6, hoarding(*spec))
    put(0, 7, c_mangalore())
    put(1, 7, c_sheet())
    put(2, 7, c_weathering_tiles())
    put(3, 7, c_thatch())
    put(4, 7, c_church())
    put(5, 7, c_mosque())
    put(6, 7, c_school())
    put(7, 7, c_hospital())
    return atlas, glow


if __name__ == "__main__":
    atlas, glow = build()
    OUT.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT / "facade_atlas.png", optimize=True)
    # Night light is a hint, not a floodlight: the shader adds this on top of the lit albedo.
    glow = glow.point(lambda v: int(v * 0.8))
    glow.resize((glow.width // 2, glow.height // 2), Image.LANCZOS).save(OUT / "facade_glow.png", optimize=True)
    print("wrote", OUT / "facade_atlas.png", atlas.size, "and facade_glow.png")
