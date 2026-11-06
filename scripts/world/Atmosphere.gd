class_name Atmosphere
extends Node
## Day/night and monsoon look, driven by GameState's shift clock and weather (GDD §3):
## Agni Nakshatram noon glare → golden Marina sunset → night; rain = overcast, denser fog.
## Headlights (group "headlight") switch on at dusk or in rain.

const SUNRISE_MIN: float = 360.0 # 6:00 over the sea
const SUNSET_MIN: float = 1110.0 # 18:30
const MAX_ELEVATION_DEG: float = 72.0
const UPDATE_INTERVAL_S: float = 0.25
## The sun only moves in coarse steps, eased over SUN_EASE_S. A sun that creeps every frame
## (or every 0.25 s) makes shadow-map texels crawl — the "fast moving shadows" seen from the
## cockpit. Stepping it rarely keeps shadows rock-steady between steps.
const SUN_STEP_DEG: float = 3.0
const SUN_EASE_S: float = 2.5
## Chennai sky (shaders/chennai_sky.gdshader): humid haze horizon, drifting cumulus, monsoon
## overcast, dusk tints, stars. Clouds come from one seamless noise texture generated once.
## Oct 31 device test: the old ProceduralSkyMaterial cover (alpha 0.24) showed no clouds at all.
const SKY_SHADER: Shader = preload("res://shaders/chennai_sky.gdshader")
const CLOUD_TEXTURE_SIZE: int = 512
const CLOUD_NOISE_SEED: int = 13080
## Cloud cover 0..1: scattered fair-weather cumulus on dry days, closed overcast in the monsoon.
const COVERAGE_RAIN: float = 0.97
const MOON_CYCLE_DAYS: int = 7
const MOON_EARLY_MIN: float = 420.0 # Moonrise after sunrise: half moon, up by the afternoon.
const MOON_LATE_MIN: float = 840.0 # Moonrise about 8 PM: just past full.
## Each day picks a sky: [cumulus cover, cirrus amount]. Some days are clear blue, some carry the
## high cirrus that makes the best sunsets.
const DAY_SKIES: Array[Vector2] = [Vector2(0.34, 0.55), Vector2(0.42, 0.3), Vector2(0.27, 0.8),
	Vector2(0.46, 0.65), Vector2(0.3, 0.2), Vector2(0.38, 0.95)]
## Sky through the day, by minute (colours are sRGB hex, researched from Chennai photos and
## weather notes: docs/CHENNAI_SKY.md):
## zenith, mid, horizon on the sun's side, horizon opposite, cloud lit, cloud shade, cirrus,
## sun glow, sunlight, ambient. 0 and 1440 must match so the day wraps.
const SKY_KEYS: Array[Array] = [
	[0.0, "050a1c", "0b1430", "2a2438", "141a34", "3a4058", "12162a", "2a3048", "6a78a0", "8c9edb", "454355"],
	[300.0, "050a1c", "0b1430", "2a2438", "141a34", "3a4058", "12162a", "2a3048", "6a78a0", "8c9edb", "454355"],
	[330.0, "0f1f4f", "2a3f7a", "e08a5a", "5a5a8c", "8a6f8a", "2a2f52", "e8907a", "ff9a60", "a89ac0", "4c4a60"],
	[360.0, "2a55a0", "7aa0d0", "ffb070", "c8b4d0", "ffd0a8", "7a6f90", "ffb090", "ffa050", "ffb070", "6a5e62"],
	[400.0, "1f5ebf", "5a9ae6", "f2e0c0", "cfe0f0", "fff4e4", "9fb0cc", "fff0e0", "ffd8a0", "ffe2b8", "6c6c76"],
	[480.0, "1a56bd", "4a92e8", "d4e8f6", "cde4f5", "ffffff", "aebfd8", "ffffff", "ffe8c0", "fff6e6", "6b6b78"],
	[720.0, "2460c0", "5a9cea", "dfeaf2", "d8e8f2", "ffffff", "b4c2d8", "f4f8ff", "ffeecc", "fffaf0", "6b6b78"],
	[960.0, "1d58b8", "5494e4", "efe8d4", "d0e4f2", "fffaf0", "a6b4cc", "fff6e8", "ffe0b0", "ffeed6", "6c6a74"],
	[1050.0, "2a5ab0", "6f9ad8", "ffd090", "d8d0dc", "ffe6bc", "8f8fb0", "ffd8a0", "ffc070", "ffc080", "746660"],
	[1095.0, "2f4f9c", "8a88c0", "ff8a3c", "e0a8b8", "ffb070", "6a5a8c", "ff8a50", "ff9040", "ff9a58", "7a5e5e"],
	[1110.0, "2a3f8a", "9a6fa8", "ff5a1e", "d88aa8", "ff8048", "4a3a6c", "ff4a3a", "ff6a20", "ff8040", "6e5462"],
	[1125.0, "1c2a6c", "6a4a90", "e8481f", "7a5a96", "d04a5a", "2e2650", "ff3a5a", "ff5030", "b06a70", "564a66"],
	[1140.0, "101c52", "34347a", "a03c50", "3a3f78", "5a3a6a", "1c1c3c", "8a3a70", "c04040", "8c8ccc", "4a4660"],
	[1165.0, "070f30", "121e4c", "32284c", "1a2244", "2a2c48", "10142a", "30284c", "6a5a90", "8c9edb", "454355"],
	[1200.0, "050a1c", "0b1430", "2a2438", "141a34", "3a4058", "12162a", "2a3048", "6a78a0", "8c9edb", "454355"],
	[1440.0, "050a1c", "0b1430", "2a2438", "141a34", "3a4058", "12162a", "2a3048", "6a78a0", "8c9edb", "454355"],
]

