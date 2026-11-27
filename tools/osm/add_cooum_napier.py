#!/usr/bin/env python3
"""Put the Cooum river back under Napier Bridge.

Nov 27 owner report (with photos): "there is no water beneath the Napier [Bridge]. That looks
totally wrong." The OSM import only asks Overpass for natural=water WAYS; the Cooum near its
mouth is mapped as a multipolygon RELATION, so the river never reached areas.json and the
procedural infill (build_world "f": 1, fill_empty_lots "f": 2) then built houses all over the
riverbed. The Napier Bridge carriageways were in the road graph but had no road surface either.

This pass, idempotent:
  1. adds config.COOUM_NAPIER (hand traced from the Napier Bridge OSM ways 24888589 / 28295242,
     the Buckingham Canal mouth (way 1127503338), the Cooum water way 620717220 and the
     coastline) to areas.json "water", merged with the canal mouth and the upstream river piece
     it touches, minus parks;
  2. removes every chunk building and dress point standing in the river or on the bridge decks
     (real OSM footprints are reported, procedural infill just goes);
  3. writes the bridge decks (from road_graph.json "Napier Bridge" edges) and the corrected
     position into the manifest's napier_bridge landmark;
  4. reruns build_water.py (the bridge keeps the water under it and opens the banks).
Usage: python3 tools/osm/add_cooum_napier.py
"""
from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

from config import COOUM_NAPIER

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
POINT_KEYS = ("trees", "parking", "stalls", "shop_people", "kolams", "dogs", "lamps", "poles")
DECK_W = 10.5       # each Napier carriageway: two lanes + kerbs (= LandmarkKit.NAPIER_DECK_W)
DECK_CLEAR = 4.0    # nothing of the city within this of a deck


def poly_of(p) -> Polygon:
    return Polygon([(float(q[0]), float(q[1])) for q in p]).buffer(0)


