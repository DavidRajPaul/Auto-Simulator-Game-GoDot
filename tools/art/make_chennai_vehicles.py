#!/usr/bin/env python3
"""Builds the Chennai street vehicles that no free model pack offers, as small one-mesh GLBs.

Nov 13 2026: "all the two wheelers that are parked are the same ... add Chennai style cars".
The free packs that can be downloaded without an account are American or European streets
(muscle cars, limousines, superbikes). What fills a Chennai kerb is different: a step-through
moped, a 100 cc commuter bike with a saree guard, a classic cruiser, a roadster bicycle, a
small hatchback, a tall-boy hatchback, a micro van and a mini truck loaded with water cans.
None of them is a copy of a real product and none carries a badge.

Every vehicle is ONE primitive with ONE material and NO texture: colours are vertex colours.
Nov 14 device feedback: the first set was boxes ("looking very low poly"). Bodies are now
smooth-shaded lofts: a car is ~30 cross-sections swept nose to tail with a curved roof, raked
glass, tumblehome and rounded corners; two-wheelers have turned tyres, rounded tanks, seats and
cowls. Still one mesh and no texture, 2-4k triangles (the downloaded scooter is 1.8k, the sedan
3.1k), and Godot builds LODs for them on import.
The body panels are written with alpha 0, glass 0.5, everything else 1; shaders/vehicle_paint.gdshader
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
# Second paint (Nov 27: "sports bike with multiple colours"): vertex alpha 200, repainted by
# shaders/vehicle_paint.gdshader in a contrast colour picked from the instance paint (graphics,
# stripes, tank decals). Unpainted it shows this off-white.
ACCENT = (232, 232, 228)
GOLD = (196, 150, 46)
SPRING = (196, 36, 30)
FRAME_SILVER = (150, 154, 160)


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
        rgba = (col[0], col[1], col[2], 0 if col is BODY else (128 if col is GLASS else (200 if col is ACCENT else 255)))
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

    def grid(self, pts, colour, ref, closed_j: bool = False, inward: bool = False, ref_ij=None) -> None:
        """Smooth-shaded surface through pts[i][j]. `colour(i, j)` paints the quad that starts at
        (i, j); `ref(i)` is a point inside the shape at row i (normals point away from it)."""
        ni, nj = len(pts), len(pts[0])
        P = np.array(pts, dtype=float)
        N = np.zeros_like(P)
        quads = []
        for i in range(ni - 1):
            for j in range(nj if closed_j else nj - 1):
                j1 = (j + 1) % nj
                a, b, c, d = P[i, j], P[i + 1, j], P[i + 1, j1], P[i, j1]
                n = np.cross(c - a, d - b)
                ln = np.linalg.norm(n)
                if ln < 1e-12:
                    continue
                if ref_ij is not None:
                    out = (a + b + c + d) * 0.25 - np.asarray(ref_ij(i, j), dtype=float)
                else:
                    out = (a + b + c + d) * 0.25 - (np.asarray(ref(i), dtype=float) + np.asarray(ref(i + 1), dtype=float)) * 0.5
                if (np.dot(n, out) < 0.0) != inward:
                    n = -n
                for (ii, jj) in ((i, j), (i + 1, j), (i + 1, j1), (i, j1)):
                    N[ii, jj] += n
                quads.append((i, j, j1, n / ln))
        for i in range(ni):
            for j in range(nj):
                ln = np.linalg.norm(N[i, j])
                N[i, j] = N[i, j] / ln if ln > 1e-12 else np.array([0.0, 1.0, 0.0])
        for (i, j, j1, n) in quads:
            col = colour(i, j)
            self.quad(P[i, j], P[i + 1, j], P[i + 1, j1], P[i, j1], col, n, (N[i, j], N[i + 1, j], N[i + 1, j1], N[i, j1]))

    def blob(self, rings, col, seg: int = 10, caps: bool = True, cols=None, square: float = 2.0) -> None:
        """Rounded part: ellipse rings [(x, y, z, rx, ry)] along a path that runs in a Y-Z plane
        (tanks, seats, cowls, silencers). rx is the half-width across the bike. `square` > 2
        makes the section a superellipse (fairings, sculpted tanks)."""
        cs = [np.array(r[:3], dtype=float) for r in rings]
        pts = []
        for i, r in enumerate(rings):
            t = cs[min(i + 1, len(cs) - 1)] - cs[max(i - 1, 0)]
            t[0] = 0.0
            t /= max(np.linalg.norm(t), 1e-9)
            v = np.array([0.0, t[2], -t[1]])
            row = []
            for k in range(seg):
                a = 2 * math.pi * k / seg
                ca, sa = math.cos(a), math.sin(a)
                if square != 2.0:
                    ca = math.copysign(abs(ca) ** (2.0 / square), ca)
                    sa = math.copysign(abs(sa) ** (2.0 / square), sa)
                row.append(cs[i] + np.array([1.0, 0.0, 0.0]) * r[3] * ca + v * r[4] * sa)
            pts.append(row)
        self.grid(pts, (lambda i, j: col if cols is None else cols[i]), lambda i: cs[i], closed_j=True)
        if caps:
            for end, sign in ((0, -1.0), (len(rings) - 1, 1.0)):
                d = (cs[end] - cs[1 if end == 0 else end - 1])
                for k in range(seg):
                    self.tri(cs[end], pts[end][k], pts[end][(k + 1) % seg], col if cols is None else cols[min(end, len(cols) - 1)], d)

    def lathe_x(self, profile, y: float, z: float, col, seg: int = 16, cols=None) -> None:
        """Turned part around the X axis through (y, z): profile [(x, radius)], open or closed
        (tyres). Faces point away from the middle of the profile's own cross-section."""
        pts = []
        for (x, r) in profile:
            pts.append([(x, y + r * math.sin(2 * math.pi * k / seg), z + r * math.cos(2 * math.pi * k / seg)) for k in range(seg)])
        xc = sum(p[0] for p in profile) / len(profile)
        rc = sum(p[1] for p in profile) / len(profile)

        def centre(_i: int, j: int):
            a = 2 * math.pi * (j + 0.5) / seg
            return (xc, y + rc * math.sin(a), z + rc * math.cos(a))

        self.grid(pts, (lambda i, j: col if cols is None else cols[i]), None, closed_j=True, ref_ij=centre)

    def panel(self, poly_zy, x_at, col, lift: float = 0.004, sides=(-1.0, 1.0)) -> None:
        """Flat decal on the flanks: polygon in (z, y) laid at half-width x_at(z, y) + lift."""
        pts = list(poly_zy)
        flat = np.array(pts, dtype=np.float64)
        idx = earcut.triangulate_float64(flat, np.array([len(pts)], dtype=np.uint32))
        for t in range(0, len(idx), 3):
            tri = [pts[int(idx[t + k])] for k in range(3)]
            for side in sides:
                self.tri(*[(side * (x_at(z, y) + lift), y, z) for (z, y) in tri], col, (side, 0, 0))

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


# ---------------------------------------------------------------- shared parts

def _tyre(m: Mesh, z: float, r: float, t: float, rim=CHROME, x: float = 0.0, seg: int = 18) -> None:
    """Round-shouldered tyre (half-width t) centred at lateral x; the inside band is the rim."""
    prof = [(x - t, r * 0.74), (x - t, r * 0.9), (x - t * 0.55, r), (x + t * 0.55, r), (x + t, r * 0.9), (x + t, r * 0.74), (x - t, r * 0.74)]
    m.lathe_x(prof, r, z, TYRE, seg, cols=[TYRE, TYRE, TYRE, TYRE, TYRE, rim, rim])


def _bike_wheel(m: Mesh, z: float, r: float, t: float, rim=CHROME, spokes: int = 6, alloy: bool = False, hub: float = 0.05, disc: bool = False) -> None:
    _tyre(m, z, r, t, rim)
    n = 5 if alloy else spokes
    for i in range(n):
        a = 2 * math.pi * i / n + 0.3
        end = (0, r + math.sin(a) * r * 0.75, z + math.cos(a) * r * 0.75)
        if alloy:
            m.tube((0, r, z), end, 0.02, rim, 4)
        else:
            m.tube((0.03, r, z), end, 0.006, rim, 3)
            m.tube((-0.03, r, z), end, 0.006, rim, 3)
    m.disc_x(-t - 0.02, t + 0.02, r, z, hub, ENGINE, 10)
    if disc:
        m.disc_x(t + 0.012, t + 0.02, r, z, r * 0.46, CHROME, 14)


