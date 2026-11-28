#!/usr/bin/env python3
"""Fails if an exported APK / AAB still contains the dev tools (AGENTS.md "Rule 7").

    check_package_clean.py build/android/NammaAuto-release.apk [more files]

The game's files sit inside assets/*.pck; their paths are stored as plain text, so a byte search of
every entry (read in chunks) finds them.
"""
import sys
import zipfile

NEEDLES = (b"scripts/devtools", b"run_devtools_tests", b"DEVTOOLS-HOOK")
CHUNK = 1 << 22


def scan(path: str) -> list[str]:
    found: list[str] = []
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            tail = b""
            with z.open(info) as f:
                while True:
                    block = f.read(CHUNK)
                    if not block:
                        break
                    data = tail + block
                    for n in NEEDLES:
                        if n in data:
                            found.append(f"{info.filename}: {n.decode()}")
                    tail = data[-64:]
    return sorted(set(found))


def main(paths: list[str]) -> int:
    bad = 0
    for p in paths:
        hits = scan(p)
        if hits:
            bad = 1
            print(f"DEV TOOLS FOUND IN {p}:")
            for h in hits:
                print("  -", h)
        else:
            print(f"{p}: clean")
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
