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
    ("slum_cluster", "chennai_slum/scene.gltf", [], 1e9, 34.0, 14000, 1024,
     '"Chennai Slum" by aswin.baskaran (Sketchfab), CC BY 4.0'),
]
# The water tower is scaled by height instead (real TWAD overhead tanks stand ~18 m).
HEIGHT_TARGET = {"water_tower": 18.0}

# More static models baked the same way (one atlas, one primitive, simplified), written into
# other folders. Keys: id, src, out (city / traffic / people), under (only meshes below the node
# with this name), drop (material substrings), size_m (longest horizontal side) or height_m,
# yaw (extra turn, radians, applied before fitting), budget, atlas, credit.
CIVIL = '"Generic civil service vehicles pack" by Comrade1280 (Sketchfab), CC BY 4.0'
POLICE_F = '"Female Police Officer in Multiple Uniforms" by Umar (Sketchfab), CC BY 4.0'
EXTRA = [
    # Lengths of the Indian equivalents: Force Traveller 108 ambulance, TNFRS fire tender, GCC
    # compactor truck, Bolero-size police car, school bus, flatbed tow truck.
    {"id": "svc_ambulance", "src": "generic_civil_service_vehicles_pack/scene.gltf", "out": "traffic", "align": True, "under": "ambulance", "yaw": 3.14159265, "size_m": 5.9, "budget": 2400, "atlas": 512, "credit": CIVIL},
    {"id": "svc_fire_truck", "src": "generic_civil_service_vehicles_pack/scene.gltf", "out": "traffic", "align": True, "under": "fire_truck", "size_m": 8.6, "budget": 2800, "atlas": 512, "credit": CIVIL},
    {"id": "svc_garbage_truck", "src": "generic_civil_service_vehicles_pack/scene.gltf", "out": "traffic", "align": True, "under": "garbage_truck", "size_m": 7.2, "budget": 2400, "atlas": 512, "credit": CIVIL},
    {"id": "svc_police_car", "src": "generic_civil_service_vehicles_pack/scene.gltf", "out": "traffic", "align": True, "under": "police_sedan", "yaw": 3.14159265, "size_m": 4.6, "budget": 2000, "atlas": 512, "credit": CIVIL},
    {"id": "svc_school_bus", "src": "generic_civil_service_vehicles_pack/scene.gltf", "out": "traffic", "align": True, "under": "school_bus", "size_m": 9.5, "budget": 2400, "atlas": 512, "credit": CIVIL},
    {"id": "svc_tow_truck", "src": "generic_civil_service_vehicles_pack/scene.gltf", "out": "traffic", "align": True, "under": "towtruck", "size_m": 6.4, "budget": 2400, "atlas": 512, "credit": CIVIL},
    # Traffic police (static, arms out = directing traffic). Each uniform is its own model.
    {"id": "police_f_khaki", "src": "female_police_officer_in_multiple_uniforms/scene.gltf", "out": "people", "under": "Female_002_1", "height_m": 1.62, "budget": 3000, "atlas": 512, "credit": POLICE_F},
    {"id": "police_m_ips", "src": "indian_ipsofficer/scene.gltf", "out": "people", "height_m": 1.76, "budget": 4000, "atlas": 512, "paint": "police_khaki", "scan": True, "no_cluster": True,
     "credit": '"Indian ipsOfficer" by @MgsGamer5 (Sketchfab), CC BY 4.0 — uniform painted (texture missing from the upload)'},
    # LPG autogas station, frontage scaled to a city lot. The real brand's logo texture is redrawn
    # first as the fictional "NAMMA GAS" (tools/art/make_station_brand.py; original kept as .orig.png).
    {"id": "gas_station", "src": "gas_station/scene.gltf", "out": "city", "size_m": 34.0, "budget": 9000, "atlas": 1024,
     "credit": '"GAS STATION" by Karim.Fares (Sketchfab), CC BY 4.0, rebranded as the fictional NAMMA GAS'},
]


def _under(g: Gltf, ni: int, name: str) -> bool:
    n = ni
    while n >= 0:
        if g.nodes[n].get("name") == name:
            return True
        n = g.parent[n]
    return False


def collect(g: Gltf, drop: list[str], max_size: float, under: str | None = None) -> list[dict]:
    rest = g.rest_world()
    parts = []
    for ni, node in enumerate(g.nodes):
        if "mesh" not in node:
            continue
        if under is not None and not _under(g, ni, under):
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


def smooth_normals(p: dict) -> None:
    t = p["idx"].reshape(-1, 3)
    v = p["pos"]
    fn = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
    n = np.zeros_like(v)
    for k in range(3):
        np.add.at(n, t[:, k], fn)
    p["nrm"] = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


