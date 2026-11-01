#!/usr/bin/env python3
"""Bakes the owner's roadside shops and the EB distribution transformer for mobile.

Sources (owner-generated with a paid Tripo plan; ~60 MB, ~1.9 M triangles, one baked texture each,
kept out of git under assets_src/incoming/models/city_new/):
  street_food_stall_3d_model.glb   tea kadai: tin-roof booth, benches, pots, EB pole, small tree
  street_fruit_stall_3d_model.glb  fruit push-cart with a striped canopy
  power_transformer_3d_model.glb   distribution transformer on a ground plinth with a railing
and the existing biryani stall (assets_src/models/biryani_shop_src.glb: 3.4k triangles,
vertex colours + a signboard decal + the owner's lungi decal).

Tripo textures carry baked shading noise and tiny shuffled UV islands, so (AGENTS.md lessons) we
never simplify the textured mesh. Instead:
  1. crop what the game does not want (diorama ground slab and litter; the transformer's plinth
     and railing and the loose cable loop: the game mounts it on a TNEB double-pole structure),
  2. weld + quadric-simplify the shape (fast_simplification) to a triangle budget,
  3. read each new triangle's colour from the nearest original triangles' texels, lift the baked
     shadow, and split it into parts (roof, walls, canopy, cart body, sign, ...),
  4. paint every livery: parts get the livery colour modulated by their own light/dark detail,
     everything else keeps its (cleaned) colour,
  5. replace the garbled AI signboard text with a clean painted Tamil sign (Baloo Thambi 2,
     bundled) on a small textured quad: generic shop words only, no real business names.
Each shop is one vertex-coloured surface + one 512 px sign surface (2 draw calls; the biryani
stall keeps its lungi decal, 3). Shop fronts face -Z (the road side under place_city_props.py's
yaw convention), origin at the footprint centre, standing on y = 0, real size in metres.

Outputs:
  assets/models/city/shops/tea_stall_<v>.glb, fruit_cart_<v>.glb, biryani_stall_<v>.glb
  assets/models/city/eb_transformer.glb   (tank only, +X along the road, base at y = 0; the
                                           poles, platform and wires are built in the chunk mesh)
Usage: python3 tools/assets/bake_street_shops.py
"""
from __future__ import annotations

import colorsys
import json
import struct
import sys
from pathlib import Path

import fast_simplification
import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "models" / "city_new"
BIRYANI_SRC = ROOT / "assets_src" / "models" / "biryani_shop_src.glb"
OUT = ROOT / "assets" / "models" / "city"
SHOPS = OUT / "shops"
FONT = ROOT / "assets" / "fonts" / "baloo_thambi_2" / "BalooThambi2-Variable.ttf"

