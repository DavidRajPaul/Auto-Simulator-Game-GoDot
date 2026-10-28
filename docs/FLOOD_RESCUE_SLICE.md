# Flood rescue: safe restart and mobile HUD

## Implemented
- When a flood zone stalls the auto, show a RESCUE touch control near KICK.
- RESCUE invokes the existing tow service to a compatible fuel/service station, using the current player position.
- When the engine is submerged at/above the vehicle's configured stall depth, kick-start is refused with a HUD explanation.
- After a rescue teleport, clear the prior water-depth state; the player can then use the existing kick-start flow.
- Rescue control hides on successful teleport. No paid assets or services.

## QA
1. In flood, stall and verify RESCUE appears.
2. Attempt KICK in deep water: refuse and explain.
3. Tap RESCUE: verify arrival at the correct nearest station, no origin-based misrouting.
4. At destination, kick-start succeeds using normal rhythm.
5. Verify no rescue button on normal dry-road gameplay; verify touchscreen layout at phone sizes.
6. Existing tow cost rules still apply. If the player has no money, verify the tow path is not blocked.

## Integration caveat
PRs #18 and #19 were merged into feature branches rather than main. This PR starts from actual main and is deliberately independent; the vegetation and monsoon visual/drag commits still need to be ported to main. Do not assume stacked PR merges deployed those changes.
