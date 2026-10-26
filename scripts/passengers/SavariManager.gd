class_name SavariManager
extends Node3D
## "Savari Mode" — the passenger pick-and-drop loop (GDD §1, Phase 3).
##
##   CRUISING ──(stop next to a hail)──▶ HAGGLING ──accept──▶ RIDING ──(stop at destination)──▶ PAYOUT
##        ▲                                   │ reject / 5 s timeout                                 │
##        └──────────────── 10 s cooldown ◀───┘◀─────────────────────────────────────────────────────┘
##
## Talks to everything else only through SignalBus. Hails are pooled (no runtime instantiate).

enum State { CRUISING, HAGGLING, RIDING, PAYOUT, COOLDOWN }

const MAX_HAILS: int = 3
const HAIL_MIN_AHEAD_M: float = 50.0
const HAIL_MAX_AHEAD_M: float = 170.0
const HAIL_DESPAWN_M: float = 260.0
const HAIL_LIFETIME_S: float = 120.0
const STAND_HAIL_RADIUS_M: float = 220.0
const PICKUP_RADIUS_M: float = 7.5
const DROPOFF_RADIUS_M: float = 14.0
const STOPPED_KMH: float = 6.0
const HAGGLE_SECONDS: float = 5.0
const REJECT_COOLDOWN_S: float = 10.0
const PAYOUT_SECONDS: float = 3.0
## Straight-line trip length (real metres, the map is 1 : 1): ~0.8–3 km by road, 2–5 min.
const MIN_TRIP_M: float = 600.0
const MAX_TRIP_M: float = 2400.0
const REROUTE_OFF_ROUTE_M: float = 30.0
const RIDE_UPDATE_INTERVAL_S: float = 0.2
## Which low-poly person each passenger archetype looks like (PersonMesh.Style).
const ARCHETYPE_STYLE: Dictionary = {
	"it_commuter": PersonMesh.Style.SHIRT_TROUSERS,
	"tnagar_shopper": PersonMesh.Style.SAREE,
	"tourist": PersonMesh.Style.TOURIST,
	"monsoon_rider": PersonMesh.Style.VESHTI,
	"college_student": PersonMesh.Style.TSHIRT_JEANS,
}

@export var world_dir: String = "res://data/world"
@export var archetypes: Array[PassengerArchetype] = []
@export var rng_seed: int = 600005

var state: State = State.CRUISING
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var graph: RoadGraph
var hails: Array[Dictionary] = [] # {id, pos, archetype, age, node, at_stand}
var destinations: Array[Dictionary] = [] # {name, pos, kind}
var zones: Array[Dictionary] = []

# Ride state.
var rider: PassengerArchetype
var destination: Dictionary = {}
var route: Dictionary = {}
var agreed_offer: int = 0
var agreed_fare: int = 0
var comfort: float = 1.0
var time_left_s: float = 0.0
var near_misses: int = 0
var _haggle_timer: float = 0.0
var _haggle_hail: Dictionary = {}
var _haggle_quotes: Array[int] = []
var _haggle_trip_km: float = 0.0
var _state_timer: float = 0.0
var _ride_update_timer: float = 0.0
var _reroute_timer: float = 0.0
var _next_hail_id: int = 1

var _player_pos: Vector3 = Vector3.ZERO
var _player_fwd: Vector3 = Vector3.FORWARD
var _speed_kmh: float = 0.0
var _hail_pool: Array[Node3D] = []
var _dest_marker: Node3D
var _comfort_damping: float = 1.0
## Haggling context: rider demand from the traffic model, and how greedy we've been lately.
var demand: float = 0.5
var greed_streak: int = 0

