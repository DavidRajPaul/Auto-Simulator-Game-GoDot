#!/usr/bin/env python3
"""Bring every voice line to one loudness, so no speaker is drowned out by the engine.

Nov 25 device report: in the Paati quest only the hero could be heard. Parler-TTS gives each voice
a very different level: Paati's English lines measured -42..-37 LUFS against the hero's -14, and
512 of 1,304 voice files were below -24 LUFS. Every file is now set to TARGET_LUFS (two-pass
EBU R128 loudnorm, linear gain where the true peak allows) and re-encoded the way the generator
encodes (mono, 32 kHz, Vorbis q1).

    python3 tools/voice/normalize_voices.py                 # fix every file under assets/audio/voice
    python3 tools/voice/normalize_voices.py --check         # list files off target, exit 1 if any
    python3 tools/voice/normalize_voices.py path/a.ogg ...  # just these files

generate_parler.py / generate_quest_voices.py call normalize_file() on every new line. Needs ffmpeg.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

TARGET_LUFS = -16.0
TRUE_PEAK_DB = -1.5
LRA = 11.0
TOLERANCE_LU = 1.5  # files within this of the target are left alone (no needless re-encode)
LAND_LU = 0.6       # a rewrite aims this close
LIMIT = 0.72        # limiter ceiling (sample peak, about -2.9 dBFS): Vorbis overshoots, so the true peak stays under TRUE_PEAK_DB
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "audio", "voice")


def measure(path: str) -> dict:
    """ffmpeg loudnorm first pass: input_i, input_tp, input_lra, input_thresh, target_offset."""
    flt = f"loudnorm=I={TARGET_LUFS}:TP={TRUE_PEAK_DB}:LRA={LRA}:print_format=json"
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", flt, "-f", "null", "-"],
                         capture_output=True, text=True, check=True).stderr
    return json.loads(out[out.rindex("{"):out.rindex("}") + 1])


def off_target(m: dict) -> bool:
    i = float(m["input_i"])
    if i == float("-inf") or i < -70.0:
        return False  # silence: nothing to fix
    return abs(i - TARGET_LUFS) > TOLERANCE_LU or float(m["input_tp"]) > TRUE_PEAK_DB + 0.5


def normalize_file(path: str, force: bool = False) -> bool:
    """Normalise one .ogg in place. Returns True when it was rewritten.

    Gain to the target, then a look-ahead limiter on the few peaks that would clip; measured again
    and nudged until it lands (short lines are too short for loudnorm's own dynamic mode, which
    left them 2-7 LU quiet)."""
    m = measure(path)
    if not force and not off_target(m):
        return False
    gain = TARGET_LUFS - float(m["input_i"])
    fd, tmp = tempfile.mkstemp(suffix=".ogg")
    os.close(fd)
    try:
        for _attempt in range(4):
            af = f"volume={gain:.2f}dB,alimiter=limit={LIMIT}:attack=4:release=60:level=disabled"
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-af", af, "-ac", "1", "-ar", "32000",
                            "-c:a", "libvorbis", "-q:a", "1", tmp], check=True)
            got = float(measure(tmp)["input_i"])
            if abs(got - TARGET_LUFS) <= LAND_LU:
                break
            gain += TARGET_LUFS - got
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return True


def voice_files(paths: list) -> list:
    if paths:
        return paths
    out = []
    for d, _dirs, files in os.walk(ROOT):
        out += [os.path.join(d, f) for f in sorted(files) if f.endswith(".ogg")]
    return sorted(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--check", action="store_true", help="report files off target, change nothing")
    ap.add_argument("--force", action="store_true", help="re-normalise files already on target")
    args = ap.parse_args()
    files = voice_files(args.files)
    bad = 0
    fixed = 0
    for n, f in enumerate(files, 1):
        if args.check:
            m = measure(f)
            if off_target(m):
                bad += 1
                print(f"off target: {f} {float(m['input_i']):.1f} LUFS, peak {float(m['input_tp']):.1f} dBTP")
        elif normalize_file(f, args.force):
            fixed += 1
        if n % 200 == 0:
            print(f"  {n}/{len(files)}", flush=True)
    if args.check:
        print(f"{bad} of {len(files)} voice files are off {TARGET_LUFS} LUFS (+/- {TOLERANCE_LU})")
        return 1 if bad else 0
    print(f"normalised {fixed} of {len(files)} voice files to {TARGET_LUFS} LUFS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
