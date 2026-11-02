# P0 semi-realism APK test

This branch changes driving, collision consequences, traffic and street enclosure. Weather,
wind, birds and sunset art are P1 and are not part of this change.

## Implemented

- Three-wheel raycast vehicle retained. Combined lateral/longitudinal tyre forces are capped
  by suspension load and friction, so full braking/acceleration cannot ignore cornering grip.
- Normal closing-speed squared drives damage, with a parking-contact threshold, 0.65 s impact
  debounce and a per-hit cap. The existing physics contact solver handles the actual impact.
  The condition bar now falls faster in serious crashes than light knocks.
- Front/rear/left/right wear persists per vehicle. Front hits affect steering and lamps; rear
  hits affect power; side hits affect suspension. Tyre wear reduces grip. The imported auto
  receives shader dents and paint scratches on damaged panels, and severe rear wear emits smoke.
  Garage repairs clear wear proportionally to payment; old saves have no new component faults.
- NPCs remain pooled, graph-driven AnimatableBodies. Mass-sensitive recoil is constrained to
  their road path and swept against primitive collisions, followed by braking/recovery. They
  are not free-body rigid vehicles or soft-body wrecks. Pooled teleports disable collision.
  Pedestrians dodge, respond to close moving-auto contact, recover, and check the walk mask.
- One existing service slot can dispatch an ambulance after a 100 s cooldown, on its next safe
  spawn. It has a positional synthesized siren and flashing beacon. Traffic ahead slows and
  shifts left when a lane is clear. Ambulances still brake for obstacles and red signals.
  Dispatch is suppressed in the tutorial; no extra moving vehicle slots are created.
- 455 generated roadside businesses (55 biryani, 180 tea, 220 fruit) plus existing tea clusters.
  Market districts get placement priority. Existing carriageway, building, water, tree, pole,
  transformer and parked-vehicle clearance tests remain in use.
- 321 mapped boundary segments and 13,791 short inferred party-wall segments between close
  buildings. Their source is recorded separately in compounds.json. They share the building
  mesh and chunk collider, and block pedestrian paths too. Roads, mapped access paths and gates,
  parks, water, beaches, shops, landmarks, stands and services retain clearance.

## Limits and calibration

This is semi-realistic game physics, not a measured Bajaj dynamics or crash-safety simulation.
Damage coefficients are gameplay tuning in data/vehicles/damage.tres; NPC mass/response and
dispatch settings are in traffic_physics.tres. Tyres lose grip rather than detaching; body dents
are visual and do not change the collision hull. Engine damage reduces power but preserves a
limp-home ability. Broken-glass geometry and detached parts are not implemented.

OSM does not contain every Chennai compound or alley. The inferred separators are **not exact
real-world parcel boundaries**. Each is less than 5 m long and joins neighbouring footprints;
unmapped legitimate passages may need manual exemptions after route review. No guessed walls
are drawn across known access corridors. The road graph and building footprints are unchanged.

## Device checks

1. Install the APK from this PR's successful Android Build run; confirm its build number.
2. Start with a repaired auto. Make a slow parking knock, a 20 km/h front hit, a rear hit and
   several 35 km/h impacts. Compare condition, visible panels, steering and power.
3. Save/relaunch. Check that damage remains. Pay for a partial repair, then repair fully.
4. Hit a two-wheeler and a bus at similar speeds. Check constrained recoil, no launching, no
   repeated damage while merely resting against a stopped vehicle, and normal traffic recovery.
5. Drive for several minutes to allow safe service-slot recycling. Check ambulance siren distance,
   beacon, yielding, braking and pool recovery. Frequency is cooldown plus safe-spawn availability.
6. Drive Mylapore → Triplicane → Anna Salai → T. Nagar. Check shops, compound visibility and
   collision. Try building gaps, then confirm public roads, mapped alleys and garage entrances work.
7. Repeat at night and in rain on Moto G40 and OnePlus Pad, followed by a 20–30 minute soak.
   Record FPS, heating, stuck locations and wall coordinates. Headless tests do not establish
   phone frame rate, texture appearance or map fidelity.

## Regeneration and verification

Run build_street_dressing.py → build_roadside_parking.py → append_street_shops.py →
build_compounds.py. Use build_compounds.py --fetch to refresh OSM barriers/access within the
unchanged config.BBOX. The supplemental extract is committed for deterministic offline rebuilds.
Python requires Shapely 2.x. Generated world data must not be edited by hand.

Run Python test_city_density.py and test_compounds.py, Godot import/boot, crash-reporter and
phase 1–12 suites, then the rendered performance probe and Android Build workflow. The P0 suite
covers damage/save/repair, recoil, pooled reset, ambulance lifecycle and compound geometry/masks.
