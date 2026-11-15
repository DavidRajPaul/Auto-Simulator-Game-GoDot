class_name TrafficPolice
extends Node3D
## Traffic police at big Chennai junctions, on the KERB (Nov 15 owner report: "remove the traffic
## police and his umbrella podium from the middle of the roads and place it in the sides … make
## sure the names match the area").
##
## Every qualifying junction (>= 3 roads, >= 2 trunk / primary / secondary arms >= 6 m wide,
## >= 150 m apart) has a Greater Chennai Police assistance booth on a free kerb corner
## (tools/osm/build_police_booths.py → data/world/police_booths.json + dress "booths"). The booth
## body is part of the chunk mesh and collider (WorldChunkStreamer._booths); this node adds:
##   * the booth signs — "GREATER CHENNAI CITY POLICE", "<code> <AREA> POLICE ASSISTANCE BOOTH" and
##     the Tamil "<code> <area> காவல் சேவை மையம்" of the station whose area it is in — as ONE
##     MultiMesh of panels from police_signs.png for the booths near the player (1 draw call);
##   * a constable in khaki standing on the kerb in front of the nearest MAX_POSTS booths, turning to
##     wave on whichever road has the green (pooled, built once).

const MAX_POSTS: int = 3
const SEARCH_M: float = 260.0
const VISIBLE_M: float = 160.0
const SIGN_M: float = 170.0
const MAX_SIGN_BOOTHS: int = 10
const PANELS_PER_BOOTH: int = 8
const UPDATE_S: float = 1.0
const TURN_SPEED: float = 2.5
const OFFICER_M: float = 1.7
const BOOTHS_FILE: String = "res://data/world/police_booths.json"
const SIGNS_TEX: String = "res://assets/textures/police_signs.png"
## The neutral male IPS model (the female one has both arms permanently out).
const OFFICERS: PackedStringArray = ["res://assets/models/people/police_m_ips.glb"]
## Atlas layout (tools/art/make_police_signs.py): 2048², station cells 768 × 256 in two columns,
## shared parts in the column at x 1536.
const ATLAS_PX: float = 2048.0

var graph: RoadGraph
## [x, z, yaw, station, junction node] per booth.
var booths: Array = []
var stations: Array = []
var _player: Vector3 = Vector3.ZERO
var _posts: Array[Node3D] = []
var _post_booth: Dictionary = {} # post -> booth index
var _headings: Dictionary = {} # post -> Array[float] approach yaws
var _head_edges: Dictionary = {} # post -> Array[int] edge behind each yaw
var _phase: Dictionary = {} # post -> int
var _timer: float = UPDATE_S
var _signs: MultiMeshInstance3D

func _ready() -> void:
	_load()
	_build_signs()
	for i: int in MAX_POSTS:
		var post: Node3D = Node3D.new()
		post.name = "PolicePost_%d" % i
		post.visible = false
		var path: String = OFFICERS[i % OFFICERS.size()]
		if ResourceLoader.exists(path):
			var officer: Node3D = (load(path) as PackedScene).instantiate() as Node3D
			officer.name = "Officer"
			for m: Node in officer.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).visibility_range_end = VISIBLE_M
			post.add_child(officer)
		# The constable is solid: the auto bumps him instead of driving through.
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 8 # Pedestrians_Props
		body.collision_mask = 0
		var cs: CollisionShape3D = CollisionShape3D.new()
		var cap: CapsuleShape3D = CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.7
		cs.shape = cap
		cs.position.y = 0.85
		body.add_child(cs)
		post.add_child(body)
		add_child(post)
		_posts.append(post)
	SignalBus.road_graph_ready.connect(_set_graph)
	if SignalBus.current_road_graph != null:
		_set_graph(SignalBus.current_road_graph)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _load() -> void:
	var f: FileAccess = FileAccess.open(BOOTHS_FILE, FileAccess.READ)
	if f == null:
		push_warning("TrafficPolice: %s missing — run tools/osm/build_police_booths.py" % BOOTHS_FILE)
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	booths = d.get("booths", [])
	stations = d.get("stations", [])

