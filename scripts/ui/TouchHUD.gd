class_name TouchHUD
extends CanvasLayer
## Mobile controls + dashboard. Touch input is converted into InputMap actions
## (Input.action_press), so the vehicle never knows whether it is driven by touch,
## keyboard or a test. Display data arrives only through SignalBus.

const STEER_DRAG_RANGE_PX: float = 140.0
const AMBER: Color = Color(1.0, 0.72, 0.1)
const PANEL_DARK: Color = Color(0.05, 0.05, 0.05, 0.62)

var steer_value: float = 0.0
var wiper_on: bool = false

var _root: Control
var _steer_zone: Panel
var _handlebar: Panel
var _steer_touch_index: int = -1
var _steer_touch_origin_x: float = 0.0
var _speed_label: Label
var _meter_label: Label
var _lpg_bar: ProgressBar
var _status_label: Label
var _status_timer: float = 0.0
var _buttons: Dictionary = {} # name -> {panel: Panel, touch: TouchScreenButton}

func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_dashboard()
	_build_controls()
	get_viewport().size_changed.connect(_layout)
	_layout()
	SignalBus.telemetry_updated.connect(_on_telemetry)
	SignalBus.engine_stalled_in_water.connect(_on_stalled)
	SignalBus.kick_start_attempt.connect(_on_kick_attempt)
	SignalBus.engine_restarted.connect(func() -> void: _flash("Engine started — vaanga po!", 2.0))
	SignalBus.gethu_stunt_bonus_earned.connect(func(stunt: String, inr: int) -> void: _flash("%s! +₹%d" % [stunt, inr], 2.0))
	SignalBus.camera_mode_changed.connect(func(mode_name: String) -> void: _flash("Camera: " + mode_name, 1.2))
	SignalBus.lpg_empty.connect(func() -> void: _flash("LPG khaali! Find a bunk.", 3.0))

func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_status_label.text = ""
	if Input.is_action_just_pressed("wiper_toggle"):
		_toggle_wiper()
	_handlebar.rotation = -steer_value * 0.6

# --- Building --------------------------------------------------------------

func _build_dashboard() -> void:
	_speed_label = _make_label("0", 64, Color.WHITE)
	_meter_label = _make_label("METER  ₹35\n0.00 km", 26, AMBER)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label = _make_label("", 30, Color(1.0, 0.9, 0.3))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lpg_bar = ProgressBar.new()
	_lpg_bar.name = "LPGBar"
	_lpg_bar.max_value = 1.0
	_lpg_bar.step = 0.001
	_lpg_bar.value = 1.0
	_lpg_bar.show_percentage = false
	_lpg_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lpg_bar)

func _build_controls() -> void:
	_steer_zone = _make_panel("SteerZone", PANEL_DARK)
	_handlebar = _make_panel("Handlebar", Color(0.12, 0.12, 0.12, 0.95))
	_handlebar.reparent(_steer_zone)
	var hint: Label = _make_label("◀  drag to steer  ▶", 18, Color(1, 1, 1, 0.7))
	hint.reparent(_steer_zone)
	hint.name = "SteerHint"
	_add_button("Accelerate", "ACCEL", "accelerate", Color(0.1, 0.55, 0.15, 0.75))
	_add_button("Brake", "BRAKE\nREV", "brake", Color(0.7, 0.1, 0.1, 0.75))
	_add_button("Handbrake", "H-BRK", "handbrake", Color(0.3, 0.3, 0.3, 0.75))
	_add_button("Horn", "POM\nPOM", "horn", Color(0.95, 0.7, 0.05, 0.85))
	_add_button("KickStart", "KICK", "kick_start", Color(0.45, 0.3, 0.1, 0.8))
	_add_button("Camera", "CAM", "camera_cycle", Color(0.2, 0.2, 0.45, 0.75))
	_add_button("Wiper", "WIPER", "", Color(0.2, 0.35, 0.45, 0.75))
	(_buttons["Wiper"]["touch"] as TouchScreenButton).pressed.connect(_toggle_wiper)

func _add_button(button_name: String, text: String, action: String, colour: Color) -> void:
	var panel: Panel = _make_panel(button_name + "Panel", colour)
	var label: Label = _make_label(text, 22, Color.WHITE)
	label.reparent(panel)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var touch: TouchScreenButton = TouchScreenButton.new()
	touch.name = button_name
	touch.action = action
	touch.passby_press = action == "accelerate" or action == "brake"
	touch.shape = RectangleShape2D.new()
	touch.shape_centered = false
	add_child(touch)
	touch.pressed.connect(func() -> void: panel.modulate = Color(1.4, 1.4, 1.4))
	touch.released.connect(func() -> void: panel.modulate = Color.WHITE)
	_buttons[button_name] = {"panel": panel, "touch": touch}

func _make_panel(panel_name: String, colour: Color) -> Panel:
	var p: Panel = Panel.new()
	p.name = panel_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(18)
	p.add_theme_stylebox_override("panel", sb)
	_root.add_child(p)
	return p

