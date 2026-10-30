#!/usr/bin/env python3
"""Add only valid biryani stall props to an existing generated map.

This is a safe incremental pass for PR builds; the full OSM rebuild also calls
add_biryani_props and replaces the previous generated biryani placements.
"""
from __future__ import annotations
import json
from place_city_props import OUT, add_biryani_props, load

def main() -> int:
    manifest, blds, segs, areas = load()
    obj = json.loads(OUT.read_text())
    old = obj.get("props", [])
    kept = [p for p in old if not p.get("biryani_cluster")]
    add_biryani_props(manifest, blds, segs, areas, kept)
    stalls = [p for p in kept if p.get("biryani_cluster")]
    if not stalls:
        raise RuntimeError("No collision-safe roadside biryani stalls found")
    obj["props"] = kept
    OUT.write_text(json.dumps(obj, indent=2) + "\n")
    print("Added", len(stalls), "roadside biryani stalls")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
