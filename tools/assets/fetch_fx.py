#!/usr/bin/env python3
"""Fetch CC0 particle textures (Kenney) for impact FX — sparks, smoke, dust, debris, scorch.

Sources (both CC0, Kenney — https://kenney.nl, mirrored on OpenGameArt):
  • Particle Pack (80+ sprites)  https://opengameart.org/content/particle-pack-80-sprites
  • Smoke Particle Assets        https://opengameart.org/content/smoke-particle-assets
Runs in CI (.github/workflows/fetch-fx.yml) because the dev sandbox can't reach these hosts.
Output: assets/fx/<name>.png (white RGBA, 128–256 px, alpha from luminance when needed)
        + assets/fx/CREDITS_fx.md + assets/fx/MANIFEST.txt (every file the zips contained).
"""
from __future__ import annotations

import io
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "fx"
ZIPS = {
    "particle": "https://opengameart.org/sites/default/files/kenney_particlePack.zip",
    "smoke": "https://opengameart.org/sites/default/files/smokeParticleAssets.zip",
}
# output name -> (zip, name keyword(s) to match, nth match, size px)
WANT = {
    "spark_a": ("particle", ("spark",), 0, 128),
    "spark_b": ("particle", ("spark",), 2, 128),
    "spark_streak": ("particle", ("trace",), 0, 128),
    "smoke_a": ("particle", ("smoke",), 0, 256),
    "smoke_b": ("particle", ("smoke",), 3, 256),
    "smoke_c": ("particle", ("smoke",), 6, 256),
    "dirt_a": ("particle", ("dirt",), 0, 256),
    "dirt_b": ("particle", ("dirt",), 1, 256),
    "scorch": ("particle", ("scorch",), 0, 256),
    "flare": ("particle", ("flare", "light"), 0, 128),
    "puff_a": ("smoke", ("whitepuff", "white puff", "puff"), 0, 256),
    "puff_b": ("smoke", ("whitepuff", "white puff", "puff"), 8, 256),
    "puff_black": ("smoke", ("blackSmoke", "black"), 4, 256),
}


def fetch(url: str) -> zipfile.ZipFile:
    req = urllib.request.Request(url, headers={"User-Agent": "NammaAuto-asset-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return zipfile.ZipFile(io.BytesIO(r.read()))


def to_white_rgba(img: Image.Image, size: int) -> Image.Image:
    img = img.convert("RGBA")
    r, g, b, a = img.split()
    lum = Image.merge("RGB", (r, g, b)).convert("L")
    if a.getextrema() == (255, 255):  # no alpha → white-on-black: brightness becomes alpha
        a = lum
    else:  # keep alpha, but let dark parts of the sprite fade too
        a = Image.composite(a, Image.new("L", a.size, 0), lum.point(lambda v: 255 if v > 8 else 0))
    white = Image.new("L", img.size, 255)
    out = Image.merge("RGBA", (white, white, white, a))
    out.thumbnail((size, size), Image.LANCZOS)
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    zips = {}
    manifest = []
    for key, url in ZIPS.items():
        try:
            zips[key] = fetch(url)
            names = [n for n in zips[key].namelist() if n.lower().endswith(".png")]
            manifest += [f"{key}: {n}" for n in names]
            print(f"OK   {key}: {len(names)} pngs")
        except Exception as e:  # noqa: BLE001
            print(f"FAIL {key}: {e}")
    (OUT / "MANIFEST.txt").write_text("\n".join(manifest) + "\n")
    got = 0
    for out, (key, words, nth, size) in WANT.items():
        z = zips.get(key)
        if z is None:
            continue
        cands = sorted(n for n in z.namelist() if n.lower().endswith(".png")
                       and any(w.lower() in n.lower().replace("_", "").replace(" ", "") or w.lower() in n.lower() for w in words))
        if not cands:
            print(f"MISS {out}: no {words} in {key}")
            continue
        src = cands[min(nth, len(cands) - 1)]
        img = to_white_rgba(Image.open(io.BytesIO(z.read(src))), size)
        img.save(OUT / f"{out}.png", optimize=True)
        got += 1
        print(f"OK   {out}.png  ← {src}")
    (OUT / "CREDITS_fx.md").write_text(
        "# Impact FX textures (CC0 — public domain)\n\n"
        "From Kenney (https://kenney.nl): *Particle Pack* and *Smoke Particle Assets*, via OpenGameArt.\n"
        "Recoloured to white RGBA and downscaled for mobile by tools/assets/fetch_fx.py. Credit optional, given with thanks.\n")
    return 0 if got else 1


if __name__ == "__main__":
    sys.exit(main())