def _bars(m: Mesh, z: float, y: float, half: float, rise: float = 0.0, mirrors: bool = True) -> None:
    for s in (-1.0, 1.0):
        m.tube((s * half, y + rise, z - 0.04), (0, y, z), 0.014, CHROME, 6)
        m.tube((s * half, y + rise, z - 0.04), (s * (half - 0.12), y + rise * 0.6, z - 0.03), 0.021, BLACK, 7, True)
        m.tube((s * (half - 0.13), y + rise * 0.6, z + 0.0), (s * (half - 0.03), y + rise * 0.8, z + 0.035), 0.006, CHROME, 3)   # lever
        if mirrors:
            mx, my = s * (half - 0.05), y + rise + 0.19
            m.tube((s * (half - 0.09), y + rise, z - 0.03), (mx, my - 0.03, z - 0.01), 0.007, BLACK, 4)
            m.blob([(mx, my, z - 0.03, 0.03, 0.022), (mx, my, z - 0.012, 0.055, 0.038), (mx, my, z - 0.002, 0.05, 0.034)], BLACK, 8)


def _fork(m: Mesh, axle_z: float, r: float, head, col=CHROME, spread: float = 0.075, lower=PLASTIC) -> None:
    for s in (-spread, spread):
        mid = (s, r + (head[1] - r) * 0.45, axle_z + (head[0] - axle_z) * 0.45)
        m.tube((s, r, axle_z), mid, 0.026, lower, 7)
        m.tube(mid, (s, head[1], head[0]), 0.019, col, 7)


def _plate(m: Mesh, z: float, y: float, half: float = 0.09) -> None:
    m.box((-half, y, z - 0.008), (half, y + 0.11, z), PLATE)


def _blinker(m: Mesh, x: float, y: float, z: float) -> None:
    m.blob([(x, y, z - 0.022, 0.012, 0.012), (x, y, z, 0.024, 0.024), (x, y, z + 0.022, 0.012, 0.012)], AMBER, 6)


def _shocks(m: Mesh, lower, upper, spread: float) -> None:
    for s in (-spread, spread):
        mid = (s, (lower[1] + upper[1]) * 0.5, (lower[0] + upper[0]) * 0.5)
        m.tube((s, lower[1], lower[0]), mid, 0.028, PLASTIC, 6)
        m.tube(mid, (s, upper[1], upper[0]), 0.017, CHROME, 6)


# ---------------------------------------------------------------- two-wheelers

def _path(m: Mesh, pts, r: float, col, seg: int = 7) -> None:
    """A bent tube through `pts` (frames, exhausts, grab rails), with a ball at every bend."""
    for p0, p1 in zip(pts, pts[1:]):
        m.tube(p0, p1, r, col, seg)
    for p in pts[1:-1]:
        x, y, z = p
        m.blob([(x, y, z - r, r * 0.6, r * 0.6), (x, y, z, r, r), (x, y, z + r, r * 0.6, r * 0.6)], col, seg)


def _ring_at(rings, z: float):
    """Interpolated (y, rx, ry) of a blob's rings at length z (rings run in falling or rising z)."""
    rs = sorted(rings, key=lambda r: r[2])
    if z <= rs[0][2]:
        return rs[0][1], rs[0][3], rs[0][4]
    for r0, r1 in zip(rs, rs[1:]):
        if r0[2] <= z <= r1[2]:
            t = (z - r0[2]) / max(r1[2] - r0[2], 1e-9)
            return (r0[1] + (r1[1] - r0[1]) * t, r0[3] + (r1[3] - r0[3]) * t, r0[4] + (r1[4] - r0[4]) * t)
    return rs[-1][1], rs[-1][3], rs[-1][4]


def _decal(m: Mesh, rings, poly_zy, col, square: float = 2.0, cell: float = 0.02) -> None:
    """Paint a flat shape (z, y) onto both flanks of a blob (tank stripes, fairing graphics). The
    shape is cut into small cells first and every cell vertex sits on the blob's own surface at
    its (z, y), lifted a few millimetres, so the decal follows the curve instead of slicing
    through it (Nov 27: big flat triangles on the fairing showed as white shards)."""
    from shapely.geometry import box as sbox

    def x_at(z: float, y: float) -> float:
        yc, rx, ry = _ring_at(rings, z)
        t = min(abs(y - yc) / max(ry, 1e-6), 0.999)
        # Superellipse |x/rx|^p + |y/ry|^p = 1.
        return rx * (1.0 - t ** square) ** (1.0 / square)

    shape = Polygon(poly_zy)
    z0, y0, z1, y1 = shape.bounds
    z = z0
    while z < z1:
        y = y0
        while y < y1:
            piece = shape.intersection(sbox(z, y, z + cell, y + cell))
            parts = [] if piece.is_empty else (list(piece.geoms) if hasattr(piece, "geoms") else [piece])
            for part in parts:
                if part.geom_type == "Polygon" and part.area > 1e-7:
                    m.panel(list(part.exterior.coords)[:-1], x_at, col, 0.004)
            y += cell
        z += cell


def _sprocket_chain(m: Mesh, front, rear, r_rear: float, side: float, col=BLACK) -> None:
    """Chain run between the gearbox sprocket (z, y) and the rear sprocket, on one side."""
    fz, fy = front
    rz, ry = rear
    m.disc_x(side - 0.006, side + 0.006, ry, rz, r_rear, ENGINE, 14)
    for dy in (0.04, -0.04):
        m.tube((side, fy + dy, fz), (side, ry + dy * r_rear / 0.04, rz), 0.007, col, 4)


