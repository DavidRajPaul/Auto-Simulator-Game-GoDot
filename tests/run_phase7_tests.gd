extends Node
## Phase 7 (play-test feedback pass, Oct 2026): smooth camera, cockpit shadows, live splash,
## scooter riders, people at pickups, cows parked, stricter bargaining, time-of-day traffic.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase7_tests.tscn

const CITY: String = "res://scenes/main_chennai.tscn"
var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 7 tests ===")
	await _test_splash()
	_test_density_model()
	_test_people_meshes()
	_test_project_settings()
	GameState.reset_profile()
	var city: Node = (load(CITY) as PackedScene).instantiate()
	add_child(city)
	await _physics(90)
	_test_traffic(city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager)
	_test_hails(city.get_node("SavariManager") as SavariManager)
	await _test_cockpit(city)
	city.queue_free()
	await _physics(2)
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_density_model() -> void:
	var peak: float = TrafficDensity.congestion(18.0 * 60.0, 2)
	_check("TomTom: weekday 6 PM is Chennai's worst hour (~110 % congestion)", peak > 1.0 and peak < 1.25, "%.2f" % peak)
	_check("4 AM is near free flow", TrafficDensity.congestion(4.0 * 60.0, 2) < 0.05)
	_check("Sunday 6 PM lighter than weekday 6 PM", TrafficDensity.congestion(1080.0, 6) < peak)
	_check("T. Nagar busier than Marina at noon", TrafficDensity.density(720.0, 1, "t_nagar") > TrafficDensity.density(720.0, 1, "marina"))
	_check("More AI vehicles at rush hour than late night",
		TrafficDensity.active_vehicles(TrafficDensity.density(1080.0, 1, "anna_salai"), 18) > TrafficDensity.active_vehicles(TrafficDensity.density(1290.0, 1, "anna_salai"), 18))
	_check("Pool cap 18 respected", TrafficDensity.active_vehicles(5.0, 18) <= 18)
	_check("Rush hour slows traffic down", TrafficDensity.speed_factor(1080.0, 1, 1.0) < 0.7)
	_check("Rain raises rider demand", TrafficDensity.rider_demand(0.3, true) > TrafficDensity.rider_demand(0.3, false))

func _test_people_meshes() -> void:
	var rider: ArrayMesh = PersonMesh.seated_rider(0)
	_check("Rider mesh is one surface (1 draw call)", rider.get_surface_count() == 1)
	var tris: int = rider.surface_get_array_len(0) / 3
	_check("Rider ≤ 1,200 triangles", tris <= 1200, "%d tris" % tris)
	var ok: bool = true
	for s: int in PersonMesh.Style.size():
		var m: ArrayMesh = PersonMesh.standing(s as PersonMesh.Style, s, true)
		if m == null or m.get_surface_count() != 1 or m.get_aabb().size.y < 1.5 or m.get_aabb().size.y > 1.9:
			ok = false
	_check("Every passenger style builds a 1.5–1.9 m person", ok)
	_check("Meshes are cached (shared between pool members)", PersonMesh.seated_rider(0) == rider)

func _test_project_settings() -> void:
	_check("Physics interpolation on (no camera judder between 60 Hz ticks)", bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)))
	_check("Main scene is the live splash", str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/splash.tscn")

func _test_traffic(traffic: ChennaiTrafficManager) -> void:
	var cows: int = 0
	var bikes: int = 0
	var riders: int = 0
	for v: TrafficVehicleAI in traffic.pool:
		if v.archetype == TrafficVehicleAI.Archetype.STRAY_COW:
			cows += 1
		if v.archetype == TrafficVehicleAI.Archetype.TWO_WHEELER:
			bikes += 1
			if v.get_node_or_null("Rider") != null:
				riders += 1
	_check("No stray cattle in the traffic pool", cows == 0)
	_check("Every scooter has a rider", bikes > 0 and riders == bikes, "%d/%d" % [riders, bikes])
	_check("Traffic density published", traffic.density >= 0.0 and traffic.target_active >= 3 and traffic.target_active <= 18, "d=%.2f n=%d" % [traffic.density, traffic.target_active])

func _test_hails(savari: SavariManager) -> void:
	var ok: bool = true
	for n: Node3D in savari._hail_pool:
		var body: MeshInstance3D = n.get_node("Body") as MeshInstance3D
		if body.mesh is CapsuleMesh or n.get_node_or_null("WaveArm") == null:
			ok = false
	_check("Pickup points show people (not capsules) with a waving arm", ok)

func _test_cockpit(city: Node) -> void:
	var rig: CameraRig = city.get_node("CameraRig") as CameraRig
	var auto: AutoRickshawController = city.get_node("AutoRickshaw") as AutoRickshawController
	while rig.mode != CameraRig.Mode.COCKPIT:
		rig.cycle_mode()
	await _physics(3)
	var model_shadow: bool = false
	for g: Node in auto.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			model_shadow = true
	_check("Cockpit view: the auto's own shadows are off", not model_shadow)
	# Head stabilisation: a sudden chassis roll moves the eye far less than the body.
	auto.global_rotation.z = 0.0
	await _physics(30)
	var cam: Camera3D = rig.get_node("Camera") as Camera3D
	var before: float = cam.global_basis.get_euler().z
	auto.global_rotation.z = deg_to_rad(8.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var after: float = cam.global_basis.get_euler().z
	_check("Cockpit soaks up sudden roll (eye moves < 30 % of the body)", absf(after - before) < deg_to_rad(8.0) * 0.3, "%.2f°" % rad_to_deg(after - before))
	while rig.mode != CameraRig.Mode.CHASE:
		rig.cycle_mode()

func _test_splash() -> void:
	var s: SplashScreen = (load("res://scenes/splash.tscn") as PackedScene).instantiate() as SplashScreen
	add_child(s)
	var p0: float = s.progress()
	for i: int in 45:
		await get_tree().process_frame
	_check("Splash progress bar actually moves", s.progress() > p0 + 0.05, "%.2f → %.2f" % [p0, s.progress()])
	for i: int in 200: # let the threaded menu load finish before freeing the splash
		if s._loaded != null:
			break
		await get_tree().process_frame
	s.set_process(false)
	s.queue_free()

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
