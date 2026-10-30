# Ripon Building + Tea Kadai: mobile asset integration

## Place the two optimized GLBs

This change is authored to load these exact two project paths:

- `assets/models/city/ripon_building.glb`
- `assets/models/city/tea_kadai.glb`

Both original Tripo exports are ~57–60 MB, ~1.8–1.9 million triangles; **never ship the originals**. The user-supplied models were downsampled via vertex clustering and the base-color texture reduced for mobile:

| Model | Original triangles | Prepared triangles | Prepared GLB |
| --- | ---: | ---: | ---: |
| Ripon Building | 1,791,171 | 31,580 | 1,437,684 bytes |
| Tea Kadai (street food stall) | 1,919,855 | 8,035 | 449,408 bytes |

The prepared files were delivered separately as `Namma_Auto_Ripon_Tea_Kadai_Optimized_Models.zip`. **Those binary GLBs are not committed by this PR**. Unzip, put each file at the path above, commit to this branch, and run the CI checks. Recheck geometry/texture rendering on Android after vertex-cluster optimization.

## Geographic accuracy

Ripon Building (Greater Chennai Corporation headquarters) source coordinate: **13.0817545 N, 80.2716236 E**, near Chennai Central.

The existing world projection from `tools/osm/build_world.py` uses origin `(13.049, 80.259)`, `110540 metres / degree latitude`, and `111320*cos(origin_lat)` metres per degree longitude. Consequently the georeferenced world position is **x=1368.97, z=-3620.68**. It is stored in `data/world/city_props.json`, not guessed from the player's location.

**Known coverage gap:** existing `data/world/manifest.json` has a northern z boundary near **-3006.57**; Ripon Building is outside the current road graph. The model is placed in its *correct geographic world position*, but players cannot drive to it until the northern map/roads are expanded. Do not relocate this heritage building nearer to the playable area to hide the map boundary problem.

Model dimensions are normalized in Tripo, so the authoring scale is 52.0; inspect the final orientation, facade direction, elevation and footprint in-game before merge.

## Roadside tea kiosks, parked two-wheelers and customers

Six tea-kadai hubs are anchored near existing parked two-wheeler clusters in Chennai's authored city props. Each hub loads the optimized kiosk if present; a cheap procedural fallback appears when the binary has not yet been uploaded. A hub also places **three low-poly standing patrons** and **two parked two-wheelers**, all distance-culled (~88 m). Nearby existing pedestrian walkers continue moving along pavement. The tea shops are added as map points.

The anchors currently use existing parking sites with 6 m / 4 m offsets, not surveyed tea-shop parcels. Test for road/sidewalk, building, and parked vehicle overlap at each hub before release; move individual prop coordinates as needed. Avoid adding large crowds with independent expensive skinning and shadows.

## QA checklist

- [ ] Commit the optimized GLB binaries to the paths above
- [ ] Verify 3D model texture orientation / world scale; Ripon clock tower and tea counter are recognizable
- [ ] Extend northern OSM data if you need Ripon Building accessible by driving
- [ ] Ensure each tea-stall hub fits a pavement/roadside space, with bikes at the kerb not across the traffic lane
- [ ] Make sure people do not clip into the kiosks
- [ ] Android headless Godot import + full CI; <=150 draw calls
- [ ] Device FPS, memory, Android APK/AAB size
- [ ] Add proper creator / generation attribution for the two uploaded models if required by the asset license
