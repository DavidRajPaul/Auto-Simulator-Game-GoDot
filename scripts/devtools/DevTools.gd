class_name DevTools
extends Node
## DEV ONLY. Developer panel for testing on a phone or PC: switch weather and time of day, freeze or
## speed up the clock, refuel / repair / add cash, switch the Monsoon flood on and off.
##
## ####  THIS FILE MUST NEVER REACH A RELEASE  ####
## * It exists on `main` only. Every `release/<major>.<minor>` branch (e.g. release/1.1) has this
##   folder deleted: run `python3 tools/release/strip_devtools.py` as the first commit on the branch.
## * CI (tools/release/check_no_devtools.py) fails any release/* branch or v* tag that still has it,
##   and the signed release APK / AAB are built after the same script strips it.
## * At runtime it is also inert unless OS.is_debug_build() is true.
## * Its only entry point is the two lines marked DEVTOOLS-HOOK in autoloads/FrameGuard.gd. Nothing
##   else may mention it (the check enforces this), so stripping is a folder delete plus those lines.
## Rules: AGENTS.md "Rule 7: Dev tools are main-only". Guide: docs/DEV_TOOLS.md.

## The panel shows only while this scene is the current scene (tests set their own scene's name).
var main_scene_name: String = "MainChennai"

const SCAN_S: float = 0.5
const STORM_HALF_WINDOW_MIN: float = 360.0
const FLOOD_FILE: String = "res://data/missions/floods/sq_017.json"
const CASH_STEP: int = 5000
const TIMES: Array = [["Dawn 6:00", 360.0], ["9 AM", 540.0], ["Noon", 720.0], ["4 PM", 960.0], ["Dusk 6:30", 1110.0], ["Night 8 PM", 1200.0]]
const FAST_FORWARD: float = 8.0

var _layer: CanvasLayer
var _panel: PanelContainer
var _status: Label
var _scan_left: float = 0.0
## "auto" = the day's own roll, otherwise "dry", "rain" or "storm".
var _mode: String = "auto"
## 0 = clock frozen, 1 = normal, FAST_FORWARD = fast.
var _speed: float = 1.0
var _frozen_minute: float = 0.0
var _flood_on: bool = false

func _ready() -> void:
	name = "DevTools"
	if not OS.is_debug_build():
		set_process(false)
		queue_free()
		return
	process_priority = 100 # after GameState's own clock tick, so freeze and fast-forward win

func is_open() -> bool:
	return _panel != null and _panel.visible

func has_panel() -> bool:
	return _layer != null

func _process(delta: float) -> void:
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN_S
		_sync_panel()
	if _layer == null or get_tree().paused:
		return
	if _speed == 0.0:
		GameState.shift_minute = _frozen_minute
	elif _speed > 1.0 and GameState.shift_running:
		var extra: float = delta * GameState.GAME_MIN_PER_SECOND * (_speed - 1.0)
		# Never run past the last minute: ending the shift by accident would lose the test setup.
		GameState.shift_minute = minf(GameState.shift_minute + extra, GameState.SHIFT_END_MIN - 1.0)

# --- Weather -------------------------------------------------------------------------------------

func set_weather(mode: String) -> void:
	_mode = mode
	_apply_weather()

func _apply_weather() -> void:
	var now: float = GameState.shift_minute
	match _mode:
		"dry":
			GameState.thunder_override = 0
			GameState.rain_window = Vector2(-1.0, -1.0)
		"rain":
			GameState.thunder_override = 0
			GameState.rain_window = Vector2(now - STORM_HALF_WINDOW_MIN, now + STORM_HALF_WINDOW_MIN)
		"storm":
			# Centred on now, so the storm is at its closest and strongest (Thunderstorm.gd).
			GameState.thunder_override = 1
			GameState.rain_window = Vector2(now - STORM_HALF_WINDOW_MIN, now + STORM_HALF_WINDOW_MIN)
		_:
			GameState.thunder_override = -1
			GameState.roll_weather()
	GameState._update_weather()

# --- Time ----------------------------------------------------------------------------------------

