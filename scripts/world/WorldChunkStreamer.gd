class_name WorldChunkStreamer
extends Node3D
## Streams the OSM-built Chennai map (data/world, made by tools/osm/build_world.py).
## Always loaded: ground collision, sea/water/beach/park areas, landmarks.
## Streamed: 250 m chunks (roads + buildings) in a (2r+1)² grid around the player,
## built on WorkerThreadPool and attached on the main thread. Per chunk = 2 draw calls:
## one road mesh (real osm2streets lanes, junctions, sidewalks, markings — or centre-line
## ribbons as a fallback) and one building mesh (real OSM footprints extruded) + a trimesh collider.

## Visual layering (ground plane sits at -0.15 so far-away flat layers never z-fight).
const GROUND_VISUAL_Y: float = -0.15
const ROAD_Y: float = 0.06
const SIDEWALK_Y: float = 0.08
const SIDEWALK_W: float = 2.5
const CHECK_INTERVAL_S: float = 0.25
const CLASS_LAYER: Dictionary = {"trunk": 6, "motorway": 6, "primary": 5, "secondary": 4, "tertiary": 3,
	"unclassified": 2, "residential": 1, "living_street": 0}
## osm2streets surface kinds → [colour, layer height]. "_up" (flyover decks) sit a hair higher.
const SURF_STYLE: Dictionary = {
	"walk": [Color(0.64, 0.6, 0.55), 0.08],
	"junction": [Color(0.28, 0.28, 0.29), 0.05],
	"road": [Color(0.31, 0.31, 0.32), 0.06],
	"lane": [Color(0.88, 0.88, 0.86), 0.07],
	"centre": [Color(0.92, 0.82, 0.42), 0.07],
}
const UP_LAYER_Y: float = 0.012
const GROUND_FLOOR_M: float = 3.2
const COLLIDER_MAX_H: float = 8.0
const KIND_PALETTES: Dictionary = {
	"temple": [Color(0.96, 0.82, 0.5), Color(0.93, 0.7, 0.45), Color(0.98, 0.93, 0.8)],
	"office": [Color(0.6, 0.68, 0.74), Color(0.75, 0.78, 0.8), Color(0.55, 0.6, 0.62)],
	"civic": [Color(0.93, 0.88, 0.76), Color(0.85, 0.5, 0.4), Color(0.95, 0.95, 0.92)],
	"shed": [Color(0.55, 0.58, 0.62), Color(0.45, 0.5, 0.6), Color(0.62, 0.55, 0.48)],
}
## Shop-front / signboard colours for ground floors on busy streets.
const SHOPFRONT: Array[Color] = [Color(0.85, 0.2, 0.15), Color(0.15, 0.4, 0.75), Color(0.95, 0.75, 0.1),
	Color(0.2, 0.6, 0.3), Color(0.35, 0.3, 0.28), Color(0.9, 0.45, 0.1)]
const ROOF_COLOUR: Color = Color(0.7, 0.68, 0.64)
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
var wetness: float = 0.0
var _road_mat: StandardMaterial3D
var _bld_mat: StandardMaterial3D
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
	_build_ground()
	_build_areas()
	_build_landmarks()
	_spawn_player()
	update_streaming(true)

func _process(delta: float) -> void:
	_attach_finished()
	_update_wetness(delta)
	_timer += delta
	if _timer >= CHECK_INTERVAL_S:
		_timer = 0.0
		update_streaming(false)

## Monsoon: roads darken and turn glossy while it rains, then dry off slowly.
func _update_wetness(delta: float) -> void:
	var target: float = 1.0 if GameState.is_raining else 0.0
	if is_equal_approx(wetness, target):
		return
	wetness = move_toward(wetness, target, delta * (0.2 if target > wetness else 0.05))
	_road_mat.albedo_color = Color.WHITE.lerp(Color(0.8, 0.82, 0.86), wetness)
	_road_mat.roughness = lerpf(0.95, 0.3, wetness)
	_road_mat.metallic_specular = lerpf(0.5, 0.9, wetness)

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
	var mesh: ArrayMesh = null
	if data.has("surf"):
		mesh = _surface_mesh(data["surf"] as Dictionary)
	elif data.has("roads"):
		mesh = _road_mesh(data["roads"] as Array)
	if mesh != null:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Roads"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var blds: Array = data.get("blds", [])
	if not blds.is_empty():
		root.add_child(_buildings(blds))
	return root

## Pre-triangulated osm2streets polygons → one flat, vertex-coloured mesh.
func _surface_mesh(surf: Dictionary) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var idx: PackedInt32Array = PackedInt32Array()
	for kind: String in surf:
		var base_kind: String = kind.trim_suffix("_up")
		if not SURF_STYLE.has(base_kind):
			continue
		var style: Array = SURF_STYLE[base_kind]
		var colour: Color = style[0]
		var y: float = float(style[1]) + (UP_LAYER_Y if kind.ends_with("_up") else 0.0)
		var part: Dictionary = surf[kind]
		var v: Array = part["v"]
		var offset: int = verts.size()
		for i: int in range(0, v.size(), 2):
			verts.append(Vector3(float(v[i]), y, float(v[i + 1])))
			cols.append(colour)
		for t: Variant in part["i"]:
			idx.append(int(t) + offset)
	if idx.is_empty():
		return null
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _road_mat)
	return mesh

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

