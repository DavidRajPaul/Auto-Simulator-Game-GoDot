#!/usr/bin/env python3
"""Guard for the dev tools (scripts/devtools). AGENTS.md "Rule 7: Dev tools are main-only".

    check_no_devtools.py            # main / feature branches: the dev tools may exist, but ONLY
                                    # reachable through the FrameGuard hook (so stripping is complete)
    check_no_devtools.py --strict   # release/* branches, v* tags, release exports: NOTHING may remain

Exit 0 = ok, 1 = violation. Pure standard library, runs in a second.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

HOOK_MARK = "DEVTOOLS-HOOK"
DEV_PATHS = ["scripts/devtools"]
DEV_GLOBS = ["tests/run_devtools_tests.*", "tests/shot_devtools*"]
# Text that must not appear in a release build's files.
NEEDLES = ["scripts/devtools", "DevTools", HOOK_MARK]
# Where the words may appear on ANY branch: docs, the rules, and this tooling.
DOC_ALLOW = ("AGENTS.md", "README.md", "docs/", "tools/release/", ".github/workflows/")
# The ONE code file allowed to carry the hook on main.
HOOK_FILES = ("autoloads/FrameGuard.gd",)
SKIP_DIRS = {".git", ".godot", "build", "android", "assets", "assets_src", "addons", "node_modules", "site", "data", "translations"}
TEXT_EXT = {".gd", ".tscn", ".tres", ".cfg", ".godot", ".py", ".yml", ".yaml", ".json", ".sh", ".md", ".csv", ".import", ".gdshader"}


def text_files():
    for p in ROOT.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in TEXT_EXT:
            continue
        rel = p.relative_to(ROOT)
        if rel.parts[0] in SKIP_DIRS and p.name != "project.godot":
            continue
        yield p


def main(argv: list[str]) -> int:
    strict = "--strict" in argv
    problems: list[str] = []

    for rel in DEV_PATHS:
        if (ROOT / rel).exists() and strict:
            problems.append(f"{rel}/ exists")
    for pattern in DEV_GLOBS:
        for p in ROOT.glob(pattern):
            if strict:
                problems.append(f"{p.relative_to(ROOT)} exists")

    for p in text_files():
        rel = p.relative_to(ROOT).as_posix()
        if rel.startswith(DOC_ALLOW):
            continue
        if rel.startswith(("scripts/devtools/", "tests/run_devtools_tests", "tests/shot_devtools")):
            continue  # the dev files themselves (their existence is judged above)
        text = p.read_text(encoding="utf-8", errors="ignore")
        hits = [n for n in NEEDLES if n in text]
        if not hits:
            continue
        if strict:
            problems.append(f"{rel} mentions {', '.join(hits)}")
        elif rel not in HOOK_FILES:
            problems.append(f"{rel} mentions {', '.join(hits)} (only {', '.join(HOOK_FILES)} may carry the hook)")
        else:
            # On main the hook file may mention it ONLY on lines carrying the marker.
            for n, line in enumerate(text.splitlines(), 1):
                if any(x in line for x in ("scripts/devtools", "DevTools")) and HOOK_MARK not in line:
                    problems.append(f"{rel}:{n} references the dev tools without the {HOOK_MARK} marker")

    mode = "strict (release)" if strict else "main"
    if problems:
        print(f"DEV TOOLS GUARD FAILED ({mode}):")
        for pr in problems:
            print("  -", pr)
        if strict:
            print("Run: python3 tools/release/strip_devtools.py   and commit the result.")
        return 1
    print(f"Dev tools guard ok ({mode}).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
