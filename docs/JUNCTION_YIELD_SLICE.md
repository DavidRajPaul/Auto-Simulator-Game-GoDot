# Junction conflict yielding

Adds a lightweight junction occupancy query to the existing pooled traffic manager. Approaching vehicles slow and stop before the start of their Hermite turn when another pooled vehicle is turning within 12 m of the junction node or a stopped vehicle occupies its centre.

The check scans the existing <=18 vehicle pool; no new physics queries, assets, or pathfinding. Traffic proceeds automatically when the junction clears.

## Limits
This is conservative yielding, not a full intersection scheduler. Multiple approaches may queue and potential deadlocks need gameplay QA; player vehicle is handled through existing following checks but not yet in junction occupancy. Future work: approach priorities, cross-traffic reservations, pedestrians and signal phases.

## QA
Run Phase 2 and all Godot CI tests. Verify approaching cars stop without clipping, resume after the turning car leaves, and do not stall permanently at crowded junctions. Test low-end Android frame time.
