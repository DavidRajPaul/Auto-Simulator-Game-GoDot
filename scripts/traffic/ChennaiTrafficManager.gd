class_name ChennaiTrafficManager
extends Node3D
## Object-pooled mixed traffic driving on a RoadGraph (left-hand traffic, 3 sub-lanes
## per lane). Uses data/world/road_graph.json when `graph_path` is set, otherwise a
## straight one-way test strip along Z (the Phase 1 greybox).
## Hard limits from AGENTS.md: ≤ 18 active vehicles within 120 m; no instantiate()/queue_free()
## after _ready.

const MAX_POOL: int = 18
## Recycle far vehicles only where the camera can't see them; on screen they stay until much
## further away (no vanishing in front of the player).
const RECYCLE_RADIUS_M: float = 120.0
const RECYCLE_ON_SCREEN_M: float = 200.0
## A vehicle may only appear in view beyond this distance (else it spawns off screen).
const SPAWN_ON_SCREEN_MIN_M: float = 115.0
const INDICATOR_YIELD_RANGE_M: float = 25.0
const HONK_FILE: String = "res://assets/audio/traffic/truck_horn.ogg"
const INDICATOR_YIELD_S: float = 3.0
const SPAWN_MIN_AHEAD_M: float = 45.0
const SPAWN_MAX_AHEAD_M: float = 110.0
const GREYBOX_LENGTH_M: float = 3000.0
const GREYBOX_WIDTH_M: float = 13.2
## Mix for TWO_WHEELER, HATCHBACK, SHARE_AUTO, MTC_BUS, STRAY_COW (Chennai: lots of two-wheelers).
const ARCHETYPE_MIX: Array[int] = [0, 0, 0, 0, 0, 6, 1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5, 0]
const ARCHETYPE_COLOURS: Array[Color] = [Color(0.15, 0.25, 0.75), Color(0.85, 0.85, 0.85), Color(0.2, 0.6, 0.25), Color(0.25, 0.45, 0.85), Color(0.93, 0.9, 0.84), Color(0.9, 0.9, 0.92), Color(0.95, 0.95, 0.95)]
## Zones (manifest ids) where stray cattle wander onto the road.
const MARKET_ZONES: PackedStringArray = ["mylapore", "t_nagar"]

@export var vehicle_scene: PackedScene
@export var player_path: NodePath
## res:// path of road_graph.json. Empty = greybox straight road.
@export var graph_path: String = ""
@export var active_count: int = 12
## Stray cattle are parked for now (design call, Oct 2026). Their slots become two-wheelers
## and hatchbacks; flip this back on to bring the Mylapore/T. Nagar cows back.
@export var stray_cattle_enabled: bool = false

var graph: RoadGraph
var pool: Array[TrafficVehicleAI] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _player: Node3D
var _honk: AudioStreamPlayer3D
var _respawn_queue: Array[TrafficVehicleAI] = []
var _quest_ambulance: TrafficVehicleAI
var _market_zones: Array[Vector3] = [] # x, z, radius
var _cow_retry_timer: float = 0.0
var emergency_cooldown: float = 0.0
var _near_miss_cooldown: Dictionary = {} # vehicle -> seconds left
## Time-of-day traffic (TrafficDensity). Off = fixed `active_count` (greybox + old tests).
@export var dynamic_density: bool = true
## Traffic cap while the guided first ride runs (TutorialScript.max_traffic overrides it).
@export var tutorial_max_active: int = 4
## Speed of a scripted "blocker" (tutorial horn step): slow enough that the player catches it.
const SCRIPTED_BLOCKER_KMH: float = 9.0
const SCRIPTED_MIN_AHEAD_M: float = 45.0
const DENSITY_UPDATE_S: float = 2.0
var _zones: Array[Dictionary] = [] # {id, x, z, r}
var _density_timer: float = DENSITY_UPDATE_S
var density: float = 0.5
var zone_id: String = ""
var target_active: int = 12
var speed_factor: float = 1.0
var _signal_nodes: PackedInt32Array = PackedInt32Array()
var _enforced_signal_nodes: Dictionary = {}
var _ticket_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _signal_posts: Array[Node3D] = []
var _signal_post_spots: Dictionary = {}
var _signal_set: Dictionary = {} # node id -> true
var _signal_group: Dictionary = {} # node id -> {edge id: 0 main road / 1 cross road}
var _signal_stop_back: Dictionary = {} # node id -> stop line distance back from the node (m)
var _signal_post_node: PackedInt32Array = PackedInt32Array()
var _signal_post_edge: PackedInt32Array = PackedInt32Array()
var _signal_lamp_meshes: Array[ArrayMesh] = []
var _player_pose_seen: bool = false
var _previous_player_pos: Vector3 = Vector3.ZERO
var _last_player_ticket_s: float = -1000.0
var _signal_refresh_timer: float = 1.0
const NEAR_MISS_CLEARANCE_M: float = 0.6
const NEAR_MISS_MIN_SPEED_KMH: float = 35.0
const PLAYER_HALF_WIDTH_M: float = 0.65
const SIGNAL_POOL_SIZE: int = 8
## Two-phase junctions: the main road's approaches get green together, then the cross road's.
## Per phase: green, amber, then a short all-red so the junction clears.
const SIGNAL_GREEN_S: float = 12.0
const SIGNAL_AMBER_S: float = 2.5
const SIGNAL_ALL_RED_S: float = 1.5
const SIGNAL_CYCLE_S: float = 2.0 * (SIGNAL_GREEN_S + SIGNAL_AMBER_S + SIGNAL_ALL_RED_S)
const SIGNAL_BRAKE_MPS2: float = 3.5 # amber: stop only if this braking is enough
enum Light { GREEN, AMBER, RED }
const SIGNAL_ENFORCEMENT_FINE_INR: int = 200
const SIGNAL_ROADS: PackedStringArray = ["trunk", "primary", "secondary"]
const SIGNAL_MIN_WIDTH_M: float = 6.0
const SIGNAL_POSTS_FILE: String = "res://data/world/signal_posts.json"

