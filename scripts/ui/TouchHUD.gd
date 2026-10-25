class_name TouchHUD
extends CanvasLayer
## Mobile controls + dashboard. Touch input is converted into InputMap actions
## (Input.action_press), so the vehicle never knows whether it is driven by touch,
## keyboard or a test. Display data arrives only through SignalBus.
##
## Layout follows the usual Indian driving-sim phone layout: steer buttons bottom-left,
## brake + gas pedals bottom-right, gear / horn / camera top-left, pause top-right and the
## speedometer, mini-map and LPG gauge along the bottom centre.
##
## Touch handling is done here, per finger, straight from InputEventScreenTouch/Drag:
##  * a press acts on the touch-down event (no waiting for release, no mouse emulation);
##  * every button has a padded hit area, so a thumb that lands between buttons still hits one;
##  * a finger can slide from gas to brake, or left to right, without lifting.
## The TouchScreenButton nodes stay only as inert markers (tests check their visibility).

const STEER_DRAG_RANGE_PX: float = 140.0
const AMBER: Color = Color(1.0, 0.72, 0.1)
const PANEL_DARK: Color = Color(0.05, 0.05, 0.05, 0.55)
const ICON_ATLAS: String = "res://assets/ui/controls_atlas.png"
const ICON_CELL: int = 128
## Icon indices in assets/ui/controls_atlas.png (tools/art/make_ui_icons.py).
const ICONS: Dictionary = {"accel": 0, "brake": 1, "handbrake": 2, "horn": 3, "ind_left": 4, "ind_right": 5,
	"gear_d": 6, "gear_r": 7, "kick": 8, "camera": 9, "wiper": 10, "handlebar": 11}
const INDICATOR_ON: Color = Color(0.2, 0.85, 0.3, 0.95)
const INDICATOR_OFF: Color = Color(0.18, 0.2, 0.22, 0.7)
## Extra touch margin around each button (px). Half the usual gap, so neighbours never fight.
const HIT_PAD: float = 18.0
## Buttons a finger may slide onto and off without lifting (held controls only).
const SLIDEABLE: Array[String] = ["Accelerate", "Brake", "SteerLeft", "SteerRight"]
const PRESSED_TINT: Color = Color(1.45, 1.45, 1.45)

var steer_value: float = 0.0
var wiper_on: bool = false

var _root: Control
## Draw-order layers: every panel first, then every label. Interleaving them broke 2D
## batching and cost ~55 draw calls on the compatibility renderer.
var _panels: Control
var _icons: Control
var _texts: Control
var _icon_tex: Texture2D
var gear: int = 1
var indicator: int = 0
var _steer_zone: Panel
var _handlebar: Panel
var _steer_touch_index: int = -1
var _steer_touch_origin_x: float = 0.0
var _speed_label: Label
var _meter_label: Label
var _lpg_bar: ProgressBar
var _status_label: Label
var _status_timer: float = 0.0
var _buttons: Dictionary = {} # name -> {panel, touch, label, icon, action}
var _ride_fare: int = -1 # -1 = meter flag up (FOR HIRE)
## 0 handlebar drag, 1 arrow buttons (default), 2 tilt (GameState.settings.control_scheme).
var control_scheme: int = 1
## finger index -> button name it is holding.
var _fingers: Dictionary = {}
## button name -> number of fingers holding it.
var _held: Dictionary = {}
var _dash: Dashboard

