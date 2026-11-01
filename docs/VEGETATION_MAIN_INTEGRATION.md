# Organic roadside vegetation — mainline integration

Ports the two procedural mesh changes from stacked PR #18 into main:
- Irregular, position-seeded six-sided canopy rings and asymmetric tops/bottoms.
- Curved two-section coconut palm fronds rather than rigid single quads.

Only WorldChunkStreamer.gd's _blob and _palm implementations are replaced. The same chunk mesh batching is retained, with no textures, external assets or new draw-call surfaces.

QA: run Godot CI and phase tests; visually inspect palms from above and below, foliage silhouette variation across chunks, triangle winding and shading; compare low-end Android draw calls and FPS. Palm geometry increases triangles per frond, so profile on device before release.

## November foliage realism pass

The same generated tree placements feed six visual types: rain tree and neem share a seeded shade-tree generator, with distinct mast tree, copper-pod, pungai, gulmohar, and imported coconut palm. The palm source has a baked colour texture and is instanced through one MultiMesh per loaded chunk; the other five types share a single opaque vertex-colour mesh per chunk.

This pass gives the shade trees a more uneven crown spread, staggers the mast-tree tiers, tones down the yellow and red flower caps, and varies the five-sided trunks by face. Each canopy lobe now has an irregular eight-sided ring with a directional sunlit upper facet and darker underside. It uses 16 triangles instead of 12 per lobe; there are no alpha leaf cards or extra materials. Both tree batches skip real-time shadow-map rendering, with dark undersides and crown overlap providing the inexpensive depth cue. Placement data, collision, and city chunk counts are unchanged.

Visual QA: inspect rain/neem side by side, the mast silhouette, and restrained copper-pod/gulmohar flowers at driving height in sun, dusk and rain. Profile low-end Android for FPS and visible draw calls before release; disabling tree shadow casting trades ground shadows for lower GPU work. A future higher-quality device tier could add a short-range shadow option once measured on hardware.
