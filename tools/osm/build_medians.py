"""Chennai centre medians between the two carriageways of a divided road.

OSM maps Chennai's main roads (Anna Salai, TTK Road, CP Ramaswamy Road, the flyovers …) as two
one-way carriageways, and osm2streets leaves the strip between them empty — so the game showed a
bare gap where the city has a painted kerb and a railing. This pass finds that strip and fills it.

For every one-way trunk / primary / secondary / tertiary edge it samples the road every STEP m and
looks to the RIGHT of travel (India drives on the left, so the other carriageway is on the right):
past this carriageway's right kerb, across a gap of MIN_GAP–MAX_GAP m with no building in it, to
road surface again that belongs to a graph edge running the OTHER way. Consecutive hits form a run;
junctions are road surface, so runs stop before every junction by themselves.

Two looks, from the owner's reference photos (Nov 6):
  "A" (gap ≥ RAILING_MIN_GAP): black / white painted kerb, earth-and-grass bed, green steel
      railing down the middle, coconut palms every PALM_EVERY m on the wider beds.
  "B" (narrow gaps and flyovers): black / white striped concrete kerb with red / white
      delineator posts along the top.

Output: data/world/dress/c_X_Z.json "medians" = [[style, x0, z0, w0, x1, z1, w1, …], …] (centre
line and full width per sample), plus palms appended to "trees" (code 1) and roadside "parking" /
"stalls" that fell inside a median dropped. Idempotent: re-running replaces earlier medians and
their palms (tagged by a seed ≥ PALM_SEED).
Run after build_street_dressing.py / build_roadside_parking.py / fill_empty_lots.py:
    python3 tools/osm/build_medians.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_street_signs import CELL, TriGrid, seg_dist  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "data" / "world"
CHUNK = 250.0
CLASSES = ("trunk", "primary", "secondary", "tertiary")
STEP = 2.0
END_SKIP = 5.0
SCAN = 0.2
MIN_GAP = 1.0
MAX_GAP = 11.0
RAILING_MIN_GAP = 2.4
PALM_MIN_GAP = 3.2
PALM_EVERY = 18.0
PALM_SEED = 900000
DEDUPE_M = 1.8


def main() -> int:
    manifest = json.loads((WORLD / "manifest.json").read_text())
    road, bld = TriGrid(), TriGrid()
    for ch in manifest["chunks"]:
        d = json.loads((WORLD / "chunks" / f"c_{ch[0]}_{ch[1]}.json").read_text())
        for kind, part in d.get("surf", {}).items():
            if kind.removesuffix("_up") not in ("road", "junction", "lane", "centre"):
                continue
            v, idx = part["v"], part["i"]
            pts = [(v[k], v[k + 1]) for k in range(0, len(v), 2)]
            for k in range(0, len(idx), 3):
                road.add(pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]])
        for b in d.get("blds", []):
            p = b["p"]
            poly = [(p[k], p[k + 1]) for k in range(0, len(p), 2)]
            for k in range(1, len(poly) - 1):
                bld.add(poly[0], poly[k], poly[k + 1])

    graph = json.loads((WORLD / "road_graph.json").read_text())
    edges = graph["edges"]
    seg_grid: dict = {}
    for ei, e in enumerate(edges):
        for a, b in zip(e["pts"], e["pts"][1:]):
            for i in range(int(min(a[0], b[0]) // CELL) - 1, int(max(a[0], b[0]) // CELL) + 2):
                for j in range(int(min(a[1], b[1]) // CELL) - 1, int(max(a[1], b[1]) // CELL) + 2):
                    seg_grid.setdefault((i, j), []).append((a, b, ei))

    def oncoming_near(x, z, dx, dz, self_ei) -> bool:
        """A graph carriageway running against (dx, dz) passes within its half-width + 1.5 m."""
        for a, b, ei in seg_grid.get((int(x // CELL), int(z // CELL)), ()):
            if ei == self_ei:
                continue
            e = edges[ei]
            if seg_dist(x, z, a, b) > float(e["w"]) * 0.5 + 1.5:
                continue
            L = math.dist(a, b)
            if L < 1e-6:
                continue
            dot = ((b[0] - a[0]) * dx + (b[1] - a[1]) * dz) / L
            two_way = e.get("lb", 0) > 0
            if two_way or dot < -0.8:
                return not two_way
        return False

    centres: dict = {}  # dedupe grid of accepted median centre points

    def near_existing(x, z) -> bool:
        for i in (int(x // 4) - 1, int(x // 4), int(x // 4) + 1):
            for j in (int(z // 4) - 1, int(z // 4), int(z // 4) + 1):
                for q in centres.get((i, j), ()):
                    if math.dist(q, (x, z)) < DEDUPE_M:
                        return True
        return False

    runs = []  # [style, [(x, z, w), …]]
    for ei, e in enumerate(edges):
        if e["c"] not in CLASSES or e.get("lb", 0) != 0:
            continue
        pts = e["pts"]
        half = float(e["w"]) * 0.5
        run: list = []
        first_run = len(runs)
        travelled = 0.0
        total = sum(math.dist(pts[i - 1], pts[i]) for i in range(1, len(pts)))

        def flush():
            nonlocal run
            if len(run) >= 3:
                runs.append(run)
            run = []

        for a, b in zip(pts, pts[1:]):
            L = math.dist(a, b)
            if L < 1e-6:
                continue
            dx, dz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            rx, rz = -dz, dx  # right of travel
            s = (STEP - travelled % STEP) % STEP
            while s <= L:
                along = travelled + s
                s += STEP
                if along < END_SKIP or along > total - END_SKIP:
                    flush()
                    continue
                x, z = a[0] + dx * (along - travelled), a[1] + dz * (along - travelled)
                # Our right kerb …
                r = 0.0
                while r < half + 4.0 and road.hit(x + rx * r, z + rz * r, 0.0):
                    r += SCAN
                if r >= half + 4.0 or r < 0.6:
                    flush()
                    continue
                r1 = r
                # … across the gap to the other carriageway.
                while r < r1 + MAX_GAP and not road.hit(x + rx * r, z + rz * r, 0.0):
                    r += SCAN
                gap = r - r1
                if r >= r1 + MAX_GAP or gap < MIN_GAP:
                    flush()
                    continue
                cx, cz = x + rx * (r1 + gap * 0.5), z + rz * (r1 + gap * 0.5)
                if any(bld.hit(x + rx * (r1 + gap * f), z + rz * (r1 + gap * f), 0.3) for f in (0.15, 0.5, 0.85)):
                    flush()
                    continue
                if not oncoming_near(x + rx * (r + 1.5), z + rz * (r + 1.5), dx, dz, ei):
                    flush()
                    continue
                if near_existing(cx, cz):
                    flush()
                    continue
                # Width jumps mean the gap opened into something else (a lay-by, a park): split.
                if run and abs(run[-1][2] - gap) > 1.6:
                    flush()
                run.append((cx, cz, gap - 0.1))
            travelled += L
        flush()
        # Register this edge's accepted centres so the opposite carriageway skips them.
        for rr in runs[first_run:]:
            for (cx, cz, _w) in rr:
                centres.setdefault((int(cx // 4), int(cz // 4)), []).append((cx, cz))

    # Split runs at chunk borders (the shared sample is kept in both halves, so no seam gap).
    per_chunk: dict = {}
    palms: dict = {}
    total_len = 0.0
    seed = PALM_SEED
    for rr in runs:
        widths = sorted(p[2] for p in rr)
        style = "A" if widths[len(widths) // 2] >= RAILING_MIN_GAP else "B"
        piece = [rr[0]]
        key = (math.floor(rr[0][0] / CHUNK), math.floor(rr[0][1] / CHUNK))
        since_palm = PALM_EVERY * 0.5
        for p, q in zip(rr, rr[1:]):
            seg = math.dist(p[:2], q[:2])
            total_len += seg
            since_palm += seg
            if style == "A" and q[2] >= PALM_MIN_GAP and since_palm >= PALM_EVERY:
                since_palm = 0.0
                seed += 1
                pk = (math.floor(q[0] / CHUNK), math.floor(q[1] / CHUNK))
                palms.setdefault(pk, []).append([round(q[0], 2), round(q[1], 2), 1, 0.9 + (seed % 5) * 0.06, seed])
            qk = (math.floor(q[0] / CHUNK), math.floor(q[1] / CHUNK))
            piece.append(q)
            if qk != key:
                if len(piece) >= 2:
                    per_chunk.setdefault(key, []).append((style, piece))
                piece = [q]
                key = qk
        if len(piece) >= 2:
            per_chunk.setdefault(key, []).append((style, piece))

    dropped = 0
    dress_dir = WORLD / "dress"
    keys = set(per_chunk) | set(palms)
    for path in sorted(dress_dir.glob("c_*.json")):
        stem = path.stem.split("_")
        k = (int(stem[1]), int(stem[2]))
        d = json.loads(path.read_text())
        had = "medians" in d or any(len(t) > 4 and int(t[4]) >= PALM_SEED for t in d.get("trees", []))
        if k not in keys and not had:
            continue
        d["trees"] = [t for t in d.get("trees", []) if not (len(t) > 4 and int(t[4]) >= PALM_SEED)]
        meds = per_chunk.get(k, [])
        if meds:
            d["medians"] = [[style] + [round(v, 2) for p in piece for v in p] for style, piece in meds]
        else:
            d.pop("medians", None)
        d["trees"].extend(palms.get(k, []))

        def inside(x, z) -> bool:
            for _style, piece in meds:
                for p, q in zip(piece, piece[1:]):
                    if seg_dist(x, z, p[:2], q[:2]) < max(p[2], q[2]) * 0.5 + 0.6:
                        return True
            return False

        for kind in ("parking", "stalls"):
            if kind in d:
                before = len(d[kind])
                d[kind] = [it for it in d[kind] if not inside(float(it[0]), float(it[1]))]
                dropped += before - len(d[kind])
        path.write_text(json.dumps(d, separators=(",", ":")))
    missing = [k for k in keys if not (dress_dir / f"c_{k[0]}_{k[1]}.json").exists()]
    for k in missing:
        d = {"medians": [[s] + [round(v, 2) for p in pc for v in p] for s, pc in per_chunk.get(k, [])],
             "trees": palms.get(k, [])}
        (dress_dir / f"c_{k[0]}_{k[1]}.json").write_text(json.dumps(d, separators=(",", ":")))
    n_runs = sum(len(v) for v in per_chunk.values())
    print(f"Medians: {n_runs} pieces, {total_len / 1000:.1f} km, {sum(len(v) for v in palms.values())} palms, "
          f"{dropped} parked cars / stalls moved out of medians")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
