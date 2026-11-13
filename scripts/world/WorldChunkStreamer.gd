class_name WorldChunkStreamer
extends Node3D
## Streams the OSM-built Chennai map (data/world, made by tools/osm/build_world.py).
## Always loaded: ground collision, sea/water/beach/park areas, landmarks.
## Streamed: 250 m chunks (roads + buildings) in a (2r+1)² grid around the player,
## built on WorkerThreadPool and attached on the main thread. Per chunk = 2 draw calls:
## one road mesh (real osm2streets lanes, junctions, sidewalks, markings — or centre-line
## ribbons as a fallback) and one building mesh (real OSM footprints extruded) + a trimesh collider.

## Visual layering (ground plane sits at -0.15 so far-away flat layers never z-fight).
## OSM footprint anchors, verified against the shipped chunks. Seed plus position prevents
## unrelated buildings sharing the modulo seed from receiving landmark architecture.
const HERITAGE_SITES: Array[Dictionary] = [
	{"seed": 9138, "point": Vector2(2594.32, -1778.52), "style": "senate"},
	{"seed": 3505, "point": Vector2(2443.58, -1676.04), "style": "palace"},
	{"seed": 3507, "point": Vector2(2462.20, -1573.74), "style": "palace"},
	{"seed": 3634, "point": Vector2(2041.64, 1702.52), "style": "cathedral"},
]
const GROUND_VISUAL_Y: float = -0.15
const ROAD_Y: float = 0.06
const SIDEWALK_Y: float = 0.08
const SIDEWALK_W: float = 2.5
const SURFACE_CELL_M: float = 1.0
## Building-footprint mask cell (finer than the height grid: walkers pass walls within a metre).
const BLOCK_CELL_M: float = 0.5
## Real-size, grounded scooter for every parked two-wheeler. The traffic two_wheeler.glb is a
## 1 m box centred on its origin (fitted at runtime by TrafficModelFit); placed raw it sank.
const PARKED_SCOOTER: String = "res://assets/models/traffic/two_wheeler_pack/scooter_parked.glb"
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
## Surface kind for shaders/street_surface.gdshader (stored in UV.x).
const SURF_KIND: Dictionary = {"road": 0.0, "junction": 0.0, "walk": 1.0, "lane": 2.0, "centre": 2.0}
## Paved plots (data/world/plots, tools/osm/build_plots.py): [colour, shader kind]. They lie
## just under the road layers, so roads and footpaths cover their edges.
const PAVE_STYLE: Dictionary = {
	"cement": [Color(0.63, 0.62, 0.59), 3.0],
	"paver": [Color(0.58, 0.56, 0.54), 4.0],
}
const PLOT_Y: float = 0.012
const GROUND_COLOUR: Color = Color(0.5, 0.45, 0.385)
const GROUND_KIND: float = 5.0
const MEDIAN_KERB_H: float = 0.24
const MEDIAN_COLLIDE_H: float = 1.25
const MEDIAN_BLACK: Color = Color(0.07, 0.07, 0.075)
const MEDIAN_WHITE: Color = Color(0.93, 0.93, 0.9)
const MEDIAN_EARTH: Color = Color(0.36, 0.42, 0.22)
const MEDIAN_CONCRETE: Color = Color(0.62, 0.61, 0.58)
const MEDIAN_RAIL: Color = Color(0.09, 0.47, 0.36)
const MEDIAN_RED: Color = Color(0.85, 0.09, 0.07)
const BARRICADE_GROUND_Y: float = 0.08 # on the footpath
const BARRICADE_YELLOW: Color = Color(0.97, 0.78, 0.08)
const BARRICADE_BLUE: Color = Color(0.1, 0.28, 0.62)
const FLOOR_M: float = 3.2
const BAY_M: float = 3.4
const ROOF_TILE_M: float = 6.0
## Facade atlas cells (column, row) — see tools/art/make_facade_atlas.py for the map.
const CELLS_HOME: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(4, 0), Vector2(0, 0), Vector2(4, 0)]
const CELLS_OFFICE: Array[Vector2] = [Vector2(5, 0), Vector2(6, 0)]
const CELLS_HOUSE_GROUND: Array[Vector2] = [Vector2(0, 1), Vector2(0, 0), Vector2(0, 1)]
const CELLS_SHOPS: Array[Vector2] = [Vector2(2, 1), Vector2(3, 1), Vector2(4, 1), Vector2(5, 1), Vector2(6, 1), Vector2(7, 1),
	Vector2(0, 2), Vector2(1, 2), Vector2(2, 2), Vector2(3, 2), Vector2(4, 2), Vector2(5, 2), Vector2(6, 2), Vector2(7, 2)]
const ROOF_CELLS: Array[Vector2] = [Vector2(2, 3), Vector2(3, 3)]
const COLLIDER_MAX_H: float = 8.0
const CITY_MODEL_DIR: String = "res://assets/models/city/"
const MARINA_LIGHTHOUSE_SCENE: String = "res://assets/models/city/lighthouse/chennai_lighthouse.glb"
const LANDMARK_VISIBLE_M: float = 420.0
const SKYLINE_DIST_M: float = 370.0
## Collision boxes for baked landmarks (the visual models carry no colliders).
const CITY_FOOTPRINT: Dictionary = {
	"water_tower": Vector3(8.0, 18.0, 6.5),
	"slum_cluster": Vector3(30.0, 4.0, 18.0),
	# Roadside shops (tools/assets/bake_street_shops.py): the booth / cart / stall body only,
	# benches and customers stay walk-through.
	"tea_stall": Vector3(2.6, 2.6, 2.4),
	"fruit_cart": Vector3(1.6, 1.2, 1.2),
	"biryani_stall": Vector3(3.2, 2.4, 3.0)
}
## Street shops are many and small: draw them only close by, never into the shadow pass.
const SHOP_VISIBLE_M: Dictionary = {"tea_stall": 100.0, "biryani_stall": 100.0, "fruit_cart": 75.0}
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
## Push-cart open-only / closed-only parts: added to UV2.y (atlas rows are 0–3, so never clashes).
const GATE_OPEN_UV2: float = 100.0
const GATE_CLOSED_UV2: float = 200.0
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
## TNEB double-pole (DP) distribution transformer structure (data/world/dress "xfmr", made by
## tools/osm/build_street_dressing.py). Real layout: two 9 m PSC poles ~2.6 m apart in the EB
## pole line, steel channel platform ~3.2 m up carrying the tank, AB switch and its operating rod,
## lightning arresters and DO fuses above, jumpers down to the HV bushings, LT box low on a pole,
## danger board, anti-climbing collars and earth pipes. The tank is the owner's model baked by
## tools/assets/bake_street_shops.py; everything merges into the chunk's one building mesh.
const XFMR_TANK: String = "res://assets/models/city/eb_transformer.glb"
const XFMR_POLE_H: float = 9.0
const XFMR_HALF_SPAN: float = 1.3
const XFMR_OUT: float = 0.55
const XFMR_PLATFORM_Y: float = 3.2
const XFMR_STEEL: Color = Color(0.24, 0.25, 0.26)
const XFMR_PORCELAIN: Color = Color(0.45, 0.25, 0.15)
const XFMR_GALV: Color = Color(0.72, 0.74, 0.75)

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
var _water_mat: ShaderMaterial
var _road_mat: StandardMaterial3D
var _street_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _bld_mat: ShaderMaterial
## Roadside and park trees (owner's models, near model + far impostors, see StreetTrees.gd).
var trees: StreetTrees
## Baked transformer tank as plain triangles (sRGB vertex colours), read once in _ready and
## only read afterwards (chunk meshes are built on worker threads).
var _xfmr_verts: PackedVector3Array = PackedVector3Array()
var _xfmr_norms: PackedVector3Array = PackedVector3Array()
var _xfmr_cols: PackedColorArray = PackedColorArray()
## Street-shop footprints per chunk (Vector2i -> Array[PackedVector2Array]): pedestrians treat
## them like buildings (walk mask). Filled by _build_city_props before any chunk streams in.
var _prop_blocks: Dictionary = {}
const STALL_HALF: Vector2 = Vector2(1.7, 1.2)
var _stall_kit: Array[Dictionary] = [] # Read once on the main thread, used by chunk workers.
var _cart_kit: Array[Dictionary] = [] # BeachCartKit variants, same pattern.
## Temple-tank footprints (water + ghat steps) per chunk: Vector2i -> PackedVector2Array, 3 points
## per triangle. Walkers never enter a tank (Nov 4: a woman walked between the steps and the wall).
var _tank_blocks: Dictionary = {}
var _compounds: Dictionary = {}
var _mutex: Mutex = Mutex.new()
var _finished: Array[Array] = [] # [key, node]
## Visual ground height per loaded chunk (SURFACE_CELL_M grid of the drawn walk / road / junction
## / park / beach layers, GROUND_VISUAL_Y elsewhere) so people stand ON what is drawn: ~70 % of
## kerb-side spots have no osm2streets sidewalk, and a fixed SIDEWALK_Y floated them 23 cm.
var _heights: Dictionary = {} # Vector2i -> PackedFloat32Array
## Building footprints per loaded chunk (BLOCK_CELL_M grid, 1 = inside a building), so people
## never walk through walls (Oct 31 device test: a woman walked along the kerb line inside a shop).
var _blocked: Dictionary = {} # Vector2i -> PackedByteArray
## Area triangles (park, beach) bucketed by chunk, filled once by _build_areas before streaming
## starts; worker threads only read it. Vector2i -> PackedVector3Array (3 vertices per triangle).
var _area_tris: Dictionary = {}
## Models waiting for their chunk's surface heights (SignalBus.ground_snap_requested).
## Vector2i -> Array[Node3D]. Snapped once: the drawn ground never changes.
var _pending_snaps: Dictionary = {}
var skyline: Node3D
## Detail layer switches (tests / profiling).
static var details_enabled: bool = true
## Chennai building types (BuildingStyles). Off = every building takes the older generic skin.
static var typed_enabled: bool = true
## Paved plots, street-side compound walls and gates (data/world/plots).
static var plots_enabled: bool = true
static var dressing_enabled: bool = true
var skyline_home: Transform3D = Transform3D.IDENTITY

func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	var f: FileAccess = FileAccess.open(world_dir.path_join("manifest.json"), FileAccess.READ)
	if f == null:
		push_error("WorldChunkStreamer: missing manifest — run the OSM Import workflow")
		return
	manifest = JSON.parse_string(f.get_as_text()) as Dictionary
	var cf: FileAccess = FileAccess.open(world_dir.path_join("compounds.json"), FileAccess.READ)
	if cf != null:
		_compounds = (JSON.parse_string(cf.get_as_text()) as Dictionary).get("chunks", {})
	chunk_size = float(manifest["chunk_size"])
	for c: Array in manifest["chunks"]:
		_available[Vector2i(int(c[0]), int(c[1]))] = true
	_road_mat = StandardMaterial3D.new()
	_road_mat.vertex_color_use_as_albedo = true
	_road_mat.vertex_color_is_srgb = true
	_road_mat.roughness = 0.95
	_road_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_street_mat = ShaderMaterial.new()
	_street_mat.shader = load("res://shaders/street_surface.gdshader") as Shader
	_street_mat.set_shader_parameter("detail", load("res://assets/textures/ground_detail.png"))
	_street_mat.set_shader_parameter("rich", int(GameState.settings.get("graphics", 1)) > 0)
	_bld_mat = ShaderMaterial.new()
	_bld_mat.shader = load("res://shaders/building_facade.gdshader") as Shader
	_bld_mat.set_shader_parameter("atlas", load("res://assets/textures/facade_atlas.png") as Texture2D)
	_bld_mat.set_shader_parameter("glow", load("res://assets/textures/facade_glow.png") as Texture2D)
	trees = StreetTrees.new()
	trees.name = "StreetTrees"
	add_child(trees)
	_load_transformer_tank()
	_stall_kit = StreetStallKit.arrays()
	_cart_kit = BeachCartKit.arrays()
	_build_ground()
	_build_areas()
	SignalBus.surface_height_provider = surface_height
	SignalBus.walkable_provider = is_walkable
	SignalBus.ground_snap_requested.connect(request_ground_snap)
	_build_landmarks()
	_spawn_player()
	update_streaming(true)

func _process(delta: float) -> void:
	_attach_finished()
	_update_wetness(delta)
	_bld_mat.set_shader_parameter("night", 1.0 - smoothstep(-0.05, 0.2, Atmosphere.sun_height(GameState.shift_minute)))
	_bld_mat.set_shader_parameter("clock_hour", clock_hour(GameState.shift_minute))
	_update_skyline()
	if trees != null:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			trees.update(cam.global_position)
		elif _player != null:
			trees.update(_player.global_position)
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
	_street_mat.set_shader_parameter("wet", wetness)
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("wet", wetness)
	if _water_mat != null:
		_water_mat.set_shader_parameter("monsoon", wetness)

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
		if loaded.has(k):
			continue
		if _pending.has(k):
			if blocking:
				# A worker is already building this chunk. A blocking load must return with it
				# attached: skipping it left the beach fence without collision for seconds after a
				# teleport, and the auto drove straight through it (phase 10 on CI).
				WorkerThreadPool.wait_for_task_completion(int(_pending[k]))
				_pending.erase(k)
			continue
		if blocking:
			_attach(k, _build_chunk(k))
		else:
			var key: Vector2i = k
			_pending[k] = WorkerThreadPool.add_task(func() -> void: _build_chunk_threaded(key), false, "chunk %s" % k)
	if blocking:
		_attach_finished()
	# Unload with one chunk of hysteresis so driving along a border doesn't thrash.
	for k: Vector2i in loaded.keys():
		if absi(k.x - c.x) > load_radius_chunks + 1 or absi(k.y - c.y) > load_radius_chunks + 1:
			(loaded[k] as Node3D).queue_free()
			loaded.erase(k)
			if trees != null:
				trees.remove_chunk(k)
			_heights.erase(k)
			_blocked.erase(k)

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
	# Heights first: parked vehicles, trees and waiting props stand on this chunk's drawn ground.
	if node.has_meta("surface_heights"):
		_heights[k] = node.get_meta("surface_heights")
		node.remove_meta("surface_heights")
	if node.has_meta("trees"):
		var recs: PackedFloat32Array = node.get_meta("trees")
		node.remove_meta("trees")
		for i: int in range(0, recs.size(), StreetTrees.REC):
			recs[i + 1] = surface_height(recs[i], recs[i + 2], 0.0) - StreetTrees.SINK_M
		if trees != null:
			trees.add_chunk(k, recs)
	if node.has_meta("building_mask"):
		_blocked[k] = node.get_meta("building_mask")
		node.remove_meta("building_mask")
	# Construct parking visuals/collision on the main thread; GLBs are cached by Godot.
	if dressing_enabled:
		RoadsideParking.populate(node, world_dir, k, surface_height, _stand_parking_spots())
	add_child(node)
	loaded[k] = node
	_flush_ground_snaps(k)

