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
const FLOOR_M: float = 3.2
const BAY_M: float = 3.4
const ROOF_TILE_M: float = 6.0
## Facade atlas cells (column, row) — see tools/art/make_facade_atlas.py for the map.
const CELLS_HOME: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(4, 0), Vector2(0, 0), Vector2(4, 0)]
const CELLS_OFFICE: Array[Vector2] = [Vector2(5, 0), Vector2(6, 0)]
const CELLS_HOUSE_GROUND: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(0, 1)]
const CELLS_SHOPS: Array[Vector2] = [Vector2(2, 1), Vector2(3, 1), Vector2(4, 1), Vector2(5, 1), Vector2(6, 1), Vector2(7, 1),
	Vector2(0, 2), Vector2(1, 2), Vector2(2, 2), Vector2(3, 2), Vector2(4, 2), Vector2(5, 2), Vector2(6, 2), Vector2(7, 2)]
const ROOF_CELLS: Array[Vector2] = [Vector2(2, 3), Vector2(3, 3)]
const COLLIDER_MAX_H: float = 8.0
const CITY_MODEL_DIR: String = "res://assets/models/city/"
const LANDMARK_VISIBLE_M: float = 420.0
const SKYLINE_DIST_M: float = 370.0
## Collision boxes for baked landmarks (the visual models carry no colliders).
const CITY_FOOTPRINT: Dictionary = {"water_tower": Vector3(8.0, 18.0, 6.5), "slum_cluster": Vector3(30.0, 4.0, 18.0)}
const KIND_PALETTES: Dictionary = {
	"temple": [Color(0.96, 0.82, 0.5), Color(0.93, 0.7, 0.45), Color(0.98, 0.93, 0.8)],
	"office": [Color(0.6, 0.68, 0.74), Color(0.75, 0.78, 0.8), Color(0.55, 0.6, 0.62)],
	"civic": [Color(0.93, 0.88, 0.76), Color(0.85, 0.5, 0.4), Color(0.95, 0.95, 0.92)],
	"shed": [Color(0.55, 0.58, 0.62), Color(0.45, 0.5, 0.6), Color(0.62, 0.55, 0.48)],
}
const ROOF_COLOUR: Color = Color(0.7, 0.68, 0.64)
## Chennai paint: sun-faded pastels (pink, mint, sky blue, lemon, peach, lavender) between whites
## and creams, terracotta and ochre on older streets.
const ZONE_PALETTES: Dictionary = {
	"marina": [Color(0.93, 0.9, 0.82), Color(0.85, 0.82, 0.7), Color(0.75, 0.82, 0.86), Color(0.96, 0.95, 0.92), Color(0.7, 0.85, 0.88)],
	"mylapore": [Color(0.95, 0.85, 0.6), Color(0.9, 0.72, 0.55), Color(0.8, 0.85, 0.7), Color(0.95, 0.93, 0.85),
		Color(0.93, 0.72, 0.72), Color(0.82, 0.5, 0.38), Color(0.72, 0.86, 0.78)],
	"anna_salai": [Color(0.72, 0.72, 0.75), Color(0.85, 0.83, 0.78), Color(0.6, 0.66, 0.72), Color(0.93, 0.92, 0.88)],
	"t_nagar": [Color(0.95, 0.75, 0.55), Color(0.85, 0.55, 0.5), Color(0.95, 0.9, 0.6), Color(0.7, 0.75, 0.85),
		Color(0.93, 0.7, 0.78), Color(0.72, 0.88, 0.74), Color(0.8, 0.74, 0.92)],
	"": [Color(0.85, 0.8, 0.7), Color(0.78, 0.74, 0.66), Color(0.9, 0.86, 0.78), Color(0.93, 0.74, 0.76),
		Color(0.7, 0.87, 0.76), Color(0.68, 0.8, 0.92), Color(0.95, 0.9, 0.58), Color(0.96, 0.8, 0.62),
		Color(0.8, 0.75, 0.92), Color(0.95, 0.94, 0.9)],
}
## 3D detail layer (all merged into the chunk's one building mesh — no extra draw calls).
## Plain surfaces sample the blank plaster cell and take their colour from the vertex paint.
const PLAIN_CELL: Vector2 = Vector2(7, 0)
const PLAIN_UV: Vector2 = Vector2(0.3, 0.5)
const PARAPET_M: float = 0.9
const LEDGE_MAX_FLOORS: int = 5
const PARAPET_T: float = 0.18
const LEDGE_AT_M: float = 2.6
const LEDGE_OUT_M: float = 0.5
const LEDGE_T: float = 0.1
const DETAIL_MAX_H: float = 30.0
const MUMTY: Vector3 = Vector3(2.4, 2.4, 2.4)
const TANK_COLOURS: Array[Color] = [Color(0.07, 0.07, 0.08), Color(0.07, 0.07, 0.08), Color(0.07, 0.07, 0.08), Color(0.12, 0.3, 0.6), Color(0.92, 0.92, 0.9)]
const AWNING_COLOURS: Array[Color] = [Color(0.13, 0.35, 0.78), Color(0.1, 0.5, 0.3), Color(0.8, 0.18, 0.15),
	Color(0.95, 0.75, 0.1), Color(0.9, 0.9, 0.88), Color(0.15, 0.55, 0.75), Color(0.55, 0.2, 0.5)]
