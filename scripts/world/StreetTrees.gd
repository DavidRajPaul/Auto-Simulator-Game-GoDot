class_name StreetTrees
extends Node3D
## Roadside and park trees from the owner's models (assets/models/city/trees, baked by
## tools/assets/bake_trees.py from assets_src/models/trees). Placements come per chunk from
## data/world/dress "trees" [x, z, code, scale, seed] (tools/osm/build_street_dressing.py).
##
## Two levels of detail, drawn through a fixed set of world-space MultiMeshes refilled around the
## camera (the BusStops pattern; no MultiMesh or node per chunk):
##   near: the full textured model, one MultiMesh per species, casts shadows (tree_near.gdshader)
##   far : one camera-facing card per tree from the VIEWS baked views, ALL species in one MultiMesh,
##         no shadows (tree_impostor)
## So the whole forest is SPECIES + 1 draw calls (+ SPECIES in the shadow pass), whatever the count.
## Between NEAR_M - FADE_M and NEAR_M + FADE_M a tree is in BOTH sets and the two shaders dither
## complementary pixels, so it cross-fades instead of popping (Nov 3 device test).
## Near models refill after the camera moves REBUILD_M (only chunks within reach are scanned), the
## far cards after FAR_REBUILD_M, both when a chunk (un)loads; per-tree numbers are precomputed when
## the chunk arrives and nothing is allocated per tree.

const DIR: String = "res://assets/models/city/trees/"
const NEAR_M: float = 56.0
const FADE_M: float = 4.0
const FAR_M: float = 420.0
const REBUILD_M: float = 5.0
## The far cards change slowly, so they refill less often; their set reaches this much further in
## (a card inside the fade band's near edge is fully dithered away, so the overlap costs little).
const FAR_REBUILD_M: float = 20.0
## Trunks sink a little so the root flare never floats over a sloped kerb.
const SINK_M: float = 0.06
## Per tree in a chunk record from records(): x, y, z, code, scale, yaw, tint r, g, b.
const REC: int = 9
## Per tree once prepared by add_chunk(): x, y, z, near slot, s*cos, s*sin, s, r*cos, r*sin,
## height, tint r, g, b, atlas row.
const PRE: int = 14
const NEAR_STRIDE: int = 16 # transform 12 + colour 4
const FAR_STRIDE: int = 20 # transform 12 + colour 4 + custom 4
## Unknown codes in older dress data (retired procedural species 5-7) draw as neem.
const FALLBACK_CODE: int = 0

var species: Dictionary = {} # code -> {"height", "radius", "row"}
var views: int = 4
var near_mmis: Dictionary = {} # code -> MultiMeshInstance3D
var far_mmi: MultiMeshInstance3D
var _slot_mmis: Array[MultiMeshInstance3D] = [] # near MultiMesh per slot
var _slot_of: Dictionary = {} # species code -> slot
var _materials: Array[ShaderMaterial] = []
var _chunks: Dictionary = {} # Vector2i -> PackedFloat32Array (PRE floats per tree)
var _bounds: Dictionary = {} # Vector2i -> Rect2 around the chunk's trees
var _last: Vector3 = Vector3(INF, INF, INF)
var _last_far: Vector3 = Vector3(INF, INF, INF)
var _eye: Vector3 = Vector3(INF, INF, INF)
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
	var near_shader: Shader = load("res://shaders/tree_near.gdshader") as Shader
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
		mmi.material_override = _near_material(mesh, near_shader)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		near_mmis[code] = mmi
		_slot_of[code] = _slot_mmis.size()
		_slot_mmis.append(mmi)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/tree_impostor.gdshader") as Shader
	mat.set_shader_parameter("atlas", load(DIR + "tree_impostors.png") as Texture2D)
	mat.set_shader_parameter("rows", float(rows))
	mat.set_shader_parameter("views", float(views))
	_materials.append(mat)
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("fade_start", NEAR_M - FADE_M)
		m.set_shader_parameter("fade_end", NEAR_M + FADE_M)
	far_mmi = MultiMeshInstance3D.new()
	far_mmi.name = "FarImpostors"
	far_mmi.multimesh = _new_multimesh(_impostor_mesh(), true)
	far_mmi.material_override = mat
	far_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mmi)
	# The MultiMeshes span the loaded map around the camera; never frustum- or range-cull them
	# as a whole (a MultiMesh at the origin with a visibility range culled every bus shelter).
	var big: AABB = AABB(Vector3(-20000.0, -50.0, -20000.0), Vector3(40000.0, 200.0, 40000.0))
	for mmi: MultiMeshInstance3D in _slot_mmis:
		mmi.custom_aabb = big
	far_mmi.custom_aabb = big

