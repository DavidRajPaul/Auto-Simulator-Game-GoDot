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
| `moped.glb` | Step-through moped, thin spoked wheels, load carrier | ~1,750 | 0.61 × 1.25 × 1.82 m |
| `commuter_bike.glb` | 100 cc commuter bike, alloy wheels, saree guard, grab rail | ~2,240 | 0.67 × 1.28 × 1.94 m |
| `cruiser_bike.glb` | Classic 350 cc cruiser, round lamp, tan seats, long silencer | ~2,350 | 0.75 × 1.30 × 2.12 m |
| `bicycle.glb` | Roadster bicycle with carrier and chain guard (parked only) | ~1,170 | 0.55 × 1.05 × 1.80 m |
| `hatchback.glb` | Small hatchback, the commonest Chennai car | ~2,520 | 1.70 (2.02 with mirrors) × 1.54 × 3.87 m |
| `tallboy.glb` | Tall-boy city hatchback with roof rails | ~2,560 | 1.52 × 1.68 × 3.62 m |
| `micro_van.glb` | One-box micro van | ~2,530 | 1.41 × 1.65 × 3.39 m |
| `mini_truck.glb` | Mini truck loaded with 20 L water cans | ~4,190 | 1.50 × 1.85 × 3.82 m |

Nov 14 device feedback on the first set ("looking very low poly"): bodies are now smooth-shaded
lofts. A car is ~30 cross-sections of 10 points swept nose to tail (curved roof and windscreen,
tumblehome, rounded corners, glass and pillars by region), with turned tyres, alloy wheels, wheel
wells, door seams, handles, mirrors, lamps, grille and plates. Two-wheelers have turned tyres,
rounded tanks, seats, cowls, engines with fins, forks, shocks and indicators. They are still
built shapes, not scans: for photo-real vehicles the owner can generate models (Tripo, like the
Bolero and the buses) and they bake through the same one-mesh pipeline.

Each is one mesh, one material, no texture. Body panels carry vertex alpha 0, glass 0.5;
`shaders/vehicle_paint.gdshader` repaints exactly those panels per instance (MultiMesh custom data
for parked rows, the `paint` instance uniform for traffic), so a kerb of mixed colours is still
one draw call per model. Palettes: `PaintSwap.TWO_WHEELER_PAINTS`, `PaintSwap.CAR_PAINTS`.
`tests/shot_chennai_vehicles.tscn` renders the line-up (`docs/images/chennai_vehicles_cars.png`,
`chennai_vehicles_bikes.png`).

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

## The living city (Nov 14)

Owner: "collision physics for moving vehicles too", "fallen people go below the road", "some
roads clean, some dusty or full of potholes", "every open shop must have a shopkeeper and a few
customers", "ladies drawing kolams in the early morning", "rain must make people run for
shelter, some with umbrellas in rain and summer".

* **Moving traffic physics** (`KnockedVehicles.gd`): traffic still drives as 18 pooled kinematic
  bodies. When the auto hits a two-wheeler (≥ 2.2 m/s closing), an NPC auto (≥ 3.8) or a car
  (≥ 4.5), the vehicle is handed to one of 3 pre-built `RigidBody3D`s: same place, size and real
  mass, its own speed plus the momentum of the hit. A scooter goes over and slides with its
  rider; a car is shoved and spun; both can be hit again. The traffic slot stays out of the pool
  until the body is handed back (after 9 s, once off screen or 75 m away). Buses, lorries,
  service vehicles and cattle keep the stop-honk-recoil. Nothing is instanced while driving.
* **Fallen bodies**: the fall clips put hands and forearms at or below the node, and a lying body
  often straddles bare ground (-0.15) and road (+0.06). A body that is down now rests on the
  highest ground under its whole length plus a small lift (`PedestrianManager.DOWN_LIFT_M`).
* **Road condition** (`WorldChunkStreamer.road_condition`, `street_surface.gdshader`): a slow
  world noise in UV.y makes ~39 % of road length clean, ~33 % dusty (sand drifted over the
  asphalt) and ~28 % broken (potholes with crumbled rims, puddles in rain). Potholes are a small
  procedural noise evaluated only on broken stretches: still two texture lookups per pixel.
* **Shop people** (`ShopPeople.gd`, `tools/assets/bake_shop_people.py`): dress `"shop_people"`
  holds ~63,600 spots (a shopkeeper at each shop bay and kerb stall, one or two customers facing
  the shop). The eight standing figures share one 1024 × 512 atlas, so the nearest 40 open spots
  within 62 m merge into ONE mesh (one draw call) at each figure's ~900-triangle import LOD.
  Shops 08:00–22:00, stalls 06:00–21:00; nobody stands on a carriageway or inside a wall.
* **Kolam drawing** (05:25–07:35, dry weather): up to 4 pooled women stand at kolam spots bent
  over the pattern, right hand tracing it (`PoseModifier.KOLAM`, a procedural pose on the idle
  clip: no kolam mocap exists in the project). Temple gates always get a kolam.
* **Rain**: on `weather_changed`, 40 % of walkers open an umbrella and walk on, the rest run to
  the nearest shop front within 45 m and wait there (or just run if none is near). Umbrellas are
  ONE MultiMesh (one draw call, only while any is open); 20 % of women also carry one in the
  11:00–15:30 sun. After the rain everyone walks on.

Perf probe on `main_chennai`: 140 / 150 draw calls, 660k primitives.

Tests: `tests/run_street_life_tests` (models, paint, parking mix, traffic variants, street life
data and mesh, birds).