const AC_COLOUR: Color = Color(0.9, 0.9, 0.87)
const POLE_H: float = 8.5
const POLE_ARM_Y: float = 7.9

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
var _bld_mat: ShaderMaterial
var _mutex: Mutex = Mutex.new()
var _finished: Array[Array] = [] # [key, node]
var skyline: Node3D
## Detail layer switches (tests / profiling).
static var details_enabled: bool = true
static var dressing_enabled: bool = true
var skyline_home: Transform3D = Transform3D.IDENTITY

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
	_bld_mat = ShaderMaterial.new()
	_bld_mat.shader = load("res://shaders/building_facade.gdshader") as Shader
	_bld_mat.set_shader_parameter("atlas", load("res://assets/textures/facade_atlas.png") as Texture2D)
	_bld_mat.set_shader_parameter("glow", load("res://assets/textures/facade_glow.png") as Texture2D)
	_build_ground()
	_build_areas()
	_build_landmarks()
	_spawn_player()
	update_streaming(true)

func _process(delta: float) -> void:
	_attach_finished()
	_update_wetness(delta)
	_bld_mat.set_shader_parameter("night", 1.0 - smoothstep(-0.05, 0.2, Atmosphere.sun_height(GameState.shift_minute)))
	_update_skyline()
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
	_player.reset_physics_interpolation()
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
	var dress: Dictionary = {}
	var df: FileAccess = FileAccess.open(world_dir.path_join("dress/c_%d_%d.json" % [k.x, k.y]), FileAccess.READ)
	if df != null:
		dress = JSON.parse_string(df.get_as_text()) as Dictionary
	if not blds.is_empty() or not dress.is_empty():
		root.add_child(_buildings(blds, dress))
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

## Real footprints (and procedural fill) extruded to their heights and skinned from the
## facade atlas (shaders/building_facade.gdshader): window bays per floor, shop fronts with
## Tamil/English boards per ground-floor bay, temple stripes, heritage shutters, terrace roofs.
## One mesh + one trimesh wall collider per chunk.
func _buildings(blds: Array, dress: Dictionary = {}) -> Node3D:
	var holder: StaticBody3D = StaticBody3D.new()
	holder.name = "Buildings"
	holder.collision_layer = 1
	holder.collision_mask = 0
	var m: MeshBuf = MeshBuf.new()
	var faces: PackedVector3Array = PackedVector3Array()
	for b: Dictionary in blds:
		var flat: Array = b["p"]
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(0, flat.size(), 2):
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
		if pts.size() < 3:
			continue
		var h: float = float(b["h"])
		var kind: String = str(b.get("k", ""))
		var zone: String = str(b.get("z", ""))
		var seed_i: int = int(b.get("s", 0))
		var colour: Color = building_colour(kind, zone, float(seed_i))
		var skin: Dictionary = facade_skin(kind, zone, h, seed_i)
		# Signed area tells us the winding, so walls always face outwards.
		var area2: float = 0.0
		for i: int in pts.size():
			area2 += pts[i - 1].cross(pts[i])
		var outward_sign: float = 1.0 if area2 > 0.0 else -1.0
		var floors: float = h / FLOOR_M
		var detailed: bool = details_enabled and h <= DETAIL_MAX_H and not (kind in ["office", "shed"])
		for i: int in pts.size():
			var a: Vector2 = pts[i - 1]
			var c: Vector2 = pts[i]
			var e: Vector2 = c - a
			var length: float = e.length()
			if length < 0.01:
				continue
			var n2: Vector2 = Vector2(e.y, -e.x).normalized() * outward_sign
			var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
			var tint: Color = colour.darkened(0.08 * (1.0 - absf(n2.x)))
			var bays: float = maxf(1.0, roundf(length / BAY_M)) if length >= 2.0 else length / BAY_M
			var ground_top: float = minf(h, FLOOR_M)
			var shops: Array = skin["ground"]
			if bool(skin["per_bay"]) and bays >= 1.0:
				# Each ground-floor bay gets its own shop, so a street front reads as many shops.
				var nb: int = int(bays)
				for k: int in nb:
					var p0: Vector2 = a.lerp(c, float(k) / float(nb))
					var p1: Vector2 = a.lerp(c, float(k + 1) / float(nb))
					var cell: Vector2 = shops[absi(seed_i * 31 + i * 7 + k * 13) % shops.size()]
					_quad(m, p0, p1, 0.0, ground_top, n, tint, Vector2(0.0, 0.0), Vector2(1.0, 1.0), cell)
			else:
				var gcell: Vector2 = shops[absi(seed_i + i) % shops.size()]
				_quad(m, a, c, 0.0, ground_top, n, tint, Vector2(0.0, 0.0), Vector2(bays, ground_top / FLOOR_M), gcell)
			if h > FLOOR_M:
				var ucells: Array = skin["upper"]
				var ucell: Vector2 = ucells[absi(seed_i * 3 + (i % 2)) % ucells.size()]
				_quad(m, a, c, FLOOR_M, h, n, tint, Vector2(0.0, 1.0), Vector2(bays, floors), ucell)
			if detailed:
				_wall_details(m, a, c, n2, h, colour, skin, seed_i * 17 + i)
			var top: float = minf(h, COLLIDER_MAX_H)
			faces.append_array([Vector3(a.x, 0.0, a.y), Vector3(c.x, 0.0, c.y), Vector3(c.x, top, c.y),
				Vector3(a.x, 0.0, a.y), Vector3(c.x, top, c.y), Vector3(a.x, top, a.y)])
		var tri: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
		if detailed and kind != "temple":
			_roof_details(m, pts, tri, h, colour, seed_i, absf(area2) * 0.5, outward_sign)
		var roof: Color = ROOF_COLOUR.lerp(colour, 0.35).darkened(fposmod(float(seed_i) * 0.13, 0.12))
		var rcell: Vector2 = ROOF_CELLS[seed_i % ROOF_CELLS.size()]
		for t: int in range(0, tri.size(), 3):
			var q0: Vector2 = pts[tri[t]]
			var q1: Vector2 = pts[tri[t + 1]]
			var q2: Vector2 = pts[tri[t + 2]]
			if (q1 - q0).cross(q2 - q0) < 0.0: # clockwise seen from above = faces up
				var tmp: Vector2 = q1
				q1 = q2
				q2 = tmp
			for p: Vector2 in [q0, q1, q2]:
				m.add(Vector3(p.x, h, p.y), Vector3.UP, roof, p / ROOF_TILE_M, rcell)
	if dressing_enabled:
		_street_dressing(m, dress)
	if m.verts.is_empty():
		return holder
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = m.verts
	arrays[Mesh.ARRAY_NORMAL] = m.norms
	arrays[Mesh.ARRAY_COLOR] = m.cols
	arrays[Mesh.ARRAY_TEX_UV] = m.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = m.uv2s
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