## Speedometer + LPG dial, drawn in one Control (a handful of 2D draw calls).
class Dashboard:
	extends Control
	var speed_kmh: float = 0.0
	var max_kmh: float = 80.0
	var lpg: float = 1.0
	var speed_centre: Vector2 = Vector2.ZERO
	var speed_radius: float = 70.0
	var fuel_centre: Vector2 = Vector2.ZERO
	var fuel_radius: float = 48.0

	func _draw() -> void:
		_dial(speed_centre, speed_radius, clampf(speed_kmh / max_kmh, 0.0, 1.0), Color(1.0, 0.72, 0.1), 8)
		_dial(fuel_centre, fuel_radius, clampf(lpg, 0.0, 1.0), Color(0.3, 0.85, 0.4) if lpg > 0.2 else Color(0.95, 0.25, 0.2), 4)

	func _dial(c: Vector2, r: float, t: float, accent: Color, ticks: int) -> void:
		var a0: float = deg_to_rad(135.0)
		var a1: float = deg_to_rad(405.0)
		draw_circle(c, r, Color(0.04, 0.04, 0.05, 0.82))
		draw_arc(c, r - 3.0, a0, a1, 40, Color(1, 1, 1, 0.85), 3.0, true)
		draw_arc(c, r - 10.0, a0, lerpf(a0, a1, t), 32, accent, 6.0, true)
		for i: int in ticks + 1:
			var a: float = lerpf(a0, a1, float(i) / float(ticks))
			var d: Vector2 = Vector2(cos(a), sin(a))
			draw_line(c + d * (r - 18.0), c + d * (r - 6.0), Color(1, 1, 1, 0.8), 2.0, true)
		var na: float = lerpf(a0, a1, t)
		draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 16.0), Color(0.95, 0.2, 0.15), 3.0, true)
		draw_circle(c, 5.0, Color(0.9, 0.9, 0.9))

func _ready() -> void:
	layer = 10
	# Deliver every touch event the moment it arrives instead of merging them per frame.
	Input.use_accumulated_input = false
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for layer_name: String in ["Panels", "Icons", "Texts"]:
		var c: Control = Control.new()
		c.name = layer_name
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(c)
	_panels = _root.get_node("Panels") as Control
	_icons = _root.get_node("Icons") as Control
	_texts = _root.get_node("Texts") as Control
	_icon_tex = load(ICON_ATLAS) as Texture2D
	_build_dashboard()
	_build_controls()
	get_viewport().size_changed.connect(_layout)
	_layout()
	SignalBus.telemetry_updated.connect(_on_telemetry)
	SignalBus.engine_stalled_in_water.connect(_on_stalled)
	SignalBus.kick_start_attempt.connect(_on_kick_attempt)
	SignalBus.kick_timed.connect(func(good: bool) -> void:
		if not good:
			_flash("Too fast/slow — kick... kick... kick", 1.2))
	SignalBus.engine_restarted.connect(func() -> void: _flash("Engine started — vaanga po!", 2.0))
	SignalBus.gethu_stunt_bonus_earned.connect(func(stunt: String, inr: int) -> void: _flash("%s! +₹%d" % [stunt, inr], 2.0))
	SignalBus.camera_mode_changed.connect(func(mode_name: String) -> void: _flash("Camera: " + mode_name, 1.2))
	SignalBus.settings_changed.connect(func(st: Dictionary) -> void: set_control_scheme(int(st.get("control_scheme", 1))))
	set_control_scheme(int(GameState.settings.get("control_scheme", 1)))
	SignalBus.ride_updated.connect(func(info: Dictionary) -> void: _ride_fare = int(info["fare"]))
	SignalBus.ride_completed.connect(func(_b: Dictionary) -> void: _ride_fare = -1)
	SignalBus.lpg_empty.connect(func() -> void: _flash("LPG khaali! Find a bunk.", 3.0))
	SignalBus.gear_changed.connect(_on_gear_changed)
	SignalBus.gear_change_refused.connect(func() -> void: _flash(tr("STOP_TO_SHIFT"), 1.5))
	SignalBus.indicator_blink.connect(_on_indicator_blink)
	SignalBus.indicator_changed.connect(func(d: int) -> void:
		indicator = d
		_on_indicator_blink(d, d != 0))
	SignalBus.signalled_turn.connect(func(_d: int) -> void: _flash(tr("SIGNAL_SIR"), 1.4))
	SignalBus.engine_restarted.connect(func() -> void: _set_button_visible("KickStart", false))
	SignalBus.weather_changed.connect(func(_r: bool) -> void: _refresh_wiper_visibility())
	_set_button_visible("KickStart", false)
	_refresh_wiper_visibility()

