class_name VehicleAudio
extends Node3D
## Placeholder auto-rickshaw audio, synthesised once at load (no asset files, zero
## per-frame DSP cost): a single-cylinder 4-stroke "phat-phat" loop pitch-shifted by
## speed, a two-tone bulb "pom-pom" horn and a kick-start clunk.
## Phase 5 replaces the generated streams with CC0 recordings (Sonniss / Kenney).
## Driven only by SignalBus events.

const MIX_RATE: int = 22050
const IDLE_PITCH: float = 0.85
const TOP_PITCH: float = 2.6
const TOP_SPEED_KMH: float = 58.0
## Real recordings replace the synth when these files exist (see docs/ASSETS.md).
const ENGINE_FILE: String = "res://assets/audio/vehicle/engine_lpg_loop.ogg"
const HORN_FILE: String = "res://assets/audio/vehicle/horn_bulb.ogg"
## Musical air horn, equipped at horn tier 2 (unlocked at Driver Level 4). Falls back to the bulb.
const HORN_AIR_FILE: String = "res://assets/audio/vehicle/horn_air.ogg"
const AIR_HORN_TIER: int = 2
const KICK_FILE: String = "res://assets/audio/vehicle/kick_start.ogg"
const TICK_FILE: String = "res://assets/audio/vehicle/indicator_tick.ogg"
## Engine on fire (the flame stage of DamageFX): the engine is silent and this is heard instead.
const FIRE_FILE: String = "res://assets/audio/vehicle/fire_loop.ogg"
const IGNITE_FILE: String = "res://assets/audio/vehicle/fire_ignite.ogg"
const FIRE_VOLUME_DB: float = -5.0
const STEAM_FILE: String = "res://assets/audio/vehicle/steam_hiss.ogg"
const BODY_FILE: String = "res://assets/audio/vehicle/impact_body.ogg"
## Same threshold as the flames on screen (DamageFX stage 4 = FIRE_FROM and up, and the wreck).
const FIRE_STAGE: int = 4
const BURN_CHECK_S: float = 0.2

@export var engine_volume_db: float = -6.0
@export var horn_volume_db: float = -2.0

var _engine: AudioStreamPlayer3D
var _horn: AudioStreamPlayer3D
var _horn_air: AudioStreamPlayer3D
var _clunk: AudioStreamPlayer3D
var _tick: AudioStreamPlayer
var _tock: AudioStream
var _tick_stream: AudioStream
var _speed_kmh: float = 0.0
var _engine_running: bool = true
var _fire: AudioStreamPlayer3D
var _ignite: AudioStreamPlayer3D
var _steam: AudioStreamPlayer3D
var _thud: AudioStreamPlayer3D
var _burning: bool = false
var _burn_check_t: float = 0.0

func _ready() -> void:
	_engine = _make_player("Engine", stream_or(ENGINE_FILE, _build_engine_loop()), engine_volume_db)
	_horn = _make_player("Horn", stream_or(HORN_FILE, _build_horn()), horn_volume_db)
	_horn_air = _make_player("HornAir", stream_or(HORN_AIR_FILE, _horn.stream), horn_volume_db)
	_clunk = _make_player("KickClunk", stream_or(KICK_FILE, _build_clunk()), -4.0)
	_fire = _make_player("EngineFire", stream_or(FIRE_FILE, _build_fire_loop()), FIRE_VOLUME_DB)
	_ignite = _make_player("EngineIgnite", stream_or(IGNITE_FILE, _build_ignite()), -2.0)
	_steam = _make_player("SteamHiss", stream_or(STEAM_FILE, _build_ignite()), -6.0)
	_thud = _make_player("BodyThud", stream_or(BODY_FILE, _build_clunk()), -2.0)
	SignalBus.pedestrian_bumped.connect(func(p: Vector3, _v: Vector3) -> void:
		_thud.global_position = p
		_thud.play()
	)
	# Indicator relay: heard inside the cab, so a plain (non-positional) player.
	_tick_stream = stream_or(TICK_FILE, _build_tick(1800.0))
	_tock = _build_tick(1350.0) if not ResourceLoader.exists(TICK_FILE) else _tick_stream
	_tick = AudioStreamPlayer.new()
	_tick.name = "IndicatorTick"
	_tick.volume_db = -10.0
	add_child(_tick)
	SignalBus.indicator_blink.connect(func(d: int, lamp_on: bool) -> void:
		if d == 0:
			return
		_tick.stream = _tick_stream if lamp_on else _tock
		_tick.play())
	_engine.play()
	_apply_drivetrain(GameState.active_stats())
	SignalBus.vehicle_loadout_changed.connect(_apply_drivetrain)
	SignalBus.speed_updated.connect(_on_speed)
	SignalBus.horn_blasted.connect(func(_o: Vector3, _f: Vector3, _r: float, tier: int) -> void: _play_horn(tier))
	SignalBus.engine_stalled_in_water.connect(func(_p: Vector3) -> void: _set_engine(false))
	SignalBus.engine_restarted.connect(func() -> void: _set_engine(true))
	SignalBus.kick_start_attempt.connect(func(_r: float) -> void: _clunk.play())

