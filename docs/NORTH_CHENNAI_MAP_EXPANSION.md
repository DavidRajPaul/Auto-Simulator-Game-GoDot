# North Chennai — Central, Ripon and Egmore map extension

## Implementation

- `tools/osm/config.py` enlarges OSM BBOX to `(13.025, 80.225, 13.090, 80.290)`.
- **Do not change the old world origin** `(13.049, 80.259)`: that would move every old Chennai model and street.
- `.github/workflows/north-chennai-map-expansion.yml` is the *ordered*, full-data build. It refetches Overpass OSM roads/buildings and named POIs, rebuilds osm2streets left-hand lane polygons, generates the full road graph and streamed chunks, then rebuilds street signs, street dressing, building-name boards and imported city props.
- `TrafficDensity.gd` extends the current weekday/Saturday/Sunday and rush-hour model to Central, Ripon and Egmore. It is a synthetic simulation based on the existing citywide model, **not measured junction-level traffic**.
- `place_city_props.py` replaces the old `chennai_central` skyline illusion with the existing real `assets/models/city/chennai_central.glb` at the exact configured coordinates; generates a separate georeferenced Ripon placement; removes conflicting generated building meshes beneath their footprints.
- New roadside barricades use clearance-tested road-edge candidates near station precincts. These indicate in-game roadside traffic management only: **do not label them as real current police barricade placements or road closures.** 
- `validate_north_chennai.py` verifies both physical models are inside map bounds, the expanded road graph reaches their neighborhoods, and street/building-name outputs exist.

## Pending / asset note

- The repository already contains the Chennai Central GLB.
- The optimized Ripon Building GLB from the earlier model-processing work must be uploaded to `assets/models/city/ripon_building.glb`. Without that file, the data placement exists but the visual model is missing. The ZIP from that work contains `ripon_building.glb`.
- Expanding the OSM boundary requires fetching fresh external data and regenerating hundreds of chunks. The workflow runs on this branch when the config/workflow changes, or can be run via Actions -> North Chennai Map Expansion -> Run workflow. Android Build runs separately.
- Model alignment/size, final kerb clearance, FPS and memory must be validated on Android. The landmark clearances are authored rectangles, not a surveyed GIS parcel polygon.
- If Overpass refuses the enlarged query, split the extraction into smaller adjacent bounding boxes and deduplicate OSM element IDs before generating; **do not accept partial map data**.
- `tools/osm/build_world.py` already checks existing building footprints against carriageway/water raster and keeps procedural infill out of streets. Sign generation checks real lane/surface polygons. New city props clear their underlying footprints before building-name placement.
- Make sure the generated `data/world` and `data/osm` changes from the workflow are committed to this branch and have completed tests before merging.
- OSM data © OpenStreetMap contributors (ODbL), existing Chennai Central model's attribution is in the asset catalog.

## QA checklist

- [ ] Full workflow succeeds and its data commit lands in branch
- [ ] Verified coordinates and road graph around Ripon and Central
- [ ] Central model is reachable by car from Mylapore, via bridges / valid connections
- [ ] Ripon optimized GLB committed and visually aligned
- [ ] Street signs and real named public buildings show in expanded northern area
- [ ] No generated buildings overlap stations, roads, signals or sidewalks
- [ ] Peak hour vs dawn traffic densities differ around Central/Ripon
- [ ] Barricades do not block driveable lanes or pedestrian sidewalks
- [ ] Android CI, FPS, draw-call, app-size budget, and physical device playtest pass
