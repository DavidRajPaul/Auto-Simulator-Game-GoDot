#!/usr/bin/env python3
"""Copies the Mixamo street clips (run, dodge, talk, …) from a shipped people GLB onto another.

process_people.py rebuilds a character with only "walk" and "idle"; add_mixamo_clips.py needs the
owner's raw Mixamo FBX files, which stay on the owner's machine. Every shipped GLB already carries
the retargeted clips on the same 22-bone rig, so this re-bakes them from one GLB onto another with
add_mixamo_clips.bake (same rest-pose alignment, root motion kept for dodge / stumble / fallen) and
fills people.json (run / flee paces scaled by hip height, "moves" from the re-baked root motion).

Usage: python3 tools/assets/copy_people_clips.py <source.glb> <source people.json> <target id> [...]
  e.g. python3 tools/assets/copy_people_clips.py /tmp/backup/woman_saree_green.glb \\
       /tmp/backup/people.json woman_saree_green
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from add_mixamo_clips import CLIPS, META, PEOPLE, add_clips, bake  # noqa: E402
from gltf_rig import Gltf  # noqa: E402
from process_people import Rig  # noqa: E402

KEEP_ON_TARGET = ("walk", "idle")


def copy(src_glb: Path, src_meta: dict, src_id: str, target_id: str) -> None:
    sg = Gltf(src_glb)
    # Both rigs are read as stored (feet on y = 0), so a character copied onto itself gets
    # exactly its own clips back (fit_skeleton_only would measure hips from the toes: +4 %).
    src = Rig(sg, 0, None)
    path = PEOPLE / f"{target_id}.glb"
    trig = Rig(Gltf(path), 0, None)
    target = trig.pose(trig.rest)
    k = target["Hips"][1][1] / max(src.pose(src.rest)["Hips"][1][1], 1e-6)
    baked = {}
    for i, a in enumerate(sg.j.get("animations", [])):
        name = a.get("name", "")
        if name in KEEP_ON_TARGET or name not in CLIPS:
            continue
        mode = CLIPS[name][1]
        frames = sg.accessor(a["samplers"][0]["input"]).shape[0]
        fps = max(1, int(round((frames - 1) / max(sg.anim_duration(i), 1e-6))))
        baked[name] = bake(target, src, mode, fps, i)
    add_clips(path, baked)
    meta = json.loads(META.read_text())
    info = meta["people"].setdefault(target_id, {})
    old = src_meta.get(src_id, {})
    for key in ("run_speed", "flee_speed", "flee_look_speed"):
        if key in old:
            info[key] = round(old[key] * k, 3)
    info["moves"] = {n: [round(float(c["move"][0]), 3), round(float(c["move"][2]), 3), round(c["duration"], 3)]
                     for n, c in baked.items() if n != "run"}
    META.write_text(json.dumps(meta, indent=1, sort_keys=True))
    print(f"OK   {target_id}: +{len(baked)} clips from {src_id} (scale {k:.2f})")


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    src_glb = Path(sys.argv[1])
    src_meta = json.loads(Path(sys.argv[2]).read_text())["people"]
    for target_id in sys.argv[3:]:
        copy(src_glb, src_meta, src_glb.stem, target_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
