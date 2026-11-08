#!/usr/bin/env python3
"""Adds the owner's Mixamo clips to every shipped pedestrian (assets/models/people/*.glb).

Raw FBX downloads (FBX Binary, 30 fps, any Mixamo character) live in
assets_src/incoming/models/mixamo/ (gitignored: Mixamo's terms allow the clips inside the game,
not redistributing the raw files). Each FBX is converted with FBX2glTF (set FBX2GLTF=/path/to/bin,
from github.com/godotengine/FBX2glTF releases), then retargeted onto the 22-bone people rig with
process_people.bake_clip — the same rest-pose alignment the walk and idle got — and appended as a
new animation to each character GLB (re-running replaces clips of the same name).

Clips (CLIPS below):
  run      Running            in place (forward root motion removed, its pace → people.json run_speed)
  dodge    Dodging_Back       root motion kept: the person steps back ~2 m; the game moves the node
                              by the clip's end offset (people.json "moves") when it finishes
  stumble  Stumble_Backwards  root motion kept, ends lying on the road
  fallen   Fallen_Idle        lying on the ground, loops

Usage: FBX2GLTF=… python3 tools/assets/add_mixamo_clips.py [raw_folder]
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_rig import Gltf, mat_to_quat, orthonormal  # noqa: E402
from process_people import FPS, KEEP, PARENT, Rig, aim_dir, arc  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets_src" / "incoming" / "models" / "mixamo"
PEOPLE = ROOT / "assets" / "models" / "people"
META = PEOPLE / "people.json"

# name: (FBX file stem, mode) — mode "inplace" removes forward drift, "root" keeps it.
CLIPS = {
    "run": ("Running", "inplace"),
    "dodge": ("Dodging_Back", "root"),
    "stumble": ("Stumble_Backwards", "root"),
    "fallen": ("Fallen_Idle", "root"),
    # Gestures and getting up. Slow, in-place poses are baked at 15 fps (half the keys, same look).
    "get_up": ("Getting_Up", "inplace"),
    "wave": ("Waving_3", "inplace", 15),
    "talk": ("Talking", "inplace", 15),
    "drink": ("Drinking", "inplace", 15),
    # Fleeing from a burning auto: a frightened run, and a run that looks back over the shoulder.
    "flee_look": ("Run_Look_Back", "inplace", 30),
}


def bake(target: dict, src: Rig, mode: str, fps: int = FPS) -> dict:
    """process_people.bake_clip, plus a "root" mode that keeps the hips' travel from frame 0."""
    g = src.g
    dur = g.anim_duration(0)
    n = max(2, int(round(dur * fps)) + 1)
    times = np.linspace(0.0, dur, n)
    s_rest = src.pose(src.rest)
    align = {}
    for b in KEEP:
        dt, ds = aim_dir(target, b), aim_dir(s_rest, b)
        align[b] = align.get(PARENT.get(b, ""), np.eye(3)) if dt is None or ds is None else arc(dt, ds)
    k = target["Hips"][1][1] / max(s_rest["Hips"][1][1], 1e-6)
    rot = {b: [] for b in KEEP}
    hips = []
    for t in times:
        sp = src.pose(g.anim_world(0, float(t)))
        world = {b: sp[b][0] @ s_rest[b][0].T @ align[b] @ target[b][0] for b in KEEP}
        for b in KEEP:
            parent = world[PARENT[b]] if b in PARENT else np.eye(3)
            rot[b].append(mat_to_quat(orthonormal(parent.T @ world[b])))
        hips.append(sp["Hips"][1])
    hips = np.array(hips)
    delta = (hips - s_rest["Hips"][1]) * k
    move = np.zeros(3)
    speed = 0.0
    if mode == "inplace":
        drift = delta[-1] - delta[0]
        drift[1] = 0.0
        speed = float(np.linalg.norm(drift) / dur)
        delta = delta - np.outer(times / dur, drift)
        delta[:, 0] -= delta[:, 0].mean()
        delta[:, 2] -= delta[:, 2].mean()
    else:
        delta[:, 0] -= delta[0, 0]
        delta[:, 2] -= delta[0, 2]
        move = delta[-1].copy()
        move[1] = 0.0
    for b in KEEP:
        q = rot[b]
        for i in range(1, len(q)):
            if np.dot(q[i], q[i - 1]) < 0:
                q[i] = -q[i]
    return {"times": times, "rot": rot, "hips": target["Hips"][1] + delta, "speed": speed,
            "move": move, "duration": dur}


