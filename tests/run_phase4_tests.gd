extends Node
## Phase 4 verification: garage economy, vehicles, fuel, condition, save/load, shift clock,
## settings, and the "unlock the 2nd auto in ~30 min" exit gate.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase4_tests.tscn

const MAIN_SCENE: String = "res://scenes/main_chennai.tscn"
const TEST_SAVE: String = "user://test_phase4_save.dat"

var _passed: int = 0
var _failed: int = 0
var _events: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 4 tests ===")
	for sig: String in ["service_available", "shift_ended", "vehicle_loadout_changed", "teleport_requested"]:
		var n: String = sig
		SignalBus.connect(sig, func(a: Variant = null, _b: Variant = null) -> void: _events[n] = a)
	GameState.reset_profile()
	_test_catalogue()
	_test_effective_stats()
	_test_purchases()
	_test_economy_exit_gate()
	_test_save_load()

	GameState.reset_profile()
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
	var services: ServicePoints = main.get_node("ServicePoints") as ServicePoints
	var ui: GarageUI = main.get_node("GarageUI") as GarageUI
	var hud: TouchHUD = main.get_node("TouchHUD") as TouchHUD
	await _physics(60)
	await _test_live_vehicle_swap(auto)
	await _test_fuel_and_services(auto, services, ui)
	_test_mylapore_workshop(services)
	await _test_condition(auto)
	await _test_shift_clock()
	await _test_settings(main, hud)
	await _test_garage_pause(ui)

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Data & maths ----------------------------------------------------------------------

func _test_catalogue() -> void:
	var s: VehicleStats = GameState.base_stats("singara_classic")
	var k: VehicleStats = GameState.base_stats("madras_king_deluxe")
	var e: VehicleStats = GameState.base_stats("namma_green_ev")
	_check("3 autos in the catalogue", s != null and k != null and e != null)
	_check("Prices rise Singara < King < EV", s.price_inr == 0 and k.price_inr > 0 and e.price_inr > k.price_inr, "₹%d / ₹%d" % [k.price_inr, e.price_inr])
	_check("King Deluxe: 72 km/h, shocks halve discomfort", is_equal_approx(k.max_speed_kmh, 72.0) and is_equal_approx(k.comfort_damping, 0.5))
	_check("Green EV: electric, instant torque, +25% green tip", e.fuel_type == 2 and e.torque_falloff < 0.2 and is_equal_approx(e.green_tip_bonus, 0.25))
	_check("Starter has the stock bulb horn (tier 0)", s.horn_tier == 0)

func _test_effective_stats() -> void:
	GameState.reset_profile()
	var base: VehicleStats = GameState.base_stats("singara_classic")
	GameState.upgrades = {"singara_classic": {"engine": 2, "suspension": 1, "tyres": 3}}
	var eff: VehicleStats = GameState.active_stats()
	_check("Engine lvl 2: +14% pull, +6 km/h", is_equal_approx(eff.engine_peak_force_n, base.engine_peak_force_n * 1.14) and is_equal_approx(eff.max_speed_kmh, base.max_speed_kmh + 6.0))
	_check("Tyres lvl 3: +18% grip", is_equal_approx(eff.rear_lateral_grip, base.rear_lateral_grip * 1.18))
	_check("Suspension lvl 1: −15% jolts", is_equal_approx(eff.comfort_damping, 0.85))
	_check("Effective stats never mutate the .tres", is_equal_approx(GameState.base_stats("singara_classic").max_speed_kmh, base.max_speed_kmh))
	GameState.condition = 30.0
	_check("Worn-out auto (< 40%) loses top speed", GameState.active_stats().max_speed_kmh < eff.max_speed_kmh)
	GameState.reset_profile()

