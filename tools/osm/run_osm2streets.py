#!/usr/bin/env python3
"""Run A/B Street's osm2streets (Apache-2.0) on our OSM extract to get real road geometry:
lane polygons, lane markings, junction polygons and crossings — left-hand (India) driving.

Needs the `osm2streets_python` wheel (built in CI: .github/workflows/osm-streets.yml).
Input : data/osm/chennai_mvp.osm.json.gz
Output: data/osm/streets/{plain,lanes,lane_markings,intersection_markings}.geojson.gz
"""
import gzip, json, sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

import osm2streets_python as o2s  # type: ignore

sys.path.insert(0, str(Path(__file__).parent))
from config import BBOX  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "osm" / "chennai_mvp.osm.json.gz"
OUT = ROOT / "data" / "osm" / "streets"


# Lane counts for roads OSM leaves untagged (Nov 14 device report: "why does Kamarajar Salai
# have very small roads?"). Without a "lanes" tag osm2streets gives a one-way carriageway ONE
# lane, so the Marina beach road - three lanes each way in reality, split by a median - came
# out as two 4.5 m strips. Only ways with no lanes tag are touched; a mapped count always wins.
# Per carriageway (one-way ways), by name prefix:
NAMED_LANES = {
    "Kamarajar Salai": 3,
    "Dr Radhakrishnan Salai": 3,
    "Anna Salai": 3,
    "Uttamar Gandhi Salai": 2,
    "Dr MGR Salai": 2,
    "TTK Road": 2,
    "Cathedral Road": 2,
    "Peters Road": 2,
    "McNichols Road": 2,
    "Mc Nichols Road": 2,
    "Anna Flyover": 2,
    "Music Academy Flyover": 2,
    "Gopathi Narayanaswami Flyover": 2,
}
# One-way carriageways of these classes get 2 lanes; two-way primaries 4 (2 each way).
ONEWAY_DEFAULT = {"trunk": 2, "primary": 2, "secondary": 2}
TWOWAY_DEFAULT = {"trunk": 4, "primary": 4}


def lanes_for(tags: dict) -> int:
    """The lane count to add for a way with no "lanes" tag (0 = leave it to osm2streets)."""
    if "lanes" in tags:
        return 0
    hw = tags.get("highway", "")
    oneway = tags.get("oneway", "no") in ("yes", "1", "true")
    name = tags.get("name", "")
    if oneway:
        for prefix, n in NAMED_LANES.items():
            if name.startswith(prefix):
                return n
        return ONEWAY_DEFAULT.get(hw, 0)
    return TWOWAY_DEFAULT.get(hw, 0)


def to_osm_xml(elements: list[dict]) -> bytes:
    """Rebuild a minimal .osm XML (nodes + highway ways) from Overpass `out geom` JSON."""
    nodes: dict[int, tuple[float, float]] = {}
    ways = []
    for e in elements:
        if e.get("type") != "way" or "highway" not in e.get("tags", {}):
            continue
        geom, ids = e.get("geometry") or [], e.get("nodes") or []
        if len(geom) != len(ids) or len(ids) < 2:
            continue
        for nid, g in zip(ids, geom):
            nodes[nid] = (g["lat"], g["lon"])
        ways.append(e)
    out = ['<?xml version="1.0" encoding="UTF-8"?>', '<osm version="0.6" generator="namma-auto">',
           f'<bounds minlat="{BBOX[0]}" minlon="{BBOX[1]}" maxlat="{BBOX[2]}" maxlon="{BBOX[3]}"/>']
    for nid, (lat, lon) in nodes.items():
        out.append(f'<node id="{nid}" lat="{lat}" lon="{lon}" version="1"/>')
    for w in ways:
        out.append(f'<way id="{w["id"]}" version="1">')
        out.extend(f'<nd ref="{n}"/>' for n in w["nodes"])
        out.extend(f'<tag k={quoteattr(k)} v={quoteattr(str(v))}/>' for k, v in w["tags"].items())
        extra = lanes_for(w["tags"])
        if extra:
            out.append(f'<tag k="lanes" v="{extra}"/>')
        out.append("</way>")
    out.append("</osm>")
    return "\n".join(out).encode()


def main() -> int:
    with gzip.open(RAW, "rt", encoding="utf-8") as f:
        elements = json.load(f)["elements"]
    s, w, n, e = BBOX
    clip = json.dumps({"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {},
        "geometry": {"type": "Polygon", "coordinates": [[[w, s], [e, s], [e, n], [w, n], [w, s]]]}}]})
    options = json.dumps({"debug_each_step": False, "dual_carriageway_experiment": False,
                          "sidepath_zipping_experiment": False, "inferred_sidewalks": True,
                          "inferred_kerbs": True, "date_time": None, "override_driving_side": "Left"})
    net = o2s.PyStreetNetwork(to_osm_xml(elements), clip, options)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("plain", net.to_geojson_plain), ("lanes", net.to_lane_polygons_geojson),
                     ("lane_markings", net.to_lane_markings_geojson),
                     ("intersection_markings", net.to_intersection_markings_geojson)):
        data = fn()
        with gzip.open(OUT / f"{name}.geojson.gz", "wt", encoding="utf-8") as f:
            f.write(data)
        print(f"{name}: {len(json.loads(data)['features'])} features")
    return 0


if __name__ == "__main__":
    sys.exit(main())
