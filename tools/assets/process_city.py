#!/usr/bin/env python3
"""Bakes downloaded Chennai landmark scenes into single-draw-call static models (assets/models/city).

Each source scene is flattened to world space, unwanted parts are dropped (trees, ground planes,
helper objects), every material is packed into one texture atlas (untextured materials become
flat colour tiles, repeating textures their average colour), all parts are merged into one
primitive, then welded and simplified to a triangle budget with gltf-transform.

Raw downloads stay in assets_src/incoming/models/city (gitignored); only the .glb files ship.
Usage: python3 tools/assets/process_city.py [ids...]
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_rig import Gltf  # noqa: E402
from process_people import Writer, build_atlas, triangles  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "models" / "city"
OUT = ROOT / "assets" / "models" / "city"
WORK = SRC / "_work"
GLTF = ROOT / "tools" / "assets" / "node_modules" / ".bin" / "gltf-transform"

# id, source scene, drop material substrings, drop parts wider than (source units),
# target size (metres, longest horizontal side), triangle budget, atlas px, credit
SPECS = [
    ("chennai_central", "chennai_central/scene.gltf", ["mossy", "bark", "sonnerat", "oak"], 300.0, 190.0, 9000, 512,
     '"chennai central" by SudharsanArivalagan (Sketchfab), CC BY 4.0'),
    ("water_tower", "chennai_water_tank/scene.gltf", [], 1e9, 0.0, 9000, 512,
     '"Chennai Water Tank" by TamilarasanRG (Sketchfab), CC BY 4.0'),
    ("slum_cluster", "chennai_slum/scene.gltf", [], 1e9, 34.0, 9000, 1024,
     '"Chennai Slum" by aswin.baskaran (Sketchfab), CC BY 4.0'),
]
# The water tower is scaled by height instead (real TWAD overhead tanks stand ~18 m).
HEIGHT_TARGET = {"water_tower": 18.0}


def collect(g: Gltf, drop: list[str], max_size: float) -> list[dict]:
    rest = g.rest_world()
    parts = []
    for ni, node in enumerate(g.nodes):
        if "mesh" not in node:
            continue
        mesh = g.j["meshes"][node["mesh"]]
        m = rest[ni]
        for prim in mesh["primitives"]:
            if prim.get("mode", 4) != 4:
                continue
            mat = g.j["materials"][prim["material"]] if "material" in prim else {}
            if any(d in mat.get("name", "").lower() for d in drop):
                continue
            a = prim["attributes"]
            pos = g.accessor(a["POSITION"])
            wpos = (np.c_[pos, np.ones(len(pos))] @ m.T)[:, :3]
            ext = wpos.max(0) - wpos.min(0)
            if max(ext[0], ext[2]) > max_size:
                continue
            nrm = g.accessor(a["NORMAL"]) if "NORMAL" in a else np.tile([0.0, 1.0, 0.0], (len(pos), 1))
            nm = np.linalg.inv(m[:3, :3]).T
            wn = nrm @ nm.T
            wn /= np.maximum(np.linalg.norm(wn, axis=1, keepdims=True), 1e-9)
            if np.linalg.det(m[:3, :3]) < 0:
                flip = True
            else:
                flip = False
            uv = g.accessor(a["TEXCOORD_0"]) if "TEXCOORD_0" in a else np.zeros((len(pos), 2))
            idx = g.accessor(prim["indices"])[:, 0].astype(np.int64) if "indices" in prim else np.arange(len(pos))
            if flip:
                idx = idx.reshape(-1, 3)[:, ::-1].reshape(-1)
            parts.append({"pos": wpos, "nrm": wn, "uv": uv, "idx": idx, "mat": mat, "label": mat.get("name", "")})
    return parts


def cluster(parts: list[dict], cell: float) -> list[dict]:
    """Vertex clustering that keeps hard edges: vertices merge only when they share a grid cell
    AND a normal direction bucket. Flat-shaded scans/kits (every face its own vertices) defeat
    edge-collapse simplifiers; this collapses them predictably to a target density."""
    out = []
    for p in parts:
        nb = np.round(p["nrm"] * 2.0).astype(np.int64)  # 5^3 direction buckets
        key = np.c_[np.floor(p["pos"] / cell).astype(np.int64), nb]
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inv = inv.reshape(-1)
        cnt = np.bincount(inv).astype(float)
        pos = np.zeros((len(first), 3))
        np.add.at(pos, inv, p["pos"])
        pos /= cnt[:, None]
        tri = inv[p["idx"].reshape(-1, 3)]
        ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
        tri = tri[ok]
        if len(tri) == 0:
            continue
        q = dict(p)
        q.update({"pos": pos, "nrm": p["nrm"][first], "uv": p["uv"][first], "idx": tri.reshape(-1)})
        out.append(q)
    return out


def write_static(path: Path, parts: list[dict], atlas_png: Path, alpha: bool) -> None:
    w = Writer()
    pos = np.concatenate([p["pos"] for p in parts])
    nrm = np.concatenate([p["nrm"] for p in parts])
    uv = np.concatenate([p["uv"] for p in parts])
    idx, base = [], 0
    for p in parts:
        idx.append(p["idx"] + base)
        base += len(p["pos"])
    idx = np.concatenate(idx)
    a_pos = w.add(pos, 5126, "VEC3", 34962, True)
    a_nrm = w.add(nrm, 5126, "VEC3", 34962)
    a_uv = w.add(uv, 5126, "VEC2", 34962)
    a_i = w.add(idx, 5125, "SCALAR", 34963)
    mat = {"name": "landmark", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
                                                        "roughnessFactor": 0.9}}
    if alpha:
        mat.update({"alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True})
    doc = {
        "asset": {"version": "2.0", "generator": "namma-auto process_city.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": path.stem, "mesh": 0}],
        "meshes": [{"name": path.stem, "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm,
                                                                      "TEXCOORD_0": a_uv},
                                                       "indices": a_i, "material": 0}]}],
        "materials": [mat], "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"uri": atlas_png.name}],
        "buffers": [{"uri": path.with_suffix(".bin").name, "byteLength": len(w.bin)}],
        "bufferViews": w.views, "accessors": w.accessors,
    }
    path.with_suffix(".bin").write_bytes(bytes(w.bin))
    path.write_text(json.dumps(doc))


def run(args: list) -> None:
    r = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"{' '.join(map(str, args))}\n{r.stdout}\n{r.stderr}")


def main() -> int:
    only = set(sys.argv[1:])
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    meta_path = OUT / "city_models.json"
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    credits = []
    for cid, src, drop, max_size, size_m, budget, atlas_px, credit in SPECS:
        credits.append(f"| `assets/models/city/{cid}.glb` | {src.split('/')[0]} | {credit} |")
        if only and cid not in only:
            continue
        g = Gltf(SRC / src)
        parts = collect(g, drop, max_size)
        allp = np.concatenate([p["pos"] for p in parts])
        lo, hi = allp.min(0), allp.max(0)
        ext = hi - lo
        if cid in HEIGHT_TARGET:
            scale = HEIGHT_TARGET[cid] / ext[1]
        else:
            scale = size_m / max(ext[0], ext[2])
        centre = np.array([(lo[0] + hi[0]) * 0.5, lo[1], (lo[2] + hi[2]) * 0.5])
        for p in parts:
            p["pos"] = (p["pos"] - centre) * scale
        tris = sum(len(p["idx"]) // 3 for p in parts)
        if tris > budget * 1.2:
            # Grow the cluster cell until the model fits its budget.
            cell = 0.02
            reduced = parts
            while cell < 5.0:
                reduced = cluster(parts, cell)
                if sum(len(p["idx"]) // 3 for p in reduced) <= budget * 1.2:
                    break
                cell *= 1.3
            print(f"     {cid}: clustered at {cell:.2f} m -> {sum(len(p['idx']) // 3 for p in reduced)} tris")
            parts = reduced
        atlas, alpha = build_atlas(g, parts, atlas_px)
        atlas_png = WORK / f"{cid}_atlas.png"
        atlas.save(atlas_png)
        raw = WORK / f"{cid}.gltf"
        write_static(raw, parts, atlas_png, alpha)
        tris_in = sum(len(p["idx"]) // 3 for p in parts)
        ratio = min(1.0, budget / max(tris_in, 1))
        welded = WORK / f"{cid}_weld.glb"
        tmp = WORK / f"{cid}_s.glb"
        dest = OUT / f"{cid}.glb"
        run([GLTF, "weld", raw, welded])
        for err in ("0.005", "0.01", "0.02", "0.05", "0.1", "0.2"):
            run([GLTF, "simplify", welded, tmp, "--ratio", f"{ratio:.4f}", "--error", err, "--lock-border", "false"])
            if triangles(tmp) <= budget * 1.2:
                break
        run([GLTF, "prune", tmp, dest])
        size = (ext * scale).round(1).tolist()
        meta[cid] = {"size_m": size, "credit": credit}
        print(f"OK   {cid}: {tris_in} -> {triangles(dest)} tris, {dest.stat().st_size // 1024} KB, size {size} m")
    meta_path.write_text(json.dumps(meta, indent=1, sort_keys=True))
    (OUT / "CREDITS_city.md").write_text("# City landmarks (made by tools/assets/process_city.py)\n\n"
                                        "| File | Source | Licence |\n|---|---|---|\n" + "\n".join(credits) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
