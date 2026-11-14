class_name Thunderstorm
extends Node3D
## Thunder and lightning (Nov 14, owner: "realistic sounds, the environment light must obey the
## light from the lightning, sounds heard from low to high"). docs/CHENNAI_THUNDERSTORMS.md.
##
## A storm runs while GameState.is_thunderstorm(): it builds, passes closest in the middle of
## today's rain and moves on (GameState.rain_progress()), from a bearing and closest approach
## picked per day. Each strike is either cloud-to-ground (a visible bolt) or inside the cloud
## (only the cloud deck lights up), at a real distance from the player, and that distance drives
## everything, as it does outdoors:
##   light  - a few return strokes, each a sharp peak that dies in ~70 ms, flicker between them.
##            The scene is lit through ONE extra shadowless DirectionalLight3D from the strike (on
##            only while it flashes), the environment's ambient and fog light energies, and the
##            sky shader's `flash` (the deck glows, brightest toward the strike). Brightness falls
##            with distance; the sky glow falls slower, so far storms flicker on the horizon.
##   sound  - real thunderclap recordings (BigSoundBank, CC0) arrive distance / 343 m/s later.
##            A close strike is a sharp crack and a loud boom, a far one a low, long rumble:
##            the clip pool, the level (-4.5 dB per doubling of distance), a low-pass that
##            drops with distance (air takes the highs first), a slightly lower pitch and a pan
##            to the side the strike is on are all set from the distance.
## Nothing is instanced while driving: the light, the bolt mesh and THUNDER_VOICES players on
## their own audio buses are built once in _ready.

const SPEED_OF_SOUND_MPS: float = 343.0
const THUNDER_VOICES: int = 3
## Recordings (tools/assets/fetch_assets.py) sorted into pools by tools/assets/analyse_thunder.py
## (thunder.json): "close" ones open with a real crack, "mid" are single booms, "far" long rolls.
## Each also has a start offset, so the thunder begins as the sound reaches the player.
const DIR: String = "res://assets/audio/weather/"
const POOLS: PackedStringArray = ["close", "mid", "far"]
const CLOSE_M: float = 1500.0
const FAR_M: float = 5000.0
## Level at REF_M and how fast it falls: thunder is a long line source, so it fades slower than
## a point (-4.5 dB, not -6 dB, per doubling).
const REF_M: float = 250.0
const LOUDEST_DB: float = -1.0
const DB_PER_DOUBLING: float = 4.5
const QUIETEST_DB: float = -30.0
const CUTOFF_NEAR_HZ: float = 16000.0
const CUTOFF_MIN_HZ: float = 320.0

## Storm path: closest approach per day between these (km); the storm starts / ends this far.
const CLOSEST_KM: Vector2 = Vector2(0.4, 3.5)
const EDGE_KM: float = 10.0
## Seconds between strikes at the storm's peak and at its edges (scaled by a random 0.6-1.4).
const GAP_PEAK_S: float = 8.0
const GAP_EDGE_S: float = 28.0
const GROUND_SHARE: float = 0.35
const MIN_STRIKE_M: float = 160.0

## Light. Each stroke decays with STROKE_TAU_S; brightness at distance d is 1 / (1 + (d / LIGHT_HALF_M)^1.3).
const STROKE_TAU_S: float = 0.07
const CLOUD_TAU_S: float = 0.12
const LIGHT_HALF_M: float = 900.0
const SKY_HALF_M: float = 2600.0
const LIGHT_MAX_ENERGY: float = 2.6
const AMBIENT_GAIN: float = 3.0
const FOG_GAIN: float = 2.2
const SKY_GAIN: float = 1.4
const CLOUD_FLASH_SCALE: float = 0.5
const FLASH_COLOUR: Color = Color(0.8, 0.85, 1.0)
const CLOUD_BASE_M: float = 1100.0
## The camera sees 400 m: a bolt further out is drawn at this distance, scaled down so it covers
## the same angle as the real one (buildings in front still hide it).
const BOLT_DRAW_M: float = 330.0
const BOLT_MAX_M: float = 9000.0
## Core width (m) as seen at draw distance: ~2-3 px on a phone.
const BOLT_CORE_M: float = 0.7

@export var environment_path: NodePath

