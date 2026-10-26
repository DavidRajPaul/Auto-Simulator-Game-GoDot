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
Fonts: Bricolage Grotesque, Rubik, Noto Sans Tamil and Baloo Thambi 2, SIL Open Font License 1.1.
Game art and screens designed with Google Stitch for Namma Auto.
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
var _stats_card: PanelContainer
var _ticker: Label
var _tip_index: int = 0
var _top_chips: HBoxContainer
const TIP_KEYS: Array[String] = ["TIP_1", "TIP_2", "TIP_3", "TIP_4", "TIP_5", "TIP_6"]

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
	var available: bool = bool(st["available"])
	for i: int in 7:
		var today: bool = i == today_idx and available
		var claimed: bool = i < today_idx or (i == today_idx and not available)
		var tile: PanelContainer = PanelContainer.new()
		tile.custom_minimum_size = Vector2(100, 112)
		tile.add_theme_stylebox_override("panel", UIKit.button_box(UIKit.Tone.YELLOW if today else UIKit.Tone.DARK, "normal"))
		var col: VBoxContainer = VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		tile.add_child(col)
		var day: Label = UIKit.label(tr("DAY_N") % (i + 1), 15, UIKit.PLUM if today else UIKit.MUTED, true)
		day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(day)
		var icon: TextureRect = UIKit.reward_icon("tick" if claimed else ("gift" if i == 6 else "coins"), 40)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(icon)
		var amt: Label = UIKit.label("₹%d" % RewardsEngine.DAILY_INR[i], 17, UIKit.PLUM if today else UIKit.JASMINE, true)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(amt)
		if claimed:
			tile.modulate = Color(1, 1, 1, 0.55)
		row.add_child(tile)
		if today:
			UIKit.pulse(tile, 0.05)
	if available:
		var claim: Button = UIKit.button("%s  ₹%d" % [tr("CLAIM"), int(st["inr"])], UIKit.Tone.GREEN, func() -> void:
			GameState.claim_daily_reward()
			close_panel(), 26, "coin")
		claim.custom_minimum_size = Vector2(0, 68)
		_panel_body.add_child(claim)
	else:
		_panel_text(tr("DAILY_COME_BACK") % GameState.rewards.streak)

