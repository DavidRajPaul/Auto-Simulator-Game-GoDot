class_name TutorialOverlay
extends CanvasLayer
## First-ride tutorial UI, "coach mode" (v2, Oct 31 playtest: the full-screen dim + big mentor
## card hid the road; lowering the dim was not the answer). Nothing covers the driving view:
##  * Coach strip — one compact pill at top centre (the sky band, above the road): Murugan
##    Anna's badge, the short task ("Tap KICK 3 times, steady"), ten progress dots and SKIP.
##  * Speech bubble — his full Tanglish line drops under the strip for SPEECH_S seconds, then
##    folds away; a hint re-opens it briefly. The task stays.
##  * Target — a pulsing ring, a bouncing arrow and a TAP/HOLD chip on the control to press.
##    No screen dimming at all.
## Pure listener on SignalBus (tutorial_step_started / tutorial_hint / tutorial_spotlight /
## tutorial_finished). Layer 12: above the driving HUDs (10–11), below menus (GarageUI 15).
## Only the SKIP button takes input; everything else ignores the mouse so driving never stops.

const RING_PAD: float = 10.0
## The coach strip sits IN the top HUD row, in the gap between the left button cluster (gear,
## horn, camera, indicators end at ~39 % of the width) and the clock/wallet (start at ~80 %),
## so it never covers the road or its vanishing point (where the STOP line and traffic appear).
const STRIP_LEFT_FRAC: float = 0.395
const STRIP_RIGHT_FRAC: float = 0.80
const STRIP_TOP_PX: float = 10.0
## The speech bubble opens over the left kerb, under the left button cluster — buildings, not road.
const BUBBLE_W: float = 400.0
const BUBBLE_TOP_FRAC: float = 0.36
const SPEECH_S: float = 6.0
const HINT_S: float = 4.5
const DONE_SHOW_S: float = 2.5
const DOT_ON: Color = Color(1.0, 0.78, 0.15)
## Per-control action word on the target chip (default TAP).
const HOLD_CONTROLS: PackedStringArray = ["Accelerate", "Brake"]

## Coach strip (kept as `card` for the tests and older callers).
var card: PanelContainer
var task_label: Label
var step_label: Label
var name_label: Label
## Speech bubble with the mentor's full line.
var bubble: PanelContainer
var line_label: Label
var skip_button: Button
## Progress dots as ONE label ("●●●○○…"): ten separate panels cost ten 2D draw calls.
var _dots: Label
var _ring: Panel
var _pointer: Label
var _chip: Label
var _hole: Rect2 = Rect2()
var _hole_id: String = ""
var _ring_tween: Tween
var _bob_tween: Tween
var _hint_tween: Tween
var _speech_timer: float = 0.0
var _hide_timer: float = 0.0
var _modal_open: bool = false

