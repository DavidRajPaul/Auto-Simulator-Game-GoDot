# Chennai monsoon — water visuals and engine stalling (first slice)

## Implemented
- Existing flood discs now use an asset-free animated muddy-water shader with two interfering ripple waves.
- Player auto experiences bounded horizontal drag proportional to water depth and velocity; no expensive fluid simulation.
- Floodwater at the vehicle's existing `water_stall_depth_m` can stall a slow-moving auto, regardless of accelerator input.
- At 1.35× the configured stall depth, the auto stalls even when moving quickly.
- Kick-start is blocked while water remains at/above the stall depth, avoiding an unrealistic submerged restart.

## Existing mechanics retained
- Flood areas activate with rain and use the existing OSM-generated manifest.
- Existing kick-start rhythm and tow/recovery controls remain intact.
- Dry-road handling and fuel consumption are unchanged.

## Important limits / next slices
- These are **gameplay approximations**, not safe real-world wading-depth advice. Real floodwater can hide hazards and damage vehicles at much shallower depths.
- Current water zones report one depth on entry; overlapping zones need aggregation in a later slice.
- Existing flood discs have a flat height and abrupt edge; add depth-gradient shoreline fade and tyre splash particles next.
- The existing stall recovery needs a visible, clearly labelled tow/recover choice while still submerged. The engine cannot be kick-started until the auto is moved out of deep water.
- Review whether high-speed shallow-water hydroplaning should be implemented separately; avoid surprising uncontrollable handling.

## QA gates
1. Godot headless import and Android build CI must pass.
2. On Android test dry road, shallow puddle, stall-depth flooding and 1.35× deep flooding.
3. Verify engine restart is refused while submerged, and succeeds after leaving the zone.
4. Check frame time and draw calls on real devices, especially transparent puddles.
5. Validate floodwater does not permanently softlock a player; tow/recovery must be available.
