#!/usr/bin/env python3
"""Adds the owner's skinned Mixamo character (Walk.fbx) as one more pedestrian: assets/models/people/mixamo_ch22.glb.

The raw FBX (gitignored, assets_src/incoming/models/mixamo/Walk.fbx) is a complete Mixamo character
("Ch22": six mesh parts, each with its own skin, 65 Mixamo bones, ~27k triangles, 64 MB of PNGs).
This runs the same pipeline as tools/assets/process_people.py — 22-bone rig, one texture atlas, one
primitive, gltf-transform weld / simplify / resize — but first merges every part's skin onto the main
skeleton, and budgets the result like the other pedestrians (~4k triangles, 512 px atlas).

Walk comes from the character's own walk cycle; idle comes from the young-man model's idle (the same
fallback process_people uses). The reaction and gesture clips are added afterwards by
tools/assets/add_mixamo_clips.py, which also writes this character's run_speed and moves.

Usage: FBX2GLTF=/path/to/FBX2glTF python3 tools/assets/add_mixamo_character.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from add_mixamo_clips import write_glb  # noqa: E402
from gltf_rig import Gltf  # noqa: E402
from process_people import (FALLBACK_CLIP_GLB, GLTF, OUT, WORK, Rig, bake_clip, build_atlas,  # noqa: E402
                            cluster_part, extract_mesh, run, triangles, write_character)

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets_src" / "incoming" / "models" / "mixamo"
PID = "mixamo_ch22"
HEIGHT = 1.72
BUDGET = 4000  # triangles, same range as the other pedestrians
CREDIT = ('Mixamo character "Ch22" (Adobe Mixamo) — used under the Mixamo terms, royalty-free in games; '
          'the raw FBX is not redistributed')


def walk_source() -> Path:
    fbx = RAW / "Walk.fbx"
    glb = RAW / "Walk.glb"
    if not glb.exists() or glb.stat().st_mtime < fbx.stat().st_mtime:
        conv = os.environ.get("FBX2GLTF", "FBX2glTF")
        subprocess.run([conv, "-b", "-i", str(fbx), "-o", str(RAW / "Walk")], check=True, capture_output=True)
    return glb


def anim_index(g: Gltf, name: str) -> int:
    for i, a in enumerate(g.j.get("animations", [])):
        if a.get("name") == name:
            return i
    raise SystemExit(f"no animation named {name!r}")


def unify_skins(src: Path, dst: Path, main_skin: int) -> None:
    """Every mesh part in this file has its own skin with a subset of the one skeleton. Rebind each
    part to the main skin: JOINTS_0 is remapped from the part's local joint list to the main list
    (same bone nodes, so the bind poses agree), and the node points at the main skin."""
    g = Gltf(src)
    doc = g.j
    binary = bytearray(g.glb_bin or b"")
    main_joints = doc["skins"][main_skin]["joints"]
    main_pos = {n: i for i, n in enumerate(main_joints)}
    done: set = set()
    for si, skin in enumerate(doc["skins"]):
        if si == main_skin:
            continue
        lut = np.zeros(len(skin["joints"]), dtype=np.int64)
        for k, node_id in enumerate(skin["joints"]):
            if node_id not in main_pos:
                raise SystemExit(f"skin {si} uses a bone that is not on the main skeleton")
            lut[k] = main_pos[node_id]
        for node in doc["nodes"]:
            if node.get("skin") != si or "mesh" not in node:
                continue
            node["skin"] = main_skin
            mesh = doc["meshes"][node["mesh"]]
            if node["mesh"] in done:
                continue
            done.add(node["mesh"])
            for prim in mesh["primitives"]:
                joints = g.accessor(prim["attributes"]["JOINTS_0"]).astype(np.int64)
                data = np.ascontiguousarray(lut[joints].astype(np.uint8))
                while len(binary) % 4:
                    binary.append(0)
                doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": data.nbytes})
                binary.extend(data.tobytes())
                doc["accessors"].append({"bufferView": len(doc["bufferViews"]) - 1, "componentType": 5121,
                                         "count": int(data.shape[0]), "type": "VEC4"})
                prim["attributes"]["JOINTS_0"] = len(doc["accessors"]) - 1
    if "inverseBindMatrices" not in doc["skins"][main_skin]:
        # The main skin ships without inverse bind matrices, which glTF treats as identity: the
        # skeleton would then be applied twice. Its bind pose is the rest pose, so use the inverse of
        # each joint's rest transform (the other skins of this file store exactly that).
        rest = g.rest_world()
        ibm = np.array([np.linalg.inv(rest[n]).T.astype(np.float32) for n in main_joints])
        while len(binary) % 4:
            binary.append(0)
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": ibm.nbytes})
        binary.extend(np.ascontiguousarray(ibm).tobytes())
        doc["accessors"].append({"bufferView": len(doc["bufferViews"]) - 1, "componentType": 5126,
                                 "count": len(main_joints), "type": "MAT4"})
        doc["skins"][main_skin]["inverseBindMatrices"] = len(doc["accessors"]) - 1
    doc["buffers"][0]["byteLength"] = len(binary)
    write_glb(dst, doc, bytes(binary))


def main() -> int:
    WORK.mkdir(parents=True, exist_ok=True)
    src = Gltf(walk_source())
    # The walk clip lives under "mixamo.com"; "Take 001" in the same file is an empty stub.
    walk_anim = anim_index(src, "mixamo.com")
    # The skin with the full 65-bone skeleton is the main one.
    skin_sizes = [len(s["joints"]) for s in src.j["skins"]]
    main_skin = max(range(len(skin_sizes)), key=lambda i: skin_sizes[i])
    unified = WORK / f"{PID}_unified.glb"
    unify_skins(src.path, unified, main_skin)
    g = Gltf(unified)
    rig = Rig(g, main_skin, HEIGHT)
    parts = extract_mesh(rig)
    print(f"     {PID}: {len(parts)} mesh parts on one {len(rig.joints)}-bone skin")
    rig.fit(np.concatenate([p["pos"] for p in parts]))
    for p in parts:
        p["pos"] = np.array([rig.norm_point(v) for v in p["pos"]])
        p["nrm"] = p["nrm"] @ rig.turn.T
        if "hair" in p["label"] and len(p["idx"]) // 3 > 60000:
            cluster_part(p, 0.04)
    pose_rest = rig.pose(rig.rest)
    atlas, alpha = build_atlas(g, parts)
    atlas_png = WORK / f"{PID}_atlas.png"
    atlas.save(atlas_png)

    walk_rig = Rig(g, main_skin, None)
    walk_rig.fit_skeleton_only()
    clips = {"walk": bake_clip(pose_rest, walk_rig, walk_anim, True)}
    fallback = Gltf(FALLBACK_CLIP_GLB)
    idle_rig = Rig(fallback, 0, None)
    idle_rig.fit_skeleton_only()
    clips["idle"] = bake_clip(pose_rest, idle_rig, [a.get("name") for a in fallback.j["animations"]].index("idle"), False)

    raw = WORK / f"{PID}.gltf"
    write_character(raw, parts, atlas_png, alpha, pose_rest, clips)
    welded = WORK / f"{PID}_weld.glb"
    dest = OUT / f"{PID}.glb"
    tmp = WORK / f"{PID}_w.glb"
    tris_in = sum(len(p["idx"]) // 3 for p in parts)
    ratio = min(1.0, BUDGET / max(tris_in, 1))
    run([GLTF, "weld", raw, welded])
    for err in ("0.02", "0.05", "0.1", "0.2"):
        run([GLTF, "simplify", welded, tmp, "--ratio", f"{ratio:.4f}", "--error", err, "--lock-border", "false"])
        if triangles(tmp) <= BUDGET * 1.15:
            break
    run([GLTF, "resize", tmp, tmp, "--width", 512, "--height", 512])
    run([GLTF, "prune", tmp, dest])

    meta_path = OUT / "people.json"
    meta = json.loads(meta_path.read_text())
    meta["people"][PID] = {"walk_speed": round(clips["walk"]["speed"], 3),
                           "walk_seconds": round(clips["walk"]["duration"], 3),
                           "height": HEIGHT, "credit": CREDIT}
    meta_path.write_text(json.dumps(meta, indent=1, sort_keys=True))
    print(f"OK   {PID}: {tris_in} -> {triangles(dest)} tris, {dest.stat().st_size // 1024} KB, "
          f"walk {clips['walk']['speed']:.2f} m/s, alpha={alpha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
