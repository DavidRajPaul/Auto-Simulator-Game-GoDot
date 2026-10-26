class_name MainMenu
extends Node3D
## Title screen: Continue / New career / Settings / Credits / Quit, over a slowly turning auto
## in front of a Chennai sunset skyline. Starting the game goes through LoadingScreen.
## Built in code (like the other HUDs) so it scales with the viewport and stays theme-free.

const GAME_SCENE: String = "res://scenes/main_chennai.tscn"
const AMBER: Color = Color(1.0, 0.72, 0.1)
## Painted game logo (1G); it includes the Tamil subtitle.
const LOGO: String = "res://assets/ui/logo.png"
const PANEL_BG: Color = Color(0.06, 0.06, 0.07, 0.9)
const SPIN_RAD_PER_S: float = 0.35
const CREDITS: String = """Namma Auto — Chennai Rickshaw Simulator 3D

Map data © OpenStreetMap contributors, available under the Open Database Licence (ODbL).
Road and lane geometry: osm2streets by the A/B Street project (Apache-2.0).
Game engine: Godot Engine (MIT). Physics: Jolt Physics (MIT).
Fonts: Noto Sans Tamil and Baloo Thambi 2, SIL Open Font License 1.1.
UI sounds: Kenney Interface Sounds (CC0). Ambience and horns: BigSoundBank, Joseph Sardin (CC0).
Auto engine and kick-start sounds: kalhan, Freesound (CC BY 4.0). Bulb horn: alex_jauk, Pixabay.
Indicator tick: ProductionNow, Freesound (CC0). Air horn: goose278, Freesound (CC0).
Traffic models: Kenney Car Kit (CC0), Cow by Quaternius (CC0). Auto rickshaw by rSquare, Indian Scooter by Shiveloper and Cow - LowPoly by Fadly.W (Sketchfab, CC BY 4.0).
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
	var sfx: UISfx = UISfx.new()
	sfx.name = "UISfx"
	add_child(sfx)
	SignalBus.back_requested.connect(_on_back)
	SignalBus.settings_changed.connect(func(_s: Dictionary) -> void: _refresh_texts())
	get_viewport().size_changed.connect(_layout)
	_layout()
	AdMonetizationManager.set_screen("main_menu")
	# A claimable daily bonus greets the player once per day.
	if bool(GameState.daily_reward_status()["available"]) and GameState.has_save():
		open_daily.call_deferred()

func _process(delta: float) -> void:
	if _auto != null:
		_auto.rotate_y(delta * SPIN_RAD_PER_S)

# --- Actions ---------------------------------------------------------------------------------

func start_game() -> void:
	GameState.shift_running = true
	LoadingScreen.go(get_tree(), GAME_SCENE)

func continue_game() -> void:
	start_game()

## 7-day stand bonus calendar (RewardsEngine): today's tile highlighted, day 7 = jackpot.
func open_daily() -> void:
	var st: Dictionary = GameState.daily_reward_status()
	_open_panel(tr("DAILY_REWARD"))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_panel_body.add_child(row)
	var today_idx: int = int(st["day_index"])
	for i: int in 7:
		var tile: Label = _label("%s\n₹%d" % [tr("DAY_N") % (i + 1), RewardsEngine.DAILY_INR[i]], 20,
			Color(0.08, 0.05, 0.02) if i == today_idx and bool(st["available"]) else (Color(0.6, 0.6, 0.6) if i < today_idx or (i == today_idx and not bool(st["available"])) else Color.WHITE))
		tile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.custom_minimum_size = Vector2(96, 76)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = AMBER if i == today_idx and bool(st["available"]) else Color(0.18, 0.16, 0.2)
		sb.set_corner_radius_all(10)
		tile.add_theme_stylebox_override("normal", sb)
		row.add_child(tile)
	if bool(st["available"]):
		_panel_body.add_child(_button("%s  ₹%d" % [tr("CLAIM"), int(st["inr"])], AMBER, func() -> void:
			GameState.claim_daily_reward()
			close_panel(), 30, Color(0.08, 0.05, 0.02)))
	else:
		_panel_text("Come back tomorrow — streak: %d day(s)." % GameState.rewards.streak)

func open_achievements() -> void:
	_open_panel(tr("ACHIEVEMENTS"))
	for id: String in RewardsEngine.ACHIEVEMENTS:
		var a: Dictionary = RewardsEngine.ACHIEVEMENTS[id]
		var done: bool = GameState.rewards.achieved.has(id)
		var pct: int = roundi(GameState.rewards.achievement_progress(id) * 100.0)
		_panel_text("%s  %s — %s   %s" % ["🏆" if done else "▫", str(a["title"]), str(a["desc"]), "✓" if done else "%d%%  (+₹%d)" % [pct, int(a["inr"])]])

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
	# The 2D skyline (CanvasLayer -1) shows through behind the 3D auto.
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.42, 0.4)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var back: CanvasLayer = CanvasLayer.new()
	back.layer = -1
	add_child(back)
	back.add_child(ChennaiBackdrop.new())
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
	gm.albedo_color = Color(0.12, 0.1, 0.12)
	disc.material = gm
	ground.mesh = disc
	ground.position = Vector3(0, -0.03, 0)
	add_child(ground)
	# The auto the player drives: the real Chennai model in stock yellow, else the procedural one.
	_auto = Node3D.new()
	_auto.position = Vector3(0, 0.8, 0)
	add_child(_auto)
	var body: Node3D = Node3D.new()
	body.set_script(load("res://scripts/vehicle/AutoRickshawModel.gd"))
	var st: VehicleStats = GameState.active_stats()
	body.set("paint", st.body_colour)
	body.set("trim", st.canopy_colour)
	_auto.add_child(body)
	if bool(body.get("uses_real_model")):
		return # the model's wheels are part of the body
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
	_menu.add_theme_constant_override("separation", 12)
	_root.add_child(_menu)
	if ResourceLoader.exists(LOGO):
		var logo: TextureRect = TextureRect.new()
		logo.name = "Logo"
		logo.texture = load(LOGO) as Texture2D
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.custom_minimum_size = Vector2(0, 200)
		_menu.add_child(logo)
	else:
		_menu.add_child(_label("NAMMA AUTO", 80, AMBER, 12))
		_menu.add_child(_label("நம்ம ஆட்டோ", 36, Color(1, 1, 1), 8))
	_buttons["tagline"] = _label(tr("TAGLINE"), 22, Color(1.0, 0.92, 0.82))
	_menu.add_child(_buttons["tagline"])
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	_menu.add_child(gap)
	var has_save: bool = GameState.has_save()
	if has_save:
		_menu.add_child(_profile_card())
		_buttons["continue"] = _button("▶  " + tr("CONTINUE"), AMBER, continue_game, 34, Color(0.08, 0.05, 0.02))
		_buttons["continue"].custom_minimum_size = Vector2(0, 88)
		_menu.add_child(_buttons["continue"])
		_buttons["new"] = _button(tr("NEW_GAME"), Color(0.22, 0.2, 0.24, 0.92), new_career)
	else:
		_buttons["new"] = _button("▶  " + tr("NEW_GAME"), AMBER, new_career, 34, Color(0.08, 0.05, 0.02))
		_buttons["new"].custom_minimum_size = Vector2(0, 88)
		_menu.add_child(_buttons["new"])
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_menu.add_child(row)
	_buttons["settings"] = _button(tr("SETTINGS"), Color(0.22, 0.2, 0.24, 0.92), open_settings)
	_buttons["credits"] = _button(tr("CREDITS"), Color(0.22, 0.2, 0.24, 0.92), open_credits)
	var secondary: Array[String] = ["settings", "credits"]
	if has_save:
		secondary.push_front("new")
	for k: String in secondary:
		(_buttons[k] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_buttons[k])
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	_menu.add_child(row2)
	_buttons["daily"] = _button("🎁 " + tr("DAILY_REWARD"), Color(0.55, 0.32, 0.05, 0.92), open_daily)
	_buttons["achievements"] = _button("🏆 " + tr("ACHIEVEMENTS"), Color(0.22, 0.2, 0.24, 0.92), open_achievements)
	for k: String in ["daily", "achievements"]:
		(_buttons[k] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(_buttons[k])
	_buttons["hint"] = _label(tr("MENU_HINT"), 18, Color(1.0, 0.92, 0.82))
	_buttons["hint"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu.add_child(_buttons["hint"])
	# Quit sits in the corner, away from the thumb's path to Play.
	_buttons["quit"] = _button(tr("QUIT"), Color(0.3, 0.12, 0.12, 0.85), func() -> void: get_tree().quit(), 20)
	_buttons["quit"].custom_minimum_size = Vector2(120, 52)
	_root.add_child(_buttons["quit"])

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
	_menu.position = Vector2(maxf(40.0, vp.x * 0.06), maxf(20.0, vp.y * 0.06))
	_menu.custom_minimum_size = Vector2(minf(520.0, vp.x * 0.42), 0)
	_menu.size = _menu.custom_minimum_size
	(_buttons["quit"] as Button).position = Vector2(vp.x - 24.0 - 120.0, 20.0)
	_panel.custom_minimum_size = Vector2(minf(820.0, vp.x - 40.0), minf(560.0, vp.y - 40.0))
	_panel.position = (vp - _panel.custom_minimum_size) * 0.5

func _refresh_texts() -> void:
	var keys: Dictionary = {"continue": "CONTINUE", "new": "NEW_GAME", "settings": "SETTINGS", "credits": "CREDITS",
		"quit": "QUIT", "back": "BACK", "tagline": "TAGLINE", "hint": "MENU_HINT"}
	var primary: String = "continue" if _buttons.has("continue") else "new"
	for k: String in keys:
		if _buttons.has(k):
			_buttons[k].set("text", ("▶  " if k == primary else "") + tr(str(keys[k])))

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

## Wallet, rating and driver level from the save, above the Continue button.
func _profile_card() -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.06, 0.72)
	sb.border_color = Color(1.0, 0.72, 0.1, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14.0)
	card.add_theme_stylebox_override("panel", sb)
	var lvl: int = GameState.progress.level()
	var text: String = "₹%d   ★%.1f   %s %d · %s   %s %d" % [GameState.wallet_inr, GameState.star_rating, tr("LEVEL"), lvl,
		DriverProgress.title(lvl), tr("DAY"), GameState.day]
	var l: Label = _label(text, 22, Color.WHITE, 0)
	card.add_child(l)
	_buttons["profile"] = card
	return card

func _label(text: String, size: int, colour: Color, outline: int = 6) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.02, 0.05))
	l.add_theme_constant_override("outline_size", outline)
	return l

func _button(text: String, colour: Color, on_press: Callable, font_size: int = 24, font_colour: Color = Color.WHITE) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", font_size)
	for st: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, font_colour)
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