func _ready() -> void:
	rng.seed = 600028
	_ticket_rng.randomize()
	_player = get_node_or_null(player_path) as Node3D
	graph = RoadGraph.from_json_file(graph_path) if graph_path != "" else _build_greybox_graph()
	_load_market_zones()
	if ResourceLoader.exists(HONK_FILE):
		_honk = AudioStreamPlayer3D.new()
		_honk.name = "HonkBack"
		_honk.stream = load(HONK_FILE) as AudioStream
		_honk.volume_db = -6.0
		_honk.unit_size = 10.0
		_honk.max_distance = 90.0
		add_child(_honk)
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
		var mix: int = ARCHETYPE_MIX[i % ARCHETYPE_MIX.size()]
		if mix == TrafficVehicleAI.Archetype.STRAY_COW and not stray_cattle_enabled:
			mix = TrafficVehicleAI.Archetype.LORRY if i % 3 == 0 else (TrafficVehicleAI.Archetype.TWO_WHEELER if i % 2 == 0 else TrafficVehicleAI.Archetype.HATCHBACK)
		var kind: TrafficVehicleAI.Archetype = mix as TrafficVehicleAI.Archetype
		v.setup(self, kind, materials[kind])
		pool.append(v)
	SignalBus.horn_blasted.connect(_on_horn_blasted)
	SignalBus.traffic_bumped.connect(_on_bumped)
	SignalBus.indicator_changed.connect(_on_player_indicator)
	SignalBus.scripted_traffic_requested.connect(place_scripted_vehicle)
	SignalBus.scripted_ambulance_provider = Callable(self, "place_quest_ambulance")
	SignalBus.mission_finished.connect(_on_quest_finished)
	SignalBus.player_pose_updated.connect(_on_player_signal_pose)
	for node_id: int in graph.nodes.size():
		var big_arms: int = 0
		for edge_id: int in graph.node_edges[node_id]:
			var edge: RoadGraph.Edge = graph.edges[edge_id]
			if SIGNAL_ROADS.has(edge.road_class) and edge.width >= SIGNAL_MIN_WIDTH_M:
				big_arms += 1
		if graph.node_edges[node_id].size() >= 3 and big_arms >= 2:
			_signal_nodes.append(node_id)
			if _ticket_rng.randf() < 0.25:
				_enforced_signal_nodes[node_id] = true
	for node_id: int in _signal_nodes:
		_setup_signal_junction(node_id)
	_load_signal_posts()
	_build_signal_pool()
	_initial_spawn.call_deferred()

func _exit_tree() -> void:
	if SignalBus.scripted_ambulance_provider.is_valid() and SignalBus.scripted_ambulance_provider.get_object() == self:
		SignalBus.scripted_ambulance_provider = Callable()

func _on_quest_finished(id: String, _status: String, _reason: String) -> void:
	if id == "sq_016" and _quest_ambulance != null:
		_quest_ambulance.deactivate()
		_quest_ambulance = null