## Where SavariManager parks each stand's autos (same maths: 4.2 m to the stand's side).
func _stand_parking_spots() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for st: Dictionary in manifest.get("auto_stands", []):
		var yaw: float = float(st.get("yaw", 0.0))
		var side: Vector2 = Vector2(-cos(yaw), sin(yaw)) # (fwd.z, -fwd.x) with fwd = (-sin, -cos)
		out.append(Vector2(float(st["x"]), float(st["z"])) + side * 4.2)
	return out

## Stand `node` on the drawn ground at its x/z (see SignalBus.ground_snap_requested).
func request_ground_snap(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var p: Vector3 = node.global_position if node.is_inside_tree() else node.position
	var k: Vector2i = chunk_of(p)
	if _heights.has(k) and node.is_inside_tree():
		TrafficModelFit.stand_on_world(node, _ground_under(node))
		return
	if not _pending_snaps.has(k):
		_pending_snaps[k] = []
	(_pending_snaps[k] as Array).append(node)

func _flush_ground_snaps(k: Vector2i) -> void:
	if not _pending_snaps.has(k):
		return
	for n: Variant in _pending_snaps[k]:
		var node: Node3D = n as Node3D
		if is_instance_valid(node) and node.is_inside_tree():
			TrafficModelFit.stand_on_world(node, _ground_under(node))
	_pending_snaps.erase(k)

## Ground height under a model: the highest drawn layer at its origin (a kerb-side scooter whose
## origin is on the sidewalk stands on the sidewalk, not the road beside it).
func _ground_under(node: Node3D) -> float:
	var p: Vector3 = node.global_position
	return surface_height(p.x, p.z, SIDEWALK_Y)

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
	var plot: Dictionary = {}
	if plots_enabled:
		var pf: FileAccess = FileAccess.open(world_dir.path_join("plots/c_%d_%d.json" % [k.x, k.y]), FileAccess.READ)
		if pf != null:
			plot = JSON.parse_string(pf.get_as_text()) as Dictionary
	var mesh: ArrayMesh = null
	if data.has("surf"):
		mesh = _surface_mesh(data["surf"] as Dictionary, plot.get("pave", {}) as Dictionary)
		root.set_meta("surface_heights", _surface_heights(k, data["surf"] as Dictionary))
	elif data.has("roads"):
		mesh = _road_mesh(data["roads"] as Array)
	elif plot.has("pave"):
		mesh = _surface_mesh({}, plot["pave"] as Dictionary)
	var walls: Array = _compounds.get("%d,%d" % [k.x, k.y], [])
	var plot_walls: Array = plot.get("walls", [])
	var gates: Array = plot.get("gates", [])
	# Walkers treat every wall and gate as solid, whoever built it.
	root.set_meta("building_mask", _building_mask(k, data.get("blds", []) as Array, walls + plot_walls + gates))
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
		_block_stalls(root, k, dress.get("stalls", []) as Array)
	if not blds.is_empty() or not dress.is_empty() or not walls.is_empty() or not plot_walls.is_empty():
		root.add_child(_buildings(blds, dress, walls, plot_walls, gates))
	if dressing_enabled and not (dress.get("trees", []) as Array).is_empty():
		root.set_meta("trees", StreetTrees.records(dress["trees"] as Array))
	return root

## Pre-triangulated osm2streets polygons → one flat, vertex-coloured mesh.
func _surface_mesh(surf: Dictionary, pave: Dictionary = {}) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var kinds: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	# Paving first: it is the lowest layer.
	for cls: String in pave:
		if not PAVE_STYLE.has(cls):
			continue
		var pstyle: Array = PAVE_STYLE[cls]
		_surface_part(verts, cols, kinds, idx, pave[cls] as Dictionary, pstyle[0] as Color, PLOT_Y, float(pstyle[1]))
	for kind: String in surf:
		var base_kind: String = kind.trim_suffix("_up")
		if not SURF_STYLE.has(base_kind):
			continue
		var style: Array = SURF_STYLE[base_kind]
		var y: float = float(style[1]) + (UP_LAYER_Y if kind.ends_with("_up") else 0.0)
		_surface_part(verts, cols, kinds, idx, surf[kind] as Dictionary, style[0] as Color, y, float(SURF_KIND[base_kind]))
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
	arrays[Mesh.ARRAY_TEX_UV] = kinds
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _street_mat)
	return mesh

## Append one pre-triangulated layer ({"v": [x, z, ...], "i": [...]}) at height y.
func _surface_part(verts: PackedVector3Array, cols: PackedColorArray, kinds: PackedVector2Array, idx: PackedInt32Array,
		part: Dictionary, colour: Color, y: float, kind: float) -> void:
	var v: Array = part["v"]
	var offset: int = verts.size()
	for i: int in range(0, v.size(), 2):
		verts.append(Vector3(float(v[i]), y, float(v[i + 1])))
		cols.append(colour)
		kinds.append(Vector2(kind, 0.0))
	for t: Variant in part["i"]:
		idx.append(int(t) + offset)

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
func _buildings(blds: Array, dress: Dictionary = {}, walls: Array = [], plot_walls: Array = [], gates: Array = []) -> Node3D:
	var holder: StaticBody3D = StaticBody3D.new()
	holder.name = "Buildings"
	holder.collision_layer = 1
	holder.collision_mask = 0
	var m: MeshBuf = MeshBuf.new()
	var faces: PackedVector3Array = PackedVector3Array()
	for wall: Array in walls:
		var a: Vector2 = Vector2(float(wall[0]), float(wall[1]))
		var b: Vector2 = Vector2(float(wall[2]), float(wall[3]))
		var mid: Vector2 = (a + b) * 0.5
		var h: float = float(wall[4])
		var thickness: float = float(wall[5])
		var colour: Color = Color(0.63, 0.57, 0.46) if str(wall[6]) == "osm" else Color(0.68, 0.65, 0.57)
		_dbox(m, Vector3(mid.x, h * 0.5, mid.y), Vector3(a.distance_to(b), h, thickness), (b - a).normalized(), colour)
		_dbox(m, Vector3(mid.x, h, mid.y), Vector3(a.distance_to(b), 0.12, thickness + 0.12), (b - a).normalized(), colour.darkened(0.15))
		_wall_faces(faces, a, b, 0.0, h + 0.06, thickness)
	for wall: Array in plot_walls:
		_compound_wall(m, faces, wall)
	for gate: Array in gates:
		_compound_gate(m, faces, gate)
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
		var heritage: String = heritage_style(b)
		var colour: Color = building_colour(kind, zone, float(seed_i))
		if heritage != "":
			colour = Color(0.87, 0.85, 0.80) if heritage == "cathedral" else Color(0.66, 0.34, 0.25)
		var skin: Dictionary = facade_skin(kind, zone, h, seed_i)
		# Signed area tells us the winding, so walls always face outwards.
		var area2: float = 0.0
		for i: int in pts.size():
			area2 += pts[i - 1].cross(pts[i])
		var outward_sign: float = 1.0 if area2 > 0.0 else -1.0
		if typed_enabled and heritage == "" and b.has("t"):
			_typed_building(m, faces, b, pts, h, zone, seed_i, outward_sign, absf(area2) * 0.5)
			continue
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
		if heritage != "":
			_heritage_roof(m, pts, h, heritage)
		elif detailed and kind != "temple":
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
	_medians(m, faces, dress.get("medians", []))
	_barricades(m, faces, dress.get("barricades", []))
	# Marina / Santhome: the sand fenced off from the road (tools/osm/build_beach_fence.py).
	_barricades(m, faces, dress.get("beach_fence", []))
	for cart: Array in dress.get("carts", []):
		_cart(m, faces, cart)
	if dressing_enabled:
		_street_dressing(m, dress)
	# Trees are not part of the chunk mesh: StreetTrees draws the owner's models for every
	# loaded chunk (see _build_chunk "trees" meta and _attach).
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

# --- Chennai building types -----------------------------------------------------------------------

## A building whose type ("t") and street-facing walls ("fw") are known
## (tools/osm/classify_buildings.py). The street front gets the type's real face, bay by bay:
## shop boards, stilt parking, balconies, the staircase jaali, showroom cladding. Walls that
## face no street stay one cheap quad per floor band, so the triangles go where the player looks.
func _typed_building(m: MeshBuf, faces: PackedVector3Array, b: Dictionary, pts: PackedVector2Array, h: float,
		zone: String, seed_raw: int, outward_sign: float, area: float) -> void:
	var t: String = str(b["t"])
	var seed_i: int = absi(seed_raw * 7919 + int(pts[0].x * 3.0) + int(pts[0].y * 5.0)) & 0x7FFFFFFF
	var front: Dictionary = {}
	var main_wall: int = -1
	var rank: int = 0
	for w: Array in b.get("fw", []):
		front[int(w[0])] = int(w[1])
		if main_wall < 0:
			main_wall = int(w[0])
			rank = int(w[1])
	var st: Dictionary = BuildingStyles.style(t, zone, h, seed_i, rank)
	var colour: Color = BuildingStyles.paint(t, zone, seed_i)
	var rich: bool = details_enabled and h <= DETAIL_MAX_H
	var floors: float = h / FLOOR_M
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
		var top: float = minf(h, COLLIDER_MAX_H)
		faces.append_array([Vector3(a.x, 0.0, a.y), Vector3(c.x, 0.0, c.y), Vector3(c.x, top, c.y),
			Vector3(a.x, 0.0, a.y), Vector3(c.x, top, c.y), Vector3(a.x, top, a.y)])
		if front.has(i) and length >= 2.4:
			_front_wall(m, a, c, n2, h, tint, st, seed_i + i * 131, rich, i == main_wall)
			continue
		var bays: float = maxf(1.0, roundf(length / BAY_M)) if length >= 2.0 else length / BAY_M
		var ground_top: float = minf(h, FLOOR_M)
		_quad(m, a, c, 0.0, ground_top, n, tint, Vector2(0.0, 0.0), Vector2(bays, ground_top / FLOOR_M),
			BuildingStyles.pick(st["side_ground"] as Array, seed_i + i, 31))
		if h > FLOOR_M:
			_quad(m, a, c, FLOOR_M, h, n, tint, Vector2(0.0, 1.0), Vector2(bays, floors),
				BuildingStyles.pick(st["side_upper"] as Array, seed_i + i, 32))
			# Hand-painted advert high on a blind side wall.
			if rich and bool(st["advert"]) and length >= 7.5 and h >= 9.0 and BuildingStyles.h01(seed_i + i, 33) < 0.10:
				var mid: Vector2 = (a + c) * 0.5
				var half: Vector2 = e / length * 2.9
				var y1: float = h - 0.5
				_tquad(m, _v3(mid - half + n2 * 0.07, y1 - 5.4), _v3(mid + half + n2 * 0.07, y1 - 5.4), _v3(mid + half + n2 * 0.07, y1),
					_v3(mid - half + n2 * 0.07, y1), Rect2(0.03, 0.12, 0.94, 0.76), BuildingStyles.WALL_ADVERT, tint, n)
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	var roof_kind: String = str(st["roof"])
	if roof_kind in ["tiles", "sheet", "thatch"] and pts.size() == 4 and _pitched_roof(m, pts, h, roof_kind, colour, seed_i, outward_sign):
		return
	var clay: bool = roof_kind == "terrace" and BuildingStyles.h01(seed_i, 41) < 0.45
	var roof: Color = Color.WHITE if clay else ROOF_COLOUR.lerp(colour, 0.35).darkened(BuildingStyles.h01(seed_i, 42) * 0.12)
	var rcell: Vector2 = BuildingStyles.ROOF_CLAY if clay else ROOF_CELLS[seed_i % ROOF_CELLS.size()]
	for k: int in range(0, tri.size(), 3):
		var q0: Vector2 = pts[tri[k]]
		var q1: Vector2 = pts[tri[k + 1]]
		var q2: Vector2 = pts[tri[k + 2]]
		if (q1 - q0).cross(q2 - q0) < 0.0:
			var tmp: Vector2 = q1
			q1 = q2
			q2 = tmp
		for p: Vector2 in [q0, q1, q2]:
			m.add(Vector3(p.x, h, p.y), Vector3.UP, roof, p / ROOF_TILE_M, rcell)
	if not rich or t in ["of", "sd"]:
		return
	_roof_details(m, pts, tri, h, colour, seed_i, area, outward_sign)
	match t:
		"tp":
			_roof_shrine(m, pts, tri, h, seed_i)
		"mq":
			_roof_dome(m, pts, tri, h)
		"ch":
			_roof_cross(m, pts, tri, h)

## The paint of the building a compound wall or gate belongs to (same seed, so it matches).
static func _compound_paint(wall: Array) -> Color:
	var zone: String = BuildingStyles.ZONE_IDS[clampi(int(wall[8]), 0, BuildingStyles.ZONE_IDS.size() - 1)]
	return BuildingStyles.paint(str(wall[6]), zone, int(wall[7])).lerp(Color(0.95, 0.94, 0.9), 0.3)

## Street-side compound wall (tools/osm/build_plots.py): [x0, z0, x1, z1, h, thickness, type, seed, zone].
## Both faces show the weathered wall run from the atlas; a long wall carries the stencilled
## panel once. Temple walls are kaavi: red and white stripes.
func _compound_wall(m: MeshBuf, faces: PackedVector3Array, wall: Array) -> void:
	var a: Vector2 = Vector2(float(wall[0]), float(wall[1]))
	var b: Vector2 = Vector2(float(wall[2]), float(wall[3]))
	var length: float = a.distance_to(b)
	if length < 0.2:
		return
	var h: float = float(wall[4])
	var half: float = float(wall[5]) * 0.5
	var along: Vector2 = (b - a) / length
	var n2: Vector2 = Vector2(-along.y, along.x)
	var temple: bool = str(wall[6]) == "tp"
	var paint: Color = Color.WHITE if temple else _compound_paint(wall)
	var cell: Vector2 = BuildingStyles.KAAVI if temple else BuildingStyles.COMPOUND
	var v0: float = 0.0 if temple else BuildingStyles.WALL_RUN_V.x
	var vh: float = (h / FLOOR_M) if temple else BuildingStyles.WALL_RUN_V.y
	var seed_i: int = int(wall[7]) + int(a.x * 7.0) + int(a.y * 3.0)
	# Where the stencilled panel sits along the wall (-1 = none).
	var panel_at: float = -1.0
	if not temple and length >= 5.5 and BuildingStyles.h01(seed_i, 91) < 0.3:
		panel_at = 1.0 + BuildingStyles.h01(seed_i, 92) * (length - 2.0 - BuildingStyles.WALL_PANEL_M)
	for side: float in [1.0, -1.0]:
		var off: Vector2 = n2 * half * side
		var n: Vector3 = Vector3(n2.x, 0.0, n2.y) * side
		var cuts: Array[float] = [0.0, length]
		if panel_at >= 0.0:
			cuts = [0.0, panel_at, panel_at + BuildingStyles.WALL_PANEL_M, length]
		for k: int in cuts.size() - 1:
			var p0: Vector2 = a + along * cuts[k] + off
			var p1: Vector2 = a + along * cuts[k + 1] + off
			var uv: Rect2 = Rect2(cuts[k] / BuildingStyles.WALL_RUN_M, v0, (cuts[k + 1] - cuts[k]) / BuildingStyles.WALL_RUN_M, vh)
			if panel_at >= 0.0 and k == 1:
				uv = BuildingStyles.WALL_PANEL_UV
			_tquad(m, _v3(p0, 0.0), _v3(p1, 0.0), _v3(p1, h), _v3(p0, h), uv, cell, paint, n)
	var cap: Color = (Color(0.72, 0.2, 0.14) if temple else paint.lerp(Color(0.9, 0.89, 0.85), 0.4)).darkened(0.06)
	var o: Vector2 = n2 * (half + 0.03)
	_face(m, [_v3(a - o, h), _v3(b - o, h), _v3(b + o, h), _v3(a + o, h)], Vector3.UP, cap)
	_face(m, [_v3(a - o, 0.0), _v3(a + o, 0.0), _v3(a + o, h), _v3(a - o, h)], _v3(-along, 0.0), cap.darkened(0.1))
	_face(m, [_v3(b - o, 0.0), _v3(b + o, 0.0), _v3(b + o, h), _v3(b - o, h)], _v3(along, 0.0), cap.darkened(0.1))
	_wall_faces(faces, a, b, 0.0, h + 0.06, half * 2.0)

