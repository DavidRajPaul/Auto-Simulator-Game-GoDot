#!/usr/bin/env python3
"""The owner's CC BY tree packs -> single street trees for StreetTrees (Nov 14 2026).

Owner: "I got a few more tree collections. There might be kits in this. You must separate each
tree. Don't increase the existing tree count, just add these trees as well."

Sources (gitignored, re-copy from the owner's zips to rebake): assets_src/incoming/models/trees_cc/
  realistic_trees_collection/  "Realistic Trees Collection" by Jungle Jim (Sketchfab, CC BY 4.0):
                               7 plants on one scene (EZTree0 Large / Medium010 / Medium011,
                               EZTree1 Bush006 / Large001 / Large009 / Medium002); Bush006 is a
                               14 m wide shrub, not a street tree, so it is split but not baked
  mango_tree/                  "Mango Tree" by stealth86 (Sketchfab, CC BY 4.0): one tree, leaves,
                               branches and fruit; the leaf texture has a black background and no
                               alpha, so alpha is made from its brightness here
  tree_animate/                "Tree Animate" by RandyGF (Sketchfab, CC BY 4.0): THREE slim
                               poplar-like trees in one mesh (a kit), split by position here

For every tree this writes, like tools/assets/bake_trees.py does for the Tripo trees:
  assets/models/city/trees/<name>.glb   ONE primitive, ONE material, real height, origin at the
                                        trunk base, using <name>_atlas.png: ONE 1024 px atlas
                                        (leaves, bark, fruit packed; alpha-cut leaves)
  a row of VIEWS impostor views appended to tree_impostors.png, and an entry in trees.json with
  "cutout": true (StreetTrees gives those tree_near_cutout.gdshader).

Kept light enough for budget phones (the Tripo trees are 4.4-7.4k triangles): leaves are cards,
so a share of the cards is dropped at random and the rest are enlarged to keep the crown full
(LEAF_TRIS); bark is decimated with pyfqmr (BARK_TRIS); mango fruit is thinned to FRUITS.

Usage: python3 tools/assets/bake_cc_trees.py
Needs: numpy, pillow, scipy, pyfqmr (pip install pyfqmr).
"""
from __future__ import annotations

import json
import math
import re
import struct
from pathlib import Path

import numpy as np
import pyfqmr
from PIL import Image
from scipy.ndimage import distance_transform_edt
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "models" / "trees_cc"
OUT = ROOT / "assets" / "models" / "city" / "trees"
CELL = 256
SUPER = 3
VIEWS = 4
ATLAS = 1024
LEAF_TRIS = 5000
LEAF_TRIS_MANGO = 8000
BARK_TRIS = 2000
FRUITS = 36
FIRST_CODE = 10

# name -> (real height m, a short description). Heights are typical for Chennai avenues.
TREES = {
    "jj_large_0": (10.5, "broad shade tree"),
    "jj_medium010_0": (8.0, "round-crowned tree"),
    "jj_medium011_0": (7.0, "young shade tree"),
    "jj_large001_1": (10.0, "dense shade tree"),
    "jj_large009_1": (11.0, "large spreading tree"),
    "jj_medium002_1": (7.5, "open-crowned tree"),
    "mango": (9.0, "mango tree with fruit"),
    "poplar_a": (9.5, "slim columnar tree"),
    "poplar_b": (11.0, "slim columnar tree (tall)"),
    "poplar_c": (8.5, "slim columnar tree (short)"),
}


# --------------------------------------------------------------------------- glTF reading

def _quat(r):
    x, y, z, w = r
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def _node_matrix(n: dict) -> np.ndarray:
    if "matrix" in n:
        return np.array(n["matrix"], float).reshape(4, 4).T
    m = np.eye(4)
    m[:3, :3] = _quat(n.get("rotation", [0, 0, 0, 1])) * np.array(n.get("scale", [1, 1, 1]), float)
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


