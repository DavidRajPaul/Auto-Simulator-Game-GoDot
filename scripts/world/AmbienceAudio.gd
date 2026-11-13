class_name AmbienceAudio
extends Node
## Zone ambience: a city-traffic bed everywhere (real Indian road recording), Marina sea waves near the coast, market crowd in Mylapore / T. Nagar /
## Anna Salai, rain on the canopy during the monsoon. Loops fade with distance / weather.
## Nov 13 (owner: "add free ambient sounds of Chennai"): crows by day (the sound of every Chennai
## street), city birds at dawn, insects after dark, and one-shots on a slow random clock: a temple
## bell near a temple, a church bell near a church, street dogs at night, a cycle bell by day.
## Files are optional (fetched by the Fetch Assets workflow); missing ones are just silent.

const FILES: Dictionary = {
	"sea": "res://assets/audio/ambience/sea_waves_loop.ogg",
	"market": "res://assets/audio/ambience/market_loop.ogg",
	"rain": "res://assets/audio/ambience/rain_roof_loop.ogg",
	"city": "res://assets/audio/ambience/city_traffic_loop.ogg",
	"crows": "res://assets/audio/ambience/crows_loop.ogg",
	"birds": "res://assets/audio/ambience/birds_city_loop.ogg",
	"night": "res://assets/audio/ambience/night_insects_loop.ogg",
}
## One-shots: file, loudest dB, [min, max] seconds between plays while its condition holds.
const SHOTS: Dictionary = {
	"temple_bell": ["res://assets/audio/ambience/temple_bell.ogg", -9.0, 14.0, 34.0],
	"church_bell": ["res://assets/audio/ambience/church_bell.ogg", -12.0, 50.0, 110.0],
	"dogs": ["res://assets/audio/ambience/dogs_far.ogg", -16.0, 25.0, 70.0],
	"cycle_bell": ["res://assets/audio/ambience/cycle_bell.ogg", -17.0, 35.0, 90.0],
}
## A temple or church bell carries this far (m); it is at full level inside a third of it.
const BELL_REACH_M: float = 260.0
const DAWN_END_MIN: float = 510.0   # 8:30 am: the dawn chorus is over
const SHOT_VOICES: int = 2
const MARKET_ZONES: PackedStringArray = ["mylapore", "t_nagar", "anna_salai"]
const SEA_ZONE: String = "marina"
const SILENT_DB: float = -60.0
const FULL_DB: Dictionary = {"sea": -8.0, "market": -12.0, "rain": -6.0, "city": -15.0, "crows": -17.0, "birds": -18.0, "night": -20.0}
const FADE_PER_S: float = 0.6

@export var world_dir: String = "res://data/world"

var players: Dictionary = {} # kind -> AudioStreamPlayer
var _zones: Array[Dictionary] = []
var _player_pos: Vector3 = Vector3.ZERO
var _level: Dictionary = {"sea": 0.0, "market": 0.0, "rain": 0.0, "city": 0.0, "crows": 0.0, "birds": 0.0, "night": 0.0}
var shot_streams: Dictionary = {} # kind -> AudioStream
var last_shot: String = ""
var _shot_voices: Array[AudioStreamPlayer] = []
var _shot_wait: Dictionary = {} # kind -> seconds until it may play again
var _temples: PackedVector2Array = PackedVector2Array()
var _churches: PackedVector2Array = PackedVector2Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	for kind: String in FILES:
		if not ResourceLoader.exists(FILES[kind]):
			continue
		var stream: AudioStream = load(FILES[kind]) as AudioStream
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Ambience_" + kind
		p.stream = stream
		p.volume_db = SILENT_DB
		add_child(p)
		p.play()
		players[kind] = p
	for kind: String in SHOTS:
		var path: String = str((SHOTS[kind] as Array)[0])
		if ResourceLoader.exists(path):
			shot_streams[kind] = load(path) as AudioStream
		_shot_wait[kind] = _rng.randf_range(4.0, float((SHOTS[kind] as Array)[2]))
	# Pre-built voices: nothing is instantiated while driving.
	for i: int in SHOT_VOICES:
		var v: AudioStreamPlayer = AudioStreamPlayer.new()
		v.name = "AmbienceShot_%d" % i
		add_child(v)
		_shot_voices.append(v)
	var f: FileAccess = FileAccess.open(world_dir.path_join("manifest.json"), FileAccess.READ)
	if f != null:
		var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
		for z: Dictionary in m.get("zones", []):
			_zones.append({"id": str(z["id"]), "pos": Vector2(float(z["x"]), float(z["z"])), "r": float(z["r"])})
	# Temples and churches (tools/osm/classify_buildings.py writes them from the building types).
	var sf: FileAccess = FileAccess.open(world_dir.path_join("sound_spots.json"), FileAccess.READ)
	if sf != null:
		var spots: Dictionary = JSON.parse_string(sf.get_as_text()) as Dictionary
		for p: Array in spots.get("temples", []):
			_temples.append(Vector2(float(p[0]), float(p[1])))
		for p: Array in spots.get("churches", []):
			_churches.append(Vector2(float(p[0]), float(p[1])))
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player_pos = p)