def main() -> int:
    areas = json.loads((WORLD / "areas.json").read_text())
    river = Polygon(COOUM_NAPIER).buffer(0)
    parks = unary_union([poly_of(p) for p in areas.get("park", []) if len(p) >= 3])
    river = river.difference(parks.buffer(1.0))
    # Real OSM footprints on the banks stay: the river gives way round them.
    real = []
    for f in (WORLD / "chunks").glob("c_*.json"):
        for b in json.loads(f.read_text()).get("blds", []):
            p = b["p"]
            if b.get("f") or not (river.bounds[0] - 20 < p[0] < river.bounds[2] + 20 and river.bounds[1] - 20 < p[1] < river.bounds[3] + 20):
                continue
            real.append(Polygon([(p[k], p[k + 1]) for k in range(0, len(p), 2)]).buffer(2.0))
    if real:
        river = river.difference(unary_union(real))
    if river.geom_type != "Polygon":
        river = max(river.geoms, key=lambda g: g.area)
    keep, merge = [], [river]
    for p in areas["water"]:
        w = poly_of(p)
        # A previous run's river (same west tip) is replaced; pieces it touches are merged.
        if w.intersects(river.buffer(1.5)):
            merge.append(w)
        else:
            keep.append(p)
    merged = unary_union(merge).buffer(0.6, join_style=2).buffer(-0.6, join_style=2)
    if merged.geom_type != "Polygon":
        merged = max(merged.geoms, key=lambda g: g.area)
    if merged.interiors:
        # areas.json keeps outer rings only: a footprint in a hole would end up under water.
        print(f"warning: {len(merged.interiors)} holes in the river (dropped) - move the traced bank")
        merged = Polygon(merged.exterior)
    ring = [[round(x, 2), round(z, 2)] for x, z in list(merged.simplify(0.3).exterior.coords)[:-1]]
    areas["water"] = keep + [ring]
    (WORLD / "areas.json").write_text(json.dumps(areas, separators=(",", ":")))
    print(f"Cooum: {len(merge) - 1} water pieces merged, {merged.area:.0f} m2, {len(ring)} points")

    graph = json.loads((WORLD / "road_graph.json").read_text())
    decks = [e["pts"] for e in graph["edges"] if e.get("n") == "Napier Bridge"]
    if len(decks) != 2:
        print(f"expected 2 Napier Bridge carriageways in road_graph.json, found {len(decks)}")
        return 1
    deck_area = unary_union([LineString(d).buffer(DECK_W / 2 + DECK_CLEAR, cap_style=2) for d in decks])
    clear = merged.buffer(3.0).union(deck_area)

    size = float(json.loads((WORLD / "manifest.json").read_text())["chunk_size"])
    x0, z0, x1, z1 = clear.bounds
    gone, real, dress = 0, [], 0
    for i in range(int(math.floor(x0 / size)), int(math.floor(x1 / size)) + 1):
        for j in range(int(math.floor(z0 / size)), int(math.floor(z1 / size)) + 1):
            f = WORLD / "chunks" / f"c_{i}_{j}.json"
            if f.exists():
                d = json.loads(f.read_text())
                kept = []
                for b in d.get("blds", []):
                    p = b["p"]
                    fp = Polygon([(p[k], p[k + 1]) for k in range(0, len(p), 2)]).buffer(0)
                    if fp.intersects(merged) and fp.intersection(merged).area > 0.3 * fp.area or fp.intersects(deck_area):
                        gone += 1
                        if not b.get("f"):
                            real.append((round(fp.centroid.x), round(fp.centroid.y), b.get("t")))
                    else:
                        kept.append(b)
                if len(kept) != len(d.get("blds", [])):
                    d["blds"] = kept
                    f.write_text(json.dumps(d, separators=(",", ":")))
            f = WORLD / "dress" / f"c_{i}_{j}.json"
            if f.exists():
                d = json.loads(f.read_text())
                changed = False
                for key in POINT_KEYS:
                    items = d.get(key, [])
                    if not items or not isinstance(items[0], list):
                        continue
                    kept = [it for it in items if not clear.contains(Point(float(it[0]), float(it[1])))]
                    if len(kept) != len(items):
                        dress += len(items) - len(kept)
                        d[key] = kept
                        changed = True
                wires = d.get("wires", [])
                kept = [w for w in wires if not (clear.contains(Point(w[0], w[1])) or clear.contains(Point(w[2], w[3])))]
                if len(kept) != len(wires):
                    d["wires"] = kept
                    changed = True
                if changed:
                    f.write_text(json.dumps(d, separators=(",", ":")))
    # Compound and plot walls of the cleared buildings.
    walls_gone = 0
    comp = json.loads((WORLD / "compounds.json").read_text())
    for key, segs in comp.get("chunks", {}).items():
        kept = [w for w in segs if not LineString([(w[0], w[1]), (w[2], w[3])]).intersects(clear)]
        walls_gone += len(segs) - len(kept)
        comp["chunks"][key] = kept
    (WORLD / "compounds.json").write_text(json.dumps(comp, separators=(",", ":")))
    for i in range(int(math.floor(x0 / size)), int(math.floor(x1 / size)) + 1):
        for j in range(int(math.floor(z0 / size)), int(math.floor(z1 / size)) + 1):
            f = WORLD / "plots" / f"c_{i}_{j}.json"
            if not f.exists():
                continue
            d = json.loads(f.read_text())
            changed = False
            for key in ("walls", "gates"):
                segs = d.get(key, [])
                kept = [w for w in segs if not LineString([(w[0], w[1]), (w[2], w[3])]).intersects(clear)]
                if len(kept) != len(segs):
                    walls_gone += len(segs) - len(kept)
                    d[key] = kept
                    changed = True
            # Paving round the cleared buildings (pre-triangulated): drop triangles in the river.
            for kind, part in d.get("pave", {}).items():
                v, idx = part["v"], part["i"]
                kept_i = []
                for t in range(0, len(idx) - 2, 3):
                    tri = idx[t:t + 3]
                    cx = sum(v[2 * q] for q in tri) / 3.0
                    cz = sum(v[2 * q + 1] for q in tri) / 3.0
                    if not clear.contains(Point(cx, cz)):
                        kept_i += tri
                if len(kept_i) != len(idx):
                    part["i"] = kept_i
                    changed = True
            if changed:
                f.write_text(json.dumps(d, separators=(",", ":")))
    print(f"cleared {walls_gone} compound / plot wall segments (and the paving in the river)")
    print(f"cleared {gone} buildings ({len(real)} real OSM footprints: {real}) and {dress} dress points")

    manifest = json.loads((WORLD / "manifest.json").read_text())
    mids = [LineString(d).interpolate(0.5, normalized=True) for d in decks]
    cx, cz = sum(p.x for p in mids) / 2, sum(p.y for p in mids) / 2
    for lm in manifest["landmarks"]:
        if lm["id"] == "napier_bridge":
            lm.update({"x": round(cx, 2), "z": round(cz, 2), "yaw": 0.0,
                       # Carriageway centre lines in the landmark's local frame (yaw 0).
                       "decks": [[[round(px - cx, 2), round(pz - cz, 2)] for px, pz in d] for d in decks]})
    (WORLD / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"napier_bridge landmark at ({cx:.1f}, {cz:.1f})")
    return subprocess.call([sys.executable, str(Path(__file__).with_name("build_water.py"))])


if __name__ == "__main__":
    raise SystemExit(main())