func _ready() -> void:
	layer = 12
	_ring = Panel.new()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = UIKit.YELLOW
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(26)
	sb.shadow_color = Color(1.0, 0.78, 0.15, 0.45)
	sb.shadow_size = 10
	_ring.add_theme_stylebox_override("panel", sb)
	_ring.visible = false
	add_child(_ring)
	_pointer = UIKit.label("▼", 44, UIKit.YELLOW, true, 6)
	_pointer.name = "Pointer"
	_pointer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.visible = false
	add_child(_pointer)
	_chip = UIKit.label("", 18, UIKit.PLUM, true)
	_chip.name = "ActionChip"
	_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var csb: StyleBoxFlat = UIKit.card_box(UIKit.YELLOW, 14)
	csb.content_margin_left = 10
	csb.content_margin_right = 10
	_chip.add_theme_stylebox_override("normal", csb)
	_chip.visible = false
	add_child(_chip)
	_build_strip()
	_build_bubble()
	SignalBus.tutorial_step_started.connect(_on_step)
	SignalBus.tutorial_hint.connect(_on_hint)
	SignalBus.tutorial_spotlight.connect(_on_spotlight)
	SignalBus.tutorial_highlight.connect(func(id: String) -> void:
		_hole_id = id
		if id == "":
			_on_spotlight(Rect2()))
	SignalBus.tutorial_finished.connect(_on_finished)
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void:
		_modal_open = open
		_refresh_visibility())
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_strip() -> void:
	card = PanelContainer.new()
	card.name = "CoachStrip"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.theme = UIKit.theme()
	var box: StyleBoxFlat = UIKit.card_box(Color(UIKit.DUSK, 0.84), 30)
	box.border_color = UIKit.YELLOW
	box.set_border_width_all(2)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	# Murugan Anna badge: brass coin with "மு" until the painted portrait lands.
	var badge: Panel = Panel.new()
	badge.custom_minimum_size = Vector2(46, 46)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb: StyleBoxFlat = StyleBoxFlat.new()
	bsb.bg_color = UIKit.YELLOW
	bsb.border_color = UIKit.ORANGE
	bsb.set_border_width_all(3)
	bsb.set_corner_radius_all(23)
	badge.add_theme_stylebox_override("panel", bsb)
	var glyph: Label = UIKit.label("மு", 22, UIKit.PLUM)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(glyph)
	row.add_child(badge)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	task_label = UIKit.label("", 21, UIKit.JASMINE, true)
	task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(task_label)
	var meta: HBoxContainer = HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(meta)
	_dots = UIKit.label("", 13, DOT_ON)
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(_dots)
	step_label = UIKit.label("", 14, UIKit.MUTED)
	meta.add_child(step_label)
	name_label = UIKit.label("", 14, UIKit.YELLOW)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_child(name_label)
	skip_button = Button.new()
	skip_button.name = "Skip"
	skip_button.text = tr("TUT_SKIP")
	skip_button.custom_minimum_size = Vector2(76, 40)
	skip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip_button.focus_mode = Control.FOCUS_NONE
	var ssb: StyleBoxFlat = UIKit.card_box(Color(1, 1, 1, 0.12), 18)
	skip_button.add_theme_stylebox_override("normal", ssb)
	skip_button.add_theme_stylebox_override("hover", ssb)
	skip_button.add_theme_stylebox_override("pressed", UIKit.card_box(Color(1, 1, 1, 0.25), 18))
	skip_button.add_theme_font_size_override("font_size", 15)
	skip_button.add_theme_color_override("font_color", UIKit.MUTED)
	skip_button.pressed.connect(func() -> void: SignalBus.tutorial_skip_requested.emit())
	row.add_child(skip_button)
	card.visible = false
	add_child(card)

func _build_bubble() -> void:
	bubble = PanelContainer.new()
	bubble.name = "SpeechBubble"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.theme = UIKit.theme()
	var box: StyleBoxFlat = UIKit.card_box(Color(1.0, 0.98, 0.92, 0.94), 16)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 9
	bubble.add_theme_stylebox_override("panel", box)
	line_label = UIKit.label("", 18, UIKit.PLUM)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(line_label)
	bubble.visible = false
	add_child(bubble)

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = vp.x * (STRIP_RIGHT_FRAC - STRIP_LEFT_FRAC)
	# Autowrap labels need a fixed width or the container grows to the full screen height.
	task_label.custom_minimum_size = Vector2(w - 46.0 - 76.0 - 16.0 - 30.0, 0.0)
	card.size = Vector2(w, 0.0)
	card.reset_size()
	card.size.x = w
	card.position = Vector2(vp.x * STRIP_LEFT_FRAC, STRIP_TOP_PX)
	var bw: float = minf(BUBBLE_W, vp.x * 0.32)
	bubble.size = Vector2(bw, 0.0)
	bubble.reset_size()
	bubble.size.x = bw
	line_label.custom_minimum_size = Vector2(bw - 28.0, 0.0)
	bubble.position = Vector2(26.0, vp.y * BUBBLE_TOP_FRAC)
	_on_spotlight(_hole)

func _process(delta: float) -> void:
	if _speech_timer > 0.0:
		_speech_timer -= delta
		if _speech_timer <= 0.0:
			_fold_bubble()
	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			card.visible = false
			bubble.visible = false

func _on_step(info: Dictionary) -> void:
	_hide_timer = 0.0
	_hole_id = str(info.get("highlight", ""))
	var index: int = int(info["index"])
	var count: int = int(info["count"])
	name_label.text = str(info.get("mentor", ""))
	step_label.text = "%d / %d" % [index + 1, count]
	task_label.text = str(info.get("task", "")) if str(info.get("task", "")) != "" else str(info.get("line", ""))
	_set_dots(index, count)
	skip_button.visible = true
	card.visible = true
	_say(str(info.get("line", "")), SPEECH_S)
	_refresh_visibility()
	_layout()
	UIKit.pop_in(card)

