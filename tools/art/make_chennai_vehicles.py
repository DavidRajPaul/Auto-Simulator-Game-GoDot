#!/usr/bin/env python3
"""Builds the Chennai street vehicles that no free model pack offers, as tiny one-mesh GLBs.

Nov 13 2026: "all the two wheelers that are parked are the same ... add Chennai style cars".
The free packs that can be downloaded without an account are American or European streets
(muscle cars, limousines, superbikes). What fills a Chennai kerb is different: a step-through
moped, a 100 cc commuter bike with a saree guard, a classic cruiser, a roadster bicycle, a
small hatchback, a tall-boy hatchback, a micro van and a mini truck loaded with water cans.
None of them is a copy of a real product and none carries a badge.

Every vehicle is ONE primitive with ONE material and NO texture: colours are vertex colours.
The body panels are written with alpha 0 (everything else alpha 1); shaders/vehicle_paint.gdshader
repaints exactly those vertices from a per-instance colour, so one MultiMesh (= one draw call)
shows a kerb full of different colours. Unpainted, the body is the silver in BODY.

Axes: +Z is the nose, +Y up, wheels stand on y = 0. Sizes are real sizes in metres.
Output: assets/models/traffic/chennai/<name>.glb
Usage: python3 tools/art/make_chennai_vehicles.py
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

import mapbox_earcut as earcut
import numpy as np
from shapely.geometry import Polygon

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "traffic" / "chennai"

# sRGB colours. BODY is the paintable part (alpha 0 in the vertex colour).
BODY = (200, 203, 206)
BLACK = (26, 26, 28)
TYRE = (22, 22, 24)
PLASTIC = (48, 49, 52)
ENGINE = (92, 94, 98)
CHROME = (176, 180, 186)
GLASS = (38, 48, 58)
LAMP = (246, 240, 208)
TAIL = (176, 22, 24)
AMBER = (232, 140, 28)
PLATE = (238, 238, 232)
SEAT = (34, 30, 28)
SEAT_TAN = (112, 78, 52)
CAN_BLUE = (36, 96, 176)
CAN_CAP = (228, 232, 236)
BED = (72, 78, 84)
RUST = (104, 96, 90)


class Mesh:
    """Flat-shaded triangle soup with a colour per vertex; `hint` fixes the winding."""

    def __init__(self) -> None:
        self.p: list[tuple[float, float, float]] = []
        self.n: list[tuple[float, float, float]] = []
        self.c: list[tuple[int, int, int, int]] = []

    def tri(self, a, b, c, col, hint, normals=None) -> None:
        a, b, c = (np.asarray(v, dtype=float) for v in (a, b, c))
        n = np.cross(b - a, c - a)
        ln = float(np.linalg.norm(n))
        if ln < 1e-10:
            return
        n /= ln
        if float(np.dot(n, np.asarray(hint, dtype=float))) < 0.0:
            b, c = c, b
            n = -n
            if normals is not None:
                normals = (normals[0], normals[2], normals[1])
        rgba = (col[0], col[1], col[2], 0 if col is BODY else 255)
        for i, v in enumerate((a, b, c)):
            self.p.append(tuple(v))
            if normals is None:
                self.n.append(tuple(n))
            else:
                m = np.asarray(normals[i], dtype=float)
                self.n.append(tuple(m / max(float(np.linalg.norm(m)), 1e-9)))
            self.c.append(rgba)

    def quad(self, a, b, c, d, col, hint, normals=None) -> None:
        self.tri(a, b, c, col, hint, None if normals is None else (normals[0], normals[1], normals[2]))
        self.tri(a, c, d, col, hint, None if normals is None else (normals[0], normals[2], normals[3]))

    def box(self, lo, hi, col, skip: str = "") -> None:
        """Axis-aligned box; `skip` lists faces to leave out, e.g. "-y" for an open bottom."""
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        faces = {
            "-x": ((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (-1, 0, 0)),
            "+x": ((x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0), (1, 0, 0)),
            "-y": ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0)),
            "+y": ((x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1), (0, 1, 0)),
            "-z": ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (0, 0, -1)),
            "+z": ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1)),
        }
        for key, (a, b, c, d, h) in faces.items():
            if key not in skip:
                self.quad(a, b, c, d, col, h)

    def tube(self, p0, p1, r: float, col, seg: int = 5, caps: bool = False) -> None:
        """Round bar from p0 to p1 (smooth-shaded sides)."""
        p0 = np.asarray(p0, dtype=float)
        p1 = np.asarray(p1, dtype=float)
        axis = p1 - p0
        ln = float(np.linalg.norm(axis))
        if ln < 1e-6:
            return
        axis /= ln
        ref = np.array([1.0, 0.0, 0.0]) if abs(axis[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
        u = np.cross(axis, ref)
        u /= np.linalg.norm(u)
        v = np.cross(axis, u)
        ring = [u * math.cos(2 * math.pi * i / seg) + v * math.sin(2 * math.pi * i / seg) for i in range(seg)]
        for i in range(seg):
            a, b = ring[i], ring[(i + 1) % seg]
            self.quad(p0 + a * r, p0 + b * r, p1 + b * r, p1 + a * r, col, a + b, (a, b, b, a))
        if caps:
            for i in range(1, seg - 1):
                self.tri(p0 + ring[0] * r, p0 + ring[i] * r, p0 + ring[i + 1] * r, col, -axis)
                self.tri(p1 + ring[0] * r, p1 + ring[i] * r, p1 + ring[i + 1] * r, col, axis)

    def disc_x(self, x0: float, x1: float, y: float, z: float, r: float, col, seg: int = 12, face=None) -> None:
        """Solid cylinder with its axis along X (car wheels, hubs, lamps)."""
        pts = [(y + r * math.sin(2 * math.pi * i / seg), z + r * math.cos(2 * math.pi * i / seg)) for i in range(seg)]
        for i in range(seg):
            (ya, za), (yb, zb) = pts[i], pts[(i + 1) % seg]
            na, nb = (0, ya - y, za - z), (0, yb - y, zb - z)
            self.quad((x0, ya, za), (x0, yb, zb), (x1, yb, zb), (x1, ya, za), col, (0, ya + yb - 2 * y, za + zb - 2 * z), (na, nb, nb, na))
            cap = col if face is None else face
            self.tri((x0, y, z), (x0, ya, za), (x0, yb, zb), cap, (-1, 0, 0))
            self.tri((x1, y, z), (x1, ya, za), (x1, yb, zb), cap, (1, 0, 0))

    def disc_z(self, z0: float, z1: float, x: float, y: float, r: float, col, seg: int = 10, face=None) -> None:
        """Solid cylinder with its axis along Z (round headlamps)."""
        pts = [(x + r * math.cos(2 * math.pi * i / seg), y + r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        for i in range(seg):
            (xa, ya), (xb, yb) = pts[i], pts[(i + 1) % seg]
            na, nb = (xa - x, ya - y, 0), (xb - x, yb - y, 0)
            self.quad((xa, ya, z0), (xb, yb, z0), (xb, yb, z1), (xa, ya, z1), col, (xa + xb - 2 * x, ya + yb - 2 * y, 0), (na, nb, nb, na))
            self.tri((x, y, z0), (xa, ya, z0), (xb, yb, z0), col, (0, 0, -1))
            self.tri((x, y, z1), (xa, ya, z1), (xb, yb, z1), col if face is None else face, (0, 0, 1))

    def ring_x(self, x0: float, x1: float, y: float, z: float, r_out: float, r_in: float, col, inner, seg: int = 14) -> None:
        """Tyre: an annulus around the X axis; the inside band shows the rim colour."""
        for i in range(seg):
            a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
            s0, c0, s1, c1 = math.sin(a0), math.cos(a0), math.sin(a1), math.cos(a1)
            o0, o1 = (y + r_out * s0, z + r_out * c0), (y + r_out * s1, z + r_out * c1)
            i0, i1 = (y + r_in * s0, z + r_in * c0), (y + r_in * s1, z + r_in * c1)
            n0, n1 = (0, s0, c0), (0, s1, c1)
            self.quad((x0, *o0), (x0, *o1), (x1, *o1), (x1, *o0), col, (0, s0 + s1, c0 + c1), (n0, n1, n1, n0))
            self.quad((x0, *i0), (x0, *i1), (x1, *i1), (x1, *i0), inner, (0, -s0 - s1, -c0 - c1))
            self.quad((x0, *o0), (x0, *o1), (x0, *i1), (x0, *i0), col, (-1, 0, 0))
            self.quad((x1, *o0), (x1, *o1), (x1, *i1), (x1, *i0), col, (1, 0, 0))

    def loft(self, profile, col, cols=None, caps: bool = True) -> None:
        """Body shell: a closed side profile [(z, y, half_width)] swept across X.
        `cols` optionally gives the colour of the band that starts at each profile point."""
        n = len(profile)
        cz = sum(p[0] for p in profile) / n
        cy = sum(p[1] for p in profile) / n
        for i in range(n):
            z0, y0, w0 = profile[i]
            z1, y1, w1 = profile[(i + 1) % n]
            band = col if cols is None or cols[i] is None else cols[i]
            mid = np.array([0.0, (y0 + y1) * 0.5 - cy, (z0 + z1) * 0.5 - cz])
            edge = np.array([0.0, y1 - y0, z1 - z0])
            out = np.array([0.0, edge[2], -edge[1]])
            if float(np.dot(out, mid)) < 0.0:
                out = -out
            self.quad((-w0, y0, z0), (w0, y0, z0), (w1, y1, z1), (-w1, y1, z1), band, out)
        if caps:
            flat = np.array([[p[0], p[1]] for p in profile], dtype=np.float64)
            idx = earcut.triangulate_float64(flat, np.array([n], dtype=np.uint32))
            for t in range(0, len(idx), 3):
                a, b, c = (profile[int(idx[t + k])] for k in range(3))
                for side in (-1.0, 1.0):
                    self.tri((side * a[2], a[1], a[0]), (side * b[2], b[1], b[0]), (side * c[2], c[1], c[0]), col, (side, 0, 0))

    def side_panel(self, poly_zy, width_at, col, inset: float = 0.0, lift: float = 0.006, sides=(-1.0, 1.0)) -> None:
        """A flat panel (glass, arch, decal) laid on both flanks: polygon in (z, y), shrunk by
        `inset`, placed at the body half-width `width_at(y)` plus `lift`."""
        shape = Polygon(poly_zy)
        if inset > 0.0:
            shape = shape.buffer(-inset, join_style=2)
        if shape.is_empty:
            return
        parts = list(shape.geoms) if hasattr(shape, "geoms") else [shape]
        for part in parts:
            pts = list(part.exterior.coords)[:-1]
            flat = np.array(pts, dtype=np.float64)
            idx = earcut.triangulate_float64(flat, np.array([len(pts)], dtype=np.uint32))
            for t in range(0, len(idx), 3):
                tri = [pts[int(idx[t + k])] for k in range(3)]
                for side in sides:
                    self.tri(*[(side * (width_at(y) + lift), y, z) for (z, y) in tri], col, (side, 0, 0))

    def arc_x(self, y: float, z: float, r: float, a0: float, a1: float, half_w: float, thick: float, col, seg: int = 5) -> None:
        """Mudguard: a strip of an arc around the X axis from angle a0 to a1 (0 = forward, 90 = up)."""
        for i in range(seg):
            t0 = math.radians(a0 + (a1 - a0) * i / seg)
            t1 = math.radians(a0 + (a1 - a0) * (i + 1) / seg)
            for rr, sign in ((r + thick, 1.0), (r, -1.0)):
                p0 = (y + rr * math.sin(t0), z + rr * math.cos(t0))
                p1 = (y + rr * math.sin(t1), z + rr * math.cos(t1))
                self.quad((-half_w, *p0), (half_w, *p0), (half_w, *p1), (-half_w, *p1), col,
                    (0, sign * (math.sin(t0) + math.sin(t1)), sign * (math.cos(t0) + math.cos(t1))))
            for side in (-half_w, half_w):
                self.quad((side, y + r * math.sin(t0), z + r * math.cos(t0)), (side, y + (r + thick) * math.sin(t0), z + (r + thick) * math.cos(t0)),
                    (side, y + (r + thick) * math.sin(t1), z + (r + thick) * math.cos(t1)), (side, y + r * math.sin(t1), z + r * math.cos(t1)), col, (side, 0, 0))

    def write(self, path: Path, name: str) -> int:
        pos = np.array(self.p, dtype=np.float32)
        nor = np.array(self.n, dtype=np.float32)
        srgb = np.array(self.c, dtype=np.float64) / 255.0
        lin = np.where(srgb[:, :3] <= 0.04045, srgb[:, :3] / 12.92, ((srgb[:, :3] + 0.055) / 1.055) ** 2.4)
        col = np.concatenate([np.round(lin * 255.0), np.round(srgb[:, 3:] * 255.0)], axis=1).astype(np.uint8)
        key = np.concatenate([np.round(pos * 2000.0), np.round(nor * 100.0), col.astype(np.float32)], axis=1)
        _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
        pos, nor, col = pos[first], nor[first], col[first]
        idx = inverse.reshape(-1).astype(np.uint16 if len(first) < 65535 else np.uint32)
        blobs = [pos.tobytes(), nor.tobytes(), col.tobytes(), idx.tobytes()]
        views, offset, body = [], 0, b""
        for i, blob in enumerate(blobs):
            pad = (-len(blob)) % 4
            views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob), "target": 34963 if i == 3 else 34962})
            body += blob + b"\0" * pad
            offset += len(blob) + pad
        doc = {
            "asset": {"version": "2.0", "generator": "namma-auto make_chennai_vehicles.py"},
            "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
            "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0}]}],
            "materials": [{"name": "VehiclePaint", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.55}}],
            "buffers": [{"byteLength": len(body)}], "bufferViews": views,
            "accessors": [
                {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()},
                {"bufferView": 1, "componentType": 5126, "count": len(nor), "type": "VEC3"},
                {"bufferView": 2, "componentType": 5121, "normalized": True, "count": len(col), "type": "VEC4"},
                {"bufferView": 3, "componentType": 5123 if idx.dtype == np.uint16 else 5125, "count": len(idx), "type": "SCALAR"},
            ],
        }
        text = json.dumps(doc, separators=(",", ":")).encode()
        text += b" " * ((-len(text)) % 4)
        total = 12 + 8 + len(text) + 8 + len(body)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"glTF" + struct.pack("<II", 2, total) + struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(body), b"BIN\0") + body)
        return len(idx) // 3


# ---------------------------------------------------------------- two-wheelers

def _wheel(m: Mesh, z: float, r: float, tw: float, rim=CHROME, spokes: int = 3, hub: float = 0.05) -> None:
    m.ring_x(-tw, tw, r, z, r, r * 0.76, TYRE, rim)
    for i in range(spokes):
        a = math.pi * i / spokes
        dy, dz = math.sin(a) * r * 0.77, math.cos(a) * r * 0.77
        m.tube((0, r - dy, z - dz), (0, r + dy, z + dz), 0.011, rim, 4)
    m.disc_x(-tw - 0.012, tw + 0.012, r, z, hub, ENGINE, 8)


def _bars(m: Mesh, z: float, y: float, half: float, rise: float = 0.0, mirrors: bool = True) -> None:
    m.tube((-half, y + rise, z - 0.04), (0, y, z), 0.014, CHROME, 4)
    m.tube((half, y + rise, z - 0.04), (0, y, z), 0.014, CHROME, 4)
    for s in (-1.0, 1.0):
        m.tube((s * half, y + rise, z - 0.04), (s * (half - 0.11), y + rise * 0.6, z - 0.03), 0.02, BLACK, 5, True)
        if mirrors:
            m.tube((s * (half - 0.07), y + rise, z - 0.03), (s * (half - 0.04), y + rise + 0.16, z - 0.01), 0.007, BLACK, 3)
            m.box((s * (half - 0.04) - 0.05, y + rise + 0.14, z - 0.02), (s * (half - 0.04) + 0.05, y + rise + 0.21, z - 0.005), BLACK)


def _fork(m: Mesh, axle_z: float, r: float, head, col=CHROME, spread: float = 0.075) -> None:
    for s in (-spread, spread):
        m.tube((s, r, axle_z), (s, head[1], head[0]), 0.019, col, 5)


def _plate(m: Mesh, z: float, y: float, half: float = 0.09) -> None:
    m.box((-half, y, z - 0.008), (half, y + 0.11, z), PLATE)


def moped() -> Mesh:
    """Step-through moped: thin 16 inch spoked wheels, flat seat, load carrier (1.83 m)."""
    m = Mesh()
    r, rz, fz = 0.28, -0.60, 0.63
    _wheel(m, rz, r, 0.034, CHROME, 4)
    _wheel(m, fz, r, 0.034, CHROME, 4)
    m.arc_x(r, fz, r + 0.02, 40, 150, 0.05, 0.012, BODY)
    m.arc_x(r, rz, r + 0.02, 50, 175, 0.055, 0.012, BODY)
    head = (0.44, 0.88)
    _fork(m, fz, r, head)
    m.tube((0, 0.88, 0.44), (0, 1.00, 0.40), 0.022, BLACK, 5)
    _bars(m, 0.40, 1.00, 0.30, 0.03)
    m.box((-0.07, 0.80, 0.44), (0.07, 0.95, 0.54), BODY)                      # headlamp cowl
    m.disc_z(0.54, 0.56, 0.0, 0.875, 0.06, CHROME, 8, LAMP)
    m.tube((0, 0.86, 0.42), (0, 0.38, 0.14), 0.04, BODY, 6)                   # underbone spine
    m.box((-0.13, 0.30, -0.02), (0.13, 0.36, 0.24), PLASTIC)                  # footboard
    m.box((-0.09, 0.22, -0.34), (0.09, 0.44, -0.02), ENGINE)                  # engine
    m.loft([(-0.58, 0.50, 0.10), (-0.04, 0.46, 0.11), (0.02, 0.62, 0.10), (-0.10, 0.70, 0.10), (-0.56, 0.70, 0.09)], BODY)   # tank / side body
    m.loft([(-0.50, 0.70, 0.12), (-0.02, 0.70, 0.11), (0.0, 0.775, 0.10), (-0.48, 0.79, 0.12)], SEAT)
    m.box((-0.12, 0.705, -0.88), (0.12, 0.725, -0.52), CHROME)                # carrier
    for s in (-0.11, 0.11):
        m.tube((s, 0.71, -0.86), (s, 0.30, -0.62), 0.009, CHROME, 3)
    m.tube((0.12, 0.30, 0.0), (0.12, 0.33, -0.66), 0.03, CHROME, 6, True)     # silencer
    m.box((-0.045, 0.60, -0.90), (0.045, 0.67, -0.87), TAIL)
    _plate(m, -0.885, 0.47, 0.08)
    return m


def commuter() -> Mesh:
    """100 cc commuter motorcycle: tank, long seat, saree guard, upswept silencer (2.0 m)."""
    m = Mesh()
    r, rz, fz = 0.31, -0.62, 0.64
    _wheel(m, rz, r, 0.045, PLASTIC, 3, 0.06)
    _wheel(m, fz, r, 0.04, PLASTIC, 3, 0.05)
    m.arc_x(r, fz, r + 0.025, 35, 150, 0.055, 0.012, BODY)
    m.arc_x(r, rz, r + 0.03, 60, 185, 0.06, 0.012, BLACK)
    head = (0.44, 0.92)
    _fork(m, fz, r, head)
    m.tube((0, 0.90, 0.42), (0, 0.42, 0.26), 0.022, BLACK, 5)                 # down tube
    m.box((-0.10, 0.84, 0.44), (0.10, 1.02, 0.55), BODY)                      # headlamp cowl
    m.box((-0.075, 0.87, 0.55), (0.075, 0.98, 0.565), LAMP)
    m.box((-0.09, 1.02, 0.42), (0.09, 1.09, 0.50), GLASS)                     # visor
    _bars(m, 0.40, 1.02, 0.33, 0.03)
    for s in (-0.115, 0.115):
        m.box((s - 0.012, 0.90, 0.46), (s + 0.012, 0.93, 0.50), AMBER)
    m.loft([(0.02, 0.72, 0.12), (0.40, 0.72, 0.10), (0.44, 0.84, 0.10), (0.30, 0.93, 0.12), (0.04, 0.88, 0.13)], BODY)     # tank
    m.loft([(-0.62, 0.80, 0.11), (0.04, 0.78, 0.13), (0.05, 0.87, 0.12), (-0.24, 0.85, 0.13), (-0.62, 0.88, 0.11)], SEAT)
    m.loft([(-0.36, 0.54, 0.115), (0.02, 0.54, 0.115), (0.02, 0.76, 0.125), (-0.42, 0.79, 0.11)], BODY)                    # side panels
    m.loft([(-0.84, 0.76, 0.05), (-0.60, 0.68, 0.10), (-0.60, 0.80, 0.105), (-0.84, 0.84, 0.05)], BODY)                    # tail cowl
    m.box((-0.05, 0.76, -0.865), (0.05, 0.83, -0.84), TAIL)
    m.box((-0.13, 0.26, -0.12), (0.13, 0.56, 0.26), ENGINE)                   # engine
    m.box((-0.10, 0.50, 0.02), (0.10, 0.70, 0.22), PLASTIC)                   # cylinder head
    m.tube((0.15, 0.30, 0.16), (0.16, 0.34, -0.20), 0.022, CHROME, 5)         # exhaust pipe
    m.tube((0.16, 0.34, -0.20), (0.17, 0.44, -0.82), 0.048, CHROME, 6, True)  # silencer
    for s in (-0.12, 0.12):
        m.tube((s, 0.36, -0.56), (s, 0.72, -0.40), 0.018, CHROME, 4)          # shocks
    for y in (0.34, 0.46, 0.58):                                              # saree guard (left)
        m.tube((-0.13, y, -0.86), (-0.13, y, -0.40), 0.006, CHROME, 3)
    m.tube((-0.13, 0.30, -0.86), (-0.13, 0.62, -0.86), 0.006, CHROME, 3)
    m.tube((-0.11, 0.84, -0.86), (0.11, 0.84, -0.86), 0.011, CHROME, 4)       # grab rail
    for s in (-0.11, 0.11):
        m.tube((s, 0.84, -0.86), (s, 0.82, -0.56), 0.011, CHROME, 4)
    for s in (-0.16, 0.16):                                                   # leg guard
        m.tube((s, 0.34, 0.30), (s * 0.5, 0.62, 0.30), 0.011, CHROME, 4)
    _plate(m, -0.87, 0.60)
    return m


def cruiser() -> Mesh:
    """Classic 350 cc cruiser: teardrop tank, round lamp, deep mudguards, long silencer (2.14 m)."""
    m = Mesh()
    r, rz, fz = 0.33, -0.70, 0.70
    _wheel(m, rz, r, 0.055, CHROME, 4, 0.07)
    _wheel(m, fz, r, 0.045, CHROME, 4, 0.06)
    m.arc_x(r, fz, r + 0.02, 20, 160, 0.065, 0.014, BODY)
    m.arc_x(r, rz, r + 0.025, 40, 200, 0.075, 0.014, BODY)
    head = (0.48, 0.94)
    _fork(m, fz, r, head, CHROME, 0.085)
    for s in (-0.085, 0.085):
        m.tube((s, 0.62, 0.59), (s, 0.94, 0.48), 0.028, BODY, 6)              # fork shrouds
    m.disc_z(0.50, 0.62, 0.0, 0.90, 0.092, BODY, 10, LAMP)                    # headlamp nacelle
    m.disc_z(0.615, 0.63, 0.0, 0.90, 0.098, CHROME, 10, LAMP)
    _bars(m, 0.44, 1.04, 0.37, 0.02)
    m.loft([(0.00, 0.74, 0.11), (0.44, 0.76, 0.09), (0.46, 0.88, 0.11), (0.30, 0.97, 0.15), (0.04, 0.92, 0.14), (-0.04, 0.82, 0.11)], BODY)  # tank
    m.loft([(-0.36, 0.80, 0.14), (0.00, 0.80, 0.13), (0.00, 0.88, 0.12), (-0.34, 0.90, 0.15)], SEAT_TAN)                   # rider seat
    m.loft([(-0.72, 0.80, 0.11), (-0.40, 0.80, 0.12), (-0.40, 0.87, 0.12), (-0.70, 0.88, 0.10)], SEAT_TAN)                 # pillion
    m.loft([(-0.34, 0.50, 0.14), (-0.04, 0.50, 0.14), (-0.02, 0.76, 0.14), (-0.30, 0.76, 0.14)], BODY)                     # tool boxes
    m.box((-0.15, 0.24, -0.04), (0.15, 0.60, 0.30), ENGINE)                   # engine
    m.disc_x(-0.17, 0.17, 0.36, 0.04, 0.13, CHROME, 10)                       # crank case
    m.box((-0.10, 0.56, 0.06), (0.10, 0.76, 0.26), PLASTIC)                   # barrel
    m.tube((0, 0.92, 0.46), (0, 0.42, 0.34), 0.024, BLACK, 5)
    m.tube((0.17, 0.34, 0.24), (0.18, 0.30, -0.10), 0.026, CHROME, 5)
    m.tube((0.18, 0.30, -0.10), (0.19, 0.33, -0.96), 0.05, CHROME, 7, True)   # long silencer
    for s in (-0.14, 0.14):
        m.tube((s, 0.36, -0.62), (s, 0.78, -0.44), 0.02, CHROME, 4)
    m.box((-0.05, 0.62, -1.06), (0.05, 0.70, -1.02), TAIL)
    _plate(m, -1.04, 0.46, 0.10)
    for s in (-0.19, 0.19):                                                   # crash bar
        m.tube((s, 0.30, 0.36), (s * 0.4, 0.66, 0.36), 0.013, CHROME, 4)
    return m


def bicycle() -> Mesh:
    """Roadster bicycle with a carrier, a stand and a chain guard (1.82 m)."""
    m = Mesh()
    r, rz, fz = 0.34, -0.54, 0.56
    for z in (rz, fz):
        m.ring_x(-0.016, 0.016, r, z, r, r * 0.9, TYRE, CHROME, 14)
        for i in range(4):
            a = math.pi * i / 4
            m.tube((0, r - math.sin(a) * r * 0.9, z - math.cos(a) * r * 0.9), (0, r + math.sin(a) * r * 0.9, z + math.cos(a) * r * 0.9), 0.004, CHROME, 3)
    m.arc_x(r, fz, r + 0.015, 30, 150, 0.022, 0.006, BODY, 4)
    m.arc_x(r, rz, r + 0.015, 30, 190, 0.022, 0.006, BODY, 5)
    seat, bb, head_t, head_b = (-0.20, 0.92), (-0.06, 0.30), (0.34, 0.90), (0.37, 0.72)
    m.tube((0, seat[1], seat[0]), (0, bb[1], bb[0]), 0.016, BODY, 5)          # seat tube
    m.tube((0, seat[1] - 0.10, seat[0] + 0.02), (0, head_t[1], head_t[0]), 0.015, BODY, 5)   # top tube
    m.tube((0, bb[1], bb[0]), (0, head_b[1], head_b[0]), 0.017, BODY, 5)      # down tube
    m.tube((0, head_b[1], head_b[0]), (0, 1.02, 0.31), 0.017, BODY, 5)        # head tube
    for s in (-0.035, 0.035):
        m.tube((s, r, fz), (s, head_b[1], head_b[0]), 0.011, BODY, 4)         # fork
        m.tube((s, r, rz), (0, bb[1], bb[0]), 0.010, BODY, 4)                 # chain stays
        m.tube((s, r, rz), (0, seat[1] - 0.12, seat[0] + 0.02), 0.009, BODY, 4)   # seat stays
        m.tube((s * 2.4, 0.70, rz - 0.30), (s, r, rz), 0.006, CHROME, 3)      # carrier stays
    m.box((-0.07, 0.69, rz - 0.32), (0.07, 0.705, rz + 0.20), CHROME)         # carrier
    m.loft([(-0.34, 0.93, 0.07), (-0.08, 0.92, 0.035), (-0.08, 0.97, 0.03), (-0.33, 0.99, 0.075)], SEAT_TAN)   # saddle
    m.tube((-0.26, 1.03, 0.24), (0.26, 1.03, 0.24), 0.011, CHROME, 4)         # handlebar
    for s in (-1.0, 1.0):
        m.tube((s * 0.26, 1.03, 0.24), (s * 0.26, 1.03, 0.10), 0.014, BLACK, 4, True)
    m.box((0.035, 0.26, -0.50), (0.045, 0.40, 0.02), BLACK)                   # chain guard
    m.disc_x(0.03, 0.05, 0.30, -0.06, 0.09, CHROME, 8)                        # chain wheel
    m.tube((-0.10, 0.30, -0.06), (0.10, 0.30, -0.06), 0.008, BLACK, 3)        # pedals
    m.box((-0.15, 0.37, -0.10), (-0.09, 0.39, -0.02), BLACK)
    m.box((0.09, 0.21, -0.10), (0.15, 0.23, -0.02), BLACK)
    m.tube((-0.04, r, rz), (-0.13, 0.01, rz + 0.06), 0.007, BLACK, 3)         # stand
    m.box((-0.03, 0.98, 0.34), (0.03, 1.04, 0.40), CHROME)                    # dynamo lamp
    return m


# ---------------------------------------------------------------- cars

def _car_wheels(m: Mesh, half_w: float, r: float, front_z: float, rear_z: float, tw: float = 0.17) -> None:
    for z in (front_z, rear_z):
        for s in (-1.0, 1.0):
            x_out = s * (half_w + 0.004)
            x_in = s * (half_w - tw)
            m.disc_x(min(x_in, x_out), max(x_in, x_out), r, z, r, TYRE, 12)
            m.disc_x(min(x_out, x_out + s * 0.008), max(x_out, x_out + s * 0.008), r, z, r * 0.62, CHROME, 10)
            m.disc_x(min(x_out, x_out + s * 0.014), max(x_out, x_out + s * 0.014), r, z, r * 0.2, PLASTIC, 6)


def _arch(m: Mesh, half_w: float, r: float, z: float, floor: float) -> None:
    pts = [(z + (r + 0.06) * math.cos(math.radians(a)), max(floor, r + (r + 0.06) * math.sin(math.radians(a)))) for a in range(0, 181, 20)]
    m.side_panel(pts, lambda _y: half_w, BLACK, 0.0, 0.002)


def _car(length: float, width: float, height: float, wheel_r: float, front_z: float, rear_z: float,
        hood_y: float, belt_y: float, cowl_z: float, a_top_z: float, roof_end_z: float, tail_belt_z: float,
        boxy: float = 0.0) -> tuple[Mesh, callable]:
    """Shared two-box car: lower body shell + greenhouse with glass, lamps, bumpers, mirrors."""
    m = Mesh()
    hl, hw, floor = length * 0.5, width * 0.5, 0.20
    nose_w, tail_w = hw - 0.07 + boxy * 0.05, hw - 0.06 + boxy * 0.05
    lower = [
        (-hl + 0.05, floor, tail_w), (-hl, 0.36, tail_w), (-hl + 0.01, belt_y - 0.10, tail_w), (tail_belt_z, belt_y, hw - 0.02),
        (cowl_z, belt_y, hw - 0.02), (hl - 0.20, hood_y, hw - 0.03), (hl - 0.03, hood_y - 0.10, nose_w), (hl, 0.40, nose_w), (hl - 0.05, floor, nose_w),
        (front_z + wheel_r + 0.10, floor, hw), (rear_z - wheel_r - 0.10, floor, hw),
    ]
    m.loft(lower, BODY)
    roof_w, belt_w = hw - 0.15 + boxy * 0.07, hw - 0.035
    green = [(tail_belt_z + 0.01, belt_y, belt_w), (roof_end_z, height, roof_w), (a_top_z, height, roof_w), (cowl_z - 0.02, belt_y, belt_w)]
    m.loft(green, BODY)

    def w_at(y: float) -> float:
        return belt_w + (roof_w - belt_w) * (y - belt_y) / (height - belt_y)

    side = [(p[0], p[1]) for p in green]
    m.side_panel(side, w_at, GLASS, 0.055, 0.004)
    mid = (a_top_z + roof_end_z) * 0.5 - 0.05                                  # B pillar
    m.side_panel([(mid - 0.035, belt_y + 0.02), (mid + 0.035, belt_y + 0.02), (mid + 0.035, height - 0.03), (mid - 0.035, height - 0.03)], w_at, BODY, 0.0, 0.008)
    # Windscreen and rear glass: quads laid on the sloped faces.
    for (z0, z1) in ((cowl_z - 0.02, a_top_z), (tail_belt_z + 0.01, roof_end_z)):
        t0, t1 = 0.12, 0.90
        za, ya = z0 + (z1 - z0) * t0, belt_y + (height - belt_y) * t0
        zb, yb = z0 + (z1 - z0) * t1, belt_y + (height - belt_y) * t1
        slope = np.array([0.0, z1 - z0, -(height - belt_y)]) * (1.0 if z0 > 0 else -1.0)
        slope = slope / np.linalg.norm(slope) * 0.006
        wa, wb = w_at(ya) - 0.07, w_at(yb) - 0.07
        m.quad((-wa, ya + slope[1], za + slope[2]), (wa, ya + slope[1], za + slope[2]), (wb, yb + slope[1], zb + slope[2]), (-wb, yb + slope[1], zb + slope[2]), GLASS, slope)
    _car_wheels(m, hw, wheel_r, front_z, rear_z)
    for z in (front_z, rear_z):
        _arch(m, hw, wheel_r, z, floor)
    # Nose: lamps, grille, bumper, plate. Tail: lamps, bumper, plate.
    zf, zr = hl + 0.004, -hl - 0.004
    lamp_y = hood_y - 0.20
    for s in (-1.0, 1.0):
        m.quad((s * (nose_w - 0.30), lamp_y, zf - 0.02), (s * (nose_w - 0.04), lamp_y, zf - 0.03), (s * (nose_w - 0.04), lamp_y + 0.11, zf - 0.035), (s * (nose_w - 0.30), lamp_y + 0.11, zf - 0.025), LAMP, (0, 0, 1))
        m.quad((s * (tail_w - 0.22), belt_y - 0.26, zr + 0.012), (s * (tail_w - 0.03), belt_y - 0.26, zr + 0.012), (s * (tail_w - 0.03), belt_y - 0.10, zr + 0.016), (s * (tail_w - 0.22), belt_y - 0.10, zr + 0.016), TAIL, (0, 0, -1))
        m.box((s * (hw + 0.01) - 0.05, belt_y + 0.01, cowl_z - 0.20), (s * (hw + 0.01) + 0.05, belt_y + 0.10, cowl_z - 0.12), PLASTIC)   # mirrors
        m.box((s * (hw - 0.015) - 0.012, belt_y - 0.12, mid + 0.10), (s * (hw - 0.015) + 0.012, belt_y - 0.09, mid + 0.24), PLASTIC)     # door handles
        m.box((s * (hw - 0.015) - 0.012, belt_y - 0.12, mid - 0.62), (s * (hw - 0.015) + 0.012, belt_y - 0.09, mid - 0.48), PLASTIC)
    m.quad((-nose_w + 0.34, lamp_y + 0.01, zf - 0.02), (nose_w - 0.34, lamp_y + 0.01, zf - 0.02), (nose_w - 0.34, lamp_y + 0.09, zf - 0.025), (-nose_w + 0.34, lamp_y + 0.09, zf - 0.025), BLACK, (0, 0, 1))
    m.box((-nose_w - 0.005, floor + 0.02, hl - 0.06), (nose_w + 0.005, 0.40, hl + 0.012), PLASTIC, "-z")       # bumpers
    m.box((-tail_w - 0.005, floor + 0.02, -hl - 0.012), (tail_w + 0.005, 0.38, -hl + 0.06), PLASTIC, "+z")
    m.box((-0.24, 0.43, zf - 0.004), (0.24, 0.53, zf + 0.004), PLATE)
    m.box((-0.24, 0.44, zr - 0.004), (0.24, 0.54, zr + 0.012), PLATE)
    return m, w_at


def hatchback() -> Mesh:
    """Small hatchback, the commonest car on a Chennai street (3.85 x 1.70 x 1.52 m)."""
    m, _ = _car(3.85, 1.70, 1.52, 0.30, 1.22, -1.23, 0.98, 0.93, 0.78, 0.22, -1.30, -1.80)
    return m


def tallboy() -> Mesh:
    """Tall-boy city hatchback: short bonnet, upright sides, high roof (3.60 x 1.52 x 1.68 m)."""
    m, _ = _car(3.60, 1.52, 1.68, 0.28, 1.16, -1.22, 0.98, 0.96, 0.92, 0.50, -1.50, -1.74, 1.0)
    m.box((-0.50, 1.68, -1.20), (-0.44, 1.71, 0.30), PLASTIC)                # roof rails
    m.box((0.44, 1.68, -1.20), (0.50, 1.71, 0.30), PLASTIC)
    return m


def van() -> Mesh:
    """One-box micro van: flat nose, sliding-door sides (3.37 x 1.41 x 1.64 m)."""
    m, _ = _car(3.37, 1.41, 1.64, 0.26, 1.02, -0.86, 1.00, 0.98, 1.50, 1.26, -1.56, -1.66, 1.0)
    return m


def mini_truck() -> Mesh:
    """Mini truck with a load of 20 litre water cans (3.80 x 1.50 x 1.85 m)."""
    m = Mesh()
    hl, hw, floor, r = 1.90, 0.75, 0.30, 0.27
    front_z, rear_z = 1.22, -0.92
    # Cab: lower shell + upright greenhouse.
    cab_back, belt_y, roof = 0.62, 1.06, 1.85
    lower = [(cab_back, floor, hw), (cab_back, belt_y, hw - 0.01), (hl - 0.10, belt_y, hw - 0.02), (hl, belt_y - 0.14, hw - 0.06), (hl, 0.46, hw - 0.06), (hl - 0.05, floor, hw - 0.06)]
    m.loft(lower, BODY)
    belt_w, roof_w = hw - 0.03, hw - 0.10
    green = [(cab_back + 0.01, belt_y, belt_w), (cab_back + 0.03, roof, roof_w), (hl - 0.42, roof, roof_w), (hl - 0.12, belt_y, belt_w)]
    m.loft(green, BODY)

    def w_at(y: float) -> float:
        return belt_w + (roof_w - belt_w) * (y - belt_y) / (roof - belt_y)

    door = [(cab_back + 0.14, belt_y + 0.03), (cab_back + 0.14, roof - 0.07), (hl - 0.46, roof - 0.07), (hl - 0.22, belt_y + 0.03)]
    m.side_panel(door, w_at, GLASS, 0.0, 0.004)
    t0, t1 = 0.12, 0.90
    z0, z1 = hl - 0.12, hl - 0.42
    za, ya, zb, yb = z0 + (z1 - z0) * t0, belt_y + (roof - belt_y) * t0, z0 + (z1 - z0) * t1, belt_y + (roof - belt_y) * t1
    m.quad((-w_at(ya) + 0.07, ya, za + 0.008), (w_at(ya) - 0.07, ya, za + 0.008), (w_at(yb) - 0.07, yb, zb + 0.008), (-w_at(yb) + 0.07, yb, zb + 0.008), GLASS, (0, 0.4, 1))
    zf = hl + 0.004
    for s in (-1.0, 1.0):
        m.quad((s * 0.36, 0.72, zf), (s * 0.64, 0.72, zf), (s * 0.64, 0.86, zf), (s * 0.36, 0.86, zf), LAMP, (0, 0, 1))
        m.box((s * (hw + 0.02) - 0.05, belt_y + 0.10, hl - 0.34), (s * (hw + 0.02) + 0.05, belt_y + 0.30, hl - 0.28), PLASTIC)
    m.quad((-0.30, 0.74, zf), (0.30, 0.74, zf), (0.30, 0.84, zf), (-0.30, 0.84, zf), BLACK, (0, 0, 1))
    m.box((-hw + 0.04, floor, hl - 0.05), (hw - 0.04, 0.50, hl + 0.014), PLASTIC, "-z")
    m.box((-0.24, 0.54, zf - 0.004), (0.24, 0.64, zf + 0.004), PLATE)
    # Load bed: chassis, deck, drop sides (open top) and the cans.
    deck = 0.74
    m.box((-0.30, 0.34, -hl + 0.10), (0.30, deck - 0.06, cab_back), BLACK)
    m.box((-hw, deck - 0.06, -hl), (hw, deck, cab_back - 0.03), BED)
    for (lo, hi) in (((-hw, deck, -hl), (-hw + 0.03, deck + 0.34, cab_back - 0.03)), ((hw - 0.03, deck, -hl), (hw, deck + 0.34, cab_back - 0.03)),
            ((-hw, deck, -hl), (hw, deck + 0.34, -hl + 0.03)), ((-hw, deck, cab_back - 0.06), (hw, deck + 0.50, cab_back - 0.03))):
        m.box(lo, hi, BODY, "-y")
    for s in (-1.0, 1.0):
        m.box((s * 0.52 - 0.11, deck - 0.26, -hl - 0.006), (s * 0.52 + 0.11, deck - 0.12, -hl + 0.02), TAIL)
    m.box((-0.24, deck - 0.28, -hl - 0.008), (0.24, deck - 0.18, -hl + 0.01), PLATE)
    can, gap = 0.27, 0.035
    nx, nz = 4, 7
    x_start = -((nx * can + (nx - 1) * gap) * 0.5)
    for layer in range(2):
        for ix in range(nx):
            for iz in range(nz):
                if layer == 1 and (iz == 0 or (ix + iz) % 5 == 0):
                    continue
                x = x_start + ix * (can + gap)
                z = -hl + 0.08 + iz * (can + gap)
                y = deck + layer * 0.40
                m.box((x, y, z), (x + can, y + 0.36, z + can), CAN_BLUE, "-y")
                if layer == 1 or iz == 0 or (ix + iz) % 5 == 0:
                    m.box((x + 0.09, y + 0.36, z + 0.09), (x + can - 0.09, y + 0.40, z + can - 0.09), CAN_CAP, "-y")
    _car_wheels(m, hw, r, front_z, rear_z, 0.15)
    return m


VEHICLES = {
    "moped": moped, "commuter_bike": commuter, "cruiser_bike": cruiser, "bicycle": bicycle,
    "hatchback": hatchback, "tallboy": tallboy, "micro_van": van, "mini_truck": mini_truck,
}


def main() -> None:
    for name, build in VEHICLES.items():
        mesh = build()
        tris = mesh.write(OUT / f"{name}.glb", name)
        pos = np.array(mesh.p)
        size = pos.max(axis=0) - pos.min(axis=0)
        print(f"{name:14s} {tris:5d} tris  {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} m  min y {pos[:, 1].min():.3f}")


if __name__ == "__main__":
    main()