def sport_bike() -> Mesh:
    """Faired 150-250 cc sports bike: full fairing with twin lamps and a screen, sculpted tank,
    split seat on a high tail, USD fork, mono-shock, belly exhaust, 17 inch alloys (2.0 m).
    Body = main paint, ACCENT = contrast graphics (fairing flash, tank and tail stripes)."""
    m = Mesh()
    r, rz, fz = 0.30, -0.69, 0.68
    _bike_wheel(m, rz, r, 0.068, BLACK, alloy=True, hub=0.07)
    _bike_wheel(m, fz, r, 0.045, BLACK, alloy=True, hub=0.05, disc=True)
    m.disc_x(-0.078, -0.07, r, rz, 0.11, CHROME, 12)                            # rear disc
    m.arc_x(r, fz, r + 0.02, 40, 135, 0.05, 0.01, BODY, 8)                     # front hugger mudguard
    m.arc_x(r, rz, r + 0.03, 70, 150, 0.075, 0.01, BLACK, 6)                   # rear hugger
    head = (0.47, 0.90)
    for sx in (-0.07, 0.07):                                                    # upside-down fork
        mid = (sx, r + (head[1] - r) * 0.5, fz + (head[0] - fz) * 0.5)
        m.tube((sx, r, fz), mid, 0.022, BLACK, 7)
        m.tube(mid, (sx, head[1], head[0]), 0.03, GOLD, 8)
        m.blob([(sx * 1.1, r + 0.03, fz - 0.04, 0.012, 0.03), (sx * 1.1, r + 0.08, fz - 0.07, 0.016, 0.04)], GOLD, 6)   # caliper
    m.box((-0.09, 0.90, 0.43), (0.09, 0.93, 0.52), FRAME_SILVER)               # top yoke
    # Twin-spar frame from the head to the swing-arm pivot, seen behind the fairing.
    for sx in (-1.0, 1.0):
        _path(m, [(sx * 0.07, 0.88, 0.45), (sx * 0.135, 0.72, 0.22), (sx * 0.14, 0.58, -0.04), (sx * 0.12, 0.44, -0.13)], 0.024, FRAME_SILVER, 6)
        _path(m, [(sx * 0.12, 0.44, -0.13), (sx * 0.10, 0.38, -0.40), (sx * 0.09, r, rz)], 0.022, BLACK, 6)   # swing arm
        _path(m, [(sx * 0.12, 0.70, -0.10), (sx * 0.08, 0.84, -0.55)], 0.012, BLACK, 5)   # sub-frame
    m.tube((0, 0.44, -0.26), (0, 0.66, -0.14), 0.024, SPRING, 8)               # mono-shock, tucked in
    m.tube((0, 0.42, -0.28), (0, 0.7, -0.12), 0.012, CHROME, 6)
    _sprocket_chain(m, (0.04, 0.40), (rz, r), 0.085, -0.085)
    # Engine: crankcase and sump below the fairing.
    m.blob([(0, 0.34, -0.12, 0.1, 0.09), (0, 0.33, 0.02, 0.14, 0.12), (0, 0.35, 0.22, 0.13, 0.11), (0, 0.40, 0.32, 0.08, 0.07)], ENGINE, 10)
    m.disc_x(0.13, 0.155, 0.36, 0.06, 0.1, ENGINE, 14)
    # Sculpted tank, square-ish in section, with a stripe each side.
    tank = [(0, 0.86, -0.08, 0.1, 0.07), (0, 0.91, 0.04, 0.155, 0.1), (0, 0.95, 0.2, 0.165, 0.11), (0, 0.95, 0.34, 0.15, 0.1), (0, 0.92, 0.44, 0.1, 0.07)]
    m.blob(tank, BODY, 12, square=2.6)
    _decal(m, tank, [(0.34, 0.95), (0.06, 0.93), (0.06, 0.905), (0.32, 0.925)], ACCENT, 2.6)
    # Front fairing: sharp nose, wide flanks, a contrast flash along each side.
    nose = [(0, 0.76, 0.92, 0.03, 0.035), (0, 0.78, 0.86, 0.11, 0.085), (0, 0.8, 0.75, 0.17, 0.14), (0, 0.79, 0.62, 0.2, 0.18), (0, 0.76, 0.48, 0.2, 0.2), (0, 0.71, 0.38, 0.18, 0.19)]
    m.blob(nose, BODY, 14, square=2.4)
    _decal(m, nose, [(0.84, 0.77), (0.6, 0.83), (0.44, 0.8), (0.46, 0.75), (0.6, 0.77)], ACCENT, 2.4)
    for sx in (-1.0, 1.0):                                                      # twin headlamps
        m.blob([(sx * 0.065, 0.765, 0.88, 0.01, 0.01), (sx * 0.065, 0.77, 0.865, 0.045, 0.024), (sx * 0.07, 0.775, 0.83, 0.05, 0.026)], LAMP, 8)
        m.blob([(sx * 0.2, 0.86, 0.6, 0.012, 0.01), (sx * 0.23, 0.9, 0.58, 0.015, 0.01)], BLACK, 5)   # mirror stalk
        m.blob([(sx * 0.27, 0.93, 0.6, 0.02, 0.016), (sx * 0.27, 0.935, 0.57, 0.06, 0.035), (sx * 0.27, 0.93, 0.55, 0.05, 0.03)], BODY, 8)
        _blinker(m, sx * 0.2, 0.83, 0.66)
    # Smoked screen.
    m.blob([(0, 0.9, 0.76, 0.1, 0.01), (0, 0.95, 0.68, 0.13, 0.012), (0, 0.99, 0.59, 0.12, 0.012), (0, 1.0, 0.54, 0.09, 0.01)], GLASS, 10)
    # Side fairings over the engine and a black belly pan with the exhaust.
    side = [(0, 0.62, 0.46, 0.2, 0.17), (0, 0.6, 0.3, 0.21, 0.18), (0, 0.58, 0.12, 0.19, 0.17), (0, 0.6, -0.0, 0.14, 0.13)]
    m.blob(side, BODY, 12, cols=[BODY, BODY, BODY, BLACK], square=2.6)
    _decal(m, side, [(0.4, 0.62), (0.08, 0.66), (0.06, 0.63), (0.38, 0.58)], ACCENT, 2.6)
    # Body-colour covers under the seat, so the frame doesn't show between fairing and tail.
    under = [(0, 0.74, 0.02, 0.12, 0.09), (0, 0.76, -0.16, 0.13, 0.1), (0, 0.8, -0.34, 0.12, 0.08)]
    m.blob(under, BODY, 10, square=2.6)
    m.blob([(0, 0.27, 0.3, 0.06, 0.04), (0, 0.25, 0.14, 0.13, 0.06), (0, 0.27, -0.06, 0.12, 0.06), (0, 0.33, -0.2, 0.06, 0.05)], BLACK, 10)
    m.blob([(0.06, 0.3, -0.14, 0.05, 0.05), (0.07, 0.31, -0.28, 0.065, 0.06), (0.07, 0.33, -0.36, 0.05, 0.045)], ENGINE, 9)   # stubby muffler
    m.disc_z(-0.39, -0.36, 0.07, 0.33, 0.028, BLACK, 8)
    # Split seat: low rider seat, raised pillion on a high tail with a stripe and an LED lamp.
    m.blob([(0, 0.82, -0.36, 0.08, 0.025), (0, 0.84, -0.26, 0.13, 0.04), (0, 0.85, -0.12, 0.15, 0.045), (0, 0.85, -0.04, 0.13, 0.04), (0, 0.86, 0.02, 0.08, 0.03)], SEAT, 10)
    tail = [(0, 0.84, -0.3, 0.14, 0.08), (0, 0.88, -0.46, 0.12, 0.07), (0, 0.93, -0.66, 0.08, 0.05), (0, 0.96, -0.82, 0.04, 0.03)]
    m.blob(tail, BODY, 10, square=2.4)
    _decal(m, tail, [(-0.34, 0.83), (-0.8, 0.95), (-0.8, 0.935), (-0.4, 0.81)], ACCENT, 2.4)
    m.blob([(0, 0.94, -0.42, 0.06, 0.018), (0, 0.97, -0.52, 0.09, 0.03), (0, 0.99, -0.66, 0.06, 0.022)], SEAT, 8)   # pillion pad
    m.blob([(0, 0.95, -0.82, 0.05, 0.015), (0, 0.95, -0.845, 0.04, 0.012)], TAIL, 8)
    _path(m, [(0, 0.9, -0.8), (0, 0.72, -0.86), (0, 0.62, -0.84)], 0.012, BLACK, 5)   # plate hugger
    _plate(m, -0.85, 0.56, 0.085)
    for sx in (-1.0, 1.0):
        _blinker(m, sx * 0.09, 0.68, -0.84)
        m.tube((sx * 0.06, 0.93, 0.47), (sx * 0.27, 0.9, 0.4), 0.014, BLACK, 6)  # clip-on bars
        m.tube((sx * 0.21, 0.9, 0.41), (sx * 0.31, 0.9, 0.39), 0.02, BLACK, 7, True)
        m.tube((sx * 0.1, 0.46, -0.22), (sx * 0.2, 0.46, -0.22), 0.012, CHROME, 4)   # rear-set pegs
    return m