func set_time(minute: float) -> void:
	GameState.shift_minute = minute
	_frozen_minute = minute
	_apply_weather() # keep the storm centred on the new time
	SignalBus.shift_clock_updated.emit(GameState.day, GameState.shift_minute)

func set_speed(speed: float) -> void:
	_speed = speed
	_frozen_minute = GameState.shift_minute

# --- Player and world ----------------------------------------------------------------------------

func refuel() -> void:
	var a: AutoRickshawController = get_tree().get_first_node_in_group("player_auto") as AutoRickshawController
	if a != null:
		a.fuel_level = a.stats.fuel_capacity

func repair() -> void:
	GameState.repair_free()

func add_cash() -> void:
	GameState.add_inr(CASH_STEP, false)

func toggle_flood() -> void:
	_flood_on = not _flood_on
	SignalBus.quest_flood_requested.emit(FLOOD_FILE if _flood_on else "")

# --- Panel ---------------------------------------------------------------------------------------

func _sync_panel() -> void:
	var scene: Node = get_tree().current_scene
	var wanted: bool = scene != null and scene.name == main_scene_name
	if wanted and _layer == null:
		_build()
	elif not wanted and _layer != null:
		_teardown()
	if _layer != null and _panel.visible:
		_status.text = "%s   day %d\nrain %s   storm %s   clock %s\nflood %s" % [
			GameState.clock_text(), GameState.day,
			"yes" if GameState.is_raining else "no", "yes" if GameState.is_thunderstorm() else "no",
			"frozen" if _speed == 0.0 else ("x%d" % int(_speed)),
			"on" if _flood_on else "off"]

func _teardown() -> void:
	if _layer != null:
		_layer.queue_free()
	_layer = null
	_panel = null
	_status = null

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "DevToolsLayer"
	_layer.layer = 40
	add_child(_layer)

	var toggle: Button = Button.new()
	toggle.text = "DEV"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 20)
	toggle.anchor_left = 0.5
	toggle.anchor_right = 0.5
	toggle.offset_left = -40.0
	toggle.offset_right = 40.0
	toggle.offset_top = 6.0
	toggle.offset_bottom = 50.0
	toggle.modulate = Color(1.0, 0.55, 0.2, 0.85)
	toggle.pressed.connect(_on_toggle)
	_layer.add_child(toggle)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -470.0
	_panel.offset_right = -8.0
	_panel.offset_top = 56.0
	_panel.offset_bottom = -8.0
	_layer.add_child(_panel)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title: Label = Label.new()
	title.text = "DEV TOOLS - debug builds on main only"
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color(1.0, 0.7, 0.3)
	box.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	box.add_child(_status)

	var weather: GridContainer = _section(box, "Weather")
	_button(weather, "Auto", func() -> void: set_weather("auto"))
	_button(weather, "Dry", func() -> void: set_weather("dry"))
	_button(weather, "Rain", func() -> void: set_weather("rain"))
	_button(weather, "Storm + lightning", func() -> void: set_weather("storm"))
	_button(weather, "Flood on/off", toggle_flood)

	var time: GridContainer = _section(box, "Time of day")
	for t: Array in TIMES:
		var minute: float = float(t[1])
		_button(time, str(t[0]), func() -> void: set_time(minute))

	var clock: GridContainer = _section(box, "Clock")
	_button(clock, "Freeze", func() -> void: set_speed(0.0))
	_button(clock, "Normal", func() -> void: set_speed(1.0))
	_button(clock, "Fast x8", func() -> void: set_speed(FAST_FORWARD))

	var player: GridContainer = _section(box, "Player")
	_button(player, "Refuel", refuel)
	_button(player, "Repair", repair)
	_button(player, "+₹%d" % CASH_STEP, add_cash)

func _on_toggle() -> void:
	if _panel != null:
		_panel.visible = not _panel.visible
		_scan_left = 0.0

func _section(parent: Control, text: String) -> GridContainer:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	parent.add_child(l)
	var g: GridContainer = GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	parent.add_child(g)
	return g

func _button(parent: Control, text: String, cb: Callable) -> void:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 52.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	parent.add_child(b)
