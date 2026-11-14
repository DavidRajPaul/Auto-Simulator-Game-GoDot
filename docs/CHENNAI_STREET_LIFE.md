# Chennai vehicles and street life (Nov 13 2026)

Owner request: "all the two wheelers that are parked are the same ... look for free 3D models of
two-wheelers seen in Chennai ... free Chennai style car models ... no compromise on performance.
Also I need the Chennai to be more lively, just like the real Chennai."

## Where the models came from

Free model sites that allow downloads without an account (OpenGameArt, Kenney, Quaternius) carry
American / European vehicles: muscle cars, limousines, police interceptors, superbikes. The
CC0 rgsdev "Free Low Poly Vehicles Pack" (OpenGameArt) is a good pack but has no two-wheeler and
no small Indian car; the Kenney car kit was already rejected on the device (Nov 1). Sketchfab and
itch.io need a login, which this build environment can't do. So the Chennai set is built from
primitives by `tools/art/make_chennai_vehicles.py`, at real size, with no brand names or badges:

| File | What it is | Tris | Size (w × h × l) |
|---|---|---|---|
| `moped.glb` | Step-through moped, thin spoked wheels, load carrier | ~700 | 0.62 × 1.23 × 1.82 m |
| `commuter_bike.glb` | 100 cc commuter bike, saree guard, grab rail | ~800 | 0.68 × 1.25 × 1.92 m |
| `cruiser_bike.glb` | Classic 350 cc cruiser, round lamp, tan seats, long silencer | ~860 | 0.76 × 1.26 × 2.10 m |
| `bicycle.glb` | Roadster bicycle with carrier and chain guard (parked only) | ~590 | 0.55 × 1.04 × 1.80 m |
| `hatchback.glb` | Small hatchback, the commonest Chennai car | ~670 | 1.82 × 1.52 × 3.87 m |
| `tallboy.glb` | Tall-boy city hatchback with roof rails | ~690 | 1.64 × 1.71 × 3.62 m |
| `micro_van.glb` | One-box micro van | ~670 | 1.53 × 1.64 × 3.39 m |
| `mini_truck.glb` | Mini truck loaded with 20 L water cans | ~1400 | 1.64 × 1.85 × 3.82 m |

Each is one mesh, one material, no texture. Body panels carry vertex alpha 0;
`shaders/vehicle_paint.gdshader` repaints exactly those panels per instance (MultiMesh custom data
for parked rows, the `paint` instance uniform for traffic), so a kerb of mixed colours is still
one draw call per model. Palettes: `PaintSwap.TWO_WHEELER_PAINTS`, `PaintSwap.CAR_PAINTS`.
`tests/shot_chennai_vehicles.tscn` renders the line-up (`docs/images/chennai_vehicles_lineup.png`).

## Parked vehicles at the same draw budget

`RoadsideParking.files_for(kind, chunk)`:

* Two-wheelers: the Activa-style scooter (45 %) plus TWO of moped / commuter / cruiser / bicycle,
  picked per chunk, so the whole city shows all four while a chunk draws 3 batches (was 1).
* Cars: hatchback, tall-boy, the white sedan and one of micro van / mini truck / SUV per chunk:
  4 batches (was 6 paint files). Colour now comes from the per-instance paint.

Each spot keeps its model by a hash of its position. Perf probe on `main_chennai`: 147 / 150 draw
calls (was 145) and 602k primitives (was 624k: the new bikes are lighter than the scooter).

## Moving traffic

`TrafficVehicleAI.TWO_WHEELER_VARIANTS` adds the commuter bike, moped and cruiser (the bicycle
can't keep traffic speed). `CAR_VARIANTS` adds the four Chennai cars. Every two-wheeler and car
slot now loads all its variants once (hidden, no instancing while driving) and shows one per
respawn (`pick_vehicle_variant`), with a fresh paint; before, each slot kept one model for the
whole session, so only the first four car files were ever seen.

## Street life (`tools/osm/place_street_life.py`, run after `build_plots.py`)

All merged into the chunk's one building mesh (`WorldChunkStreamer._street_life`): no nodes, no
draw calls, no colliders.

* **Kolams** (~6,900): rice-flour patterns (dot grid, nested squares with petals, coloured-powder
  flower, star) on the ground outside house / old house / hamlet / tenement / flat gates, on the
  street side, never on a stall, pole, tree or parked vehicle.
* **Street dogs** (~585): lying or sitting beside 40 % of the kerb stalls, four coats.
* **Festival flags** (~840 wires): strings of small coloured flags under the EB wires within
  160 m of a temple or church.
* **Birds** (`BirdFlock.gd`, `shaders/bird_flock.gdshader`): 32 crows and pigeons wheeling over the
  roofs and 2 black kites soaring high, flown entirely on the GPU in ONE MultiMesh (+1 draw call),
  re-centred round the camera every 110 m, roosting at night.

Tests: `tests/run_street_life_tests` (models, paint, parking mix, traffic variants, street life
data and mesh, birds).