func _set_graph(g: RoadGraph) -> void:
	graph = g

## Where booth `i` stands, its front (towards the junction) and the constable's spot.
func booth_pos(i: int) -> Vector3:
	var b: Array = booths[i]
	return Vector3(float(b[0]), 0.0, float(b[1]))

func booth_front(i: int) -> Vector3:
	var yaw: float = float((booths[i] as Array)[2])
	return Vector3(sin(yaw), 0.0, cos(yaw))

func officer_spot(i: int) -> Vector3:
	return booth_pos(i) + booth_front(i) * OFFICER_M

## "R-1 MAMBALAM" etc. for booth i.
func booth_name(i: int) -> String:
	var st: Array = stations[int((booths[i] as Array)[3])]
	return "%s %s" % [st[0], st[1]]

# --- Signs ------------------------------------------------------------------------------------

## Atlas rect (u0, v0, u1, v1) of a sign part: "en" / "ta" strip of a station, or the shared
## "header" / "panel".
static func sign_rect(part: String, station: int) -> Color:
	var x: float = 1536.0
	var y: float = 0.0
	var w: float = 512.0
	var h: float = 128.0
	match part:
		"panel":
			y = 128.0
			h = 256.0
		"en", "ta":
			x = float(station % 2) * 768.0
			y = float(station / 2) * 256.0 + (128.0 if part == "ta" else 0.0)
			w = 768.0
	return Color(x / ATLAS_PX, y / ATLAS_PX, (x + w) / ATLAS_PX, (y + h) / ATLAS_PX)

func _build_signs() -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = MAX_SIGN_BOOTHS * PANELS_PER_BOOTH
	mm.visible_instance_count = 0
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/police_sign.gdshader") as Shader
	if ResourceLoader.exists(SIGNS_TEX):
		mat.set_shader_parameter("atlas", load(SIGNS_TEX) as Texture2D)
	_signs = MultiMeshInstance3D.new()
	_signs.name = "BoothSigns"
	_signs.multimesh = mm
	_signs.material_override = mat
	_signs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_signs.custom_aabb = AABB(Vector3(-1e5, -10.0, -1e5), Vector3(2e5, 40.0, 2e5))
	add_child(_signs)

## One panel on booth face: centre `c`, outward normal `n`, size (w, h), atlas rect.
func _panel(mm: MultiMesh, k: int, c: Vector3, n: Vector3, w: float, h: float, rect: Color) -> void:
	var right: Vector3 = (-n).cross(Vector3.UP).normalized()
	mm.set_instance_transform(k, Transform3D(Basis(right * w, Vector3.UP * h, n), c))
	mm.set_instance_custom_data(k, rect)

func _refresh_signs() -> void:
	(_signs.material_override as ShaderMaterial).set_shader_parameter("night", StreetLights.lit(GameState.shift_minute))
	var mm: MultiMesh = _signs.multimesh
	var near: Array[Vector2] = []
	for i: int in booths.size():
		var d: float = Vector2(float(booths[i][0]) - _player.x, float(booths[i][1]) - _player.z).length()
		if d < SIGN_M:
			near.append(Vector2(d, float(i)))
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var k: int = 0
	for e: Vector2 in near.slice(0, MAX_SIGN_BOOTHS):
		var i: int = int(e.y)
		var st: int = int((booths[i] as Array)[3])
		var c: Vector3 = booth_pos(i)
		var f: Vector3 = booth_front(i)
		var s: Vector3 = Vector3(f.z, 0.0, -f.x)
		var front: Vector3 = c + f * (WorldChunkStreamer.BOOTH_D * 0.5 + 0.012)
		_panel(mm, k, front + Vector3(0.0, 2.59, 0.0), f, 2.0, 0.32, sign_rect("header", st))
		_panel(mm, k + 1, front + Vector3(0.0, 2.245, 0.0), f, 2.0, 0.33, sign_rect("en", st))
		_panel(mm, k + 2, front + Vector3(0.0, 0.99, 0.0), f, 1.24, 0.62, sign_rect("panel", st))
		_panel(mm, k + 3, front + Vector3(0.0, 0.49, 0.0), f, 2.0, 0.36, sign_rect("ta", st))
		var j: int = k + 4
		for side: float in [-1.0, 1.0]:
			var n: Vector3 = s * side
			var at: Vector3 = c + n * (WorldChunkStreamer.BOOTH_W * 0.5 + 0.012)
			_panel(mm, j, at + Vector3(0.0, 2.6, 0.0), n, 1.5, 0.3, sign_rect("header", st))
			_panel(mm, j + 1, at + Vector3(0.0, 2.25, 0.0), n, 1.5, 0.27, sign_rect("en", st))
			j += 2
		k += PANELS_PER_BOOTH
	mm.visible_instance_count = k

