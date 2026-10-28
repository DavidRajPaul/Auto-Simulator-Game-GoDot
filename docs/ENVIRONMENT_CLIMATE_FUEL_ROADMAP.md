# Namma Auto — Chennai Environment, Climate, Water & Fuel Roadmap

**Principle:** Open-source/CC0 first. No paid assets or services without approval. Maintain Godot 4.4.1, Android performance, road geometry and existing gameplay.

## Value-ranked delivery

| Priority | Slice | Player value | Scope / acceptance |
|---|---|---|---|
| P0 | Fuel consumption and low-fuel warning | Critical gameplay loop | Shorter but fair starter-tank range, idle consumption, 20% warning, no burn during tutorial or engine stall, existing refuel/save behavior preserved |
| P0 | Fuel-station navigation and rescue | Prevents frustrating dead ends | Select nearest compatible station by *road route*, show distance on HUD/map; at zero fuel allow free manual push/limited emergency rescue or ₹150 tow; never softlock if wallet empty |
| P1 | Chennai cloud and sky moods | High visual impact | Clear coastal haze, hot noon, sea-breeze cumulus, grey monsoon cloud cover, sunset; mobile-compatible procedural sky or small CC0 HDRI; no Forward+-only volumetric fog |
| P1 | Realistic roadside vegetation | High visual impact | Neem, rain trees, coconut palms, shrubs, irregular trunk/canopy silhouettes; LOD and MultiMesh; preserve road sightlines and collision; zone-aware placement |
| P1 | Road/soil/building materials | High visual impact | 1K/2K CC0 PBR asphalt, dust, concrete, moss, shopfront decals; texture atlases and batching |
| P2 | Monsoon water appearance | High seasonal impact | Animated puddle ripples, roadside drainage, shallow flood gradients, tyre wake/splash, reflection approximation, wetness fade |
| P2 | Water/vehicle interaction | Medium-high gameplay impact | Depth-dependent drag and traction, splash strength from speed, existing stall and kick-start behavior preserved; avoid full fluid simulation |
| P2 | Chennai ambient life | Immersion | Crows, distant horns, wind in trees, monsoon thunder, waves near Marina; pooled/culled audio and objects |
| P3 | Seasonal presets | Variety | Hot dry, humid overcast, Northeast Monsoon, post-rain clear; deterministic weather transitions and configurable quality |
| P3 | Android performance polish | Release gate | ≤150 draw calls, traffic ≤18, app size target, real device visual checks |

## Fuel design

- **20% reserve**: one clear HUD warning; optional route to nearest LPG bunk.
- **10%**: persistent amber/red gauge; no intrusive full-screen dialog while driving.
- **0%**: engine loses power and player can choose a **tow to nearest compatible bunk** or a free safety rescue (small emergency reserve / push-to-safe-location). Never force ads or require money to continue.
- **Refuel**: stop at a real station and purchase affordable partial fill or full tank. Preserve existing garage and EV distinction.
- **Range balancing**: initial starter 8 units / 0.3 units/km ≈26.7 km moving, plus small idle burn. Tune using average ride length and player feedback. Do not present this as real-world mileage.
- **Current code note**: the tutorial intentionally disables fuel burn; existing 0.1 units/km gives an ~80 km starter tank, which may explain the apparently static gauge. Verify that the HUD's telemetry and persistence update as expected.

## Water implementation

Do not use CPU fluid solvers. Use a shallow surface shader with two scrolling normal/ripple patterns, edge foam near curbs, pooled particle bursts at wheels, and a simple water-depth lookup for tyre drag/stall. Compare dry/wet steering in headless physics tests and run Android GPU tests.

## Asset candidates and license gates

- **Poly Haven**: CC0 sky HDRIs, surface textures, 3D models — https://polyhaven.com/license
- **ambientCG**: CC0 road, soil, concrete and water textures — https://ambientcg.com
- **Quaternius**: CC0 vegetation packs, but many are stylized; inspect before choosing final Chennai tree meshes
- **Kenney**: CC0 props and placeholder assets — https://kenney.nl/assets
- **Own procedural meshes**: preferred for neem/rain tree silhouettes if CC0 models look too blocky

Before importing any third-party file: record original asset URL, creator, license and date in an asset manifest; check actual source license and polygon/texture budgets. No hotlinking assets at runtime.

## Delivery policy

One focused PR per slice, tests + Godot Android CI before merge. Phase 2 physics PR #14 is independent and must not be silently merged with these features. Real Android visual review is required for atmosphere and water.
