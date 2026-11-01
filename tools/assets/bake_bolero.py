#!/usr/bin/env python3
"""Bakes the owner's Mahindra Bolero (Sketchfab, CC BY 4.0) into light traffic cars + the police jeep.

Source: assets_src/incoming/models/traffic/bolero/scene.gltf ("Bolero" by Waseem Kadri,
https://sketchfab.com/3d-models/bolero-9f1e594c45e24012b50992bbfeeecda0, CC BY 4.0).
It is 25 MB: 34.9k triangles in 20 parts, three 4096 px textures (colour, normal, metal/rough)
with baked dirt. The game needs a few thousand triangles and no textures:

  1. merge the 20 parts into one scene, keep each part as its own primitive, and simplify
     seam-safe (UV islands keep their borders) to TRI_BUDGET;
  2. colour every simplified triangle from the texture (several samples per triangle,
     majority vote) into a small palette: body paint, black trim/glass, grey trim, chrome rims,
     red tail lamps, amber indicators, clear headlamps. Dirt counts as body paint (clean cars);
  3. write one vertex-coloured mesh, one material, per paint (one draw call, ~100 KB).

The police jeep is always the same: Tamil Nadu police white, a blue waist band with a red line,
and a roof light bar baked as a SECOND primitive with the material
"Beacon": the game puts a flashing red/blue shader on it (TrafficVehicleAI._light_beacon).

Facing +Z (grille), real size (4.34 m with the spare wheel, 1.83 m tall).
Output: assets/models/traffic/cars/bolero_<paint>.glb, bolero_police.glb
Usage: python3 tools/assets/bake_bolero.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bake_car_colours import _lin, _with_material  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "models" / "traffic" / "bolero"
OUT = ROOT / "assets" / "models" / "traffic" / "cars"
TMP = ROOT / "assets_src" / "incoming" / "models" / "_bolero_tmp"
TRI_BUDGET = 3000

PAINTS = {  # sRGB: the colours Boleros actually come in on Chennai roads
    "white": (232, 232, 226),
    "silver": (170, 174, 178),
    "black": (32, 33, 36),
    "maroon": (104, 28, 32),
    "green": (46, 74, 52),
}
FIXED = {
    "black": (22, 23, 25),
    "trim": (70, 72, 76),
    "chrome": (132, 135, 140),
    "tyre": (28, 28, 30),
    "red": (196, 26, 24),
    "amber": (230, 130, 24),
    "lamp": (226, 230, 232),
}
POLICE = {"body": (240, 240, 236), "band": (24, 52, 128), "line": (190, 28, 30)}
# Parts whose colour is fixed whatever the texture says.
PART_CLASS = {"Tyre": "tyre", "Rim": "chrome", "wiper": "black", "Dark": "black", "Grill": "black",
              "Logo": "chrome", "Flaps": "black"}


def _sample(img: np.ndarray, uv: np.ndarray) -> np.ndarray:
    h, w, _ = img.shape
    x = np.clip((uv[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    y = np.clip((1.0 - (uv[:, 1] % 1.0)) * (h - 1), 0, h - 1).astype(int)
    return img[y, x] / 255.0


def _classify(rgb: np.ndarray) -> np.ndarray:
    """Per-sample class name from the texture colour."""
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    mx, mn = rgb.max(1), rgb.min(1)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    out = np.full(len(rgb), "trim", dtype=object)
    out[mx < 0.3] = "black"
    out[(mx >= 0.45) & (sat < 0.38)] = "paint"  # white body + its brown dirt
    out[(r > 0.5) & (r - g > 0.3) & (r - b > 0.3)] = "red"
    out[(r > 0.6) & (g > 0.3) & (g < 0.7) & (b < 0.3) & (r - g > 0.2)] = "amber"
    return out


def build_parts() -> list[tuple[str, trimesh.Trimesh, np.ndarray]]:
    """Simplified parts: (part name, mesh, per-face class)."""
    TMP.mkdir(parents=True, exist_ok=True)
    src = trimesh.load(SRC / "scene.gltf", force="scene")
    tex = Image.open(SRC / "textures" / "Bolero_baseColor.png").convert("RGB").resize((1024, 1024))
    mat = trimesh.visual.material.PBRMaterial(baseColorTexture=tex)
    scene = trimesh.Scene()
    for node in src.graph.nodes_geometry:
        xf, gname = src.graph[node]
        m = src.geometry[gname].copy()
        m.apply_transform(xf)
        part = trimesh.Trimesh(m.vertices, m.faces, process=False,
                               visual=trimesh.visual.TextureVisuals(uv=m.visual.uv, material=mat))
        scene.add_geometry(part, geom_name=gname.split("_")[0], node_name=gname.split("_")[0])
    merged = TMP / "merged.glb"
    simple = TMP / "simple.glb"
    scene.export(merged)
    subprocess.run(["node", str(ROOT / "tools" / "assets" / "seam_safe_simplify.mjs"), str(merged), str(simple), str(TRI_BUDGET)], check=True)
    img = np.asarray(Image.open(SRC / "textures" / "Bolero_baseColor.png").convert("RGB").resize((2048, 2048)))
    out = []
    s = trimesh.load(simple, force="scene")
    bary = np.array([[1 / 3, 1 / 3, 1 / 3], [0.6, 0.2, 0.2], [0.2, 0.6, 0.2], [0.2, 0.2, 0.6], [0.45, 0.45, 0.1], [0.1, 0.45, 0.45], [0.45, 0.1, 0.45]])
    for node in s.graph.nodes_geometry:
        xf, gname = s.graph[node]
        m = s.geometry[gname].copy()
        m.apply_transform(xf)
        name = str(node)
        fixed = next((c for k, c in PART_CLASS.items() if name.startswith(k)), None)
        if fixed is not None:
            cls = np.full(len(m.faces), fixed, dtype=object)
        else:
            uvf = m.visual.uv[m.faces]  # (F, 3, 2)
            votes = [_classify(_sample(img, np.einsum("k,fkd->fd", w, uvf))) for w in bary]
            votes = np.stack(votes, 1)
            cls = np.array([max(set(v), key=list(v).count) for v in votes], dtype=object)
        out.append((name, trimesh.Trimesh(m.vertices, m.faces, process=False), cls))
    return out


def _mesh(parts: list, colour_of) -> trimesh.Trimesh:
    """One flat-per-face-coloured mesh with smooth normals from each welded part."""
    verts, faces, cols, norms = [], [], [], []
    base = 0
    for name, m, cls in parts:
        vn = m.vertex_normals
        tri = m.vertices[m.faces].reshape(-1, 3)
        verts.append(tri)
        norms.append(vn[m.faces].reshape(-1, 3))
        fc = np.array([colour_of(name, i, c, m) for i, c in enumerate(cls)])
        cols.append(np.repeat(fc, 3, axis=0))
        faces.append(np.arange(len(tri)).reshape(-1, 3) + base)
        base += len(tri)
    out = trimesh.Trimesh(np.concatenate(verts), np.concatenate(faces), vertex_normals=np.concatenate(norms), process=False)
    out.visual = trimesh.visual.ColorVisuals(out, vertex_colors=(np.concatenate(cols) * 255).round().astype(np.uint8))
    return out


def _export(meshes: dict[str, trimesh.Trimesh], out: Path) -> dict:
    """Write the named meshes as primitives; material 0 = CarPaint, 1 = Beacon (if present)."""
    scene = trimesh.Scene()
    for name, m in meshes.items():
        scene.add_geometry(m, geom_name=name, node_name=name)
    glb = trimesh.exchange.gltf.export_glb(scene, include_normals=True)
    glb = _with_material(glb)
    if "Beacon" in meshes:
        glb = _beacon_material(glb)
    out.write_bytes(glb)
    tris = sum(len(m.faces) for m in meshes.values())
    lo = np.min([m.bounds[0] for m in meshes.values()], 0)
    hi = np.max([m.bounds[1] for m in meshes.values()], 0)
    return {"file": out.relative_to(ROOT).as_posix(), "triangles": int(tris), "size_m": np.round(hi - lo, 2).tolist(),
            "kb": round(out.stat().st_size / 1024)}


def _beacon_material(glb: bytes) -> bytes:
    import struct
    jlen = struct.unpack_from("<I", glb, 12)[0]
    j = json.loads(glb[20:20 + jlen])
    bin_chunk = glb[20 + jlen:]
    j["materials"].append({"name": "Beacon", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.3}})
    for node in j["nodes"]:
        if node.get("name") == "Beacon" and "mesh" in node:
            for prim in j["meshes"][node["mesh"]]["primitives"]:
                prim["material"] = len(j["materials"]) - 1
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + bin_chunk
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    parts = build_parts()
    report = []
    for paint, rgb in PAINTS.items():
        def colour(_name: str, _i: int, c: str, _m: trimesh.Trimesh, rgb: tuple = rgb) -> np.ndarray:
            return _lin(rgb) if c == "paint" else _lin(FIXED[c])
        report.append(_export({"Body": _mesh(parts, colour)}, OUT / f"bolero_{paint}.glb"))

    # Police: same body, white paint with a blue band and red line on the flanks.
    body_faces = [(n, m) for n, m, _ in parts if n.startswith("CarBody")]
    lo, hi = body_faces[0][1].bounds
    h = hi[1] - lo[1]

    def police(name: str, i: int, c: str, m: trimesh.Trimesh) -> np.ndarray:
        return _lin(POLICE["body"]) if c == "paint" else _lin(FIXED[c])
    body = _mesh(parts, police)
    # Waist band (blue) with a red line above, as thin strips laid just outside each flank:
    # colouring the body's own triangles by height came out as a ragged zig-zag.
    strips = []
    v = body_faces[0][1].vertices
    for y0, y1, col in ((0.30, 0.40, POLICE["band"]), (0.40, 0.43, POLICE["line"])):
        ya, yb = lo[1] + h * y0, lo[1] + h * y1
        near = v[(v[:, 1] > ya - 0.05) & (v[:, 1] < yb + 0.05) & (np.abs(v[:, 2]) < 1.2)]
        half = float(np.percentile(np.abs(near[:, 0]), 90)) + 0.012
        for sx in (-1.0, 1.0):
            strip = trimesh.creation.box(extents=(0.01, yb - ya, 3.1),
                                         transform=trimesh.transformations.translation_matrix((sx * half, (ya + yb) * 0.5, 0.15)))
            strip.visual = trimesh.visual.ColorVisuals(strip, vertex_colors=np.tile((_lin(col) * 255).astype(np.uint8), (len(strip.vertices), 1)))
            strips.append(strip)
    body = trimesh.util.concatenate([body] + strips)
    # Roof light bar: a dark base and two lamp blocks (left red, right blue, recoloured and
    # flashed by the game's beacon shader from the sign of x).
    roof = float(body.bounds[1][1])
    zc = 0.25
    base = trimesh.creation.box(extents=(1.3, 0.06, 0.32), transform=trimesh.transformations.translation_matrix((0, roof + 0.03, zc)))
    base.visual = trimesh.visual.ColorVisuals(base, vertex_colors=np.tile((_lin((26, 26, 30)) * 255).astype(np.uint8), (len(base.vertices), 1)))
    lamps = []
    for x, col in ((-0.34, (220, 30, 30)), (0.34, (30, 70, 230))):
        lamp = trimesh.creation.box(extents=(0.58, 0.12, 0.26), transform=trimesh.transformations.translation_matrix((x, roof + 0.12, zc)))
        lamp.visual = trimesh.visual.ColorVisuals(lamp, vertex_colors=np.tile((_lin(col) * 255).astype(np.uint8), (len(lamp.vertices), 1)))
        lamps.append(lamp)
    body = trimesh.util.concatenate([body, base])
    beacon = trimesh.util.concatenate(lamps)
    report.append(_export({"Body": body, "Beacon": beacon}, OUT / "bolero_police.glb"))
    print(json.dumps(report, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
