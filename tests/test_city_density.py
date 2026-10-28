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
        self.assertLess(DEFAULT_ZONE_STYLE["bld_density"], 0.85)


if __name__ == "__main__":
    unittest.main()
