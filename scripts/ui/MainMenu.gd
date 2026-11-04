class_name MainMenu
extends Node3D
## Title screen over a slowly turning auto in front of a Chennai sunset skyline: Continue, the
## driver card (tap: rank + rating explained), the auto picker (browse, buy, choose what you drive),
## achievements, daily bonus, settings, credits. Starting the game goes through LoadingScreen.
## Built in code (like the other HUDs) so it scales with the viewport and stays theme-free.

const GAME_SCENE: String = "res://scenes/main_chennai.tscn"
const AMBER: Color = Color(1.0, 0.72, 0.1)
## Painted game logo (1G); it includes the Tamil subtitle.
const LOGO: String = "res://assets/ui/logo.png"
const SPIN_RAD_PER_S: float = 0.35
const CREDITS: String = """Namma Auto — Chennai Rickshaw Simulator 3D

Map data © OpenStreetMap contributors, available under the Open Database Licence (ODbL).
Bus stops and routes: CUMTA / MTC via Chennai One, from the Reclaim Chennai MTC bus map (ODbL).
Road and lane geometry: osm2streets by the A/B Street project (Apache-2.0).
Game engine: Godot Engine (MIT). Physics: Jolt Physics (MIT).
Fonts: Bricolage Grotesque, Rubik, Noto Sans Tamil and Baloo Thambi 2, SIL Open Font License 1.1.
Game art and screens designed with Google Stitch for Namma Auto.
UI sounds: Kenney Interface Sounds (CC0). Ambience and horns: BigSoundBank, Joseph Sardin (CC0).
Auto engine and kick-start sounds: kalhan, Freesound (CC BY 4.0). Bulb horn: alex_jauk, Pixabay.
Indicator tick: ProductionNow, Freesound (CC0). Air horn: goose278, Freesound (CC0).
Traffic models: Cars Bundle and Cow by Quaternius (CC0). Auto rickshaw by rSquare, "Bolero" by Waseem Kadri, Indian Scooter by Shiveloper, Cow - LowPoly by Fadly.W and "Two-Wheeler Vehicles Pack Low-Poly" by SymetrikGames (Sketchfab, CC BY 4.0).
Tamil Nadu buses and lorry: "Tamilnadu TNSTC Bus 2009-2014" and "Tamilnadu SETC Bus 2017-2026" by Nobel Tech, "Tamilnadu Lorry" by Oren garage (Sketchfab, CC BY 4.0).
People: "Indian Old man walking" by anandmohan662, "Alex Texel A-pose" by alex.texelsales, "Female test" by CloudHubOmniTeam, "South Indian Women" by alnmathew (Sketchfab, CC BY 4.0); "Indian Woman in Saree" by Pixel_Monster (Sketchfab Standard licence).
City: "chennai central" by SudharsanArivalagan, "Chennai Water Tank" by TamilarasanRG, "Chennai Slum" by aswin.baskaran (Sketchfab, CC BY 4.0). Diesel auto: recordx_media; city road ambience: SoundQue (Pixabay).
Build-time triangulation: earcut (ISC).

Made for every Chennai auto anna and akka. Drive safe, use the meter."""

## Tallest and widest the auto gets while it turns (m), and where its middle sits.
const AUTO_HEIGHT_M: float = 2.1
const AUTO_CENTRE_Y: float = 0.95
const CAMERA_FOV: float = 45.0
const CAMERA_LIFT_M: float = 0.55
const TICKER_H: float = 44.0
const TICKER_GAP: float = 58.0
const TOP_BAND: float = 84.0
const CARD_W: float = 480.0
const COMPACT_PANEL_H: float = 370.0
## Comfort bar: comfort_damping is a jolt multiplier, so LOWER is a smoother ride.
const COMFORT_WORST: float = 1.5
const COMFORT_RANGE: float = 1.2

var _auto: Node3D
var _body: Node3D
var _stage: Node3D
var _cam: Camera3D
var _root: Control
var _panel_compact: bool = false
var _panel_scroll: ScrollContainer
var _card_slot: MarginContainer
## The auto shown on the turntable; may be one the player has not bought yet.
var _shown_vehicle: String = ""
var _menu: VBoxContainer
var _panel: PanelContainer
var _panel_title: Label
var _panel_body: VBoxContainer
var _buttons: Dictionary = {}
var _stats_card: PanelContainer
var _ticker: Label
var _tip_index: int = 0
var _top_chips: HBoxContainer
const TIP_KEYS: Array[String] = ["TIP_1", "TIP_2", "TIP_3", "MENU_HINT", "TIP_4", "TIP_5", "TIP_6"]

