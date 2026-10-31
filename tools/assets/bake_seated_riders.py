#!/usr/bin/env python3
"""Bakes the city's people (assets/models/people/*.glb, 22-bone rig) into static scooter riders.

Oct 31 device test: two-wheeler riders were PersonMesh's procedural blocks ("look like
characters"), next to realistic textured pedestrians. Each rider here is a real character
posed on a scooter: upright back, thighs forward on the seat, feet on the floorboard, hands on
the handlebar. One mesh, one material each (same draw cost as the procedural rider), origin at
the hip joint, facing +Z. Same pipeline as the hero driver (tools/assets/bake_seated_hero.py).

Output: assets/models/people/riders/<id>_rider.glb
Usage: python3 tools/assets/bake_seated_riders.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bake_seated_hero import bake  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PEOPLE = ROOT / "assets" / "models" / "people"
OUT = PEOPLE / "riders"
# Commuters on Chennai scooters: office goer, casual, a woman in modern dress, a college girl.
RIDERS = ["young_man", "man_casual", "woman_modern", "girl_churidar"]
TRI_BUDGET = 2400

# Mixamo-style 22-bone rig (process_people.py). Character faces +Z, +X is his left.
POSE = [
    ("Spine", "Spine1", np.array([0.0, 1.0, 0.06])),            # nearly upright, scooter posture
    ("LeftUpLeg", "LeftLeg", np.array([0.12, -0.22, 1.0])),     # thighs forward on the seat
    ("RightUpLeg", "RightLeg", np.array([-0.12, -0.22, 1.0])),
    ("LeftLeg", "LeftFoot", np.array([0.02, -1.0, 0.1])),       # shins down to the floorboard
    ("RightLeg", "RightFoot", np.array([-0.02, -1.0, 0.1])),
    ("LeftArm", "LeftForeArm", np.array([0.3, -0.75, 0.6])),    # arms forward to the handlebar
    ("RightArm", "RightForeArm", np.array([-0.3, -0.75, 0.6])),
    ("LeftForeArm", "LeftHand", np.array([0.05, -0.1, 1.0])),
    ("RightForeArm", "RightHand", np.array([-0.05, -0.1, 1.0])),
]


def main() -> int:
    meta = json.loads((PEOPLE / "people.json").read_text())["people"]
    OUT.mkdir(parents=True, exist_ok=True)
    report = []
    for rid in RIDERS:
        r = bake(PEOPLE / f"{rid}.glb", OUT / f"{rid}_rider.glb", POSE, "Hips", float(meta[rid]["height"]), TRI_BUDGET)
        r["credit"] = meta[rid]["credit"]
        report.append(r)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
