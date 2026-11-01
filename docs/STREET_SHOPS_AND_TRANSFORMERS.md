# Roadside shops and TNEB transformers (Nov 1, 2026)

Owner request: add street / roadside shops and transformers. Optimise the owner's transformer,
tea stall and fruit stall models, mount the transformer above the ground on poles with wires
like the real ones in Chennai, change the shop colours and put them in many places; recolour and
multiply the existing biryani stall too.

## Assets — `tools/assets/bake_street_shops.py`

| Output | Source | Triangles | Surfaces | Size |
|---|---|---:|---:|---|
| `assets/models/city/shops/tea_stall_{a,b,c,d}.glb` | owner's Tripo `street_food_stall_3d_model.glb` (60 MB, 1.92 M tris) | 9,000 | 2 (paint + sign) | 3.8 × 3.5 m, 3.5 m tall |
| `assets/models/city/shops/fruit_cart_{a,b,c,d}.glb` | owner's Tripo `street_fruit_stall_3d_model.glb` (62 MB, 1.90 M tris) | 5,000 | 2 | 1.75 × 1.4 m, 2.25 m tall |
| `assets/models/city/shops/biryani_stall_{a,b,c,d}.glb` | owner's stall, `assets_src/models/biryani_shop_src.glb` | 3,452 | 3 (paint + lungi + sign) | 3.7 × 4.3 m, 3 m tall |
| `assets/models/city/eb_transformer.glb` | owner's Tripo `power_transformer_3d_model.glb` (60 MB, 1.90 M tris) | 1,403 | 1 | 1.74 × 1.04 m, 1.71 m tall |

The Tripo sources stay out of git (`assets_src/incoming/models/city_new/`, gitignored); re-run
the baker after putting them there. Pipeline (AGENTS.md: never simplify a Tripo photo atlas):
crop (diorama ground slab and litter; the transformer's plinth, railing and loose cable loop) →
weld + quadric simplify → per-triangle colour from the nearest original texels, baked shadow
lifted → parts (roof, walls, canopy, cart body, sign board, …) → livery paint modulated by each
face's own light/dark detail → one vertex-coloured surface.

The AI signboards were garbled ("CHHCNNHAI", half-formed Tamil). Each shop now carries a clean
painted board on its own 512 px textured quad, drawn with the bundled Baloo Thambi 2 font
(Raqm shaping, so Tamil vowel signs are correct). Signs use generic shop words only — no real
business names: டீ கடை / டீ • காபி / தேநீர் கடை / டீ ஸ்டால்; பழக்கடை / பழங்கள் / ஜூஸ் • பழம் /
சீசன் பழம்; பிரியாணி with DUM / CHICKEN / MUTTON / KUSKA.

Liveries (two-tone enamel booths, blue tarpaulin or rusty tin roofs, painted push-carts):

| | a | b | c | d |
|---|---|---|---|---|
| Tea stall | teal / mustard, blue tarp | green / cream, rust tin | red / yellow, grey tin | purple / sky blue, orange tarp |
| Fruit cart | blue cart, orange stripes | green, yellow | red, blue | yellow, purple |
| Biryani stall | blue frame, blue tarp | green, orange tarp | maroon, tin | ochre, teal tarp |

Every shop faces **-Z** (the road side), origin at the footprint centre, standing on y = 0.
The biryani model used to face +X (its sign looked along the road); the bake turns it.

## Placement — `tools/osm/place_city_props.py` `add_street_shops()`

Run order after an OSM rebuild: `build_street_dressing.py` → `build_roadside_parking.py` →
`append_street_shops.py` (the OSM Import workflow does this; the *Place Roadside Street Shops*
workflow re-runs only the last step).

| Kind | Count | Same-kind spacing | Roads |
|---|---:|---:|---|
| `biryani_stall` (+2 customers, 2 parked scooters) | 18 | 260 m | primary, secondary, tertiary |
| `tea_stall` | 44 + the 6 hand-placed kadais with their regulars | 170 m | + residential |
| `fruit_cart` | 48 | 140 m | + living streets |

Seeded and deterministic. Each footprint (with its customer apron) must be clear of buildings,
the carriageway (front 0.9 m back from the road edge), water and beach, EB poles, trees,
transformer structures, parked vehicles and other props; ≥ 45 m between any two shops, ≥ 40 m
from landmarks and auto stands. Liveries rotate a → d. The hand-placed tea kadais that overlapped
the road at the new size moved to the nearest clear kerb (≤ 26 m).

In game (`WorldChunkStreamer._build_city_props`): no shadow pass, drawn within 100 m (carts
75 m), box colliders on the booth / cart / stall body, and the footprint goes into the chunk's
pedestrian walk mask so walkers go round the shops.

## Transformers — `tools/osm/build_street_dressing.py` `"xfmr"`

How they look in Chennai: TANGEDCO/TNPDCL 11 kV / 433 V distribution transformers (typically
100–250 kVA; a 250 kVA unit can't go on a single pole) stand on a **double-pole (DP) structure**
in the line of EB poles: two PSC poles ~2.6 m apart, a steel channel platform ~3 m up carrying
the tank, the 11 kV line on pin insulators on top, a gang-operated AB switch with its operating
rod down to a handle, lightning arresters, a DO fuse set, jumpers down to the HV bushings, an LT
distribution box low on a pole with cables up to the street lines and down into the ground, a
red danger board, barbed-wire anti-climbing collars and GI earth pipes in pits beside each foot.

Placement: one EB pole per ≥ 280 m (primary → residential roads) becomes a structure where the
kerb has room — 245 across the map. The pole is removed (its overhead wires now end on the
structure's top girder); the tank sits 0.55 m behind the pole line, away from the road, and the
whole structure is checked clear of every carriageway (including side-road mouths) and building.

Rendering: `WorldChunkStreamer._transformer()` builds the structure procedurally and merges the
baked tank (loaded once in `_ready`, glTF linear colours → sRGB paint) into the chunk's single
building mesh — no extra nodes or draw calls (AGENTS.md street-dressing rule).

## Checks

- `tests/test_city_density.py` `StreetShopsAndTransformersTests`: counts and liveries, every
  shop corner ≥ 0.5 m off the carriageway, tea_kadai gone, transformers spread ≥ 280 m apart,
  off the road, and never doubled with a plain pole.
- `tests/run_phase9_tests`: shops spawn, no shadows, ≤ 100 m range, every livery ≤ 10k
  triangles / ≤ 3 surfaces, walk-mask blocks, tank loaded (< 2k triangles), DP structure ~9 m
  with the tank on its platform.
- Perf probe: 137 / 150 draw calls, same as the main branch (shop meshes now stop at 75–100 m;
  the old kadai and biryani meshes were drawn out to 420 m).
- [ ] Device pass on the Mylapore benchmark route (OnePlus tab, Moto G40): shop signs readable,
  no kerb clipping, walkers round the stalls, frame time.