func _ready() -> void:
	GameState.shift_running = false
	get_tree().paused = false
	_shown_vehicle = GameState.active_vehicle
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
	_open_panel(tr("DAILY_REWARD"), true)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_panel_body.add_child(row)
	var today_idx: int = int(st["day_index"])
	var available: bool = bool(st["available"])
	for i: int in 7:
		var today: bool = i == today_idx and available
		var claimed: bool = i < today_idx or (i == today_idx and not available)
		var tile: PanelContainer = PanelContainer.new()
		tile.custom_minimum_size = Vector2(0, 124)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

## Achievements: how far along you are, the closest goals, then every achievement by category.
func open_achievements() -> void:
	_open_panel(tr("ACHIEVEMENTS"))
	var rw: RewardsEngine = GameState.rewards
	var total: int = RewardsEngine.ACHIEVEMENTS.size()
	var done: int = rw.achieved.size()
	var summary: HBoxContainer = HBoxContainer.new()
	summary.add_theme_constant_override("separation", 14)
	_panel_body.add_child(summary)
	summary.add_child(UIKit.label(tr("ACHIEVEMENTS_UNLOCKED") % [done, total], 20, UIKit.JASMINE, true))
	var all: ProgressBar = UIKit.bar(float(done) / float(total), UIKit.GREEN, 120.0, 14.0)
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	summary.add_child(all)
	var next: Array[String] = rw.nearest_achievements(2)
	if not next.is_empty():
		_achievement_section(tr("ACH_NEXT_UP"), next)
	for cat: String in RewardsEngine.ACHIEVEMENT_CATEGORIES:
		var ids: Array[String] = []
		for id: String in RewardsEngine.ACHIEVEMENTS:
			if str(RewardsEngine.ACHIEVEMENTS[id]["cat"]) == cat:
				ids.append(id)
		_achievement_section(tr(str(RewardsEngine.ACHIEVEMENT_CATEGORIES[cat])), ids)

func _achievement_section(title: String, ids: Array[String]) -> void:
	_panel_body.add_child(UIKit.label(title, 20, UIKit.YELLOW, true))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_child(grid)
	for id: String in ids:
		grid.add_child(_achievement_row(id))

