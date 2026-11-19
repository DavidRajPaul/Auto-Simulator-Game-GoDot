#!/usr/bin/env python3
"""Voice quest lines with AI4Bharat Indic Parler-TTS (Apache 2.0, free for commercial use).

Same script format as generate_quest_voices.py. Each speaker's voice comes from cast.json
"parler": a named Parler speaker + a description + a fixed seed, so a character (above all the
hero "Driver") sounds the same in every line and every quest. The [bracket] acting tags are
not spoken: they pick the emotion word added to the description.

Writes <out>/<id>_<ta|en>.ogg (mono Vorbis, small); lines that already have a file are skipped.
Needs: torch, git+https://github.com/huggingface/parler-tts, soundfile, ffmpeg, and an HF_TOKEN
for an account that accepted the model's terms (huggingface.co/ai4bharat/indic-parler-tts).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_quest_voices import parse  # noqa: E402

MODEL = "ai4bharat/indic-parler-tts"
# ElevenLabs-style acting tags -> the emotion Indic Parler knows (Tamil supports emotions).
EMOTIONS = [
    ("sad", ("cry", "sob", "sad", "breaking", "disappoint", "tired", "sniffl", "sigh")),
    ("fearful", ("panic", "desperate", "scared", "anxious", "tense", "worried", "nervous", "plead", "breathless", "alarm")),
    ("angry", ("angry", "impatient", "frustrat", "sharp", "firm")),
    ("surprised", ("startled", "gasp", "surpris")),
    ("happy", ("excited", "happy", "laugh", "giggl", "triumph", "grateful", "touched", "shy", "relief", "playful", "warm", "hopeful")),
    ("commanding", ("urgent", "guiding", "shout", "insist")),
]


def emotion_for(tags):
    joined = " ".join(tags).lower()
    for word, keys in EMOTIONS:
        if any(k in joined for k in keys):
            return word
    return "conversational"


def split_tags(text):
    tags = re.findall(r"\[([^\]]*)\]", text)
    return re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]", "", text)).strip(), tags


# Normal speech here is ~0.07 s per character. Parler sometimes cuts a line short (0.5 s for a
# whole sentence) or rambles: retry with another seed, up to ATTEMPTS times.
MIN_S_PER_CHAR = 0.035
MAX_S_PER_CHAR = 0.2
ATTEMPTS = 4
TRIM = ("silenceremove=start_periods=1:start_threshold=-50dB,areverse,"
        "silenceremove=start_periods=1:start_threshold=-50dB,areverse")


def voice_line(model, tok, desc_tok, rate, ogg, text, desc, seed, sf, torch, locked=False):
    """Generate, trim, check the length, encode. Returns seconds; raises if every attempt is off.
    A locked speaker (the hero) is never re-rolled: a different seed would be a different voice."""
    best = None
    for attempt in range(1 if locked else ATTEMPTS):
        torch.manual_seed(seed + 1000 * attempt)
        d = desc_tok(desc, return_tensors="pt")
        p = tok(text, return_tensors="pt")
        with torch.inference_mode():
            audio = model.generate(input_ids=d.input_ids, attention_mask=d.attention_mask,
                                   prompt_input_ids=p.input_ids, prompt_attention_mask=p.attention_mask)
        raw = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
        trimmed = raw[:-4] + "_t.wav"
        sf.write(raw, audio.cpu().numpy().squeeze(), rate)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-af", TRIM, trimmed], check=True)
        os.remove(raw)
        seconds = sf.info(trimmed).duration
        per_char = seconds / max(1, len(text))
        if MIN_S_PER_CHAR <= per_char <= MAX_S_PER_CHAR:
            if best:
                os.remove(best[1])
            best = (seconds, trimmed)
            break
        print(f"  {os.path.basename(ogg)}: {seconds:.1f}s for {len(text)} chars, retrying", flush=True)
        if best is None or abs(per_char - 0.07) < abs(best[0] / max(1, len(text)) - 0.07):
            if best:
                os.remove(best[1])
            best = (seconds, trimmed)
        else:
            os.remove(trimmed)
    seconds, trimmed = best
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", trimmed, "-ac", "1", "-ar", "32000",
                    "-c:a", "libvorbis", "-q:a", "1", ogg], check=True)
    os.remove(trimmed)
    per_char = seconds / max(1, len(text))
    if not MIN_S_PER_CHAR <= per_char <= MAX_S_PER_CHAR:
        raise RuntimeError(f"still {seconds:.1f}s for {len(text)} chars after {ATTEMPTS} tries (kept best, check it)")
    return seconds


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("script")
    ap.add_argument("--cast", default=os.path.join(here, "cast.json"))
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", help="comma-separated line ids to redo")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="print the prompts, load no model")
    args = ap.parse_args()

    cast = {k: v for k, v in json.load(open(args.cast, encoding="utf-8")).items() if not k.startswith("_")}
    only = set(args.only.split(",")) if args.only else None
    os.makedirs(args.out, exist_ok=True)

    jobs = []
    for line_id, speaker, ta, en in parse(args.script):
        if only and line_id not in only:
            continue
        voice = cast.get(speaker, {}).get("parler")
        if not voice:
            print(f"no parler voice for '{speaker}' ({line_id}) in cast.json", file=sys.stderr)
            sys.exit(1)
        for lang, raw in (("ta", ta), ("en", en)):
            ogg = os.path.join(args.out, f"{line_id}_{lang}.ogg")
            if os.path.exists(ogg) and not args.force:
                continue
            text, tags = split_tags(raw)
            if voice.get("locked_description"):
                desc = voice["description"]  # the hero: identical in every line, every quest
                locked = True
            else:
                desc = voice["description"].format(name=voice["speaker"], emotion=emotion_for(tags))
                locked = False
            jobs.append((ogg, text, desc, int(voice["seed"]), locked))

    if args.dry_run:
        for ogg, text, desc, seed, _locked in jobs:
            print(f"{os.path.basename(ogg)} seed={seed}\n  text: {text}\n  desc: {desc}")
        print(f"{len(jobs)} files")
        return
    if not jobs:
        print("nothing to do")
        return

    import soundfile as sf
    import torch
    from parler_tts import ParlerTTSForConditionalGeneration
    from transformers import AutoTokenizer

    torch.set_num_threads(os.cpu_count() or 2)
    model = ParlerTTSForConditionalGeneration.from_pretrained(MODEL).eval()
    tok = AutoTokenizer.from_pretrained(MODEL)
    desc_tok = AutoTokenizer.from_pretrained(model.config.text_encoder._name_or_path)
    rate = model.config.sampling_rate

    failed = 0
    for i, (ogg, text, desc, seed, locked) in enumerate(jobs, 1):
        try:
            seconds = voice_line(model, tok, desc_tok, rate, ogg, text, desc, seed, sf, torch, locked)
            print(f"[{i}/{len(jobs)}] ok {os.path.basename(ogg)} {seconds:.1f}s", flush=True)
        except Exception as e:  # keep going: one bad line must not lose the rest
            failed += 1
            print(f"[{i}/{len(jobs)}] FAIL {os.path.basename(ogg)}: {e}", file=sys.stderr, flush=True)
    print(f"done={len(jobs) - failed} failed={failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
