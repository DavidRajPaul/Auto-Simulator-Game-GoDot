# Chennai roadside biryani stalls — asset and placement

## Uploaded assets

1. `chennai_biryani_shop_lowpoly.txt` is **actually a valid binary glTF 2.0 file**, not plain text. It includes stall frame, biryani pot, signboard, shop owner, cooking and dining props. The source is 3,452 triangles and is approximately 472 KB.
2. `street food stall 3d model 2.glb` is approximately **1,867,715 triangles** and ~60 MB, too expensive for a mobile roadside prop; it must not ship at original resolution.

The first asset has been converted to an optimized GLB combining solid materials into one vertex-colored mesh while preserving two textured meshes (sign face and owner's lungi). The result has **3 meshes / ~3,452 triangles / ~274 KB**.

The prepared asset is supplied separately in `Namma_Auto_Biryani_Stall_Asset.zip`. **GitHub's connected text-file actions cannot transfer this binary directly**. Before merging, extract and commit:

`assets/models/city/biryani_shop.glb`

The game loader deliberately falls back to a lightweight procedural roadside stall while the model is absent. The fallback has no specific biryani art; it is not a substitute for the supplied GLB.

## Placement and gameplay

- Regenerated with `tools/osm/append_biryani_stalls.py`, or as part of `place_city_props.py` after a full OSM rebuild.
- Up to two stalls per zone across T. Nagar, Mylapore, Anna Salai, Egmore and the Central precinct. The actual count depends on OSM building and road clearance.
- Candidate road segments are required to be at least 20 m long. Placement tests the complete **9 m × 7 m** stall/crowd/bike envelope against buildings, carriageway, beach and water. No raw coordinates are invented.
- At least 140 m spacing between stalls within each zone, 15 m from existing world props. Does not place shops inside road intersections, and does not bulldoze existing real buildings.
- Shop owner is part of the low-poly GLB. Two additional visible static customers and up to two parked scooters use existing shared assets, with 85 m distance culling and no shadows.
- Other characters continue walking on pavements from the existing 30-character pedestrian pool.
- No OSM real-world businesses are labeled or misrepresented.

## Checks

- [ ] Automatic placement workflow succeeds and commits city_props.json
- [ ] Optimized GLB uploaded to assets/models/city/biryani_shop.glb
- [ ] Verify stall sign faces pedestrian/roadside direction; no clipping into road/buildings
- [ ] Verify 2D full map, draw call count, Godot import and Android APK/AAB
- [ ] Test that crowds and parked scooters don't obstruct NPC walking space