## 0–1 loudness for each loop at the current spot.
func targets() -> Dictionary:
	var here: Vector2 = Vector2(_player_pos.x, _player_pos.z)
	var sea: float = 0.0
	var market: float = 0.0
	for z: Dictionary in _zones:
		var near: float = 1.0 - clampf((here.distance_to(z["pos"]) - float(z["r"]) * 0.5) / float(z["r"]), 0.0, 1.0)
		if str(z["id"]) == SEA_ZONE:
			sea = maxf(sea, near)
		elif MARKET_ZONES.has(str(z["id"])):
			market = maxf(market, near)
	var night: bool = GameState.is_night()
	var rain: bool = GameState.is_raining
	# The city traffic bed is everywhere, thinner on the beach front, at night and in heavy rain.
	var city: float = (1.0 - 0.5 * sea) * (0.4 if night else 1.0) * (0.6 if rain else 1.0)
	market *= (0.35 if night else 1.0) * (0.5 if rain else 1.0)
	# Crows own the day, loudest where the bazaar is not; birds only at dawn; insects after dark
	# away from the bazaars. Rain sends all three to shelter.
	var dry: float = 0.0 if rain else 1.0
	var dawn: float = clampf((DAWN_END_MIN - GameState.shift_minute) / 90.0, 0.0, 1.0)
	return {"sea": sea, "market": market, "rain": 1.0 if rain else 0.0, "city": city,
		"crows": dry * (0.0 if night else 1.0) * (1.0 - 0.6 * market) * (0.6 + 0.4 * dawn),
		"birds": dry * dawn * (0.0 if night else 1.0),
		"night": dry * (1.0 if night else 0.0) * (1.0 - 0.7 * market)}

## 0–1: how strongly a bell from the nearest of `spots` reaches the player.
func bell_level(spots: PackedVector2Array) -> float:
	var here: Vector2 = Vector2(_player_pos.x, _player_pos.z)
	var best: float = BELL_REACH_M
	for p: Vector2 in spots:
		best = minf(best, here.distance_to(p))
	return clampf((BELL_REACH_M - best) / (BELL_REACH_M * 0.67), 0.0, 1.0)

## 0–1 loudness each one-shot would play at here and now (0 = it stays quiet).
func shot_levels() -> Dictionary:
	var night: bool = GameState.is_night()
	var dry: float = 0.0 if GameState.is_raining else 1.0
	return {"temple_bell": bell_level(_temples) * (0.5 if night else 1.0),
		"church_bell": bell_level(_churches),
		"dogs": dry * (1.0 if night else 0.0),
		"cycle_bell": dry * (0.0 if night else 0.7)}

## Play one-shot `kind` at `level` on a free voice. Returns false when it cannot (no file, all voices busy).
func play_shot(kind: String, level: float) -> bool:
	if not shot_streams.has(kind) or level <= 0.01:
		return false
	for v: AudioStreamPlayer in _shot_voices:
		if v.playing:
			continue
		v.stream = shot_streams[kind]
		v.volume_db = lerpf(-34.0, float((SHOTS[kind] as Array)[1]), sqrt(level))
		v.pitch_scale = _rng.randf_range(0.94, 1.06)
		v.play()
		last_shot = kind
		return true
	return false

func _update_shots(delta: float) -> void:
	var levels: Dictionary = shot_levels()
	for kind: String in SHOTS:
		_shot_wait[kind] = float(_shot_wait[kind]) - delta
		if float(_shot_wait[kind]) > 0.0:
			continue
		var spec: Array = SHOTS[kind]
		_shot_wait[kind] = _rng.randf_range(float(spec[2]), float(spec[3]))
		play_shot(kind, float(levels[kind]))

func _process(delta: float) -> void:
	_update_shots(delta)
	var t: Dictionary = targets()
	for kind: String in players:
		_level[kind] = move_toward(float(_level[kind]), float(t[kind]), delta * FADE_PER_S)
		var lv: float = float(_level[kind])
		(players[kind] as AudioStreamPlayer).volume_db = SILENT_DB if lv < 0.01 else lerpf(-30.0, float(FULL_DB[kind]), sqrt(lv))