func _ready() -> void:
	rng.seed = rng_seed
	if archetypes.is_empty():
		for id: String in ["it_commuter", "tnagar_shopper", "tourist", "monsoon_rider", "college_student"]:
			var a: PassengerArchetype = load("res://data/passengers/%s.tres" % id) as PassengerArchetype
			if a != null:
				archetypes.append(a)
	_load_manifest()
	_build_pools()
	SignalBus.player_pose_updated.connect(_on_pose)
	SignalBus.speed_updated.connect(func(kmh: float) -> void: _speed_kmh = kmh)
	SignalBus.haggle_choice_made.connect(_on_haggle_choice)
	SignalBus.traffic_density_changed.connect(func(d: float, _zone: String, _peak: bool) -> void:
		demand = TrafficDensity.rider_demand(d, GameState.is_raining))
	SignalBus.vehicle_dynamics.connect(_on_dynamics)
	SignalBus.player_collision.connect(_on_collision)
	SignalBus.near_miss.connect(_on_near_miss)
	SignalBus.road_graph_ready.connect(func(g: RoadGraph) -> void: graph = g)
	graph = SignalBus.current_road_graph
	_comfort_damping = GameState.active_stats().comfort_damping
	SignalBus.vehicle_loadout_changed.connect(func(s: VehicleStats) -> void: _comfort_damping = s.comfort_damping)

func _load_manifest() -> void:
	var f: FileAccess = FileAccess.open(world_dir.path_join("manifest.json"), FileAccess.READ)
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	for l: Dictionary in m.get("landmarks", []):
		destinations.append({"name": str(l["name"]), "pos": Vector3(float(l["x"]), 0.0, float(l["z"])), "kind": "landmark"})
	for s: Dictionary in m.get("auto_stands", []):
		destinations.append({"name": str(s["name"]), "pos": Vector3(float(s["x"]), 0.0, float(s["z"])), "kind": "stand"})
	for z: Dictionary in m.get("zones", []):
		zones.append({"id": str(z["id"]), "name": str(z["name"]), "pos": Vector3(float(z["x"]), 0.0, float(z["z"])), "r": float(z["r"])})
		destinations.append({"name": str(z["name"]), "pos": Vector3(float(z["x"]), 0.0, float(z["z"])), "kind": "zone"})

func _physics_process(delta: float) -> void:
	if graph == null:
		graph = SignalBus.current_road_graph
		if graph == null:
			return
	_age_hails(delta)
	_animate_hails()
	match state:
		State.CRUISING:
			_maintain_hails()
			_check_pickup()
		State.HAGGLING:
			_haggle_timer -= delta
			if _haggle_timer <= 0.0:
				_resolve_haggle(-1) # passenger got bored and walked off
		State.RIDING:
			_tick_ride(delta)
		State.PAYOUT, State.COOLDOWN:
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = State.CRUISING

# --- Hails -------------------------------------------------------------------

func zone_at(p: Vector3) -> String:
	for z: Dictionary in zones:
		if Vector2(p.x - (z["pos"] as Vector3).x, p.z - (z["pos"] as Vector3).z).length() <= float(z["r"]):
			return str(z["id"])
	return ""

func pick_archetype(zone_id: String) -> PassengerArchetype:
	var total: float = 0.0
	var weights: Array[float] = []
	for a: PassengerArchetype in archetypes:
		var w: float = a.spawn_weight * (2.0 if zone_id != "" and a.home_zones.has(zone_id) else 1.0)
		if a.surge_multiplier > 1.0 and not GameState.is_raining and not GameState.is_night():
			w *= 0.15 # monsoon / late-night riders are rare on dry days
		elif a.surge_multiplier > 1.0:
			w *= 2.5
		weights.append(w)
		total += w
	var roll: float = rng.randf() * total
	for i: int in archetypes.size():
		roll -= weights[i]
		if roll <= 0.0:
			return archetypes[i]
	return archetypes[archetypes.size() - 1]

## Public so tests (and later, scripted missions) can place a hail exactly.
func spawn_hail_at(pos: Vector3, archetype: PassengerArchetype, at_stand: bool = false) -> Dictionary:
	var node: Node3D = null
	for n: Node3D in _hail_pool:
		if not n.visible:
			node = n
			break
	if node == null:
		return {}
	var h: Dictionary = {"id": _next_hail_id, "pos": pos, "archetype": archetype, "age": 0.0, "node": node, "at_stand": at_stand}
	_next_hail_id += 1
	node.global_position = pos
	var body: MeshInstance3D = node.get_node("Body") as MeshInstance3D
	var style: PersonMesh.Style = ARCHETYPE_STYLE.get(archetype.id, PersonMesh.Style.SHIRT_TROUSERS) as PersonMesh.Style
	var variant: int = rng.randi() % 12
	body.mesh = PersonMesh.standing(style, variant, true)
	(node.get_node("WaveArm") as MeshInstance3D).mesh = PersonMesh.wave_arm(style, variant)
	# Face the road / the approaching auto.
	var to_player: Vector3 = _player_pos - pos
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		node.global_basis = Basis.looking_at(to_player.normalized(), Vector3.UP)
	(node.get_node("Label") as Label3D).text = archetype.archetype_name
	node.visible = true
	hails.append(h)
	_publish_hails()
	return h

