#!/usr/bin/env python3
"""Optimise traffic models from assets_src/incoming/models/ into small .glb files in assets/models/.

Raw downloads stay local (gitignored). Only the optimised .glb files go into the game.
Each model is kept light for mobile: textures capped at 512 px, geometry trimmed where it helps,
and no animation or Draco/meshopt compression (Godot 4 handles plain glTF best).

Usage: python3 tools/assets/process_models.py [out paths to rebuild, e.g. traffic/lorry.glb]
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
SPECS = [
    ("traffic/hatchback.glb", "traffic/kenney_hatchback-sports.glb", 0.4, 512, False,
     "Kenney Car Kit (hatchback-sports), kenney.nl, CC0"),
    ("traffic/share_auto.glb", "traffic/rsquare_auto_rickshaw/scene.gltf", 0.15, 256, False,
     "Auto Rickshaw by rSquare (Sketchfab), CC BY 4.0"),
    ("traffic/two_wheeler.glb", "traffic/shiveloper_scooter.glb", 0.15, 256, False,
     "Indian Scooter by Shiveloper (Sketchfab), CC BY 4.0"),
    ("traffic/stray_cow.glb", "traffic/quaternius_Cow_converted.glb", 0.4, 256, True,
     "Cow by Quaternius (poly.pizza), CC0"),
    ("traffic/stray_cow_fadly.glb", "traffic/fadly_cow/scene.gltf", 0.03, 256, False,
     "Cow - LowPoly by Fadly.W (Sketchfab), CC BY 4.0", "cow 2"),
    # Tamil Nadu buses (fitted to the 11 m MTC_BUS box) and the mini goods carrier.
    ("traffic/bus_tnstc.glb", "traffic/tamilnadu_tnstc_bus_2009-2014/scene.gltf", None, 512, False,
     "Tamilnadu TNSTC Bus 2009-2014 by Nobel Tech (Sketchfab), CC BY 4.0"),
    ("traffic/bus_setc.glb", "traffic/tamilnadu_setc_bus_2017-2026/scene.gltf", None, 512, False,
     "Tamilnadu SETC Bus 2017-2026 by Nobel Tech (Sketchfab), CC BY 4.0"),
    ("traffic/lorry.glb", "traffic/tamilnadu_lorry/scene.gltf", None, 512, False,
     "Tamilnadu Lorry by Oren garage (Sketchfab), CC BY 4.0"),
    # The player's own auto: same rSquare model at higher detail (seen up close all the time).
    ("vehicles/player_auto.glb", "traffic/rsquare_auto_rickshaw/scene.gltf", 0.5, 1024, False,
     "Auto Rickshaw by rSquare (Sketchfab), CC BY 4.0"),
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


def optimise(src: Path, dest: Path, simplify: float | None, texture_px: int, static: bool, keep: str = "") -> None:
    """Static props first (drop skins and animations), then the standard optimiser, then textures."""
    work = dest.with_suffix(".work.glb")
    step = src
    if static:
        run(["node", TOOLS / "static_prop.mjs", src, work])
        step = work
    if keep:
        picked = dest.with_suffix(".keep.glb")
        run(["node", TOOLS / "keep_mesh.mjs", step, picked, keep])
        step = picked
    opt = ["optimize", step, dest, "--compress", "false", "--texture-compress", "false", "--prune", "true"]
    if simplify is None:
        opt += ["--simplify", "false"]
    else:
        opt += ["--simplify", "true", "--simplify-ratio", simplify, "--simplify-error", "0.05"]
    run([GLTF, *opt])
    run([GLTF, "resize", "--width", texture_px, "--height", texture_px, dest, work])
    run(["node", TOOLS / "fix_materials.mjs", work, dest])
    work.unlink(missing_ok=True)
    dest.with_suffix(".keep.glb").unlink(missing_ok=True)


def main() -> int:
    if not GLTF.exists():
        print("gltf-transform missing: run `npm i` in tools/assets first")
        return 2
    credits = ["# Vehicle and traffic models (optimised by tools/assets/process_models.py)", "",
               "| File | Source | Licence |", "|---|---|---|"]
    failed = 0
    only = sys.argv[1:]  # optional: output paths to (re)build; the others keep their committed .glb
    for spec in SPECS:
        out_rel, src_rel, simplify, texture_px, static, credit = spec[:6]
        if only and out_rel not in only:
            credits.append(f"| `assets/models/{out_rel}` | {src_rel} | {credit} |")
            continue
        keep = spec[6] if len(spec) > 6 else ""
        src = SRC / src_rel
        if not src.exists():
            print(f"MISSING {src_rel}")
            failed += 1
            continue
        dest = OUT / out_rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        optimise(src, dest, simplify, texture_px, static, keep)
        print(f"OK   {out_rel}: {triangles(dest)} tris, {dest.stat().st_size // 1024} KB")
        credits.append(f"| `assets/models/{out_rel}` | {src_rel} | {credit} |")
    (OUT / "CREDITS_models.md").write_text("\n".join(credits) + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
