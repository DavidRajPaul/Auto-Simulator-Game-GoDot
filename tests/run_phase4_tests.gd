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
	_test_upgrade_performance_baseline()
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
	await _test_fire_limp(main, auto, ui)
	await _test_wreck_rescue(main, auto, services, ui, hud)

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

## Phase 0: deterministic performance contract for the existing single-model fleet.
## These checks validate configuration and the drive-force curve, NOT observed road speed.
func _test_upgrade_performance_baseline() -> void:
	GameState.reset_profile()
	for vehicle_id: String in GameState.VEHICLE_ORDER:
		var stock: VehicleStats = GameState.base_stats(vehicle_id)
		var idle: VehicleStats = GameState.effective_stats(vehicle_id)
		_check("%s stock configured speed is stable" % vehicle_id,
			is_equal_approx(stock.max_speed_kmh, idle.max_speed_kmh))
		_check("%s produces positive force near its speed limit" % vehicle_id,
			stock.engine_peak_force_n > 0.0 and stock.torque_falloff >= 0.0
			and stock.torque_falloff < 1.0 and stock.max_speed_kmh > 0.0)
		var baseline_force: float = stock.engine_peak_force_n * (1.0 - stock.torque_falloff * 0.5)
		var halfway_drag: float = stock.aero_drag_coeff * pow(stock.max_speed_kmh / 7.2, 2.0)
		_check("%s has enough theoretical midrange drive force" % vehicle_id,
			baseline_force > halfway_drag)
	GameState.upgrades = {"singara_classic": {"engine": 3, "suspension": 3, "tyres": 3}}
	var stock_classic: VehicleStats = GameState.base_stats("singara_classic")
	var tuned: VehicleStats = GameState.effective_stats("singara_classic")
	_check("Fully tuned Singara gains 9 km/h configured speed",
		is_equal_approx(tuned.max_speed_kmh, stock_classic.max_speed_kmh + 9.0))
	_check("Fully tuned engine gains 21% peak force",
		is_equal_approx(tuned.engine_peak_force_n, stock_classic.engine_peak_force_n * 1.21))
	_check("Full suspension tune reduces jolts and tyres increase grip",
		tuned.comfort_damping < stock_classic.comfort_damping
		and tuned.rear_lateral_grip > stock_classic.rear_lateral_grip)
	GameState.condition = 30.0
	_check("Engine wear lowers speed and force together",
		GameState.effective_stats("singara_classic").max_speed_kmh < tuned.max_speed_kmh
		and GameState.effective_stats("singara_classic").engine_peak_force_n < tuned.engine_peak_force_n)
	GameState.reset_profile()

func _test_purchases() -> void:
	GameState.reset_profile()
	_check("Can't buy King Deluxe with ₹500", not GameState.buy_vehicle("madras_king_deluxe") and GameState.wallet_inr == 500)
	GameState.add_inr(2000)
	var left: int = 2500 - GameState.base_stats("madras_king_deluxe").price_inr
	_check("Buy King Deluxe with ₹2,500", GameState.buy_vehicle("madras_king_deluxe") and GameState.active_vehicle == "madras_king_deluxe" and GameState.wallet_inr == left)
	_check("Switch back to the Singara for free", GameState.select_vehicle("singara_classic") and GameState.wallet_inr == left)
	_check("Engine upgrade costs ₹350", GameState.buy_upgrade("engine") and GameState.wallet_inr == left - 350 and GameState.upgrade_level("singara_classic", "engine") == 1)
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
		var fare: int = FareCalculator.meter_fare(km, rider.surge_multiplier) + (0 if rng.randf() < 0.6 else 30)
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
	_check("New paint is saved in model color selection", model.paint.is_equal_approx(GameState.PAINTS[2]["body"]))
	_check("Custom paint never swaps away the imported auto body", model.uses_real_model and model.real_body != null)
	_check("Custom paint keeps procedural replacement body hidden", model.body_mesh != null and not model.body_mesh.visible)
	var pm: ShaderMaterial = model.paint_material
	_check("Custom paint recolours the imported body (paint-mask shader, same textures)", pm != null and pm.shader != null
		and pm.get_shader_parameter("albedo_tex") != null and pm.get_shader_parameter("mask_tex") != null
		and (pm.get_shader_parameter("body_colour") as Color).is_equal_approx(GameState.PAINTS[2]["body"])
		and (pm.get_shader_parameter("canopy_colour") as Color).is_equal_approx(GameState.PAINTS[2]["canopy"]))
	var tris_painted: int = _real_body_triangles(model)
	GameState.reset_profile()
	GameState.select_vehicle("singara_classic")
	GameState.buy_paint(0)
	await _physics(2)
	# Nov 3: the paint/glass shaders always run (they draw the crash damage); stock yellow shows the
	# texture's own colours through them, non-metal like the file's material.
	var stock: ShaderMaterial = model.paint_material
	_check("Stock yellow shows the imported texture's own colours (stock_paint, non-metal)", model.uses_real_model and stock != null
		and bool(stock.get_shader_parameter("stock_paint")) and float(stock.get_shader_parameter("metallic_scale")) == 0.0
		and int(stock.get_shader_parameter("dent_count")) == 0)
	_check("Repaint never changes the auto's geometry (same triangle count)", tris_painted > 0 and tris_painted == _real_body_triangles(model), "%d vs %d" % [tris_painted, _real_body_triangles(model)])