def outward_normals(p: dict) -> None:
    """Scans often mix triangle windings. For an upright figure, point every face away from the
    body's vertical axis (per height slice), fixing the winding to match its normal."""
    v = p["pos"]
    t = p["idx"].reshape(-1, 3)
    cen = v[t].mean(1)
    # Axis centre per 5 cm slice.
    sl = np.floor(cen[:, 1] / 0.05).astype(int)
    axis = np.zeros((sl.max() + 2, 2))
    cnt = np.zeros(sl.max() + 2)
    np.add.at(axis, sl, cen[:, [0, 2]])
    np.add.at(cnt, sl, 1)
    axis /= np.maximum(cnt, 1)[:, None]
    out = np.c_[cen[:, 0] - axis[sl, 0], np.zeros(len(t)), cen[:, 2] - axis[sl, 1]]
    fn = np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]])
    flip = (fn * out).sum(1) < 0
    # Normals from the outward-oriented faces; the triangles keep their winding and the model is
    # drawn double-sided (turning faces made holes where the scan has two layers).
    fn[flip] = -fn[flip]
    n = np.zeros_like(v)
    for k in range(3):
        np.add.at(n, t[:, k], fn)
    p["nrm"] = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


def cluster(parts: list[dict], cell: float, use_normals: bool = True) -> list[dict]:
    """Vertex clustering that keeps hard edges: vertices merge only when they share a grid cell
    AND a normal direction bucket. Flat-shaded scans/kits (every face its own vertices) defeat
    edge-collapse simplifiers; this collapses them predictably to a target density."""
    out = []
    for p in parts:
        nb = np.round(p["nrm"] * 2.0).astype(np.int64) if use_normals else np.zeros((len(p["pos"]), 3), np.int64)
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
        if not use_normals:
            smooth_normals(q)
            outward_normals(q)
        out.append(q)
    return out


def write_static(path: Path, parts: list[dict], atlas_png: Path, alpha: bool, double_sided: bool = False) -> None:
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
    if double_sided:
        mat["doubleSided"] = True
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


