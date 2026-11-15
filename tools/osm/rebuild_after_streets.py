#!/usr/bin/env python3
"""Re-run every world pass after the road geometry changed (data/osm/streets), in order.

Each pass places things against the real road surface, so after osm2streets runs again (new
lanes, new widths) all of them must run again, in this order (see AGENTS.md lessons):
  world + graph -> water, bus stops -> street dressing -> parking -> city props + street shops
  -> empty lots -> signal posts, street signs -> barricades -> beach carts -> beach fence
  -> medians -> road works -> roundabout islands -> street lights -> police booths -> compounds -> building names -> lodges/eateries
  -> building types (classify) -> plots (walls, gates) -> street life -> density audit.
Usage: python3 tools/osm/rebuild_after_streets.py [--from build_street_dressing.py]
       (needs data/osm/streets from run_osm2streets.py; --from resumes the chain at a step)
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORDER = [
    "build_world.py",
    "build_water.py",
    "build_bus_stops.py",
    "build_street_dressing.py",
    "build_roadside_parking.py",
    "place_city_props.py",
    "append_street_shops.py",
    "fill_empty_lots.py",
    "build_signal_posts.py",
    "build_street_signs.py",
    "build_barricades.py",
    "build_beach_carts.py",
    "build_beach_fence.py",
    "build_medians.py",
    "build_road_works.py",
    "build_roundabouts.py",
    "build_street_lights.py",
    "build_police_booths.py",
    "build_compounds.py",
    "build_building_names.py",
    "add_lodges_eateries.py",
    "classify_buildings.py",
    "build_plots.py",
    "place_street_life.py",
    "audit_city_density.py",
]


def main() -> int:
    start = 0
    if "--from" in sys.argv:
        start = ORDER.index(sys.argv[sys.argv.index("--from") + 1])
    for step in ORDER[start:]:
        print(f"=== {step}", flush=True)
        r = subprocess.run([sys.executable, str(HERE / step)], cwd=HERE.parents[1])
        if r.returncode != 0:
            print(f"!!! {step} failed ({r.returncode})", flush=True)
            return r.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