## One achievement: medal (grey until earned), name, what to do, progress with numbers, reward.
func _achievement_row(id: String) -> PanelContainer:
	var a: Dictionary = RewardsEngine.ACHIEVEMENTS[id]
	var rw: RewardsEngine = GameState.rewards
	var done: bool = rw.achieved.has(id)
	var cell: PanelContainer = PanelContainer.new()
	cell.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.SURFACE, 16))
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	cell.add_child(row)
	var inr: int = int(a["inr"])
	var medal: TextureRect = UIKit.reward_icon("badge_bronze" if inr <= 250 else ("badge_silver" if inr <= 800 else "badge_gold"), 56)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not done:
		medal.modulate = Color(0.42, 0.4, 0.46, 0.75)
	row.add_child(medal)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	row.add_child(text)
	text.add_child(UIKit.label(tr(RewardsEngine.title_key(id)), 18, UIKit.YELLOW if done else UIKit.JASMINE, true))
	var desc: Label = UIKit.label(tr(RewardsEngine.desc_key(id)), 14, UIKit.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(160, 0)
	text.add_child(desc)
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	text.add_child(line)
	var pb: ProgressBar = UIKit.bar(rw.achievement_progress(id), UIKit.GREEN if done else UIKit.YELLOW, 60.0, 10.0)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(pb)
	line.add_child(UIKit.label(rw.achievement_progress_text(id), 14, UIKit.JASMINE, true))
	var reward: HBoxContainer = UIKit.chip("tick" if done else "coin", "₹%s" % UIKit.inr(inr), 15)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if done:
		reward.modulate = Color(1, 1, 1, 0.65)
	row.add_child(reward)
	return cell

## What "Puthu Driver" and the stars mean, what they do, and the whole rank ladder.
func open_profile() -> void:
	_open_panel(tr("DRIVER_PROFILE"))
	var lvl: int = GameState.progress.level()
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_panel_body.add_child(head)
	head.add_child(UIKit.reward_icon(UIKit.badge_for_level(lvl), 96))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	head.add_child(col)
	col.add_child(UIKit.label(DriverProgress.title(lvl), 28, UIKit.JASMINE, true))
	var at_top: bool = lvl >= DriverProgress.MAX_LEVEL
	var xp_text: String = tr("PROFILE_XP") % [UIKit.inr(GameState.progress.xp), UIKit.inr(DriverProgress.xp_for_level(mini(lvl + 1, DriverProgress.MAX_LEVEL)))]
	col.add_child(UIKit.label("%s %d · %s" % [tr("LV"), lvl, xp_text], 17, UIKit.MUTED))
	var pb: ProgressBar = UIKit.bar(GameState.progress.level_progress(), UIKit.GREEN, 260.0, 12.0)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(pb)
	col.add_child(UIKit.label(tr("PROFILE_MAX_RANK") if at_top else tr("PROFILE_NEXT_RANK") % DriverProgress.title(lvl + 1), 17, UIKit.YELLOW, true))
	_panel_section("PROFILE_RANK_TITLE", "PROFILE_RANK_HELP")
	var rating_head: HBoxContainer = _star_row(GameState.star_rating, 24)
	_panel_section("PROFILE_RATING_TITLE", "PROFILE_RATING_HELP", rating_head)
	_panel_body.add_child(UIKit.label(tr("PROFILE_CAREER_TITLE"), 22, UIKit.YELLOW, true))
	var stats: Dictionary = GameState.rewards.stats
	var career: HBoxContainer = HBoxContainer.new()
	career.add_theme_constant_override("separation", 28)
	_panel_body.add_child(career)
	for pair: Array in [["RIDES_DONE", str(GameState.completed_savaris)], ["EARNED_TOTAL", "₹" + UIKit.inr(int(stats.get("earned", 0)))],
			["DISTANCE_TOTAL", "%d km" % (int(stats.get("ride_m", 0)) / 1000)]]:
		var box: VBoxContainer = VBoxContainer.new()
		box.add_child(UIKit.label(tr(str(pair[0])), 15, UIKit.MUTED))
		box.add_child(UIKit.label(str(pair[1]), 22, UIKit.JASMINE, true))
		career.add_child(box)
	_panel_body.add_child(UIKit.label(tr("PROFILE_ALL_RANKS"), 22, UIKit.YELLOW, true))
	var ladder: GridContainer = GridContainer.new()
	ladder.columns = 2
	ladder.add_theme_constant_override("h_separation", 24)
	ladder.add_theme_constant_override("v_separation", 8)
	ladder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_child(ladder)
	for level: int in range(1, DriverProgress.MAX_LEVEL + 1):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var badge: TextureRect = UIKit.reward_icon(UIKit.badge_for_level(level), 38)
		var reached: bool = level <= lvl
		if not reached:
			badge.modulate = Color(0.42, 0.4, 0.46, 0.75)
		row.add_child(badge)
		var name_col: VBoxContainer = VBoxContainer.new()
		name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_col)
		name_col.add_child(UIKit.label("%d · %s" % [level, DriverProgress.title(level)], 17, UIKit.YELLOW if level == lvl else (UIKit.JASMINE if reached else UIKit.MUTED), true))
		if level > 1:
			row.add_child(UIKit.label(tr("PROFILE_LEVEL_BONUS") % DriverProgress.level_reward_inr(level), 15, UIKit.MUTED))
		ladder.add_child(row)

## Section title (with an optional widget beside it) and a wrapped explanation.
func _panel_section(title_key: String, help_key: String, beside: Control = null) -> void:
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_panel_body.add_child(head)
	head.add_child(UIKit.label(tr(title_key), 22, UIKit.YELLOW, true))
	if beside != null:
		head.add_child(beside)
	var help: Label = UIKit.label(tr(help_key), 17, UIKit.JASMINE)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_child(help)

func new_career() -> void:
	if GameState.has_save():
		_open_panel(tr("NEW_GAME"), true)
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
	# Replay the guided first ride next time the city loads.
	var done: bool = bool(s.get("first_ride_done", false))
	_panel_body.add_child(UIKit.button(tr("REPLAY_TUTORIAL") if done else tr("TUTORIAL_QUEUED"),
		UIKit.Tone.ORANGE if done else UIKit.Tone.PURPLE, func() -> void:
			GameState.set_setting("first_ride_step", 0)
			GameState.set_setting("first_ride_done", false)
			open_settings(), 22))
	# Wiping a career is rare and final, so it lives here rather than beside Continue.
	if GameState.has_save():
		_panel_body.add_child(UIKit.button(tr("NEW_GAME"), UIKit.Tone.RED, new_career, 22))