class Gltf:
    def __init__(self, folder: Path):
        self.dir = folder
        self.j = json.loads((folder / "scene.gltf").read_text())
        self.bin = (folder / "scene.bin").read_bytes()

    def accessor(self, i: int) -> np.ndarray:
        a = self.j["accessors"][i]
        v = self.j["bufferViews"][a["bufferView"]]
        comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        dt = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[a["componentType"]]
        size = np.dtype(dt).itemsize * comps
        stride = v.get("byteStride", size)
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        raw = np.frombuffer(self.bin, np.uint8, count=(a["count"] - 1) * stride + size, offset=off)
        return np.lib.stride_tricks.as_strided(raw, (a["count"], size), (stride, 1)).copy().view(dt).reshape(a["count"], comps)

    def primitives(self) -> list[dict]:
        world: dict[int, np.ndarray] = {}

        def walk(i: int, parent: np.ndarray) -> None:
            world[i] = parent @ _node_matrix(self.j["nodes"][i])
            for c in self.j["nodes"][i].get("children", []):
                walk(c, world[i])

        for r in self.j["scenes"][self.j.get("scene", 0)]["nodes"]:
            walk(r, np.eye(4))
        out = []
        for i, m in world.items():
            node = self.j["nodes"][i]
            if "mesh" not in node:
                continue
            for p in self.j["meshes"][node["mesh"]]["primitives"]:
                pos = self.accessor(p["attributes"]["POSITION"]).astype(float)
                pos = (np.c_[pos, np.ones(len(pos))] @ m.T)[:, :3]
                nor = self.accessor(p["attributes"]["NORMAL"]).astype(float) @ np.linalg.inv(m[:3, :3])
                nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-9)
                uv = self.accessor(p["attributes"]["TEXCOORD_0"]).astype(float)
                idx = self.accessor(p["indices"]).reshape(-1, 3).astype(np.int64)
                out.append({"node": node.get("name", ""), "P": pos, "N": nor, "UV": uv, "I": idx,
                            "mat": self.j["materials"][p.get("material", 0)], "g": self})
        return out

    def texture(self, mat: dict) -> Image.Image:
        t = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if t is None:
            t = mat.get("extensions", {}).get("KHR_materials_pbrSpecularGlossiness", {}).get("diffuseTexture")
        img = self.j["images"][self.j["textures"][t["index"]]["source"]]
        return Image.open(self.dir / img["uri"]).convert("RGBA")


# --------------------------------------------------------------------------- splitting

def _components(pos: np.ndarray, idx: np.ndarray) -> np.ndarray:
    """Connected piece id per triangle (vertices welded by position)."""
    _, inv = np.unique(np.round(pos * 1e4).astype(np.int64), axis=0, return_inverse=True)
    j = inv.ravel()[idx]
    n = int(j.max()) + 1
    a = coo_matrix((np.ones(2 * len(j)), (np.r_[j[:, 0], j[:, 1]], np.r_[j[:, 1], j[:, 2]])), shape=(n, n))
    return connected_components(a, directed=False)[1][j[:, 0]]


def _sub(p: dict, keep_tris: np.ndarray) -> dict:
    idx = p["I"][keep_tris]
    used, inv = np.unique(idx.ravel(), return_inverse=True)
    q = dict(p)
    q["P"], q["N"], q["UV"], q["I"] = p["P"][used], p["N"][used], p["UV"][used], inv.reshape(-1, 3)
    return q


def split_trees() -> dict[str, list[dict]]:
    trees: dict[str, list[dict]] = {}
    for p in Gltf(SRC / "realistic_trees_collection").primitives():
        m = re.match(r"Tree (EZTree\d)\.([A-Za-z]+\d*)_", p["node"])
        p["kind"] = "leaf" if "leaves" in p["node"] else "bark"
        trees.setdefault(f"jj_{m.group(2).lower()}_{m.group(1)[-1]}", []).append(p)
    for p in Gltf(SRC / "mango_tree").primitives():
        p["kind"] = {"Material.001": "leaf", "Material.002": "bark", "Material.004": "fruit"}[p["mat"]["name"]]
        trees.setdefault("mango", []).append(p)
    # Tree Animate: three trees side by side in each mesh. Cut on the two widest gaps along X
    # between trunk pieces, then send every piece of every mesh to the tree it stands in.
    prims = Gltf(SRC / "tree_animate").primitives()
    bark = next(p for p in prims if p["mat"]["name"] == "Bark")
    trunk_x = np.sort(bark["P"][bark["P"][:, 1] < bark["P"][:, 1].min() + 2.0][:, 0])
    gaps = np.argsort(np.diff(trunk_x))[-2:]
    cuts = sorted((trunk_x[g] + trunk_x[g + 1]) * 0.5 for g in gaps)
    names = ["poplar_a", "poplar_b", "poplar_c"]
    for p in prims:
        comp = _components(p["P"], p["I"])
        cx = np.zeros(comp.max() + 1)
        np.add.at(cx, comp, p["P"][p["I"][:, 0], 0])
        cx /= np.maximum(np.bincount(comp), 1)
        which = np.searchsorted(cuts, cx[comp])
        kind = "bark" if p["mat"]["name"] == "Bark" else "leaf"
        for k in range(3):
            q = _sub(p, which == k)
            q["kind"] = kind
            trees.setdefault(names[k], []).append(q)
    return trees


