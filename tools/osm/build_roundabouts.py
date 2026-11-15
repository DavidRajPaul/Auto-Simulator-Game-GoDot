#!/usr/bin/env python3
"""Chennai's real roundabouts inside the map box: a raised, kerbed traffic island in every ring.

osm2streets draws a roundabout's ring of carriageway but leaves the middle as bare open ground the
auto could cut straight across (owner, Nov 15: "go through the real roundabouts in Chennai and
implement them"). This pass finds each ring and fills its hole with an island:

  * every OSM `junction=roundabout` ring in the extract (Temple Tower roundabout in Nandanam, the
    College Road circle in Nungambakkam, CIT Nagar), plus
  * REAL_CIRCLES - circles OSM maps only as loose one-way links: Gemini Circle under the Anna
    Flyover, the "circle roundabout below the centre of the flyover" with two identical statues of
    a man controlling a horse (put up when horse racing was banned) and fountains on landscaped
    traffic islands (Wikipedia: Anna Flyover).

The island outline comes from the DRAWN surfaces (0.5 m raster of road / junction / lane / walk
triangles at ground level; flyover decks "_up" don't count): rays from the centre stop at the first
surface, so the kerb sits exactly on the edge of the ring road. A site whose rays escape (no closed
ring) is skipped with a warning.

Output: dress "islands" = [[kind, cx, cz, yaw, x0, z0, x1, z1, ...], ...] in the chunk holding the centre
(drawn + collided by WorldChunkStreamer._islands, no draw calls), and data/world/roundabouts.json
(for tests / the map). Parking, stalls, carts, poles, medians and buildings inside an island are
removed; trees are kept except where a statue or fountain stands. Idempotent.
Run after build_road_works.py (rebuild_after_streets.py does), before build_plots.py.
"""
from __future__ import annotations

import gzip
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_world import project  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
RAW = ROOT / "data" / "osm" / "chennai_mvp.osm.json.gz"
CHUNK = 250.0
RES = 0.5
BOX = 90.0            # half-size of the raster around a site (m)
RAYS = 96
MAX_R = 42.0          # a ray longer than this escaped the ring: not a closed roundabout
MIN_R = 1.6           # smaller holes are a mini-roundabout dot, not an island
INSET = 0.45          # kerb face sits this far inside the drawn road edge
SURF = ("road", "junction", "lane", "centre", "walk")

# Circles OSM doesn't tag as roundabouts. kind picks the centre-piece (WorldChunkStreamer._islands).
REAL_CIRCLES = [
    # The game draws the Anna Flyover flat, across the circle, so Gemini becomes one island each
    # side of it with one horse statue on each ("horse" islands, back to back).
    {"name": "Gemini Circle", "lat": 13.05238, "lon": 80.25104, "kind": "gemini"},
]
# Named OSM rings (by any way id of the ring) - everything else is a plain "garden" island.
OSM_NAMES = {
    214148755: "Temple Tower roundabout, Nandanam",
    1409787446: "Temple Tower roundabout, Nandanam",
    701779251: "College Road circle, Nungambakkam",
    1237237480: "CIT Nagar roundabout",
}


def osm_sites() -> list[dict]:
    with gzip.open(RAW, "rt", encoding="utf-8") as f:
        elements = json.load(f)["elements"]
    rings = []
    for e in elements:
        if e.get("type") == "way" and e.get("tags", {}).get("junction") == "roundabout":
            pts = [project(g["lat"], g["lon"]) for g in e.get("geometry") or []]
            if len(pts) >= 3:
                rings.append((e["id"], pts))
    sites: list[dict] = []
    for wid, pts in rings:
        # Halves of one ring (two open ways) merge into one site.
        cx, cz = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
        for s in sites:
            if math.hypot(s["_sx"] / s["_n"] - cx, s["_sz"] / s["_n"] - cz) < 40.0:
                s["_pts"].extend(pts)
                s["_sx"] += cx
                s["_sz"] += cz
                s["_n"] += 1
                break
        else:
            sites.append({"name": OSM_NAMES.get(wid, f"roundabout {wid}"), "kind": "garden", "osm": wid,
                          "_pts": list(pts), "_sx": cx, "_sz": cz, "_n": 1})
    out = []
    for s in sites:
        pts = s["_pts"]
        # Centre of the ring's bounding box: robust when the two halves have different vertex counts.
        xs, zs = [p[0] for p in pts], [p[1] for p in pts]
        out.append({"name": s["name"], "kind": s["kind"], "osm": s["osm"],
                    "x": (min(xs) + max(xs)) / 2, "z": (min(zs) + max(zs)) / 2})
    return out