func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_status_label.text = ""
	if control_scheme == 2:
		_tilt_steer()
	if Input.is_action_just_pressed("wiper_toggle"):
		_toggle_wiper()
	_handlebar.rotation = -steer_value * 0.6

func _notification(what: int) -> void:
	# A finger lifted while the app was in the background never sends its release.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()

# --- Building --------------------------------------------------------------

func _build_dashboard() -> void:
	_dash = Dashboard.new()
	_dash.name = "Dashboard"
	_dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panels.add_child(_dash)
	_speed_label = _make_label("0", 30, Color.WHITE)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter_label = _make_label("METER\nFOR HIRE", 24, AMBER)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label = _make_label("", 30, Color(1.0, 0.9, 0.3))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kmh: Label = _make_label("km/h", 14, Color(1, 1, 1, 0.75), false)
	kmh.name = "KmhCaption"
	kmh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lpg: Label = _make_label("LPG", 14, Color(1, 1, 1, 0.75), false)
	lpg.name = "LpgCaption"
	lpg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The dial shows the level; the bar is kept for code that reads it.
	_lpg_bar = ProgressBar.new()
	_lpg_bar.name = "LPGBar"
	_lpg_bar.max_value = 1.0
	_lpg_bar.step = 0.001
	_lpg_bar.value = 1.0
	_lpg_bar.show_percentage = false
	_lpg_bar.visible = false
	_lpg_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panels.add_child(_lpg_bar)

func _build_controls() -> void:
	_steer_zone = _make_panel("SteerZone", PANEL_DARK)
	_handlebar = _make_panel("Handlebar", Color(0.12, 0.12, 0.12, 0.95))
	_handlebar.reparent(_steer_zone)
	var hint: Label = _make_label("◀  drag to steer  ▶", 18, Color(1, 1, 1, 0.7), false)
	hint.name = "SteerHint"
	_add_button("Accelerate", "", "accelerate", Color(0.12, 0.5, 0.18, 0.78), "accel")
	_add_button("Brake", "", "brake", Color(0.68, 0.12, 0.1, 0.78), "brake")
	_add_button("Gear", "", "gear_toggle", Color(0.16, 0.18, 0.22, 0.8), "gear_d")
	_add_button("Handbrake", "", "handbrake", Color(0.3, 0.3, 0.3, 0.7), "handbrake")
	_add_button("Horn", "", "horn", Color(0.95, 0.7, 0.05, 0.82), "horn")
	_add_button("IndicatorLeft", "", "indicator_left", INDICATOR_OFF, "ind_left")
	_add_button("IndicatorRight", "", "indicator_right", INDICATOR_OFF, "ind_right")
	_add_button("KickStart", "KICK", "kick_start", Color(0.55, 0.36, 0.1, 0.9), "kick")
	_add_button("Camera", "", "camera_cycle", Color(0.2, 0.2, 0.45, 0.7), "camera")
	_add_button("Wiper", "", "", Color(0.2, 0.35, 0.45, 0.7), "wiper")
	_add_button("SteerLeft", "◀", "steer_left", Color(0.2, 0.2, 0.24, 0.72))
	_add_button("SteerRight", "▶", "steer_right", Color(0.2, 0.2, 0.24, 0.72))

func _add_button(button_name: String, text: String, action: String, colour: Color, icon: String = "") -> void:
	var panel: Panel = _make_panel(button_name + "Panel", colour)
	var sb: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(2)
	var icon_rect: TextureRect = null
	if icon != "":
		icon_rect = TextureRect.new()
		icon_rect.name = button_name + "Icon"
		icon_rect.texture = _icon(icon)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icons.add_child(icon_rect)
	var label: Label = _make_label(text, 16 if icon != "" else 44, Color.WHITE, false)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if icon != "" else VERTICAL_ALIGNMENT_CENTER
	# Inert marker: input is handled in _input() so a press acts on touch-down.
	var touch: TouchScreenButton = TouchScreenButton.new()
	touch.name = button_name
	add_child(touch)
	_buttons[button_name] = {"panel": panel, "touch": touch, "label": label, "icon": icon_rect, "action": action}