@export var environment_path: NodePath
@export var sun_path: NodePath

var _env: Environment
var _sun: DirectionalLight3D
var _sky: ShaderMaterial
var _cloud_texture: NoiseTexture2D
var _timer: float = 0.0
var _rain_blend: float = 0.0
var _base_fog_density: float = 0.0028
var _sun_target: Vector3 = Vector3.ZERO
var _sun_dir: Vector3 = Vector3.ZERO

func _ready() -> void:
	var we: WorldEnvironment = get_node_or_null(environment_path) as WorldEnvironment
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if we != null:
		_env = we.environment
		_base_fog_density = _env.fog_density
		# The sky draws its own horizon air. Fog over the sky turned the whole dome grey.
		_env.fog_sky_affect = 0.0
		if _env.sky != null:
			# The sky resource can be shared between scenes; only modify our copy.
			_env.sky = _env.sky.duplicate() as Sky
			_sky = ShaderMaterial.new()
			_sky.shader = SKY_SHADER
			_env.sky.sky_material = _sky
			# Ambient is a colour and reflections are off (Env), so the sky never feeds a radiance
			# cubemap; keep it tiny and incremental in case a later change turns one on.
			_env.sky.radiance_size = Sky.RADIANCE_SIZE_32
			_env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
			_setup_clouds()
	_rain_blend = 1.0 if GameState.is_raining else 0.0
	apply(GameState.shift_minute, _rain_blend)

## Deterministic, asset-free cloud noise, generated asynchronously by Godot; mipmapped so the
## distant cloud layer near the horizon doesn't shimmer.
func _setup_clouds() -> void:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = CLOUD_NOISE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.014
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5
	_cloud_texture = NoiseTexture2D.new()
	_cloud_texture.width = CLOUD_TEXTURE_SIZE
	_cloud_texture.height = CLOUD_TEXTURE_SIZE
	_cloud_texture.seamless = true
	_cloud_texture.generate_mipmaps = true
	_cloud_texture.noise = noise
	_sky.set_shader_parameter("cloud_noise", _cloud_texture)

func _process(delta: float) -> void:
	_rain_blend = move_toward(_rain_blend, 1.0 if GameState.is_raining else 0.0, delta * 0.25)
	_timer += delta
	if _timer >= UPDATE_INTERVAL_S:
		_timer = 0.0
		apply(GameState.shift_minute, _rain_blend)
	_ease_sun(delta)

