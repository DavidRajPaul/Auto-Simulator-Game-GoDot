class_name SplashScreen
extends Control
## First scene after the engine boot splash. Godot's boot splash is a single static image
## (the engine can't animate it), so it is kept clean — no painted "Loading…" pill — and this
## scene takes over with the same art plus a *live* bar: real threaded-load progress of the
## main menu, a spinning gear, and pulsing dots. Then it fades into the menu.

const ART: String = "res://assets/icon/boot_splash.png"
const NEXT_SCENE: String = "res://scenes/main_menu.tscn"
const AMBER: Color = Color(1.0, 0.72, 0.1)
const DEEP: Color = Color(0.2, 0.06, 0.24)
## Short floor so the art isn't a flash on fast phones; the bar never waits on a fake timer.
const MIN_SECONDS: float = 1.0
const FADE_SECONDS: float = 0.3

var _t: float = 0.0
var _shown: float = 0.0
var _goal: float = 0.0
var _loaded: PackedScene
var _fading: float = -1.0
var _art: TextureRect
var _bar_bg: Panel
var _bar_fill: Panel
var _gear: Label
var _text: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.118, 0.098, 0.129)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_art = TextureRect.new()
	if ResourceLoader.exists(ART):
		_art.texture = load(ART) as Texture2D
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_art)
	_bar_bg = _panel(Color(DEEP, 0.85), AMBER, 3)
	_bar_fill = _panel(AMBER, Color(0, 0, 0, 0), 0)
	_text = _label("LOADING", 26)
	_gear = _label("⚙", 56)
	_gear.pivot_offset = Vector2(24, 30)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if ResourceLoader.load_threaded_request(NEXT_SCENE, "PackedScene", false) != OK:
		_loaded = load(NEXT_SCENE) as PackedScene

func _process(delta: float) -> void:
	_t += delta
	if _loaded == null:
		var prog: Array = []
		var st: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(NEXT_SCENE, prog)
		if prog.size() > 0:
			_goal = float(prog[0]) * 0.95
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_loaded = ResourceLoader.load_threaded_get(NEXT_SCENE) as PackedScene
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loaded = load(NEXT_SCENE) as PackedScene
	else:
		_goal = 1.0
	# Always moving: eases toward real progress, plus a slow creep so it never looks frozen.
	_shown = move_toward(_shown, maxf(_goal, minf(_shown + delta * 0.15, 0.9)), delta * 1.8)
	_gear.rotation = _t * 4.0
	_text.text = "LOADING" + ".".repeat(int(_t * 3.0) % 4)
	_update_bar()
	if _loaded != null and _shown >= 0.999 and _t >= MIN_SECONDS and _fading < 0.0:
		_fading = 0.0
	if _fading >= 0.0:
		_fading += delta
		modulate.a = 1.0 - clampf(_fading / FADE_SECONDS, 0.0, 1.0)
		if _fading >= FADE_SECONDS:
			get_tree().change_scene_to_packed(_loaded)
			set_process(false)

## Same spot as the pill in the art, so the hand-off from the boot splash is seamless.
func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(440.0, vp.x * 0.4)
	_bar_bg.size = Vector2(w, 40)
	_bar_bg.position = Vector2((vp.x - w) * 0.5, vp.y * 0.915 - 20.0)
	_gear.position = _bar_bg.position + Vector2(-34, -10)
	_gear.size = Vector2(48, 60)
	_text.position = _bar_bg.position
	_text.size = _bar_bg.size
	_update_bar()

func _update_bar() -> void:
	var f: float = clampf(_shown, 0.0, 1.0)
	_bar_fill.position = _bar_bg.position + Vector2(4, 4)
	_bar_fill.size = Vector2(maxf(0.0, (_bar_bg.size.x - 8.0) * f), _bar_bg.size.y - 8.0)
	_bar_fill.visible = f > 0.02

func progress() -> float:
	return _shown

func _label(text: String, size: int) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", DEEP)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _panel(bg: Color, border: Color, bw: int) -> Panel:
	var p: Panel = Panel.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(20)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p
