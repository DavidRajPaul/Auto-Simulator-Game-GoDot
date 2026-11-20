#!/usr/bin/env python3
"""Turns downloaded Sketchfab people into light, walking game characters (assets/models/people/*.glb).

For each character:
  1. Skins the source mesh into world space at its rest pose, turns it to face +Z, stands it on the
     ground (feet at y = 0) and scales it to a real Chennai height.
  2. Rebuilds a clean 22-bone humanoid skeleton (fingers, eyes, twist and neck helper bones folded
     into their nearest kept parent) - fewer bones = cheaper animation on budget phones.
  3. Retargets the shared clips onto that skeleton: "walk" (in place, from the old man's walk) and
     "idle" (from the saree model's idle). Bones are first aligned to the source's rest pose, then
     the source's world-space rotation per frame is applied, so A-pose and T-pose rigs both work.
     The walk's forward root motion is removed and its true speed is written to people.json, so the
     game moves each person at exactly the pace their feet step (no ice-skating).
  4. Packs every texture into one atlas and merges all parts into one primitive: one draw call.
  5. Simplify region by region (people_detail.py: faces and hands keep their own budgets), then
     gltf-transform prune writes the GLB with the 1024 px atlas.

Raw downloads stay in assets_src/incoming/models/people (gitignored); only the .glb files ship.
Needs: numpy, Pillow, scipy, meshoptimizer (pip) and gltf-transform (npm ci in tools/assets).
Rebuilding drops the street clips: copy them back with copy_people_clips.py (see AGENTS.md).
Usage: python3 tools/assets/process_people.py [ids...]
"""
from __future__ import annotations

import json
import math
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_rig import Gltf, arc, canonical, mat_to_quat, orthonormal, yaw  # noqa: E402
import people_detail as detail  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "models" / "people"
OUT = ROOT / "assets" / "models" / "people"
GLTF = ROOT / "tools" / "assets" / "node_modules" / ".bin" / "gltf-transform"
WORK = ROOT / "assets_src" / "incoming" / "models" / "people" / "_work"

KEEP = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
        "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
        "RightShoulder", "RightArm", "RightForeArm", "RightHand",
        "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
        "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
PARENT = {"Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1", "Neck": "Spine2", "Head": "Neck",
          "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
          "RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot"}
for _s in ("Left", "Right"):
    PARENT.update({f"{_s}Shoulder": "Spine2", f"{_s}Arm": f"{_s}Shoulder", f"{_s}ForeArm": f"{_s}Arm",
                   f"{_s}Hand": f"{_s}ForeArm"})
# Where each bone points (for the rest-pose alignment). Leaves use an end site when the rig has one.
AIM = {b: c for c, b in PARENT.items() if c not in ("LeftUpLeg", "RightUpLeg", "LeftShoulder", "RightShoulder")}
AIM.update({"Hips": "Spine", "Spine2": "Neck", "Head": "HeadTop_End", "LeftHand": "LeftHandMiddle1",
            "RightHand": "RightHandMiddle1", "LeftToeBase": "LeftToe_End", "RightToeBase": "RightToe_End"})
DROP_PARTS = ("cornea", "teeth", "tongue", "eyelash", "lash", "occlusion", "tearline")
FPS = 30

# Animation sources: (raw folder, animation index, keep root motion as speed)
CLIPS = {
    "walk": ("indian_old_man_walking", 0),
    "idle": ("female_test", 0),
}

# Fallback clip source when the raw animation downloads above are not on this machine: a shipped
# character that already carries the retargeted in-place "walk" and "idle" on the same 22 bones.
# Its walk has no root motion left, so the pace comes from people.json, scaled by hips height.
FALLBACK_CLIP_GLB = OUT / "young_man.glb"
FALLBACK_CLIP_ID = "young_man"

