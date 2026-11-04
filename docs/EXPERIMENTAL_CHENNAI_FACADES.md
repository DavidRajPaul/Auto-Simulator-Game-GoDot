# Experimental Chennai building facades

Status: planning and source audit only; no visual/runtime changes yet.
Branch: experimental/chennai-building-facades
Audited main: 3f0978edb1268bc07ff022e398bdf15fe6817687
Date: 2026-11-04

## Goal

Make ordinary street buildings recognisably Chennai at auto driving height, retaining low-poly geometry and Android performance. First benchmark: Kapaleeshwarar temple tank → Luz Corner → R.K. Mutt Road. Compare identical camera, clock, weather and graphics settings before extending citywide. Keep this experiment separate from main until device acceptance.

## Findings from the actual implementation

- tools/art/make_facade_atlas.py creates one 1024×512 atlas: 32 cells, each 128×128 pixels. Many shop categories use the same shelves with different signs.
- scripts/world/WorldChunkStreamer.gd already selects zone/kind-dependent skins, splits shop floors from upper floors, and builds sunshades, awnings, AC units, parapets, rooftop headrooms and tanks.
- facade_skin returns a building-wide skin; the wall loop applies shop ground floors to every edge. There is no frontage-specific selection here.
- shaders/building_facade.gdshader already supports tint masks, repeated bay/floor UVs and night emission. Preserve this batching architecture.
- tools/osm/build_world.py already honours tagged heights/levels and supplies zone-dependent fallback heights. fetch_osm.py is not the mesh extrusion implementation.
- config.py currently agrees with the attached BBOX (13.028, 80.230, 13.070, 80.288) and ORIGIN (13.049, 80.259). Keep them.
- The attachment's landmark coordinates differ from current config in multiple places. Neither list is a substitute for coordinate verification. Do not relocate landmarks as part of this work.
- Existing zones use centres/radii, not the attachment's overlapping rectangles. Do not replace them without explicit boundary precedence and regression checks.
- Several landmark, tank and roadside tasks already exist. Do not regenerate these assets just to execute the rough plan. Do not assume its chunk count or uniform-grey-building description describes current data.

## Visual direction

Low-poly volumes with detailed, restrained, photograph-informed surfaces. Building identity should come from frontage proportions, entrance placement, balconies, parapets and material wear, not just random colours.

| Building family | Distinguishing features |
| --- | --- |
| Mylapore older house | Narrow entrance, grilled windows, recessed veranda, restrained pastel plaster, occasional tiled roof |
| Mixed shop and residence | Distinct ground-floor trade, upper residence, concrete sunshade, irregular paint repairs |
| Small apartment | Stairwell strip, recessed balcony, parapet, terrace tank, compound gate |
| Commercial block | Wider showroom bays, coherent sign bands, concrete slabs; glazing only where appropriate |
| Service/workshop | Broad shutter, deep opening, worn lower plaster, simpler upper wall |
| Side/rear wall | Sparse openings, drainpipes, stains, patched plaster; no repeated shops |

Do not turn every Mylapore house into a heritage house or every Anna Salai parcel into a tall glass office.

## Implementation sequence

### 1. Facade art prototype
- Create original or appropriately licensed rectified surface references; avoid perspective, people, vehicles and hard baked sunlight.
- Make trade-specific shop imagery: tea counter, pharmacy, textile display, workshop shutter, house gate. Keep Tamil text separately typeset with the bundled font and reviewed for spelling.
- Prototype one shared 2048×1024 atlas with 256-pixel cells, retaining the existing UV2 cell contract. This is four times the base pixel count of the current atlas, not a free upgrade.
- Preserve alpha as paint mask, not transparency. Preserve the unpainted frame/sign/glass regions and matching emission coordinates.
- Add restrained plaster grain, monsoon streaks below sills, sun-faded paint, repaired patches and lower-wall dirt. Keep blank/plain cells usable by batched props.
- Keep a deterministic build recipe and asset provenance. AI imagery must be authored into a valid atlas, not plugged in as an arbitrary picture.
- Inspect mip levels for neighbour-cell bleeding. Use edge padding and validated UV sampling; a fixed percentage gutter alone is not proof against coarse-mip bleed.
- Compare at driving distance; do not accept an attractive standalone texture sheet as evidence of in-game quality.

### 2. Frontage selection and building identity
- Extend generated building metadata with street-facing edge indices, selected from nearby accessible roads and unobstructed frontage segments. Corner plots may have two frontages.
- Use deterministic building IDs/seeds. Backward-compatible runtime fallback for old chunks must remain.
- Preserve real footprint, tagged height, roadway/sidewalk/water exclusions and current collision boundaries.
- Add family selection based on building kind, district and footprint dimensions. Keep residential/commercial mix plausible; label inferred styles as artistic approximation.
- Apply shop bays only on selected frontages. Side/rear walls get plain/plaster/window variants.
- Fit bay widths to wall length; avoid stretched signs and fractional entrance fragments on narrow edges.
- Keep family geometry in the existing chunk mesh: selective balcony recess cues, short individual sunshades, parapet variations and drainpipes.
- Check every projection against street/footpath clearance. Never block a lane or create a drive-through entrance visually suggesting access where collision blocks it.

### 3. Device comparison, then district expansion
- Capture before/after stills and short driving footage at the same three route positions, including a corner building and narrow residential street.
- Review midday, evening, night and rain; ensure shops do not all glow like bright identical boxes.
- Profile on Moto G40 and OnePlus Pad. Record renderer, graphics preset, FPS/frame-time, draw calls, memory and sustained heat/stutter.
- Keep the repository's ≤150 draw-call target and moving-vehicle limits. No per-building material or scene node, no transparent layered facade quads, no realtime glass reflections.
- Measure atlas memory and APK delta. Retain lower-resolution assets if the larger atlas is not justified by device results.
- Extend accepted families to other districts only after Mylapore passes visual and performance review.

## Validation gates

Before a visual implementation is marked ready:
1. Atlas layout/tint/emission alignment and deterministic regeneration checks.
2. Frontage fixtures: corner, interior parcel, narrow edge, residential plot, legacy chunk.
3. Godot 4.5.1 import and all repository scene suites; perf probe.
4. Android Build CI green and experimental APK available.
5. Owner compares matching captures on Android; no main merge before acceptance.

No engine tests or APK are claimed for this planning-only commit.

## Phone-only workflow

Development and asset integration happen on this branch. Once runtime changes land, a PR to main triggers the existing Android Build workflow; manual workflow_dispatch can also select the branch. Download the successful APK artifact and test on Android. An APK cannot be installed on iPhone.

Xogot is an optional Godot-based iPhone/iPad editor, but compatibility with this project's Godot 4.5.1, Jolt and plugins would need validation. It is unnecessary for reviewing this experiment. Keep the game Android-only; do not introduce an iOS port or web-engine conversion.

## References

- User attachment: Chennai_Map_Visual_Upgrade_Plan.md (rough input; superseded by this audit for implementation order).
- https://www.projectmadras.com/ — visual direction reference. The official site describes Unreal Engine 5, Nanite, Lumen and scanning; do not assume its rendering pipeline is suitable for this Android game or copy its assets.
- https://godotengine.org/article/godot-showcase-xogot/
- https://docs.xogot.com/documentation/xogot/