# --------------------------------------------------------------------------- reduction

def thin_cards(p: dict, budget: int, rng: np.random.Generator, grow_cap: float = 2.2) -> dict:
    """Leaf cards: keep a random share of the pieces, enlarged about their own centre."""
    tris = len(p["I"])
    if tris <= budget:
        return p
    comp = _components(p["P"], p["I"])
    n = comp.max() + 1
    keep_n = max(1, int(n * budget / tris))
    kept = np.zeros(n, bool)
    kept[rng.choice(n, keep_n, replace=False)] = True
    q = _sub(p, kept[comp])
    grow = min(1.0 / math.sqrt(keep_n / n), grow_cap)
    vc = _components(q["P"], q["I"])
    centre = np.zeros((vc.max() + 1, 3))
    np.add.at(centre, vc, q["P"][q["I"]].mean(axis=1))
    centre /= np.maximum(np.bincount(vc), 1)[:, None]
    vert_piece = np.zeros(len(q["P"]), np.int64)
    vert_piece[q["I"].ravel()] = np.repeat(vc, 3)
    c = centre[vert_piece]
    q["P"] = c + (q["P"] - c) * grow
    return q


def decimate(p: dict, budget: int) -> dict:
    """Bark and fruit: weld by position (UV seams split the source mesh into open pieces, which
    pyfqmr then refuses to touch), simplify, and give every new triangle the UV mapping of the
    source triangle nearest to it (barycentric in that triangle's plane), so no triangle spans
    a UV seam. The result is per-corner (I = 0, 1, 2, ...); write_glb welds it again."""
    if len(p["I"]) <= budget:
        return p
    from scipy.spatial import cKDTree
    # Hundreds of loose twigs (the mango has 1455 bark pieces) would eat the whole budget and leave
    # the trunk a spike: drop the smallest pieces first, then simplify what is left.
    if len(p["I"]) > budget * 3:
        p = drop_twigs(p, budget * 3)
    key, first, inv = np.unique(np.round(p["P"] * 1e4).astype(np.int64), axis=0, return_index=True, return_inverse=True)
    s = pyfqmr.Simplify()
    s.setMesh(p["P"][first], inv.ravel()[p["I"]])
    s.simplify_mesh(target_count=budget, aggressiveness=6, preserve_border=False, verbose=False)
    v, f, _ = s.getMesh()
    v, f = np.asarray(v, float), np.asarray(f, np.int64)
    src = p["P"][p["I"]]
    near = cKDTree(src.mean(axis=1)).query(v[f].mean(axis=1))[1]
    a, b_, c = src[near, 0], src[near, 1], src[near, 2]
    e0, e1 = b_ - a, c - a
    d00, d01, d11 = (e0 * e0).sum(1), (e0 * e1).sum(1), (e1 * e1).sum(1)
    den = np.where(np.abs(d00 * d11 - d01 * d01) < 1e-12, 1e-12, d00 * d11 - d01 * d01)
    uv_src = p["UV"][p["I"][near]]
    corners = v[f]
    fn = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    vn = np.zeros_like(v)
    for k in range(3):
        np.add.at(vn, f[:, k], fn)
    uv = np.zeros((len(f), 3, 2))
    nor = np.zeros((len(f), 3, 3))
    for k in range(3):
        w = corners[:, k] - a
        d20, d21 = (w * e0).sum(1), (w * e1).sum(1)
        bv = (d11 * d20 - d01 * d21) / den
        bw = (d00 * d21 - d01 * d20) / den
        bu = 1.0 - bv - bw
        uv[:, k] = bu[:, None] * uv_src[:, 0] + bv[:, None] * uv_src[:, 1] + bw[:, None] * uv_src[:, 2]
        nor[:, k] = vn[f[:, k]]
    nor /= np.maximum(np.linalg.norm(nor, axis=2, keepdims=True), 1e-9)
    q = dict(p)
    q["P"], q["UV"], q["N"] = corners.reshape(-1, 3), uv.reshape(-1, 2), nor.reshape(-1, 3)
    q["I"] = np.arange(len(f) * 3).reshape(-1, 3)
    if len(f) > budget * 1.15:
        q = drop_twigs(q, budget)
    return q


