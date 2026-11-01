class_name BusStops
extends Node3D
## Real MTC bus stops (data/world/bus_stops.json, tools/osm/build_bus_stops.py): Chennai bus
## shelters on the footpath at the real stop positions, a name board on the nearest ones, and
## the lookup buses use to pull in and dwell (TrafficVehicleAI._bus_stop_gap).
##
## Draw budget: the nearest MAX_SHELTERS shelters share ONE MultiMesh (1 draw call); only the
## NAMED nearest stops get a Label3D name board (1 draw call each). Collision: one pooled box
## per shown shelter, so the auto cannot drive through a shelter on the footpath.
##
## Shelter (GCC style, ~11 m^2): raised concrete plinth, four steel posts, a flat steel roof with
## a blue fascia/ad panel facing the road, a perforated back panel, a steel bench and a blue
## "BUS STOP" sign on a pole. Built once in code (vertex colours, one material). Front = +Z.

const STOPS_FILE: String = "res://data/world/bus_stops.json"
const MAX_SHELTERS: int = 8
const NAMED: int = 2
const SEARCH_M: float = 150.0
const VISIBLE_M: float = 140.0
const LABEL_M: float = 70.0
const UPDATE_S: float = 0.6
const CELL_M: float = 100.0
const LENGTH_M: float = 5.6
const DEPTH_M: float = 1.9
const ROOF_M: float = 2.7
const FASCIA: Color = Color(0.06, 0.25, 0.62)
const STEEL: Color = Color(0.72, 0.74, 0.76)
const CONCRETE: Color = Color(0.62, 0.6, 0.56)
const PANEL: Color = Color(0.55, 0.6, 0.64)

## Every stop: {x, z, yaw, name, routes, edge, dir, s}.
var stops: Array = []
## Route number -> destination (for the buses' destination boards).
var routes: Dictionary = {}
var _by_edge: Dictionary = {} # edge * 2 + (dir > 0) -> PackedFloat32Array of s (sorted)
var _grid: Dictionary = {} # Vector2i -> PackedInt32Array
var _player: Vector3 = Vector3.ZERO
var _timer: float = UPDATE_S
var _mm: MultiMesh
var _bodies: Array[StaticBody3D] = []
var _labels: Array[Label3D] = []
var shown: PackedInt32Array = PackedInt32Array()

## People waiting at the nearest stops (Nov 1): static baked poses (tools/assets/
## bake_waiting_people.py), standing at the kerb or seated on the bench, dress and saree colours
## varied by PaintSwap. WAITING slots in all, each pre-instancing every pose (nothing is
## instanced while driving); one draw call per visible person, only within WAIT_VISIBLE_M.
const WAITING: int = 5
const WAIT_VISIBLE_M: float = 65.0
const WAIT_DIR: String = "res://assets/models/people/waiting/"
var _wait_meta: Dictionary = {}
var _wait_poses: Array = [] # [id, sit(bool), PackedScene]
var _wait_slots: Array = [] # per slot: Array[Node3D] (one per pose)
## Per shown person: [pose index, stop index], for tests.
var waiting: Array = []

func _ready() -> void:
	_load()
	SignalBus.current_bus_stops = self
	var inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	inst.name = "Shelters"
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = shelter_mesh()
	_mm.instance_count = MAX_SHELTERS
	_mm.visible_instance_count = 0
	inst.multimesh = _mm
	# No visibility range here: it is measured from the node (the world origin), which culled every
	# shelter. The pool only ever holds shelters near the player.
	add_child(inst)
	for i: int in MAX_SHELTERS:
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(LENGTH_M + 0.3, ROOF_M + 0.2, DEPTH_M + 0.2)
		cs.shape = box
		cs.position.y = box.size.y * 0.5
		body.add_child(cs)
		body.process_mode = Node.PROCESS_MODE_DISABLED
		body.visible = false
		add_child(body)
		_bodies.append(body)
	for i: int in NAMED:
		var l: Label3D = Label3D.new()
		l.name = "StopName_%d" % i
		l.pixel_size = 0.0047
		l.font_size = 56
		l.outline_size = 0
		l.modulate = Color.WHITE
		l.shaded = false
		l.double_sided = false
		l.width = 1150.0
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.visibility_range_end = LABEL_M
		l.visible = false
		add_child(l)
		_labels.append(l)
	_build_waiting()
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _exit_tree() -> void:
	if SignalBus.current_bus_stops == self:
		SignalBus.current_bus_stops = null

