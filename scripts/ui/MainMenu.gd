class_name MainMenu
extends Node3D
## Title screen: Continue / New career / Settings / Credits / Quit, over a slowly turning auto.
## Built in code (like the other HUDs) so it scales with the viewport and stays theme-free.

const GAME_SCENE: String = "res://scenes/main_chennai.tscn"
const AMBER: Color = Color(1.0, 0.72, 0.1)
const PANEL_BG: Color = Color(0.06, 0.06, 0.07, 0.9)
const SPIN_RAD_PER_S: float = 0.35
const CREDITS: String = """Namma Auto — Chennai Rickshaw Simulator 3D

Map data © OpenStreetMap contributors, available under the Open Database Licence (ODbL).
Road and lane geometry: osm2streets by the A/B Street project (Apache-2.0).
Game engine: Godot Engine (MIT). Physics: Jolt Physics (MIT).
Tamil font: Noto Sans Tamil, SIL Open Font License 1.1.
Build-time triangulation: earcut (ISC).

Made for every Chennai auto anna and akka. Drive safe, use the meter."""

var _auto: Node3D
var _root: Control
var _menu: VBoxContainer
var _panel: PanelContainer
var _panel_title: Label
var _panel_body: VBoxContainer
var _buttons: Dictionary = {}

func _ready() -> void:
	GameState.shift_running = false
	get_tree().paused = false
	_build_scene()
	_build_ui()
	SignalBus.back_requested.connect(_on_back)
	SignalBus.settings_changed.connect(func(_s: Dictionary) -> void: _refresh_texts())
	get_viewport().size_changed.connect(_layout)
	_layout()

func _process(delta: float) -> void:
	if _auto != null:
		_auto.rotate_y(delta * SPIN_RAD_PER_S)

# --- Actions ---------------------------------------------------------------------------------

func start_game() -> void:
	GameState.shift_running = true
	get_tree().change_scene_to_file(GAME_SCENE)

func continue_game() -> void:
	start_game()

func new_career() -> void:
	if GameState.has_save():
		_open_panel(tr("NEW_GAME"))
		_panel_text(tr("NEW_GAME_CONFIRM"))
		_panel_body.add_child(_button(tr("YES_START"), Color(0.6, 0.25, 0.15), func() -> void:
			GameState.new_career()
			start_game()))
		return
	GameState.new_career()
	start_game()

func open_settings() -> void:
	_open_panel(tr("SETTINGS"))
	var s: Dictionary = GameState.settings
	_choice(tr("LANGUAGE"), PackedStringArray(["English", "தமிழ்"]), 0 if str(s["language"]) == "en" else 1,
		func(i: int) -> void:
			GameState.set_setting("language", "en" if i == 0 else "ta")
			open_settings())
	_choice(tr("CONTROLS"), PackedStringArray([tr("CTRL_WHEEL"), tr("CTRL_ARCADE"), tr("CTRL_TILT")]), int(s["control_scheme"]),
		func(i: int) -> void:
			GameState.set_setting("control_scheme", i)
			open_settings())
	_choice(tr("GRAPHICS"), PackedStringArray([tr("GFX_LOW"), tr("GFX_MED"), tr("GFX_HIGH")]), int(s["graphics"]),
		func(i: int) -> void:
			GameState.set_setting("graphics", i)
			open_settings())

func open_credits() -> void:
	_open_panel(tr("CREDITS"))
	_panel_text(CREDITS)

func close_panel() -> void:
	_panel.visible = false
	_menu.visible = true

func _on_back() -> void:
	if _panel.visible:
		close_panel()
	else:
		get_tree().quit()

# --- 3D backdrop -----------------------------------------------------------------------------

func _build_scene() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.09, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.42, 0.4)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.78, 0.55) # Marina sunset
	sun.light_energy = 1.1
	sun.rotation = Vector3(-0.5, 0.9, 0.0)
	add_child(sun)
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(-2.6, 1.7, 6.4)
	cam.fov = 45.0
	add_child(cam)
	cam.look_at(Vector3(-1.9, 0.6, 0.0), Vector3.UP)
	cam.current = true
	var ground: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 2.6
	disc.bottom_radius = 2.6
	disc.height = 0.06
	disc.radial_segments = 40
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.22, 0.24)
	disc.material = gm
	ground.mesh = disc
	ground.position = Vector3(0, -0.03, 0)
	add_child(ground)
	# The same procedural Bajaj RE the player drives, painted in their current colours.
	_auto = Node3D.new()
	_auto.position = Vector3(0, 0.8, 0)
	add_child(_auto)
	var body: Node3D = Node3D.new()
	body.set_script(load("res://scripts/vehicle/AutoRickshawModel.gd"))
	var st: VehicleStats = GameState.active_stats()
	body.set("paint", st.body_colour)
	body.set("trim", st.canopy_colour)
	_auto.add_child(body)
	for w: Array in [[Vector3(0, -0.64, -1.05), true], [Vector3(-0.58, -0.64, 0.88), false], [Vector3(0.58, -0.64, 0.88), false]]:
		var wheel: Node3D = Node3D.new()
		wheel.set_script(load("res://scripts/vehicle/WheelModel.gd"))
		wheel.set("is_front", w[1])
		wheel.position = w[0]
		_auto.add_child(wheel)

