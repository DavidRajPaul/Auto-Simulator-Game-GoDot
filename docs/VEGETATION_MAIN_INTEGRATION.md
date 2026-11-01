# Organic roadside vegetation — mainline integration

Ports the two procedural mesh changes from stacked PR #18 into main:
- Irregular, position-seeded six-sided canopy rings and asymmetric tops/bottoms.
- Curved two-section coconut palm fronds rather than rigid single quads.

Only WorldChunkStreamer.gd's _blob and _palm implementations are replaced. The same chunk mesh batching is retained, with no textures, external assets or new draw-call surfaces.

QA: run Godot CI and phase tests; visually inspect palms from above and below, foliage silhouette variation across chunks, triangle winding and shading; compare low-end Android draw calls and FPS. Palm geometry increases triangles per frond, so profile on device before release.

## November foliage realism pass

The same generated tree placements feed six visual types: rain tree and neem share a seeded shade-tree generator, with distinct mast tree, copper-pod, pungai, gulmohar, and imported coconut palm. The palm source has a baked colour texture and is instanced through one MultiMesh per loaded chunk; the other five types share a single opaque vertex-colour mesh per chunk.

This pass gives the shade trees a more uneven crown spread, staggers the mast-tree tiers, tones down the yellow and red flower caps, and varies the five-sided trunks by face. Each canopy lobe now has an irregular eight-sided ring with brighter upper facets and a darker underside. It uses 16 triangles instead of 12 per lobe; there are no alpha leaf cards or extra materials. Tree shadows retain their existing behaviour. Placement data, collision, draw-call count, and city chunk counts are unchanged.

Visual QA: inspect rain/neem side by side, the mast silhouette, and restrained copper-pod/gulmohar flowers at driving height in sun, dusk and rain. Profile low-end Android for FPS and triangle/shadow costs before release; the extra crown facets increase geometry even though the number of batches stays fixed.

## Visible species expansion after device feedback

The earlier pass retained all existing tree types and made modest facet and colour changes. It did not add new trees. This update adds two conspicuous silhouettes in the shipped `data/world/dress/` chunks:

| ID | Tree | Driving-view shape | Placement |
| --- | --- | --- | --- |
| 6 | Indian almond / naattu badam (*Terminalia catappa*) | Three spaced horizontal tiers, with occasional copper lower foliage | Avenues across the map |
| 7 | Poovarasu (*Thespesia populnea*) | Rounded wind-shaped crown, few small yellow blooms | Most frequent near the coast; uncommon inland |

The [Greater Chennai Corporation avenue-tree guidance](https://chennaicorporation.gov.in/images/Tree%20planting.pdf) lists both among suitable trees for medium roads and describes poovarasu as salt and wind resistant. The distribution is a visual design choice, not a survey of individual Chennai trees. We preserved every existing tree coordinate, scale, seed, parking record, pole, wire and transformer while updating species IDs. Both shapes join the existing opaque per-chunk foliage mesh; no new material or draw-call surface is needed.

Check the **new Android Build artifact from this commit** rather than an older APK or release. At street height, look for the tiered almond crown and the poovarasu near Marina. The phase 9 suite checks that the packaged dressing data actually includes both IDs. Performance CI checks draw calls; a budget Android device still needs a visual and sustained FPS review.
