"""Generated compound safety: no roads/paths/gates blocked, no off-map segments."""
import json
import math
import sys
import unittest
from pathlib import Path
from shapely.geometry import LineString, Point
from shapely.ops import unary_union
from shapely.prepared import prep

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/osm"))
from place_city_props import project
from config import BBOX


class CompoundSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        world = ROOT / "data/world"
        cls.data = json.loads((world / "compounds.json").read_text())
        cls.access = json.loads((ROOT / "data/osm/chennai_access.osm.json").read_text())["elements"]
        graph = json.loads((world / "road_graph.json").read_text())
        corridors = [LineString(e["pts"]).buffer(e["w"] * 0.5 + 1.7) for e in graph["edges"] if len(e["pts"]) > 1]
        for e in cls.access:
            tags = e.get("tags", {})
            coords = [project(p["lat"], p["lon"]) for p in e.get("geometry", [])]
            if tags.get("highway") and len(coords) > 1:
                corridors.append(LineString(coords).buffer(2.7 if tags["highway"] == "service" else 1.2))
            if e["type"] == "node" and tags.get("barrier") in ("gate", "lift_gate", "entrance", "swing_gate", "bollard"):
                corridors.append(Point(project(e["lat"], e["lon"])).buffer(2.2))
        cls.clear = prep(unary_union(corridors))

    def test_access_stays_open(self):
        for key, walls in self.data["chunks"].items():
            for wall in walls:
                shape = LineString([wall[:2], wall[2:4]]).buffer(wall[5] / 2)
                self.assertFalse(self.clear.intersects(shape), (key, wall))

    def test_provenance_and_chunk_bounds(self):
        ids = {e["id"] for e in self.access if e["type"] == "way"}
        sx, sz = project(BBOX[0], BBOX[1])
        nx, nz = project(BBOX[2], BBOX[3])
        self.assertGreater(self.data["counts"]["osm"], 0)
        self.assertGreater(self.data["counts"]["inferred"], 100)
        for key, walls in self.data["chunks"].items():
            x, z = map(int, key.split(","))
            for wall in walls:
                for px, pz in (wall[:2], wall[2:4]):
                    self.assertTrue(sx - .02 <= px <= nx + .02 and nz - .02 <= pz <= sz + .02)
                    self.assertTrue(x * 250 - .02 <= px <= (x + 1) * 250 + .02)
                    self.assertTrue(z * 250 - .02 <= pz <= (z + 1) * 250 + .02)
                if wall[6] == "osm":
                    self.assertIn(wall[7], ids)
                else:
                    self.assertEqual(wall[6], "inferred")
                    self.assertLess(math.dist(wall[:2], wall[2:4]), 5.03)


if __name__ == "__main__":
    unittest.main()