# --- UI --------------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 14)
	_root.add_child(_menu)
	_menu.add_child(_label("NAMMA AUTO", 64, AMBER))
	_menu.add_child(_label("நம்ம ஆட்டோ", 34, Color(1, 1, 1)))
	_buttons["tagline"] = _label(tr("TAGLINE"), 22, Color(0.85, 0.85, 0.85))
	_menu.add_child(_buttons["tagline"])
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_menu.add_child(gap)
	if GameState.has_save():
		_buttons["continue"] = _button(tr("CONTINUE"), Color(0.15, 0.5, 0.22), continue_game)
		_menu.add_child(_buttons["continue"])
	_buttons["new"] = _button(tr("NEW_GAME"), Color(0.75, 0.5, 0.05) if not GameState.has_save() else Color(0.3, 0.3, 0.34), new_career)
	_buttons["settings"] = _button(tr("SETTINGS"), Color(0.3, 0.3, 0.34), open_settings)
	_buttons["credits"] = _button(tr("CREDITS"), Color(0.3, 0.3, 0.34), open_credits)
	_buttons["quit"] = _button(tr("QUIT"), Color(0.35, 0.18, 0.18), func() -> void: get_tree().quit())
	for k: String in ["new", "settings", "credits", "quit"]:
		_menu.add_child(_buttons[k])
	_buttons["hint"] = _label(tr("MENU_HINT"), 18, Color(0.75, 0.75, 0.75))
	_buttons["hint"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu.add_child(_buttons["hint"])

	_panel = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(22.0)
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	_root.add_child(_panel)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	_panel.add_child(outer)
	var head: HBoxContainer = HBoxContainer.new()
	outer.add_child(head)
	_panel_title = _label("", 30, AMBER)
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_panel_title)
	_buttons["back"] = _button(tr("BACK"), Color(0.3, 0.3, 0.34), close_panel)
	_buttons["back"].custom_minimum_size = Vector2(140, 56)
	head.add_child(_buttons["back"])
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_panel_body = VBoxContainer.new()
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_panel_body)

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_menu.position = Vector2(maxf(40.0, vp.x * 0.07), maxf(24.0, vp.y * 0.08))
	_menu.custom_minimum_size = Vector2(minf(440.0, vp.x * 0.42), 0)
	_menu.size = _menu.custom_minimum_size
	_panel.custom_minimum_size = Vector2(minf(820.0, vp.x - 40.0), minf(560.0, vp.y - 40.0))
	_panel.position = (vp - _panel.custom_minimum_size) * 0.5

func _refresh_texts() -> void:
	var keys: Dictionary = {"continue": "CONTINUE", "new": "NEW_GAME", "settings": "SETTINGS", "credits": "CREDITS",
		"quit": "QUIT", "back": "BACK", "tagline": "TAGLINE", "hint": "MENU_HINT"}
	for k: String in keys:
		if _buttons.has(k):
			_buttons[k].set("text", tr(str(keys[k])))

func _open_panel(title: String) -> void:
	_panel_title.text = title
	for c: Node in _panel_body.get_children():
		c.queue_free()
	_menu.visible = false
	_panel.visible = true

func _panel_text(text: String) -> void:
	var l: Label = _label(text, 20, Color(0.92, 0.92, 0.92))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_child(l)

func _choice(title: String, options: PackedStringArray, selected: int, on_pick: Callable) -> void:
	_panel_body.add_child(_label(title, 22, AMBER))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for i: int in options.size():
		var idx: int = i
		var b: Button = _button(options[i], Color(0.15, 0.45, 0.2) if i == selected else Color(0.25, 0.25, 0.28), func() -> void: on_pick.call(idx))
		b.custom_minimum_size = Vector2(170, 58)
		row.add_child(b)
	_panel_body.add_child(row)

func _label(text: String, size: int, colour: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l

func _button(text: String, colour: Color, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 24)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = colour.lightened(0.2) if state == "pressed" else (colour.darkened(0.5) if state == "disabled" else colour)
		if state == "focus":
			sb.draw_center = false
			sb.border_color = AMBER
			sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(12.0)
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(on_press)
	return b