func _real_body_triangles(model: AutoRickshawModel) -> int:
	var n: int = 0
	if model.real_body == null:
		return 0
	for node: Node in model.real_body.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (node as MeshInstance3D).mesh
		for s: int in m.get_surface_count():
			n += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n

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
	_check("Crashes wear the auto by normal impact energy", is_equal_approx(GameState.condition, 100.0 - GameState.DAMAGE.points(10.0)))
	var cost: int = GameState.repair_cost()
	GameState.add_inr(100)
	var wallet: int = GameState.wallet_inr
	_check("Repair ₹4 per point restores condition", cost == ceili(GameState.DAMAGE.points(10.0) * 4.0) and GameState.repair() and is_equal_approx(GameState.condition, 100.0) and GameState.wallet_inr == wallet - cost)
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

## Nov 8 owner questions: a wrecked auto with no money, the rider on board, the horn. The wreck
## panel explains itself and always has the free patch-up (ads stay optional); a wrecked auto can
## be towed to the nearest garage; the rider jumps out and runs on the frightened run with no fare
## and no rating; the horn is silent and greyed out.
func _test_wreck_rescue(main: Node, auto: AutoRickshawController, services: ServicePoints, ui: GarageUI, hud: TouchHUD) -> void:
	GameState.tutorial_active = false
	GameState.repair_free()
	GameState.wallet_inr = 0
	var garage: Dictionary = services.nearest("garage", auto.global_position)
	var spot: Vector3 = Vector3.INF
	for off: Vector3 in [Vector3(140, 0, 0), Vector3(-140, 0, 0), Vector3(0, 0, 140), Vector3(0, 0, -140), Vector3(220, 0, 220)]:
		var q: Vector3 = (garage["pos"] as Vector3) + off
		if services.services.all(func(sv: Dictionary) -> bool: return (sv["pos"] as Vector3).distance_to(q) > 30.0):
			spot = q
			break
	_check("Found a wreck spot away from every service", spot != Vector3.INF)
	auto.global_transform = Transform3D(Basis.IDENTITY, spot + Vector3(0, 1, 0))
	auto.linear_velocity = Vector3.ZERO
	await _physics(30)
	# A ride in progress when the auto catches fire.
	var savari: SavariManager = main.get_node("SavariManager") as SavariManager
	var phud: PassengerHUD = main.get_node("PassengerHUD") as PassengerHUD
	var abandoned: Array[String] = []
	var on_abandon: Callable = func(line: String) -> void: abandoned.append(line)
	SignalBus.ride_abandoned.connect(on_abandon)
	savari.rider = savari.archetypes[0]
	savari.destination = {"pos": spot + Vector3(600, 0, 0), "name": "Test"}
	savari.route = {}
	savari.agreed_fare = 120
	savari._rider_person = "woman_saree_green"
	savari.state = SavariManager.State.RIDING
	phud._ride_card.visible = true
	var rides: int = GameState.completed_savaris
	var fwd: Vector3 = -auto.global_basis.z
	var left: Vector3 = Vector3.UP.cross(Vector3(fwd.x, 0.0, fwd.z).normalized())
	for i: int in 12:
		if GameState.is_wrecked():
			break
		SignalBus.player_collision.emit(14.0)
	await _physics(2)
	_check("Crashing to 0 % wrecks the auto", GameState.is_wrecked())
	_check("Fire mid-ride: the ride ends with the rider's line", savari.state == SavariManager.State.COOLDOWN and savari.rider == null
		and abandoned.size() == 1 and abandoned[0] == tr("RIDER_FLED_FIRE"))
	_check("No fare and no rating for a ride the fire ended", GameState.wallet_inr == 0 and GameState.completed_savaris == rides)
	_check("The ride card goes away", not phud._ride_card.visible)
	var runner: Node3D = savari._fleer.get_node_or_null("Runner_woman_saree_green") as Node3D
	var ap: AnimationPlayer = runner.find_child("AnimationPlayer", true, false) as AnimationPlayer if runner != null else null
	_check("The rider gets out on the kerb (left) side", savari._fleer.visible and runner != null and runner.visible
		and (savari._fleer.global_position - auto.global_position).dot(left) > 0.5)
	_check("The rider runs on the frightened run", ap != null and ap.current_animation == "flee" and ap.is_playing())
	var run_from: Vector3 = savari._fleer.global_position
	await _physics(90)
	_check("The rider runs away from the burning auto", savari._fleer.global_position.distance_to(run_from) > 1.5
		and savari._fleer.global_position.distance_to(auto.global_position) > run_from.distance_to(auto.global_position))
	# The wreck panel with an empty wallet.
	await _process_frames(2)
	var rows: VBoxContainer = ui._wreck_rows
	_check("Wreck panel shows what happened and the money", ui._wreck_card.visible and ui._wreck_title.text == tr("WRECKED_MSG")
		and ui._wreck_detail.text == tr("WRECK_DETAIL") % [UIKit.inr(GameState.repair_cost()), UIKit.inr(0)], ui._wreck_detail.text)
	_check("Free patch-up is always offered, so ads stay optional", rows.get_node_or_null("Patch") != null)
	_check("An ad repair is offered only when an ad is ready", (rows.get_node_or_null("AdRepair") != null) == AdMonetizationManager.can_offer_rewarded("ad_wreck_repair"))
	_check("No pay option with an empty wallet", rows.get_node_or_null("Pay") == null)
	var tow_row: Node = rows.get_node_or_null("Tow")
	_check("Empty wallet: a free tow to the nearest garage, no ad needed", tow_row != null and rows.get_node_or_null("AdTow") == null
		and (tow_row.get_node("Button") as Button).text == tr("WRECK_TOW_FREE_BTN")
		and (tow_row.get_node("Desc") as Label).text.begins_with(tr("WRECK_TOW_DESC").get_slice("%", 0)))
	_check("The engine-on-fire panel hides the old service bar", not ui._service_bar.visible)
	# The horn is silent and greyed out while wrecked.
	var horns: Array[int] = [0]
	var on_horn: Callable = func(_p: Vector3, _f: Vector3, _r: float, _t: int) -> void: horns[0] += 1
	SignalBus.horn_blasted.connect(on_horn)
	Input.action_press("horn")
	await _physics(3)
	Input.action_release("horn")
	auto.blow_horn()
	_check("No horn from a wrecked auto", horns[0] == 0)
	var horn_icon: TextureRect = hud._buttons["Horn"]["icon"] as TextureRect
	_check("Horn button is greyed out while wrecked", horn_icon.modulate == TouchHUD.HORN_OFF_TINT)
	_check("The fire warning gives way to the wreck panel", hud._banner == null or not hud._banner.visible)
	# Free patch-up.
	((rows.get_node("Patch") as Node).get_node("Button") as Button).pressed.emit()
	await _process_frames(2)
	_check("Patch-up runs again at 15 %, panel closes", not GameState.is_wrecked() and GameState.condition == GameState.PATCH_UP_CONDITION
		and not ui._wreck_card.visible)
	auto.blow_horn()
	_check("Horn works again after the patch-up", horns[0] == 1 and horn_icon.modulate == Color.WHITE)
	SignalBus.horn_blasted.disconnect(on_horn)
	# Wrecked again with money: pay option, then a paid tow to the garage.
	GameState.wallet_inr = 500
	for i: int in 12:
		if GameState.is_wrecked():
			break
		SignalBus.player_collision.emit(14.0)
	await _process_frames(2)
	var pay_row: Node = rows.get_node_or_null("Pay")
	var cost: int = GameState.repair_cost()
	_check("With money: pay option says what it buys", pay_row != null
		and (pay_row.get_node("Button") as Button).text == tr("WRECK_PAY_BTN") % UIKit.inr(mini(cost, 500))
		and (pay_row.get_node("Desc") as Label).text == (tr("WRECK_PAY_FULL_DESC") if 500 >= cost else tr("WRECK_PAY_DESC") % mini(100, floori(float(500) / GameState.REPAIR_COST_PER_POINT))))
	var tow_btn: Button = (rows.get_node("Tow") as Node).get_node("Button") as Button
	_check("Paid tow shows its price", tow_btn.text == tr("WRECK_TOW_BTN") % UIKit.inr(ServicePoints.TOW_COST_INR))
	var target: Dictionary = services.nearest("garage", auto.global_position)
	tow_btn.pressed.emit()
	await _physics(30)
	await _process_frames(2)
	_check("Tow drops the wreck at the nearest garage for ₹210", (target["pos"] as Vector3).distance_to(auto.global_position) < 6.0
		and GameState.wallet_inr == 500 - ServicePoints.TOW_COST_INR, "%.1f m, ₹%d" % [(target["pos"] as Vector3).distance_to(auto.global_position), GameState.wallet_inr])
	_check("Towing does not repair: still wrecked at the garage", GameState.is_wrecked() and ui._wreck_card.visible)
	_check("At the garage the panel offers the garage instead of a tow", rows.get_node_or_null("Garage") != null and rows.get_node_or_null("Tow") == null)
	((rows.get_node("Garage") as Node).get_node("Button") as Button).pressed.emit()
	_check("Open garage from the wreck panel", ui.is_open() and ui._modal_title.text == tr("GARAGE"))
	ui.close_modal()
	GameState.repair()
	await _process_frames(2)
	_check("Repair at the garage clears the wreck panel", not GameState.is_wrecked() and not ui._wreck_card.visible)
	# The runner disappears once out of the way.
	await _physics(int(SavariManager.FLEER_SECONDS * 60.0))
	_check("The fled rider is gone after a few seconds", not savari._fleer.visible)
	SignalBus.ride_abandoned.disconnect(on_abandon)
	GameState.repair_free()