# id, raw folder, height m, triangle budget, skin index (for files with several people), credit
PEOPLE = [
    ("old_man_veshti", "indian_old_man_walking", 1.66, 3000, 0,
     '"Indian Old man walking" by anandmohan662 (Sketchfab), CC BY 4.0'),
    # Imported from the user-supplied CC BY packs, after review of the source glTF rigs.
    # Dhoti cloth in this particular export previously distorted; check final render before release.
    ("man_dhoti_new", "indian_man_in_dhoti", 1.68, 3400, 0,
     '"Indian Man In Dhoti" by anandmohan662 (Sketchfab), CC BY 4.0'),
    ("man_pattern_shirt", "indian_man_in_pattern_shirt", 1.73, 3500, 0,
     '"indian man in pattern shirt" by Pixel_Monster (Sketchfab), CC BY 4.0'),
    ("woman_saree_new", "sareewoman", 1.57, 3400, 0,
     '"Sareewoman" by dk8026854 (Sketchfab), CC BY 4.0'),
    ("young_man", "alex_texel_a-pose", 1.72, 3000, 0,
     '"Alex Texel A-pose" by alex.texelsales (Sketchfab), CC BY 4.0'),
    # "Indian Woman in Saree" (Pixel_Monster) is left out: Sketchfab Standard licence, and the project
    # ships only CC0 / CC BY / Pixabay assets (docs/ASSETS.md). Its body is the same avatar as
    # "Female test", which is CC BY and gives the saree women below (outfit colour overridden).
    ("woman_saree_violet", "female_test", 1.56, 3200, 0,
     '"Female test" by CloudHubOmniTeam (Sketchfab), CC BY 4.0', {}, {"paint": ["outfit"]}),
    ("woman_saree_green", "female_test", 1.58, 3200, 0,
     '"Female test" by CloudHubOmniTeam (Sketchfab), CC BY 4.0, saree recoloured', {"outfit": [0.03, 0.26, 0.09, 1.0]},
     {"paint": ["outfit"]}),
    ("woman_saree_maroon", "female_test", 1.54, 3200, 0,
     '"Female test" by CloudHubOmniTeam (Sketchfab), CC BY 4.0, saree recoloured', {"outfit": [0.33, 0.02, 0.04, 1.0]},
     {"paint": ["outfit"]}),
    # Ready Player Me style avatars (74 bones, 50–112k tris, ~25 textures) → 22 bones, one atlas.
    # "woman_modern" ("Modern Indian Woman", Pixel_Monster, CC BY 4.0) was removed on Nov 20: its
    # face and hands had collapsed in the old simplifier and the raw download was not available to
    # rebuild it. woman_coat took its place. Add the spec back here to rebuild it from the source.
    ("man_casual", "chennai_man_rpm", 1.72, 3600, 0,
     '"Dhanush 3d model" by Peter Charles (Sketchfab), CC BY 4.0 — face repainted as a generic character'),
    # ^ Before baking, the photo face on its head texture is replaced by tools/art/genericize_face.py
    #   (the licence covers the model, not the actor's likeness). Keep the .orig.jpeg next to it.
    # Nov 20 owner upload. "Wife Final" has no skeleton: it borrows the bones and skin weights of
    # "Female test" (also a saree, also an A-pose) through rig_static.py.
    ("woman_saree_kanchi", "wife_final", 1.56, 3400, None,
     '"Wife Final" by svgmishra95 (Sketchfab), CC BY 4.0', {},
     {"rig_from": "female_test", "paint": ["Saree"]}),
    # Reallusion Character Creator rig (CC_Base_* bones, mapped in gltf_rig.canonical).
    ("woman_coat", "lady_in_coat", 1.62, 3400, 0,
     '"Lady in Coat" by aribb (Sketchfab), CC BY 4.0', {}, {"paint": ["Long_slim_coat"]}),
    ("girl_churidar", "south_indian_women", 1.55, 3200, 0,
     '"South Indian Women" by alnmathew (Sketchfab), CC BY 4.0', {}, {"solid_hair": True, "paint": ["Kurta"]}),
    ("girl_pavadai", "south_indian_women", 1.52, 4000, 1,
     '"South Indian Women" by alnmathew (Sketchfab), CC BY 4.0', {}, {"paint": ["Skirt"]}),
]


# --- Source analysis -------------------------------------------------------------------------

class Rig:
    """One skin of a source file, resolved to canonical bone names and normalised space."""

    def __init__(self, g: Gltf, skin_index: int, height: float | None):
        self.g = g
        skin = g.j["skins"][skin_index]
        self.skin_index = skin_index
        self.joints: list[int] = skin["joints"]
        self.ibm = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1) \
            if "inverseBindMatrices" in skin else np.tile(np.eye(4), (len(self.joints), 1, 1))
        self.by_name: dict[str, int] = {}
        for j in self.joints:
            c = canonical(g.nodes[j].get("name", ""))
            self.by_name.setdefault(c, j)
        missing = [b for b in KEEP if b not in self.by_name]
        if missing:
            raise SystemExit(f"{g.path}: skin {skin_index} lacks bones {missing}")
        rest = g.rest_world()
        self.rest = rest
        # Facing: average foot -> toe direction on the ground plane becomes +Z.
        fwd = np.zeros(3)
        for s in ("Left", "Right"):
            fwd += rest[self.by_name[f"{s}ToeBase"]][:3, 3] - rest[self.by_name[f"{s}Foot"]][:3, 3]
        fwd[1] = 0.0
        self.turn = yaw(math.atan2(-fwd[0], fwd[2])) if np.linalg.norm(fwd) > 1e-6 else np.eye(3)
        # Recheck: turn @ fwd should point to +Z.
        f2 = self.turn @ fwd
        if f2[2] < 0:
            self.turn = yaw(math.pi) @ self.turn
        self.height = height
        self.scale = 1.0
        self.offset = np.zeros(3)

    def fit(self, verts_world: np.ndarray) -> None:
        """Scale/offset so the skinned mesh is `height` tall, feet on y=0, hips over the origin."""
        v = verts_world @ self.turn.T
        h = v[:, 1].max() - v[:, 1].min()
        self.scale = (self.height / h) if self.height else 1.0
        hips = self.turn @ self.rest[self.by_name["Hips"]][:3, 3]
        self.offset = -np.array([hips[0] * self.scale, v[:, 1].min() * self.scale, hips[2] * self.scale])

    def fit_skeleton_only(self) -> None:
        """For animation sources: scale from hips height (no mesh needed); feet on the ground."""
        ys = [self.turn @ self.rest[self.by_name[b]][:3, 3] for b in ("LeftToeBase", "RightToeBase", "Hips")]
        ground = min(ys[0][1], ys[1][1])
        self.scale = 1.0
        self.offset = -np.array([ys[2][0], ground, ys[2][2]])

    def norm_point(self, p: np.ndarray) -> np.ndarray:
        return (self.turn @ p) * self.scale + self.offset

    def norm_rot(self, m: np.ndarray) -> np.ndarray:
        return orthonormal(self.turn @ m[:3, :3])

    def pose(self, world: list[np.ndarray]) -> dict[str, tuple[np.ndarray, np.ndarray]]:
        """Kept bones (+ aim end sites) -> (normalised rotation, normalised position)."""
        out = {}
        names = set(KEEP) | set(AIM.values())
        for n in names:
            j = self.by_name.get(n)
            if j is None:
                continue
            out[n] = (self.norm_rot(world[j]), self.norm_point(world[j][:3, 3]))
        return out


