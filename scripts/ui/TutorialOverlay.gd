class_name TutorialOverlay
extends CanvasLayer
## First-ride tutorial UI: Murugan Anna's subtitle card and the spotlight that dims the screen
## except the control to press (pulsing ring + pointer). Pure listener on SignalBus:
## tutorial_step_started / tutorial_hint / tutorial_spotlight / tutorial_finished.
## Sits above the driving HUDs (layers 10–11) and below menus (GarageUI 15).
## Nothing here takes input: the dim and the card ignore the mouse, so driving never stops.

const DIM: Color = Color(0.11, 0.08, 0.13, 0.16)
const RING_PAD: float = 10.0
const CARD_W: float = 470.0
const DONE_SHOW_S: float = 2.5

var card: PanelContainer
var line_label: Label
var name_label: Label
var step_label: Label
var _badge: Label
var _dims: Array[ColorRect] = []
var _ring: Panel
var _pointer: Label
var _hole: Rect2 = Rect2()
var _ring_tween: Tween
var _hint_tween: Tween
var _hide_timer: float = 0.0
var _modal_open: bool = false

func _ready() -> void:
	layer = 12
	for i: int in 4:
		var d: ColorRect = ColorRect.new()
		d.name = "Dim%d" % i
		d.color = DIM
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.visible = false
		add_child(d)
		_dims.append(d)
	_ring = Panel.new()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = UIKit.YELLOW
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(26)
	_ring.add_theme_stylebox_override("panel", sb)
	_ring.visible = false
	add_child(_ring)
	_pointer = UIKit.label("▼", 46, UIKit.YELLOW, true, 6)
	_pointer.name = "Pointer"
	_pointer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pointer.visible = false
	add_child(_pointer)
	_build_card()
	SignalBus.tutorial_step_started.connect(_on_step)
	SignalBus.tutorial_hint.connect(_on_hint)
	SignalBus.tutorial_spotlight.connect(_on_spotlight)
	SignalBus.tutorial_highlight.connect(func(id: String) -> void:
		if id == "":
			_on_spotlight(Rect2()))
	SignalBus.tutorial_finished.connect(_on_finished)
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void:
		_modal_open = open
		_refresh_visibility())
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_card() -> void:
	card = PanelContainer.new()
	card.name = "MentorCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.theme = UIKit.theme()
	var box: StyleBoxFlat = UIKit.card_box(Color(UIKit.DUSK, 0.94), 20)
	box.border_color = UIKit.YELLOW
	box.set_border_width_all(3)
	box.content_margin_left = 14
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	# Placeholder portrait: a round brass badge with "மு" (Murugan) until the painted portrait lands.
	var badge_bg: Panel = Panel.new()
	badge_bg.custom_minimum_size = Vector2(76, 76)
	badge_bg.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb: StyleBoxFlat = StyleBoxFlat.new()
	bsb.bg_color = UIKit.YELLOW
	bsb.border_color = UIKit.ORANGE
	bsb.set_border_width_all(4)
	bsb.set_corner_radius_all(38)
	badge_bg.add_theme_stylebox_override("panel", bsb)
	_badge = UIKit.label("மு", 34, UIKit.PLUM) # body font: it has the Tamil fallback
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_bg.add_child(_badge)
	row.add_child(badge_bg)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	name_label = UIKit.label("", 20, UIKit.YELLOW, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	step_label = UIKit.label("", 16, UIKit.MUTED)
	head.add_child(step_label)
	line_label = UIKit.label("", 22, UIKit.JASMINE)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size = Vector2(CARD_W - 120.0, 0.0)
	col.add_child(line_label)
	card.visible = false
	add_child(card)

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = minf(CARD_W, vp.x - 52.0)
	card.size = Vector2(w, 0.0)
	card.position = Vector2(26.0, vp.y * 0.33)
	_on_spotlight(_hole)

func _process(delta: float) -> void:
	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			card.visible = false

func _on_step(info: Dictionary) -> void:
	_hide_timer = 0.0
	name_label.text = str(info.get("mentor", ""))
	step_label.text = "%d / %d" % [int(info["index"]) + 1, int(info["count"])]
	line_label.text = str(info.get("line", ""))
	line_label.modulate = Color.WHITE
	card.visible = true
	_refresh_visibility()
	card.reset_size()
	UIKit.pop_in(card)

func _on_hint(text: String) -> void:
	if not card.visible:
		return
	line_label.text = text
	if _hint_tween != null:
		_hint_tween.kill()
	_hint_tween = create_tween()
	line_label.modulate = Color(1.0, 0.85, 0.3)
	_hint_tween.tween_property(line_label, "modulate", Color.WHITE, 1.6)

func _on_spotlight(rect: Rect2) -> void:
	_hole = rect
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var on: bool = rect.has_area()
	if on:
		var r: Rect2 = rect.grow(RING_PAD)
		# top, bottom, left, right bands around the hole
		_set_rect(_dims[0], Rect2(0, 0, vp.x, r.position.y))
		_set_rect(_dims[1], Rect2(0, r.end.y, vp.x, vp.y - r.end.y))
		_set_rect(_dims[2], Rect2(0, r.position.y, r.position.x, r.size.y))
		_set_rect(_dims[3], Rect2(r.end.x, r.position.y, vp.x - r.end.x, r.size.y))
		_set_rect(_ring, r)
		_pointer.size = Vector2(r.size.x, 56.0)
		_pointer.position = Vector2(r.position.x, r.position.y - 58.0) if r.position.y > 70.0 else Vector2(r.position.x, r.end.y + 2.0)
		_pointer.text = "▼" if r.position.y > 70.0 else "▲"
		_pulse()
	elif _ring_tween != null:
		_ring_tween.kill()
		_ring_tween = null
	_refresh_visibility()

func _set_rect(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = Vector2(maxf(r.size.x, 0.0), maxf(r.size.y, 0.0))

func _pulse() -> void:
	if _ring_tween != null:
		_ring_tween.kill()
	_ring.modulate = Color.WHITE
	_ring_tween = create_tween().set_loops()
	_ring_tween.tween_property(_ring, "modulate", Color(1, 1, 1, 0.35), 0.55)
	_ring_tween.tween_property(_ring, "modulate", Color.WHITE, 0.55)

func _refresh_visibility() -> void:
	var spot: bool = _hole.has_area() and not _modal_open
	for d: ColorRect in _dims:
		d.visible = spot
	_ring.visible = spot
	_pointer.visible = spot
	visible = not _modal_open

func is_spotlight_on() -> bool:
	return _ring.visible and _hole.has_area()

func _on_finished(skipped: bool) -> void:
	_on_spotlight(Rect2())
	if skipped:
		card.visible = false
		return
	name_label.text = tr("TUT_MENTOR")
	step_label.text = ""
	line_label.text = tr("TUT_ALL_DONE")
	card.visible = true
	_hide_timer = DONE_SHOW_S
