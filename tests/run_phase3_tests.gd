extends Node
## Phase 3 verification: fares, haggling odds, GPS routing, and full rides end-to-end.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase3_tests.tscn

const MAIN_SCENE: String = "res://scenes/main_chennai.tscn"
const ARCHETYPE_IDS: PackedStringArray = ["it_commuter", "tnagar_shopper", "tourist", "monsoon_rider", "college_student"]

var _passed: int = 0
var _failed: int = 0
var _events: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 3 tests ===")
	_test_archetypes()
	_test_fares()
	_test_odds()
	_test_settlement()
	_test_routing()

	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
	var savari: SavariManager = main.get_node("SavariManager") as SavariManager
	var traffic: ChennaiTrafficManager = main.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	for sig: String in ["haggle_started", "haggle_resolved", "ride_completed", "route_updated", "near_miss", "hails_updated"]:
		var name_copy: String = sig
		SignalBus.connect(sig, func(a: Variant = null, _b: Variant = null) -> void: _events[name_copy] = a)
	await _physics(90)

	_check("Road graph published to SignalBus", SignalBus.current_road_graph != null and savari.graph != null)
	_check("Hails appear around the player", savari.hails.size() >= 1, "%d hails" % savari.hails.size())
	var mm: MiniMap = main.get_node("PassengerHUD").minimap
	_check("Mini-map built its road grid", mm != null and not mm._grid.is_empty())
	await _test_haggle_timeout(savari, auto)
	await _test_full_ride(savari, auto, main)
	await _test_comfort_and_near_miss(savari, auto)
	await _test_near_miss_detector(traffic, auto)

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Unit ---------------------------------------------------------------------

func _rider(id: String) -> PassengerArchetype:
	return load("res://data/passengers/%s.tres" % id) as PassengerArchetype

func _test_archetypes() -> void:
	var ok: bool = true
	for id: String in ARCHETYPE_IDS:
		var a: PassengerArchetype = _rider(id)
		if a == null or a.haggle_ceiling < 1.0 or a.haggle_ceiling > 1.5 or a.haggle_patience < 1 or a.haggle_open_ratio > 1.0:
			ok = false
	_check("5 archetypes load with sane bargaining values", ok)
	_check("T. Nagar shopper carries +45 kg luggage", is_equal_approx(_rider("tnagar_shopper").luggage_kg, 45.0))
	_check("Monsoon rider pays 1.5× surge", _rider("monsoon_rider").surge_multiplier >= 1.5)

func _test_fares() -> void:
	var it: PassengerArchetype = _rider("it_commuter")
	_check("Meter: 1 km (inside the 1.8 km base) = ₹50", FareCalculator.meter_fare(1.0) == 50)
	_check("Meter: 5 km = ₹130", FareCalculator.meter_fare(5.0) == 130)

