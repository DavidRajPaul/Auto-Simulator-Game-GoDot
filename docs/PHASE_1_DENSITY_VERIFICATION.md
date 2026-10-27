# Phase 1 — Chennai building density verification

This PR changes **procedural infill probabilities**. It does not alter existing OSM building outlines, roads, or coastline.

| Area | Before | After |
| --- | ---: | ---: |
| Marina | 0.45 | 0.45 |
| Mylapore | 0.95 | 0.98 |
| Anna Salai | 0.85 | 0.95 |
| T. Nagar | 1.00 | 1.00 |
| Other areas | 0.60 | 0.72 |

## Regenerate committed map data (required before merge)

The shipped Android map is pre-generated under `data/world/`. Updating `config.py` alone **does not** update that map.

On GitHub (works from mobile browser):
1. Open [OSM Import workflow](https://github.com/DavidRajPaul/Auto-Simulator-Game-GoDot/actions/workflows/osm-import.yml).
2. Select **Run workflow**, choose `feature/phase-1-chennai-building-density`, and leave **refetch = false** to preserve the existing OSM snapshot.
3. Wait for success. The workflow rebuilds `data/world/` and commits the generated files to the selected branch.
4. Inspect the changed chunk count and run `python3 tools/osm/audit_city_density.py` against the regenerated branch.
5. Confirm that real OSM footprint count, road graph and landmark locations have not regressed.

## Quality gates

- Python: `python3 -m unittest discover -s tests -p 'test_city_density.py' -v`
- Godot: all existing phase suites on the Android Build PR check
- Performance: Chennai scene <=150 draw calls; <=18 active traffic; compare primitives, memory and APK size against Phase 0 baseline
- Visual: capture Marina, Mylapore, Anna Salai and T. Nagar from a real Android device, including night/rain
- Safety: no buildings across carriageways, sidewalks, water or landmark clear zones

## Scope and limitations

The procedural generator already uses a 2 m occupancy raster and polygon intersection checks to avoid occupied roads, walks, water and buildings. This phase intentionally leaves those guards unchanged. The new audit reports counts and malformed polygons; **it does not prove collision-free geometry**. Visual inspection and regeneration are required. Do not merge before all gates pass.
