# Organic roadside vegetation — mainline integration

Ports the two procedural mesh changes from stacked PR #18 into main:
- Irregular, position-seeded six-sided canopy rings and asymmetric tops/bottoms.
- Curved two-section coconut palm fronds rather than rigid single quads.

Only WorldChunkStreamer.gd's _blob and _palm implementations are replaced. The same chunk mesh batching is retained, with no textures, external assets or new draw-call surfaces.

QA: run Godot CI and phase tests; visually inspect palms from above and below, foliage silhouette variation across chunks, triangle winding and shading; compare low-end Android draw calls and FPS. Palm geometry increases triangles per frond, so profile on device before release.
