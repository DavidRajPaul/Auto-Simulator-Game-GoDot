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

@export var engine_volume_db: float = -6.0
@export var horn_volume_db: float = -2.0

var _engine: AudioStreamPlayer3D
var _horn: AudioStreamPlayer3D
var _clunk: AudioStreamPlayer3D
var _speed_kmh: float = 0.0
var _engine_running: bool = true

func _ready() -> void:
	_engine = _make_player("Engine", _build_engine_loop(), engine_volume_db)
	_horn = _make_player("Horn", _build_horn(), horn_volume_db)
	_clunk = _make_player("KickClunk", _build_clunk(), -4.0)
	_engine.play()
	_apply_drivetrain(GameState.active_stats())
	SignalBus.vehicle_loadout_changed.connect(_apply_drivetrain)
	SignalBus.speed_updated.connect(_on_speed)
	SignalBus.horn_blasted.connect(func(_o: Vector3, _f: Vector3, _r: float, _t: int) -> void: _horn.play())
	SignalBus.engine_stalled_in_water.connect(func(_p: Vector3) -> void: _set_engine(false))
	SignalBus.engine_restarted.connect(func() -> void: _set_engine(true))
	SignalBus.kick_start_attempt.connect(func(_r: float) -> void: _clunk.play())

func _process(delta: float) -> void:
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
	_engine.stream = _build_ev_whine() if is_ev else _build_engine_loop()
	_engine.volume_db = engine_volume_db - (8.0 if is_ev else 0.0)
	if _engine_running:
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
		_engine.play()
	else:
		_engine.stop()

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