func _icon(icon_name: String) -> AtlasTexture:
	var idx: int = int(ICONS[icon_name])
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = _icon_tex
	at.region = Rect2((idx % 8) * ICON_CELL, (idx / 8) * ICON_CELL, ICON_CELL, ICON_CELL)
	return at

func _set_button_visible(button_name: String, on: bool) -> void:
	var e: Dictionary = _buttons[button_name]
	(e["panel"] as Panel).visible = on
	(e["label"] as Label).visible = on
	(e["touch"] as TouchScreenButton).visible = on
	if e["icon"] != null:
		(e["icon"] as TextureRect).visible = on
	if not on:
		_force_release(button_name)

func _make_panel(panel_name: String, colour: Color) -> Panel:
	var p: Panel = Panel.new()
	p.name = panel_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(16)
	p.add_theme_stylebox_override("panel", sb)
	_panels.add_child(p)
	return p

func _make_label(text: String, size: int, colour: Color, outline: bool = true) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if outline:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texts.add_child(l)
	return l

# --- Layout ------------------------------------------------------------------

## Screen-space insets for notches / rounded corners, in canvas units.
func _safe_margins() -> Vector4:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var screen: Vector2 = Vector2(DisplayServer.screen_get_size())
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if screen.x <= 0.0 or safe.size.x <= 0 or OS.get_name() != "Android":
		return Vector4.ZERO
	var k: Vector2 = vp / screen
	return Vector4(safe.position.x * k.x, safe.position.y * k.y,
		(screen.x - safe.end.x) * k.x, (screen.y - safe.end.y) * k.y)

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var safe: Vector4 = _safe_margins()
	var ml: float = 26.0 + safe.x
	var mt: float = 20.0 + safe.y
	var mr: float = 26.0 + safe.z
	var mb: float = 22.0 + safe.w
	var g: float = 14.0 # gap between controls
	var b: float = clampf(vp.y * 0.165, 84.0, 140.0) # base button size

	# Bottom-left: two big steer buttons, indicators just above them.
	var sl: Rect2 = Rect2(ml, vp.y - mb - b * 1.5, b * 1.3, b * 1.5)
	var sr: Rect2 = Rect2(sl.end.x + g, sl.position.y, b * 1.3, b * 1.5)
	_place_button("SteerLeft", sl)
	_place_button("SteerRight", sr)
	# Drag-to-steer zone (scheme 0) covers the same area.
	var steer: Rect2 = Rect2(sl.position, Vector2(sr.end.x - sl.position.x, sl.size.y))
	_place(_steer_zone, steer)
	_handlebar.size = Vector2(steer.size.x * 0.82, b * 0.3)
	_handlebar.position = Vector2(steer.size.x * 0.09, steer.size.y * 0.42)
	_handlebar.pivot_offset = _handlebar.size * 0.5
	var hint: Label = _texts.get_node("SteerHint") as Label
	hint.position = steer.position + Vector2(steer.size.x * 0.18, steer.size.y * 0.72)

	# Bottom-right: tall gas pedal at the edge, wider brake pedal beside it, handbrake further in.
	var accel: Rect2 = Rect2(vp.x - mr - b * 1.0, vp.y - mb - b * 1.95, b * 1.0, b * 1.95)
	var brake: Rect2 = Rect2(accel.position.x - g - b * 1.15, vp.y - mb - b * 1.5, b * 1.15, b * 1.5)
	var hbrake: Rect2 = Rect2(brake.position.x - g - b * 0.75, vp.y - mb - b * 0.75, b * 0.75, b * 0.75)
	_place_button("Accelerate", accel)
	_place_button("Brake", brake)
	_place_button("Handbrake", hbrake)
	_place_button("KickStart", Rect2(hbrake.position.x, hbrake.position.y - g - b * 0.8, b * 0.75, b * 0.8))

	# Top-left: D/R gear, horn, camera; wiper under the gear.
	var s: float = b * 0.78
	var gear_r: Rect2 = Rect2(ml, mt, s, s * 1.15)
	_place_button("Gear", gear_r)
	_place_button("Horn", Rect2(gear_r.end.x + g, mt, s * 1.1, s * 1.15))
	var cam: Rect2 = Rect2(gear_r.end.x + g * 2.0 + s * 1.1, mt, s, s * 0.8)
	_place_button("Camera", cam)
	# Indicators: a separate pair on the top row so they never look like steering.
	_place_button("IndicatorLeft", Rect2(cam.end.x + g * 2.0, mt, s * 0.85, s * 0.8))
	_place_button("IndicatorRight", Rect2(cam.end.x + g * 2.5 + s * 0.85, mt, s * 0.85, s * 0.8))
	_place_button("Wiper", Rect2(ml, gear_r.end.y + g, s, s * 0.8))

	# Bottom centre: speedometer | mini-map (PassengerHUD) | LPG dial.
	var map_half: float = PassengerHUD.MINIMAP_SIZE * 0.5
	var cx: float = vp.x * 0.5
	var r_speed: float = clampf(b * 0.62, 56.0, 84.0)
	var r_fuel: float = r_speed * 0.68
	_dash.speed_centre = Vector2(cx - map_half - g - r_speed, vp.y - mb - r_speed)
	_dash.fuel_centre = Vector2(cx + map_half + g + r_fuel, vp.y - mb - r_fuel)
	_dash.speed_radius = r_speed
	_dash.fuel_radius = r_fuel
	_dash.queue_redraw()
	_speed_label.position = _dash.speed_centre + Vector2(-r_speed, r_speed * 0.18)
	_speed_label.size = Vector2(r_speed * 2.0, 40.0)
	var kmh: Label = _texts.get_node("KmhCaption") as Label
	kmh.position = _dash.speed_centre + Vector2(-r_speed, r_speed * 0.62)
	kmh.size = Vector2(r_speed * 2.0, 20.0)
	var lpg: Label = _texts.get_node("LpgCaption") as Label
	lpg.position = _dash.fuel_centre + Vector2(-r_fuel, r_fuel * 0.35)
	lpg.size = Vector2(r_fuel * 2.0, 20.0)

	# Meter flag sits under the wallet on the right.
	_meter_label.position = Vector2(vp.x - mr - 240.0, 180.0 + safe.y)
	_meter_label.size = Vector2(240.0, 64.0)
	_status_label.position = Vector2(0.0, vp.y * 0.22)
	_status_label.size = Vector2(vp.x, 50.0)

