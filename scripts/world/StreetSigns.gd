class_name StreetSigns
extends Node3D
## Street-name boards at real junctions, using the real OSM names of each street (Tamil on top,
## English below, like Greater Chennai Corporation boards: blue plate on two posts).
##
## Pooled: MAX_SIGNS boards are built once and re-assigned to the nearest junctions as the
## player drives (no instantiate/free while driving). A board stands on the left kerb a few
## metres into each named street that leaves a junction, facing traffic turning into it.
## Cost per board: 1 mesh (plate + posts merged) + 2 Label3D ≈ 3 draw calls, culled past
## VISIBLE_M, so the whole system stays inside the 150-draw-call budget.

const MAX_SIGNS: int = 8
const SEARCH_M: float = 110.0
const VISIBLE_M: float = 95.0
const UPDATE_S: float = 0.75
const INTO_STREET_M: float = 7.0
const KERB_GAP_M: float = 1.1
const CELL_M: float = 60.0
const PLATE: Vector3 = Vector3(2.2, 0.62, 0.05)
const PLATE_HEIGHT_M: float = 2.35
const BLUE: Color = Color(0.05, 0.22, 0.6)

var graph: RoadGraph
var _player: Vector3 = Vector3.ZERO
var _pool: Array[Node3D] = []
var _assigned: Dictionary = {} # key -> Node3D
var _junction_grid: Dictionary = {} # Vector2i -> PackedInt32Array(node ids)
var _timer: float = UPDATE_S

func _ready() -> void:
	var mesh: ArrayMesh = _sign_mesh()
	for i: int in MAX_SIGNS:
		var n: Node3D = Node3D.new()
		n.name = "Sign_%d" % i
		n.visible = false
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_end = VISIBLE_M
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		n.add_child(_label("Tamil", PLATE_HEIGHT_M + 0.12, 54))
		n.add_child(_label("English", PLATE_HEIGHT_M - 0.13, 44))
		add_child(n)
		_pool.append(n)
	SignalBus.road_graph_ready.connect(_set_graph)
	if SignalBus.current_road_graph != null:
		_set_graph(SignalBus.current_road_graph)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _label(label_name: String, y: float, font_size: int) -> Label3D:
	var l: Label3D = Label3D.new()
	l.name = label_name
	l.position = Vector3(0.0, y, -PLATE.z * 0.5 - 0.01)
	l.rotation.y = PI # read from the -Z side (the side facing the approaching driver)
	l.pixel_size = 0.0042
	l.font_size = font_size
	l.outline_size = 0
	l.modulate = Color.WHITE
	l.double_sided = false
	l.width = 500.0
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.visibility_range_end = VISIBLE_M * 0.8
	l.shaded = false
	return l

func _set_graph(g: RoadGraph) -> void:
	graph = g
	_junction_grid.clear()
	for ni: int in g.nodes.size():
		if g.node_edges[ni].size() < 3:
			continue # only real junctions get boards
		var p: Vector3 = g.nodes[ni]
		var k: Vector2i = Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))
		var arr: PackedInt32Array = _junction_grid.get(k, PackedInt32Array())
		arr.append(ni)
		_junction_grid[k] = arr

func _process(delta: float) -> void:
	if graph == null:
		return
	_timer += delta
	if _timer < UPDATE_S:
		return
	_timer = 0.0
	refresh()

## Re-pick the nearest boards. Public for tests.
func refresh() -> void:
	var wanted: Array[Dictionary] = candidates(_player)
	var keep: Dictionary = {}
	for c: Dictionary in wanted:
		keep[c["key"]] = c
	# Free boards whose spot is no longer wanted.
	for key: String in _assigned.keys():
		if not keep.has(key):
			(_assigned[key] as Node3D).visible = false
			_assigned.erase(key)
	for c: Dictionary in wanted:
		if _assigned.has(c["key"]):
			continue
		var n: Node3D = _free_board()
		if n == null:
			break
		_place(n, c)
		_assigned[c["key"]] = n

func _free_board() -> Node3D:
	for n: Node3D in _pool:
		if not n.visible:
			return n
	return null

