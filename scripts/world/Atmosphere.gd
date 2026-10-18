class_name Atmosphere
extends Node
## Day/night and monsoon look, driven by GameState's shift clock and weather (GDD §3):
## Agni Nakshatram noon glare → golden Marina sunset → night; rain = overcast, denser fog.
## Headlights (group "headlight") switch on at dusk or in rain.

const SUNRISE_MIN: float = 360.0 # 6:00
const SUNSET_MIN: float = 1110.0 # 18:30
const MAX_ELEVATION_DEG: float = 72.0
const UPDATE_INTERVAL_S: float = 0.25

@export var environment_path: NodePath
@export var sun_path: NodePath

var _env: Environment
var _sun: DirectionalLight3D
var _sky: ProceduralSkyMaterial
var _timer: float = 0.0
var _rain_blend: float = 0.0
var _base_fog_density: float = 0.0028

func _ready() -> void:
	var we: WorldEnvironment = get_node_or_null(environment_path) as WorldEnvironment
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if we != null:
		_env = we.environment
		_base_fog_density = _env.fog_density
		if _env.sky != null:
			_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_rain_blend = 1.0 if GameState.is_raining else 0.0
	apply(GameState.shift_minute, _rain_blend)

func _process(delta: float) -> void:
	_rain_blend = move_toward(_rain_blend, 1.0 if GameState.is_raining else 0.0, delta * 0.25)
	_timer += delta
	if _timer >= UPDATE_INTERVAL_S:
		_timer = 0.0
		apply(GameState.shift_minute, _rain_blend)

## 0 at the horizon → 1 at noon; negative at night.
static func sun_height(minute: float) -> float:
	var t: float = (minute - SUNRISE_MIN) / (SUNSET_MIN - SUNRISE_MIN)
	return sin(PI * t) if t >= 0.0 and t <= 1.0 else -0.3

func apply(minute: float, rain: float) -> void:
	var t: float = clampf((minute - SUNRISE_MIN) / (SUNSET_MIN - SUNRISE_MIN), 0.0, 1.0)
	var h: float = sun_height(minute)
	var day: float = smoothstep(-0.05, 0.25, h) # 0 night … 1 day
	var golden: float = (1.0 - smoothstep(0.05, 0.35, h)) * day # low sun glow

	if _sun != null:
		# East (+x) at sunrise → overhead (tilted south, +z, at 13°N) → west at sunset.
		var to_sun: Vector3 = Vector3(cos(PI * t), maxf(h, 0.08) * sin(deg_to_rad(MAX_ELEVATION_DEG)), 0.35).normalized()
		if day < 0.01:
			to_sun = Vector3(-0.3, 0.8, -0.4).normalized() # moonlight
		_sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD), _sun.global_position)
		var sun_col: Color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.62, 0.35), golden)
		_sun.light_color = sun_col.lerp(Color(0.55, 0.62, 0.85), 1.0 - day)
		_sun.light_energy = lerpf(0.28, 0.8, day) * lerpf(1.0, 0.35, rain)

	if _env != null:
		var amb_day: Color = Color(0.42, 0.42, 0.47).lerp(Color(0.5, 0.42, 0.38), golden)
		# Night stays readable: sodium-lit Chennai streets, never pitch black.
		var amb: Color = Color(0.27, 0.26, 0.33).lerp(amb_day, day)
		_env.ambient_light_color = amb.lerp(Color(0.38, 0.4, 0.44) * lerpf(0.75, 1.0, day), rain * 0.7)
		var horizon: Color = Color(0.2, 0.19, 0.24).lerp(Color(0.86, 0.82, 0.72).lerp(Color(1.0, 0.6, 0.35), golden), day)
		horizon = horizon.lerp(Color(0.5, 0.52, 0.55) * lerpf(0.35, 1.0, day), rain)
		_env.fog_light_color = horizon * 0.8
		_env.fog_density = lerpf(_base_fog_density, _base_fog_density * 2.6, rain) * lerpf(1.3, 1.0, day)
		if _sky != null:
			var top: Color = Color(0.02, 0.03, 0.08).lerp(Color(0.35, 0.55, 0.85).lerp(Color(0.4, 0.4, 0.62), golden), day)
			_sky.sky_top_color = top.lerp(Color(0.45, 0.47, 0.5) * lerpf(0.3, 1.0, day), rain)
			_sky.sky_horizon_color = horizon
			_sky.ground_horizon_color = horizon

	var lights_on: bool = day < 0.55 or rain > 0.5
	for n: Node in get_tree().get_nodes_in_group("headlight"):
		(n as Light3D).visible = lights_on