func open_credits() -> void:
	_open_panel(tr("CREDITS"))
	_panel_text(CREDITS)

func close_panel() -> void:
	_panel.visible = false
	_menu.visible = true
	_stats_card.visible = true
	_stage.visible = true
	_refresh_status()

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
	_cam = Camera3D.new()
	_cam.fov = CAMERA_FOV
	add_child(_cam)
	_cam.current = true
	_stage = Node3D.new()
	add_child(_stage)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 2.0
	disc.bottom_radius = 2.0
	disc.height = 0.06
	disc.radial_segments = 40
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.12, 0.1, 0.12)
	disc.material = gm
	ground.mesh = disc
	ground.position = Vector3(0, -0.03, 0)
	_stage.add_child(ground)
	# Glowing turntable rim (4A "pulse-ring").
	var rim: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.94
	torus.outer_radius = 2.0
	torus.rings = 48
	torus.ring_segments = 6
	var rm: StandardMaterial3D = StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.95, 0.5, 0.1)
	torus.material = rm
	rim.mesh = torus
	rim.position = Vector3(0, 0.01, 0)
	_stage.add_child(rim)
	var glow: Tween = create_tween().set_loops()
	glow.tween_property(rm, "albedo_color", Color(1.0, 0.75, 0.25), 1.25).set_trans(Tween.TRANS_SINE)
	glow.tween_property(rm, "albedo_color", Color(0.95, 0.5, 0.1), 1.25).set_trans(Tween.TRANS_SINE)
	# The auto the player drives: the real Chennai model in stock yellow, else the procedural one.
	_auto = Node3D.new()
	_auto.position = Vector3(0, 0.8, 0)
	_stage.add_child(_auto)
	# Hover bob (4A "arcade-bob", 3.2 s).
	var bob: Tween = create_tween().set_loops()
	bob.tween_property(_auto, "position:y", 0.86, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_auto, "position:y", 0.8, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_show_auto()
	if bool(_body.get("uses_real_model")):
		return # the model's wheels are part of the body
	for w: Array in [[Vector3(0, -0.64, -1.05), true], [Vector3(-0.58, -0.64, 0.88), false], [Vector3(0.58, -0.64, 0.88), false]]:
		var wheel: Node3D = Node3D.new()
		wheel.set_script(load("res://scripts/vehicle/WheelModel.gd"))
		wheel.set("is_front", w[1])
		wheel.position = w[0]
		_auto.add_child(wheel)

## Puts _shown_vehicle on the turntable. Crash damage shows only on the auto you actually drive.
func _show_auto() -> void:
	if _body != null:
		_auto.remove_child(_body)
		_body.queue_free()
	_body = Node3D.new()
	_body.set_script(load("res://scripts/vehicle/AutoRickshawModel.gd"))
	var st: VehicleStats = GameState.effective_stats(_shown_vehicle)
	_body.set("paint", st.body_colour)
	_body.set("trim", st.canopy_colour)
	_body.set("show_damage", _shown_vehicle == GameState.active_vehicle)
	_auto.add_child(_body)

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

	# Left column: logo, tagline, driver card, PLAY, then a tidy 2 × 2 of everything else.
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	_root.add_child(_menu)
	if ResourceLoader.exists(LOGO):
		var logo: TextureRect = TextureRect.new()
		logo.name = "Logo"
		logo.texture = load(LOGO) as Texture2D
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.custom_minimum_size = Vector2(0, 120)
		_menu.add_child(logo)
	else:
		_menu.add_child(UIKit.label("NAMMA AUTO", 60, UIKit.YELLOW, true, 10))
	_buttons["tagline"] = UIKit.label(tr("TAGLINE"), 18, UIKit.JASMINE, true, 6)
	_menu.add_child(_buttons["tagline"])
	_card_slot = MarginContainer.new()
	_menu.add_child(_card_slot)
	var primary_key: String = "continue" if has_save else "new"
	var primary: Button = UIKit.button("▶  " + tr("CONTINUE" if has_save else "NEW_GAME"), UIKit.Tone.YELLOW,
		continue_game if has_save else new_career, 34)
	primary.custom_minimum_size = Vector2(0, 80)
	_buttons[primary_key] = primary
	_menu.add_child(primary)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_menu.add_child(grid)
	_buttons["daily"] = UIKit.button(tr("DAILY_SHORT"), UIKit.Tone.GREEN, open_daily, 19, "gift")
	_buttons["achievements"] = UIKit.button(tr("ACHIEVEMENTS"), UIKit.Tone.PURPLE, open_achievements, 19, "badge_gold")
	_buttons["settings"] = UIKit.button(tr("SETTINGS"), UIKit.Tone.PURPLE, open_settings, 19)
	_buttons["credits"] = UIKit.button(tr("CREDITS"), UIKit.Tone.PURPLE, open_credits, 19)
	for k: String in ["daily", "achievements", "settings", "credits"]:
		(_buttons[k] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(_buttons[k])

	# Top-right currency / rating / rank chips + quit.
	_top_chips = HBoxContainer.new()
	_top_chips.add_theme_constant_override("separation", 22)
	_root.add_child(_top_chips)
	_buttons["quit"] = UIKit.button(tr("QUIT"), UIKit.Tone.RED, func() -> void: get_tree().quit(), 18)
	_buttons["quit"].custom_minimum_size = Vector2(110, 56)

	# Right: the auto picker, under the turntable so the auto stays in full view.
	_stats_card = UIKit.card()
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
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_panel_scroll)
	_panel_body = VBoxContainer.new()
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_constant_override("separation", 12)
	_panel_scroll.add_child(_panel_body)
	_refresh_status()
	# Breathing PLAY button once it has a size.
	(func() -> void: UIKit.pulse(primary, 0.035, 1.4)).call_deferred()

## Everything that shows live numbers: wallet chips, driver card, auto picker, daily button.
func _refresh_status() -> void:
	var lvl: int = GameState.progress.level()
	for c: Node in _top_chips.get_children():
		if c != _buttons["quit"]:
			_top_chips.remove_child(c)
			c.queue_free()
	if _buttons["quit"].get_parent() == null:
		_top_chips.add_child(_buttons["quit"])
	var chips: Array[HBoxContainer] = [UIKit.chip("coin", "₹" + UIKit.inr(GameState.wallet_inr)),
		UIKit.chip("star", "%.1f" % GameState.star_rating), UIKit.chip(UIKit.badge_for_level(lvl), "%s %d" % [tr("LV"), lvl])]
	for i: int in chips.size():
		_top_chips.add_child(chips[i])
		_top_chips.move_child(chips[i], i)
	for c: Node in _card_slot.get_children():
		_card_slot.remove_child(c)
		c.queue_free()
	_card_slot.add_child(_driver_card(lvl))
	_fill_vehicle_card()
	# Green only while there is something to claim.
	UIKit.set_tone(_buttons["daily"] as Button, UIKit.Tone.GREEN if bool(GameState.daily_reward_status()["available"]) else UIKit.Tone.PURPLE)
	if is_inside_tree():
		_layout.call_deferred()

## Driver card: rank badge, title, rating stars, day, XP. Tap for what it all means.
func _driver_card(lvl: int) -> PanelContainer:
	var card: PanelContainer = UIKit.card()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent) -> void:
		var tap: InputEventMouseButton = e as InputEventMouseButton
		if tap != null and tap.button_index == MOUSE_BUTTON_LEFT and not tap.pressed:
			open_profile())
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(UIKit.reward_icon(UIKit.badge_for_level(lvl), 78))
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(UIKit.label(DriverProgress.title(lvl), 24, UIKit.JASMINE, true))
	col.add_child(_star_row(GameState.star_rating, 22))
	var xp: ProgressBar = UIKit.bar(GameState.progress.level_progress(), UIKit.GREEN, 200.0, 10.0)
	xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(xp)
	col.add_child(UIKit.label("%s %d · %s %d" % [tr("LV"), lvl, tr("DAY"), GameState.day], 15, UIKit.MUTED))
	var more: Label = UIKit.label("▶", 18, UIKit.YELLOW, true)
	row.add_child(more)
	_buttons["profile"] = card
	return card

