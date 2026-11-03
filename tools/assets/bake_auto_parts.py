#!/usr/bin/env python3
"""Player auto damage parts: assets_src/models/player_auto_src.glb -> assets/models/vehicles/player_auto.glb.

The source is what tools/assets/process_models.py makes from the free model. process_models.py writes
straight to assets/models/vehicles/player_auto.glb, so after re-running it pass --from-processed:
that copies the fresh output to assets_src/models/player_auto_src.glb before baking (never
automatic: an earlier version mistook a half-baked file for a fresh source).
tools/assets/bake_auto_parts.mjs tags every vertex with its part in UV2.x (0 body, 1 left mirror,
2 right mirror, 3 windshield, 4 rear glass, 5 headlamp) and subdivides the body panels so dents
can bend them. shaders/auto_paint.gdshader and shaders/auto_glass.gdshader read the ids: no extra
mesh or draw call per part. UV0, textures and materials are unchanged, so the paint mask
(tools/assets/make_auto_paint_mask.py) still lines up.

Run after process_models.py or when the classification changes:
  (cd tools/assets && npm i) && python3 tools/assets/bake_auto_parts.py [--from-processed]
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "models" / "player_auto_src.glb"
OUT = ROOT / "assets" / "models" / "vehicles" / "player_auto.glb"
SCRIPT = ROOT / "tools" / "assets" / "bake_auto_parts.mjs"
# Connected parts per id on the shipped model (mirror = housing + arm + glass): a new source
# model needs the rules in bake_auto_parts.mjs re-tuned, so fail rather than mis-tag.
EXPECTED = {"1": 3, "2": 3, "3": 4, "4": 2, "5": 1}


def main() -> int:
    if "--from-processed" in sys.argv:
        shutil.copyfile(OUT, SRC)
        print(f"process_models output -> {SRC.relative_to(ROOT)}")
    res = subprocess.run(["node", str(SCRIPT), str(SRC), str(OUT)], check=True, capture_output=True, text=True,
                         cwd=SCRIPT.parent)
    report = json.loads(res.stdout.strip().splitlines()[-1])
    print(report)
    got = {k: v for k, v in report["parts"].items() if k != "0"}
    if got != EXPECTED:
        raise SystemExit(f"part classification changed: {got} != {EXPECTED}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
