class_name LoadingScreen
extends CanvasLayer
## Loading screen between the menu and the city. Loads the game scene on a background thread
## (ResourceLoader.load_threaded_request) with a real progress bar, then stays on top while the
## scene builds its first chunks and the first frames settle, then fades out. It lives on the
## tree root, so it survives the scene change. Start it with LoadingScreen.go(tree, path).

const AMBER: Color = Color(1.0, 0.72, 0.1)
const TIP_KEYS: Array[String] = ["TIP_1", "TIP_2", "TIP_3", "TIP_4", "TIP_5", "TIP_6"]
const TIP_SECONDS: float = 3.5
## Time to keep covering the city after it is in the tree (first chunks, shaders, traffic).
const SETTLE_SECONDS: float = 0.8
const FADE_SECONDS: float = 0.35
## Painted night-street art (tools/art/import_game_art.py, 1F). It carries its own logo, so the
## drawn backdrop and text title are hidden when it is present.
const ART_BG: String = "res://assets/ui/loading_bg.jpg"

enum Stage { LOADING, BUILDING, SETTLING, FADING }

var target: String = ""
var stage: Stage = Stage.LOADING
var _backdrop: ChennaiBackdrop
var _bar_bg: Panel
var _bar_fill: Panel
var _auto_icon: Label
var _status: Label
var _tip: Label
var _percent: Label
var _root: Control
var _art: TextureRect
var _stripes: Stripes
var _tip_card: PanelContainer

## Diagonal stripes scrolling across the progress fill (4D "progressStripes").
class Stripes:
	extends Control
	var offset: float = 0.0
	func _process(delta: float) -> void:
		offset = fmod(offset + delta * 60.0, 28.0)
		queue_redraw()
	func _draw() -> void:
		var x: float = -28.0 + offset
		while x < size.x + size.y:
			draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 12, 0), Vector2(x + 12 - size.y, size.y), Vector2(x - size.y, size.y)]),
				Color(1, 1, 1, 0.22))
			x += 28.0
var _band: ColorRect
var _rider: TextureRect
var _shown: float = 0.0
var _goal: float = 0.0
var _tip_index: int = 0
var _tip_timer: float = 0.0
var _stage_timer: float = 0.0
var _frames_waited: int = 0

static func go(tree: SceneTree, path: String) -> LoadingScreen:
	var ls: LoadingScreen = LoadingScreen.new()
	ls.name = "LoadingScreen"
	ls.target = path
	tree.root.add_child(ls)
	return ls

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_tip_index = randi() % TIP_KEYS.size()
	_tip.text = tr(TIP_KEYS[_tip_index])
	var err: Error = ResourceLoader.load_threaded_request(target, "PackedScene", true)
	if err != OK:
		# Fall back to a plain blocking load rather than leaving the player on this screen.
		stage = Stage.BUILDING