def aim_dir(pose: dict, bone: str) -> np.ndarray | None:
    tgt = AIM.get(bone)
    if tgt is None or tgt not in pose:
        return None
    d = pose[tgt][1] - pose[bone][1]
    return d if np.linalg.norm(d) > 1e-5 else None


# --- Mesh extraction -------------------------------------------------------------------------

def kept_ancestor(rig: Rig, node: int) -> str:
    """Canonical name of the nearest kept bone at or above `node` (Hips if none)."""
    g = rig.g
    n = node
    while n >= 0:
        c = canonical(g.nodes[n].get("name", ""))
        if c in KEEP and rig.by_name.get(c) == n:
            return c
        n = g.parent[n]
    return "Hips"


def extract_mesh(rig: Rig):
    """World-space skinned rest mesh of every primitive bound to this skin (minus tiny eye parts).
    Returns list of parts: dict(pos, nrm, uv, joints[k,4] as kept-bone indices, weights, material)."""
    g = rig.g
    parts = []
    joint_keep = [KEEP.index(kept_ancestor(rig, j)) for j in rig.joints]
    for ni, node in enumerate(g.nodes):
        if "mesh" not in node:
            continue
        skinned = node.get("skin") == rig.skin_index
        if "skin" in node and not skinned:
            continue
        if "skin" not in node:
            # Rigid prop under the skeleton (hair clip, bag...). Only take it if it hangs off this rig.
            anc = node.get("name", "")
            n = g.parent[ni]
            under = False
            while n >= 0:
                if n in rig.joints:
                    under = True
                    break
                n = g.parent[n]
            if not under:
                continue
        mesh = g.j["meshes"][node["mesh"]]
        for prim in mesh["primitives"]:
            mat_i = prim.get("material")
            mat = g.j["materials"][mat_i] if mat_i is not None else {}
            label = (mesh.get("name", "") + " " + mat.get("name", "")).lower()
            if any(k in label for k in DROP_PARTS):
                continue
            if prim.get("mode", 4) != 4:
                continue
            a = prim["attributes"]
            pos = g.accessor(a["POSITION"])
            nrm = g.accessor(a["NORMAL"]) if "NORMAL" in a else np.tile([0.0, 1.0, 0.0], (len(pos), 1))
            uv = g.accessor(a["TEXCOORD_0"]) if "TEXCOORD_0" in a else np.zeros((len(pos), 2))
            idx = g.accessor(prim["indices"])[:, 0].astype(np.int64) if "indices" in prim else np.arange(len(pos))
            if skinned:
                J = g.accessor(a["JOINTS_0"]).astype(np.int64)
                W = g.accessor(a["WEIGHTS_0"])
                W = W / np.maximum(W.sum(1, keepdims=True), 1e-9)
                mats = np.array([rig.rest[j] @ rig.ibm[k] for k, j in enumerate(rig.joints)])
                skin_m = np.einsum("vk,vkij->vij", W, mats[J])
                p4 = np.c_[pos, np.ones(len(pos))]
                wpos = np.einsum("vij,vj->vi", skin_m, p4)[:, :3]
                wn = np.einsum("vij,vj->vi", skin_m[:, :3, :3], nrm)
                kj = np.array(joint_keep)[J]
                # Merge weights per kept bone, keep the 4 strongest.
                newJ = np.zeros((len(pos), 4), np.int64)
                newW = np.zeros((len(pos), 4))
                for v in range(len(pos)):
                    acc: dict[int, float] = {}
                    for k in range(4):
                        if W[v, k] > 0:
                            acc[int(kj[v, k])] = acc.get(int(kj[v, k]), 0.0) + W[v, k]
                    top = sorted(acc.items(), key=lambda x: -x[1])[:4]
                    s = sum(w for _, w in top)
                    for k, (jj, w) in enumerate(top):
                        newJ[v, k] = jj
                        newW[v, k] = w / s
            else:
                m = rig.rest[ni]
                wpos = (np.c_[pos, np.ones(len(pos))] @ m.T)[:, :3]
                wn = nrm @ m[:3, :3].T
                newJ = np.zeros((len(pos), 4), np.int64)
                newJ[:, 0] = KEEP.index(kept_ancestor(rig, ni))
                newW = np.zeros((len(pos), 4))
                newW[:, 0] = 1.0
            wn = wn / np.maximum(np.linalg.norm(wn, axis=1, keepdims=True), 1e-9)
            parts.append({"pos": wpos, "nrm": wn, "uv": uv, "idx": idx, "J": newJ, "W": newW, "mat": mat,
                          "label": label})
    if not parts:
        raise SystemExit(f"{g.path}: no mesh found for skin {rig.skin_index}")
    return parts