func _load() -> void:
	var f: FileAccess = FileAccess.open(STOPS_FILE, FileAccess.READ)
	if f == null:
		push_warning("BusStops: %s missing — run tools/osm/build_bus_stops.py" % STOPS_FILE)
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	stops = d.get("stops", [])
	routes = d.get("routes", {})
	for i: int in stops.size():
		var s: Dictionary = stops[i]
		var key: int = int(s["edge"]) * 2 + (1 if int(s["dir"]) > 0 else 0)
		var arr: PackedFloat32Array = _by_edge.get(key, PackedFloat32Array())
		arr.append(float(s["s"]))
		arr.sort()
		_by_edge[key] = arr
		var k: Vector2i = Vector2i(floori(float(s["x"]) / CELL_M), floori(float(s["z"]) / CELL_M))
		var cell: PackedInt32Array = _grid.get(k, PackedInt32Array())
		cell.append(i)
		_grid[k] = cell

## Distance (m) from edge parameter `ep` to the next stop ahead on `edge` travelling `dir`,
## skipping the stop at `skip_s` (just served). INF if none within `max_m`.
func distance_ahead(edge: int, dir: int, ep: float, max_m: float, skip_s: float = -1000.0) -> float:
	var arr: PackedFloat32Array = _by_edge.get(edge * 2 + (1 if dir > 0 else 0), PackedFloat32Array())
	var best: float = INF
	for s: float in arr:
		if absf(s - skip_s) < 1.0:
			continue
		var ahead: float = (s - ep) * float(dir)
		if ahead >= -0.5 and ahead < best and ahead <= max_m:
			best = ahead
	return best

## Edge parameter of the stop `distance_ahead` found (for marking it served).
func stop_param(edge: int, dir: int, ep: float, ahead: float) -> float:
	return ep + ahead * float(dir)

## Index of the stop nearest `p` (or -1).
func nearest(p: Vector3, max_m: float = 400.0) -> int:
	var best: int = -1
	var best_d: float = max_m * max_m
	var c: Vector2i = Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))
	var r: int = ceili(max_m / CELL_M)
	for dx: int in range(-r, r + 1):
		for dz: int in range(-r, r + 1):
			for i: int in _grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var s: Dictionary = stops[i]
				var d2: float = Vector2(float(s["x"]) - p.x, float(s["z"]) - p.z).length_squared()
				if d2 < best_d:
					best_d = d2
					best = i
	return best

func _process(delta: float) -> void:
	_timer += delta
	if _timer < UPDATE_S or stops.is_empty():
		return
	_timer = 0.0
	refresh()

## Show the nearest shelters around the player. Public for tests.
func refresh() -> void:
	var cand: Array = []
	var c: Vector2i = Vector2i(floori(_player.x / CELL_M), floori(_player.z / CELL_M))
	var r: int = ceili(SEARCH_M / CELL_M)
	for dx: int in range(-r, r + 1):
		for dz: int in range(-r, r + 1):
			for i: int in _grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var s: Dictionary = stops[i]
				var d: float = Vector2(float(s["x"]) - _player.x, float(s["z"]) - _player.z).length()
				if d <= SEARCH_M:
					cand.append([d, i])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var n: int = mini(cand.size(), MAX_SHELTERS)
	shown = PackedInt32Array()
	for k: int in n:
		var i: int = int(cand[k][1])
		shown.append(i)
		var xf: Transform3D = shelter_transform(i)
		_mm.set_instance_transform(k, xf)
		_bodies[k].global_transform = xf
		_bodies[k].process_mode = Node.PROCESS_MODE_INHERIT
	_mm.visible_instance_count = n
	for k: int in range(n, MAX_SHELTERS):
		_bodies[k].process_mode = Node.PROCESS_MODE_DISABLED
		_bodies[k].global_position = Vector3(0.0, -300.0, 0.0)
	for k: int in NAMED:
		var l: Label3D = _labels[k]
		l.visible = k < n
		if not l.visible:
			continue
		var i: int = shown[k]
		var s: Dictionary = stops[i]
		var rs: Array = s["routes"]
		var line2: String = "  ".join(PackedStringArray(rs.slice(0, mini(rs.size(), 6))))
		l.text = "%s\n%s" % [str(s["name"]).to_upper(), line2]
		# On the fascia, facing the road.
		l.global_transform = shelter_transform(i) * Transform3D(Basis.IDENTITY, Vector3(0.0, ROOF_M - 0.32, DEPTH_M * 0.5 + 0.34))
	_place_waiting()

