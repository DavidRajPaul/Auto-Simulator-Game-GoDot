# Organic roadside vegetation — mainline integration

## November 2: owner's tree models replace the procedural trees (current)

Everything below this section describes the **retired** procedural trees (`_shade_tree`, `_blob`, `_palm`, …),
kept for history. Now:

- **Models:** the owner's Tripo neem, coconut palm, Ashoka A (spreading) and B (slim) and pungai
  (`assets_src/models/trees/`), baked by `tools/assets/bake_trees.py` to real height (8–10 m, ×0.8–1.25 per tree),
  origin at the trunk base, matte non-metal. Dress tree codes: 0 neem, 1 palm, 2 Ashoka A, 3 Ashoka B, 4 pungai.
- **Placement** (`tools/osm/build_street_dressing.py`): kerb step 10–12 m (was 20–26 m), 90 % fill, the pole kerb
  too on roads ≥ 8 m wide (≥ 4.5 m from poles), a 0.8 m pull towards the road where a building blocks the spot,
  plus a jittered 11 m grid in OSM parks. 33.3k trees (was 11.2k): neem 33 %, Ashoka 39 %, pungai 25 %, palms 3 %
  (30 % near the beach). Poles, transformers, parking and shops are unchanged.
- **Rendering** (`scripts/world/StreetTrees.gd`): a fixed set of world MultiMeshes refilled around the camera
  every 5 m. Within 60 m the full model per species (casts shadows); beyond, one MultiMesh of 4 crossed impostor
  cards for every species (`tree_impostors.png`, `shaders/tree_impostor.gdshader`, no shadows). 6 draw calls total
  (+5 in the shadow pass) instead of one tree mesh + one palm MultiMesh per chunk.
- **Not done:** no LOD between 60 m and the cards (simplifying these leaf-card models shreds them); no collision;
  no rain tree, copper-pod or gulmohar model yet (add one = a source GLB + a `SPECIES` entry + a placement weight).

QA: phase 9 checks the species counts, near/far split, materials and that chunks carry no tree nodes. On device,
drive Kapaleeshwarar tank → Luz Corner → R.K. Mutt Road and check FPS, the 60 m model/card switch, and that the
cards' colour matches the near models in sun, dusk and rain.

## November 3: tree glitch fix (device test)

On the tablet the trees flickered while driving towards them. Causes and fixes:
- The impostor atlas imported **without mipmaps** (a headless import never runs Godot's 3D detection), so distant
  cards shimmered and sparkled. `tree_impostors.png.import` now has mipmaps + VRAM compression (ETC2/ASTC,
  ~1.75 MB instead of ~7 MB).
- Transparent atlas pixels were black, so small mips went dark and grainy. Every transparent pixel now carries the
  nearest leaf colour; the card shader raises alpha with the mip level so distant crowns keep their coverage.
- The swap from card to model at 60 m was instant. Between 50 and 62 m both are drawn and dither complementary
  pixels (`tree_near.gdshader` / `tree_impostor.gdshader`), so a tree cross-fades over 12 m.
- Rebuilds allocated an array per tree. They now write into preallocated buffers; the near models refill every 5 m
  from nearby chunks only and the far cards every 20 m: 0.24 ms per camera step on desktop (was 1.54 ms).

## Earlier procedural passes (retired)

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

## Nov 4 device test: far trees match the near model

The tree glitch was still visible when driving towards trees. Side-by-side renders at the swap distance showed the cause: each far tree was 4 crossed cards with straight-up normals, so it took full sun and read as a pale, flat blob, then turned into the darker, self-shadowed model at 56 m. A card seen edge-on showed as a thin bright vertical slab, and 4 overlapping alpha-tested cards meant 4× overdraw.

- **One card per tree.** `tree_impostor.gdshader` turns a single upright quad to face the camera, picks the two baked views either side of the real view direction, and blends them. A view seen from behind is its own mirror, so the 4 baked views cover the full circle. Silhouettes now line up with the model at the swap.
- **Lit like the model.** The normal faces the camera and leans to the sky (`sky_lean`), and albedo is scaled by `card_tone` = 0.75. Both were calibrated by drawing a shifted copy of the far cards next to the real models in the same frame. They agree within about 5 % in linear green (before: about 3.5× too bright and pale). With `cull_disabled` Godot flips a back face's normal, which made the card dark brown. The fragment shader now sets the normal again.
- **Shorter cross-fade.** The band is now 52–60 m (`FADE_M` 4, was 6), so the dither phase is brief.

Performance: 140 draw calls on the perf probe (budget 150, was 141). Far trees now cost 2 triangles each instead of 8, with 1 layer of alpha overdraw instead of up to 4. Phase 9 checks that the far set is one 4-vertex card fed the atlas view count.

