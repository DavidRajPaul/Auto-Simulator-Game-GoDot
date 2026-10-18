extends Node
## Phase 1 headless verification suite. Runs as a scene (not `-s`) so autoload
## globals such as SignalBus resolve when game scripts compile.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase1_tests.tscn
## Exit code 0 = all passed, 1 = at least one failure.

const MAIN_SCENE: String = "res://scenes/main_phase1_greybox.tscn"
const REQUIRED_RESOURCES: PackedStringArray = [
	"res://autoloads/SignalBus.gd",
	"res://autoloads/GameState.gd",
	"res://data/vehicles/VehicleStats.gd",
	"res://data/vehicles/Bajaj_RE_4S.tres",
	"res://data/passengers/PassengerArchetype.gd",
	"res://scripts/vehicle/AutoRickshawController.gd",
	"res://scripts/vehicle/CameraRig.gd",
	"res://scripts/traffic/ChennaiTrafficManager.gd",
	"res://scripts/traffic/TrafficVehicleAI.gd",
	"res://scripts/ui/TouchHUD.gd",
	"res://scenes/vehicles/auto_rickshaw.tscn",
	"res://scenes/traffic/ai_traffic_vehicle.tscn",
	"res://scenes/ui/touch_hud.tscn",
	MAIN_SCENE,
]

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 1 tests ===")
	await get_tree().process_frame
	_test_resources_load()
	_test_vehicle_stats()
	_test_meter_fare()

	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
	var traffic: ChennaiTrafficManager = main.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	await _physics(30)

	_test_traffic_pool(traffic, auto)
	var child_count_before: int = traffic.get_child_count()

	# Physics tests run on an empty road so traffic can't interfere.
	_park_all(traffic)
	await _physics(90) # let suspension settle
	_check("Auto settles on 3 wheels", auto.wheels_grounded == 3, "grounded=%d" % auto.wheels_grounded)
	await _test_acceleration(auto)
	await _test_steering_roll(auto)
	await _reset_auto(auto)
	await _test_horn(traffic, auto)
	await _test_water_stall_and_kick_start(auto)
	_test_passenger_mass(auto)
	_check("No traffic instantiate/free during driving", traffic.get_child_count() == child_count_before,
		"children %d -> %d" % [child_count_before, traffic.get_child_count()])

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Tests -----------------------------------------------------------------

func _test_resources_load() -> void:
	for path: String in REQUIRED_RESOURCES:
		_check("Loads " + path, ResourceLoader.load(path) != null)

func _test_vehicle_stats() -> void:
	var s: VehicleStats = load("res://data/vehicles/Bajaj_RE_4S.tres") as VehicleStats
	_check("Bajaj_RE_4S is VehicleStats", s != null)
	if s == null:
		return
	_check("Front steer angle is 45°", is_equal_approx(s.max_steer_angle_deg, 45.0))
	_check("Rear-biased centre of mass", s.center_of_mass_offset.is_equal_approx(Vector3(0.0, -0.25, 0.35)))
	_check("Two-wheel tilt window 12–18°", is_equal_approx(s.two_wheel_tilt_min_deg, 12.0) and is_equal_approx(s.max_safe_roll_angle_deg, 18.0))

func _test_meter_fare() -> void:
	var gs: Node = get_node("/root/GameState")
	_check("Meter: 1 km = ₹35", int(gs.call("calculate_meter_fare", 1.0)) == 35)
	_check("Meter: 5 km = ₹95", int(gs.call("calculate_meter_fare", 5.0)) == 95)
	_check("Meter: 5 km night = ₹140", int(gs.call("calculate_meter_fare", 5.0, true)) == 140)

func _test_traffic_pool(traffic: ChennaiTrafficManager, auto: AutoRickshawController) -> void:
	_check("Traffic pool is 18", traffic.pool.size() == ChennaiTrafficManager.MAX_POOL)
	var active: Array[TrafficVehicleAI] = traffic.active_vehicles()
	_check("Active traffic ≤ 18", active.size() <= 18 and active.size() > 0, "active=%d" % active.size())
	var far: int = 0
	for v: TrafficVehicleAI in active:
		if v.global_position.distance_to(auto.global_position) > ChennaiTrafficManager.RECYCLE_RADIUS_M:
			far += 1
	_check("All active traffic within 120 m", far == 0, "far=%d" % far)

func _test_acceleration(auto: AutoRickshawController) -> void:
	Input.action_press("accelerate")
	var airborne_front_frames: int = 0
	for i: int in 240: # 4.0 s at 60 Hz
		await get_tree().physics_frame
		if not auto.front_wheel_ray.is_colliding():
			airborne_front_frames += 1
	Input.action_release("accelerate")
	_check("No wheelie under full throttle", airborne_front_frames < 6, "front airborne %d frames" % airborne_front_frames)
	_check("Throttle 4 s → ≥ 35 km/h", auto.current_speed_kmh >= 35.0, "%.1f km/h" % auto.current_speed_kmh)
	_check("Top speed respected", auto.current_speed_kmh <= auto.stats.max_speed_kmh + 3.0, "%.1f km/h" % auto.current_speed_kmh)