## Board spots near `p`, nearest first: {key, pos, yaw, name, ta}.
func candidates(p: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r: int = ceili(SEARCH_M / CELL_M)
	var c: Vector2i = Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))
	for dx: int in range(-r, r + 1):
		for dz: int in range(-r, r + 1):
			for ni: int in _junction_grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var jp: Vector3 = graph.nodes[ni]
				var d: float = Vector2(jp.x - p.x, jp.z - p.z).length()
				if d > SEARCH_M:
					continue
				var seen: Dictionary = {}
				for ei: int in graph.node_edges[ni]:
					var e: RoadGraph.Edge = graph.edges[ei]
					if e.road_name == "" or seen.has(e.road_name) or e.length < INTO_STREET_M * 2.0:
						continue
					seen[e.road_name] = true
					var spot: Dictionary = _spot(ni, ei)
					spot["dist"] = d
					out.append(spot)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	if out.size() > MAX_SIGNS:
		out.resize(MAX_SIGNS)
	return out

## A few metres into street `ei` from junction `ni`, on the left kerb, plate across the kerb
## facing the junction (what you see as you turn in).
func _spot(ni: int, ei: int) -> Dictionary:
	var e: RoadGraph.Edge = graph.edges[ei]
	var from_a: bool = e.a == ni
	var s: float = INTO_STREET_M if from_a else e.length - INTO_STREET_M
	var pd: Array[Vector3] = graph.sample(ei, s, 1 if from_a else -1)
	var into: Vector3 = pd[1] # direction leaving the junction
	var left: Vector3 = Vector3(into.z, 0.0, -into.x)
	var pos: Vector3 = pd[0] + left * (e.width * 0.5 + KERB_GAP_M)
	# Plate faces back toward the junction.
	var yaw: float = atan2(into.x, into.z)
	return {"key": "%d:%d" % [ni, ei], "pos": pos, "yaw": yaw, "name": e.road_name, "ta": e.road_name_ta}

func _place(n: Node3D, c: Dictionary) -> void:
	n.global_position = c["pos"]
	n.rotation = Vector3(0.0, float(c["yaw"]), 0.0)
	var ta: Label3D = n.get_node("Tamil") as Label3D
	var en: Label3D = n.get_node("English") as Label3D
	var english: String = _short(str(c["name"]))
	ta.text = str(c["ta"])
	en.text = english
	# Single-language board: centre the English line.
	en.position.y = PLATE_HEIGHT_M - 0.13 if ta.text != "" else PLATE_HEIGHT_M
	en.font_size = 44 if ta.text != "" else 52
	# Long names shrink to fit the plate.
	var fit: float = clampf(22.0 / maxf(float(english.length()), 1.0), 0.55, 1.0)
	en.pixel_size = 0.0042 * fit
	ta.pixel_size = 0.0042 * clampf(18.0 / maxf(float(ta.text.length()), 1.0), 0.5, 1.0)
	n.visible = true

## Chennai boards abbreviate: "Road" → "Rd", "Street" → "St", "Salai" stays.
static func _short(s: String) -> String:
	return s.replace(" Road", " Rd").replace(" Street", " St").replace(" Avenue", " Ave").replace("Doctor ", "Dr ")

static func _sign_mesh() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.box(st, Vector3(0, PLATE_HEIGHT_M, 0), PLATE, BLUE)
	MeshKit.box(st, Vector3(0, PLATE_HEIGHT_M, 0.005), PLATE + Vector3(0.06, 0.06, -0.02), Color(0.92, 0.92, 0.92)) # white rim
	for side: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(side * (PLATE.x * 0.5 - 0.12), (PLATE_HEIGHT_M - PLATE.y * 0.5) * 0.5, 0.03), Vector3(0.06, PLATE_HEIGHT_M - PLATE.y * 0.5, 0.06), Color(0.85, 0.85, 0.85))
		# Black-and-yellow kerb paint at the foot of each post (very Chennai).
		MeshKit.box(st, Vector3(side * (PLATE.x * 0.5 - 0.12), 0.2, 0.03), Vector3(0.08, 0.4, 0.08), Color(0.95, 0.8, 0.1))
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	return MeshKit.finish(st, mat)
