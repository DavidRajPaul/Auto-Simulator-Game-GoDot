#!/usr/bin/env python3
"""Stage user-provided CC BY pedestrian archives for the existing optimization pipeline.

Usage:
    python3 tools/assets/stage_new_people.py /path/to/downloads
    python3 tools/assets/process_people.py man_dhoti_new man_pattern_shirt woman_saree_new

The staging step does not ship raw models; it validates their archives and licences.
"""
from __future__ import annotations
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets_src" / "incoming" / "models" / "people"
PACKS = {
    "indian_man_in_dhoti.zip": "indian_man_in_dhoti",
    "indian_man_in_pattern_shirt.zip": "indian_man_in_pattern_shirt",
    "sareewoman.zip": "sareewoman",
    "sareelady.zip": "sareelady",
}

def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: stage_new_people.py <folder containing four zip files>")
        return 2
    downloads = Path(sys.argv[1])
    failed = []
    for name, folder in PACKS.items():
        source = downloads / name
        if not source.is_file():
            print(f"SKIP {name}: not provided")
            continue
        try:
            with zipfile.ZipFile(source) as archive:
                if archive.testzip() is not None:
                    raise ValueError("CRC error")
                names = archive.namelist()
                if not {"license.txt", "scene.gltf", "scene.bin"}.issubset(set(names)):
                    raise ValueError("missing glTF or licence")
                licence = archive.read("license.txt").decode("utf-8", errors="replace")
                if "CC-BY-4.0" not in licence:
                    raise ValueError("not a verified CC BY 4.0 model")
                target = DEST / folder
                target.mkdir(parents=True, exist_ok=True)
                for entry in archive.infolist():
                    if entry.is_dir():
                        continue
                    out = (target / entry.filename).resolve()
                    if not out.is_relative_to(target.resolve()):
                        raise ValueError("unsafe archive path")
                    out.parent.mkdir(parents=True, exist_ok=True)
                    out.write_bytes(archive.read(entry))
                (target / "license.txt").write_text(licence, encoding="utf-8")
                print(f"STAGED {name} -> {target}")
        except (zipfile.BadZipFile, OSError, ValueError, RuntimeError) as exc:
            print(f"ERROR {name}: {exc}")
            failed.append(name)
    if failed:
        print("Damaged archives must be re-exported or re-downloaded:", ", ".join(failed))
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
