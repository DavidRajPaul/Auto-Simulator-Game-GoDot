class_name PassengerHUD
extends CanvasLayer
## Savari-mode UI: haggle card (5 s), active passenger card, fare breakdown, wallet &
## stand rating, toasts and the mini-map. Reads SignalBus only; choices go back out as
## SignalBus.haggle_choice_made. Laid out for thumbs per the GDD HUD wireframe.

const AMBER: Color = Color(1.0, 0.72, 0.1)
const CARD_BG: Color = Color(0.06, 0.06, 0.07, 0.86)
const OFFER_COLOURS: Array[Color] = [Color(0.12, 0.55, 0.22), Color(0.85, 0.55, 0.05), Color(0.75, 0.15, 0.15)]
const OFFER_TAGS: PackedStringArray = ["safe", "bargain", "greedy"]
const OFFER_SHORT: PackedStringArray = ["Correct Meter", "Meter Mela", "Fixed Rate"]
const MINIMAP_SIZE: float = 190.0

var _root: Control
var _wallet: Label
var _level: Label
var _xp_bar: ProgressBar
var _ride_card: PanelContainer
var _ride_text: Label
var _comfort_bar: ProgressBar
var _haggle: PanelContainer
var _haggle_title: Label
var _haggle_line: Label
var _haggle_buttons: Array[Button] = []
var _haggle_timer_bar: ProgressBar
var _haggle_time: float = 0.0
var _haggle_total: float = 5.0
var _fare_card: PanelContainer
var _fare_text: Label
var _fare_timer: float = 0.0
var _toast: Label
var _toast_timer: float = 0.0
var minimap: MiniMap
var _hint: Label
var _hint_timer: float = 0.0

func _ready() -> void:
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	minimap = MiniMap.new()
	minimap.name = "MiniMap"
	minimap.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.position = Vector2(16.0, 16.0)
	_root.add_child(minimap)
	_wallet = _label("₹500   ★4.5", 26, Color.WHITE)
	_xp_bar = ProgressBar.new()
	_xp_bar.max_value = 1.0
	_xp_bar.step = 0.001
	_xp_bar.show_percentage = false
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.72, 0.1)
	fill.set_corner_radius_all(4)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(4)
	_xp_bar.add_theme_stylebox_override("fill", fill)
	_xp_bar.add_theme_stylebox_override("background", bg)
	_root.add_child(_xp_bar)
	_level = _label("", 18, Color(1.0, 0.85, 0.45))
	_build_ride_card()
	_build_haggle()
	_build_fare_card()
	_toast = _label("", 26, Color(1.0, 0.92, 0.5))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_wallet()
	SignalBus.wallet_balance_changed.connect(func(_b: int, _d: int) -> void: _refresh_wallet())
	SignalBus.stand_respect_changed.connect(func(_xp: int, _r: float) -> void: _refresh_wallet())
	SignalBus.haggle_started.connect(_on_haggle_started)
	SignalBus.haggle_resolved.connect(_on_haggle_resolved)
	SignalBus.ride_updated.connect(_on_ride_updated)
	SignalBus.ride_completed.connect(_on_ride_completed)
	_hint = _label("", 22, Color(0.75, 1.0, 0.8))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	SignalBus.hint_requested.connect(func(text: String, seconds: float) -> void:
		_hint.text = text
		_hint_timer = seconds)
	_layout()
	SignalBus.near_miss.connect(func(_c: float) -> void: toast("Gap-la Gethu!", 1.2))
	SignalBus.driver_xp_changed.connect(func(_x: int, _l: int, _p: float) -> void: _refresh_level())
	SignalBus.driver_level_up.connect(func(lvl: int, title: String, reward: int, unlock_key: String) -> void:
		var extra: String = ("\n" + tr(unlock_key)) if unlock_key != "" else ""
		toast("%s %d — %s!  +₹%d%s" % [tr("LEVEL_UP"), lvl, title, reward, extra], 4.0))
	SignalBus.goal_completed.connect(func(g: Dictionary) -> void:
		toast("%s: %s  +₹%d" % [tr("GOAL_DONE"), goal_text(g), DriverProgress.GOAL_INR], 3.0))
	SignalBus.all_goals_completed.connect(func(bonus: int) -> void: toast("%s  +₹%d" % [tr("ALL_GOALS_DONE"), bonus], 4.0))
	_refresh_level()