func _test_purchases() -> void:
	GameState.reset_profile()
	_check("Can't buy King Deluxe with ₹500", not GameState.buy_vehicle("madras_king_deluxe") and GameState.wallet_inr == 500)
	GameState.add_inr(2000)
	var left: int = 2500 - GameState.base_stats("madras_king_deluxe").price_inr
	_check("Buy King Deluxe with ₹2,500", GameState.buy_vehicle("madras_king_deluxe") and GameState.active_vehicle == "madras_king_deluxe" and GameState.wallet_inr == left)
	_check("Switch back to the Singara for free", GameState.select_vehicle("singara_classic") and GameState.wallet_inr == left)
	_check("Engine upgrade costs ₹250", GameState.buy_upgrade("engine") and GameState.wallet_inr == left - 250 and GameState.upgrade_level("singara_classic", "engine") == 1)
	_check("Upgrades are per-auto", GameState.upgrade_level("madras_king_deluxe", "engine") == 0)
	GameState.add_inr(5000)
	GameState.buy_upgrade("engine")
	GameState.buy_upgrade("engine")
	_check("Max 3 upgrade levels", not GameState.buy_upgrade("engine") and GameState.next_upgrade_cost("engine") == -1)
	_check("Horns unlock in order (no skipping to air-horn)", not GameState.buy_horn(2))
	_check("Twin horn ₹300", GameState.buy_horn(1) and GameState.horn_equipped == 1 and GameState.active_stats().horn_tier == 1)
	_check("Paint adds prestige (better Meter Mela odds)", GameState.buy_paint(2) and GameState.prestige() > 0.3)
	_check("Equipping an owned paint is free", GameState.buy_paint(0) and GameState.buy_paint(2))
	GameState.reset_profile()

## Exit gate: with the revised starter fuel consumption, the second auto must remain affordable within 14 rides.
func _test_economy_exit_gate() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 30
	var ids: PackedStringArray = ["it_commuter", "tnagar_shopper", "tourist", "college_student"]
	var wallet: float = 500.0
	var stats: VehicleStats = GameState.base_stats("singara_classic")
	var rides: int = 0
	while wallet < float(GameState.base_stats("madras_king_deluxe").price_inr) and rides < 40:
		var rider: PassengerArchetype = load("res://data/passengers/%s.tres" % ids[rng.randi() % ids.size()]) as PassengerArchetype
		var km: float = rng.randf_range(0.6, 2.4) * 1.3 # route ≈ 1.3× straight-line (1 : 1 map)
		var offer: FareCalculator.Offer = FareCalculator.Offer.METER if rng.randf() < 0.6 else FareCalculator.Offer.METER_MELA
		var fare: int = FareCalculator.quote(offer, km, rider)
		var b: Dictionary = FareCalculator.settle(fare, rider, rng.randf_range(0.55, 0.95), rng.randf() < 0.85, rng.randi_range(0, 2))
		var pickup_km: float = rng.randf_range(0.1, 0.4)
		wallet += float(int(b["total"])) - (km + pickup_km) * stats.fuel_burn_per_km * stats.fuel_price_inr
		rides += 1
	_check("2nd auto affordable within 14 rides with revised fuel cost", rides >= 6 and rides <= 14, "%d rides" % rides)

func _test_save_load() -> void:
	GameState.reset_profile()
	GameState.persistence_enabled = true
	GameState.save_path = TEST_SAVE
	GameState.add_inr(1234)
	GameState.buy_horn(1)
	GameState.day = 4
	GameState.set_setting("language", "ta")
	_check("Save writes an encrypted file", GameState.save_game() and FileAccess.file_exists(TEST_SAVE))
	var raw: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.READ)
	var bytes: PackedByteArray = raw.get_buffer(raw.get_length())
	raw.close()
	_check("Save is not readable plain text", not bytes.get_string_from_ascii().contains("wallet"))
	var wallet: int = GameState.wallet_inr
	GameState.reset_profile()
	_check("Load restores wallet, horn, day, settings", GameState.load_game() and GameState.wallet_inr == wallet and GameState.horns_owned == 1 and GameState.day == 4 and str(GameState.settings["language"]) == "ta")
	var w: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	bytes[bytes.size() / 2] = bytes[bytes.size() / 2] ^ 0xFF
	w.store_buffer(bytes)
	w.close()
	GameState.reset_profile()
	_check("Tampered save is rejected (fresh profile)", not GameState.load_game() and GameState.wallet_inr == 500)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	GameState.set_setting("language", "en")
	GameState.persistence_enabled = false
	GameState.save_path = GameState.SAVE_PATH

# --- In-scene ---------------------------------------------------------------------------

func _test_live_vehicle_swap(auto: AutoRickshawController) -> void:
	GameState.add_inr(2000)
	GameState.buy_vehicle("madras_king_deluxe")
	await _physics(2)
	_check("Buying swaps the driven auto live (72 km/h, 390 kg)", is_equal_approx(auto.stats.max_speed_kmh, 72.0) and is_equal_approx(auto.mass, 390.0), "%.0f km/h, %.0f kg" % [auto.stats.max_speed_kmh, auto.mass])
	GameState.buy_paint(0)
	GameState.add_inr(220)
	GameState.buy_paint(2)
	await _physics(2)
	var model: AutoRickshawModel = auto.get_node("Model") as AutoRickshawModel
	_check("New paint shows on the model", model.paint.is_equal_approx(GameState.PAINTS[2]["body"]))
	GameState.reset_profile()
	GameState.select_vehicle("singara_classic")
	GameState.buy_paint(0)
	await _physics(2)

