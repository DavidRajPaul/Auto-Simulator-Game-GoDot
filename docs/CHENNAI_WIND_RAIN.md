# Wind, potholes you can feel, rain splashes, shopping bags (Nov 14 2026)

Owner questions: "will the trees respect the wind direction?", "will the auto obey physics
going through potholes?", "will rain splash when it hits the ground?", plus "add shopping bags
to some NPCs" and "Bus Simulator Indonesia has realistic trees, can we do the same?".

## Wind (`scripts/world/Wind.gd`)

One wind for the city as three shader globals (`project.godot [shader_globals]`: `wind_dir`,
`wind_strength`, `wind_gust`). Chennai's day: a light land breeze from the west in the morning,
the sea breeze from the south-east through the afternoon (strongest), calm at night; rain adds
strength and more frequent gusts (every 6–18 s, ~3.5 s each).

* `tree_near.gdshader`: the whole tree bends with the wind (displacement grows with the square
  of height; ~3 % of tree height at full push), each tree out of step with its neighbours, leaves
  flutter on top. Runs in the shadow pass too, so shadows sway.
* `tree_impostor.gdshader`: the far card's top leans by the same formula, so the cross-fade at
  52–60 m doesn't jump.
* Road dust (`WindDustFX`) and the rain spray follow the same direction.

No nodes, no draw calls; a few vertex operations.

## Potholes you can feel (`scripts/world/RoadWear.gd`)

The road shader paints potholes from `road_condition` + a world-space value noise. `RoadWear`
is the same formula in GDScript. Each player wheel asks `pothole_depth` at its contact point
(on drawn asphalt only): the spring sees the extra length so the wheel drops into the hole, and
climbing out of the far lip at speed applies an upward kick with a little drag, a camera jolt
(`camera_shake`), a low thump (`VehicleAudio`, `crash_light.ogg` pitched down) and
`SignalBus.pothole_hit`. The comfort meter already reads vertical jolts, so riders feel it.
Max depth 7.5 cm. Not reproduced on the CPU: the detail-texture nudge and repair patches
(texture lookups), so a hole edge can be a few cm off.

## Rain splashes (`scripts/world/RainSplashes.gd`, `shaders/rain_splash.gdshader`)

* 320 splashes round the camera in ONE MultiMesh (+1 draw call while raining): each a ring
  spreading on the ground and a crown of spray, re-placed every 0.42 s by a hash of its index and
  cycle in the vertex shader (no CPU work), leaning with the wind.
* Raindrop rings on the wet road itself (`street_surface.gdshader`, procedural, within 28 m of
  the camera, brightest in potholes), only while it is actually raining.
* Tyre spray behind the auto on a wet road, and a splash when a wheel drops into a
  rain-filled pothole (two `CPUParticles3D`, drawn only while emitting).

## Shopping bags (`PedestrianManager`)

About a third of walkers carry a bag (a quarter of those, two): Chennai's yellow cloth manja pai,
printed cloth, white or blue plastic, jute. Re-rolled at every spawn. All bags are one MultiMesh
hung from the hand bones each frame (+1 draw call). A hand holding an umbrella, a woman drawing a
kolam and a fallen walker carry no bag. The pool size is unchanged: more walkers would cost a
draw call each.

## Trees: what Bus Simulator Indonesia does, and what we do

BUSSID (Maleo, Unity) can't be inspected, but its roadside trees show the standard mobile
recipe for realistic foliage:

1. **Photo-sourced leaf cards**: crowns built from many small quads with alpha-cut photographs of
   real leaf clusters, around a simple trunk. Real photos read as "realistic" more than any
   modelled leaf.
2. **Billboard LOD far away**, with dithered or alpha fading between the two.
3. **Wind in the vertex shader**: trunk bend plus leaf flutter.
4. **Variation**: a few species, random scale, rotation and tint per tree.
5. **Cheap lighting tricks**: darker inner crown (baked ambient occlusion in vertex colour),
   light coming through the leaves (translucency), and haze in the distance.

Where Namma Auto stands: 2 (near model + impostor cards with a dithered cross-fade), 4 (five
Chennai species with per-tree size, yaw and tint) and 5 (fog) were already done; this change adds
3 (wind) and the translucency of 5 (`BACKLIGHT` on the crown). What remains is 1: our trees are
the owner's Tripo models with baked textures, not photographed leaf cards. To match BUSSID's look,
the owner can supply photo-textured tree models (CC0 sources: Poly Haven / ambientCG leaf
photos, or Tripo models generated from real neem / rain tree / coconut photos); they go through
`tools/assets/bake_trees.py` like today, and the wind and impostors apply automatically.

## Device fixes (Nov 14, afternoon)

* **Shopkeepers and customers now run from a fire.** They are a static merged mesh
  (`ShopPeople`), so when the auto catches fire every shop person within 22 m is taken out of
  it and handed to a pooled walker of the same character standing on the same spot
  (`SignalBus.shop_people_scattered`, up to 8); the usual fire scare then runs them off with
  screams. The spots stay empty until the player has left (70 m) or 2 minutes after the fire.
* **Traffic steers instead of sliding.** A wheeled vehicle can only move sideways while it
  rolls forward: the sideways rate is now capped by forward speed × how hard each kind can
  steer (car 0.3, bike 0.55, plus a little foot-paddling for two-wheelers at a standstill), and
  the body turns its nose into the lane change (up to 20°), easing in and out. Two-wheelers
  lean into it. A stopped car never moves sideways.
* **People chat.** The owner's Mixamo `Talking_2` and `Talking_4` were retargeted onto every
  pedestrian (`add_mixamo_clips.py --only talk_2,talk_4`, +~100 KB per character). About half of
  standing walkers get a partner 1.05 m away along the kerb, face to face, turned a little to the
  road; they take turns (talker plays `talk` / `talk_2` / `talk_4`, the listener idles and now and
  then chimes in), swapping every 3.5–8 s. A reaction, a fire or either one leaving ends the
  chat. Pairs never stand in a tree trunk or an EB pole. `Talking_3.fbx` arrived truncated (its
  Connections section is cut ~21 KB short) and converts to an empty file: re-download it from
  Mixamo and it will be added the same way (`talk_3` is already listed).
