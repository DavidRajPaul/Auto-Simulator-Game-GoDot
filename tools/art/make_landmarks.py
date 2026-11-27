#!/usr/bin/env python3
"""Procedural heritage landmarks: San Thome Basilica, the Kapaleeshwarar temple and Senate House.

Nov 27 owner report (with photos): the game drew the basilica's footprint as a temple (red and
white kaavi stripes, which belong to Hindu temples only) and the Kapaleeshwarar gopuram as a
generic stepped box. These are built from the owner's photos and published facts:

* San Thome Basilica (Wikipedia; rebuilt 1893-96 in neo-Gothic by Capt. J. A. Power): 64 m long,
  12.2 m wide, nave 10 m, spire 47.2 m (155 ft). White walls, deep red-brown lancet windows,
  terracotta tiled roofs, pinnacles on every buttress and corner, red cross on the spire. The
  tower stands SOUTH of the nave's west gable (photos; "on the left side of the entrance"), and a
  small second spire over the centre marks the tomb. Built on the real OSM footprint.
* Kapaleeshwarar Temple (Wikipedia, TN Temples Project): seven-tier east rajagopuram of 1906,
  ~37-40 m (120 ft), covered in painted stucco figures, crowned by a barrel vault with a row of
  golden kalasams and Nandi bulls at the corners; a smaller west gopuram faces the tank; the
  sanctum faces west; Karpagambal's shrine; a golden flagstaff; flat-roofed mandapams with figure
  parapets; kaavi-striped walls; the tank's 16-pillared neerazhi mandapam.

Each model is ONE vertex-coloured mesh (one draw call), local +x = east along the main axis,
+z = south, y up, origin on the ground. Output:
    assets/models/landmarks/<name>.glb
    data/world/landmark_models.json   placements (world x, z, yaw), collider boxes, clear areas
Usage: python3 tools/art/make_landmarks.py [--only santhome,...] [--preview DIR]
"""
from __future__ import annotations

import argparse
import json
import math
import random

import mapbox_earcut as earcut
import numpy as np
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from landmark_geo import LM, arch, circle, offset, shade  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "landmarks"
PLACEMENTS = ROOT / "data" / "world" / "landmark_models.json"

# ---------------------------------------------------------------- San Thome palette
WHITE = (240, 239, 233)
WHITE_SH = (218, 217, 210)
TRIM = (248, 247, 243)
PLINTH = (186, 184, 177)
RED_WIN = (158, 50, 40)
RED_DEEP = (118, 36, 30)
ROOF = (172, 86, 58)
ROOF2 = (156, 76, 51)
ROOF_RIDGE = (128, 60, 42)
CROSS_RED = (168, 26, 32)
DOOR = (88, 50, 36)
IRON = (28, 28, 30)


# ================================================================= shared Gothic parts

def lancet(m: LM, x: float, y0: float, w: float, spring: float, rise=None, col=RED_WIN,
           frame: float = 0.16, depth: float = 0.14, kind: str = "pointed", hood: bool = True) -> None:
    """A pointed (or round) window in the wall plane z = 0, facing +z: dark fill + white surround."""
    inner = arch(w, y0, spring, kind, n=6, rise=rise)
    outer = offset(inner, frame)
    m.push((x, 0.0, 0.0))
    m.flat(inner, 0.015, col)
    m.extrude(outer, 0.0, depth, TRIM, back=False, holes=[inner])
    if hood:
        # Drip-stone hood over the arch.
        top = [p for p in outer if p[1] >= spring - 0.01]
        top.sort(key=lambda p: p[0])
        for a, b in zip(top, top[1:]):
            m.bar((a[0], a[1] + 0.06, depth + 0.02), (b[0], b[1] + 0.06, depth + 0.02), 0.07, TRIM, 4)
    m.pop()


def rose(m: LM, x: float, y: float, r: float, col=RED_WIN) -> None:
    inner = circle(r, 0.0, y, 14)
    outer = circle(r + 0.22, 0.0, y, 14)
    m.push((x, 0.0, 0.0))
    m.flat(inner, 0.015, col)
    m.extrude(outer, 0.0, 0.16, TRIM, back=False, holes=[inner])
    # Tracery spokes.
    for k in range(6):
        a = math.pi * k / 6
        m.bar((-math.cos(a) * r, y - math.sin(a) * r, 0.06), (math.cos(a) * r, y + math.sin(a) * r, 0.06), 0.045, TRIM, 4)
    m.pop()


def pinnacle(m: LM, x: float, y0: float, z: float, r: float, shaft: float, cap: float,
             col=WHITE, cross: bool = False, gablets: bool = True) -> None:
    rot = math.pi / 8
    m.prism(8, r, r, y0, y0 + shaft, col, top=False, rot=rot, cx=x, cz=z)
    yc = y0 + shaft
    m.prism(8, r * 1.28, r * 1.28, yc, yc + 0.14, TRIM, top=True, bottom=True, rot=rot, cx=x, cz=z)
    if gablets and shaft > 1.2:
        # Little gables round the top of the shaft (the crocketed look of the photos).
        for k in range(4):
            a = k * math.pi / 2
            cx, cz = x + math.cos(a) * r * 0.98, z + math.sin(a) * r * 0.98
            m.push((cx, 0.0, cz), yaw=math.atan2(math.cos(a), math.sin(a)))
            g = r * 0.75
            m.extrude([(-g, yc - g * 1.1), (g, yc - g * 1.1), (0.0, yc + g * 0.9)], -0.05, 0.06, TRIM, back=False)
            m.pop()
    m.prism(8, r * 1.1, 0.0, yc + 0.14, yc + 0.14 + cap, col, rot=rot, cx=x, cz=z)
    top = yc + 0.14 + cap
    m.prism(6, r * 0.32, 0.0, top - cap * 0.12, top + r * 0.55, TRIM, rot=0.0, cx=x, cz=z)
    if cross:
        c = r * 1.3
        m.cbox((x, top + c * 0.9, z), (0.09, c * 1.6, 0.09), CROSS_RED)
        m.cbox((x, top + c * 1.15, z), (c * 0.9, 0.09, 0.09), CROSS_RED)


def cross(m: LM, x: float, y: float, z: float, h: float, col=CROSS_RED, yaw: float = 0.0) -> None:
    m.push((x, y, z), yaw=yaw)
    t = h * 0.075
    m.cbox((0.0, h * 0.5, 0.0), (t, h, t), col)
    m.cbox((0.0, h * 0.68, 0.0), (h * 0.55, t, t), col)
    m.pop()


def wall_frame(m: LM, face: str, x: float, z: float, y: float = 0.0) -> None:
    """Push a frame on a wall: local +x along the wall, +z out of it. face = -x, +x, -z, +z."""
    yaw = {"+z": 0.0, "-z": math.pi, "+x": math.pi / 2, "-x": -math.pi / 2}[face]
    m.push((x, y, z), yaw=yaw)


def gable_roof(m: LM, x0: float, x1: float, cz: float, half: float, y_eave: float, y_ridge: float,
               over: float = 0.4, strips: int = 7, col=ROOF, col2=ROOF2) -> None:
    """Pitched roof, ridge along x. Banded strips read as tile courses."""
    slope = (y_ridge - y_eave) / half
    for side in (-1.0, 1.0):
        z_e = cz + side * (half + over)
        y_e = y_eave - over * slope
        for k in range(strips):
            t0, t1 = k / strips, (k + 1) / strips
            za, ya = z_e + (cz - z_e) * t0, y_e + (y_ridge - y_e) * t0
            zb, yb = z_e + (cz - z_e) * t1, y_e + (y_ridge - y_e) * t1
            c = col if k % 2 == 0 else col2
            m.quad((x0 - over * 0.5, ya, za), (x1 + over * 0.5, ya, za), (x1 + over * 0.5, yb, zb), (x0 - over * 0.5, yb, zb),
                   c, (0, 1, side * slope))
        # Underside, so the eave never looks paper-thin from the street.
        m.quad((x0 - over * 0.5, y_e - 0.12, z_e), (x1 + over * 0.5, y_e - 0.12, z_e),
               (x1 + over * 0.5, y_eave - 0.12, cz + side * half), (x0 - over * 0.5, y_eave - 0.12, cz + side * half),
               ROOF_RIDGE, (0, -1, 0))
        m.quad((x0 - over * 0.5, y_e - 0.12, z_e), (x1 + over * 0.5, y_e - 0.12, z_e),
               (x1 + over * 0.5, y_e, z_e), (x0 - over * 0.5, y_e, z_e), ROOF_RIDGE, (0, 0, side))
    m.bar((x0 - over * 0.5, y_ridge + 0.05, cz), (x1 + over * 0.5, y_ridge + 0.05, cz), 0.13, ROOF_RIDGE, 4)


def gable_end(m: LM, face: str, x: float, cz: float, half: float, y_eave: float, y_apex: float,
              col=WHITE, coping: bool = True) -> None:
    """Triangular wall over the eaves on a wall facing +x or -x; local x runs along z."""
    sgn = 1.0 if face == "+x" else -1.0
    wall_frame(m, face, x, cz)
    lx = lambda zz: (zz - cz) * (-sgn)  # noqa: E731  local x for a world z on this face
    del lx
    m.extrude([(-half, y_eave), (half, y_eave), (0.0, y_apex)], -0.5, 0.0, col, back=False)
    if coping:
        for s in (-1.0, 1.0):
            m.bar((s * (half + 0.15), y_eave - 0.05, 0.05), (0.0, y_apex + 0.2, 0.05), 0.16, TRIM, 4)
    m.pop()


