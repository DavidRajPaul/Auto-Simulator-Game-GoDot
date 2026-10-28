# Monsoon mainline integration

This PR ports the monsoon effects originally authored in stacked PR #19 to the actual main branch.

- Animated muddy water ripple shader on existing flood discs.
- Bounded horizontal drag scaled by water depth.
- Flooding at the configured stall threshold stops the engine at low speed regardless of accelerator; extreme depth (1.35x) stalls even at speed.
- Existing rescue and submerged restart safeguards from PR #20 remain unchanged.

## Test plan
- CI: Godot import, all phase tests, Android export.
- Device: check dry roads have unchanged handling, shallow water slows, deep water stalls, rescue and kick-start after tow work.
- Validate GPU cost of transparent ripple shader, visible water edges, and performance on low-end Android.
- Next: aggregate overlapping flood zones and add pooled near-camera tyre splash effects.

The model is gameplay-focused, not a real vehicle's safe wading-depth specification.