def drop_twigs(p: dict, budget: int) -> dict:
    """A mesh of hundreds of separate twigs can't be simplified below ~25 triangles a twig.
    Keep the biggest pieces (trunk, limbs) up to the budget; the small twigs sit inside the
    leaves and are not missed."""
    comp = _components(p["P"], p["I"])
    tri = p["P"][p["I"]]
    area = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1)
    size = np.bincount(comp, area)
    count = np.bincount(comp)
    order = np.argsort(-size)
    keep = order[np.cumsum(count[order]) <= budget]
    if len(keep) == 0:
        keep = order[:1]
    return _sub(p, np.isin(comp, keep))


# --------------------------------------------------------------------------- atlas

def leaf_alpha(img: Image.Image) -> Image.Image:
    """Mango leaf texture: black background, no alpha. Make alpha from brightness."""
    a = np.asarray(img, np.float32) / 255.0
    lum = a[..., :3].max(axis=2)
    a[..., 3] = np.clip((lum - 0.06) / 0.08, 0.0, 1.0)
    return Image.fromarray((a * 255).astype(np.uint8), "RGBA")


def opaque_islands(img: Image.Image) -> Image.Image:
    """Bark is opaque, but the mango's bark texture is grey branch islands on BLACK: decimated
    triangles and mipmaps pull that black in. Every background pixel takes the nearest island's
    colour (a no-op for the collection's full tiling bark)."""
    a = np.asarray(img.convert("RGB"), np.float32) / 255.0
    rgba = np.concatenate([a, (a.max(axis=2, keepdims=True) > 0.04).astype(np.float32)], axis=2)
    out = bleed(rgba)
    out[..., 3] = 1.0
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def greener(img: Image.Image) -> Image.Image:
    """Tree Animate's leaves are olive (autumn in Chennai's light): lean them to a fresh green."""
    a = np.asarray(img, np.float32) / 255.0
    lum = a[..., :3].mean(axis=2, keepdims=True)
    rgb = a[..., :3] * np.array([0.72, 1.0, 0.78])
    rgb *= lum / np.maximum(rgb.mean(axis=2, keepdims=True), 1e-4)
    a[..., :3] = np.clip(rgb * 1.08, 0.0, 1.0)
    return Image.fromarray((a * 255).astype(np.uint8), "RGBA")


def bleed(a: np.ndarray) -> np.ndarray:
    """Every see-through pixel takes the colour of the nearest leaf pixel (mipmaps stay green)."""
    solid = a[..., 3] > 0.5
    if not solid.any() or solid.all():
        return a
    _, (iy, ix) = distance_transform_edt(~solid, return_indices=True)
    out = a.copy()
    out[..., :3] = a[..., :3][iy, ix]
    return out


