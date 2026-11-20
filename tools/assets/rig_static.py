"""Rigs a person who arrives as a static mesh (no skin), for process_people.py.

"Wife Final" (svgmishra95, CC BY 4.0) is a saree woman with no skeleton. She stands in an A-pose
like "Female test", which is rigged and also wears a saree, so she borrows its bones and its
artist-painted skin weights:

  1. Her mesh is turned to face +Z (from where her pupils sit on the head), scaled to `height`
     with the feet on y = 0, hips over the origin.
  2. The reference skeleton is re-posed so each arm points at her fingertips (one rotation and
     one stretch per arm chain, about the shoulder), and its mesh is skinned into that pose.
  3. Every one of her vertices takes the blended weights of the nearest reference skin/outfit
     vertices (hair left out, so the bun doesn't follow a shoulder), smoothed over her mesh.
Returns parts in the same shape extract_mesh() gives, plus the re-posed rest pose.
"""
from __future__ import annotations

import numpy as np
from scipy.spatial import cKDTree

from gltf_rig import arc

ARM = ("Arm", "ForeArm", "Hand", "HandMiddle1")


def _target_parts(g, drop: tuple[str, ...]) -> list[dict]:
    rest = g.rest_world()
    parts = []
    for ni, node in enumerate(g.nodes):
        if "mesh" not in node:
            continue
        mesh = g.j["meshes"][node["mesh"]]
        for prim in mesh["primitives"]:
            mat_i = prim.get("material")
            mat = g.j["materials"][mat_i] if mat_i is not None else {}
            label = (mesh.get("name", "") + " " + mat.get("name", "")).lower()
            if any(k in label for k in drop) or prim.get("mode", 4) != 4:
                continue
            a = prim["attributes"]
            pos = g.accessor(a["POSITION"])
            nrm = g.accessor(a["NORMAL"]) if "NORMAL" in a else np.tile([0.0, 1.0, 0.0], (len(pos), 1))
            uv = g.accessor(a["TEXCOORD_0"]) if "TEXCOORD_0" in a else np.zeros((len(pos), 2))
            idx = g.accessor(prim["indices"])[:, 0].astype(np.int64) if "indices" in prim else np.arange(len(pos))
            m = rest[ni]
            wpos = (np.c_[pos, np.ones(len(pos))] @ m.T)[:, :3]
            wn = nrm @ m[:3, :3].T
            wn /= np.maximum(np.linalg.norm(wn, axis=1, keepdims=True), 1e-9)
            parts.append({"pos": wpos, "nrm": wn, "uv": uv, "idx": idx, "mat": mat, "label": label})
    return parts


