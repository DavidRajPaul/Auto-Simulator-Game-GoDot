# Intelligent traffic following — first slice

Upgrades the existing 18-vehicle pooled RoadGraph AI rather than introducing a second traffic controller.

- Nearest lead vehicle query returns front-bumper clearance and lead speed; includes the player's forward velocity.
- Following target uses 1.5-second headway, 3 m static buffer, and a speed-based stopping-distance cap.
- Comfort braking is limited to 4 m/s²; close-range emergency braking up to 9 m/s².
- Movement step clamps to remaining bumper gap, preventing same-lane tunnelling at low frame rates.
- Existing lateral gap seeking, horn reactions, junction curves and pooling remain.

## Limitations / next slices
- Same-edge follower detection; junction entry still uses the existing gap_ahead logic and needs cross-edge conflict reservation.
- No general world-obstacle raycast or pedestrian detection in this slice.
- Player and NPC traffic may still collide due to sideways movement; validate with Android physics and real gameplay.

## QA
Run all Godot phase tests, especially Phase 2 stopped-lead regression; inspect stop-and-go traffic, merge behavior, buses, turns, and player braking interactions. Profile 18 pooled vehicles on a low-end Android device.
