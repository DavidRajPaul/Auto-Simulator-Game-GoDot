#!/usr/bin/env python3
"""Roundabout islands and road sizes (Nov 15, tools/osm/build_roundabouts.py, audit_road_widths.py).

* every island keeps off the drawn carriageway (its kerb sits on the inner edge of the ring road);
* no building, parked vehicle, stall, cart or pole stands on an island;
* the known circles are all there (Temple Tower, College Road, both sides of Gemini Circle);
* the road-width audit finds no implausibly narrow road in the box.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "osm"))
from build_roundabouts import inside  # noqa: E402
from build_street_signs import TriGrid  # noqa: E402

WORLD = ROOT / "data" / "world"


def main() -> int:
    fails = []
    islands = json.loads((WORLD / "roundabouts.json").read_text())["islands"]
    names = {i["name"] for i in islands}
    for want in ("Temple Tower roundabout, Nandanam", "College Road circle, Nungambakkam", "Gemini Circle"):
        if want not in names:
            fails.append(f"missing island: {want}")
    if sum(1 for i in islands if i["kind"] == "horse") != 2:
        fails.append("Gemini Circle should have two statue islands")
    manifest = json.loads((WORLD / "manifest.json").read_text())
    road = TriGrid()
    for ch in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for kind, part in d.get("surf", {}).items():
            if kind.removesuffix("_up") not in ("road", "junction", "lane", "centre"):
                continue
            v, idx = part["v"], part["i"]
            for k in range(0, len(idx), 3):
                road.add(*[(v[2 * idx[k + m]], v[2 * idx[k + m] + 1]) for m in range(3)])
    for isl in islands:
        p = isl["poly"]
        poly = [(p[k], p[k + 1]) for k in range(0, len(p), 2)]
        xs, zs = [q[0] for q in poly], [q[1] for q in poly]
        on_road = 0
        x = min(xs)
        while x <= max(xs):
            z = min(zs)
            while z <= max(zs):
                if inside(x, z, poly) and road.hit(x, z, 0.0):
                    on_road += 1
                z += 0.5
            x += 0.5
        if on_road > 2:
            fails.append(f"{isl['name']} ({isl['kind']}): {on_road} island cells on the carriageway")
        cx, cz = isl["x"], isl["z"]
        k = (int(cx // 250), int(cz // 250))
        dress = json.loads((WORLD / "dress" / f"c_{k[0]}_{k[1]}.json").read_text())
        for key in ("parking", "stalls", "carts", "poles"):
            for it in dress.get(key, []):
                if inside(float(it[0]), float(it[1]), poly):
                    fails.append(f"{isl['name']}: {key} item on the island at {it[:2]}")
        chunk = json.loads((WORLD / "chunks" / f"c_{k[0]}_{k[1]}.json").read_text())
        for b in chunk.get("blds", []):
            bp = b["p"]
            if inside(sum(bp[0::2]) / (len(bp) / 2), sum(bp[1::2]) / (len(bp) / 2), poly):
                fails.append(f"{isl['name']}: a building stands on the island")
        if not any(r[0] == isl["kind"] and abs(r[1] - cx) < 0.02 and abs(r[2] - cz) < 0.02 for r in dress.get("islands", [])):
            fails.append(f"{isl['name']}: not written into its chunk's dress")
    audit = subprocess.run([sys.executable, str(ROOT / "tools" / "osm" / "audit_road_widths.py")],
                           capture_output=True, text=True)
    if audit.returncode != 0:
        fails.append("road-width audit flags roads:\n" + "\n".join(l for l in audit.stdout.splitlines() if l.startswith("FLAG")))
    for f in fails:
        print("FAIL", f)
    print(f"roundabouts: {len(islands)} islands checked, {len(fails)} problems")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