def moped() -> Mesh:
    """TVS XL style moped (1.84 m): a thick open backbone frame you step through, the tank and
    side box under a long flat seat, a low engine with a round flywheel cover, flat foot rests,
    16 inch spoked wheels, a big rear carrier and a hook carrier on the handlebar cowl."""
    m = Mesh()
    r, rz, fz = 0.28, -0.6, 0.63
    _bike_wheel(m, rz, r, 0.036, CHROME, 8, hub=0.07)
    _bike_wheel(m, fz, r, 0.034, CHROME, 8, hub=0.06)
    m.disc_x(-0.05, 0.05, r, rz, 0.075, ENGINE, 12)                            # drum hubs
    m.disc_x(-0.045, 0.045, r, fz, 0.065, ENGINE, 12)
    m.arc_x(r, fz, r + 0.03, 25, 160, 0.055, 0.012, BODY, 10)
    m.arc_x(r, rz, r + 0.03, 50, 185, 0.06, 0.012, BODY, 10)
    head = (0.45, 0.9)
    for sx in (-0.07, 0.07):                                                    # fork with gaiters
        m.tube((sx, r, fz), (sx, 0.55, 0.56), 0.02, CHROME, 6)
        m.tube((sx, 0.55, 0.56), (sx, head[1], head[0]), 0.028, BLACK, 7)
    # Handlebar cowl with the round lamp and the speedometer, a hook carrier in front.
    m.blob([(0, 0.92, 0.36, 0.08, 0.07), (0, 0.95, 0.44, 0.13, 0.1), (0, 0.94, 0.52, 0.12, 0.095), (0, 0.92, 0.57, 0.08, 0.07)], BODY, 12)
    m.disc_z(0.565, 0.585, 0.0, 0.92, 0.066, CHROME, 14, LAMP)
    m.disc_z(0.40, 0.41, 0.0, 1.04, 0.045, BLACK, 10, (236, 236, 230))          # speedo face
    _bars(m, 0.42, 1.0, 0.33, 0.02)
    _path(m, [(-0.08, 0.86, 0.6), (-0.08, 0.8, 0.66), (0.08, 0.8, 0.66), (0.08, 0.86, 0.6)], 0.008, CHROME, 4)
    for sx in (-0.12, 0.12):
        _blinker(m, sx, 0.9, 0.5)
        _blinker(m, sx, 0.66, -0.86)
    # The thick black backbone: down from the head, low through the step-through, up to the seat.
    _path(m, [(0, 0.86, 0.44), (0, 0.6, 0.32), (0, 0.42, 0.18), (0, 0.38, -0.02), (0, 0.5, -0.24), (0, 0.66, -0.42)], 0.045, BLACK, 10)
    for sx in (-1.0, 1.0):
        _path(m, [(sx * 0.08, 0.66, -0.42), (sx * 0.09, 0.7, -0.86)], 0.013, BLACK, 5)
        m.box((sx * 0.1 - 0.07, 0.3, 0.02), (sx * 0.1 + 0.07, 0.315, 0.24), PLASTIC)   # flat foot rests
        m.tube((sx * 0.06, 0.33, 0.12), (sx * 0.13, 0.31, 0.12), 0.01, BLACK, 4)
    # Low engine: crankcase, finned cylinder, a round flywheel cover on the left.
    m.blob([(0, 0.27, -0.24, 0.07, 0.07), (0, 0.27, -0.12, 0.11, 0.1), (0, 0.28, 0.0, 0.11, 0.1), (0, 0.3, 0.06, 0.07, 0.07)], ENGINE, 10)
    m.disc_x(-0.15, -0.105, 0.28, -0.1, 0.11, CHROME, 16)
    m.disc_x(-0.16, -0.15, 0.28, -0.1, 0.06, ENGINE, 10)
    for k in range(4):
        m.box((-0.08, 0.32 + k * 0.035, 0.0 + k * 0.012), (0.08, 0.33 + k * 0.035, 0.12 + k * 0.012), ENGINE)
    # Tank and side box under the seat, with a decal.
    box = [(0, 0.6, -0.08, 0.08, 0.07), (0, 0.6, -0.2, 0.125, 0.11), (0, 0.6, -0.42, 0.13, 0.115), (0, 0.6, -0.58, 0.1, 0.09), (0, 0.6, -0.64, 0.05, 0.05)]
    m.blob(box, BODY, 12, square=2.6)
    _decal(m, box, [(-0.12, 0.66), (-0.5, 0.66), (-0.52, 0.63), (-0.12, 0.63)], ACCENT, 2.6)
    m.blob([(0, 0.73, -0.62, 0.08, 0.025), (0, 0.75, -0.5, 0.13, 0.045), (0, 0.755, -0.24, 0.13, 0.045), (0, 0.75, -0.06, 0.11, 0.04), (0, 0.74, 0.0, 0.06, 0.03)], SEAT, 12)
    # Big rear carrier: a frame of rails over the wheel, the luggage hook rail at the back.
    m.box((-0.15, 0.77, -0.9), (0.15, 0.785, -0.62), CHROME, skip="-y")
    for z in (-0.86, -0.78, -0.7):
        m.tube((-0.15, 0.79, z), (0.15, 0.79, z), 0.006, BLACK, 4)
    for sx in (-0.14, 0.14):
        m.tube((sx, 0.77, -0.9), (sx * 0.8, 0.32, -0.62), 0.009, CHROME, 4)
    m.tube((-0.15, 0.80, -0.92), (0.15, 0.80, -0.92), 0.01, CHROME, 5)
    # Exhaust low on the right.
    _path(m, [(0.06, 0.32, 0.08), (0.13, 0.24, -0.02), (0.14, 0.24, -0.28)], 0.016, BLACK, 6)
    m.blob([(0.14, 0.24, -0.28, 0.03, 0.03), (0.15, 0.25, -0.4, 0.042, 0.042), (0.15, 0.28, -0.66, 0.042, 0.042), (0.15, 0.29, -0.72, 0.025, 0.025)], BLACK, 9)
    _sprocket_chain(m, (-0.06, 0.28), (rz, r), 0.07, -0.07)
    _shocks(m, (-0.56, 0.32), (-0.42, 0.68), 0.12)
    m.tube((-0.06, 0.3, -0.12), (-0.14, 0.01, -0.06), 0.009, BLACK, 4)        # side stand
    m.blob([(0, 0.62, -0.905, 0.04, 0.03), (0, 0.62, -0.925, 0.03, 0.022)], TAIL, 8)
    _plate(m, -0.91, 0.45, 0.08)
    return m