def paint_police(parts: list[dict]) -> None:
    """The IPS officer arrived without its texture: paint a Tamil Nadu police uniform as a smooth
    height ramp (u = height, v = body / arm row), so colours never streak across triangles."""
    from PIL import Image
    allp = np.concatenate([p["pos"] for p in parts])
    hgt = allp[:, 1].max()
    W = 256
    img = Image.new("RGB", (W, 16))
    bands = [(0.0, (18, 16, 15)), (0.045, (150, 128, 86)), (0.50, (70, 45, 28)), (0.535, (172, 149, 102)),
             (0.80, (168, 118, 88)), (0.945, (25, 22, 20)), (0.958, (126, 104, 64))]  # shoes, trousers, belt, shirt, skin, cap band, cap
    arm = [(0.0, (150, 128, 86)), (0.37, (150, 104, 78)), (0.47, (168, 118, 88)), (0.64, (172, 149, 102)), (0.80, (168, 118, 88))]
    for x in range(W):
        h = (x + 0.5) / W
        body = [c for b, c in bands if h >= b][-1]
        armc = [c for b, c in arm if h >= b][-1]
        for y in range(16):
            img.putpixel((x, y), body if y < 8 else armc)
    mat = {"name": "police_palette", "_image": img}
    for p in parts:
        h = np.clip(p["pos"][:, 1] / hgt, 0.0, 0.999)
        lat = np.abs(p["pos"][:, 0]) / hgt
        row = np.where(lat > 0.125, 0.75, 0.25)
        p["uv"] = np.c_[h, row]
        p["mat"] = mat


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
    credits = []  # (out folder, row)
    specs = [{"id": c, "src": sr, "out": "city", "drop": d, "max_size": ms, "size_m": sz, "budget": b, "atlas": ap, "credit": cr}
             for c, sr, d, ms, sz, b, ap, cr in SPECS] + EXTRA
    for sp in specs:
        cid = sp["id"]
        out_dir = ROOT / "assets" / "models" / sp.get("out", "city")
        credits.append((sp.get("out", "city"), f"| `assets/models/{sp.get('out', 'city')}/{cid}.glb` | {sp['src'].split('/')[0]} | {sp['credit']} |"))
        if only and cid not in only:
            continue
        if not (SRC / sp["src"]).exists():
            print(f"SKIP {cid}: {sp['src']} not in assets_src/incoming/models/city")
            continue
        g = Gltf(SRC / sp["src"])
        parts = collect(g, sp.get("drop", []), sp.get("max_size", 1e9), sp.get("under"))
        if not parts:
            print(f"SKIP {cid}: no meshes under {sp.get('under')}")
            continue
        if sp.get("align"):
            # Packs lay vehicles out at odd angles: turn the long axis (PCA on the ground plane)
            # onto Z so the footprint, and the traffic box fitted to it, is the real one.
            allp = np.concatenate([p["pos"] for p in parts])
            xz = allp[:, [0, 2]] - allp[:, [0, 2]].mean(0)
            w, v = np.linalg.eigh(xz.T @ xz)
            major = v[:, int(np.argmax(w))]
            ang = np.arctan2(major[0], major[1])
            c, s_ = np.cos(-ang), np.sin(-ang)
            rot = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
            for p in parts:
                p["pos"] = p["pos"] @ rot.T
                p["nrm"] = p["nrm"] @ rot.T
        if sp.get("yaw"):
            c, s_ = np.cos(sp["yaw"]), np.sin(sp["yaw"])
            rot = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
            for p in parts:
                p["pos"] = p["pos"] @ rot.T
                p["nrm"] = p["nrm"] @ rot.T
        allp = np.concatenate([p["pos"] for p in parts])
        lo, hi = allp.min(0), allp.max(0)
        ext = hi - lo
        if cid in HEIGHT_TARGET:
            scale = HEIGHT_TARGET[cid] / ext[1]
        elif "height_m" in sp:
            scale = sp["height_m"] / ext[1]
        else:
            scale = sp["size_m"] / max(ext[0], ext[2])
        centre = np.array([(lo[0] + hi[0]) * 0.5, lo[1], (lo[2] + hi[2]) * 0.5])
        for p in parts:
            p["pos"] = (p["pos"] - centre) * scale
        if sp.get("paint") == "police_khaki":
            paint_police(parts)
        budget = sp["budget"]
        tris = sum(len(p["idx"]) // 3 for p in parts)
        # Clustering is only for scans / huge kits that edge-collapse can't handle; ordinary models
        # go straight to meshoptimizer, which keeps their silhouette.
        if tris > budget * 12 and not sp.get("no_cluster"):
            scan = bool(sp.get("scan", False))
            cell = 0.004 if "height_m" in sp else 0.02
            reduced = parts
            while cell < 5.0:
                reduced = cluster(parts, cell, not scan)
                if sum(len(p["idx"]) // 3 for p in reduced) <= budget * 6:
                    break
                cell *= 1.2
            print(f"     {cid}: clustered at {cell:.3f} m -> {sum(len(p['idx']) // 3 for p in reduced)} tris")
            parts = reduced
        atlas, alpha = build_atlas(g, parts, sp["atlas"])
        atlas_png = WORK / f"{cid}_atlas.png"
        atlas.save(atlas_png)
        raw = WORK / f"{cid}.gltf"
        write_static(raw, parts, atlas_png, alpha, bool(sp.get("scan", False)))
        tris_in = sum(len(p["idx"]) // 3 for p in parts)
        ratio = min(1.0, budget / max(tris_in, 1))
        welded = WORK / f"{cid}_weld.glb"
        tmp = WORK / f"{cid}_s.glb"
        out_dir.mkdir(parents=True, exist_ok=True)
        dest = out_dir / f"{cid}.glb"
        run([GLTF, "weld", raw, welded])
        for err in ("0.005", "0.01", "0.02", "0.05", "0.1", "0.2"):
            run([GLTF, "simplify", welded, tmp, "--ratio", f"{ratio:.4f}", "--error", err, "--lock-border", "false"])
            if triangles(tmp) <= budget * 1.2:
                break
        run([GLTF, "prune", tmp, dest])
        size = (ext * scale).round(2).tolist()
        meta[cid] = {"size_m": size, "credit": sp["credit"], "out": sp.get("out", "city")}
        print(f"OK   {cid}: {tris_in} -> {triangles(dest)} tris, {dest.stat().st_size // 1024} KB, size {size} m")
    city_meta = {k: v for k, v in meta.items() if v.get("out", "city") == "city"}
    meta_path.write_text(json.dumps(city_meta, indent=1, sort_keys=True))
    head = "| File | Source | Licence |\n|---|---|---|\n"
    (OUT / "CREDITS_city.md").write_text("# City landmarks (made by tools/assets/process_city.py)\n\n" + head
                                        + "\n".join(r for o, r in credits if o == "city") + "\n")
    for folder, title in (("traffic", "Civil service vehicles"), ("people", "Police (static)")):
        rows = [r for o, r in credits if o == folder]
        d = ROOT / "assets" / "models" / folder
        (d / "CREDITS_static.md").write_text(f"# {title} (made by tools/assets/process_city.py)\n\n" + head + "\n".join(rows) + "\n")
        sub = {k: v for k, v in meta.items() if v.get("out") == folder}
        (d / "static_models.json").write_text(json.dumps(sub, indent=1, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
