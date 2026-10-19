class_name ChennaiTrafficManager
extends Node3D
## Object-pooled mixed traffic driving on a RoadGraph (left-hand traffic, 3 sub-lanes
## per lane). Uses data/world/road_graph.json when `graph_path` is set, otherwise a
## straight one-way test strip along Z (the Phase 1 greybox).
## Hard limits from AGENTS.md: ≤ 18 active vehicles within 120 m; no instantiate()/queue_free()
## after _ready.

const MAX_POOL: int = 18
const RECYCLE_RADIUS_M: float = 120.0
const INDICATOR_YIELD_RANGE_M: float = 25.0
const INDICATOR_YIELD_S: float = 3.0
const SPAWN_MIN_AHEAD_M: float = 45.0
const SPAWN_MAX_AHEAD_M: float = 110.0
const GREYBOX_LENGTH_M: float = 3000.0
const GREYBOX_WIDTH_M: float = 13.2
## Mix for TWO_WHEELER, HATCHBACK, SHARE_AUTO, MTC_BUS, STRAY_COW (Chennai: lots of two-wheelers).
const ARCHETYPE_MIX: Array[int] = [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 0]
const ARCHETYPE_COLOURS: Array[Color] = [Color(0.15, 0.25, 0.75), Color(0.85, 0.85, 0.85), Color(0.2, 0.6, 0.25), Color(0.25, 0.45, 0.85), Color(0.93, 0.9, 0.84)]
## Zones (manifest ids) where stray cattle wander onto the road.
const MARKET_ZONES: PackedStringArray = ["mylapore", "t_nagar"]

@export var vehicle_scene: PackedScene
@export var player_path: NodePath
## res:// path of road_graph.json. Empty = greybox straight road.
@export var graph_path: String = ""
@export var active_count: int = 12

var graph: RoadGraph
var pool: Array[TrafficVehicleAI] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _player: Node3D
var _respawn_queue: Array[TrafficVehicleAI] = []
var _market_zones: Array[Vector3] = [] # x, z, radius
var _cow_retry_timer: float = 0.0
var _near_miss_cooldown: Dictionary = {} # vehicle -> seconds left
const NEAR_MISS_CLEARANCE_M: float = 0.6
const NEAR_MISS_MIN_SPEED_KMH: float = 35.0
const PLAYER_HALF_WIDTH_M: float = 0.65

func _ready() -> void:
	rng.seed = 600028
	_player = get_node_or_null(player_path) as Node3D
	graph = RoadGraph.from_json_file(graph_path) if graph_path != "" else _build_greybox_graph()
	_load_market_zones()
	SignalBus.current_road_graph = graph
	SignalBus.road_graph_ready.emit.call_deferred(graph)
	var materials: Array[StandardMaterial3D] = []
	for c: Color in ARCHETYPE_COLOURS:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = c
		materials.append(m)
	for i: int in MAX_POOL:
		var v: TrafficVehicleAI = vehicle_scene.instantiate() as TrafficVehicleAI
		v.name = "Traffic_%02d" % i
		v.position = Vector3(0.0, -200.0, float(i) * 15.0) # parked far below the map
		add_child(v)
		var kind: TrafficVehicleAI.Archetype = ARCHETYPE_MIX[i % ARCHETYPE_MIX.size()] as TrafficVehicleAI.Archetype
		v.setup(self, kind, materials[kind])
		pool.append(v)
	SignalBus.horn_blasted.connect(_on_horn_blasted)
	SignalBus.indicator_changed.connect(_on_player_indicator)
	_initial_spawn.call_deferred()

func _load_market_zones() -> void:
	if graph_path == "":
		return
	var f: FileAccess = FileAccess.open(graph_path.get_base_dir().path_join("manifest.json"), FileAccess.READ)
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	for z: Dictionary in m.get("zones", []):
		if MARKET_ZONES.has(str(z["id"])):
			_market_zones.append(Vector3(float(z["x"]), float(z["z"]), float(z["r"])))

func in_market_zone(p: Vector3) -> bool:
	for z: Vector3 in _market_zones:
		if Vector2(p.x - z.x, p.z - z.y).length() <= z.z:
			return true
	return false

func _build_greybox_graph() -> RoadGraph:
	var g: RoadGraph = RoadGraph.new()
	var a: int = g.add_node(Vector3(0.0, 0.0, GREYBOX_LENGTH_M * 0.5))
	var b: int = g.add_node(Vector3(0.0, 0.0, -GREYBOX_LENGTH_M * 0.5))
	g.add_edge(a, b, PackedVector3Array([g.nodes[a], g.nodes[b]]), GREYBOX_WIDTH_M, 2, 0, "trunk", "Anna Salai test strip")
	return g

