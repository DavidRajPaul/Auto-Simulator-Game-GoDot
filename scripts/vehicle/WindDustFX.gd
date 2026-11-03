class_name WindDustFX
extends Node3D
## Wind and road dust for the player auto (Nov 3 request). Every 12–35 s a gust sweeps across the road
## ahead: long streaks of wind, a sheet of dust and some grit, for about 2.5 s. While the auto moves
## on a dry road a thin trail of dust rises behind the rear wheels. Child of AutoRickshawController
## (local space = the auto's), emitters use world-space particles (local_coords = false), so a gust
## keeps drifting after the auto has moved on. Nothing runs while the auto is parked.
## Textures: Kenney Particle Pack (CC0) via tools/assets/fetch_fx.py. Emitters are built once; gusts
## only toggle `emitting`, so nothing restarts while the timer runs.

const GUST_MIN_S: float = 12.0
const GUST_MAX_S: float = 35.0
const GUST_LEN_S: float = 2.5
const FIRST_GUST_S: float = 6.0
const TRAIL_MIN_KMH: float = 12.0
## Prevailing breeze over the city, blowing from the sea (east) towards the west, world space.
const WIND_WORLD: Vector3 = Vector3(-0.92, 0.08, -0.38)
const REAR_POS: Vector3 = Vector3(0.0, -0.35, 0.9)

var _streaks: CPUParticles3D
var _sheet: CPUParticles3D
var _grit: CPUParticles3D
var _trail: CPUParticles3D
var _auto: AutoRickshawController
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wait_s: float = FIRST_GUST_S
var _gust_left_s: float = 0.0

func _ready() -> void:
	_auto = get_parent() as AutoRickshawController
	_streaks = _build_streaks()
	add_child(_streaks)
	_sheet = _build_sheet()
	add_child(_sheet)
	_grit = _build_grit()
	add_child(_grit)
	_trail = _build_trail()
	_trail.position = REAR_POS
	add_child(_trail)
	_rng.randomize()

func _process(delta: float) -> void:
	var raining: bool = GameState.is_raining
	# Gusts: a short burst, then a long quiet spell. Monsoon wind still gusts, but no dust (wet road).
	if _gust_left_s > 0.0:
		_gust_left_s -= delta
		if _gust_left_s <= 0.0:
			_stop_gust()
	else:
		_wait_s -= delta
		if _wait_s <= 0.0:
			_start_gust(raining)
			_gust_left_s = GUST_LEN_S
			_wait_s = _rng.randf_range(GUST_MIN_S, GUST_MAX_S)
	# Road dust: only while the auto is really moving, not in the rain, and not when wrecked.
	var moving: bool = _auto != null and _auto.current_speed_kmh >= TRAIL_MIN_KMH
	var wrecked: bool = GameState.is_wrecked()
	_trail.emitting = moving and not raining and not wrecked

## Prevailing wind turned a little at random, so no two gusts look the same.
func _start_gust(raining: bool) -> void:
	var dir_world: Vector3 = WIND_WORLD.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)).normalized()
	var dir_local: Vector3 = (global_basis.inverse() * dir_world).normalized()
	# Ahead of the auto, a few metres to either side of its path, where the camera looks.
	var place: Vector3 = Vector3(_rng.randf_range(-7.0, 7.0), 0.0, _rng.randf_range(-16.0, -7.0))
	_streaks.position = place + Vector3(0.0, _rng.randf_range(0.6, 2.2), 0.0)
	_streaks.direction = dir_local
	_streaks.emitting = true
	if not raining:
		_sheet.position = place + Vector3(0.0, 0.4, 0.0)
		_sheet.direction = dir_local
		_sheet.emitting = true
		_grit.position = place + Vector3(0.0, 0.2, 0.0)
		_grit.direction = dir_local
		_grit.emitting = true

func _stop_gust() -> void:
	_streaks.emitting = false
	_sheet.emitting = false
	_grit.emitting = false

