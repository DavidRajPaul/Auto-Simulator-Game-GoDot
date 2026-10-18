class_name WorldChunkStreamer
extends Node3D
## Streams the OSM-built Chennai map (data/world, made by tools/osm/build_world.py).
## Always loaded: ground collision, sea/water/beach/park areas, landmarks.
## Streamed: 250 m chunks (roads + buildings) in a (2r+1)² grid around the player,
## built on WorkerThreadPool and attached on the main thread. Per chunk ≈ 2 draw calls
## (one road/sidewalk mesh, one building MultiMesh) + building colliders.

## Visual layering (ground plane sits at -0.15 so far-away flat layers never z-fight).
const GROUND_VISUAL_Y: float = -0.15
const ROAD_Y: float = 0.06
const SIDEWALK_Y: float = 0.08
const SIDEWALK_W: float = 2.5
const CHECK_INTERVAL_S: float = 0.25
const CLASS_LAYER: Dictionary = {"trunk": 6, "motorway": 6, "primary": 5, "secondary": 4, "tertiary": 3,
	"unclassified": 2, "residential": 1, "living_street": 0}
const ZONE_PALETTES: Dictionary = {
	"marina": [Color(0.93, 0.9, 0.82), Color(0.85, 0.82, 0.7), Color(0.75, 0.82, 0.86)],
	"mylapore": [Color(0.95, 0.85, 0.6), Color(0.9, 0.72, 0.55), Color(0.8, 0.85, 0.7), Color(0.95, 0.93, 0.85)],
	"anna_salai": [Color(0.72, 0.72, 0.75), Color(0.85, 0.83, 0.78), Color(0.6, 0.66, 0.72)],
	"t_nagar": [Color(0.95, 0.75, 0.55), Color(0.85, 0.55, 0.5), Color(0.95, 0.9, 0.6), Color(0.7, 0.75, 0.85)],
	"": [Color(0.85, 0.8, 0.7), Color(0.78, 0.74, 0.66), Color(0.9, 0.86, 0.78)],
}

@export var world_dir: String = "res://data/world"
@export var player_path: NodePath
@export var load_radius_chunks: int = 1
## Auto stand the player spawns at (manifest auto_stands id). Empty = don't move the player.
@export var spawn_stand_id: String = "stand_mylapore"

var manifest: Dictionary = {}
var chunk_size: float = 250.0
var loaded: Dictionary = {} # Vector2i -> Node3D
var _pending: Dictionary = {} # Vector2i -> task id
var _available: Dictionary = {} # Vector2i -> true (chunks that exist in data)
var _player: Node3D
var _timer: float = 0.0
var _road_mat: StandardMaterial3D
var _bld_mat: StandardMaterial3D
var _bld_mesh: BoxMesh
var _mutex: Mutex = Mutex.new()
var _finished: Array[Array] = [] # [key, node]

func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	var f: FileAccess = FileAccess.open(world_dir.path_join("manifest.json"), FileAccess.READ)
	if f == null:
		push_error("WorldChunkStreamer: missing manifest — run the OSM Import workflow")
		return
	manifest = JSON.parse_string(f.get_as_text()) as Dictionary
	chunk_size = float(manifest["chunk_size"])
	for c: Array in manifest["chunks"]:
		_available[Vector2i(int(c[0]), int(c[1]))] = true
	_road_mat = StandardMaterial3D.new()
	_road_mat.vertex_color_use_as_albedo = true
	_road_mat.vertex_color_is_srgb = true
	_road_mat.roughness = 0.95
	_road_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bld_mat = StandardMaterial3D.new()
	_bld_mat.vertex_color_use_as_albedo = true
	_bld_mat.vertex_color_is_srgb = true
	_bld_mat.roughness = 0.9
	_bld_mesh = BoxMesh.new()
	_bld_mesh.material = _bld_mat
	_build_ground()
	_build_areas()
	_build_landmarks()
	_spawn_player()
	update_streaming(true)

func _process(delta: float) -> void:
	_attach_finished()
	_timer += delta
	if _timer >= CHECK_INTERVAL_S:
		_timer = 0.0
		update_streaming(false)