func _play_horn(tier: int) -> void:
	(_horn_air if tier >= AIR_HORN_TIER else _horn).play()

func _process(delta: float) -> void:
	_burn_check_t -= delta
	if _burn_check_t <= 0.0:
		_burn_check_t = BURN_CHECK_S
		_set_burning(DamageFX.stage_for(GameState.damage_severity(), GameState.is_wrecked()) >= FIRE_STAGE)
	if not _engine_running:
		return
	var t: float = clampf(_speed_kmh / TOP_SPEED_KMH, 0.0, 1.0)
	var target_pitch: float = lerpf(IDLE_PITCH, TOP_PITCH, sqrt(t))
	if Input.is_action_pressed("accelerate"):
		target_pitch += 0.15 # throttle "blip"
	_engine.pitch_scale = lerpf(_engine.pitch_scale, target_pitch, 1.0 - exp(-8.0 * delta))

## EV autos get a quiet electric whine instead of the LPG putter.
func _apply_drivetrain(s: VehicleStats) -> void:
	var is_ev: bool = s.fuel_type == 2
	var loop_file: String = s.engine_loop if s.engine_loop != "" and ResourceLoader.exists(s.engine_loop) else ENGINE_FILE
	_engine.stream = _build_ev_whine() if is_ev else stream_or(loop_file, _build_engine_loop())
	_engine.volume_db = engine_volume_db - (8.0 if is_ev else 0.0)
	if _engine_running and not _burning:
		_engine.play()

func _build_ev_whine() -> AudioStreamWAV:
	var n: int = MIX_RATE / 2
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i: int in n:
		var t: float = float(i) / MIX_RATE
		samples[i] = 0.35 * sin(TAU * 180.0 * t) + 0.15 * sin(TAU * 360.0 * t) + 0.05 * sin(TAU * 1080.0 * t)
	return _to_wav(samples, true)

func _on_speed(kmh: float) -> void:
	_speed_kmh = kmh

func _set_engine(on: bool) -> void:
	_engine_running = on
	if on:
		_engine.pitch_scale = IDLE_PITCH
		if not _burning:
			_engine.play()
	else:
		_engine.stop()

## On fire the engine is dead: its sound stops and the fire roars in its place (and a whoomph
## when it catches). Back to normal when the damage is repaired below the flame stage.
func _set_burning(on: bool) -> void:
	if on == _burning:
		return
	_burning = on
	SignalBus.vehicle_burning.emit(on)
	if on:
		_engine.stop()
		_ignite.play()
		_fire.play()
	else:
		_fire.stop()
		_steam.play()
		if _engine_running:
			_engine.play()

