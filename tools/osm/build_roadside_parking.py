#!/usr/bin/env python3
"""Deterministic Chennai kerbside parking. Run AFTER build_street_dressing.py.
Adds 'parking' records to existing dress files; never modifies generated roads.
Each record: [x, z, yaw, vehicle_type], where 0=scooter, 1=car, 2=auto.
"""
from __future__ import annotations
import json
import math
import random
from pathlib import Path

WORLD = Path(__file__).resolve().parents[2] / "data/world"
KINDS = {"residential": .64, "living_street": .56, "tertiary": .43,
         "secondary": .20, "primary": .09}
JUNCTION_CLEAR = 15.0
SPACING = 7.5
SEED = 20261031

def inside(x, z, poly):
    hit = False
    for i in range(len(poly)):
        ax, az = poly[i - 1]
        bx, bz = poly[i]
        if (az > z) != (bz > z) and x < (bx-ax)*(z-az)/(bz-az)+ax:
            hit = not hit
    return hit

def main():
    manifest = json.loads((WORLD / "manifest.json").read_text())
    graph = json.loads((WORLD / "road_graph.json").read_text())
    size = float(manifest["chunk_size"])
    zones = manifest.get("zones", [])
    grid = {}
    for c in manifest["chunks"]:
        data = json.loads((WORLD / "chunks" / f"c_{c[0]}_{c[1]}.json").read_text())
        for b in data.get("blds", []):
            flat = b["p"]
            poly = list(zip(flat[::2], flat[1::2]))
            for ix in range(math.floor(min(p[0] for p in poly)/30), math.floor(max(p[0] for p in poly)/30)+1):
                for iz in range(math.floor(min(p[1] for p in poly)/30), math.floor(max(p[1] for p in poly)/30)+1):
                    grid.setdefault((ix, iz), []).append(poly)

    def near_building(x, z, radius):
        # Sampling the swept bounding disc avoids placing a bumper through a facade.
        samples = [(0, 0)] + [(math.cos(a*math.pi/4)*radius, math.sin(a*math.pi/4)*radius) for a in range(8)]
        for dx, dz in samples:
            xx, zz = x+dx, z+dz
            if any(inside(xx, zz, p) for p in grid.get((math.floor(xx/30), math.floor(zz/30)), ())):
                return True
        return False

    def zone_multiplier(x, z):
        for name, value in (("mylapore", 1.2), ("t_nagar", 1.35),
                            ("triplicane", 1.2), ("marina", .55)):
            if any(z0["id"] == name and math.hypot(x-z0["x"], z-z0["z"]) < z0["r"] for z0 in zones):
                return value
        return 1.0

    dress = WORLD/"dress"
    occupied = set()
    out = {}
    placed = 0
    for edge_index, edge in enumerate(graph["edges"]):
        road_class = str(edge["c"])
        if road_class not in KINDS:
            continue
        width = float(edge["w"])
        if width < 5.3:
            continue
        points = edge["pts"]
        lengths = [math.dist(a, b) for a,b in zip(points,points[1:])]
        total = sum(lengths)
        if total < 2*JUNCTION_CLEAR + SPACING:
            continue
        rng = random.Random(SEED + edge_index*7919)
        for side in (-1,1):
            cursor = JUNCTION_CLEAR + rng.uniform(0, SPACING)
            while cursor < total-JUNCTION_CLEAR:
                along = cursor
                for i, length in enumerate(lengths):
                    if along <= length or i == len(lengths)-1:
                        a,b = points[i],points[i+1]
                        t = min(1.0,along/max(length, .0001))
                        dx,dz = (b[0]-a[0])/max(length,.0001),(b[1]-a[1])/max(length,.0001)
                        x,z = a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t
                        break
                    along -= length
                car_length = 2.0
                density = min(.8, KINDS[road_class]*zone_multiplier(x,z))
                if rng.random() < density:
                    # Prefer scooters on narrow Chennai lanes, cars on wider roads.
                    kind = rng.choices((0,1,2), (.72,.21,.07) if width < 8 else (.57,.35,.08))[0]
                    car_width = (0.85, 1.85, 1.55)[kind]
                    car_length = (2.0, 4.2, 2.8)[kind]
                    # Entire vehicle is outside the drivable road ribbon, beside kerb.
                    offset = width/2 + car_width/2 + .30
                    nx,nz = dz*side,-dx*side
                    px,pz = x+nx*offset,z+nz*offset
                    cell = (round(px/3),round(pz/3))
                    if not near_building(px,pz,math.hypot(car_length/2,car_width/2)+.35) and all(
                        (cell[0]+ix,cell[1]+iz) not in occupied for ix in range(-2,3) for iz in range(-2,3)
                    ):
                        # Heading follows tangent, not random world rotations.
                        yaw = math.atan2(-dx,-dz)
                        ck = (math.floor(px/size),math.floor(pz/size))
                        out.setdefault(ck,[]).append([round(px,2),round(pz,2),round(yaw,4),kind])
                        occupied.add(cell)
                        placed += 1
                cursor += car_length + rng.uniform(3.5,8.0)
    # Preserve poles/trees/wires and allow repeatable re-generation.
    for c in manifest["chunks"]:
        ck = (int(c[0]),int(c[1]))
        path = dress/f"c_{ck[0]}_{ck[1]}.json"
        data = json.loads(path.read_text()) if path.exists() else {}
        data["parking"] = out.get(ck,[])
        if data:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(data,separators=(",",":")))
    print(f"Placed {placed} parked vehicles across {len(out)} chunks")

if __name__ == "__main__":
    main()
