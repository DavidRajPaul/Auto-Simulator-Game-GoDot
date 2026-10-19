#!/usr/bin/env python3
"""Download the CC0 assets the game uses from hosts the dev sandbox can't reach, convert them
for mobile, and record their credits. Runs in CI (.github/workflows/fetch-assets.yml).

Every entry is CC0 (public domain): BigSoundBank (Joseph Sardin) — https://bigsoundbank.com
Output: assets/audio/**.ogg (mono Vorbis) + assets/audio/CREDITS_fetched.md
Needs: ffmpeg. Usage: python3 tools/assets/fetch_assets.py
"""
from __future__ import annotations

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
]


def main() -> int:
    credits = ["# Fetched assets (all CC0 — public domain)", "",
               "| File | Source | Title | Author | Licence |", "|---|---|---|---|---|"]
    failed = 0
    for out, url, page, start, dur, title in ASSETS:
        dest = ROOT / out
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            with tempfile.NamedTemporaryFile(suffix=".mp3") as tmp:
                req = urllib.request.Request(url, headers={"User-Agent": "NammaAuto-asset-fetch/1.0"})
                with urllib.request.urlopen(req, timeout=60) as r:
                    tmp.write(r.read())
                tmp.flush()
                # Mono, 44.1 kHz, ~80 kbps Vorbis; short fades so loops don't click.
                fade_out = max(0.0, dur - 0.4)
                subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(start), "-t", str(dur), "-i", tmp.name,
                                "-ac", "1", "-ar", "44100", "-af", f"afade=t=in:d=0.3,afade=t=out:st={fade_out}:d=0.4,loudnorm=I=-20",
                                "-c:a", "libvorbis", "-q:a", "3", str(dest)], check=True)
            print(f"OK   {out} ({dest.stat().st_size // 1024} KB)")
            credits.append(f"| `{out}` | [{page}]({page}) | {title} | Joseph Sardin (BigSoundBank) | CC0 |")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"FAIL {out}: {e}")
    (ROOT / "assets" / "audio" / "CREDITS_fetched.md").write_text("\n".join(credits) + "\n")
    return 1 if failed == len(ASSETS) else 0


if __name__ == "__main__":
    sys.exit(main())
