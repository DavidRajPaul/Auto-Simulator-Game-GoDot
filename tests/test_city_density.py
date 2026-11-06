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

    def test_empty_lots_filled_and_stalls_placed(self) -> None:
        import glob
        import json
        buildings = stalls = 0
        kinds = set()
        for path in glob.glob(str(ROOT / "data/world/chunks/c_*.json")):
            buildings += len(json.load(open(path)).get("blds", []))
        for path in glob.glob(str(ROOT / "data/world/dress/c_*.json")):
            rows = json.load(open(path)).get("stalls", [])
            stalls += len(rows)
            kinds.update(int(r[3]) for r in rows)
        self.assertGreaterEqual(buildings, 45000)
        self.assertGreaterEqual(stalls, 1200)
        self.assertEqual(kinds, set(range(7)))

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


class StreetShopsAndTransformersTests(unittest.TestCase):
    """Roadside shops (tools/osm/place_city_props.py add_street_shops) and TNEB transformer
    structures (tools/osm/build_street_dressing.py "xfmr"): Nov 1 request, shops at many places
    and transformers mounted above the ground like the real ones."""

    @classmethod
    def setUpClass(cls) -> None:
        import json
        import math
        world = ROOT / "data" / "world"
        cls.props = json.loads((world / "city_props.json").read_text())["props"]
        graph = json.loads((world / "road_graph.json").read_text())
        cls.segs = []
        for e in graph["edges"]:
            pts = e["pts"]
            for i in range(1, len(pts)):
                cls.segs.append((pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], float(e["w"]) * 0.5))
        cls.xfmr = []
        cls.poles = []
        for f in sorted((world / "dress").glob("c_*.json")):
            d = json.loads(f.read_text())
            cls.xfmr += d.get("xfmr", [])
            cls.poles += d.get("poles", [])
        cls.math = math

    def _road_gap(self, x: float, z: float) -> float:
        """Distance from (x, z) to the nearest carriageway edge (negative = on the road)."""
        best = 1e9
        for ax, az, bx, bz, hw in self.segs:
            if min(ax, bx) - 30 > x or max(ax, bx) + 30 < x or min(az, bz) - 30 > z or max(az, bz) + 30 < z:
                continue
            dx, dz = bx - ax, bz - az
            L = dx * dx + dz * dz
            t = 0.0 if L == 0 else max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / L))
            best = min(best, self.math.hypot(x - (ax + dx * t), z - (az + dz * t)) - hw)
        return best

    def test_many_shops_of_every_kind_and_colour(self) -> None:
        for kind, least in (("tea_stall", 30), ("fruit_cart", 30), ("biryani_stall", 10)):
            with self.subTest(kind=kind):
                shops = [p for p in self.props if p["model"] == kind]
                self.assertGreaterEqual(len(shops), least)
                variants = {p["asset"] for p in shops}
                self.assertGreaterEqual(len(variants), 4, "every livery is used")
                for a in variants:
                    self.assertTrue((ROOT / a.replace("res://", "")).exists(), a)

    def test_shops_stand_off_the_carriageway(self) -> None:
        m = self.math
        for p in self.props:
            if p["model"] not in ("tea_stall", "fruit_cart", "biryani_stall") or "block" not in p:
                continue
            hx, hz = p["block"]
            yaw = float(p["yaw"])
            for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                cx = p["x"] + sx * hx * m.cos(yaw) + sz * hz * m.sin(yaw)
                cz = p["z"] - sx * hx * m.sin(yaw) + sz * hz * m.cos(yaw)
                self.assertGreater(self._road_gap(cx, cz), 0.5, f"{p['model']} at {p['x']},{p['z']}")

    def test_no_old_tea_kadai_model(self) -> None:
        self.assertFalse(any(p["model"] == "tea_kadai" for p in self.props))
        self.assertFalse((ROOT / "assets" / "models" / "city" / "tea_kadai.glb").exists())

    def test_transformers_are_spread_and_off_the_road(self) -> None:
        m = self.math
        self.assertGreaterEqual(len(self.xfmr), 100)
        for x, z, yaw, ox, oz in self.xfmr[::5]:
            self.assertAlmostEqual(m.hypot(ox, oz), 1.0, places=2)
            # The tank (1.04 m deep, centred 0.55 m behind the pole line) never hangs over traffic.
            self.assertGreater(self._road_gap(x + ox * 0.03, z + oz * 0.03), 0.0, f"xfmr at {x},{z}")
        pts = [(q[0], q[1]) for q in self.xfmr]
        for i, (x, z) in enumerate(pts[:60]):
            near = min(m.hypot(x - a, z - b) for j, (a, b) in enumerate(pts) if j != i)
            self.assertGreaterEqual(near, 279.0)
        # The structure replaces its pole: no plain pole left at the same spot.
        pole_at = {(round(p[0], 1), round(p[1], 1)) for p in self.poles}
        self.assertFalse(any((round(x, 1), round(z, 1)) in pole_at for x, z, *_ in self.xfmr))
