"""Geometry kit for the procedural heritage landmarks (tools/art/make_landmarks.py).

A flat-shaded, vertex-coloured triangle soup (make_chennai_vehicles.Mesh) with a transform stack,
so every part is built in its own little frame (+z = the face that looks out, +y = up) and then
placed with push(pos, yaw). yaw follows Godot's Basis(Vector3.UP, yaw): local +x -> (cos, 0, -sin),
local +z -> (sin, 0, cos).
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import mapbox_earcut as earcut
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_chennai_vehicles import Mesh  # noqa: E402


def shade(col, k: float):
    """k < 1 darkens, k > 1 lightens towards white."""
    if k <= 1.0:
        return tuple(int(round(c * k)) for c in col)
    t = min(k - 1.0, 1.0)
    return tuple(int(round(c + (255 - c) * t)) for c in col)


class LM(Mesh):
    def __init__(self) -> None:
        super().__init__()
        self.stack = [np.eye(4)]
        self.boxes: list[tuple] = []  # collider boxes (centre xyz, size xyz, yaw) in model space

    # ------------------------------------------------------------ transforms
    def push(self, pos=(0.0, 0.0, 0.0), yaw: float = 0.0, scale: float = 1.0) -> None:
        c, s = math.cos(yaw), math.sin(yaw)
        m = np.array([[c * scale, 0, s * scale, pos[0]], [0, scale, 0, pos[1]],
                      [-s * scale, 0, c * scale, pos[2]], [0, 0, 0, 1]], dtype=float)
        self.stack.append(self.stack[-1] @ m)

    def pop(self) -> None:
        self.stack.pop()

    def world(self, v):
        t = self.stack[-1]
        return t[:3, :3] @ np.asarray(v, dtype=float) + t[:3, 3]

    def yaw_now(self) -> float:
        t = self.stack[-1]
        return math.atan2(t[0, 2], t[0, 0])

    def tri(self, a, b, c, col, hint, normals=None) -> None:
        t = self.stack[-1]
        r = t[:3, :3]
        a, b, c = (r @ np.asarray(v, dtype=float) + t[:3, 3] for v in (a, b, c))
        h = r @ np.asarray(hint, dtype=float)
        if normals is not None:
            normals = tuple(r @ np.asarray(n, dtype=float) for n in normals)
        super().tri(a, b, c, col, h, normals)

    def collider(self, centre, size) -> None:
        """An oriented collision box in the current frame (only yaw is kept)."""
        self.boxes.append((tuple(round(float(v), 3) for v in self.world(centre)),
                           tuple(round(float(v), 3) for v in size), round(self.yaw_now(), 4)))

    # ------------------------------------------------------------ solids
    def cbox(self, centre, size, col, skip: str = "") -> None:
        cx, cy, cz = centre
        sx, sy, sz = size
        self.box((cx - sx / 2, cy - sy / 2, cz - sz / 2), (cx + sx / 2, cy + sy / 2, cz + sz / 2), col, skip)

    def ybox(self, x0, x1, y0, y1, z0, z1, col, skip: str = "") -> None:
        self.box((min(x0, x1), y0, min(z0, z1)), (max(x0, x1), y1, max(z0, z1)), col, skip)

    def prism(self, n: int, r0: float, r1: float, y0: float, y1: float, col, top=True, bottom=False,
              rot: float = 0.0, cx: float = 0.0, cz: float = 0.0, cols=None) -> None:
        """n-sided frustum (r = circumradius); r1 = 0 makes a pyramid."""
        ring = [(math.cos(rot + 2 * math.pi * i / n), math.sin(rot + 2 * math.pi * i / n)) for i in range(n)]
        for i in range(n):
            (ax, az), (bx, bz) = ring[i], ring[(i + 1) % n]
            c = col if cols is None else cols[i % len(cols)]
            mx, mz = (ax + bx) / 2, (az + bz) / 2
            if r1 <= 1e-6:
                self.tri((cx + ax * r0, y0, cz + az * r0), (cx + bx * r0, y0, cz + bz * r0), (cx, y1, cz), c, (mx, (r0 - r1) / max(y1 - y0, 1e-6) * 0.5, mz))
            else:
                self.quad((cx + ax * r0, y0, cz + az * r0), (cx + bx * r0, y0, cz + bz * r0),
                          (cx + bx * r1, y1, cz + bz * r1), (cx + ax * r1, y1, cz + az * r1), c, (mx, 0.3 * (r0 - r1), mz))
        if top and r1 > 1e-6:
            for i in range(1, n - 1):
                self.tri((cx + ring[0][0] * r1, y1, cz + ring[0][1] * r1), (cx + ring[i][0] * r1, y1, cz + ring[i][1] * r1),
                         (cx + ring[i + 1][0] * r1, y1, cz + ring[i + 1][1] * r1), col, (0, 1, 0))
        if bottom:
            for i in range(1, n - 1):
                self.tri((cx + ring[0][0] * r0, y0, cz + ring[0][1] * r0), (cx + ring[i][0] * r0, y0, cz + ring[i][1] * r0),
                         (cx + ring[i + 1][0] * r0, y0, cz + ring[i + 1][1] * r0), col, (0, -1, 0))

    def rfrustum(self, w0, d0, w1, d1, y0, y1, col, top=True, cx=0.0, cz=0.0, side_cols=None) -> None:
        """Rectangular frustum: w along x, d along z. side_cols = (+z, +x, -z, -x)."""
        b = [(-w0 / 2, -d0 / 2), (w0 / 2, -d0 / 2), (w0 / 2, d0 / 2), (-w0 / 2, d0 / 2)]
        t = [(-w1 / 2, -d1 / 2), (w1 / 2, -d1 / 2), (w1 / 2, d1 / 2), (-w1 / 2, d1 / 2)]
        hints = [(0, 0, -1), (1, 0, 0), (0, 0, 1), (-1, 0, 0)]
        order = {(0, 0, 1): 0, (1, 0, 0): 1, (0, 0, -1): 2, (-1, 0, 0): 3}
        for i in range(4):
            j = (i + 1) % 4
            c = col if side_cols is None else side_cols[order[hints[i]]]
            self.quad((cx + b[i][0], y0, cz + b[i][1]), (cx + b[j][0], y0, cz + b[j][1]),
                      (cx + t[j][0], y1, cz + t[j][1]), (cx + t[i][0], y1, cz + t[i][1]), c, hints[i])
        if top:
            self.quad((cx + t[0][0], y1, cz + t[0][1]), (cx + t[1][0], y1, cz + t[1][1]),
                      (cx + t[2][0], y1, cz + t[2][1]), (cx + t[3][0], y1, cz + t[3][1]), col, (0, 1, 0))

    def lathe(self, prof, seg: int, col, cx=0.0, cz=0.0, y=0.0, rot=0.0, cols=None) -> None:
        """Surface of revolution through (r, y) pairs, bottom to top (r 0 closes a pole)."""
        ring = [(math.cos(rot + 2 * math.pi * i / seg), math.sin(rot + 2 * math.pi * i / seg)) for i in range(seg)]
        for k in range(len(prof) - 1):
            (r0, y0), (r1, y1) = prof[k], prof[k + 1]
            c = col if cols is None else cols[k % len(cols)]
            for i in range(seg):
                (ax, az), (bx, bz) = ring[i], ring[(i + 1) % seg]
                mx, mz = (ax + bx) / 2, (az + bz) / 2
                h = (mx * (y1 - y0 if abs(y1 - y0) > 1e-6 else 0.0) + 0.0, (r0 - r1) + (1.0 if abs(y1 - y0) < 1e-6 and r1 < r0 else 0.0), mz * (y1 - y0 if abs(y1 - y0) > 1e-6 else 0.0))
                if abs(y1 - y0) < 1e-6:
                    h = (0, 1 if r1 < r0 else -1, 0)
                else:
                    h = (mx, (r0 - r1) / (y1 - y0), mz)
                p00 = (cx + ax * r0, y + y0, cz + az * r0)
                p01 = (cx + bx * r0, y + y0, cz + bz * r0)
                p11 = (cx + bx * r1, y + y1, cz + bz * r1)
                p10 = (cx + ax * r1, y + y1, cz + az * r1)
                if r0 < 1e-6:
                    self.tri(p00, p11, p10, c, h)
                elif r1 < 1e-6:
                    self.tri(p00, p01, p10, c, h)
                else:
                    self.quad(p00, p01, p11, p10, c, h)

    def bar(self, p0, p1, r: float, col, seg: int = 4) -> None:
        """Flat-shaded bar (no smooth normals: they light badly at this scale)."""
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
        ring = [u * math.cos(2 * math.pi * (i + 0.5) / seg) + v * math.sin(2 * math.pi * (i + 0.5) / seg) for i in range(seg)]
        for i in range(seg):
            a, b = ring[i], ring[(i + 1) % seg]
            self.quad(p0 + a * r, p0 + b * r, p1 + b * r, p1 + a * r, col, a + b)
        for i in range(1, seg - 1):
            self.tri(p1 + ring[0] * r, p1 + ring[i] * r, p1 + ring[i + 1] * r, col, axis)

    # ------------------------------------------------------------ planar shapes (local XY, facing +z)
    def flat(self, poly, z: float, col, facing: float = 1.0, holes=None) -> None:
        rings = [list(poly)] + [list(h) for h in (holes or [])]
        pts = [p for r in rings for p in r]
        ends, n = [], 0
        for r in rings:
            n += len(r)
            ends.append(n)
        idx = earcut.triangulate_float64(np.array(pts, dtype=np.float64), np.array(ends, dtype=np.uint32))
        for t in range(0, len(idx), 3):
            a, b, c = (pts[int(idx[t + k])] for k in range(3))
            self.tri((a[0], a[1], z), (b[0], b[1], z), (c[0], c[1], z), col, (0, 0, facing))

    def extrude(self, poly, z0: float, z1: float, col, side=None, back=True, holes=None) -> None:
        """Polygon in the XY plane, from z0 (back) to z1 (front, facing +z)."""
        self.flat(poly, z1, col, 1.0, holes)
        if back:
            self.flat(poly, z0, col, -1.0, holes)
        sc = col if side is None else side
        for ring, inward in [(list(poly), False)] + [(list(h), True) for h in (holes or [])]:
            n = len(ring)
            area = sum(ring[i - 1][0] * ring[i][1] - ring[i][0] * ring[i - 1][1] for i in range(n))
            for i in range(n):
                a, b = ring[i], ring[(i + 1) % n]
                ex, ey = b[0] - a[0], b[1] - a[1]
                nx, ny = (ey, -ex) if area > 0 else (-ey, ex)
                if inward:
                    nx, ny = -nx, -ny
                if abs(ex) + abs(ey) < 1e-7:
                    continue
                self.quad((a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1), sc, (nx, ny, 0))


# ------------------------------------------------------------ outlines

def arch(w: float, y0: float, spring: float, kind: str = "pointed", n: int = 6, rise: float | None = None):
    """Opening outline (counter-clockwise), w wide, sill y0, springing at `spring`.
    pointed: two arcs of radius ~w (equilateral); round: semicircle; horseshoe: 3/4 circle;
    rise overrides the apex height above the springing for pointed arches."""
    h = w / 2.0
    pts = [(-h, y0), (h, y0), (h, spring)]
    if kind == "round":
        for i in range(1, n):
            a = math.pi * i / n
            pts.append((h * math.cos(a), spring + h * math.sin(a)))
    elif kind == "horseshoe":
        r = h * 1.12
        cy = spring + math.sqrt(max(r * r - h * h, 0.0))
        a0 = -math.asin(h / r) if r > h else 0.0
        a0 = math.atan2(spring - cy, h)
        a1 = math.pi - a0
        for i in range(1, 2 * n):
            a = a0 + (a1 - a0) * i / (2 * n)
            pts.append((r * math.cos(a), cy + r * math.sin(a)))
    else:
        apex = h * 1.73 if rise is None else rise
        # Each side is an arc centred on the opposite springing line, radius R (through the apex).
        R = (h * h + apex * apex) / (2 * h) if apex > 0 else w
        cxr = h - R  # centre of the right-hand arc (x)
        for i in range(1, n + 1):
            t = i / n
            yy = apex * t
            x = cxr + math.sqrt(max(R * R - yy * yy, 0.0))
            pts.append((x, spring + yy))
        for i in range(n - 1, 0, -1):
            t = i / n
            yy = apex * t
            x = cxr + math.sqrt(max(R * R - yy * yy, 0.0))
            pts.append((-x, spring + yy))
    pts.append((-h, spring))
    return pts


def circle(r: float, cx: float, cy: float, n: int = 12):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def offset(poly, d: float):
    """Grow a convex-ish outline by d (vertex normals); good enough for arches and circles."""
    n = len(poly)
    area = sum(poly[i - 1][0] * poly[i][1] - poly[i][0] * poly[i - 1][1] for i in range(n))
    sgn = 1.0 if area > 0 else -1.0
    out = []
    for i in range(n):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % n]
        e0 = (p1[0] - p0[0], p1[1] - p0[1])
        e1 = (p2[0] - p1[0], p2[1] - p1[1])
        n0 = (e0[1], -e0[0])
        n1 = (e1[1], -e1[0])
        l0 = math.hypot(*n0) or 1.0
        l1 = math.hypot(*n1) or 1.0
        nx, ny = n0[0] / l0 + n1[0] / l1, n0[1] / l0 + n1[1] / l1
        ln = math.hypot(nx, ny) or 1.0
        nx, ny = nx / ln, ny / ln
        cosh = max(0.35, (n0[0] * n1[0] + n0[1] * n1[1]) / (l0 * l1) * 0.5 + 0.5) ** 0.5
        out.append((p1[0] + sgn * nx * d / cosh, p1[1] + sgn * ny * d / cosh))
    return out