func _place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size

func _place_button(button_name: String, r: Rect2) -> void:
	var entry: Dictionary = _buttons[button_name]
	_place(entry["panel"] as Panel, r)
	var lbl: Label = entry["label"] as Label
	lbl.position = r.position
	lbl.size = r.size
	var t: TouchScreenButton = entry["touch"] as TouchScreenButton
	t.position = r.position
	if entry["icon"] != null:
		var ic: TextureRect = entry["icon"] as TextureRect
		var has_text: bool = lbl.text != ""
		var side: float = minf(r.size.x, r.size.y) * (0.6 if has_text else 0.7)
		ic.size = Vector2(side, side)
		ic.position = r.position + Vector2((r.size.x - side) * 0.5, (r.size.y - side) * (0.35 if has_text else 0.5))
		lbl.position.y -= 6.0

# --- Touch input (per finger, acts on touch-down) ----------------------------

func set_control_scheme(scheme: int) -> void:
	control_scheme = clampi(scheme, 0, 2)
	var drag: bool = control_scheme == 0
	_steer_zone.visible = drag
	for n: String in ["SteerLeft", "SteerRight"]:
		var e: Dictionary = _buttons[n]
		var on: bool = control_scheme == 1
		(e["panel"] as Panel).visible = on
		(e["label"] as Label).visible = on
		(e["touch"] as TouchScreenButton).visible = on
		if not on:
			_force_release(n)
	var hint: Label = _texts.get_node("SteerHint") as Label
	hint.visible = control_scheme != 1
	hint.text = "◀  drag to steer  ▶" if drag else "tilt phone to steer"
	if not drag:
		_steer_touch_index = -1
	if control_scheme != 2:
		set_steer(0.0)

