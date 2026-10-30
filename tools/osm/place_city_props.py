#!/usr/bin/env python3
"""Finds free ground for the baked Chennai landmark models and writes data/world/city_props.json.

  water_tower   TWAD overhead tanks: one near each neighbourhood, on open ground clear of
                buildings and roads.
  slum_cluster  canal-side settlements: along the Buckingham Canal / Cooum banks, long side
                parallel to the water, canal wall facing it.
  chennai_central  Chennai Central at its real position (just north of the playable map),
                seen on the skyline from the north end of Kamarajar Salai and Napier Bridge.

Reads only generated world data (chunks, road graph, areas) - re-run after an OSM rebuild.
Usage: python3 tools/osm/place_city_props.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
OUT = WORLD / "city_props.json"

# Real Chennai Central (13.0827 N, 80.2757 E) through the build_world projection.
ORIGIN = (13.049, 80.259)
M_PER_DEG_LAT = 110540.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(ORIGIN[0]))


def project(lat: float, lon: float) -> tuple[float, float]:
    return ((lon - ORIGIN[1]) * M_PER_DEG_LON, -(lat - ORIGIN[0]) * M_PER_DEG_LAT)


def load():
    manifest = json.loads((WORLD / "manifest.json").read_text())
    blds = []
    for c in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{c[0]}_{c[1]}.json").read_text())
        for b in d.get("blds", []):
            p = b["p"]
            pts = [(p[i], p[i + 1]) for i in range(0, len(p), 2)]
            xs = [q[0] for q in pts]
            zs = [q[1] for q in pts]
            blds.append((min(xs), min(zs), max(xs), max(zs), pts))
    graph = json.loads((WORLD / "road_graph.json").read_text())
    segs = []
    for e in graph["edges"]:
        pts = e["pts"]
        for i in range(1, len(pts)):
            segs.append((pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], float(e["w"]) * 0.5))
    areas = json.loads((WORLD / "areas.json").read_text())
    return manifest, blds, segs, areas


class Grid:
    def __init__(self, items, box, cell=50.0):
        self.cell = cell
        self.g: dict = {}
        for it in items:
            x0, z0, x1, z1 = box(it)
            for i in range(int(math.floor(x0 / cell)), int(math.floor(x1 / cell)) + 1):
                for j in range(int(math.floor(z0 / cell)), int(math.floor(z1 / cell)) + 1):
                    self.g.setdefault((i, j), []).append(it)

    def near(self, x0, z0, x1, z1):
        seen = set()
        for i in range(int(math.floor(x0 / self.cell)), int(math.floor(x1 / self.cell)) + 1):
            for j in range(int(math.floor(z0 / self.cell)), int(math.floor(z1 / self.cell)) + 1):
                for it in self.g.get((i, j), []):
                    if id(it) not in seen:
                        seen.add(id(it))
                        yield it


def seg_dist(px, pz, s) -> float:
    ax, az, bx, bz, _ = s
    dx, dz = bx - ax, bz - az
    L = dx * dx + dz * dz
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L))
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))


def point_in(px, pz, poly) -> bool:
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / (zj - zi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def rect_corners(cx, cz, yaw, hx, hz):
    c, s = math.cos(yaw), math.sin(yaw)
    out = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1), (0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
        lx, lz = sx * hx, sz * hz
        out.append((cx + lx * c + lz * s, cz - lx * s + lz * c))
    return out


def free(cx, cz, yaw, hx, hz, bgrid, sgrid, water, road_gap=3.0) -> bool:
    r = math.hypot(hx, hz)
    for b in bgrid.near(cx - r, cz - r, cx + r, cz + r):
        if b[2] < cx - r or b[0] > cx + r or b[3] < cz - r or b[1] > cz + r:
            continue
        for (px, pz) in rect_corners(cx, cz, yaw, hx, hz):
            if point_in(px, pz, b[4]):
                return False
        for (bx, bz) in b[4]:
            # building corner inside our rectangle
            c, s = math.cos(-yaw), math.sin(-yaw)
            lx = (bx - cx) * c + (bz - cz) * s
            lz = -(bx - cx) * s + (bz - cz) * c
            if abs(lx) < hx and abs(lz) < hz:
                return False
    for sg in sgrid.near(cx - r - 20, cz - r - 20, cx + r + 20, cz + r + 20):
        for (px, pz) in rect_corners(cx, cz, yaw, hx, hz):
            if seg_dist(px, pz, sg) < sg[4] + road_gap:
                return False
    for poly in water:
        for (px, pz) in rect_corners(cx, cz, yaw, hx, hz):
            if point_in(px, pz, poly):
                return False
    return True


def clear_buildings(manifest, cx, cz, yaw, hx, hz) -> int:
    """Remove generated buildings overlapping a rotated rectangle from the chunk files."""
    c, s = math.cos(-yaw), math.sin(-yaw)

    def inside(x, z):
        lx = (x - cx) * c + (z - cz) * s
        lz = -(x - cx) * s + (z - cz) * c
        return abs(lx) < hx and abs(lz) < hz
    removed = 0
    corners = rect_corners(cx, cz, yaw, hx, hz)
    for ch in manifest["chunks"]:
        path = WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json"
        d = json.loads(path.read_text())
        keep = []
        for b in d.get("blds", []):
            pts = [(b["p"][i], b["p"][i + 1]) for i in range(0, len(b["p"]), 2)]
            hit = any(inside(x, z) for x, z in pts) or any(point_in(x, z, pts) for x, z in corners)
            if hit:
                removed += 1
            else:
                keep.append(b)
        if len(keep) != len(d.get("blds", [])):
            d["blds"] = keep
            path.write_text(json.dumps(d, separators=(",", ":")))
    return removed


def main() -> int:
    manifest, blds, segs, areas = load()
    bgrid = Grid(blds, lambda b: (b[0], b[1], b[2], b[3]))
    sgrid = Grid(segs, lambda s: (min(s[0], s[2]) - s[4], min(s[1], s[3]) - s[4], max(s[0], s[2]) + s[4], max(s[1], s[3]) + s[4]))
    water = [[(p[0], p[1]) for p in poly] for poly in areas.get("water", []) + areas.get("sea", []) + areas.get("beach", [])]
    marks = [(float(l["x"]), float(l["z"])) for l in manifest.get("landmarks", [])]
    marks += [(float(s["x"]), float(s["z"])) for s in manifest.get("auto_stands", [])]

    def clear_of_marks(px: float, pz: float, r: float) -> bool:
        return all(math.hypot(px - mx, pz - mz) > r for mx, mz in marks)
    meta = json.loads((ROOT / "assets" / "models" / "city" / "city_models.json").read_text())
    props = []
    # These are real-world locations in the SAME fixed coordinate origin as the old city.
    # Central is no longer a distant skyline illusion: it is physically reachable.
    cx, cz = project(13.0827, 80.2757)
    props.append({"model": "chennai_central", "x": round(cx, 1), "z": round(cz, 1),
                  "yaw": round(math.pi * 0.5, 3), "landmark": True, "scale": 1.0})
    rx, rz = project(13.0817545, 80.2716236)
    props.append({"model": "ripon_building", "x": round(rx, 2), "z": round(rz, 2),
                  "yaw": round(math.pi, 3), "scale": 52.0,
                  "asset": "res://assets/models/city/ripon_building.glb", "landmark": True})
    # Imported landmarks replace (rather than overlap) OSM/procedural building meshes.
    # Collision shapes are applied separately by the game.
    clear_buildings(manifest, cx, cz, math.pi * 0.5, 38.0, 98.0)
    clear_buildings(manifest, rx, rz, math.pi, 27.0, 23.0)
    # Water towers: near each zone centre, spiralling out to the first free spot.
    wt = meta["water_tower"]["size_m"]
    for z in manifest["zones"]:
        placed = False
        for ring in range(20, 80):
            rr = ring * 12.0
            for k in range(int(2 * math.pi * rr / 12.0) + 1):
                a = k * 12.0 / rr
                px, pz = z["x"] + math.cos(a) * rr, z["z"] + math.sin(a) * rr
                if clear_of_marks(px, pz, 150.0) and free(px, pz, 0.0, wt[0] * 0.5 + 2.0, wt[2] * 0.5 + 2.0, bgrid, sgrid, water, 4.0):
                    props.append({"model": "water_tower", "x": round(px, 1), "z": round(pz, 1), "yaw": round(a, 3),
                                  "zone": z["id"]})
                    placed = True
                    break
            if placed:
                break
    # Slums: walk the long canal/river polygons, try spots just off the bank on the land side.
    sl = meta["slum_cluster"]["size_m"]
    hx, hz = sl[0] * 0.5, sl[2] * 0.5
    placed = []
    for poly in sorted(areas.get("water", []), key=lambda p: -len(p)):
        if len(poly) < 8:
            continue
        for i in range(0, len(poly)):
            if len(placed) >= 10:
                break
            ax, az = poly[i - 1]
            bx, bz = poly[i]
            L = math.hypot(bx - ax, bz - az)
            if L < 12.0:
                continue
            mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
            nx, nz = (bz - az) / L, -(bx - ax) / L
            for sign in (1.0, -1.0):
                px, pz = mx + nx * sign * (hz + 3.0), mz + nz * sign * (hz + 3.0)
                if point_in(px, pz, poly):
                    continue
                if any(math.hypot(px - q[0], pz - q[1]) < 250.0 for q in placed):
                    continue
                # Long side along the bank; the model's canal wall (+Z side) faces the water.
                yaw = math.atan2(-sign * nx, -sign * nz)
                if clear_of_marks(px, pz, 150.0) and free(px, pz, yaw, hx, hz, bgrid, sgrid, water, 2.0):
                    props.append({"model": "slum_cluster", "x": round(px, 1), "z": round(pz, 1), "yaw": round(yaw, 3)})
                    placed.append((px, pz))
                    break
    # LPG autogas stations: one per LPG service point, forecourt (model -Z side, with the sign
    # tower) facing the road the bunk is on, set just back from the kerb on a free lot nearby.
    if "gas_station" in meta:
        gsz = meta["gas_station"]["size_m"]
        ghx, ghz = gsz[0] * 0.5, gsz[2] * 0.5
        for sv in manifest.get("services", []):
            if sv["kind"] != "lpg":
                continue
            rx, rz = float(sv.get("road_x", sv["x"])), float(sv.get("road_z", sv["z"]))
            best = None
            for sg in sgrid.near(rx - 30, rz - 30, rx + 30, rz + 30):
                d = seg_dist(rx, rz, sg)
                if best is None or d < best[0]:
                    best = (d, sg)
            if best is None:
                continue
            ax, az, bx, bz, hw = best[1]
            L = math.hypot(bx - ax, bz - az) or 1.0
            dx, dz = (bx - ax) / L, (bz - az) / L
            done = False
            # Full size first; dense bazaars (T. Nagar) get the compact forecourt.
            for scale in (1.0, 0.8, 0.65):
                hx2, hz2 = ghx * scale, ghz * scale
                for k in range(0, 31):
                    slide = (k // 2) * 6.0 * (1 if k % 2 == 0 else -1)
                    for side in (1.0, -1.0):
                        nx, nz = -dz * side, dx * side
                        off = hw + 2.0 + hz2
                        px, pz = rx + dx * slide + nx * off, rz + dz * slide + nz * off
                        yaw = math.atan2(nx, nz)  # local -Z (forecourt) faces the road
                        if clear_of_marks(px, pz, 30.0) and free(px, pz, yaw, hx2, hz2, bgrid, sgrid, water, 0.5):
                            fx, fz = px - nx * hz2 * 0.45, pz - nz * hz2 * 0.45
                            props.append({"model": "gas_station", "x": round(px, 1), "z": round(pz, 1), "yaw": round(yaw, 3),
                                          "scale": scale, "service": sv["id"], "fx": round(fx, 1), "fz": round(fz, 1)})
                            done = True
                            break
                    if done:
                        break
                if done:
                    break
            if not done:
                # Dense bazaar: no empty lot. Take the plot like a real bunk would: compact station
                # on the frontage, generated buildings under it removed from the chunk data.
                for k in range(0, 31):
                    slide = (k // 2) * 6.0 * (1 if k % 2 == 0 else -1)
                    for side in (1.0, -1.0):
                        nx, nz = -dz * side, dx * side
                        hx2, hz2 = ghx * 0.65, ghz * 0.65
                        off = hw + 2.0 + hz2
                        px, pz = rx + dx * slide + nx * off, rz + dz * slide + nz * off
                        yaw = math.atan2(nx, nz)
                        if clear_of_marks(px, pz, 30.0) and free(px, pz, yaw, hx2, hz2, Grid([], lambda b: b), sgrid, water, 0.5):
                            fx, fz = px - nx * hz2 * 0.45, pz - nz * hz2 * 0.45
                            props.append({"model": "gas_station", "x": round(px, 1), "z": round(pz, 1), "yaw": round(yaw, 3),
                                          "scale": 0.65, "service": sv["id"], "fx": round(fx, 1), "fz": round(fz, 1)})
                            cleared = clear_buildings(manifest, px, pz, yaw, hx2 + 1.0, hz2 + 1.0)
                            print(f"  gas_station at {sv['id']}: compact, {cleared} buildings cleared for the lot")
                            done = True
                            break
                    if done:
                        break
            if not done:
                print(f"  gas_station: no lot near {sv['id']}, keeps the marker")
    # Low-risk traffic-management barriers on the pavement side of busy station roads.
    # These are GAMEPLAY roadside safety props, not claims of real police road closures.
    # Candidate locations come from the expanded street graph and are rejected when
    # they intersect the road carriageway, an OSM building, or water.
    for place_id, lat, lon in (("central", 13.0827, 80.2757),
                               ("ripon", 13.0817545, 80.2716236),
                               ("egmore", 13.0770, 80.2600)):
        tx, tz = project(lat, lon)
        nearby = sorted(
            (seg for seg in segs if seg_dist(tx, tz, seg) < 240.0),
            key=lambda seg: seg_dist(tx, tz, seg))
        placed = []
        for seg in nearby:
            ax, az, bx, bz, half_width = seg
            dx, dz = bx - ax, bz - az
            length = math.hypot(dx, dz)
            if length < 10.0:
                continue
            nx, nz = -dz / length, dx / length
            mx, mz = (ax + bx) / 2.0, (az + bz) / 2.0
            for side in (1.0, -1.0):
                off = half_width + 4.2
                px, pz = mx + side * nx * off, mz + side * nz * off
                if math.hypot(px - tx, pz - tz) > 225.0:
                    continue
                if any(math.hypot(px - x, pz - z) < 42.0 for x, z in placed):
                    continue
                yaw = math.atan2(dx, dz)
                if not free(px, pz, yaw, 1.0, 0.5, bgrid, sgrid, water, 0.7):
                    continue
                props.append({
                    "model": "barricade/roadside_barricade",
                    "x": round(px, 1), "z": round(pz, 1),
                    "yaw": round(yaw, 3), "scale": 1.0,
                    "barricade_type": "yellow_black",
                    "zone": place_id, "generated_safety_barrier": True
                })
                placed.append((px, pz))
                break
            if len(placed) >= 3:
                break
    # Deterministic biryani stalls in busy mixed-use neighborhoods. Each candidate
    # is beside an actual OSM road, with a checked 9m x 7m footprint for the
    # stall, patrons and parked scooters. No fabricated shop-name/geolocation.
    # Keep away from landmark compounds and from other placed roadside props.
    biryani_zones = ("t_nagar", "mylapore", "anna_salai", "egmore", "central")
    for zone_id in biryani_zones:
        zone = next((z for z in manifest.get("zones", []) if z["id"] == zone_id), None)
        if zone is None:
            continue
        zx, zz = float(zone["x"]), float(zone["z"])
        radius = min(500.0, float(zone["r"]) * 0.7)
        candidates = sorted(
            (sg for sg in segs if seg_dist(zx, zz, sg) <= radius),
            key=lambda sg: (int(seg_dist(zx, zz, sg) // 50),
                            round(sg[0], 1), round(sg[1], 1),
                            round(sg[2], 1), round(sg[3], 1)))
        picked = []
        for sg in candidates:
            ax, az, bx, bz, half_width = sg
            length = math.hypot(bx - ax, bz - az)
            if length < 20.0:
                continue
            dx, dz = (bx - ax) / length, (bz - az) / length
            for fraction in (0.35, 0.65):
                mx = ax + fraction * (bx - ax)
                mz = az + fraction * (bz - az)
                for side in (1.0, -1.0):
                    nx, nz = -dz * side, dx * side
                    # Entire stall, customers and bikes must remain outside the carriageway.
                    px = mx + nx * (half_width + 6.8)
                    pz = mz + nz * (half_width + 6.8)
                    if math.hypot(px - zx, pz - zz) > radius:
                        continue
                    if any(math.hypot(px - qx, pz - qz) < 140.0 for qx, qz in picked):
                        continue
                    if any(math.hypot(px - float(p["x"]), pz - float(p["z"])) < 15.0
                           for p in props):
                        continue
                    yaw = math.atan2(nx, nz)
                    if not free(px, pz, yaw, 4.5, 3.5, bgrid, sgrid, water, 1.0):
                        continue
                    props.append({
                        "model": "biryani_shop",
                        "asset": "res://assets/models/city/biryani_shop.glb",
                        "x": round(px, 2), "z": round(pz, 2),
                        "yaw": round(yaw, 3), "scale": 1.0,
                        "zone": zone_id, "biryani_cluster": True,
                        "landmark_footprint": [4.3, 3.0, 3.7]
                    })
                    picked.append((px, pz))
                    break
                if len(picked) >= 2:
                    break
            if len(picked) >= 2:
                break
        print(f"biryani stalls for {zone_id}: {len(picked)}")
    # Keep hand-authored street dressing that the procedural rebuild does not own.
    # Do not copy old Central/Ripon props: they have authoritative coordinates above.
    if OUT.exists():
        prior = json.loads(OUT.read_text()).get("props", [])
        for p in prior:
            if p.get("model") not in ("chennai_central", "ripon_building") and (
                    p.get("tea_cluster") or p.get("parked_two_wheeler")
                    or p.get("maintenance_display") or (p.get("barricade_type") and not p.get("generated_safety_barrier"))):
                props.append(p)
    OUT.write_text(json.dumps({"_note": "made by tools/osm/place_city_props.py", "props": props}, indent=1))
    for p in props:
        print(p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