def cluster_part(p: dict, cell: float) -> None:
    """Vertex clustering for strand-soup hair that meshoptimizer cannot collapse: snap to a grid,
    merge each cell's vertices, drop collapsed triangles. Crude, but hair reads fine at street range."""
    key = np.floor(p["pos"] / cell).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    counts = np.bincount(inverse).astype(float)
    pos = np.zeros((len(first), 3))
    nrm = np.zeros((len(first), 3))
    np.add.at(pos, inverse, p["pos"])
    np.add.at(nrm, inverse, p["nrm"])
    pos /= counts[:, None]
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    tri = inverse[p["idx"].reshape(-1, 3)]
    ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
    tri = tri[ok]
    p["pos"], p["nrm"] = pos, nrm
    p["uv"], p["J"], p["W"] = p["uv"][first], p["J"][first], p["W"][first]
    p["idx"] = tri.reshape(-1)


# --- Texture atlas ---------------------------------------------------------------------------

def material_image(g: Gltf, mat: dict) -> tuple[Image.Image, bool]:
    """Base colour (texture x factor) as RGBA, and whether it needs alpha testing."""
    if "_image" in mat:  # synthetic palette (process_city paint)
        return mat["_image"].convert("RGBA"), False
    pbr = mat.get("pbrMetallicRoughness", {})
    factor = np.array(pbr.get("baseColorFactor", [1, 1, 1, 1]), float)
    tex = pbr.get("baseColorTexture")
    sg = mat.get("extensions", {}).get("KHR_materials_pbrSpecularGlossiness")
    if sg is not None and tex is None:
        # Older Sketchfab exports: diffuse texture/factor live in the spec-gloss extension.
        factor = np.array(sg.get("diffuseFactor", [1, 1, 1, 1]), float)
        tex = sg.get("diffuseTexture")
    if tex is not None:
        img_i = g.j["textures"][tex["index"]]["source"]
        im = g.j["images"][img_i]
        if "uri" in im:
            img = Image.open(g.path.parent / im["uri"])
        else:
            bv = g.j["bufferViews"][im["bufferView"]]
            import io
            data = g.buffer(bv["buffer"])[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
            img = Image.open(io.BytesIO(data))
        img = img.convert("RGBA")
        img.thumbnail((1024, 1024))
    else:
        img = Image.new("RGBA", (8, 8), (255, 255, 255, 255))
    arr = np.asarray(img).astype(np.float64) / 255.0
    # glTF factors are linear; the texture is sRGB. Multiply in sRGB with the factor converted.
    f_srgb = np.where(factor[:3] <= 0.0031308, factor[:3] * 12.92, 1.055 * np.power(factor[:3], 1 / 2.4) - 0.055)
    arr[..., :3] *= f_srgb
    arr[..., 3] *= factor[3]
    blend = mat.get("alphaMode", "OPAQUE") in ("MASK", "BLEND")
    needs_alpha = blend and bool((arr[..., 3] < 0.5).any())
    if not blend:
        arr[..., 3] = 1.0
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA"), needs_alpha


def tri_area(p: np.ndarray, idx: np.ndarray) -> float:
    t = p[idx.reshape(-1, 3)]
    return float(np.linalg.norm(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]), axis=1).sum() * 0.5)


