"""Real building heights for Chennai from Google Open Buildings 2.5D Temporal.

OSM only tags ~360 of ~22,000 buildings in our bounding box with a height or floor count, so
the world builder had to guess the rest. Google's Open Buildings 2.5D Temporal raster gives a
building_height (metres above terrain, 0–100 m) at 4 m effective resolution for all of South
Asia, yearly 2016–2023, licensed CC BY 4.0 or ODbL v1.0 (your choice) — free for this game,
with attribution in the Credits screen.

This script samples that raster under every footprint in data/world/chunks/*.json and writes
the real height into "h" (keeping the old guess when the raster has no confident pixels).
Road widths already come from real lane geometry (osm2streets + OSM width/lanes tags).

1. Export the raster for our box (Earth Engine Code Editor, free for research/education):

    var box = ee.Geometry.Rectangle([80.230, 13.028, 80.288, 13.070]);
    var img = ee.ImageCollection('GOOGLE/Research/open-buildings-temporal/v1')
        .filterBounds(box).filterDate('2023-01-01', '2023-12-31').mosaic()
        .select('building_height');
    Export.image.toDrive({image: img, description: 'chennai_heights', region: box,
                          scale: 4, crs: 'EPSG:4326', maxPixels: 1e9});

   (No Earth Engine account? Google's site links a Colab notebook that downloads the same
   tiles from Cloud Storage.)
2. Save it as data/osm/chennai_heights_2023.tif (data/osm is excluded from the APK).
3. pip install rasterio && python3 tools/osm/apply_building_heights.py
   (--selftest runs on a synthetic raster, no download needed.)
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import BBOX, MAP_SCALE, ORIGIN  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CHUNKS = ROOT / "data" / "world" / "chunks"
DEFAULT_TIF = ROOT / "data" / "osm" / "chennai_heights_2023.tif"
M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))
MIN_PIXELS = 3
MIN_HEIGHT_M = 2.5
MAX_HEIGHT_M = 100.0
PERCENTILE = 70  # roofs + parapets; edges of the footprint blur toward 0


def to_latlon(x: float, z: float) -> tuple[float, float]:
    return (ORIGIN[0] - z / (M_PER_DEG_LAT * MAP_SCALE), ORIGIN[1] + x / (M_PER_DEG_LON * MAP_SCALE))


def apply(tif: Path, dry_run: bool = False, chunks_dir: Path = CHUNKS) -> dict:
    import rasterio
    from rasterio.features import geometry_mask
    from rasterio.windows import from_bounds

    stats = {"buildings": 0, "updated": 0, "kept_guess": 0, "delta_sum": 0.0}
    with rasterio.open(tif) as src:
        band = src.read(1, masked=True)
        for path in sorted(chunks_dir.glob("c_*.json")):
            chunk = json.loads(path.read_text())
            changed = False
            for b in chunk.get("blds", []):
                if b.get("f"):  # procedural filler blocks have no real footprint
                    continue
                stats["buildings"] += 1
                flat = b["p"]
                ring = [to_latlon(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]
                lons = [p[1] for p in ring]
                lats = [p[0] for p in ring]
                win = from_bounds(min(lons), min(lats), max(lons), max(lats), src.transform).round_offsets().round_lengths()
                if win.width < 1 or win.height < 1:
                    win = win.__class__(win.col_off, win.row_off, max(win.width, 1), max(win.height, 1))
                r0, c0 = int(win.row_off), int(win.col_off)
                h, w = int(win.height), int(win.width)
                if r0 < 0 or c0 < 0 or r0 + h > band.shape[0] or c0 + w > band.shape[1]:
                    stats["kept_guess"] += 1
                    continue
                sub = band[r0:r0 + h, c0:c0 + w]
                tr = src.window_transform(win)
                geom = {"type": "Polygon", "coordinates": [[(lon, lat) for lat, lon in ring] + [(ring[0][1], ring[0][0])]]}
                inside = ~geometry_mask([geom], out_shape=(h, w), transform=tr, all_touched=True)
                vals = np.asarray(sub.filled(0))[inside]
                vals = vals[vals > 1.0]
                if vals.size < MIN_PIXELS:
                    stats["kept_guess"] += 1
                    continue
                real = float(np.clip(np.percentile(vals, PERCENTILE), MIN_HEIGHT_M, MAX_HEIGHT_M))
                stats["delta_sum"] += abs(real - float(b["h"]))
                b["h"] = round(real, 2)
                b["hs"] = "gob25d"  # height source: Google Open Buildings 2.5D
                stats["updated"] += 1
                changed = True
            if changed and not dry_run:
                path.write_text(json.dumps(chunk, separators=(",", ":")))
    n = max(stats["updated"], 1)
    print(f"Heights: {stats['updated']}/{stats['buildings']} real footprints updated from the raster "
          f"(mean change {stats['delta_sum'] / n:.1f} m), {stats['kept_guess']} kept the estimate")
    return stats


def selftest() -> int:
    """Synthetic raster: one 30 m tall block under a fake footprint must read back ~30 m."""
    import tempfile

    import rasterio
    from rasterio.transform import from_origin

    tmp = Path(tempfile.mkdtemp())
    res = 4.0 / 111000.0
    w = int((BBOX[3] - BBOX[1]) / res) + 1
    h = int((BBOX[2] - BBOX[0]) / res) + 1
    data = np.zeros((h, w), dtype=np.float32)
    tr = from_origin(BBOX[1], BBOX[2], res, res)
    # A 40 m × 40 m footprint around local (100, 100).
    lat, lon = to_latlon(100.0, 100.0)
    col, row = int((lon - BBOX[1]) / res), int((BBOX[2] - lat) / res)
    data[row - 5:row + 6, col - 5:col + 6] = 30.0
    tif = tmp / "t.tif"
    with rasterio.open(tif, "w", driver="GTiff", width=w, height=h, count=1, dtype="float32", crs="EPSG:4326", transform=tr) as dst:
        dst.write(data, 1)
    cdir = tmp / "chunks"
    cdir.mkdir()
    fp = [80, 80, 120, 80, 120, 120, 80, 120]
    (cdir / "c_0_0.json").write_text(json.dumps({"blds": [{"p": fp, "h": 9.0}, {"p": [2000, 2000, 2010, 2000, 2010, 2010], "h": 7.0}]}))
    apply(tif, chunks_dir=cdir)
    out = json.loads((cdir / "c_0_0.json").read_text())["blds"]
    ok = abs(out[0]["h"] - 30.0) < 0.5 and out[1]["h"] == 7.0 and out[0].get("hs") == "gob25d"
    print("selftest", "PASS" if ok else "FAIL", out)
    return 0 if ok else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tif", type=Path, default=DEFAULT_TIF)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    if not a.tif.exists():
        sys.exit(f"Missing {a.tif} — export it from Earth Engine first (see this file's docstring).")
    apply(a.tif, a.dry_run)