## Gate in a compound wall: two piers and a pair of steel leaves (closed, solid).
func _compound_gate(m: MeshBuf, faces: PackedVector3Array, gate: Array) -> void:
	var a: Vector2 = Vector2(float(gate[0]), float(gate[1]))
	var b: Vector2 = Vector2(float(gate[2]), float(gate[3]))
	var length: float = a.distance_to(b)
	if length < 1.0:
		return
	var h: float = float(gate[4])
	var along: Vector2 = (b - a) / length
	var n2: Vector2 = Vector2(-along.y, along.x)
	var pier: Color = (Color(0.93, 0.9, 0.82) if str(gate[6]) == "tp" else _compound_paint(gate)).lerp(Color(0.96, 0.95, 0.92), 0.35)
	for p: Vector2 in [a + along * 0.2, b - along * 0.2]:
		_dbox(m, Vector3(p.x, (h + 0.3) * 0.5, p.y), Vector3(0.4, h + 0.3, 0.4), along, pier)
		_dbox(m, Vector3(p.x, h + 0.36, p.y), Vector3(0.5, 0.12, 0.5), along, pier.darkened(0.12))
	var g0: Vector2 = a + along * 0.4
	var g1: Vector2 = b - along * 0.4
	var mid: Vector2 = (g0 + g1) * 0.5
	var top: float = h - 0.05
	for side: float in [1.0, -1.0]:
		var n: Vector3 = Vector3(n2.x, 0.0, n2.y) * side
		var off: Vector2 = n2 * 0.04 * side
		for leaf: Array in [[g0, mid], [mid, g1]]:
			var l0: Vector2 = (leaf[0] as Vector2) + off
			var l1: Vector2 = (leaf[1] as Vector2) + off
			_tquad(m, _v3(l0, 0.06), _v3(l1, 0.06), _v3(l1, top), _v3(l0, top), BuildingStyles.GATE_LEAF_UV, BuildingStyles.COMPOUND, Color.WHITE, n)
	_wall_faces(faces, g0, g1, 0.0, top, 0.1)

static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

## Street front: one ground quad and one upper strip per bay, each with its own atlas cell.
func _front_wall(m: MeshBuf, a: Vector2, c: Vector2, n2: Vector2, h: float, tint: Color, st: Dictionary,
		seed_i: int, rich: bool, is_main: bool) -> void:
	var e: Vector2 = c - a
	var length: float = e.length()
	var along: Vector2 = e / length
	var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
	var nb: int = maxi(1, int(roundf(length / BAY_M)))
	var bay_w: float = length / float(nb)
	var ground_top: float = minf(h, FLOOR_M)
	var floors_f: float = h / FLOOR_M
	var floors: int = maxi(1, floori(floors_f + 0.01))
	var shops: bool = bool(st["shops"])
	var ground: Array = st["front_ground"]
	var upper: Array = st["front_upper"]
	var stair_bay: int = (seed_i % nb) if (bool(st["stair"]) and nb >= 3 and floors >= 2) else -1
	var concrete: Color = tint.lerp(Color(0.92, 0.91, 0.88), 0.55)
	# A showroom's sign covers the first floors of its main front: leave those bays plain cladding.
	var sign_cell: int = int(st["sign"]) if is_main else -1
	for k: int in nb:
		var p0: Vector2 = a.lerp(c, float(k) / float(nb))
		var p1: Vector2 = a.lerp(c, float(k + 1) / float(nb))
		var gcell: Vector2 = BuildingStyles.pick(ground, seed_i + k * 13, 51)
		if shops and BuildingStyles.h01(seed_i + k * 13, 52) < 0.07:
			gcell = BuildingStyles.SHUTTER
		elif st["entrance"] != null and k == floori(float(nb) * 0.5):
			gcell = st["entrance"]   # the door, gate or portico: once per street front
		_quad(m, p0, p1, 0.0, ground_top, n, tint, Vector2(0.0, 0.0), Vector2(1.0, ground_top / FLOOR_M), gcell)
		var is_shop: bool = BuildingStyles.SHOPS.has(gcell)
		if rich and is_shop and bay_w >= 2.6:
			if BuildingStyles.h01(seed_i + k * 5, 53) < 0.6:
				var col: Color = AWNING_COLOURS[int(BuildingStyles.h01(seed_i + k * 11, 54) * float(AWNING_COLOURS.size())) % AWNING_COLOURS.size()]
				_awning(m, p0 + along * 0.12, p1 - along * 0.12, n2, 2.95, 2.5, 1.35, col)
		if h <= FLOOR_M + 0.4:
			continue
		var ucell: Vector2 = BuildingStyles.pick(upper, seed_i + k * 29, 55)
		if k == stair_bay:
			ucell = BuildingStyles.JAALI
		_quad(m, p0, p1, FLOOR_M, h, n, tint, Vector2(0.0, 1.0), Vector2(1.0, floors_f), ucell)
		if not rich:
			continue
		# The shop's own board again on the first floor: stacked signs are the look of a bazaar street.
		if is_shop and floors >= 2 and sign_cell < 0 and BuildingStyles.h01(seed_i + k * 7, 56) < 0.45:
			var r: Rect2 = BuildingStyles.SHOP_BOARD_UV
			var q0: Vector2 = p0 + along * 0.1 + n2 * 0.14
			var q1: Vector2 = p1 - along * 0.1 + n2 * 0.14
			var by: float = FLOOR_M + 0.25
			var bh: float = minf(0.95, (bay_w - 0.2) * 0.23)
			_tquad(m, _v3(q0, by), _v3(q1, by), _v3(q1, by + bh), _v3(q0, by + bh), r, gcell, Color.WHITE, n)
		elif (ucell == BuildingStyles.BALCONY or ucell == BuildingStyles.BALCONY_WASH) and bay_w >= 2.6 \
				and BuildingStyles.h01(seed_i + k * 3, 57) < float(st["balcony"]):
			for f: int in range(1, mini(floors, LEDGE_MAX_FLOORS + 1)):
				if float(f) * FLOOR_M + 1.0 > h:
					break
				_balcony(m, (p0 + p1) * 0.5, along, n2, float(f) * FLOOR_M, bay_w - 0.5, tint, ucell == BuildingStyles.BALCONY_WASH, seed_i + k * 17 + f)
	if not rich:
		return
	if bool(st["ledges"]):
		var a2: Vector2 = a + along * 0.15
		var c2: Vector2 = c - along * 0.15
		for k: int in range(1, mini(floors, LEDGE_MAX_FLOORS)):
			var y: float = float(k) * FLOOR_M + LEDGE_AT_M + 0.12
			if y > h - 0.25:
				break
			_ledge(m, a2, c2, n2, y, LEDGE_OUT_M, LEDGE_T, concrete, false)
	if not is_main:
		return
	if sign_cell >= 0 and h >= FLOOR_M * 2.0 and length >= 5.0:
		# Showroom name across the front: a 2 : 1 hoarding cell, as wide as the wall allows.
		var sw: float = minf(length - 0.8, minf(11.0, (h - FLOOR_M - 0.4) * 2.0))
		var sh: float = sw * 0.5
		var mid: Vector2 = (a + c) * 0.5 + n2 * 0.18
		var y0: float = FLOOR_M + 0.2
		_tquad(m, _v3(mid - along * sw * 0.5, y0), _v3(mid + along * sw * 0.5, y0), _v3(mid + along * sw * 0.5, y0 + sh),
			_v3(mid - along * sw * 0.5, y0 + sh), BuildingStyles.FULL_CELL, Vector2(float(sign_cell), BuildingStyles.HOARDING_ROW), Color.WHITE, n)
	if int(st["hoarding"]) >= 0 and length >= 5.0:
		_roof_hoarding(m, (a + c) * 0.5 - n2 * 0.35, along, n2, h, minf(length * 0.85, 9.0), int(st["hoarding"]))

## Textured quad v0→v1 (bottom) → v2→v3 (top) showing `uv` (x, y bottom, w, h in bay/floor UVs)
## of one atlas cell, wound to face `want_n`.
func _tquad(m: MeshBuf, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, uv: Rect2, cell: Vector2, col: Color, want_n: Vector3) -> void:
	var vs: Array[Vector3] = [v0, v1, v2, v3]
	var ts: Array[Vector2] = [uv.position, Vector2(uv.end.x, uv.position.y), uv.end, Vector2(uv.position.x, uv.end.y)]
	var nrm: Vector3 = (v1 - v0).cross(v3 - v0)
	var order: PackedInt32Array = PackedInt32Array([0, 2, 1, 0, 3, 2])
	if nrm.dot(want_n) < 0.0:
		order = PackedInt32Array([0, 1, 2, 0, 2, 3])
		nrm = -nrm
	var nn: Vector3 = nrm.normalized() if nrm.length() > 0.0001 else want_n
	for k: int in order:
		m.add(vs[k], nn, col, ts[k], cell)

## Cantilevered balcony with a solid parapet (the common brick-and-plaster kind), seen from
## below: front, two ends, underside, top rim. Washing hangs over the rail on some.
func _balcony(m: MeshBuf, at: Vector2, along: Vector2, n2: Vector2, floor_y: float, width: float, paint: Color, washing: bool, seed_i: int) -> void:
	var depth: float = 0.95
	var hgt: float = 1.0
	var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
	var u: Vector3 = Vector3(along.x, 0.0, along.y) * width * 0.5
	var base: Vector3 = Vector3(at.x, floor_y - 0.12, at.y)
	var out: Vector3 = n * depth
	var up: Vector3 = Vector3(0.0, hgt + 0.12, 0.0)
	var body: Color = paint.lerp(Color(0.95, 0.94, 0.9), 0.3)
	_face(m, [base - u + out, base + u + out, base + u + out + up, base - u + out + up], n, body)
	_face(m, [base - u, base - u + out, base - u + out + up, base - u + up], -u.normalized(), body.darkened(0.1))
	_face(m, [base + u, base + u + out, base + u + out + up, base + u + up], u.normalized(), body.darkened(0.1))
	_face(m, [base - u, base + u, base + u + out, base - u + out], Vector3.DOWN, body.darkened(0.3))
	_face(m, [base - u + up, base + u + up, base + u + out + up, base - u + out + up], Vector3.UP, body.darkened(0.45))
	if not washing:
		return
	var x: float = -width * 0.5 + 0.15
	var k: int = 0
	var a3: Vector3 = Vector3(along.x, 0.0, along.y)
	var face_at: Vector3 = base + out + n * 0.04 + up
	while x < width * 0.5 - 0.4 and k < 4:
		var w: float = 0.3 + BuildingStyles.h01(seed_i, 60 + k) * 0.35
		var drop: float = 0.35 + BuildingStyles.h01(seed_i, 70 + k) * 0.35
		var cloth: Color = BuildingStyles.WASHING[int(BuildingStyles.h01(seed_i, 80 + k) * float(BuildingStyles.WASHING.size())) % BuildingStyles.WASHING.size()]
		_face(m, [face_at + a3 * x - Vector3(0.0, drop, 0.0), face_at + a3 * (x + w) - Vector3(0.0, drop, 0.0),
			face_at + a3 * (x + w), face_at + a3 * x], n, cloth)
		x += w + 0.1 + BuildingStyles.h01(seed_i, 90 + k) * 0.3
		k += 1

## Hoarding on a steel frame over the street front: two posts, the board, its plain back.
func _roof_hoarding(m: MeshBuf, at: Vector2, along: Vector2, n2: Vector2, h: float, width: float, cell: int) -> void:
	var n: Vector3 = Vector3(n2.x, 0.0, n2.y)
	var a3: Vector3 = Vector3(along.x, 0.0, along.y)
	var bh: float = width * 0.5
	var y0: float = h + PARAPET_M + 0.5
	var mid: Vector3 = Vector3(at.x, 0.0, at.y)
	var steel: Color = Color(0.22, 0.23, 0.25)
	for s: float in [-0.36, 0.36]:
		var foot: Vector3 = mid + a3 * width * s - n * 0.12
		_dbox(m, foot + Vector3(0.0, h + (y0 + bh - h) * 0.5, 0.0), Vector3(0.14, y0 + bh - h, 0.14), along, steel)
	var v0: Vector3 = mid - a3 * width * 0.5 + Vector3(0.0, y0, 0.0)
	var v1: Vector3 = mid + a3 * width * 0.5 + Vector3(0.0, y0, 0.0)
	var up: Vector3 = Vector3(0.0, bh, 0.0)
	_tquad(m, v0, v1, v1 + up, v0 + up, BuildingStyles.FULL_CELL, Vector2(float(cell), BuildingStyles.HOARDING_ROW), Color.WHITE, n)
	_face(m, [v0 - n * 0.05, v1 - n * 0.05, v1 - n * 0.05 + up, v0 - n * 0.05 + up], -n, Color(0.4, 0.41, 0.42))