func _make_player(player_name: String, stream: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.name = player_name
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 8.0
	p.max_distance = 80.0
	p.attenuation_filter_cutoff_hz = 20500.0 # no muffling; cheaper on mobile
	add_child(p)
	return p

# --- Synthesis (runs once) --------------------------------------------------

## 0.5 s loop holding exactly 5 firing pulses (10 Hz) so it loops seamlessly.
func _build_engine_loop() -> AudioStreamWAV:
	var n: int = MIX_RATE / 2
	var pulses: int = 5
	var period: int = n / pulses
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 198 # 198 cc
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i: int in n:
		var tp: float = float(i % period) / MIX_RATE # time since last firing
		var env: float = exp(-tp * 38.0)
		var thump: float = sin(TAU * 52.0 * tp) + 0.55 * sin(TAU * 104.0 * tp + 0.7) + 0.25 * sin(TAU * 260.0 * tp)
		var exhaust_noise: float = rng.randf_range(-1.0, 1.0) * exp(-tp * 90.0) * 0.45
		var hum: float = 0.07 * sin(TAU * 40.0 * float(i) / MIX_RATE)
		samples[i] = (thump * env * 0.6 + exhaust_noise + hum)
	return _to_wav(samples, true)

## Classic rubber-bulb "pom-pom": two short honks, slightly detuned square-ish tone.
func _build_horn() -> AudioStreamWAV:
	var honk_len: float = 0.16
	var gap: float = 0.07
	var total: int = int(MIX_RATE * (honk_len * 2.0 + gap))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(total)
	for i: int in total:
		var t: float = float(i) / MIX_RATE
		var in_first: bool = t < honk_len
		var in_second: bool = t > honk_len + gap
		if not in_first and not in_second:
			samples[i] = 0.0
			continue
		var lt: float = t if in_first else t - honk_len - gap
		var f: float = 410.0 if in_first else 395.0
		var env: float = minf(lt / 0.01, 1.0) * minf((honk_len - lt) / 0.03, 1.0)
		var tone: float = signf(sin(TAU * f * lt)) * 0.5 + sin(TAU * f * 1.5 * lt) * 0.3 + sin(TAU * f * 0.5 * lt) * 0.2
		samples[i] = tone * env * 0.55
	return _to_wav(samples, false)

## Use a real recording when it's been added to the project, else the synthesised fallback.
static func stream_or(path: String, fallback: AudioStream) -> AudioStream:
	if ResourceLoader.exists(path):
		var s: AudioStream = load(path) as AudioStream
		if s != null:
			if s is AudioStreamOggVorbis and path.contains("_loop"):
				(s as AudioStreamOggVorbis).loop = true
			return s
	return fallback

## Fire roaring under the bonnet: a low, swaying rumble with sharp crackling pops. One second, looped.
func _build_fire_loop() -> AudioStreamWAV:
	var n: int = MIX_RATE
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1138
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var rumble: float = 0.0
	for i: int in n:
		rumble += (rng.randf_range(-1.0, 1.0) - rumble) * 0.03 # one-pole low-pass: the roar
		var sway: float = 0.75 + 0.25 * sin(TAU * 3.0 * float(i) / n) # 3 cycles per loop: seamless
		samples[i] = rumble * 2.2 * sway
	for k: int in 14: # pops, each a short decaying burst
		var start: int = rng.randi() % n
		var amp: float = rng.randf_range(0.25, 0.7)
		for j: int in int(MIX_RATE * 0.02):
			samples[(start + j) % n] += amp * rng.randf_range(-1.0, 1.0) * exp(-float(j) / (MIX_RATE * 0.004))
	return _to_wav(samples, true)

## The catch: a noisy swell with a fast front, half a second.
func _build_ignite() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.6)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 451
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var lp: float = 0.0
	for i: int in n:
		var t: float = float(i) / MIX_RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
		samples[i] = lp * minf(t / 0.02, 1.0) * exp(-t * 5.0) * 0.9
	return _to_wav(samples, false)

## Indicator relay click: a 25 ms damped burst.
func _build_tick(freq: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.025)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i: int in n:
		var t: float = float(i) / MIX_RATE
		samples[i] = sin(TAU * freq * t) * exp(-t * 260.0) * 0.8
	return _to_wav(samples, false)

func _build_clunk() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.18)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i: int in n:
		var t: float = float(i) / MIX_RATE
		samples[i] = (sin(TAU * 70.0 * t) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.4) * exp(-t * 28.0)
	return _to_wav(samples, false)

func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
