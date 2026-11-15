class_name StreetLights
extends Node3D
## Chennai's street lights at night (Nov 15 owner report: "there does not seem to be street light
## posts … the light from the street lights must be very photo realistic").
##
## The poles are part of each chunk's mesh (WorldChunkStreamer._lamps). The light is two
## MultiMeshes, so the whole city costs 2 draw calls and nothing by day:
##   * POOLS: one ground quad per lamp near the camera, drawn additively by
##     shaders/street_light_pool.gdshader. The pool follows real photometry: illuminance from a
##     point source at height h is I·cos θ / r² = I·h / r³, stretched along the road like a
##     road-lighting (type II) optic, white-balanced per fitting (cool LED on the main roads,
##     neutral on EB-pole brackets), with a wet-road reflection streak towards the camera in rain.
##   * LENSES: one camera-facing card per lamp out to LENS_M: the bright LED lens plus a soft
##     atmospheric halo (bigger in rain and haze), kept at least a few pixels wide so distant rows
##     of lamps read as a line of lights down the road, like the reference photos.
## Real light sources are not used: on the GL Compatibility renderer every light adds a pass per
## lit object, and the city would blow the 150 draw-call budget.

const REC: int = 7 # x, y, z, road dir x, road dir z, kind, ground y
const HEIGHT: PackedFloat32Array = [9.0, 10.0, 6.5] # kerb, median, EB bracket (fitting height)
const INTENSITY: PackedFloat32Array = [1.0, 1.15, 0.6]
## Fitting colour (linear): cool-white LED retrofits on the main roads, warmer brackets.
const TINT: Array[Color] = [Color(0.93, 0.96, 1.0), Color(0.9, 0.95, 1.0), Color(1.0, 0.9, 0.74)]
const POOL_M: float = 170.0
const LENS_M: float = 520.0
const MAX_POOLS: int = 220
const MAX_LENSES: int = 900
const REFILL_M: float = 8.0

var _chunks: Dictionary = {} # Vector2i -> PackedFloat32Array
var _pools: MultiMeshInstance3D
var _lenses: MultiMeshInstance3D
var _pool_mat: ShaderMaterial
var _lens_mat: ShaderMaterial
var _filled_at: Vector3 = Vector3(INF, INF, INF)
var _dirty: bool = true
var on: float = 0.0