def load_surfaces(manifest: dict) -> list[list[tuple[float, float]]]:
    tris = []
    for ch in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for kind, part in d.get("surf", {}).items():
            # Flyover decks ("_up") count too: the game draws them flat on the ground, so an island
            # under one would block the flyover. Gemini's circle is split by the Anna Flyover.
            if kind.removesuffix("_up") not in SURF:
                continue
            v, idx = part["v"], part["i"]
            for k in range(0, len(idx), 3):
                tris.append([(v[2 * idx[k + m]], v[2 * idx[k + m] + 1]) for m in range(3)])
    return tris


def island_outline(cx: float, cz: float, tris: list) -> list[tuple[float, float]] | None:
    n = int(2 * BOX / RES)
    img = Image.new("L", (n, n), 0)
    dr = ImageDraw.Draw(img)
    x0, z0 = cx - BOX, cz - BOX
    for t in tris:
        if all(abs(p[0] - cx) > BOX + 5 or abs(p[1] - cz) > BOX + 5 for p in t):
            continue
        dr.polygon([((p[0] - x0) / RES, (p[1] - z0) / RES) for p in t], fill=255)
    px = img.load()
    if px[n // 2, n // 2]:
        return None
    radii = []
    for k in range(RAYS):
        a = math.tau * k / RAYS
        dx, dz = math.cos(a), math.sin(a)
        r = 0.0
        while r < MAX_R:
            i, j = int((cx + dx * r - x0) / RES), int((cz + dz * r - z0) / RES)
            if px[i, j]:
                break
            r += RES * 0.5
        if r >= MAX_R:
            return None
        radii.append(r)
    # Median of 3 knocks out single-ray notches (a lane-marking gap, a stray triangle seam).
    sm = [sorted((radii[k - 1], radii[k], radii[(k + 1) % RAYS]))[1] for k in range(RAYS)]
    if min(sm) - INSET < MIN_R:
        return None
    out = []
    for k, r in enumerate(sm):
        a = math.tau * k / RAYS
        out.append((round(cx + math.cos(a) * (r - INSET), 2), round(cz + math.sin(a) * (r - INSET), 2)))
    # Douglas-Peucker on the closed ring: the 0.5 m raster leaves a staircase along straight kerbs
    # (the flyover edge at Gemini); 0.3 m tolerance straightens it without cutting into the road.
    return simplify_ring(out, 0.3)


def simplify_ring(pts: list, tol: float) -> list:
    far = max(range(len(pts)), key=lambda k: math.dist(pts[0], pts[k]))

    def rdp(seq: list) -> list:
        if len(seq) < 3:
            return seq
        (ax, az), (bx, bz) = seq[0], seq[-1]
        L = math.hypot(bx - ax, bz - az) or 1e-9
        d = [abs((bx - ax) * (az - z) - (ax - x) * (bz - az)) / L for x, z in seq[1:-1]]
        k = max(range(len(d)), key=d.__getitem__)
        if d[k] <= tol:
            return [seq[0], seq[-1]]
        return rdp(seq[:k + 2])[:-1] + rdp(seq[k + 1:])

    return rdp(pts[:far + 1])[:-1] + rdp(pts[far:] + [pts[0]])[:-1]


def inside(x: float, z: float, poly: list[tuple[float, float]]) -> bool:
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
            c = not c
        j = i
    return c


def centroid(poly: list) -> tuple[float, float]:
    a2 = gx = gz = 0.0
    for k in range(len(poly)):
        (x0, z0), (x1, z1) = poly[k - 1], poly[k]
        c = x0 * z1 - x1 * z0
        a2 += c
        gx += (x0 + x1) * c
        gz += (z0 + z1) * c
    if abs(a2) < 1e-6:
        return sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly)
    return gx / (3 * a2), gz / (3 * a2)