var light: DirectionalLight3D
var bolt: MeshInstance3D
var voices: Array[AudioStreamPlayer] = []
## Strike under way: start time, distance, flash direction (towards the strike), kind.
var strokes: Array[Vector2] = [] # (start time s, peak 0..1)
var flash_distance_m: float = INF
var flash_to_ground: bool = false
var flash_dir: Vector3 = Vector3.RIGHT
## Thunder on its way: [due time s, distance m, bearing rad].
var pending: Array[Array] = []
## Last thunder played (tests): file, db, cutoff_hz, pan, distance_m.
var last_thunder: Dictionary = {}
var strike_count: int = 0

var _env: Environment
var _base_ambient: float = 1.0
var _base_fog: float = 1.0
var _bolt_mesh: ArrayMesh
var _bolt_mat: StandardMaterial3D
var _streams: Dictionary = {} # name -> AudioStream
var _starts: Dictionary = {} # name -> seconds into the file
var pools: Dictionary = {"close": PackedStringArray(), "mid": PackedStringArray(), "far": PackedStringArray()}
var _buses: PackedInt32Array = PackedInt32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _t: float = 0.0
var _next_strike: float = -1.0
var _was_storm: bool = false
var _lit_last_frame: bool = false
var _player: Vector3 = Vector3.ZERO
var _storm_bearing: float = 0.0
var _closest_km: float = 1.5
var _storm_day: int = -1

func _ready() -> void:
	_rng.seed = 140711
	var we: WorldEnvironment = get_node_or_null(environment_path) as WorldEnvironment
	if we != null:
		_env = we.environment
		_base_ambient = _env.ambient_light_energy
		_base_fog = _env.fog_light_energy
	light = DirectionalLight3D.new()
	light.name = "LightningLight"
	light.shadow_enabled = false
	light.light_color = FLASH_COLOUR
	light.light_energy = 0.0
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	light.visible = false
	add_child(light)
	_bolt_mesh = ArrayMesh.new()
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_mat.vertex_color_use_as_albedo = true
	_bolt_mat.disable_fog = true
	_bolt_mat.no_depth_test = false
	bolt = MeshInstance3D.new()
	bolt.name = "Bolt"
	bolt.mesh = _bolt_mesh
	bolt.material_override = _bolt_mat
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.visible = false
	bolt.top_level = true
	add_child(bolt)
	_load_recordings()
	for i: int in THUNDER_VOICES:
		var bus: int = _make_bus("Thunder%d" % i)
		_buses.append(bus)
		var v: AudioStreamPlayer = AudioStreamPlayer.new()
		v.name = "Thunder_%d" % i
		v.bus = AudioServer.get_bus_name(bus)
		add_child(v)
		voices.append(v)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _load_recordings() -> void:
	var f: FileAccess = FileAccess.open(DIR + "thunder.json", FileAccess.READ)
	if f == null:
		return
	var files: Dictionary = (JSON.parse_string(f.get_as_text()) as Dictionary).get("files", {})
	for pool: String in POOLS:
		# Packed arrays come out of a Dictionary as copies: fill a local one, then store it.
		var names: PackedStringArray = PackedStringArray()
		for n: String in files:
			var info: Dictionary = files[n]
			var path: String = DIR + n + ".ogg"
			if str(info.get("pool", "")) != pool or not ResourceLoader.exists(path):
				continue
			_streams[n] = load(path) as AudioStream
			_starts[n] = float(info.get("start", 0.0))
			names.append(n)
		names.sort()
		pools[pool] = names

## One bus per voice so each thunder gets its own distance filter and pan: low-pass, panner and a
## short city reverb (the roll off buildings), then Master.
func _make_bus(bus_name: String) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	var lp: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
	lp.cutoff_hz = CUTOFF_NEAR_HZ
	lp.db = AudioEffectFilter.FILTER_12DB
	AudioServer.add_bus_effect(idx, lp, 0)
	AudioServer.add_bus_effect(idx, AudioEffectPanner.new(), 1)
	var rv: AudioEffectReverb = AudioEffectReverb.new()
	rv.room_size = 0.75
	rv.damping = 0.6
	rv.wet = 0.12
	rv.dry = 1.0
	AudioServer.add_bus_effect(idx, rv, 2)
	return idx

# --- Distance rules (static: tests check them) --------------------------------------------------

