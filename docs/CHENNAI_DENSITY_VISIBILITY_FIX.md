# Chennai density and visible trees — corrective slice

## Root causes and corrections
- Main currently includes 24,564 building footprints across 512 250-m chunks. Outside the named zones, procedural frontage density was only 0.72; interior lots often remain empty.
- Increase general urban frontage probability to 0.94, and Mylapore/Anna Salai to 1.0. Keep Marina at 0.45 to protect open beach character.
- Add a collision-checked second row of small courtyard buildings behind eligible roadside frontage. Raster rejects roads, sidewalks, water, existing buildings and protected landmarks.
- Tree data already exists in data/world/dress, but previously tree geometry was mixed into the facade-atlas building mesh. Now foliage uses a separate per-chunk vertex-colour material and a named RoadsideTrees mesh, even for chunks with no building geometry.

## Critical deployment requirement
The density generator change **does not change existing chunk JSON until data is regenerated and committed**. Run OSM Import / rebuild world, then regenerate dressing and audit; only test the APK built from a commit containing regenerated data. Do not claim the map is denser on device before this.

## Manual visual QA
1. At Mylapore Tank Auto Stand, drive along residential streets and compare building frontage and side streets to the prior APK.
2. Repeat in T. Nagar and Anna Salai; check missing plots, buildings floating or intruding into roads, and buildings overlapping landmarks.
3. Verify Marina Beach and parks remain open; no new buildings in water.
4. Inspect RoadsideTrees under both sun and rain; green foliage and bark should be visibly distinct from facade textures, with no white window patterns.
5. Check trees at the boundary of adjacent chunks, and after driving away and returning.
6. Profile FPS and memory on lower-end Android, especially dense street views. This fix adds one draw call per tree-containing chunk.
7. Record screenshots from identical camera positions, build SHAs and device FPS for before/after comparison.