def walls(m: LM, plan, y0: float, y1: float, col, top_col=None) -> None:
    """Vertical walls round a closed plan polygon [(x, z)] (counter-clockwise seen from above
    or not: the hint is taken from the centroid) + flat top."""
    n = len(plan)
    cx = sum(p[0] for p in plan) / n
    cz = sum(p[1] for p in plan) / n
    for i in range(n):
        a, b = plan[i], plan[(i + 1) % n]
        mx, mz = (a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cz
        ex, ez = b[0] - a[0], b[1] - a[1]
        nx, nz = ez, -ex
        if nx * mx + nz * mz < 0:
            nx, nz = -nx, -nz
        m.quad((a[0], y0, a[1]), (b[0], y0, b[1]), (b[0], y1, b[1]), (a[0], y1, a[1]), col, (nx, 0, nz))
    if top_col is not None:
        for i in range(1, n - 1):
            m.tri((plan[0][0], y1, plan[0][1]), (plan[i][0], y1, plan[i][1]), (plan[i + 1][0], y1, plan[i + 1][1]), top_col, (0, 1, 0))


def course(m: LM, x0: float, x1: float, z0: float, z1: float, y: float, h: float = 0.22, out: float = 0.12, col=TRIM) -> None:
    """A string course / cornice band round a rectangle."""
    m.ybox(x0 - out, x1 + out, y, y + h, z0 - out, z1 + out, col, skip="-y")


# ================================================================= San Thome Basilica

# Local frame from the OSM way 1115403900: x along the nave (east), z across (south), origin at
# the west front on the nave's centre line. Axis bearing 14.2 deg south of east.
SANTHOME_ORIGIN = (2004.674, 1693.183)
SANTHOME_AXIS_DEG = 14.2

NAVE_HALF = 6.1       # nave walls (12.2 m wide)
AISLE_OUT = 9.2       # aisle outer walls (footprint 18.4 m)
NAVE_EAVE = 12.8
NAVE_RIDGE = 19.0
AISLE_EAVE = 7.2
AISLE_TOP = 9.7       # lean-to roof meets the nave wall
BAY = 4.6
TOWER_C = (8.1, 10.3)
TOWER_W = 7.0


def santhome() -> LM:
    m = LM()
    _st_west_front(m)
    _st_nave(m)
    _st_east(m)
    _st_tower(m)
    _st_fleche(m, 50.0)
    return m


def _st_west_front(m: LM) -> None:
    """The west gable block: three doors, three lancets, a rose, corner turrets, cross on top."""
    z0, z1, x0, x1 = -7.6, 6.8, 0.0, 3.9
    cz = (z0 + z1) / 2
    half = (z1 - z0) / 2
    m.ybox(x0 - 0.25, x1, 0.0, 0.5, z0 - 0.25, z1 + 0.25, PLINTH)
    m.ybox(x0, x1, 0.5, 11.5, z0, z1, WHITE, skip="-y")
    m.collider(((x0 + x1) / 2, 6.0, cz), (x1 - x0, 12.0, z1 - z0))
    course(m, x0, x1, z0, z1, 6.0, 0.24, 0.1)
    course(m, x0, x1, z0, z1, 11.3, 0.3, 0.16)
    gable_end(m, "-x", x0, cz, half, 11.5, 19.2)
    # Front openings (face -x: local x runs from z1 to z0, so local x = cz - z ... use frame).
    wall_frame(m, "-x", x0, cz)
    for lx, w, spring in ((0.0, 2.5, 3.8), (-4.3, 1.8, 3.1), (4.3, 1.8, 3.1)):
        lancet(m, lx, 0.5, w, spring, col=DOOR, frame=0.22, depth=0.22)
    for lx, w, spring in ((0.0, 1.35, 10.0), (-3.2, 1.2, 9.4), (3.2, 1.2, 9.4)):
        lancet(m, lx, 6.7, w, spring)
    rose(m, 0.0, 14.1, 1.05)
    # Gable-side blind arcading (three small lancets under the coping).
    for lx in (-2.6, 2.6):
        lancet(m, lx, 12.3, 0.55, 13.3, frame=0.1, depth=0.08, hood=False)
    m.pop()
    cross(m, x0 - 0.05, 19.25, cz, 2.1)
    # Corner turrets: octagonal shafts rising above the eaves into pinnacles with crosses.
    for z in (z0 + 0.35, z1 - 0.35):
        m.prism(8, 0.78, 0.78, 0.5, 15.0, WHITE, top=False, rot=math.pi / 8, cx=x0 + 0.35, cz=z)
        for y in (6.0, 11.3):
            m.prism(8, 0.92, 0.92, y, y + 0.25, TRIM, top=True, bottom=True, rot=math.pi / 8, cx=x0 + 0.35, cz=z)
        pinnacle(m, x0 + 0.35, 15.0, z, 0.62, 0.9, 3.0, cross=True)
    # Back corners of the block get small pinnacles over the aisle roofs.
    for z in (z0 + 0.3, z1 - 0.3):
        pinnacle(m, x1 - 0.3, 11.5, z, 0.32, 0.9, 1.6)


def _st_nave(m: LM) -> None:
    x0, x1 = 3.9, 62.0
    # Clerestory walls and roof.
    m.ybox(x0, x1, 0.0, NAVE_EAVE, -NAVE_HALF, NAVE_HALF, WHITE, skip="-y-x")
    m.collider(((x0 + x1) / 2, NAVE_EAVE / 2, 0.0), (x1 - x0, NAVE_EAVE, NAVE_HALF * 2))
    course(m, x0, x1, -NAVE_HALF, NAVE_HALF, NAVE_EAVE - 0.3, 0.3, 0.15)
    gable_roof(m, x0, x1, 0.0, NAVE_HALF, NAVE_EAVE, NAVE_RIDGE)
    # Clerestory windows: a pair per bay above the aisle roofs.
    xb = x0
    bays = []
    while xb + BAY <= 47.6:
        bays.append(xb + BAY / 2)
        xb += BAY
    for side, face in ((-1.0, "-z"), (1.0, "+z")):
        for bx in bays:
            wall_frame(m, face, bx, side * NAVE_HALF)
            for d in (-0.75, 0.75):
                lancet(m, d, 10.0, 0.62, 11.6, frame=0.12, depth=0.1, hood=False)
            m.pop()
    # Aisles: north from the front block, south from behind the tower; both run to the wings.
    for side, xa in ((-1.0, x0), (1.0, TOWER_C[0] + TOWER_W / 2)):
        xe = 47.5
        zi, zo = side * NAVE_HALF, side * AISLE_OUT
        m.ybox(xa, xe, 0.0, AISLE_EAVE, min(zi, zo), max(zi, zo), WHITE, skip="-y+y")
        m.collider(((xa + xe) / 2, AISLE_EAVE / 2, (zi + zo) / 2), (xe - xa, AISLE_EAVE, abs(zo - zi)))
        m.ybox(xa - 0.2, xe, 0.0, 0.5, min(zi, zo) - (0.25 if side < 0 else 0), max(zi, zo) + (0.25 if side > 0 else 0), PLINTH)
        # Lean-to roof.
        over = 0.4
        slope = (AISLE_TOP - AISLE_EAVE) / (AISLE_OUT - NAVE_HALF)
        strips = 4
        for k in range(strips):
            t0, t1 = k / strips, (k + 1) / strips
            za = zo + side * over + (zi - zo - side * over) * t0
            zb = zo + side * over + (zi - zo - side * over) * t1
            ya = AISLE_EAVE - over * slope + (AISLE_TOP - AISLE_EAVE + over * slope) * t0
            yb = AISLE_EAVE - over * slope + (AISLE_TOP - AISLE_EAVE + over * slope) * t1
            m.quad((xa, ya, za), (xe, ya, za), (xe, yb, zb), (xa, yb, zb), ROOF if k % 2 == 0 else ROOF2, (0, 1, side * slope))
        # Parapet band along the eaves.
        m.ybox(xa, xe, AISLE_EAVE - 0.35, AISLE_EAVE + 0.15, zo - side * 0.1 - 0.12, zo + side * 0.25 + 0.12, TRIM)
        face = "+z" if side > 0 else "-z"
        bx = xa
        k = 0
        while bx <= xe + 0.01:
            # Buttress + pinnacle at every bay line.
            bz = zo + side * 0.45
            m.ybox(bx - 0.38, bx + 0.38, 0.0, AISLE_EAVE - 1.2, bz - 0.5, bz + 0.5, WHITE)
            m.prism(4, 0.54, 0.35, AISLE_EAVE - 1.2, AISLE_EAVE - 0.4, WHITE_SH, top=True, rot=math.pi / 4, cx=bx, cz=bz - side * 0.05)
            pinnacle(m, bx, AISLE_EAVE - 0.4, bz - side * 0.1, 0.3, 1.7, 1.7, gablets=False)
            if bx + BAY <= xe + 0.01:
                wall_frame(m, face, bx + BAY / 2, zo)
                lancet(m, 0.0, 1.6, 1.15, 4.9)
                m.pop()
            bx += BAY
            k += 1
    # North porch (the small block on the footprint's north-west corner).
    m.ybox(4.7, 11.8, 0.0, 7.8, -10.8, -AISLE_OUT, WHITE)
    m.collider((8.25, 3.9, -10.0), (7.1, 7.8, 1.6))
    course(m, 4.7, 11.8, -10.8, -AISLE_OUT, 7.6, 0.3, 0.12)
    wall_frame(m, "-z", 8.25, -10.8)
    lancet(m, 0.0, 0.5, 1.6, 2.9, col=DOOR, frame=0.18, depth=0.18)
    lancet(m, 0.0, 4.0, 0.9, 6.0)
    m.pop()
    for x in (4.95, 11.55):
        pinnacle(m, x, 7.9, -10.55, 0.34, 1.0, 1.7)


def _st_east(m: LM) -> None:
    # Side wings (chapels): ridge along x.
    for z0, z1, x0, x1 in ((-17.7, -8.6, 36.1, 61.7), (8.9, 16.8, 36.5, 62.4)):
        cz, half = (z0 + z1) / 2, (z1 - z0) / 2
        m.ybox(x0 - 0.25, x1 + 0.25, 0.0, 0.5, z0 - 0.25, z1 + 0.25, PLINTH)
        m.ybox(x0, x1, 0.5, 8.6, z0, z1, WHITE, skip="-y")
        m.collider(((x0 + x1) / 2, 4.3, cz), (x1 - x0, 8.6, z1 - z0))
        course(m, x0, x1, z0, z1, 8.4, 0.28, 0.14)
        gable_roof(m, x0, x1, cz, half, 8.6, 8.6 + half * 0.95)
        for face, x in (("-x", x0), ("+x", x1)):
            gable_end(m, face, x, cz, half, 8.6, 8.6 + half * 0.95)
            wall_frame(m, face, x, cz)
            for lx in (-2.2, 0.0, 2.2):
                lancet(m, lx, 2.0, 1.1, 5.6 if lx else 6.2)
            rose(m, 0.0, 10.1, 0.6)
            m.pop()
            sgn = -1.0 if face == "-x" else 1.0
            for z in (z0 + 0.3, z1 - 0.3):
                pinnacle(m, x + sgn * 0.05, 8.6, z, 0.4, 1.4, 2.0)
            cross(m, x + sgn * 0.1, 8.6 + half * 0.95, cz, 1.5)
        outer = z0 if z0 < 0 else z1
        face = "-z" if z0 < 0 else "+z"
        sgn = -1.0 if z0 < 0 else 1.0
        bx = x0 + 0.1
        while bx <= x1 + 0.01:
            m.ybox(bx - 0.35, bx + 0.35, 0.0, 7.0, outer + sgn * 0.0 - 0.0, outer + sgn * 0.85, WHITE)
            pinnacle(m, bx, 8.0, outer + sgn * 0.42, 0.28, 1.0, 1.6, gablets=False)
            m.prism(4, 0.5, 0.3, 7.0, 8.0, WHITE_SH, rot=math.pi / 4, cx=bx, cz=outer + sgn * 0.42)
            if bx + 4.2 <= x1:
                wall_frame(m, face, bx + 2.1, outer)
                lancet(m, 0.0, 1.8, 1.1, 5.4)
                m.pop()
            bx += 4.2
    # Links between the choir and the wings stay aisle height (already from _st_nave to 47.5);
    # the polygonal apse closes the choir.
    cx, r = 62.0, NAVE_HALF
    plan = [(cx + r * math.cos(a), r * math.sin(a)) for a in (-math.pi / 2, -math.pi / 4, 0.0, math.pi / 4, math.pi / 2)]
    for i in range(len(plan) - 1):
        a, b = plan[i], plan[i + 1]
        nx, nz = (a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2
        m.quad((a[0], 0.0, a[1]), (b[0], 0.0, b[1]), (b[0], NAVE_EAVE, b[1]), (a[0], NAVE_EAVE, a[1]), WHITE, (nx, 0, nz))
        m.quad((a[0], NAVE_EAVE, a[1]), (b[0], NAVE_EAVE, b[1]), (cx, NAVE_RIDGE, 0.0), (cx, NAVE_RIDGE, 0.0), ROOF, (nx, 1.0, nz))
        m.tri((a[0] + nx * 0.07, NAVE_EAVE - 0.05, a[1] + nz * 0.07), (b[0] + nx * 0.07, NAVE_EAVE - 0.05, b[1] + nz * 0.07),
              (cx, NAVE_RIDGE + 0.05, 0.0), ROOF2 if i % 2 else ROOF, (nx, 1.0, nz))
        # Tall lancet in each facet, buttress pinnacle at each corner.
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        m.push((mid[0], 0.0, mid[1]), yaw=math.atan2(nx, nz))
        lancet(m, 0.0, 3.0, 1.0, 9.6)
        m.pop()
    for p in plan:
        d = (p[0] - cx, p[1])
        ln = math.hypot(*d)
        ux, uz = d[0] / ln, d[1] / ln
        m.prism(4, 0.6, 0.6, 0.0, 10.4, WHITE, top=False, rot=math.atan2(uz, ux) + math.pi / 4, cx=p[0] + ux * 0.35, cz=p[1] + uz * 0.35)
        pinnacle(m, p[0] + ux * 0.35, 10.4, p[1] + uz * 0.35, 0.34, 1.6, 2.2, gablets=False)
    m.collider((cx + 2.2, NAVE_EAVE / 2, 0.0), (4.4, NAVE_EAVE, NAVE_HALF * 2))


def _st_tower(m: LM) -> None:
    tx, tz = TOWER_C
    h = TOWER_W / 2
    m.ybox(tx - h - 0.3, tx + h + 0.3, 0.0, 0.6, tz - h - 0.3, tz + h + 0.3, PLINTH)
    m.ybox(tx - h, tx + h, 0.6, 22.0, tz - h, tz + h, WHITE, skip="-y")
    m.collider((tx, 11.0, tz), (TOWER_W + 0.6, 22.0, TOWER_W + 0.6))
    for y, hh, out in ((9.0, 0.3, 0.14), (17.0, 0.28, 0.14), (21.5, 0.5, 0.22)):
        course(m, tx - h, tx + h, tz - h, tz + h, y, hh, out)
    # Corner buttresses rising into the gallery pinnacles.
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            bx, bz = tx + sx * (h + 0.05), tz + sz * (h + 0.05)
            m.ybox(bx - 0.55, bx + 0.55, 0.6, 21.5, bz - 0.55, bz + 0.55, WHITE)
            for y in (6.5, 13.5):
                m.prism(4, 0.85, 0.6, y, y + 0.7, WHITE_SH, top=False, rot=math.pi / 4, cx=bx, cz=bz)
            pinnacle(m, bx, 22.0, bz, 0.5, 2.6, 3.6)
    # Faces: door (west) / tall lancet / oculus on each face.
    for face, fx, fz in (("-x", tx - h, tz), ("+x", tx + h, tz), ("-z", tx, tz - h), ("+z", tx, tz + h)):
        wall_frame(m, face, fx, fz)
        if face == "-x":
            lancet(m, 0.0, 0.6, 2.3, 3.8, col=DOOR, frame=0.3, depth=0.3)
            lancet(m, 0.0, 5.2, 1.0, 7.4, frame=0.12, depth=0.1)
        else:
            lancet(m, 0.0, 2.4, 1.0, 6.6)
        lancet(m, 0.0, 10.2, 1.5, 14.6, rise=1.9, frame=0.2, depth=0.16)
        # Gabled hood over the tall lancet.
        m.extrude([(-1.25, 15.2), (1.25, 15.2), (0.0, 16.8)], 0.0, 0.22, TRIM, back=False)
        rose(m, 0.0, 19.2, 0.85)
        # Gallery: an arcaded parapet.
        m.extrude([(-h - 0.2, 22.0), (h + 0.2, 22.0), (h + 0.2, 23.3), (-h - 0.2, 23.3)], -0.15, 0.05, TRIM, back=False)
        for k in range(6):
            lx = -2.1 + k * 0.84
            m.push((lx, 0.0, 0.0))
            m.flat(arch(0.42, 22.25, 22.8, "pointed", n=3, rise=0.28), 0.065, IRON)
            m.pop()
        m.pop()
    m.ybox(tx - h - 0.2, tx + h + 0.2, 21.9, 22.05, tz - h - 0.2, tz + h + 0.2, TRIM)
    m.ybox(tx - h - 0.3, tx + h + 0.3, 23.3, 23.55, tz - h - 0.3, tz + h + 0.3, TRIM)
    # Octagonal belfry.
    R = 2.95
    rot = math.pi / 8
    m.prism(8, R, R, 22.0, 30.6, WHITE, top=False, rot=rot, cx=tx, cz=tz)
    m.prism(8, R + 0.25, R + 0.25, 30.6, 31.0, TRIM, top=True, bottom=True, rot=rot, cx=tx, cz=tz)
    m.prism(8, R + 0.2, R + 0.2, 23.55, 23.85, TRIM, top=False, bottom=True, rot=rot, cx=tx, cz=tz)
    apo = R * math.cos(math.pi / 8)
    for k in range(8):
        a = rot + math.pi / 8 + k * math.pi / 4  # face centre angle
        fx, fz = tx + math.cos(a) * apo, tz + math.sin(a) * apo
        m.push((fx, 0.0, fz), yaw=math.atan2(math.cos(a), math.sin(a)))
        if k % 2 == 0:
            lancet(m, 0.0, 24.4, 0.95, 28.3, frame=0.14, depth=0.12, col=RED_DEEP)
            m.extrude([(-0.95, 29.0), (0.95, 29.0), (0.0, 31.4)], 0.0, 0.18, WHITE, back=False)
            m.bar((-0.95, 29.0, 0.2), (0.0, 31.45, 0.2), 0.08, TRIM, 4)
            m.bar((0.95, 29.0, 0.2), (0.0, 31.45, 0.2), 0.08, TRIM, 4)
        else:
            lancet(m, 0.0, 25.6, 0.5, 27.8, frame=0.1, depth=0.08, hood=False)
        m.pop()
    for k in range(8):
        a = rot + k * math.pi / 4  # corners
        px, pz = tx + math.cos(a) * (R + 0.05), tz + math.sin(a) * (R + 0.05)
        pinnacle(m, px, 29.6, pz, 0.2, 1.3, 1.5, gablets=False)
    # Spire with a collar, lucarnes and the red cross.
    m.prism(8, R - 0.1, 1.55, 31.0, 38.0, WHITE, top=False, rot=rot, cx=tx, cz=tz)
    m.prism(8, 1.72, 1.72, 38.0, 38.35, TRIM, top=False, bottom=True, rot=rot, cx=tx, cz=tz)
    m.prism(8, 1.55, 0.0, 38.35, 45.6, WHITE, rot=rot, cx=tx, cz=tz)
    m.prism(8, 0.22, 0.22, 45.3, 45.9, TRIM, rot=rot, cx=tx, cz=tz)
    for k in range(4):
        a = math.pi / 2 * k
        dist = (R - 0.1) - (R - 0.1 - 1.55) * (1.3 / 7.0) + 0.05
        lx, lz = tx + math.cos(a) * dist, tz + math.sin(a) * dist
        m.push((lx, 0.0, lz), yaw=math.atan2(math.cos(a), math.sin(a)))
        m.extrude([(-0.5, 31.6), (0.5, 31.6), (0.5, 32.9), (0.0, 33.7), (-0.5, 32.9)], -0.6, 0.15, WHITE, back=False)
        m.flat(arch(0.42, 31.8, 32.6, "pointed", n=3, rise=0.45), 0.16, RED_DEEP)
        m.pop()
    cross(m, tx, 45.85, tz, 1.75, yaw=math.radians(0.0))


def _st_fleche(m: LM, x: float) -> None:
    """The small spire over the tomb at the centre of the church."""
    rot = math.pi / 8
    m.prism(8, 1.05, 1.05, NAVE_RIDGE - 1.0, NAVE_RIDGE + 2.6, WHITE, top=False, rot=rot, cx=x, cz=0.0)
    for k in range(8):
        a = rot + math.pi / 8 + k * math.pi / 4
        apo = 1.05 * math.cos(math.pi / 8)
        m.push((x + math.cos(a) * apo, 0.0, math.sin(a) * apo), yaw=math.atan2(math.cos(a), math.sin(a)))
        m.flat(arch(0.32, NAVE_RIDGE + 0.2, NAVE_RIDGE + 1.5, "pointed", n=3), 0.02, RED_DEEP)
        m.pop()
    m.prism(8, 1.25, 1.25, NAVE_RIDGE + 2.6, NAVE_RIDGE + 2.85, TRIM, bottom=True, rot=rot, cx=x, cz=0.0)
    m.prism(8, 1.1, 0.0, NAVE_RIDGE + 2.85, NAVE_RIDGE + 8.2, WHITE, rot=rot, cx=x, cz=0.0)
    cross(m, x, NAVE_RIDGE + 8.15, 0.0, 1.2)


# ================================================================= Kapaleeshwarar: stucco palette

GRANITE = (172, 166, 154)
GRANITE_L = (192, 186, 174)
GRANITE_D = (138, 132, 122)
DOORWAY = (34, 25, 21)
TEAK = (96, 58, 34)
GOLD = (212, 166, 62)
GOLD_D = (172, 128, 44)
STUCCO_WHITE = (238, 233, 222)
KAAVI_RED = (176, 52, 40)
KAAVI_WHITE = (238, 232, 220)
RED_OXIDE = (138, 98, 82)
PAVING = (188, 182, 170)
# Tier grounds: the 2019 repaint is lavender, sky blue, pink, mint and gold (owner photos).
ARCH = [(168, 156, 216), (136, 170, 222), (230, 166, 192), (146, 200, 178), (236, 208, 132), (202, 142, 192)]
BANDS = [(226, 120, 150), (96, 132, 210), (110, 180, 120), (236, 186, 80), (168, 100, 196), (90, 170, 190)]
SKINS = [(92, 132, 214), (240, 192, 160), (226, 156, 118), (126, 182, 112), (236, 236, 230), (226, 118, 118), (246, 202, 92), (170, 120, 200)]
CLOTH = [(238, 88, 78), (252, 198, 60), (88, 168, 92), (190, 88, 190), (240, 148, 60), (80, 118, 202), (248, 248, 242), (230, 90, 150)]
NANDI = (236, 234, 226)


def pick(rng: random.Random, pal):
    return pal[rng.randrange(len(pal))]


# ------------------------------------------------------------ figures (built facing +z, feet at y 0, height 1)

def figure(m: LM, rng: random.Random, kind: str = "stand") -> None:
    """A painted stucco figure, ~70-110 triangles: dhoti or folded legs, torso, head, crown, 2 or 4 arms."""
    skin = pick(rng, SKINS)
    cloth = pick(rng, CLOTH)
    crown = GOLD if rng.random() < 0.65 else pick(rng, CLOTH)
    if kind == "sit":
        m.rfrustum(0.44, 0.3, 0.36, 0.26, 0.0, 0.2, cloth)              # folded legs on a seat
        y_t0, y_t1, y_h = 0.2, 0.5, 0.58
    else:
        m.rfrustum(0.28, 0.18, 0.2, 0.14, 0.0, 0.47, cloth)              # legs / dhoti
        y_t0, y_t1, y_h = 0.47, 0.76, 0.84
    m.rfrustum(0.2, 0.13, 0.29, 0.15, y_t0, y_t1, skin)                  # torso
    m.prism(5, 0.075, 0.075, y_h - 0.07, y_h + 0.03, skin, top=False, rot=math.pi / 2)   # head
    m.prism(5, 0.075, 0.02, y_h + 0.03, y_h + 0.2, crown, rot=math.pi / 2)              # crown
    sh = y_t1 - 0.03
    four = rng.random() < 0.4
    pose = rng.randrange(3)
    for s in (-1.0, 1.0):
        if pose == 0:
            hand = (s * 0.17, sh - 0.3, 0.06)
        elif pose == 1:
            hand = (s * 0.2, sh + 0.04, 0.08) if s > 0 else (s * 0.15, sh - 0.28, 0.06)
        else:
            hand = (s * 0.05, sh - 0.12, 0.13)
        m.bar((s * 0.13, sh, 0.0), hand, 0.03, skin, 3)
        if four:
            m.bar((s * 0.12, sh - 0.02, -0.03), (s * 0.25, sh + 0.17, -0.02), 0.025, skin, 3)


def nandi(m: LM) -> None:
    """Lying Nandi, facing +z, about 1 m long."""
    m.rfrustum(0.42, 0.78, 0.36, 0.7, 0.0, 0.32, NANDI)                 # body
    m.rfrustum(0.44, 0.5, 0.4, 0.46, 0.18, 0.36, KAAVI_RED, cz=-0.02)    # saddle cloth
    m.rfrustum(0.3, 0.22, 0.2, 0.14, 0.32, 0.46, NANDI, cz=0.18)         # hump
    m.rfrustum(0.2, 0.3, 0.17, 0.26, 0.3, 0.52, NANDI, cz=0.42)          # neck + head
    m.rfrustum(0.14, 0.14, 0.12, 0.12, 0.33, 0.46, NANDI, cz=0.6)        # muzzle
    m.rfrustum(0.24, 0.05, 0.24, 0.05, 0.34, 0.39, GOLD, cz=0.36)        # bell collar
    for s in (-1.0, 1.0):
        m.bar((s * 0.07, 0.5, 0.42), (s * 0.15, 0.64, 0.38), 0.022, (60, 52, 46), 4)   # horns
        m.bar((s * 0.1, 0.46, 0.44), (s * 0.2, 0.45, 0.4), 0.025, NANDI, 4)           # ears
        m.rfrustum(0.12, 0.28, 0.1, 0.26, 0.0, 0.1, NANDI, cx=s * 0.24, cz=0.12)    # folded legs
    m.bar((0.0, 0.25, -0.38), (0.12, 0.05, -0.42), 0.02, NANDI, 4)


# ------------------------------------------------------------ stucco architecture

def kuta(m: LM, x: float, y: float, z: float, s: float, col, roof, square: bool = True) -> None:
    """Miniature shrine: a cell, a white ledge, a domed roof (square or round) and a gold finial."""
    m.rfrustum(s, s * 0.8, s * 0.9, s * 0.72, y, y + s * 0.62, col, top=False, cx=x, cz=z)
    m.rfrustum(s * 1.12, s * 0.92, s * 1.12, s * 0.92, y + s * 0.62, y + s * 0.72, STUCCO_WHITE, top=False, cx=x, cz=z)
    seg, rot = (4, math.pi / 4) if square else (6, math.pi / 6)
    r = s * 0.55 / math.cos(math.pi / seg)
    m.lathe([(r, 0.0), (r * 0.95, s * 0.3), (r * 0.5, s * 0.55), (0.0, s * 0.62)], seg, roof, cx=x, cz=z, y=y + s * 0.72, rot=rot)
    m.prism(4, s * 0.09, 0.0, y + s * 1.3, y + s * 1.6, GOLD, cx=x, cz=z, rot=math.pi / 4)


def shala(m: LM, x: float, y: float, z: float, length: float, depth: float, col, roof, along_x: bool = True) -> None:
    """Miniature barrel-vaulted shrine with horseshoe gable ends."""
    m.push((x, y, z), yaw=0.0 if along_x else math.pi / 2)
    m.rfrustum(length, depth, length * 0.96, depth * 0.92, 0.0, depth * 0.7, col)
    m.ybox(-length * 0.54, length * 0.54, depth * 0.7, depth * 0.8, -depth * 0.58, depth * 0.58, STUCCO_WHITE)
    prof = arch(depth * 0.95, 0.0, 0.0, "round", n=5)
    pts = [(p[0], p[1] * 0.75) for p in prof]
    # Vault: the arch profile swept along x.
    ring = [p for p in pts if p[1] > 1e-6 or True]
    yb = depth * 0.8
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        if a[1] < 1e-6 and b[1] < 1e-6:
            continue
        nz, ny = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5 + 0.01
        m.quad((-length / 2, yb + a[1], a[0]), (length / 2, yb + a[1], a[0]), (length / 2, yb + b[1], b[0]), (-length / 2, yb + b[1], b[0]), roof, (0, ny, nz))
    for s in (-1.0, 1.0):
        m.push((s * length / 2, 0.0, 0.0), yaw=s * math.pi / 2)
        horse = arch(depth * 0.95, yb - depth * 0.05, yb + 0.02, "horseshoe", n=4)
        m.extrude([(p[0], p[1]) for p in horse], -0.02, 0.08, STUCCO_WHITE, back=False)
        m.flat(circle(depth * 0.2, 0.0, yb + depth * 0.32, 6), 0.09, col)
        m.pop()
    for k in range(3):
        fx = (k - 1) * length * 0.3
        m.prism(6, depth * 0.08, 0.0, yb + depth * 0.7, yb + depth * 0.95, GOLD, cx=fx)
    m.pop()


def stripe_wall(m: LM, a, b, y0: float, y1: float, band: float = 0.9, c0=KAAVI_RED, c1=KAAVI_WHITE) -> None:
    """Kaavi wall face from plan point a to b (both (x, z)), outward to the right of a->b."""
    ln = math.hypot(b[0] - a[0], b[1] - a[1])
    n = max(1, int(round(ln / band)))
    ux, uz = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
    nx, nz = uz, -ux
    for k in range(n):
        p0 = (a[0] + ux * ln * k / n, a[1] + uz * ln * k / n)
        p1 = (a[0] + ux * ln * (k + 1) / n, a[1] + uz * ln * (k + 1) / n)
        m.quad((p0[0], y0, p0[1]), (p1[0], y0, p1[1]), (p1[0], y1, p1[1]), (p0[0], y1, p0[1]), c0 if k % 2 == 0 else c1, (nx, 0, nz))


def stucco_tier(m: LM, rng: random.Random, w: float, d: float, w2: float, d2: float, y0: float, h: float,
                ground, band, fig_h: float, window: bool = True, nandis: bool = False, fig_short: bool = True) -> None:
    """One storey of a gopuram or vimana, the way the Kapaleeshwarar tiers are built: a moulded
    base, a painted wall where every bay is a small niche (white pilasters, an arched torana)
    holding a figure almost as tall as the storey, a projecting centre bay with a dark window
    flanked by larger deities, a kapota cornice, and a parapet of miniature shrines all round."""
    yb = y0 + 0.2
    yk = y0 + h - 0.38
    m.rfrustum(w + 0.2, d + 0.2, w + 0.2, d + 0.2, y0, yb, band, top=False)
    m.rfrustum(w, d, w2, d2, yb, yk, ground, top=False)
    m.rfrustum(w2 + 0.05, d2 + 0.05, w2 + 0.6, d2 + 0.6, yk, yk + 0.26, band, top=False)
    m.rfrustum(w2 + 0.6, d2 + 0.6, w2 + 0.6, d2 + 0.6, yk + 0.26, yk + 0.38, STUCCO_WHITE, top=True)
    ytop = yk + 0.38
    wall_h = yk - yb
    light = shade(ground, 1.18)
    for face in ("+z", "-z", "+x", "-x"):
        long_face = face in ("+z", "-z")
        half_len, half_dep = (w / 2, d / 2) if long_face else (d / 2, w / 2)
        top_half = (d2 / 2) if long_face else (w2 / 2)
        yaw = {"+z": 0.0, "-z": math.pi, "+x": math.pi / 2, "-x": -math.pi / 2}[face]
        m.push((0.0, 0.0, 0.0), yaw=yaw)
        zf = (half_dep + top_half) / 2  # wall plane at mid height (the wall leans in)
        bw = max(1.3, half_len * 0.36) if long_face else max(1.0, half_len * 0.5)
        if not window or not long_face:
            bw = min(bw, half_len)
        # Centre bay stands forward; corner bays a little.
        m.rfrustum(bw, 0.45, bw * 0.97, 0.45, yb, yk, light, top=False, cz=zf + 0.12)
        m.ybox(-bw / 2 - 0.1, bw / 2 + 0.1, yk - 0.22, yk, zf + 0.12, zf + 0.42, band)
        for s in (-1.0, 1.0):
            m.rfrustum(0.9, 0.36, 0.88, 0.36, yb, yk, shade(ground, 1.08), top=False, cx=s * (half_len - 0.45), cz=zf + 0.02)
        if window and long_face:
            win = arch(min(0.62, bw * 0.3), yb + wall_h * 0.18, yb + wall_h * 0.6, "horseshoe", n=4)
            m.flat(win, zf + 0.35, DOORWAY)
            m.extrude(offset(win, 0.1), zf + 0.33, zf + 0.4, STUCCO_WHITE, back=False, holes=[win])
            if fig_h > 0.0:
                for s in (-1.0, 1.0):
                    m.push((s * (bw / 2 - 0.32), yb + 0.03, zf + 0.42), scale=fig_h * 1.12 / 1.04)
                    figure(m, rng, "stand")
                    m.pop()
        elif fig_h > 0.0 and (long_face or fig_short):
            m.push((0.0, yb + 0.03, zf + 0.42), scale=fig_h * 1.05 / 1.04)
            figure(m, rng, "stand" if rng.random() < 0.7 else "sit")
            m.pop()
        # Niches between the centre and the corners.
        inner0, inner1 = bw / 2 + 0.06, half_len - 0.92
        span = inner1 - inner0
        if span > 0.5:
            bays = max(1, int(round(span / 1.12)))
            step = span / bays
            for s in (-1.0, 1.0):
                for k in range(bays + 1):
                    px = s * (inner0 + k * step)
                    m.rfrustum(0.1, 0.1, 0.1, 0.1, yb, yk - 0.2, STUCCO_WHITE, top=False, cx=px, cz=zf + 0.05)
                for k in range(bays):
                    px = s * (inner0 + (k + 0.5) * step)
                    # Torana: an arched lintel over the niche.
                    tor = arch(step * 0.86, yk - 0.42, yk - 0.3, "round", n=4)
                    m.push((px, 0.0, 0.0))
                    m.extrude([(p[0], p[1]) for p in tor], zf, zf + 0.12, band if k % 2 == 0 else STUCCO_WHITE, back=False)
                    # Each niche has its own painted back, so a storey is never one flat colour.
                    m.flat([(-step * 0.43, yb), (step * 0.43, yb), (step * 0.43, yk - 0.42), (-step * 0.43, yk - 0.42)],
                           zf + 0.01, ARCH[(k + int(abs(px) * 7)) % len(ARCH)] if (k + (s > 0)) % 2 else shade(ground, 0.9))
                    m.pop()
                    if fig_h > 0.0 and (long_face or fig_short):
                        sit = rng.random() < 0.22
                        fh = min(fig_h, (wall_h - 0.5) * (1.0 if not sit else 0.75))
                        m.push((px, yb + 0.03, zf + 0.2), scale=fh / (0.78 if sit else 1.04))
                        figure(m, rng, "sit" if sit else "stand")
                        m.pop()
        if fig_h > 0.0 and (long_face or fig_short):
            for s in (-1.0, 1.0):
                m.push((s * (half_len - 0.45), yb + 0.03, zf + 0.32), scale=min(fig_h, wall_h - 0.4) / 1.04)
                figure(m, rng, "stand")
                m.pop()
        m.pop()
    # Parapet (hara): Nandis or kutas at the corners, a shala over each centre bay, round kutas between.
    roof = shade(band, 0.88)
    ox, oz = w2 / 2 + 0.25, d2 / 2 + 0.25
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            if nandis:
                m.push((sx * (ox - 0.15), ytop, sz * (oz - 0.15)), yaw=math.atan2(sx, sz), scale=max(0.9, fig_h * 0.62))
                nandi(m)
                m.pop()
            else:
                kuta(m, sx * (ox - 0.3), ytop, sz * (oz - 0.3), 0.75, light, roof)
    for long_face, half_len, off in ((True, w2 / 2, oz), (False, d2 / 2, ox)):
        sl = max(1.1, half_len * (0.6 if long_face else 0.7))
        for s in (-1.0, 1.0):
            if long_face:
                shala(m, 0.0, ytop, s * (off - 0.2), sl, 0.55, light, roof, True)
            else:
                shala(m, s * (off - 0.2), ytop, 0.0, sl, 0.55, light, roof, False)
            room = half_len - sl / 2 - 0.85
            n_p = max(0, int(room / 1.45))
            for k in range(n_p):
                p = sl / 2 + 0.15 + (k + 0.5) * room / n_p
                for t in (-1.0, 1.0):
                    if long_face:
                        kuta(m, t * p, ytop, s * (off - 0.2), 0.44, light, ground, square=False)
                    else:
                        kuta(m, s * (off - 0.2), ytop, t * p, 0.44, light, ground, square=False)


def kalasam(m: LM, x: float, y: float, z: float, s: float) -> None:
    prof = [(0.22, 0.0), (0.38, 0.12), (0.44, 0.32), (0.36, 0.52), (0.16, 0.62), (0.2, 0.7), (0.12, 0.78), (0.17, 0.86),
            (0.09, 0.95), (0.05, 1.3), (0.0, 1.45)]
    m.lathe([(r * s, yy * s) for r, yy in prof], 8, GOLD, cx=x, cz=z, y=y, cols=[GOLD, GOLD_D, GOLD, GOLD, GOLD_D, GOLD, GOLD_D, GOLD, GOLD, GOLD])


def shala_crown(m: LM, rng: random.Random, length: float, depth: float, y: float, n_kalasam: int, ground, band) -> float:
    """Gopuram crown: barrel vault along x on a plinth, great horseshoe arches on the ends and the
    middle of each long face, yali horns at the ends, a row of golden kalasams on the ridge."""
    m.rfrustum(length + 0.6, depth + 0.6, length + 0.6, depth + 0.6, y, y + 0.45, band, top=False)
    m.rfrustum(length, depth, length, depth, y + 0.45, y + 1.3, ground, top=False)
    yv = y + 1.3
    r = depth / 2
    prof = [(r * math.cos(a), r * 0.95 * math.sin(a)) for a in [math.pi * i / 10 for i in range(11)]]
    for i in range(len(prof) - 1):
        a, b = prof[i], prof[i + 1]
        c = ground if i % 2 == 0 else shade(ground, 0.92)
        m.quad((-length / 2, yv + a[1], a[0]), (length / 2, yv + a[1], a[0]), (length / 2, yv + b[1], b[0]), (-length / 2, yv + b[1], b[0]),
               c, (0, (a[1] + b[1]) * 0.5, (a[0] + b[0]) * 0.5))
    top = yv + r * 0.95
    # Ribs across the vault.
    for k in range(7):
        x = -length / 2 + length * (k + 0.5) / 7
        pts = [(x, yv + p[1] + 0.05, p[0] * 1.04) for p in prof]
        for a, b in zip(pts, pts[1:]):
            m.bar(a, b, 0.07, band, 4)
    for s in (-1.0, 1.0):
        # End gables: horseshoe frame with a kirtimukha face.
        m.push((s * length / 2, 0.0, 0.0), yaw=s * math.pi / 2)
        outer = arch(depth * 1.15, yv - 0.4, yv + 0.1, "horseshoe", n=6)
        inner = arch(depth * 0.8, yv - 0.2, yv + 0.1, "horseshoe", n=6)
        m.extrude(outer, -0.05, 0.35, band, back=False, holes=[inner])
        m.flat(inner, 0.12, shade(ground, 0.85))
        cy = yv + r * 0.5
        m.flat(circle(r * 0.42, 0.0, cy, 10), 0.16, (232, 182, 96))
        for ex in (-0.16, 0.16):
            m.flat(circle(r * 0.07, ex * r * 2.0, cy + r * 0.1, 6), 0.17, (30, 30, 30))
        m.flat([(-r * 0.18, cy - r * 0.2), (r * 0.18, cy - r * 0.2), (0.0, cy - r * 0.32)], 0.17, (200, 50, 50))
        m.pop()
        # Yali horns curling up and out from the ends of the ridge.
        pts = [(s * length * 0.5, top - 0.3, 0.0)]
        for k in range(1, 7):
            t = k / 6
            pts.append((s * (length * 0.5 + 0.9 * math.sin(t * 2.2)), top - 0.3 + 2.0 * t, -0.25 * math.sin(t * 3.0)))
        for k in range(len(pts) - 1):
            rr = 0.32 * (1.0 - k / 7) + 0.06
            m.bar(pts[k], pts[k + 1], rr, BANDS[1] if k % 2 else BANDS[3], 5)
    for s in (-1.0, 1.0):
        # Maha-nasi: the great arch in the middle of each long face, with a seated figure in it.
        m.push((0.0, 0.0, s * (r + 0.02)), yaw=0.0 if s > 0 else math.pi)
        outer = arch(depth * 0.62, yv - 0.7, yv - 0.1, "horseshoe", n=6)
        inner = arch(depth * 0.42, yv - 0.55, yv - 0.1, "horseshoe", n=6)
        m.extrude(outer, -0.2, 0.25, band, back=False, holes=[inner])
        m.flat(inner, 0.0, shade(ground, 0.8))
        m.push((0.0, yv - 0.55, 0.05), scale=1.0 / 0.8)
        figure(m, rng, "sit")
        m.pop()
        m.pop()
    # Ridge and kalasams.
    m.ybox(-length / 2, length / 2, top - 0.12, top + 0.18, -0.35, 0.35, band)
    for k in range(n_kalasam):
        x = -length / 2 + 0.45 + (length - 0.9) * k / max(n_kalasam - 1, 1)
        kalasam(m, x, top + 0.18, 0.0, 1.5)
    return top + 0.18 + 1.5 * 1.45


def gopuram(m: LM, rng: random.Random, W: float, D: float, base_h: float, tiers: int, tier_h: float,
            top_w: float, top_d: float, n_kal: int, fig_h: float) -> float:
    """A Dravidian gopuram facing +-z (width along x): granite base with the gateway, `tiers`
    painted stucco storeys, the crown. Returns the height of the kalasam tips."""
    # Granite base: upapitha, mouldings, pilastered wall with niches, kapota.
    m.rfrustum(W + 1.6, D + 1.6, W + 1.6, D + 1.6, 0.0, 0.5, GRANITE_D)
    ys = [(0.5, 0.85, 0.6), (0.85, 1.05, 0.3), (1.05, 1.5, 0.45), (1.5, 1.7, 0.15)]
    for y0, y1, g in ys:
        m.rfrustum(W + g * 2, D + g * 2, W + g * 2, D + g * 2, y0, y1, GRANITE if g > 0.2 else GRANITE_L)
    yw0, yw1 = 1.7, base_h - 0.9
    m.rfrustum(W, D, W, D, yw0, yw1, GRANITE, top=False)
    m.rfrustum(W + 0.1, D + 0.1, W + 1.2, D + 1.2, yw1, yw1 + 0.5, GRANITE_L, top=False)
    m.rfrustum(W + 1.2, D + 1.2, W + 1.2, D + 1.2, yw1 + 0.5, base_h, GRANITE_D)
    door_w, door_h = min(4.4, W * 0.2), min(8.2, (yw1 - yw0) * 0.95)
    for face in ("+z", "-z", "+x", "-x"):
        yaw = {"+z": 0.0, "-z": math.pi, "+x": math.pi / 2, "-x": -math.pi / 2}[face]
        half_len, half_dep = (W / 2, D / 2) if face in ("+z", "-z") else (D / 2, W / 2)
        m.push((0.0, 0.0, half_dep), yaw=yaw)
        n = max(2, int(half_len * 2 / 1.6))
        for k in range(n + 1):
            x = -half_len + 2 * half_len * k / n
            if face in ("+z", "-z") and abs(x) < door_w / 2 + 0.7:
                continue
            m.ybox(x - 0.2, x + 0.2, yw0, yw1, 0.0, 0.14, GRANITE_L)
        # Niches (koshtas) with dark recesses between pilasters.
        for k in range(n):
            x = -half_len + 2 * half_len * (k + 0.5) / n
            if face in ("+z", "-z") and abs(x) < door_w / 2 + 1.4:
                continue
            if k % 2 == 0:
                m.ybox(x - 0.42, x + 0.42, yw0 + 1.2, yw0 + 3.4, 0.0, 0.03, GRANITE_D)
                m.ybox(x - 0.55, x + 0.55, yw0 + 3.4, yw0 + 3.8, 0.0, 0.2, GRANITE_L)
        if face in ("+z", "-z"):
            # Gateway: stepped granite frame, dark passage, the great teak doors folded back.
            frame = [(-door_w / 2 - 0.6, yw0 - 1.2), (door_w / 2 + 0.6, yw0 - 1.2), (door_w / 2 + 0.6, yw0 + door_h + 0.6), (-door_w / 2 - 0.6, yw0 + door_h + 0.6)]
            hole = [(-door_w / 2, 0.5), (door_w / 2, 0.5), (door_w / 2, yw0 + door_h), (-door_w / 2, yw0 + door_h)]
            m.extrude(frame, -0.02, 0.32, GRANITE_L, back=False, holes=[hole])
            m.flat(hole, -1.1, DOORWAY)
            for s in (-1.0, 1.0):
                m.quad((s * door_w / 2, 0.5, 0.3), (s * door_w / 2, 0.5, -1.1), (s * door_w / 2, yw0 + door_h, -1.1), (s * door_w / 2, yw0 + door_h, 0.3),
                       GRANITE_D, (-s, 0, 0))
                m.ybox(s * (door_w / 2 - 0.12), s * (door_w / 2 - 0.02), 0.5, yw0 + door_h - 0.2, -1.05, 0.1, TEAK)
            m.quad((-door_w / 2, yw0 + door_h, 0.3), (door_w / 2, yw0 + door_h, 0.3), (door_w / 2, yw0 + door_h, -1.1), (-door_w / 2, yw0 + door_h, -1.1),
                   GRANITE_D, (0, -1, 0))
            m.ybox(-door_w / 2 + 0.25, door_w / 2 - 0.25, 0.5, 0.75, -0.2, 0.32, GRANITE_L)  # threshold
        m.pop()
    m.collider((0.0, base_h / 2, 0.0), (W + 1.6, base_h, D + 1.6))
    # Stucco tiers.
    y = base_h
    w, d = W - 1.6, D - 1.6
    step_w = (w - top_w) / tiers
    step_d = (d - top_d) / tiers
    for t in range(tiers):
        h = tier_h - t * 0.08
        w2, d2 = w - step_w * 0.55, d - step_d * 0.55
        nand = t in (0, tiers // 2, tiers - 1)
        stucco_tier(m, rng, w, d, w2, d2, y, h, ARCH[t % len(ARCH)], BANDS[(t * 2 + 1) % len(BANDS)],
                    fig_h * (1.0 - t * 0.04), nandis=nand)
        y += h
        w, d = w - step_w, d - step_d
    m.collider((0.0, (base_h + y) / 2, 0.0), ((W - 1.6 + top_w) / 2, y - base_h, (D - 1.6 + top_d) / 2))
    return shala_crown(m, rng, top_w, top_d, y, n_kal, ARCH[tiers % len(ARCH)], BANDS[0])


def vimana(m: LM, rng: random.Random, x: float, z: float, y0: float, s: float, tiers: int, dome: str, yaw: float = 0.0) -> None:
    """Shrine tower on a flat roof: square storeys of figures, a neck (griva) and the dome
    (shikhara: square, octagonal or round) under one kalasam. s = side of the first storey."""
    m.push((x, y0, z), yaw=yaw)
    m.rfrustum(s + 0.6, s + 0.6, s + 0.6, s + 0.6, 0.0, 0.5, STUCCO_WHITE)
    yy = 0.5
    w = s
    for t in range(tiers):
        h = 2.1 - t * 0.15
        stucco_tier(m, rng, w, w, w - 0.2, w - 0.2, yy, h, ARCH[(t + 2) % len(ARCH)], BANDS[(t + 3) % len(BANDS)],
                    0.95 - t * 0.08, window=False)
        yy += h
        w *= 0.72
    # Griva with four seated figures, then the dome.
    gw = w * 0.85
    m.rfrustum(gw, gw, gw * 0.95, gw * 0.95, yy, yy + 0.9, ARCH[1], top=False)
    for k in range(4):
        a = k * math.pi / 2
        m.push((math.sin(a) * gw * 0.5, yy + 0.05, math.cos(a) * gw * 0.5), yaw=a, scale=0.8 / 0.8)
        figure(m, rng, "sit")
        m.pop()
    seg, rot = {"square": (4, math.pi / 4), "octagon": (8, math.pi / 8), "round": (14, 0.0)}[dome]
    R = gw * 0.75 / math.cos(math.pi / seg)
    prof = [(R * 0.92, 0.0), (R * 1.06, R * 0.35), (R * 1.02, R * 0.7), (R * 0.75, R * 1.05), (R * 0.32, R * 1.25), (0.0, R * 1.3)]
    m.lathe(prof, seg, ARCH[3], y=yy + 0.9, rot=rot, cols=[ARCH[3], BANDS[2], ARCH[3], BANDS[2], ARCH[3]])
    # Nasi arches on four sides of the dome.
    for k in range(4):
        a = k * math.pi / 2 + (0.0 if seg != 4 else 0.0)
        m.push((math.sin(a) * R * 0.98, 0.0, math.cos(a) * R * 0.98), yaw=a)
        outer = arch(R * 0.46, yy + 0.9 + R * 0.08, yy + 0.9 + R * 0.4, "horseshoe", n=4)
        inner = arch(R * 0.28, yy + 0.9 + R * 0.16, yy + 0.9 + R * 0.4, "horseshoe", n=4)
        m.extrude(outer, -0.3, 0.12, STUCCO_WHITE, back=False, holes=[inner])
        m.flat(inner, -0.05, BANDS[1])
        m.pop()
    kalasam(m, 0.0, yy + 0.9 + R * 1.28, 0.0, 0.9)
    m.pop()


def mandapam(m: LM, rng: random.Random, x0: float, x1: float, z0: float, z1: float, h: float,
             open_sides: str = "", figures: bool = True) -> None:
    """Flat-roofed hall: kaavi-striped walls (or granite pillars on `open_sides`, any of n s e w),
    red-oxide terrace, a white parapet with stucco figure groups and little pavilions."""
    corners = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    sides = {"n": (corners[0], corners[1]), "e": (corners[1], corners[2]), "s": (corners[2], corners[3]), "w": (corners[3], corners[0])}
    for key, (a, b) in sides.items():
        if key in open_sides:
            ln = math.hypot(b[0] - a[0], b[1] - a[1])
            n = max(2, int(ln / 3.0))
            for k in range(n + 1):
                px = a[0] + (b[0] - a[0]) * k / n
                pz = a[1] + (b[1] - a[1]) * k / n
                m.ybox(px - 0.3, px + 0.3, 0.0, h - 0.6, pz - 0.3, pz + 0.3, GRANITE_L)
                m.ybox(px - 0.45, px + 0.45, h - 0.9, h - 0.6, pz - 0.45, pz + 0.45, GRANITE)
        else:
            stripe_wall(m, b, a, 0.0, h - 0.6)
    # Inner dark (seen through open sides).
    m.ybox(x0 + 1.2, x1 - 1.2, 0.0, h - 0.6, z0 + 1.2, z1 - 1.2, (104, 92, 82), skip="-y+y")
    m.ybox(x0 - 0.3, x1 + 0.3, h - 0.6, h - 0.25, z0 - 0.3, z1 + 0.3, GRANITE)
    m.ybox(x0 - 0.15, x1 + 0.15, h - 0.25, h - 0.18, z0 - 0.15, z1 + 0.15, RED_OXIDE, skip="-y")
    # Parapet.
    for (a, b) in sides.values():
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        ux, uz = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        m.push(((a[0] + b[0]) / 2, h - 0.25, (a[1] + b[1]) / 2), yaw=math.atan2(uz, -ux) + math.pi)
        m.ybox(-ln / 2, ln / 2, 0.0, 0.55, -0.12, 0.12, STUCCO_WHITE)
        if figures and ln > 6.0:
            n = max(1, int(ln / 7.0))
            for k in range(n):
                px = -ln / 2 + ln * (k + 0.5) / n
                if k % 3 == 1:
                    for d in (-0.55, 0.0, 0.55):
                        m.push((px + d, 0.55, 0.0), yaw=math.pi, scale=1.15 / 1.02)
                        figure(m, rng, "stand")
                        m.pop()
                else:
                    kuta(m, px, 0.55, 0.0, 0.8, ARCH[rng.randrange(len(ARCH))], BANDS[rng.randrange(len(BANDS))])
        m.pop()
    m.collider(((x0 + x1) / 2, h / 2, (z0 + z1) / 2), (x1 - x0, h, z1 - z0))


# ================================================================= Kapaleeshwarar temple

# Temple frame: the Mylapore street grid runs 15 deg off east (North Mada St, Sannadhi St). The
# block between North Mada St, East Tank Square St, Kumara Gurunatha St and Ponnambalam Vathiyar
# St is u 0..94, v 0..110 from (u, v) = (1530, 1269) in that rotated frame; the mapped temple
# structures (OSM ways 208567685..211277743) and Sannadhi Street place the east rajagopuram at
# (88, 66) and the west gopuram at (9.5, 61.5). Model origin = block point (50, 58).
KAPALI_ROT_DEG = 15.0
KAPALI_UV0 = (1530.0 + 50.0, 1269.0 + 58.0)


def _uv_world(u: float, v: float, deg: float):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (u * c - v * s, u * s + v * c)


KAPALI_ORIGIN = _uv_world(*KAPALI_UV0, KAPALI_ROT_DEG)


def kapaleeshwarar() -> LM:
    m = LM()
    rng = random.Random(1906)
    L = lambda u, v: (u - 50.0, v - 58.0)  # noqa: E731  block (u, v) -> model (x, z)
    # Courtyard paving inside the compound.
    x0, z0 = L(7.0, 12.0)
    x1, z1 = L(90.0, 105.0)
    m.quad((x0, 0.04, z0), (x1, 0.04, z0), (x1, 0.04, z1), (x0, 0.04, z1), PAVING, (0, 1, 0))
    # East rajagopuram (7 tiers, ~38 m to the kalasam tips), facing east.
    gx, gz = L(88.0, 66.0)
    m.push((gx, 0.0, gz), yaw=math.pi / 2)
    tip = gopuram(m, rng, W=24.0, D=13.0, base_h=10.2, tiers=7, tier_h=3.15, top_w=10.4, top_d=4.4, n_kal=9, fig_h=1.75)
    m.pop()
    print(f"  east rajagopuram top {tip:.1f} m")
    # West gopuram (5 tiers) facing the tank.
    gx, gz = L(9.5, 61.5)
    m.push((gx, 0.0, gz), yaw=-math.pi / 2)
    tip = gopuram(m, rng, W=16.0, D=9.0, base_h=6.8, tiers=5, tier_h=2.55, top_w=6.6, top_d=3.0, n_kal=7, fig_h=1.3)
    m.pop()
    print(f"  west gopuram top {tip:.1f} m")
    # Halls round the courtyard (from the mapped footprints), flat red-oxide terraces.
    def hall(u0: float, u1: float, v0: float, v1: float, h: float, open_sides: str) -> None:
        mandapam(m, rng, u0 - 50.0, u1 - 50.0, v0 - 58.0, v1 - 58.0, h, open_sides)

    hall(12.0, 84.0, 14.0, 21.0, 5.2, "s")     # north cloister along North Mada St
    hall(22.0, 61.0, 88.0, 98.0, 6.4, "n")     # long south hall
    hall(62.0, 80.0, 82.0, 102.0, 6.0, "w")    # south-east hall
    hall(12.0, 21.0, 75.0, 102.0, 5.4, "e")    # south-west hall
    # The main shrine enclosure (Kapaleeshwarar, facing west) and its terrace.
    hall(27.0, 74.0, 48.0, 76.0, 6.6, "w")
    # Karpagambal's shrine to the north (faces south) and the Singaravelar shrine to the south.
    hall(27.0, 45.0, 31.0, 45.0, 6.0, "s")
    hall(40.0, 60.0, 77.5, 84.0, 5.6, "n")
    vx, vz = L(62.0, 62.0)
    vimana(m, rng, vx, vz, 6.6, 7.0, 2, "square", yaw=-math.pi / 2)
    vx, vz = L(36.0, 37.0)
    vimana(m, rng, vx, vz, 6.0, 5.6, 2, "octagon", yaw=0.0)
    vx, vz = L(44.0, 80.8)
    vimana(m, rng, vx, vz, 5.6, 4.0, 1, "round", yaw=0.0)
    # Smaller shrines in the corners.
    for (u, v, dome) in ((80.0, 26.0, "square"), (20.0, 28.0, "round"), (84.0, 76.0, "octagon")):
        vx, vz = L(u, v)
        m.ybox(vx - 2.4, vx + 2.4, 0.0, 3.6, vz - 2.4, vz + 2.4, GRANITE)
        vimana(m, rng, vx, vz, 3.6, 3.4, 1, dome)
        m.collider((vx, 1.8, vz), (4.8, 3.6, 4.8))
    # Golden flagstaff, bali peetam and the Nandi pavilion west of the sanctum (all facing it).
    fx, fz = L(22.5, 62.0)
    m.ybox(fx - 1.2, fx + 1.2, 0.0, 1.2, fz - 1.2, fz + 1.2, GRANITE_L)
    m.ybox(fx - 0.9, fx + 0.9, 1.2, 1.6, fz - 0.9, fz + 0.9, GOLD_D)
    m.prism(8, 0.34, 0.22, 1.6, 15.5, GOLD, cx=fx, cz=fz, rot=math.pi / 8)
    for yy in (3.5, 6.5, 9.5, 12.5):
        m.prism(8, 0.42, 0.42, yy, yy + 0.2, GOLD_D, bottom=True, cx=fx, cz=fz, rot=math.pi / 8)
    m.ybox(fx - 0.15, fx + 0.15, 15.2, 15.5, fz - 0.9, fz + 0.9, GOLD)
    for d in (-0.7, 0.0, 0.7):
        m.bar((fx, 15.5, fz + d), (fx, 16.2, fz + d), 0.06, GOLD, 4)
    m.lathe([(0.6, 0.0), (0.7, 0.4), (0.4, 0.7), (0.5, 1.0), (0.0, 1.1)], 8, GRANITE_L, cx=fx + 1.8, cz=fz)  # bali peetam
    m.collider((fx, 7.0, fz), (2.4, 14.0, 2.4))
    nx, nz = L(17.0, 62.0)
    m.ybox(nx - 2.2, nx + 2.2, 0.0, 0.9, nz - 2.2, nz + 2.2, GRANITE)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            m.ybox(nx + sx * 1.8 - 0.22, nx + sx * 1.8 + 0.22, 0.9, 4.2, nz + sz * 1.8 - 0.22, nz + sz * 1.8 + 0.22, GRANITE_L)
    m.ybox(nx - 2.4, nx + 2.4, 4.2, 4.6, nz - 2.4, nz + 2.4, GRANITE)
    kuta(m, nx, 4.6, nz, 2.0, ARCH[0], BANDS[0])
    m.push((nx, 0.9, nz), yaw=math.pi / 2, scale=1.7)
    nandi(m)
    m.pop()
    m.collider((nx, 2.3, nz), (4.8, 4.6, 4.8))
    return m


def tank_mandapam() -> LM:
    """Neerazhi mandapam in the middle of the tank: striped plinth, 16 granite pillars behind a
    grille, granite roof, a small painted vimana on top (owner photo from the tank bank)."""
    m = LM()
    rng = random.Random(16)
    S = 10.0
    h = S / 2
    for face in ((-h, -h, h, -h), (h, -h, h, h), (h, h, -h, h), (-h, h, -h, -h)):
        stripe_wall(m, (face[0], face[1]), (face[2], face[3]), -1.2, 1.5, band=0.8)
    m.ybox(-h, h, 1.5, 1.7, -h, h, KAAVI_WHITE)
    m.ybox(-h + 0.4, h - 0.4, 1.7, 1.9, -h + 0.4, h - 0.4, GRANITE_L)
    for i in range(4):
        for j in range(4):
            px, pz = -3.6 + 2.4 * i, -3.6 + 2.4 * j
            m.ybox(px - 0.28, px + 0.28, 1.9, 5.2, pz - 0.28, pz + 0.28, GRANITE_L)
            m.ybox(px - 0.4, px + 0.4, 4.9, 5.2, pz - 0.4, pz + 0.4, GRANITE)
    # Grille between the outer pillars.
    for a, b in (((-3.6, -3.6), (3.6, -3.6)), ((3.6, -3.6), (3.6, 3.6)), ((3.6, 3.6), (-3.6, 3.6)), ((-3.6, 3.6), (-3.6, -3.6))):
        n = 36
        for k in range(1, n):
            t = k / n
            px, pz = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            m.bar((px, 1.9, pz), (px, 4.6, pz), 0.025, (70, 74, 78), 4)
        m.bar((a[0], 4.6, a[1]), (b[0], 4.6, b[1]), 0.04, (70, 74, 78), 4)
        m.bar((a[0], 2.0, a[1]), (b[0], 2.0, b[1]), 0.04, (70, 74, 78), 4)
    m.ybox(-1.4, 1.4, 1.9, 4.6, -1.4, 1.4, (78, 70, 64))
    m.ybox(-4.5, 4.5, 5.2, 5.75, -4.5, 4.5, GRANITE)
    m.rfrustum(9.0, 9.0, 9.8, 9.8, 5.75, 6.05, GRANITE_L)
    m.ybox(-4.9, 4.9, 6.05, 6.25, -4.9, 4.9, KAAVI_WHITE)
    vimana(m, rng, 0.0, 0.0, 6.25, 4.2, 1, "square")
    m.collider((0.0, 2.0, 0.0), (S, 6.0, S))
    return m


# ================================================================= Senate House

# University of Madras Senate House (1879, Robert Chisholm; owner reference photos, Nov 27):
# Indo-Saracenic red brick. A great hall under a steep red-tiled roof, four square corner towers
# whose tall faces carry red-and-cream striped horseshoe arches with stained glass, each crowned
# by a white lace cornice and an orange Byzantine (onion) dome patterned in white; a porch with
# three striped arches at each end, flanked by slim octagonal turrets with little domes; low
# arcaded verandahs along both long sides; rows of small white domed pinnacles at the eaves.
# Local frame: x along the long axis (+x = north), z across (+z = east, Kamarajar Salai and
# the sea), origin at the centre of the OSM footprint (way seed 9138, 93 x 31 m).
SENATE_ORIGIN = (2594.3, -1778.55)
SENATE_AXIS_DEG = -79.33
SENATE_FOOTPRINT = [(2570.2, -1735.7), (2601.1, -1729.6), (2618.4, -1821.4), (2587.5, -1827.5)]


def senate_campus():
    """The lawn between Senate House and Kamarajar Salai (owner, Nov 27: it must be seen from the
    road): infill buildings in it are cleared (\"clear_fill\"); local x -62..62, z -26..62 (to the kerb)."""
    ax = math.radians(SENATE_AXIS_DEG)
    ux, uz = math.cos(ax), math.sin(ax)      # local +x (north)
    vx, vz = -uz, ux                          # local +z (east, the road)
    ox, oz = SENATE_ORIGIN
    return [(ox + lx * ux + lz * vx, oz + lx * uz + lz * vz) for lx, lz in ((-62, -26), (62, -26), (62, 62), (-62, 62))]

SH_BRICK = (198, 98, 64)
SH_BRICK_D = (178, 84, 56)
SH_BRICK_L = (212, 116, 80)
SH_CREAM = (236, 224, 200)
SH_LACE = (246, 242, 232)
SH_STONE = (168, 150, 130)
SH_DOME = (230, 140, 82)
SH_DOME_D = (210, 120, 70)
SH_TILE = (178, 76, 50)
SH_TILE2 = (160, 66, 44)
SH_RECESS = (60, 38, 32)
SH_GLASS = [(48, 60, 84), (128, 52, 46), (56, 96, 132), (176, 140, 60), (60, 104, 76)]

HALL_X = 27.5       # hall half length (tower centres)
HALL_Z = 9.5        # hall half width
SH_EAVE = 15.5
SH_RIDGE = 22.5
TW = 4.4            # tower half size
TW_TOP = 23.5
VER_Z = 13.6        # verandah outer face
VER_H = 9.0
PORCH_X0 = HALL_X + TW
PORCH_X1 = PORCH_X0 + 7.8
PORCH_Z = 7.2
PORCH_H = 11.6


def striped_arch(m: LM, x: float, y0: float, w: float, spring: float, depth: float = 0.25,
                 band: float = 0.55, n: int = 9, fill=SH_RECESS, glass: bool = False, kind: str = "horseshoe") -> None:
    """Saracenic opening in the wall plane z = 0, facing +z: alternating red / cream voussoirs."""
    h = w / 2.0
    if kind == "horseshoe":
        r = h * 1.1
        cy = spring + math.sqrt(r * r - h * h)
        a0 = math.atan2(spring - cy, h)
    else:  # round
        r, cy, a0 = h, spring, 0.0
    a1 = math.pi - a0
    arc = [(r * math.cos(a0 + (a1 - a0) * i / (2 * n)), cy + r * math.sin(a0 + (a1 - a0) * i / (2 * n))) for i in range(2 * n + 1)]
    opening = [(-h, y0), (h, y0)] + arc
    m.push((x, 0.0, 0.0))
    m.flat(opening, 0.02, fill)
    if glass:
        # Three tall lights with coloured panes, white mullions.
        top = cy + r * 0.55
        for k in range(3):
            lx = -h * 0.62 + k * h * 0.62
            for row in range(int((top - y0 - 0.4) / 0.9)):
                yy = y0 + 0.3 + row * 0.9
                m.flat([(lx - h * 0.24, yy), (lx + h * 0.24, yy), (lx + h * 0.24, yy + 0.8), (lx - h * 0.24, yy + 0.8)], 0.04,
                       SH_GLASS[(k * 3 + row) % len(SH_GLASS)])
    # Jambs.
    for s in (-1.0, 1.0):
        m.ybox(s * h - 0.18, s * h + 0.18, y0, spring, -0.02, depth, SH_CREAM)
    # Voussoirs: quads between the arc and an outer ring, alternating colours.
    for i in range(2 * n):
        (ax, ay), (bx, by) = arc[i], arc[i + 1]
        oa = ((ax) * (r + band) / r, cy + (ay - cy) * (r + band) / r)
        ob = ((bx) * (r + band) / r, cy + (by - cy) * (r + band) / r)
        col = SH_CREAM if i % 2 == 0 else (168, 58, 42)
        m.extrude([(ax, ay), (bx, by), ob, oa], 0.0, depth, col, back=False)
    m.pop()


def pointed_opening(m: LM, x: float, y0: float, w: float, spring: float, col=SH_RECESS, frame: float = 0.22,
                    depth: float = 0.2, rise=None) -> None:
    inner = arch(w, y0, spring, "pointed", n=5, rise=rise)
    m.push((x, 0.0, 0.0))
    m.flat(inner, 0.02, col)
    m.extrude(offset(inner, frame), 0.0, depth, SH_CREAM, back=False, holes=[inner])
    m.pop()


def crenels(m: LM, x0: float, x1: float, y: float, h: float = 0.9, step: float = 0.9, depth: float = 0.35, col=SH_LACE) -> None:
    """White Saracenic parapet along the wall plane z = 0: a coping strip with stepped merlons."""
    m.ybox(x0, x1, y, y + 0.35, -depth, 0.12, col)
    k = 0
    xx = x0
    while xx + step * 0.6 <= x1 + 1e-6:
        mx = xx + step * 0.3
        m.extrude([(mx - step * 0.28, y + 0.35), (mx + step * 0.28, y + 0.35), (mx + step * 0.28, y + h * 0.7),
                   (mx, y + h), (mx - step * 0.28, y + h * 0.7)], -depth + 0.1, 0.1, col, back=False)
        xx += step
        k += 1


def onion_dome(m: LM, cx: float, y: float, cz: float, r: float, seg: int = 16, col=SH_DOME, lace=SH_LACE) -> None:
    """Byzantine dome: bulbous profile, horizontal white lace bands, a spike finial."""
    prof = [(r * 0.9, 0.0), (r * 0.98, 0.18 * r), (r * 1.1, 0.5 * r), (r * 1.14, 0.8 * r), (r * 1.06, 1.1 * r),
            (r * 0.88, 1.38 * r), (r * 0.64, 1.62 * r), (r * 0.4, 1.82 * r), (r * 0.18, 1.98 * r), (r * 0.06, 2.1 * r),
            (0.0, 2.16 * r)]
    # A white lace band round the base, orange above it, a thin white collar near the top.
    cols = [lace, lace, col, SH_DOME_D, col, col, col, lace, col, col]
    m.lathe(prof, seg, col, cx=cx, cz=cz, y=y, cols=cols)
    m.bar((cx, y + 2.1 * r, cz), (cx, y + 2.1 * r + r * 0.55, cz), max(0.05, r * 0.05), (190, 160, 90), 4)
    m.prism(8, r * 0.1, 0.0, y + 2.1 * r + r * 0.55, y + 2.1 * r + r * 0.75, (190, 160, 90), cx=cx, cz=cz)


def sh_turret(m: LM, cx: float, cz: float, top: float, r: float = 1.35) -> None:
    """Slim octagonal turret: brick with cream bands, an open arcaded lantern, a small dome."""
    rot = math.pi / 8
    m.prism(8, r + 0.15, r + 0.15, 0.0, 1.0, SH_STONE, top=False, rot=rot, cx=cx, cz=cz)
    y = 1.0
    k = 0
    while y < top - 2.6:
        hh = 1.4 if k % 2 == 0 else 0.35
        m.prism(8, r, r, y, min(y + hh, top - 2.6), SH_BRICK if k % 2 == 0 else SH_CREAM, top=False, rot=rot, cx=cx, cz=cz)
        y += hh
        k += 1
    m.prism(8, r + 0.22, r + 0.22, top - 2.6, top - 2.4, SH_LACE, top=True, bottom=True, rot=rot, cx=cx, cz=cz)
    # Lantern: eight slim posts with striped arch heads.
    for i in range(8):
        a = rot + i * math.pi / 4
        px, pz = cx + math.cos(a) * r * 0.85, cz + math.sin(a) * r * 0.85
        m.ybox(px - 0.11, px + 0.11, top - 2.4, top - 0.7, pz - 0.11, pz + 0.11, SH_LACE)
    m.prism(8, r * 0.55, r * 0.55, top - 2.4, top - 0.7, SH_RECESS, top=False, rot=rot, cx=cx, cz=cz)
    m.prism(8, r + 0.12, r + 0.12, top - 0.7, top - 0.2, SH_BRICK, top=True, rot=rot, cx=cx, cz=cz,
            cols=[SH_BRICK, SH_CREAM])
    onion_dome(m, cx, top - 0.2, cz, r * 0.82, seg=10)


def sh_pinnacle(m: LM, x: float, y: float, z: float, s: float = 0.32) -> None:
    m.prism(6, s, s, y, y + 0.9, SH_LACE, top=False, cx=x, cz=z)
    m.lathe([(s * 1.1, 0.0), (s * 1.25, 0.3), (s * 0.9, 0.62), (s * 0.4, 0.85), (0.0, 1.0)], 6, SH_LACE, cx=x, cz=z, y=y + 0.9)


def sh_tower(m: LM, tx: float, tz: float) -> None:
    m.ybox(tx - TW - 0.3, tx + TW + 0.3, 0.0, 1.0, tz - TW - 0.3, tz + TW + 0.3, SH_STONE)
    m.ybox(tx - TW, tx + TW, 1.0, TW_TOP, tz - TW, tz + TW, SH_BRICK, skip="-y")
    m.collider((tx, TW_TOP / 2, tz), (2 * TW + 0.6, TW_TOP, 2 * TW + 0.6))
    for y, hh in ((7.6, 0.3), (14.6, 0.35)):
        course(m, tx - TW, tx + TW, tz - TW, tz + TW, y, hh, 0.14, SH_CREAM)
    # Corner piers: slightly proud, with cream quoin bands.
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            px, pz = tx + sx * (TW - 0.35), tz + sz * (TW - 0.35)
            m.ybox(px - 0.55, px + 0.55, 1.0, TW_TOP + 0.4, pz - 0.55, pz + 0.55, SH_BRICK_D)
            for y in range(2, int(TW_TOP), 3):
                m.ybox(px - 0.58, px + 0.58, y, y + 0.35, pz - 0.58, pz + 0.58, SH_CREAM)
            sh_pinnacle(m, px, TW_TOP + 1.25, pz, 0.38)
    for face, fx, fz in (("-x", tx - TW, tz), ("+x", tx + TW, tz), ("-z", tx, tz - TW), ("+z", tx, tz + TW)):
        wall_frame(m, face, fx, fz)
        pointed_opening(m, 0.0, 2.2, 1.6, 4.8)
        striped_arch(m, 0.0, 8.4, 2.4, 11.6, band=0.42, n=7, glass=True)
        # The tall striped horseshoe arch with stained glass (the reference photos' signature).
        striped_arch(m, 0.0, 15.3, 4.4, 20.0, band=0.62, n=9, glass=True)
        # Small roundels either side, like the wheel ornaments on the towers.
        for s in (-1.0, 1.0):
            m.flat(circle(0.32, s * 2.9, 17.6, 8), 0.06, SH_CREAM)
            m.flat(circle(0.2, s * 2.9, 17.6, 8), 0.08, SH_BRICK_D)
        m.pop()
    # White lace cornice and crown.
    m.ybox(tx - TW - 0.35, tx + TW + 0.35, TW_TOP, TW_TOP + 0.8, tz - TW - 0.35, tz + TW + 0.35, SH_LACE)
    for face, fx, fz in (("-x", tx - TW - 0.35, tz), ("+x", tx + TW + 0.35, tz), ("-z", tx, tz - TW - 0.35), ("+z", tx, tz + TW + 0.35)):
        wall_frame(m, face, fx, fz)
        crenels(m, -TW - 0.35, TW + 0.35, TW_TOP + 0.8, h=0.75, step=0.95, depth=0.3)
        m.pop()
    # Octagonal drum: cream with striped little arches, then the onion dome.
    rot = math.pi / 8
    R = TW * 0.86
    m.prism(8, R, R, TW_TOP + 0.8, TW_TOP + 3.2, SH_LACE, top=True, rot=rot, cx=tx, cz=tz)
    apo = R * math.cos(math.pi / 8)
    for k in range(8):
        a = rot + math.pi / 8 + k * math.pi / 4
        m.push((tx + math.cos(a) * apo, 0.0, tz + math.sin(a) * apo), yaw=math.atan2(math.cos(a), math.sin(a)))
        striped_arch(m, 0.0, TW_TOP + 1.2, 1.1, TW_TOP + 2.3, depth=0.12, band=0.22, n=4)
        m.pop()
    m.prism(8, R + 0.2, R + 0.2, TW_TOP + 3.2, TW_TOP + 3.5, SH_DOME_D, top=True, bottom=True, rot=rot, cx=tx, cz=tz)
    onion_dome(m, tx, TW_TOP + 3.5, tz, R * 0.98, seg=16)


def senate() -> LM:
    m = LM()
    # ---- Great hall: plinth, walls, roof.
    m.ybox(-HALL_X, HALL_X, 0.0, 1.0, -HALL_Z - 0.2, HALL_Z + 0.2, SH_STONE)
    m.ybox(-HALL_X, HALL_X, 1.0, SH_EAVE, -HALL_Z, HALL_Z, SH_BRICK, skip="-y")
    m.collider((0.0, SH_EAVE / 2, 0.0), (2 * HALL_X, SH_EAVE, 2 * VER_Z))
    course(m, -HALL_X, HALL_X, -HALL_Z, HALL_Z, SH_EAVE - 0.5, 0.5, 0.25, SH_LACE)
    gable_roof(m, -HALL_X + TW, HALL_X - TW, 0.0, HALL_Z, SH_EAVE, SH_RIDGE, over=0.6, strips=9, col=SH_TILE, col2=SH_TILE2)
    # Gable ends behind the porches: brick, a great striped window, a white coped edge.
    for face, x in (("-x", -HALL_X + TW), ("+x", HALL_X - TW)):
        wall_frame(m, face, x, 0.0)
        m.extrude([(-HALL_Z, SH_EAVE), (HALL_Z, SH_EAVE), (0.0, SH_RIDGE + 0.3)], -0.4, 0.0, SH_BRICK, back=False)
        for s in (-1.0, 1.0):
            m.bar((s * (HALL_Z + 0.2), SH_EAVE, 0.08), (0.0, SH_RIDGE + 0.55, 0.08), 0.2, SH_LACE, 4)
        sh_pinnacle(m, 0.0, SH_RIDGE + 0.4, 0.0, 0.4)
        m.pop()
    for face, x in (("-x", -HALL_X - TW), ("+x", HALL_X + TW)):
        wall_frame(m, face, x, 0.0)
        striped_arch(m, 0.0, PORCH_H + 0.9, 5.6, SH_EAVE + 1.0, band=0.7, n=10, glass=True)
        m.pop()
    # ---- Long sides: clerestory windows over arcaded verandahs.
    bays = 9
    span = 2 * (HALL_X - TW) / bays
    for sz in (-1.0, 1.0):
        face = "+z" if sz > 0 else "-z"
        # Clerestory (hall wall above the verandah roof).
        wall_frame(m, face, 0.0, sz * HALL_Z)
        for b in range(bays):
            bx = -(HALL_X - TW) + span * (b + 0.5)
            striped_arch(m, bx, VER_H + 1.4, 2.0, VER_H + 3.6, band=0.36, n=6, glass=True)
        m.pop()
        # Verandah block.
        z0, z1 = sorted((sz * HALL_Z, sz * VER_Z))
        m.ybox(-HALL_X + TW, HALL_X - TW, 0.0, 0.9, z0, z1 + (0.25 if sz > 0 else -0.25) * 0, SH_STONE)
        m.ybox(-HALL_X + TW, HALL_X - TW, 0.9, VER_H, z0, z1, SH_BRICK, skip="-y")
        m.ybox(-HALL_X + TW, HALL_X - TW, VER_H - 0.05, VER_H + 0.25, z0 - 0.2, z1 + 0.2, SH_CREAM)
        wall_frame(m, face, 0.0, sz * VER_Z)
        for b in range(bays):
            bx = -(HALL_X - TW) + span * (b + 0.5)
            pointed_opening(m, bx, 0.9, span * 0.62, 5.0, frame=0.3, depth=0.25)
            # Cream pier capitals between the arches.
            if b > 0:
                px = bx - span * 0.5
                m.ybox(px - 0.45, px + 0.45, 4.8, 5.2, -0.05, 0.3, SH_CREAM)
        crenels(m, -HALL_X + TW, HALL_X - TW, VER_H + 0.25, h=0.85, step=0.9)
        m.pop()
        # Small white domed pinnacles along the hall eave (the row seen in the aerial photos).
        for b in range(bays + 1):
            bx = -(HALL_X - TW) + span * b
            sh_pinnacle(m, bx, SH_EAVE, sz * (HALL_Z + 0.1), 0.3)
    # ---- Corner towers.
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            sh_tower(m, sx * HALL_X, sz * (HALL_Z + 0.6))
    # ---- End porches with three striped arches, turrets at their corners.
    for sx in (-1.0, 1.0):
        x0, x1 = sorted((sx * PORCH_X0, sx * PORCH_X1))
        m.ybox(x0, x1, 0.0, 0.9, -PORCH_Z - 0.2, PORCH_Z + 0.2, SH_STONE)
        m.ybox(x0, x1, 0.9, PORCH_H, -PORCH_Z, PORCH_Z, SH_BRICK, skip="-y")
        m.collider(((x0 + x1) / 2, PORCH_H / 2, 0.0), (x1 - x0, PORCH_H, 2 * PORCH_Z))
        course(m, x0, x1, -PORCH_Z, PORCH_Z, PORCH_H - 0.4, 0.4, 0.2, SH_LACE)
        face = "+x" if sx > 0 else "-x"
        wall_frame(m, face, sx * PORCH_X1, 0.0)
        striped_arch(m, 0.0, 0.9, 4.4, 6.4, depth=0.3, band=0.75, n=10)
        for s in (-1.0, 1.0):
            striped_arch(m, s * 4.6, 0.9, 2.6, 4.9, depth=0.3, band=0.55, n=8)
            # Cusped (multifoil) hood: a cream band round the outer arches.
        crenels(m, -PORCH_Z, PORCH_Z, PORCH_H, h=0.9, step=0.9)
        m.pop()
        for sz in (-1.0, 1.0):
            wall_frame(m, "+z" if sz > 0 else "-z", (x0 + x1) / 2, sz * PORCH_Z)
            striped_arch(m, 0.0, 0.9, 3.0, 5.0, depth=0.3, band=0.55, n=8)
            crenels(m, -(x1 - x0) / 2, (x1 - x0) / 2, PORCH_H, h=0.9, step=0.9)
            m.pop()
            sh_turret(m, sx * (PORCH_X1 - 0.6), sz * (PORCH_Z + 0.4), 17.5)
            # Inner turrets where the porch meets the towers.
            sh_turret(m, sx * (PORCH_X0 + 1.0), sz * (PORCH_Z + 0.2), 15.0, r=0.95)
    # The lawn between the hall and Kamarajar Salai (owner: it must be seen from the road), a
    # drive from the gate, flower beds and trimmed hedges along the verandahs.
    lawn = (86, 140, 62)
    lawn2 = (78, 128, 56)
    for k, (z0, z1) in enumerate(((VER_Z + 1.2, 54.0), (-24.0, -VER_Z - 1.2))):
        for j in range(6):
            x0 = -48.0 + j * 16.0
            m.flat_y(x0, x0 + 16.0, z0, z1, 0.05, lawn if (j + k) % 2 == 0 else lawn2)
    m.flat_y(-2.6, 2.6, VER_Z + 0.2, 58.0, 0.07, (204, 196, 178))
    m.flat_y(-40.0, 40.0, VER_Z + 0.2, VER_Z + 1.4, 0.07, (204, 196, 178))
    for sx in (-1.0, 1.0):
        m.ybox(sx * 3.2 - 0.4, sx * 3.2 + 0.4, 0.0, 0.7, VER_Z + 3.0, 52.0, (52, 104, 44))
        for k in range(5):
            m.ybox(sx * 12.0 + k * sx * 6.0 - 1.2, sx * 12.0 + k * sx * 6.0 + 1.2, 0.05, 0.3, 24.0, 27.0, (196, 60, 70) if k % 2 else (236, 190, 60))
    # Steps up to each porch.
    for sx in (-1.0, 1.0):
        for k in range(3):
            xa = sx * (PORCH_X1 + 0.5 * (3 - k))
            x0, x1 = sorted((xa, sx * PORCH_X1))
            m.ybox(x0, x1, 0.0, 0.3 * (k + 1), -3.0, 3.0, SH_STONE)
    return m


# ================================================================= Chepauk Palace

# Chepauk Palace (Nawab of Arcot, 1768; Paul Benfield; reworked by Robert Chisholm 1868-71), from
# Wikipedia, TN Tourism, Madras Musings and photos (Nov 27): two red-brick, white-trimmed
# Indo-Saracenic blocks. Kalas Mahal (south, restored 2017) is two storeys with arcaded verandahs,
# a white balustraded parapet and minareted entrances on its west and south sides. Humayun Mahal
# (north) got a first floor and a Madras terrace from Chisholm, its new front matching Kalas Mahal,
# a new east entrance facing the beach, and the tall striped tower (~75 ft) built in front of it.
# Each block is built on its real OSM footprint (seeds 3505 / 3507), local frame = world axes.
CP_RED = (200, 86, 60)
CP_RED_D = (176, 70, 50)
CP_WHITE = (240, 236, 224)
CP_DOME = (238, 234, 222)
HUMAYUN_FOOTPRINT = [(2428.0, -1700.0), (2427.6, -1698.3), (2425.8, -1698.7), (2412.6, -1645.1), (2476.9, -1629.4), (2490.6, -1684.8)]
KALAS_FOOTPRINT = [(2456.6, -1618.2), (2452.2, -1619.2), (2438.4, -1560.6), (2450.3, -1557.7), (2448.6, -1550.5), (2442.0, -1552.2),
                   (2436.8, -1530.5), (2472.7, -1521.7), (2477.7, -1543.1), (2472.8, -1544.3), (2474.6, -1551.9), (2481.8, -1550.1),
                   (2495.6, -1608.7), (2466.8, -1615.8), (2469.3, -1626.5), (2459.1, -1629.0)]


def _centroid(poly):
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def _local(poly):
    cx, cz = _centroid(poly)
    pts = [(x - cx, z - cz) for x, z in poly]
    # Drop slivers (< 2.5 m edges) so every wall gets real bays.
    out = []
    for p in pts:
        if not out or math.dist(out[-1], p) > 2.5:
            out.append(p)
    if math.dist(out[0], out[-1]) < 2.5:
        out.pop()
    return out


def _ccw(poly):
    area = sum(poly[i - 1][0] * poly[i][1] - poly[i][0] * poly[i - 1][1] for i in range(len(poly)))
    return poly if area > 0 else list(reversed(poly))


def _roof(m: LM, poly, y: float, col) -> None:
    pts = np.array(poly, dtype=np.float64)
    idx = earcut.triangulate_float64(pts, np.array([len(poly)], dtype=np.uint32))
    for t in range(0, len(idx), 3):
        a, b, c = (poly[int(idx[t + k])] for k in range(3))
        m.tri((a[0], y, a[1]), (c[0], y, c[1]), (b[0], y, b[1]), col, (0, 1, 0))


def palace_block(m: LM, poly, h: float, rng: random.Random, minar_h: float) -> list:
    """Red Indo-Saracenic block on a footprint: arcaded ground floor, arched first-floor windows,
    white string courses, balustraded parapet with pinnacles, a slim minaret at every corner.
    Returns the walls as (a, b, outward normal) for the features added afterwards."""
    poly = _ccw(poly)
    n = len(poly)
    m.collider((0.0, h / 2, 0.0), (1.0, 1.0, 1.0))  # replaced below by per-wall boxes
    m.boxes.pop()
    walls_out = []
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        ex, ez = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(ex, ez)
        # CCW in (x, z) with z pointing south: outward is (ez, -ex) / ln.
        nx, nz = ez / ln, -ex / ln
        yaw = math.atan2(nx, nz)  # local +z = outward
        walls_out.append((a, b, (nx, nz)))
        # Frame at the wall's midpoint, local +x along the wall.
        mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        m.push((mx, 0.0, mz), yaw=yaw)
        hl = ln / 2
        m.ybox(-hl, hl, 0.0, 0.8, -0.6, 0.15, SH_STONE)
        m.quad((-hl, 0.8, 0.0), (hl, 0.8, 0.0), (hl, h, 0.0), (-hl, h, 0.0), CP_RED, (0, 0, 1))
        bays = max(1, int(round(ln / 3.8)))
        bw = ln / bays
        for k in range(bays):
            bx = -hl + bw * (k + 0.5)
            if ln >= 3.0:
                pointed_opening(m, bx, 0.8, bw * 0.62, 3.6, frame=0.26, depth=0.22, rise=bw * 0.42)
                if h > 8.0:
                    pointed_opening(m, bx, 6.0, bw * 0.42, 8.0, col=(70, 44, 36), frame=0.2, depth=0.16)
                    # Jharokha hood over the first-floor window.
                    m.ybox(bx - bw * 0.36, bx + bw * 0.36, 9.3, 9.5, -0.05, 0.55, CP_WHITE)
            if k > 0:
                px = -hl + bw * k
                m.ybox(px - 0.32, px + 0.32, 0.8, h - 0.4, -0.05, 0.28, CP_RED_D)
        for y, hh in ((5.0, 0.4), (h - 0.6, 0.6)):
            m.ybox(-hl - 0.1, hl + 0.1, y, y + hh, -0.05, 0.3, CP_WHITE)
        crenels(m, -hl, hl, h, h=0.95, step=0.85, depth=0.3, col=CP_WHITE)
        for k in range(bays + 1):
            sh_pinnacle(m, -hl + bw * k, h + 0.35, 0.0, 0.26)
        m.pop()
        # Collider: a slab along the wall (the courtyard is inside the box anyway).
        m.boxes.append(((round(mx - nx * 2.0, 3), round(h / 2, 3), round(mz - nz * 2.0, 3)), (round(ln, 3), round(h, 3), 4.0), round(yaw, 4)))
    _roof(m, poly, h - 0.05, (178, 132, 108))  # Madras terrace, brick-tile finish
    # Minarets at the convex corners.
    for i in range(n):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % n]
        cross = (p1[0] - p0[0]) * (p2[1] - p1[1]) - (p1[1] - p0[1]) * (p2[0] - p1[0])
        if cross > 0 and min(math.dist(p0, p1), math.dist(p1, p2)) > 6.0:
            cp_minaret(m, p1[0], p1[1], minar_h, 1.15)
    return walls_out


def cp_minaret(m: LM, cx: float, cz: float, top: float, r: float) -> None:
    """White-banded red octagonal minaret with balconies, a chhatri and a white dome."""
    rot = math.pi / 8
    m.prism(8, r + 0.2, r + 0.2, 0.0, 0.9, SH_STONE, top=False, rot=rot, cx=cx, cz=cz)
    y = 0.9
    for k, (hh, col) in enumerate(((top * 0.42, CP_RED), (0.35, CP_WHITE), (top * 0.25, CP_RED), (0.35, CP_WHITE))):
        rr = r if k < 2 else r * 0.85
        m.prism(8, rr, rr, y, y + hh, col, top=False, rot=rot, cx=cx, cz=cz)
        y += hh
    m.prism(8, r + 0.35, r + 0.35, y, y + 0.25, CP_WHITE, top=True, bottom=True, rot=rot, cx=cx, cz=cz)
    for i in range(8):
        a = rot + i * math.pi / 4
        px, pz = cx + math.cos(a) * r * 0.75, cz + math.sin(a) * r * 0.75
        m.ybox(px - 0.09, px + 0.09, y + 0.25, y + 1.6, pz - 0.09, pz + 0.09, CP_WHITE)
    m.prism(8, r * 0.95, r * 0.95, y + 1.6, y + 1.9, CP_WHITE, top=True, rot=rot, cx=cx, cz=cz)
    onion_dome(m, cx, y + 1.9, cz, r * 0.78, seg=10, col=CP_DOME, lace=CP_WHITE)


def cp_entrance(m: LM, a, b, nrm, h: float, minar: float, width: float = 9.0) -> None:
    """A minareted entrance: a projecting porch with a big cusped arch, two tall minarets."""
    mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    yaw = math.atan2(nrm[0], nrm[1])
    m.push((mx, 0.0, mz), yaw=yaw)
    hw = width / 2
    m.ybox(-hw, hw, 0.0, h + 1.6, 0.0, 4.0, CP_RED, skip="-y")
    m.boxes.append((tuple(round(float(v), 3) for v in m.world((0.0, (h + 1.6) / 2, 2.0))), (width, h + 1.6, 4.0), round(m.yaw_now(), 4)))
    m.push((0.0, 0.0, 4.0))
    striped_arch(m, 0.0, 0.8, width * 0.48, h * 0.42, depth=0.3, band=0.6, n=9)
    pointed_opening(m, 0.0, h * 0.62, width * 0.3, h * 0.82, col=(70, 44, 36))
    crenels(m, -hw, hw, h + 1.6, h=1.1, step=0.9, col=CP_WHITE)
    m.pop()
    for sx in (-1.0, 1.0):
        lx, lz = m.world((sx * (hw + 0.6), 0.0, 4.0))[0], m.world((sx * (hw + 0.6), 0.0, 4.0))[2]
        m.pop()
        cp_minaret(m, lx, lz, minar, 1.35)
        m.push((mx, 0.0, mz), yaw=yaw)
    m.pop()


def cp_tower(m: LM, a, b, nrm, h_base: float) -> None:
    """Chisholm's tower in front of Humayun Mahal: square, four storeys, white bands, domed top."""
    mx, mz = (a[0] + b[0]) / 2 + nrm[0] * 5.0, (a[1] + b[1]) / 2 + nrm[1] * 5.0
    S = 4.6
    top = 22.8
    m.ybox(mx - S - 0.3, mx + S + 0.3, 0.0, 0.9, mz - S - 0.3, mz + S + 0.3, SH_STONE)
    m.ybox(mx - S, mx + S, 0.9, top, mz - S, mz + S, CP_RED, skip="-y")
    m.collider((mx, top / 2, mz), (2 * S + 0.6, top, 2 * S + 0.6))
    for y in (5.2, 10.6, 16.0):
        course(m, mx - S, mx + S, mz - S, mz + S, y, 0.45, 0.16, CP_WHITE)
    for face, fx, fz in (("-x", mx - S, mz), ("+x", mx + S, mz), ("-z", mx, mz - S), ("+z", mx, mz + S)):
        wall_frame(m, face, fx, fz)
        striped_arch(m, 0.0, 0.9, 3.6, 3.8, depth=0.3, band=0.5, n=8)
        for y0, y1 in ((6.6, 9.2), (12.0, 14.6)):
            pointed_opening(m, 0.0, y0, 1.6, y1, col=(70, 44, 36))
        striped_arch(m, 0.0, 17.2, 3.0, 20.0, band=0.45, n=7, glass=True)
        crenels(m, -S - 0.2, S + 0.2, top, h=0.9, step=0.95, col=CP_WHITE)
        m.pop()
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            cp_minaret(m, mx + sx * S, mz + sz * S, top + 2.0, 0.75)
    rot = math.pi / 8
    m.prism(8, S * 0.8, S * 0.8, top, top + 2.4, CP_WHITE, top=True, rot=rot, cx=mx, cz=mz)
    onion_dome(m, mx, top + 2.4, mz, S * 0.78, seg=16, col=CP_DOME, lace=(214, 200, 176))


def chepauk_humayun() -> LM:
    m = LM()
    rng = random.Random(3505)
    poly = _local(HUMAYUN_FOOTPRINT)
    walls = palace_block(m, poly, 12.8, rng, 18.5)
    # The east entrance facing the beach, with the tower in front of it.
    east = max(walls, key=lambda w: w[2][0] * math.dist(w[0], w[1]) ** 0.2)
    cp_tower(m, east[0], east[1], east[2], 12.8)
    # The new front on Wallajah Road (north) matches Kalas Mahal: a minareted entrance.
    north = min(walls, key=lambda w: w[2][1])
    cp_entrance(m, north[0], north[1], north[2], 12.8, 21.0)
    return m


def chepauk_kalas() -> LM:
    m = LM()
    rng = random.Random(3507)
    poly = _local(KALAS_FOOTPRINT)
    walls = palace_block(m, poly, 12.4, rng, 17.5)
    # Minareted entrances on the west and south sides (Wikipedia).
    longest = lambda ws: max(ws, key=lambda w: math.dist(w[0], w[1]))  # noqa: E731
    west = longest([w for w in walls if w[2][0] < -0.7])
    south = longest([w for w in walls if w[2][1] > 0.7])
    for w in (west, south):
        cp_entrance(m, w[0], w[1], w[2], 12.4, 21.5)
    return m


# Areas the models replace (world x, z outlines): chunk buildings, trees, stalls, parked vehicles,
# kolams, dogs and shop people inside them are removed by tools/osm/clear_landmark_sites.py.
SANTHOME_FOOTPRINT = [(2014.4, 1705.1), (2037.8, 1711.1), (2036.0, 1718.3), (2057.9, 1724.0), (2061.6, 1722.6), (2062.4, 1718.9),
                      (2060.2, 1716.3), (2049.2, 1713.6), (2049.9, 1710.7), (2063.8, 1714.1), (2068.2, 1711.8), (2069.5, 1705.2),
                      (2067.1, 1702.0), (2052.3, 1698.4), (2052.7, 1696.6), (2063.9, 1699.4), (2067.1, 1698.3), (2068.2, 1693.5),
                      (2066.4, 1690.6), (2044.0, 1684.9), (2041.9, 1693.1), (2018.4, 1687.2), (2018.8, 1685.6), (2011.9, 1683.9),
                      (2011.1, 1687.0), (2006.6, 1685.8), (2003.0, 1699.8), (2006.7, 1700.8), (2005.0, 1707.4), (2013.3, 1709.5)]
# Temple compound in the block frame (u, v): the kaavi wall (build_landmark_compounds.py) runs round it.
KAPALI_COMPOUND_UV = (6.0, 91.0, 11.0, 106.0)


def kapali_clear():
    u0, u1, v0, v1 = KAPALI_COMPOUND_UV
    return [_uv_world(1530.0 + u, 1269.0 + v, KAPALI_ROT_DEG) for u, v in ((u0 - 1, v0 - 1), (u1 + 3.5, v0 - 1), (u1 + 3.5, v1 + 1), (u0 - 1, v1 + 1))]


# Tank centre and side direction from OSM way 24270420 (Kapaleeshwara Koil Kulam).
TANK_CENTRE = (1051.5, 1720.6)
TANK_AXIS_DEG = 7.6


# ================================================================= output

def world_place(origin, axis_deg: float):
    """Model placement: Godot yaw so local +x points along the axis (bearing below east)."""
    return {"x": round(origin[0], 3), "z": round(origin[1], 3), "yaw": round(-math.radians(axis_deg), 5)}


# Grounds round a model where only procedural infill ("f" buildings) and dress points go.
def chepauk_grounds():
    """The palace grounds inside the compound (build_landmark_compounds.py "chepauk_palace" rect):
    procedural infill goes, the real government buildings on the grounds stay."""
    cx, cz, w, d, yaw = 2455.0, -1612.0, 112.0, 208.0, 2.903
    c, s_ = math.cos(yaw), math.sin(yaw)
    return [(cx + lx * c + lz * s_, cz - lx * s_ + lz * c) for lx, lz in ((-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2))]


CLEAR_FILL = {"senate_house": lambda: senate_campus(), "chepauk_humayun_mahal": lambda: chepauk_grounds()}

BUILDERS = {
    "santhome_basilica": (santhome, SANTHOME_ORIGIN, SANTHOME_AXIS_DEG, lambda: SANTHOME_FOOTPRINT),
    "kapaleeshwarar_temple": (kapaleeshwarar, KAPALI_ORIGIN, KAPALI_ROT_DEG, kapali_clear),
    "kapaleeshwarar_tank_mandapam": (tank_mandapam, TANK_CENTRE, TANK_AXIS_DEG, lambda: []),
    "senate_house": (senate, SENATE_ORIGIN, SENATE_AXIS_DEG, lambda: SENATE_FOOTPRINT),
    "chepauk_humayun_mahal": (chepauk_humayun, _centroid(HUMAYUN_FOOTPRINT), 0.0, lambda: HUMAYUN_FOOTPRINT),
    "chepauk_kalas_mahal": (chepauk_kalas, _centroid(KALAS_FOOTPRINT), 0.0, lambda: KALAS_FOOTPRINT),
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()
    only = {s for s in args.only.split(",") if s}
    out = Path(args.out)
    placements = json.loads(PLACEMENTS.read_text()) if PLACEMENTS.exists() else {"models": []}
    by_id = {p["id"]: p for p in placements.get("models", [])}
    for name, (fn, origin, axis, clear) in BUILDERS.items():
        if only and name not in only:
            continue
        random.seed(name)
        m = fn()
        tris = m.write(out / f"{name}.glb", name)
        place = world_place(origin, axis)
        place.update({"id": name, "glb": f"res://assets/models/landmarks/{name}.glb", "tris": tris,
                      "boxes": [list(c) + list(s) + [y] for c, s, y in m.boxes],
                      "clear": [[round(x, 2), round(z, 2)] for x, z in clear()]})
        if name in CLEAR_FILL:
            place["clear_fill"] = [[round(x, 2), round(z, 2)] for x, z in CLEAR_FILL[name]()]
        by_id[name] = place
        print(f"{name}: {tris} triangles, {len(m.boxes)} collider boxes")
    placements = {"_note": "Generated by tools/art/make_landmarks.py: one GLB per landmark; boxes = "
                           "[cx, cy, cz, sx, sy, sz, yaw] in model space.",
                  "models": [by_id[k] for k in sorted(by_id)]}
    PLACEMENTS.write_text(json.dumps(placements, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