## Which atlas cells a building uses: {"upper": [cells], "ground": [cells], "per_bay": bool}.
static func facade_skin(kind: String, zone: String, h: float, seed_i: int) -> Dictionary:
	match kind:
		"temple":
			return {"upper": [Vector2(0, 3)], "ground": [Vector2(1, 3), Vector2(0, 3)], "per_bay": false}
		"office":
			return {"upper": CELLS_OFFICE, "ground": [Vector2(5, 0)], "per_bay": false}
		"civic":
			return {"upper": [Vector2(6, 3)], "ground": [Vector2(7, 3)], "per_bay": false}
		"shed":
			return {"upper": [Vector2(7, 0)], "ground": [Vector2(7, 0), Vector2(2, 1)], "per_bay": false}
	var busy: bool = zone in ["t_nagar", "anna_salai"]
	var shop: bool = kind == "shop" or (busy and seed_i % 10 < 7) or (zone == "mylapore" and seed_i % 10 < 3)
	if zone == "mylapore" and h <= 8.0 and not shop and seed_i % 3 == 0:
		return {"upper": [Vector2(4, 3)], "ground": [Vector2(5, 3)], "per_bay": false} # heritage house
	if busy and h > 18.0 and seed_i % 2 == 0:
		return {"upper": CELLS_OFFICE, "ground": CELLS_SHOPS, "per_bay": true}
	if shop:
		return {"upper": CELLS_HOME, "ground": CELLS_SHOPS, "per_bay": true}
	return {"upper": CELLS_HOME, "ground": CELLS_HOUSE_GROUND, "per_bay": false}

# --- Chennai detail layer -----------------------------------------------------------------------

## Per wall: a concrete sunshade ledge over every floor's windows (the Chennai chajja), shop
## awnings over ground-floor bays, the odd AC outdoor unit. n2 = outward normal on the ground plane.
func _wall_details(m: MeshBuf, a: Vector2, c: Vector2, n2: Vector2, h: float, paint: Color, skin: Dictionary, seed_i: int) -> void:
	var e: Vector2 = c - a
	var length: float = e.length()
	if length < 4.0:
		return
	var along: Vector2 = e / length
	var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
	var concrete: Color = paint.lerp(Color(0.92, 0.91, 0.88), 0.55)
	var a2: Vector2 = a + along * 0.15
	var c2: Vector2 = c - along * 0.15
	var floors: int = maxi(1, floori(h / FLOOR_M + 0.01))
	var shop: bool = bool(skin["per_bay"])
	for k: int in mini(floors, LEDGE_MAX_FLOORS):
		if k == 0 and shop:
			continue
		var y: float = float(k) * FLOOR_M + LEDGE_AT_M
		if y > h - 0.25:
			break
		_ledge(m, a2, c2, n2, y, LEDGE_OUT_M, LEDGE_T, concrete, k == 0)
	if shop:
		var nb: int = maxi(1, int(roundf(length / BAY_M)))
		for k: int in nb:
			if absi(seed_i * 7 + k * 5) % 10 >= 6:
				continue
			var p0: Vector2 = a.lerp(c, float(k) / float(nb)) + along * 0.12
			var p1: Vector2 = a.lerp(c, float(k + 1) / float(nb)) - along * 0.12
			var col: Color = AWNING_COLOURS[absi(seed_i * 3 + k * 11) % AWNING_COLOURS.size()]
			_awning(m, p0, p1, n2, 2.95, 2.5, 1.35, col)
	# AC outdoor units: a few per building on upper floors.
	if floors >= 2 and absi(seed_i) % 3 == 0:
		var k2: int = 1 + absi(seed_i) % (floors - 1)
		var t: float = 0.2 + fposmod(float(seed_i) * 0.37, 0.6)
		var p: Vector2 = a.lerp(c, t) + n2 * 0.17
		_dbox(m, Vector3(p.x, float(k2) * FLOOR_M + 1.05, p.y), Vector3(0.85, 0.6, 0.32), along, AC_COLOUR)