func _maintain_hails() -> void:
	if hails.size() >= MAX_HAILS:
		return
	# Auto stands nearby always have a rider waiting.
	for d: Dictionary in destinations:
		if str(d["kind"]) != "stand":
			continue
		var p: Vector3 = d["pos"]
		if p.distance_to(_player_pos) < STAND_HAIL_RADIUS_M and p.distance_to(_player_pos) > 25.0 and not _hail_near(p, 20.0):
			spawn_hail_at(_kerb_point(p), pick_archetype(zone_at(p)), true)
			return
	var cands: Array[Dictionary] = graph.spawn_candidates(_player_pos, _player_fwd, HAIL_MIN_AHEAD_M, HAIL_MAX_AHEAD_M)
	if cands.is_empty():
		return
	var c: Dictionary = cands[rng.randi() % cands.size()]
	var pd: Array[Vector3] = graph.sample(int(c["edge"]), float(c["s"]), int(c["dir"]))
	var left: Vector3 = Vector3(pd[1].z, 0.0, -pd[1].x)
	var pos: Vector3 = pd[0] + left * (graph.edges[int(c["edge"])].width * 0.5 + 0.9)
	if not _hail_near(pos, 40.0):
		spawn_hail_at(pos, pick_archetype(zone_at(pos)))

func _kerb_point(p: Vector3) -> Vector3:
	var cp: Dictionary = graph.closest_point(p)
	if int(cp["edge"]) < 0:
		return p
	var pd: Array[Vector3] = graph.sample(int(cp["edge"]), float(cp["s"]), 1)
	var left: Vector3 = Vector3(pd[1].z, 0.0, -pd[1].x)
	var side: float = signf((p - pd[0]).dot(left))
	return pd[0] + left * (side if side != 0.0 else 1.0) * (graph.edges[int(cp["edge"])].width * 0.5 + 0.9)

func _hail_near(p: Vector3, r: float) -> bool:
	for h: Dictionary in hails:
		if (h["pos"] as Vector3).distance_to(p) < r:
			return true
	return false

func _age_hails(delta: float) -> void:
	var changed: bool = false
	for i: int in range(hails.size() - 1, -1, -1):
		var h: Dictionary = hails[i]
		h["age"] = float(h["age"]) + delta
		if h == _haggle_hail:
			continue
		var far: bool = (h["pos"] as Vector3).distance_to(_player_pos) > HAIL_DESPAWN_M
		if far or float(h["age"]) > HAIL_LIFETIME_S:
			_remove_hail(h)
			changed = true
	if changed:
		_publish_hails()

func _remove_hail(h: Dictionary) -> void:
	(h["node"] as Node3D).visible = false
	hails.erase(h)

func _publish_hails() -> void:
	var out: Array = []
	for h: Dictionary in hails:
		out.append({"id": h["id"], "position": h["pos"], "archetype": (h["archetype"] as PassengerArchetype).id})
	SignalBus.hails_updated.emit(out)

func _check_pickup() -> void:
	if _speed_kmh > STOPPED_KMH:
		return
	for h: Dictionary in hails:
		if Vector2((h["pos"] as Vector3).x - _player_pos.x, (h["pos"] as Vector3).z - _player_pos.z).length() <= PICKUP_RADIUS_M:
			start_haggle(h)
			return

# --- Haggling -----------------------------------------------------------------