## Request/unload chunks around the player. `blocking` builds synchronously (first frame / tests).
func update_streaming(blocking: bool) -> void:
	if _player == null:
		return
	var c: Vector2i = chunk_of(_player.global_position)
	var wanted: Dictionary = {}
	for dx: int in range(-load_radius_chunks, load_radius_chunks + 1):
		for dz: int in range(-load_radius_chunks, load_radius_chunks + 1):
			var k: Vector2i = c + Vector2i(dx, dz)
			if _available.has(k):
				wanted[k] = true
	for k: Vector2i in wanted:
		if loaded.has(k) or _pending.has(k):
			continue
		if blocking:
			_attach(k, _build_chunk(k))
		else:
			var key: Vector2i = k
			_pending[k] = WorkerThreadPool.add_task(func() -> void: _build_chunk_threaded(key), false, "chunk %s" % k)
	# Unload with one chunk of hysteresis so driving along a border doesn't thrash.
	for k: Vector2i in loaded.keys():
		if absi(k.x - c.x) > load_radius_chunks + 1 or absi(k.y - c.y) > load_radius_chunks + 1:
			(loaded[k] as Node3D).queue_free()
			loaded.erase(k)

func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / chunk_size), floori(p.z / chunk_size))

func stand_transform(stand_id: String) -> Transform3D:
	for s: Dictionary in manifest.get("auto_stands", []):
		if str(s["id"]) == stand_id:
			return Transform3D(Basis(Vector3.UP, float(s["yaw"])), Vector3(float(s["x"]), 1.0, float(s["z"])))
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))

func _spawn_player() -> void:
	if _player == null or spawn_stand_id == "":
		return
	_player.global_transform = stand_transform(spawn_stand_id)
	if _player is RigidBody3D:
		(_player as RigidBody3D).linear_velocity = Vector3.ZERO
		(_player as RigidBody3D).angular_velocity = Vector3.ZERO

# --- Threading ---------------------------------------------------------------

func _build_chunk_threaded(k: Vector2i) -> void:
	var node: Node3D = _build_chunk(k)
	_mutex.lock()
	_finished.append([k, node])
	_mutex.unlock()

func _attach_finished() -> void:
	_mutex.lock()
	var done: Array[Array] = _finished.duplicate()
	_finished.clear()
	_mutex.unlock()
	for item: Array in done:
		var k: Vector2i = item[0]
		if _pending.has(k):
			WorkerThreadPool.wait_for_task_completion(int(_pending[k]))
			_pending.erase(k)
		_attach(k, item[1] as Node3D)

func _attach(k: Vector2i, node: Node3D) -> void:
	if node == null:
		return
	if loaded.has(k):
		node.free()
		return
	add_child(node)
	loaded[k] = node

func _exit_tree() -> void:
	for k: Vector2i in _pending:
		WorkerThreadPool.wait_for_task_completion(int(_pending[k]))
	_pending.clear()
	_attach_finished()

# --- Chunk building (runs on worker threads; touches no scene tree) ---------

func _build_chunk(k: Vector2i) -> Node3D:
	var f: FileAccess = FileAccess.open(world_dir.path_join("chunks/c_%d_%d.json" % [k.x, k.y]), FileAccess.READ)
	if f == null:
		return null
	var data: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var root: Node3D = Node3D.new()
	root.name = "Chunk_%d_%d" % [k.x, k.y]
	var roads: Array = data.get("roads", [])
	if not roads.is_empty():
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Roads"
		mi.mesh = _road_mesh(roads)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var blds: Array = data.get("buildings", [])
	if not blds.is_empty():
		root.add_child(_buildings(blds, k))
	return root

func _road_mesh(roads: Array) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for r: Dictionary in roads:
		var pts: PackedVector2Array = PackedVector2Array()
		for p: Array in r["pts"]:
			pts.append(Vector2(float(p[0]), float(p[1])))
		var w: float = float(r["w"])
		var layer: int = int(CLASS_LAYER.get(str(r["c"]), 1))
		# Sidewalk underneath, then asphalt; major roads sit a hair higher at junctions.
		_ribbon(st, pts, w + SIDEWALK_W * 2.0, SIDEWALK_Y - 0.035, Color(0.66, 0.62, 0.56))
		var shade: float = 0.3 + 0.015 * float(6 - layer)
		_ribbon(st, pts, w, ROAD_Y + float(layer) * 0.002, Color(shade, shade, shade * 0.98))
		if w >= 9.0:
			_ribbon(st, pts, 0.18, ROAD_Y + 0.02, Color(0.9, 0.85, 0.55)) # centre line
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _road_mat)
	return mesh

