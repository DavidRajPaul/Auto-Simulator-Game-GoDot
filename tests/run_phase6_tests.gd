extends Node
## Phase 6 (controls, building skins, driver levels) verification.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase6_tests.tscn

const GREYBOX: String = "res://scenes/main_phase1_greybox.tscn"
const CITY: String = "res://scenes/main_chennai.tscn"
const TEST_SAVE: String = "user://test_phase6_save.dat"

var _passed: int = 0
var _failed: int = 0
var _events: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 6 tests ===")
	for sig: String in ["gear_changed", "gear_change_refused", "indicator_changed", "indicator_blink", "signalled_turn",
			"brake_lights_changed", "driver_level_up", "goal_completed", "all_goals_completed"]:
		var n: String = sig
		SignalBus.connect(sig, func(a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
			_events[n] = a if a != null else true)
	GameState.reset_profile()
	_test_level_maths()
	_test_level_ups_and_gates()
	_test_goals()
	_test_progress_save()

	GameState.reset_profile()
	var main: Node = (load(GREYBOX) as PackedScene).instantiate()
	add_child(main)
	var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
	var hud: TouchHUD = main.get_node("TouchHUD") as TouchHUD
	await _physics(60)
	await _test_gears(auto, hud)
	await _test_auto_reverse(auto)
	await _test_indicators(auto, hud)
	await _test_give_way(main)
	_test_contextual_buttons(hud)
	await _test_touch_controls(hud)
	_test_player_model(auto)
	main.queue_free()
	await _physics(2)

	var city: Node = (load(CITY) as PackedScene).instantiate()
	add_child(city)
	await _physics(30)
	_test_facades(city.get_node("World") as WorldChunkStreamer)
	await _test_sounds(city)
	city.queue_free()
	await _physics(2)

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Driver levels & goals ---------------------------------------------------------------------

func _test_level_maths() -> void:
	_check("Lv 1 at 0 XP, Lv 2 at 100, Lv 5 at 1000", DriverProgress.level_for_xp(0) == 1 and DriverProgress.level_for_xp(100) == 2
		and DriverProgress.level_for_xp(99) == 1 and DriverProgress.level_for_xp(1000) == 5)
	_check("Level cap is 20 (Madras Legend)", DriverProgress.level_for_xp(10_000_000) == 20 and DriverProgress.title(20) == "Madras Legend")
	var smooth: int = DriverProgress.ride_xp({"comfort": 1.0, "on_time": true, "offer": 0, "near_misses": 2})
	var rough: int = DriverProgress.ride_xp({"comfort": 0.2, "on_time": false, "offer": 2, "near_misses": 0})
	_check("Smooth, on-time, honest rides earn more XP", smooth == 42 and rough == 22, "%d vs %d" % [smooth, rough])
	_check("Lv 2 takes ~4 rides, Lv 5 ~30 rides", 100.0 / 30.0 < 5.0 and 1000.0 / 30.0 < 40.0)

func _test_level_ups_and_gates() -> void:
	GameState.reset_profile()
	GameState.wallet_inr = 10000
	_check("Green EV is locked at Lv 1, even with the money", not GameState.buy_vehicle("namma_green_ev") and GameState.wallet_inr == 10000)
	_check("King Deluxe is never level-gated", GameState.is_unlocked("vehicle:madras_king_deluxe"))
	var w: int = GameState.wallet_inr
	_events.erase("driver_level_up")
	GameState.add_driver_xp(1000)
	_check("Reaching Lv 5 announces the level-up", _events.get("driver_level_up", 0) == 5 and GameState.driver_level() == 5)
	_check("Every level crossed pays its bonus (₹100+150+200+250)", GameState.wallet_inr == w + 700, "₹%d" % (GameState.wallet_inr - w))
	_check("Lv 5 unlocks the EV in the garage", GameState.buy_vehicle("namma_green_ev"))
	_check("Musical air-horn needs Lv 4 (now unlocked)", GameState.is_unlocked("horn:2") and not GameState.is_unlocked("paint:4"))
	GameState.reset_profile()

func _test_goals() -> void:
	var a: DriverProgress = DriverProgress.new()
	a.roll_goals(3)
	var b: DriverProgress = DriverProgress.new()
	b.roll_goals(3)
	var kinds: Dictionary = {}
	for g: Dictionary in a.goals:
		kinds[g["kind"]] = true
	_check("3 distinct shift goals per day", a.goals.size() == 3 and kinds.size() == 3)
	_check("Goals are the same for everyone on a given day", str(a.goals) == str(b.goals))
	GameState.reset_profile()
	GameState.progress.goals = [
		{"kind": "rides", "text": "GOAL_RIDES", "target": 2, "progress": 0, "done": false},
		{"kind": "meter", "text": "GOAL_METER", "target": 1, "progress": 0, "done": false},
		{"kind": "signal", "text": "GOAL_SIGNAL", "target": 1, "progress": 0, "done": false},
	]
	var w: int = GameState.wallet_inr
	_events.erase("goal_completed")
	_events.erase("all_goals_completed")
	SignalBus.ride_completed.emit({"total": 60, "comfort": 0.9, "on_time": true, "offer": 0, "near_misses": 0})
	_check("A Correct Meter ride completes the meter goal", _events.has("goal_completed") and bool(GameState.progress.goals[1]["done"]))
	SignalBus.ride_completed.emit({"total": 60, "comfort": 0.9, "on_time": true, "offer": 1, "near_misses": 0})
	SignalBus.signalled_turn.emit(1)
	_check("All 3 goals done pays the shift bonus", _events.has("all_goals_completed") and GameState.progress.all_goals_done())
	_check("Goal rewards land in the wallet (3 × ₹40 + ₹100)", GameState.wallet_inr - w >= 3 * DriverProgress.GOAL_INR + DriverProgress.ALL_GOALS_BONUS_INR, "+₹%d" % (GameState.wallet_inr - w))
	_check("Pause-menu goal text formats", PassengerHUD.goal_text(GameState.progress.goals[0]).contains("2"))
	GameState.reset_profile()

func _test_progress_save() -> void:
	GameState.reset_profile()
	GameState.persistence_enabled = true
	GameState.save_path = TEST_SAVE
	GameState.add_driver_xp(350)
	GameState.progress.goals[0]["progress"] = 1
	GameState.save_game()
	GameState.reset_profile()
	_check("Driver XP and goal progress survive save/load", GameState.load_game() and GameState.progress.xp == 350 and int(GameState.progress.goals[0]["progress"]) == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	GameState.persistence_enabled = false
	GameState.save_path = GameState.SAVE_PATH
	GameState.reset_profile()

# --- Controls ----------------------------------------------------------------------------------

func _test_gears(auto: AutoRickshawController, hud: TouchHUD) -> void:
	GameState.settings["auto_reverse"] = false
	Input.action_press("accelerate")
	await _physics(120)
	Input.action_release("accelerate")
	_events.erase("gear_change_refused")
	_check("Can't shift to R while moving", not auto.set_gear(AutoRickshawController.GEAR_REVERSE) and _events.has("gear_change_refused"))
	await _stop(auto)
	Input.action_press("gear_toggle")
	await _physics(2) # physics_frame fires before nodes' _physics_process
	Input.action_release("gear_toggle")
	_check("Gear button shifts to R at a standstill", auto.gear == -1 and _events.get("gear_changed", 0) == -1 and hud.gear == -1)
	Input.action_press("accelerate")
	await _physics(150)
	var back_speed: float = auto.forward_speed_mps * 3.6
	Input.action_release("accelerate")
	_check("In R, ACCEL drives backwards (within reverse limit)", back_speed < -5.0 and -back_speed <= auto.stats.reverse_max_speed_kmh + 2.0, "%.1f km/h" % back_speed)
	Input.action_press("brake")
	await _physics(20)
	_check("Brake lights on while braking", auto.is_braking and (auto.get_node("BrakeLamps") as MeshInstance3D).visible)
	await _physics(100)
	Input.action_release("brake")
	_check("BRAKE stops the auto in reverse too", auto.current_speed_kmh < 1.5, "%.1f km/h" % auto.current_speed_kmh)
	auto.set_gear(AutoRickshawController.GEAR_DRIVE)
	await _physics(2)
	_check("Back in D", auto.gear == 1 and hud.gear == 1)

func _test_auto_reverse(auto: AutoRickshawController) -> void:
	await _stop(auto)
	GameState.settings["auto_reverse"] = false
	Input.action_press("brake")
	await _physics(90)
	Input.action_release("brake")
	_check("Auto-reverse OFF: holding BRAKE stays in D", auto.gear == 1 and auto.forward_speed_mps > -0.5)
	GameState.settings["auto_reverse"] = true
	Input.action_press("brake")
	await _physics(150)
	var v: float = auto.forward_speed_mps * 3.6
	Input.action_release("brake")
	_check("Auto-reverse ON: hold BRAKE at a stop → R, rolls back", auto.gear == -1 and v < -2.0, "%.1f km/h" % v)
	Input.action_press("accelerate")
	await _physics(90)
	Input.action_release("accelerate")
	_check("…then ACCEL stops it and returns to D", auto.gear == 1, "gear %d" % auto.gear)
	await _stop(auto)

func _test_indicators(auto: AutoRickshawController, hud: TouchHUD) -> void:
	Input.action_press("indicator_left")
	await _physics(2) # physics_frame fires before nodes' _physics_process
	Input.action_release("indicator_left")
	_check("Left indicator on", auto.indicator == -1 and hud.indicator == -1)
	var lamp: MeshInstance3D = auto.get_node("IndicatorLeft") as MeshInstance3D
	var seen_on: bool = false
	var seen_off: bool = false
	var blinks: int = 0
	_events.erase("indicator_blink")
	for i: int in 90:
		await get_tree().physics_frame
		seen_on = seen_on or lamp.visible
		seen_off = seen_off or not lamp.visible
		if _events.has("indicator_blink"):
			blinks += 1
			_events.erase("indicator_blink")
	_check("Indicator lamp blinks (~1.5 Hz) with ticks", seen_on and seen_off and blinks >= 2, "%d ticks in 1.5 s" % blinks)
	_check("Right lamp stays dark", not (auto.get_node("IndicatorRight") as MeshInstance3D).visible)
	Input.action_press("indicator_left")
	await _physics(2) # physics_frame fires before nodes' _physics_process
	Input.action_release("indicator_left")
	_check("Pressing again cancels it", auto.indicator == 0)
	# Signal right, make a right turn, straighten: self-cancels and earns respect.
	var respect: int = GameState.stand_respect_xp
	_events.erase("signalled_turn")
	auto.set_indicator(1)
	Input.action_press("accelerate", 0.6)
	Input.action_press("steer_right", 1.0)
	for i: int in 240:
		await get_tree().physics_frame
		if _events.has("signalled_turn"):
			break
	Input.action_release("steer_right")
	await _physics(60)
	Input.action_release("accelerate")
	_check("Turning the signalled way counts as a signalled turn", _events.get("signalled_turn", 0) == 1)
	_check("…+2 Respect", GameState.stand_respect_xp == respect + GameState.SIGNAL_RESPECT_XP, "%d → %d" % [respect, GameState.stand_respect_xp])
	_check("Indicator self-cancels after the turn", auto.indicator == 0)
	await _stop(auto)

func _test_give_way(main: Node) -> void:
	var traffic: ChennaiTrafficManager = main.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var v: TrafficVehicleAI = null
	for t: TrafficVehicleAI in traffic.pool:
		if t.active and t.archetype == TrafficVehicleAI.Archetype.HATCHBACK:
			v = t
			break
	if v == null:
		_check("A hatchback is available to test give-way", false)
		return
	var before: float = v.cruise_speed_mps
	v.give_way(2.0)
	for i: int in 60:
		v.tick(1.0 / 60.0)
	_check("Traffic eases off to let an indicating auto in", v.current_speed_mps < before * 0.7, "%.1f → %.1f m/s" % [before, v.current_speed_mps])

func _test_contextual_buttons(hud: TouchHUD) -> void:
	var kick: Dictionary = hud._buttons["KickStart"]
	_check("KICK button hidden until the engine floods", not (kick["panel"] as Panel).visible)
	SignalBus.engine_stalled_in_water.emit(Vector3.ZERO)
	_check("…shown when it floods", (kick["panel"] as Panel).visible)
	SignalBus.engine_restarted.emit()
	_check("…hidden again once restarted", not (kick["panel"] as Panel).visible)
	GameState.set_rain(false)
	hud._refresh_wiper_visibility()
	_check("Wiper button only in rain", not (hud._buttons["Wiper"]["panel"] as Panel).visible)
	GameState.set_rain(true, 60.0)
	_check("…appears when it rains", (hud._buttons["Wiper"]["panel"] as Panel).visible)
	GameState.set_rain(false)
	for n: String in ["Accelerate", "Brake", "Gear", "Horn", "IndicatorLeft", "IndicatorRight", "Handbrake"]:
		if hud._buttons[n]["icon"] == null:
			_check("%s has an icon" % n, false)
			return
	_check("All driving buttons use the icon atlas", true)

# --- Touch controls v2 / models ------------------------------------------------------------------

func _touch(hud: TouchHUD, index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	hud._input(e)

func _drag(hud: TouchHUD, index: int, pos: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	hud._input(e)

func _centre(hud: TouchHUD, button_name: String) -> Vector2:
	var p: Panel = hud._buttons[button_name]["panel"] as Panel
	return p.position + p.size * 0.5

func _test_touch_controls(hud: TouchHUD) -> void:
	_check("Steer buttons are the default controls", GameState.settings["control_scheme"] == 1 and hud.control_scheme == 1)
	var gas: Vector2 = _centre(hud, "Accelerate")
	_touch(hud, 0, gas, true)
	_check("Gas acts on touch-down (no wait for release)", Input.is_action_pressed("accelerate"))
	var gas_icon: TextureRect = hud._buttons["Accelerate"]["icon"] as TextureRect
	_check("Painted dials, needles and meter flag are in use (drawn dashboard hidden)", hud._speed_needle != null and hud._meter != null and not hud._dash.visible)
	SignalBus.telemetry_updated.emit({"speed_kmh": 40.0, "lpg_liters": 1.0, "lpg_capacity": 1.0})
	_check("Speed needle points straight up at 40 km/h (half of the 80 dial)", absf(hud._speed_needle.rotation) < 0.01, "%.3f rad" % hud._speed_needle.rotation)
	hud._flash("test", 1.0, TouchHUD.Tone.WARN)
	_check("Warnings show on the red ribbon", hud._banner.visible and hud._banner.texture == hud._hud("banner_red"))
	_check("Painted game art drives the buttons (pressed pedal art while held)", hud._buttons["Accelerate"].has("art")
		and (gas_icon.texture as AtlasTexture).atlas.resource_path == TouchHUD.ART_ATLAS and gas_icon.texture == hud._art("gas_p"))
	_drag(hud, 0, _centre(hud, "Brake"))
	_check("Sliding gas → brake swaps pedals without lifting", Input.is_action_pressed("brake") and not Input.is_action_pressed("accelerate"))
	_touch(hud, 0, _centre(hud, "Brake"), false)
	_check("Lifting releases the pedal", not Input.is_action_pressed("brake"))
	var sl: Panel = hud._buttons["SteerLeft"]["panel"] as Panel
	var near_edge: Vector2 = Vector2(sl.position.x - TouchHUD.HIT_PAD * 0.5, sl.position.y + sl.size.y * 0.5)
	_check("Padded hit area: a thumb just outside the button still steers", hud.button_at(near_edge) == "SteerLeft")
	_touch(hud, 1, _centre(hud, "SteerLeft"), true)
	_touch(hud, 2, gas, true)
	_check("Steer + gas together (multitouch)", Input.is_action_pressed("steer_left") and Input.is_action_pressed("accelerate"))
	_drag(hud, 1, _centre(hud, "SteerRight"))
	_check("Thumb slides from left to right", Input.is_action_pressed("steer_right") and not Input.is_action_pressed("steer_left"))
	hud.release_all()
	await _physics(4)
	var modes: Array[String] = []
	var on_mode: Callable = func(m: String) -> void: modes.append(m)
	SignalBus.camera_mode_changed.connect(on_mode)
	_touch(hud, 3, _centre(hud, "Camera"), true)
	_touch(hud, 3, _centre(hud, "Camera"), false)
	_check("A same-frame tap still registers (held a few frames)", Input.is_action_pressed("camera_cycle"))
	await _physics(5)
	_check("…and is released afterwards", not Input.is_action_pressed("camera_cycle"))
	_check("Camera button switches the camera mode", modes.size() == 1, "%d changes" % modes.size())
	SignalBus.camera_mode_changed.disconnect(on_mode)
	for i: int in 3:
		_touch(hud, 3, _centre(hud, "Camera"), true)
		_touch(hud, 3, _centre(hud, "Camera"), false)
		await _physics(5) # back to chase
	_check("release_all lets go of every control", not Input.is_action_pressed("steer_right") and not Input.is_action_pressed("accelerate"))
	await _physics(2)

func _test_player_model(auto: AutoRickshawController) -> void:
	var model: AutoRickshawModel = auto.get_node("Model") as AutoRickshawModel
	_check("Player auto uses the real Chennai auto model in stock yellow", model.uses_real_model and model.real_body != null and not model.body_mesh.visible)
	_check("…and hides the procedural wheels (the model has its own)", not (auto.get_node("FrontWheelMesh") as Node3D).visible)
	_check("Traffic models face their direction of travel (glTF +Z files are turned)",
		TrafficVehicleAI.MODEL_FLIP == [false, true, true, true, true, true] and TrafficVehicleAI.COW_FLIP == [true, true] and TrafficVehicleAI.BUS_FLIP)

# --- Building skins ----------------------------------------------------------------------------

func _test_facades(world: WorldChunkStreamer) -> void:
	var tex: Texture2D = load("res://assets/textures/facade_atlas.png") as Texture2D
	_check("Facade atlas imported (1024×512)", tex != null and tex.get_width() == 1024 and tex.get_height() == 512)
	var uv2_ok: int = 0
	var shaded: int = 0
	for k: Vector2i in world.loaded:
		var mi: MeshInstance3D = (world.loaded[k] as Node3D).get_node_or_null("Buildings/BuildingMeshes") as MeshInstance3D
		if mi == null:
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		if arr[Mesh.ARRAY_TEX_UV2] != null and (arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() == (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			uv2_ok += 1
		if mi.mesh.surface_get_material(0) is ShaderMaterial:
			shaded += 1
	_check("Building meshes carry facade UVs + atlas cells", uv2_ok >= 4, "%d chunks" % uv2_ok)
	_check("Buildings use the facade shader", shaded >= 4)
	var temple: Dictionary = WorldChunkStreamer.facade_skin("temple", "mylapore", 6.0, 1)
	var shop: Dictionary = WorldChunkStreamer.facade_skin("shop", "t_nagar", 9.0, 2)
	_check("Temples get kaavi stripes, shops get a board per bay", temple["upper"][0] == Vector2(0, 3) and bool(shop["per_bay"]) and (shop["ground"] as Array).size() >= 10)

# --- Sounds -----------------------------------------------------------------------------------

func _test_sounds(city: Node) -> void:
	var sfx: UISfx = city.get_node("UISfx") as UISfx
	var b: Button = Button.new()
	add_child(b)
	await get_tree().process_frame
	sfx.last_played = ""
	b.pressed.emit()
	_check("Every button clicks (Kenney UI sound)", sfx.last_played == "click")
	b.queue_free()
	SignalBus.ride_completed.emit({"total": 0, "fare": 0, "comfort_tip": 0, "gethu_bonus": 0, "stars": 3.0, "comfort": 0.0,
		"on_time": false, "offer": 2, "near_misses": 0, "destination": "Test", "archetype_name": "Test", "line": ""})
	_check("Fare paid plays the coin sound", sfx.last_played == "coin")
	var amb: AmbienceAudio = city.get_node("AmbienceAudio") as AmbienceAudio
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/manifest.json")) as Dictionary
	var marina: Dictionary = {}
	for z: Dictionary in m["zones"]:
		if str(z["id"]) == "marina":
			marina = z
	SignalBus.player_pose_updated.emit(Vector3(float(marina["x"]), 0.0, float(marina["z"])), Vector3.FORWARD)
	var t: Dictionary = amb.targets()
	_check("Sea ambience swells at Marina, market fades", float(t["sea"]) > 0.8 and float(t["market"]) < float(t["sea"]), str(t))
	GameState.set_rain(true, 30.0)
	_check("Rain loop target follows the weather", float(amb.targets()["rain"]) == 1.0)
	GameState.set_rain(false)

# --- Helpers -----------------------------------------------------------------------------------

func _stop(auto: AutoRickshawController) -> void:
	Input.action_release("accelerate")
	var auto_rev: bool = bool(GameState.settings.get("auto_reverse", true))
	GameState.settings["auto_reverse"] = false
	Input.action_press("brake")
	for i: int in 300:
		await get_tree().physics_frame
		if auto.current_speed_kmh < 0.5:
			break
	Input.action_release("brake")
	await _physics(5)
	GameState.settings["auto_reverse"] = auto_rev

func _physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", test_name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_failed += 1
		printerr("  FAIL  ", test_name, ("  (" + detail + ")") if detail != "" else "")