func start_haggle(h: Dictionary) -> void:
	var a: PassengerArchetype = h["archetype"]
	destination = _choose_destination(a)
	route = graph.find_route(_player_pos, destination["pos"])
	if not bool(route.get("ok", false)):
		_remove_hail(h)
		_publish_hails()
		return
	state = State.HAGGLING
	_haggle_hail = h
	_haggle_timer = HAGGLE_SECONDS
	_haggle_trip_km = float(route["length"]) / 1000.0
	_haggle_quotes.clear()
	var odds: Array[float] = []
	for o: int in 3:
		_haggle_quotes.append(FareCalculator.quote(o as FareCalculator.Offer, _haggle_trip_km, a))
		odds.append(_odds(o, a))
	SignalBus.haggle_started.emit({
		"archetype": a.id, "name": a.archetype_name, "line": a.line_hail,
		"destination": destination["name"], "distance_km": _haggle_trip_km * FareCalculator.REAL_KM_PER_GAME_KM,
		"quotes": _haggle_quotes.duplicate(), "odds": odds, "offers": FareCalculator.OFFER_NAMES,
	}, HAGGLE_SECONDS)

func _choose_destination(a: PassengerArchetype) -> Dictionary:
	var options: Array[Dictionary] = []
	for d: Dictionary in destinations:
		var dist: float = (d["pos"] as Vector3).distance_to(_player_pos)
		if dist >= MIN_TRIP_M and dist <= MAX_TRIP_M:
			options.append(d)
			if a.id == "tourist" and str(d["kind"]) == "landmark":
				options.append(d) # tourists love landmarks
	if options.is_empty():
		# Fallback: any road point at a sensible distance.
		var cands: Array[Dictionary] = graph.spawn_candidates(_player_pos, Vector3.ZERO, MIN_TRIP_M, 1500.0)
		if not cands.is_empty():
			var c: Dictionary = cands[rng.randi() % cands.size()]
			var p: Vector3 = graph.sample(int(c["edge"]), float(c["s"]), 1)[0]
			var nm: String = graph.edges[int(c["edge"])].road_name
			return {"name": nm if nm != "" else "Nearby street", "pos": p, "kind": "street"}
		return {"name": "Nearby street", "pos": _player_pos + _player_fwd * 400.0, "kind": "street"}
	return options[rng.randi() % options.size()]

func _odds(offer: int, a: PassengerArchetype) -> float:
	return FareCalculator.acceptance_chance(offer as FareCalculator.Offer, a, GameState.is_raining, GameState.prestige(),
		_haggle_quotes[0] if not _haggle_quotes.is_empty() else 0, demand, GameState.star_rating, greed_streak)

func _on_haggle_choice(offer: int) -> void:
	if state == State.HAGGLING:
		_resolve_haggle(offer)

func _resolve_haggle(offer: int) -> void:
	var a: PassengerArchetype = _haggle_hail["archetype"]
	var accepted: bool = false
	if offer >= 0:
		accepted = rng.randf() < _odds(offer, a)
	# Greed memory: asking above meter raises the streak (more if refused); honest meter rides
	# calm the stand down again.
	if offer == FareCalculator.Offer.METER:
		greed_streak = maxi(0, greed_streak - 2)
	elif offer > 0:
		greed_streak = mini(greed_streak + (2 if not accepted else 1), FareCalculator.MAX_GREED_STREAK)
	_remove_hail(_haggle_hail)
	_haggle_hail = {}
	_publish_hails()
	if not accepted:
		# Walking away from a greedy fixed-rate ask hurts the stand's opinion more.
		GameState.add_respect(FareCalculator.RESPECT_XP_REJECTED * (4 if offer == FareCalculator.Offer.FIXED else (2 if offer == FareCalculator.Offer.METER_MELA else 1)))
		SignalBus.haggle_resolved.emit({"accepted": false, "offer": offer, "fare": 0, "line": a.line_reject})
		state = State.COOLDOWN
		_state_timer = REJECT_COOLDOWN_S
		return
	rider = a
	agreed_offer = offer
	agreed_fare = _haggle_quotes[offer]
	comfort = 1.0
	near_misses = 0
	time_left_s = FareCalculator.ride_time_limit_s(float(route["length"]), a)
	state = State.RIDING
	SignalBus.haggle_resolved.emit({"accepted": true, "offer": offer, "fare": agreed_fare, "line": a.line_accept})
	SignalBus.passenger_boarded.emit(a.party_size, a.luggage_kg)
	_publish_route(route)
	_dest_marker.global_position = destination["pos"]
	_dest_marker.visible = true

