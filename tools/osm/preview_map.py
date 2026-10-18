#!/usr/bin/env python3
"""Render a top-down PNG of the built world (needs Pillow).
Usage: python3 tools/osm/preview_map.py out.png [scale px/m] [x0 z0 x1 z1 crop in metres]"""
import glob
import json
import sys

from PIL import Image, ImageDraw

W = "data/world/"
m = json.load(open(W + "manifest.json"))
a = json.load(open(W + "areas.json"))
S = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
x0, z0, x1, z1 = [float(v) for v in sys.argv[3:7]] if len(sys.argv) > 6 else m["bounds"]
pad = 50
img = Image.new("RGB", (int((x1 - x0 + 2 * pad) * S), int((z1 - z0 + 2 * pad) * S)), (180, 168, 146))
d = ImageDraw.Draw(img)
P = lambda x, z: ((x - x0 + pad) * S, (z - z0 + pad) * S)  # noqa: E731
for k, c in (("sea", (70, 120, 170)), ("beach", (240, 220, 160)), ("park", (140, 190, 110)), ("water", (80, 140, 190))):
    for poly in a[k]:
        d.polygon([P(*p) for p in poly], fill=c)
SURF = {"walk": (205, 198, 186), "junction": (70, 70, 74), "road": (80, 80, 84), "lane": (235, 235, 235),
        "centre": (240, 220, 120)}
ROAD_COL = {"trunk": (90, 90, 95), "primary": (105, 105, 110), "secondary": (120, 120, 125), "tertiary": (135, 135, 140)}
for f in sorted(glob.glob(W + "chunks/*.json")):
    c = json.load(open(f))
    for kind in ("walk", "walk_up", "junction", "road", "road_up", "lane", "centre", "centre_up", "lane_up"):
        s = c.get("surf", {}).get(kind)
        if not s:
            continue
        v, idx = s["v"], s["i"]
        col = SURF[kind.replace("_up", "")]
        for t in range(0, len(idx), 3):
            d.polygon([P(v[2 * idx[t + q]], v[2 * idx[t + q] + 1]) for q in range(3)], fill=col)
    for r in c.get("roads", []):
        d.line([P(*p) for p in r["pts"]], fill=ROAD_COL.get(r["c"], (150, 150, 150)), width=max(1, int(r["w"] * S)))
    for b in c.get("blds", []):
        p = b["p"]
        h = b["h"]
        shade = max(0, 200 - int(h * 3))
        col = (shade, shade - 20 if b.get("f") else shade - 40, 150 if not b.get("f") else 200)
        d.polygon([P(p[i], p[i + 1]) for i in range(0, len(p), 2)], fill=col)
for l in m["landmarks"]:
    x, y = P(l["x"], l["z"])
    d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=(220, 40, 40))
    d.text((x + 9, y - 6), l["name"], fill=(0, 0, 0))
for s in m["auto_stands"]:
    x, y = P(s["x"], s["z"])
    d.rectangle([x - 6, y - 6, x + 6, y + 6], fill=(250, 200, 0), outline=(0, 0, 0))
    d.text((x + 9, y + 4), s["name"], fill=(60, 40, 0))
for s in m.get("services", []):
    x, y = P(s["x"], s["z"])
    d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(0, 160, 80) if s["kind"] != "garage" else (140, 80, 30))
img.save(sys.argv[1])
print(img.size)