func _star_row(rating: float, side: float) -> HBoxContainer:
	var stars: HBoxContainer = HBoxContainer.new()
	stars.add_theme_constant_override("separation", 2)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in 5:
		var cell: String = "star" if rating >= i + 0.75 else ("star_half" if rating >= i + 0.25 else "star_empty")
		stars.add_child(UIKit.reward_icon(cell, side))
	stars.add_child(UIKit.label("  %.1f" % rating, 17, UIKit.YELLOW, true))
	return stars

## 0–1 for the comfort bar: comfort_damping multiplies the jolts, so smaller is better.
static func comfort_score(comfort_damping: float) -> float:
	return clampf((COMFORT_WORST - comfort_damping) / COMFORT_RANGE, 0.0, 1.0)

## The auto picker for _shown_vehicle: ◀ name ▶, stats, and Driving / Drive / Buy / Unlocks at Lv.
func _fill_vehicle_card() -> void:
	for c: Node in _stats_card.get_children():
		_stats_card.remove_child(c)
		c.queue_free()
	var id: String = _shown_vehicle
	var st: VehicleStats = GameState.effective_stats(id)
	var active: bool = id == GameState.active_vehicle
	var owned: bool = GameState.owned_vehicles.has(id)
	var order: PackedStringArray = GameState.VEHICLE_ORDER
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_stats_card.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var prev: Button = UIKit.button("◀", UIKit.Tone.PURPLE, func() -> void: browse_vehicle(-1), 20)
	prev.custom_minimum_size = Vector2(60, 52)
	head.add_child(prev)
	var names: VBoxContainer = VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	var title: Label = UIKit.label(st.display_name, 24, UIKit.YELLOW, true, 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	names.add_child(title)
	var page: Label = UIKit.label(tr("VEHICLE_N_OF") % [order.find(id) + 1, order.size()], 14, UIKit.MUTED)
	page.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	names.add_child(page)
	var next: Button = UIKit.button("▶", UIKit.Tone.PURPLE, func() -> void: browse_vehicle(1), 20)
	next.custom_minimum_size = Vector2(60, 52)
	head.add_child(next)
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)
	var bars: VBoxContainer = VBoxContainer.new()
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_theme_constant_override("separation", 4)
	body.add_child(bars)
	bars.add_child(UIKit.stat_bar(tr("STAT_SPEED"), st.max_speed_kmh / 80.0, UIKit.YELLOW, 150))
	bars.add_child(UIKit.stat_bar(tr("STAT_COMFORT"), comfort_score(st.comfort_damping), UIKit.GREEN, 150))
	bars.add_child(UIKit.stat_bar(tr("STAT_BATTERY" if st.fuel_type == 2 else "STAT_TANK"), clampf(st.fuel_capacity / 12.0, 0.0, 1.0), UIKit.ORANGE, 150))
	if active and GameState.condition < 100.0:
		bars.add_child(UIKit.stat_bar(tr("CONDITION"), GameState.condition / 100.0, UIKit.RED if GameState.condition < 40.0 else UIKit.ORANGE, 150))
		var hint: Label = UIKit.label(tr("AUTO_REPAIR_HINT"), 14, UIKit.MUTED)
		bars.add_child(hint)
	var unlocked: bool = owned or GameState.is_unlocked("vehicle:" + id)
	var text: String = tr("DRIVING")
	var tone: UIKit.Tone = UIKit.Tone.GREEN
	var icon: String = "tick"
	var enabled: bool = false
	if not unlocked:
		text = "%s %d" % [tr("LV"), DriverProgress.required_level("vehicle:" + id)]
		tone = UIKit.Tone.DARK
		icon = "lock"
	elif not owned:
		text = "₹" + UIKit.inr(st.price_inr)
		tone = UIKit.Tone.YELLOW
		icon = "coin"
		enabled = GameState.wallet_inr >= st.price_inr
	elif not active:
		text = tr("DRIVE")
		tone = UIKit.Tone.YELLOW
		icon = ""
		enabled = true
	var action: Button = UIKit.button(text, tone, take_shown_vehicle, 19, icon)
	action.disabled = not enabled
	action.custom_minimum_size = Vector2(136, 64)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_buttons["vehicle_action"] = action
	body.add_child(action)

