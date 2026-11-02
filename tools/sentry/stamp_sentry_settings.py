#!/usr/bin/env python3
"""Stamp Sentry settings into project.godot right before an export (CI only, never committed).

    SENTRY_DSN=... python3 tools/sentry/stamp_sentry_settings.py \
        --release namma-auto@0.5.0+123 --dist 123 --environment ci-debug

The DSN comes from the environment (GitHub secret GLITCHTIP_DSN, passed as SENTRY_DSN), so it never lands in git.
GlitchTip speaks the Sentry protocol, so the Sentry SDK addon works unchanged.
With no DSN the build still works; it just sends nothing (the summary says so).
"""
import argparse
import os
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2] / "project.godot"


def set_key(text: str, section: str, key: str, value: str) -> str:
    line = f'{key}="{value}"' if not value.lower() in ("true", "false") else f"{key}={value.lower()}"
    sec = re.search(rf"^\[{re.escape(section)}\]\s*$", text, re.M)
    if sec is None:
        return text.rstrip("\n") + f"\n\n[{section}]\n\n{line}\n"
    start = sec.end()
    nxt = re.search(r"^\[[^\]]+\]\s*$", text[start:], re.M)
    end = start + nxt.start() if nxt else len(text)
    body = text[start:end]
    pat = re.compile(rf"^{re.escape(key)}=.*$", re.M)
    body = pat.sub(line, body) if pat.search(body) else body.rstrip("\n") + f"\n{line}\n\n"
    return text[:start] + body + text[end:]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--release", required=True)
    ap.add_argument("--dist", default="")
    ap.add_argument("--environment", required=True)
    ap.add_argument("--smoke-test", default="false")
    a = ap.parse_args()
    dsn = os.environ.get("SENTRY_DSN", "").strip()
    if dsn and not re.match(r"^https://[^@\s]+@[^/\s]+/\d+$", dsn):
        print("::error::SENTRY_DSN does not look like https://<key>@<host>/<project_id>")
        return 1
    text = PROJECT.read_text(encoding="utf-8")
    text = set_key(text, "sentry", "options/dsn", dsn)
    text = set_key(text, "sentry", "options/release", a.release)
    text = set_key(text, "sentry", "options/dist", a.dist)
    text = set_key(text, "sentry", "options/environment", a.environment)
    text = set_key(text, "namma_auto", "crash_reporting/send_smoke_test_on_boot", a.smoke_test)
    PROJECT.write_text(text, encoding="utf-8")
    state = "ENABLED" if dsn else "DISABLED (no GLITCHTIP_DSN secret yet)"
    print(f"Sentry crash reporting {state}: release={a.release} dist={a.dist} env={a.environment} smoke_test={a.smoke_test}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"**Sentry:** {state} · release `{a.release}` · env `{a.environment}`\n\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