def build_atlas(g: Gltf, parts: list[dict], size: int = 1024) -> tuple[Image.Image, bool]:
    """Packs one tile per part (power-of-two squares sized by surface share) and rewrites its UVs."""
    keyed: dict[int, list[dict]] = {}
    for p in parts:
        keyed.setdefault((id(p["mat"]), p.get("tile_region", 0)), []).append(p)
    groups = []
    total = sum(tri_area(p["pos"], p["idx"]) for p in parts) or 1.0
    for _, ps in keyed.items():
        img, alpha = material_image(g, ps[0]["mat"])
        uv = np.concatenate([p["uv"] for p in ps])
        # Which unit square the UVs live in: take it from the centre of their range. Flooring the
        # minimum sent a material with a tiny overshoot (u = -0.004) a whole tile off, and every
        # vertex was clamped onto one atlas pixel (the white "Chennai Slum" walls).
        lo = np.floor((uv.min(0) + uv.max(0)) * 0.5)
        span = uv.max(0) - uv.min(0)
        # Only a real repeat counts as tiled. Eyeballs overshoot 0..1 a little on their hidden
        # back (South Indian Women: -0.15..1.15); averaging those wiped out the iris (white eyes).
        tiled = bool((span > 1.5).any())
        share = sum(tri_area(p["pos"], p["idx"]) for p in ps) / total
        # Faces and hands get more texels than their surface share (people_detail.TILE_WEIGHT).
        regions = np.concatenate([p["region"] for p in ps]) if "region" in ps[0] else np.zeros(1, int)
        weight = max([1.0] + [detail.TILE_WEIGHT[int(r)] for r in np.unique(regions) if np.mean(regions == r) > 0.25])
        face = bool(np.mean(regions == detail.REGION_FACE) > 0.25) and ps[0].get("tile_region", 0) != detail.REGION_BODY
        crop = (0.0, 0.0, 1.0, 1.0)
        if not tiled:
            # Only the part of the texture the UVs use goes into the atlas (padded by 1 %).
            local = np.clip(uv - lo, 0.0, 1.0)
            a0 = np.clip(local.min(0) - 0.01, 0.0, 1.0)
            a1 = np.clip(local.max(0) + 0.01, 0.0, 1.0)
            if (a1 - a0).min() > 0.02:
                crop = (float(a0[0]), float(a0[1]), float(a1[0]), float(a1[1]))
                w_, h_ = img.size
                img = img.crop((int(crop[0] * w_), int(crop[1] * h_),
                                max(int(crop[0] * w_) + 1, int(np.ceil(crop[2] * w_))),
                                max(int(crop[1] * h_) + 1, int(np.ceil(crop[3] * h_)))))
        groups.append({"parts": ps, "img": img, "alpha": alpha, "lo": lo, "tiled": tiled,
                       "share": share * weight, "face": face, "crop": crop})
    # Tile side by surface share, then shrink everything until the squares fit the atlas.
    def side(share: float) -> int:
        s = 32
        while s < size // 2 and (s * 2) ** 2 <= share * size * size * 1.6:
            s *= 2
        return s
    total_share = sum(gr["share"] for gr in groups) or 1.0
    for gr in groups:
        gr["share"] /= total_share
        arr = np.asarray(gr["img"].convert("RGB").resize((16, 16))).reshape(-1, 3)
        gr["flat"] = bool(arr.std(0).max() < 3.0)
        if gr["flat"] or gr["tiled"]:
            gr["side"] = 16  # one colour: a 16 px swatch is the same as a 256 px one
        else:
            gr["side"] = max(side(gr["share"]), detail.FACE_TILE_MIN if gr["face"] else 32)
    while sum(gr["side"] ** 2 for gr in groups) > size * size:
        # Shrink the largest tiles first, so the face keeps its resolution.
        big = max(gr["side"] for gr in groups)
        for gr in groups:
            if gr["side"] == big:
                gr["side"] = max(16, gr["side"] // 2)
    # Then fill the free space: double the tile that has the fewest texels for its share, while it
    # fits (power-of-two squares, largest first, always pack when their area fits).
    while True:
        used = sum(gr["side"] ** 2 for gr in groups)
        grow = [gr for gr in groups if not gr["flat"] and not gr["tiled"] and gr["side"] < size // 2
                and used + 3 * gr["side"] ** 2 <= size * size]
        if not grow:
            break
        best = max(grow, key=lambda gr: gr["share"] / gr["side"] ** 2)
        best["side"] *= 2
    # Quadtree packing of power-of-two squares (largest first) always succeeds when area fits.
    free = [(0, 0, size)]
    atlas = Image.new("RGBA", (size, size), (128, 128, 128, 255))
    any_alpha = False
    for gr in sorted(groups, key=lambda x: -x["side"]):
        s = gr["side"]
        free.sort(key=lambda f: (f[2], f[1], f[0]))
        slot = next(f for f in free if f[2] >= s)
        free.remove(slot)
        x, y, fs = slot
        while fs > s:
            fs //= 2
            free += [(x + fs, y, fs), (x, y + fs, fs), (x + fs, y + fs, fs)]
        pad = 2 if s >= 32 else 1
        inner = s - pad * 2
        if gr["tiled"]:
            # Repeating textures cannot live in an atlas: use their average colour.
            avg = tuple(int(c) for c in np.asarray(gr["img"]).reshape(-1, 4).mean(0))
            tile = Image.new("RGBA", (s, s), avg)
        else:
            tile = gr["img"].resize((inner, inner), Image.LANCZOS)
            tile = tile.crop((-pad, -pad, inner + pad, inner + pad))  # transparent border
            arr = np.asarray(tile).copy()
            # Bleed the edge pixels into the padding so mip/filtering never picks up neighbours.
            arr[:pad, :] = arr[pad:pad + 1, :]
            arr[-pad:, :] = arr[-pad - 1:-pad, :]
            arr[:, :pad] = arr[:, pad:pad + 1]
            arr[:, -pad:] = arr[:, -pad - 1:-pad]
            tile = Image.fromarray(arr, "RGBA")
        atlas.paste(tile, (x, y))
        any_alpha = any_alpha or gr["alpha"]
        for p in gr["parts"]:
            p["tile_rect"] = (x / size, y / size, (x + s) / size, (y + s) / size)
            if gr["tiled"]:
                p["uv"] = np.tile([(x + s * 0.5) / size, (y + s * 0.5) / size], (len(p["uv"]), 1))
            else:
                c = gr["crop"]
                local = np.clip(p["uv"] - gr["lo"], 0.0, 1.0)
                local = (local - [c[0], c[1]]) / [max(c[2] - c[0], 1e-6), max(c[3] - c[1], 1e-6)]
                local = np.clip(local, 0.0, 1.0)
                p["uv"] = np.c_[(x + pad + local[:, 0] * inner) / size, (y + pad + local[:, 1] * inner) / size]
    return atlas, any_alpha


# --- Retargeting -----------------------------------------------------------------------------

def bake_clip(target_pose_rest: dict, src: Rig, anim: int, remove_drift: bool) -> dict:
    """Per-frame local rotations for every kept bone + hips translation, in the target skeleton."""
    g = src.g
    dur = g.anim_duration(anim)
    n_frames = max(2, int(round(dur * FPS)) + 1)
    times = np.linspace(0.0, dur, n_frames)
    s_rest = src.pose(src.rest)
    # Alignment: rotate each target bone so it points where the source's rest bone points.
    align = {}
    for b in KEEP:
        dt = aim_dir(target_pose_rest, b)
        ds = aim_dir(s_rest, b)
        if dt is None or ds is None:
            align[b] = align.get(PARENT.get(b, ""), np.eye(3))
        else:
            align[b] = arc(dt, ds)
    src_hips_h = s_rest["Hips"][1][1]
    tgt_hips_h = target_pose_rest["Hips"][1][1]
    k = tgt_hips_h / max(src_hips_h, 1e-6)
    frames_rot = {b: [] for b in KEEP}
    hips_pos = []
    src_hips = []
    for t in times:
        w = g.anim_world(anim, float(t))
        sp = src.pose(w)
        world_rot = {}
        for b in KEEP:
            world_rot[b] = sp[b][0] @ s_rest[b][0].T @ align[b] @ target_pose_rest[b][0]
        for b in KEEP:
            parent = world_rot[PARENT[b]] if b in PARENT else np.eye(3)
            frames_rot[b].append(mat_to_quat(orthonormal(parent.T @ world_rot[b])))
        src_hips.append(sp["Hips"][1])
    src_hips = np.array(src_hips)
    delta = (src_hips - s_rest["Hips"][1]) * k
    speed = 0.0
    if remove_drift:
        drift = (src_hips[-1] - src_hips[0]) * k
        drift[1] = 0.0
        speed = float(np.linalg.norm(drift) / dur)
        delta = delta - np.outer(times / dur, drift)
    # Horizontally the clip is centred on the hips' rest spot (sway kept, offset and drift removed);
    # vertically it keeps the source's dip relative to its rest height.
    delta[:, 0] -= delta[:, 0].mean()
    delta[:, 2] -= delta[:, 2].mean()
    hips_pos = target_pose_rest["Hips"][1] + delta
    # Keep quaternion signs continuous (no flips when Godot interpolates).
    for b in KEEP:
        q = frames_rot[b]
        for i in range(1, len(q)):
            if np.dot(q[i], q[i - 1]) < 0:
                q[i] = -q[i]
    return {"times": times, "rot": frames_rot, "hips": hips_pos, "speed": speed, "duration": dur}


# --- glTF writer -----------------------------------------------------------------------------

class Writer:
    def __init__(self):
        self.bin = bytearray()
        self.views = []
        self.accessors = []

    def add(self, arr: np.ndarray, ctype: int, typ: str, target: int | None = None, minmax: bool = False) -> int:
        dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[ctype]
        data = np.ascontiguousarray(arr, dtype=dt)
        while len(self.bin) % 4:
            self.bin.append(0)
        view = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": data.nbytes}
        if target:
            view["target"] = target
        self.bin += data.tobytes()
        self.views.append(view)
        count = data.shape[0]
        acc = {"bufferView": len(self.views) - 1, "componentType": ctype, "count": count, "type": typ}
        if minmax:
            flat = data.reshape(count, -1)
            acc["min"] = flat.min(0).tolist()
            acc["max"] = flat.max(0).tolist()
        self.accessors.append(acc)
        return len(self.accessors) - 1


def write_character(path: Path, parts: list[dict], atlas_png: Path, alpha: bool, pose_rest: dict,
                    clips: dict) -> None:
    w = Writer()
    pos, nrm, uv, J, W, idx = [], [], [], [], [], []
    base = 0
    for p in parts:
        pos.append(p["pos"])
        nrm.append(p["nrm"])
        uv.append(p["uv"])
        J.append(p["J"])
        W.append(p["W"])
        idx.append(p["idx"] + base)
        base += len(p["pos"])
    pos = np.concatenate(pos)
    nrm = np.concatenate(nrm)
    uv = np.concatenate(uv)
    J = np.concatenate(J)
    W = np.concatenate(W)
    idx = np.concatenate(idx)
    a_pos = w.add(pos, 5126, "VEC3", 34962, True)
    a_nrm = w.add(nrm, 5126, "VEC3", 34962)
    a_uv = w.add(uv, 5126, "VEC2", 34962)
    a_j = w.add(J, 5121, "VEC4", 34962)
    a_w = w.add(W, 5126, "VEC4", 34962)
    a_i = w.add(idx, 5125, "SCALAR", 34963)
    # Joint nodes: node 0 = scene root, 1 = mesh, 2.. = bones in KEEP order.
    nodes = [{"name": "Person", "children": [1, 2]}, {"name": "Body", "mesh": 0, "skin": 0}]
    jn = {b: 2 + i for i, b in enumerate(KEEP)}
    ibms = []
    for b in KEEP:
        r, p = pose_rest[b]
        if b in PARENT:
            pr, pp = pose_rest[PARENT[b]]
            lr = pr.T @ r
            lt = pr.T @ (p - pp)
        else:
            lr, lt = r, p
        node = {"name": b, "rotation": mat_to_quat(lr).tolist(), "translation": lt.tolist()}
        kids = [jn[c] for c, par in PARENT.items() if par == b]
        if kids:
            node["children"] = kids
        nodes.append(node)
        m = np.eye(4)
        m[:3, :3] = r
        m[:3, 3] = p
        ibms.append(np.linalg.inv(m).T.reshape(-1))
    a_ibm = w.add(np.array(ibms), 5126, "MAT4")
    nodes[0]["children"] = [1, jn["Hips"]]
    anims = []
    for name, c in clips.items():
        samplers, channels = [], []
        a_t = w.add(c["times"].reshape(-1, 1), 5126, "SCALAR", None, True)
        for b in KEEP:
            a_r = w.add(np.array(c["rot"][b]), 5126, "VEC4")
            samplers.append({"input": a_t, "output": a_r, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": jn[b], "path": "rotation"}})
        a_h = w.add(np.array(c["hips"]), 5126, "VEC3")
        samplers.append({"input": a_t, "output": a_h, "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": jn["Hips"], "path": "translation"}})
        anims.append({"name": name, "samplers": samplers, "channels": channels})
    mat = {"name": "person", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
                                                      "roughnessFactor": 0.85}}
    if alpha:
        mat["alphaMode"] = "MASK"
        mat["alphaCutoff"] = 0.5
        mat["doubleSided"] = True
    doc = {
        "asset": {"version": "2.0", "generator": "namma-auto process_people.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes,
        "meshes": [{"name": "Body", "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm,
                                                                    "TEXCOORD_0": a_uv, "JOINTS_0": a_j,
                                                                    "WEIGHTS_0": a_w},
                                                     "indices": a_i, "material": 0}]}],
        "skins": [{"joints": [jn[b] for b in KEEP], "inverseBindMatrices": a_ibm, "skeleton": jn["Hips"]}],
        "materials": [mat], "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"uri": atlas_png.name}],
        "animations": anims,
        "buffers": [{"uri": path.with_suffix(".bin").name, "byteLength": len(w.bin)}],
        "bufferViews": w.views, "accessors": w.accessors,
    }
    path.with_suffix(".bin").write_bytes(bytes(w.bin))
    path.write_text(json.dumps(doc))


