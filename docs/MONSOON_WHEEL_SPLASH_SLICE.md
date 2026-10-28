# Monsoon wheel splash slice

Adds three GPU particle emitters (one per wheel) to AutoRickshawController. Shared procedural quad and particle material, ten particles per wheel at peak; no texture downloads or CPU particle loops.

- Only emits when water depth exceeds 0.06 m, speed exceeds 6 km/h and that wheel has ground contact.
- Emission density ramps up toward 42 km/h; naturally shuts off when leaving the water or stopping.
- Particle lifetime 0.42 s; translucent pale grey spray; no physics or collision calculations.
- Headless regression asserts all three emitters exist.

QA: test flooded streets at different speeds, dry roads, stationary engine stalls, reverse driving, and low-end Android graphics. Inspect sprite facing, scale and actual draw calls on device. Existing monsoon water visuals require PR #21 to be merged; splash emitter uses the already-existing depth signal on main.
