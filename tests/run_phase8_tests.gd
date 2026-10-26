extends Node
## Phase 8 (play-test feedback pass, Oct 2026): smooth camera, cockpit shadows, live splash,
## scooter riders, people at pickups, cows parked, stricter bargaining, time-of-day traffic.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase8_tests.tscn

const CITY: String = "res://scenes/main_chennai.tscn"
var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 8 tests ===")
	await _test_splash()
	_test_density_model()
	_test_people_meshes()
	_test_project_settings()
	_test_rewards_engine()
	await _test_ads()
	GameState.reset_profile()
	var city: Node = (load(CITY) as PackedScene).instantiate()
	add_child(city)
	await _physics(90)
	_test_traffic(city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager)
	_test_hails(city.get_node("SavariManager") as SavariManager)
	await _test_cockpit(city)
	_test_street_names_and_signs(city)
	await _test_gps(city)
	await _test_full_map(city)
	city.queue_free()
	await _physics(2)
	await _test_collisions()
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

func _test_street_names_and_signs(city: Node) -> void:
	var g: RoadGraph = SignalBus.current_road_graph
	var named: int = 0
	var tamil: int = 0
	for e: RoadGraph.Edge in g.edges:
		named += 1 if e.road_name != "" else 0
		tamil += 1 if e.road_name_ta != "" else 0
	_check("Real OSM street names on the road graph (≥ 60 % of edges)", float(named) / g.edges.size() >= 0.6, "%d/%d" % [named, g.edges.size()])
	_check("Tamil street names attached from OSM name:ta", tamil >= 500, "%d" % tamil)
	var ss: StreetSigns = city.get_node("StreetSigns") as StreetSigns
	ss._player = (city.get_node("AutoRickshaw") as Node3D).global_position
	ss.refresh()
	var shown: int = 0
	var real: bool = true
	for n: Node3D in ss._pool:
		if n.visible:
			shown += 1
			if (n.get_node("English") as Label3D).text == "":
				real = false
	_check("Street-name boards stand at nearby junctions", shown >= 2 and real, "%d boards" % shown)
	_check("Board pool capped (draw-call budget)", ss._pool.size() <= 8)

func _test_gps(city: Node) -> void:
	var g: RoadGraph = SignalBus.current_road_graph
	var auto: Node3D = city.get_node("AutoRickshaw") as Node3D
	var dest: Vector3 = auto.global_position + Vector3(900, 0, 400)
	var r: Dictionary = g.find_route(auto.global_position, dest)
	var gps: GpsRoute = GpsRoute.build(g, r)
	_check("GPS route builds a smooth guide path", gps.path.size() > r["points"].size() and gps.length > 100.0, "%d pts, %.0f m" % [gps.path.size(), gps.length])
	var max_kink: float = 0.0
	for i: int in range(2, gps.path.size()):
		var a: Vector3 = (gps.path[i - 1] - gps.path[i - 2])
		var b: Vector3 = (gps.path[i] - gps.path[i - 1])
		if a.length() > 0.3 and b.length() > 0.3:
			max_kink = maxf(max_kink, rad_to_deg(a.angle_to(b)))
	_check("Guide line has rounded corners (no sharp kinks)", max_kink < 50.0, "max %.0f°" % max_kink)
	_check("Turn-by-turn ends with Arrive", not gps.maneuvers.is_empty() and int(gps.maneuvers[-1]["turn"]) == GpsRoute.Turn.ARRIVE)
	var info: Array = []
	var cb: Callable = func(d: Dictionary) -> void: info.append(d)
	SignalBus.nav_instruction.connect(cb)
	SignalBus.gps_route_changed.emit(gps)
	await _physics(15)
	SignalBus.nav_instruction.disconnect(cb)
	_check("Nav prompt published (distance + turn text)", not info.is_empty() and (info[-1] as Dictionary).has("distance_m") and str((info[-1] as Dictionary)["text"]) != "")
	var rl: RouteLine = city.get_node("RouteLine") as RouteLine
	_check("Guide ribbon is one shader mesh", rl.mesh != null and rl.mesh.get_surface_count() == 1 and rl.material_override is ShaderMaterial)
	var banner: NavBanner = (city.get_node("PassengerHUD") as PassengerHUD).nav_banner
	_check("Nav banner shows", banner.visible)
	SignalBus.gps_route_changed.emit(null)

func _test_full_map(city: Node) -> void:
	var fm: FullMap = (city.get_node("PassengerHUD") as PassengerHUD).full_map
	SignalBus.full_map_requested.emit(true)
	await get_tree().process_frame
	_check("Full map opens and pauses the game", fm.visible and get_tree().paused)
	var before: float = fm.scale_px
	fm._zoom_at(1.5, fm.size * 0.5)
	_check("Full map zooms", fm.scale_px > before)
	SignalBus.full_map_requested.emit(false)
	await get_tree().process_frame
	_check("Full map closes and resumes", not fm.visible and not get_tree().paused)