def run(args: list) -> None:
    r = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"{' '.join(map(str, args))}\n{r.stdout}\n{r.stderr}")


def triangles(path: Path) -> int:
    d = path.read_bytes()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    return sum(j["accessors"][p["indices"]]["count"] // 3 for m in j["meshes"] for p in m["primitives"])


def main() -> int:
    only = set(sys.argv[1:])
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    meta = {}
    meta_path = OUT / "people.json"
    if meta_path.exists():
        meta = json.loads(meta_path.read_text()).get("people", {})
    sources = {}
    fallback_speed = 0.0
    for clip, (folder, anim) in CLIPS.items():
        path = SRC / folder / "scene.gltf"
        if path.exists():
            g = Gltf(path)
            rig = Rig(g, 0, None)
            rig.fit_skeleton_only()
            sources[clip] = (rig, anim)
        else:
            g = Gltf(FALLBACK_CLIP_GLB)
            names = [a.get("name", "") for a in g.j.get("animations", [])]
            rig = Rig(g, 0, None)
            rig.fit_skeleton_only()
            sources[clip] = (rig, names.index(clip))
            fallback_speed = float(meta.get(FALLBACK_CLIP_ID, {}).get("walk_speed", 1.3))
            print(f"     clip '{clip}': raw {folder} missing, using {FALLBACK_CLIP_GLB.name}")
    credits = []
    for spec in PEOPLE:
        pid, folder, height, budget, skin_i, credit = spec[:6]
        recolour: dict = spec[6] if len(spec) > 6 else {}
        opts: dict = spec[7] if len(spec) > 7 else {}
        credits.append(f"| `assets/models/people/{pid}.glb` | {folder} | {credit} |")
        if only and pid not in only:
            continue
        g = Gltf(SRC / folder / "scene.gltf")
        for mat in g.j.get("materials", []):
            if mat.get("name") in recolour:
                mat.setdefault("pbrMetallicRoughness", {})["baseColorFactor"] = recolour[mat["name"]]
        if opts.get("solid_hair"):
            # Strand-soup hair with alpha strands breaks into black shards once simplified: draw it
            # as a solid mass instead.
            for mat in g.j.get("materials", []):
                if any(w in mat.get("name", "").lower() for w in detail.HAIR_WORDS):
                    mat["alphaMode"] = "OPAQUE"
        if "rig_from" in opts:
            # No skeleton in the download: borrow the bones and skin weights of a rigged model.
            import rig_static
            ref_spec = next(sp for sp in PEOPLE if sp[1] == opts["rig_from"])
            ref = Rig(Gltf(SRC / opts["rig_from"] / "scene.gltf"), ref_spec[4], height)
            ref_parts = extract_mesh(ref)
            ref.fit(np.concatenate([p["pos"] for p in ref_parts]))
            for p in ref_parts:
                p["pos"] = np.array([ref.norm_point(v) for v in p["pos"]])
            parts, pose_rest = rig_static.rig_static(g, height, ref_parts, ref.pose(ref.rest), KEEP, PARENT,
                                                     DROP_PARTS, opts)
        else:
            rig = Rig(g, skin_i, height)
            parts = extract_mesh(rig)
            rig.fit(np.concatenate([p["pos"] for p in parts]))
            for p in parts:
                p["pos"] = np.array([rig.norm_point(v) for v in p["pos"]])
                p["nrm"] = p["nrm"] @ rig.turn.T
            pose_rest = rig.pose(rig.rest)
        for p in parts:
            if "hair" in p["label"] and len(p["idx"]) // 3 > 60000:
                before = len(p["idx"]) // 3
                cluster_part(p, 0.04)
                print(f"     {pid}: hair {before} -> {len(p['idx']) // 3} tris (clustered)")
            p["region"] = detail.vertex_regions(p, KEEP)
        parts = detail.split_by_region(parts)
        atlas, alpha = build_atlas(g, parts)
        # Where the garment PaintSwap recolours ended up in the atlas, and its colour there.
        paint = {}
        if opts.get("paint"):
            rects = [p["tile_rect"] for p in parts if p["mat"].get("name") in opts["paint"]]
            # The garment's main tile (a few of its triangles may sit in a face / hands tile).
            r = list(max(rects, key=lambda t: (t[2] - t[0]) * (t[3] - t[1])))
            crop = np.asarray(atlas.convert("RGB").crop((int(r[0] * 1024), int(r[1] * 1024),
                                                         int(r[2] * 1024), int(r[3] * 1024))))
            paint = {"rect": [round(v, 4) for v in r],
                     "colour": [int(c) for c in np.median(crop.reshape(-1, 3), axis=0)]}
            print(f"     {pid}: paint {paint}")
        atlas_png = WORK / f"{pid}_atlas.png"
        atlas.save(atlas_png)
        clips = {}
        for clip, (src, anim) in sources.items():
            clips[clip] = bake_clip(pose_rest, src, anim, clip == "walk")
            if clip == "walk" and clips[clip]["speed"] < 0.05 and fallback_speed > 0.0:
                # In-place source: scale its known pace by leg length (hips height ratio).
                k = pose_rest["Hips"][1][1] / max(src.pose(src.rest)["Hips"][1][1], 1e-6)
                clips[clip]["speed"] = fallback_speed * k
        raw = WORK / f"{pid}.gltf"
        tris_in = sum(len(p["idx"]) // 3 for p in parts)
        # Merge, then simplify region by region: the body and hair to `budget`, the face and the
        # hands to their own budgets (people_detail), so faces and fingers never collapse.
        cat = lambda k: np.concatenate([p[k] for p in parts])  # noqa: E731
        offs = np.cumsum([0] + [len(p["pos"]) for p in parts[:-1]])
        idx_all = np.concatenate([p["idx"] + o for p, o in zip(parts, offs)])
        pos, nrm, uv, J, W, reg, idx_all = detail.simplify_by_region(
            cat("pos"), cat("nrm"), cat("uv"), cat("J"), cat("W"), cat("region"), idx_all, budget)
        counts = detail.region_counts(reg, idx_all)
        merged = [{"pos": pos, "nrm": nrm, "uv": uv, "J": J, "W": W, "idx": idx_all}]
        write_character(raw, merged, atlas_png, alpha, pose_rest, clips)
        dest = OUT / f"{pid}.glb"
        # The atlas stays 1024 px (it was halved to 512, which left a face about 64 px wide).
        run([GLTF, "prune", raw, dest])
        print(f"     {pid}: regions {counts}")
        speed = clips["walk"]["speed"]
        meta[pid] = {"walk_speed": round(speed, 3), "walk_seconds": round(clips["walk"]["duration"], 3),
                     "height": height, "credit": credit}
        if paint:
            meta[pid]["paint"] = paint
        print(f"OK   {pid}: {tris_in} -> {triangles(dest)} tris, {dest.stat().st_size // 1024} KB, "
              f"walk {speed:.2f} m/s, alpha={alpha}")
    meta_path.write_text(json.dumps({"_note": "made by tools/assets/process_people.py — walk_speed is the "
                                     "in-place walk's true pace in m/s at speed_scale 1",
                                     "people": meta}, indent=1, sort_keys=True))
    # Only shipped files get a row; rows this script does not own (Mixamo, quest riders) and the
    # notes under the table are kept as they are.
    ids = {sp[0] for sp in PEOPLE}
    old = (OUT / "CREDITS_people.md").read_text().splitlines() if (OUT / "CREDITS_people.md").exists() else []
    keep_rows = [ln for ln in old if ln.startswith("| `") and Path(ln.split("`")[1]).stem not in ids]
    tail = []
    for i, ln in enumerate(old):
        if i > 0 and not ln.startswith("|") and any(o.startswith("|") for o in old[:i]):
            tail = old[i:]
            break
    rows = [c for c in credits if (ROOT / c.split("`")[1]).exists()] + keep_rows
    (OUT / "CREDITS_people.md").write_text("# People (made by tools/assets/process_people.py)\n\n"
                                          "| File | Source | Licence |\n|---|---|---|\n" + "\n".join(rows) + "\n"
                                          + ("\n".join(tail) + "\n" if tail else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
