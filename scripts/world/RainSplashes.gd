class_name RainSplashes
extends Node3D
## Rain round the camera (Nov 14 owner question: "will rain splash when it hits the ground?";
## Nov 14 device report: "the rain is very bad, white boxes behind the auto").
##  * Falling rain: ONE MultiMesh of STREAKS thin lit streaks in a world-anchored grid that wraps
##    round the camera (shaders/rain_streaks.gdshader): drops seen with motion blur, slanted by
##    the wind, catching headlights, street lights and lightning.
##  * Splashes round the camera: ONE MultiMesh of COUNT splashes that reposition themselves in
##    the vertex shader (shaders/rain_splash.gdshader): a ring spreading on the road and a crown
##    of spray, at random spots within RADIUS_M, leaning with the wind. Drawn only while it
##    rains, faded in and out with the rain.
##  * Tyre spray behind the player's auto on a wet road, and a splash when a wheel drops into a
##    rain-filled pothole (SignalBus.pothole_hit): one CPUParticles3D each, emitting only then,
##    drawn as soft round mist puffs (shaders/rain_mist.gdshader) that fade before the camera.
## The wet road's ripples are drawn by street_surface.gdshader itself.
const COUNT: int = 380
const RADIUS_M: float = 12.0
const STREAKS: int = 1400
const STREAK_RADIUS_M: float = 16.0
const STREAK_HEIGHT_M: float = 12.0
const SPRAY_MIN_MPS: float = 4.0
const FADE_PER_S: float = 0.35

var rain: float = 0.0
var _splashes: MultiMeshInstance3D
var _mat: ShaderMaterial
var _streaks: MultiMeshInstance3D
var _streak_mat: ShaderMaterial
var _spray: CPUParticles3D
var _burst: CPUParticles3D
var _player_pos: Vector3 = Vector3.ZERO
var _player_fwd: Vector3 = Vector3.FORWARD
var _player_speed: float = 0.0

func _ready() -> void:
	name = "RainSplashes"
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/rain_splash.gdshader")
	_mat.set_shader_parameter("radius", RADIUS_M)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = splash_mesh()
	mm.instance_count = COUNT
	for i: int in COUNT:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	# The splashes move in the shader: never cull the batch by its rest bounds.
	mm.custom_aabb = AABB(Vector3(-8000.0, -50.0, -8000.0), Vector3(16000.0, 150.0, 16000.0))
	_splashes = MultiMeshInstance3D.new()
	_splashes.name = "Splashes"
	_splashes.multimesh = mm
	_splashes.material_override = _mat
	_splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splashes.visible = false
	add_child(_splashes)
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = preload("res://shaders/rain_streaks.gdshader")
	_streak_mat.set_shader_parameter("radius", STREAK_RADIUS_M)
	_streak_mat.set_shader_parameter("height", STREAK_HEIGHT_M)
	_streaks = MultiMeshInstance3D.new()
	_streaks.name = "Streaks"
	_streaks.multimesh = _identity_multimesh(streak_mesh(), STREAKS)
	_streaks.material_override = _streak_mat
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streaks.visible = false
	add_child(_streaks)
	_spray = _make_particles("TyreSpray", 24, 0.9)
	# Both rear wheels (1.1 m apart), puffs drifting back and up a little and spreading.
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_spray.emission_box_extents = Vector3(0.55, 0.05, 0.1)
	_spray.direction = Vector3(0.0, 0.35, 1.0)
	_spray.spread = 25.0
	_spray.initial_velocity_min = 0.8
	_spray.initial_velocity_max = 1.8
	_spray.gravity = Vector3(0.0, -0.6, 0.0)
	_spray.damping_min = 1.5
	_spray.damping_max = 2.5
	_spray.scale_amount_min = 0.25
	_spray.scale_amount_max = 0.45
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.6))
	_spray.scale_amount_curve = grow
	_burst = _make_particles("PotholeSplash", 28, 0.6)
	_burst.one_shot = true
	_burst.explosiveness = 0.95
	_burst.direction = Vector3.UP
	_burst.spread = 55.0
	_burst.initial_velocity_min = 1.4
	_burst.initial_velocity_max = 2.8
	rain = 1.0 if GameState.is_raining else 0.0
	SignalBus.player_pose_updated.connect(func(p: Vector3, f: Vector3) -> void:
		_player_pos = p
		_player_fwd = f)
	SignalBus.speed_updated.connect(func(kmh: float) -> void: _player_speed = kmh / 3.6)
	SignalBus.pothole_hit.connect(_on_pothole)

