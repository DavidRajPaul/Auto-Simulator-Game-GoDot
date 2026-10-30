# Auto Garage upgrade roadmap — Phase 0 baseline

## Scope

This PR adds automated configuration checks for the existing vehicle fleet. It does **not** claim the auto reaches its configured speed in gameplay, change live physics, add a garage mesh, or modify purchase prices. The starter auto uses `assets/models/vehicles/player_auto.glb`; no additional auto model is required.

## Existing configurations (confirmed in `data/vehicles/*.tres`)

| Profile | Configured stock maximum | Peak engine force | Torque falloff |
| --- | ---: | ---: | ---: |
| Singara Classic | 58 km/h | 1800 N | 0.35 |
| Madras King Deluxe | 72 km/h | 2150 N | 0.40 |
| Namma Green EV | 68 km/h | 2300 N | 0.10 |

The controller drives its rear wheels with `engine_peak_force_n * 0.5` per wheel while below the configured speed limit; the force reduces with speed according to `torque_falloff`. The configured speed is an engine cutoff, not a measured equilibrium speed.

The existing garage buys engine levels 1–3 (+7% force and +3 km/h per level), suspension (+8% damping stiffness and -15% jolts per level) and tyres (+6% grip per level). A condition under 40% imposes a 15% top-speed and 10% engine-force reduction.

## Android / desktop real-driving benchmark (manual)

Run on a long unobstructed level section of road, no passenger, full fuel, 100% vehicle condition. Use the *same scene and road segment* for each run.

1. Record starting auto, upgrades, condition, fuel level, display FPS, and device.
2. Accelerate at full throttle from rest and record approximate 0–30 km/h, 0–50 km/h and stable peak speed. Record whether steering, traffic, road slope, or collisions disrupted the run.
3. Repeat with three engine upgrades, then with three passengers where supported. Compare average results over three clean runs.
4. Repeat using the Deluxe and EV vehicle profiles if available, on the same segment.
5. Record speedometer readout alongside the in-game speed values; don't infer performance from the configured cap alone.
6. Test full-throttle steering, braking distance from 40 km/h, and high-speed stability with and without tyres/suspension upgrades.

| Scenario | Configured cap | Measured 0–30 s | Measured 0–50 s | Measured peak | Observations |
| --- | ---: | --- | --- | --- | --- |
| Singara stock / 100% condition | 58 | TBD | TBD | TBD | |
| Singara engine level 3 / 100% | 67 | TBD | TBD | TBD | |
| Singara stock / 30% condition | 49.3 | TBD | TBD | TBD | |
| Deluxe stock / 100% | 72 | TBD | TBD | TBD | |
| EV stock / 100% | 68 | TBD | TBD | TBD | |

The 49.3 km/h worn-out cap is **one plausible explanation** for an observed ~50 km/h, but it has not been verified as the user's specific cause.

## Test strategy

`tests/run_phase4_tests.gd` contains Phase 0 contract checks. Existing Godot CI runs it. These checks verify config consistency, positive drive-force curves, upgrade effects, per-vehicle profiles and damage penalties, but not actual road dynamics. Do not adjust force, drag, braking or speed caps until measured results establish a baseline.

## Phased next steps

- **Phase 1:** Create one reusable low-poly roadside garage, verify footprint and collision-free placement near Mylapore's garage service marker.
- **Phase 2:** Add garage wayfinding, parking/entry state and exit camera flow.
- **Phase 3:** Garage preview UI with effective-stats comparison and transactional purchasing.
- **Phase 4:** Extend mechanical upgrades (gearbox/brakes) and tune physics from the measured baseline.
- **Phase 5:** Unlock levels, earning economy and save compatibility.
- **Phase 6:** Cosmetic sockets and modular parts on existing player auto mesh.
- **Phase 7–8:** Android benchmarks, accessibility, CI and production polish.

## What the user needs to supply

**Nothing for Phase 0.** For Phase 1, the user can provide a Tripo-exported optimized `.glb` file by attaching it to this chat or uploading it to `assets/models/city/` in a GitHub branch. Suggested filename: `garage_workshop.glb`. The scene should have an open service bay, tin roof, tyre rack and toolbox. No second auto model is required. If a binary file cannot be transferred directly through GitHub connector, use a GitHub upload to the PR branch and ask the assistant to integrate the committed path.