static func _gradient(c0: Color, c1: Color) -> Gradient:
	# Fades in from nothing, holds, fades out: gusts should not pop in.
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(c0.r, c0.g, c0.b, 0.0))
	g.add_point(0.25, c0)
	g.set_color(g.get_point_count() - 1, Color(c1.r, c1.g, c1.b, 0.0))
	return g

static func _grow(from: float, to: float) -> Curve:
	var c: Curve = Curve.new()
	c.add_point(Vector2(0.0, from))
	c.add_point(Vector2(1.0, to))
	return c

## Long soft streaks shooting along the gust, stretched by their velocity (align_y).
static func _build_streaks() -> CPUParticles3D:
	var e: CPUParticles3D = CollisionFX._emitter("WindStreaks", 1.6, Vector2(0.26, 2.6),
		CollisionFX._mat(CollisionFX._tex("wind_streak.png"), false))
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = 22
	e.local_coords = false
	e.particle_flag_align_y = true
	e.spread = 10.0
	e.initial_velocity_min = 9.0
	e.initial_velocity_max = 13.0
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(4.0, 1.2, 2.5)
	e.color_ramp = _gradient(Color(0.92, 0.94, 0.92, 0.6), Color(0.92, 0.94, 0.92, 0.0))
	return e

## Tan dust lifting off the road and rolling with the gust.
static func _build_sheet() -> CPUParticles3D:
	var e: CPUParticles3D = CollisionFX._emitter("WindDust", 3.0, Vector2(2.6, 2.6),
		CollisionFX._mat(CollisionFX._tex("dust_puff.png"), false))
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = 14
	e.local_coords = false
	e.spread = 8.0
	e.initial_velocity_min = 4.0
	e.initial_velocity_max = 7.0
	e.damping_min = 0.4
	e.damping_max = 0.8
	e.gravity = Vector3(0.0, 0.05, 0.0)
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -15.0
	e.angular_velocity_max = 15.0
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(3.5, 0.5, 2.5)
	e.scale_amount_min = 0.7
	e.scale_amount_max = 1.2
	e.scale_amount_curve = _grow(0.4, 1.2)
	e.color_ramp = _gradient(Color(0.74, 0.67, 0.52, 0.62), Color(0.74, 0.67, 0.52, 0.0))
	return e

## Small grit thrown up by the gust and falling back onto the road.
static func _build_grit() -> CPUParticles3D:
	var e: CPUParticles3D = CollisionFX._emitter("WindGrit", 1.2, Vector2(0.22, 0.22),
		CollisionFX._mat(CollisionFX._tex("dust_grit.png"), false))
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = 16
	e.local_coords = false
	e.spread = 25.0
	e.initial_velocity_min = 5.0
	e.initial_velocity_max = 8.0
	e.gravity = Vector3(0.0, -7.0, 0.0)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(3.0, 0.2, 2.0)
	e.color_ramp = _gradient(Color(0.62, 0.55, 0.42, 0.85), Color(0.62, 0.55, 0.42, 0.0))
	return e

## Dust trail behind the rear wheels while the auto moves: rises and thins out, never a cloud.
static func _build_trail() -> CPUParticles3D:
	var e: CPUParticles3D = CollisionFX._emitter("RoadDust", 1.4, Vector2(1.2, 1.2),
		CollisionFX._mat(CollisionFX._tex("dust_puff.png"), false))
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = 9
	e.local_coords = false
	e.direction = Vector3(0.0, 0.5, 1.0) # behind the auto: the auto faces -Z
	e.spread = 25.0
	e.initial_velocity_min = 1.0
	e.initial_velocity_max = 2.2
	e.gravity = Vector3(0.0, 0.3, 0.0)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.2
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.0
	e.scale_amount_curve = _grow(0.5, 1.4)
	e.color_ramp = _gradient(Color(0.74, 0.67, 0.52, 0.32), Color(0.74, 0.67, 0.52, 0.0))
	return e