## Pitched roof on a four-cornered footprint: a tiled or thatched gable with eaves, or a
## single-slope sheet roof. Returns false when the footprint is too skewed to take one.
func _pitched_roof(m: MeshBuf, pts: PackedVector2Array, h: float, kind: String, paint: Color, seed_i: int, outward_sign: float) -> bool:
	var p: Array[Vector2] = [pts[0], pts[1], pts[2], pts[3]]
	if (p[1] - p[0]).length() < (p[2] - p[1]).length():
		p = [pts[1], pts[2], pts[3], pts[0]]
	# p0→p1 and p3→p2 are now the long sides.
	var long_len: float = ((p[1] - p[0]).length() + (p[2] - p[3]).length()) * 0.5
	var span: float = ((p[3] - p[0]).length() + (p[2] - p[1]).length()) * 0.5
	if span < 2.0 or span > 9.0 or long_len > 24.0 or absf((p[1] - p[0]).normalized().dot((p[2] - p[3]).normalized())) < 0.9:
		return false
	var wall: Color = paint.darkened(0.05)
	if kind == "sheet":
		var rise: float = clampf(span * 0.16, 0.45, 1.1)
		var ov: float = 0.3
		var down: Vector2 = (p[3] - p[0]).normalized()
		var lng: Vector2 = (p[1] - p[0]).normalized()
		var hi0: Vector3 = _v3(p[0] - down * ov - lng * ov, h + rise + 0.05)
		var hi1: Vector3 = _v3(p[1] - down * ov + lng * ov, h + rise + 0.05)
		var lo1: Vector3 = _v3(p[2] + down * ov + lng * ov, h + 0.08)
		var lo0: Vector3 = _v3(p[3] + down * ov - lng * ov, h + 0.08)
		var sheet: Color = BuildingStyles.SHEET_COLOURS[seed_i % BuildingStyles.SHEET_COLOURS.size()]
		var uv: Rect2 = Rect2(0.0, 0.0, long_len / 2.4, span / 2.4)
		_tquad(m, lo0, lo1, hi1, hi0, uv, BuildingStyles.ROOF_SHEET, sheet, Vector3.UP)
		_tquad(m, lo0, lo1, hi1, hi0, uv, BuildingStyles.ROOF_SHEET, sheet.darkened(0.45), Vector3.DOWN)
		# Wall carried up to the sheet on the high side and the two ends.
		_face(m, [_v3(p[0], h), _v3(p[1], h), _v3(p[1], h + rise), _v3(p[0], h + rise)], _v3(-down, 0.0), wall)
		for s: Array in [[p[0], p[3], -lng], [p[1], p[2], lng]]:
			var hi: Vector2 = s[0]
			var lo: Vector2 = s[1]
			var o: Vector2 = s[2]
			_tri_facing(m, _v3(hi, h), _v3(lo, h), _v3(hi, h + rise), _v3(o, 0.0), wall)
		return true
	var rh: float = clampf(span * 0.3, 0.9, 3.2)
	var ov2: float = 0.55
	var r0: Vector2 = (p[0] + p[3]) * 0.5
	var r1: Vector2 = (p[1] + p[2]) * 0.5
	var ridge_dir: Vector2 = (r1 - r0).normalized()
	var ra: Vector3 = _v3(r0 - ridge_dir * ov2, h + rh)
	var rb: Vector3 = _v3(r1 + ridge_dir * ov2, h + rh)
	var cell: Vector2 = BuildingStyles.ROOF_THATCH if kind == "thatch" else BuildingStyles.ROOF_TILES
	var slope_len: float = sqrt(span * span * 0.25 + rh * rh)
	var uv2: Rect2 = Rect2(0.0, 0.0, (long_len + ov2 * 2.0) / 3.0, (slope_len + ov2) / 3.0)
	var drop: float = ov2 * rh / (span * 0.5)
	for side: int in 2:
		var e0: Vector2 = p[0] if side == 0 else p[3]
		var e1: Vector2 = p[1] if side == 0 else p[2]
		var o0: Vector2 = (e0 - r0).normalized()
		var o1: Vector2 = (e1 - r1).normalized()
		var v0: Vector3 = _v3(e0 + o0 * ov2 - ridge_dir * ov2, h - drop)
		var v1: Vector3 = _v3(e1 + o1 * ov2 + ridge_dir * ov2, h - drop)
		var up_n: Vector3 = (Vector3.UP * (span * 0.5) + _v3(o0, 0.0) * rh).normalized()
		_tquad(m, v0, v1, rb, ra, uv2, cell, Color.WHITE, up_n)
		_tquad(m, v0, v1, rb, ra, uv2, cell, Color(0.45, 0.4, 0.36), -up_n)
	# Gable ends in the wall colour.
	_tri_facing(m, _v3(p[0], h), _v3(p[3], h), _v3(r0, h + rh), _v3(-ridge_dir, 0.0), wall)
	_tri_facing(m, _v3(p[1], h), _v3(p[2], h), _v3(r1, h + rh), _v3(ridge_dir, 0.0), wall)
	return true

## Plain triangle wound to face `want_n`.
func _tri_facing(m: MeshBuf, a: Vector3, b: Vector3, c: Vector3, want_n: Vector3, col: Color) -> void:
	var nrm: Vector3 = (b - a).cross(c - a)
	var vs: Array[Vector3] = [a, c, b]
	if nrm.dot(want_n) < 0.0:
		vs = [a, b, c]
		nrm = -nrm
	var nn: Vector3 = nrm.normalized() if nrm.length() > 0.0001 else want_n
	for v: Vector3 in vs:
		m.add(v, nn, col, PLAIN_UV, PLAIN_CELL)

## Centre of the largest roof triangle: a spot that is always inside the footprint.
func _roof_spot(pts: PackedVector2Array, tri: PackedInt32Array) -> Vector3:
	var best: float = 0.0
	var at: Vector2 = pts[0]
	for t: int in range(0, tri.size(), 3):
		var ar: float = absf((pts[tri[t + 1]] - pts[tri[t]]).cross(pts[tri[t + 2]] - pts[tri[t]])) * 0.5
		if ar > best:
			best = ar
			at = (pts[tri[t]] + pts[tri[t + 1]] + pts[tri[t + 2]]) / 3.0
	return Vector3(at.x, best, at.y)

## Street-corner temple: a small stepped vimana in painted stucco with a gilt kalasam.
func _roof_shrine(m: MeshBuf, pts: PackedVector2Array, tri: PackedInt32Array, h: float, seed_i: int) -> void:
	var spot: Vector3 = _roof_spot(pts, tri)
	if spot.y < 9.0:
		return
	var s: float = clampf(sqrt(spot.y) * 0.75, 1.6, 5.0)
	var y: float = h
	var tiers: Array[Color] = [Color(0.95, 0.86, 0.62), Color(0.56, 0.78, 0.86), Color(0.94, 0.66, 0.6), Color(0.95, 0.86, 0.62)]
	for k: int in 4:
		var w: float = s * (1.0 - float(k) * 0.2)
		var th: float = s * 0.36
		_dbox(m, Vector3(spot.x, y + th * 0.5, spot.z), Vector3(w, th, w), Vector2.RIGHT, tiers[(k + seed_i) % tiers.size()])
		y += th
	_trunk(m, Vector3(spot.x, y, spot.z), Vector3(spot.x, y + s * 0.3, spot.z), s * 0.3, s * 0.12, Color(0.94, 0.66, 0.6))
	_trunk(m, Vector3(spot.x, y + s * 0.3, spot.z), Vector3(spot.x, y + s * 0.55, spot.z), s * 0.07, 0.02, Color(0.9, 0.72, 0.2))

## Mosque: a green dome on a drum and two slim minarets.
func _roof_dome(m: MeshBuf, pts: PackedVector2Array, tri: PackedInt32Array, h: float) -> void:
	var spot: Vector3 = _roof_spot(pts, tri)
	if spot.y < 12.0:
		return
	var r: float = clampf(sqrt(spot.y) * 0.45, 1.4, 4.0)
	var c: Vector3 = Vector3(spot.x, h, spot.z)
	var white: Color = Color(0.95, 0.95, 0.92)
	var green: Color = Color(0.16, 0.5, 0.34)
	_trunk(m, c, c + Vector3(0, r * 0.5, 0), r, r, white)
	_trunk(m, c + Vector3(0, r * 0.5, 0), c + Vector3(0, r * 1.05, 0), r * 1.02, r * 0.8, green)
	_trunk(m, c + Vector3(0, r * 1.05, 0), c + Vector3(0, r * 1.45, 0), r * 0.8, r * 0.3, green)
	_trunk(m, c + Vector3(0, r * 1.45, 0), c + Vector3(0, r * 1.9, 0), 0.08, 0.02, Color(0.9, 0.75, 0.25))
	for k: int in [0, 1]:
		var p: Vector2 = pts[k % pts.size()].lerp(Vector2(spot.x, spot.z), 0.12)
		var b: Vector3 = Vector3(p.x, h, p.y)
		_trunk(m, b, b + Vector3(0, 5.5, 0), 0.4, 0.32, white)
		_trunk(m, b + Vector3(0, 5.5, 0), b + Vector3(0, 6.0, 0), 0.55, 0.55, green)
		_trunk(m, b + Vector3(0, 6.0, 0), b + Vector3(0, 7.2, 0), 0.42, 0.03, green)

## Church: a short bell turret with a cross.
func _roof_cross(m: MeshBuf, pts: PackedVector2Array, tri: PackedInt32Array, h: float) -> void:
	var spot: Vector3 = _roof_spot(pts, tri)
	if spot.y < 6.0:
		return
	var c: Vector3 = Vector3(spot.x, h, spot.z)
	var cream: Color = Color(0.95, 0.93, 0.86)
	_dbox(m, c + Vector3(0, 1.6, 0), Vector3(1.8, 3.2, 1.8), Vector2.RIGHT, cream)
	_trunk(m, c + Vector3(0, 3.2, 0), c + Vector3(0, 5.2, 0), 1.3, 0.05, Color(0.62, 0.3, 0.22))
	_dbox(m, c + Vector3(0, 6.1, 0), Vector3(0.16, 1.8, 0.16), Vector2.RIGHT, cream)
	_dbox(m, c + Vector3(0, 6.4, 0), Vector3(1.0, 0.16, 0.16), Vector2.RIGHT, cream)

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

## EB poles with sagging overhead wires and TNEB transformers (data/world/dress, made by
## tools/osm/build_street_dressing.py), merged into the chunk mesh like everything else.
func _street_dressing(m: MeshBuf, dress: Dictionary) -> void:
	var concrete: Color = Color(0.66, 0.65, 0.62)
	for p: Array in dress.get("poles", []):
		var base: Vector3 = Vector3(float(p[0]), 0.0, float(p[1]))
		var along: Vector2 = Vector2(sin(float(p[2])), cos(float(p[2])))
		_pole(m, base, along, concrete)
	for x: Array in dress.get("xfmr", []):
		_transformer(m, Vector3(float(x[0]), 0.0, float(x[1])), Vector2(sin(float(x[2])), cos(float(x[2]))),
			Vector2(float(x[3]), float(x[4])), concrete)
	for stall: Array in dress.get("stalls", []):
		_stall(m, stall)
	for w: Array in dress.get("wires", []):
		var a: Vector3 = Vector3(float(w[0]), 0.0, float(w[1]))
		var b: Vector3 = Vector3(float(w[2]), 0.0, float(w[3]))
		var d: Vector3 = b - a
		var across: Vector3 = Vector3(-d.z, 0.0, d.x).normalized()
		for k: int in 2:
			var off: Vector3 = across * (float(k) - 0.5) * 1.1 + Vector3(0.0, POLE_ARM_Y + 0.05, 0.0)
			_wire(m, a + off, b + off, 0.35 + 0.12 * float(k))

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

## Reads the baked tank (one vertex-coloured surface) into flat triangle arrays.
## Walkers go round stalls, as they do buildings.
func _block_stalls(root: Node3D, k: Vector2i, stalls: Array) -> void:
	if stalls.is_empty():
		return
	var mask: PackedByteArray = root.get_meta("building_mask")
	var origin: Vector2 = Vector2(float(k.x), float(k.y)) * chunk_size
	var n: int = int(ceil(chunk_size / BLOCK_CELL_M))
	for s: Array in stalls:
		var at: Vector2 = Vector2(float(s[0]), float(s[1]))
		var along: Vector2 = Vector2(cos(float(s[2])), -sin(float(s[2]))) * STALL_HALF.x
		var deep: Vector2 = Vector2(sin(float(s[2])), cos(float(s[2]))) * STALL_HALF.y
		var c0: Vector2 = at - along - deep
		var c2: Vector2 = at + along + deep
		_mask_triangle(mask, n, origin, c0, at + along - deep, c2)
		_mask_triangle(mask, n, origin, c0, c2, at - along + deep)
	root.set_meta("building_mask", mask)

## Kerb stalls merge into the chunk's one building mesh, like the transformers: no nodes, no
## draw calls, so the city can carry hundreds of them.
func _stall(m: MeshBuf, s: Array) -> void:
	var kind: int = int(s[3])
	if kind < 0 or kind >= _stall_kit.size():
		return
	var at: Vector3 = Vector3(float(s[0]), 0.0, float(s[1]))
	var yaw: float = float(s[2])
	var ground: float = 0.08
	var c: float = cos(yaw)
	var n: float = sin(yaw)
	var kit: Dictionary = _stall_kit[kind]
	var v: PackedVector3Array = kit["v"]
	var nn: PackedVector3Array = kit["n"]
	var col: PackedColorArray = kit["c"]
	for i: int in v.size():
		var p: Vector3 = v[i]
		var q: Vector3 = nn[i]
		m.add(at + Vector3(p.x * c + p.z * n, p.y + ground, -p.x * n + p.z * c), Vector3(q.x * c + q.z * n, q.y, -q.x * n + q.z * c), col[i], PLAIN_UV, PLAIN_CELL)

## Push-cart shop (tools/osm/build_beach_carts.py): [x, z, yaw, variant, name, ground y,
## open hour, close hour]. Merged into the chunk mesh; a solid box so the auto bumps it. The
## open-only / closed-only parts carry their hours in UV (PLAIN_UV + whole numbers, so the facade
## lookup is unchanged) and the gate in UV2.y (+GATE_OPEN_UV2 / +GATE_CLOSED_UV2 on the atlas
## row); building_facade.gdshader hides the part that doesn't match `clock_hour`. Names: CartSigns.
func _cart(m: MeshBuf, faces: PackedVector3Array, s: Array) -> void:
	var kind: int = int(s[3])
	if kind < 0 or kind >= _cart_kit.size():
		return
	var at: Vector3 = Vector3(float(s[0]), 0.0, float(s[1]))
	var yaw: float = float(s[2])
	var ground: float = float(s[5]) if s.size() > 5 else 0.08
	var open_h: int = int(s[6]) if s.size() > 7 else 0
	var close_h: int = int(s[7]) if s.size() > 7 else 24
	var c: float = cos(yaw)
	var n: float = sin(yaw)
	var kit: Dictionary = _cart_kit[kind]
	var v: PackedVector3Array = kit["v"]
	var nn: PackedVector3Array = kit["n"]
	var col: PackedColorArray = kit["c"]
	var gates: PackedByteArray = kit["g"]
	# Hours ride in UV (whole numbers on top of PLAIN_UV), the gate in UV2.y (+100 / +200 on the
	# atlas row). The gate must live in UV2: roofs use world metres / ROOF_TILE_M as UV, so any
	# "big UV" test also caught every roof east of x ≈ 300 m and flung it into the sky.
	var hours_uv: Vector2 = PLAIN_UV + Vector2(float(open_h), float(close_h))
	var uvs: Array[Vector2] = [PLAIN_UV, hours_uv, hours_uv]
	var cells: Array[Vector2] = [PLAIN_CELL, PLAIN_CELL + Vector2(0.0, GATE_OPEN_UV2), PLAIN_CELL + Vector2(0.0, GATE_CLOSED_UV2)]
	for i: int in v.size():
		var p: Vector3 = v[i]
		var q: Vector3 = nn[i]
		m.add(at + Vector3(p.x * c + p.z * n, p.y + ground, -p.x * n + p.z * c), Vector3(q.x * c + q.z * n, q.y, -q.x * n + q.z * c), col[i], uvs[gates[i]], cells[gates[i]])
	var across: Vector2 = Vector2(c, -n) # the cart's local +X (its width)
	var centre: Vector2 = Vector2(at.x, at.z)
	_wall_faces(faces, centre - across * 0.95, centre + across * 0.95, 0.0, 2.2, 1.05)