## Next / previous auto on the turntable, without changing what the player drives.
func browse_vehicle(step: int) -> void:
	var order: PackedStringArray = GameState.VEHICLE_ORDER
	var i: int = order.find(_shown_vehicle)
	_shown_vehicle = order[posmod(i + step, order.size())]
	_show_auto()
	_refresh_status()

## Drive the shown auto (buying it first if needed).
func take_shown_vehicle() -> void:
	if not GameState.owned_vehicles.has(_shown_vehicle):
		if not GameState.buy_vehicle(_shown_vehicle):
			return
	elif not GameState.select_vehicle(_shown_vehicle):
		return
	_show_auto()
	_refresh_status()

func _next_tip() -> void:
	if _ticker == null:
		return
	_ticker.text = tr(TIP_KEYS[_tip_index % TIP_KEYS.size()])
	_tip_index += 1
	_ticker.modulate.a = 0.0
	create_tween().tween_property(_ticker, "modulate:a", 1.0, 0.4)

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var m: float = maxf(24.0, vp.x * 0.03)
	var column_w: float = minf(470.0, vp.x * 0.38)
	_menu.position = Vector2(m, 10.0)
	_menu.custom_minimum_size = Vector2(column_w, 0)
	_menu.size = Vector2(column_w, 0)
	_top_chips.reset_size()
	_top_chips.position = Vector2(vp.x - m - _top_chips.get_combined_minimum_size().x, 14.0)
	var bar: Control = _root.get_node("Ticker") as Control
	bar.position = Vector2(m, vp.y - TICKER_GAP)
	bar.size = Vector2(vp.x - m * 2.0, TICKER_H)
	# The stage is the space right of the column: the card sits at its foot, the auto above.
	var stage_left: float = m + column_w + 16.0
	var stage_mid: float = (stage_left + vp.x - m) * 0.5
	_stats_card.reset_size()
	var sc: Vector2 = _stats_card.get_combined_minimum_size()
	sc.x = maxf(sc.x, CARD_W)
	_stats_card.size = sc
	_stats_card.position = Vector2(minf(stage_mid - sc.x * 0.5, vp.x - m - sc.x), vp.y - TICKER_GAP - 10.0 - sc.y)
	_aim_camera(vp, stage_mid, (TOP_BAND + _stats_card.position.y) * 0.5, _stats_card.position.y - TOP_BAND)
	_panel.custom_minimum_size = Vector2(minf(1120.0, vp.x - 40.0), COMPACT_PANEL_H if _panel_compact else vp.y - TOP_BAND - TICKER_GAP - 10.0)
	_panel.size = _panel.custom_minimum_size
	_panel.position = Vector2((vp.x - _panel.size.x) * 0.5, TOP_BAND)