def build_atlas(parts: list[dict]) -> tuple[np.ndarray, dict]:
    """Pack the tree's textures into one ATLAS^2 image. Leaves get the top 5/8, bark 1/4, fruit
    or a second leaf texture the rest. Returns (RGBA float image, material name -> rect)."""
    textures: dict[str, tuple[str, Image.Image]] = {}
    for p in parts:
        name = p["mat"]["name"]
        if name not in textures:
            img = p["g"].texture(p["mat"])
            if p["kind"] == "leaf" and p["g"].dir.name == "mango_tree":
                img = leaf_alpha(img)
            if p["kind"] == "leaf" and p["g"].dir.name == "tree_animate":
                img = greener(img)
            if p["kind"] == "bark":
                img = opaque_islands(img)
            textures[name] = (p["kind"], img)
    leaf = [n for n, (k, _) in textures.items() if k == "leaf"]
    other = [n for n, (k, _) in textures.items() if k != "leaf"]
    rects: dict[str, tuple[int, int, int, int]] = {}
    if len(leaf) == 1:
        rects[leaf[0]] = (0, 0, ATLAS, ATLAS * 5 // 8)
    else:
        rects[leaf[0]] = (0, 0, ATLAS, ATLAS * 5 // 8)
        rects[leaf[1]] = (ATLAS // 2, ATLAS * 7 // 8, ATLAS // 2, ATLAS // 8)
    y = ATLAS * 5 // 8
    for n in other:
        if textures[n][0] == "bark":
            rects[n] = (0, y, ATLAS, ATLAS // 4)
        else:
            rects[n] = (0, ATLAS * 7 // 8, ATLAS // 2, ATLAS // 8)
    atlas = np.zeros((ATLAS, ATLAS, 4), np.float32)
    for n, (kind, img) in textures.items():
        x, y0, w, h = rects[n]
        cell = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
        atlas[y0:y0 + h, x:x + w] = bleed(cell) if kind == "leaf" else cell
    return atlas, rects


def remap_uv(p: dict, rect: tuple[int, int, int, int]) -> np.ndarray:
    """UV into the atlas rect. Tiled bark (UVs past 0..1) is folded per triangle (each triangle
    keeps its own tile), so the bark pattern repeats instead of smearing."""
    x, y, w, h = rect
    uv = p["UV"][p["I"]]  # per corner
    if uv.min() < -0.01 or uv.max() > 1.01:
        uv = uv - np.floor(uv.min(axis=1, keepdims=True))
    uv = np.clip(uv, 0.0, 1.0)
    inset = 2.0 / ATLAS
    u = (x + w * uv[..., 0]) / ATLAS
    v = (y + h * uv[..., 1]) / ATLAS
    return np.stack([np.clip(u, x / ATLAS + inset, (x + w) / ATLAS - inset), np.clip(v, y / ATLAS + inset, (y + h) / ATLAS - inset)], axis=-1)


# --------------------------------------------------------------------------- one tree

def bake_tree(name: str, parts: list[dict], height: float, rng: np.random.Generator) -> dict:
    bark = np.concatenate([p["P"] for p in parts if p["kind"] == "bark"])
    lo = bark[:, 1].min()
    span = np.concatenate([p["P"] for p in parts])[:, 1]
    base = bark[bark[:, 1] <= lo + (span.max() - lo) * 0.02]
    centre = np.array([base[:, 0].mean(), lo, base[:, 2].mean()])
    scale = height / (span.max() - lo)
    reduced = []
    leaf_total = sum(len(p["I"]) for p in parts if p["kind"] == "leaf")
    bark_total = sum(len(p["I"]) for p in parts if p["kind"] == "bark")
    for p in parts:
        if p["kind"] == "leaf":
            # Mango leaves are 3D sprays, not flat cards: enlarged far they turn into spikes, so
            # the mango keeps more of them and grows them less.
            budget = LEAF_TRIS_MANGO if name == "mango" else LEAF_TRIS
            q = thin_cards(p, max(1, int(budget * len(p["I"]) / leaf_total)), rng, 1.7 if name == "mango" else 2.2)
        elif p["kind"] == "bark":
            q = decimate(p, max(200, int(BARK_TRIS * len(p["I"]) / bark_total)))
        else:
            comp = _components(p["P"], p["I"])
            pick = rng.choice(comp.max() + 1, min(FRUITS, comp.max() + 1), replace=False)
            q = decimate(_sub(p, np.isin(comp, pick)), FRUITS * 24)
        q = dict(q)
        q["P"] = (q["P"] - centre) * scale
        reduced.append(q)
    atlas, rects = build_atlas(reduced)
    # Leaf normals lean outward from the crown's middle, so a crown shades like a round mass
    # instead of a box of randomly lit cards (the usual foliage trick).
    leaf_pts = np.concatenate([q["P"] for q in reduced if q["kind"] == "leaf"])
    crown = leaf_pts.mean(axis=0)
    pos, nor, uvs = [], [], []
    for q in reduced:
        tri_p = q["P"][q["I"]]
        tri_n = q["N"][q["I"]]
        if q["kind"] == "leaf":
            out = tri_p - crown
            out /= np.maximum(np.linalg.norm(out, axis=2, keepdims=True), 1e-6)
            tri_n = out * 0.75 + tri_n * 0.25
            tri_n /= np.maximum(np.linalg.norm(tri_n, axis=2, keepdims=True), 1e-6)
        pos.append(tri_p.reshape(-1, 3))
        nor.append(tri_n.reshape(-1, 3))
        uvs.append(remap_uv(q, rects[q["mat"]["name"]]).reshape(-1, 2))
    pos, nor, uv = np.concatenate(pos), np.concatenate(nor), np.concatenate(uvs)
    tris = len(pos) // 3
    radius = float(np.max(np.hypot(pos[:, 0], pos[:, 2])))
    write_glb(OUT / f"{name}.glb", name, pos, nor, uv, atlas)
    return {"pos": pos, "uv": uv, "atlas": atlas, "radius": radius, "tris": tris}


def write_glb(path: Path, name: str, pos: np.ndarray, nor: np.ndarray, uv: np.ndarray, atlas: np.ndarray) -> None:
    key = np.concatenate([np.round(pos * 2000), np.round(nor * 200), np.round(uv * 8192)], axis=1)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    p, n, t = pos[first].astype(np.float32), nor[first].astype(np.float32), uv[first].astype(np.float32)
    idx = inverse.ravel().astype(np.uint32)
    # The atlas sits beside the GLB (not embedded), so Godot imports it once as a VRAM-compressed,
    # mipmapped texture instead of extracting a second copy.
    png_name = f"{name}_atlas.png"
    Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA").save(path.parent / png_name, "PNG", optimize=True)
    blobs = [p.tobytes(), n.tobytes(), t.tobytes(), idx.tobytes()]
    views, body, off = [], b"", 0
    for k, blob in enumerate(blobs):
        view = {"buffer": 0, "byteOffset": off, "byteLength": len(blob)}
        if k < 4:
            view["target"] = 34963 if k == 3 else 34962
        views.append(view)
        pad = (-len(blob)) % 4
        body += blob + b"\0" * pad
        off += len(blob) + pad
    doc = {
        "asset": {"version": "2.0", "generator": "namma-auto bake_cc_trees.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": name, "doubleSided": True, "alphaMode": "MASK", "alphaCutoff": 0.5,
                       "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0}}],
        "textures": [{"source": 0, "sampler": 0}], "samplers": [{"magFilter": 9729, "minFilter": 9987}],
        "images": [{"uri": png_name}],
        "buffers": [{"byteLength": len(body)}], "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(p), "type": "VEC3", "min": p.min(0).tolist(), "max": p.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(n), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(t), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ],
    }
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * ((-len(text)) % 4)
    path.write_bytes(b"glTF" + struct.pack("<II", 2, 28 + len(text) + len(body)) + struct.pack("<I4s", len(text), b"JSON") + text
                     + struct.pack("<I4s", len(body), b"BIN\0") + body)


# --------------------------------------------------------------------------- impostor views

def render_view(pos: np.ndarray, uv: np.ndarray, tex: np.ndarray, angle: float, radius: float, height: float) -> np.ndarray:
    """Unlit orthographic, alpha-tested render, the same framing as bake_trees.render_view."""
    n = CELL * SUPER
    a = np.array([math.cos(angle), 0.0, math.sin(angle)])
    d = np.cross([0.0, 1.0, 0.0], a)
    sx = (pos @ a + radius) / (2.0 * radius) * n
    sy = (1.0 - pos[:, 1] / height) * n
    depth = pos @ d
    th, tw = tex.shape[:2]
    rgb = np.zeros((n, n, 3), np.float32)
    zbuf = np.full((n, n), np.inf, np.float32)
    for t in range(len(pos) // 3):
        f = (3 * t, 3 * t + 1, 3 * t + 2)
        x0, x1, x2 = sx[list(f)]
        y0, y1, y2 = sy[list(f)]
        minx, maxx = max(int(math.floor(min(x0, x1, x2))), 0), min(int(math.ceil(max(x0, x1, x2))), n - 1)
        miny, maxy = max(int(math.floor(min(y0, y1, y2))), 0), min(int(math.ceil(max(y0, y1, y2))), n - 1)
        if minx > maxx or miny > maxy:
            continue
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-9:
            continue
        px, py = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
        w0 = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / den
        w1 = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / den
        w2 = 1.0 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        b0, b1, b2 = w0[inside], w1[inside], w2[inside]
        z = b0 * depth[f[0]] + b1 * depth[f[1]] + b2 * depth[f[2]]
        iy, ix = py[inside].astype(int), px[inside].astype(int)
        u = b0 * uv[f[0], 0] + b1 * uv[f[1], 0] + b2 * uv[f[2], 0]
        v = b0 * uv[f[0], 1] + b1 * uv[f[1], 1] + b2 * uv[f[2], 1]
        c = tex[np.clip((v * th).astype(int), 0, th - 1), np.clip((u * tw).astype(int), 0, tw - 1)]
        ok = (c[:, 3] >= 0.5) & (z < zbuf[iy, ix])
        if not ok.any():
            continue
        zbuf[iy[ok], ix[ok]] = z[ok]
        rgb[iy[ok], ix[ok]] = c[ok, :3]
    alpha = np.isfinite(zbuf).astype(np.float32)
    pre = np.concatenate([rgb * alpha[..., None], alpha[..., None]], axis=2)
    pre = pre.reshape(CELL, SUPER, CELL, SUPER, 4).mean(axis=(1, 3))
    a_ = pre[..., 3:4]
    col = np.where(a_ > 0, pre[..., :3] / np.maximum(a_, 1e-6), 0.0)
    return bleed_card(np.concatenate([col, a_], axis=2))


def bleed_card(cell: np.ndarray) -> np.ndarray:
    filled = cell[..., 3] > 0.0
    if not filled.any():
        return cell
    _, (iy, ix) = distance_transform_edt(~filled, return_indices=True)
    return np.concatenate([cell[..., :3][iy, ix], cell[..., 3:4]], axis=2)


# --------------------------------------------------------------------------- main

def main() -> int:
    meta = json.loads((OUT / "trees.json").read_text())
    # Keep the Tripo trees' rows (bake_trees.py) and replace any rows of an earlier run of this.
    base_rows = sum(1 for sp in meta["species"].values() if not sp.get("cutout"))
    meta["species"] = {k: v for k, v in meta["species"].items() if not v.get("cutout")}
    old = np.asarray(Image.open(OUT / "tree_impostors.png").convert("RGBA"), np.float32)[: base_rows * CELL] / 255.0
    rows = [old]
    rng = np.random.default_rng(1411)
    trees = split_trees()
    for k, name in enumerate(TREES):
        height = TREES[name][0]
        res = bake_tree(name, trees[name], height, rng)
        atlas_tex = res["atlas"]
        row = np.zeros((CELL, CELL * VIEWS, 4), np.float32)
        for v in range(VIEWS):
            row[:, v * CELL:(v + 1) * CELL] = render_view(res["pos"], res["uv"], atlas_tex, math.pi * v / VIEWS, res["radius"], height)
        rows.append(row)
        code = FIRST_CODE + k
        meta["species"][str(code)] = {"name": name, "height": height, "radius": round(res["radius"], 2),
                                      "row": base_rows + k, "tris": res["tris"], "cutout": True}
        print(f"{name:16s} code {code}  {res['tris']:5d} tris  height {height} m  crown radius {res['radius']:.2f} m")
    meta["rows"] = base_rows + len(TREES)
    atlas = np.concatenate(rows, axis=0)
    Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT / "tree_impostors.png", optimize=True)
    (OUT / "trees.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"atlas {atlas.shape[1]}x{atlas.shape[0]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
