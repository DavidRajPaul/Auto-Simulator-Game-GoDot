#!/usr/bin/env python3
"""Download the CC0 / CC BY assets the game uses from hosts the dev sandbox can't reach, convert them
for mobile, and record their credits. Runs in CI (.github/workflows/fetch-assets.yml).

Every entry is CC0 (public domain): BigSoundBank (Joseph Sardin) — https://bigsoundbank.com
Output: assets/audio/**.ogg (mono Vorbis) + assets/audio/CREDITS_fetched.md
Needs: ffmpeg. Usage: python3 tools/assets/fetch_assets.py
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# out path, source URL, page, start s, duration s, ffmpeg extra filter
ASSETS = [
    ("assets/audio/ambience/rain_roof_loop.ogg", "https://bigsoundbank.com/UPLOAD/mp3/1293.mp3",
     "https://bigsoundbank.com/detail-1293-rain-on-car-roof.html", 5, 30, "Rain on car roof"),
    ("assets/audio/ambience/sea_waves_loop.ogg", "https://bigsoundbank.com/UPLOAD/mp3/0698.mp3",
     "https://bigsoundbank.com/sea-waves_s0698.html", 10, 40, "Sea Waves"),
    ("assets/audio/ambience/market_loop.ogg", "https://bigsoundbank.com/UPLOAD/mp3/2728.mp3",
     "https://bigsoundbank.com/sound-2728-marche-exterieur-1.html", 10, 40, "Outdoor Market #1"),
    ("assets/audio/traffic/truck_horn.ogg", "https://bigsoundbank.com/UPLOAD/mp3/2721.mp3",
     "https://bigsoundbank.com/sound-2721-truck-horn.html", 0, 3, "Truck Horn"),
    # Nov 13 street ambience (scripts/world/AmbienceAudio.gd): day crows, dawn birds, night insects,
    # and one-shots for temple / church bells, street dogs and a cycle bell.
    ("assets/audio/ambience/crows_loop.ogg", "https://bigsoundbank.com/UPLOAD/mp3/0754.mp3",
     "https://bigsoundbank.com/crows-s0754.html", 2, 40, "Crows 1"),
    ("assets/audio/ambience/birds_city_loop.ogg", "https://bigsoundbank.com/UPLOAD/mp3/3575.mp3",
     "https://bigsoundbank.com/oiseaux-en-ville-1-s3575.html", 2, 40, "Birds in the City #1"),
    ("assets/audio/ambience/night_insects_loop.ogg", "https://bigsoundbank.com/UPLOAD/mp3/3187.mp3",
     "https://bigsoundbank.com/insect-song-4-s3187.html", 1, 30, "Insect song #4"),
    ("assets/audio/ambience/temple_bell.ogg", "https://bigsoundbank.com/UPLOAD/mp3/0897.mp3",
     "https://bigsoundbank.com/bell-s0897.html", 0, 9, "Bell"),
    ("assets/audio/ambience/church_bell.ogg", "https://bigsoundbank.com/UPLOAD/mp3/0830.mp3",
     "https://bigsoundbank.com/1-church-bell-s0830.html", 2, 14, "1 church bell"),
    ("assets/audio/ambience/dogs_far.ogg", "https://bigsoundbank.com/UPLOAD/mp3/0288.mp3",
     "https://bigsoundbank.com/barking-dogs-s0288.html", 0, 8, "Barking dogs"),
    ("assets/audio/ambience/cycle_bell.ogg", "https://bigsoundbank.com/UPLOAD/mp3/0974.mp3",
     "https://bigsoundbank.com/search?q=bells", 0, 4, "Bicycle Bell #3 (sound 0974)"),
]
# Nov 14 thunderstorms (scripts/world/Thunderstorm.gd): BigSoundBank "Thunder #1-#11", single real
# thunderclaps recorded without rain (Joseph Sardin, CC0). Full length, no fade-in: the opening
# crack IS the sound of a close strike. The game picks one by strike distance and filters it.
THUNDER = [(2718, 23), (3113, 6), (3114, 12), (3115, 18), (3116, 22), (3179, 14), (3180, 13),
           (3181, 42), (3182, 30), (3183, 31), (3184, 36)]
for _n, (_id, _len) in enumerate(THUNDER, start=1):
    ASSETS.append((f"assets/audio/weather/thunder_{_n:02d}.ogg", f"https://bigsoundbank.com/UPLOAD/mp3/{_id:04d}.mp3",
                   "https://bigsoundbank.com/search?q=coup+de+tonnerre", 0, _len, f"Thunder #{_n} (sound {_id:04d})"))
# Those are all medium-to-far booms and rumbles (nothing above ~1 kHz). A strike close by starts
# with a ripping crack, so the close set comes from Freesound field recordings of very close
# strikes. "freesound:" URLs are resolved to the sound's public preview (og:audio on its page).
ASSETS += [
    ("assets/audio/weather/thunder_close_01.ogg", "freesound:https://freesound.org/people/TSP-Talk/sounds/844420/",
     "https://freesound.org/people/TSP-Talk/sounds/844420/", 0, 40, "Close thunderclap, Munich-Trudering"),
    ("assets/audio/weather/thunder_close_02.ogg", "freesound:https://freesound.org/people/InspectorJ/sounds/360328/",
     "https://freesound.org/people/InspectorJ/sounds/360328/", 0, 14, "Thunder, Very Close, Rain, A.wav"),
    ("assets/audio/weather/thunder_close_03.ogg", "freesound:https://freesound.org/people/kevp888/sounds/639273/",
     "https://freesound.org/people/kevp888/sounds/639273/", 9, 32, "VOC_220619-2022-2_FR_LoudThunderclap.wav"),
]


# Sounds on BigSoundBank that are not Joseph Sardin's own recordings.
AUTHORS = {
    "assets/audio/ambience/dogs_far.ogg": "DenisChardonnet (BigSoundBank)",
    "assets/audio/weather/thunder_close_01.ogg": "TSP-Talk (Freesound)",
    "assets/audio/weather/thunder_close_02.ogg": "InspectorJ, www.jshaw.co.uk (Freesound)",
    "assets/audio/weather/thunder_close_03.ogg": "kevp888 / Kevin Luce (Freesound)",
}
# Everything else is CC0.
LICENCES = {
    "assets/audio/weather/thunder_close_02.ogg": "CC BY 4.0",
    "assets/audio/weather/thunder_close_03.ogg": "CC BY 4.0",
}


def resolve(url: str) -> str:
    """A "freesound:<page>" URL becomes the sound's public HQ preview (no login needed)."""
    if not url.startswith("freesound:"):
        return url
    page = url[len("freesound:"):]
    req = urllib.request.Request(page, headers={"User-Agent": "Mozilla/5.0 NammaAuto-asset-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        html = r.read().decode("utf-8", "replace")
    m = re.search(r'https://cdn\.freesound\.org/previews/\d+/\d+_\d+-hq\.(?:mp3|ogg)', html)
    if not m:
        raise RuntimeError(f"no preview on {page}")
    return m.group(0)


def main() -> int:
    credits = ["# Fetched assets (CC0 — public domain — unless the Licence column says CC BY)", "",
               "| File | Source | Title | Author | Licence |", "|---|---|---|---|---|"]
    failed = 0
    force = "--force" in sys.argv
    for out, url, page, start, dur, title in ASSETS:
        dest = ROOT / out
        dest.parent.mkdir(parents=True, exist_ok=True)
        author = AUTHORS.get(out, "Joseph Sardin (BigSoundBank)")
        line = f"| `{out}` | [{page}]({page}) | {title} | {author} | {LICENCES.get(out, 'CC0')} |"
        if dest.exists() and not force:
            print(f"KEEP {out} (already fetched; --force to replace)")
            credits.append(line)
            continue
        try:
            with tempfile.NamedTemporaryFile(suffix=".mp3") as tmp:
                req = urllib.request.Request(resolve(url), headers={"User-Agent": "Mozilla/5.0 NammaAuto-asset-fetch/1.0"})
                with urllib.request.urlopen(req, timeout=60) as r:
                    tmp.write(r.read())
                tmp.flush()
                # Mono, 44.1 kHz, ~80 kbps Vorbis; short fades so loops don't click.
                fade_out = max(0.0, dur - 0.4)
                # Thunder keeps its own attack (a fade-in would blunt the crack); the game sets each
                # strike's level from its distance, so every file is normalised the same way.
                if "/weather/thunder_" in out:
                    fade_out = max(0.0, dur - 1.5)
                    filters = f"afade=t=out:st={fade_out}:d=1.5,loudnorm=I=-16:TP=-1"
                else:
                    filters = f"afade=t=in:d=0.3,afade=t=out:st={fade_out}:d=0.4,loudnorm=I=-20"
                subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(start), "-t", str(dur), "-i", tmp.name,
                                "-ac", "1", "-ar", "44100", "-af", filters,
                                "-c:a", "libvorbis", "-q:a", "3", str(dest)], check=True)
            print(f"OK   {out} ({dest.stat().st_size // 1024} KB)")
            credits.append(line)
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"FAIL {out}: {e}")
            if dest.exists():
                credits.append(line)
    (ROOT / "assets" / "audio" / "CREDITS_fetched.md").write_text("\n".join(credits) + "\n")
    return 1 if failed == len(ASSETS) else 0


if __name__ == "__main__":
    sys.exit(main())
