# Namma Auto — Manual regression test plan (Android)

**Build under test:** After PR #25 → #26 → #27 are merged into main and main CI is green, install a fresh APK built from that exact main SHA. Do not treat a green CI result as proof of visual or device behavior.

## Before testing
- [ ] Record APK build SHA, Android version, device model, screen resolution, and average FPS.
- [ ] Start a fresh game; separately test an existing save. Keep a screenshot/video for each issue.
- [ ] Use in-game weather/time controls where available; if absent, use a debug scene/test build rather than guessing how to trigger weather.
- [ ] Test landscape orientation, touch input and audio, including pause/resume and a cold restart.

## P0 — Must pass before release
### Basic driving and controls
- [ ] Launch game from fresh install; no crash, blank screen, missing assets or broken UI.
- [ ] Accelerate, brake, reverse and steer at low/high speeds; vehicle stays upright and wheels track road.
- [ ] Change camera views; cockpit controls, horn, indicators and wiper work.
- [ ] Drive into a wall at low speed and glance along it; auto does not stick, launch or flip.
- [ ] Teleport/respawn if available; vehicle and physics reset without a violent impulse.

### NPC traffic — PR #25
- [ ] Follow a moving auto/car at ~20–30 km/h; NPC behind slows smoothly rather than clipping.
- [ ] Stop ahead of an NPC on a straight road; NPC brakes and waits without entering the player's body.
- [ ] Resume driving; following NPC accelerates without repeated stop/start oscillation.
- [ ] Observe buses and bikes behind slow traffic; lane shifts happen only with free lateral space.
- [ ] Observe 10+ minutes of traffic; no vehicles drive through each other or teleport in view.

### Junctions — PR #26
- [ ] Watch a vehicle turn across an intersection while another approaches; approaching vehicle yields before the curve.
- [ ] Wait until junction clears; waiting vehicle resumes.
- [ ] Observe a crowded junction for 3–5 minutes; record any permanent deadlock or side impact.
- [ ] Drive the player auto across a junction; check whether NPCs still collide (player-aware intersection reservation is NOT in this slice).

### Monsoon traffic — PR #27
- [ ] In dry weather, observe NPC speeds near a known flood spot; no flood penalty.
- [ ] Start rain and return to the same flood spot; NPCs slow as they approach water.
- [ ] Observe deep flooded area; NPCs crawl more slowly than near shallow puddles.
- [ ] Leave the flood area; NPCs regain normal traffic speed.
- [ ] Stop rain; flood slowdown disappears. Check whether visual flood drainage and traffic timing feel consistent.
- [ ] Note: NPC route avoidance and NPC engine stalling are NOT implemented in PR #27. Do not mark these as failures of this slice; track them as future features.

### Water and player auto — PRs #20–24
- [ ] During rain, inspect wet roads, puddle shader, rain overlay, cockpit drops and wiper.
- [ ] Drive slowly then faster through water; three-wheel splash density rises with speed, stops when dry/stationary.
- [ ] Drive through shallow flood; drag feels stronger but vehicle remains controllable.
- [ ] Enter deep flood; engine stalls; kick-start while submerged is blocked and rescue/tow option is available.
- [ ] Use rescue/tow; auto returns safely near a service location and can drive again.
- [ ] Drive through overlapping flood spots if available; exiting the shallower area must not incorrectly reset the deeper depth. **Verify PR #22 is actually merged; otherwise log as known gap.**
- [ ] Turn rain off and leave flood; no permanent water drag or splash effect.

### Fuel and service
- [ ] Drive long enough to consume fuel; gauge decreases rather than remaining full.
- [ ] Reach low fuel; warning appears; locate service/fuel station.
- [ ] Refuel; gauge updates, cost applies if configured, and driving resumes.
- [ ] Reach empty tank in a controlled test; note engine behavior and recovery path.

## P1 — Gameplay and city authenticity
### Passenger and economy
- [ ] Accept a passenger request, reach pickup, board, drive to destination, drop off, receive fare.
- [ ] Check incorrect pickup/drop-off, cancellations, rewards, odometer, mission state and save/reload.
- [ ] Verify tutorial prompts, first ride and progression do not block normal driving.

### Environment and weather
- [ ] Inspect coconut palms and roadside tree crowns from near/far; no obvious rectangular foliage, inverted faces or missing shadows.
- [ ] Compare clouds and sky under clear and rainy conditions.
- [ ] Check Chennai landmarks, shop fronts, road markings, buildings, buses, pedestrians and street ambience.
- [ ] Drive between map chunks; no visible missing roads, major stutters or assets popping directly in front of player.
- [ ] Check morning/evening/night lighting if available.

### Vehicle systems and audio
- [ ] Test horn variants, engine idle/rev, gear/reverse, indicators, collision sounds and rain audio.
- [ ] Test kick-start rhythm after a non-flood stall if available.
- [ ] Verify garage/loadout, paint or upgrades persist after restart if available.

## P0 — Android performance and reliability
- [ ] Run 15 minutes in busy traffic and 15 minutes during heavy rain/floods; record FPS, thermal throttling and memory.
- [ ] Test with battery saver enabled and after switching apps for 2 minutes; game resumes with sound and input intact.
- [ ] Disconnect network; offline driving still works.
- [ ] Force-close and reopen; save/progression remains valid.
- [ ] Check no recurring errors in Godot/Android logs if accessible.

## Issue report format
**Build SHA:**  
**Device / Android:**  
**Location or mission:**  
**Weather / time:**  
**Steps to reproduce:**  
**Expected:**  
**Actual:**  
**Repro rate:** e.g. 3/3  
**Screenshot/video:**  

**Release gate:** all P0 checks pass on at least one lower-end Android phone and one representative target phone; no persistent NPC junction deadlocks, no flood soft-lock, no blocking crash. Track P1 separately.