def write_glb(path: Path, doc: dict, binary: bytes) -> None:
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binary += b"\0" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    out = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js \
        + struct.pack("<II", len(binary), 0x004E4942) + binary
    path.write_bytes(out)


def add_clips(path: Path, baked: dict) -> None:
    g = Gltf(path)
    doc = g.j
    binary = bytearray(g.glb_bin or b"")
    nodes = {n.get("name"): i for i, n in enumerate(doc["nodes"])}

    def add(arr: np.ndarray, typ: str, minmax: bool = False) -> int:
        data = np.ascontiguousarray(arr, dtype=np.float32)
        while len(binary) % 4:
            binary.append(0)
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": data.nbytes})
        binary.extend(data.tobytes())
        acc = {"bufferView": len(doc["bufferViews"]) - 1, "componentType": 5126, "count": int(data.shape[0]),
               "type": typ}
        if minmax:
            flat = data.reshape(data.shape[0], -1)
            acc["min"], acc["max"] = flat.min(0).tolist(), flat.max(0).tolist()
        doc["accessors"].append(acc)
        return len(doc["accessors"]) - 1

    # Re-running replaces: drop old copies of these clips (their buffer bytes are left unused —
    # rerun from a clean checkout of the GLBs to compact; the cost is tens of KB).
    doc["animations"] = [a for a in doc.get("animations", []) if a.get("name") not in baked]
    for name, c in baked.items():
        samplers, channels = [], []
        a_t = add(c["times"].reshape(-1, 1), "SCALAR", True)
        for b in KEEP:
            samplers.append({"input": a_t, "output": add(np.array(c["rot"][b]), "VEC4"), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": nodes[b], "path": "rotation"}})
        samplers.append({"input": a_t, "output": add(np.array(c["hips"]), "VEC3"), "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": nodes["Hips"], "path": "translation"}})
        doc["animations"].append({"name": name, "samplers": samplers, "channels": channels})
    doc["buffers"][0]["byteLength"] = len(binary)
    write_glb(path, doc, bytes(binary))


def main() -> int:
    raw = Path(sys.argv[1]) if len(sys.argv) > 1 else RAW
    conv = os.environ.get("FBX2GLTF", "FBX2glTF")
    sources = {}
    for name, (stem, mode, *_fps) in CLIPS.items():
        fbx = next(iter(sorted(raw.glob(f"*{stem}.fbx"))), None)
        glb = raw / f"{stem}.glb"
        if fbx is not None and (not glb.exists() or glb.stat().st_mtime < fbx.stat().st_mtime):
            subprocess.run([conv, "-b", "-i", str(fbx), "-o", str(raw / stem)], check=True, capture_output=True)
        if not glb.exists():
            raise SystemExit(f"missing {stem}.fbx / .glb in {raw}")
        rig = Rig(Gltf(glb), 0, None)
        rig.fit_skeleton_only()
        sources[name] = (rig, mode, _fps[0] if _fps else FPS)
    meta = json.loads(META.read_text())
    for pid, info in meta["people"].items():
        path = PEOPLE / f"{pid}.glb"
        if not path.exists():
            continue
        target_rig = Rig(Gltf(path), 0, None)
        target = target_rig.pose(target_rig.rest)
        baked = {name: bake(target, src, mode, fps) for name, (src, mode, fps) in sources.items()}
        add_clips(path, baked)
        info["run_speed"] = round(baked["run"]["speed"], 3)
        info["moves"] = {n: [round(float(c["move"][0]), 3), round(float(c["move"][2]), 3), round(c["duration"], 3)]
                         for n, c in baked.items() if n != "run"}
        for n in ("flee_look",):
            info[f"{n}_speed"] = round(baked[n]["speed"], 3)
        print(f"OK   {pid}: +{', '.join(baked)}  run {info['run_speed']:.2f} m/s, "
              f"dodge back {-info['moves']['dodge'][1]:.2f} m, {path.stat().st_size // 1024} KB")
    META.write_text(json.dumps(meta, indent=1, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
