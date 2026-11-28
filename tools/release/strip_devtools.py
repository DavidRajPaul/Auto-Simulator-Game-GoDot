#!/usr/bin/env python3
"""Remove every trace of the dev tools (scripts/devtools, its test, the DEVTOOLS-HOOK lines).

Run it as the FIRST commit on every release branch (release/<major>.<minor>, e.g. release/1.1) and
in CI before any release-grade export. Idempotent. Rules: AGENTS.md "Rule 7".

    python3 tools/release/strip_devtools.py          # strip, then verify
    python3 tools/release/strip_devtools.py --dry    # list what would change
"""
import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_no_devtools as guard  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    changed: list[str] = []

    for rel in guard.DEV_PATHS:
        p = ROOT / rel
        if p.is_dir():
            changed.append(f"delete dir  {rel}")
            if not args.dry:
                shutil.rmtree(p)
    for pattern in guard.DEV_GLOBS:
        for p in sorted(ROOT.glob(pattern)):
            changed.append(f"delete file {p.relative_to(ROOT)}")
            if not args.dry:
                p.unlink()
    for p in guard.text_files():
        rel = p.relative_to(ROOT).as_posix()
        if rel.startswith(guard.DOC_ALLOW) or rel.startswith("scripts/devtools/"):
            continue  # docs and this tooling legitimately mention the marker
        text = p.read_text(encoding="utf-8", errors="ignore")
        if guard.HOOK_MARK not in text:
            continue
        kept = [ln for ln in text.splitlines(keepends=True) if guard.HOOK_MARK not in ln]
        changed.append(f"remove {len(text.splitlines()) - len(kept)} hook line(s) from {p.relative_to(ROOT)}")
        if not args.dry:
            p.write_text("".join(kept), encoding="utf-8")

    for c in changed:
        print(c)
    if not changed:
        print("Nothing to strip: dev tools are already absent.")
    if args.dry:
        return 0
    return guard.main(["--strict"])


if __name__ == "__main__":
    sys.exit(main())