func _set_dots(index: int, count: int) -> void:
	_dots.text = "●".repeat(index + 1) + "○".repeat(maxi(count - index - 1, 0))

func _say(text: String, seconds: float) -> void:
	line_label.text = text
	bubble.visible = text != "" and not _modal_open
	_speech_timer = seconds if text != "" else 0.0
	if bubble.visible:
		bubble.modulate = Color.WHITE
		_layout()

func _fold_bubble() -> void:
	if not bubble.visible:
		return
	var t: Tween = create_tween()
	t.tween_property(bubble, "modulate", Color(1, 1, 1, 0), 0.35)
	t.tween_callback(func() -> void: bubble.visible = false)

func is_bubble_open() -> bool:
	return bubble.visible and bubble.modulate.a > 0.5

func _on_hint(text: String) -> void:
	if not card.visible:
		return
	_say(text, HINT_S)
	if _hint_tween != null:
		_hint_tween.kill()
	_hint_tween = create_tween()
	line_label.modulate = Color(0.85, 0.35, 0.05)
	_hint_tween.tween_property(line_label, "modulate", Color.WHITE, 1.6)

func _on_spotlight(rect: Rect2) -> void:
	_hole = rect
	var on: bool = rect.has_area()
	if on:
		var r: Rect2 = rect.grow(RING_PAD)
		_set_rect(_ring, r)
		var above: bool = r.position.y > 90.0
		_pointer.size = Vector2(r.size.x, 52.0)
		_pointer.position = Vector2(r.position.x, r.position.y - 54.0) if above else Vector2(r.position.x, r.end.y + 2.0)
		_pointer.text = "▼" if above else "▲"
		_chip.text = tr("TUT_HOLD") if _hole_id in HOLD_CONTROLS else tr("TUT_TAP")
		_chip.reset_size()
		var cs: Vector2 = _chip.get_combined_minimum_size()
		# Chip beside the ring, on the side that stays on screen.
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var cx: float = r.position.x - cs.x - 8.0 if r.get_center().x > vp.x * 0.5 else r.end.x + 8.0
		_chip.position = Vector2(cx, r.get_center().y - cs.y * 0.5)
		_chip.size = cs
		_pulse(above)
	else:
		if _ring_tween != null:
			_ring_tween.kill()
			_ring_tween = null
		if _bob_tween != null:
			_bob_tween.kill()
			_bob_tween = null
	_refresh_visibility()

func _set_rect(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = Vector2(maxf(r.size.x, 0.0), maxf(r.size.y, 0.0))

func _pulse(above: bool) -> void:
	if _ring_tween != null:
		_ring_tween.kill()
	_ring.modulate = Color.WHITE
	_ring_tween = create_tween().set_loops()
	_ring_tween.tween_property(_ring, "modulate", Color(1, 1, 1, 0.35), 0.55)
	_ring_tween.tween_property(_ring, "modulate", Color.WHITE, 0.55)
	if _bob_tween != null:
		_bob_tween.kill()
	var y0: float = _pointer.position.y
	var dy: float = 10.0 if above else -10.0
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(_pointer, "position:y", y0 + dy, 0.4).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(_pointer, "position:y", y0, 0.4).set_trans(Tween.TRANS_SINE)

func _refresh_visibility() -> void:
	var spot: bool = _hole.has_area() and not _modal_open
	_ring.visible = spot
	_pointer.visible = spot
	_chip.visible = spot
	visible = not _modal_open

func is_spotlight_on() -> bool:
	return _ring.visible and _hole.has_area()

## True if any part of the overlay covers more than `max_frac` of the screen (regression guard:
## the old full-screen dim hid the road).
func covered_fraction() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var area: float = 0.0
	for c: Control in [card, bubble, _ring, _pointer, _chip]:
		if c.visible:
			area += c.size.x * c.size.y
	return area / maxf(vp.x * vp.y, 1.0)

func _on_finished(skipped: bool) -> void:
	_on_spotlight(Rect2())
	skip_button.visible = false
	if skipped:
		card.visible = false
		bubble.visible = false
		return
	name_label.text = tr("TUT_MENTOR")
	step_label.text = ""
	task_label.text = tr("TUT_ALL_DONE")
	card.visible = true
	bubble.visible = false
	_hide_timer = DONE_SHOW_S
	_layout()
