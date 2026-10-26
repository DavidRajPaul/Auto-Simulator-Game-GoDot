class_name NavBanner
extends PanelContainer
## Google-Maps-style turn prompt: big arrow, distance to the turn, the street you turn onto
## (English + Tamil from OSM). Fed by SignalBus.nav_instruction (RouteLine). Hidden with no route.

const GREEN: Color = Color(0.06, 0.45, 0.25, 0.92)
const SOON_M: float = 40.0

var _glyph: Label
var _dist: Label
var _road: Label
var _road_ta: Label
var _sb: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sb = StyleBoxFlat.new()
	_sb.bg_color = GREEN
	_sb.set_corner_radius_all(14)
	_sb.content_margin_left = 12
	_sb.content_margin_right = 14
	_sb.content_margin_top = 6
	_sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", _sb)
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	add_child(h)
	_glyph = _mk(54, Color.WHITE)
	_glyph.custom_minimum_size = Vector2(56, 0)
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(_glyph)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	h.add_child(v)
	_dist = _mk(30, Color.WHITE)
	v.add_child(_dist)
	_road = _mk(18, Color(0.88, 1.0, 0.9))
	_road.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_road.custom_minimum_size = Vector2(230, 0)
	v.add_child(_road)
	_road_ta = _mk(16, Color(0.8, 0.95, 0.85))
	v.add_child(_road_ta)
	visible = false
	SignalBus.nav_instruction.connect(show_instruction)

func show_instruction(info: Dictionary) -> void:
	if info.is_empty():
		visible = false
		return
	visible = true
	var d: float = float(info["distance_m"])
	var turn: int = int(info["turn"])
	_glyph.text = str(info["glyph"])
	if turn == GpsRoute.Turn.ARRIVE:
		_dist.text = _fmt(d)
		_road.text = "Destination ahead"
	else:
		_dist.text = ("Now" if d < 15.0 else _fmt(d))
		_road.text = str(info["text"])
	var ta: String = str(info.get("road_ta", ""))
	_road_ta.text = ta
	_road_ta.visible = ta != "" and turn != GpsRoute.Turn.ARRIVE
	# Turn is close: brighter so it catches the eye mid-traffic.
	_sb.bg_color = Color(0.1, 0.62, 0.32, 0.95) if d < SOON_M else GREEN

static func _fmt(m: float) -> String:
	if m >= 1000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d m" % (int(m / 10.0) * 10 if m >= 50.0 else int(m))

func _mk(size: int, colour: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
