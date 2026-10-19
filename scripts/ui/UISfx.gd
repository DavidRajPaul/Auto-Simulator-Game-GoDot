class_name UISfx
extends Node
## UI sounds (Kenney Interface Sounds, CC0): every Button click, plus fare paid, level up,
## goal done, deal accepted and "can't do that". Hooks any Button added to the tree, so menus
## don't need to know about it.

const SOUNDS: Dictionary = {
	"click": "res://assets/audio/ui/click.ogg",
	"coin": "res://assets/audio/ui/coin.ogg",
	"level_up": "res://assets/audio/ui/level_up.ogg",
	"goal": "res://assets/audio/ui/goal.ogg",
	"refused": "res://assets/audio/ui/refused.ogg",
	"select": "res://assets/audio/ui/select.ogg",
	"back": "res://assets/audio/ui/back.ogg",
}
const VOICES: int = 3

var last_played: String = ""
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # menus click while the game is paused
	for k: String in SOUNDS:
		if ResourceLoader.exists(SOUNDS[k]):
			_streams[k] = load(SOUNDS[k])
	for i: int in VOICES:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_voices.append(p)
	get_tree().node_added.connect(_on_node_added)
	for b: Node in get_tree().root.find_children("*", "Button", true, false):
		_hook(b as Button)
	SignalBus.ride_completed.connect(func(_b: Dictionary) -> void: play("coin"))
	SignalBus.driver_level_up.connect(func(_l: int, _t: String, _r: int, _u: String) -> void: play("level_up"))
	SignalBus.goal_completed.connect(func(_g: Dictionary) -> void: play("goal"))
	SignalBus.gear_change_refused.connect(func() -> void: play("refused"))
	SignalBus.haggle_resolved.connect(func(r: Dictionary) -> void: play("select" if bool(r["accepted"]) else "back"))

func play(kind: String) -> void:
	if not _streams.has(kind):
		return
	var p: AudioStreamPlayer = _voices[_next]
	_next = (_next + 1) % _voices.size()
	p.stream = _streams[kind]
	p.play()
	last_played = kind

func _on_node_added(n: Node) -> void:
	if n is Button:
		_hook(n as Button)

func _hook(b: Button) -> void:
	if not b.pressed.is_connected(_on_button):
		b.pressed.connect(_on_button)

func _on_button() -> void:
	play("click")
