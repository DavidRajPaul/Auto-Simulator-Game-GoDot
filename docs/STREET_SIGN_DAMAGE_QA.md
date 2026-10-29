# Street board text, collision and damage — Android QA

## Changes
- Fit English and Tamil by measured glyph width and height inside the 2 m blue plate rather than text length.
- Solid plate and twin post collision shapes, with a player-only impact trigger.
- First player contact bends the complete board; a later contact after leaving and re-entering breaks it.
- After 35 seconds, the broken sign respawns when the nearby sign pool refreshes.
- Sign damage is session-local; no save persistence.

## Manual verification
1. Visit several long street names and Tamil signs; no text should extend outside the blue rectangle.
2. Drive slowly into the plate and each post; the auto must not pass through the board.
3. On first collision, plate, posts and text tilt together, with no detached floating labels.
4. Reverse clear, then hit again; board falls and disappears. Wait 35 seconds and drive nearby; board reappears upright.
5. Drive to a different neighborhood and return; pooled boards retain correct text and transform, with no broken/tilted state leaking to another sign.
6. Check FPS with eight nearby signs; verify no noticeable spikes or errors.
7. Inspect small font legibility on long names; prioritize containment over illegibly tiny text in future UX tuning.

## Known limitations
- This is a stylized bend-and-fall tween, not a fully simulated rigid-body debris object.
- Impact detection uses area overlap; a brush at low speed can count as an impact.
- Actual Tamil glyph width depends on font fallback, so test on target Android devices.