func _test_odds() -> void:
	var it: PassengerArchetype = _rider("it_commuter")
	var shopper: PassengerArchetype = _rider("tnagar_shopper")
	GameState.shift_minute = 1330.0
	var late: bool = GameState.night_fare_now()
	GameState.shift_minute = 700.0
	_check("Night fare applies from 10 PM, not by day", late and not GameState.night_fare_now())
	_check("Honest meter is always within the limit", FareCalculator.rider_limit(100, shopper, PackedStringArray(["broke", "app", "bus"]), 0.0, 0.0, 1.0, 5, -0.06) == 100)
	var plain: int = FareCalculator.rider_limit(200, it, PackedStringArray())
	_check("A hurried rider pays more", FareCalculator.rider_limit(200, it, PackedStringArray(["late"])) > plain)
	_check("Rain raises the limit", FareCalculator.rider_limit(200, it, PackedStringArray(["rain"])) > plain)
	_check("A cab app lowers the limit", FareCalculator.rider_limit(200, it, PackedStringArray(["app"])) < plain)
	_check("Greed at the stand lowers the limit", FareCalculator.rider_limit(200, it, PackedStringArray(), 0.0, 0.5, 4.5, 5) < plain)
	_check("Low rating lowers the limit", FareCalculator.rider_limit(200, it, PackedStringArray(), 0.0, 0.5, 2.0) < plain)
	_check("Rush hour raises the limit", FareCalculator.rider_limit(200, it, PackedStringArray(), 0.0, 1.0) > plain)
	_check("Shoppers open below the meter", FareCalculator.opening_offer(200, shopper, PackedStringArray()) < 200)
	var asks: Array[int] = FareCalculator.next_asks(160, 200)
	_check("First ask is the meter, the second a gamble", asks[0] == 200 and asks[1] >= 250)
	_check("Ask above the offer even past the meter", FareCalculator.next_asks(220, 200)[0] == 230)
	var fair: Dictionary = FareCalculator.respond(200, 220, 160, 2)
	_check("An ask within the limit closes the deal", bool(fair["accepted"]) and int(fair["patience"]) == 2)
	var push: Dictionary = FareCalculator.respond(230, 220, 160, 2)
	_check("A small overreach costs one patience and gets a counter", not bool(push["accepted"]) and not bool(push["walked"]) and int(push["patience"]) == 1 and int(push["offer"]) > 160 and int(push["offer"]) <= 220)
	var insult: Dictionary = FareCalculator.respond(300, 220, 160, 2)
	_check("A greedy ask costs double and ends the talk", bool(insult["insulted"]) and bool(insult["walked"]))
	var limit: int = 220
	var offer: int = 160
	var patience: int = 3
	for round_no: int in 2:
		var r: Dictionary = FareCalculator.respond(limit + 10, limit, offer, patience)
		_check("Counters climb but never pass the limit (%d)" % round_no, int(r["offer"]) > offer and int(r["offer"]) <= limit)
		offer = int(r["offer"])
		patience = int(r["patience"])
	var greedy_tip: Dictionary = FareCalculator.settle(300, it, 1.0, true, 0, 0.0, 200)
	var fair_tip: Dictionary = FareCalculator.settle(200, it, 1.0, true, 0, 0.0, 200)
	_check("Overcharged riders tip half", int(greedy_tip["comfort_tip"]) == int(fair_tip["comfort_tip"]) / 2)
	_check("Fair deals in a row pay a bonus", int(FareCalculator.settle(200, it, 1.0, true, 0, 0.0, 200, 3)["streak_bonus"]) == 15)

func _test_settlement() -> void:
	var it: PassengerArchetype = _rider("it_commuter")
	var college: PassengerArchetype = _rider("college_student")
	var smooth: Dictionary = FareCalculator.settle(100, it, 1.0, true, 0)
	_check("Smooth on-time ride earns full comfort tip", int(smooth["comfort_tip"]) == it.max_tip_inr and int(smooth["total"]) == 100 + it.max_tip_inr)
	var late: Dictionary = FareCalculator.settle(100, it, 1.0, false, 0)
	_check("Late ride: no tip, a star lost", int(late["comfort_tip"]) == 0 and float(late["stars"]) < float(smooth["stars"]))
	var gethu: Dictionary = FareCalculator.settle(80, college, 0.8, true, 3)
	_check("College student pays Gap-la Gethu bonus", int(gethu["gethu_bonus"]) == 3 * (FareCalculator.NEAR_MISS_BONUS_INR + college.near_miss_tip_inr))
	_check("Other riders don't pay for near misses", int(FareCalculator.settle(80, it, 0.8, true, 3)["gethu_bonus"]) == 0)

