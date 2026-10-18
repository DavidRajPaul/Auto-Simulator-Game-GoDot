# 🛺 Namma Auto: Chennai Rickshaw Simulator 3D

[![Android Build](https://github.com/DavidRajPaul/Auto-Simulator-Game-GoDot/actions/workflows/android-build.yml/badge.svg)](https://github.com/DavidRajPaul/Auto-Simulator-Game-GoDot/actions/workflows/android-build.yml)

A culturally authentic auto-rickshaw driving and economy simulator set in Chennai, built in **Godot 4.x** for budget Android phones. The project is developed mostly by AI coding agents (Claude Code, Codex, Cursor) working under the rules in [`AGENTS.md`](AGENTS.md).

> **Pitch:** Drive a yellow-and-black Bajaj RE through Marina Beach, Mylapore and Anna Salai. Haggle fares in Tanglish ("Meter Podu vs. Bargain"), squeeze through gaps between MTC buses, survive the Northeast Monsoon, and build your Auto Stand reputation. Free Roam and Savari (passenger) mode are open from minute one, with no parking-gate grind.

---

## 📌 At a glance

| | |
|---|---|
| **Genre** | Open-zone driving + economy sim (hybrid-casual / mid-core) |
| **Platform** | **Android only** (Google Play), arm64-v8a + armeabi-v7a |
| **Engine** | Godot 4.4.1 (pinned), Mobile renderer + GLES3 fallback, Jolt Physics 3D |
| **Language** | Fully statically typed GDScript 2.0 |
| **Target device** | Helio G85 / Snapdragon 680, 3–4 GB RAM, 60 FPS |
| **Size budget** | < 85 MB initial `.aab` |
| **Monetization** | Hybrid: rewarded + capped interstitial ads, Play Billing IAP (UPI) |

### Design pillars
1. **Madras Soul** – real Chennai landmarks, signage, sounds, vehicles and Tanglish dialogue.
2. **Immediate freedom** – Free Roam and Savari mode unlocked at install.
3. **Meter vs. Bargain** – 5-second fare haggling, fuel/LPG/EV management, Auto Stand respect.
4. **AI-agent modularity** – `SignalBus` decoupling, data in `.tres` resources, headless CLI tests.

---

## 🧱 Tech stack

| Layer | Choice |
|---|---|
| Engine / physics | Godot 4.x + Jolt, custom 3-point raycast delta-trike (based on `DAShoe1/Godot-Easy-Vehicle-Physics`) |
| Roads & traffic lanes | `TheDuckCow/godot-road-generator` |
| Map pipeline | OpenStreetMap → Blosm (Blender) / Python → chunked `.tscn` (250 m × 250 m, 3×3 streaming) |
| Agent tooling | `satelliteoflove/godot-mcp`, `Coding-Solo/godot-mcp` |
| Ads | AppLovin MAX or CAS.AI mediation + AdMob (`godot-sdk-integrations/godot-admob`) |
| IAP | Google Play Billing v7/v8 (`godot-google-play-billing`) – UPI via Play checkout |
| Save / social | Encrypted local save + Play Games Services v2; Nakama later |
| Assets | CC0/CC-BY only: Kenney, Quaternius, ambientCG, Poly Haven, Sonniss |

---

## 📂 Repository layout

```text
.
├── AGENTS.md                         # Agent constitution – read before every task
├── project.godot                     # Config, InputMap, autoloads, Jolt, 60 Hz physics
├── export_presets.cfg                # Android preset (arm64 + armv7)
├── .github/workflows/android-build.yml   # CI: tests → Android APK
├── autoloads/        SignalBus.gd, GameState.gd
├── data/vehicles/    VehicleStats.gd, Bajaj_RE_4S.tres
├── data/passengers/  PassengerArchetype.gd
├── scenes/           main_phase1_greybox.tscn, vehicles/, traffic/, ui/
├── scripts/vehicle/  AutoRickshawController.gd, CameraRig.gd
├── scripts/traffic/  ChennaiTrafficManager.gd, TrafficVehicleAI.gd
├── scripts/world/    WaterlogZone.gd, GreyboxDressing.gd
├── scripts/ui/       TouchHUD.gd
└── tests/            run_phase1_tests.gd + .tscn (38 checks)
```

### Phase 1 controls (greybox)
| Action | Touch | Keyboard (editor testing) |
|---|---|---|
| Accelerate / Brake–reverse | right pedals | W/↑ · S/↓ |
| Steer | drag the handlebar zone (bottom-left) | A/← · D/→ |
| Handbrake | H-BRK | Space |
| Horn ("Pom-Pom") | POM POM | H |
| Kick-start after flooding | KICK | K |
| Camera (Chase → Cockpit → Top-down) | CAM | C |
| Wiper | WIPER | V |

The greybox strip has a speed breaker at 180 m and a monsoon puddle (right side) at 320 m. Stop in it and the engine floods; tap KICK three times to restart.

---

## 🚀 Getting started

```bash
git clone https://github.com/DavidRajPaul/Auto-Simulator-Game-GoDot.git
cd Auto-Simulator-Game-GoDot

godot --headless --path . --import                                          # import assets
godot --headless --path . --fixed-fps 60 res://tests/run_phase1_tests.tscn  # run tests (exit 0 = pass)
```

Open the folder in **Godot 4.4.1** to play the greybox in the editor (keyboard controls above).

## 📦 Android builds (GitHub Actions)

Every push and PR to `main` runs **[Android Build](.github/workflows/android-build.yml)**:

1. **Headless tests:** import, boot the main scene, run the Phase 1 suite. The build stops if anything fails.
2. **Export:** Godot 4.4.1 + export templates (cached) + JDK 17 + the runner's Android SDK → `NammaAuto-debug.apk` (arm64-v8a + armeabi-v7a). The version code is the CI run number.
3. **Download:** Actions → latest run → *Artifacts* → `NammaAuto-android-<run>`. Install with `adb install -r NammaAuto-debug.apk` or sideload.
4. **Release APK (optional):** add repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS` and `ANDROID_KEYSTORE_PASSWORD`, and CI also signs `NammaAuto-release.apk`.
5. **Tags:** pushing a tag like `v0.1.0` attaches the APKs to a GitHub Release.

> Play Store uploads need an **AAB** built through Godot's Gradle build. That is scheduled for Phase 6 (see priorities).

---

# 🗺️ Roadmap

The work is split into **MVP phases (1–5)**, which end in a feature-complete, closed-testable build, and **launch phases (6–10)**, which take that build through Google Play and into LiveOps. Every phase has an exit gate; an agent cannot start the next phase until the gate passes in CI.

Legend: ✅ done · 🟡 partly done · ⬜ not started · **Android only**: no iOS, desktop or web targets.

## Part A — MVP

### Phase 1 · Core greybox & 3-wheel physics 🟡 code ✅, device gate pending *(Weeks 1–2)*
**Goal:** the auto feels right to drive on a test strip, on a real budget phone.

| Item | Status |
|---|---|
| `AGENTS.md`, `project.godot` (InputMap, autoloads, Jolt, 60 Hz physics, strict typing) | ✅ |
| `SignalBus.gd`, `GameState.gd` (meter fare ₹35 + ₹18/km, night 1.5×) | ✅ |
| `VehicleStats.gd` + `Bajaj_RE_4S.tres`, `PassengerArchetype.gd` | ✅ |
| `AutoRickshawController.gd`: 3-ray suspension, anti-roll, two-wheel Gethu, water stall + kick-start, passenger mass/CoM, LPG burn, odometer | ✅ |
| `CameraRig.gd`: Chase, Cockpit, Top-down | ✅ |
| `ChennaiTrafficManager.gd` + `TrafficVehicleAI.gd`: 18-vehicle pool, 6 sub-lanes, gap-seeking, horn tiers (buses ignore twin horn) | ✅ |
| `TouchHUD.gd`: multitouch handlebar, pedals, horn, kick, camera, wiper, speedo, fare meter, LPG bar | ✅ |
| Greybox Anna Salai strip: speed breaker, monsoon puddle, MultiMesh buildings | ✅ |
| `tests/run_phase1_tests.tscn`: 38 automated checks | ✅ |
| GitHub Actions: tests → Android debug APK (+ signed release when secrets exist) | ✅ |
| On-device tuning & 60 FPS on Helio G85 / SD680 | ⬜ **needs you + a phone** |

**Exit gate:** headless tests pass; throttle 4 s → ≥ 35 km/h; full steer at 30 km/h keeps roll < 22°; horn shifts AI within 18 m; steady 60 FPS on the budget test device.

### Phase 2 · Chennai world: 3 zones *(Weeks 3–4)*
**Goal:** a dense 2.5 km × 2.5 km connected loop that is recognisably Chennai.
- OSM → Blosm/Python pipeline producing 250 m chunks and `WorldChunkStreamer.gd` (3×3 threaded loading).
- **Zone 1 – Marina / Kamarajar Salai:** lighthouse, Napier Bridge, 6-lane coastal road.
- **Zone 2 – Mylapore Tank:** Kapaleeshwarar gopuram, narrow 2-lane tank streets, stray cattle.
- **Zone 3 – Anna Salai → T. Nagar:** LIC Building, Gemini Flyover, Panagal Park, heavy congestion.
- Road network via `godot-road-generator`; traffic lanes baked from it.
- Shared 2048² ETC2/ASTC texture atlases; `MultiMeshInstance3D` props; full traffic archetypes (MTC buses, two-wheelers, share autos, cattle/jaywalkers).

**Exit gate:** drive all three zones without hitches; ≤ 150 draw calls; RAM < 400 MB; 60 FPS on device.

### Phase 3 · Core loop: Savari & "Meter vs. Bargain" *(Weeks 4–5)*
**Goal:** the money-making loop works end to end.
- `PassengerArchetype.gd` resources: IT commuter, T. Nagar shopper (+45 kg), tourist, monsoon rider.
- Roadside hailing, Auto Stand spawns, pickup/drop zones, GPS route line and mini-map.
- 5-second Tanglish haggling card (Correct Meter / Meter Mela +₹30 / Fixed ₹200) with the acceptance matrix in data.
- Comfort tea-cup meter (lateral G, potholes, speed breakers), "Gap-la Gethu" near-miss combo.
- Fare breakdown screen; Respect XP; star rating.

**Exit gate:** 30-minute session of continuous rides with no crash; fare maths covered by tests.

### Phase 4 · Economy, garage & vehicles *(Week 5)*
**Goal:** progression from starter auto to the second auto.
- LPG/fuel use and pull-in LPG bunk; EV charge kiosks.
- Garage: repair, engine/suspension/tyre upgrades, paint, hood, stickers, horn tiers (bulb → twin → musical air-horn).
- 3 autos as `.tres`: Singara Classic, Madras King Deluxe (₹15,000), Namma Green EV.
- Encrypted local save (`FileAccess.open_encrypted_with_pass`, HMAC).
- Settings: 3 control schemes (wheel, arcade buttons, tilt), graphics presets, Tamil/English text.

**Exit gate:** a new player can earn and unlock Madras King Deluxe in ~30 min; save/load survives app kill.

### Phase 5 · Polish: weather, audio, UX → **MVP complete** *(Week 6)*
**Goal:** a build good enough to put in front of testers.
- Day/night cycle (Agni Nakshatram noon, Marina sunset, neon night) with headlights.
- Northeast Monsoon: rain shader, working wiper, waterlogged puddles, kick-start rhythm mini-game.
- Pitch-shifted 2-/4-stroke engine loops, EV whine, 5 horns, Tamil street ambience, UI SFX.
- First-launch onboarding (no forced parking tutorial), main menu, pause, credits/attributions.
- Performance pass on the budget device; size pass.

**MVP exit gate:** feature-complete loop; `.aab` < 85 MB; 60 FPS sustained 20 min without thermal drop below 45 FPS; zero known crashers.

---

## Part B — Play Store launch & beyond

### Phase 6 · Monetization & platform services *(Week 7)*
- `AdMonetizationManager.gd`: mediation (AppLovin MAX or CAS.AI + AdMob), rewarded 2× fare / fuel rescue / test-drive, interstitials capped (8-minute first-session grace, ≥ 180 s apart, ≤ 2 per 10 min, never blocking), native 3D billboards on Anna Salai/Usman Road.
- UMP consent (GDPR / India DPDP).
- Play Billing: `no_ads_forever` (₹99–149), `starter_pack_chennai` (₹29–49), garage bundle, zone unlocks, Madras Monsoon Pass (₹149/mo).
- Play Games Services v2: cloud save, achievements, leaderboards.
- Firebase Analytics, Crashlytics, Remote Config (ad caps and prices remote-tunable).

**Exit gate:** test ads fill in sandbox; UPI license-test purchase succeeds; ANR rate 0 % in internal testing.

### Phase 7 · Compliance & store readiness *(Week 7–8)*
- Target API level current for Play, 64-bit, signed `.aab`, Play App Signing.
- Data Safety form, privacy policy page, IARC rating, `app-ads.txt` on developer domain.
- Store listing in English + Tamil: icon, feature graphic, screenshots, 30-s trailer.
- Licence audit of every asset and plugin (CC0/CC-BY/MIT/Apache only) and credits screen.

**Exit gate:** listing and policy declarations approved for testing tracks.

### Phase 8 · Closed testing (Google Play 14-day rule) *(Weeks 8–10)*
- Internal track → Closed track with ≥ 12 opted-in testers for 14 continuous days (required for new personal developer accounts).
- Device matrix: Redmi, Realme, Samsung M/A series, at least one 3 GB device.
- Collect feedback in-app; fix-release weekly.

**Exit gate:** crash-free sessions ≥ 99.2 %; production access granted.

### Phase 9 · Soft launch & production release *(Weeks 10–12)*
- Soft launch in India, UAE, Singapore, Malaysia (diaspora eCPMs).
- Track D1 (target ≥ 32–35 %), D7, D30 (target ≥ 6 %), ARPDAU (target ~$0.015), session length.
- A/B test icons and store screenshots; tune haggling and ad caps via Remote Config.
- Staged rollout to production (10 % → 50 % → 100 %).

**Exit gate:** retention and crash targets met; 100 % rollout.

### Phase 10 · LiveOps & content updates *(Month 3+)*
- **1.1** – MGR Central, Kathipara cloverleaf, OMR IT corridor zones; Namma-Yatri-style dashboard app dispatch.
- **1.2** – 7-seater Share Auto mode (multiple passengers on a fixed route); traffic police challans.
- **1.3** – Madras Sticker & Livery Studio with custom `.png` import; weekly Auto Stand leaderboards (Nakama / Play Games).
- Seasonal events (Pongal, Deepavali, Monsoon Pass seasons); ASO for "auto rickshaw game", "Chennai game".

---

## 🎯 Next priorities

In order. Each one should land as its own PR with green CI.

1. **Install the CI APK on a budget phone (you).** Check FPS (add a Godot FPS overlay), steering feel, pedal reach and the handlebar drag range. Note any numbers that feel wrong; they live in `Bajaj_RE_4S.tres`. This closes Phase 1.
2. **Physics feel pass.** Grip currently limits turns to ~0.65 g, roll peaks around 7° and the Gethu tilt window is rarely reached. Tune grip, anti-roll strength and steer-vs-speed in the `.tres`, add a slow-speed U-turn radius test (target ≈ 2.4 m), and make 0–40 km/h take ~5–6 s instead of ~2 s.
3. **Engine & horn audio placeholders** (CC0 from Kenney/Sonniss): pitch-shifted engine loop by speed plus a horn sample. Cheap, and it makes device testing feel real.
4. **Phase 2 kickoff: OSM pipeline spike.** A Python script that pulls one 250 m chunk of Anna Salai from Overpass and writes a `.tscn` road + building blocks, then `WorldChunkStreamer.gd` with 3×3 threaded loading. Prove it on one chunk before importing all three zones.
5. **Performance harness.** A test scene that logs draw calls, physics time and memory to the CI summary so the 150-draw-call and 400 MB budgets are checked on every PR.
6. **Phase 3 prep:** passenger archetype `.tres` files and the haggling-card UI as a standalone scene with unit tests for acceptance odds.
7. **Play Store plumbing early (Phase 6/7 risk reducers):** switch CI to a Gradle build to produce an **AAB**, create the upload keystore and add it as secrets, and register the Play Console app so the 14-day closed-test clock can start as soon as the MVP is ready.

---

## ✅ Verification loop (every task)

1. `godot --headless --path . --import` then `--quit-after 120`: no `SCRIPT ERROR`.
2. `godot --headless --path . --fixed-fps 60 res://tests/run_phaseN_tests.tscn`: exit code 0.
3. **Android Build** workflow green on the PR.
4. MCP playtest when Godot MCP is connected (see `AGENTS.md` §4).

## 📏 Rules for contributors and agents

See [`AGENTS.md`](AGENTS.md). In short: communicate only through `SignalBus`, type everything, keep tunables in `.tres`, never fake 4-wheel physics, never `instantiate()`/`queue_free()` while driving, respect the 150-draw-call and 18-vehicle budgets, and don't hand-write `uid://` values.

## 📜 Licence & credits

Code licence: TBD. Third-party assets and plugins are listed with their licences in the in-game Credits screen. OpenStreetMap data © OpenStreetMap contributors (ODbL).