func sign_panels() -> int:
	return _signs.multimesh.visible_instance_count

# --- Constables -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= UPDATE_S:
		_timer = 0.0
		refresh()
	if graph == null:
		return
	var tm: ChennaiTrafficManager = get_parent().get_node_or_null("ChennaiTrafficManager") as ChennaiTrafficManager
	for post: Node3D in _posts:
		if not post.visible:
			continue
		var heads: Array = _headings.get(post, [])
		if heads.is_empty():
			continue
		var ni: int = int((booths[int(_post_booth[post])] as Array)[4])
		if tm != null and tm.is_signal_junction(ni):
			# He faces whichever road has the green and waves it on.
			var edges: Array = _head_edges.get(post, [])
			for k: int in edges.size():
				if tm.approach_light(ni, int(edges[k])) != ChennaiTrafficManager.Light.RED:
					_phase[post] = k
					break
		var officer: Node3D = post.get_node_or_null("Officer") as Node3D
		if officer != null:
			var want: float = float(heads[int(_phase.get(post, 0))])
			officer.rotation.y = lerp_angle(officer.rotation.y, want, 1.0 - exp(-TURN_SPEED * delta))

## Signs round the player, constables at the nearest booths. Public for tests.
func refresh() -> void:
	_refresh_signs()
	var near: Array[Vector2] = []
	for i: int in booths.size():
		var d: float = Vector2(float(booths[i][0]) - _player.x, float(booths[i][1]) - _player.z).length()
		if d <= SEARCH_M:
			near.append(Vector2(d, float(i)))
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var want: Dictionary = {}
	for e: Vector2 in near.slice(0, MAX_POSTS):
		want[int(e.y)] = true
	for post: Node3D in _posts:
		if post.visible and not want.has(int(_post_booth.get(post, -1))):
			post.visible = false
			_post_booth.erase(post)
	var taken: Dictionary = {}
	for post: Node3D in _posts:
		if post.visible:
			taken[int(_post_booth[post])] = true
	for i: int in want:
		if taken.has(i):
			continue
		for post: Node3D in _posts:
			if not post.visible:
				_place(post, i)
				break

func _place(post: Node3D, i: int) -> void:
	var spot: Vector3 = officer_spot(i)
	spot.y = SignalBus.surface_height(spot.x, spot.z, 0.08)
	post.global_position = spot
	var heads: Array = []
	var head_edges: Array = []
	if graph != null:
		var ni: int = int((booths[i] as Array)[4])
		# Face each approach in turn, looking down the road at the oncoming traffic.
		for ei: int in graph.node_edges[ni]:
			var e: RoadGraph.Edge = graph.edges[ei]
			var other: Vector3 = e.points[1] if e.a == ni else e.points[e.points.size() - 2]
			var d: Vector3 = other - spot
			if d.length_squared() > 0.01:
				heads.append(atan2(d.x, d.z))
				head_edges.append(ei)
	_headings[post] = heads
	_head_edges[post] = head_edges
	_post_booth[post] = i
	_phase[post] = 0
	var officer: Node3D = post.get_node_or_null("Officer") as Node3D
	if officer != null:
		officer.rotation.y = float(heads[0]) if not heads.is_empty() else atan2(booth_front(i).x, booth_front(i).z)
	post.visible = true

func active_posts() -> int:
	var n: int = 0
	for p: Node3D in _posts:
		n += 1 if p.visible else 0
	return n