func _build_waiting() -> void:
	var f: FileAccess = FileAccess.open(WAIT_DIR + "waiting.json", FileAccess.READ)
	if f == null:
		return
	_wait_meta = JSON.parse_string(f.get_as_text()) as Dictionary
	var ids: Array = _wait_meta.keys()
	ids.sort()
	for id: Variant in ids:
		for sit: bool in [false, true]:
			var path: String = WAIT_DIR + "%s_%s.glb" % [id, "sit" if sit else "stand"]
			if ResourceLoader.exists(path):
				_wait_poses.append([str(id), sit, load(path) as PackedScene])
	for k: int in WAITING:
		var nodes: Array[Node3D] = []
		for p: Array in _wait_poses:
			var n: Node3D = (p[2] as PackedScene).instantiate() as Node3D
			n.visible = false
			for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
				(mi as GeometryInstance3D).visibility_range_end = WAIT_VISIBLE_M
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			PaintSwap.prepare(n, str(p[0]))
			add_child(n)
			nodes.append(n)
		_wait_slots.append(nodes)

## Who waits at stop `i`: [[pose index, local transform, paint], ...]. Deterministic per stop
## and hour, more people at rush hours: up to 2 on the bench, the rest standing at the kerb
## looking up or down the road for the bus.
func _waiting_at(i: int) -> Array:
	if _wait_poses.is_empty():
		return []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var hour: int = int(GameState.shift_minute / 60.0)
	rng.seed = i * 7919 + hour
	var rush: bool = (hour >= 7 and hour < 10) or (hour >= 16 and hour < 20)
	var n: int = rng.randi_range(2, 4) if rush else rng.randi_range(1, 2)
	var out: Array = []
	var seats: Array = [-1.4, 0.2]
	var spots: Array = [1.4, 2.2, -2.0]
	var sitters: Array[int] = []
	var standers: Array[int] = []
	for pi: int in _wait_poses.size():
		if bool(_wait_poses[pi][1]):
			sitters.append(pi)
		else:
			standers.append(pi)
	for k: int in n:
		var sit: bool = k < 2 and rng.randf() < 0.6 and not seats.is_empty()
		var pool: Array[int] = sitters if sit else standers
		if pool.is_empty() or (not sit and spots.is_empty()):
			continue
		var pi: int = pool[rng.randi() % pool.size()]
		var id: String = str(_wait_poses[pi][0])
		var meta: Dictionary = _wait_meta.get(id, {})
		var xf: Transform3D
		if sit:
			var drop: float = float(meta.get("sit_drop", 0.5))
			xf = Transform3D(Basis.IDENTITY, Vector3(float(seats.pop_front()), clampf(drop - 0.02, 0.5, 0.6), -DEPTH_M * 0.5 + 0.3))
		else:
			var yaw: float = rng.randf_range(-1.2, 1.2)
			xf = Transform3D(Basis(Vector3.UP, yaw), Vector3(float(spots.pop_front()), float(meta.get("stand_hip", 0.85)), DEPTH_M * 0.5 + 0.55))
		var pal: Array[Color] = PaintSwap.palette_for_person(id)
		var paint: Color = PaintSwap.NO_PAINT if pal.is_empty() or rng.randf() < 0.25 else pal[rng.randi() % pal.size()]
		out.append([pi, xf, paint])
	return out