## Chunk loaded: `trees` holds REC floats per tree from records() (y already on the drawn ground).
## Everything the rebuild needs per tree is worked out here, once.
func add_chunk(k: Vector2i, trees: PackedFloat32Array) -> void:
	if trees.is_empty() or species.is_empty():
		return
	var n: int = trees.size() / REC
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n * PRE)
	var rect: Rect2 = Rect2(trees[0], trees[2], 0.0, 0.0)
	for j: int in n:
		var i: int = j * REC
		var o: int = j * PRE
		var code: int = int(trees[i + 3])
		if not species.has(code):
			code = FALLBACK_CODE
		var sp: Dictionary = species[code]
		var s: float = trees[i + 4]
		var c: float = cos(trees[i + 5])
		var sn: float = sin(trees[i + 5])
		var r: float = float(sp["radius"]) * s
		out[o] = trees[i]
		out[o + 1] = trees[i + 1]
		out[o + 2] = trees[i + 2]
		out[o + 3] = float(_slot_of.get(code, -1))
		out[o + 4] = c * s
		out[o + 5] = sn * s
		out[o + 6] = s
		out[o + 7] = c * r
		out[o + 8] = sn * r
		out[o + 9] = float(sp["height"]) * s
		out[o + 10] = trees[i + 6]
		out[o + 11] = trees[i + 7]
		out[o + 12] = trees[i + 8]
		out[o + 13] = float(sp["row"])
		rect = rect.expand(Vector2(trees[i], trees[i + 2]))
	_chunks[k] = out
	_bounds[k] = rect
	_dirty = true

func remove_chunk(k: Vector2i) -> void:
	_bounds.erase(k)
	if _chunks.erase(k):
		_dirty = true

func tree_count() -> int:
	var n: int = 0
	for k: Vector2i in _chunks:
		n += (_chunks[k] as PackedFloat32Array).size() / PRE
	return n

## Call every frame with the camera position: feeds the fade to the shaders and refills the near
## models after REBUILD_M of movement and the far cards after FAR_REBUILD_M (cheap otherwise).
func update(cam: Vector3) -> void:
	if cam.distance_squared_to(_eye) > 0.0025:
		_eye = cam
		for m: ShaderMaterial in _materials:
			m.set_shader_parameter("eye_pos", cam)
	var all: bool = _dirty
	_dirty = false
	if all or cam.distance_squared_to(_last) >= REBUILD_M * REBUILD_M:
		_last = cam
		_rebuild_near(cam)
	if all or cam.distance_squared_to(_last_far) >= FAR_REBUILD_M * FAR_REBUILD_M:
		_last_far = cam
		_rebuild_far(cam)

## Near set: out to the far edge of the fade band plus REBUILD_M (the camera moves between
## refills; the shader hides whatever is past the band this frame). Only nearby chunks are read.
func _rebuild_near(cam: Vector3) -> void:
	var lim: float = NEAR_M + FADE_M + REBUILD_M
	var lim2: float = lim * lim
	var cam2: Vector2 = Vector2(cam.x, cam.z)
	var slots: int = _slot_mmis.size()
	var keys: Array[Vector2i] = []
	for k: Vector2i in _chunks:
		var r: Rect2 = _bounds[k]
		var closest: Vector2 = cam2.clamp(r.position, r.end)
		if closest.distance_squared_to(cam2) < lim2:
			keys.append(k)
	# Pass 1: count per species slot; pass 2: write slot-contiguous into one buffer.
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(slots)
	counts.fill(0)
	for k: Vector2i in keys:
		var t: PackedFloat32Array = _chunks[k]
		for i: int in range(0, t.size(), PRE):
			var dx: float = t[i] - cam.x
			var dz: float = t[i + 2] - cam.z
			var slot: int = int(t[i + 3])
			if dx * dx + dz * dz < lim2 and slot >= 0:
				counts[slot] += 1
	var offsets: PackedInt32Array = PackedInt32Array()
	offsets.resize(slots + 1)
	offsets[0] = 0
	for sl: int in slots:
		offsets[sl + 1] = offsets[sl] + counts[sl]
	var cursor: PackedInt32Array = offsets.slice(0, slots)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(offsets[slots] * NEAR_STRIDE)
	near_positions.resize(offsets[slots])
	for k: Vector2i in keys:
		var t: PackedFloat32Array = _chunks[k]
		for i: int in range(0, t.size(), PRE):
			var dx: float = t[i] - cam.x
			var dz: float = t[i + 2] - cam.z
			var slot: int = int(t[i + 3])
			if dx * dx + dz * dz >= lim2 or slot < 0:
				continue
			var idx: int = cursor[slot]
			cursor[slot] = idx + 1
			near_positions[idx] = Vector3(t[i], t[i + 1], t[i + 2])
			# Basis(UP, yaw) * s, row-major as the MultiMesh buffer expects.
			var o: int = idx * NEAR_STRIDE
			buf[o] = t[i + 4]
			buf[o + 1] = 0.0
			buf[o + 2] = t[i + 5]
			buf[o + 3] = t[i]
			buf[o + 4] = 0.0
			buf[o + 5] = t[i + 6]
			buf[o + 6] = 0.0
			buf[o + 7] = t[i + 1]
			buf[o + 8] = -t[i + 5]
			buf[o + 9] = 0.0
			buf[o + 10] = t[i + 4]
			buf[o + 11] = t[i + 2]
			buf[o + 12] = t[i + 10]
			buf[o + 13] = t[i + 11]
			buf[o + 14] = t[i + 12]
			buf[o + 15] = 1.0
	near_count = 0
	for sl: int in slots:
		var part: PackedFloat32Array = buf.slice(offsets[sl] * NEAR_STRIDE, offsets[sl + 1] * NEAR_STRIDE)
		near_count += _upload(_slot_mmis[sl].multimesh, part, NEAR_STRIDE)