## Shift clock hour (0–24) for the facade shader's open / closed shop parts.
static func clock_hour(minute: float) -> float:
	return fposmod(minute, 1440.0) / 60.0

func _load_transformer_tank() -> void:
	if not ResourceLoader.exists(XFMR_TANK):
		return
	var scene: PackedScene = load(XFMR_TANK) as PackedScene
	if scene == null:
		return
	var root: Node3D = scene.instantiate() as Node3D
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		var xf: Transform3D = Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for sidx: int in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(sidx)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var c: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = idx.size() if not idx.is_empty() else v.size()
			for k: int in count:
				var i: int = idx[k] if not idx.is_empty() else k
				_xfmr_verts.append(xf * v[i])
				_xfmr_norms.append((xf.basis * nn[i]).normalized())
				# glTF vertex colours are linear; the chunk mesh takes sRGB paint.
				_xfmr_cols.append((c[i] if not c.is_empty() else Color(0.66, 0.68, 0.67)).linear_to_srgb())
	root.free()

## One DP transformer structure. base = pole-line centre on the ground, along = road direction,
## out = unit vector away from the road (the tank and LT box sit on that side).
func _transformer(m: MeshBuf, base: Vector3, along: Vector2, out2: Vector2, concrete: Color) -> void:
	var u: Vector3 = Vector3(along.x, 0.0, along.y)
	var o: Vector3 = Vector3(out2.x, 0.0, out2.y)
	var up: Vector3 = Vector3.UP
	var poles: Array[Vector3] = [base + u * XFMR_HALF_SPAN, base - u * XFMR_HALF_SPAN]
	for k: int in 2:
		var p: Vector3 = poles[k]
		_dp_pole(m, p, along, concrete)
		_dbox(m, p + up * 0.15, Vector3(0.5, 0.3, 0.5), along, concrete.darkened(0.1)) # muffing
		# Anti-climbing barbed-wire collars.
		for y: float in [2.35, 2.6]:
			_dbox(m, p + up * y, Vector3(0.36, 0.07, 0.36), along, Color(0.18, 0.18, 0.18))
		# Earth pipe beside the foot, its pit cover, and the earth strip up the pole.
		var pipe: Vector3 = p + u * (0.45 if k == 0 else -0.45) + o * 0.35
		_dbox(m, pipe + up * 0.03, Vector3(0.45, 0.06, 0.45), along, concrete.lightened(0.08))
		_trunk(m, pipe, pipe + up * 0.5, 0.045, 0.04, XFMR_GALV)
		_dbox(m, p - o * 0.13 + up * 3.4, Vector3(0.05, 6.8, 0.012), along, Color(0.3, 0.3, 0.3))
		# Cantilever arm from the pole to the back channel, with a diagonal brace.
		_dbox(m, p + o * 0.55 + up * (XFMR_PLATFORM_Y - 0.06), Vector3(0.12, 0.12, 1.2), along, XFMR_STEEL)
		_trunk(m, p + up * 2.0 + o * 0.08, p + o * 1.05 + up * (XFMR_PLATFORM_Y - 0.12), 0.035, 0.035, XFMR_STEEL)
	# Platform: two channels along the road carrying the tank.
	for w: float in [0.05, 1.05]:
		_dbox(m, base + o * w + up * (XFMR_PLATFORM_Y - 0.06), Vector3(2.9, 0.12, 0.1), along, XFMR_STEEL)
	# The tank (owner's model), long side along the road.
	var tc: Vector3 = base + o * XFMR_OUT + up * XFMR_PLATFORM_Y
	var w3: Vector3 = u.cross(up) # local +Z
	for i: int in _xfmr_verts.size():
		var v: Vector3 = _xfmr_verts[i]
		var nn: Vector3 = _xfmr_norms[i]
		m.add(tc + u * v.x + up * v.y + w3 * v.z, (u * nn.x + up * nn.y + w3 * nn.z), _xfmr_cols[i], PLAIN_UV, PLAIN_CELL)
	# Top girder where the street's overhead lines end, cross arm and pin insulators.
	var top: float = POLE_ARM_Y + 0.05
	_dbox(m, base + up * top, Vector3(2.9, 0.1, 0.1), along, XFMR_STEEL)
	_dbox(m, base + up * (top - 0.02), Vector3(0.1, 0.1, 1.6), along, XFMR_STEEL)
	for s: float in [-0.55, 0.55]:
		_dbox(m, base + o * s + up * (top + 0.14), Vector3(0.09, 0.18, 0.09), along, XFMR_PORCELAIN)
	# AB switch: frame, three post insulators with blades, operating rod down pole 0 to a handle.
	var ab_y: float = 7.25
	_dbox(m, base + up * ab_y, Vector3(2.7, 0.1, 0.1), along, XFMR_STEEL)
	var phases: Array[float] = [-0.6, 0.0, 0.6]
	for t: float in phases:
		var q: Vector3 = base + u * t + up * ab_y
		_trunk(m, q + up * 0.05, q + up * 0.36, 0.05, 0.04, XFMR_PORCELAIN)
		_dbox(m, q + up * 0.4 + o * 0.12, Vector3(0.04, 0.03, 0.28), along, XFMR_GALV)
	var rod_top: Vector3 = poles[0] + o * 0.16 + up * ab_y
	_trunk(m, rod_top - up * (ab_y - 1.25), rod_top, 0.022, 0.022, XFMR_GALV)
	_dbox(m, poles[0] + o * 0.2 + up * 1.15, Vector3(0.12, 0.22, 0.12), along, XFMR_STEEL)
	# Lightning arresters and DO fuse set, each on its own channel.
	var la_y: float = 6.65
	var do_y: float = 5.95
	_dbox(m, base + up * la_y, Vector3(2.7, 0.08, 0.08), along, XFMR_STEEL)
	_dbox(m, base + up * do_y, Vector3(2.7, 0.08, 0.08), along, XFMR_STEEL)
	for t: float in phases:
		var la: Vector3 = base + u * t + up * la_y
		_trunk(m, la + up * 0.04, la + up * 0.42, 0.06, 0.05, Color(0.55, 0.55, 0.55))
		var f0: Vector3 = base + u * t + o * 0.08 + up * (do_y - 0.28)
		var f1: Vector3 = base + u * t + o * 0.22 + up * (do_y + 0.28)
		_trunk(m, f0, f1, 0.04, 0.04, Color(0.32, 0.2, 0.12))
		# Jumpers: AB switch -> arrester -> fuse -> HV bushing on the tank.
		var bushing: Vector3 = tc + u * (0.2 + t * 0.4) + up * 1.62
		_trunk(m, base + u * t + up * (ab_y + 0.36) + o * 0.02, la + up * 0.42, 0.012, 0.012, Color(0.1, 0.1, 0.1))
		_trunk(m, f1, la + up * 0.04, 0.012, 0.012, Color(0.1, 0.1, 0.1))
		_trunk(m, bushing, f0, 0.012, 0.012, Color(0.1, 0.1, 0.1))
	# LT side: distribution box low on pole 1, cable from the tank, cables up to the street lines
	# and down into the ground.
	var box: Vector3 = poles[1] + o * 0.28 + up * 1.9
	_dbox(m, box, Vector3(0.65, 0.85, 0.32), along, Color(0.42, 0.5, 0.45))
	_dbox(m, box + up * 0.47, Vector3(0.75, 0.06, 0.4), along, Color(0.36, 0.42, 0.38)) # rain hood
	var lt: Color = Color(0.06, 0.06, 0.06)
	_trunk(m, box + up * 0.43, tc - u * 0.75 + up * 1.0, 0.035, 0.035, lt)
	_trunk(m, box + up * 0.43 + u * 0.15, poles[1] + o * 0.18 + up * top, 0.03, 0.03, lt)
	_trunk(m, poles[1] + o * 0.18 + u * 0.12, box - up * 0.42 + u * 0.12, 0.035, 0.035, lt)
	# Danger board on pole 0, facing the road (red band, white plate).
	var board: Vector3 = poles[0] - o * 0.16 + up * 2.0
	_dbox(m, board, Vector3(0.3, 0.38, 0.02), along, Color(0.95, 0.95, 0.92))
	_dbox(m, board + up * 0.13 - o * 0.012, Vector3(0.3, 0.1, 0.012), along, Color(0.8, 0.1, 0.1))
	_dbox(m, board - up * 0.06 - o * 0.012, Vector3(0.12, 0.12, 0.012), along, Color(0.75, 0.12, 0.1))

## Tapered square PSC pole for the DP structure (no cross-arm of its own).
func _dp_pole(m: MeshBuf, base: Vector3, along: Vector2, col: Color) -> void:
	var u: Vector3 = Vector3(along.x, 0.0, along.y)
	var w: Vector3 = Vector3(-along.y, 0.0, along.x)
	var top: Vector3 = base + Vector3(0.0, XFMR_POLE_H, 0.0)
	var r0: float = 0.14
	var r1: float = 0.08
	var c0: Array[Vector3] = [base - u * r0 - w * r0, base + u * r0 - w * r0, base + u * r0 + w * r0, base - u * r0 + w * r0]
	var c1: Array[Vector3] = [top - u * r1 - w * r1, top + u * r1 - w * r1, top + u * r1 + w * r1, top - u * r1 + w * r1]
	for k: int in 4:
		var j: int = (k + 1) % 4
		var mid: Vector3 = (c0[k] + c0[j]) * 0.5 - base
		_face(m, [c0[k], c0[j], c1[j], c1[k]], mid.normalized(), col if k % 2 == 0 else col.darkened(0.12))
	_face(m, [c1[0], c1[1], c1[2], c1[3]], Vector3.UP, col)

func _trunk(m: MeshBuf, a: Vector3, b: Vector3, r0: float, r1: float, col: Color) -> void:
	var sides: int = 5
	var grain: float = sin(a.x * 1.21 + a.z * 0.79 + b.y * 1.87)
	for k: int in sides:
		var a0: float = TAU * float(k) / float(sides)
		var a1: float = TAU * float(k + 1) / float(sides)
		var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		var out: Vector3 = (d0 + d1).normalized()
		var shade: Color = col.lightened(0.055 * maxf(out.x, 0.0))
		shade = shade.darkened(0.045 * maxf(-out.x, 0.0) + 0.025 * maxf(sin(float(k) * 2.7 + grain), 0.0))
		_face(m, [a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1], out, shade)

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

## Centre medians between divided carriageways (tools/osm/build_medians.py), from the owner's
## Chennai photos: "A" = black/white painted kerb, earth bed and a green steel railing (palms come
## through StreetTrees); "B" = black/white striped concrete kerb with red/white delineator posts.
## Each record is [style, x0, z0, w0, x1, z1, w1, …]. Merged into the chunk mesh (no draw calls)
## and into the chunk collider, so the auto can't cut across the median.
func _medians(m: MeshBuf, faces: PackedVector3Array, medians: Array) -> void:
	for rec: Array in medians:
		var railing: bool = str(rec[0]) == "A"
		var kerb_h: float = MEDIAN_KERB_H if railing else MEDIAN_KERB_H + 0.08
		for i: int in range(1, rec.size() - 3, 3):
			var a: Vector2 = Vector2(float(rec[i]), float(rec[i + 1]))
			var b: Vector2 = Vector2(float(rec[i + 3]), float(rec[i + 4]))
			var seg: float = a.distance_to(b)
			if seg < 0.05:
				continue
			var along: Vector2 = (b - a) / seg
			var w: float = (float(rec[i + 2]) + float(rec[i + 5])) * 0.5
			# Painted kerb: alternating black and white blocks, one per 2 m sample (cheap to build).
			var c: Vector2 = (a + b) * 0.5
			var paint: Color = MEDIAN_BLACK if floori(float(i) / 3.0) % 2 == 0 else MEDIAN_WHITE
			_dbox(m, Vector3(c.x, kerb_h * 0.5, c.y), Vector3(seg + 0.02, kerb_h, w), along, paint)
			# Bed on top (top face only).
			var bed: Color = MEDIAN_EARTH if railing else MEDIAN_CONCRETE
			var u3: Vector3 = Vector3(along.x, 0.0, along.y) * (seg * 0.5 + 0.01)
			var w3: Vector3 = Vector3(-along.y, 0.0, along.x) * maxf(w * 0.5 - 0.15, 0.1)
			var c3: Vector3 = Vector3(c.x, kerb_h + 0.01, c.y)
			_face(m, [c3 - u3 - w3, c3 + u3 - w3, c3 + u3 + w3, c3 - u3 + w3], Vector3.UP, bed)
			if railing:
				# Green railing down the middle: a post per sample, two rails, two balusters.
				_dbox(m, Vector3(a.x, kerb_h + 0.5, a.y), Vector3(0.07, 1.0, 0.07), along, MEDIAN_RAIL.darkened(0.2))
				for rail_y: float in [0.38, 0.95]:
					_dbox(m, Vector3(c.x, kerb_h + rail_y, c.y), Vector3(seg, 0.05, 0.05), along, MEDIAN_RAIL)
				for f: float in [0.33, 0.67]:
					var bp: Vector2 = a.lerp(b, f)
					_dbox(m, Vector3(bp.x, kerb_h + 0.66, bp.y), Vector3(0.03, 0.56, 0.03), along, MEDIAN_RAIL)
			else:
				# Flexible delineator post: red with a white reflective band.
				_dbox(m, Vector3(a.x, kerb_h + 0.39, a.y), Vector3(0.09, 0.78, 0.09), along, MEDIAN_RED)
				_dbox(m, Vector3(a.x, kerb_h + 0.58, a.y), Vector3(0.1, 0.12, 0.1), along, MEDIAN_WHITE)
			_wall_faces(faces, a - along * 0.05, b + along * 0.05, 0.0, MEDIAN_COLLIDE_H if railing else MEDIAN_COLLIDE_H - 0.3, w)

