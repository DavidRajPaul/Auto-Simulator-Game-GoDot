#!/usr/bin/env python3
"""Packs the standing figures into ONE model with ONE texture, for shopkeepers and customers.

Nov 14 owner request: "the shops are empty; every open shop must have a shopkeeper and a few
customers". A city of shop fronts needs dozens of people in view; a draw call each is not
affordable. The static standing poses already exist (bake_waiting_people.py, one texture
each). This bake puts the eight 512 px textures into one 1024 x 512 atlas (256 px each),
moves every figure's UVs into its cell, lifts it so its feet are at y = 0 (the sources have
the origin at the hip) and writes them as eight meshes of one GLB sharing one material.
ShopPeople.gd merges the nearest figures into ONE mesh at runtime: one draw call for every
shopkeeper and customer on screen.

Output: assets/models/people/shop_people.glb (meshes named by character id)
Usage: python3 tools/assets/bake_shop_people.py
"""
from __future__ import annotations

import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "models" / "people" / "waiting"
OUT = ROOT / "assets" / "models" / "people" / "shop_people.glb"
IDS = ["man_casual", "woman_saree_green", "young_man", "woman_saree_maroon", "old_man_veshti", "woman_modern", "woman_saree_violet", "girl_churidar"]
CELL = 256
COLS = 4


def read_glb(path: Path) -> dict:
    data = path.read_bytes()
    n = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + n])
    binary = data[20 + n + 8:]

    def accessor(i: int) -> np.ndarray:
        acc = doc["accessors"][i]
        view = doc["bufferViews"][acc["bufferView"]]
        comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
        dtype = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[acc["componentType"]]
        size = np.dtype(dtype).itemsize * comps
        stride = view.get("byteStride", size)
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        raw = np.frombuffer(binary, dtype=np.uint8, count=(acc["count"] - 1) * stride + size, offset=start)
        rows = np.lib.stride_tricks.as_strided(raw, shape=(acc["count"], size), strides=(stride, 1))
        return np.ascontiguousarray(rows).view(dtype).reshape(acc["count"], comps)

    prim = doc["meshes"][0]["primitives"][0]
    view = doc["bufferViews"][doc["images"][0]["bufferView"]]
    png = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
    return {"pos": accessor(prim["attributes"]["POSITION"]).astype(np.float32), "nor": accessor(prim["attributes"]["NORMAL"]).astype(np.float32),
        "uv": accessor(prim["attributes"]["TEXCOORD_0"]).astype(np.float32), "idx": accessor(prim["indices"]).reshape(-1).astype(np.uint32),
        "image": Image.open(io.BytesIO(png)).convert("RGB")}


def main() -> None:
    hips = json.loads((SRC / "waiting.json").read_text())
    rows = (len(IDS) + COLS - 1) // COLS
    atlas = Image.new("RGB", (COLS * CELL, rows * CELL))
    blobs, views, accessors, meshes, nodes = [], [], [], [], []
    offset = 0

    def add(arr: np.ndarray, target: int | None) -> int:
        nonlocal offset
        raw = arr.tobytes()
        pad = (-len(raw)) % 4
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw)}
        if target is not None:
            view["target"] = target
        views.append(view)
        blobs.append(raw + b"\0" * pad)
        offset += len(raw) + pad
        return len(views) - 1

    for k, pid in enumerate(IDS):
        fig = read_glb(SRC / f"{pid}_stand.glb")
        cx, cy = k % COLS, k // COLS
        atlas.paste(fig["image"].resize((CELL, CELL), Image.LANCZOS), (cx * CELL, cy * CELL))
        # Half a texel in from the cell edge so neighbours never bleed in.
        uv = np.mod(fig["uv"], 1.0) if fig["uv"].min() < 0.0 or fig["uv"].max() > 1.0 else fig["uv"]
        inset = 0.5 / CELL
        uv = (uv * (1.0 - 2.0 * inset) + inset + np.array([cx, cy], dtype=np.float32)) / np.array([COLS, rows], dtype=np.float32)
        pos = fig["pos"].copy()
        pos[:, 1] += float(hips[pid]["stand_hip"])
        pos[:, 1] -= max(0.0, float(pos[:, 1].min()))  # feet exactly on y = 0
        idx = fig["idx"].astype(np.uint16 if len(pos) < 65535 else np.uint32)
        a0 = len(accessors)
        accessors.append({"bufferView": add(pos.astype(np.float32), 34962), "componentType": 5126, "count": len(pos), "type": "VEC3",
            "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()})
        accessors.append({"bufferView": add(fig["nor"], 34962), "componentType": 5126, "count": len(pos), "type": "VEC3"})
        accessors.append({"bufferView": add(uv.astype(np.float32), 34962), "componentType": 5126, "count": len(pos), "type": "VEC2"})
        accessors.append({"bufferView": add(idx, 34963), "componentType": 5123 if idx.dtype == np.uint16 else 5125, "count": len(idx), "type": "SCALAR"})
        meshes.append({"name": pid, "primitives": [{"attributes": {"POSITION": a0, "NORMAL": a0 + 1, "TEXCOORD_0": a0 + 2}, "indices": a0 + 3, "material": 0}]})
        nodes.append({"name": pid, "mesh": k})
        print(f"{pid:22s} {len(idx) // 3} tris, height {pos[:, 1].max():.2f} m")
    png = io.BytesIO()
    atlas.save(png, format="PNG", optimize=True)
    image_view = add(np.frombuffer(png.getvalue(), dtype=np.uint8), None)
    body = b"".join(blobs)
    doc = {
        "asset": {"version": "2.0", "generator": "namma-auto bake_shop_people.py"},
        "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes,
        "materials": [{"name": "ShopPeople", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.85}}],
        "textures": [{"source": 0, "sampler": 0}], "samplers": [{"wrapS": 33071, "wrapT": 33071}],
        "images": [{"mimeType": "image/png", "bufferView": image_view}],
        "buffers": [{"byteLength": len(body)}], "bufferViews": views, "accessors": accessors,
    }
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * ((-len(text)) % 4)
    OUT.write_bytes(b"glTF" + struct.pack("<II", 2, 28 + len(text) + len(body)) + struct.pack("<I4s", len(text), b"JSON") + text
        + struct.pack("<I4s", len(body), b"BIN\0") + body)
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