static func thunder_db(distance_m: float) -> float:
	var doublings: float = log(maxf(distance_m, 1.0) / REF_M) / log(2.0)
	return clampf(LOUDEST_DB - DB_PER_DOUBLING * doublings, QUIETEST_DB, LOUDEST_DB)

## Air absorbs high frequencies over distance: a strike next door cracks, a far one only rumbles.
static func thunder_cutoff_hz(distance_m: float) -> float:
	return clampf(CUTOFF_NEAR_HZ * pow(maxf(distance_m, REF_M) / REF_M, -0.95), CUTOFF_MIN_HZ, CUTOFF_NEAR_HZ)

static func light_falloff(distance_m: float) -> float:
	return 1.0 / (1.0 + pow(distance_m / LIGHT_HALF_M, 1.3))

static func sky_falloff(distance_m: float) -> float:
	return 1.0 / (1.0 + distance_m / SKY_HALF_M)

static func pool_for(distance_m: float) -> String:
	if distance_m < CLOSE_M:
		return "close"
	return "mid" if distance_m < FAR_M else "far"

## Recordings for a strike this far: its own pool, else the nearest pool that has any.
func files_for(distance_m: float) -> PackedStringArray:
	var want: int = POOLS.find(pool_for(distance_m))
	for step: int in POOLS.size():
		for p: int in [want - step, want + step]:
			if p >= 0 and p < POOLS.size() and not (pools[POOLS[p]] as PackedStringArray).is_empty():
				return pools[POOLS[p]]
	return PackedStringArray()

# --- Storm ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	var storm: bool = GameState.is_thunderstorm()
	if storm:
		if _storm_day != GameState.day:
			_new_storm_day()
		if not _was_storm or _next_strike < 0.0:
			_next_strike = _t + _rng.randf_range(3.0, 8.0)
		elif _t >= _next_strike:
			_auto_strike()
	else:
		_next_strike = -1.0
	_was_storm = storm
	_play_due_thunder()
	_apply_flash()

## Today's storm: which way it lies and how close it comes (a hash of the day).
func _new_storm_day() -> void:
	_storm_day = GameState.day
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash(GameState.day * 6151 + 3)
	_storm_bearing = r.randf_range(0.0, TAU)
	_closest_km = r.randf_range(CLOSEST_KM.x, CLOSEST_KM.y)

## 0 at the storm's edges, 1 when it is overhead (the middle of today's rain).
func storm_peak() -> float:
	return pow(sin(PI * GameState.rain_progress()), 1.3)

func storm_centre_m() -> float:
	return lerpf(EDGE_KM, _closest_km, storm_peak()) * 1000.0

func _auto_strike() -> void:
	var peak: float = storm_peak()
	var d: float = maxf(MIN_STRIKE_M, storm_centre_m() * _rng.randf_range(0.55, 1.45))
	var bearing: float = _storm_bearing + _rng.randf_range(-0.9, 0.9)
	strike(d, bearing, _rng.randf() < GROUND_SHARE)
	_next_strike = _t + lerpf(GAP_EDGE_S, GAP_PEAK_S, peak) * _rng.randf_range(0.6, 1.4)

## A strike `distance_m` from the player on `bearing` (radians from +X towards +Z). Public so
## tests and shots can call one.
func strike(distance_m: float, bearing: float, to_ground: bool) -> void:
	strike_count += 1
	var flat: Vector3 = Vector3(cos(bearing), 0.0, sin(bearing))
	var at: Vector3 = _player + flat * distance_m
	flash_distance_m = distance_m
	flash_to_ground = to_ground
	# The light comes from the channel / the lit cloud: high up when close, low when far.
	var height: float = CLOUD_BASE_M * (0.45 if to_ground else 1.2)
	flash_dir = (flat * distance_m + Vector3.UP * height).normalized()
	strokes.clear()
	var t0: float = _t
	if to_ground:
		# A faint stepped leader, then 1-4 return strokes 40-120 ms apart (the flicker).
		strokes.append(Vector2(t0, 0.25))
		var t: float = t0 + 0.03
		var n: int = 1 + _rng.randi_range(0, 3)
		for i: int in n:
			strokes.append(Vector2(t, 1.0 if i == 0 else _rng.randf_range(0.55, 0.9)))
			t += _rng.randf_range(0.04, 0.12)
		if distance_m < BOLT_MAX_M:
			_build_bolt(flat, distance_m)
	else:
		# Inside the cloud: softer, slower flickers spread over up to half a second.
		var t: float = t0
		for i: int in 1 + _rng.randi_range(0, 2):
			strokes.append(Vector2(t, _rng.randf_range(0.5, 1.0)))
			t += _rng.randf_range(0.08, 0.22)
	pending.append([_t + distance_m / SPEED_OF_SOUND_MPS, distance_m, bearing])
	SignalBus.lightning_struck.emit(at, distance_m, to_ground)