func _initial_spawn() -> void:
	for i: int in pool.size():
		if i < active_count or pool[i].archetype == TrafficVehicleAI.Archetype.STRAY_COW:
			_respawn(pool[i])

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	for v: TrafficVehicleAI in pool:
		if not v.active:
			continue
		v.tick(delta)
		if v.active and v.global_position.distance_to(_player.global_position) > RECYCLE_RADIUS_M:
			_respawn_queue.append(v)
	_detect_near_misses(delta)
	# Parked cattle retry every few seconds (they only appear in market zones).
	_cow_retry_timer += delta
	if _cow_retry_timer > 3.0 and not _market_zones.is_empty():
		_cow_retry_timer = 0.0
		for v: TrafficVehicleAI in pool:
			if not v.active and v.archetype == TrafficVehicleAI.Archetype.STRAY_COW and not _respawn_queue.has(v):
				_respawn_queue.append(v)
	# Respawn at most 2 per tick to keep frame time flat.
	var n: int = 0
	while not _respawn_queue.is_empty() and n < 2:
		_respawn(_respawn_queue.pop_front())
		n += 1

## "Gap-la Gethu": the player squeezes past a moving vehicle with < 0.6 m to spare
## above 35 km/h without touching it. One event per vehicle per pass.
func _detect_near_misses(delta: float) -> void:
	for v: Variant in _near_miss_cooldown.keys():
		_near_miss_cooldown[v] = float(_near_miss_cooldown[v]) - delta
		if float(_near_miss_cooldown[v]) <= 0.0:
			_near_miss_cooldown.erase(v)
	var body: RigidBody3D = _player as RigidBody3D
	if body == null or body.linear_velocity.length() * 3.6 < NEAR_MISS_MIN_SPEED_KMH:
		return
	for v: TrafficVehicleAI in pool:
		if not v.active or v.current_speed_mps < 1.0 or _near_miss_cooldown.has(v):
			continue
		var rel: Vector3 = _player.global_position - v.global_position
		if rel.length() > 8.0:
			continue
		var fwd: Vector3 = -v.global_transform.basis.z
		var along: float = absf(rel.dot(fwd))
		var lateral: float = absf(rel.dot(Vector3(fwd.z, 0.0, -fwd.x)))
		var clearance: float = lateral - v.half_width() - PLAYER_HALF_WIDTH_M
		if along < v.half_length() + 1.4 and clearance > 0.05 and clearance < NEAR_MISS_CLEARANCE_M:
			_near_miss_cooldown[v] = 2.0
			SignalBus.near_miss.emit(clearance)

func request_respawn(v: TrafficVehicleAI) -> void:
	if not _respawn_queue.has(v):
		_respawn_queue.append(v)

func active_vehicles() -> Array[TrafficVehicleAI]:
	var out: Array[TrafficVehicleAI] = []
	for v: TrafficVehicleAI in pool:
		if v.active:
			out.append(v)
	return out

## Which sub-lane a world position sits in on (edge, dir).
func sub_lane_at(edge_idx: int, dir: int, world_pos: Vector3) -> int:
	var cp: Dictionary = graph.closest_point(world_pos)
	var e: int = int(cp["edge"]) if int(cp["edge"]) >= 0 else edge_idx
	var pd: Array[Vector3] = graph.sample(e, float(cp["s"]), dir)
	var left: Vector3 = Vector3(pd[1].z, 0.0, -pd[1].x)
	var lat: float = (world_pos - pd[0]).dot(left)
	var best: int = 0
	var best_d: float = INF
	for i: int in graph.sub_lane_count(e, dir):
		var d: float = absf(graph.sub_lane_offset(e, dir, i) - lat)
		if d < best_d:
			best_d = d
			best = i
	return best

## Put a pooled vehicle at an exact graph position (used by spawning and tests).
func place_vehicle(v: TrafficVehicleAI, edge_idx: int, edge_s: float, dir: int, lane: int) -> void:
	var travelled: float = edge_s if dir > 0 else graph.edges[edge_idx].length - edge_s
	v.place(edge_idx, travelled, dir, lane)

