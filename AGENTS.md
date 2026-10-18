# AGENTS.md — AI Agent Repository Constitution
# Project: Namma Auto: Chennai Rickshaw Simulator 3D (Godot 4.x)
# Repository: https://github.com/DavidRajPaul/Auto-Simulator-Game-GoDot

## 1. Mission & Project Identity
You are an autonomous AI game engineering agent building **Namma Auto: Chennai Rickshaw Simulator 3D**, a culturally authentic, 60 FPS Android driving and auto-rickshaw economic simulator set in Chennai, Tamil Nadu, India.

* **Target Platform:** **Android only** (Google Play). Do not add iOS, desktop or web export presets, plugins or code paths.
* **Target Engine:** Godot Engine **4.4.1** (pinned in CI), `mobile` renderer with OpenGL ES 3 fallback, **Jolt Physics 3D**.
* **Primary Language:** Statically-typed **GDScript 2.0** (strict typing enforced on all variables, parameters, and return types).
* **Target Hardware Baseline:** Budget Indian Android smartphones (MediaTek Helio G85 / Snapdragon 680, 3 GB–4 GB RAM, OpenGL ES 3.0 / Vulkan 1.1, 60 FPS target, <85 MB initial download).

---

## 2. Directory & File Architecture
Maintain this structure across all phases. Never place loose scripts or scenes in the project root.

```text
res://
├── AGENTS.md                        # This constitution (read before every task)
├── README.md                        # Roadmap (Phases 1–10) and status — keep it current
├── project.godot                    # Project config, InputMap, Autoloads, Jolt Physics
├── export_presets.cfg               # Android preset (arm64-v8a + armeabi-v7a)
├── .github/workflows/android-build.yml  # CI: headless tests → Android APK artifact
├── autoloads/
│   ├── SignalBus.gd                 # Global typed event bus (ZERO direct cross-scene get_node calls)
│   ├── GameState.gd                 # Wallet (INR), Respect XP, shift state, meter fare maths
│   └── AdMonetizationManager.gd     # (Phase 6) Mediated ads, cooldowns & rewarded hooks
├── data/
│   ├── vehicles/
│   │   ├── VehicleStats.gd          # Custom Resource class_name VehicleStats
│   │   ├── Bajaj_RE_4S.tres         # Starter "Singara Classic"
│   │   ├── Madras_King_Deluxe.tres  # (Phase 4) Mid-tier auto
│   │   └── Namma_Green_EV.tres      # (Phase 4) Electric auto
│   └── passengers/
│       └── PassengerArchetype.gd    # Haggling & comfort tolerance
├── scenes/
│   ├── main_phase1_greybox.tscn     # Phase 1 Anna Salai test strip
│   ├── vehicles/auto_rickshaw.tscn  # Player 3-wheel raycast delta-trike prefab
│   ├── traffic/ai_traffic_vehicle.tscn  # Pooled AI traffic vehicle prefab
│   └── ui/touch_hud.tscn            # Mobile touch controls & dashboard
├── scripts/
│   ├── vehicle/
│   │   ├── AutoRickshawController.gd
│   │   └── CameraRig.gd
│   ├── traffic/
│   │   ├── ChennaiTrafficManager.gd
│   │   └── TrafficVehicleAI.gd
│   ├── world/
│   │   ├── WaterlogZone.gd          # Monsoon puddle → SignalBus.water_depth_changed
│   │   └── GreyboxDressing.gd       # MultiMesh lane dashes & placeholder buildings
│   └── ui/
│       └── TouchHUD.gd
└── tests/
    ├── run_phase1_tests.gd          # Headless verification suite (Node script)
    └── run_phase1_tests.tscn        # Runner scene — run as a scene, NOT with `-s`
```

---

## 3. Non-Negotiable Architectural Rules for AI Agents

### Rule 1: Strict Decoupling via `SignalBus.gd`
* **FORBIDDEN:** brittle cross-subsystem paths such as `get_node("../../UI/TouchHUD/Speedometer")`.
* **REQUIRED:** emit and connect typed signals through `SignalBus` (e.g. `SignalBus.speed_updated.emit(kmh)`, `SignalBus.horn_blasted.emit(pos, fwd, radius, tier)`).
* **Input:** touch controls press InputMap actions (`Input.action_press`). Gameplay code reads actions only, so keyboard, touch and tests drive the game identically.

### Rule 2: 100% Static Typing in GDScript
* Every variable, array, dictionary, argument and return value has an explicit type. `untyped_declaration` is set to **Error** in `project.godot`.

### Rule 3: Plain-Text Scene & Resource Hygiene (`.tscn` / `.tres`)
* Never invent `uid://` values when hand-writing `.tscn`/`.tres`; omit `uid=` and let Godot assign. Commit the generated `*.uid` and `*.import` files.
* All tunable gameplay numbers live in `.tres` resources, never in physics code.

### Rule 4: Delta-Trike (3-Wheel) Physics Fidelity
* Never use a 4-wheel template. **1 front centre steerable wheel** (`max_steer_angle_deg = 45.0`) and **2 rear drive wheels**, rear-biased `center_of_mass_offset = Vector3(0.0, -0.25, 0.35)`.
* 3-point `RayCast3D` suspension with anti-roll stabilisation; `12°–18°` roll on two wheels = **"Two-Wheel Side-Tilt Gethu"**.

### Rule 5: Mobile Performance Guardrails
* ≤ **150 draw calls** per frame; shared materials, ETC2/ASTC, `MultiMeshInstance3D` for static props.
* ≤ **18 pooled AI vehicles** within **120 m** of the player. Never `instantiate()`/`queue_free()` during driving frames.
* Physics at a fixed **60 Hz**. Primitive colliders (`BoxShape3D`, `CapsuleShape3D`) on moving bodies.

### Lessons recorded (do not regress)
* Pooled `AnimatableBody3D` traffic must be teleported with its collision shape **disabled** and re-enabled the next tick. Teleporting with collision on made Jolt launch the player auto at ~260 m/s.
* Apply longitudinal (drive/brake) wheel forces at **CoM height**; at contact height the trike wheelies.
* Wheel rays start **below** the chassis origin so the CoM offset sits ~0.55 m above the road; otherwise the auto can never lean.

---

## 4. Closed-Loop Verification Protocol (Run After Every Task)
1. **Import & scene load check:**
   ```bash
   godot --headless --path . --import
   godot --headless --path . --quit-after 120   # must print no SCRIPT ERROR
   ```
2. **Phase test suite** (exit code 0 = pass):
   ```bash
   godot --headless --path . --fixed-fps 60 res://tests/run_phase1_tests.tscn
   ```
   Do not use `-s` — autoload globals (`SignalBus`, `GameState`) don't resolve in `-s` scripts. Each new phase adds `tests/run_phaseN_tests.tscn` and a CI step.
3. **CI:** the **Android Build** workflow (tests + APK export) must be green before a milestone is marked done.
4. **MCP interactive playtest** (when Godot MCP is connected): throttle 4 s → ≥ 35 km/h; full steer at 30 km/h → roll < 22°; horn → AI within 18 m shift sub-lane.

---

## 5. Phase Status
Full roadmap with exit gates: `README.md` → Roadmap.
* **Phase 1 — Core greybox & 3-wheel physics:** code complete, 38/38 headless tests, CI APK build. Remaining exit gate: on-device feel tuning and 60 FPS on a budget phone.
* **Phase 2 — Chennai 3-zone world:** next.