## Which visible button is under `pos` (padded hit areas; the closest centre wins).
func button_at(pos: Vector2) -> String:
	var best: String = ""
	var best_d: float = INF
	for n: String in _buttons:
		var e: Dictionary = _buttons[n]
		var p: Panel = e["panel"] as Panel
		if not p.visible:
			continue
		var r: Rect2 = Rect2(p.position, p.size)
		if not r.grow(HIT_PAD).has_point(pos):
			continue
		var d: float = pos.distance_squared_to(r.get_center())
		if r.has_point(pos):
			d *= 0.25 # a direct hit beats a padded neighbour
		if d < best_d:
			best_d = d
			best = n
	return best

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			_touch_down(st.index, st.position)
		else:
			_touch_up(st.index)
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		_touch_move(sd.index, sd.position)

func _touch_down(index: int, pos: Vector2) -> void:
	if control_scheme == 0 and _steer_touch_index == -1 and _steer_zone.get_global_rect().grow(HIT_PAD).has_point(pos):
		_steer_touch_index = index
		_steer_touch_origin_x = pos.x
		return
	var hit: String = button_at(pos)
	if hit != "":
		_finger_on(index, hit)

func _touch_move(index: int, pos: Vector2) -> void:
	if index == _steer_touch_index:
		# Gentle curve: fine control near centre, full lock at the edge.
		var raw: float = clampf((pos.x - _steer_touch_origin_x) / STEER_DRAG_RANGE_PX, -1.0, 1.0)
		set_steer(signf(raw) * pow(absf(raw), 1.4))
		return
	var cur: String = str(_fingers.get(index, ""))
	if cur != "" and not SLIDEABLE.has(cur):
		return # tap buttons stay pressed until the finger lifts
	var hit: String = button_at(pos)
	if hit == cur:
		return
	if hit != "" and not SLIDEABLE.has(hit):
		hit = ""
	if cur != "":
		_finger_off(index)
	if hit != "":
		_finger_on(index, hit)

func _touch_up(index: int) -> void:
	if index == _steer_touch_index:
		_steer_touch_index = -1
		set_steer(0.0)
		return
	if _fingers.has(index):
		_finger_off(index)

func _finger_on(index: int, button_name: String) -> void:
	_fingers[index] = button_name
	var n: int = int(_held.get(button_name, 0)) + 1
	_held[button_name] = n
	if n == 1:
		_press(button_name)

func _finger_off(index: int) -> void:
	var button_name: String = str(_fingers[index])
	_fingers.erase(index)
	var n: int = int(_held.get(button_name, 1)) - 1
	if n <= 0:
		_held.erase(button_name)
		_release(button_name)
	else:
		_held[button_name] = n

func _press(button_name: String) -> void:
	var e: Dictionary = _buttons[button_name]
	(e["panel"] as Panel).modulate = PRESSED_TINT
	var action: String = str(e["action"])
	if button_name == "Wiper":
		_toggle_wiper()
	elif action != "":
		Input.action_press(action)
	if button_name == "SteerLeft" or button_name == "SteerRight":
		steer_value = -1.0 if button_name == "SteerLeft" else 1.0
	if OS.get_name() == "Android" and bool(GameState.settings.get("vibration", true)):
		Input.vibrate_handheld(12)