func _test_fuel_and_services(auto: AutoRickshawController, services: ServicePoints, ui: GarageUI) -> void:
	_check("Service points loaded (LPG, EV, garages)", services.services.size() >= 9 and not services.nearest("lpg", Vector3.ZERO).is_empty() and not services.nearest("garage", Vector3.ZERO).is_empty())
	var before: float = auto.fuel_level
	auto._update_fuel_and_odometer(0.0) # no-op sanity
	auto.current_speed_kmh = 36.0
	auto._update_fuel_and_odometer(100.0) # 1 game-km at 36 km/h
	_check("LPG burns per km plus engine idle", is_equal_approx(before - auto.fuel_level, auto.stats.fuel_burn_per_km + auto.IDLE_FUEL_UNITS_PER_HOUR * 100.0 / 3600.0), "%.3f L" % (before - auto.fuel_level))
	# Drive into an LPG bunk.
	var bunk: Dictionary = services.nearest("lpg", auto.global_position)
	_events.erase("service_available")
	auto.global_transform = Transform3D(Basis.IDENTITY, (bunk["pos"] as Vector3) + Vector3(0, 1, 0))
	auto.linear_velocity = Vector3.ZERO
	await _physics(10)
	_check("Stopping at a bunk offers LPG", _events.has("service_available") and services.current.get("kind", "") == "lpg")
	SignalBus.fuel_changed.emit(2.0, auto.stats.fuel_capacity) # 2 L left
	SignalBus.refueled.emit(2.0)
	var wallet: int = GameState.wallet_inr
	var litres: float = GameState.buy_fuel()
	await _physics(2)
	_check("Fill-up charges ₹62/L and fills the tank", is_equal_approx(litres, 6.0) and GameState.wallet_inr == wallet - ceili(6.0 * 62.0) and is_equal_approx(auto.fuel_level, auto.stats.fuel_capacity), "%.1f L, ₹%d" % [litres, wallet - GameState.wallet_inr])
	# Wrong-fuel warning at an EV kiosk.
	var kiosk: Dictionary = services.nearest("ev", auto.global_position)
	auto.global_transform = Transform3D(Basis.IDENTITY, (kiosk["pos"] as Vector3) + Vector3(0, 1, 0))
	auto.linear_velocity = Vector3.ZERO
	await _physics(10)
	_check("EV kiosk warns an LPG auto", ui._service_msg.text == tr("WRONG_FUEL_EV"))
	# Tow when out of fuel.
	GameState.add_inr(500)
	wallet = GameState.wallet_inr
	_events.erase("teleport_requested")
	SignalBus.tow_requested.emit(auto.global_position + Vector3(300, 0, 300))
	await _physics(3)
	var nearest_bunk: Dictionary = services.nearest("lpg", auto.global_position)
	_check("Tow costs ₹150 and drops you at an LPG bunk", _events.has("teleport_requested") and GameState.wallet_inr == wallet - ServicePoints.TOW_COST_INR and (nearest_bunk["pos"] as Vector3).distance_to(auto.global_position) < 5.0)

## Phase 1B regression: uploaded GLB renders at Mylapore with a clear front bay.
func _test_mylapore_workshop(services: ServicePoints) -> void:
	var garage: Node3D = services.get_node_or_null("garage_mylapore") as Node3D
	_check("Mylapore garage service marker exists", garage != null)
	if garage == null:
		return
	var imported: Node3D = garage.get_node_or_null("MylaporeWorkshop") as Node3D
	_check("Mylapore GLB model imported", imported != null)
	if imported == null:
		return
	_check("Mylapore workshop uses bounded visual scale",
		is_equal_approx(imported.scale.x, 8.0) and imported.scale.x == imported.scale.z)
	for wall_name: String in ["WorkshopRearGuard", "WorkshopLeftGuard", "WorkshopRightGuard"]:
		var wall: StaticBody3D = garage.get_node_or_null(wall_name) as StaticBody3D
		_check("%s has a collision shape" % wall_name,
			wall != null and wall.get_node_or_null("CollisionShape3D") is CollisionShape3D)
	_check("Garage interaction location stays tied to service marker",
		services.nearest("garage", garage.global_position).get("id", "") == "garage_mylapore")