## Terrace: parapet wall round the roof, the staircase head-room (mumty) with the black Sintex
## water tank on top of it — the most Chennai roofline there is.
func _roof_details(m: MeshBuf, pts: PackedVector2Array, tri: PackedInt32Array, h: float, paint: Color, seed_i: int, area: float, outward_sign: float) -> void:
	var cap: Color = paint.lerp(Color(0.95, 0.94, 0.9), 0.5)
	for i: int in pts.size():
		var a: Vector2 = pts[i - 1]
		var c: Vector2 = pts[i]
		var e: Vector2 = c - a
		if e.length() < 0.3:
			continue
		var n2: Vector2 = Vector2(e.y, -e.x).normalized() * outward_sign
		var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
		var ai: Vector2 = a - n2 * PARAPET_T
		var ci: Vector2 = c - n2 * PARAPET_T
		var top: float = h + PARAPET_M
		_face(m, [Vector3(a.x, h, a.y), Vector3(c.x, h, c.y), Vector3(c.x, top, c.y), Vector3(a.x, top, a.y)], n, paint)
		_face(m, [Vector3(a.x, top, a.y), Vector3(c.x, top, c.y), Vector3(ci.x, top, ci.y), Vector3(ai.x, top, ai.y)], Vector3.UP, cap)
	if area < 60.0 or tri.size() < 3:
		return
	# Head-room in the largest roof triangle (always inside the footprint), aligned to that triangle's long side.
	var best: int = 0
	var best_area: float = 0.0
	for t: int in range(0, tri.size(), 3):
		var ar: float = absf((pts[tri[t + 1]] - pts[tri[t]]).cross(pts[tri[t + 2]] - pts[tri[t]]))
		if ar > best_area:
			best_area = ar
			best = t
	var q0: Vector2 = pts[tri[best]]
	var q1: Vector2 = pts[tri[best + 1]]
	var q2: Vector2 = pts[tri[best + 2]]
	var centre: Vector2 = (q0 + q1 + q2) / 3.0
	var side: Vector2 = q1 - q0
	if (q2 - q1).length() > side.length():
		side = q2 - q1
	if (q0 - q2).length() > side.length():
		side = q0 - q2
	var along: Vector2 = side.normalized()
	if best_area * 0.5 < 12.0:
		return
	var mumty_col: Color = paint.darkened(0.06)
	var has_mumty: bool = absi(seed_i) % 5 != 0
	var base_y: float = h
	if has_mumty:
		_dbox(m, Vector3(centre.x, h + MUMTY.y * 0.5, centre.y), MUMTY, along, mumty_col)
		base_y = h + MUMTY.y
	var tanks: int = 1 if area < 220.0 else 2
	for k: int in tanks:
		var off: Vector2 = along * (0.0 if tanks == 1 else (float(k) - 0.5) * 1.5)
		var r: float = 0.55 + fposmod(float(seed_i) * 0.21, 0.25)
		var th: float = 1.1 + fposmod(float(seed_i) * 0.17, 0.35)
		var col: Color = TANK_COLOURS[absi(seed_i + k) % TANK_COLOURS.size()]
		var p: Vector2 = centre + off
		_dbox(m, Vector3(p.x, base_y + 0.15, p.y), Vector3(r * 2.1, 0.3, r * 2.1), along, Color(0.62, 0.6, 0.57))
		_tank(m, Vector3(p.x, base_y + 0.3, p.y), r, th, col)

## EB poles with sagging overhead wires and roadside trees (data/world/dress, made by
## tools/osm/build_street_dressing.py), merged into the chunk mesh like everything else.
func _street_dressing(m: MeshBuf, dress: Dictionary) -> void:
	var concrete: Color = Color(0.66, 0.65, 0.62)
	for p: Array in dress.get("poles", []):
		var base: Vector3 = Vector3(float(p[0]), 0.0, float(p[1]))
		var along: Vector2 = Vector2(sin(float(p[2])), cos(float(p[2])))
		_pole(m, base, along, concrete)
	for w: Array in dress.get("wires", []):
		var a: Vector3 = Vector3(float(w[0]), 0.0, float(w[1]))
		var b: Vector3 = Vector3(float(w[2]), 0.0, float(w[3]))
		var d: Vector3 = b - a
		var across: Vector3 = Vector3(-d.z, 0.0, d.x).normalized()
		for k: int in 2:
			var off: Vector3 = across * (float(k) - 0.5) * 1.1 + Vector3(0.0, POLE_ARM_Y + 0.05, 0.0)
			_wire(m, a + off, b + off, 0.35 + 0.12 * float(k))
	for t: Array in dress.get("trees", []):
		var base2: Vector3 = Vector3(float(t[0]), 0.0, float(t[1]))
		match int(t[2]):
			1: _palm(m, base2, float(t[3]), int(t[4]))
			2: _mast_tree(m, base2, float(t[3]), int(t[4]))
			3: _copper_pod(m, base2, float(t[3]), int(t[4]))
			_: _shade_tree(m, base2, float(t[3]), int(t[4]))

