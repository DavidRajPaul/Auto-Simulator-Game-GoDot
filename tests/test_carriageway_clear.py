#!/usr/bin/env python3
"""Nothing stands on a drawn carriageway (Nov 15 device report: "trees in the middle of the road").

The game draws flyovers flat on the ground, so flyover decks ("_up" surfaces) are carriageway too:
434 trees, 153 parked vehicles, 130 poles and 41 stalls once stood on them because the dressing
passes only rastered ground-level roads. Checks every tree trunk (with a 0.25 m margin), pole,
parked vehicle, stall, cart and transformer against every road / lane / junction triangle.
"""
from __future__ import annotations

import glob
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "osm"))
from build_street_signs import TriGrid  # noqa: E402

WORLD = ROOT / "data" / "world"
CARRIAGEWAY = ("road", "lane", "junction", "centre")
# Item key -> clearance radius (m) its centre must keep from the carriageway.
ITEMS = {"trees": 0.25, "poles": 0.0, "parking": 0.0, "stalls": 0.0, "carts": 0.0, "xfmr": 0.0}


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    road = TriGrid()
    for ch in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for kind, part in d.get("surf", {}).items():
            if kind.removesuffix("_up") not in CARRIAGEWAY:
                continue
            v, idx = part["v"], part["i"]
            for k in range(0, len(idx), 3):
                road.add(*[(v[2 * idx[k + m]], v[2 * idx[k + m] + 1]) for m in range(3)])
    bad: dict[str, list] = {k: [] for k in ITEMS}
    total = 0
    for f in sorted(glob.glob(str(WORLD / "dress" / "c_*.json"))):
        d = json.loads(Path(f).read_text())
        for key, r in ITEMS.items():
            for it in d.get(key, []):
                total += 1
                x, z = float(it[0]), float(it[1])
                if key == "trees" and len(it) > 4 and int(it[4]) >= 900000:
                    continue  # median palms stand in the gap between carriageways
                if road.hit(x, z, r):
                    bad[key].append((round(x, 1), round(z, 1)))
    fails = 0
    for key, items in bad.items():
        if items:
            fails += len(items)
            print(f"FAIL {len(items)} {key} on the carriageway, e.g. {items[:5]}")
    # A few kerb trees may lean over a road edge by a hand's width; none may stand in it.
    print(f"carriageway clear: {total} items checked, {fails} on the road")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
