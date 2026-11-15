class_name SignalChip
extends Control
## The next traffic signal ahead, as Chennai's own signals show it: the lit lamp and a countdown
## (Nov 15 device report: "as a player I barely notice the traffic signals"). A camera mark means
## the junction is watched (fines). One CanvasItem drawn in _draw: no textures, ~2 draw calls.
## Fed by SignalBus.signal_ahead_changed (ChennaiTrafficManager.signal_ahead); hidden when no signal
## is within SIGNAL_AHEAD_M in front of the auto.

const W: float = 176.0
const H: float = 58.0
const LAMP_R: float = 11.0
const OFF: Color = Color(0.22, 0.22, 0.22)
const LIT: Array[Color] = [Color(0.25, 0.95, 0.35), Color(1.0, 0.72, 0.1), Color(1.0, 0.22, 0.18)]

var light: int = -1 # ChennaiTrafficManager.Light: 0 green, 1 amber, 2 red; -1 = nothing ahead
var seconds: int = 0
var enforced: bool = false
var distance_m: float = 0.0
var _blink: float = 0.0
var _panel: StyleBoxFlat = StyleBoxFlat.new()

func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	SignalBus.signal_ahead_changed.connect(show_info)

func show_info(info: Dictionary) -> void:
	if info.is_empty():
		light = -1
		visible = false
		return
	light = int(info.get("light", 0))
	seconds = ceili(float(info.get("seconds", 0.0)))
	enforced = bool(info.get("enforced", false))
	distance_m = float(info.get("distance", 0.0))
	visible = true
	queue_redraw()

func _process(delta: float) -> void:
	# Red at a watched junction pulses, so it is noticed without looking for it.
	if visible and light == 2 and enforced:
		_blink = fposmod(_blink + delta * 2.0, 1.0)
		queue_redraw()

func _draw() -> void:
	if light < 0:
		return
	_panel.bg_color = Color(0.06, 0.06, 0.08, 0.82)
	_panel.set_corner_radius_all(14)
	_panel.border_color = LIT[light] if light != 2 or not enforced or _blink < 0.5 else Color.WHITE
	_panel.set_border_width_all(3)
	draw_style_box(_panel, Rect2(Vector2.ZERO, Vector2(W, H)))
	# Red, amber, green left to right, like a horizontal Chennai signal head.
	for k: int in 3:
		var which: int = 2 - k
		var c: Vector2 = Vector2(22.0 + float(k) * 27.0, H * 0.5)
		draw_circle(c, LAMP_R, LIT[which] if which == light else OFF)
	var font: Font = get_theme_default_font()
	var txt: String = "%d" % seconds
	draw_string(font, Vector2(96.0, H * 0.5 + 11.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, LIT[light])
	if enforced:
		# A small camera: body + lens.
		var o: Vector2 = Vector2(W - 34.0, H * 0.5 - 8.0)
		draw_rect(Rect2(o, Vector2(22.0, 15.0)), Color(0.92, 0.92, 0.92))
		draw_rect(Rect2(o + Vector2(4.0, -4.0), Vector2(7.0, 4.0)), Color(0.92, 0.92, 0.92))
		draw_circle(o + Vector2(11.0, 7.5), 4.5, Color(0.1, 0.1, 0.12))
