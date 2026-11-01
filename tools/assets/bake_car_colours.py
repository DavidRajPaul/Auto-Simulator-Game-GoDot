#!/usr/bin/env python3
"""Bakes the Quaternius cars (CC0) into ONE-mesh, vertex-coloured paint variants + a police SUV.

Nov 1 device test: the Kenney hatchback (green, flared grey arches) looked odd next to the
Quaternius cars, and the Tripo police SUV rendered as a shredded white-and-black mess. Both go.
Every car is now one of the three Quaternius bodies (sedan, SUV, sports) in a Chennai street
colour, and the police vehicle is the SUV in Tamil Nadu police white with a blue-and-red waist
stripe and a red/blue light bar.

Each source car is ~13 meshes with 7 flat-coloured materials (= ~13 draw calls). The bake turns
material colours into vertex colours and merges everything into one primitive with one
material: one draw call per car, a recolour is just a different file, no textures.

Output: assets/models/traffic/cars/<body>_<paint>.glb and police_suv.glb (facing +Z, source size).
Usage: python3 tools/assets/bake_car_colours.py
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "models" / "traffic"
OUT = SRC / "cars"

# Body file -> its paintable material (everything else keeps its own flat colour).
BODIES = {
    "sedan": ("quaternius_normal_car.glb", "LightBlue"),
    "suv": ("quaternius_suv.glb", "White.002"),
    "sports": ("quaternius_sports_car.glb", "White.001"),
}
# Chennai street mix: mostly white and silver, then grey, dark blue, maroon, red, black.
PAINTS = {  # sRGB
    "white": (236, 236, 232),
    "silver": (178, 182, 186),
    "grey": (98, 102, 108),
    "blue": (34, 58, 112),
    "maroon": (112, 26, 34),
    "red": (178, 30, 28),
    "black": (30, 31, 34),
}
VARIANTS = [
    ("sedan", "white"), ("sedan", "silver"), ("sedan", "maroon"), ("sedan", "blue"),
    ("suv", "white"), ("suv", "silver"), ("suv", "black"),
    ("sports", "red"), ("sports", "grey"), ("sports", "white"),
]
POLICE_WHITE = (240, 240, 236)
POLICE_BLUE = (24, 52, 128)
POLICE_RED = (190, 28, 30)


def _lin(srgb: tuple[int, int, int]) -> np.ndarray:
    c = np.array(srgb, dtype=float) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return np.append(lin, 1.0)


def _parts(path: Path) -> list[tuple[trimesh.Trimesh, str, np.ndarray]]:
    """(mesh in scene space, material name, linear RGBA) for every primitive."""
    scene = trimesh.load(path, force="scene")
    out = []
    for node in scene.graph.nodes_geometry:
        xf, gname = scene.graph[node]
        g = scene.geometry[gname].copy()
        g.apply_transform(xf)
        m = g.visual.material
        f = np.array(getattr(m, "baseColorFactor", None) if getattr(m, "baseColorFactor", None) is not None else [200, 200, 200, 255], dtype=float)
        f = f / 255.0 if f.max() > 1.0 else f
        out.append((g, str(m.name), f))
    return out


def _coloured(mesh: trimesh.Trimesh, rgba: np.ndarray) -> trimesh.Trimesh:
    m = trimesh.Trimesh(vertices=mesh.vertices.copy(), faces=mesh.faces.copy(),
                        vertex_normals=mesh.vertex_normals.copy(), process=False)
    m.visual = trimesh.visual.ColorVisuals(m, vertex_colors=np.tile((rgba * 255).round().astype(np.uint8), (len(m.vertices), 1)))
    return m


def _write(meshes: list[trimesh.Trimesh], out: Path) -> dict:
    normals = np.concatenate([m.vertex_normals for m in meshes])
    merged = trimesh.util.concatenate(meshes)
    merged = trimesh.Trimesh(vertices=merged.vertices, faces=merged.faces, vertex_normals=normals, process=False)
    merged.visual = trimesh.visual.ColorVisuals(merged, vertex_colors=np.concatenate([m.visual.vertex_colors for m in meshes]))
    out.parent.mkdir(parents=True, exist_ok=True)
    glb = trimesh.exchange.gltf.export_glb(trimesh.Scene(merged), include_normals=True)
    # One plain PBR material (trimesh writes none for vertex colours): semi-gloss paint.
    out.write_bytes(_with_material(glb))
    lo, hi = merged.bounds
    return {"file": out.relative_to(ROOT).as_posix(), "triangles": int(len(merged.faces)),
            "size_m": np.round(hi - lo, 2).tolist()}


def _with_material(glb: bytes) -> bytes:
    import struct
    jlen = struct.unpack_from("<I", glb, 12)[0]
    j = json.loads(glb[20:20 + jlen])
    bin_chunk = glb[20 + jlen:]
    j["materials"] = [{"name": "CarPaint", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.45}}]
    for mesh in j["meshes"]:
        for prim in mesh["primitives"]:
            prim["material"] = 0
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + bin_chunk
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def bake_paint(body: str, paint: str) -> dict:
    src, paint_mat = BODIES[body]
    meshes = [_coloured(g, _lin(PAINTS[paint]) if name == paint_mat else rgba) for g, name, rgba in _parts(SRC / src)]
    return _write(meshes, OUT / f"{body}_{paint}.glb")


def bake_police() -> dict:
    src, paint_mat = BODIES["suv"]
    meshes = []
    body_parts = []
    for g, name, rgba in _parts(SRC / src):
        if name == paint_mat:
            body_parts.append(g)
        else:
            meshes.append(_coloured(g, rgba))
    body = trimesh.util.concatenate(body_parts)
    lo, hi = body.bounds
    meshes.append(_coloured(body, _lin(POLICE_WHITE)))
    # Waist stripe: a straight blue band with a thin red line on top, as thin strips laid just
    # outside each flank (colouring the body's own triangles came out as a ragged zig-zag).
    h = hi[1] - lo[1]
    v = body.vertices
    for y0, y1, col in ((0.38, 0.48, POLICE_BLUE), (0.48, 0.515, POLICE_RED)):
        ya, yb = lo[1] + h * y0, lo[1] + h * y1
        near = v[(v[:, 1] > ya - 0.05) & (v[:, 1] < yb + 0.05) & (np.abs(v[:, 2]) < 1.3)]
        half = float(np.percentile(np.abs(near[:, 0]), 85)) + 0.012
        length = (hi[2] - lo[2]) * 0.62
        for sx in (-1.0, 1.0):
            strip = trimesh.creation.box(extents=(0.01, yb - ya, length),
                                         transform=trimesh.transformations.translation_matrix((sx * half, (ya + yb) * 0.5, (lo[2] + hi[2]) * 0.5 - 0.1)))
            meshes.append(_coloured(strip, _lin(col)))
    # Light bar on the roof, a little behind the windscreen: red (left), blue (right), dark base.
    roof_y = hi[1]
    zc = lo[2] + (hi[2] - lo[2]) * 0.52
    base = trimesh.creation.box(extents=(1.25, 0.05, 0.3), transform=trimesh.transformations.translation_matrix((0, roof_y + 0.025, zc)))
    meshes.append(_coloured(base, _lin((30, 30, 34))))
    for x, col in ((-0.33, POLICE_RED), (0.33, POLICE_BLUE)):
        lamp = trimesh.creation.box(extents=(0.56, 0.1, 0.24), transform=trimesh.transformations.translation_matrix((x, roof_y + 0.1, zc)))
        meshes.append(_coloured(lamp, _lin(col)))
    return _write(meshes, OUT / "police_suv.glb")


def main() -> int:
    report = [bake_paint(b, p) for b, p in VARIANTS]
    report.append(bake_police())
    print(json.dumps(report, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