# Liveries: paint colours (sRGB hex). Chennai tea kadais and carts are hand-painted in loud
# two-tone enamel, roofs are rusty tin or the ubiquitous blue tarpaulin.
TEA_LIVERIES = {
    "a": {"wall_lo": "1f7a8c", "wall_hi": "e8c547", "roof": "2b5fb3", "awning": "d9472b",
          "sign": ("டீ கடை", "TEA STALL", "fbe15a", "c0231c")},
    "b": {"wall_lo": "2f8f3a", "wall_hi": "f2efe6", "roof": "9a5a34", "awning": "f2a51f",
          "sign": ("டீ • காபி", "TEA • COFFEE", "1d6f3a", "ffffff")},
    "c": {"wall_lo": "b8322a", "wall_hi": "f4d06f", "roof": "6f7a80", "awning": "2e7d32",
          "sign": ("தேநீர் கடை", "TEA • SNACKS", "c62828", "ffe082")},
    "d": {"wall_lo": "5b3c9a", "wall_hi": "8fd3e8", "roof": "e07a1f", "awning": "1565c0",
          "sign": ("டீ ஸ்டால்", "BUN • BAJJI", "0d47a1", "ffffff")},
}
FRUIT_LIVERIES = {
    "a": {"body": "2d6cb5", "stripe": "e64a19", "board": "f6c143",
          "sign": ("பழக்கடை", "FRESH FRUITS", "f6c143", "8e1b10")},
    "b": {"body": "2e8b57", "stripe": "f9a825", "board": "2e8b57",
          "sign": ("பழங்கள்", "FRUITS", "2e8b57", "ffffff")},
    "c": {"body": "c0392b", "stripe": "1e88e5", "board": "fafafa",
          "sign": ("ஜூஸ் • பழம்", "JUICE • FRUITS", "fafafa", "c0392b")},
    "d": {"body": "f2b705", "stripe": "6a1b9a", "board": "6a1b9a",
          "sign": ("சீசன் பழம்", "SEASON FRUITS", "6a1b9a", "fff176")},
}
BIRYANI_LIVERIES = {
    "a": {"wood": "1e5aa8", "roof": "2b5fb3", "board": "1e5aa8",
          "sign": ("பிரியாணி", "DUM BIRYANI", "ffd54f", "b71c1c")},
    "b": {"wood": "2e7d32", "roof": "ef6c00", "board": "2e7d32",
          "sign": ("பிரியாணி", "CHICKEN BIRYANI", "ffffff", "1b5e20")},
    "c": {"wood": "8e1b2b", "roof": "b9bec4", "board": "8e1b2b",
          "sign": ("பிரியாணி", "MUTTON BIRYANI", "fff3e0", "8e1b2b")},
    "d": {"wood": "c77d0a", "roof": "1b8a6b", "board": "c77d0a",
          "sign": ("பிரியாணி • குஸ்கா", "BIRYANI • KUSKA", "263238", "ffca28")},
}
# TNEB distribution transformers: light grey tank, brown porcelain bushings, black cable.
TRANSFORMER = {"tank": "a9aeab", "bushing": "6b3f26", "cable": "1b1b1c", "steel": "5d6164"}


# --- colour helpers -----------------------------------------------------------------------------