func _test_routing() -> void:
	var g: RoadGraph = RoadGraph.from_json_file("res://data/world/road_graph.json")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var ok_count: int = 0
	var legal: bool = true
	var continuous: bool = true
	var ends_ok: bool = true
	var tries: int = 25
	for t: int in tries:
		var a: Vector3 = g.nodes[rng.randi() % g.nodes.size()]
		var b: Vector3 = g.nodes[rng.randi() % g.nodes.size()]
		var r: Dictionary = g.find_route(a, b)
		if not bool(r.get("ok", false)):
			continue
		ok_count += 1
		var steps: Array = r["steps"]
		for i: int in steps.size():
			var e: RoadGraph.Edge = g.edges[int(steps[i][0])]
			var d: int = int(steps[i][1])
			if (d > 0 and e.lanes_fwd == 0) or (d < 0 and e.lanes_back == 0):
				legal = false
			if i > 0:
				var pe: RoadGraph.Edge = g.edges[int(steps[i - 1][0])]
				var pd: int = int(steps[i - 1][1])
				var exit_node: int = pe.b if pd > 0 else pe.a
				var entry_node: int = e.a if d > 0 else e.b
				if exit_node != entry_node:
					continuous = false
		var pts: PackedVector3Array = r["points"]
		if pts.size() < 2 or pts[0].distance_to(a) > 2.0 or pts[pts.size() - 1].distance_to(b) > 2.0:
			ends_ok = false
		if float(r["length"]) + 1.0 < Vector2(a.x - b.x, a.z - b.z).length():
			ends_ok = false
	_check("GPS finds routes between random junctions", ok_count >= tries - 2, "%d/%d" % [ok_count, tries])
	_check("Routes never drive the wrong way down a one-way", legal)
	_check("Route steps connect end to end", continuous)
	_check("Route polyline starts/ends at the requested points", ends_ok)

# --- Integration ----------------------------------------------------------------

func _kerb_ahead(savari: SavariManager, auto: AutoRickshawController, ahead_m: float) -> Vector3:
	var fwd: Vector3 = -auto.global_transform.basis.z
	var p: Vector3 = auto.global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * ahead_m
	return Vector3(p.x, 0.0, p.z)

func _stop(auto: AutoRickshawController) -> void:
	auto.linear_velocity = Vector3.ZERO
	auto.angular_velocity = Vector3.ZERO

func _test_haggle_timeout(savari: SavariManager, auto: AutoRickshawController) -> void:
	_events.clear()
	var respect_before: int = GameState.stand_respect_xp
	var wallet_before: int = GameState.wallet_inr
	_clear_hails(savari)
	savari.spawn_hail_at(_kerb_ahead(savari, auto, 3.0), _rider("tourist"))
	await _physics(10)
	_check("Stopping beside a hail opens the bargain card", _events.has("haggle_started") and savari.state == SavariManager.State.HAGGLING)
	if _events.has("haggle_started"):
		var info: Dictionary = _events["haggle_started"]
		var q: Array = info["asks"]
		_check("Offer ≤ meter ≤ asks", int(info["offer"]) <= int(info["meter"]) and int(info["meter"]) <= int(q[0]) and int(q[0]) < int(q[1]), str(q))
		_check("Haggle card names a destination", str(info["destination"]) != "", str(info["destination"]))
	await _physics(570) # > 9 s with no tap
	_check("No answer → rider walks off", _events.has("haggle_resolved") and not bool((_events["haggle_resolved"] as Dictionary)["accepted"]))
	_check("Walk-off costs Respect, not money", GameState.stand_respect_xp == respect_before + FareCalculator.RESPECT_XP_REJECTED and GameState.wallet_inr == wallet_before)
	_check("10 s cooldown after a rejection", savari.state == SavariManager.State.COOLDOWN)
	savari._state_timer = 0.0
	await _physics(2)

