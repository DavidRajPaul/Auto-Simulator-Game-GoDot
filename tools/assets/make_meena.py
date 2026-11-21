"""Bakes Meena (sq_004, "Paati Knows the Way") from the street model girl_churidar.glb: the same
rig, mesh and clips, with the olive churidar recoloured rose pink in her own copy of the texture.

Why a copy and not PaintSwap: girl_churidar is a common street model, and in the city the GL
Compatibility renderer can run out of instance-uniform slots, so a repaint on a late-spawned quest
actor silently shows the stock olive dress (Nov 20 owner report: the dialogue said one colour, the
screen showed green). A baked texture always shows, and no other person in the city wears it.

Run from the repo root: python3 tools/assets/make_meena.py   (then godot --headless --import)
"""
import colorsys
import io
import json
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/models/people/girl_churidar.glb"
OUT = ROOT / "assets/models/people/quest/meena.glb"
PEOPLE = json.loads((ROOT / "assets/models/people/people.json").read_text())["people"]

PINK_HUE = 335.0 / 360.0  # rose pink ("rose colour" churidar)
HUE_TOL = 0.12
MIN_SAT = 0.2


def read_glb(path):
    data = path.read_bytes()
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen = struct.unpack("<I", data[off:off + 4])[0]
    return gltf, bytearray(data[off + 8:off + 8 + blen])


def write_glb(path, gltf, binary):
    j = json.dumps(gltf, separators=(",", ":")).encode()
    j += b" " * (-len(j) % 4)
    binary = bytes(binary) + b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(j) + 8 + len(binary)
    path.write_bytes(struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(j), 0x4E4F534A) + j
                     + struct.pack("<II", len(binary), 0x004E4942) + binary)


def recolour(img, src_rgb, rect):
    src_h = colorsys.rgb_to_hsv(*[c / 255.0 for c in src_rgb])[0]
    px = img.load()
    w, h = img.size
    x0, y0, x1, y1 = int(rect[0] * w), int(rect[1] * h), int(rect[2] * w), int(rect[3] * h)
    changed = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, *a = px[x, y]
            hh, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            dh = abs((hh - src_h + 0.5) % 1.0 - 0.5)
            if dh > HUE_TOL or s < MIN_SAT:
                continue
            nr, ng, nb = colorsys.hsv_to_rgb(PINK_HUE, min(1.0, s * 0.62), min(1.0, v * 1.45 + 0.08))
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), *a)
            changed += 1
    return changed


def main():
    gltf, binary = read_glb(SRC)
    paint = PEOPLE["girl_churidar"]["paint"]
    image = gltf["images"][0]
    view = gltf["bufferViews"][image["bufferView"]]
    start, length = view.get("byteOffset", 0), view["byteLength"]
    img = Image.open(io.BytesIO(bytes(binary[start:start + length]))).convert("RGBA")
    n = recolour(img, paint["colour"], paint["rect"])
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    png = buf.getvalue()
    png += b"\0" * (-len(png) % 4)
    # Replace the image's bytes and shift every buffer view that comes after it.
    delta = len(png) - length
    binary[start:start + length] = png
    view["byteLength"] = len(png)
    for other in gltf["bufferViews"]:
        if other is not view and other.get("byteOffset", 0) > start:
            other["byteOffset"] += delta
    gltf["buffers"][0]["byteLength"] = len(binary)
    write_glb(OUT, gltf, binary)
    print(f"wrote {OUT.relative_to(ROOT)}: {n} dress pixels recoloured")


if __name__ == "__main__":
    main()