## Lamp head records from dress "lamps" ([x, z, yaw, type, reach]): where each fitting's lens is.
static func heads(lamps: Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for l: Array in lamps:
		var base: Vector3 = Vector3(float(l[0]), 0.0, float(l[1]))
		var yaw: float = float(l[2])
		var kind: int = clampi(int(l[3]), 0, 2)
		var reach: float = float(l[4])
		var dir: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
		var h: float = HEIGHT[kind]
		if kind == 2:
			_head(out, base + dir * reach + Vector3(0.0, h - 0.08, 0.0), Vector3(dir.z, 0.0, -dir.x), kind)
		elif kind == 0:
			_head(out, base + dir * (reach + 0.3) + Vector3(0.0, h + 0.02, 0.0), Vector3(dir.z, 0.0, -dir.x), kind)
		else:
			for side: float in [-1.0, 1.0]:
				var a: Vector3 = Vector3(dir.z, 0.0, -dir.x) * side
				_head(out, base + a * (reach + 0.3) + Vector3(0.0, h + 0.02, 0.0), dir, kind)
	return out

static func _head(out: PackedFloat32Array, p: Vector3, road: Vector3, kind: int) -> void:
	out.append_array(PackedFloat32Array([p.x, p.y, p.z, road.x, road.z, float(kind), 0.0]))

## Lamps are on from dusk to dawn (they switch on before the sky is fully dark).
static func lit(minute: float) -> float:
	return 1.0 - smoothstep(-0.04, 0.07, Atmosphere.sun_height(minute))

func _ready() -> void:
	_pool_mat = ShaderMaterial.new()
	_pool_mat.shader = load("res://shaders/street_light_pool.gdshader") as Shader
	_lens_mat = ShaderMaterial.new()
	_lens_mat.shader = load("res://shaders/street_light_lens.gdshader") as Shader
	_pools = _make_multimesh("LightPools", _pool_mat, MAX_POOLS, Vector3(2.0, 0.0, 2.0))
	_lenses = _make_multimesh("LampLenses", _lens_mat, MAX_LENSES, Vector3(1.0, 1.0, 0.0))

func _make_multimesh(nm: String, mat: ShaderMaterial, cap: int, quad: Vector3) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(quad.x, quad.z if quad.z > 0.0 else quad.y)
	if quad.y == 0.0:
		q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Placed by world transforms round the camera: never cull by the node's own box.
	mi.custom_aabb = AABB(Vector3(-1e5, -100.0, -1e5), Vector3(2e5, 400.0, 2e5))
	mi.visible = false
	add_child(mi)
	return mi

func add_chunk(k: Vector2i, recs: PackedFloat32Array) -> void:
	_chunks[k] = recs
	_dirty = true

func remove_chunk(k: Vector2i) -> void:
	if _chunks.erase(k):
		_dirty = true

func lamp_count() -> int:
	var n: int = 0
	for k: Vector2i in _chunks:
		n += (_chunks[k] as PackedFloat32Array).size() / REC
	return n

func _process(_delta: float) -> void:
	on = lit(GameState.shift_minute)
	var cam: Camera3D = get_viewport().get_camera_3d()
	var show: bool = on > 0.001 and cam != null
	_pools.visible = show
	_lenses.visible = show
	if not show:
		return
	var rain: float = 1.0 if GameState.is_raining else 0.0
	for mat: ShaderMaterial in [_pool_mat, _lens_mat]:
		mat.set_shader_parameter("on", on)
		mat.set_shader_parameter("wet", rain)
	var at: Vector3 = cam.global_position
	if _dirty or at.distance_to(_filled_at) > REFILL_M:
		refill(at)

## Fill both MultiMeshes with the lamps round `at` (nearest first). Public for tests.
func refill(at: Vector3) -> void:
	_dirty = false
	_filled_at = at
	var near: Array[Vector2] = [] # (distance², flat index into _all)
	var all: Array[PackedFloat32Array] = []
	for k: Vector2i in _chunks:
		var recs: PackedFloat32Array = _chunks[k]
		var ci: int = all.size()
		all.append(recs)
		for i: int in range(0, recs.size(), REC):
			var d2: float = Vector2(recs[i] - at.x, recs[i + 2] - at.z).length_squared()
			if d2 < LENS_M * LENS_M:
				near.append(Vector2(d2, float(ci * 1000000 + i)))
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var pools: MultiMesh = _pools.multimesh
	var lenses: MultiMesh = _lenses.multimesh
	var np: int = 0
	var nl: int = 0
	for e: Vector2 in near:
		if nl >= MAX_LENSES:
			break
		var code: int = int(e.y)
		var recs: PackedFloat32Array = all[code / 1000000]
		var i: int = code % 1000000
		var p: Vector3 = Vector3(recs[i], recs[i + 1], recs[i + 2])
		var road: Vector3 = Vector3(recs[i + 3], 0.0, recs[i + 4])
		var kind: int = int(recs[i + 5])
		var ground: float = recs[i + 6]
		var h: float = maxf(2.0, p.y - ground)
		var tint: Color = TINT[kind]
		lenses.set_instance_transform(nl, Transform3D(Basis.IDENTITY, p))
		lenses.set_instance_custom_data(nl, Color(tint.r, tint.g, tint.b, INTENSITY[kind]))
		nl += 1
		if np < MAX_POOLS and e.x < POOL_M * POOL_M:
			# The quad spans 2 × 2 units: scale it to the pool's reach (≈ 3 h along the road,
			# 2 h across), turned to the road, laid just above the drawn surface.
			var along: Vector3 = road.normalized() if road.length_squared() > 0.01 else Vector3.FORWARD
			var across: Vector3 = Vector3(along.z, 0.0, -along.x)
			var b: Basis = Basis(across * h * 2.0, Vector3.UP, along * h * 3.0)
			pools.set_instance_transform(np, Transform3D(b, Vector3(p.x, ground + 0.07, p.z)))
			pools.set_instance_custom_data(np, Color(tint.r, tint.g, tint.b, INTENSITY[kind]))
			np += 1
	pools.visible_instance_count = np
	lenses.visible_instance_count = nl

func pool_count() -> int:
	return _pools.multimesh.visible_instance_count

func lens_count() -> int:
	return _lenses.multimesh.visible_instance_count