func _test_full_ride(savari: SavariManager, auto: AutoRickshawController, main: Node) -> void:
	_events.clear()
	_clear_hails(savari)
	var wallet_before: int = GameState.wallet_inr
	var rides_before: int = GameState.completed_savaris
	savari.spawn_hail_at(_kerb_ahead(savari, auto, 3.0), _rider("it_commuter"))
	await _physics(10)
	SignalBus.haggle_choice_made.emit(FareCalculator.Choice.ACCEPT)
	await _physics(3)
	_check("Correct Meter accepted → ride starts", savari.state == SavariManager.State.RIDING)
	_check("Passengers add mass to the auto", auto.mass > auto.stats.base_mass_kg)
	_check("GPS route published and drawn on the road", _events.has("route_updated") and (main.get_node("RouteLine") as MeshInstance3D).mesh != null)
	var dest: Vector3 = savari.destination["pos"]
	var bonus: Array[int] = [0]
	SignalBus.reward_granted.connect(func(_src: String, inr: int, _xp: int) -> void: bonus[0] += inr)
	SignalBus.driver_level_up.connect(func(_l: int, _t: String, inr: int, _u: String) -> void: bonus[0] += inr)
	# Teleport next to the destination (skips the drive) and stop.
	auto.global_transform = Transform3D(Basis.IDENTITY, dest + Vector3(0.0, 1.0, 0.0))
	_stop(auto)
	savari.comfort = 1.0 # teleporting registers as a crash; this test is about payout
	await _physics(30)
	_check("Stopping at the destination completes the ride", _events.has("ride_completed") and savari.state == SavariManager.State.PAYOUT)
	if _events.has("ride_completed"):
		var b: Dictionary = _events["ride_completed"]
		_check("Wallet credited with fare + tips", GameState.wallet_inr - bonus[0] == wallet_before + int(b["total"]) and int(b["total"]) >= int(b["fare"]), "₹%d" % int(b["total"]))
	_check("Ride counted for the stand rating", GameState.completed_savaris == rides_before + 1)
	_check("Passengers alight (mass restored)", is_equal_approx(auto.mass, auto.stats.base_mass_kg))
	savari._state_timer = 0.0
	await _physics(2)

func _test_comfort_and_near_miss(savari: SavariManager, auto: AutoRickshawController) -> void:
	_clear_hails(savari)
	savari.spawn_hail_at(_kerb_ahead(savari, auto, 3.0), _rider("tnagar_shopper"))
	await _physics(10)
	SignalBus.haggle_choice_made.emit(FareCalculator.Choice.ACCEPT)
	await _physics(3)
	if savari.state != SavariManager.State.RIDING:
		_check("Second ride starts", false)
		return
	savari.comfort = 1.0
	for i: int in 60:
		SignalBus.vehicle_dynamics.emit(1.1, 0.0, 0.0) # hard cornering at 1.1 g
	_check("Hard cornering spills the tea cup", savari.comfort < 0.8, "comfort %.2f" % savari.comfort)
	var c: float = savari.comfort
	SignalBus.vehicle_dynamics.emit(0.0, 0.0, 2.0) # speed breaker at speed
	_check("Speed breaker jolt spills more", savari.comfort < c)
	SignalBus.near_miss.emit(0.3)
	_check("Near misses are counted on the ride", savari.near_misses == 1)
	savari.complete_ride()
	savari._state_timer = 0.0
	await _physics(2)

func _test_near_miss_detector(traffic: ChennaiTrafficManager, auto: AutoRickshawController) -> void:
	_events.erase("near_miss")
	var v: TrafficVehicleAI = traffic.pool[0]
	if not v.active:
		traffic.place_vehicle(v, 0, traffic.graph.edges[0].length * 0.5, 1, 0)
	v.current_speed_mps = 10.0
	var fwd: Vector3 = -v.global_transform.basis.z
	var left: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	auto.global_transform = Transform3D(v.global_transform.basis, v.global_position + left * (v.half_width() + ChennaiTrafficManager.PLAYER_HALF_WIDTH_M + 0.35) + Vector3(0, 1.0, 0))
	auto.linear_velocity = fwd * 12.0 # 43 km/h
	traffic._near_miss_cooldown.clear()
	traffic._detect_near_misses(0.016)
	_check("Passing 0.35 m from a moving vehicle at 43 km/h = Gap-la Gethu", _events.has("near_miss"))
	_events.erase("near_miss")
	traffic._near_miss_cooldown.clear()
	auto.global_position += left * 1.5
	traffic._detect_near_misses(0.016)
	_check("Passing with 1.8 m to spare is not a near miss", not _events.has("near_miss"))
	_stop(auto)

func _clear_hails(savari: SavariManager) -> void:
	for h: Dictionary in savari.hails.duplicate():
		savari._remove_hail(h)

# --- Helpers ----------------------------------------------------------------------

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
