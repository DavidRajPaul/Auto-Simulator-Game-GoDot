# AGENTS.md — AI Agent Repository Constitution
# Project: Namma Auto: Chennai Rickshaw Simulator 3D (Godot 4.x)

## 1. Mission & Project Identity
You are an autonomous AI game engineering agent building **Namma Auto: Chennai Rickshaw Simulator 3D**, a culturally authentic, 60 FPS Android driving and auto-rickshaw economic simulator set in Chennai, Tamil Nadu, India.

* **Target Engine:** Godot Engine 4.4+ / 4.6 Stable (`gl_compatibility` / `mobile` Vulkan renderer, **Jolt Physics 3D**).
* **Primary Language:** Statically-typed **GDScript 2.0** (strict typing enforced on all variables, parameters, and return types).
* **Target Hardware Baseline:** Budget Indian Android smartphones (MediaTek Helio G85 / Snapdragon 680, 3 GB–4 GB RAM, OpenGL ES 3.0 / Vulkan 1.1, 60 FPS target, <85 MB initial `.aab` size).

## 2. Directory & File Architecture
Maintain this exact repository structure across all phases:
- `AGENTS.md` — Repository constitution
- `project.godot` — Godot 4 project config, InputMap, Autoloads, Mobile renderer
- `autoloads/SignalBus.gd` — Global typed event bus (no cross-scene get_node calls)
- `autoloads/GameState.gd` — Player wallet (INR), Respect XP, current shift
- `data/vehicles/VehicleStats.gd` & `Bajaj_RE_4S.tres` — Custom Resource definitions
- `scenes/main_phase1_greybox.tscn` — Phase 1 playable Anna Salai greybox test arena
- `scenes/vehicles/auto_rickshaw.tscn` — Player 3-wheel raycast delta-trike prefab
- `scripts/vehicle/AutoRickshawController.gd` — 3-point raycast suspension, delta-trike steering, monsoon stall/kickstart
- `scripts/traffic/ChennaiTrafficManager.gd` — 3-sub-lane object-pooled traffic & horn reaction system
- `tests/run_phase1_tests.gd` — Headless CLI verification suite

## 3. Non-Negotiable Architectural Rules for AI Agents
1. **Strict Decoupling via `SignalBus.gd`:** Never use brittle cross-scene `get_node()` paths; emit and connect typed signals through `SignalBus`.
2. **100% Static Typing in GDScript:** Every variable, parameter, and return value must have explicit type annotations.
3. **Plain-Text Scene & Resource Hygiene (`.tscn` / `.tres`):** Never invent fake UIDs; keep tunable numbers in `.tres` resources.
4. **Delta-Trike (3-Wheel) Physics Fidelity:** 1 front center steerable wheel (`max_steer_angle = 44°`) and 2 rear drive wheels with rear-biased center of mass (`Vector3(0, -0.26, 0.32)`).
5. **Mobile Performance Guardrails:** Max 150 draw calls/frame, max 18 pooled AI traffic vehicles within 120m, 60 Hz physics tick.

## 4. Closed-Loop CLI Verification Protocol
Run before completing any task:
- `godot --headless --path . --quit`
- `godot --headless --path . -s res://tests/run_phase1_tests.gd`