# --- Helpers ------------------------------------------------------------------------------

## Owner report (Nov 9): flames showing and the auto still drove smoothly. Under black smoke and
## fire the engine limps (less power, lower top speed, misfires), and a burning auto takes no
## riders and no LPG.
func _top_speed_after(auto: AutoRickshawController, frames: int) -> float:
	auto.global_transform = Transform3D(auto.global_basis.orthonormalized(), auto.global_position + Vector3(0, 0.3, 0))
	auto.linear_velocity = Vector3.ZERO
	auto.angular_velocity = Vector3.ZERO
	await _physics(20)
	var top: float = 0.0
	Input.action_press("accelerate")
	for i: int in frames:
		await get_tree().physics_frame
		top = maxf(top, auto.current_speed_kmh)
	Input.action_release("accelerate")
	auto.linear_velocity = Vector3.ZERO
	await _physics(10)
	return top

func _test_fire_limp(main: Node, auto: AutoRickshawController, ui: GarageUI) -> void:
	GameState.tutorial_active = false
	GameState.repair_free()
	await _physics(5)
	auto._update_limp(0.016)
	_check("A healthy engine has full power", is_equal_approx(auto.limp_power, 1.0) and is_equal_approx(auto.limp_speed, 1.0) and not GameState.is_on_fire())
	var start: Transform3D = auto.global_transform
	var healthy: float = await _top_speed_after(auto, 240)
	GameState.condition = 8.0 # flames (severity 0.92)
	SignalBus.condition_changed.emit(GameState.condition)
	var misfires: Array[float] = []
	var on_misfire: Callable = func(t: float) -> void: misfires.append(t)
	SignalBus.engine_misfired.connect(on_misfire)
	auto.global_transform = start
	var burning: float = await _top_speed_after(auto, 240)
	SignalBus.engine_misfired.disconnect(on_misfire)
	_check("On fire the auto is on fire for every system", GameState.is_on_fire() and not GameState.is_wrecked())
	_check("On fire the engine limps: far less power and top speed",
			is_equal_approx(auto.limp_power, AutoRickshawController.LIMP_FIRE.y) and burning < healthy * 0.6
			and burning <= auto.stats.max_speed_kmh * AutoRickshawController.LIMP_FIRE.x + 2.0,
			"healthy %.1f, burning %.1f km/h" % [healthy, burning])
	_check("…and it misfires under throttle", misfires.size() >= 1, "%d misfires in 4 s" % misfires.size())
	# Nobody waits for, or gets into, a burning auto.
	var savari: SavariManager = main.get_node("SavariManager") as SavariManager
	await _process_frames(3)
	var waiting: int = 0
	for h: Dictionary in savari.hails:
		waiting += 0 if bool(h.get("scripted", false)) else 1
	_check("No riders hail a burning auto", waiting == 0, "%d waiting" % waiting)
	# No LPG for a burning auto.
	ui._service_kind = "lpg"
	ui._service_info = {"name": "Test bunk"}
	ui._render_service()
	var fill_offered: bool = false
	for c: Node in ui._service_bar.get_children():
		fill_offered = fill_offered or (c is Button and not (c as Button).is_queued_for_deletion())
	_check("The LPG bunk won't fill a burning auto", ui._service_msg.text == tr("NO_FUEL_ON_FIRE") and not fill_offered)
	ui._service_kind = ""
	ui._hide_service()
	GameState.repair_free()
	auto.global_transform = start
	auto.linear_velocity = Vector3.ZERO
	await _physics(10)
	auto._update_limp(0.016)
	_check("Repaired, the engine is back to full power", is_equal_approx(auto.limp_power, 1.0) and not GameState.is_on_fire())

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
