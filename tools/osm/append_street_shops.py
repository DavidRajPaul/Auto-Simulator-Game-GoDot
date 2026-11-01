#!/usr/bin/env python3
"""Re-place the roadside shops (tea stalls, fruit carts, biryani stalls) in the existing map.

Incremental pass for content changes without a full OSM rebuild: keeps every other prop,
drops the previously generated shops, points the hand-authored tea kadais at the re-baked
stall and runs add_street_shops again. The full rebuild (place_city_props.py) does the same.
Run after tools/osm/build_street_dressing.py (shops keep clear of poles, trees, transformers).
Usage: python3 tools/osm/append_street_shops.py
"""
from __future__ import annotations

import json

from place_city_props import (OUT, SHOP_KINDS, add_street_shops, load, restyle_tea_clusters,
                              settle_tea_clusters)


def main() -> int:
    manifest, blds, segs, areas = load()
    obj = json.loads(OUT.read_text())
    kept = [p for p in obj.get("props", []) if not (p.get("biryani_cluster") or p.get("street_shop"))]
    restyle_tea_clusters(kept)
    settle_tea_clusters(manifest, blds, segs, areas, kept)
    report = add_street_shops(manifest, blds, segs, areas, kept)
    for kind, cfg in SHOP_KINDS.items():
        if report.get(kind, 0) < cfg["count"] // 2:
            raise RuntimeError(f"only {report.get(kind, 0)} collision-safe {kind} spots found")
    obj["props"] = kept
    OUT.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