func _ease_sun(delta: float) -> void:
	if _sun == null or _sun_target == Vector3.ZERO:
		return
	if _sun_dir == Vector3.ZERO:
		_sun_dir = _sun_target
	elif _sun_dir.is_equal_approx(_sun_target):
		return
	else:
		_sun_dir = _sun_dir.slerp(_sun_target, clampf(delta / SUN_EASE_S * 3.0, 0.0, 1.0)).normalized()
		if _sun_dir.angle_to(_sun_target) < 0.002:
			_sun_dir = _sun_target
	_sun.global_transform = Transform3D(Basis.looking_at(-_sun_dir, Vector3.UP if absf(_sun_dir.y) < 0.99 else Vector3.FORWARD), _sun.global_position)

## Where the moon is. It rises later each day and its phase changes, staying between a half
## moon and just past full, so a night shift nearly always has one to see.
static func moon_direction(minute: float, game_day: int) -> Vector3:
	var cycle: int = posmod(game_day, MOON_CYCLE_DAYS * 2)
	var age: float = float(mini(cycle, MOON_CYCLE_DAYS * 2 - cycle)) / float(MOON_CYCLE_DAYS)
	var rise: float = SUNRISE_MIN + lerpf(MOON_LATE_MIN, MOON_EARLY_MIN, age)
	var t: float = fposmod(minute - rise, 1440.0) / (SUNSET_MIN - SUNRISE_MIN)
	return Vector3(cos(PI * t), sin(PI * t) * sin(deg_to_rad(MAX_ELEVATION_DEG)) if t <= 1.9 else -0.3, -0.3).normalized()

## 0 at the horizon → 1 at noon; slightly negative through twilight, -0.3 at night.
static func sun_height(minute: float) -> float:
	var t: float = (minute - SUNRISE_MIN) / (SUNSET_MIN - SUNRISE_MIN)
	return maxf(sin(PI * t), -0.3) if t >= -0.5 and t <= 1.5 else -0.3

## Sky colours at this minute, blended between the two nearest SKY_KEYS.
static func sky_colours(minute: float) -> Array[Color]:
	var m: float = fposmod(minute, 1440.0)
	var i: int = 0
	while i < SKY_KEYS.size() - 2 and m >= float(SKY_KEYS[i + 1][0]):
		i += 1
	var a: Array = SKY_KEYS[i]
	var b: Array = SKY_KEYS[i + 1]
	var f: float = smoothstep(float(a[0]), float(b[0]), m)
	var out: Array[Color] = []
	for k: int in range(1, a.size()):
		out.append(Color(str(a[k])).lerp(Color(str(b[k])), f))
	return out