def commuter() -> Mesh:
    """Hero Splendor style 100 cc commuter (1.99 m): tank with knee recesses and stripes, long
    flat seat, striped side panels, round lamp under a small visor, black 5-spoke alloys,
    silver finned engine, full chain cover, chrome silencer with a black guard, saree guard."""
    m = Mesh()
    r, rz, fz = 0.3, -0.62, 0.62
    _bike_wheel(m, rz, r, 0.045, BLACK, alloy=True, hub=0.075)
    _bike_wheel(m, fz, r, 0.04, BLACK, alloy=True, hub=0.065)
    m.disc_x(-0.055, 0.055, r, rz, 0.085, ENGINE, 12)                          # drums
    m.disc_x(-0.05, 0.05, r, fz, 0.075, ENGINE, 12)
    m.arc_x(r, fz, r + 0.025, 25, 150, 0.055, 0.012, BODY, 10)
    m.arc_x(r, rz, r + 0.03, 50, 190, 0.065, 0.012, BLACK, 10)
    head = (0.43, 0.93)
    _fork(m, fz, r, head, CHROME, 0.072, BLACK)
    # Headlamp in a small cowl with a visor, speedo pod behind.
    m.blob([(0, 0.92, 0.42, 0.08, 0.085), (0, 0.93, 0.48, 0.11, 0.11), (0, 0.92, 0.55, 0.095, 0.09)], BLACK, 12)
    m.disc_z(0.55, 0.565, 0.0, 0.92, 0.078, CHROME, 14, LAMP)
    m.blob([(0, 1.0, 0.46, 0.08, 0.012), (0, 1.02, 0.52, 0.09, 0.012), (0, 1.02, 0.56, 0.06, 0.01)], BODY, 8)   # visor
    m.blob([(0, 1.03, 0.4, 0.05, 0.04), (0, 1.04, 0.42, 0.07, 0.05), (0, 1.03, 0.44, 0.05, 0.04)], BLACK, 10)
    _bars(m, 0.38, 1.03, 0.34, 0.03)
    for sx in (-0.13, 0.13):
        _blinker(m, sx, 0.91, 0.47)
        _blinker(m, sx * 0.85, 0.74, -0.8)
    m.tube((0, 0.92, 0.42), (0, 0.44, 0.27), 0.024, BLACK, 6)
    tank = [(0, 0.81, 0.0, 0.08, 0.05), (0, 0.85, 0.1, 0.13, 0.085), (0, 0.87, 0.24, 0.14, 0.1), (0, 0.85, 0.36, 0.115, 0.085), (0, 0.81, 0.44, 0.055, 0.045)]
    m.blob(tank, BODY, 12, square=2.3)
    _decal(m, tank, [(0.36, 0.88), (0.06, 0.85), (0.06, 0.83), (0.36, 0.86)], ACCENT, 2.3)
    m.blob([(-0.05, 0.84, 0.2, 0.02, 0.035), (-0.06, 0.84, 0.15, 0.02, 0.04)], PLASTIC, 6)   # knee pads
    m.blob([(0.05, 0.84, 0.2, 0.02, 0.035), (0.06, 0.84, 0.15, 0.02, 0.04)], PLASTIC, 6)
    m.disc_x(-0.02, 0.02, 0.96, 0.26, 0.028, CHROME, 8)
    m.blob([(0, 0.8, -0.68, 0.07, 0.025), (0, 0.815, -0.56, 0.12, 0.042), (0, 0.815, -0.26, 0.13, 0.046), (0, 0.81, -0.02, 0.115, 0.042), (0, 0.815, 0.05, 0.07, 0.03)], SEAT, 12)
    panels = [(0, 0.66, 0.02, 0.09, 0.08), (0, 0.66, -0.08, 0.125, 0.11), (0, 0.66, -0.3, 0.125, 0.11), (0, 0.66, -0.42, 0.09, 0.08)]
    m.blob(panels, BODY, 10, square=2.6)
    _decal(m, panels, [(-0.04, 0.72), (-0.36, 0.69), (-0.36, 0.665), (-0.04, 0.695)], ACCENT, 2.6)
    m.blob([(0, 0.75, -0.6, 0.1, 0.05), (0, 0.77, -0.76, 0.085, 0.045), (0, 0.78, -0.88, 0.045, 0.03)], BODY, 10)
    m.blob([(0, 0.78, -0.885, 0.04, 0.028), (0, 0.78, -0.91, 0.03, 0.02)], TAIL, 8)
    # Engine: silver crankcase, finned cylinder leaning forward, kick lever.
    m.blob([(0, 0.36, -0.14, 0.1, 0.09), (0, 0.36, -0.02, 0.135, 0.12), (0, 0.36, 0.16, 0.135, 0.12), (0, 0.38, 0.26, 0.09, 0.08)], FRAME_SILVER, 10)
    m.disc_x(-0.15, -0.13, 0.36, 0.06, 0.1, FRAME_SILVER, 14)
    m.blob([(0, 0.44, 0.13, 0.07, 0.07), (0, 0.55, 0.17, 0.078, 0.078), (0, 0.66, 0.21, 0.07, 0.07)], ENGINE, 8)
    for k in range(5):
        y = 0.46 + k * 0.042
        m.box((-0.095, y, 0.06 + k * 0.016), (0.095, y + 0.012, 0.26 + k * 0.016), FRAME_SILVER)
    m.tube((0.14, 0.4, -0.1), (0.16, 0.3, 0.06), 0.01, BLACK, 4)              # kick lever
    for sx in (-0.09, 0.09):
        m.tube((sx, 0.34, -0.12), (sx, r, rz), 0.02, BLACK, 5)
        m.tube((sx, 0.72, -0.1), (sx, 0.76, -0.7), 0.014, BLACK, 5)
    # Full chain cover on the left.
    m.blob([(-0.1, 0.34, -0.04, 0.02, 0.05), (-0.1, 0.33, -0.3, 0.025, 0.07), (-0.1, 0.32, -0.62, 0.025, 0.09), (-0.1, 0.32, -0.7, 0.02, 0.06)], BLACK, 8)
    # Silencer: chrome with a black heat guard.
    _path(m, [(0.1, 0.42, 0.22), (0.16, 0.3, 0.02), (0.16, 0.31, -0.12)], 0.018, CHROME, 6)
    sil = [(0.16, 0.31, -0.12, 0.03, 0.03), (0.17, 0.33, -0.3, 0.05, 0.05), (0.17, 0.41, -0.7, 0.055, 0.055), (0.17, 0.44, -0.86, 0.035, 0.035)]
    m.blob(sil, CHROME, 10)
    m.blob([(0.19, 0.38, -0.28, 0.02, 0.04), (0.2, 0.4, -0.4, 0.02, 0.05), (0.2, 0.42, -0.5, 0.018, 0.04)], BLACK, 6)
    _shocks(m, (-0.56, 0.36), (-0.4, 0.72), 0.125)
    for y in (0.34, 0.46, 0.58):                                              # saree guard
        m.tube((-0.14, y, -0.88), (-0.14, y, -0.4), 0.006, CHROME, 4)
    m.tube((-0.14, 0.3, -0.88), (-0.14, 0.62, -0.88), 0.006, CHROME, 4)
    _path(m, [(-0.11, 0.82, -0.56), (-0.11, 0.84, -0.88), (0.11, 0.84, -0.88), (0.11, 0.82, -0.56)], 0.011, CHROME, 5)   # grab rail
    for sx in (-0.11, 0.11):
        m.tube((sx * 1.5, 0.34, 0.3), (sx * 0.7, 0.62, 0.3), 0.011, CHROME, 5)   # leg guard
        m.tube((sx * 0.9, 0.3, 0.02), (sx * 1.7, 0.3, 0.02), 0.012, BLACK, 4)
    _plate(m, -0.89, 0.6)
    return m