## Use the existing SERVICE slot; never teleport a visible vehicle into the quest.
func place_quest_ambulance() -> bool:
	if _quest_ambulance != null:
		return true
	if _player == null or graph == null:
		return false
	var here: Dictionary = graph.closest_point(_player.global_position)
	if int(here.get("edge", -1)) < 0:
		return false
	var edge: int = int(here["edge"])
	var facing: Vector3 = -_player.global_transform.basis.z
	var forward: Vector3 = graph.sample(edge, float(here["s"]), 1)[1]
	var direction: int = 1 if facing.dot(forward) >= 0 else -1
	if graph.lanes_in_dir(edge, direction) <= 0:
		direction = -direction
	var behind: float = float(here["s"]) - 48.0 * direction
	if behind < 8.0 or behind > graph.edges[edge].length - 8.0:
		return false
	for vehicle: TrafficVehicleAI in pool:
		if vehicle.archetype != TrafficVehicleAI.Archetype.SERVICE:
			continue
		if vehicle.active and ViewCheck.on_screen(get_viewport(), vehicle.global_position + Vector3.UP, vehicle.half_length() + 1.0):
			return false
		_respawn_queue.erase(vehicle)
		place_vehicle(vehicle, edge, behind, direction, 0)
		vehicle.show_quest_ambulance()
		_quest_ambulance = vehicle
		return true
	return false

func _load_market_zones() -> void:
	if graph_path == "":
		return
	var f: FileAccess = FileAccess.open(graph_path.get_base_dir().path_join("manifest.json"), FileAccess.READ)
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	for z: Dictionary in m.get("zones", []):
		_zones.append({"id": str(z["id"]), "x": float(z["x"]), "z": float(z["z"]), "r": float(z["r"])})
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

var _initial: bool = false

func _initial_spawn() -> void:
	_initial = true # behind the loading screen: traffic may start anywhere, in view too
	target_active = active_count
	if dynamic_density and graph_path != "":
		_update_density()
	for i: int in pool.size():
		if i < target_active or pool[i].archetype == TrafficVehicleAI.Archetype.STRAY_COW:
			_respawn(pool[i])
	_initial = false

## Zone the player is in (nearest centre inside its radius), "" outside the three MVP zones.
func zone_at(p: Vector3) -> String:
	var best: String = ""
	var best_d: float = INF
	for z: Dictionary in _zones:
		var d: float = Vector2(p.x - float(z["x"]), p.z - float(z["z"])).length()
		if d <= float(z["r"]) and d < best_d:
			best_d = d
			best = str(z["id"])
	return best

func _update_density() -> void:
	var minute: float = GameState.shift_minute
	var weekday: int = (GameState.day - 1) % 7
	zone_id = zone_at(_player.global_position) if _player != null else ""
	density = TrafficDensity.density(minute, weekday, zone_id)
	target_active = mini(TrafficDensity.active_vehicles(density, MAX_POOL), MAX_POOL)
	if GameState.tutorial_active:
		target_active = mini(target_active, tutorial_max_active) # first ride: quiet streets
	speed_factor = TrafficDensity.speed_factor(minute, weekday, density)
	SignalBus.traffic_density_changed.emit(density, zone_id, TrafficDensity.is_peak(minute, weekday))

func active_vehicle_count() -> int:
	var n: int = 0
	for v: TrafficVehicleAI in pool:
		if v.active and v.archetype != TrafficVehicleAI.Archetype.STRAY_COW:
			n += 1
	return n

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	emergency_cooldown = maxf(0.0, emergency_cooldown - delta)
	_yield_to_emergency()
	for v: TrafficVehicleAI in pool:
		if not v.active:
			continue
		v.tick(delta)
		if v.active and v != _quest_ambulance and not _respawn_queue.has(v) and should_recycle(v):
			_respawn_queue.append(v)
	_detect_near_misses(delta)
	if dynamic_density and graph_path != "":
		_density_timer += delta
		if _density_timer >= DENSITY_UPDATE_S:
			_density_timer = 0.0
			_update_density()
			# Rush hour builds up: wake parked pool vehicles (≤ 2 per update, frame time stays flat).
			var woken: int = 0
			for v: TrafficVehicleAI in pool:
				if active_vehicle_count() + _respawn_queue.size() >= target_active or woken >= 2:
					break
				if not v.active and v.archetype != TrafficVehicleAI.Archetype.STRAY_COW and not _respawn_queue.has(v):
					_respawn_queue.append(v)
					woken += 1
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
		var rv: TrafficVehicleAI = _respawn_queue.pop_front()
		# Traffic thinning out after the rush: recycled vehicles park instead of respawning.
		if dynamic_density and graph_path != "" and rv.archetype != TrafficVehicleAI.Archetype.STRAY_COW \
				and active_vehicle_count() > target_active:
			rv.deactivate()
		else:
			_respawn(rv)
		n += 1
	_signal_refresh_timer += delta
	if _signal_refresh_timer >= 1.0:
		_signal_refresh_timer = 0.0
		_refresh_signal_lights()
	else:
		_update_signal_lamps()

