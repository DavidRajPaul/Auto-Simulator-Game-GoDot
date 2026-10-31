#!/usr/bin/env python3
"""Bakes the owner's hero (assets/models/hero/namma_auto_hero.glb) into a static SEATED driver.

The hero file is a 78-joint skinned character in 33 mesh parts (= 33 draw calls), standing,
~1 m tall in file units, with walk/run/jump clips and no sitting pose. For the first release the
driver never leaves the auto, so the game needs him seated at the handlebar, once, cheaply:

  1. evaluate the rig at rest, then pose it in world space: hips flexed, knees bent, feet on the
     floor board, arms forward to the handlebar, a slight forward lean;
  2. linear-blend skin all 33 parts into that pose and merge them into ONE primitive with the
     hero's own texture (one material -> one draw call);
  3. scale to SEATED_HIP_TO_HEAD real metres, put the origin at the hip joint (the seat point),
     face +Z like every glTF in the project (AutoRickshawModel turns it to -Z);
  4. weld + seam-safe simplify to TRI_BUDGET.

Output: assets/models/hero/namma_auto_hero_seated.glb (+ report). The animated original stays
for the on-foot mode planned for a later release.
Usage: python3 tools/assets/bake_seated_hero.py
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
from gltf_rig import Gltf, arc  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "models" / "hero" / "namma_auto_hero.glb"
OUT = ROOT / "assets" / "models" / "hero" / "namma_auto_hero_seated.glb"
TMP = ROOT / "assets_src" / "incoming" / "models" / "_hero_seated_tmp.glb"
STANDING_HEIGHT_M = 1.70
TRI_BUDGET = 7000

# World-space bone directions for the seated pose (character faces +Z, +X is his left).
# Each entry: bone -> (child bone that marks its tip, target direction). Applied parent-first.
POSE = [
    ("Spine01", "Spine02", np.array([0.0, 1.0, 0.12])),        # slight forward lean
    ("L_Thigh", "L_Calf", np.array([0.10, -0.12, 1.0])),       # thighs forward along the bench
    ("R_Thigh", "R_Calf", np.array([-0.10, -0.12, 1.0])),
    ("L_Calf", "L_Foot", np.array([0.02, -1.0, 0.18])),        # shins down to the floor board
    ("R_Calf", "R_Foot", np.array([-0.02, -1.0, 0.18])),
    ("L_Upperarm", "L_Forearm", np.array([0.25, -0.6, 0.75])),  # arms forward and down
    ("R_Upperarm", "R_Forearm", np.array([-0.25, -0.6, 0.75])),
    ("L_Forearm", "L_Hand", np.array([0.0, -0.05, 1.0])),      # forearms level to the grips
    ("R_Forearm", "R_Hand", np.array([0.0, -0.05, 1.0])),
]


def _descendants(g: Gltf, i: int) -> list[int]:
    out = [i]
    for c in g.nodes[i].get("children", []):
        out += _descendants(g, c)
    return out


def posed_world(g: Gltf) -> list[np.ndarray]:
    world = [m.copy() for m in g.rest_world()]
    by_name = {n.get("name"): i for i, n in enumerate(g.nodes)}
    for bone, tip, target in POSE:
        b, t = by_name[bone], by_name[tip]
        head = world[b][:3, 3].copy()
        cur = world[t][:3, 3] - head
        r = arc(cur, target)
        rot = np.eye(4)
        rot[:3, :3] = r
        pivot = np.eye(4)
        pivot[:3, 3] = head
        unpivot = np.eye(4)
        unpivot[:3, 3] = -head
        m = pivot @ rot @ unpivot
        for d in _descendants(g, b):
            world[d] = m @ world[d]
    return world


def skin(g: Gltf, world: list[np.ndarray]) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    sk = g.j["skins"][0]
    joints = sk["joints"]
    ibm = g.accessor(sk["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    joint_m = np.array([world[j] @ ibm[k] for k, j in enumerate(joints)])
    pos_all, nrm_all, uv_all, idx_all = [], [], [], []
    base = 0
    for node in g.nodes:
        if "mesh" not in node:
            continue
        for prim in g.j["meshes"][node["mesh"]]["primitives"]:
            a = prim["attributes"]
            p = g.accessor(a["POSITION"])
            n = g.accessor(a["NORMAL"]) if "NORMAL" in a else np.zeros_like(p)
            uv = g.accessor(a["TEXCOORD_0"])
            jt = g.accessor(a["JOINTS_0"]).astype(int)
            wt = g.accessor(a["WEIGHTS_0"])
            wt = wt / np.maximum(wt.sum(1, keepdims=True), 1e-8)
            m = np.einsum("vk,vkij->vij", wt, joint_m[jt])
            ph = np.concatenate([p, np.ones((len(p), 1))], 1)
            pos_all.append(np.einsum("vij,vj->vi", m, ph)[:, :3])
            nn = np.einsum("vij,vj->vi", m[:, :3, :3], n)
            nrm_all.append(nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-8))
            uv_all.append(uv)
            idx = g.accessor(prim["indices"]).astype(int).reshape(-1)
            idx_all.append(idx + base)
            base += len(p)
    return np.concatenate(pos_all), np.concatenate(nrm_all), np.concatenate(uv_all), np.concatenate(idx_all)


def texture(g: Gltf) -> Image.Image:
    img = g.j["images"][0]
    bv = g.j["bufferViews"][img["bufferView"]]
    data = g.buffer(bv["buffer"])[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
    import io
    return Image.open(io.BytesIO(data)).convert("RGB")


def main() -> int:
    g = Gltf(SRC)
    rest = g.rest_world()
    by_name = {n.get("name"): i for i, n in enumerate(g.nodes)}
    # Standing height from the rest skin -> metres.
    p_rest, _, _, _ = skin(g, rest)
    scale = STANDING_HEIGHT_M / (p_rest[:, 1].max() - p_rest[:, 1].min())
    world = posed_world(g)
    pos, nrm, uv, idx = skin(g, world)
    hip = world[by_name["Hip"]][:3, 3]
    pos = (pos - hip) * scale
    tex = texture(g)
    # trimesh stores glTF UVs with v flipped; give it its convention so the export round-trips.
    uv_t = np.column_stack([uv[:, 0], 1.0 - uv[:, 1]])
    mat = trimesh.visual.material.PBRMaterial(baseColorTexture=tex, metallicFactor=0.0, roughnessFactor=0.8)
    mesh = trimesh.Trimesh(vertices=pos, faces=idx.reshape(-1, 3), vertex_normals=nrm, process=False,
                           visual=trimesh.visual.TextureVisuals(uv=uv_t, material=mat))
    TMP.parent.mkdir(parents=True, exist_ok=True)
    mesh.export(TMP)
    subprocess.run(["node", str(ROOT / "tools" / "assets" / "seam_safe_simplify.mjs"), str(TMP), str(OUT), str(TRI_BUDGET)],
                   check=True)
    TMP.unlink()
    out = trimesh.util.concatenate(trimesh.load(OUT, force="scene").dump())
    lo, hi = out.bounds
    report = {"file": OUT.relative_to(ROOT).as_posix(), "triangles": int(len(out.faces)),
              "bounds_min": np.round(lo, 3).tolist(), "bounds_max": np.round(hi, 3).tolist(),
              "scale_from_file": round(float(scale), 4), "feet_below_hip_m": round(float(-lo[1]), 3)}
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