func _pole(m: MeshBuf, base: Vector3, along: Vector2, col: Color) -> void:
	var u: Vector3 = Vector3(along.x, 0.0, along.y)
	var w: Vector3 = Vector3(-along.y, 0.0, along.x)
	var top: Vector3 = base + Vector3(0.0, POLE_H, 0.0)
	var r0: float = 0.13
	var r1: float = 0.07
	var c0: Array[Vector3] = [base - u * r0 - w * r0, base + u * r0 - w * r0, base + u * r0 + w * r0, base - u * r0 + w * r0]
	var c1: Array[Vector3] = [top - u * r1 - w * r1, top + u * r1 - w * r1, top + u * r1 + w * r1, top - u * r1 + w * r1]
	for k: int in 4:
		var j: int = (k + 1) % 4
		var mid: Vector3 = (c0[k] + c0[j]) * 0.5 - base
		_face(m, [c0[k], c0[j], c1[j], c1[k]], mid.normalized(), col if k % 2 == 0 else col.darkened(0.12))
	_face(m, [c1[0], c1[1], c1[2], c1[3]], Vector3.UP, col)
	# Cross-arm across the road direction.
	_dbox(m, base + Vector3(0.0, POLE_ARM_Y, 0.0), Vector3(0.1, 0.1, 1.5), along, Color(0.3, 0.3, 0.32))

## Overhead wire: a thin dark ribbon sagging between two points (both faces).
func _wire(m: MeshBuf, a: Vector3, b: Vector3, sag: float) -> void:
	var col: Color = Color(0.08, 0.08, 0.08)
	var segs: int = 3
	var d: Vector3 = b - a
	var side: Vector3 = Vector3(-d.z, 0.0, d.x).normalized()
	var prev: Vector3 = a
	for k: int in range(1, segs + 1):
		var t: float = float(k) / float(segs)
		var p: Vector3 = a.lerp(b, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0)
		var q: Array[Vector3] = [prev, p, p + Vector3(0.0, 0.035, 0.0), prev + Vector3(0.0, 0.035, 0.0)]
		_face(m, q, side, col)
		_face(m, q, -side, col)
		prev = p

## Rain tree (wide umbrella crown, very common on Chennai roads) or neem (rounder, denser),
## picked by seed. Thick trunk that forks into the crown.
func _shade_tree(m: MeshBuf, base: Vector3, s: float, seed_i: int) -> void:
	var bark: Color = Color(0.34, 0.27, 0.2)
	var rain: bool = seed_i % 2 == 0
	var trunk_h: float = (3.6 if rain else 3.0) * s
	var top: Vector3 = base + Vector3(0.0, trunk_h, 0.0)
	_trunk(m, base, top, 0.26 * s, 0.16 * s, bark)
	var greens: Array[Color] = [Color(0.26, 0.46, 0.19), Color(0.21, 0.4, 0.17), Color(0.31, 0.5, 0.21), Color(0.24, 0.43, 0.22)]
	var lobes: int = 5 if rain else 4
	for k: int in lobes:
		var a: float = float(seed_i % 7) + float(k) * TAU / float(lobes)
		var r: float = (1.9 if rain else 1.1) * s
		# Forked limbs out to each lobe.
		var tip: Vector3 = top + Vector3(cos(a) * r * 0.7, (0.9 if rain else 0.8) * s, sin(a) * r * 0.7)
		_trunk(m, top - Vector3(0.0, 0.3 * s, 0.0), tip, 0.1 * s, 0.06 * s, bark)
		var size: Vector3 = Vector3(2.6, 1.2, 2.6) * s if rain else Vector3(2.0, 1.7, 2.0) * s
		_blob(m, top + Vector3(cos(a) * r, (1.1 if rain else 1.0 + float(k % 2) * 0.5) * s, sin(a) * r), size, greens[(seed_i + k) % greens.size()])
	_blob(m, top + Vector3(0.0, (1.5 if rain else 1.8) * s, 0.0), Vector3(3.0, 1.2, 3.0) * s if rain else Vector3(2.2, 1.8, 2.2) * s, greens[seed_i % greens.size()].lightened(0.04))

## Ashoka / mast tree (Polyalthia longifolia): the tall, slim, dark-green column lining Chennai
## avenues and compound walls.
func _mast_tree(m: MeshBuf, base: Vector3, s: float, seed_i: int) -> void:
	var h: float = 8.0 * s + float(seed_i % 5) * 0.3
	_trunk(m, base, base + Vector3(0.0, 1.4 * s, 0.0), 0.13 * s, 0.1 * s, Color(0.3, 0.24, 0.18))
	var green: Color = Color(0.13, 0.3, 0.12)
	var tiers: int = 4
	for k: int in tiers:
		var f: float = float(k) / float(tiers - 1)
		var y: float = 1.6 * s + f * (h - 2.4 * s)
		var w: float = lerpf(1.5, 0.6, f) * s
		_blob(m, base + Vector3(0.0, y + 0.6 * s, 0.0), Vector3(w, 2.2 * s, w), green.lightened(0.05 * float(k % 2)))