# --- Riding --------------------------------------------------------------------

func _tick_ride(delta: float) -> void:
	time_left_s -= delta
	var dest: Vector3 = destination["pos"]
	var flat_dist: float = Vector2(dest.x - _player_pos.x, dest.z - _player_pos.z).length()
	if flat_dist <= DROPOFF_RADIUS_M and _speed_kmh <= STOPPED_KMH:
		complete_ride()
		return
	_reroute_timer -= delta
	if _reroute_timer <= 0.0:
		_reroute_timer = 2.0
		if _distance_to_route() > REROUTE_OFF_ROUTE_M:
			var r: Dictionary = graph.find_route(_player_pos, dest)
			if bool(r.get("ok", false)):
				route = r
				_publish_route(route)
	_ride_update_timer -= delta
	if _ride_update_timer <= 0.0:
		_ride_update_timer = RIDE_UPDATE_INTERVAL_S
		SignalBus.ride_updated.emit({
			"destination": destination["name"], "remaining_m": _remaining_route_m(),
			"time_left_s": time_left_s, "comfort": comfort, "fare": agreed_fare,
			"near_misses": near_misses, "archetype": rider.archetype_name,
		})

## Sat-nav: the lane-offset, corner-rounded guide line + turn-by-turn for the GPS (RouteLine),
## the mini-map and the full map. An empty route clears them.
func _publish_route(r: Dictionary) -> void:
	if r.is_empty():
		SignalBus.route_updated.emit(PackedVector3Array())
		SignalBus.gps_route_changed.emit(null)
		return
	var gps: GpsRoute = GpsRoute.build(graph, r)
	SignalBus.route_updated.emit(gps.path)
	SignalBus.gps_route_changed.emit(gps)

func complete_ride() -> void:
	var on_time: bool = time_left_s >= 0.0
	var vs: VehicleStats = GameState.active_stats()
	var green: float = vs.green_tip_bonus if rider.id == "it_commuter" else 0.0
	var b: Dictionary = FareCalculator.settle(agreed_fare, rider, comfort, on_time, near_misses, green)
	b["destination"] = destination["name"]
	b["archetype_name"] = rider.archetype_name
	b["archetype"] = rider.id
	b["distance_km"] = _haggle_trip_km * FareCalculator.REAL_KM_PER_GAME_KM
	b["line"] = rider.line_happy if comfort >= 0.5 and on_time else rider.line_upset
	b["offer"] = agreed_offer
	b["comfort"] = comfort
	b["near_misses"] = near_misses
	# Unique per ride: rewarded "2× fare" can be claimed once for this ride only.
	b["ride_id"] = "d%d-r%d-%d" % [GameState.day, GameState.completed_savaris + 1, Time.get_ticks_msec()]
	GameState.add_inr(int(b["total"]))
	GameState.add_respect(FareCalculator.RESPECT_XP[agreed_offer])
	GameState.record_ride_rating(float(b["stars"]))
	SignalBus.passenger_alighted.emit()
	_publish_route({})
	SignalBus.ride_completed.emit(b)
	_dest_marker.visible = false
	rider = null
	state = State.PAYOUT
	_state_timer = PAYOUT_SECONDS

func _distance_to_route() -> float:
	var pts: PackedVector3Array = route.get("points", PackedVector3Array())
	var best: float = INF
	for i: int in range(1, pts.size()):
		var q: Vector3 = Geometry3D.get_closest_point_to_segment(_player_pos, pts[i - 1], pts[i])
		best = minf(best, Vector2(q.x - _player_pos.x, q.z - _player_pos.z).length())
	return best

