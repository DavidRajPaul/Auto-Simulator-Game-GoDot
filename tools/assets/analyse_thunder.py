#!/usr/bin/env python3
"""Sort the fetched thunder recordings for scripts/world/Thunderstorm.gd (Nov 14).

Writes assets/audio/weather/thunder.json: for every thunder_*.ogg its pool and where to start it.
  close  a recording with a real crack (energy above 2 kHz right after the onset): a strike within
         ~1.5 km. Only very close field recordings have one (the Freesound files).
  mid    a single boom under ~20 s whose peak comes early.
  far    a long roll (over 20 s, or its loudest part late): the storm a few kilometres off.
start    seconds into the file where the thunder begins (a short pre-roll for close and mid,
         a longer lead-in kept for far rumbles), so a strike's sound arrives exactly
         distance / 343 s after its flash instead of after the recording's own silence.

Run after the Fetch Assets workflow adds or replaces thunder files. Needs ffmpeg and numpy.
Usage: python3 tools/assets/analyse_thunder.py
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT / "assets" / "audio" / "weather"
SR = 22050
HOP = 441  # 20 ms
CRACK_SHARE = 0.01  # >1 % of the energy above 2 kHz in the first 0.4 s = a crack
# Heard and sorted by hand where the measure can't tell: TSP-Talk's very close Munich strike is a
# huge boom, but its public preview carries no crack, so it plays for strikes a little further out.
POOL_OVERRIDE = {"thunder_close_01": "mid"}


def decode(path: Path, sr: int) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def analyse(path: Path) -> dict:
    x = decode(path, SR)
    frames = len(x) // HOP
    rms = np.sqrt((x[:frames * HOP].reshape(frames, HOP) ** 2).mean(axis=1)) + 1e-9
    db = 20.0 * np.log10(rms)
    peak = int(db.argmax())
    onset = int(np.argmax(db > db[peak] - 15.0))
    soft_onset = int(np.argmax(db > db[peak] - 25.0))
    # High-frequency share just after the onset, from a full-band decode.
    hi = decode(path, 44100)
    a = int(onset * HOP / SR * 44100)
    seg = hi[a:a + int(0.4 * 44100)]
    seg = seg * np.hanning(len(seg)) if len(seg) > 32 else seg
    spec = np.abs(np.fft.rfft(seg)) ** 2
    freq = np.fft.rfftfreq(len(seg), 1.0 / 44100)
    crack = float(spec[freq > 2000].sum() / max(spec.sum(), 1e-12))
    length = len(x) / SR
    peak_s = peak * HOP / SR
    if crack >= CRACK_SHARE:
        pool = "close"
    elif length > 20.0 or peak_s > 8.0:
        pool = "far"
    else:
        pool = "mid"
    pool = POOL_OVERRIDE.get(path.stem, pool)
    start = max(0.0, (soft_onset * HOP / SR - 0.6) if pool == "far" else (onset * HOP / SR - 0.08))
    return {"pool": pool, "start": round(start, 2), "length": round(length, 2), "peak_s": round(peak_s, 2),
            "crack": round(crack, 4)}


def main() -> int:
    out: dict = {}
    for f in sorted(DIR.glob("thunder_*.ogg")):
        out[f.stem] = analyse(f)
        print(f.stem, out[f.stem])
    (DIR / "thunder.json").write_text(json.dumps({"files": out}, indent=1) + "\n")
    pools = {p: [k for k, v in out.items() if v["pool"] == p] for p in ("close", "mid", "far")}
    print({p: len(v) for p, v in pools.items()})
    return 0 if all(pools.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