## Copper-pod / gulmohar: spreading flat crown, yellow or flame-orange flowers on top.
func _copper_pod(m: MeshBuf, base: Vector3, s: float, seed_i: int) -> void:
	var bark: Color = Color(0.4, 0.33, 0.25)
	var top: Vector3 = base + Vector3(0.0, 3.6 * s, 0.0)
	_trunk(m, base, top, 0.2 * s, 0.13 * s, bark)
	var leaf: Color = Color(0.3, 0.5, 0.2)
	var bloom: Color = Color(0.98, 0.78, 0.1) if seed_i % 3 != 0 else Color(0.95, 0.35, 0.12)
	_blob(m, top + Vector3(0.0, 0.7 * s, 0.0), Vector3(4.6, 1.3, 4.6) * s, leaf)
	for k: int in 3:
		var a: float = float(seed_i % 11) + float(k) * 2.1
		_blob(m, top + Vector3(cos(a) * 1.2 * s, 1.3 * s, sin(a) * 1.2 * s), Vector3(1.6, 0.6, 1.6) * s, bloom if k != 1 else leaf.lightened(0.1))

## Coconut palm: leaning trunk, drooping fronds.
func _palm(m: MeshBuf, base: Vector3, s: float, seed_i: int) -> void:
	var lean_a: float = float(seed_i % 360) * 0.0174533
	var lean: Vector3 = Vector3(cos(lean_a), 0.0, sin(lean_a)) * 0.9 * s
	var h: float = 7.5 * s
	var mid: Vector3 = base + Vector3(0.0, h * 0.5, 0.0) + lean * 0.3
	var top: Vector3 = base + Vector3(0.0, h, 0.0) + lean
	var bark: Color = Color(0.5, 0.42, 0.32)
	_trunk(m, base, mid, 0.2 * s, 0.17 * s, bark)
	_trunk(m, mid, top, 0.17 * s, 0.14 * s, bark.darkened(0.08))
	var frond: Color = Color(0.3, 0.52, 0.2)
	for k: int in 6:
		var a: float = TAU * float(k) / 6.0 + float(seed_i % 10) * 0.1
		var dir: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var tip: Vector3 = top + dir * 2.6 * s - Vector3(0.0, 1.3 * s, 0.0)
		var mid2: Vector3 = top + dir * 1.4 * s + Vector3(0.0, 0.35 * s, 0.0)
		var wv: Vector3 = Vector3(-dir.z, 0.0, dir.x) * 0.45 * s
		var col: Color = frond if k % 2 == 0 else frond.darkened(0.15)
		var q: Array[Vector3] = [top, mid2 - wv, tip, mid2 + wv]
		_face(m, q, Vector3.UP, col)
		_face(m, q, Vector3.DOWN, col.darkened(0.25))
	_blob(m, top - Vector3(0.0, 0.25 * s, 0.0), Vector3(0.6, 0.5, 0.6) * s, Color(0.45, 0.4, 0.15))

func _trunk(m: MeshBuf, a: Vector3, b: Vector3, r0: float, r1: float, col: Color) -> void:
	var sides: int = 5
	for k: int in sides:
		var a0: float = TAU * float(k) / float(sides)
		var a1: float = TAU * float(k + 1) / float(sides)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		var out: Vector3 = (d0 + d1).normalized()
		_face(m, [a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1], out, col.lightened(0.06 * out.x))

## Irregular low-poly leaf crown (12 triangles). Keeps the original mesh/face
## budget while removing the identical diamond silhouette from every tree.
## Variation is deterministic from crown position, so streaming is stable.
func _blob(m: MeshBuf, c: Vector3, size: Vector3, col: Color) -> void:
	var ring: Array[Vector3] = []
	var seed_f: float = c.x * 1.73 + c.z * 2.19 + c.y * 0.61
	var twist: float = sin(seed_f * 0.17) * 0.28
	for k: int in 6:
		var a: float = TAU * float(k) / 6.0 + 0.3 + twist
		var radius: float = 0.82 + 0.18 * sin(seed_f + float(k) * 2.47)
		var rise: float = 0.13 * size.y * sin(seed_f * 0.47 + float(k) * 2.11)
		ring.append(c + Vector3(cos(a) * size.x * 0.5 * radius, rise, sin(a) * size.z * 0.5 * radius))
	var top: Vector3 = c + Vector3(0.12 * size.x * sin(seed_f), size.y * 0.58, 0.09 * size.z * cos(seed_f))
	var bot: Vector3 = c + Vector3(-0.08 * size.x * cos(seed_f), -size.y * 0.44, 0.07 * size.z * sin(seed_f))
	for k: int in 6:
		var p0: Vector3 = ring[k]
		var p1: Vector3 = ring[(k + 1) % 6]
		var tint: float = 0.025 * sin(seed_f + float(k) * 1.9)
		_tri_out(m, p0, p1, top, c, col.lightened(0.08 + maxf(tint, 0.0)))
		_tri_out(m, p0, p1, bot, c, col.darkened(0.12 + maxf(-tint, 0.0)))

## Triangle wound to face away from `centre`.
func _tri_out(m: MeshBuf, a: Vector3, b: Vector3, c: Vector3, centre: Vector3, col: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - centre) < 0.0:
		var t: Vector3 = b
		b = c
		c = t
		n = -n
	var nn: Vector3 = n.normalized()
	for v: Vector3 in [a, c, b]:
		m.add(v, nn, col, PLAIN_UV, PLAIN_CELL)

