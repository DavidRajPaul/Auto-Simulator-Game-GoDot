class_name CollisionFX
extends Node3D
## Impact feedback, the part top driving sims get right and we were missing: a crunch sized to
## the hit, a metal scrape while sliding along a wall, a burst of sparks at the contact point,
## a short camera shake and a phone buzz on hard hits. Reads SignalBus only.

const CRASH_HARD: String = "res://assets/audio/vehicle/crash_hard.ogg"
const CRASH_LIGHT: String = "res://assets/audio/vehicle/crash_light.ogg"
const SCRAPE: String = "res://assets/audio/vehicle/scrape_loop.ogg"
const HARD_SEVERITY: float = 0.45

var _hard: AudioStreamPlayer3D
var _light: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _sparks: CPUParticles3D
var _scrape_level: float = 0.0
var _scrape_target: float = 0.0

func _ready() -> void:
	_hard = _player(CRASH_HARD, 0.0)
	_light = _player(CRASH_LIGHT, -3.0)
	_scrape = _player(SCRAPE, -8.0)
	if _scrape.stream is AudioStreamOggVorbis:
		(_scrape.stream as AudioStreamOggVorbis).loop = true
	_sparks = _build_sparks()
	add_child(_sparks)
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
	var p: AudioStreamPlayer3D = _hard if sev >= HARD_SEVERITY else _light
	if p.stream != null:
		p.global_position = at
		p.volume_db = lerpf(-12.0, 2.0, sev)
		p.pitch_scale = randf_range(0.9, 1.1)
		p.play()
	if str(info.get("kind", "")) != "prop" or sev > 0.3:
		_sparks.global_position = at + Vector3(0, 0.3, 0)
		var n: Vector3 = info.get("normal", Vector3.UP)
		_sparks.direction = n + Vector3(0, 0.6, 0)
		_sparks.amount = clampi(roundi(lerpf(10.0, 40.0, sev)), 10, 40)
		_sparks.restart()
	SignalBus.camera_shake.emit(lerpf(0.15, 1.0, sev))
	if sev >= HARD_SEVERITY and bool(GameState.settings.get("vibration", true)):
		Input.vibrate_handheld(roundi(lerpf(40.0, 160.0, sev)))

func _on_scrape(speed_mps: float, at: Vector3) -> void:
	_scrape_target = clampf(speed_mps / 8.0, 0.0, 1.0)
	if speed_mps > 0.0:
		_scrape.global_position = at
		if randf() < 0.25:
			_sparks.global_position = at + Vector3(0, 0.25, 0)
			_sparks.amount = 8
			_sparks.restart()

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

static func _build_sparks() -> CPUParticles3D:
	var s: CPUParticles3D = CPUParticles3D.new()
	s.name = "Sparks"
	s.emitting = false
	s.one_shot = true
	s.explosiveness = 0.9
	s.amount = 24
	s.lifetime = 0.45
	s.spread = 55.0
	s.initial_velocity_min = 3.0
	s.initial_velocity_max = 7.5
	s.gravity = Vector3(0, -9.8, 0)
	s.scale_amount_min = 0.03
	s.scale_amount_max = 0.06
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(1, 1)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.75, 0.3)
	m.vertex_color_use_as_albedo = true
	q.material = m
	s.mesh = q
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6))
	g.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	s.color_ramp = g
	return s