## Roadside barricades on the kerb (tools/osm/build_barricades.py): [x, z, yaw, type] with
## 0 = traffic-police steel (yellow/black), 1 = water-filled plastic (red/white), 2 = Corporation
## steel (blue/white). Merged into the chunk mesh and collider like the medians.
func _barricades(m: MeshBuf, faces: PackedVector3Array, items: Array) -> void:
	var i: int = 0
	for it: Array in items:
		i += 1
		var c: Vector2 = Vector2(float(it[0]), float(it[1]))
		var yaw: float = float(it[2])
		var along: Vector2 = Vector2(sin(yaw), cos(yaw))
		var across: Vector2 = Vector2(along.y, -along.x)
		var kind: int = int(it[3])
		var g: float = BARRICADE_GROUND_Y
		if kind == 1:
			var col: Color = MEDIAN_RED if i % 2 == 0 else MEDIAN_WHITE
			_dbox(m, Vector3(c.x, g + 0.3, c.y), Vector3(1.9, 0.6, 0.55), along, col)
			_dbox(m, Vector3(c.x, g + 0.71, c.y), Vector3(1.7, 0.22, 0.3), along, col)
			_wall_faces(faces, c - along * 0.95, c + along * 0.95, 0.0, 0.85, 0.5)
			continue
		var stripe_a: Color = BARRICADE_YELLOW if kind == 0 else MEDIAN_WHITE
		var stripe_b: Color = MEDIAN_BLACK if kind == 0 else BARRICADE_BLUE
		for sgn: float in [-1.0, 1.0]:
			var end: Vector2 = c + along * (0.95 * sgn)
			_dbox(m, Vector3(end.x, g + 0.03, end.y), Vector3(0.08, 0.06, 0.75), along, MEDIAN_BLACK) # foot
			_dbox(m, Vector3(end.x, g + 0.55, end.y), Vector3(0.05, 1.05, 0.05), along, stripe_b) # upright
		for rail_y: float in [0.24, 1.06]:
			_dbox(m, Vector3(c.x, g + rail_y, c.y), Vector3(1.95, 0.06, 0.05), along, stripe_a)
		for k: int in 5:
			var p: Vector2 = c + along * (-0.76 + 0.38 * float(k))
			_dbox(m, Vector3(p.x, g + 0.65, p.y), Vector3(0.36, 0.74, 0.025), along, stripe_a if k % 2 == 0 else stripe_b)
		# Name plate in the middle (blue "Traffic Police" / white Corporation plate).
		var plate: Vector2 = c + across * 0.02
		_dbox(m, Vector3(plate.x, g + 0.82, plate.y), Vector3(0.8, 0.22, 0.04), along, BARRICADE_BLUE if kind == 0 else MEDIAN_WHITE.darkened(0.05))
		_wall_faces(faces, c - along * 1.0, c + along * 1.0, 0.0, 1.1, 0.12)

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
	# Packed earth with the same world-space detail as the roads (one extra material, same shader).
	_ground_mat = _street_mat.duplicate() as ShaderMaterial
	_ground_mat.set_shader_parameter("fixed_kind", GROUND_KIND)
	_ground_mat.set_shader_parameter("fixed_colour", GROUND_COLOUR)
	plane.material = _ground_mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3((float(b[0]) + float(b[2])) * 0.5, GROUND_VISUAL_Y, (float(b[1]) + float(b[3])) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)

func _bucket_area_triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var lo: Vector2i = Vector2i(floori(minf(a.x, minf(b.x, c.x)) / chunk_size), floori(minf(a.z, minf(b.z, c.z)) / chunk_size))
	var hi: Vector2i = Vector2i(floori(maxf(a.x, maxf(b.x, c.x)) / chunk_size), floori(maxf(a.z, maxf(b.z, c.z)) / chunk_size))
	for i: int in range(lo.x, hi.x + 1):
		for j: int in range(lo.y, hi.y + 1):
			var key: Vector2i = Vector2i(i, j)
			if not _area_tris.has(key):
				_area_tris[key] = PackedVector3Array()
			var arr: PackedVector3Array = _area_tris[key]
			arr.append(a)
			arr.append(b)
			arr.append(c)
			_area_tris[key] = arr

## Height of the drawn ground at (x, z): walk 0.08, road 0.06, junction 0.05, park/beach, or the
## bare ground plane. Unloaded chunks return `fallback`.
## False inside a building footprint. Unloaded chunks count as walkable (nothing drawn there).
func is_walkable(x: float, z: float) -> bool:
	var k: Vector2i = Vector2i(floori(x / chunk_size), floori(z / chunk_size))
	if not _blocked.has(k):
		return true
	var mask: PackedByteArray = _blocked[k]
	var n: int = int(ceil(chunk_size / BLOCK_CELL_M))
	var ci: int = clampi(int((x - float(k.x) * chunk_size) / BLOCK_CELL_M), 0, n - 1)
	var cj: int = clampi(int((z - float(k.y) * chunk_size) / BLOCK_CELL_M), 0, n - 1)
	return mask[cj * n + ci] == 0

## Worker-thread raster of this chunk's building footprints (same polygons as the walls).
func _building_mask(k: Vector2i, blds: Array, walls: Array = []) -> PackedByteArray:
	var n: int = int(ceil(chunk_size / BLOCK_CELL_M))
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(n * n)
	mask.fill(0)
	var origin: Vector2 = Vector2(float(k.x), float(k.y)) * chunk_size
	for wall: Array in walls:
		var a: Vector2 = Vector2(float(wall[0]), float(wall[1]))
		var b: Vector2 = Vector2(float(wall[2]), float(wall[3]))
		var d: Vector2 = (b - a).normalized()
		var side: Vector2 = Vector2(-d.y, d.x) * (float(wall[5]) * 0.5 + BLOCK_CELL_M)
		_mask_triangle(mask, n, origin, a - side, b - side, b + side)
		_mask_triangle(mask, n, origin, a - side, b + side, a + side)
	for b: Variant in blds:
		var flat: Array = (b as Dictionary)["p"]
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(0, flat.size(), 2):
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
		if pts.size() < 3:
			continue
		var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
		for t: int in range(0, idx.size(), 3):
			_mask_triangle(mask, n, origin, pts[idx[t]], pts[idx[t + 1]], pts[idx[t + 2]])
	# Street shops stand on the pavement like little buildings: walkers go round them.
	for poly: PackedVector2Array in _prop_blocks.get(k, []):
		_mask_triangle(mask, n, origin, poly[0], poly[1], poly[2])
		_mask_triangle(mask, n, origin, poly[0], poly[2], poly[3])
	var tank: PackedVector2Array = _tank_blocks.get(k, PackedVector2Array())
	for t: int in range(0, tank.size(), 3):
		_mask_triangle(mask, n, origin, tank[t], tank[t + 1], tank[t + 2])
	return mask

func _mask_triangle(mask: PackedByteArray, n: int, origin: Vector2, a: Vector2, b: Vector2, c: Vector2) -> void:
	var area: float = (b - a).cross(c - a)
	if absf(area) < 1e-6:
		return
	var i0: int = maxi(0, floori((minf(a.x, minf(b.x, c.x)) - origin.x) / BLOCK_CELL_M))
	var i1: int = mini(n - 1, floori((maxf(a.x, maxf(b.x, c.x)) - origin.x) / BLOCK_CELL_M))
	var j0: int = maxi(0, floori((minf(a.y, minf(b.y, c.y)) - origin.y) / BLOCK_CELL_M))
	var j1: int = mini(n - 1, floori((maxf(a.y, maxf(b.y, c.y)) - origin.y) / BLOCK_CELL_M))
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var p: Vector2 = origin + Vector2((float(i) + 0.5) * BLOCK_CELL_M, (float(j) + 0.5) * BLOCK_CELL_M)
			var w0: float = (b - p).cross(c - p) / area
			var w1: float = (c - p).cross(a - p) / area
			if w0 < -0.02 or w1 < -0.02 or w0 + w1 > 1.02:
				continue
			mask[j * n + i] = 1

func surface_height(x: float, z: float, fallback: float = SIDEWALK_Y) -> float:
	var k: Vector2i = Vector2i(floori(x / chunk_size), floori(z / chunk_size))
	if not _heights.has(k):
		return fallback
	var grid: PackedFloat32Array = _heights[k]
	var n: int = int(ceil(chunk_size / SURFACE_CELL_M))
	var ci: int = clampi(int((x - float(k.x) * chunk_size) / SURFACE_CELL_M), 0, n - 1)
	var cj: int = clampi(int((z - float(k.y) * chunk_size) / SURFACE_CELL_M), 0, n - 1)
	return grid[cj * n + ci]

## Worker-thread raster of one chunk's drawn layers (highest layer wins per cell centre).
func _surface_heights(k: Vector2i, surf: Dictionary) -> PackedFloat32Array:
	var n: int = int(ceil(chunk_size / SURFACE_CELL_M))
	var grid: PackedFloat32Array = PackedFloat32Array()
	grid.resize(n * n)
	grid.fill(GROUND_VISUAL_Y)
	var origin: Vector2 = Vector2(float(k.x), float(k.y)) * chunk_size
	var areas: PackedVector3Array = _area_tris.get(k, PackedVector3Array())
	for t: int in range(0, areas.size(), 3):
		_raster_triangle(grid, n, origin, Vector2(areas[t].x, areas[t].z), Vector2(areas[t + 1].x, areas[t + 1].z), Vector2(areas[t + 2].x, areas[t + 2].z), areas[t].y)
	for kind: String in surf:
		var base_kind: String = kind.trim_suffix("_up")
		if not base_kind in ["walk", "road", "junction"]:
			continue
		var y: float = float(SURF_STYLE[base_kind][1]) + (UP_LAYER_Y if kind.ends_with("_up") else 0.0)
		var part: Dictionary = surf[kind]
		var v: Array = part["v"]
		var ix: Array = part["i"]
		for t: int in range(0, ix.size() - 2, 3):
			var a: int = int(ix[t]) * 2
			var b: int = int(ix[t + 1]) * 2
			var c: int = int(ix[t + 2]) * 2
			_raster_triangle(grid, n, origin, Vector2(float(v[a]), float(v[a + 1])), Vector2(float(v[b]), float(v[b + 1])), Vector2(float(v[c]), float(v[c + 1])), y)
	return grid

func _raster_triangle(grid: PackedFloat32Array, n: int, origin: Vector2, a: Vector2, b: Vector2, c: Vector2, y: float) -> void:
	var area: float = (b - a).cross(c - a)
	if absf(area) < 1e-6:
		return
	var i0: int = maxi(0, floori((minf(a.x, minf(b.x, c.x)) - origin.x) / SURFACE_CELL_M))
	var i1: int = mini(n - 1, floori((maxf(a.x, maxf(b.x, c.x)) - origin.x) / SURFACE_CELL_M))
	var j0: int = maxi(0, floori((minf(a.y, minf(b.y, c.y)) - origin.y) / SURFACE_CELL_M))
	var j1: int = mini(n - 1, floori((maxf(a.y, maxf(b.y, c.y)) - origin.y) / SURFACE_CELL_M))
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var p: Vector2 = origin + Vector2((float(i) + 0.5) * SURFACE_CELL_M, (float(j) + 0.5) * SURFACE_CELL_M)
			var w0: float = (b - p).cross(c - p) / area
			var w1: float = (c - p).cross(a - p) / area
			if w0 < 0.0 or w1 < 0.0 or w0 + w1 > 1.0:
				continue
			var cell: int = j * n + i
			if y > grid[cell]:
				grid[cell] = y

func _build_areas() -> void:
	var f: FileAccess = FileAccess.open(world_dir.path_join("areas.json"), FileAccess.READ)
	if f == null:
		return
	var areas: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var specs: Dictionary = {
		"sea": [Color(0.18, 0.42, 0.6), -0.05], "water": [Color(0.22, 0.45, 0.55), -0.02],
		"beach": [Color(0.93, 0.85, 0.62), -0.08], "park": [Color(0.42, 0.62, 0.32), -0.07],
	}
	var built_water: bool = _build_water()
	for kind: String in specs:
		var polys: Array = areas.get(kind, [])
		if polys.is_empty() or (kind == "water" and built_water):
			continue
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		var y: float = float(specs[kind][1])
		var water_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		water_rng.seed = 80421
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
				if kind in ["beach", "park"]:
					_bucket_area_triangle(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y))
				var tint: Color = Color(0.10, 0.43, 0.53).lerp(Color(0.23, 0.63, 0.68), water_rng.randf())
				var ripple: float = water_rng.randf_range(-0.012, 0.012) if kind == "water" else 0.0
				for v: Vector2 in [a, b, c]:
					st.set_color(tint)
					st.add_vertex(Vector3(v.x, y + ripple, v.y))
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = specs[kind][0]
		mat.vertex_color_use_as_albedo = kind == "water"
		mat.roughness = 0.38 if kind in ["sea", "water"] else 1.0
		mat.metallic = 0.08 if kind == "water" else 0.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Area_" + kind
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		if kind == "water":
			_build_water_barriers(polys, y)

## Low retaining edge around ponds and lakes: a visible concrete curb and a solid collision
## barrier. Water remains a visual-only surface, so the player cannot drive over a lake.
## Low-poly canals / ponds / temple tanks from data/world/water.json (tools/osm/build_water.py):
## one faceted water mesh, one mesh for every bank wall, tank ghat and bridge parapet (vertex
## colours, one draw call), one concave collision shape for the walls. Banks are open where
## roads cross water (Oct 31: an invisible wall blocked the Venkatesa Agraharam Road bridge).
## Returns false when the file is missing (the legacy flat water + kerbs are used then).
const WATER_Y: float = -0.02
const BANK_H: float = 0.95
## Temple-tank parapet: taller than a canal wall so the top ghat step sits below its coping
## (Nov 4: the steps rose 16 cm above the old 0.95 m wall).
const TANK_WALL_H: float = 1.3
const BANK_T: float = 0.32
const RAIL_H: float = 1.0
const POST_EVERY_M: float = 6.0
## Banks are built per BANK_TILE_M tile and drawn only within BANK_VISIBLE_M (8.5 km of canal
## wall in one always-drawn mesh was ~200k vertices).
const BANK_TILE_M: float = 250.0
const BANK_VISIBLE_M: float = 350.0
const STRIPE_M: float = 1.6
const GHAT_STEPS: int = 5
## = tools/osm/build_water.py GHAT_INSET_M: the "steps" ring is the tank outline inset this far.
const GHAT_WIDTH_M: float = 5.0
## Top tread, just under the tank parapet's coping (base GROUND_VISUAL_Y + TANK_WALL_H = 1.15).
const GHAT_TOP_Y: float = 0.72
const CANAL_WHITE: Color = Color(0.86, 0.85, 0.80)
const CANAL_CAP: Color = Color(0.55, 0.55, 0.52)
const TANK_RED: Color = Color(0.70, 0.17, 0.12) # temple kavi stripes
const TANK_WHITE: Color = Color(0.93, 0.90, 0.84)
const GHAT_STONE: Color = Color(0.50, 0.48, 0.45) # granite
const HAZARD_YELLOW: Color = Color(0.96, 0.78, 0.10)
const HAZARD_BLACK: Color = Color(0.10, 0.10, 0.10)

