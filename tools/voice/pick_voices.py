#!/usr/bin/env python3
"""Pick a Tamil ElevenLabs voice for every speaker in cast.json that has none in voices.json.

Searches the public Voice Library (language=ta first), skips voices already used by another
speaker, adds the chosen voice to the account's library and writes its voice_id to voices.json.
Speakers marked "locked" in cast.json (the hero driver) are never re-picked once set, so the
hero sounds the same in every quest. Child speakers fall back to a child voice in any language
(Eleven v3 voices can speak Tamil) and then to a young female Tamil voice.

Usage: ELEVENLABS_API_KEY=... python3 pick_voices.py [--cast cast.json] [--voices voices.json]
Writes a Markdown summary (speaker, voice name, preview link) to $GITHUB_STEP_SUMMARY if set.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://api.elevenlabs.io/v1"
LIB_PREFIX = "NammaAuto "


def call(method, path, key, params=None, body=None):
    url = BASE + path + ("?" + urllib.parse.urlencode(params) if params else "")
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"xi-api-key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path} -> {e.code}: {e.read().decode('utf-8', 'replace')[:300]}")


def shared(key, **params):
    params = {k: v for k, v in params.items() if v}
    params.setdefault("page_size", 50)
    params.setdefault("sort", "usage_character_count_1y")
    return call("GET", "/shared-voices", key, params).get("voices", [])


def candidates(key, spec):
    """Queries from most to least specific; yields voices in order."""
    gender, ages, terms = spec["gender"], spec.get("age", []), spec.get("search", [])
    child = spec.get("child", False)
    queries = []
    for age in ages:
        for term in terms:
            queries.append(dict(language="ta", gender=gender, age=age, search=term))
        queries.append(dict(language="ta", gender=gender, age=age))
    if child:
        for term in terms:
            queries.append(dict(search=term, accent="indian"))
            queries.append(dict(search=term))
        queries.append(dict(language="ta", gender="female", age="young"))
    queries.append(dict(language="ta", gender=gender))
    seen = set()
    for q in queries:
        try:
            found = shared(key, **q)
        except RuntimeError as e:
            print(f"  query {q} failed: {e}", file=sys.stderr)
            continue
        for v in found:
            if v.get("voice_id") in seen or v.get("free_users_allowed") is False:
                continue
            seen.add(v["voice_id"])
            yield q, v


def add_to_library(key, speaker, v):
    """Returns the voice_id to use. Falls back to the shared id if the library is full."""
    name = LIB_PREFIX + speaker
    for mine in call("GET", "/voices", key).get("voices", []):
        if mine.get("name") == name:
            return mine["voice_id"]
    try:
        out = call("POST", f"/voices/add/{v['public_owner_id']}/{v['voice_id']}", key, body={"new_name": name})
        return out.get("voice_id", v["voice_id"])
    except RuntimeError as e:
        print(f"  could not add to library ({e}); using the shared voice id", file=sys.stderr)
        return v["voice_id"]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--cast", default=os.path.join(here, "cast.json"))
    ap.add_argument("--voices", default=os.path.join(here, "voices.json"))
    args = ap.parse_args()
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not key:
        sys.exit("Set ELEVENLABS_API_KEY first.")

    cast = {k: v for k, v in json.load(open(args.cast, encoding="utf-8")).items() if not k.startswith("_")}
    voices = json.load(open(args.voices, encoding="utf-8"))
    used = {v for k, v in voices.items() if not k.startswith("_")}
    rows = []
    for speaker, spec in cast.items():
        if voices.get(speaker):
            rows.append((speaker, "(kept)", voices[speaker], ""))
            continue
        pick = next(((q, v) for q, v in candidates(key, spec) if v["voice_id"] not in used), None)
        if pick is None:
            print(f"no voice found for {speaker}", file=sys.stderr)
            rows.append((speaker, "NOT FOUND", "", ""))
            continue
        q, v = pick
        voice_id = add_to_library(key, speaker, v)
        voices[speaker] = voice_id
        used.add(v["voice_id"])
        used.add(voice_id)
        how = ", ".join(f"{k}={val}" for k, val in q.items())
        rows.append((speaker, f"{v.get('name', '?')} ({how})", voice_id, v.get("preview_url", "")))
        print(f"{speaker}: {v.get('name')} [{voice_id}] via {how}")

    with open(args.voices, "w", encoding="utf-8") as f:
        json.dump(voices, f, ensure_ascii=False, indent=2)
        f.write("\n")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("## Voices\n\n| Speaker | Voice | id | Preview |\n|---|---|---|---|\n")
            for s, n, i, p in rows:
                f.write(f"| {s} | {n} | `{i}` | {f'[listen]({p})' if p else ''} |\n")
    if any(r[1] == "NOT FOUND" for r in rows):
        sys.exit(1)


if __name__ == "__main__":
    main()
