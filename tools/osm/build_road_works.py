"""Metro rail works at the Lighthouse, with a closed road and "take diversion" signs.

Chennai Metro Phase 2's Lighthouse–Poonamallee corridor starts at the Lighthouse, and its station
works have turned the Marina end of Kamarajar Salai into a barricaded site. This pass lays out
that scene for the game (data/world/road_works.json, read by scripts/world/RoadWorks.gd):

* SITE — a hoarded station-box work site beside Kamarajar Salai, as close to the Lighthouse as a
  free rectangle allows (no building, no carriageway inside; footpath may be taken over, as the
  real sites do).
* CLOSED — the Foreshore Estate slip off Kamarajar Salai, found by road name + nearness to the
  Lighthouse. Traffic and GPS route around it; the tool checks the rest of the network stays
  connected. Every place the closed road meets an open one gets a row of water-filled
  barriers across it and a ROAD CLOSED board; the main-road approaches get TAKE DIVERSION boards.

Re-run after an OSM rebuild:  python3 tools/osm/build_road_works.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from shapely import affinity
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0
SITE_NEAR = "marina_lighthouse"
SITE_ROAD = "Kamarajar Salai"
CLOSE_ROAD = "Foreshore Estate Promenade"
CLOSE_RADIUS_M = 110.0  # closed pieces of CLOSE_ROAD: within this of the site road's junction
SITE_SIZES = ((26.0, 70.0), (26.0, 60.0), (22.0, 60.0), (18.0, 50.0))  # width, length
ROW_BACK_M = 6.0  # barrier row this far into the closed road from the junction node
DIVERSION_BACK_M = 35.0  # diversion board this far up the main-road approach


def edge_len(e) -> float:
    return sum(math.dist(a, b) for a, b in zip(e["pts"], e["pts"][1:]))


def along(pts, s):
    """Point and unit direction s metres along a polyline (from pts[0])."""
    for a, b in zip(pts, pts[1:]):
        seg = math.dist(a, b)
        if s <= seg or b is pts[-1]:
            t = 0.0 if seg < 1e-6 else min(max(s / seg, 0.0), 1.0)
            d = ((b[0] - a[0]) / max(seg, 1e-6), (b[1] - a[1]) / max(seg, 1e-6))
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), d
        s -= seg
    a, b = pts[-2], pts[-1]
    seg = max(math.dist(a, b), 1e-6)
    return tuple(b), ((b[0] - a[0]) / seg, (b[1] - a[1]) / seg)


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    lm = next(l for l in manifest["landmarks"] if l["id"] == SITE_NEAR)
    centre = (float(lm["x"]), float(lm["z"]))
    graph = json.loads((WORLD / "road_graph.json").read_text())
    edges, nodes = graph["edges"], graph["nodes"]

    # --- what is already on the ground near the Lighthouse -----------------------------------
    blds, roads = [], []
    for ch in manifest["chunks"]:
        if abs((ch[0] + 0.5) * CHUNK - centre[0]) > 2 * CHUNK or abs((ch[1] + 0.5) * CHUNK - centre[1]) > 2 * CHUNK:
            continue
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for b in d.get("blds", []):
            p = b["p"]
            blds.append(Polygon(list(zip(p[0::2], p[1::2]))).buffer(0))
        for kind, part in d.get("surf", {}).items():
            if kind.removesuffix("_up") in ("road", "junction", "lane", "centre"):
                v, idx = part["v"], part["i"]
                for k in range(0, len(idx), 3):
                    roads.append(Polygon([(v[2 * idx[k + t]], v[2 * idx[k + t] + 1]) for t in range(3)]))
    built = unary_union(blds)
    carriageway = unary_union(roads)
    no_go = carriageway.buffer(1.0)

    # --- the closed road ----------------------------------------------------------------------
    site_edges = [i for i, e in enumerate(edges) if e.get("n") == SITE_ROAD
                  and min(math.dist(p, centre) for p in e["pts"]) < 400.0]
    site_nodes = {edges[i]["a"] for i in site_edges} | {edges[i]["b"] for i in site_edges}
    close = []
    for i, e in enumerate(edges):
        if e.get("n") != CLOSE_ROAD or (e["a"] in site_nodes and e["b"] in site_nodes):
            continue  # (a crossover between the two carriageways stays open)
        near = min(min(math.dist(nodes[n][::2] if len(nodes[n]) == 3 else nodes[n], p) for p in e["pts"]) for n in site_nodes)
        if near < CLOSE_RADIUS_M and edge_len(e) < 80.0:
            close.append(i)
    if not close:
        print("Road works: no edges to close (road names changed?)")
        return 1
    closed = set(close)

    def strongly_connected(skip) -> int:
        adj, radj = {}, {}
        for i, e in enumerate(edges):
            if i in skip:
                continue
            if e["lf"] > 0:
                adj.setdefault(e["a"], []).append(e["b"]); radj.setdefault(e["b"], []).append(e["a"])
            if e["lb"] > 0:
                adj.setdefault(e["b"], []).append(e["a"]); radj.setdefault(e["a"], []).append(e["b"])
        start = edges[site_edges[0]]["a"]

        def reach(g):
            seen, st = {start}, [start]
            while st:
                n = st.pop()
                for m in g.get(n, ()):
                    if m not in seen:
                        seen.add(m)
                        st.append(m)
            return seen
        return len(reach(adj) & reach(radj))

    before, after = strongly_connected(set()), strongly_connected(closed)
    interior = {edges[i]["a"] for i in closed} | {edges[i]["b"] for i in closed}
    node_edges: dict = {}
    for i, e in enumerate(edges):
        node_edges.setdefault(e["a"], []).append(i)
        node_edges.setdefault(e["b"], []).append(i)
    boundary = sorted(n for n in interior if any(j not in closed for j in node_edges[n]))
    lost = before - after
    dead_inside = len(interior) - len(boundary)
    if lost > dead_inside:
        print(f"Road works: closing {close} would cut {lost} junctions off the network")
        return 1

    # --- barrier rows + boards where the closed road meets open roads -------------------------
    def road_width_at(px, pz, dx, dz) -> float:
        lx, lz = -dz, dx
        w = 0.0
        for sgn in (1, -1):
            r = 0.0
            while r < 14.0 and carriageway.contains(Polygon([(px + lx * sgn * r - 0.05, pz + lz * sgn * r - 0.05),
                                                            (px + lx * sgn * r + 0.05, pz + lz * sgn * r - 0.05),
                                                            (px + lx * sgn * r + 0.05, pz + lz * sgn * r + 0.05)])):
                r += 0.25
            w += r
        return max(w, 4.0)

    rows, boards = [], []
    for n in boundary:
        for i in node_edges[n]:
            if i not in closed:
                continue
            e = edges[i]
            pts = e["pts"] if e["a"] == n else list(reversed(e["pts"]))  # running away from the open junction
            back = min(ROW_BACK_M, edge_len(e) * 0.5)
            (px, pz), (dx, dz) = along(pts, back)
            width = road_width_at(px, pz, dx, dz) + 0.6
            yaw = math.atan2(dx, dz)  # row faces back towards the open junction (-direction)
            rows.append({"c": [round(px, 2), round(pz, 2)], "yaw": round(yaw, 3), "width": round(width, 2)})
            boards.append({"kind": "closed", "c": [round(px - dx * 1.2, 2), round(pz - dz * 1.2, 2)], "yaw": round(yaw + math.pi, 3)})
        # Main-road approaches into this junction (open, driveable towards n): a diversion board
        # on their left kerb, DIVERSION_BACK_M before the junction.
        for i in node_edges[n]:
            if i in closed:
                continue
            e = edges[i]
            into = (e["b"] == n and e["lf"] > 0) or (e["a"] == n and e["lb"] > 0)
            if not into or edge_len(e) < DIVERSION_BACK_M + 5.0:
                continue
            pts = e["pts"] if e["a"] == n else list(reversed(e["pts"]))  # away from n
            (px, pz), (dx, dz) = along(pts, DIVERSION_BACK_M)
            # Incoming traffic travels -d; its left is (-dz, dx).
            lx, lz = -dz, dx
            half = road_width_at(px, pz, dx, dz) * 0.5
            for extra in (1.2, 2.0, 3.0, 4.0):
                bx, bz = px + lx * (half + extra), pz + lz * (half + extra)
                if not no_go.contains(Polygon([(bx - 0.3, bz - 0.3), (bx + 0.3, bz - 0.3), (bx, bz + 0.3)])):
                    boards.append({"kind": "diversion", "c": [round(bx, 2), round(bz, 2)], "yaw": round(math.atan2(dx, dz), 3)})
                    break

    # --- the station-box site beside Kamarajar Salai -----------------------------------------
    best = None
    for ei in site_edges:
        e = edges[ei]
        pts = e["pts"]
        L = edge_len(e)
        for wid, length in SITE_SIZES:
            for s in range(0, int(L - length), 4):
                (ax, az), (dx, dz) = along(pts, s + length * 0.5)
                for side in (1, -1):
                    rx, rz = -dz * side, dx * side
                    for off in range(3, 40):
                        cx, cz = ax + rx * (off + wid * 0.5), az + rz * (off + wid * 0.5)
                        r = Polygon([(-length / 2, -wid / 2), (length / 2, -wid / 2), (length / 2, wid / 2), (-length / 2, wid / 2)])
                        r = affinity.translate(affinity.rotate(r, math.degrees(math.atan2(dz, dx)), origin=(0, 0)), cx, cz)
                        if r.intersects(no_go):
                            continue
                        if r.intersects(built):
                            break
                        score = math.dist((cx, cz), centre) - wid * length * 0.02
                        if best is None or score < best[0]:
                            best = (score, cx, cz, math.atan2(dx, dz), length, wid)
                        break
            if best is not None:
                break
    if best is None:
        print("Road works: no free site beside", SITE_ROAD)
        return 1
    _, cx, cz, yaw, length, wid = best
    site = {"id": "lighthouse_metro", "c": [round(cx, 2), round(cz, 2)], "yaw": round(yaw, 3),
            "len": length, "wid": wid}
    # Hoarding boards on the long side facing the road (both long sides carry one).
    for sgn in (1, -1):
        rx, rz = math.cos(yaw) * sgn, -math.sin(yaw) * sgn  # local +X of a yaw-rotated frame
        boards.append({"kind": "metro", "c": [round(cx + rx * (wid * 0.5 + 0.05), 2), round(cz + rz * (wid * 0.5 + 0.05), 2)],
                       "yaw": round(yaw + (math.pi * 0.5 if sgn > 0 else -math.pi * 0.5), 3)})

    # Clear street dress (trees, poles, transformers, parked cars, stalls) out of the site and off
    # the barrier rows; wires whose either end is inside go too.
    footprint = affinity.translate(affinity.rotate(
        Polygon([(-wid / 2 - 0.8, -length / 2 - 0.8), (wid / 2 + 0.8, -length / 2 - 0.8),
                 (wid / 2 + 0.8, length / 2 + 0.8), (-wid / 2 - 0.8, length / 2 + 0.8)]),
        -math.degrees(yaw), origin=(0, 0)), cx, cz)
    keep_out = unary_union([footprint] + [Point(r["c"]).buffer(r["width"] * 0.5 + 1.0) for r in rows]
                           + [Point(b["c"]).buffer(1.4) for b in boards if b["kind"] != "metro"])
    removed = 0
    for path in sorted((WORLD / "dress").glob("c_*.json")):
        k = path.stem.split("_")
        kx, kz = int(k[1]), int(k[2])
        if not keep_out.intersects(Polygon([(kx * CHUNK, kz * CHUNK), ((kx + 1) * CHUNK, kz * CHUNK),
                                            ((kx + 1) * CHUNK, (kz + 1) * CHUNK), (kx * CHUNK, (kz + 1) * CHUNK)])):
            continue
        d = json.loads(path.read_text())
        changed = False
        for key in ("trees", "poles", "xfmr", "parking", "stalls", "wires", "barricades", "beach_fence", "carts"):
            items = d.get(key)
            if not items:
                continue
            kept = []
            for it in items:
                pts_in = [Point(it[0], it[1])] + ([Point(it[2], it[3])] if key == "wires" else [])
                if any(keep_out.contains(q) for q in pts_in):
                    removed += 1
                    changed = True
                else:
                    kept.append(it)
            d[key] = kept
        if changed:
            path.write_text(json.dumps(d, separators=(",", ":")))

    out = {"_note": "tools/osm/build_road_works.py — metro works at the Lighthouse; edge ids match road_graph.json",
           "closed_edges": sorted(close), "rows": rows, "boards": boards, "sites": [site]}
    (WORLD / "road_works.json").write_text(json.dumps(out, indent=1))
    print(f"Road works: site {length:.0f}×{wid:.0f} m at ({cx:.0f}, {cz:.0f}), "
          f"{dist_txt(site, centre)} from the Lighthouse; closed {len(close)} edges of {CLOSE_ROAD} "
          f"(network keeps {after}/{before} junctions), {len(rows)} barrier rows, {len(boards)} boards, "
          f"{removed} street props cleared")
    return 0


def dist_txt(site, centre) -> str:
    return f"{math.dist(site['c'], centre):.0f} m"


if __name__ == "__main__":
    raise SystemExit(main())
