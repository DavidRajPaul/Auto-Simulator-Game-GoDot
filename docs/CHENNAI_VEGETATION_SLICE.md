# Chennai vegetation — organic silhouette slice

## Implemented
- Roadside shade-tree, Ashoka, neem, rain-tree and flowering-tree foliage now uses deterministic irregular crowns instead of perfectly regular hexagonal bipyramids.
- Crown vertices vary in radial extent, height, twist and apex offset; color varies subtly per face.
- Existing crown triangle count stays at 12 per crown; no new texture or mesh resources.
- Coconut fronds use two tapered drooping panels per frond instead of one flat kite; this increases palm foliage geometry but preserves chunk batching and draw calls.

## Constraints
- Retains the existing Chennai species distribution and OSM-based street placement.
- No imported assets, external licenses, new material passes or runtime per-frame vegetation animation.
- Meshes are generated with the same deterministic chunk-streaming pipeline.

## Acceptance
1. CI Godot import/tests and Android export pass.
2. Inspect Marina palms, Mylapore shade trees and avenues at near/mid distance.
3. Compare draw calls, triangles, chunk generation time and mobile frame time against main.
4. Reject if branch panels look self-intersecting, crowns look spiky, or vegetation crowds roads.
5. Next slice: wind variation and optional verified CC0 higher-detail near-camera models only if performance allows.