func _remaining_route_m() -> float:
	var pts: PackedVector3Array = route.get("points", PackedVector3Array())
	if pts.size() < 2:
		return 0.0
	var best_i: int = 1
	var best_d: float = INF
	for i: int in range(1, pts.size()):
		var q: Vector3 = Geometry3D.get_closest_point_to_segment(_player_pos, pts[i - 1], pts[i])
		var d: float = q.distance_to(_player_pos)
		if d < best_d:
			best_d = d
			best_i = i
	var total: float = Vector2(pts[best_i].x - _player_pos.x, pts[best_i].z - _player_pos.z).length()
	for i: int in range(best_i + 1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	return total

# --- Comfort (the dashboard tea cup) -------------------------------------------

func _on_dynamics(lateral_g: float, longitudinal_g: float, vertical_jolt: float) -> void:
	if state != State.RIDING:
		return
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var tol: float = rider.comfort_tolerance_g
	var spill: float = 0.0
	if absf(lateral_g) > tol:
		spill += (absf(lateral_g) - tol) * 0.6 * dt
	if longitudinal_g < -0.55: # hard braking
		spill += (-longitudinal_g - 0.55) * 0.4 * dt
	if vertical_jolt > 0.9: # speed breaker / pothole at speed
		spill += minf((vertical_jolt - 0.9) * 0.08, 0.15)
	spill *= _comfort_damping
	if rider.likes_fast_driving:
		spill *= 0.35
		if _speed_kmh < 20.0:
			spill += 0.004 * dt # bored
	comfort = clampf(comfort - spill, 0.0, 1.0)

func _on_collision(impulse: float) -> void:
	if state == State.RIDING:
		comfort = clampf(comfort - clampf(impulse * 0.04, 0.05, 0.35), 0.0, 1.0)

func _on_near_miss(_clearance_m: float) -> void:
	if state != State.RIDING:
		return
	near_misses += 1
	comfort = clampf(comfort + (0.05 if rider.likes_fast_driving else -0.06), 0.0, 1.0)

func _on_pose(pos: Vector3, fwd: Vector3) -> void:
	_player_pos = pos
	_player_fwd = fwd

# --- Visual pools ----------------------------------------------------------------

## Hailing passengers wave their raised arm ("Auto!") — one rotation per visible hail.
func _animate_hails() -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for h: Dictionary in hails:
		var n: Node3D = h["node"]
		var arm: Node3D = n.get_node_or_null("WaveArm") as Node3D
		if arm != null:
			arm.rotation.z = -0.35 + sin(t * 7.0 + float(h["id"])) * 0.45

func _build_pools() -> void:
	var beam: CylinderMesh = CylinderMesh.new()
	beam.top_radius = 0.35
	beam.bottom_radius = 0.35
	beam.height = 9.0
	var beam_mat: StandardMaterial3D = StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(1.0, 0.82, 0.1, 0.35)
	beam.material = beam_mat
	for i: int in MAX_HAILS + 1:
		var n: Node3D = Node3D.new()
		n.name = "Hail_%d" % i
		n.visible = false
		var body: MeshInstance3D = MeshInstance3D.new()
		body.name = "Body"
		body.mesh = PersonMesh.standing(PersonMesh.Style.SHIRT_TROUSERS, i, true)
		n.add_child(body)
		var arm: MeshInstance3D = MeshInstance3D.new()
		arm.name = "WaveArm"
		arm.mesh = PersonMesh.wave_arm(PersonMesh.Style.SHIRT_TROUSERS, i)
		arm.position = Vector3(0.21, 1.38, 0.0)
		n.add_child(arm)
		var b: MeshInstance3D = MeshInstance3D.new()
		b.mesh = beam
		b.position.y = 4.5
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(b)
		var label: Label3D = Label3D.new()
		label.name = "Label"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 2.4
		label.font_size = 48
		label.outline_size = 12
		label.no_depth_test = true
		n.add_child(label)
		add_child(n)
		_hail_pool.append(n)
	_dest_marker = Node3D.new()
	_dest_marker.name = "DestinationMarker"
	_dest_marker.visible = false
	var ring: CylinderMesh = CylinderMesh.new()
	ring.top_radius = DROPOFF_RADIUS_M * 0.6
	ring.bottom_radius = DROPOFF_RADIUS_M * 0.6
	ring.height = 14.0
	ring.cap_top = false
	ring.cap_bottom = false
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.albedo_color = Color(0.2, 1.0, 0.45, 0.28)
	ring.material = ring_mat
	var rmi: MeshInstance3D = MeshInstance3D.new()
	rmi.mesh = ring
	rmi.position.y = 7.0
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dest_marker.add_child(rmi)
	add_child(_dest_marker)
