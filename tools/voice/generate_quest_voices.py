#!/usr/bin/env python3
"""Generate quest voice lines with ElevenLabs from a script markdown file.

Reads lines like:
  - sq07_l01 Lakshmi: [shouting, panicked] Tamil text / [shouting, panicked] English text

For each line it writes <out>/<id>_ta.ogg and <out>/<id>_en.ogg (mono Vorbis, small: the
whole of assets/audio has a size budget). Needs ffmpeg; without it the .mp3 is kept instead.

Usage:
  export ELEVENLABS_API_KEY=...
  python3 generate_quest_voices.py SQ07_Red_Kite_Voice_Script.md \
      --voices voices.json --out ../../assets/audio/voice/sq07

Only lines whose speaker is in voices.json are generated; existing files are skipped
unless --force is given, so re-running after an edit only redoes what you changed.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_44100_128"
MODEL = "eleven_v3"
LINE = re.compile(r"^- (sq\d+_\w+)\s+([^:(]+?)(?:\s*\([^)]*\))?:\s+(.+)$")


def parse(path):
    """Yield (id, speaker, tamil_text, english_text) for every voiced line."""
    for raw in open(path, encoding="utf-8"):
        m = LINE.match(raw.strip())
        if not m:
            continue
        line_id, speaker, body = m.group(1), m.group(2).strip(), m.group(3)
        if " / " not in body:
            print(f"skip {line_id}: no ' / ' between Tamil and English", file=sys.stderr)
            continue
        ta, en = (part.strip() for part in body.split(" / ", 1))
        yield line_id, speaker, ta, en


def synthesise(api_key, voice_id, text):
    body = json.dumps({
        "text": text,
        "model_id": MODEL,
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.8},
    }).encode("utf-8")
    req = urllib.request.Request(
        API.format(voice_id=voice_id), data=body, method="POST",
        headers={"xi-api-key": api_key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"ElevenLabs {e.code}: {e.read().decode('utf-8', 'replace')[:300]}")


def to_ogg(mp3_path):
    """Mono Vorbis ~48 kbps, then the mp3 is deleted. No ffmpeg: keep the mp3."""
    if not shutil.which("ffmpeg"):
        return
    ogg_path = mp3_path[:-4] + ".ogg"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3_path, "-ac", "1", "-ar", "32000",
                    "-c:a", "libvorbis", "-q:a", "1", ogg_path], check=True)
    os.remove(mp3_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("script")
    ap.add_argument("--voices", required=True, help="JSON map: speaker name -> ElevenLabs voice_id")
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", help="comma-separated line ids to regenerate, e.g. sq07_l01,sq07_l02")
    ap.add_argument("--force", action="store_true", help="overwrite existing files")
    ap.add_argument("--dry-run", action="store_true", help="list what would be generated, no API calls")
    args = ap.parse_args()

    api_key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Set ELEVENLABS_API_KEY first.")
    voices = {k: v for k, v in json.load(open(args.voices, encoding="utf-8")).items() if not k.startswith("_")}
    only = set(args.only.split(",")) if args.only else None
    os.makedirs(args.out, exist_ok=True)

    done = skipped = failed = 0
    for line_id, speaker, ta, en in parse(args.script):
        if only and line_id not in only:
            continue
        if not voices.get(speaker):
            print(f"no voice set for '{speaker}' ({line_id}); add it to {args.voices}", file=sys.stderr)
            failed += 1
            continue
        for lang, text in (("ta", ta), ("en", en)):
            out_path = os.path.join(args.out, f"{line_id}_{lang}.mp3")
            done_already = os.path.exists(out_path) or os.path.exists(out_path[:-4] + ".ogg")
            if done_already and not args.force:
                skipped += 1
                continue
            if args.dry_run:
                print(f"would make {out_path} [{speaker}]: {text[:60]}")
                continue
            try:
                audio = synthesise(api_key, voices[speaker], text)
                with open(out_path, "wb") as f:
                    f.write(audio)
                to_ogg(out_path)
                done += 1
                print(f"ok {out_path}")
            except (RuntimeError, OSError, subprocess.CalledProcessError) as e:
                failed += 1
                print(f"FAIL {line_id}_{lang}: {e}", file=sys.stderr)

    print(f"done={done} skipped={skipped} failed={failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
