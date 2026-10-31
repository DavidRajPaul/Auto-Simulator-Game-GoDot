#!/usr/bin/env python3
"""Turns the two user-supplied traffic downloads into game-ready, single-vehicle GLBs.

1. Two-wheeler pack ("Two-Wheeler Vehicles Pack Low-Poly", SymetrikGames, CC BY 4.0).
   The download is ONE merged mesh holding a 4 x 4 showroom grid (sport bike, BMX,
   bicycle and loose parts, each in 4 colours) spread over ~65 x 73 units. Fitting that
   whole grid into one 0.8 x 2.0 m traffic box is what made every "two-wheeler" in the
   city a squashed cluster of tiny bikes. Here the grid is split into connected parts,
   the parts are grouped into vehicles, and only the motorised sport bike of each colour
   column is kept (bicycles at 40 km/h in the scooter lane would look wrong). Each bike
   is re-centred, stood on y = 0, turned front-to-+Z and scaled to a real 2.05 m length.

2. Police SUV (Tripo-generated, user supplied). The raw file is a 0.46 x 0.48 x 0.98
   unit box with 18.5k triangles and metallic/normal maps. TrafficVehicleAI squeezed it
   non-uniformly into a saloon-sized 1.78 x 1.67 x 4.6 m box (26 % flatter than the real
   shape) and the metallic map renders near-black without reflection probes on mobile.
   Here it is scaled uniformly to 4.5 m, its normal / metallic-roughness maps are dropped
   (matte paint like the rest of the fleet), and it is simplified to the traffic budget.

Raw sources stay in assets_src/incoming/models/traffic (gitignored); only results ship.
Usage: python3 tools/assets/process_vehicle_packs.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "models" / "traffic"
OUT = ROOT / "assets" / "models" / "traffic"
GLTF = ROOT / "tools" / "assets" / "node_modules" / ".bin" / "gltf-transform"

BIKE_LENGTH_M = 2.05
SCOOTER_LENGTH_M = 1.83
POLICE_LENGTH_M = 4.5
POLICE_TRIANGLES = 3000


def _groups(mesh: trimesh.Trimesh, margin: float) -> list[trimesh.Trimesh]:
    """Connected parts merged into vehicles: parts whose boxes touch (within margin) join."""
    parts = mesh.split(only_watertight=False)
    boxes = np.array([p.bounds for p in parts])
    parent = list(range(len(parts)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(parts)):
        lo, hi = boxes[i, 0] - margin, boxes[i, 1] + margin
        hit = np.all(boxes[:, 0] <= hi, axis=1) & np.all(boxes[:, 1] >= lo, axis=1)
        for j in np.nonzero(hit)[0]:
            parent[find(i)] = find(int(j))
    buckets: dict[int, list[int]] = {}
    for i in range(len(parts)):
        buckets.setdefault(find(i), []).append(i)
    return [trimesh.util.concatenate([parts[k] for k in ids]) for ids in buckets.values()]


CELL_PX = 4


def _face_colours(mesh: trimesh.Trimesh) -> np.ndarray:
    """Base-colour texture sampled per face (median of the centroid and three inset corners)."""
    img = mesh.visual.material.baseColorTexture if hasattr(mesh.visual.material, "baseColorTexture") \
        else mesh.visual.material.image
    tex = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    h, w = tex.shape[:2]
    uv = mesh.visual.uv[mesh.faces]  # (F, 3, 2)
    centre = uv.mean(1, keepdims=True)
    pts = np.concatenate([centre, uv * 0.5 + centre * 0.5], axis=1)  # (F, 4, 2)
    px = np.clip((pts[..., 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    py = np.clip((1.0 - pts[..., 1] % 1.0) * (h - 1), 0, h - 1).astype(int)
    return np.median(tex[py, px], axis=1)


def _palette_mesh(mesh: trimesh.Trimesh, colours: np.ndarray) -> trimesh.Trimesh:
    """Flat-colour copy: every face samples the centre of one solid cell of a tiny palette PNG.
    Clean colours instead of the source's noisy / bleeding texels, and simplification can never
    smear a UV seam (a whole colour region shares one UV)."""
    q = np.round(np.clip(colours, 0, 1) * 255).astype(np.uint8)
    uniq, inverse = np.unique(q, axis=0, return_inverse=True)
    inverse = inverse.reshape(-1)
    n = int(np.ceil(np.sqrt(len(uniq))))
    size = max(n * CELL_PX, 8)
    img = np.zeros((size, size, 3), dtype=np.uint8)
    cell_uv = np.zeros((len(uniq), 2))
    for i, c in enumerate(uniq):
        cx, cy = i % n, i // n
        img[cy * CELL_PX:(cy + 1) * CELL_PX, cx * CELL_PX:(cx + 1) * CELL_PX] = c
        cell_uv[i] = [(cx + 0.5) * CELL_PX / size, 1.0 - (cy + 0.5) * CELL_PX / size]
    verts = mesh.vertices[mesh.faces].reshape(-1, 3)
    faces = np.arange(len(verts)).reshape(-1, 3)
    uv = np.repeat(cell_uv[inverse], 3, axis=0)
    from PIL import Image
    mat = trimesh.visual.material.PBRMaterial(baseColorTexture=Image.fromarray(img), metallicFactor=0.0,
                                              roughnessFactor=0.7, doubleSided=True)
    # Keep the source's smooth normals per corner (generated normals on the split faces came out
    # as random dark facets).
    normals = mesh.vertex_normals[mesh.faces].reshape(-1, 3)
    out = trimesh.Trimesh(vertices=verts, faces=faces, vertex_normals=normals, process=False,
                          visual=trimesh.visual.TextureVisuals(uv=uv, material=mat))
    return out


# Police livery: Tamil Nadu patrol SUVs are white with dark trim, tinted glass and a red/blue bar.
POLICE_PALETTE = np.array([
    [0.93, 0.93, 0.91],  # 0 body white
    [0.10, 0.10, 0.11],  # 1 tyres, grille, bull bar
    [0.20, 0.25, 0.30],  # 2 tinted glass
    [0.82, 0.10, 0.10],  # 3 red (beacon, stripe)
    [0.10, 0.24, 0.82],  # 4 blue (beacon, stripe)
    [0.55, 0.56, 0.58],  # 5 chrome / grey trim
])


def _police_classes(mesh: trimesh.Trimesh, colours: np.ndarray) -> np.ndarray:
    r, g, b = colours[:, 0], colours[:, 1], colours[:, 2]
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    sat = colours.max(1) - colours.min(1)
    # The AI texture bakes heavy shading into a white body: anything not clearly dark is paint.
    cls = np.full(len(colours), 0)
    cls[(lum < 0.34) & (sat < 0.15)] = 5
    cls[lum < 0.09] = 1
    low = (mesh.triangles_center[:, 1] - mesh.bounds[0][1]) < (mesh.bounds[1][1] - mesh.bounds[0][1]) * 0.3
    cls[low & (lum < 0.3)] = 1  # tyres and the underside stay black
    height = mesh.bounds[1][1] - mesh.bounds[0][1]
    y = mesh.triangles_center[:, 1] - mesh.bounds[0][1]
    glass = (lum >= 0.08) & (lum <= 0.42) & (y > height * 0.52) & (y < height * 0.88) & (sat < 0.2)
    cls[glass] = 2
    cls[(sat > 0.28) & (r > g + 0.15) & (r > b + 0.15)] = 3
    cls[(sat > 0.25) & (b > r + 0.12) & (b > g + 0.05)] = 4
    # Majority vote over edge neighbours removes the AI texture's speckle (keeps beacons).
    adj = mesh.face_adjacency
    for _ in range(6):
        votes = np.zeros((len(cls), len(POLICE_PALETTE)), dtype=np.int32)
        np.add.at(votes, (adj[:, 0], cls[adj[:, 1]]), 1)
        np.add.at(votes, (adj[:, 1], cls[adj[:, 0]]), 1)
        np.add.at(votes, (np.arange(len(cls)), cls), 1)
        keep = np.isin(cls, [3, 4]) & (votes[np.arange(len(cls)), cls] >= 2)
        cls = np.where(keep, cls, votes.argmax(1))
    print("police classes (white, trim, glass, red, blue, grey):", np.bincount(cls, minlength=6).tolist())
    return cls


def _normalise(mesh: trimesh.Trimesh, length_m: float) -> trimesh.Trimesh:
    """Centre on x/z, stand on y = 0, scale so the z extent is length_m (uniform)."""
    lo, hi = mesh.bounds
    mesh.apply_translation([-(lo[0] + hi[0]) * 0.5, -lo[1], -(lo[2] + hi[2]) * 0.5])
    mesh.apply_scale(length_m / (hi[2] - lo[2]))
    return mesh


def split_two_wheelers() -> list[dict]:
    scene = trimesh.load(SRC / "two_wheeler_pack.glb", force="scene")
    mesh = trimesh.util.concatenate(scene.dump())
    vehicles = _groups(mesh, 0.3)
    # Sport bikes: the only groups longer than 13 units and taller than 7 (the 15.2 x 7.7
    # silhouettes in the first showroom row). One per colour column, sorted left to right.
    bikes = [v for v in vehicles if (v.bounds[1] - v.bounds[0])[2] > 13.0 and (v.bounds[1] - v.bounds[0])[1] > 7.0
             and v.bounds[0][2] < -45.0]
    bikes.sort(key=lambda v: v.bounds.mean(0)[0])
    if len(bikes) != 4:
        raise SystemExit(f"expected 4 sport bikes in the pack, found {len(bikes)}")
    out_dir = OUT / "two_wheeler_pack"
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for i, bike in enumerate(bikes):
        # The pack's bikes already face +Z (windscreen and front wheel at the +Z end).
        bike = _normalise(bike, BIKE_LENGTH_M)
        bike = _palette_mesh(bike, _face_colours(bike))
        path = out_dir / f"sport_bike_{i}.glb"
        bike.export(path)
        size = bike.bounds[1] - bike.bounds[0]
        written.append({"file": path.relative_to(ROOT).as_posix(), "size": [round(float(s), 3) for s in size],
                        "triangles": int(len(bike.faces))})
    # A real-size, grounded copy of the Activa-style traffic scooter for parked rows (the
    # traffic file is a 1-unit box centred on its origin, so it would sink if just scaled).
    scooter = trimesh.util.concatenate(trimesh.load(OUT / "two_wheeler.glb", force="scene").dump())
    scooter = _normalise(scooter, SCOOTER_LENGTH_M)
    path = out_dir / "scooter_parked.glb"
    scooter.export(path)
    size = scooter.bounds[1] - scooter.bounds[0]
    written.append({"file": path.relative_to(ROOT).as_posix(), "size": [round(float(s), 3) for s in size],
                    "triangles": int(len(scooter.faces))})
    return written


def bake_police() -> dict:
    raw = SRC / "police_car_tripo.glb"
    tmp = SRC / "_police_scaled.glb"
    scene = trimesh.load(raw, force="scene")
    mesh = trimesh.util.concatenate(scene.dump())
    # Tripo exports front-to-+Z already (bull bar at +Z); keep it, like the other svc_* files.
    mesh = _normalise(mesh, POLICE_LENGTH_M)
    mesh.merge_vertices(merge_tex=True, merge_norm=True)
    cls = _police_classes(mesh, _face_colours(mesh))
    mesh = _palette_mesh(mesh, POLICE_PALETTE[cls])
    mesh.export(tmp, include_normals=True)
    out = OUT / "police_car" / "svc_police_car.glb"
    subprocess.run(["node", str(ROOT / "tools" / "assets" / "matte_vehicle.mjs"), str(tmp), str(out),
                    str(POLICE_TRIANGLES)], check=True)
    tmp.unlink()
    check = trimesh.load(out, force="scene")
    m = trimesh.util.concatenate(check.dump())
    size = m.bounds[1] - m.bounds[0]
    return {"file": out.relative_to(ROOT).as_posix(), "size": [round(float(s), 3) for s in size],
            "triangles": int(len(m.faces))}


def main() -> int:
    report = {"two_wheelers": split_two_wheelers(), "police": bake_police()}
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
