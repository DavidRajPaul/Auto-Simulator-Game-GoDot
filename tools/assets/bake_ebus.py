#!/usr/bin/env python3
"""Bakes the owner's Tripo electric bus into every Chennai bus livery (and a yellow college bus).

Source: assets_src/incoming/models/traffic/electric_bus_tripo.glb (owner-generated with a paid
Tripo plan): 60 MB, 1.9 M triangles, one 512 px texture atlas of tiny shuffled islands, white
and blue, 0.98 units long. Problems for the game: the size, a texture that cannot be
repainted, and stubby midi-bus proportions (wheelbase ~3 m at bus scale).

Pipeline:
  1. weld + quadric-simplify the shape (fast_simplification) to SIMPLIFY_TO triangles;
  2. read each triangle's original colour (7 samples -> nearest original triangles -> texture)
     and sort it into parts: tyre, rim, glass, interior, lamps, mirror, paintable body. The
     paintable body is split into the livery ZONES by height (skirt, stripe, body, belt line,
     window band, roof band, roof), measured on this model;
  3. lengthen it the way coachbuilders do: cut the bay between the axles and repeat it
     (EXTRA_BAYS), so a city bus is ~11 m with round wheels and normal windows;
  4. paint each livery and write one vertex-coloured mesh, one material (one draw call).

Liveries (research, Nov 2026; see docs/BUSES.md):
  MTC electric non-AC (Switch EiV12): cyan body, purple roof and skirt, orange stripe, black glass band
  MTC electric AC: red, black glass band, yellow stripe
  MTC Premium (gold, launched Mar 2026, P570S / P91): champagne gold and black
  MTC ordinary (diesel, standard floor): sky blue with a yellow stripe, separate windows
  MTC ordinary AC (diesel): deep blue, pale roof
  MTC pink bus (free travel for women, Magalir Vidiyal Payanam): pink
  MTC small bus (2026 batch): bright yellow and red, short body
  College bus: fully yellow (TN educational institution bus rule), black band
Output: assets/models/traffic/buses/<id>.glb  (+X = left side, front +Z, real size)
Usage: python3 tools/assets/bake_ebus.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import fast_simplification
import numpy as np
import trimesh
from PIL import Image
from scipy.spatial import cKDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bake_car_colours import _lin, _with_material  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "models" / "traffic" / "electric_bus_tripo.glb"
OUT = ROOT / "assets" / "models" / "traffic" / "buses"
SIMPLIFY_TO = 5000
SCALE = 6.4            # model units -> metres: body 0.408 wide -> 2.6 m
BAY = (-0.12, 0.08)    # model z of the bay between the axles that is repeated
# Zone heights (model y, roof at 0.459), read off the source's side colours.
Y_SKIRT, Y_STRIPE, Y_BELT, Y_GLASS, Y_ROOFBAND, Y_ROOF = 0.10, 0.12, 0.20, 0.218, 0.383, 0.415

LIVERIES = {
    # id: zone colours (sRGB hex), window style, extra bays, display name
    "mtc_electric": {"roof": "5a2ad0", "roofband": "5a2ad0", "body": "45d2e6", "belt": "45d2e6", "stripe": "f09a1e", "skirt": "5a2ad0", "pillar": "15181c", "bays": 3, "name": "MTC electric (non-AC)"},
    "mtc_electric_ac": {"roof": "e2343c", "roofband": "e2343c", "body": "e2343c", "belt": "c42a31", "stripe": "f2b620", "skirt": "c42a31", "pillar": "15181c", "bays": 3, "name": "MTC electric AC"},
    "mtc_premium": {"roof": "d9b96e", "roofband": "101215", "body": "c9a24f", "belt": "101215", "stripe": "f1d48a", "skirt": "b48b3a", "pillar": "101215", "bays": 3, "name": "MTC Premium (gold)"},
    "mtc_ordinary": {"roof": "a9d8f4", "roofband": "86c6ef", "body": "86c6ef", "belt": "86c6ef", "stripe": "f2c230", "skirt": "6fb4e4", "pillar": "86c6ef", "bays": 3, "name": "MTC ordinary"},
    "mtc_ordinary_ac": {"roof": "d6e4f5", "roofband": "2c62b8", "body": "2c62b8", "belt": "244f96", "stripe": "9fd3f4", "skirt": "244f96", "pillar": "1d2733", "bays": 3, "name": "MTC deluxe AC"},
    "mtc_pink": {"roof": "f5c6dc", "roofband": "e0478f", "body": "e75a9e", "belt": "e0478f", "stripe": "ffffff", "skirt": "c2367a", "pillar": "e75a9e", "bays": 3, "name": "MTC pink (free for women)"},
    "mtc_small": {"roof": "d7262b", "roofband": "d7262b", "body": "f6c419", "belt": "d7262b", "stripe": "d7262b", "skirt": "d7262b", "pillar": "15181c", "bays": 1, "name": "MTC small bus"},
    "college": {"roof": "f2b705", "roofband": "f2b705", "body": "f2b705", "belt": "1c1c1c", "stripe": "1c1c1c", "skirt": "f2b705", "pillar": "f2b705", "bays": 2, "name": "College bus"},
}
FIXED = {"tyre": "1c1c1e", "rim": "8a8d92", "glass": "15181c", "interior": "3a3634", "amber": "f09a1e",
         "headlamp": "eef2f4", "tail": "c81e1e", "mirror": "1c1c1e", "chassis": "2a2a2c"}


def _hex(h: str) -> np.ndarray:
    return _lin((int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))


def load_source() -> tuple[trimesh.Trimesh, np.ndarray, np.ndarray]:
    """Welded source mesh, original face centroids and their texture colours (0..255)."""
    s = trimesh.load(SRC, force="scene")
    node = s.graph.nodes_geometry[0]
    g = s.geometry[s.graph[node][1]].copy()
    g.apply_transform(s.graph[node][0])
    # The atlas is the base colour texture of the single material.
    tex = np.asarray(g.visual.material.baseColorTexture.convert("RGB"))
    h, w, _ = tex.shape
    uv = g.visual.uv[g.faces].mean(1)
    col = tex[np.clip(((1 - uv[:, 1]) % 1) * h, 0, h - 1).astype(int), np.clip((uv[:, 0] % 1) * w, 0, w - 1).astype(int)]
    cent = g.triangles_center
    m = trimesh.Trimesh(g.vertices, g.faces, process=False)
    m.merge_vertices(merge_tex=True, merge_norm=True, digits_vertex=5)
    m.remove_unreferenced_vertices()
    return m, cent, col


def simplify(m: trimesh.Trimesh) -> trimesh.Trimesh:
    v, f = fast_simplification.simplify(np.asarray(m.vertices, np.float32), np.asarray(m.faces),
                                        target_reduction=1.0 - SIMPLIFY_TO / len(m.faces))
    out = trimesh.Trimesh(v.astype(float), f, process=False)
    out.remove_degenerate_faces() if hasattr(out, "remove_degenerate_faces") else None
    return out


def cut_zones(m: trimesh.Trimesh) -> trimesh.Trimesh:
    """Split every triangle that crosses a zone height, so each livery band has a straight edge
    (classifying whole low-poly triangles by height gave zig-zag stripes)."""
    for y in (Y_SKIRT, Y_STRIPE, Y_BELT, Y_GLASS, Y_ROOFBAND, Y_ROOF):
        lo = m.slice_plane([0, y, 0], [0, -1, 0])
        hi = m.slice_plane([0, y, 0], [0, 1, 0])
        m = trimesh.util.concatenate([lo, hi])
    return m


WHEELS_Z = (-0.262, 0.215)  # axle positions (model z)
WHEEL_Y, WHEEL_R, RIM_R = 0.075, 0.082, 0.05


def raw_colours(m: trimesh.Trimesh, cent: np.ndarray, col: np.ndarray) -> np.ndarray:
    tree = cKDTree(cent)
    bary = np.array([[1 / 3, 1 / 3, 1 / 3], [.6, .2, .2], [.2, .6, .2], [.2, .2, .6], [.45, .45, .1], [.1, .45, .45], [.45, .1, .45]])
    pts = np.einsum("kj,fjd->fkd", bary, m.triangles).reshape(-1, 3)
    _, ii = tree.query(pts, k=3)
    return np.median(col[ii].reshape(len(m.faces), -1, 3), axis=1).astype(float)


def classify(m: trimesh.Trimesh, raw: np.ndarray) -> np.ndarray:
    """Part / livery zone per face."""
    c = m.triangles_center
    x, y, z = np.abs(c[:, 0]), c[:, 1], c[:, 2]
    n = m.face_normals
    lum = raw.mean(1)
    orange = (raw[:, 0] > 150) & (raw[:, 0] - raw[:, 2] > 60)
    zmin, zmax = m.bounds[0][2], m.bounds[1][2]
    out = np.full(len(c), "body", dtype=object)
    front = z > zmax - 0.035
    rear = z < zmin + 0.035
    shell = (x > 0.17) | front | rear | (y > Y_ROOFBAND)
    out[~shell & (y > 0.03)] = "interior"
    out[(y < Y_SKIRT) & shell] = "skirt"
    out[(y >= Y_SKIRT) & (y < Y_STRIPE) & shell] = "stripe"
    out[(y >= Y_BELT) & (y < Y_GLASS) & shell] = "belt"
    band = (y >= Y_GLASS) & (y < Y_ROOFBAND) & shell
    out[band] = np.where(lum[band] < 105, "glass", "pillar")
    out[(y >= Y_ROOFBAND) & (y < Y_ROOF)] = "roofband"
    out[y >= Y_ROOF] = "roof"
    # Windscreen and rear window: dark faces on the ends between the belt and the roof band.
    ends = (front | rear) & (y > Y_STRIPE + 0.04) & (y < Y_ROOFBAND) & (lum < 110)
    out[ends] = "glass"
    # Wheels: inside a circle round each axle, outboard, inside the body width.
    r = np.min([np.hypot(y - WHEEL_Y, z - zc) for zc in WHEELS_Z], axis=0)
    wheel = (r < WHEEL_R) & (x > 0.1) & (x < 0.205)
    out[wheel] = np.where((r[wheel] < RIM_R) & (lum[wheel] > 110), "rim", "tyre")
    out[(y < 0.03)] = "chassis"
    out[(x > 0.215)] = "mirror"
    out[orange & shell & (y < Y_GLASS)] = "amber"
    out[rear & (y < 0.2) & (y > 0.05) & (raw[:, 0] - raw[:, 1] > 50)] = "tail"
    return out


def headlamps(m: trimesh.Trimesh) -> list[trimesh.Trimesh]:
    """Two neat rectangular headlamp clusters on the front face (the Tripo texture's white
    blotches there are noise)."""
    out = []
    c = m.triangles_center
    zfront = float(np.percentile(c[(c[:, 1] > 0.08) & (c[:, 1] < 0.13) & (np.abs(c[:, 0]) < 0.12), 2], 97))
    for sx in (-1.0, 1.0):
        lamp = trimesh.creation.box(extents=(0.07, 0.03, 0.006),
                                    transform=trimesh.transformations.translation_matrix((sx * 0.145, 0.112, zfront + 0.002)))
        out.append(lamp)
    return out


def lengthen(m: trimesh.Trimesh, cls: np.ndarray, bays: int) -> tuple[trimesh.Trimesh, np.ndarray]:
    """Cut at BAY[0] and BAY[1] and repeat the middle bay `bays` extra times (front pushed forward)."""
    if bays <= 0:
        return m, cls
    a, b = BAY
    tree = cKDTree(m.triangles_center)

    def piece(lo: float | None, hi: float | None) -> tuple[trimesh.Trimesh, np.ndarray]:
        p = m
        if lo is not None:
            p = p.slice_plane([0, 0, lo], [0, 0, 1])
        if hi is not None:
            p = p.slice_plane([0, 0, hi], [0, 0, -1])
        _, idx = tree.query(p.triangles_center)
        return p, cls[idx]

    rear, rc = piece(None, a)
    mid, mc = piece(a, b)
    front, fc = piece(b, None)
    span = b - a
    parts, classes = [rear], [rc]
    for k in range(bays + 1):
        mm = mid.copy()
        mm.apply_translation([0, 0, span * k])
        parts.append(mm)
        classes.append(mc)
    ff = front.copy()
    ff.apply_translation([0, 0, span * bays])
    parts.append(ff)
    classes.append(fc)
    out = trimesh.util.concatenate(parts)
    out.apply_translation([0, 0, -span * bays * 0.5])  # keep it centred
    return out, np.concatenate(classes)


def paint(m: trimesh.Trimesh, cls: np.ndarray, livery: dict) -> trimesh.Trimesh:
    """Weld vertices that share a position and a colour; smooth normals within each colour."""
    fixed = dict(FIXED)
    if livery["pillar"] in ("15181c", "101215", "1d2733"):
        fixed["interior"] = "1e2124"  # tinted glass band: the cabin reads dark from outside
    cols = np.array([_hex(livery[c]) if c in livery else _hex(fixed[c]) for c in cls])
    tri = m.triangles.reshape(-1, 3) * SCALE
    vc = np.repeat(cols, 3, axis=0)
    key = np.c_[np.round(tri, 4), np.round(vc[:, :3], 3)]
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    faces = inverse.reshape(-1, 3)
    out = trimesh.Trimesh(tri[first], faces, process=False)
    out.visual = trimesh.visual.ColorVisuals(out, vertex_colors=(vc[first] * 255).round().astype(np.uint8))
    out.vertex_normals  # smooth per welded vertex
    # Stand on y = 0.
    out.apply_translation([0, -out.bounds[0][1], 0])
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    src, cent, col = load_source()
    m = cut_zones(simplify(src))
    cls = classify(m, raw_colours(m, cent, col))
    report = []
    for lid, liv in LIVERIES.items():
        lm, lc = lengthen(m, cls, int(liv["bays"]))
        lamps = headlamps(lm)
        lm = trimesh.util.concatenate([lm] + lamps)
        lc = np.concatenate([lc] + [np.full(len(l.faces), "headlamp", dtype=object) for l in lamps])
        mesh = paint(lm, lc, liv)
        glb = trimesh.exchange.gltf.export_glb(trimesh.Scene(mesh), include_normals=True)
        path = OUT / f"{lid}.glb"
        path.write_bytes(_with_material(glb))
        lo, hi = mesh.bounds
        report.append({"id": lid, "name": liv["name"], "triangles": int(len(mesh.faces)),
                       "size_m": np.round(hi - lo, 2).tolist(), "kb": round(path.stat().st_size / 1024)})
    print(json.dumps(report, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
