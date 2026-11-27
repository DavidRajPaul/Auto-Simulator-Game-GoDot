#!/usr/bin/env python3
"""Builds the roadside fruit push-cart (thallu vandi) as four painted liveries:
assets/models/city/shops/fruit_cart_<a..d>.glb.

Nov 27 owner report: "the fruit stall can be realistic". The old carts were a 5k-triangle Tripo
model squeezed to a flat palette: the fruit read as coloured lumps. This one is modelled the way a
Chennai fruit cart is put together: a wooden bed on four spoked bicycle wheels with push handles
and a prop leg, a striped cloth canopy on bamboo poles, and on the bed what sells: pyramids of
mosambi, apples, pomegranates and sapota on plastic sheets, grapes in bunches, a cut watermelon
and papaya, pineapples, banana bunches hanging from the canopy rail, a hanging pan scale, small
price slates and a painted name board (the sign texture from bake_street_shops.sign_image).

One vertex-coloured primitive (+ the sign quad), no other texture; ~4k triangles. The game draws
it like the old carts (WorldChunkStreamer street shops, front -Z = road side, 75 m view range).
Usage: python3 tools/art/make_fruit_cart.py
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
import trimesh

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "assets"))
import make_chennai_vehicles as V  # noqa: E402
from bake_street_shops import FRUIT_LIVERIES, SHOPS, _rgb, coloured, export, sign_image, sign_quad  # noqa: E402

WOOD = (120, 78, 44)
WOOD_DARK = (84, 54, 30)
BAMBOO = (178, 152, 92)
SHEET = (40, 110, 60)          # green plastic sheet under the fruit
MOSAMBI = (150, 178, 60)
ORANGE = (236, 140, 30)
APPLE = (186, 28, 36)
POMEGRANATE = (150, 24, 40)
SAPOTA = (122, 84, 52)
GRAPE = (96, 140, 40)
GRAPE_BLACK = (60, 30, 70)
BANANA = (236, 200, 50)
MELON_RIND = (40, 110, 40)
MELON_FLESH = (226, 50, 60)
PAPAYA_SKIN = (210, 150, 40)
PAPAYA_FLESH = (240, 120, 40)
PINE = (190, 140, 50)
PINE_TOP = (60, 120, 50)
SLATE = (36, 40, 38)
CLOTH_WHITE = (240, 234, 216)


def hexc(h: str):
    r, g, b = _rgb(h)
    return (int(r), int(g), int(b))


def ball(m: V.Mesh, x: float, y: float, z: float, r: float, col, seg: int = 5) -> None:
    m.blob([(x, y - r * 0.8, z, r * 0.55, r * 0.55), (x, y, z, r, r), (x, y + r * 0.8, z, r * 0.55, r * 0.55)], col, seg)


def jitter(col, rng, amount: int = 14):
    return tuple(int(max(0, min(255, c + rng.integers(-amount, amount + 1)))) for c in col)


def pyramid(m: V.Mesh, cx: float, y: float, cz: float, n: int, r: float, col, rng) -> None:
    """Fruit stacked the way vendors stack them: an n x n base, each layer sits in the hollows."""
    for layer in range(n):
        k = n - layer
        for i in range(k):
            for j in range(k):
                x = cx + (i - (k - 1) * 0.5) * r * 2.0
                z = cz + (j - (k - 1) * 0.5) * r * 2.0
                ball(m, x, y + r + layer * r * 1.45, z, r * rng.uniform(0.92, 1.05), jitter(col, rng), 5)


def bunch(m: V.Mesh, x: float, y: float, z: float, col, rng, n: int = 10, r: float = 0.019) -> None:
    """Grapes: small berries in a cone hanging under a stalk."""
    for k in range(n):
        layer = k // 5
        a = k * 2.4
        rr = (0.045 - layer * 0.012)
        ball(m, x + math.cos(a) * rr, y - layer * 0.03, z + math.sin(a) * rr, r, jitter(col, rng, 10), 3)


def banana_bunch(m: V.Mesh, x: float, y: float, z: float, rng) -> None:
    m.tube((x, y + 0.1, z), (x, y - 0.42, z), 0.02, (90, 80, 40), 5)
    for tier in range(3):
        ty = y - 0.04 - tier * 0.12
        for k in range(5):
            a = 2 * math.pi * k / 5 + tier * 0.5
            d = (math.cos(a), math.sin(a))
            p0 = (x + d[0] * 0.03, ty, z + d[1] * 0.03)
            p1 = (x + d[0] * 0.13, ty + 0.07, z + d[1] * 0.13)
            m.tube(p0, p1, 0.022, jitter(BANANA, rng, 10), 4)


def pineapple(m: V.Mesh, x: float, y: float, z: float) -> None:
    m.blob([(x, y, z, 0.04, 0.04), (x, y + 0.06, z, 0.075, 0.075), (x, y + 0.16, z, 0.07, 0.07), (x, y + 0.21, z, 0.04, 0.04)], PINE, 8)
    for k in range(6):
        a = 2 * math.pi * k / 6
        m.tube((x, y + 0.2, z), (x + math.cos(a) * 0.05, y + 0.32, z + math.sin(a) * 0.05), 0.012, PINE_TOP, 3)


def build(liv: dict) -> V.Mesh:
    rng = np.random.default_rng(42)
    m = V.Mesh()
    body = hexc(liv["body"])
    stripe = hexc(liv["stripe"])
    L, W = 1.72, 1.08          # length (z) and width (x); road side is +x before the turn
    bed_y = 0.78
    # Four spoked cycle wheels on two axles, the bed on top, push handles and a prop leg.
    r = 0.29
    for z in (-0.55, 0.55):
        for x in (-0.5, 0.5):
            V._tyre(m, z, r, 0.02, V.CHROME, x, 12)
            for i in range(6):
                a = math.pi * i / 6
                m.tube((x, r - math.sin(a) * r * 0.76, z - math.cos(a) * r * 0.76), (x, r + math.sin(a) * r * 0.76, z + math.cos(a) * r * 0.76), 0.004, V.CHROME, 3)
        m.tube((-0.52, r, z), (0.52, r, z), 0.018, V.ENGINE, 6)
    m.box((-W / 2, bed_y - 0.05, -L / 2), (W / 2, bed_y, L / 2), WOOD)
    for x in (-W / 2, W / 2):
        m.box((x - 0.02, bed_y - 0.2, -L / 2), (x + 0.02, bed_y - 0.05, L / 2), body)        # painted skirt
        m.box((x - 0.02, bed_y, -L / 2), (x + 0.02, bed_y + 0.08, L / 2), WOOD_DARK)        # side lip
    for z in (-L / 2, L / 2):
        m.box((-W / 2, bed_y - 0.2, z - 0.02), (W / 2, bed_y - 0.05, z + 0.02), body)
        m.box((-W / 2, bed_y, z - 0.02), (W / 2, bed_y + 0.08, z + 0.02), WOOD_DARK)
    m.box((-W / 2 + 0.02, bed_y - 0.17, -L / 2 + 0.02), (W / 2 - 0.02, bed_y - 0.14, L / 2 - 0.02), CLOTH_WHITE)   # painted band
    for x in (-0.3, 0.3):
        m.tube((x, bed_y - 0.06, -L / 2), (x * 1.15, bed_y + 0.06, -L / 2 - 0.42), 0.02, WOOD, 6)
        m.tube((x * 1.15, bed_y + 0.06, -L / 2 - 0.42), (x * 1.15, bed_y + 0.06, -L / 2 - 0.55), 0.024, (30, 30, 30), 6, caps=True)
    m.tube((0, bed_y - 0.06, -L / 2 + 0.1), (0, 0.0, -L / 2 + 0.05), 0.02, WOOD_DARK, 5)
    # Plastic sheet and the fruit: pyramids at the front, bunches and cut fruit behind.
    m.box((-W / 2 + 0.04, bed_y + 0.002, -L / 2 + 0.04), (W / 2 - 0.04, bed_y + 0.012, L / 2 - 0.04), SHEET)
    y0 = bed_y + 0.012
    pyramid(m, 0.27, y0, -0.5, 3, 0.04, MOSAMBI, rng)
    pyramid(m, 0.27, y0, -0.1, 3, 0.04, APPLE, rng)
    pyramid(m, 0.27, y0, 0.3, 3, 0.042, ORANGE, rng)
    pyramid(m, 0.27, y0, 0.66, 2, 0.04, POMEGRANATE, rng)
    pyramid(m, -0.12, y0, -0.55, 3, 0.03, SAPOTA, rng)
    for z in (-0.22, -0.02):
        bunch(m, -0.12, y0 + 0.08, z, GRAPE, rng)
    bunch(m, -0.02, y0 + 0.08, -0.12, GRAPE_BLACK, rng)
    # A watermelon and a papaya, cut open to show the flesh.
    m.blob([(-0.18, y0 + 0.02, 0.25, 0.1, 0.07), (-0.18, y0 + 0.12, 0.33, 0.15, 0.12), (-0.18, y0 + 0.12, 0.47, 0.15, 0.12), (-0.18, y0 + 0.05, 0.57, 0.08, 0.06)], MELON_RIND, 10)
    m.blob([(-0.38, y0 + 0.002, 0.35, 0.02, 0.01), (-0.38, y0 + 0.09, 0.41, 0.012, 0.1), (-0.38, y0 + 0.09, 0.47, 0.012, 0.1)], MELON_FLESH, 8)
    m.blob([(-0.35, y0 + 0.05, 0.6, 0.06, 0.05), (-0.35, y0 + 0.07, 0.7, 0.07, 0.065), (-0.35, y0 + 0.05, 0.8, 0.045, 0.04)], PAPAYA_SKIN, 8)
    m.box((-0.38, y0, 0.55), (-0.32, y0 + 0.02, 0.66), PAPAYA_FLESH)
    for z in (0.05, 0.2):
        pineapple(m, -0.4, y0, z)
    # Price slates stuck in the heaps (no text).
    for (x, z) in ((0.45, -0.5), (0.45, -0.1), (0.45, 0.3)):
        m.box((x - 0.002, y0 + 0.12, z - 0.06), (x + 0.004, y0 + 0.2, z + 0.06), SLATE)
        m.tube((x, y0, z), (x, y0 + 0.12, z), 0.004, WOOD, 3)
    # Bamboo poles and a striped cloth canopy that sags a little and overhangs the road side.
    top = 2.0
    for z in (-L / 2 + 0.05, L / 2 - 0.05):
        for x in (-W / 2 + 0.03, W / 2 - 0.03):
            m.tube((x, bed_y, z), (x, top - (0.12 if x > 0 else 0.0), z), 0.022, BAMBOO, 6)
    m.tube((W / 2 - 0.03, top - 0.12, -L / 2), (W / 2 - 0.03, top - 0.12, L / 2), 0.018, BAMBOO, 5)
    nz, nx = 8, 4
    for i in range(nz):
        for j in range(nx):
            def p(ii: int, jj: int):
                z = -L / 2 - 0.08 + (L + 0.16) * ii / nz
                xx = -W / 2 - 0.05 + (W + 0.4) * jj / nx
                sag = 0.06 * math.sin(math.pi * ii / nz) * math.sin(math.pi * jj / nx)
                return (xx, top - 0.16 * (xx + W / 2) / W - sag, z)
            col = stripe if i % 2 == 0 else CLOTH_WHITE
            a, b, c, d = p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)
            m.quad(a, b, c, d, col, (0, 1, 0))
            m.quad(a, b, c, d, col, (0, -1, 0))
    # Scalloped valance on the road side.
    for i in range(nz):
        z0 = -L / 2 - 0.08 + (L + 0.16) * i / nz
        z1 = z0 + (L + 0.16) / nz
        xv = W / 2 + 0.35
        yv = top - 0.16 * (xv + W / 2) / W
        col = stripe if i % 2 == 0 else CLOTH_WHITE
        for side in (1, -1):
            m.quad((xv, yv, z0), (xv, yv, z1), (xv, yv - 0.12, (z0 + z1) * 0.5 + 0.03), (xv, yv - 0.16, (z0 + z1) * 0.5), col, (side, 0, 0))
    # Hanging from the rail: banana bunches and a pan scale.
    for z in (-0.6, 0.55):
        banana_bunch(m, W / 2 - 0.08, top - 0.2, z, rng)
    sx, sy, sz = W / 2 - 0.2, top - 0.2, 0.0
    m.tube((sx, sy, sz), (sx, sy - 0.25, sz), 0.004, V.CHROME, 3)
    m.box((sx - 0.01, sy - 0.26, sz - 0.24), (sx + 0.01, sy - 0.24, sz + 0.24), V.CHROME)
    for dz in (-0.22, 0.22):
        m.tube((sx, sy - 0.25, sz + dz), (sx, sy - 0.52, sz + dz), 0.003, V.CHROME, 3)
        m.blob([(sx, sy - 0.55, sz + dz, 0.11, 0.11), (sx, sy - 0.52, sz + dz, 0.12, 0.12)], V.CHROME, 10)
    # Name board on the road side of the canopy (painted; the sign quad goes on its face).
    board = hexc(liv["board"])
    m.box((W / 2 + 0.33, top - 0.36, -0.55), (W / 2 + 0.36, top - 0.18, 0.55), board)
    return m


def to_trimesh(m: V.Mesh) -> tuple[trimesh.Trimesh, np.ndarray]:
    pos = np.array(m.p, dtype=float).reshape(-1, 3, 3)
    cols = np.array(m.c, dtype=float)[::3, :3]
    t = trimesh.Trimesh(pos.reshape(-1, 3), np.arange(len(pos) * 3).reshape(-1, 3), process=False)
    return t, cols


def main() -> None:
    for v, liv in FRUIT_LIVERIES.items():
        mesh = build(liv)
        cart, cols = to_trimesh(mesh)
        # Road side +X -> -Z (the game's shop front), centred on the footprint, on y = 0.
        rot = trimesh.transformations.rotation_matrix(math.pi * 0.5, [0, 1, 0])
        cart.apply_transform(rot)
        lo, hi = cart.bounds
        shift = np.eye(4)
        shift[:3, 3] = [-(lo[0] + hi[0]) * 0.5, -lo[1], -(lo[2] + hi[2]) * 0.5]
        cart.apply_transform(shift)
        xf = shift @ rot
        # Sign: the outer face of the name board (x = W/2 + 0.36 before the turn).
        W, top = 1.08, 2.0
        corners = np.array([[W / 2 + 0.365, top - 0.355, 0.54], [W / 2 + 0.365, top - 0.355, -0.54],
                            [W / 2 + 0.365, top - 0.185, -0.54], [W / 2 + 0.365, top - 0.185, 0.54]])
        sc = trimesh.transform_points(corners, xf)
        img = sign_image(*liv["sign"], (512, 80))
        out = export({"cart": coloured(cart, cols), "sign": sign_quad(sc, img)}, SHOPS / f"fruit_cart_{v}.glb")
        size = cart.bounds[1] - cart.bounds[0]
        print(f"fruit_cart_{v}: {len(cart.faces)} tris, {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} m", out if isinstance(out, dict) else "")


if __name__ == "__main__":
    main()