## Signal posts: per post one body mesh (pole, black housing, sun visors, white backboard rim) and
## one lamp mesh, swapped between three pre-lit versions (red / amber / green on) as the phase
## changes — two draw calls per post, shared meshes, no per-post materials.
func _build_signal_pool() -> void:
	var body: ArrayMesh = _signal_body_mesh()
	_signal_lamp_meshes.clear()
	for lit: int in 3:
		_signal_lamp_meshes.append(_signal_lamp_mesh(lit))
	for i: int in SIGNAL_POOL_SIZE:
		var post: Node3D = Node3D.new()
		post.name = "TrafficSignal_%d" % i
		post.visible = false
		var shell: MeshInstance3D = MeshInstance3D.new()
		shell.name = "Body"
		shell.mesh = body
		post.add_child(shell)
		var lamps: MeshInstance3D = MeshInstance3D.new()
		lamps.name = "Lamps"
		lamps.mesh = _signal_lamp_meshes[0]
		lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		post.add_child(lamps)
		add_child(post)
		_signal_posts.append(post)
		_signal_post_node.append(-1)
		_signal_post_edge.append(-1)

static func _signal_body_mesh() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var grey: Color = Color(0.2, 0.22, 0.23)
	var black: Color = Color(0.04, 0.05, 0.05)
	var white: Color = Color(0.9, 0.9, 0.88)
	MeshKit.tube(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 4.2, 0.0), 0.09, grey, 8)
	MeshKit.box(st, Vector3(0.0, 0.25, 0.0), Vector3(0.34, 0.5, 0.34), Color(0.95, 0.85, 0.1)) # yellow base collar
	MeshKit.box(st, Vector3(0.0, 4.8, 0.06), Vector3(0.62, 1.78, 0.06), white) # backboard rim
	MeshKit.box(st, Vector3(0.0, 4.8, 0.12), Vector3(0.48, 1.62, 0.36), black) # housing
	for k: int in 3:
		MeshKit.box(st, Vector3(0.0, 5.33 - float(k) * 0.53 + 0.16, 0.42), Vector3(0.4, 0.03, 0.24), black) # visor
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	return MeshKit.finish(st, mat)

## Three lamp discs on the housing's +Z face; `lit` 0 = red, 1 = amber, 2 = green.
static func _signal_lamp_mesh(lit: int) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var colours: Array[Color] = [Color(1.0, 0.08, 0.05), Color(1.0, 0.6, 0.05), Color(0.08, 1.0, 0.3)]
	for k: int in 3:
		var c: Color = colours[k] if k == lit else colours[k].darkened(0.82)
		MeshKit.disc(st, Vector3(0.0, 5.33 - float(k) * 0.53, 0.305), Vector3.BACK, 0.16, c, 14)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # lamps glow, day and night
	return MeshKit.finish(st, mat)

## Tests freeze the signal clock (seconds) with this; < 0 = real time.
var signal_clock_override: float = -1.0

func _signal_phase(node_id: int) -> float:
	var clock: float = signal_clock_override if signal_clock_override >= 0.0 else float(Time.get_ticks_msec()) / 1000.0
	return fposmod(clock + float(node_id * 7), SIGNAL_CYCLE_S)

## Split a junction's roads into the main road (phase 0: the widest arm and whatever runs in
## line with it) and the cross road (phase 1), and set the stop line back from the node so a
## queue waits before the crossing, not inside it.
func _setup_signal_junction(node_id: int) -> void:
	var dirs: Dictionary = {}
	var widest: int = -1
	var stop_back: float = 0.0
	for edge_id: int in graph.node_edges[node_id]:
		var e: RoadGraph.Edge = graph.edges[edge_id]
		var away: Vector3 = (e.points[1] - e.points[0]) if e.a == node_id else (e.points[e.points.size() - 2] - e.points[e.points.size() - 1])
		away.y = 0.0
		dirs[edge_id] = away.normalized()
		if widest < 0 or e.width > graph.edges[widest].width:
			widest = edge_id
		stop_back = maxf(stop_back, e.width * 0.5)
	var axis: Vector3 = dirs[widest]
	var groups: Dictionary = {}
	var cross: int = 0
	var least_aligned: int = -1
	for edge_id: int in dirs:
		var along: float = absf((dirs[edge_id] as Vector3).dot(axis))
		groups[edge_id] = 0 if along >= 0.7 else 1
		cross += int(groups[edge_id])
		if least_aligned < 0 or along < absf((dirs[least_aligned] as Vector3).dot(axis)):
			least_aligned = edge_id
	if cross == 0:
		groups[least_aligned] = 1 # every arm in line: still give the odd one its own phase
	_signal_set[node_id] = true
	_signal_group[node_id] = groups
	_signal_stop_back[node_id] = stop_back + 1.0

