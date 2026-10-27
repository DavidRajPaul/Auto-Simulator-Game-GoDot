class_name CollisionFX
extends Node3D
## Impact feedback: a crunch sized to the hit, a metal scrape while sliding along a wall, and
## textured particles at the contact point — velocity-stretched spark streaks, a short hit flash,
## a dust/smoke cloud that billows and fades, and debris chips that fall — plus a camera jolt and
## a phone buzz on hard hits. Textures: Kenney CC0 particle packs (assets/fx, CREDITS_fx.md);
## each emitter falls back to a soft procedural sprite if a texture is missing, never a square.
## Reads SignalBus only. ≤ 4 draw calls while active, 0 when idle.

const CRASH_HARD: String = "res://assets/audio/vehicle/crash_hard.ogg"
const CRASH_LIGHT: String = "res://assets/audio/vehicle/crash_light.ogg"
const SCRAPE: String = "res://assets/audio/vehicle/scrape_loop.ogg"
const FX_DIR: String = "res://assets/fx/"
const HARD_SEVERITY: float = 0.45

var _hard: AudioStreamPlayer3D
var _light: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _sparks: CPUParticles3D
var _flash: CPUParticles3D
var _dust: CPUParticles3D
var _debris: CPUParticles3D
var _scrape_level: float = 0.0
var _scrape_target: float = 0.0
static var _soft_dot: Texture2D

func _ready() -> void:
	_hard = _player(CRASH_HARD, 0.0)
	_light = _player(CRASH_LIGHT, -3.0)
	_scrape = _player(SCRAPE, -8.0)
	if _scrape.stream is AudioStreamOggVorbis:
		(_scrape.stream as AudioStreamOggVorbis).loop = true
	_sparks = _build_sparks()
	_flash = _build_flash()
	_dust = _build_dust()
	_debris = _build_debris()
	for p: CPUParticles3D in [_sparks, _flash, _dust, _debris]:
		p.top_level = true # stays where the hit happened while the auto drives on
		add_child(p)
	SignalBus.player_impact.connect(_on_impact)
	SignalBus.player_scraping.connect(_on_scrape)

func _player(path: String, db: float) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	if ResourceLoader.exists(path):
		p.stream = load(path) as AudioStream
	p.volume_db = db
	p.unit_size = 6.0
	p.max_distance = 60.0
	add_child(p)
	return p

func _on_impact(info: Dictionary) -> void:
	var sev: float = float(info.get("severity", 0.3))
	var at: Vector3 = info.get("point", global_position)
	var n: Vector3 = info.get("normal", Vector3.UP)
	var p: AudioStreamPlayer3D = _hard if sev >= HARD_SEVERITY else _light
	if p.stream != null:
		p.global_position = at
		p.volume_db = lerpf(-12.0, 2.0, sev)
		p.pitch_scale = randf_range(0.9, 1.1)
		p.play()
	var kind: String = str(info.get("kind", ""))
	# Metal on concrete/metal throws sparks; every hit kicks up road dust.
	if kind != "prop" or sev > 0.3:
		_burst(_sparks, at + Vector3(0, 0.35, 0), n + Vector3(0, 0.5, 0), roundi(lerpf(8.0, 32.0, sev)))
		_burst(_flash, at + Vector3(0, 0.45, 0), n, 1)
	_burst(_dust, at + Vector3(0, 0.25, 0), n + Vector3(0, 0.8, 0), roundi(lerpf(3.0, 9.0, sev)))
	if sev >= 0.35:
		_burst(_debris, at + Vector3(0, 0.5, 0), n + Vector3(0, 1.0, 0), roundi(lerpf(4.0, 14.0, sev)))
	SignalBus.camera_shake.emit(lerpf(0.15, 1.0, sev))
	if sev >= HARD_SEVERITY and bool(GameState.settings.get("vibration", true)):
		Input.vibrate_handheld(roundi(lerpf(40.0, 160.0, sev)))

func _burst(e: CPUParticles3D, at: Vector3, dir: Vector3, amount: int) -> void:
	e.global_position = at
	e.direction = dir.normalized()
	e.amount = maxi(amount, 1)
	e.restart()

func _on_scrape(speed_mps: float, at: Vector3) -> void:
	_scrape_target = clampf(speed_mps / 8.0, 0.0, 1.0)
	if speed_mps > 0.0:
		_scrape.global_position = at
		if randf() < 0.3:
			_burst(_sparks, at + Vector3(0, 0.3, 0), Vector3(0, 0.6, 0), 6)

func _process(delta: float) -> void:
	_scrape_level = move_toward(_scrape_level, _scrape_target, delta * 6.0)
	if _scrape.stream == null:
		return
	if _scrape_level > 0.02:
		if not _scrape.playing:
			_scrape.play()
		_scrape.volume_db = lerpf(-24.0, -4.0, _scrape_level)
		_scrape.pitch_scale = lerpf(0.85, 1.25, _scrape_level)
	elif _scrape.playing:
		_scrape.stop()
	_scrape_target = move_toward(_scrape_target, 0.0, delta * 2.0) # decays if events stop

