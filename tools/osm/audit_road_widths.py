#!/usr/bin/env python3
"""Audit carriageway sizes across the whole map box.

For every trunk / primary / secondary / tertiary way in data/osm/chennai_mvp.osm.json.gz it reports
the lane count OSM maps, the count run_osm2streets.py will write (lanes_for) and the resulting
carriageway width, then flags roads that would still come out implausibly narrow:
  * a one-way carriageway with one lane (a mapped lanes=1 on a tertiary is believed);
  * a two-way primary / secondary road with fewer than 4 lanes (unless OSM maps 2: flyovers);
  * a mapped "width" more than 3 m wider than the lanes we draw.
Exit code 1 when anything is flagged (tests/test_road_widths.py runs it).

    python3 tools/osm/audit_road_widths.py            # summary + flags
    python3 tools/osm/audit_road_widths.py --all      # every named road
"""
from __future__ import annotations

import gzip
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_osm2streets import LANE_M, _is_oneway, lanes_for  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "osm" / "chennai_mvp.osm.json.gz"
CLASSES = ("trunk", "primary", "secondary", "tertiary")
# osm2streets' own default when no lanes tag is written: one lane per direction.
O2S_DEFAULT_ONEWAY, O2S_DEFAULT_TWOWAY = 1, 2


def _len_m(geom: list[dict]) -> float:
    k = 111320.0 * math.cos(math.radians(13.05))
    return sum(math.hypot((b["lat"] - a["lat"]) * 110540.0, (b["lon"] - a["lon"]) * k) for a, b in zip(geom, geom[1:]))


def drawn_lanes(tags: dict) -> int:
    n = lanes_for(tags)
    if n:
        return n
    try:
        t = int(str(tags.get("lanes", "")).split(";")[0])
    except ValueError:
        t = 0
    return t or (O2S_DEFAULT_ONEWAY if _is_oneway(tags) else O2S_DEFAULT_TWOWAY)


def main() -> int:
    show_all = "--all" in sys.argv
    with gzip.open(RAW, "rt", encoding="utf-8") as f:
        elements = json.load(f)["elements"]
    roads: dict[str, dict] = defaultdict(lambda: {"m": 0.0, "lanes": defaultdict(float), "cls": set()})
    flags = []
    for e in elements:
        tags = e.get("tags", {})
        hw = tags.get("highway", "")
        if e.get("type") != "way" or hw not in CLASSES:
            continue
        geom = e.get("geometry") or []
        if len(geom) < 2:
            continue
        L = _len_m(geom)
        oneway = _is_oneway(tags)
        n = drawn_lanes(tags)
        name = tags.get("name", "(unnamed)")
        r = roads[name]
        r["m"] += L
        r["lanes"][(n, oneway)] += L
        r["cls"].add(hw)
        why = ""
        mapped = "lanes" in tags and not lanes_for(tags)
        if oneway and n < 2 and (hw != "tertiary" or not mapped):
            # A mapped single lane on a one-way tertiary is believed (CIT Nagar's 5th Main Road).
            why = "one-way, 1 lane"
        elif not oneway and n < 2:
            why = f"two-way {hw}, {n} lane"
        elif not oneway and hw in ("trunk", "primary", "secondary") and n < 4 and "lanes" not in tags:
            why = f"two-way {hw}, {n} lanes"
        elif "width" in tags:
            try:
                w = float(str(tags["width"]).split()[0].rstrip("m"))
                if w - n * LANE_M > 3.0 and not (oneway and n >= 3):
                    why = f"width {w} m but {n} lanes"
            except ValueError:
                pass
        if why and L > 40:
            flags.append((name, e["id"], hw, why, round(L)))
    rows = sorted(roads.items(), key=lambda kv: -kv[1]["m"])
    print(f"{len(rows)} named trunk..tertiary roads")
    for name, r in rows if show_all else rows[:40]:
        (n, ow), _ = max(r["lanes"].items(), key=lambda kv: kv[1])
        print(f"  {name[:48]:48s} {'/'.join(sorted(r['cls'])):28s} {int(r['m']):6d} m  "
              f"{n} lane{'s' if n > 1 else ''} {'one-way' if ow else 'two-way'} "
              f"= {n * LANE_M:4.1f} m{' per carriageway' if ow else ''}")
    for f in flags:
        print("FLAG", *f)
    print(f"{len(flags)} flagged")
    return 1 if flags else 0


if __name__ == "__main__":
    sys.exit(main())