def settle(x: float, z: float, tris: list) -> tuple[float, float, list] | None:
    """Outline around (x, z), re-cast from its own centroid (OSM's centre of a circle is often off
    to one side, which skews the rays)."""
    poly = island_outline(x, z, tris)
    if poly is None:
        return None
    for _ in range(2):
        gx, gz = centroid(poly)
        again = island_outline(gx, gz, tris)
        if not again:
            break
        poly, x, z = again, gx, gz
    return x, z, poly


def pieces_for(site: dict, tris: list) -> list[tuple[str, float, float, float, list]]:
    """(kind, x, z, yaw, outline) islands for one site. A circle whose middle is road (Gemini: the
    flyover runs across it) becomes one island per free side."""
    got = settle(site["x"], site["z"], tris)
    if got and site["kind"] != "gemini":
        return [(site["kind"], got[0], got[1], 0.0, got[2])]
    seeds = [(site["x"], site["z"])] if got else []
    for r in (7.0, 11.0, 15.0):
        for k in range(12):
            a = math.tau * k / 12
            seeds.append((site["x"] + math.cos(a) * r, site["z"] + math.sin(a) * r))
    out: list = []
    for sx, sz in seeds:
        got = settle(sx, sz, tris)
        if not got or any(inside(got[0], got[1], q[4]) or inside(sx, sz, q[4]) for q in out):
            continue
        x, z, poly = got
        if math.hypot(x - site["x"], z - site["z"]) > MAX_R:
            continue
        # The statue faces away from the middle of the circle, so the pair stand back to back.
        yaw = math.atan2(z - site["z"], x - site["x"])
        kind = "horse" if site["kind"] == "gemini" else site["kind"]
        out.append((kind, x, z, yaw, poly))
    if site["kind"] == "gemini":
        # The two biggest sides get the statues (the fountains sit on those islands too).
        out.sort(key=lambda q: -poly_area(q[4]))
        out = out[:2] + [("garden", q[1], q[2], 0.0, q[4]) for q in out[2:]]
    return out


def poly_area(poly: list) -> float:
    return 0.5 * abs(sum(poly[k - 1][0] * poly[k][1] - poly[k][0] * poly[k - 1][1] for k in range(len(poly))))