func open_achievements() -> void:
	_open_panel(tr("ACHIEVEMENTS"))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_body.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for id: String in RewardsEngine.ACHIEVEMENTS:
		var a: Dictionary = RewardsEngine.ACHIEVEMENTS[id]
		var done: bool = GameState.rewards.achieved.has(id)
		var prog: float = GameState.rewards.achievement_progress(id)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)
		row.add_child(UIKit.reward_icon("badge_gold" if done else "lock", 44))
		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 2)
		row.add_child(text)
		text.add_child(UIKit.label(str(a["title"]), 19, UIKit.YELLOW if done else UIKit.JASMINE, true))
		var desc: Label = UIKit.label(str(a["desc"]), 15, UIKit.MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(desc)
		text.add_child(UIKit.bar(prog, UIKit.GREEN if done else UIKit.YELLOW))
		row.add_child(UIKit.chip("tick" if done else "coin", "✓" if done else "₹%d" % int(a["inr"]), 16))

func new_career() -> void:
	if GameState.has_save():
		_open_panel(tr("NEW_GAME"))
		_panel_text(tr("NEW_GAME_CONFIRM"))
		_panel_body.add_child(UIKit.button(tr("YES_START"), UIKit.Tone.RED, func() -> void:
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
	_stats_card.visible = true

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
	# Glowing turntable rim (4A "pulse-ring").
	var rim: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 2.53
	torus.outer_radius = 2.6
	torus.rings = 48
	torus.ring_segments = 6
	var rm: StandardMaterial3D = StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.95, 0.5, 0.1)
	torus.material = rm
	rim.mesh = torus
	rim.position = Vector3(0, 0.01, 0)
	add_child(rim)
	var glow: Tween = create_tween().set_loops()
	glow.tween_property(rm, "albedo_color", Color(1.0, 0.75, 0.25), 1.25).set_trans(Tween.TRANS_SINE)
	glow.tween_property(rm, "albedo_color", Color(0.95, 0.5, 0.1), 1.25).set_trans(Tween.TRANS_SINE)
	# The auto the player drives: the real Chennai model in stock yellow, else the procedural one.
	_auto = Node3D.new()
	_auto.position = Vector3(0, 0.8, 0)
	add_child(_auto)
	# Hover bob (4A "arcade-bob", 3.2 s).
	var bob: Tween = create_tween().set_loops()
	bob.tween_property(_auto, "position:y", 0.86, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_auto, "position:y", 0.8, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
	_root.theme = UIKit.theme()
	layer.add_child(_root)
	var has_save: bool = GameState.has_save()
	var lvl: int = GameState.progress.level()

	# Left column (4A): logo, tagline, driver card, PLAY, secondary row.
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 14)
	_root.add_child(_menu)
	if ResourceLoader.exists(LOGO):
		var logo: TextureRect = TextureRect.new()
		logo.name = "Logo"
		logo.texture = load(LOGO) as Texture2D
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.custom_minimum_size = Vector2(0, 170)
		_menu.add_child(logo)
	else:
		_menu.add_child(UIKit.label("NAMMA AUTO", 72, UIKit.YELLOW, true, 10))
	_buttons["tagline"] = UIKit.label(tr("TAGLINE"), 20, UIKit.JASMINE, true, 6)
	_menu.add_child(_buttons["tagline"])
	_menu.add_child(_driver_card(lvl, has_save))
	var primary_key: String = "continue" if has_save else "new"
	var primary: Button = UIKit.button("▶  " + tr("CONTINUE" if has_save else "NEW_GAME"), UIKit.Tone.YELLOW,
		continue_game if has_save else new_career, 36)
	primary.custom_minimum_size = Vector2(0, 92)
	_buttons[primary_key] = primary
	_menu.add_child(primary)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_menu.add_child(row)
	if has_save:
		_buttons["new"] = UIKit.button(tr("NEW_GAME"), UIKit.Tone.ORANGE, new_career, 20)
	_buttons["settings"] = UIKit.button(tr("SETTINGS"), UIKit.Tone.PURPLE, open_settings, 20)
	_buttons["credits"] = UIKit.button(tr("CREDITS"), UIKit.Tone.PURPLE, open_credits, 20)
	for k: String in (["new", "settings", "credits"] if has_save else ["settings", "credits"]):
		(_buttons[k] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_buttons[k])
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	_menu.add_child(row2)
	_buttons["daily"] = UIKit.button(tr("DAILY_REWARD"), UIKit.Tone.GREEN, open_daily, 20, "gift")
	_buttons["achievements"] = UIKit.button(tr("ACHIEVEMENTS"), UIKit.Tone.PURPLE, open_achievements, 20, "badge_gold")
	for k: String in ["daily", "achievements"]:
		(_buttons[k] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(_buttons[k])
	_buttons["hint"] = UIKit.label(tr("MENU_HINT"), 16, UIKit.MUTED)
	_buttons["hint"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu.add_child(_buttons["hint"])

	# Top-right currency / rating / rank chips + quit.
	_top_chips = HBoxContainer.new()
	_top_chips.add_theme_constant_override("separation", 22)
	_root.add_child(_top_chips)
	_top_chips.add_child(UIKit.chip("coin", "₹" + UIKit.inr(GameState.wallet_inr)))
	_top_chips.add_child(UIKit.chip("star", "%.1f" % GameState.star_rating))
	_top_chips.add_child(UIKit.chip(UIKit.badge_for_level(lvl), "%s %d" % [tr("LV"), lvl]))
	_buttons["quit"] = UIKit.button(tr("QUIT"), UIKit.Tone.RED, func() -> void: get_tree().quit(), 18)
	_buttons["quit"].custom_minimum_size = Vector2(110, 56)
	_top_chips.add_child(_buttons["quit"])

	# Right: the auto's card above the turntable.
	_stats_card = _vehicle_card()
	_root.add_child(_stats_card)

	# Bottom ticker with rotating tips (4A footer).
	var bar: PanelContainer = PanelContainer.new()
	bar.name = "Ticker"
	bar.add_theme_stylebox_override("panel", UIKit.pill_box(Color(UIKit.PLUM, 0.9), UIKit.PLUM))
	_root.add_child(bar)
	_ticker = UIKit.label("", 17, UIKit.JASMINE)
	_ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_ticker)
	_next_tip()
	var t: Timer = Timer.new()
	t.wait_time = 4.5
	t.autostart = true
	t.timeout.connect(_next_tip)
	add_child(t)

	_panel = UIKit.card()
	_panel.visible = false
	_root.add_child(_panel)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	_panel.add_child(outer)
	var head: HBoxContainer = HBoxContainer.new()
	outer.add_child(head)
	_panel_title = UIKit.label("", 32, UIKit.YELLOW, true, 6)
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_panel_title)
	_buttons["back"] = UIKit.button(tr("BACK"), UIKit.Tone.PURPLE, close_panel, 20)
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
	# Breathing PLAY button once it has a size.
	(func() -> void: UIKit.pulse(primary, 0.035, 1.4)).call_deferred()

## Driver card: rank badge, title, rating stars, day / rides (4A "Thala Murugan" card).
func _driver_card(lvl: int, has_save: bool) -> PanelContainer:
	var card: PanelContainer = UIKit.card()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	row.add_child(UIKit.reward_icon(UIKit.badge_for_level(lvl), 92))
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	col.add_child(UIKit.label(DriverProgress.title(lvl), 26, UIKit.JASMINE, true))
	var stars: HBoxContainer = HBoxContainer.new()
	stars.add_theme_constant_override("separation", 2)
	col.add_child(stars)
	var rating: float = GameState.star_rating
	for i: int in 5:
		var cell: String = "star" if rating >= i + 0.75 else ("star_half" if rating >= i + 0.25 else "star_empty")
		stars.add_child(UIKit.reward_icon(cell, 26))
	stars.add_child(UIKit.label("  %.1f" % rating, 18, UIKit.YELLOW, true))
	var sub: String = "%s %d · %s %d" % [tr("LV"), lvl, tr("DAY"), GameState.day]
	if not has_save:
		sub = tr("TAGLINE")
	col.add_child(UIKit.label(sub, 16, UIKit.MUTED))
	var xp: ProgressBar = UIKit.bar(GameState.progress.level_progress(), UIKit.GREEN, 260, 12)
	col.add_child(xp)
	_buttons["profile"] = card
	return card

## The auto on the turntable: name + stat bars (4A "Classic Chennai 200cc" card).
func _vehicle_card() -> PanelContainer:
	var st: VehicleStats = GameState.active_stats()
	var card: PanelContainer = UIKit.card()
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	col.add_child(UIKit.label(st.display_name, 28, UIKit.YELLOW, true, 4))
	col.add_child(UIKit.stat_bar(tr("STAT_SPEED"), st.max_speed_kmh / 80.0, UIKit.YELLOW, 200))
	col.add_child(UIKit.stat_bar(tr("STAT_COMFORT"), clampf(st.comfort_damping / 1.5, 0.0, 1.0), UIKit.GREEN, 200))
	col.add_child(UIKit.stat_bar(tr("STAT_TANK"), clampf(st.fuel_capacity / 12.0, 0.0, 1.0), UIKit.ORANGE, 200))
	return card

func _next_tip() -> void:
	if _ticker == null:
		return
	_ticker.text = tr(TIP_KEYS[_tip_index % TIP_KEYS.size()])
	_tip_index += 1
	_ticker.modulate.a = 0.0
	create_tween().tween_property(_ticker, "modulate:a", 1.0, 0.4)

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var m: float = maxf(28.0, vp.x * 0.04)
	_menu.position = Vector2(m, maxf(16.0, vp.y * 0.03))
	_menu.custom_minimum_size = Vector2(minf(520.0, vp.x * 0.4), 0)
	_menu.size = _menu.custom_minimum_size
	_top_chips.reset_size()
	_top_chips.position = Vector2(vp.x - m - _top_chips.get_combined_minimum_size().x, 18.0)
	_stats_card.reset_size()
	var sc: Vector2 = _stats_card.get_combined_minimum_size()
	_stats_card.position = Vector2(vp.x - m - sc.x, vp.y * 0.17)
	var bar: Control = _root.get_node("Ticker") as Control
	bar.position = Vector2(m, vp.y - 58.0)
	bar.size = Vector2(vp.x - m * 2.0, 44.0)
	_panel.custom_minimum_size = Vector2(minf(860.0, vp.x - 40.0), minf(580.0, vp.y - 40.0))
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
	_stats_card.visible = false
	_panel.visible = true
	UIKit.pop_in(_panel, 0.0, 0.25)

func _panel_text(text: String) -> void:
	var l: Label = UIKit.label(text, 19, UIKit.JASMINE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_child(l)

func _choice(title: String, options: PackedStringArray, selected: int, on_pick: Callable) -> void:
	_panel_body.add_child(UIKit.label(title, 22, UIKit.YELLOW, true))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for i: int in options.size():
		var idx: int = i
		var b: Button = UIKit.button(options[i], UIKit.Tone.GREEN if i == selected else UIKit.Tone.PURPLE, func() -> void: on_pick.call(idx), 20)
		b.custom_minimum_size = Vector2(170, 60)
		row.add_child(b)
	_panel_body.add_child(row)
