#!/usr/bin/env python3
"""Download named places (shops, offices, banks, hospitals, temples, restaurants, schools…) for the
MVP bounding box from Overpass. Runs in CI (needs internet): .github/workflows/osm-pois.yml.

Separate from fetch_osm.py so the world (roads / buildings) is not rebuilt when only names change.
Ways and relations come back as their centre point. Output: data/osm/chennai_pois.json.gz
Data © OpenStreetMap contributors, ODbL.
"""
import gzip
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from config import BBOX

MIRRORS = ["https://overpass-api.de/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter",
           "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]
KEYS = ["shop", "amenity", "office", "tourism", "healthcare", "craft", "leisure", "historic", "building"]


def query() -> str:
    b = "%f,%f,%f,%f" % BBOX
    parts = "\n".join(f'  nwr["name"]["{k}"]({b});' for k in KEYS)
    return f"""[out:json][timeout:180];
(
{parts}
);
out center tags;"""


def main() -> int:
    out = Path(__file__).resolve().parents[2] / "data" / "osm" / "chennai_pois.json.gz"
    out.parent.mkdir(parents=True, exist_ok=True)
    body = urllib.parse.urlencode({"data": query()}).encode()
    for attempt in range(6):
        url = MIRRORS[attempt % len(MIRRORS)]
        try:
            print(f"POST {url} (attempt {attempt + 1})", flush=True)
            req = urllib.request.Request(url, data=body, headers={"User-Agent": "NammaAuto-OSM-Pipeline/1.0"})
            with urllib.request.urlopen(req, timeout=240) as r:
                data = json.loads(r.read())
            els = data.get("elements", [])
            if len(els) < 50:
                raise RuntimeError(f"suspiciously few elements: {len(els)}")
            with gzip.open(out, "wt", encoding="utf-8") as f:
                json.dump(data, f, separators=(",", ":"), ensure_ascii=False)
            kinds: dict = {}
            for e in els:
                t = e.get("tags", {})
                k = next((k for k in KEYS if k in t), "?")
                kinds[k] = kinds.get(k, 0) + 1
            print(f"OK: {len(els)} named places → {out} ({out.stat().st_size // 1024} KB gz) {kinds}")
            return 0
        except Exception as e:  # noqa: BLE001
            print(f"  failed: {e}", flush=True)
            time.sleep(15 * (attempt + 1))
    return 1


if __name__ == "__main__":
    sys.exit(main())
