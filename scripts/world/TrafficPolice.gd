class_name TrafficPolice
extends Node3D
## Traffic police posts at big Chennai junctions: an officer (khaki TN police uniform) on a small
## round platform under a red-and-white traffic umbrella, standing in the middle of the junction
## and turning to wave each approach through in turn, like a real signal cycle.
##
## Junctions qualify when ≥ 3 roads meet and at least two arms are trunk / primary / secondary
## roads ≥ 6 m wide (OSM widths run narrow), thinned so posts are ≥ 150 m apart. Pooled: MAX_POSTS posts are built once and moved to the nearest qualifying
## junctions as the player drives. Per post: officer (1 draw) + platform/umbrella (1 mesh,
## 2 surfaces) + one small collider, culled past VISIBLE_M.

const MAX_POSTS: int = 3
const SEARCH_M: float = 260.0
const VISIBLE_M: float = 160.0
const UPDATE_S: float = 1.0
const TURN_EVERY_S: float = 6.0
const TURN_SPEED: float = 2.5
const MIN_WIDTH_M: float = 6.0
const MIN_SPACING_M: float = 150.0
const BIG_ROADS: PackedStringArray = ["trunk", "primary", "secondary"]
## Officers: male IPS (arms at sides) and female constable (arms out — directing traffic).
const OFFICERS: PackedStringArray = ["res://assets/models/people/police_m_ips.glb", "res://assets/models/people/police_f_khaki.glb"]
const PLATFORM_R: float = 0.85
const PLATFORM_H: float = 0.32

var graph: RoadGraph
var junctions: PackedInt32Array = PackedInt32Array()
var _player: Vector3 = Vector3.ZERO
var _posts: Array[Node3D] = []
var _assigned: Dictionary = {} # junction node -> post
var _headings: Dictionary = {} # post -> Array[float] approach yaws
var _phase: Dictionary = {} # post -> int
var _timer: float = UPDATE_S
var _turn_timer: float = 0.0

func _ready() -> void:
	var stand: ArrayMesh = _stand_mesh()
	for i: int in MAX_POSTS:
		var post: Node3D = Node3D.new()
		post.name = "PolicePost_%d" % i
		post.visible = false
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Stand"
		mi.mesh = stand
		mi.visibility_range_end = VISIBLE_M
		post.add_child(mi)
		var path: String = OFFICERS[i % OFFICERS.size()]
		if ResourceLoader.exists(path):
			var officer: Node3D = (load(path) as PackedScene).instantiate() as Node3D
			officer.name = "Officer"
			officer.position.y = PLATFORM_H
			for m: Node in officer.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).visibility_range_end = VISIBLE_M
			post.add_child(officer)
		# Small collider so the auto bumps the platform instead of driving through it.
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 8 # Pedestrians_Props
		body.collision_mask = 0
		var cs: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = PLATFORM_R
		cyl.height = 1.2
		cs.shape = cyl
		cs.position.y = 0.6
		body.add_child(cs)
		post.add_child(body)
		add_child(post)
		_posts.append(post)
	SignalBus.road_graph_ready.connect(_set_graph)
	if SignalBus.current_road_graph != null:
		_set_graph(SignalBus.current_road_graph)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _set_graph(g: RoadGraph) -> void:
	graph = g
	junctions = PackedInt32Array()
	for ni: int in g.nodes.size():
		var eis: PackedInt32Array = g.node_edges[ni]
		if eis.size() < 3:
			continue
		var big: int = 0
		for ei: int in eis:
			var e: RoadGraph.Edge = g.edges[ei]
			if BIG_ROADS.has(e.road_class) and e.width >= MIN_WIDTH_M:
				big += 1
		if big < 2:
			continue
		var p: Vector3 = g.nodes[ni]
		var crowded: bool = false
		for other: int in junctions:
			if g.nodes[other].distance_to(p) < MIN_SPACING_M:
				crowded = true
				break
		if not crowded:
			junctions.append(ni)

func _process(delta: float) -> void:
	if graph == null:
		return
	_timer += delta
	if _timer >= UPDATE_S:
		_timer = 0.0
		refresh()
	_turn_timer += delta
	var step: bool = _turn_timer >= TURN_EVERY_S
	if step:
		_turn_timer = 0.0
	for post: Node3D in _posts:
		if not post.visible:
			continue
		var heads: Array = _headings.get(post, [])
		if heads.is_empty():
			continue
		if step:
			_phase[post] = (int(_phase.get(post, 0)) + 1) % heads.size()
		var officer: Node3D = post.get_node_or_null("Officer") as Node3D
		if officer != null:
			var want: float = float(heads[int(_phase.get(post, 0))])
			officer.rotation.y = lerp_angle(officer.rotation.y, want, 1.0 - exp(-TURN_SPEED * delta))

