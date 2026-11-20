class_name SavariVoice
extends Node
## Savari dialogue: picks one of ten lines for each moment and plays its voice (Nov 20 owner
## request: "10 variety of dialogues in English and Tamil … a passenger calling auto, saying the
## place to go, like T. Nagar ponum … voice dialogs for bargain features too").
##
## Text: SAV_* keys in translations/ui.csv; voice: assets/audio/voice/sav/<id>_<ta|en>.ogg. Both
## come from tools/voice/savari_lines.py (edit lines there). A rider speaks in one of four voices,
## chosen by the character at the kerb (voice_of); the elder calls the driver "தம்பி", the others
## "அண்ணா". A destination is voiced with 4 of its 10 phrasings per voice (dest_templates, the
## same rotation as the generator). The hero speaks his side of the bargain in his locked voice.
## Lines play one after another; their timing comes from the .ogg lengths, never from
## `finished` (the Dummy audio driver in tests never finishes). A missing file just stays silent.

const DIR: String = "res://assets/audio/voice/sav/"
const VOICES: Array[String] = ["man", "woman", "elder", "girl"]
const LINES_PER: int = 10
const DEST_PER_VOICE: int = 4
const GAP_S: float = 0.15
## Rider categories (SAV_<CAT>_NN) and the hero's (SAV_DRV_<CAT>_NN).
const RIDER_CATS: Array[String] = ["call", "open", "counter", "angry", "deal", "walk", "happy", "upset"]
const DRIVER_CATS: Array[String] = ["meter", "more", "high", "accept", "letgo"]
## Place ids, in the generator's order (their index rotates the destination phrasings).
const PLACES: Array[String] = ["tnagar", "mylapore_tank", "kapali", "lighthouse", "marina", "mount_road",
	"napier", "vivekananda", "lic", "gemini", "panagal", "near"]
## Destination names (manifest landmarks, stands, zones) -> the place a rider names.
const PLACE_OF: Dictionary = {
	"T. Nagar Usman Road": "tnagar",
	"Mylapore Temple Tank": "mylapore_tank", "Mylapore Tank Auto Stand": "mylapore_tank",
	"Mylapore Heritage Tank": "mylapore_tank",
	"Kapaleeshwarar Temple": "kapali",
	"Marina Lighthouse": "lighthouse", "Marina Lighthouse Auto Stand": "lighthouse",
	"Marina Beach & Kamarajar Salai": "marina",
	"Anna Salai (Mount Road)": "mount_road",
	"Napier Bridge": "napier",
	"Vivekananda House": "vivekananda",
	"LIC Building": "lic",
	"Gemini Flyover": "gemini",
	"Panagal Park": "panagal", "Panagal Park Auto Stand": "panagal",
}
## Character (people/*.glb id) -> rider voice. Riders without a character (tourist) speak as "man".
const VOICE_OF: Dictionary = {
	"young_man": "man", "man_casual": "man", "mixamo_ch22": "man",
	"old_man_veshti": "elder",
	"woman_saree_green": "woman", "woman_saree_maroon": "woman", "woman_saree_violet": "woman",
	"woman_saree_kanchi": "woman", "woman_coat": "woman",
	"girl_churidar": "girl", "girl_pavadai": "girl",
}

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## What was said last (tests read it): [{"id", "text", "path", "seconds"}].
var last_said: Array[Dictionary] = []
var _player: AudioStreamPlayer
var _call_player: AudioStreamPlayer3D
var _queue: Array[Dictionary] = []
var _left: float = 0.0
var _last_pick: Dictionary = {} # category key -> last index, so a line never repeats back to back


func _ready() -> void:
	rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.name = "Voice"
	add_child(_player)
	_call_player = AudioStreamPlayer3D.new()
	_call_player.name = "Call"
	_call_player.unit_size = 12.0
	_call_player.max_distance = 80.0
	add_child(_call_player)


static func voice_of(person_id: String) -> String:
	return str(VOICE_OF.get(person_id, "man"))