def cruiser() -> Mesh:
    """Royal Enfield Thunderbird style 350 cc cruiser (2.16 m): big teardrop tank, tall pulled-
    back bars, twin-pod console, round lamp with a ring light and visor, stepped seat with a
    backrest, wide rear tyre, black finned engine, long chrome exhaust, crash guard."""
    m = Mesh()
    r, rz, fz = 0.32, -0.71, 0.7
    _bike_wheel(m, rz, r, 0.07, BLACK, alloy=True, hub=0.075)
    _bike_wheel(m, fz, r, 0.048, BLACK, alloy=True, hub=0.06, disc=True)
    m.disc_x(-0.082, -0.074, r, rz, 0.12, CHROME, 12)
    m.arc_x(r, fz, r + 0.02, 15, 160, 0.07, 0.014, BODY, 10)
    m.arc_x(r, rz, r + 0.03, 35, 200, 0.085, 0.014, BODY, 10)
    for sx in (-0.1, 0.1):
        m.tube((sx, r + 0.04, rz - 0.1), (sx, 0.62, rz - 0.34), 0.008, CHROME, 4)   # mudguard stays
    head = (0.52, 0.96)
    _fork(m, fz, r, head, CHROME, 0.09)
    for sx in (-0.09, 0.09):
        m.tube((sx, 0.66, 0.6), (sx, 0.96, 0.5), 0.032, BLACK, 8)               # fork gaiters
    # Lamp: chrome bowl, a ring light round the lens, small visor; twin pods behind.
    m.blob([(0, 0.93, 0.5, 0.07, 0.07), (0, 0.93, 0.56, 0.105, 0.105), (0, 0.93, 0.63, 0.105, 0.105)], CHROME, 14)
    m.disc_z(0.63, 0.645, 0.0, 0.93, 0.1, LAMP, 16, LAMP)
    m.disc_z(0.645, 0.65, 0.0, 0.93, 0.07, CHROME, 14, LAMP)
    m.blob([(0, 1.02, 0.55, 0.08, 0.01), (0, 1.04, 0.61, 0.09, 0.012), (0, 1.04, 0.64, 0.06, 0.01)], BODY, 8)
    for sx in (-0.06, 0.06):
        m.disc_z(0.46, 0.5, sx, 1.07, 0.045, CHROME, 12, (236, 236, 230))
    # Tall pulled-back cruiser bars.
    for sx in (-1.0, 1.0):
        _path(m, [(sx * 0.05, 1.0, 0.5), (sx * 0.16, 1.15, 0.46), (sx * 0.32, 1.17, 0.34), (sx * 0.38, 1.15, 0.26)], 0.014, CHROME, 6)
        m.tube((sx * 0.3, 1.16, 0.32), (sx * 0.41, 1.14, 0.22), 0.021, BLACK, 7, True)
        m.tube((sx * 0.2, 1.16, 0.44), (sx * 0.27, 1.27, 0.45), 0.007, CHROME, 4)
        m.blob([(sx * 0.27, 1.29, 0.43, 0.03, 0.022), (sx * 0.27, 1.295, 0.45, 0.055, 0.04), (sx * 0.27, 1.29, 0.46, 0.05, 0.035)], CHROME, 8)
        _blinker(m, sx * 0.16, 0.9, 0.55)
        _blinker(m, sx * 0.15, 0.7, -0.94)
    tank = [(0, 0.81, -0.06, 0.07, 0.045), (0, 0.87, 0.04, 0.15, 0.1), (0, 0.9, 0.2, 0.175, 0.12), (0, 0.89, 0.36, 0.155, 0.105), (0, 0.84, 0.48, 0.07, 0.05)]
    m.blob(tank, BODY, 14)
    _decal(m, tank, [(0.4, 0.905), (0.05, 0.905), (0.04, 0.89), (0.4, 0.89)], ACCENT)
    m.disc_x(-0.024, 0.024, 1.01, 0.24, 0.032, CHROME, 10)
    # Stepped seat: low rider seat, raised pillion, a backrest on chrome loops.
    m.blob([(0, 0.79, -0.4, 0.11, 0.04), (0, 0.8, -0.26, 0.17, 0.055), (0, 0.8, -0.1, 0.15, 0.05), (0, 0.81, -0.02, 0.08, 0.035)], SEAT, 12)
    m.blob([(0, 0.86, -0.72, 0.09, 0.035), (0, 0.87, -0.6, 0.13, 0.045), (0, 0.86, -0.46, 0.12, 0.04)], SEAT, 10)
    for sx in (-0.1, 0.1):
        _path(m, [(sx * 1.3, 0.78, -0.56), (sx, 0.95, -0.8), (sx, 1.08, -0.82)], 0.012, CHROME, 5)
    m.blob([(0, 1.06, -0.84, 0.1, 0.05), (0, 1.07, -0.82, 0.12, 0.07), (0, 1.06, -0.8, 0.1, 0.05)], SEAT, 10)   # backrest pad
    box = [(0, 0.62, -0.36, 0.1, 0.09), (0, 0.62, -0.25, 0.155, 0.13), (0, 0.62, -0.08, 0.155, 0.13), (0, 0.62, 0.0, 0.11, 0.1)]
    m.blob(box, BODY, 10)
    # Black engine with chrome covers.
    m.blob([(0, 0.38, -0.1, 0.11, 0.1), (0, 0.38, 0.02, 0.16, 0.14), (0, 0.38, 0.2, 0.16, 0.14), (0, 0.4, 0.32, 0.1, 0.09)], (40, 40, 44), 10)
    m.disc_x(-0.18, -0.15, 0.38, 0.06, 0.12, CHROME, 16)
    m.disc_x(0.15, 0.18, 0.4, 0.14, 0.09, CHROME, 14)
    m.blob([(0, 0.5, 0.16, 0.09, 0.09), (0, 0.62, 0.17, 0.097, 0.097), (0, 0.75, 0.18, 0.085, 0.085)], (40, 40, 44), 10)
    for k in range(6):
        y = 0.5 + k * 0.042
        m.box((-0.12, y, 0.05), (0.12, y + 0.012, 0.3), (58, 58, 62))
    m.blob([(0, 0.8, 0.18, 0.07, 0.03), (0, 0.82, 0.18, 0.09, 0.04)], CHROME, 10)   # rocker cover
    m.tube((0, 0.96, 0.48), (0, 0.44, 0.36), 0.026, BLACK, 6)
    for sx in (-0.1, 0.1):
        m.tube((sx, 0.36, -0.1), (sx, r, rz), 0.024, BLACK, 5)
        m.tube((sx, 0.74, -0.1), (sx, 0.76, -0.82), 0.016, BLACK, 5)
    _path(m, [(0.12, 0.62, 0.26), (0.19, 0.34, 0.2), (0.2, 0.31, -0.06)], 0.025, CHROME, 7)
    m.blob([(0.2, 0.31, -0.06, 0.03, 0.03), (0.21, 0.31, -0.2, 0.05, 0.05), (0.21, 0.35, -0.86, 0.06, 0.06), (0.21, 0.37, -1.02, 0.045, 0.045)], CHROME, 12)
    _sprocket_chain(m, (0.06, 0.36), (rz, r), 0.1, -0.1)
    _shocks(m, (-0.64, 0.36), (-0.46, 0.78), 0.15)
    m.blob([(0, 0.66, -1.02, 0.055, 0.05), (0, 0.66, -1.05, 0.045, 0.04)], TAIL, 10)
    _plate(m, -1.04, 0.46, 0.1)
    for sx in (-0.2, 0.2):
        _path(m, [(sx * 0.4, 0.66, 0.4), (sx, 0.52, 0.42), (sx, 0.3, 0.36)], 0.014, CHROME, 5)   # crash guard
        m.tube((sx * 0.5, 0.32, 0.08), (sx * 1.05, 0.32, 0.08), 0.013, BLACK, 4)
    return m


def bicycle() -> Mesh:
    """Roadster bicycle with a carrier, a stand and a chain guard (1.82 m)."""
    m = Mesh()
    r, rz, fz = 0.34, -0.54, 0.56
    for z in (rz, fz):
        _tyre(m, z, r, 0.017, CHROME, 0.0, 20)
        for i in range(8):
            a = math.pi * i / 8
            m.tube((0, r - math.sin(a) * r * 0.76, z - math.cos(a) * r * 0.76), (0, r + math.sin(a) * r * 0.76, z + math.cos(a) * r * 0.76), 0.004, CHROME, 3)
        m.disc_x(-0.03, 0.03, r, z, 0.018, CHROME, 6)
    m.arc_x(r, fz, r + 0.015, 30, 150, 0.022, 0.006, BODY, 8)
    m.arc_x(r, rz, r + 0.015, 30, 190, 0.022, 0.006, BODY, 9)
    seat, bb, head_t, head_b = (-0.20, 0.92), (-0.06, 0.30), (0.34, 0.90), (0.37, 0.72)
    m.tube((0, seat[1], seat[0]), (0, bb[1], bb[0]), 0.016, BODY, 7)          # seat tube
    m.tube((0, seat[1] - 0.10, seat[0] + 0.02), (0, head_t[1], head_t[0]), 0.015, BODY, 7)   # top tube
    m.tube((0, bb[1], bb[0]), (0, head_b[1], head_b[0]), 0.017, BODY, 7)      # down tube
    m.tube((0, head_b[1], head_b[0]), (0, 1.02, 0.31), 0.017, BODY, 7)        # head tube
    for s in (-0.035, 0.035):
        m.tube((s, r, fz), (s, head_b[1], head_b[0]), 0.011, BODY, 5)         # fork
        m.tube((s, r, rz), (0, bb[1], bb[0]), 0.010, BODY, 5)                 # chain stays
        m.tube((s, r, rz), (0, seat[1] - 0.12, seat[0] + 0.02), 0.009, BODY, 5)   # seat stays
        m.tube((s * 2.4, 0.70, rz - 0.30), (s, r, rz), 0.006, CHROME, 4)      # carrier stays
    m.box((-0.07, 0.69, rz - 0.32), (0.07, 0.705, rz + 0.20), CHROME)         # carrier
    m.blob([(0, 0.955, -0.36, 0.06, 0.02), (0, 0.96, -0.28, 0.085, 0.03), (0, 0.955, -0.14, 0.05, 0.026), (0, 0.95, -0.07, 0.022, 0.018)], SEAT_TAN, 8)   # saddle
    m.tube((-0.26, 1.03, 0.24), (0.26, 1.03, 0.24), 0.011, CHROME, 6)         # handlebar
    for s in (-1.0, 1.0):
        m.tube((s * 0.26, 1.03, 0.24), (s * 0.26, 1.03, 0.10), 0.015, BLACK, 6, True)
    m.box((0.035, 0.26, -0.50), (0.045, 0.40, 0.02), BLACK)                   # chain guard
    m.disc_x(0.03, 0.05, 0.30, -0.06, 0.09, CHROME, 12)                       # chain wheel
    m.tube((-0.10, 0.30, -0.06), (0.10, 0.30, -0.06), 0.008, BLACK, 4)        # pedals
    m.box((-0.15, 0.37, -0.10), (-0.09, 0.39, -0.02), BLACK)
    m.box((0.09, 0.21, -0.10), (0.15, 0.23, -0.02), BLACK)
    m.tube((-0.04, r, rz), (-0.13, 0.01, rz + 0.06), 0.007, BLACK, 4)         # stand
    m.blob([(0, 1.01, 0.33, 0.03, 0.03), (0, 1.01, 0.37, 0.04, 0.04), (0, 1.01, 0.40, 0.03, 0.03)], CHROME, 8)   # dynamo lamp
    return m