func _test_condition(_auto: AutoRickshawController) -> void:
	GameState.condition = 100.0
	SignalBus.player_collision.emit(10.0)
	_check("Crashes wear the auto (−12%)", is_equal_approx(GameState.condition, 88.0))
	var cost: int = GameState.repair_cost()
	GameState.add_inr(100)
	var wallet: int = GameState.wallet_inr
	_check("Repair ₹3 per point restores condition", cost == 36 and GameState.repair() and is_equal_approx(GameState.condition, 100.0) and GameState.wallet_inr == wallet - 36)
	await _physics(1)

func _test_shift_clock() -> void:
	GameState.start_next_day()
	var day: int = GameState.day
	_check("Shift starts at 6:00 AM", GameState.clock_text() == "6:00 AM")
	GameState.shift_minute = GameState.SHIFT_END_MIN - 0.5
	_events.erase("shift_ended")
	await _process_frames(60)
	_check("10 PM ends the shift with a summary", _events.has("shift_ended") and not GameState.shift_running and int((_events["shift_ended"] as Dictionary)["day"]) == day)
	GameState.start_next_day()
	_check("Next day resets the clock", GameState.day == day + 1 and GameState.shift_running and is_equal_approx(GameState.shift_minute, GameState.SHIFT_START_MIN))
	_check("18 real minutes per shift", is_equal_approx((GameState.SHIFT_END_MIN - GameState.SHIFT_START_MIN) / GameState.GAME_MIN_PER_SECOND, 1080.0))

func _test_settings(main: Node, hud: TouchHUD) -> void:
	var sun: DirectionalLight3D = main.get_node("Sun") as DirectionalLight3D
	GameState.set_setting("graphics", 0)
	_check("Low graphics: no shadows, 70% 3D resolution", not sun.shadow_enabled and is_equal_approx(get_tree().root.scaling_3d_scale, 0.7))
	GameState.set_setting("graphics", 2)
	_check("High graphics: shadows, full resolution", sun.shadow_enabled and is_equal_approx(get_tree().root.scaling_3d_scale, 1.0))
	GameState.set_setting("graphics", 1)
	GameState.set_setting("control_scheme", 1)
	_check("Arrow-button controls replace the handlebar", hud.control_scheme == 1 and not hud._steer_zone.visible and (hud._buttons["SteerLeft"]["touch"] as TouchScreenButton).visible)
	GameState.set_setting("control_scheme", 2)
	_check("Tilt controls hide the handlebar & buttons", hud.control_scheme == 2 and not hud._steer_zone.visible and not (hud._buttons["SteerLeft"]["touch"] as TouchScreenButton).visible)
	GameState.set_setting("control_scheme", 0)
	_check("Handlebar drag restored", hud._steer_zone.visible)
	GameState.set_setting("language", "ta")
	_check("Tamil UI strings", tr("GARAGE") == "கேரேஜ்" and tr("FILL_LPG") == "LPG நிரப்பு")
	var tamil: Font = load("res://assets/fonts/NotoSansTamil-Regular.ttf") as Font
	_check("Tamil font installed as UI fallback", ThemeDB.fallback_font.fallbacks.has(tamil))
	GameState.set_setting("language", "en")
	_check("English restored", tr("GARAGE") == "Garage")
	await _physics(1)

func _test_garage_pause(ui: GarageUI) -> void:
	ui.open_garage()
	_check("Garage opens and pauses the game", ui.is_open() and get_tree().paused)
	for tab: String in ["TAB_REPAIR", "TAB_UPGRADES", "TAB_HORN", "TAB_PAINT", "TAB_AUTOS"]:
		ui._current_tab = tab
		ui._render_garage()
	await _process_frames(2)
	_check("All garage tabs render", ui._modal_body.get_child_count() >= 3)
	ui.close_modal()
	_check("Closing resumes the game", not ui.is_open() and not get_tree().paused)
	ui.open_pause()
	_check("Pause menu shows settings", ui.is_open() and ui._modal_body.get_child_count() >= 5)
	ui.close_modal()

# --- Helpers ------------------------------------------------------------------------------

func _physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame

func _process_frames(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", test_name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_failed += 1
		printerr("  FAIL  ", test_name, ("  (" + detail + ")") if detail != "" else "")