func _ribbon(st: SurfaceTool, pts: PackedVector2Array, width: float, y: float, colour: Color) -> void:
	if pts.size() < 2:
		return
	var hw: float = width * 0.5
	var left: PackedVector3Array = PackedVector3Array()
	var right: PackedVector3Array = PackedVector3Array()
	for i: int in pts.size():
		var d_in: Vector2 = (pts[i] - pts[i - 1]).normalized() if i > 0 else (pts[1] - pts[0]).normalized()
		var d_out: Vector2 = (pts[i + 1] - pts[i]).normalized() if i < pts.size() - 1 else d_in
		var tangent: Vector2 = (d_in + d_out).normalized()
		if tangent == Vector2.ZERO:
			tangent = d_out
		var n: Vector2 = Vector2(-tangent.y, tangent.x)
		var miter: float = clampf(1.0 / maxf(n.dot(Vector2(-d_out.y, d_out.x)), 0.35), 1.0, 2.5)
		var p: Vector2 = pts[i] + n * hw * miter
		var q: Vector2 = pts[i] - n * hw * miter
		left.append(Vector3(p.x, y, p.y))
		right.append(Vector3(q.x, y, q.y))
	st.set_color(colour)
	for i: int in range(1, pts.size()):
		# Two triangles per segment, wound to face up.
		st.add_vertex(left[i - 1])
		st.add_vertex(right[i - 1])
		st.add_vertex(left[i])
		st.add_vertex(left[i])
		st.add_vertex(right[i - 1])
		st.add_vertex(right[i])

func _buildings(blds: Array, k: Vector2i) -> Node3D:
	var holder: StaticBody3D = StaticBody3D.new()
	holder.name = "Buildings"
	holder.collision_layer = 1
	holder.collision_mask = 0
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _bld_mesh
	mm.instance_count = blds.size()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(k)
	for i: int in blds.size():
		var b: Dictionary = blds[i]
		var size: Vector3 = Vector3(float(b["d"]), float(b["h"]), float(b["w"]))
		var basis: Basis = Basis(Vector3.UP, float(b["yaw"]))
		var pos: Vector3 = Vector3(float(b["x"]), size.y * 0.5, float(b["z"]))
		mm.set_instance_transform(i, Transform3D(basis * Basis.from_scale(size), pos))
		var palette: Array = ZONE_PALETTES.get(str(b.get("zone", "")), ZONE_PALETTES[""])
		mm.set_instance_color(i, (palette[rng.randi() % palette.size()] as Color).darkened(rng.randf_range(0.0, 0.15)))
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(basis, pos)
		holder.add_child(cs)
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "BuildingMeshes"
	mmi.multimesh = mm
	holder.add_child(mmi)
	return holder

# --- Always-loaded layers ----------------------------------------------------

func _build_ground() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	var b: Array = manifest["bounds"]
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(float(b[2]) - float(b[0]) + 1200.0, float(b[3]) - float(b[1]) + 1200.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.53, 0.44)
	mat.roughness = 1.0
	plane.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3((float(b[0]) + float(b[2])) * 0.5, GROUND_VISUAL_Y, (float(b[1]) + float(b[3])) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)