## Flash 0..1 before distance (sum of the strokes' decaying peaks).
func flash_envelope() -> float:
	var e: float = 0.0
	var tau: float = STROKE_TAU_S if flash_to_ground else CLOUD_TAU_S
	for s: Vector2 in strokes:
		if _t >= s.x:
			e += s.y * exp(-(_t - s.x) / tau)
	return minf(e, 1.3)

## How brightly the strike lights the street right now (0 = no flash).
func flash_brightness() -> float:
	if strokes.is_empty():
		return 0.0
	return flash_envelope() * light_falloff(flash_distance_m) * (1.0 if flash_to_ground else CLOUD_FLASH_SCALE)

func _apply_flash() -> void:
	var env: float = flash_envelope() if not strokes.is_empty() else 0.0
	if env < 0.002:
		if not strokes.is_empty() and _t - strokes[strokes.size() - 1].x > 1.0:
			strokes.clear()
		if _lit_last_frame:
			_set_light(0.0, 0.0)
			bolt.visible = false
			_lit_last_frame = false
		return
	var ground: float = flash_brightness()
	var sky: float = env * sky_falloff(flash_distance_m)
	_set_light(ground, sky)
	bolt.visible = flash_to_ground and flash_distance_m < BOLT_MAX_M and env > 0.05
	_bolt_mat.albedo_color = Color(1.0, 1.0, 1.0) * clampf(env * 1.6, 0.0, 2.0)
	_lit_last_frame = true

func _set_light(ground: float, sky: float) -> void:
	light.visible = ground > 0.001
	light.light_energy = ground * LIGHT_MAX_ENERGY
	if light.visible:
		light.global_transform = Transform3D(Basis.looking_at(-flash_dir, Vector3.UP if absf(flash_dir.y) < 0.99 else Vector3.FORWARD), Vector3.ZERO)
	if _env != null:
		_env.ambient_light_energy = _base_ambient * (1.0 + ground * AMBIENT_GAIN)
		_env.fog_light_energy = _base_fog * (1.0 + ground * FOG_GAIN)
		var sm: ShaderMaterial = _env.sky.sky_material as ShaderMaterial if _env.sky != null else null
		if sm != null:
			sm.set_shader_parameter("flash", sky * SKY_GAIN)
			sm.set_shader_parameter("flash_dir", flash_dir)
			sm.set_shader_parameter("flash_colour", FLASH_COLOUR)

# --- Thunder -------------------------------------------------------------------------------------

func _play_due_thunder() -> void:
	var i: int = 0
	while i < pending.size():
		var p: Array = pending[i]
		if _t >= float(p[0]):
			_play_thunder(float(p[1]), float(p[2]))
			pending.remove_at(i)
		else:
			i += 1

func _play_thunder(distance_m: float, bearing: float) -> void:
	var have: PackedStringArray = files_for(distance_m)
	var pan: float = _pan_for(bearing, distance_m)
	last_thunder = {"file": "", "db": thunder_db(distance_m), "cutoff_hz": thunder_cutoff_hz(distance_m), "pan": pan, "distance_m": distance_m}
	if have.is_empty():
		return
	var pick: String = have[_rng.randi_range(0, have.size() - 1)]
	last_thunder["file"] = pick
	# A free voice, else the one that has played longest (old rumble tails give way).
	var vi: int = 0
	var oldest: float = -1.0
	for k: int in voices.size():
		if not voices[k].playing:
			vi = k
			oldest = INF
			break
		if voices[k].get_playback_position() > oldest:
			oldest = voices[k].get_playback_position()
			vi = k
	var bus: int = _buses[vi]
	(AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter).cutoff_hz = thunder_cutoff_hz(distance_m)
	(AudioServer.get_bus_effect(bus, 1) as AudioEffectPanner).pan = pan
	var v: AudioStreamPlayer = voices[vi]
	v.stream = _streams[pick]
	v.volume_db = thunder_db(distance_m)
	# Far thunder sounds a touch lower and slower.
	v.pitch_scale = lerpf(1.0, 0.88, clampf(distance_m / 10000.0, 0.0, 1.0)) * _rng.randf_range(0.96, 1.04)
	v.play(float(_starts.get(pick, 0.0)))