func _test_collisions() -> void:
	var main: Node = (load("res://scenes/main_phase1_greybox.tscn") as PackedScene).instantiate()
	add_child(main)
	var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
	var traffic: ChennaiTrafficManager = main.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	for v: TrafficVehicleAI in traffic.pool:
		v.deactivate()
	await _physics(30)
	_check("Chassis has low-friction bounce material + chamfered hull", auto.physics_material_override != null and auto.physics_material_override.friction <= 0.2 \
		and (auto.get_node("ChassisCollision") as CollisionShape3D).shape is ConvexPolygonShape3D)
	var fwd: Vector3 = -auto.global_basis.z
	var wall: StaticBody3D = StaticBody3D.new()
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bx: BoxShape3D = BoxShape3D.new()
	bx.size = Vector3(14, 4, 1)
	cs.shape = bx
	wall.add_child(cs)
	main.add_child(wall)
	wall.global_position = auto.global_position + fwd * 40.0 + Vector3(0, 1.5, 0)
	wall.look_at(wall.global_position + fwd.rotated(Vector3.UP, deg_to_rad(35.0)), Vector3.UP)
	var impacts: Array[Dictionary] = []
	var cb: Callable = func(i: Dictionary) -> void: impacts.append(i)
	SignalBus.player_impact.connect(cb)
	Input.action_press("accelerate")
	var hit_frame: int = -1
	var slide: float = 0.0
	for i: int in 400:
		await get_tree().physics_frame
		if hit_frame < 0 and not impacts.is_empty():
			hit_frame = i
		if hit_frame >= 0 and i == hit_frame + 30:
			slide = Vector2(auto.linear_velocity.x, auto.linear_velocity.z).length()
			break
	Input.action_release("accelerate")
	SignalBus.player_impact.disconnect(cb)
	_check("Wall impact detected from contacts with severity", not impacts.is_empty() and float(impacts[0]["severity"]) > 0.3, str(impacts.slice(0, 1)))
	_check("Glancing hit slides along the wall (doesn't glue to it)", slide > 1.5, "%.1f m/s" % slide)
	_check("Impact never flips the auto", auto.global_basis.y.dot(Vector3.UP) > 0.8)
	var v: TrafficVehicleAI = traffic.pool[3]
	traffic.place_vehicle(v, 0, 300.0, 1, 1)
	SignalBus.traffic_bumped.emit(v, 6.0)
	_check("Bumped AI stops (no bulldozing)", v.bumped_timer > 1.0 and is_zero_approx(v.current_speed_mps))
	main.queue_free()
	await _physics(2)

func _test_rewards_engine() -> void:
	var r: RewardsEngine = RewardsEngine.new()
	var g1: Dictionary = r.grant("ad_double_fare", 120, 0, "ad_double_fare:ride-1", "2026-10-26")
	var g2: Dictionary = r.grant("ad_double_fare", 120, 0, "ad_double_fare:ride-1", "2026-10-26")
	_check("Rewards are idempotent (same ride can't be doubled twice)", int(g1["inr"]) == 120 and int(g2["inr"]) == 0 and str(g2["refused"]) == "duplicate")
	for i: int in 20:
		r.grant("ad_double_fare", 10, 0, "x%d" % i, "2026-10-26")
	_check("Daily cap per source", r.remaining_today("ad_double_fare", "2026-10-26") == 0 and r.remaining_today("ad_double_fare", "2026-10-27") > 0)
	var d1: Dictionary = r.claim_daily("2026-10-26")
	var again: Dictionary = r.claim_daily("2026-10-26")
	var d2: Dictionary = r.claim_daily("2026-10-27")
	_check("Daily login: once per day, streak grows on consecutive days", int(d1["inr"]) == RewardsEngine.DAILY_INR[0] and int(again["inr"]) == 0 and int(d2["inr"]) == RewardsEngine.DAILY_INR[1] and r.streak == 2)
	r.claim_daily("2026-10-30")
	_check("Missing a day resets the streak", r.streak == 1)
	r.add_stat("rides", 1)
	var got: Array[String] = r.check_achievements("2026-10-30")
	_check("Achievement unlocks once", got.has("first_savari") and r.check_achievements("2026-10-30").is_empty())
	var r2: RewardsEngine = RewardsEngine.new()
	r2.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())) as Dictionary)
	_check("Rewards survive save/load", r2.streak == r.streak and r2.achieved.has("first_savari") and r2.granted_ids.has("ad_double_fare:ride-1"))
	GameState.reset_profile()
	var w: int = GameState.wallet_inr
	GameState.claim_daily_reward()
	_check("GameState pays the daily bonus into the wallet", GameState.wallet_inr == w + RewardsEngine.DAILY_INR[0])
	GameState.reset_profile()

func _test_ads() -> void:
	var ads: Node = get_node("/root/AdMonetizationManager")
	_check("Ad manager autoload with a provider", ads != null and ads.provider != null, str(ads.provider.provider_name()))
	_check("No forced ad in the first-session grace period", ads.interstitial_block_reason("after_fare_summary") == "first_session_grace")
	_check("Forced ads never at arbitrary placements", ads.interstitial_block_reason("mid_ride") == "placement_not_allowed")
	ads.debug_advance(900.0)
	_check("Ride spacing: not after every ride", ads.interstitial_block_reason("after_fare_summary") == "ride_spacing")
	_check("Shift end may show one after grace", ads.interstitial_block_reason("shift_end") == "")
	ads.maybe_show_interstitial("shift_end")
	await get_tree().process_frame
	_check("Cooldown blocks a second interstitial", ads.interstitial_block_reason("shift_end") == "cooldown")
	GameState.no_ads = true
	_check("No-Ads purchase blocks forced ads", ads.interstitial_block_reason("shift_end") == "no_ads_purchased")
	GameState.no_ads = false
	GameState.reset_profile()
	var w: int = GameState.wallet_inr
	ads.show_rewarded("ad_double_fare", {"ride_id": "t-1", "inr": 90})
	for i: int in 3:
		await get_tree().process_frame
	_check("Rewarded 2× fare pays after the ad completes", GameState.wallet_inr == w + 90, "%d → %d" % [w, GameState.wallet_inr])
	ads.show_rewarded("ad_double_fare", {"ride_id": "t-1", "inr": 90})
	for i: int in 3:
		await get_tree().process_frame
	_check("…and only once per ride", GameState.wallet_inr == w + 90)
	GameState.reset_profile()

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