def _rgb(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


def _lin(srgb: np.ndarray) -> np.ndarray:
    c = np.clip(srgb / 255.0, 0, 1)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _hsv(rgb: np.ndarray) -> np.ndarray:
    return np.array([colorsys.rgb_to_hsv(*(c / 255.0)) for c in rgb])


def _lift(raw: np.ndarray) -> np.ndarray:
    """Undo most of Tripo's baked ambient occlusion: raise value, keep hue."""
    hsv = _hsv(raw)
    hsv[:, 2] = np.clip(hsv[:, 2], 0, 1) ** 0.7
    hsv[:, 1] = np.clip(hsv[:, 1] * 1.1, 0, 1)
    return np.array([colorsys.hsv_to_rgb(*c) for c in hsv]) * 255.0


def _flatten(cols: np.ndarray, k: int) -> np.ndarray:
    """Snap colours to a k-colour palette (removes texel noise; flat low-poly look)."""
    from scipy.cluster.vq import kmeans2
    cen, lab = kmeans2(cols, k, seed=7, minit="++")
    return cen[lab]


def _detail(raw: np.ndarray, sel: np.ndarray) -> np.ndarray:
    """Per-face light/dark factor inside a part (keeps planks, folds and ribs readable)."""
    lum = raw.mean(1)
    ref = np.median(lum[sel]) if sel.any() else 1.0
    return np.clip(0.82 + 0.35 * (lum / max(ref, 1.0) - 1.0), 0.62, 1.1)


def _paint(cols: np.ndarray, raw: np.ndarray, sel: np.ndarray, hexcol: str) -> None:
    cols[sel] = np.clip(_rgb(hexcol)[None, :] * _detail(raw, sel)[sel, None], 0, 255)


# --- source mesh --------------------------------------------------------------------------------

def load_tripo(path: Path, keep, budget: int) -> tuple[trimesh.Trimesh, np.ndarray]:
    """Cropped, welded, simplified mesh and each face's sampled sRGB colour (0..255)."""
    s = trimesh.load(path, force="scene")
    node = s.graph.nodes_geometry[0]
    g = s.geometry[s.graph[node][1]].copy()
    g.apply_transform(s.graph[node][0])
    tex = np.asarray(g.visual.material.baseColorTexture.convert("RGB"))
    h, w, _ = tex.shape
    uv = g.visual.uv[g.faces].mean(1)
    col = tex[np.clip(((1 - uv[:, 1]) % 1) * h, 0, h - 1).astype(int),
              np.clip((uv[:, 0] % 1) * w, 0, w - 1).astype(int)].astype(float)
    cent = g.triangles_center
    k = keep(cent)
    m = trimesh.Trimesh(g.vertices, g.faces[k], process=False)
    m.merge_vertices(digits_vertex=5)
    m.remove_unreferenced_vertices()
    v, f = fast_simplification.simplify(np.asarray(m.vertices, np.float32), np.asarray(m.faces),
                                        target_reduction=1.0 - budget / len(m.faces))
    m = trimesh.Trimesh(v.astype(float), f, process=False)
    m.update_faces(m.nondegenerate_faces())
    tree = cKDTree(cent[k])
    bary = np.array([[1 / 3, 1 / 3, 1 / 3], [.6, .2, .2], [.2, .6, .2], [.2, .2, .6],
                     [.45, .45, .1], [.1, .45, .45], [.45, .1, .45]])
    pts = np.einsum("kj,fjd->fkd", bary, m.triangles).reshape(-1, 3)
    _, ii = tree.query(pts, k=3)
    raw = np.median(col[k][ii].reshape(len(m.faces), -1, 3), axis=1)
    return m, raw


def drop_crumbs(m: trimesh.Trimesh, raw: np.ndarray, max_faces: int, below_y: float):
    """Remove small loose pieces near the ground (litter left over from the diorama slab)."""
    labels = trimesh.graph.connected_component_labels(m.face_adjacency, node_count=len(m.faces))
    keep = np.ones(len(m.faces), bool)
    c = m.triangles_center
    for lab in np.unique(labels):
        s = labels == lab
        if s.sum() <= max_faces and c[s, 1].max() < below_y:
            keep[s] = False
    m = trimesh.Trimesh(m.vertices, m.faces[keep], process=False)
    m.remove_unreferenced_vertices()
    return m, raw[keep]


def place(m: trimesh.Trimesh, yaw_deg: float, scale: float) -> np.ndarray:
    """Rotate about Y, scale to metres, centre the footprint on the origin, stand on y = 0.
    Returns the 4x4 transform applied (signs are placed with the same one)."""
    rot = trimesh.transformations.rotation_matrix(np.radians(yaw_deg), [0, 1, 0])
    sc = np.diag([scale, scale, scale, 1.0])
    xf = sc @ rot
    v = trimesh.transform_points(m.vertices, xf)
    lo, hi = v.min(0), v.max(0)
    t = np.eye(4)
    t[:3, 3] = [-(lo[0] + hi[0]) * 0.5, -lo[1], -(lo[2] + hi[2]) * 0.5]
    xf = t @ xf
    m.apply_transform(xf)
    return xf


# --- signs ---------------------------------------------------------------------------------------

def sign_image(tamil: str, english: str, board: str, ink: str, size: tuple[int, int]) -> Image.Image:
    """Hand-painted shop board: border, big Tamil word, small English line."""
    w, h = size
    img = Image.new("RGB", (w, h), tuple(int(c) for c in _rgb(board)))
    d = ImageDraw.Draw(img)
    inkc = tuple(int(c) for c in _rgb(ink))
    bw = max(4, h // 18)
    d.rectangle([bw // 2, bw // 2, w - 1 - bw // 2, h - 1 - bw // 2], outline=inkc, width=bw)

    def fit(text: str, max_w: float, max_h: float, weight: int) -> ImageFont.FreeTypeFont:
        sz = int(max_h)
        while sz > 8:
            f = ImageFont.truetype(str(FONT), sz, layout_engine=ImageFont.Layout.RAQM)
            try:
                f.set_variation_by_axes([weight])
            except Exception:
                pass
            l, t, r, b = d.textbbox((0, 0), text, font=f)
            if r - l <= max_w and b - t <= max_h:
                return f
            sz -= 2
        return ImageFont.truetype(str(FONT), 8)

    pad = bw * 3
    big = fit(tamil, w - 2 * pad, h * 0.52, 800)
    small = fit(english, w - 2 * pad, h * 0.2, 700)
    l, t, r, b = d.textbbox((0, 0), tamil, font=big)
    d.text(((w - (r - l)) / 2 - l, h * 0.1 - t + (h * 0.52 - (b - t)) / 2), tamil, font=big, fill=inkc)
    l, t, r, b = d.textbbox((0, 0), english, font=small)
    d.text(((w - (r - l)) / 2 - l, h * 0.68 - t), english, font=small, fill=inkc)
    return img


def sign_quad(corners: np.ndarray, image: Image.Image) -> trimesh.Trimesh:
    """Quad from 4 corners (bottom-left, bottom-right, top-right, top-left as seen from the
    front) with the sign texture."""
    q = trimesh.Trimesh(corners, [[0, 1, 2], [0, 2, 3]], process=False)
    mat = trimesh.visual.material.PBRMaterial(name="ShopSign", baseColorTexture=image,
                                              metallicFactor=0.0, roughnessFactor=0.85)
    q.visual = trimesh.visual.TextureVisuals(uv=np.array([[0, 0], [1, 0], [1, 1], [0, 1]], float),
                                             material=mat)
    return q


# --- export --------------------------------------------------------------------------------------

def coloured(m: trimesh.Trimesh, srgb: np.ndarray) -> trimesh.Trimesh:
    """Per-face colours -> welded vertex colours (shared positions with the same colour merge,
    so normals smooth within a colour and stay hard across colour edges)."""
    tri = m.triangles.reshape(-1, 3)
    vc = np.repeat(np.round(_lin(srgb), 4), 3, axis=0)
    key = np.c_[np.round(tri, 4), vc]
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    o = trimesh.Trimesh(tri[first], inv.reshape(-1, 3), process=False)
    o.visual = trimesh.visual.ColorVisuals(
        o, vertex_colors=np.c_[np.round(vc[first] * 255), np.full(len(first), 255)].astype(np.uint8))
    o.vertex_normals  # noqa: B018 - computed and cached for export
    return o


def export(parts: dict[str, trimesh.Trimesh], out: Path) -> dict:
    """Write a GLB; vertex-coloured primitives share one matte "ShopPaint" material."""
    scene = trimesh.Scene()
    for name, g in parts.items():
        scene.add_geometry(g, geom_name=name, node_name=name)
    glb = trimesh.exchange.gltf.export_glb(scene, include_normals=True)
    jlen = struct.unpack_from("<I", glb, 12)[0]
    j = json.loads(glb[20:20 + jlen])
    bin_chunk = glb[20 + jlen:]
    mats = j.setdefault("materials", [])
    paint = len(mats)
    mats.append({"name": "ShopPaint", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                                               "metallicFactor": 0.0, "roughnessFactor": 0.85}})
    for mat in mats[:paint]:
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.85
    for mesh in j["meshes"]:
        for prim in mesh["primitives"]:
            if "COLOR_0" in prim["attributes"]:
                prim["material"] = paint
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + bin_chunk
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)
    tris = sum(len(g.faces) for g in parts.values())
    lo = np.min([g.bounds[0] for g in parts.values()], axis=0)
    hi = np.max([g.bounds[1] for g in parts.values()], axis=0)
    return {"file": out.relative_to(ROOT).as_posix(), "triangles": int(tris), "surfaces": len(parts),
            "size_m": np.round(hi - lo, 2).tolist(), "kb": round(out.stat().st_size / 1024)}


# --- models --------------------------------------------------------------------------------------

def bake_tea() -> list[dict]:
    # Source: front (counter, sign) faces -X; ground slab top at y = 0.055; 0.85 units tall.
    m, raw = load_tripo(SRC / "street_food_stall_3d_model.glb", lambda c: c[:, 1] > 0.058, 9000)
    m, raw = drop_crumbs(m, raw, 40, 0.1)
    raw = _lift(raw)
    base = _flatten(raw, 22)
    c, n = m.triangles_center, m.face_normals
    hsv = _hsv(raw)
    booth = (c[:, 0] > -0.135) & (c[:, 0] < 0.36) & (np.abs(c[:, 2]) < 0.31)
    vertical = np.abs(n[:, 1]) < 0.35
    sign = (c[:, 1] > 0.6) & (c[:, 0] < -0.09) & (c[:, 0] > -0.135) & (np.abs(c[:, 2]) < 0.24) & vertical
    greenish = (hsv[:, 0] > 0.17) & (hsv[:, 0] < 0.4) & (hsv[:, 1] > 0.3)
    awning = (n[:, 1] > 0.3) & (c[:, 1] > 0.45) & (c[:, 1] < 0.6) & greenish & (c[:, 0] < 0.0)
    roof = (np.abs(n[:, 1]) > 0.4) & (c[:, 1] > 0.58) & ~awning & ~sign & (c[:, 0] > -0.36)
    walls = booth & vertical & (c[:, 1] < 0.6) & (c[:, 1] > 0.07) & ~sign & ~greenish & (hsv[:, 2] < 0.75)
    xf_yaw, scale = -90.0, 4.4      # front -X -> -Z; booth front ~2.2 m, whole plot ~4.3 m
    xf = place(m, xf_yaw, scale)
    # Sign board front plane in source units: x = -0.12, y 0.635..0.775, z -0.215..0.205.
    sc = trimesh.transform_points(np.array([[-0.128, 0.638, -0.21], [-0.128, 0.638, 0.2],
                                            [-0.128, 0.772, 0.2], [-0.128, 0.772, -0.21]]), xf)
    out = []
    for v, liv in TEA_LIVERIES.items():
        cols = base.copy()
        _paint(cols, raw, walls & (c[:, 1] < 0.27), liv["wall_lo"])
        _paint(cols, raw, walls & (c[:, 1] >= 0.27), liv["wall_hi"])
        _paint(cols, raw, roof, liv["roof"])
        _paint(cols, raw, awning, liv["awning"])
        _paint(cols, raw, sign, liv["sign"][2])
        img = sign_image(*liv["sign"], (512, 176))
        out.append(export({"stall": coloured(m, cols), "sign": sign_quad(sc, img)},
                          SHOPS / f"tea_stall_{v}.glb"))
    return out


def bake_fruit() -> list[dict]:
    # Source: sign and long side face +Z; canopy y 0.70..0.83, roof board above it.
    m, raw = load_tripo(SRC / "street_fruit_stall_3d_model.glb", lambda c: c[:, 1] > -1, 5000)
    raw = _lift(raw)
    base = _flatten(raw, 18)
    c, n = m.triangles_center, m.face_normals
    hsv = _hsv(raw)
    canopy = (c[:, 1] > 0.69) & (c[:, 1] < 0.84)
    stripe = canopy & (hsv[:, 0] < 0.09) & (hsv[:, 1] > 0.38)
    sign = (c[:, 1] > 0.8) & (c[:, 2] > 0.14)
    board = (c[:, 1] > 0.83) & ~sign
    wheel = hsv[:, 2] < 0.32
    body = (c[:, 1] < 0.315) & ~wheel & (np.abs(n[:, 1]) < 0.6)  # counter top at 0.32, fruit above
    xf = place(m, 180.0, 2.3)       # front +Z -> -Z; cart ~1.75 m long, 2.25 m tall
    sc = trimesh.transform_points(np.array([[-0.282, 0.826, 0.222], [0.282, 0.826, 0.222],
                                            [0.282, 0.946, 0.222], [-0.282, 0.946, 0.222]]), xf)
    out = []
    for v, liv in FRUIT_LIVERIES.items():
        cols = base.copy()
        _paint(cols, raw, stripe, liv["stripe"])
        _paint(cols, raw, canopy & ~stripe, "f3ead8")
        _paint(cols, raw, body, liv["body"])
        _paint(cols, raw, board | sign, liv["board"])
        img = sign_image(*liv["sign"], (512, 112))
        out.append(export({"cart": coloured(m, cols), "sign": sign_quad(sc, img)},
                          SHOPS / f"fruit_cart_{v}.glb"))
    return out


def bake_biryani() -> list[dict]:
    """Repaint the existing stall per livery; new sign; turn its front (+X) to -Z."""
    s = trimesh.load(BIRYANI_SRC, force="scene")
    geo = {}
    for node in s.graph.nodes_geometry:
        xf, gname = s.graph[node]
        g = s.geometry[gname].copy()
        g.apply_transform(xf)
        geo[gname] = g
    body = geo["Biryani_Stall_SharedColors"]
    lungi = geo["Biryani_Decal_0"]
    fc = body.visual.face_colors[:, :3].astype(int)
    rows = [tuple(r) for r in fc]
    wood = np.array([r in {(112, 69, 38), (148, 97, 54), (163, 110, 79)} for r in rows])
    roof = np.array([r == (191, 194, 199) for r in rows])
    board = np.array([r == (66, 143, 138) for r in rows])
    rot = trimesh.transformations.rotation_matrix(np.radians(90.0), [0, 1, 0])
    m = trimesh.Trimesh(body.vertices, body.faces, process=False)
    m.apply_transform(rot)
    lo = m.bounds[0]
    hi = m.bounds[1]
    t = np.eye(4)
    t[:3, 3] = [-(lo[0] + hi[0]) * 0.5, -lo[1], -(lo[2] + hi[2]) * 0.5]
    m.apply_transform(t)
    xf = t @ rot
    lungi = lungi.copy()
    lungi.apply_transform(xf)
    lungi.visual.material.metallicFactor = 0.0
    # Old sign decal plane: x = 0.2, z -0.72..1.12, y 2.03..2.81, facing +X (now -Z).
    sc = trimesh.transform_points(np.array([[0.205, 2.04, 1.11], [0.205, 2.04, -0.71],
                                            [0.205, 2.80, -0.71], [0.205, 2.80, 1.11]]), xf)
    raw = fc.astype(float)
    out = []
    for v, liv in BIRYANI_LIVERIES.items():
        cols = raw.copy()
        _paint(cols, raw, wood, liv["wood"])
        _paint(cols, raw, roof, liv["roof"])
        _paint(cols, raw, board, liv["board"])
        img = sign_image(*liv["sign"], (512, 216))
        out.append(export({"stall": coloured(m, cols), "lungi": lungi, "sign": sign_quad(sc, img)},
                          SHOPS / f"biryani_stall_{v}.glb"))
    return out


def bake_transformer() -> dict:
    # Keep the tank: drop the plinth (y < 0.07), the railing (outside the tank below its rim)
    # and the loose cable loop beside the bushings (x > 0.36 above mid height).
    def keep(c: np.ndarray) -> np.ndarray:
        tank_box = (np.abs(c[:, 2]) < 0.2) & (c[:, 0] > -0.33) & (c[:, 0] < 0.35)
        return (c[:, 1] > 0.07) & ((c[:, 1] >= 0.28) | tank_box) & ~((c[:, 0] > 0.36) & (c[:, 1] > 0.45))
    m, raw = load_tripo(SRC / "power_transformer_3d_model.glb", keep, 1800)  # merged into chunk meshes
    m, raw = drop_crumbs(m, raw, 30, 2.0)
    c = m.triangles_center
    lum = raw.mean(1)
    bushing = (c[:, 1] > 0.68) & (c[:, 0] > 0.05) & (c[:, 0] < 0.34)
    outside = (np.abs(c[:, 2]) > 0.17) | (c[:, 0] > 0.33) | (c[:, 1] > 0.69)
    cable = (lum < 45) & outside & ~bushing
    feet = c[:, 1] < 0.13
    cols = np.zeros_like(raw)
    tank = ~bushing & ~cable
    _paint(cols, raw, tank, TRANSFORMER["tank"])
    _paint(cols, raw, feet & tank, TRANSFORMER["steel"])
    _paint(cols, raw, bushing, TRANSFORMER["bushing"])
    cols[cable] = _rgb(TRANSFORMER["cable"])
    place(m, 0.0, 2.3)              # tank ~1.5 m long (+X along the road), ~1.85 m with bushings
    return export({"tank": coloured(m, cols)}, OUT / "eb_transformer.glb")


def main() -> int:
    for f in ("street_food_stall_3d_model.glb", "street_fruit_stall_3d_model.glb", "power_transformer_3d_model.glb"):
        if not (SRC / f).exists():
            print(f"missing source {SRC / f}: put the owner's Tripo export there", file=sys.stderr)
            return 1
    report = {"transformer": bake_transformer(), "tea": bake_tea(), "fruit": bake_fruit(),
              "biryani": bake_biryani()}
    print(json.dumps(report, indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
