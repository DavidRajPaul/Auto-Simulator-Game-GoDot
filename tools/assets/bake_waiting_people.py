#!/usr/bin/env python3
"""Bakes the city's people into static poses for bus stops: standing (arms down) and seated on
the shelter bench (thighs forward, hands on the lap).

Same pipeline as the scooter riders (bake_seated_riders.py / bake_seated_hero.bake): posed
22-bone rig -> one skinned-then-frozen mesh, one material with the character's own texture,
origin at the hip joint, facing +Z. The texture layout is unchanged, so PaintSwap's garment
rects still recolour sarees and shirts on these.

Output: assets/models/people/waiting/<id>_stand.glb, <id>_sit.glb + waiting.json
  waiting.json: {id: {"stand_hip": m above the feet, "sit_drop": m from hip to the lowest point}}
Usage: python3 tools/assets/bake_waiting_people.py
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
OUT = PEOPLE / "waiting"
IDS = ["woman_saree_green", "woman_saree_maroon", "woman_saree_violet", "man_casual",
       "old_man_veshti", "young_man", "girl_churidar", "woman_modern"]
TRI_BUDGET = 2400

ARMS_DOWN = [
    ("LeftArm", "LeftForeArm", np.array([0.14, -1.0, 0.02])),
    ("RightArm", "RightForeArm", np.array([-0.14, -1.0, 0.02])),
    ("LeftForeArm", "LeftHand", np.array([0.06, -1.0, 0.12])),
    ("RightForeArm", "RightHand", np.array([-0.06, -1.0, 0.12])),
]
# Some rest poses are mid-stride (old_man_veshti): stand the legs up straight.
STAND = [
    ("LeftUpLeg", "LeftLeg", np.array([0.06, -1.0, 0.0])),
    ("RightUpLeg", "RightLeg", np.array([-0.06, -1.0, 0.0])),
    ("LeftLeg", "LeftFoot", np.array([0.04, -1.0, -0.03])),
    ("RightLeg", "RightFoot", np.array([-0.04, -1.0, -0.03])),
] + ARMS_DOWN
# Sarees drape badly when the legs fold (the skirt follows the thighs): those only stand.
NO_SIT = {"woman_saree_green", "woman_saree_maroon", "woman_saree_violet"}
SIT = [
    ("Spine", "Spine1", np.array([0.0, 1.0, -0.04])),           # upright, leaning back a touch
    ("LeftUpLeg", "LeftLeg", np.array([0.1, -0.06, 1.0])),      # thighs along the bench
    ("RightUpLeg", "RightLeg", np.array([-0.1, -0.06, 1.0])),
    ("LeftLeg", "LeftFoot", np.array([0.02, -1.0, 0.06])),      # shins down to the floor
    ("RightLeg", "RightFoot", np.array([-0.02, -1.0, 0.06])),
    ("LeftArm", "LeftForeArm", np.array([0.16, -0.92, 0.3])),   # hands resting on the lap
    ("RightArm", "RightForeArm", np.array([-0.16, -0.92, 0.3])),
    ("LeftForeArm", "LeftHand", np.array([-0.05, -0.25, 1.0])),
    ("RightForeArm", "RightHand", np.array([0.05, -0.25, 1.0])),
]


def main() -> int:
    meta = json.loads((PEOPLE / "people.json").read_text())["people"]
    OUT.mkdir(parents=True, exist_ok=True)
    report = {}
    for pid in IDS:
        if pid not in meta:
            continue
        h = float(meta[pid]["height"])
        st = bake(PEOPLE / f"{pid}.glb", OUT / f"{pid}_stand.glb", STAND, "Hips", h, TRI_BUDGET)
        report[pid] = {"stand_hip": st["feet_below_hip_m"], "credit": meta[pid]["credit"]}
        if pid not in NO_SIT:
            si = bake(PEOPLE / f"{pid}.glb", OUT / f"{pid}_sit.glb", SIT, "Hips", h, TRI_BUDGET)
            report[pid]["sit_drop"] = si["feet_below_hip_m"]
    (OUT / "waiting.json").write_text(json.dumps(report, indent=1))
    print(json.dumps(report, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