## Distance from `me`'s front bumper to the nearest obstacle in its corridor:
## other AI on the same edge & direction, and the player auto.
func gap_ahead(me: TrafficVehicleAI) -> float:
	var best: float = INF
	for o: TrafficVehicleAI in pool:
		if o == me or not o.active or o.edge != me.edge or o.dir != me.dir:
			continue
		if absf(o.lateral - me.lateral) > me.half_width() + o.half_width():
			continue
		var gap: float = (o.t - o.half_length()) - (me.t + me.half_length())
		if gap > -0.5 and gap < best:
			best = gap
	if _player != null:
		var fwd: Vector3 = -me.global_transform.basis.z
		var to_p: Vector3 = _player.global_position - me.global_position
		var along: float = to_p.dot(fwd)
		var side: float = absf(to_p.dot(Vector3(fwd.z, 0.0, -fwd.x)))
		if along > 0.0 and side < me.half_width() + 0.9:
			best = minf(best, along - me.half_length() - 1.4)
	return best

func is_sub_lane_free(me: TrafficVehicleAI, lane: int) -> bool:
	var lat: float = graph.sub_lane_offset(me.edge, me.dir, lane)
	for o: TrafficVehicleAI in pool:
		if o == me or not o.active or o.edge != me.edge or o.dir != me.dir:
			continue
		if absf(o.lateral - lat) > me.half_width() + o.half_width() + 0.2:
			continue
		if absf(o.t - me.t) < me.half_length() + o.half_length() + 2.0:
			return false
	return true

func _respawn(v: TrafficVehicleAI) -> void:
	if _player == null:
		v.deactivate()
		return
	var heading: Vector3 = -_player.global_transform.basis.z
	var candidates: Array[Dictionary] = graph.spawn_candidates(_player.global_position, heading, SPAWN_MIN_AHEAD_M, SPAWN_MAX_AHEAD_M)
	var is_cow: bool = v.archetype == TrafficVehicleAI.Archetype.STRAY_COW
	if is_cow:
		# Cattle only wander in market zones, ambling along the kerb.
		var in_zone: Array[Dictionary] = []
		for c: Dictionary in candidates:
			if in_market_zone(graph.sample(int(c["edge"]), float(c["s"]), 1)[0]):
				in_zone.append(c)
		candidates = in_zone
	for attempt: int in 8:
		if candidates.is_empty():
			break
		var c: Dictionary = candidates[rng.randi() % candidates.size()]
		var lanes: int = graph.sub_lane_count(int(c["edge"]), int(c["dir"]))
		var lane: int = 0 if is_cow else rng.randi() % maxi(lanes, 1)
		place_vehicle(v, int(c["edge"]), float(c["s"]), int(c["dir"]), lane)
		if _spawn_spot_free(v):
			return
	v.deactivate()

func _spawn_spot_free(v: TrafficVehicleAI) -> bool:
	for o: TrafficVehicleAI in pool:
		if o == v or not o.active:
			continue
		if o.global_position.distance_to(v.global_position) < v.half_length() + o.half_length() + 3.0:
			return false
	if _player != null and _player.global_position.distance_to(v.global_position) < 15.0:
		return false
	return true

## Vehicles just behind the player, on the side being signalled, give way (Chennai traffic
## won't always — but an indicator should help). Buses and cows don't bother.
func _on_player_indicator(direction: int) -> void:
	if direction == 0 or _player == null:
		return
	var fwd: Vector3 = -_player.global_transform.basis.z
	var left: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	for v: TrafficVehicleAI in pool:
		if not v.active or v.archetype in [TrafficVehicleAI.Archetype.MTC_BUS, TrafficVehicleAI.Archetype.STRAY_COW]:
			continue
		var to_v: Vector3 = v.global_position - _player.global_position
		var behind: float = -to_v.dot(fwd)
		var side: float = to_v.dot(left) * float(-direction) # >0 on the signalled side (left = -1)
		if behind > -3.0 and behind < INDICATOR_YIELD_RANGE_M and side > -1.0 and side < 7.0:
			v.give_way(INDICATOR_YIELD_S)

func _on_horn_blasted(origin: Vector3, forward_dir: Vector3, radius_m: float, horn_tier: int) -> void:
	for v: TrafficVehicleAI in pool:
		if not v.active or not v.reacts_to_horn(horn_tier):
			continue
		var to_v: Vector3 = v.global_position - origin
		to_v.y = 0.0
		if to_v.length() > radius_m or to_v.normalized().dot(forward_dir) < 0.25: # forward cone only
			continue
		# Move away from the horn: if the player is on the vehicle's left, shift right (+1).
		var fwd: Vector3 = -v.global_transform.basis.z
		var left: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
		var player_on_left: bool = (origin - v.global_position).dot(left) >= 0.0
		v.hear_horn(1 if player_on_left else -1)