## Frames the auto inside a free screen band whatever the aspect ratio: distance from the band
## height, then the lens is shifted (not turned) so the auto stays upright and centred in it.
func _aim_camera(vp: Vector2, mid_x: float, mid_y: float, band_h: float) -> void:
	var world_h: float = AUTO_HEIGHT_M * vp.y / maxf(band_h, 120.0)
	var dist: float = world_h / (2.0 * tan(deg_to_rad(CAMERA_FOV * 0.5)))
	_cam.position = Vector3(0.0, AUTO_CENTRE_Y + CAMERA_LIFT_M, dist)
	_cam.look_at(Vector3(0.0, AUTO_CENTRE_Y, 0.0), Vector3.UP)
	var m_per_px: float = world_h / vp.y
	_cam.h_offset = -(mid_x - vp.x * 0.5) * m_per_px
	_cam.v_offset = -(vp.y * 0.5 - mid_y) * m_per_px

func _refresh_texts() -> void:
	var keys: Dictionary = {"continue": "CONTINUE", "new": "NEW_GAME", "settings": "SETTINGS", "credits": "CREDITS",
		"quit": "QUIT", "back": "BACK", "tagline": "TAGLINE", "daily": "DAILY_SHORT", "achievements": "ACHIEVEMENTS"}
	var primary: String = "continue" if _buttons.has("continue") else "new"
	for k: String in keys:
		if _buttons.has(k):
			_buttons[k].set("text", ("▶  " if k == primary else "") + tr(str(keys[k])))
	_refresh_status()

func _open_panel(title: String, compact: bool = false) -> void:
	_panel_title.text = title
	_panel_compact = compact
	_panel_scroll.scroll_vertical = 0
	for c: Node in _panel_body.get_children():
		_panel_body.remove_child(c)
		c.queue_free()
	_menu.visible = false
	_stats_card.visible = false
	_stage.visible = false
	_panel.visible = true
	_layout()
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