# ---------------------------------------------------------------- cars

def _car_wheels(m: Mesh, w_at, r: float, zs, t: float = 0.09) -> None:
    for z in zs:
        for s in (-1.0, 1.0):
            xc = s * (w_at(z) - t - 0.012)
            _tyre(m, z, r, t, PLASTIC, xc, 18)
            xo = xc + s * t * 0.82
            m.disc_x(min(xc - s * t * 0.8, xo), max(xc - s * t * 0.8, xo), r, z, r * 0.745, PLASTIC, 18, CHROME)
            for k in range(5):                                                # the gaps between the alloy's spokes
                a = 2 * math.pi * k / 5
                poly = [(z + r * rr * math.cos(a + da), r + r * rr * math.sin(a + da)) for (rr, da) in ((0.30, -0.25), (0.64, -0.42), (0.64, 0.42), (0.30, 0.25))]
                m.panel(poly, lambda _z, _y, xo=xo: abs(xo), PLASTIC, 0.003, (s,))
            m.panel([(z + r * 0.16 * math.cos(a), r + r * 0.16 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 9)[:-1]], lambda _z, _y, xo=xo: abs(xo), CHROME, 0.005, (s,))


def _car(P: dict) -> Mesh:
    """Smooth car body between z0 (tail) and z1 (nose): ~30 cross-sections of 10 points, glass
    and pillars by region, then wheels, arches, lamps, grille, seams, handles, mirrors, plates."""
    m = Mesh()
    z0, z1 = P["z0"], P["z1"]
    hw, H, belt, floor = P["W"] * 0.5, P["H"], P["belt"], P.get("floor", 0.2)
    cowl, atop, rend, rbase = P["cowl"], P["a_top"], P["roof_end"], P["rear_base"]
    hood_y, deck_y = P["hood_y"], P.get("deck_y", belt)
    tuck, crown = P.get("tuck", 0.15), P.get("crown", 0.04)
    taper_f, taper_r = P.get("taper", 0.10), P.get("taper_rear", P.get("taper", 0.10))
    pillars = P.get("pillars", [])
    glass_rear = P.get("glass_rear", rend)
    rear_glass = P.get("rear_glass", True)
    length = z1 - z0
    mid = (z0 + z1) * 0.5

    def ease(t: float) -> float:
        return math.sin(max(0.0, min(1.0, t)) * math.pi * 0.5)

    def beltline(z: float) -> float:
        if z > cowl:
            return belt - 0.03 + (hood_y - (belt - 0.03)) * ((z - cowl) / max(z1 - cowl, 1e-6)) ** 1.3
        if z < rbase:
            return belt + (deck_y - belt) * (rbase - z) / max(rbase - z0, 1e-6)
        return belt

    def top(z: float) -> float:
        b = beltline(z)
        if rend <= z <= atop:
            return H
        if atop < z < cowl:
            return b + 0.012 + (H - b - 0.012) * ease((cowl - z) / (cowl - atop))
        if rbase < z < rend:
            return b + 0.012 + (H - b - 0.012) * ease((z - rbase) / (rend - rbase))
        return b + 0.012

    def w_at(z: float) -> float:
        s_f = max(0.0, min(1.0, (z - (mid + 0.3 * length)) / (0.2 * length)))
        s_r = max(0.0, min(1.0, ((mid - 0.3 * length) - z) / (0.2 * length)))
        return hw * (1.0 - taper_f * s_f * s_f - taper_r * s_r * s_r)

    def ring(z: float, end: bool) -> list:
        w, b, t = w_at(z), beltline(z), top(z)
        s_end = max(0.0, (abs(z - mid) - 0.3 * length) / (0.2 * length))
        yb = floor + 0.07 * s_end * s_end
        f = max(0.0, min(1.0, (t - b) / (H - belt)))
        wt = (w - 0.05) - (tuck - 0.05) * f
        y5 = b + min(0.035, 0.3 * (t - b))
        y6 = max(y5, t - 0.075)

        def xg(y: float) -> float:
            return (w - 0.015) + (wt - (w - 0.015)) * ((y - b) / max(t - b, 1e-6))

        c = crown * (0.4 + 0.6 * f)
        pts = [(0.0, yb), (w * 0.8, yb), (w, yb + 0.07), (w, b - 0.05), (w - 0.015, b), (xg(y5), y5), (xg(y6), y6), (wt, t - 0.012), (wt * 0.55, t + c * 0.8), (0.0, t + c)]
        if end:
            ym = (yb + t) * 0.5
            pts = [(x * 0.9, ym + (y - ym) * 0.86) for (x, y) in pts]
        return pts

    zs = {z0, z0 + 0.10, z1 - 0.10, z1, rbase + 0.07, rend - 0.05, atop + 0.05, cowl - 0.06, cowl - 0.03, glass_rear,
        mid + 0.3 * length, mid + 0.4 * length, mid - 0.3 * length, mid - 0.4 * length}
    zs |= set(np.linspace(rbase, rend, 5)) | set(np.linspace(atop, cowl, 6)) | set(np.linspace(cowl, z1 - 0.10, 4))
    zs |= set(np.linspace(z0 + 0.10, rbase, 3)) | set(np.linspace(rend, atop, 4))
    for pz in pillars:
        zs |= {pz - 0.04, pz + 0.04}
    stations = []
    for z in sorted(float(v) for v in zs if z0 <= v <= z1):
        if not stations or z - stations[-1] > 0.012:
            stations.append(z)
        elif z in (z0, z1):
            stations[-1] = z
    rings = [ring(z, z in (z0, z1) and ((z == z1 and taper_f > 0.0) or (z == z0 and taper_r > 0.0))) for z in stations]

    def colour(i: int, j: int):
        zm = (stations[i] + stations[i + 1]) * 0.5
        if j <= 1:
            return PLASTIC
        tall = top(zm) - beltline(zm) > 0.14
        if j == 5 and tall and glass_rear - 0.005 <= zm <= cowl - 0.03 and not any(abs(zm - pz) < 0.04 for pz in pillars):
            return GLASS
        if j >= 7 and (atop + 0.05 < zm < cowl - 0.06 or (rear_glass and rbase + 0.07 < zm < rend - 0.05)):
            return GLASS
        return BODY

    for side in (1.0, -1.0):
        pts = [[(side * x, y, z) for (x, y) in rings[i]] for i, z in enumerate(stations)]
        m.grid(pts, colour, lambda i: (0.0, (floor + beltline(stations[i])) * 0.5, stations[i]))
        for end, hint in ((0, -1.0), (len(stations) - 1, 1.0)):
            row = pts[end]
            cy = (row[0][1] + row[-1][1]) * 0.5
            for j in range(len(row) - 1):
                m.tri((0.0, cy, stations[end]), row[j], row[j + 1], PLASTIC if j <= 1 else BODY, (0, 0, hint))
    # Wheels and dark wheel wells on the flat of the flank.
    r = P["wheel_r"]
    _car_wheels(m, w_at, r, P["wheels"])
    for wz in P["wheels"]:
        arch = [(wz + (r + 0.065) * math.cos(math.radians(a)), max(floor + 0.07, r + (r + 0.065) * math.sin(math.radians(a)))) for a in range(0, 181, 15)]
        m.panel(arch, lambda z, _y: w_at(z), BLACK, 0.003)
    # Door seams, handles and mirrors.
    for dz in P.get("seams", []):
        m.panel([(dz - 0.006, floor + 0.09), (dz + 0.006, floor + 0.09), (dz + 0.006, belt - 0.05), (dz - 0.006, belt - 0.05)], lambda z, _y: w_at(z), PLASTIC, 0.003)
    for hz in P.get("handles", []):
        for s in (-1.0, 1.0):
            m.box((s * (w_at(hz) + 0.012) - 0.012, belt - 0.13, hz - 0.07), (s * (w_at(hz) + 0.012) + 0.012, belt - 0.10, hz + 0.07), PLASTIC)
    for s in (-1.0, 1.0):
        mx, my, mz = s * (w_at(cowl) + 0.085), belt + 0.06, cowl - 0.20
        m.blob([(mx, my, mz - 0.05, 0.03, 0.03), (mx, my, mz, 0.075, 0.055), (mx, my, mz + 0.04, 0.06, 0.045)], BODY if P.get("body_mirrors", True) else PLASTIC, 8)
        m.box((min(mx, s * w_at(cowl)), my - 0.02, mz - 0.02), (max(mx, s * w_at(cowl)), my, mz + 0.02), PLASTIC)
    # Nose: lamps, grille, lower intake, plate.  Tail: lamps, plate, reflector strip.
    nose, tail = rings[-1], rings[0]
    nw, n_top, n_bot = nose[3][0], nose[7][1], nose[0][1]
    zf, zr = z1 + 0.004, z0 - 0.004
    lamp_lo, lamp_hi = n_top - P.get("lamp_drop", 0.2), n_top - 0.06
    for s in (-1.0, 1.0):
        m.quad((s * nw * 0.42, lamp_lo, zf), (s * nw * 0.93, lamp_lo + 0.02, zf), (s * nw * 0.93, lamp_hi, zf), (s * nw * 0.42, lamp_hi - 0.02, zf), LAMP, (0, 0, 1))
        m.quad((s * nw * 0.80, lamp_lo + 0.02, zf + 0.002), (s * nw * 0.93, lamp_lo + 0.02, zf + 0.002), (s * nw * 0.93, lamp_hi, zf + 0.002), (s * nw * 0.80, lamp_hi - 0.01, zf + 0.002), AMBER, (0, 0, 1))
    m.quad((-nw * 0.38, lamp_lo + 0.01, zf), (nw * 0.38, lamp_lo + 0.01, zf), (nw * 0.38, lamp_hi - 0.03, zf), (-nw * 0.38, lamp_hi - 0.03, zf), BLACK, (0, 0, 1))
    m.quad((-nw * 0.34, (lamp_lo + lamp_hi) * 0.5 - 0.012, zf + 0.002), (nw * 0.34, (lamp_lo + lamp_hi) * 0.5 - 0.012, zf + 0.002), (nw * 0.34, (lamp_lo + lamp_hi) * 0.5 + 0.004, zf + 0.002), (-nw * 0.34, (lamp_lo + lamp_hi) * 0.5 + 0.004, zf + 0.002), CHROME, (0, 0, 1))
    m.quad((-nw * 0.72, n_bot + 0.05, zf), (nw * 0.72, n_bot + 0.05, zf), (nw * 0.62, n_bot + 0.19, zf), (-nw * 0.62, n_bot + 0.19, zf), BLACK, (0, 0, 1))
    m.box((-0.24, n_bot + 0.215, zf - 0.004), (0.24, n_bot + 0.315, zf + 0.004), PLATE)
    tw, t_top, t_bot = tail[3][0], tail[4][1], tail[0][1]
    for s in (-1.0, 1.0):
        m.quad((s * tw * 0.62, t_top - 0.30, zr), (s * tw * 0.95, t_top - 0.30, zr), (s * tw * 0.95, t_top - 0.07, zr), (s * tw * 0.62, t_top - 0.10, zr), TAIL, (0, 0, -1))
        m.quad((s * tw * 0.62, t_top - 0.30, zr - 0.002), (s * tw * 0.95, t_top - 0.30, zr - 0.002), (s * tw * 0.95, t_top - 0.25, zr - 0.002), (s * tw * 0.62, t_top - 0.25, zr - 0.002), LAMP, (0, 0, -1))
    m.box((-0.24, t_top - 0.36, zr - 0.004), (0.24, t_top - 0.26, zr + 0.004), PLATE)
    m.quad((-tw * 0.7, t_bot + 0.05, zr), (tw * 0.7, t_bot + 0.05, zr), (tw * 0.7, t_bot + 0.15, zr), (-tw * 0.7, t_bot + 0.15, zr), BLACK, (0, 0, -1))
    return m