## -1 left .. 1 right, as heard facing where the camera looks; close strikes pan harder.
func _pan_for(bearing: float, distance_m: float) -> float:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 0.0
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return 0.0
	var side: float = right.normalized().dot(Vector3(cos(bearing), 0.0, sin(bearing)))
	return side * lerpf(0.75, 0.35, clampf(distance_m / 8000.0, 0.0, 1.0))

# --- Bolt ----------------------------------------------------------------------------------------

## A branching channel from the cloud base to the ground, as two ribbons per segment: a white
## core and a wide faint blue glow. Rebuilt once per ground strike (not per frame).
func _build_bolt(flat: Vector3, distance_m: float) -> void:
	var draw_m: float = minf(distance_m, BOLT_DRAW_M)
	var k: float = draw_m / distance_m
	var main: PackedVector2Array = _channel(Vector2(_rng.randf_range(-80.0, 80.0), CLOUD_BASE_M), Vector2(0.0, 0.0), 7, 0.22)
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	# Widths are set for what the eye sees at draw distance (the node is scaled by k), so a far
	# bolt stays a few pixels wide instead of vanishing below one.
	var core: float = BOLT_CORE_M / k
	_ribbon(verts, cols, main, core * 5.0, Color(0.45, 0.55, 1.0, 0.22))
	_ribbon(verts, cols, main, core, Color(1.0, 1.0, 1.0, 1.0))
	for b: int in _rng.randi_range(2, 4):
		var from: Vector2 = main[_rng.randi_range(main.size() / 8, main.size() / 2)]
		var drop: float = from.y * _rng.randf_range(0.25, 0.5)
		var to: Vector2 = from + Vector2(_rng.randf_range(-0.6, 0.6) * drop, -drop)
		var br: PackedVector2Array = _channel(from, to, 5, 0.3)
		_ribbon(verts, cols, br, core * 3.0, Color(0.45, 0.55, 1.0, 0.12))
		_ribbon(verts, cols, br, core * 0.55, Color(0.9, 0.92, 1.0, 0.7))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	_bolt_mesh.clear_surfaces()
	_bolt_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Stand it on the ground at draw distance, flat side to the player, scaled to the real angle.
	var base: Vector3 = _player + flat * draw_m
	base.y = 0.0
	var facing: Basis = Basis.looking_at(flat, Vector3.UP)
	bolt.global_transform = Transform3D(facing.scaled(Vector3(k, k, k)), base)

## Midpoint displacement: a jagged path from `a` to `b` in the bolt's plane (x across, y up).
func _channel(a: Vector2, b: Vector2, levels: int, rough: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array([a, b])
	for l: int in levels:
		var nxt: PackedVector2Array = PackedVector2Array()
		for i: int in pts.size() - 1:
			var p: Vector2 = pts[i]
			var q: Vector2 = pts[i + 1]
			nxt.append(p)
			var len: float = p.distance_to(q)
			nxt.append((p + q) * 0.5 + Vector2(_rng.randf_range(-1.0, 1.0) * len * rough, _rng.randf_range(-0.2, 0.2) * len * rough))
		nxt.append(pts[pts.size() - 1])
		pts = nxt
	return pts

func _ribbon(verts: PackedVector3Array, cols: PackedColorArray, pts: PackedVector2Array, width: float, c: Color) -> void:
	for i: int in pts.size() - 1:
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		var side: Vector2 = (q - p).orthogonal().normalized() * width * 0.5
		var a: Vector3 = Vector3(p.x - side.x, p.y - side.y, 0.0)
		var b: Vector3 = Vector3(p.x + side.x, p.y + side.y, 0.0)
		var cc: Vector3 = Vector3(q.x + side.x, q.y + side.y, 0.0)
		var d: Vector3 = Vector3(q.x - side.x, q.y - side.y, 0.0)
		verts.append_array(PackedVector3Array([a, b, cc, a, cc, d]))
		for j: int in 6:
			cols.append(c)
