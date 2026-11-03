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
    # Engine fire, wind and dust (Nov 3): exact file names from the Particle Pack, "=" = basename match.
    "flame_tongue": ("particle", ("=flame_05.png",), 0, 256),  # licking flame tongue
    "flame_body": ("particle", ("=flame_01.png",), 0, 256),    # soft flame mass under the smoke
    "fire_embers": ("particle", ("=fire_01.png",), 0, 256),    # bright sparks rising off the fire
    "wind_streak": ("particle", ("=trace_06.png",), 0, 256),   # long soft gust streak
    "dust_puff": ("particle", ("=smoke_07.png",), 0, 256),     # soft dust cloud on the road
    "dust_grit": ("particle", ("=dirt_02.png",), 0, 256),      # grit blown off the road
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


def match(z: zipfile.ZipFile, words: tuple[str, ...], nth: int) -> str | None:
    if words[0].startswith("="):  # exact file name, whatever folder it sits in (e.g. PNG (Transparent)/)
        exact = [n for n in z.namelist() if n.lower().endswith(".png") and n.split("/")[-1] == words[0][1:]]
        return exact[0] if exact else None
    cands = sorted(n for n in z.namelist() if n.lower().endswith(".png")
                   and any(w.lower() in n.lower().replace("_", "").replace(" ", "") or w.lower() in n.lower() for w in words))
    return cands[min(nth, len(cands) - 1)] if cands else None


def main() -> int:
    # --particle-zip / --smoke-zip: use a zip already downloaded (no network). --offline: never fetch,
    # so only the zips given are read. --only a,b: write just those outputs (leaves the rest alone).
    args = sys.argv[1:]
    local: dict[str, str] = {}
    for key in ZIPS:
        if f"--{key}-zip" in args:
            local[key] = args[args.index(f"--{key}-zip") + 1]
    offline = "--offline" in args
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    OUT.mkdir(parents=True, exist_ok=True)
    zips: dict[str, zipfile.ZipFile] = {}
    loaded: set[str] = set()
    for key, url in ZIPS.items():
        try:
            if key in local:
                zips[key] = zipfile.ZipFile(local[key])
            elif not offline:
                zips[key] = fetch(url)
            else:
                continue
            loaded.add(key)
            names = [n for n in zips[key].namelist() if n.lower().endswith(".png")]
            print(f"OK   {key}: {len(names)} pngs")
        except Exception as e:  # noqa: BLE001
            print(f"FAIL {key}: {e}")
    # MANIFEST lists what each zip held: keep the lines of zips this run did not open.
    mf = OUT / "MANIFEST.txt"
    kept = [ln for ln in (mf.read_text().splitlines() if mf.exists() else [])
            if ln.split(":")[0] not in loaded]
    manifest = kept + [f"{key}: {n}" for key in loaded for n in zips[key].namelist() if n.lower().endswith(".png")]
    mf.write_text("\n".join(manifest) + "\n")
    got = 0
    for out, (key, words, nth, size) in WANT.items():
        z = zips.get(key)
        if z is None or (only is not None and out not in only):
            continue
        src = match(z, words, nth)
        if src is None:
            print(f"MISS {out}: no {words} in {key}")
            continue
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