func _process(delta: float) -> void:
	if _haggle.visible:
		_haggle_time -= delta
		_haggle_timer_bar.value = maxf(_haggle_time, 0.0) / _haggle_total
		if _haggle_time <= 0.0:
			_haggle.visible = false
	if _fare_card.visible:
		_fare_timer -= delta
		if _fare_timer <= 0.0:
			_fare_card.visible = false
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint.text = ""
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.text = ""

# --- Building ------------------------------------------------------------------

func _label(text: String, size: int, colour: Color, outline: bool = true) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if outline:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l

func _card() -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(14.0)
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	_root.add_child(p)
	return p

func _build_ride_card() -> void:
	_ride_card = _card()
	var v: VBoxContainer = VBoxContainer.new()
	_ride_card.add_child(v)
	_ride_text = _label("", 20, Color.WHITE, false)
	_ride_text.reparent(v)
	var row: HBoxContainer = HBoxContainer.new()
	v.add_child(row)
	var cup: Label = _label("Tea cup", 18, AMBER, false)
	cup.reparent(row)
	_comfort_bar = ProgressBar.new()
	_comfort_bar.max_value = 1.0
	_comfort_bar.step = 0.01
	_comfort_bar.show_percentage = false
	_comfort_bar.custom_minimum_size = Vector2(160, 16)
	_comfort_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_comfort_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_comfort_bar)

