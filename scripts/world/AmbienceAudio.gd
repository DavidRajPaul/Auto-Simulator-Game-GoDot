class_name AmbienceAudio
extends Node
## Zone ambience: Marina sea waves near the coast, market crowd in Mylapore / T. Nagar /
## Anna Salai, rain on the canopy during the monsoon. Loops fade with distance / weather.
## Files are optional (fetched by the Fetch Assets workflow); missing ones are just silent.

const FILES: Dictionary = {
	"sea": "res://assets/audio/ambience/sea_waves_loop.ogg",
	"market": "res://assets/audio/ambience/market_loop.ogg",
	"rain": "res://assets/audio/ambience/rain_roof_loop.ogg",
}
const MARKET_ZONES: PackedStringArray = ["mylapore", "t_nagar", "anna_salai"]
const SEA_ZONE: String = "marina"
const SILENT_DB: float = -60.0
const FULL_DB: Dictionary = {"sea": -8.0, "market": -12.0, "rain": -6.0}
const FADE_PER_S: float = 0.6

@export var world_dir: String = "res://data/world"

var players: Dictionary = {} # kind -> AudioStreamPlayer
var _zones: Array[Dictionary] = []
var _player_pos: Vector3 = Vector3.ZERO
var _level: Dictionary = {"sea": 0.0, "market": 0.0, "rain": 0.0}

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
	var f: FileAccess = FileAccess.open(world_dir.path_join("manifest.json"), FileAccess.READ)
	if f != null:
		var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
		for z: Dictionary in m.get("zones", []):
			_zones.append({"id": str(z["id"]), "pos": Vector2(float(z["x"]), float(z["z"])), "r": float(z["r"])})
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
	return {"sea": sea, "market": market * (0.35 if night else 1.0) * (0.5 if GameState.is_raining else 1.0),
		"rain": 1.0 if GameState.is_raining else 0.0}

func _process(delta: float) -> void:
	var t: Dictionary = targets()
	for kind: String in players:
		_level[kind] = move_toward(float(_level[kind]), float(t[kind]), delta * FADE_PER_S)
		var lv: float = float(_level[kind])
		(players[kind] as AudioStreamPlayer).volume_db = SILENT_DB if lv < 0.01 else lerpf(-30.0, float(FULL_DB[kind]), sqrt(lv))