func _place_waiting() -> void:
	waiting = []
	var used: int = 0
	for k: int in mini(NAMED, shown.size()):
		var i: int = shown[k]
		for w: Array in _waiting_at(i):
			if used >= _wait_slots.size():
				break
			var nodes: Array = _wait_slots[used]
			for pi: int in nodes.size():
				(nodes[pi] as Node3D).visible = pi == int(w[0])
			var n: Node3D = nodes[int(w[0])]
			n.global_transform = shelter_transform(i) * (w[1] as Transform3D)
			PaintSwap.set_paint(n, w[2] as Color)
			waiting.append([int(w[0]), i])
			used += 1
	for k: int in range(used, _wait_slots.size()):
		for n: Variant in _wait_slots[k]:
			(n as Node3D).visible = false

## Shelter transform: drawn footpath height, front (+Z) facing the road.
func shelter_transform(i: int) -> Transform3D:
	var s: Dictionary = stops[i]
	var x: float = float(s["x"])
	var z: float = float(s["z"])
	var y: float = SignalBus.surface_height(x, z, 0.08)
	return Transform3D(Basis(Vector3.UP, float(s["yaw"])), Vector3(x, y, z))

## The shelter as one vertex-coloured mesh (one surface).
static func shelter_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl: float = LENGTH_M * 0.5
	var hd: float = DEPTH_M * 0.5
	_box(st, Vector3(0.0, -0.2, 0.0), Vector3(LENGTH_M + 0.4, 0.34, DEPTH_M + 0.3), CONCRETE) # plinth
	for px: float in [-hl + 0.1, hl - 0.1]:
		for pz: float in [-hd + 0.08, hd - 0.12]:
			_box(st, Vector3(px, ROOF_M * 0.5, pz), Vector3(0.09, ROOF_M, 0.09), STEEL)
	_box(st, Vector3(0.0, ROOF_M + 0.04, 0.05), Vector3(LENGTH_M + 0.3, 0.08, DEPTH_M + 0.45), STEEL) # roof
	_box(st, Vector3(0.0, ROOF_M - 0.32, hd + 0.3), Vector3(LENGTH_M + 0.3, 0.64, 0.06), FASCIA) # name board hung under the roof edge
	_box(st, Vector3(0.0, ROOF_M + 0.19, hd + 0.16), Vector3(LENGTH_M + 0.3, 0.05, 0.065), Color(0.95, 0.95, 0.95)) # white trim
	_box(st, Vector3(0.0, 1.45, -hd + 0.06), Vector3(LENGTH_M - 0.3, 1.5, 0.04), PANEL) # back panel
	_box(st, Vector3(0.0, 0.46, -hd + 0.42), Vector3(LENGTH_M - 1.2, 0.05, 0.42), STEEL) # bench seat
	_box(st, Vector3(0.0, 0.75, -hd + 0.2), Vector3(LENGTH_M - 1.2, 0.4, 0.04), STEEL) # bench back
	for bx: float in [-hl + 0.9, 0.0, hl - 0.9]:
		_box(st, Vector3(bx, 0.22, -hd + 0.42), Vector3(0.05, 0.44, 0.38), Color(0.3, 0.31, 0.33))
	# "BUS STOP" sign: pole at the front corner, blue plate with a white bus band.
	_box(st, Vector3(hl + 0.45, 1.5, hd + 0.05), Vector3(0.07, 3.0, 0.07), STEEL)
	_box(st, Vector3(hl + 0.45, 2.85, hd + 0.05), Vector3(0.55, 0.5, 0.04), FASCIA)
	_box(st, Vector3(hl + 0.45, 2.85, hd + 0.075), Vector3(0.4, 0.14, 0.02), Color(0.97, 0.97, 0.97))
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.6
	mat.metallic = 0.15
	mesh.surface_set_material(0, mat)
	return mesh

static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h: Vector3 = size * 0.5
	var faces: Array = [
		[Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
	]
	for f: Array in faces:
		var q: Array = f[1]
		for idx: int in [0, 2, 1, 0, 3, 2]: # clockwise = Godot front face
			st.set_color(col)
			st.add_vertex(c + (q[idx] as Vector3))