def hatchback() -> Mesh:
    """Small hatchback, the commonest car on a Chennai street (3.85 x 1.70 x 1.52 m)."""
    return _car({"z0": -1.925, "z1": 1.925, "W": 1.70, "H": 1.50, "belt": 0.92, "hood_y": 0.78, "cowl": 0.82, "a_top": 0.12,
        "roof_end": -1.22, "rear_base": -1.80, "deck_y": 0.9, "pillars": [-0.42], "wheel_r": 0.30, "wheels": (1.22, -1.24),
        "seams": [0.62, -0.42, -1.02], "handles": [-0.30, -0.92]})


def tallboy() -> Mesh:
    """Tall-boy city hatchback: short bonnet, upright sides, high roof (3.60 x 1.52 x 1.68 m)."""
    m = _car({"z0": -1.80, "z1": 1.80, "W": 1.52, "H": 1.64, "belt": 0.97, "hood_y": 0.86, "cowl": 0.95, "a_top": 0.46,
        "roof_end": -1.48, "rear_base": -1.72, "deck_y": 0.95, "taper": 0.07, "tuck": 0.10, "glass_rear": -1.36,
        "pillars": [-0.24, -1.0], "wheel_r": 0.28, "wheels": (1.16, -1.22), "seams": [0.70, -0.24, -1.0], "handles": [-0.12, -0.88]})
    for s in (-0.52, 0.52):
        m.tube((s, 1.675, -1.2), (s, 1.675, 0.25), 0.014, PLASTIC, 5, True)   # roof rails
    return m


def van() -> Mesh:
    """One-box micro van: flat nose, sliding-door sides (3.37 x 1.41 x 1.64 m)."""
    return _car({"z0": -1.685, "z1": 1.685, "W": 1.41, "H": 1.62, "belt": 0.98, "hood_y": 0.92, "cowl": 1.50, "a_top": 1.16,
        "roof_end": -1.56, "rear_base": -1.66, "deck_y": 0.97, "taper": 0.05, "tuck": 0.08, "crown": 0.03, "glass_rear": -1.44,
        "pillars": [0.40, -0.55], "wheel_r": 0.26, "wheels": (1.05, -0.86), "seams": [0.40, -0.55], "handles": [0.52, -0.42],
        "body_mirrors": False, "lamp_drop": 0.24})


def mini_truck() -> Mesh:
    """Mini truck with a load of 20 litre water cans (3.80 x 1.50 x 1.85 m)."""
    hl, hw, r = 1.90, 0.75, 0.27
    cab_back = 0.62
    m = _car({"z0": cab_back, "z1": hl, "W": 1.50, "H": 1.82, "belt": 1.06, "hood_y": 0.98, "cowl": 1.78, "a_top": 1.50,
        "roof_end": cab_back + 0.08, "rear_base": cab_back + 0.01, "floor": 0.30, "taper": 0.16, "taper_rear": 0.0, "tuck": 0.09,
        "crown": 0.03, "rear_glass": False, "pillars": [], "wheel_r": r, "wheels": (1.22,), "seams": [0.80],
        "handles": [0.92], "body_mirrors": False, "lamp_drop": 0.26})
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
                x = x_start + ix * (can + gap) + can * 0.5
                z = -hl + 0.08 + iz * (can + gap) + can * 0.5
                y = deck + layer * 0.40
                # A can: round drum with a shoulder and a white cap.
                seg = 6
                rings = [(y, can * 0.5), (y + 0.30, can * 0.5), (y + 0.36, can * 0.2), (y + 0.40, can * 0.2)]
                pts = [[(x + rr * math.cos(2 * math.pi * k / seg), yy, z + rr * math.sin(2 * math.pi * k / seg)) for k in range(seg)] for (yy, rr) in rings]
                m.grid(pts, lambda i, j: CAN_CAP if i == 2 else CAN_BLUE, lambda i, x=x, z=z, rings=rings: (x, rings[i][0], z), closed_j=True)
                for k in range(1, seg - 1):
                    m.tri(pts[3][0], pts[3][k], pts[3][k + 1], CAN_CAP, (0, 1, 0))
    _car_wheels(m, lambda _z: hw, r, (-0.92,))
    return m


VEHICLES = {
    "moped": moped, "commuter_bike": commuter, "cruiser_bike": cruiser, "sport_bike": sport_bike, "bicycle": bicycle,
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