func _test_steering_roll(auto: AutoRickshawController) -> void:
	# Bring speed to ~30 km/h.
	Input.action_press("brake")
	var guard: int = 0
	while auto.current_speed_kmh > 31.0 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	Input.action_release("brake")
	var start_speed: float = auto.current_speed_kmh
	var max_roll: float = 0.0
	Input.action_press("steer_right", 1.0)
	for i: int in 180:
		await get_tree().physics_frame
		max_roll = maxf(max_roll, auto.current_roll_deg)
	Input.action_release("steer_right")
	_check("Full steer at ~30 km/h: roll < 22°", max_roll < 22.0, "start %.1f km/h, max roll %.1f°" % [start_speed, max_roll])
	_check("Auto still upright after turn", auto.global_transform.basis.y.y > 0.8)

func _test_horn(traffic: ChennaiTrafficManager, auto: AutoRickshawController) -> void:
	_park_all(traffic)
	var lane: int = traffic.sub_lane_of_x(auto.global_position.x)
	var bike: TrafficVehicleAI = _first_of(traffic, TrafficVehicleAI.Archetype.TWO_WHEELER)
	var bus: TrafficVehicleAI = _first_of(traffic, TrafficVehicleAI.Archetype.MTC_BUS)
	bike.activate(Vector3(traffic.sub_lane_x(lane), 0.0, auto.global_position.z - 10.0), lane)
	bike.cruise_speed_mps = 0.0
	bike.current_speed_mps = 0.0
	bus.activate(Vector3(traffic.sub_lane_x(0), 0.0, auto.global_position.z - 14.0), 0)
	bus.cruise_speed_mps = 0.0
	bus.current_speed_mps = 0.0
	await _physics(2)
	Input.action_press("horn")
	await _physics(1)
	Input.action_release("horn")
	await _physics(60)
	_check("Horn (tier 1): two-wheeler within 18 m shifts sub-lane", bike.sub_lane != lane, "lane %d -> %d" % [lane, bike.sub_lane])
	_check("Horn (tier 1): MTC bus ignores twin horn", bus.sub_lane == 0)
	_park_all(traffic)

func _test_water_stall_and_kick_start(auto: AutoRickshawController) -> void:
	var bus: Node = get_node("/root/SignalBus")
	bus.emit_signal("water_depth_changed", 0.35)
	await _physics(3)
	_check("Deep water at low revs stalls the engine", auto.is_engine_stalled)
	bus.emit_signal("water_depth_changed", 0.0)
	for i: int in auto.stats.kick_start_pulls_needed:
		Input.action_press("kick_start")
		await _physics(1)
		Input.action_release("kick_start")
		await _physics(2)
	_check("Kick-start restarts the engine", not auto.is_engine_stalled)

func _test_passenger_mass(auto: AutoRickshawController) -> void:
	var bus: Node = get_node("/root/SignalBus")
	bus.emit_signal("passenger_boarded", 3, 45.0)
	var expected: float = auto.stats.base_mass_kg + 3.0 * auto.stats.passenger_mass_kg + 45.0
	_check("Passengers + luggage add mass", is_equal_approx(auto.mass, expected), "%.1f kg" % auto.mass)
	_check("Load shifts CoM rearward", auto.center_of_mass.z > auto.stats.center_of_mass_offset.z)
	bus.emit_signal("passenger_alighted")
	_check("Alighting restores base mass", is_equal_approx(auto.mass, auto.stats.base_mass_kg))

# --- Helpers ---------------------------------------------------------------

func _physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame

func _park_all(traffic: ChennaiTrafficManager) -> void:
	traffic.active_count = 0
	for v: TrafficVehicleAI in traffic.pool:
		v.deactivate()

func _first_of(traffic: ChennaiTrafficManager, kind: TrafficVehicleAI.Archetype) -> TrafficVehicleAI:
	for v: TrafficVehicleAI in traffic.pool:
		if v.archetype == kind:
			return v
	return traffic.pool[0]

func _reset_auto(auto: AutoRickshawController) -> void:
	auto.global_transform = Transform3D(Basis.IDENTITY, Vector3(1.1, 1.0, auto.global_position.z))
	auto.linear_velocity = Vector3.ZERO
	auto.angular_velocity = Vector3.ZERO
	await _physics(60)

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", test_name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_failed += 1
		printerr("  FAIL  ", test_name, ("  (" + detail + ")") if detail != "" else "")
