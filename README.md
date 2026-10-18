# 🛺 Namma Auto: Chennai Rickshaw Simulator 3D

A culturally authentic auto-rickshaw driving and economy simulator set in Chennai, built in **Godot 4.x** for budget Android phones. The project is developed mostly by AI coding agents (Claude Code, Codex, Cursor) working under the rules in [`AGENTS.md`](AGENTS.md).

> **Pitch:** Drive a yellow-and-black Bajaj RE through Marina Beach, Mylapore and Anna Salai. Haggle fares in Tanglish ("Meter Podu vs. Bargain"), squeeze through gaps between MTC buses, survive the Northeast Monsoon, and build your Auto Stand reputation. Free Roam and Savari (passenger) mode are open from minute one, with no parking-gate grind.

---

## 📌 At a glance

| | |
|---|---|
| **Genre** | Open-zone driving + economy sim (hybrid-casual / mid-core) |
| **Platform** | Android (Google Play), ARM64 + ARMv7 |
| **Engine** | Godot 4.4+ / 4.6, Mobile or GL Compatibility renderer, Jolt Physics 3D |
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

The full target structure is defined in [`AGENTS.md` §2](AGENTS.md). Current contents:

```text
.
├── AGENTS.md                         # Agent constitution – read before every task
├── project.godot                     # Project config, InputMap, autoloads, Jolt
├── autoloads/
│   ├── SignalBus.gd                  # Global typed event bus
│   └── GameState.gd                  # Wallet (INR), Respect XP, shift state
├── scripts/vehicle/
│   └── AutoRickshawController.gd     # 3-wheel raycast suspension & anti-roll
├── deploy-phase1.yml
└── .github/workflows/deploy-phase1.yml
```

---

## 🚀 Getting started

```bash
git clone https://github.com/DavidRajPaul/Auto-Simulator-Game-GoDot.git
cd Auto-Simulator-Game-GoDot

# Import project & check for script/scene errors
godot --headless --path . --quit

# Run the phase test suite (once tests/ exists)
godot --headless --path . -s res://tests/run_phase1_tests.gd
```

Open in the Godot 4.4+ editor for interactive work. Android export needs the official export templates, Android SDK, and a debug keystore.

---

# 🗺️ Roadmap

The work is split into **MVP phases (1–5)**, which end in a feature-complete, closed-testable build, and **launch phases (6–10)**, which take that build through Google Play and into LiveOps. Every phase has an exit gate; an agent cannot start the next phase until the gate passes in CI.

Legend: ✅ done · 🟡 partly done · ⬜ not started

## Part A — MVP

### Phase 1 · Core greybox & 3-wheel physics 🟡 *(Weeks 1–2)*
**Goal:** the auto feels right to drive on a test strip, on a real budget phone.

| Item | Status |
|---|---|
| `AGENTS.md`, `project.godot` (InputMap, autoloads, Jolt, 60 Hz physics) | ✅ |
| `SignalBus.gd`, `GameState.gd` | ✅ |
| `AutoRickshawController.gd` – 3-point raycast suspension, anti-roll (> 18°), two-wheel "Gethu" tilt (12–18°), water stall + kick-start, passenger mass offset | ✅ (needs scene + tests to verify) |
| `data/vehicles/VehicleStats.gd` + `Bajaj_RE_4S.tres` | ⬜ |
| `CameraRig.gd` – Chase, Cockpit, Top-down | ⬜ |
| `ChennaiTrafficManager.gd` + `TrafficVehicleAI.gd` – pooled (≤ 18 within 120 m), 3 sub-lanes, horn lane-shift | ⬜ |
| `TouchHUD.gd` + `touch_hud.tscn` – virtual handlebar, pedals, horn, meter, wiper | ⬜ |
| `scenes/vehicles/auto_rickshaw.tscn`, `scenes/main_phase1_greybox.tscn` (Anna Salai strip) | ⬜ |
| `tests/run_phase1_tests.gd` + CI running it headless | ⬜ |
| First debug APK on a test phone | ⬜ |

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

## ✅ Verification loop (every task)

1. `godot --headless --path . --quit` – no script or scene load errors.
2. `godot --headless --path . -s res://tests/run_phaseN_tests.gd` – current phase suite passes.
3. MCP playtest when Godot MCP is connected (see `AGENTS.md` §4).

## 📏 Rules for contributors and agents

See [`AGENTS.md`](AGENTS.md). In short: communicate only through `SignalBus`, type everything, keep tunables in `.tres`, never fake 4-wheel physics, never `instantiate()`/`queue_free()` while driving, respect the 150-draw-call and 18-vehicle budgets, and don't hand-write `uid://` values.

## 📜 Licence & credits

Code licence: TBD. Third-party assets and plugins are listed with their licences in the in-game Credits screen. OpenStreetMap data © OpenStreetMap contributors (ODbL).