## Far set: from the near edge of the fade band minus FAR_REBUILD_M out to FAR_M.
func _rebuild_far(cam: Vector3) -> void:
	var inner: float = maxf(0.0, NEAR_M - FADE_M - FAR_REBUILD_M)
	var in2: float = inner * inner
	var out2: float = FAR_M * FAR_M
	var n: int = 0
	for k: Vector2i in _chunks:
		var t: PackedFloat32Array = _chunks[k]
		for i: int in range(0, t.size(), PRE):
			var dx: float = t[i] - cam.x
			var dz: float = t[i + 2] - cam.z
			var d2: float = dx * dx + dz * dz
			if d2 <= out2 and (d2 > in2 or t[i + 3] < 0.0):
				n += 1
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n * FAR_STRIDE)
	var p: int = 0
	for k: Vector2i in _chunks:
		var t: PackedFloat32Array = _chunks[k]
		for i: int in range(0, t.size(), PRE):
			var dx: float = t[i] - cam.x
			var dz: float = t[i + 2] - cam.z
			var d2: float = dx * dx + dz * dz
			if d2 > out2 or (d2 <= in2 and t[i + 3] >= 0.0):
				continue
			buf[p] = t[i + 7]
			buf[p + 1] = 0.0
			buf[p + 2] = t[i + 8]
			buf[p + 3] = t[i]
			buf[p + 4] = 0.0
			buf[p + 5] = t[i + 9]
			buf[p + 6] = 0.0
			buf[p + 7] = t[i + 1]
			buf[p + 8] = -t[i + 8]
			buf[p + 9] = 0.0
			buf[p + 10] = t[i + 7]
			buf[p + 11] = t[i + 2]
			buf[p + 12] = t[i + 10]
			buf[p + 13] = t[i + 11]
			buf[p + 14] = t[i + 12]
			buf[p + 15] = 1.0
			buf[p + 16] = t[i + 13]
			buf[p + 17] = 0.0
			buf[p + 18] = 0.0
			buf[p + 19] = 0.0
			p += FAR_STRIDE
	far_count = _upload(far_mmi.multimesh, buf, FAR_STRIDE)

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

## The baked texture, matte, both leaf faces, instance colour as a tint, distance cross-fade.
func _near_material(mesh: Mesh, shader: Shader) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	var src: BaseMaterial3D = mesh.surface_get_material(0) as BaseMaterial3D
	if src != null:
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	_materials.append(mat)
	return mat

## One upright quad, x in [-1, 1] and y in [0, 1]: tree_impostor.gdshader turns it to face the
## camera, scales it to crown radius x height from the instance basis and picks the atlas views
## (Nov 4: replaces 4 crossed cards - edge-on slabs, 4x overdraw). UVs are worked out in the shader.
static func _impostor_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The card swings round the trunk: give culling the whole crown footprint, not a flat quad.
	mesh.custom_aabb = AABB(Vector3(-1, 0, -1), Vector3(2, 1, 2))
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
