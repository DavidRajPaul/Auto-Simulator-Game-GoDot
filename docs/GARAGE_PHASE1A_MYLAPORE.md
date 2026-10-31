# Garage Phase 1A — Mylapore workshop integration

## Source asset
The user supplied `garage_workshop.glb` (GLB 2.0, approximately 763 KiB). Inspection showed one mesh, one material, one image/texture, approximately **9,834 triangles** (29,502 triangle indices). Its native position bounds are about 0.96 x 0.61 x 1.0 local units; the initial visual scale in Godot is 8.0. The final visual orientation and scale **are not validated on device**.

## Exact binary upload required
The GitHub connector used to author this branch cannot transfer the conversation-attached binary. **Before merging**, upload the supplied asset to this exact PR branch as:

`assets/models/city/garage_workshop/garage_workshop.glb`

GitHub mobile/web: open the PR branch, navigate to `assets/models/city`, use **Add file → Upload files**, create the `garage_workshop` directory in the upload path if needed, and commit to `feature/garage-phase1a-mylapore-workshop`. Do not rename or convert the binary again.

Until the file exists, `ServicePoints.gd` deliberately keeps the old procedural garage representation. Only `garage_mylapore` attempts to load the new asset; Marina and T. Nagar remain unchanged.

## Current scope
- Reuse the existing `ServicePoints` garage identity and stop-to-open interaction.
- Load the authored GLB for Mylapore if it has been committed.
- Retain the existing procedural marker as fallback.
- Retain the other garage locations and all other service types.

## Explicitly not complete
- Road/footpath clearance, driveable service bay and proper workshop orientation.
- Physical wall collider setup and vehicle approach verification.
- Android screenshot/render validation; test GLB materials and one-mesh draw budget.
- Confirming `garage_mylapore` marker is off the live carriageway. Current authored manifest service position should not be treated as a collision-safe building site without geometry checks.

## Next slice (Phase 1B)
1. Import GLB in Godot and inspect forward direction, visible front opening, texture and meter scale.
2. Project the existing Mylapore service point onto an adjacent vacant lot, checking footprints against OSM roads, existing building outlines, and props.
3. Place collider primitives around solid walls, while leaving the vehicle bay open.
4. Add a designated parking polygon with stop speed requirement and link the workshop interaction location to that bay.
5. Add Godot tests verifying one model placement, successful asset load, collision/driveway clearance and unchanged other service points.
6. Test Android touch entry/exit and performance, then proceed to navigation/map affordances in Phase 2.

No additional player auto model is needed.