func apply(minute: float, rain: float) -> void:
	var t: float = (minute - SUNRISE_MIN) / (SUNSET_MIN - SUNRISE_MIN)
	var h: float = sun_height(minute)
	var day: float = smoothstep(-0.05, 0.25, h) # 0 night … 1 day
	var low: float = (1.0 - smoothstep(0.06, 0.42, h)) * smoothstep(-0.3, -0.1, h)
	var c: Array[Color] = sky_colours(minute)
	# True sun, below the horizon in twilight. The light itself stops just above it.
	var true_sun: Vector3 = Vector3(cos(PI * t), h * sin(deg_to_rad(MAX_ELEVATION_DEG)), 0.35).normalized()

	var moon: Vector3 = moon_direction(minute, GameState.day)

	if _sun != null:
		# East (+x) at sunrise → overhead (tilted south, +z, at 13°N) → west at sunset.
		var to_sun: Vector3 = Vector3(cos(PI * clampf(t, 0.0, 1.0)), maxf(h, 0.08) * sin(deg_to_rad(MAX_ELEVATION_DEG)), 0.35).normalized()
		if day < 0.01:
			to_sun = Vector3(-0.3, 0.8, -0.4).normalized() # Moonlight, from high when the moon is low.
			if moon.y > 0.3:
				to_sun = moon
		if _sun_target == Vector3.ZERO or _sun_target.angle_to(to_sun) >= deg_to_rad(SUN_STEP_DEG) or day < 0.01:
			var first: bool = _sun_target == Vector3.ZERO
			_sun_target = to_sun
			if first or not is_inside_tree():
				_sun_dir = to_sun
				_sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD), _sun.global_position)
		_sun.light_color = c[8].lerp(Color(0.9, 0.9, 0.92), rain * 0.6)
		_sun.light_energy = lerpf(0.28, 0.85, day) * lerpf(1.0, 0.35, rain)

	if _env != null:
		# Night stays readable: sodium-lit Chennai streets, never pitch black.
		_env.ambient_light_color = c[9].lerp(Color(0.38, 0.4, 0.44) * lerpf(0.75, 1.0, day), rain * 0.7)
		var horizon: Color = c[2].lerp(c[3], 0.5)
		var fog: Color = horizon.lerp(Color(0.5, 0.52, 0.55) * lerpf(0.35, 1.0, day), rain)
		_env.fog_light_color = fog * 0.8
		_env.fog_density = lerpf(_base_fog_density, _base_fog_density * 2.6, rain) * lerpf(1.3, 1.0, day)
		if _sky != null:
			var slate: Color = Color(0.52, 0.55, 0.6) * lerpf(0.3, 1.0, day)
			var mood: Vector2 = DAY_SKIES[posmod(GameState.day, DAY_SKIES.size())]
			_sky.set_shader_parameter("zenith_colour", c[0].lerp(Color(0.42, 0.45, 0.5) * lerpf(0.3, 1.0, day), rain))
			_sky.set_shader_parameter("mid_colour", c[1].lerp(Color(0.48, 0.5, 0.55) * lerpf(0.3, 1.0, day), rain))
			_sky.set_shader_parameter("horizon_sun", c[2].lerp(Color(0.5, 0.52, 0.56) * lerpf(0.35, 1.0, day), rain))
			_sky.set_shader_parameter("horizon_far", c[3].lerp(Color(0.5, 0.52, 0.56) * lerpf(0.35, 1.0, day), rain))
			_sky.set_shader_parameter("ground_colour", fog * 0.6)
			_sky.set_shader_parameter("cloud_lit", c[4].lerp(slate, rain))
			_sky.set_shader_parameter("cloud_shade", c[5].lerp(Color(0.33, 0.36, 0.41) * lerpf(0.3, 1.0, day), rain))
			_sky.set_shader_parameter("cirrus_colour", c[6])
			_sky.set_shader_parameter("sun_glow_colour", c[7])
			_sky.set_shader_parameter("sun_dir", true_sun)
			_sky.set_shader_parameter("moon_dir", moon)
			_sky.set_shader_parameter("coverage", lerpf(mood.x, COVERAGE_RAIN, rain))
			# High cloud thickens toward evening: it is what catches the sunset.
			_sky.set_shader_parameter("cirrus", clampf(mood.y + low * 0.35, 0.0, 1.0) * (1.0 - rain))
			_sky.set_shader_parameter("cloud_alpha", lerpf(0.7, 1.0, day))
			_sky.set_shader_parameter("base_dark", lerpf(0.45, 0.9, maxf(rain, low)))
			_sky.set_shader_parameter("low_sun", low * (1.0 - rain))
			_sky.set_shader_parameter("rays", low * smoothstep(0.25, 0.45, mood.x) * (1.0 - rain))
			_sky.set_shader_parameter("night", 1.0 - smoothstep(-0.22, -0.02, h))
			_sky.set_shader_parameter("overcast", rain)
			_sky.set_shader_parameter("wind_speed", lerpf(0.004, 0.012, rain))

	var lights_on: bool = day < 0.55 or rain > 0.5
	for n: Node in get_tree().get_nodes_in_group("headlight"):
		(n as Light3D).visible = lights_on
		if not n.has_meta("undamaged_energy"):
			n.set_meta("undamaged_energy", (n as Light3D).light_energy)
		(n as Light3D).light_energy = float(n.get_meta("undamaged_energy")) * lerpf(1.0, 0.25, float(GameState.damage_state()["lights"]) / 100.0)
