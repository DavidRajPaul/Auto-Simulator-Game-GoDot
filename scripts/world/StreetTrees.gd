class_name StreetTrees
extends Node3D
## Roadside and park trees from the owner's models (assets/models/city/trees, baked by
## tools/assets/bake_trees.py from assets_src/models/trees). Placements come per chunk from
## data/world/dress "trees" [x, z, code, scale, seed] (tools/osm/build_street_dressing.py).
##
## Two levels of detail, drawn through a fixed set of world-space MultiMeshes refilled around the
## camera (the BusStops pattern; no MultiMesh or node per chunk):
##   near (< NEAR_M): the full textured model, one MultiMesh per species, casts shadows
##   far            : VIEWS crossed impostor cards, ALL species in one MultiMesh, no shadows
## So the whole forest is SPECIES + 1 draw calls (+ SPECIES in the shadow pass), whatever the count.
## Instance transforms are rebuilt only after the camera moves REBUILD_M or a chunk (un)loads.

const DIR: String = "res://assets/models/city/trees/"
const NEAR_M: float = 60.0
const FAR_M: float = 420.0
const REBUILD_M: float = 5.0
## Trunks sink a little so the root flare never floats over a sloped kerb.
const SINK_M: float = 0.06
## Per tree in a chunk record: x, y, z, code, scale, yaw, tint r, g, b.
const REC: int = 9
const NEAR_STRIDE: int = 16 # transform 12 + colour 4
const FAR_STRIDE: int = 20 # transform 12 + colour 4 + custom 4
## Unknown codes in older dress data (retired procedural species 5-7) draw as neem.
const FALLBACK_CODE: int = 0

var species: Dictionary = {} # code -> {"height", "radius", "row"}
var views: int = 4
var near_mmis: Dictionary = {} # code -> MultiMeshInstance3D
var far_mmi: MultiMeshInstance3D
var _chunks: Dictionary = {} # Vector2i -> PackedFloat32Array (REC floats per tree)
var _last: Vector3 = Vector3(INF, INF, INF)
var _dirty: bool = true
## Trees drawn at each level after the last rebuild (tests, debug overlay).
var near_count: int = 0
var far_count: int = 0
## Where the near models stand after the last rebuild (tests; the headless renderer keeps no
## MultiMesh data to read back).
var near_positions: PackedVector3Array = PackedVector3Array()

func _ready() -> void:
	var meta: Dictionary = {}
	var f: FileAccess = FileAccess.open(DIR + "trees.json", FileAccess.READ)
	if f == null:
		push_error("StreetTrees: missing %strees.json, run tools/assets/bake_trees.py" % DIR)
		return
	meta = JSON.parse_string(f.get_as_text()) as Dictionary
	views = int(meta.get("views", 4))
	var rows: int = int(meta.get("rows", 1))
	var sp_all: Dictionary = meta.get("species", {})
	for key: String in sp_all:
		var sp: Dictionary = sp_all[key]
		var code: int = int(key)
		species[code] = sp
		var mesh: Mesh = _load_mesh(DIR + str(sp["name"]) + ".glb")
		if mesh == null:
			continue
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "Near_" + str(sp["name"])
		mmi.multimesh = _new_multimesh(mesh, false)
		mmi.material_override = _near_material(mesh)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		near_mmis[code] = mmi
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/tree_impostor.gdshader") as Shader
	mat.set_shader_parameter("atlas", load(DIR + "tree_impostors.png") as Texture2D)
	mat.set_shader_parameter("rows", float(rows))
	far_mmi = MultiMeshInstance3D.new()
	far_mmi.name = "FarImpostors"
	far_mmi.multimesh = _new_multimesh(_impostor_mesh(views, rows), true)
	far_mmi.material_override = mat
	far_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mmi)
	# The MultiMeshes span the loaded map around the camera; never frustum- or range-cull them
	# as a whole (a MultiMesh at the origin with a visibility range culled every bus shelter).
	var big: AABB = AABB(Vector3(-20000.0, -50.0, -20000.0), Vector3(40000.0, 200.0, 40000.0))
	for mmi: MultiMeshInstance3D in near_mmis.values():
		mmi.custom_aabb = big
	far_mmi.custom_aabb = big

## Chunk loaded: `trees` holds REC floats per tree (y already on the drawn ground).
func add_chunk(k: Vector2i, trees: PackedFloat32Array) -> void:
	if trees.is_empty():
		return
	_chunks[k] = trees
	_dirty = true

func remove_chunk(k: Vector2i) -> void:
	if _chunks.erase(k):
		_dirty = true

func tree_count() -> int:
	var n: int = 0
	for k: Vector2i in _chunks:
		n += (_chunks[k] as PackedFloat32Array).size() / REC
	return n