func _process(delta: float) -> void:
	_tip_timer += delta
	if _tip_timer >= TIP_SECONDS:
		_tip_timer = 0.0
		_tip_index = (_tip_index + 1) % TIP_KEYS.size()
		_tip.text = tr(TIP_KEYS[_tip_index])
	match stage:
		Stage.LOADING:
			var prog: Array = []
			var st: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(target, prog)
			if prog.size() > 0:
				_goal = 0.7 * float(prog[0])
			if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				stage = Stage.BUILDING
				_frames_waited = 0
		Stage.BUILDING:
			_goal = 0.8
			_status.text = tr("LOADING_STREETS")
			# Two frames so "building streets" is on screen before the blocking chunk build.
			_frames_waited += 1
			if _frames_waited >= 2:
				var packed: PackedScene = ResourceLoader.load_threaded_get(target) as PackedScene
				if packed == null:
					packed = load(target) as PackedScene
				get_tree().change_scene_to_packed(packed)
				stage = Stage.SETTLING
				_stage_timer = 0.0
		Stage.SETTLING:
			_stage_timer += delta
			_goal = lerpf(0.85, 1.0, clampf(_stage_timer / SETTLE_SECONDS, 0.0, 1.0))
			_status.text = tr("LOADING_READY")
			if _stage_timer >= SETTLE_SECONDS:
				stage = Stage.FADING
				_stage_timer = 0.0
		Stage.FADING:
			_stage_timer += delta
			_root.modulate.a = 1.0 - clampf(_stage_timer / FADE_SECONDS, 0.0, 1.0)
			if _stage_timer >= FADE_SECONDS:
				queue_free()
	_shown = move_toward(_shown, _goal, delta * 1.6)
	_update_bar()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP # swallow taps while loading
	_root.theme = UIKit.theme()
	add_child(_root)
	_backdrop = ChennaiBackdrop.new()
	_backdrop.dash_y = 0.86 # keep the dashes clear of the bar and the tip
	_root.add_child(_backdrop)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.25)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	# Two looks, picked at random: the painted night street (1F) or the drawn Marina sunset.
	if ResourceLoader.exists(ART_BG) and randf() < 0.6:
		_art = TextureRect.new()
		_art.texture = load(ART_BG) as Texture2D
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_art)
		_band = ColorRect.new()
		_band.color = Color(0.05, 0.02, 0.07, 0.62) # keeps the bar and tip readable over the art
		_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_band)
		_backdrop.visible = false
		shade.visible = false
	var title: Label = _label("NAMMA AUTO", 72, AMBER, 10)
	title.name = "Title"
	var tamil: Label = _label("நம்ம ஆட்டோ", 32, Color.WHITE, 6)
	tamil.name = "Tamil"
	_bar_bg = _panel(Color("120c16"), UIKit.PLUM)
	_bar_fill = _panel(UIKit.YELLOW, Color(0, 0, 0, 0))
	_bar_fill.clip_contents = true
	_stripes = Stripes.new()
	_stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill.add_child(_stripes)
	_auto_icon = Label.new() # kept for the layout code; the painted auto rides on top
	_auto_icon.visible = false
	_root.add_child(_auto_icon)
	_status = _label(tr("LOADING_CITY"), 24, UIKit.JASMINE, 6)
	_percent = _label("0%", 46, UIKit.YELLOW, 8)
	_tip_card = PanelContainer.new()
	_tip_card.add_theme_stylebox_override("panel", UIKit.card_box(Color(UIKit.DUSK, 0.92), 18))
	_tip_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tip_card)
	var tip_row: HBoxContainer = HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", 12)
	_tip_card.add_child(tip_row)
	tip_row.add_child(UIKit.reward_icon("star", 34))
	_tip = UIKit.label("", 19, UIKit.JASMINE)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(_tip)
	# The little auto bouncing along the bar (4C "autoBounce", 0.45 s).
	_rider = TextureRect.new()
	_rider.texture = load(TouchHUD.HUD_ATLAS) as Texture2D
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = _rider.texture
	at.region = TouchHUD.HUD_REGIONS["pin_player"] as Rect2
	_rider.texture = at
	_rider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rider.rotation = PI * 0.5 # the map pin faces up; turn it to drive along the bar
	_rider.size = Vector2(54, 54)
	_rider.pivot_offset = _rider.size * 0.5
	_rider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rider)
	var bounce: Tween = _rider.create_tween().set_loops()
	bounce.tween_property(_rider, "scale", Vector2(1.0, 1.08), 0.225).set_trans(Tween.TRANS_SINE)
	bounce.tween_property(_rider, "scale", Vector2.ONE, 0.225).set_trans(Tween.TRANS_SINE)
	if _art == null:
		UIKit.flicker(title, 2.5) # neon sign flicker on the drawn-skyline look (4C T. Nagar)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if _art != null:
		_art.position = Vector2.ZERO
		_art.size = vp
		_band.position = Vector2(0, vp.y * 0.7)
		_band.size = Vector2(vp.x, vp.y * 0.3)
	var title: Label = _root.get_node("Title") as Label
	title.visible = _art == null
	title.position = Vector2(0, vp.y * 0.12)
	title.size = Vector2(vp.x, 90)
	var tamil: Label = _root.get_node("Tamil") as Label
	tamil.visible = _art == null
	tamil.position = Vector2(0, vp.y * 0.12 + 88)
	tamil.size = Vector2(vp.x, 44)
	var bw: float = minf(760.0, vp.x * 0.66)
	bw = minf(900.0, vp.x * 0.74)
	_bar_bg.position = Vector2((vp.x - bw) * 0.5, vp.y * 0.78)
	_bar_bg.size = Vector2(bw, 30)
	_stripes.size = Vector2(bw, 30)
	_status.position = Vector2(_bar_bg.position.x, _bar_bg.position.y - 46)
	_status.size = Vector2(bw * 0.75, 36)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_percent.position = Vector2(_bar_bg.position.x + bw * 0.6, _bar_bg.position.y - 62)
	_percent.size = Vector2(bw * 0.4, 56)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tip_card.position = Vector2((vp.x - bw) * 0.5, vp.y * 0.78 + 46)
	_tip_card.custom_minimum_size = Vector2(bw, 0)
	_tip_card.size = Vector2(bw, 0)
	_update_bar()

func _update_bar() -> void:
	var fill: float = clampf(_shown, 0.0, 1.0)
	_bar_fill.position = _bar_bg.position + Vector2(3, 3)
	_bar_fill.size = Vector2(maxf(0.0, (_bar_bg.size.x - 6.0) * fill), _bar_bg.size.y - 6.0)
	_auto_icon.position = Vector2(_bar_fill.position.x + _bar_fill.size.x - 10.0, _bar_bg.position.y - 9.0)
	_auto_icon.size = Vector2(30, 40)
	if _rider != null:
		_rider.position = Vector2(_bar_fill.position.x + _bar_fill.size.x - 30.0, _bar_bg.position.y - 14.0)
	_percent.text = "%d%%" % roundi(fill * 100.0)
	_backdrop.road_scroll = fill * 4.0
	_backdrop.queue_redraw()

func _label(text: String, size: int, colour: Color, outline: int) -> Label:
	var l: Label = UIKit.label(text, size, colour, true, outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(l)
	return l

func _panel(bg: Color, border: Color) -> Panel:
	var p: Panel = Panel.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(4 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(15)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(p)
	return p