## Horizontal concrete slab sticking out of a wall (top, underside, front edge).
## The street camera sees ledges from below, so only the ground-floor one gets a top face.
func _ledge(m: MeshBuf, a: Vector2, c: Vector2, n2: Vector2, y: float, out: float, t: float, col: Color, with_top: bool) -> void:
	var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
	var ao: Vector2 = a + n2 * out
	var co: Vector2 = c + n2 * out
	if with_top:
		_face(m, [Vector3(a.x, y, a.y), Vector3(c.x, y, c.y), Vector3(co.x, y, co.y), Vector3(ao.x, y, ao.y)], Vector3.UP, col)
	_face(m, [Vector3(a.x, y - t, a.y), Vector3(c.x, y - t, c.y), Vector3(co.x, y - t, co.y), Vector3(ao.x, y - t, ao.y)], Vector3.DOWN, col.darkened(0.2))
	_face(m, [Vector3(ao.x, y - t, ao.y), Vector3(co.x, y - t, co.y), Vector3(co.x, y, co.y), Vector3(ao.x, y, ao.y)], n, col)

## Sloped shop awning (tarpaulin / tin) with a front valance.
func _awning(m: MeshBuf, a: Vector2, c: Vector2, n2: Vector2, y_wall: float, y_out: float, out: float, col: Color) -> void:
	var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
	var ao: Vector2 = a + n2 * out
	var co: Vector2 = c + n2 * out
	var up: Vector3 = (Vector3.UP * out + n * (y_wall - y_out)).normalized()
	var top: Array[Vector3] = [Vector3(a.x, y_wall, a.y), Vector3(c.x, y_wall, c.y), Vector3(co.x, y_out, co.y), Vector3(ao.x, y_out, ao.y)]
	_face(m, top, up, col)
	_face(m, top, -up, col.darkened(0.35))
	_face(m, [Vector3(ao.x, y_out - 0.28, ao.y), Vector3(co.x, y_out - 0.28, co.y), Vector3(co.x, y_out, co.y), Vector3(ao.x, y_out, ao.y)], n, col.darkened(0.1))

## Box centred at `c` (size x along `along`, z across), five faces (no bottom).
func _dbox(m: MeshBuf, c: Vector3, size: Vector3, along: Vector2, col: Color) -> void:
	var u: Vector3 = Vector3(along.x, 0.0, along.y) * size.x * 0.5
	var w: Vector3 = Vector3(-along.y, 0.0, along.x) * size.z * 0.5
	var hy: Vector3 = Vector3(0.0, size.y * 0.5, 0.0)
	var un: Vector3 = u.normalized()
	var wn: Vector3 = w.normalized()
	var shade: Color = col.darkened(0.12)
	_face(m, [c - u - w + hy, c + u - w + hy, c + u + w + hy, c - u + w + hy], Vector3.UP, col)
	_face(m, [c - u - w - hy, c + u - w - hy, c + u - w + hy, c - u - w + hy], -wn, shade)
	_face(m, [c - u + w - hy, c + u + w - hy, c + u + w + hy, c - u + w + hy], wn, col)
	_face(m, [c + u - w - hy, c + u + w - hy, c + u + w + hy, c + u - w + hy], un, shade)
	_face(m, [c - u - w - hy, c - u + w - hy, c - u + w + hy, c - u - w + hy], -un, col)

## Rooftop water tank: 8-sided drum with a lid.
func _tank(m: MeshBuf, base: Vector3, r: float, h: float, col: Color) -> void:
	var sides: int = 8
	var lid: Vector3 = base + Vector3(0.0, h + 0.12, 0.0)
	for k: int in sides:
		var a0: float = TAU * float(k) / float(sides)
		var a1: float = TAU * float(k + 1) / float(sides)
		var p0: Vector3 = base + Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1: Vector3 = base + Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		var mid: Vector3 = Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		_face(m, [p0, p1, p1 + Vector3(0.0, h, 0.0), p0 + Vector3(0.0, h, 0.0)], mid, col.lightened(0.08 * mid.x))
		var t0: Vector3 = p0 + Vector3(0.0, h, 0.0)
		var t1: Vector3 = p1 + Vector3(0.0, h, 0.0)
		_tri(m, t0, t1, lid, col.lightened(0.12))

## Quad given in any order: wound so its front faces `want_n`.
func _face(m: MeshBuf, q: Array[Vector3], want_n: Vector3, col: Color) -> void:
	var n: Vector3 = (q[1] - q[0]).cross(q[3] - q[0])
	if n.dot(want_n) < 0.0:
		q = [q[3], q[2], q[1], q[0]]
		n = -n
	var nn: Vector3 = n.normalized() if n.length() > 0.0001 else want_n
	for k: int in [0, 2, 1, 0, 3, 2]:
		m.add(q[k], nn, col, PLAIN_UV, PLAIN_CELL)

