# Chennai cloud rendering — first environment slice

This PR adds procedural sky-cover noise to the existing Godot ProceduralSkyMaterial, using a deterministic 256×256 seamless FastNoiseLite texture generated in engine. It is asset-free and does not require paid or restricted third-party content.

## Chennai moods
- **Dry daytime:** pale, relatively sparse coastal cumulus, warm haze already handled by the atmosphere.
- **Monsoon:** overcast slate-grey clouds, with existing rain fog and wet-road effects.
- **Night:** subtle dark cloud cover; existing street lighting stays readable.
- **Transitions:** follow the existing weather blend and shift clock.

## Implementation constraints
- No volumetric fog/cloud ray marching, particle clouds, external textures, new meshes or per-frame texture regeneration.
- Uses a single 256×256 noise texture; sky parameters update on the existing 0.25-second cadence.
- Sky resources are duplicated per scene to avoid leaking parameter changes to shared resources.

## Verification
1. CI: Godot headless import and existing tests; Android APK/AAB export.
2. Android visual checks at Marina/Mylapore/Anna Salai at noon, dusk, night and monsoon.
3. Compare draw calls and frame times to main; retain the <=150 draw-call budget.
4. If cloud edges look noisy or repetitive, tune noise frequency and cover modulation; do not increase texture size without measurements.

## Next environment slices
1. Replace existing generated tree silhouettes with a better irregular branch/frond mesh or verified CC0 models, batched by species and LOD.
2. Improve monsoon puddle ripples and tyre splashes without fluid simulation.
3. Road texture and zone-specific clutter, using documented CC0 licenses.

The existing procedural street dressing already generates rain trees, neem, Ashoka and palms; it is not entirely box-based. Improvements should refine those shapes rather than introduce excessive individual draw calls.