## The light shown to traffic arriving at `node_id` along `edge_id`.
func approach_light(node_id: int, edge_id: int) -> Light:
	var group: int = int((_signal_group.get(node_id, {}) as Dictionary).get(edge_id, 0))
	var half: float = SIGNAL_CYCLE_S * 0.5
	var t: float = fposmod(_signal_phase(node_id) - float(group) * half, SIGNAL_CYCLE_S)
	if t < SIGNAL_GREEN_S:
		return Light.GREEN
	if t < SIGNAL_GREEN_S + SIGNAL_AMBER_S:
		return Light.AMBER
	return Light.RED

func is_signal_junction(node_id: int) -> bool:
	return _signal_set.has(node_id)

func signal_stop_back(node_id: int) -> float:
	return float(_signal_stop_back.get(node_id, 0.0))

## Distance to this vehicle's stop line if it must stop for the light; INF means drive on.
## Amber: stop only when there is room to brake comfortably, otherwise clear the junction.
## A vehicle already at or past the stop line never stops (it would block the crossing).
func signal_stop_gap(vehicle: TrafficVehicleAI) -> float:
	if vehicle.turning:
		return INF
	var edge: RoadGraph.Edge = graph.edges[vehicle.edge]
	var node_id: int = edge.b if vehicle.dir > 0 else edge.a
	if not _signal_set.has(node_id):
		return INF
	var light: Light = approach_light(node_id, vehicle.edge)
	if light == Light.GREEN:
		return INF
	# The bumper waits at the stop line, but never so close that the centre is inside the turn
	# blend (from there the vehicle is already "turning" and ignores the light — the old bug).
	var hl: float = vehicle.half_length()
	var line: float = maxf(float(_signal_stop_back[node_id]), minf(TrafficVehicleAI.TURN_BLEND_M, edge.length * 0.45) + 0.4 - hl)
	var gap: float = edge.length - vehicle.t - hl - line
	if gap < -0.5:
		return INF
	if light == Light.AMBER:
		var v: float = vehicle.current_speed_mps
		if gap < v * v / (2.0 * SIGNAL_BRAKE_MPS2):
			return INF
	# Treated as a stopped lead, which the follower keeps FOLLOW_MIN_GAP_M behind: shift it so
	# the bumper stops ~0.3 m short of the stop line.
	return maxf(0.0, gap) + TrafficVehicleAI.FOLLOW_MIN_GAP_M - 0.3

