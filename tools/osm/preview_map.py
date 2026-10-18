#!/usr/bin/env python3
"""Render a top-down PNG of the built world (needs Pillow). Usage: python3 tools/osm/preview_map.py out.png"""
import json, glob, sys
from PIL import Image, ImageDraw, ImageFont
W = "data/world/"
m = json.load(open(W+"manifest.json")); a = json.load(open(W+"areas.json"))
x0,z0,x1,z1 = m["bounds"]; pad=150; S = 0.6
img = Image.new("RGB", (int((x1-x0+2*pad)*S), int((z1-z0+2*pad)*S)), (226,214,190))
d = ImageDraw.Draw(img)
P = lambda x,z: ((x-x0+pad)*S, (z-z0+pad)*S)
for k,c in (("sea",(70,120,170)),("beach",(240,220,160)),("park",(140,190,110)),("water",(80,140,190))):
    for poly in a[k]: d.polygon([P(*p) for p in poly], fill=c)
cols = {"trunk":(90,90,95),"primary":(105,105,110),"secondary":(120,120,125),"tertiary":(135,135,140)}
for f in glob.glob(W+"chunks/*.json"):
    c = json.load(open(f))
    for b in c["buildings"]:
        r = max(b["w"],b["d"])/2*S; x,y = P(b["x"],b["z"]); h = b["h"]
        d.rectangle([x-r*0.7,y-r*0.7,x+r*0.7,y+r*0.7], fill=(200-int(h*3),170-int(h*2),150))
    for r in c["roads"]:
        d.line([P(*p) for p in r["pts"]], fill=cols.get(r["c"],(150,150,150)), width=max(1,int(r["w"]*S)))
for l in m["landmarks"]:
    x,y = P(l["x"],l["z"]); d.ellipse([x-7,y-7,x+7,y+7], fill=(220,40,40)); d.text((x+9,y-6), l["name"], fill=(0,0,0))
for s in m["auto_stands"]:
    x,y = P(s["x"],s["z"]); d.rectangle([x-6,y-6,x+6,y+6], fill=(250,200,0), outline=(0,0,0)); d.text((x+9,y+4), s["name"], fill=(60,40,0))
for z in m["zones"]:
    x,y = P(z["x"],z["z"]); r=z["r"]*S; d.ellipse([x-r,y-r,x+r,y+r], outline=(200,0,120), width=2); d.text((x-40,y-r-14), z["name"], fill=(150,0,90))
img.save(sys.argv[1]); print(img.size)
