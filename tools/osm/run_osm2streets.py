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

sys.path.insert(0, str(Path(__file__).parent))
from config import BBOX  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "osm" / "chennai_mvp.osm.json.gz"
OUT = ROOT / "data" / "osm" / "streets"


# Lane counts for Chennai's roads (Nov 14 device report: "why does Kamarajar Salai have very small
# roads?"; Nov 15: "the entire bounding box ... we have wrong road sizes"). Without a "lanes" tag
# osm2streets gives a one-way carriageway ONE 3 m lane and a two-way road one lane each way, so the
# Marina beach road came out as two 4.5 m strips and Lloyds Road / Eldams Road / St Mary's Road as
# 6 m lanes. An audit of every trunk..tertiary road in the box (tools/osm/audit_road_widths.py)
# set these rules:
#   * named arterials get their real lane count per carriageway (NAMED_LANES);
#   * one-way trunk / primary / secondary / tertiary carriageways get at least 2 lanes - even when
#     OSM says lanes=1 on a primary / secondary (South Usman Road, Royapettah High Road, Adithanar
#     Road are tagged 1 but carry two or three columns of traffic);
#   * two-way trunk / primary / secondary roads get 2 lanes each way (Chennai's two-way secondaries
#     are 11-13 m kerb to kerb, not 6 m);
#   * NAMED_TWOWAY widens two-way roads OSM under-classes;
#   * a mapped "width" gives width / 3.4 m lanes when that is more;
#   * a roundabout ring is one-way whatever its oneway tag says, and keeps its mapped size (only a
#     mapped width widens it: class defaults filled the small College Road circle).
# A plausible mapped count always wins.
# Per carriageway (one-way ways), by name prefix:
NAMED_LANES = {
    "Kamarajar Salai": 3,
    "Dr Radhakrishnan Salai": 3,
    "Anna Salai": 3,
    "Uttamar Gandhi Salai": 2,
    "Dr MGR Salai": 2,
    "Doctor M.G.R. Salai": 2,
    "TTK Road": 2,
    "T T Krishnamachari Road": 2,
    "Cathedral Road": 2,
    "Peters Road": 2,
    "McNichols Road": 2,
    "Mc Nichols Road": 2,
    "South Usman Road": 2,
    "Greams Road": 2,
    "Sterling Road": 2,
    "Royapettah High Road": 2,
    "Adithanar Road": 2,
    "Anna Flyover": 2,
    "Music Academy Flyover": 2,
    "Gopathi Narayanaswami Flyover": 2,
}
# Two-way roads OSM classes as tertiary but that are 4-lane in reality (Lloyds Road, Pycrofts Road).
NAMED_TWOWAY = {"Avvai Shanmugam Salai": 4, "Bharathi Salai": 4}
# One-way carriageways of these classes get at least 2 lanes; two-way ones 4 (2 each way).
ONEWAY_DEFAULT = {"trunk": 2, "primary": 2, "secondary": 2, "tertiary": 2}
TWOWAY_DEFAULT = {"trunk": 4, "primary": 4, "secondary": 4}
LANE_M = 3.4


def _is_oneway(tags: dict) -> bool:
    return tags.get("oneway", "no") in ("yes", "1", "true", "-1") or tags.get("junction") == "roundabout"


def lanes_for(tags: dict) -> int:
    """The lane count to write for a way (0 = keep what OSM says / leave it to osm2streets)."""
    hw = tags.get("highway", "")
    oneway = _is_oneway(tags)
    name = tags.get("name", "")
    try:
        tagged = int(str(tags.get("lanes", "")).split(";")[0])
    except ValueError:
        tagged = 0
    named = 0
    for prefix, n in NAMED_LANES.items():
        if name.startswith(prefix):
            named = n
            break
    from_width = _lanes_from_width(tags["width"], 1 if oneway else 2) if "width" in tags else 0
    if tags.get("junction") == "roundabout":
        # A ring keeps its mapped size: class defaults made the small College Road circle's ring
        # two lanes wide and filled its whole middle. Only a mapped width widens it (Temple Tower).
        return from_width if from_width > max(tagged, 1) else 0
    if oneway:
        want = max(named or ONEWAY_DEFAULT.get(hw, 0), from_width)
        if tagged:
            # Mapped counts stand, except a lone lane on a one-way primary / secondary or a named
            # arterial (South Usman Road is tagged 1 but carries two columns of traffic).
            raise_it = tagged < want and (hw in ("trunk", "primary", "secondary") or named)
            return want if raise_it else 0
        return want
    if tagged:
        # A two-way road with one lane in total is a mapping slip (the Thiru Vi Ka flyover).
        return 2 if tagged < 2 else 0
    named2 = next((n for prefix, n in NAMED_TWOWAY.items() if name.startswith(prefix)), 0)
    return max(named2, TWOWAY_DEFAULT.get(hw, 0), from_width)


def _lanes_from_width(width: str, minimum: int) -> int:
    try:
        w = float(str(width).split()[0].rstrip("m"))
    except ValueError:
        return 0
    n = max(minimum, min(6, round(w / LANE_M)))
    if minimum == 2 and n % 2:
        n -= 1 if n > 2 else -1
    return n


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
        lanes = lanes_for(w["tags"])
        out.extend(f'<tag k={quoteattr(k)} v={quoteattr(str(v))}/>' for k, v in w["tags"].items()
                   if not (lanes and k in ("lanes", "lanes:forward", "lanes:backward")))
        if lanes:
            out.append(f'<tag k="lanes" v="{lanes}"/>')
            if w["tags"].get("junction") == "roundabout" and "oneway" not in w["tags"]:
                out.append('<tag k="oneway" v="yes"/>')
        out.append("</way>")
    out.append("</osm>")
    return "\n".join(out).encode()


def main() -> int:
    import osm2streets_python as o2s  # type: ignore  # built in CI only
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