# --- Emitters -----------------------------------------------------------------------------

static func _tex(file: String) -> Texture2D:
	var path: String = FX_DIR + file
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if _soft_dot == null:
		# Soft round sprite: the fallback is a blurred dot, never a hard square.
		var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y: int in 32:
			for x: int in 32:
				var d: float = Vector2(x - 15.5, y - 15.5).length() / 16.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2))
		_soft_dot = ImageTexture.create_from_image(img)
	return _soft_dot

static func _mat(tex: Texture2D, additive: bool, billboard: bool = true) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
	return m

static func _emitter(name: String, lifetime: float, quad: Vector2, mat: Material) -> CPUParticles3D:
	var e: CPUParticles3D = CPUParticles3D.new()
	e.name = name
	e.emitting = false
	e.one_shot = true
	e.explosiveness = 0.95
	e.lifetime = lifetime
	e.local_coords = false
	var q: QuadMesh = QuadMesh.new()
	q.size = quad
	q.material = mat
	e.mesh = q
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return e

static func _fade(c0: Color, c1: Color) -> Gradient:
	var g: Gradient = Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	return g

## Hot streaks stretched along their velocity (align_y), white-yellow → orange → gone.
static func _build_sparks() -> CPUParticles3D:
	var e: CPUParticles3D = _emitter("Sparks", 0.5, Vector2(0.08, 0.6), _mat(_tex("spark_streak.png"), true, false))
	e.particle_flag_align_y = true
	e.amount = 24
	e.spread = 60.0
	e.initial_velocity_min = 4.0
	e.initial_velocity_max = 9.0
	e.gravity = Vector3(0, -9.8, 0)
	e.damping_min = 1.0
	e.damping_max = 3.0
	e.scale_amount_min = 0.6
	e.scale_amount_max = 1.2
	var c: Gradient = _fade(Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.3, 0.05, 0.0))
	c.add_point(0.4, Color(1.0, 0.7, 0.2, 0.95))
	e.color_ramp = c
	return e

## One bright starburst that pops for a tenth of a second at the contact point.
static func _build_flash() -> CPUParticles3D:
	var e: CPUParticles3D = _emitter("HitFlash", 0.16, Vector2(1.7, 1.7), _mat(_tex("scorch.png"), true))
	e.amount = 1
	e.spread = 0.0
	e.initial_velocity_min = 0.0
	e.initial_velocity_max = 0.0
	e.gravity = Vector3.ZERO
	e.angle_min = 0.0
	e.angle_max = 360.0
	var s: Curve = Curve.new()
	s.add_point(Vector2(0.0, 0.5))
	s.add_point(Vector2(0.3, 1.0))
	s.add_point(Vector2(1.0, 0.8))
	e.scale_amount_curve = s
	e.color_ramp = _fade(Color(1.0, 0.92, 0.7, 1.0), Color(1.0, 0.6, 0.3, 0.0))
	return e

## Road dust / bumper smoke: soft puffs that billow out, grow 3× and fade over ~1.4 s.
static func _build_dust() -> CPUParticles3D:
	var e: CPUParticles3D = _emitter("Dust", 1.5, Vector2(1.7, 1.7), _mat(_tex("smoke_b.png"), false))
	e.amount = 8
	e.explosiveness = 0.85
	e.spread = 70.0
	e.initial_velocity_min = 0.8
	e.initial_velocity_max = 2.4
	e.gravity = Vector3(0, 0.35, 0) # warm air lifts it a little
	e.damping_min = 1.5
	e.damping_max = 2.5
	e.angle_min = 0.0
	e.angle_max = 360.0
	e.angular_velocity_min = -40.0
	e.angular_velocity_max = 40.0
	e.scale_amount_min = 0.7
	e.scale_amount_max = 1.2
	var s: Curve = Curve.new()
	s.add_point(Vector2(0.0, 0.4))
	s.add_point(Vector2(1.0, 1.6))
	e.scale_amount_curve = s
	var c: Gradient = _fade(Color(0.78, 0.72, 0.62, 0.0), Color(0.7, 0.68, 0.64, 0.0))
	c.add_point(0.12, Color(0.78, 0.73, 0.64, 0.55))
	c.add_point(0.55, Color(0.72, 0.7, 0.66, 0.3))
	e.color_ramp = c
	return e

## Paint flakes and plastic chips that tumble and fall.
static func _build_debris() -> CPUParticles3D:
	var e: CPUParticles3D = _emitter("Debris", 0.9, Vector2(0.28, 0.28), _mat(_tex("dirt_a.png"), false))
	e.amount = 10
	e.spread = 55.0
	e.initial_velocity_min = 2.5
	e.initial_velocity_max = 5.0
	e.gravity = Vector3(0, -9.8, 0)
	e.angle_min = 0.0
	e.angle_max = 360.0
	e.angular_velocity_min = -360.0
	e.angular_velocity_max = 360.0
	e.scale_amount_min = 0.4
	e.scale_amount_max = 1.0
	e.color_ramp = _fade(Color(0.45, 0.42, 0.38, 1.0), Color(0.4, 0.38, 0.35, 0.0))
	return e