func _make_label(text: String, size: int, colour: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l

# --- Layout (thumb-reach zones from the GDD HUD wireframe) -----------------

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var m: float = 24.0
	var b: float = clampf(vp.y * 0.17, 84.0, 140.0) # base button size
	_place(_steer_zone, Rect2(m, vp.y - b * 2.0 - m, b * 3.2, b * 2.0))
	_handlebar.size = Vector2(b * 2.6, b * 0.32)
	_handlebar.position = Vector2(b * 0.3, b * 0.84)
	_handlebar.pivot_offset = _handlebar.size * 0.5
	var hint: Label = _steer_zone.get_node("SteerHint") as Label
	hint.position = Vector2(b * 0.55, b * 1.4)
	_place_button("Horn", Rect2(m, vp.y - b * 3.25 - m, b * 1.1, b * 1.1))
	_place_button("Wiper", Rect2(m + b * 1.3, vp.y - b * 2.95 - m, b * 1.2, b * 0.8))
	_place_button("Accelerate", Rect2(vp.x - m - b * 1.15, vp.y - m - b * 2.4, b * 1.15, b * 2.4))
	_place_button("Brake", Rect2(vp.x - m - b * 2.65, vp.y - m - b * 1.4, b * 1.35, b * 1.4))
	_place_button("Handbrake", Rect2(vp.x - m - b * 2.65, vp.y - m - b * 2.4, b * 1.35, b * 0.85))
	_place_button("KickStart", Rect2(vp.x - m - b * 3.9, vp.y - m - b * 0.9, b * 1.1, b * 0.9))
	_place_button("Camera", Rect2(vp.x - m - b * 1.1, m, b * 1.1, b * 0.7))
	_speed_label.position = Vector2(vp.x - m - b * 2.7, vp.y - m - b * 3.4)
	_lpg_bar.position = Vector2(vp.x - m - b * 2.65, vp.y - m - b * 2.65)
	_lpg_bar.size = Vector2(b * 2.65, 14.0)
	_meter_label.position = Vector2(vp.x - m - b * 1.3 - 230.0, m)
	_meter_label.size = Vector2(220.0, 70.0)
	_status_label.position = Vector2(0.0, vp.y * 0.22)
	_status_label.size = Vector2(vp.x, 50.0)

func _place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size

func _place_button(button_name: String, r: Rect2) -> void:
	var entry: Dictionary = _buttons[button_name]
	_place(entry["panel"] as Panel, r)
	var t: TouchScreenButton = entry["touch"] as TouchScreenButton
	t.position = r.position
	(t.shape as RectangleShape2D).size = r.size

# --- Steering (multitouch-safe: tracks its own finger index) ---------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed and _steer_touch_index == -1 and _steer_zone.get_global_rect().grow(40.0).has_point(st.position):
			_steer_touch_index = st.index
			_steer_touch_origin_x = st.position.x
		elif not st.pressed and st.index == _steer_touch_index:
			_steer_touch_index = -1
			set_steer(0.0)
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if sd.index == _steer_touch_index:
			set_steer((sd.position.x - _steer_touch_origin_x) / STEER_DRAG_RANGE_PX)

## -1 = full left, +1 = full right. Public so tests and tilt-steering can reuse it.
func set_steer(value: float) -> void:
	steer_value = clampf(value, -1.0, 1.0)
	if steer_value > 0.02:
		Input.action_press("steer_right", steer_value)
		Input.action_release("steer_left")
	elif steer_value < -0.02:
		Input.action_press("steer_left", -steer_value)
		Input.action_release("steer_right")
	else:
		Input.action_release("steer_left")
		Input.action_release("steer_right")

# --- SignalBus handlers ----------------------------------------------------

func _on_telemetry(data: Dictionary) -> void:
	var speed: float = data.get("speed_kmh", 0.0)
	var km: float = data.get("odometer_km", 0.0)
	_speed_label.text = "%d km/h" % roundi(speed)
	_meter_label.text = "METER  ₹%d\n%.2f km" % [GameState.calculate_meter_fare(km), km]
	var cap: float = maxf(data.get("lpg_capacity", 1.0), 0.001)
	_lpg_bar.value = float(data.get("lpg_liters", cap)) / cap
	if data.get("is_stalled", false) and _status_timer <= 0.0:
		_status_label.text = "Engine flooded! Tap KICK"

func _on_stalled(_pos: Vector3) -> void:
	_flash("Engine flooded! Tap KICK", 3.0)

func _on_kick_attempt(ratio: float) -> void:
	_flash("Kick… %d%%" % roundi(ratio * 100.0), 1.0)

func _toggle_wiper() -> void:
	wiper_on = not wiper_on
	SignalBus.wiper_toggled.emit(wiper_on)
	_flash("Wiper " + ("ON" if wiper_on else "OFF"), 1.0)

func _flash(text: String, seconds: float) -> void:
	_status_label.text = text
	_status_timer = seconds