def _yaw(a: float) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rig_static(g, height: float, ref_parts: list[dict], ref_pose: dict, keep: list[str],
               parent: dict, drop: tuple[str, ...], opts: dict):
    parts = _target_parts(g, drop)
    allp = np.concatenate([p["pos"] for p in parts])
    # Facing: pupils (or eyes) sit in front of the head's centre.
    top = allp[:, 1].max()
    h = top - allp[:, 1].min()
    head = allp[allp[:, 1] > top - h * 0.12]
    eyes = [p for p in parts if any(w in p["label"] for w in ("pupil", "eye", "iris"))]
    fwd = (np.concatenate([p["pos"] for p in eyes]).mean(0) - head.mean(0)) if eyes else np.array([0, 0, 1.0])
    fwd[1] = 0.0
    turn = _yaw(np.arctan2(fwd[0], fwd[2])).T if np.linalg.norm(fwd) > 1e-9 else np.eye(3)
    scale = height / h
    v = allp @ turn.T
    band = v[(v[:, 1] > v[:, 1].min() + h * 0.48) & (v[:, 1] < v[:, 1].min() + h * 0.55)]
    off = -np.array([band[:, 0].mean() * scale, v[:, 1].min() * scale, band[:, 2].mean() * scale])
    for p in parts:
        p["pos"] = (p["pos"] @ turn.T) * scale + off
        p["nrm"] = p["nrm"] @ turn.T
    allp = np.concatenate([p["pos"] for p in parts])

    # Reference: dense weights per vertex, hair left out.
    ref_body = [p for p in ref_parts if "hair" not in p["label"]]
    rpos = np.concatenate([p["pos"] for p in ref_body])
    rW = np.zeros((len(rpos), len(keep)))
    o = 0
    for p in ref_body:
        for k in range(4):
            np.add.at(rW, (np.arange(o, o + len(p["pos"])), p["J"][:, k]), p["W"][:, k])
        o += len(p["pos"])

    # Re-pose each reference arm to point at the target's fingertips.
    pose = {b: (r.copy(), q.copy()) for b, (r, q) in ref_pose.items()}
    moved = rpos.copy()
    for side in ("Left", "Right"):
        sh = ref_pose[f"{side}Arm"][1]
        sx = np.sign(ref_pose[f"{side}Hand"][1][0] - ref_pose["Hips"][1][0])
        hand_j = keep.index(f"{side}Hand")
        rtip = rpos[rW[:, hand_j] > 0.5]
        rtip = rtip[np.argmax(np.linalg.norm(rtip - sh, axis=1))]
        cand = allp[np.sign(allp[:, 0]) == sx]
        ttip = cand[np.argmax(np.abs(cand[:, 0]))]
        R = arc(rtip - sh, ttip - sh)
        s = np.linalg.norm(ttip - sh) / max(np.linalg.norm(rtip - sh), 1e-6)
        for b in ARM:
            name = f"{side}{b}"
            if name in pose:
                r, q = pose[name]
                pose[name] = (R @ r, sh + s * (R @ (q - sh)))
        chain = [keep.index(f"{side}{b}") for b in ARM if f"{side}{b}" in keep]
        wa = rW[:, chain].sum(1, keepdims=True)
        moved = moved * (1 - wa) + (sh + s * ((rpos - sh) @ R.T)) * wa

    # Nearest-vertex weight transfer, then smoothing over the target's own connectivity.
    tree = cKDTree(moved)
    d, nn = tree.query(allp, k=8)
    w = 1.0 / np.maximum(d, 1e-5) ** 2
    dense = (rW[nn] * w[..., None]).sum(1) / w.sum(1, keepdims=True)
    key = np.round(allp, 5)
    _, weld_ix = np.unique(key, axis=0, return_inverse=True)
    weld_ix = weld_ix.reshape(-1)
    edges = []
    o = 0
    for p in parts:
        t = p["idx"].reshape(-1, 3) + o
        edges += [t[:, [0, 1]], t[:, [1, 2]], t[:, [2, 0]]]
        o += len(p["pos"])
    e = weld_ix[np.concatenate(edges)]
    nw = weld_ix.max() + 1
    for _ in range(3):
        acc = np.zeros((nw, len(keep)))
        np.add.at(acc, weld_ix, dense)
        cnt = np.bincount(weld_ix, minlength=nw)[:, None].astype(float)
        acc /= np.maximum(cnt, 1)
        nb = np.zeros_like(acc)
        np.add.at(nb, e[:, 0], acc[e[:, 1]])
        np.add.at(nb, e[:, 1], acc[e[:, 0]])
        deg = np.bincount(np.r_[e[:, 0], e[:, 1]], minlength=nw)[:, None].astype(float)
        acc = 0.5 * acc + 0.5 * nb / np.maximum(deg, 1)
        dense = acc[weld_ix]
    order = np.argsort(-dense, axis=1)[:, :4]
    top4 = np.take_along_axis(dense, order, axis=1)
    top4 /= np.maximum(top4.sum(1, keepdims=True), 1e-9)
    o = 0
    for p in parts:
        n = len(p["pos"])
        p["J"] = order[o:o + n].astype(np.int64)
        p["W"] = top4[o:o + n]
        o += n
    return parts, pose