func _identity_multimesh(m: Mesh, n: int) -> MultiMesh:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = n
	for i: int in n:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	# Placed in the shader: never cull the batch by its rest bounds.
	mm.custom_aabb = AABB(Vector3(-8000.0, -50.0, -8000.0), Vector3(16000.0, 150.0, 16000.0))
	return mm

## One streak: a unit quad (UV.x across, UV.y along); the shader sizes and orients it.
static func streak_mesh() -> ArrayMesh:
	var v: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
	var uv: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## A ground ring (UV.y 0..0.49) and two crossed upright cards for the spray (UV.y 0.5..1).
static func splash_mesh() -> ArrayMesh:
	var v: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	var quads: Array = [
		[Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector2(0, 0), Vector2(1, 0.49)],
		[Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0), Vector2(0, 0.5), Vector2(1, 1)],
		[Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, -1), Vector2(0, 0.5), Vector2(1, 1)],
	]
	for q: Array in quads:
		var lo: Vector2 = q[4]
		var hi: Vector2 = q[5]
		var corners: Array[Vector2] = [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]
		for i: int in [0, 1, 2, 0, 2, 3]:
			v.append(q[i])
			uv.append(corners[i])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _make_particles(n: String, amount: int, life: float) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.09
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2.ONE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = preload("res://shaders/rain_mist.gdshader")
	q.material = mat
	p.mesh = q
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _process(delta: float) -> void:
	rain = move_toward(rain, 1.0 if GameState.is_raining else 0.0, delta * FADE_PER_S)
	_splashes.visible = rain > 0.02
	_streaks.visible = _splashes.visible
	var cam: Camera3D = get_viewport().get_camera_3d()
	if _splashes.visible and cam != null:
		var c: Vector3 = cam.global_position
		# Centre the disc a little ahead of the camera, where the player is looking.
		var ahead: Vector3 = -cam.global_basis.z
		ahead.y = 0.0
		c += ahead.normalized() * RADIUS_M * 0.6 if ahead.length() > 0.01 else Vector3.ZERO
		_mat.set_shader_parameter("centre", c)
		_mat.set_shader_parameter("ground_y", SignalBus.surface_height(c.x, c.z, 0.06))
		_mat.set_shader_parameter("intensity", rain)
		_streak_mat.set_shader_parameter("centre", cam.global_position)
		_streak_mat.set_shader_parameter("ground_y", SignalBus.surface_height(cam.global_position.x, cam.global_position.z, 0.06))
		_streak_mat.set_shader_parameter("intensity", rain)
	# Tyre spray: from behind the rear wheels while the auto runs on a wet road.
	var spraying: bool = rain > 0.5 and _player_speed > SPRAY_MIN_MPS
	if spraying:
		_spray.global_position = _player_pos - _player_fwd.normalized() * 1.2 + Vector3(0.0, 0.2, 0.0)
		var back: Vector3 = -_player_fwd.normalized()
		_spray.global_basis = Basis.looking_at(-back, Vector3.UP) if back.length() > 0.1 else Basis.IDENTITY
		_spray.initial_velocity_max = 1.2 + _player_speed * 0.08
	if _spray.emitting != spraying:
		_spray.emitting = spraying

func _on_pothole(pos: Vector3, _severity: float) -> void:
	if rain < 0.3:
		return
	_burst.global_position = pos + Vector3(0.0, 0.05, 0.0)
	_burst.restart()
	_burst.emitting = true

func splash_count() -> int:
	return COUNT if _splashes.visible else 0
