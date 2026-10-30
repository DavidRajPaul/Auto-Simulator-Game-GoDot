#!/usr/bin/env python3
"""Validate GLB container structure before Godot import.

This detects truncated/corrupted GLB binaries that exist on disk but cannot be
loaded. It does not attempt to repair missing binary data or verify textures.
"""
from __future__ import annotations
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def validate(path: Path) -> str | None:
    size = path.stat().st_size
    if size < 20:
        return f"too small ({size} bytes)"
    with path.open("rb") as stream:
        h = stream.read(12)
        magic, version, total = struct.unpack("<4sII", h)
        if magic != b"glTF" or version != 2:
            return f"invalid GLB magic/version: {magic!r}/{version}"
        if total != size:
            return f"TRUNCATED or invalid header: declares {total:,} bytes, repository file has {size:,}"
        offset = 12
        found_json = False
        while offset < size:
            chunk = stream.read(8)
            if len(chunk) != 8:
                return f"incomplete chunk header at byte {offset}"
            length, kind = struct.unpack("<I4s", chunk)
            offset += 8
            if length % 4:
                return f"misaligned chunk at byte {offset}"
            if length > size - offset:
                return f"TRUNCATED chunk at byte {offset}: needs {length:,}, only {size-offset:,} remain"
            if kind == b"JSON":
                found_json = True
            stream.seek(length, 1)
            offset += length
        if not found_json:
            return "missing JSON chunk"
        if offset != size:
            return f"GLB chunk boundary mismatch: {offset:,} != {size:,}"
    return None


def main() -> int:
    paths = sorted((ROOT / "assets").rglob("*.glb"))
    broken = []
    for p in paths:
        err = validate(p)
        if err:
            name = p.relative_to(ROOT)
            print(f"::error file={name}::Corrupt GLB: {err}")
            broken.append(name)
    print(f"Checked {len(paths)} GLB source models; {len(broken)} corrupt")
    if broken:
        print("Restore these models from intact original uploads; .glb.import sidecars cannot repair corrupt bytes")
    return 1 if broken else 0


if __name__ == "__main__":
    raise SystemExit(main())