## Kerb-side post spots per signal junction (tools/osm/build_signal_posts.py): node id →
## [[x, z, yaw], …], one per big approach, always off the carriageway.
func _load_signal_posts() -> void:
	_signal_post_spots.clear()
	var f: FileAccess = FileAccess.open(SIGNAL_POSTS_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	for key: Variant in (parsed as Dictionary):
		_signal_post_spots[int(str(key))] = (parsed as Dictionary)[key]

## World transform of a signal post: on the left kerb of an approach, lamps facing the queue.
## Junctions without a measured kerb spot get no post (better none than one in a lane).
func signal_post_spots(node_id: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for spot: Variant in _signal_post_spots.get(node_id, []):
		var a: Array = spot as Array
		var y: float = graph.nodes[node_id].y
		out.append(Transform3D(Basis(Vector3.UP, float(a[2])), Vector3(float(a[0]), y, float(a[1]))))
	return out

## Approach edge each post at `node_id` serves (same order as signal_post_spots).
func signal_post_edges(node_id: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for spot: Variant in _signal_post_spots.get(node_id, []):
		var a: Array = spot as Array
		out.append(int(a[3]) if a.size() > 3 else -1)
	return out

func _refresh_signal_lights() -> void:
	var near: Array[Array] = []
	var origin: Vector3 = _player.global_position if _player != null else Vector3.INF
	for node_id: int in _signal_nodes:
		if _player == null or origin.distance_to(graph.nodes[node_id]) >= 190.0:
			continue
		var spots: Array[Transform3D] = signal_post_spots(node_id)
		var spot_edges: PackedInt32Array = signal_post_edges(node_id)
		for k: int in spots.size():
			near.append([origin.distance_to(spots[k].origin), node_id, spots[k], spot_edges[k]])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i: int in _signal_posts.size():
		var post: Node3D = _signal_posts[i]
		if i >= near.size():
			post.visible = false
			continue
		post.global_transform = near[i][2] as Transform3D
		post.visible = true
		_signal_post_node[i] = int(near[i][1])
		_signal_post_edge[i] = int(near[i][3])
	_update_signal_lamps()

## Lamps follow each post's own approach every frame (placement only changes once a second).
func _update_signal_lamps() -> void:
	for i: int in _signal_posts.size():
		var post: Node3D = _signal_posts[i]
		if not post.visible:
			continue
		var light: Light = approach_light(_signal_post_node[i], _signal_post_edge[i])
		var lamp: int = 2 if light == Light.GREEN else (1 if light == Light.AMBER else 0)
		var mi: MeshInstance3D = post.get_node("Lamps") as MeshInstance3D
		if mi.mesh != _signal_lamp_meshes[lamp]:
			mi.mesh = _signal_lamp_meshes[lamp]

## Which road the player came in on: the arm whose direction out of the junction best matches
## where the player was. -1 if the player isn't near any arm.
func player_approach_edge(node_id: int, from_pos: Vector3) -> int:
	var centre: Vector3 = graph.nodes[node_id]
	var rel: Vector3 = Vector3(from_pos.x - centre.x, 0.0, from_pos.z - centre.z)
	if rel.length() < 0.1:
		return -1
	rel = rel.normalized()
	var best: int = -1
	var best_dot: float = 0.5
	for edge_id: int in graph.node_edges[node_id]:
		var e: RoadGraph.Edge = graph.edges[edge_id]
		var away: Vector3 = (e.points[1] - e.points[0]) if e.a == node_id else (e.points[e.points.size() - 2] - e.points[e.points.size() - 1])
		away.y = 0.0
		var d: float = rel.dot(away.normalized())
		if d > best_dot:
			best_dot = d
			best = edge_id
	return best

func _on_player_signal_pose(pos: Vector3, heading: Vector3) -> void:
	if not _player_pose_seen:
		_previous_player_pos = pos
		_player_pose_seen = true
		return
	if GameState.tutorial_active:
		_previous_player_pos = pos
		return
	var now_s: float = float(Time.get_ticks_msec()) / 1000.0
	if now_s - _last_player_ticket_s < 8.0:
		_previous_player_pos = pos
		return
	# Red-light camera / constable: the player crosses an enforced junction's stop line (enters
	# its stop circle from outside) while their own approach shows red. Amber is never fined.
	for node_id: int in _enforced_signal_nodes:
		var centre: Vector3 = graph.nodes[node_id]
		var r: float = float(_signal_stop_back[node_id])
		var now_d: float = Vector2(pos.x - centre.x, pos.z - centre.z).length()
		var was_d: float = Vector2(_previous_player_pos.x - centre.x, _previous_player_pos.z - centre.z).length()
		if now_d > r or was_d <= r or was_d > r + 12.0:
			continue
		var from_edge: int = player_approach_edge(node_id, _previous_player_pos)
		if from_edge < 0 or approach_light(node_id, from_edge) != Light.RED:
			break
		if _player is RigidBody3D and (_player as RigidBody3D).linear_velocity.length() > 2.0:
			var fine: int = mini(SIGNAL_ENFORCEMENT_FINE_INR, GameState.wallet_inr)
			if fine > 0 and GameState.spend(fine):
				SignalBus.police_intercept_requested.emit(pos, heading, fine)
				SignalBus.hint_requested.emit("Police stop · ₹%d fine. Red signal violation." % fine, 3.0)
			_last_player_ticket_s = now_s
		break
	_previous_player_pos = pos

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
			honk_at(v)

## A squeezed driver honks back (one pooled 3D player; buses/lorries get the air-horn).
func honk_at(v: TrafficVehicleAI) -> void:
	if _honk == null or v.archetype == TrafficVehicleAI.Archetype.STRAY_COW:
		return
	_honk.global_position = v.global_position
	_honk.pitch_scale = 0.8 if v.archetype in [TrafficVehicleAI.Archetype.MTC_BUS, TrafficVehicleAI.Archetype.LORRY] else rng.randf_range(1.15, 1.45)
	_honk.play()

func request_respawn(v: TrafficVehicleAI) -> void:
	if not _respawn_queue.has(v):
		_respawn_queue.append(v)

## Tutorial / mission hook: put a slow vehicle of `kind` in the player's lane, `ahead_m` metres
## in front, travelling the same way. Reuses a pool vehicle (no instantiate). Returns it or null.
func place_scripted_vehicle(kind: String, ahead_m: float) -> TrafficVehicleAI:
	if _player == null or graph == null:
		return null
	var want: TrafficVehicleAI.Archetype = TrafficVehicleAI.Archetype.TWO_WHEELER if kind == "two_wheeler" else TrafficVehicleAI.Archetype.HATCHBACK
	# Never steal a vehicle the player can see (it would vanish and pop up ahead):
	# parked first, then one out of view, an on-screen one only as a last resort.
	var pick: TrafficVehicleAI = null
	var pick_rank: int = 99
	for v: TrafficVehicleAI in pool:
		if v.archetype != want:
			continue
		var rank: int = 0 if not v.active else (1 if not ViewCheck.on_screen(get_viewport(), v.global_position + Vector3(0, 1, 0), v.half_length() + 1.0) else 2)
		if rank < pick_rank:
			pick = v
			pick_rank = rank
	if pick == null:
		return null
	var fwd: Vector3 = -_player.global_transform.basis.z
	var here: Dictionary = graph.closest_point(_player.global_position)
	if int(here["edge"]) < 0:
		return null
	var e: int = int(here["edge"])
	var tangent: Vector3 = graph.sample(e, float(here["s"]), 1)[1]
	var dir: int = 1 if tangent.dot(fwd) >= 0.0 else -1
	if graph.lanes_in_dir(e, dir) <= 0:
		dir = -dir
	# It appears in view, so not right under the player's nose: at least SCRIPTED_MIN_AHEAD_M.
	var s_ahead: float = clampf(float(here["s"]) + maxf(ahead_m, SCRIPTED_MIN_AHEAD_M) * float(dir), 0.0, graph.edges[e].length)
	place_vehicle(pick, e, s_ahead, dir, sub_lane_at(e, dir, _player.global_position))
	pick.cruise_speed_mps = SCRIPTED_BLOCKER_KMH / 3.6
	pick.current_speed_mps = pick.cruise_speed_mps
	return pick

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
	# Mid-junction: whoever is already on the road we are turning into.
	var nx: Dictionary = me.turn_next_edge()
	if not nx.is_empty():
		for o: TrafficVehicleAI in pool:
			if o == me or not o.active or o.turning or o.edge != int(nx["edge"]) or o.dir != int(nx["dir"]):
				continue
			var gap2: float = me.turn_remaining() - me._turn_t_after + o.t - o.half_length() - me.half_length()
			if gap2 > -0.5 and gap2 < best:
				best = gap2
	if _player != null:
		var fwd: Vector3 = -me.global_transform.basis.z
		var to_p: Vector3 = _player.global_position - me.global_position
		var along: float = to_p.dot(fwd)
		var side: float = absf(to_p.dot(Vector3(fwd.z, 0.0, -fwd.x)))
		if along > 0.0 and side < me.half_width() + 0.9:
			best = minf(best, along - me.half_length() - 1.4)
	return best

## Lead obstacle data for car-following. Reuses the fixed traffic pool; no physics raycast.
## The closest obstacle includes the lead speed, so braking responds to closing rate.
func lead_ahead(me: TrafficVehicleAI) -> Dictionary:
	var best: Dictionary = {"gap": INF, "speed": 0.0}
	for o: TrafficVehicleAI in pool:
		if o == me or not o.active or o.edge != me.edge or o.dir != me.dir:
			continue
		if absf(o.lateral - me.lateral) > me.half_width() + o.half_width():
			continue
		var gap: float = (o.t - o.half_length()) - (me.t + me.half_length())
		if gap >= -0.5 and gap < float(best["gap"]):
			best = {"gap": gap, "speed": o.current_speed_mps}
	if _player != null:
		var fwd: Vector3 = -me.global_transform.basis.z
		var to_p: Vector3 = _player.global_position - me.global_position
		var along: float = to_p.dot(fwd)
		var side: float = absf(to_p.dot(Vector3(fwd.z, 0.0, -fwd.x)))
		var gap_p: float = along - me.half_length() - 1.4
		if along > 0.0 and side < me.half_width() + 0.9 and gap_p < float(best["gap"]):
			var player_body: RigidBody3D = _player as RigidBody3D
			var player_speed: float = maxf(0.0, player_body.linear_velocity.dot(fwd)) if player_body != null else 0.0
			best = {"gap": gap_p, "speed": player_speed}
	return best

## Player hit this vehicle: it stops and leans on the horn ("Enna pa, kannu theriyala?").
func _on_bumped(v: Node3D, impact_mps: float) -> void:
	var tv: TrafficVehicleAI = v as TrafficVehicleAI
	if tv == null or not pool.has(tv):
		return
	var push: Vector3 = (tv.global_position - _player.global_position).normalized() if _player != null else Vector3.ZERO
	var player_mass: float = (_player as RigidBody3D).mass if _player is RigidBody3D else 365.0
	tv.bumped(impact_mps, push, player_mass)
	if _honk != null and tv.archetype != TrafficVehicleAI.Archetype.STRAY_COW:
		_honk.global_position = tv.global_position
		_honk.pitch_scale = 0.8 if tv.archetype in [TrafficVehicleAI.Archetype.MTC_BUS, TrafficVehicleAI.Archetype.LORRY] else rng.randf_range(1.15, 1.45)
		_honk.play()

func claim_emergency() -> bool:
	if GameState.tutorial_active or emergency_cooldown > 0.0:
		return false
	return true

func _yield_to_emergency() -> void:
	for ambulance: TrafficVehicleAI in pool:
		if not ambulance.active or not ambulance.emergency_active:
			continue
		for v: TrafficVehicleAI in pool:
			if v == ambulance or not v.active or v.edge != ambulance.edge or v.dir != ambulance.dir:
				continue
			var ahead: float = v.t - ambulance.t
			if ahead > 0.0 and ahead < TrafficVehicleAI.PHYSICS.emergency_range_m:
				v.give_way(TrafficVehicleAI.PHYSICS.yield_time_s)
				v._try_shift(-1, true) # move left only when the existing safety check permits it
		ambulance._try_shift(1, true)

func is_sub_lane_free(me: TrafficVehicleAI, lane: int) -> bool:
	var lat: float = graph.sub_lane_offset(me.edge, me.dir, lane)
	# Never side-step into the player's auto (a kinematic body would shove it sideways).
	if _player != null:
		var fwd: Vector3 = -me.global_transform.basis.z
		var left: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
		var to_p: Vector3 = _player.global_position - me.global_position
		var along: float = to_p.dot(fwd)
		var p_lat: float = me.lateral + to_p.dot(left)
		if absf(along) < me.half_length() + 2.5 and absf(p_lat - lat) < me.half_width() + PLAYER_HALF_WIDTH_M + 0.4:
			return false
	for o: TrafficVehicleAI in pool:
		if o == me or not o.active or o.edge != me.edge or o.dir != me.dir:
			continue
		if absf(o.lateral - lat) > me.half_width() + o.half_width() + 0.2:
			continue
		if absf(o.t - me.t) < me.half_length() + o.half_length() + 2.0:
			return false
	return true

## Far away, and either out of view or really far.
func should_recycle(v: TrafficVehicleAI) -> bool:
	var d: float = v.global_position.distance_to(_player.global_position)
	if d <= RECYCLE_RADIUS_M:
		return false
	return d > RECYCLE_ON_SCREEN_M or not ViewCheck.on_screen(get_viewport(), v.global_position + Vector3(0, 1, 0), v.half_length() + 1.0)

## Spawn spots ordered so nothing pops into view: off-screen ahead, off-screen behind, then
## on-screen spots only when they are far away.
func _visible_safe_candidates() -> Array[Dictionary]:
	var heading: Vector3 = -_player.global_transform.basis.z
	heading.y = 0.0
	heading = heading.normalized()
	if _initial:
		return graph.spawn_candidates(_player.global_position, heading, SPAWN_MIN_AHEAD_M, SPAWN_MAX_AHEAD_M)
	var all: Array[Dictionary] = graph.spawn_candidates(_player.global_position, Vector3.ZERO, SPAWN_MIN_AHEAD_M, SPAWN_MAX_AHEAD_M + 40.0)
	var ahead_off: Array[Dictionary] = []
	var behind_off: Array[Dictionary] = []
	var far_on: Array[Dictionary] = []
	for c: Dictionary in all:
		var p: Vector3 = graph.sample(int(c["edge"]), float(c["s"]), 1)[0]
		var to_p: Vector3 = Vector3(p.x - _player.global_position.x, 0.0, p.z - _player.global_position.z)
		if ViewCheck.on_screen(get_viewport(), p + Vector3(0, 1, 0), 6.0):
			if to_p.length() >= SPAWN_ON_SCREEN_MIN_M:
				far_on.append(c)
		elif to_p.length() <= SPAWN_MAX_AHEAD_M and to_p.normalized().dot(heading) > -0.2:
			ahead_off.append(c)
		else:
			behind_off.append(c)
	if not ahead_off.is_empty():
		return ahead_off
	if not far_on.is_empty():
		return far_on
	return behind_off

func _respawn(v: TrafficVehicleAI) -> void:
	if _player == null:
		v.deactivate()
		return
	var candidates: Array[Dictionary] = _visible_safe_candidates()
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
