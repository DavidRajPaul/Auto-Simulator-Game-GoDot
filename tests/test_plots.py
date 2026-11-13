#!/usr/bin/env python3
"""Compound walls and gates must never stand on a road or footpath, or inside a building."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
WORLD = ROOT / "data" / "world"
CELL = 0.5
SIZE = 250.0


def raster(chunk: dict, ox: float, oz: float) -> tuple:
    n = int(SIZE / CELL)
    road, bld = Image.new("L", (n, n), 0), Image.new("L", (n, n), 0)
    rd, bd = ImageDraw.Draw(road), ImageDraw.Draw(bld)
    for kind, part in chunk.get("surf", {}).items():
        if kind.removesuffix("_up") not in ("road", "junction"):
            continue
        v, tri = part["v"], part["i"]
        for t in range(0, len(tri), 3):
            rd.polygon([((v[2 * tri[t + k]] - ox) / CELL, (v[2 * tri[t + k] + 1] - oz) / CELL) for k in range(3)], fill=1)
    for b in chunk.get("blds", []):
        p = b["p"]
        bd.polygon([((p[i] - ox) / CELL, (p[i + 1] - oz) / CELL) for i in range(0, len(p), 2)], fill=1)
    return road.load(), bld.load(), n


class PlotTests(unittest.TestCase):
    def test_walls_keep_off_roads_and_buildings(self) -> None:
        files = sorted((WORLD / "plots").glob("c_*.json"))
        self.assertGreater(len(files), 400)
        on_road = in_building = samples = 0
        for f in files[::6]:
            i, j = (int(v) for v in f.stem.split("_")[1:])
            chunk_file = WORLD / "chunks" / f.name
            if not chunk_file.exists():
                continue
            road, bld, n = raster(json.loads(chunk_file.read_text()), i * SIZE, j * SIZE)
            d = json.loads(f.read_text())
            for w in d.get("walls", []) + d.get("gates", []):
                for t in (0.1, 0.5, 0.9):
                    x = (w[0] + (w[2] - w[0]) * t - i * SIZE) / CELL
                    z = (w[1] + (w[3] - w[1]) * t - j * SIZE) / CELL
                    if not (0 <= x < n and 0 <= z < n):
                        continue
                    samples += 1
                    on_road += road[int(x), int(z)]
                    in_building += bld[int(x), int(z)]
        self.assertGreater(samples, 5000)
        self.assertEqual(on_road, 0, "a compound wall or gate stands on a carriageway")
        self.assertLess(in_building / samples, 0.01, "walls run through buildings")

    def test_gates_have_walls(self) -> None:
        walls = gates = 0
        for f in (WORLD / "plots").glob("c_*.json"):
            d = json.loads(f.read_text())
            walls += len(d.get("walls", []))
            gates += len(d.get("gates", []))
        self.assertGreater(gates, 6000)
        self.assertGreater(walls, gates * 2)


if __name__ == "__main__":
    unittest.main()
