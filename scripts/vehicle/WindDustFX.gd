class_name WindDustFX
extends Node3D
## Wind-blown dust for the player auto. Every 12–35 s a gust rolls a low, thin haze of road dust
## across the road ahead for about 2.5 s. Child of AutoRickshawController (local space = the
## auto's); the particles are world space (local_coords = false), so a gust keeps drifting after
## the auto has passed. No dust in the rain or when wrecked; nothing runs between gusts.
##
## Nov 4 device test: the Kenney sprite version (streaks, puffs, grit and a wheel trail) read as
## cartoon. Now there are no sprites at all: shaders/dust_haze.gdshader draws each particle as a
## soft billowing patch from procedural noise. Budget: one emitter, HAZE_AMOUNT quads, only while
## a gust is on screen; particles fade before they reach the camera, so overdraw stays small.
## No wheel trail: an auto on asphalt does not throw a dust plume, and it ran all the time.

const GUST_MIN_S: float = 12.0
const GUST_MAX_S: float = 35.0
const GUST_LEN_S: float = 2.5
const FIRST_GUST_S: float = 6.0
const HAZE_AMOUNT: int = 8
const HAZE_LIFETIME_S: float = 3.2
## Prevailing breeze over the city, blowing from the sea (east) towards the west, world space.
const WIND_WORLD: Vector3 = Vector3(-0.92, 0.04, -0.38)

var _haze: CPUParticles3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wait_s: float = FIRST_GUST_S
var _gust_left_s: float = 0.0

func _ready() -> void:
	_haze = _build_haze()
	add_child(_haze)
	_rng.randomize()

func _process(delta: float) -> void:
	if _gust_left_s > 0.0:
		_gust_left_s -= delta
		if _gust_left_s <= 0.0:
			_stop_gust()
		return
	_wait_s -= delta
	if _wait_s <= 0.0:
		_wait_s = _rng.randf_range(GUST_MIN_S, GUST_MAX_S)
		# Wet roads do not dust; a wreck has better things to show.
		if not GameState.is_raining and not GameState.is_wrecked():
			_start_gust()

## True while a gust's dust is being emitted (tests, debug overlay).
func gusting() -> bool:
	return _haze.emitting

## Prevailing wind turned a little at random, so no two gusts look the same.
func _start_gust() -> void:
	var dir_world: Vector3 = WIND_WORLD.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)).normalized()
	# Ahead of the auto, a few metres to either side of its path, where the camera looks.
	_haze.position = Vector3(_rng.randf_range(-5.0, 5.0), 0.35, _rng.randf_range(-17.0, -10.0))
	_haze.direction = (global_basis.inverse() * dir_world).normalized()
	_haze.emitting = true
	_gust_left_s = GUST_LEN_S

func _stop_gust() -> void:
	_haze.emitting = false
	_gust_left_s = 0.0

## Low dust rolling with the gust: large, faint, growing and thinning as it drifts.
static func _build_haze() -> CPUParticles3D:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/dust_haze.gdshader") as Shader
	var e: CPUParticles3D = CollisionFX._emitter("WindDust", HAZE_LIFETIME_S, Vector2(5.0, 2.2), mat)
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = HAZE_AMOUNT
	e.local_coords = false
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.spread = 12.0
	e.initial_velocity_min = 2.0
	e.initial_velocity_max = 3.5
	e.damping_min = 0.3
	e.damping_max = 0.6
	e.gravity = Vector3(0.0, 0.05, 0.0)
	# The angle is only the shader's per-particle noise seed (the shader billboards upright).
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(4.0, 0.2, 3.0)
	e.scale_amount_min = 0.8
	e.scale_amount_max = 1.3
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.4))
	e.scale_amount_curve = grow
	# Fades in from nothing, holds, fades out: gusts never pop.
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 1))
	g.add_point(0.65, Color(1, 1, 1, 0.8))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	e.color_ramp = g
	return e
