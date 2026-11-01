"""Phase 1: regression checks for zone-specific procedural building density.

Run from repository root: python -m unittest discover -s tests -p 'test_city_density.py'
No Godot or third-party Python packages are required.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "osm"))

from config import DEFAULT_ZONE_STYLE, ZONES  # noqa: E402


class CityDensityTests(unittest.TestCase):
    def test_all_density_values_are_probabilities(self) -> None:
        for name, style in [("default", DEFAULT_ZONE_STYLE), *ZONES.items()]:
            with self.subTest(zone=name):
                self.assertGreater(float(style["bld_density"]), 0.0)
                self.assertLessEqual(float(style["bld_density"]), 1.0)
                lo, hi = style["bld_height"]
                self.assertGreater(lo, 0.0)
                self.assertGreaterEqual(hi, lo)

    def test_dense_commercial_corridors(self) -> None:
        self.assertGreaterEqual(ZONES["t_nagar"]["bld_density"], 0.95)
        self.assertGreaterEqual(ZONES["anna_salai"]["bld_density"], 0.90)
        self.assertGreaterEqual(ZONES["mylapore"]["bld_density"], 0.95)

    def test_marina_keeps_open_coastal_character(self) -> None:
        self.assertLess(ZONES["marina"]["bld_density"], DEFAULT_ZONE_STYLE["bld_density"])
        self.assertLess(ZONES["marina"]["bld_density"], ZONES["mylapore"]["bld_density"])

    def test_default_infill_not_unbounded(self) -> None:
        self.assertGreaterEqual(DEFAULT_ZONE_STYLE["bld_density"], 0.65)
        self.assertLessEqual(DEFAULT_ZONE_STYLE["bld_density"], 0.96)




class WaterDataTests(unittest.TestCase):
    """data/world/water.json (tools/osm/build_water.py): Oct 31 device test, an invisible wall
    across the Venkatesa Agraharam Road canal bridge."""

    @classmethod
    def setUpClass(cls) -> None:
        import json
        world = Path(__file__).resolve().parents[1] / "data" / "world"
        cls.water = json.loads((world / "water.json").read_text())
        cls.graph = json.loads((world / "road_graph.json").read_text())

    @staticmethod
    def _seg_dist(p, a, b) -> float:
        ax, az = a
        bx, bz = b
        px, pz = p
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz
        t = 0.0 if L2 == 0 else ((px - ax) * dx + (pz - az) * dz) / L2
        if t < 0.0 or t > 1.0:
            return float("inf")  # beyond a segment end: a wall at a road's dead end is fine
        cx, cz = ax + t * dx, az + t * dz
        return ((px - cx) ** 2 + (pz - cz) ** 2) ** 0.5

    def test_no_bank_across_a_road(self) -> None:
        """No bank wall comes within a carriageway half-width of any road centre-line."""
        bad = []
        for b in self.water["banks"]:
            mid = ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)
            for e in self.graph["edges"]:
                pts = e["pts"]
                if min(abs(mid[0] - p[0]) + abs(mid[1] - p[1]) for p in pts) > 60:
                    continue
                for a, c in zip(pts, pts[1:]):
                    for q in ((b[0], b[1]), mid, (b[2], b[3])):
                        if self._seg_dist(q, a, c) < e["w"] * 0.5 - 0.05:
                            bad.append((e.get("n", ""), q))
        self.assertEqual(bad, [], f"bank walls on carriageways: {bad[:5]}")

    def test_bridges_have_parapets(self) -> None:
        self.assertGreaterEqual(len(self.water["rails"]), 2)
        self.assertGreater(len(self.water["banks"]), 100)
        self.assertGreater(len(self.water["surface"]["i"]) // 3, 5000)


if __name__ == "__main__":
    unittest.main()
