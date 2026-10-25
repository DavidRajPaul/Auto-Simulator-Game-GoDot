#!/usr/bin/env python3
"""Optimise traffic models from assets_src/incoming/models/ into small .glb files in assets/models/.

Raw downloads stay local (gitignored). Only the optimised .glb files go into the game.
Each model is kept light for mobile: textures capped at 512 px, geometry trimmed where it helps,
and no animation or Draco/meshopt compression (Godot 4 handles plain glTF best).

Usage: python3 tools/assets/process_models.py
Needs: Node.js and @gltf-transform/cli 4.5.1 in tools/assets/node_modules (npm i in tools/assets).
Writes assets/models/traffic/*.glb and assets/models/CREDITS_models.md.
"""
from __future__ import annotations

import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "models"
OUT = ROOT / "assets" / "models"
TOOLS = ROOT / "tools" / "assets"
GLTF = TOOLS / "node_modules" / ".bin" / "gltf-transform"

# out path, raw source (under assets_src/incoming/models), simplify ratio or None,
# texture size in px, static prop (drop skins/animations), credit
# The MTC bus is not here: the free bus models are 4 m long, far from the 11 m box, so it keeps its box.
SPECS = [
    ("traffic/hatchback.glb", "traffic/kenney_hatchback-sports.glb", 0.4, 512, False,
     "Kenney Car Kit (hatchback-sports), kenney.nl, CC0"),
    ("traffic/share_auto.glb", "traffic/rsquare_auto_rickshaw/scene.gltf", 0.15, 256, False,
     "Auto Rickshaw by rSquare (Sketchfab), CC BY 4.0"),
    ("traffic/two_wheeler.glb", "traffic/shiveloper_scooter.glb", 0.15, 256, False,
     "Indian Scooter by Shiveloper (Sketchfab), CC BY 4.0"),
    ("traffic/stray_cow.glb", "traffic/quaternius_Cow_converted.glb", 0.4, 256, True,
     "Cow by Quaternius (poly.pizza), CC0"),
]


def triangles(path: Path) -> int:
    d = path.read_bytes()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    total = 0
    for mesh in j.get("meshes", []):
        for prim in mesh["primitives"]:
            if "indices" in prim:
                total += j["accessors"][prim["indices"]]["count"] // 3
            else:
                total += j["accessors"][prim["attributes"]["POSITION"]]["count"] // 3
    return total


def run(args: list[str]) -> None:
    subprocess.run([str(c) for c in args], check=True, capture_output=True)


def optimise(src: Path, dest: Path, simplify: float | None, texture_px: int, static: bool) -> None:
    """Static props first (drop skins and animations), then the standard optimiser, then textures."""
    work = dest.with_suffix(".work.glb")
    step = src
    if static:
        run(["node", TOOLS / "static_prop.mjs", src, work])
        step = work
    opt = ["optimize", step, dest, "--compress", "false", "--texture-compress", "false", "--prune", "true"]
    if simplify is None:
        opt += ["--simplify", "false"]
    else:
        opt += ["--simplify", "true", "--simplify-ratio", simplify, "--simplify-error", "0.05"]
    run([GLTF, *opt])
    run([GLTF, "resize", "--width", texture_px, "--height", texture_px, dest, work])
    run(["node", TOOLS / "fix_materials.mjs", work, dest])
    work.unlink(missing_ok=True)


def main() -> int:
    if not GLTF.exists():
        print("gltf-transform missing: run `npm i` in tools/assets first")
        return 2
    credits = ["# Traffic models (optimised by tools/assets/process_models.py)", "",
               "| File | Source | Licence |", "|---|---|---|"]
    failed = 0
    for out_rel, src_rel, simplify, texture_px, static, credit in SPECS:
        src = SRC / src_rel
        if not src.exists():
            print(f"MISSING {src_rel}")
            failed += 1
            continue
        dest = OUT / out_rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        optimise(src, dest, simplify, texture_px, static)
        print(f"OK   {out_rel}: {triangles(dest)} tris, {dest.stat().st_size // 1024} KB")
        credits.append(f"| `assets/models/{out_rel}` | {src_rel} | {credit} |")
    (OUT / "CREDITS_models.md").write_text("\n".join(credits) + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