func _tri(m: MeshBuf, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	var up: bool = n.y >= 0.0
	var nn: Vector3 = n.normalized() * (1.0 if up else -1.0)
	for v: Vector3 in ([a, c, b] if up else [a, b, c]):
		m.add(v, nn, col, PLAIN_UV, PLAIN_CELL)

## One wall quad a→c between heights y0..y1 facing n. uv0/uv1 = bay/floor coordinates at the
## bottom-left/top-right corners (they repeat inside `cell` in the shader).
func _quad(m: MeshBuf, a: Vector2, c: Vector2, y0: float, y1: float, n: Vector3, colour: Color,
		uv0: Vector2, uv1: Vector2, cell: Vector2) -> void:
	var v0: Vector3 = Vector3(a.x, y0, a.y)
	var v1: Vector3 = Vector3(c.x, y0, c.y)
	var v2: Vector3 = Vector3(c.x, y1, c.y)
	var v3: Vector3 = Vector3(a.x, y1, a.y)
	var t0: Vector2 = uv0
	var t1: Vector2 = Vector2(uv1.x, uv0.y)
	var t2: Vector2 = uv1
	var t3: Vector2 = Vector2(uv0.x, uv1.y)
	# Godot front faces are clockwise when viewed from the front.
	var order: PackedInt32Array = PackedInt32Array([0, 2, 1, 0, 3, 2])
	if (v1 - v0).cross(v3 - v0).dot(n) <= 0.0:
		order = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var vs: Array[Vector3] = [v0, v1, v2, v3]
	var ts: Array[Vector2] = [t0, t1, t2, t3]
	for k: int in order:
		m.add(vs[k], n, colour, ts[k], cell)

## Growable vertex buffers for one chunk's building mesh (packed arrays are copied when
## read out of a Dictionary, so they live as members here).
class MeshBuf:
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var uv2s: PackedVector2Array = PackedVector2Array()

	func add(v: Vector3, n: Vector3, c: Color, uv: Vector2, uv2: Vector2) -> void:
		verts.append(v)
		norms.append(n)
		cols.append(c)
		uvs.append(uv)
		uv2s.append(uv2)

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
	_build_city_props(holder)
	for l: Dictionary in manifest.get("landmarks", []):
		var pos: Vector3 = Vector3(float(l["x"]), 0.0, float(l["z"]))
		var yaw: float = float(l.get("yaw", 0.0))
		var node: Node3D = Node3D.new()
		node.name = str(l["id"])
		node.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		holder.add_child(node)
		match str(l["kind"]):
			"lighthouse":
				_kit_part(node, holder, LandmarkKit.lighthouse(), Vector3(14.0, 9.0, 14.0))
			"gopuram":
				_kit_part(node, holder, LandmarkKit.gopuram(), Vector3(25.5, 11.0, 15.5))
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

## A procedural LandmarkKit mesh with a box collider round its base.
func _kit_part(node: Node3D, holder: StaticBody3D, mesh: ArrayMesh, base: Vector3) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = LANDMARK_VISIBLE_M
	node.add_child(mi)
	_base_collider(node, holder, base)

func _base_collider(node: Node3D, holder: StaticBody3D, base: Vector3) -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = base
	cs.shape = box
	cs.transform = node.transform * Transform3D(Basis.IDENTITY, Vector3(0.0, base.y * 0.5, 0.0))
	holder.add_child(cs)

## Baked landmark models (assets/models/city, placed by tools/osm/place_city_props.py):
## TWAD water towers, canal-side settlements, and Chennai Central on the northern skyline.
func _build_city_props(holder: StaticBody3D) -> void:
	var f: FileAccess = FileAccess.open(world_dir.path_join("city_props.json"), FileAccess.READ)
	if f == null:
		return
	var props: Array = (JSON.parse_string(f.get_as_text()) as Dictionary).get("props", [])
	var cache: Dictionary = {}
	var index: int = 0
	for p: Dictionary in props:
		index += 1
		var model: String = str(p["model"])
		var path: String = CITY_MODEL_DIR + model + ".glb"
		if not cache.has(model):
			cache[model] = load(path) if ResourceLoader.exists(path) else null
		var scene: PackedScene = cache[model] as PackedScene
		if scene == null:
			continue
		var inst: Node3D = scene.instantiate() as Node3D
		inst.name = "%s_%d" % [model, index]
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0))).scaled(Vector3.ONE * float(p.get("scale", 1.0))), Vector3(float(p["x"]), 0.0, float(p["z"])))
		if bool(p.get("skyline", false)):
			skyline = inst
			skyline_home = xf
			add_child(inst)
			_set_cast_shadow(inst, false)
			continue
		inst.transform = xf
		holder.add_child(inst)
		var size: Vector3 = CITY_FOOTPRINT.get(model, Vector3.ZERO)
		if size != Vector3.ZERO:
			var node: Node3D = Node3D.new()
			node.transform = xf
			_base_collider(node, holder, size)
			node.free()
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = LANDMARK_VISIBLE_M

func _set_cast_shadow(n: Node, on: bool) -> void:
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Skyline objects live far outside the camera's 400 m range; keep them at the same bearing and
## apparent size inside it (moved in and shrunk in proportion), like a painted backdrop.
func _update_skyline() -> void:
	if skyline == null or _player == null:
		return
	var to: Vector3 = skyline_home.origin - _player.global_position
	to.y = 0.0
	var dist: float = to.length()
	var k: float = minf(1.0, SKYLINE_DIST_M / maxf(dist, 1.0))
	var pos: Vector3 = _player.global_position + to * k
	pos.y = 0.0
	skyline.transform = Transform3D(skyline_home.basis.scaled(Vector3.ONE * k), pos)

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