def clear_spots(kind: str, x: float, z: float, poly: list) -> list[tuple[float, float, float]]:
    """Spots (x, z, radius) the centre-piece takes, where trees must not stand."""
    r = min(math.hypot(p[0] - x, p[1] - z) for p in poly)
    if kind == "horse":
        return [(x, z, 8.0)]
    return [(x, z, max(1.5, min(3.0, r * 0.45)))]


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    tris = load_surfaces(manifest)
    sites = osm_sites()
    for c in REAL_CIRCLES:
        x, z = project(c["lat"], c["lon"])
        sites.append({"name": c["name"], "kind": c["kind"], "osm": 0, "x": x, "z": z})
    dress: dict[tuple[int, int], dict] = {}
    chunks: dict[tuple[int, int], dict] = {}

    def dress_of(k: tuple[int, int]) -> dict:
        if k not in dress:
            p = WORLD / "dress" / f"c_{k[0]}_{k[1]}.json"
            dress[k] = json.loads(p.read_text()) if p.exists() else {}
        return dress[k]

    # Every dress file loses its old islands first (idempotent).
    for ch in manifest["chunks"]:
        dress_of((ch[0], ch[1])).pop("islands", None)
    report, removed = [], 0
    for s in sites:
        pieces = pieces_for(s, tris)
        if not pieces:
            print(f"  WARNING: {s['name']}: no closed ring around ({s['x']:.0f}, {s['z']:.0f}), skipped")
            continue
        for kind, x, z, yaw, poly in pieces:
            removed += place(kind, x, z, yaw, poly, dress_of, chunks)
            report.append({"name": s["name"], "kind": kind, "osm": s["osm"], "x": round(x, 2), "z": round(z, 2),
                           "yaw": round(yaw, 3), "area_m2": round(poly_area(poly), 1),
                           "r_min": round(min(math.hypot(p[0] - x, p[1] - z) for p in poly), 2),
                           "poly": [v for p in poly for v in p]})
            print(f"  {s['name']}: {kind} island {poly_area(poly):.0f} m2, {len(poly)} kerb points")
    for k, d in dress.items():
        p = WORLD / "dress" / f"c_{k[0]}_{k[1]}.json"
        if d or p.exists():
            p.write_text(json.dumps(d, separators=(",", ":")))
    for k, c in chunks.items():
        (WORLD / "chunks" / f"c_{k[0]}_{k[1]}.json").write_text(json.dumps(c, separators=(",", ":")))
    (WORLD / "roundabouts.json").write_text(json.dumps(
        {"_note": "made by tools/osm/build_roundabouts.py", "islands": report}, separators=(",", ":")))
    print(f"roundabouts: {len(report)} islands, {removed} items cleared off them")
    return 0


def place(kind: str, x: float, z: float, yaw: float, poly: list, dress_of, chunks: dict) -> int:
    """Write one island into its chunk's dress and clear what can't stand on it."""
    removed = 0
    key = (math.floor(x / CHUNK), math.floor(z / CHUNK))
    dress_of(key).setdefault("islands", []).append([kind, round(x, 2), round(z, 2), round(yaw, 3)]
                                                   + [v for p in poly for v in p])
    clear = clear_spots(kind, x, z, poly)
    xs, zs = [p[0] for p in poly], [p[1] for p in poly]
    for i in range(math.floor((min(xs) - 1) / CHUNK), math.floor((max(xs) + 1) / CHUNK) + 1):
        for j in range(math.floor((min(zs) - 1) / CHUNK), math.floor((max(zs) + 1) / CHUNK) + 1):
            d = dress_of((i, j))
            for k in ("parking", "stalls", "carts", "poles", "xfmr", "barricades", "dogs", "bunting",
                      "shop_people", "kolams"):
                if k in d:
                    before = len(d[k])
                    d[k] = [it for it in d[k] if not inside(float(it[0]), float(it[1]), poly)]
                    removed += before - len(d[k])
            if "wires" in d:
                d["wires"] = [w for w in d["wires"] if not (inside(w[0], w[1], poly) or inside(w[2], w[3], poly))]
            if "trees" in d:
                d["trees"] = [t for t in d["trees"]
                              if not any(math.hypot(t[0] - fx, t[1] - fz) < fr for fx, fz, fr in clear)]
            if "medians" in d:
                d["medians"] = [m for m in d["medians"]
                                if not any(inside(m[q], m[q + 1], poly) for q in range(1, len(m) - 2, 3))]
            cp = WORLD / "chunks" / f"c_{i}_{j}.json"
            if cp.exists():
                if (i, j) not in chunks:
                    chunks[(i, j)] = json.loads(cp.read_text())
                keep = []
                for b in chunks[(i, j)].get("blds", []):
                    bp = b["p"]
                    if inside(sum(bp[0::2]) / (len(bp) / 2), sum(bp[1::2]) / (len(bp) / 2), poly):
                        removed += 1
                    else:
                        keep.append(b)
                chunks[(i, j)]["blds"] = keep
    return removed


if __name__ == "__main__":
    sys.exit(main())