## Refill the MultiMeshes if the camera moved far enough (call every frame; cheap otherwise).
func update(cam: Vector3) -> void:
	if not _dirty and cam.distance_squared_to(_last) < REBUILD_M * REBUILD_M:
		return
	_dirty = false
	_last = cam
	# Near trees go into one local buffer tagged with their code (packed arrays held in a
	# Dictionary are copies, appending to them does nothing); split per species below.
	var near_all: PackedFloat32Array = PackedFloat32Array()
	var far_buf: PackedFloat32Array = PackedFloat32Array()
	var near2: float = NEAR_M * NEAR_M
	var far2: float = FAR_M * FAR_M
	for k: Vector2i in _chunks:
		var t: PackedFloat32Array = _chunks[k]
		for i: int in range(0, t.size(), REC):
			var dx: float = t[i] - cam.x
			var dz: float = t[i + 2] - cam.z
			var d2: float = dx * dx + dz * dz
			if d2 > far2:
				continue
			var code: int = int(t[i + 3])
			if not species.has(code):
				code = FALLBACK_CODE
			var s: float = t[i + 4]
			var yaw: float = t[i + 5]
			var c: float = cos(yaw)
			var sn: float = sin(yaw)
			if d2 < near2 and near_mmis.has(code):
				# Basis(UP, yaw) * s, written row-major as the MultiMesh buffer expects.
				near_all.append_array(PackedFloat32Array([float(code),
					c * s, 0.0, sn * s, t[i],
					0.0, s, 0.0, t[i + 1],
					-sn * s, 0.0, c * s, t[i + 2],
					t[i + 6], t[i + 7], t[i + 8], 1.0]))
			else:
				var sp: Dictionary = species[code]
				var r: float = float(sp["radius"]) * s
				var h: float = float(sp["height"]) * s
				far_buf.append_array(PackedFloat32Array([
					c * r, 0.0, sn * r, t[i],
					0.0, h, 0.0, t[i + 1],
					-sn * r, 0.0, c * r, t[i + 2],
					t[i + 6], t[i + 7], t[i + 8], 1.0,
					float(sp["row"]), 0.0, 0.0, 0.0]))
	near_count = 0
	near_positions.clear()
	var rec: int = NEAR_STRIDE + 1
	for j: int in range(0, near_all.size(), rec):
		near_positions.append(Vector3(near_all[j + 4], near_all[j + 8], near_all[j + 12]))
	for code: int in near_mmis:
		var buf: PackedFloat32Array = PackedFloat32Array()
		for j: int in range(0, near_all.size(), rec):
			if int(near_all[j]) == code:
				buf.append_array(near_all.slice(j + 1, j + rec))
		near_count += _upload((near_mmis[code] as MultiMeshInstance3D).multimesh, buf, NEAR_STRIDE)
	far_count = _upload(far_mmi.multimesh, far_buf, FAR_STRIDE)

## Writes `buf` into `mm`, growing its capacity when needed. Returns the instance count.
func _upload(mm: MultiMesh, buf: PackedFloat32Array, stride: int) -> int:
	var n: int = buf.size() / stride
	if n > mm.instance_count:
		# Changing the count clears the buffer; the full buffer is written right after.
		mm.instance_count = maxi(64, int(float(n) * 1.3))
	buf.resize(mm.instance_count * stride)
	mm.buffer = buf
	mm.visible_instance_count = n
	return n

func _new_multimesh(mesh: Mesh, custom: bool) -> MultiMesh:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = 0
	return mm

func _load_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		push_error("StreetTrees: missing " + path)
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var mesh: Mesh = null
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		mesh = (node as MeshInstance3D).mesh
		break
	root.free()
	return mesh

## The baked texture, matte, both leaf faces, instance colour as a tint.
func _near_material(mesh: Mesh) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var src: BaseMaterial3D = mesh.surface_get_material(0) as BaseMaterial3D
	if src != null:
		mat.albedo_texture = src.albedo_texture
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.0
	mat.metallic_specular = 0.2
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

## `count` vertical cards through the trunk axis, 180/count degrees apart, x in [-1, 1] and
## y in [0, 1] (the instance basis scales them to crown radius x height). Card k samples atlas
## column k of row 0; the shader offsets the row per species.
static func _impostor_mesh(count: int, rows: int) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var cw: float = 1.0 / float(count)
	var ch: float = 1.0 / float(rows)
	for k: int in count:
		var ang: float = PI * float(k) / float(count)
		var a: Vector3 = Vector3(cos(ang), 0.0, sin(ang))
		var base: int = verts.size()
		verts.append_array(PackedVector3Array([-a, a, a + Vector3.UP, -a + Vector3.UP]))
		uvs.append_array(PackedVector2Array([Vector2(cw * float(k), ch), Vector2(cw * float(k + 1), ch),
			Vector2(cw * float(k + 1), 0.0), Vector2(cw * float(k), 0.0)]))
		for _i: int in 4:
			norms.append(Vector3.UP)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Chunk record from dress "trees" (worker thread safe: pure maths). y is filled on attach.
static func records(dress_trees: Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for t: Array in dress_trees:
		var seed_i: int = int(t[4]) if t.size() > 4 else 0
		var yaw: float = float(seed_i % 360) * 0.0174533
		# Per-tree tint: brightness 0.86-1.06, a slight warm/cool lean, from the seed.
		var b: float = 0.86 + 0.2 * fposmod(float(seed_i) * 0.618, 1.0)
		var warm: float = 0.04 * (fposmod(float(seed_i) * 0.371, 1.0) - 0.5)
		out.append_array(PackedFloat32Array([float(t[0]), 0.0, float(t[1]), float(int(t[2])),
			float(t[3]) if t.size() > 3 else 1.0, yaw, b * (1.0 + warm), b, b * (1.0 - warm)]))
	return out
