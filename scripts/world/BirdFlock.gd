class_name BirdFlock
extends MultiMeshInstance3D
## Birds over the street (Nov 13 owner request: "more lively, just like the real Chennai"):
## crows wheeling over the roofs, pigeons in quick circles, black kites soaring high. ONE
## MultiMesh (one draw call, no texture, no shadows) whose instances fly on the GPU
## (shaders/bird_flock.gdshader); the script only re-centres the circles round the camera every
## RECENTRE_M and hides the birds at night (crows roost). Nothing is instanced while driving.
const SHADER: Shader = preload("res://shaders/bird_flock.gdshader")
const COUNT: int = 34
const SPREAD_M: float = 140.0
const RECENTRE_M: float = 110.0
const CROW: Color = Color(0.05, 0.05, 0.06)
const CROW_NECK: Color = Color(0.22, 0.22, 0.24)
const PIGEON: Color = Color(0.42, 0.44, 0.5)
const KITE: Color = Color(0.32, 0.2, 0.12)
## Birds fly from dawn (05:40) to dusk (18:40); shift minutes.
const DAY_START: float = 340.0
const DAY_END: float = 1120.0

var _centre: Vector3 = Vector3(INF, 0.0, INF)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _check_s: float = 0.0
## Last layout (circle centres and custom data), kept for tests: the headless renderer keeps
## no MultiMesh data.
var centres: PackedVector3Array = PackedVector3Array()
var customs: PackedColorArray = PackedColorArray()

func _ready() -> void:
	name = "BirdFlock"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = bird_mesh()
	mm.instance_count = COUNT
	# The birds move in the vertex shader, so the batch must never be culled by its rest AABB.
	mm.custom_aabb = AABB(Vector3(-400.0, -50.0, -400.0), Vector3(800.0, 200.0, 800.0))
	multimesh = mm
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	material_override = mat
	_rng.seed = 7741

## One bird (crow size, 0.9 m span): a slim body and two wings; UV.x = 1 at the wing tips.
static func bird_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body: Array[Vector3] = [Vector3(0.0, 0.0, 0.26), Vector3(0.06, 0.0, 0.0), Vector3(0.0, 0.05, 0.02), Vector3(-0.06, 0.0, 0.0), Vector3(0.0, 0.0, -0.22)]
	var tris: Array = [[0, 1, 2], [0, 2, 3], [2, 1, 4], [3, 2, 4], [0, 3, 1], [1, 3, 4]]
	for t: Array in tris:
		for i: int in t:
			st.set_color(Color(1, 1, 1))
			st.set_uv(Vector2(0.0, 0.0))
			st.add_vertex(body[i])
	# Wings: inner edge on the body, swept tips; the tail is a small fan at the back.
	for s: float in [-1.0, 1.0]:
		var wing: Array[Vector3] = [Vector3(s * 0.05, 0.02, 0.1), Vector3(s * 0.45, 0.0, -0.04), Vector3(s * 0.05, 0.02, -0.08), Vector3(s * 0.3, 0.01, 0.06)]
		var uvx: Array[float] = [0.0, 1.0, 0.0, 0.7]
		for i: int in [0, 3, 2, 3, 1, 2]:
			st.set_color(Color(1, 1, 1))
			st.set_uv(Vector2(uvx[i], 0.0))
			st.add_vertex(wing[i])
	for i: Vector3 in [Vector3(0.0, 0.0, -0.18), Vector3(0.07, 0.0, -0.34), Vector3(-0.07, 0.0, -0.34)]:
		st.set_color(Color(1, 1, 1))
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(i)
	st.generate_normals()
	return st.commit()

func _process(delta: float) -> void:
	_check_s -= delta
	if _check_s > 0.0:
		return
	_check_s = 0.5
	var minute: float = fmod(GameState.shift_minute, 1440.0)
	visible = minute >= DAY_START and minute <= DAY_END
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or not visible:
		return
	var at: Vector3 = cam.global_position
	if Vector2(at.x - _centre.x, at.z - _centre.z).length() > RECENTRE_M:
		recentre(Vector3(at.x, 0.0, at.z))

## Lay the circles out round `centre`: a few loose groups of crows, pigeons low and fast, two
## kites high and slow. Deterministic from the centre cell, so a return trip looks the same.
func recentre(centre: Vector3) -> void:
	_centre = centre
	_rng.seed = hash(Vector2i(floori(centre.x / RECENTRE_M), floori(centre.z / RECENTRE_M)))
	var mm: MultiMesh = multimesh
	centres.resize(COUNT)
	customs.resize(COUNT)
	var groups: Array[Vector3] = []
	for g: int in 4:
		groups.append(centre + Vector3(_rng.randf_range(-SPREAD_M, SPREAD_M), 0.0, _rng.randf_range(-SPREAD_M, SPREAD_M)))
	for i: int in COUNT:
		var kind: int = 2 if i < 2 else (1 if i < 10 else 0) # 2 kites, 8 pigeons, crows
		var g: Vector3 = groups[i % groups.size()]
		var centre_i: Vector3 = g + Vector3(_rng.randf_range(-14.0, 14.0), 0.0, _rng.randf_range(-14.0, 14.0))
		var radius: float = _rng.randf_range(6.0, 16.0)
		var speed: float = _rng.randf_range(9.0, 12.0) / radius
		var height: float = _rng.randf_range(16.0, 30.0)
		var rate: float = _rng.randf_range(2.6, 3.4)
		var size: float = _rng.randf_range(0.9, 1.1)
		var colour: Color = CROW if _rng.randf() < 0.8 else CROW_NECK
		match kind:
			1:
				radius = _rng.randf_range(5.0, 10.0)
				speed = _rng.randf_range(10.0, 13.0) / radius
				height = _rng.randf_range(12.0, 20.0)
				rate = _rng.randf_range(4.0, 5.0)
				size = 0.8
				colour = PIGEON
			2:
				centre_i = centre + Vector3(_rng.randf_range(-60.0, 60.0), 0.0, _rng.randf_range(-60.0, 60.0))
				radius = _rng.randf_range(22.0, 34.0)
				speed = _rng.randf_range(5.0, 7.0) / radius
				height = _rng.randf_range(45.0, 60.0)
				rate = 0.2
				size = 1.9
				colour = KITE
		if _rng.randf() < 0.5:
			speed = -speed
		centres[i] = centre_i + Vector3(0.0, height, 0.0)
		customs[i] = Color(radius, speed, _rng.randf() * TAU, rate)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), centres[i]))
		mm.set_instance_color(i, colour)
		mm.set_instance_custom_data(i, customs[i])