func _release(button_name: String) -> void:
	var e: Dictionary = _buttons[button_name]
	(e["panel"] as Panel).modulate = Color.WHITE
	var action: String = str(e["action"])
	if action != "":
		Input.action_release(action)
	if (button_name == "SteerLeft" or button_name == "SteerRight") and not _held.has("SteerLeft") and not _held.has("SteerRight"):
		steer_value = 0.0

## Drop every finger holding this button (it was hidden or the scheme changed).
func _force_release(button_name: String) -> void:
	if not _held.has(button_name):
		return
	for i: int in _fingers.keys():
		if str(_fingers[i]) == button_name:
			_fingers.erase(i)
	_held.erase(button_name)
	_release(button_name)

func release_all() -> void:
	for n: String in _held.keys():
		_force_release(n)
	_fingers.clear()
	if _steer_touch_index != -1:
		_steer_touch_index = -1
		set_steer(0.0)

## Tilt steering: phone held landscape like a handlebar. Gravity along the device's
## Y axis grows as it's rolled; flip for reverse-landscape.
func _tilt_steer() -> void:
	var gv: Vector3 = Input.get_gravity()
	if gv.length_squared() < 0.01:
		return # no sensor (desktop / emulator)
	var flip: float = -1.0 if DisplayServer.screen_get_orientation() == DisplayServer.SCREEN_REVERSE_LANDSCAPE else 1.0
	set_steer(clampf(gv.y / 5.5, -1.0, 1.0) * flip)

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
	_speed_label.text = "%d" % roundi(absf(speed))
	_dash.speed_kmh = absf(speed)
	_meter_label.text = "METER\nFOR HIRE" if _ride_fare < 0 else "METER  ₹%d\nhired" % _ride_fare
	var cap: float = maxf(data.get("lpg_capacity", 1.0), 0.001)
	_lpg_bar.value = float(data.get("lpg_liters", cap)) / cap
	_dash.lpg = _lpg_bar.value
	_dash.queue_redraw()
	if data.get("is_stalled", false):
		_set_button_visible("KickStart", true)
		if _status_timer <= 0.0:
			_status_label.text = "Engine flooded! Tap KICK"

func _on_stalled(_pos: Vector3) -> void:
	_flash("Engine flooded! Tap KICK in a steady rhythm", 3.0)
	_set_button_visible("KickStart", true)

func _on_gear_changed(g: int) -> void:
	gear = g
	var e: Dictionary = _buttons["Gear"]
	(e["icon"] as TextureRect).texture = _icon("gear_r" if g < 0 else "gear_d")
	((e["panel"] as Panel).get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.85, 0.85, 0.88, 0.9) if g < 0 else Color(0.16, 0.18, 0.22, 0.8)
	(e["icon"] as TextureRect).modulate = Color(0.1, 0.1, 0.12) if g < 0 else Color.WHITE
	_flash(tr("GEAR_REVERSE") if g < 0 else tr("GEAR_DRIVE"), 1.2)

## Blink the indicator button with the lamps; the other side stays dark.
func _on_indicator_blink(d: int, lamp_on: bool) -> void:
	for side: int in [-1, 1]:
		var e: Dictionary = _buttons["IndicatorLeft" if side < 0 else "IndicatorRight"]
		var lit: bool = d == side and lamp_on
		((e["panel"] as Panel).get_theme_stylebox("panel") as StyleBoxFlat).bg_color = INDICATOR_ON if lit else (Color(0.12, 0.35, 0.16, 0.85) if d == side else INDICATOR_OFF)

func _refresh_wiper_visibility() -> void:
	_set_button_visible("Wiper", GameState.is_raining or wiper_on)

func _on_kick_attempt(ratio: float) -> void:
	_flash("Kick… %d%%" % roundi(ratio * 100.0), 1.0)

func _toggle_wiper() -> void:
	wiper_on = not wiper_on
	SignalBus.wiper_toggled.emit(wiper_on)
	_flash("Wiper " + ("ON" if wiper_on else "OFF"), 1.0)
	_refresh_wiper_visibility()

func _flash(text: String, seconds: float) -> void:
	_status_label.text = text
	_status_timer = seconds
