"""Fail CI if authored quests drift off the currently generated playable Chennai map."""

import csv
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "osm"))
from config import BBOX, CHUNK_SIZE_M, MAP_SCALE, ORIGIN  # noqa: E402

PACK = ROOT / "data" / "missions" / "side_quests"
VECTOR = re.compile(r"(?:start_anchor|target) = Vector3\((-?[\d.]+), 0, (-?[\d.]+)\)")
OPTION_LINE = re.compile(r"^target_options = (.*)$", re.M)
OPTION = re.compile(r"\"SQ\d+_[A-Z_]+\": Vector3\((-?[\d.]+), 0, (-?[\d.]+)\)")
PLACE = re.compile(r"^place_pos = Vector3\((-?[\d.]+), 0, (-?[\d.]+)\)", re.M)
PLAIN_WORDS = re.compile(r"\b(integrity|kerb|bay|designated|verify|accessible|façade|facade|perimeter|mandatory|claimant)\b", re.I)
OPEN_AIR = {"sq_006", "sq_007", "sq_008", "sq_010"}  # Beach stops stand at the sand, not a building.


def distance_to_segment(x, z, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz + 1e-9)))
    return math.hypot(x - ax - t * dx, z - az - t * dz)


def inside(x, z, poly):
    hit = False
    for a, b in zip(poly, poly[1:] + poly[:1]):
        if (a[1] > z) != (b[1] > z) and x < (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]) + a[0]:
            hit = not hit
    return hit


def nearby_buildings(x, z):
    cx, cz = math.floor(x / CHUNK_SIZE_M), math.floor(z / CHUNK_SIZE_M)
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            chunk_file = ROOT / f"data/world/chunks/c_{cx+dx}_{cz+dz}.json"
            if chunk_file.exists():
                for building in json.loads(chunk_file.read_text()).get("blds", []):
                    yield building["p"]


def check_plain_text():
    with open(ROOT / "translations/ui.csv", encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle):
            if row and re.match(r"(SQ\d+_|QUEST_)", row[0]):
                bad = PLAIN_WORDS.search(row[1])
                assert not bad, f"{row[0]}: use a simpler word than '{bad.group()}'"


def main():
    check_plain_text()
    sources = json.loads((PACK / "anchors.json").read_text())
    manifest = json.loads((ROOT / "data/world/manifest.json").read_text())
    graph = json.loads((ROOT / "data/world/road_graph.json").read_text())
    areas = json.loads((ROOT / "data/world/areas.json").read_text())
    compounds = json.loads((ROOT / "data/world/compounds.json").read_text())["chunks"]
    chunks = {tuple(pair) for pair in manifest["chunks"]}
    assert manifest["origin_latlon"] == list(ORIGIN) and manifest["map_scale"] == MAP_SCALE
    assert len(sources) == 24 and len({v["sector"] for v in sources.values()}) == 24
    segments = []
    for edge in graph["edges"]:
        for a, b in zip(edge["pts"], edge["pts"][1:]):
            segments.append((*a, *b))
    starts = []
    for path in sorted(PACK.glob("sq_*.tres")):
        qid = path.stem
        assert qid in sources, f"unlisted quest {qid}"
        content = path.read_text()
        assert f'id = "{qid}"' in content and "discoverable = true" in content, qid
        start = re.search(r"start_anchor = Vector3\((-?[\d.]+), 0, (-?[\d.]+)\)", content)
        assert start is not None, qid
        sx, sz = (float(v) for v in start.groups())
        src = sources[qid]
        lat, lon = src["lat"], src["lon"]
        assert BBOX[0] < lat < BBOX[2] and BBOX[1] < lon < BBOX[3], qid
        x = (lon - ORIGIN[1]) * 111320.0 * math.cos(math.radians(ORIGIN[0])) * MAP_SCALE
        z = -(lat - ORIGIN[0]) * 111320.0 * MAP_SCALE
        assert math.hypot(x - sx, z - sz) < 0.15, f"{qid}: source coordinate drift"
        assert all(math.hypot(sx - a, sz - b) >= 120.0 for a, b in starts), f"{qid}: start overlap"
        starts.append((sx, sz))
        options = [pair for line in OPTION_LINE.findall(content) for pair in OPTION.findall(line)]
        points = {(float(a), float(b)) for a, b in VECTOR.findall(content) + options}
        assert "hidden_route" not in content, f"{qid}: every stop needs a GPS route"
        for stage in re.split(r"(?=^\[sub_resource)", content, flags=re.M)[1:]:
            stage = stage.split("[resource]")[0]
            located = re.search(r'^kind = "(goto|photo|yield|inspect|calm|park|cargo)"', stage, re.M)
            assert not located or "place_key" in stage or "place_options" in stage, f"{qid}: unnamed stop\n{stage}"
        for fx, fz in PLACE.findall(content):
            fx, fz = float(fx), float(fz)
            gap = min((min(math.hypot(fx - a, fz - b) for a, b in zip(p[::2], p[1::2])), fx, fz) for p in nearby_buildings(fx, fz))[0] if qid not in OPEN_AIR else 0.0
            assert gap <= 40.0, f"{qid}: sign {(fx, fz)} stands {gap:.0f} m from any building"
        assert points, qid
        for px, pz in points:
            clat = ORIGIN[0] - pz / (111320.0 * MAP_SCALE)
            clon = ORIGIN[1] + px / (111320.0 * math.cos(math.radians(ORIGIN[0])) * MAP_SCALE)
            assert BBOX[0] < clat < BBOX[2] and BBOX[1] < clon < BBOX[3], (qid, px, pz)
            cx, cz = math.floor(px / CHUNK_SIZE_M), math.floor(pz / CHUNK_SIZE_M)
            assert (cx, cz) in chunks, f"{qid}: missing loaded chunk {(cx, cz)}"
            nearby = [seg for seg in segments if min(seg[0], seg[2]) - 3 <= px <= max(seg[0], seg[2]) + 3 and min(seg[1], seg[3]) - 3 <= pz <= max(seg[1], seg[3]) + 3]
            assert nearby and min(distance_to_segment(px, pz, *s) for s in nearby) <= 2.0, f"{qid}: off-road {(px, pz)}"
            for name in ("water", "sea"):
                assert not any(inside(px, pz, poly) for poly in areas[name]), f"{qid}: {name}"
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    chunk_file = ROOT / f"data/world/chunks/c_{cx+dx}_{cz+dz}.json"
                    if chunk_file.exists():
                        for building in json.loads(chunk_file.read_text()).get("blds", []):
                            flat = building["p"]
                            assert not inside(px, pz, list(zip(flat[::2], flat[1::2]))), f"{qid}: inside building"
            assert all(distance_to_segment(px, pz, *wall[:4]) >= 2.0 for wall in compounds.get(f"{cx},{cz}", [])), f"{qid}: compound wall"
            dress = ROOT / f"data/world/dress/c_{cx}_{cz}.json"
            if dress.exists():
                assert all(math.hypot(px - park[0], pz - park[1]) >= 3.0 for park in json.loads(dress.read_text()).get("parking", [])), f"{qid}: parked vehicle"
        print(f"PASS {qid}: {len(points)} mapped anchors within the current Chennai box")
    assert len(starts) == len(sources), "quest source/pack mismatch"


if __name__ == "__main__":
    main()