## Real footprints (and procedural fill) extruded to their heights: walls + flat roofs in one
## vertex-coloured mesh, shop-front bands on busy streets, one trimesh collider for the walls.
func _buildings(blds: Array) -> Node3D:
	var holder: StaticBody3D = StaticBody3D.new()
	holder.name = "Buildings"
	holder.collision_layer = 1
	holder.collision_mask = 0
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var faces: PackedVector3Array = PackedVector3Array()
	for b: Dictionary in blds:
		var flat: Array = b["p"]
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(0, flat.size(), 2):
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
		if pts.size() < 3:
			continue
		var h: float = float(b["h"])
		var seed_f: float = float(b.get("s", 0))
		var colour: Color = building_colour(str(b.get("k", "")), str(b.get("z", "")), seed_f)
		var shopfront: bool = h > 6.0 and (str(b.get("k", "")) == "shop" or (str(b.get("z", "")) in ["t_nagar", "anna_salai"] and fposmod(seed_f * 0.37, 1.0) < 0.7))
		var band: Color = SHOPFRONT[int(seed_f) % SHOPFRONT.size()]
		# Signed area tells us the winding, so walls always face outwards.
		var area2: float = 0.0
		for i: int in pts.size():
			area2 += pts[i - 1].cross(pts[i])
		var outward_sign: float = 1.0 if area2 > 0.0 else -1.0
		for i: int in pts.size():
			var a: Vector2 = pts[i - 1]
			var c: Vector2 = pts[i]
			var e: Vector2 = c - a
			if e.length_squared() < 0.0001:
				continue
			var n2: Vector2 = Vector2(e.y, -e.x).normalized() * outward_sign
			var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
			# Cheap fake AO/sun: walls facing the sea-breeze east/south a touch brighter.
			var tint: Color = colour.darkened(0.08 * (1.0 - absf(n2.x)))
			if shopfront:
				_quad(verts, norms, cols, a, c, 0.0, GROUND_FLOOR_M, n, band)
				_quad(verts, norms, cols, a, c, GROUND_FLOOR_M, h, n, tint)
			else:
				_quad(verts, norms, cols, a, c, 0.0, h, n, tint)
			var top: float = minf(h, COLLIDER_MAX_H)
			faces.append_array([Vector3(a.x, 0.0, a.y), Vector3(c.x, 0.0, c.y), Vector3(c.x, top, c.y),
				Vector3(a.x, 0.0, a.y), Vector3(c.x, top, c.y), Vector3(a.x, top, a.y)])
		var tri: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
		var roof: Color = ROOF_COLOUR.lerp(colour, 0.35).darkened(fposmod(seed_f * 0.13, 0.12))
		for t: int in range(0, tri.size(), 3):
			var p0: Vector2 = pts[tri[t]]
			var p1: Vector2 = pts[tri[t + 1]]
			var p2: Vector2 = pts[tri[t + 2]]
			if (p1 - p0).cross(p2 - p0) < 0.0: # clockwise seen from above = faces up
				var tmp: Vector2 = p1
				p1 = p2
				p2 = tmp
			for p: Vector2 in [p0, p1, p2]:
				verts.append(Vector3(p.x, h, p.y))
				norms.append(Vector3.UP)
				cols.append(roof)
	if verts.is_empty():
		return holder
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _bld_mat)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "BuildingMeshes"
	mi.mesh = mesh
	holder.add_child(mi)
	var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	holder.add_child(cs)
	return holder

static func building_colour(kind: String, zone: String, seed_f: float) -> Color:
	var palette: Array = KIND_PALETTES.get(kind, ZONE_PALETTES.get(zone, ZONE_PALETTES[""]))
	var pick: Color = palette[int(seed_f) % palette.size()]
	return pick.darkened(fposmod(seed_f * 0.618, 1.0) * 0.15)

## One wall quad from a→c between heights y0 and y1, facing n (wound for front faces).
func _quad(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, a: Vector2, c: Vector2,
		y0: float, y1: float, n: Vector3, colour: Color) -> void:
	var v0: Vector3 = Vector3(a.x, y0, a.y)
	var v1: Vector3 = Vector3(c.x, y0, c.y)
	var v2: Vector3 = Vector3(c.x, y1, c.y)
	var v3: Vector3 = Vector3(a.x, y1, a.y)
	# Godot front faces are clockwise when viewed from the front.
	var tri: PackedVector3Array = PackedVector3Array([v0, v2, v1, v0, v3, v2])
	if (v1 - v0).cross(v3 - v0).dot(n) <= 0.0:
		tri = PackedVector3Array([v0, v1, v2, v0, v2, v3])
	for v: Vector3 in tri:
		verts.append(v)
		norms.append(n)
		cols.append(colour)

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
