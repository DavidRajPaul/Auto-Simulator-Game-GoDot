#!/usr/bin/env python3
"""Download raw OSM data for the MVP bounding box from Overpass (run in CI; needs internet).
Writes data/osm/chennai_mvp.osm.json.gz. Data © OpenStreetMap contributors, ODbL."""
import gzip, json, sys, time, urllib.parse, urllib.request
from pathlib import Path
from config import BBOX

MIRRORS = ["https://overpass-api.de/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter",
           "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]

def query() -> str:
    b = "%f,%f,%f,%f" % BBOX
    hw = "^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street)(_link)?$"
    return f"""[out:json][timeout:180];
(
  way["highway"~"{hw}"]({b});
  way["natural"="coastline"]({b});
  way["natural"="water"]({b});
  way["natural"="beach"]({b});
  way["leisure"="park"]({b});
);
out geom;"""

def main() -> int:
    out = Path(__file__).resolve().parents[2] / "data" / "osm" / "chennai_mvp.osm.json.gz"
    out.parent.mkdir(parents=True, exist_ok=True)
    body = urllib.parse.urlencode({"data": query()}).encode()
    for attempt in range(6):
        url = MIRRORS[attempt % len(MIRRORS)]
        try:
            print(f"POST {url} (attempt {attempt + 1})", flush=True)
            req = urllib.request.Request(url, data=body, headers={"User-Agent": "NammaAuto-OSM-Pipeline/1.0"})
            with urllib.request.urlopen(req, timeout=240) as r:
                raw = r.read()
            data = json.loads(raw)
            n = len(data.get("elements", []))
            if n < 100:
                raise RuntimeError(f"suspiciously few elements: {n}")
            with gzip.open(out, "wt", encoding="utf-8") as f:
                json.dump(data, f, separators=(",", ":"))
            print(f"OK: {n} elements → {out} ({out.stat().st_size // 1024} KB gz)")
            return 0
        except Exception as e:  # noqa: BLE001
            print(f"  failed: {e}", flush=True)
            time.sleep(15 * (attempt + 1))
    return 1

if __name__ == "__main__":
    sys.exit(main())