static func place_of(destination_name: String) -> String:
	return str(PLACE_OF.get(destination_name, "near"))


## The phrasings this voice speaks for this place (tools/voice/savari_lines.py dest_templates).
static func dest_templates(voice: String, place: String) -> Array[int]:
	var g: int = maxi(0, VOICES.find(voice))
	var p: int = maxi(0, PLACES.find(place))
	var out: Array[int] = []
	for j: int in DEST_PER_VOICE:
		out.append((g * 3 + j + p) % LINES_PER)
	return out


static func language() -> String:
	return "ta" if str(GameState.settings.get("language", "en")) == "ta" else "en"


## A rider line: {"id", "text", "path"}.
func rider_line(cat: String, voice: String) -> Dictionary:
	var i: int = _pick(cat + voice, range(LINES_PER))
	var key: String = "SAV_%s_%02d" % [cat.to_upper(), i + 1]
	return _line("sav_%s_%02d_%s" % [cat, i + 1, voice], _for_voice(tr(key), voice))


## The rider naming where to go.
func dest_line(place: String, voice: String) -> Dictionary:
	var choices: Array[int] = dest_templates(voice, place)
	var t: int = _pick("dest" + voice, choices)
	var text: String
	if place == "near":
		text = tr("SAV_NEAR_%02d" % (t + 1))
	else:
		text = tr("SAV_DEST_%02d" % (t + 1)) % tr("SAV_PLACE_%s" % place.to_upper())
		text = text.left(1).to_upper() + text.substr(1)
	return _line("sav_dest_%s_%02d_%s" % [place, t + 1, voice], _for_voice(text, voice))


## The hero's side of the bargain.
func driver_line(cat: String) -> Dictionary:
	var i: int = _pick("drv" + cat, range(LINES_PER))
	return _line("sav_drv_%s_%02d" % [cat, i + 1], tr("SAV_DRV_%s_%02d" % [cat.to_upper(), i + 1]))


## Plays lines one after another (after anything still playing). Returns their total seconds.
func say(lines: Array[Dictionary], interrupt: bool = false) -> float:
	if interrupt:
		stop()
	var total: float = 0.0
	for l: Dictionary in lines:
		_queue.append(l)
		total += float(l["seconds"]) + GAP_S
	last_said = lines.duplicate()
	if _left <= 0.0:
		_next()
	return total


## A rider shouting for the auto, heard from where they stand.
func call_out(line: Dictionary, at: Vector3) -> void:
	last_said = [line]
	var stream: AudioStream = _stream(str(line["path"]))
	if stream == null:
		return
	_call_player.global_position = at
	_call_player.stream = stream
	_call_player.play()


func stop() -> void:
	_queue.clear()
	_left = 0.0
	_player.stop()


func busy() -> bool:
	return _left > 0.0 or not _queue.is_empty()


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_left = 0.0
		return
	var l: Dictionary = _queue.pop_front()
	_left = float(l["seconds"]) + GAP_S
	var stream: AudioStream = _stream(str(l["path"]))
	if stream != null:
		_player.stream = stream
		_player.play()


func _line(id: String, text: String) -> Dictionary:
	var path: String = DIR + id + "_" + language() + ".ogg"
	var stream: AudioStream = _stream(path)
	return {"id": id, "text": text, "path": path, "seconds": stream.get_length() if stream != null else 0.0}


func _stream(path: String) -> AudioStream:
	return load(path) as AudioStream if ResourceLoader.exists(path) else null


func _pick(key: String, options: Array) -> int:
	var last: int = int(_last_pick.get(key, -1))
	var pool: Array = options.filter(func(o: Variant) -> bool: return int(o) != last)
	if pool.is_empty():
		pool = options
	var i: int = int(pool[rng.randi() % pool.size()])
	_last_pick[key] = i
	return i


## The elder rider is older than the driver: he calls him தம்பி (the voice says it too).
static func _for_voice(text: String, voice: String) -> String:
	return text.replace("அண்ணா", "தம்பி") if voice == "elder" else text