func _build_areas() -> void:
	var f: FileAccess = FileAccess.open(world_dir.path_join("areas.json"), FileAccess.READ)
	if f == null:
		return
	var areas: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var specs: Dictionary = {
		"sea": [Color(0.18, 0.42, 0.6), -0.05], "water": [Color(0.22, 0.45, 0.55), -0.02],
		"beach": [Color(0.93, 0.85, 0.62), -0.08], "park": [Color(0.42, 0.62, 0.32), -0.07],
	}
	for kind: String in specs:
		var polys: Array = areas.get(kind, [])
		if polys.is_empty():
			continue
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		var y: float = float(specs[kind][1])
		for poly: Array in polys:
			var pts: PackedVector2Array = PackedVector2Array()
			for p: Array in poly:
				pts.append(Vector2(float(p[0]), float(p[1])))
			var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
			# Triangulation winding varies with input order; emit each triangle facing up.
			for i: int in range(0, idx.size(), 3):
				var a: Vector2 = pts[idx[i]]
				var b: Vector2 = pts[idx[i + 1]]
				var c: Vector2 = pts[idx[i + 2]]
				if (b - a).cross(c - a) > 0.0:
					var tmp: Vector2 = b
					b = c
					c = tmp
				for v: Vector2 in [a, b, c]:
					st.add_vertex(Vector3(v.x, y, v.y))
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = specs[kind][0]
		mat.roughness = 0.15 if kind in ["sea", "water"] else 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Area_" + kind
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

## Placeholder landmark silhouettes (replaced by low-poly GLTF hero models in Phase 5).
func _build_landmarks() -> void:
	var holder: StaticBody3D = StaticBody3D.new()
	holder.name = "Landmarks"
	holder.collision_layer = 1
	holder.collision_mask = 0
	add_child(holder)
	for l: Dictionary in manifest.get("landmarks", []):
		var pos: Vector3 = Vector3(float(l["x"]), 0.0, float(l["z"]))
		var yaw: float = float(l.get("yaw", 0.0))
		var node: Node3D = Node3D.new()
		node.name = str(l["id"])
		node.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		holder.add_child(node)
		match str(l["kind"]):
			"lighthouse":
				_part(node, holder, _cyl(3.2, 4.2, 42.0), Vector3(0, 21, 0), Color(0.85, 0.2, 0.15), true)
				_part(node, holder, _cyl(3.0, 3.0, 4.0), Vector3(0, 44, 0), Color(0.95, 0.95, 0.9), false)
			"gopuram":
				for tier: int in 6:
					var w: float = 16.0 - tier * 2.2
					_part(node, holder, _box(Vector3(w, 5.0, w * 0.6)), Vector3(0, 2.5 + tier * 5.0, 0),
						Color.from_hsv(0.05 + tier * 0.1, 0.55, 0.92), tier == 0)
			"tower":
				_part(node, holder, _box(Vector3(18, 54, 18)), Vector3(0, 27, 0), Color(0.82, 0.8, 0.74), true)
			"bridge":
				_part(node, holder, _box(Vector3(3, 6, 40)), Vector3(9, 3, 0), Color(0.3, 0.45, 0.85), false)
				_part(node, holder, _box(Vector3(3, 6, 40)), Vector3(-9, 3, 0), Color(0.95, 0.95, 0.95), false)
			"flyover":
				_part(node, holder, _box(Vector3(20, 1.2, 70)), Vector3(0, 7.5, 0), Color(0.6, 0.6, 0.6), false)
				_part(node, holder, _box(Vector3(2, 7, 2)), Vector3(12, 3.5, 0), Color(0.55, 0.55, 0.55), true)
				_part(node, holder, _box(Vector3(2, 7, 2)), Vector3(-12, 3.5, 0), Color(0.55, 0.55, 0.55), true)
			"heritage":
				_part(node, holder, _box(Vector3(30, 9, 18)), Vector3(0, 4.5, 0), Color(0.95, 0.9, 0.75), true)
			"tank", "park":
				pass # drawn by the water / park areas
			_:
				_part(node, holder, _box(Vector3(10, 10, 10)), Vector3(0, 5, 0), Color.MAGENTA, true)

func _part(node: Node3D, holder: StaticBody3D, mesh: PrimitiveMesh, offset: Vector3, colour: Color, collide: bool) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = colour
	mesh.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset
	node.add_child(mi)
	if collide:
		var cs: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = mesh.get_aabb().size
		cs.shape = box
		cs.transform = node.transform * Transform3D(Basis.IDENTITY, offset)
		holder.add_child(cs)

func _box(size: Vector3) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	return m

func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 12
	return m