func _build_haggle() -> void:
	_haggle = _card()
	_haggle.mouse_filter = Control.MOUSE_FILTER_STOP
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_haggle.add_child(v)
	_haggle_title = _label("", 24, AMBER, false)
	_haggle_title.reparent(v)
	_haggle_line = _label("", 22, Color.WHITE, false)
	_haggle_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_haggle_line.reparent(v)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	for i: int in 3:
		var b: Button = Button.new()
		b.custom_minimum_size = Vector2(190, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = OFFER_COLOURS[i]
		sb.set_corner_radius_all(12)
		b.add_theme_stylebox_override("normal", sb)
		var sbp: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
		sbp.bg_color = OFFER_COLOURS[i].lightened(0.25)
		b.add_theme_stylebox_override("pressed", sbp)
		b.add_theme_stylebox_override("hover", sb)
		var offer: int = i
		b.pressed.connect(func() -> void: _choose(offer))
		row.add_child(b)
		_haggle_buttons.append(b)
	_haggle_timer_bar = ProgressBar.new()
	_haggle_timer_bar.max_value = 1.0
	_haggle_timer_bar.step = 0.001
	_haggle_timer_bar.show_percentage = false
	_haggle_timer_bar.custom_minimum_size = Vector2(0, 10)
	v.add_child(_haggle_timer_bar)

func _build_fare_card() -> void:
	_fare_card = _card()
	_fare_text = _label("", 22, Color.WHITE, false)
	_fare_text.reparent(_fare_card)

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_wallet.position = Vector2(vp.x - 24.0 - 260.0, 104.0) # under the CAM button, clear of the meter
	_wallet.size = Vector2(260.0, 40.0)
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level.position = Vector2(vp.x - 24.0 - 260.0, 138.0)
	_level.size = Vector2(260.0, 26.0)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_bar.position = Vector2(vp.x - 24.0 - 160.0, 166.0)
	_xp_bar.size = Vector2(160.0, 8.0)
	_ride_card.position = Vector2(vp.x * 0.5 - 200.0, 12.0)
	_ride_card.custom_minimum_size = Vector2(400.0, 0.0)
	_haggle.custom_minimum_size = Vector2(minf(680.0, vp.x - 40.0), 0.0)
	_haggle.position = Vector2((vp.x - _haggle.custom_minimum_size.x) * 0.5, vp.y * 0.22)
	_fare_card.custom_minimum_size = Vector2(360.0, 0.0)
	_fare_card.position = Vector2(vp.x * 0.5 - 180.0, vp.y * 0.2)
	_toast.position = Vector2(0.0, vp.y * 0.25)
	if _hint != null:
		_hint.position = Vector2(vp.x * 0.2, vp.y * 0.36)
		_hint.size = Vector2(vp.x * 0.6, 60.0)
	_toast.size = Vector2(vp.x, 40.0)

# --- Behaviour -----------------------------------------------------------------

func toast(text: String, seconds: float) -> void:
	_toast.text = text
	_toast_timer = seconds

func _refresh_level() -> void:
	var lvl: int = GameState.driver_level()
	_level.text = "%s %d · %s" % [tr("LV"), lvl, DriverProgress.title(lvl)]
	_xp_bar.value = GameState.progress.level_progress()

## "Complete 3 rides (1/3)"
static func goal_text(g: Dictionary) -> String:
	return TranslationServer.translate(str(g["text"])) % int(g["target"])

func _refresh_wallet() -> void:
	_wallet.text = "₹%s   ★%.1f" % [_inr(GameState.wallet_inr), GameState.star_rating]

func _inr(v: int) -> String:
	var s: String = str(absi(v))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

func _on_haggle_started(info: Dictionary, seconds: float) -> void:
	_fare_card.visible = false
	_haggle_title.text = "%s → %s (%.1f km)" % [info["name"], info["destination"], float(info["distance_km"])]
	_haggle_line.text = "“%s”" % info["line"]
	var quotes: Array = info["quotes"]
	for i: int in 3:
		_haggle_buttons[i].text = "%s\n₹%d\n%s" % [OFFER_SHORT[i], int(quotes[i]), OFFER_TAGS[i]]
		_haggle_buttons[i].disabled = false
	_haggle_time = seconds
	_haggle_total = seconds
	_haggle.visible = true

func _choose(offer: int) -> void:
	for b: Button in _haggle_buttons:
		b.disabled = true
	SignalBus.haggle_choice_made.emit(offer)

func _on_haggle_resolved(result: Dictionary) -> void:
	_haggle.visible = false
	if bool(result["accepted"]):
		toast("“%s”  Deal: ₹%d" % [result["line"], int(result["fare"])], 3.0)
		_ride_card.visible = true
	else:
		toast("“%s”" % result["line"], 3.0)

func _on_ride_updated(info: Dictionary) -> void:
	_ride_card.visible = true
	var t: float = float(info["time_left_s"])
	var clock: String = "%d:%02d" % [int(absf(t)) / 60, int(absf(t)) % 60]
	_ride_text.text = "%s → %s\n%.1f km   %s%s   ₹%d" % [info["archetype"], info["destination"],
		float(info["remaining_m"]) / 1000.0 * FareCalculator.REAL_KM_PER_GAME_KM, "-" if t < 0.0 else "", clock, int(info["fare"])]
	_ride_text.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if t < 0.0 else Color.WHITE)
	_comfort_bar.value = float(info["comfort"])

func _on_ride_completed(b: Dictionary) -> void:
	_ride_card.visible = false
	var stars: int = roundi(float(b["stars"]))
	_fare_text.text = "Dropped at %s\n\nFare            ₹%d\nComfort tip     ₹%d\nGap-la Gethu    ₹%d\n────────────────\nTotal           ₹%d\n\n%s   %s\n“%s”" % [
		b["destination"], int(b["fare"]), int(b["comfort_tip"]), int(b["gethu_bonus"]), int(b["total"]),
		"★".repeat(stars) + "☆".repeat(5 - stars), "On time" if bool(b["on_time"]) else "Late!", b["line"]]
	_fare_card.visible = true
	_fare_timer = 5.0
