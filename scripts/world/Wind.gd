class_name Wind
extends Node
## One wind for the whole city (Nov 14 owner question: "will the trees respect the wind?").
## Direction, strength and gusts are shader globals (project.godot [shader_globals]) read by
## every tree (tree_near / tree_impostor), the rain splashes and the road dust, so they all
## move the same way. No nodes, no draw calls: just three numbers a frame.
##
## Chennai's day: a light land breeze from the west in the morning, the sea breeze from the
## south-east setting in by the afternoon (the strongest wind of the day), dying away at night.
## Rain brings stronger, gustier wind. Gusts arrive every 6–18 s and last a few seconds.
const LAND_BREEZE: Vector2 = Vector2(0.92, 0.2)    # blowing towards the east (from the west)
const SEA_BREEZE: Vector2 = Vector2(-0.8, 0.6)     # blowing towards the north-west (from the SE)
## Strength by hour (0 calm, 1 strong): [hour, strength].
const DAY_CURVE: Array[Vector2] = [Vector2(0.0, 0.18), Vector2(6.0, 0.15), Vector2(10.0, 0.22), Vector2(13.0, 0.4),
	Vector2(16.0, 0.55), Vector2(19.0, 0.4), Vector2(22.0, 0.22), Vector2(24.0, 0.18)]
const RAIN_EXTRA: float = 0.35
const GUST_EVERY_S: Vector2 = Vector2(6.0, 18.0)
const GUST_LEN_S: float = 3.5

## Current values (also readable by scripts: WindDustFX, tests).
static var direction: Vector2 = Vector2(-0.92, -0.38)
static var strength: float = 0.3
static var gust: float = 0.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_gust: float = 4.0
var _gust_t: float = -1.0
var _rain: float = 0.0

func _ready() -> void:
	name = "Wind"
	_rng.randomize()

func _process(delta: float) -> void:
	_rain = move_toward(_rain, 1.0 if GameState.is_raining else 0.0, delta * 0.3)
	var hour: float = fmod(GameState.shift_minute, 1440.0) / 60.0
	direction = direction_at(hour)
	strength = clampf(strength_at(hour) + _rain * RAIN_EXTRA, 0.0, 1.0)
	_next_gust -= delta
	if _next_gust <= 0.0:
		_next_gust = _rng.randf_range(GUST_EVERY_S.x, GUST_EVERY_S.y) * (0.6 if _rain > 0.5 else 1.0)
		_gust_t = 0.0
	if _gust_t >= 0.0:
		_gust_t += delta
		gust = sin(clampf(_gust_t / GUST_LEN_S, 0.0, 1.0) * PI) * (0.6 + 0.4 * _rain)
		if _gust_t > GUST_LEN_S:
			_gust_t = -1.0
			gust = 0.0
	push()

static func push() -> void:
	RenderingServer.global_shader_parameter_set("wind_dir", direction)
	RenderingServer.global_shader_parameter_set("wind_strength", strength)
	RenderingServer.global_shader_parameter_set("wind_gust", gust)

## The sea breeze swings in through the late morning and goes back to the land breeze at night.
static func direction_at(hour: float) -> Vector2:
	var sea: float = smoothstep(9.0, 13.0, hour) * (1.0 - smoothstep(20.0, 23.0, hour))
	return LAND_BREEZE.lerp(SEA_BREEZE, sea).normalized()

static func strength_at(hour: float) -> float:
	for i: int in range(1, DAY_CURVE.size()):
		if hour <= DAY_CURVE[i].x:
			var a: Vector2 = DAY_CURVE[i - 1]
			var b: Vector2 = DAY_CURVE[i]
			return lerpf(a.y, b.y, (hour - a.x) / maxf(b.x - a.x, 0.001))
	return DAY_CURVE[0].y

## World-space wind as a Vector3 (for particles).
static func world_vector() -> Vector3:
	return Vector3(direction.x, 0.03, direction.y).normalized()