func _build_water() -> bool:
	var f: FileAccess = FileAccess.open(world_dir.path_join("water.json"), FileAccess.READ)
	if f == null:
		return false
	var data: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var surf: Dictionary = data.get("surface", {})
	var v: Array = surf.get("v", [])
	var d: Array = surf.get("d", [])
	var ix: Array = surf.get("i", [])
	if not ix.is_empty():
		var verts: PackedVector3Array = PackedVector3Array()
		var uvs: PackedVector2Array = PackedVector2Array()
		var normals: PackedVector3Array = PackedVector3Array()
		for i: int in d.size():
			verts.append(Vector3(float(v[i * 2]), WATER_Y, float(v[i * 2 + 1])))
			uvs.append(Vector2(float(d[i]), 0.0))
			normals.append(Vector3.UP)
		var idx: PackedInt32Array = PackedInt32Array()
		for t: Variant in ix:
			idx.append(int(t))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://shaders/water_lowpoly.gdshader") as Shader
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Area_water"
		mi.mesh = mesh
		mi.material_override = _water_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var tiles: Dictionary = {} # Vector2i -> SurfaceTool
	var faces: PackedVector3Array = PackedVector3Array()
	for b: Variant in data.get("banks", []):
		var seg: Array = b
		var a: Vector2 = Vector2(float(seg[0]), float(seg[1]))
		var c: Vector2 = Vector2(float(seg[2]), float(seg[3]))
		_bank_wall(_tile_st(tiles, (a + c) * 0.5), faces, a, c, int(seg[4]))
	for r: Variant in data.get("rails", []):
		var seg: Array = r
		var a: Vector2 = Vector2(float(seg[0]), float(seg[1]))
		var c: Vector2 = Vector2(float(seg[2]), float(seg[3]))
		_bridge_rail(_tile_st(tiles, (a + c) * 0.5), faces, a, c)
	for ring: Variant in data.get("steps", []):
		var rr: Array = ring
		_ghat(_tile_st(tiles, Vector2(float(rr[0]), float(rr[1]))), rr)
	var walls_mat: StandardMaterial3D = StandardMaterial3D.new()
	walls_mat.vertex_color_use_as_albedo = true
	walls_mat.vertex_color_is_srgb = true
	walls_mat.roughness = 0.92
	var holder: Node3D = Node3D.new()
	holder.name = "WaterBanks"
	add_child(holder)
	for key: Vector2i in tiles:
		var walls: MeshInstance3D = MeshInstance3D.new()
		walls.name = "Banks_%d_%d" % [key.x, key.y]
		walls.mesh = MeshKit.finish(tiles[key] as SurfaceTool, walls_mat)
		walls.visibility_range_end = BANK_VISIBLE_M
		holder.add_child(walls)
	if not faces.is_empty():
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "WaterBarriers"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
	return true

func _tile_st(tiles: Dictionary, p: Vector2) -> SurfaceTool:
	var key: Vector2i = Vector2i(floori(p.x / BANK_TILE_M), floori(p.y / BANK_TILE_M))
	if not tiles.has(key):
		tiles[key] = MeshKit.begin()
	return tiles[key] as SurfaceTool

## A wall along a-b: whitewashed canal parapet with posts, or a red/white striped tank wall.
func _bank_wall(st: SurfaceTool, faces: PackedVector3Array, a: Vector2, b: Vector2, kind: int) -> void:
	var e: Vector2 = b - a
	var length: float = e.length()
	if length < 0.05:
		return
	var yaw: float = -atan2(e.y, e.x)
	var basis: Basis = Basis(Vector3.UP, yaw)
	var dir: Vector3 = Vector3(e.x, 0.0, e.y) / length
	var base: float = WorldChunkStreamer.GROUND_VISUAL_Y
	if kind == 1:
		# Temple tank: vertical kavi (red and white) stripes, a stone coping on top.
		# One white wall box, then the red stripes as thin face quads on both sides of it.
		MeshKit.box(st, Vector3((a.x + b.x) * 0.5, base + TANK_WALL_H * 0.5, (a.y + b.y) * 0.5), Vector3(length, TANK_WALL_H, BANK_T), TANK_WHITE, basis)
		var side: Vector3 = Vector3(-dir.z, 0.0, dir.x) * (BANK_T * 0.5 + 0.01)
		var n: int = maxi(1, int(roundf(length / STRIPE_M)))
		for k: int in range(0, n, 2):
			var p0: Vector3 = Vector3(a.x, 0.0, a.y) + dir * length * float(k) / float(n)
			var p1: Vector3 = Vector3(a.x, 0.0, a.y) + dir * length * float(k + 1) / float(n)
			for sgn: float in [-1.0, 1.0]:
				var o: Vector3 = side * sgn
				_quad_facing(st, p0 + o + Vector3(0, base, 0), p1 + o + Vector3(0, base, 0), p1 + o + Vector3(0, base + TANK_WALL_H, 0), p0 + o + Vector3(0, base + TANK_WALL_H, 0), o, TANK_RED)
		MeshKit.box(st, Vector3((a.x + b.x) * 0.5, base + TANK_WALL_H + 0.05, (a.y + b.y) * 0.5), Vector3(length + 0.1, 0.1, BANK_T + 0.12), GHAT_STONE, basis)
	else:
		MeshKit.box(st, Vector3((a.x + b.x) * 0.5, base + BANK_H * 0.5, (a.y + b.y) * 0.5), Vector3(length, BANK_H, BANK_T), CANAL_WHITE, basis)
		MeshKit.box(st, Vector3((a.x + b.x) * 0.5, base + BANK_H + 0.04, (a.y + b.y) * 0.5), Vector3(length + 0.06, 0.08, BANK_T + 0.08), CANAL_CAP, basis)
		var posts: int = int(length / POST_EVERY_M)
		for k: int in range(1, posts + 1):
			var c: Vector3 = Vector3(a.x, 0.0, a.y) + dir * float(k) * POST_EVERY_M
			MeshKit.box(st, c + Vector3(0, base + (BANK_H + 0.18) * 0.5, 0), Vector3(0.4, BANK_H + 0.18, BANK_T + 0.14), CANAL_WHITE.darkened(0.08), basis)
	_wall_faces(faces, a, b, base, (TANK_WALL_H if kind == 1 else BANK_H) + 0.1, BANK_T)

## Bridge parapet along a road over water, yellow/black hazard blocks at both ends.
func _bridge_rail(st: SurfaceTool, faces: PackedVector3Array, a: Vector2, b: Vector2) -> void:
	var e: Vector2 = b - a
	var length: float = e.length()
	if length < 0.05:
		return
	var basis: Basis = Basis(Vector3.UP, -atan2(e.y, e.x))
	var dir: Vector3 = Vector3(e.x, 0.0, e.y) / length
	var y0: float = ROAD_Y
	MeshKit.box(st, Vector3((a.x + b.x) * 0.5, y0 + RAIL_H * 0.5, (a.y + b.y) * 0.5), Vector3(length, RAIL_H, 0.28), CANAL_WHITE, basis)
	MeshKit.box(st, Vector3((a.x + b.x) * 0.5, y0 + RAIL_H + 0.04, (a.y + b.y) * 0.5), Vector3(length + 0.06, 0.08, 0.36), CANAL_CAP, basis)
	for end: Vector3 in [Vector3(a.x, 0.0, a.y) + dir * 0.35, Vector3(b.x, 0.0, b.y) - dir * 0.35]:
		for k: int in 4:
			MeshKit.box(st, end + Vector3(0, y0 + 0.15 + 0.3 * float(k), 0), Vector3(0.7, 0.3, 0.34), HAZARD_YELLOW if k % 2 == 0 else HAZARD_BLACK, basis)
	_wall_faces(faces, a, b, y0, RAIL_H + 0.1, 0.28)

## Temple-tank ghat: GHAT_STEPS steps climbing from the water line to the striped parapet, like
## the Kapaleeshwarar tank's granite ghats. `ring` is the tank outline inset GHAT_WIDTH_M (mitred,
## build_water.py), so step j spans the ring offset outward by j/GHAT_STEPS .. (j+1)/GHAT_STEPS of
## that width, with mitred corners: the top step ends exactly under the bank wall on every side.
## (Nov 4 device test: steps were pushed out radially from the tank centre, which reaches the
## wall only where an edge faces the centre - Chitrakulam's west side kept a ~1 m strip of open
## water between the steps and the wall, and walkers strolled along it.)
func _ghat(st: SurfaceTool, ring: Array) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(0, ring.size(), 2):
		pts.append(Vector2(float(ring[i]), float(ring[i + 1])))
	if pts.size() < 3:
		return
	var rise: float = (GHAT_TOP_Y - (WATER_Y + 0.1)) / float(GHAT_STEPS - 1)
	var in_sgn: float = 1.0 if _ring_ccw(pts) else -1.0
	var outlines: Array[PackedVector2Array] = []
	for j: int in GHAT_STEPS + 1:
		# The last outline tucks under the wall (half its thickness) so no seam shows.
		var r: float = GHAT_WIDTH_M * float(j) / float(GHAT_STEPS) + (BANK_T * 0.5 if j == GHAT_STEPS else 0.0)
		outlines.append(offset_ring(pts, r))
	for j: int in GHAT_STEPS:
		var inner: PackedVector2Array = outlines[j]
		var outer: PackedVector2Array = outlines[j + 1]
		var top: float = WATER_Y + 0.1 + rise * float(j)
		var below: float = WATER_Y - 0.1 if j == 0 else top - rise
		var tread: Color = GHAT_STONE.darkened(0.07 * float(j % 2))
		for i: int in pts.size():
			var a0: Vector2 = inner[i - 1]
			var b0: Vector2 = inner[i]
			var a1: Vector2 = outer[i - 1]
			var b1: Vector2 = outer[i]
			_quad_facing(st, Vector3(a0.x, top, a0.y), Vector3(b0.x, top, b0.y), Vector3(b1.x, top, b1.y), Vector3(a1.x, top, a1.y), Vector3.UP, tread)
			# Riser facing the water (inward = against the outward edge normal).
			var e: Vector2 = b0 - a0
			var inward: Vector2 = Vector2(-e.y, e.x) * in_sgn
			_quad_facing(st, Vector3(a0.x, below, a0.y), Vector3(b0.x, below, b0.y), Vector3(b0.x, top, b0.y), Vector3(a0.x, top, a0.y), Vector3(inward.x, 0.0, inward.y), tread.darkened(0.25))
	# The whole tank (water + steps, out to the wall) is off limits to walkers.
	_add_tank_block(outlines[GHAT_STEPS])

## True when the (x, z) ring winds counter-clockwise in the x-right, z-up plane (positive area).
static func _ring_ccw(pts: PackedVector2Array) -> bool:
	var area: float = 0.0
	for i: int in pts.size():
		area += pts[i - 1].cross(pts[i])
	return area > 0.0

## `pts` grown outward by `d` metres with mitred corners (the inverse of shapely's
## buffer(-d, join_style=mitre) that made the ghat ring). Mitres are capped at 4 d on spikes.
static func offset_ring(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = pts.size()
	out.resize(n)
	var sgn: float = 1.0 if _ring_ccw(pts) else -1.0
	for i: int in n:
		var e0: Vector2 = (pts[i] - pts[i - 1]).normalized()
		var e1: Vector2 = (pts[(i + 1) % n] - pts[i]).normalized()
		var n0: Vector2 = Vector2(e0.y, -e0.x) * sgn
		var n1: Vector2 = Vector2(e1.y, -e1.x) * sgn
		var m: Vector2 = n0 + n1
		if m.length_squared() < 1e-8:
			out[i] = pts[i] + n0 * d
			continue
		m = m.normalized()
		out[i] = pts[i] + m * minf(d / maxf(m.dot(n0), 1e-3), 4.0 * d)
	return out

## Tank footprint triangles bucketed by chunk for the walk mask (filled by _build_water before
## streaming starts; worker threads only read it).
func _add_tank_block(poly: PackedVector2Array) -> void:
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var lo: Vector2 = poly[0]
	var hi: Vector2 = poly[0]
	for q: Vector2 in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	var tris: PackedVector2Array = PackedVector2Array()
	for t: int in idx:
		tris.append(poly[t])
	for cx: int in range(floori(lo.x / chunk_size), floori(hi.x / chunk_size) + 1):
		for cz: int in range(floori(lo.y / chunk_size), floori(hi.y / chunk_size) + 1):
			var k: Vector2i = Vector2i(cx, cz)
			var arr: PackedVector2Array = _tank_blocks.get(k, PackedVector2Array())
			arr.append_array(tris)
			_tank_blocks[k] = arr

## MeshKit.quad with its winding chosen so the face normal points along `facing` (tank rings
## come in either orientation from OSM).
func _quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, colour: Color) -> void:
	# MeshKit.quad's outside is where a-b-c looks counter-clockwise: normal = (b - a) x (c - a).
	if (b - a).cross(c - a).dot(facing) >= 0.0:
		MeshKit.quad(st, a, b, c, d, colour)
	else:
		MeshKit.quad(st, a, d, c, b, colour)

## Collision for a wall a-b (an oriented box as 12 triangles).
func _wall_faces(faces: PackedVector3Array, a: Vector2, b: Vector2, y0: float, h: float, t: float) -> void:
	var e: Vector2 = (b - a).normalized()
	var n: Vector2 = Vector2(-e.y, e.x) * t * 0.5
	var c: Array[Vector3] = []
	for p: Vector2 in [a - n, b - n, b + n, a + n]:
		c.append(Vector3(p.x, y0, p.y))
	for p: Vector2 in [a - n, b - n, b + n, a + n]:
		c.append(Vector3(p.x, y0 + h, p.y))
	for q: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]:
		faces.append_array(PackedVector3Array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]]))