## Move posts to the nearest qualifying junctions. Public for tests.
func refresh() -> void:
	var near: Array[Array] = []
	for ni: int in junctions:
		var p: Vector3 = graph.nodes[ni]
		var d: float = Vector2(p.x - _player.x, p.z - _player.z).length()
		if d <= SEARCH_M:
			near.append([d, ni])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var want: Dictionary = {}
	for k: int in mini(near.size(), MAX_POSTS):
		want[int(near[k][1])] = true
	for ni: Variant in _assigned.keys():
		if not want.has(ni):
			(_assigned[ni] as Node3D).visible = false
			_assigned.erase(ni)
	for ni: int in want:
		if _assigned.has(ni):
			continue
		var post: Node3D = _free_post()
		if post == null:
			break
		_place(post, ni)
		_assigned[ni] = post

func _free_post() -> Node3D:
	for p: Node3D in _posts:
		if not p.visible:
			return p
	return null

func _place(post: Node3D, ni: int) -> void:
	post.global_position = graph.nodes[ni]
	# Face each approach in turn (looking back down the road at oncoming traffic).
	var heads: Array = []
	for ei: int in graph.node_edges[ni]:
		var e: RoadGraph.Edge = graph.edges[ei]
		var other: Vector3 = e.points[1] if e.a == ni else e.points[e.points.size() - 2]
		var d: Vector3 = other - graph.nodes[ni]
		if d.length_squared() > 0.01:
			heads.append(atan2(d.x, d.z))
	_headings[post] = heads
	_phase[post] = 0
	var officer: Node3D = post.get_node_or_null("Officer") as Node3D
	if officer != null and not heads.is_empty():
		officer.rotation.y = float(heads[0])
	post.visible = true

func active_posts() -> int:
	var n: int = 0
	for p: Node3D in _posts:
		n += 1 if p.visible else 0
	return n

## Round platform (white with a blue band) + a red-and-white segmented traffic umbrella.
static func _stand_mesh() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var white: Color = Color(0.93, 0.93, 0.92)
	var blue: Color = Color(0.1, 0.25, 0.6)
	MeshKit.tube(st, Vector3(0, 0.0, 0), Vector3(0, PLATFORM_H * 0.55, 0), PLATFORM_R, white, 16)
	MeshKit.tube(st, Vector3(0, PLATFORM_H * 0.55, 0), Vector3(0, PLATFORM_H * 0.8, 0), PLATFORM_R + 0.01, blue, 16)
	MeshKit.tube(st, Vector3(0, PLATFORM_H * 0.8, 0), Vector3(0, PLATFORM_H, 0), PLATFORM_R, white, 16)
	# Umbrella pole behind the officer.
	MeshKit.tube(st, Vector3(0, PLATFORM_H, 0.55), Vector3(0, 2.75, 0.55), 0.03, Color(0.75, 0.75, 0.78), 6)
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.6
	var mesh: ArrayMesh = MeshKit.finish(st, paint)
	var um: SurfaceTool = MeshKit.begin()
	var apex: Vector3 = Vector3(0, 2.95, 0.55)
	var segs: int = 8
	for k: int in segs:
		var a0: float = TAU * float(k) / float(segs)
		var a1: float = TAU * float(k + 1) / float(segs)
		var r: float = 1.35
		var p0: Vector3 = Vector3(cos(a0) * r, 2.55, 0.55 + sin(a0) * r)
		var p1: Vector3 = Vector3(cos(a1) * r, 2.55, 0.55 + sin(a1) * r)
		um.set_color(Color(0.85, 0.1, 0.1) if k % 2 == 0 else Color(0.97, 0.97, 0.95))
		um.set_smooth_group(-1)
		# Both faces (seen from below while driving, and from above in the top-down camera).
		um.add_vertex(apex)
		um.add_vertex(p1)
		um.add_vertex(p0)
		um.add_vertex(apex)
		um.add_vertex(p0)
		um.add_vertex(p1)
	var canopy: StandardMaterial3D = StandardMaterial3D.new()
	canopy.vertex_color_use_as_albedo = true
	canopy.roughness = 0.8
	canopy.cull_mode = BaseMaterial3D.CULL_DISABLED
	MeshKit.finish(um, canopy, mesh)
	return mesh
