#!/usr/bin/env python3
"""Turn raw downloads in assets_src/incoming/ into small game-ready OGG files.

Raw sources (WAV/MP3, tens of MB) stay local and are gitignored. Only the processed OGGs
(a few hundred KB each) go into assets/audio/, which is what the game loads and what git stores.

Each clip is cut to the part the game needs, looped with a crossfade where needed, peak-normalised
(VehicleAudio sets the actual volume), and encoded as mono Vorbis at about 96 kbps.

Usage: python3 tools/assets/process_incoming.py [output file names to rebuild]
Needs: ffmpeg, numpy. Writes assets/audio/vehicle/*.ogg and assets/audio/CREDITS_vehicle.md.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src" / "incoming" / "audio"
OUT = ROOT / "assets" / "audio" / "vehicle"
SR = 44100
PEAK_DB = -1.0

# out name, source (relative to assets_src/incoming/audio), mode, credit line
SPECS = [
    ("engine_lpg_loop.ogg", "kalhan/261059__kalhan__auto-rickshaw-start-idle-some-revving.wav",
     "steady_loop", "kalhan (Freesound #261059), CC BY 4.0"),
    ("kick_start.ogg", "kalhan/261063__kalhan__auto-rickshaw-start-lever-attempts-start-idle-with-little-revving.wav",
     "trim", "kalhan (Freesound #261063), CC BY 4.0"),
    ("horn_bulb.ogg", "horns/2ac72971-alex_jauk-bulb-horn-honk-221702.mp3",
     "trim", "alex_jauk (Pixabay Content Licence)"),
    ("horn_air.ogg", "horns/ed77d235-174819__goose278__air-horn-close-and-loud.wav",
     "trim", "goose278 (Freesound #174819), CC0"),
    ("indicator_tick.ogg", "indicator/22008cfc-195994__productionnow__car-turn-signal-blinker-left-and-right.wav",
     "first_click", "ProductionNow (Freesound #195994), CC0"),
    # Madras King Deluxe: the diesel auto's heavier knock (VehicleStats.engine_loop).
    ("engine_diesel_loop.ogg", "vehicle/recordx_media-diesel-auto-rickshaw-sound-199866.mp3",
     "steady_loop", "recordx_media (Pixabay #199866), Pixabay Content Licence"),
    # Everywhere-bed of Indian city traffic under the zone ambiences (AmbienceAudio "city").
    ("../ambience/city_traffic_loop.ogg", "ambience/soundque-indian-city-road-ambience-446354.mp3",
     "ambience_loop", "SoundQue field recording (Pixabay #446354), Pixabay Content Licence"),
]


def load_mono(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1",
                          "-ar", str(SR), "pipe:1"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def trim_silence(x: np.ndarray, floor_db: float = -45.0, pad_s: float = 0.02) -> np.ndarray:
    env = np.abs(x)
    idx = np.nonzero(env > 10 ** (floor_db / 20))[0]
    if idx.size == 0:
        return x
    pad = int(pad_s * SR)
    return x[max(0, idx[0] - pad): min(len(x), idx[-1] + pad)]


def steady_window(x: np.ndarray, seconds: float) -> np.ndarray:
    """Pick the most even-sounding stretch (lowest level variation), skipping cranking."""
    frame = int(0.05 * SR)
    n = len(x) // frame
    rms = np.sqrt((x[: n * frame].reshape(n, frame) ** 2).mean(axis=1) + 1e-12)
    db = 20 * np.log10(rms)
    w = int(seconds / 0.05)
    best, best_score = 0, float("inf")
    for i in range(0, n - w, 4):
        seg = db[i: i + w]
        if seg.mean() < -40:
            continue
        score = seg.std()
        if score < best_score:
            best, best_score = i, score
    start = best * frame
    return x[start: start + w * frame]


def make_loop(seg: np.ndarray, xfade_s: float = 0.5) -> np.ndarray:
    """Crossfade the tail into the head so the wrap-around point has no click."""
    x = int(xfade_s * SR)
    body = seg[: len(seg) - x].copy()
    tail = seg[len(seg) - x:]
    w = np.linspace(0.0, 1.0, x)
    body[:x] = body[:x] * w + tail * (1.0 - w)
    return body


def first_click(x: np.ndarray, length_s: float = 0.25) -> np.ndarray:
    env = np.abs(x)
    peak = env.max()
    idx = int(np.argmax(env > 0.3 * peak))
    start = max(0, idx - int(0.01 * SR))
    seg = x[start: start + int(length_s * SR)].copy()
    fade = min(len(seg), int(0.08 * SR))
    seg[-fade:] *= np.linspace(1.0, 0.0, fade)
    return seg


def ambience_window(x: np.ndarray, seconds: float) -> np.ndarray:
    """A lively but even stretch: skip the first seconds, avoid the loudest/quietest extremes."""
    frame = int(0.5 * SR)
    n = len(x) // frame
    db = 20 * np.log10(np.sqrt((x[: n * frame].reshape(n, frame) ** 2).mean(axis=1) + 1e-12))
    w = int(seconds / 0.5)
    target = np.median(db)
    best, best_score = 4, float("inf")
    for i in range(4, n - w):
        seg = db[i: i + w]
        score = abs(seg.mean() - target) + 0.5 * seg.std() + 0.3 * max(0.0, seg.max() - target - 9.0)
        if score < best_score:
            best, best_score = i, score
    return x[best * frame: (best + w) * frame]


def fade_edges(x: np.ndarray, ms: float = 8.0) -> np.ndarray:
    n = min(len(x) // 2, int(ms / 1000 * SR))
    x = x.copy()
    x[:n] *= np.linspace(0.0, 1.0, n)
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


def normalise(x: np.ndarray) -> np.ndarray:
    peak = np.abs(x).max()
    return x * (10 ** (PEAK_DB / 20) / peak) if peak > 0 else x


def encode(x: np.ndarray, dest: Path) -> None:
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1",
                    "-i", "pipe:0", "-c:a", "libvorbis", "-b:a", "96k", str(dest)],
                   input=x.astype(np.float32).tobytes(), check=True)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    credits = ["# Vehicle sounds (processed from assets_src/incoming)", "",
               "| File | Source | Licence |", "|---|---|---|"]
    failed = 0
    only = sys.argv[1:]
    # Keep credit rows for files this script does not make (synthesised SFX etc.).
    keep_rows: dict[str, str] = {}
    credits_path = ROOT / "assets" / "audio" / "CREDITS_vehicle.md"
    if credits_path.exists():
        for line in credits_path.read_text().splitlines():
            if line.startswith("| `assets/"):
                keep_rows[line.split("`")[1]] = line
    for out_name, rel, mode, credit in SPECS:
        dest_rel = f"assets/audio/vehicle/{out_name}" if "/" not in out_name else "assets/audio/" + out_name.split("../")[-1]
        keep_rows[dest_rel] = f"| `{dest_rel}` | {rel} | {credit} |"
        if only and Path(out_name).name not in only:
            continue
        src = SRC / rel
        if not src.exists():
            print(f"MISSING {rel}")
            failed += 1
            continue
        x = load_mono(src)
        if mode == "steady_loop":
            y = make_loop(steady_window(x, 8.0))
        elif mode == "ambience_loop":
            y = make_loop(ambience_window(x, 46.0), 2.0)
        elif mode == "first_click":
            y = fade_edges(first_click(x))
        else:
            y = fade_edges(trim_silence(x))
        y = normalise(y)
        dest = (OUT / out_name).resolve()
        dest.parent.mkdir(parents=True, exist_ok=True)
        encode(y, dest)
        kb = dest.stat().st_size // 1024
        print(f"OK   {out_name}: {len(y) / SR:.2f} s, {kb} KB, peak {20 * np.log10(np.abs(y).max()):.1f} dBFS")
    credits.extend(keep_rows.values())
    credits_path.write_text("\n".join(credits) + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