func _build_water_barriers(polys: Array, water_y: float) -> void:
	var holder: StaticBody3D = StaticBody3D.new()
	holder.name = "WaterBarriers"
	holder.collision_layer = 1
	holder.collision_mask = 0
	add_child(holder)
	var edge_count: int = 0
	for poly: Array in polys:
		edge_count += poly.size()
	var curb_mesh: BoxMesh = BoxMesh.new()
	curb_mesh.size = Vector3(1.0, 0.7, 0.65)
	var curb_mat: StandardMaterial3D = StandardMaterial3D.new()
	curb_mat.albedo_color = Color(0.63, 0.62, 0.55)
	curb_mat.roughness = 0.95
	curb_mesh.material = curb_mat
	var curb_multi: MultiMesh = MultiMesh.new()
	curb_multi.transform_format = MultiMesh.TRANSFORM_3D
	curb_multi.mesh = curb_mesh
	curb_multi.instance_count = edge_count
	var curb_draw: MultiMeshInstance3D = MultiMeshInstance3D.new()
	curb_draw.name = "ConcreteEdges"
	curb_draw.multimesh = curb_multi
	curb_draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(curb_draw)
	var instance_index: int = 0
	var xforms: Array[Transform3D] = []
	for poly: Array in polys:
		for i: int in poly.size():
			var a: Vector2 = Vector2(float(poly[i][0]), float(poly[i][1]))
			var b: Vector2 = Vector2(float(poly[(i + 1) % poly.size()][0]), float(poly[(i + 1) % poly.size()][1]))
			var edge: Vector2 = b - a
			if edge.length() < 0.05:
				continue
			var pos: Vector3 = Vector3((a.x + b.x) * 0.5, water_y + 0.35, (a.y + b.y) * 0.5)
			var yaw: float = -atan2(edge.y, edge.x)
			var shape: CollisionShape3D = CollisionShape3D.new()
			var box: BoxShape3D = BoxShape3D.new()
			box.size = Vector3(edge.length(), 0.7, 0.65)
			shape.shape = box
			shape.position = pos
			shape.rotation.y = yaw
			holder.add_child(shape)
			xforms.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.IDENTITY.scaled(Vector3(edge.length(), 1.0, 1.0)), pos))
			instance_index += 1
	# Set the count BEFORE writing transforms: changing instance_count clears the buffer, which
	# left these kerbs invisible while their collision stayed (an invisible wall).
	curb_multi.instance_count = instance_index
	for i: int in xforms.size():
		curb_multi.set_instance_transform(i, xforms[i])

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
				var lighthouse_scene: PackedScene = load(MARINA_LIGHTHOUSE_SCENE) as PackedScene
				if lighthouse_scene != null:
					var lighthouse: Node3D = lighthouse_scene.instantiate() as Node3D
					lighthouse.scale = Vector3.ONE * 48.0
					node.add_child(lighthouse)
					_base_collider(node, holder, Vector3(14.0, 48.0, 14.0))
				else:
					_kit_part(node, holder, LandmarkKit.lighthouse(), Vector3(14.0, 9.0, 14.0))
			"gopuram":
				_kit_part(node, holder, LandmarkKit.gopuram(), Vector3(25.5, 11.0, 15.5))
			"tower":
				_kit_part(node, holder, LandmarkKit.lic_building(), Vector3(18, 54, 18))
			"bridge":
				var bridge_mesh: MeshInstance3D = MeshInstance3D.new()
				bridge_mesh.mesh = LandmarkKit.napier_bridge()
				bridge_mesh.visibility_range_end = LANDMARK_VISIBLE_M
				node.add_child(bridge_mesh)
			"flyover":
				_part(node, holder, _box(Vector3(20, 1.2, 70)), Vector3(0, 7.5, 0), Color(0.6, 0.6, 0.6), false)
				_part(node, holder, _box(Vector3(2, 7, 2)), Vector3(12, 3.5, 0), Color(0.55, 0.55, 0.55), true)
				_part(node, holder, _box(Vector3(2, 7, 2)), Vector3(-12, 3.5, 0), Color(0.55, 0.55, 0.55), true)
			"heritage":
				_kit_part(node, holder, LandmarkKit.vivekananda_house(), Vector3(30, 9, 18))
			"tank", "park":
				pass # drawn by the water / park areas
			_:
				_part(node, holder, _box(Vector3(10, 10, 10)), Vector3(0, 5, 0), Color.MAGENTA, true)
		# Bridges and flyovers keep their authored deck height; buildings stand on the ground.
		if not str(l["kind"]) in ["bridge", "flyover", "tank", "park"]:
			request_ground_snap(node)

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
## TWAD water towers, canal-side settlements, and other local city details.
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
		var path: String = str(p.get("asset", CITY_MODEL_DIR + model + ".glb"))
		var cache_key: String = path
		if not cache.has(cache_key):
			cache[cache_key] = load(path) if ResourceLoader.exists(path) else null
		var scene: PackedScene = cache[cache_key] as PackedScene
		if scene == null:
			if bool(p.get("biryani_cluster", false)):
				_add_tea_stall_fallback(holder, p, index)
				_add_biryani_customers(holder, p, index)
				continue
			if bool(p.get("tea_cluster", false)):
				_add_tea_stall_fallback(holder, p, index)
				_add_tea_crowd(holder, p, index)
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
		# Stand it on the drawn ground (several GLBs are centred on their origin: the palm spans
		# -0.5..0.5, the biryani shop starts at -0.18; sidewalks are 0.08, bare ground -0.15).
		TrafficModelFit.stand_on_world(inst, SIDEWALK_Y)
		request_ground_snap(inst)
		var size: Vector3 = CITY_FOOTPRINT.get(model, Vector3.ZERO)
		if size != Vector3.ZERO:
			var node: Node3D = Node3D.new()
			# Model authoring scale is not a real-world collider scale.
			node.transform = Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0))), Vector3(float(p["x"]), 0.0, float(p["z"])))
			_base_collider(node, holder, size)
			node.free()
		var view_m: float = float(SHOP_VISIBLE_M.get(model, LANDMARK_VISIBLE_M))
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = view_m
		if SHOP_VISIBLE_M.has(model):
			_set_cast_shadow(inst, false)
			_block_footprint(p)
		if bool(p.get("landmark", false)):
			_set_cast_shadow(inst, false)
		if bool(p.get("parked_two_wheeler", false)):
			_add_parked_rider(inst, index, p)
		if bool(p.get("tea_cluster", false)):
			_set_cast_shadow(inst, false)
			_add_tea_crowd(holder, p, index)
		if bool(p.get("biryani_cluster", false)):
			_set_cast_shadow(inst, false)
			_add_biryani_customers(holder, p, index)

## Records a shop's footprint (rotated rectangle, "block" = half sizes) for the chunk's walk mask.
func _block_footprint(p: Dictionary) -> void:
	var half: Array = p.get("block", [])
	if half.size() < 2:
		return
	var yaw: float = float(p.get("yaw", 0.0))
	var c: Vector2 = Vector2(float(p["x"]), float(p["z"]))
	var ax: Vector2 = Vector2(cos(yaw), -sin(yaw)) * float(half[0]) # local +X on the ground
	var az: Vector2 = Vector2(sin(yaw), cos(yaw)) * float(half[1])  # local +Z on the ground
	var poly: PackedVector2Array = PackedVector2Array([c - ax - az, c + ax - az, c + ax + az, c - ax + az])
	var keys: Dictionary = {}
	for q: Vector2 in poly:
		keys[Vector2i(floori(q.x / chunk_size), floori(q.y / chunk_size))] = true
	for k: Vector2i in keys:
		if not _prop_blocks.has(k):
			_prop_blocks[k] = []
		(_prop_blocks[k] as Array).append(poly)

## A compact, low-draw-call fallback while the uploaded Tripo tea model is optimized.
## All parts share one mesh and material; no physics interactions are needed for patrons.
func _add_tea_stall_fallback(holder: StaticBody3D, p: Dictionary, index: int) -> void:
	var place: Node3D = Node3D.new()
	place.name = "TeaKadai_%d" % index
	place.transform = Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0))), Vector3(float(p["x"]), 0.0, float(p["z"])))
	holder.add_child(place)
	var surf: SurfaceTool = MeshKit.begin()
	MeshKit.box(surf, Vector3(0.0, 1.1, 0.0), Vector3(2.4, 1.0, 1.7), Color(0.28, 0.44, 0.3))
	MeshKit.box(surf, Vector3(0.0, 2.5, 0.0), Vector3(3.1, 0.22, 2.4), Color(0.75, 0.2, 0.13))
	MeshKit.box(surf, Vector3(0.0, 1.2, -1.1), Vector3(2.6, 0.75, 0.5), Color(0.67, 0.42, 0.2))
	var kiosk: MeshInstance3D = MeshInstance3D.new()
	kiosk.mesh = MeshKit.finish(surf, PersonMesh.material())
	kiosk.visibility_range_end = 115.0
	kiosk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	place.add_child(kiosk)

## Tea kadais are social hubs: three regulars and parked scooters in the kerbside bay.
## They are static, bounded and never spawn on the lane centreline.
func _add_tea_crowd(holder: StaticBody3D, p: Dictionary, index: int) -> void:
	var yaw: float = float(p.get("yaw", 0.0))
	var basis: Basis = Basis(Vector3.UP, yaw)
	var centre: Vector3 = Vector3(float(p["x"]), 0.0, float(p["z"]))
	var hub: Node3D = Node3D.new()
	hub.name = "TeaCrowd_%d" % index
	hub.transform = Transform3D(basis, centre)
	holder.add_child(hub)
	for i: int in 3:
		var guest: MeshInstance3D = MeshInstance3D.new()
		guest.name = "TeaCustomer_%d" % i
		var style: PersonMesh.Style = (PersonMesh.Style.VESHTI if i == 0 else (PersonMesh.Style.SAREE if i == 1 else PersonMesh.Style.SHIRT_TROUSERS))
		guest.mesh = PersonMesh.standing(style, index + i, false)
		guest.position = Vector3(-2.6 + float(i) * 1.35, 0.08, -2.7)
		guest.rotation.y = PI + 0.25 * float(i)
		guest.visibility_range_end = 88.0
		guest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hub.add_child(guest)
	if not ResourceLoader.exists(PARKED_SCOOTER):
		return
	var bikes: PackedScene = load(PARKED_SCOOTER) as PackedScene
	if bikes == null:
		return
	for i: int in 2:
		var bike: Node3D = bikes.instantiate() as Node3D
		bike.name = "TeaParkedBike_%d" % i
		bike.position = Vector3(-4.6 + float(i) * 2.0, 0.0, -4.0)
		bike.rotation.y = -PI * 0.5 + float(i) * 0.15
		hub.add_child(bike)
		request_ground_snap(bike)
		_set_cast_shadow(bike, false)
		for m: Node in bike.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).visibility_range_end = 88.0

## Owner and cooking props already live in the biryani stall model (shops/biryani_stall_<v>.glb).
## Two shared-mesh visitors and a pair of parked scooters add pavement activity
## without animation or shadow overhead. The generator reserves this whole area.
func _add_biryani_customers(holder: StaticBody3D, p: Dictionary, index: int) -> void:
	var spot: Node3D = Node3D.new()
	spot.name = "BiryaniGathering_%d" % index
	spot.transform = Transform3D(
		Basis(Vector3.UP, float(p.get("yaw", 0.0))),
		Vector3(float(p["x"]), 0.0, float(p["z"])))
	holder.add_child(spot)
	for i: int in 2:
		var person: MeshInstance3D = MeshInstance3D.new()
		person.mesh = PersonMesh.standing(
			PersonMesh.Style.SHIRT_TROUSERS if i == 0 else PersonMesh.Style.VESHTI,
			index + i, false)
		person.position = Vector3(-1.2 + float(i) * 2.4, 0.08, -2.75)
		person.rotation.y = PI
		person.visibility_range_end = 85.0
		person.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spot.add_child(person)
	# Keep parking outside the stall and customer aisle.
	if not ResourceLoader.exists(PARKED_SCOOTER):
		return
	var bike_scene: PackedScene = load(PARKED_SCOOTER) as PackedScene
	if bike_scene == null:
		return
	for i: int in 2:
		var bike: Node3D = bike_scene.instantiate() as Node3D
		bike.name = "BiryaniParkedScooter_%d" % i
		bike.position = Vector3(-1.0 + float(i) * 2.0, 0.0, 2.9)
		bike.rotation.y = PI * 0.5
		spot.add_child(bike)
		request_ground_snap(bike)
		_set_cast_shadow(bike, false)
		for mesh: Node in bike.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).visibility_range_end = 85.0

func _add_parked_rider(vehicle: Node3D, index: int, prop: Dictionary) -> void:
	var rider: Node3D = PersonMesh.rider_node(index)
	rider.name = "ParkedRider_%d" % index
	var off: Array = prop.get("rider_offset", [0.0, 0.72, 0.22])
	rider.position = Vector3(float(off[0]), float(off[1]), float(off[2])) + PersonMesh.PROCEDURAL_HIP
	# The scooter file faces -Z like the rider; the sport-bike files face +Z, so their riders
	# turn round (before Oct 31 they sat backwards, facing the tail).
	if str(prop.get("model", "")) == "parked_sport_bike":
		rider.rotation.y += PI
		rider.position.z -= 2.0 * PersonMesh.PROCEDURAL_HIP.z
	vehicle.add_child(rider)

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


static func heritage_style(b: Dictionary) -> String:
	var flat: Array = b.get("p", [])
	if flat.size() < 6:
		return ""
	var centre: Vector2 = Vector2.ZERO
	for i: int in range(0, flat.size(), 2):
		centre += Vector2(float(flat[i]), float(flat[i + 1]))
	centre /= float(flat.size() / 2)
	for site: Dictionary in HERITAGE_SITES:
		if int(b.get("s", -1)) == int(site["seed"]) and centre.distance_to(site["point"] as Vector2) < 20.0:
			return str(site["style"])
	return ""

## Architectural roof accents are merged into the original footprint mesh. Ground-floor
## geometry, collision and road clearance are inherited from the actual OSM building.
func _heritage_roof(m: MeshBuf, pts: PackedVector2Array, h: float, style: String) -> void:
	var centre: Vector2 = Vector2.ZERO
	for p: Vector2 in pts:
		centre += p
	centre /= float(pts.size())
	var cream: Color = Color(0.84, 0.79, 0.65)
	var red: Color = Color(0.62, 0.30, 0.21)
	for i: int in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var d: Vector2 = b - a
		var mid: Vector2 = (a + b) * 0.5
		_dbox(m, Vector3(mid.x, h + 0.25, mid.y), Vector3(d.length(), 0.5, 0.45), d.normalized(), cream)
	if style == "cathedral":
		# West-facing entrance tower within the original church footprint.
		var west: Vector2 = pts[0]
		for p: Vector2 in pts:
			if p.x < west.x:
				west = p
		var tower: Vector2 = west.lerp(centre, 0.28)
		var base: Vector3 = Vector3(tower.x, h, tower.y)
		_dbox(m, base + Vector3(0, 8, 0), Vector3(4.0, 16.0, 4.0), Vector2.RIGHT, Color(0.87, 0.85, 0.80))
		_trunk(m, base + Vector3(0, 16, 0), base + Vector3(0, 31, 0), 2.9, 0.05, Color(0.80, 0.80, 0.77))
		_dbox(m, base + Vector3(0, 32, 0), Vector3(0.16, 2.2, 0.16), Vector2.RIGHT, cream)
		_dbox(m, base + Vector3(0, 32.4, 0), Vector3(1.2, 0.16, 0.16), Vector2.RIGHT, cream)
	else:
		# Corner pavilions, with faceted domed caps, distinguish the red heritage skyline.
		for i: int in mini(4, pts.size()):
			var p: Vector2 = pts[i].lerp(centre, 0.16)
			var base: Vector3 = Vector3(p.x, h, p.y)
			_trunk(m, base, base + Vector3(0, 5, 0), 1.6, 1.6, red)
			_trunk(m, base + Vector3(0, 5, 0), base + Vector3(0, 6, 0), 1.9, 2.1, cream)
			_trunk(m, base + Vector3(0, 6, 0), base + Vector3(0, 8.5, 0), 2.1, 0.25, cream)
