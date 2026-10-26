class_name GarageUI
extends CanvasLayer
## Phase 4 UI: service prompts (LPG / EV / garage / tow), shift clock, pause menu with
## settings, the garage screen and the end-of-shift summary. Menus pause the game;
## this layer keeps processing (PROCESS_MODE_ALWAYS). Purchases go through GameState.

const AMBER: Color = Color(1.0, 0.72, 0.1)
const BG: Color = Color(0.06, 0.06, 0.07, 0.94)

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
var _shift_title: String = "-"
var _root: Control
var _clock: Label
var _service_bar: HBoxContainer
var _service_msg: Label
var _pause_btn: Button
var _modal: PanelContainer
var _modal_body: VBoxContainer
var _modal_title: Label
var _service_kind: String = ""
var _service_info: Dictionary = {}
var _fuel_level: float = 1.0
var _speed_kmh: float = 0.0
var _out_of_fuel_shown: bool = false
var _current_tab: String = "TAB_REPAIR"
var _dim: ColorRect
var _modal_ribbon: PanelContainer

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIKit.theme()
	add_child(_root)
	_clock = _label("", 20, Color.WHITE)
	_service_bar = HBoxContainer.new()
	_service_bar.add_theme_constant_override("separation", 14)
	_service_bar.visible = false
	_root.add_child(_service_bar)
	_service_msg = _label("", 20, AMBER)
	_service_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_btn = _button("⏸", Color(0.2, 0.2, 0.25, 0.85), func() -> void: open_pause())
	_pause_btn.custom_minimum_size = Vector2(72, 56)
	_root.add_child(_pause_btn)
	_paint_pause_button()
	_build_modal()
	get_viewport().size_changed.connect(_layout)
	_layout()
	SignalBus.shift_clock_updated.connect(func(d: int, _m: float) -> void: _clock.text = "%s %d · %s" % [tr("DAY"), d, GameState.clock_text()])
	SignalBus.service_available.connect(_on_service_available)
	SignalBus.service_unavailable.connect(_hide_service)
	SignalBus.fuel_changed.connect(_on_fuel)
	SignalBus.speed_updated.connect(func(k: float) -> void: _speed_kmh = k)
	SignalBus.shift_ended.connect(_on_shift_ended)
	SignalBus.pause_requested.connect(func(open: bool) -> void:
		if open and not is_open():
			open_pause())
	SignalBus.recover_available.connect(_on_recover_available)
	SignalBus.back_requested.connect(func() -> void:
		if not is_open():
			open_pause()
		elif _modal_title.text != _shift_title:
			close_modal())
	SignalBus.settings_changed.connect(func(_s: Dictionary) -> void: _refresh_texts())
	SignalBus.wallet_balance_changed.connect(func(_b: int, _d: int) -> void:
		if _modal.visible and _modal_title.text == tr("GARAGE"):
			_render_garage())
	_clock.text = "%s %d · %s" % [tr("DAY"), GameState.day, GameState.clock_text()]

# --- Helpers ------------------------------------------------------------------------------

func _label(text: String, size: int, colour: Color) -> Label:
	var l: Label = UIKit.label(text, size, colour, true, 6)
	_root.add_child(l)
	return l

## Arcade button from the shared kit; the old colour argument picks the closest tone.
func _button(text: String, colour: Color, on_press: Callable) -> Button:
	return UIKit.button(text, _tone_for(colour), on_press, 22)

static func _tone_for(c: Color) -> UIKit.Tone:
	if c.s < 0.3:
		return UIKit.Tone.PURPLE
	var h: float = c.h
	if h < 0.035 or h > 0.93:
		return UIKit.Tone.RED
	if h < 0.095:
		return UIKit.Tone.ORANGE
	if h < 0.19:
		return UIKit.Tone.YELLOW
	if h < 0.5:
		return UIKit.Tone.GREEN
	return UIKit.Tone.PURPLE

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Top-right corner (the top-left belongs to the gear / horn / camera buttons).
	_pause_btn.position = Vector2(vp.x - 26.0 - _pause_btn.custom_minimum_size.x, 16.0)
	_clock.size = Vector2(240.0, 30.0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.position = Vector2(vp.x - 26.0 - 72.0 - 14.0 - 240.0, 34.0)
	_service_bar.position = Vector2(vp.x * 0.5 - 220.0, vp.y * 0.58)
	_service_msg.position = Vector2(0.0, vp.y * 0.52)
	_service_msg.size = Vector2(vp.x, 30.0)
	_modal.custom_minimum_size = Vector2(minf(880.0, vp.x - 40.0), minf(600.0, vp.y - 40.0))
	_modal.position = (vp - _modal.custom_minimum_size) * 0.5
	if _dim != null:
		_dim.position = Vector2.ZERO
		_dim.size = vp

# --- Service prompts ------------------------------------------------------------------------

func _on_service_available(kind: String, info: Dictionary) -> void:
	_service_kind = kind
	_service_info = info
	_render_service()

func _render_service() -> void:
	for c: Node in _service_bar.get_children():
		c.queue_free()
	_service_msg.text = str(_service_info.get("name", ""))
	var stats: VehicleStats = GameState.active_stats()
	var is_ev: bool = stats.fuel_type == 2
	match _service_kind:
		"lpg", "ev":
			if (_service_kind == "ev") != is_ev:
				_service_msg.text = tr("WRONG_FUEL_EV") if _service_kind == "ev" else tr("WRONG_FUEL_LPG")
			else:
				var cost: int = GameState.fuel_cost_to_fill()
				var b: Button = _button("%s  ₹%d" % [tr("CHARGE_EV") if is_ev else tr("FILL_LPG"), cost] if cost > 0 else tr("TANK_FULL"),
					Color(0.1, 0.5, 0.25), func() -> void:
						GameState.buy_fuel()
						_render_service())
				b.disabled = cost <= 0
				_service_bar.add_child(b)
		"garage":
			_service_bar.add_child(_button(tr("OPEN_GARAGE"), Color(0.45, 0.3, 0.12), func() -> void: open_garage()))
	_service_bar.visible = true

func _hide_service() -> void:
	_service_kind = ""
	_service_bar.visible = false
	_service_msg.text = ""
	_out_of_fuel_shown = false

func _on_fuel(level: float, _capacity: float) -> void:
	_fuel_level = level
	if level <= 0.0 and _speed_kmh < 2.0 and not _out_of_fuel_shown and _service_kind == "":
		_out_of_fuel_shown = true
		for c: Node in _service_bar.get_children():
			c.queue_free()
		_service_msg.text = tr("OUT_OF_FUEL")
		_service_bar.add_child(_button("%s  ₹%d" % [tr("TOW"), ServicePoints.TOW_COST_INR], Color(0.6, 0.2, 0.15), _tow))
		_service_bar.visible = true

func _on_recover_available(available: bool) -> void:
	if not available:
		if _service_kind == "" and not _out_of_fuel_shown:
			_service_bar.visible = false
			_service_msg.text = ""
		return
	if _service_kind != "":
		return
	for c: Node in _service_bar.get_children():
		c.queue_free()
	_service_msg.text = ""
	_service_bar.add_child(_button(tr("RESET_AUTO"), Color(0.25, 0.35, 0.6), func() -> void:
		SignalBus.recover_requested.emit()
		_service_bar.visible = false))
	_service_bar.visible = true

func _tow() -> void:
	SignalBus.tow_requested.emit(_last_player_pos())
	_hide_service()

func _last_player_pos() -> Vector3:
	var autos: Array[Node] = get_tree().get_nodes_in_group("player_auto")
	return (autos[0] as Node3D).global_position if not autos.is_empty() else Vector3.ZERO

# --- Modal framework -------------------------------------------------------------------------

func _build_modal() -> void:
	_dim = UIKit.backdrop()
	_dim.visible = false
	_root.add_child(_dim)
	_modal = UIKit.card()
	_modal.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.DUSK))
	_modal.visible = false
	_root.add_child(_modal)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	_modal.add_child(outer)
	var head: HBoxContainer = HBoxContainer.new()
	outer.add_child(head)
	_modal_title = UIKit.label("", 32, UIKit.YELLOW, true, 6)
	_modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_modal_title)
	var x: Button = UIKit.button("✕", UIKit.Tone.RED, close_modal, 22)
	x.custom_minimum_size = Vector2(64, 60)
	head.add_child(x)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_modal_body = VBoxContainer.new()
	_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_modal_body)

func _open_modal(title: String) -> void:
	_modal_title.text = title
	for c: Node in _modal_body.get_children():
		c.queue_free()
	_modal.visible = true
	_dim.visible = true
	SignalBus.ui_modal_changed.emit(true)
	_layout()
	UIKit.pop_in(_modal, 0.0, 0.22)
	get_tree().paused = true

func close_modal() -> void:
	_modal.visible = false
	_dim.visible = false
	SignalBus.ui_modal_changed.emit(false)
	get_tree().paused = false

func is_open() -> bool:
	return _modal.visible

## One item tile (garage / pause / summary): text on the left, an arcade button on the right.
## Prices get a coin, locked items the padlock, paints a swatch of their colour.
func _row(text: String, button_text: String, enabled: bool, on_press: Callable, colour: Color = Color(0.15, 0.45, 0.2)) -> void:
	var tile: PanelContainer = PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.SURFACE_HI, 16))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	tile.add_child(row)
	if _current_tab == "TAB_PAINT" and _modal_title.text == tr("GARAGE") and button_text != "":
		var sw: Panel = Panel.new()
		sw.custom_minimum_size = Vector2(46, 46)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb: StyleBoxFlat = UIKit.pill_box(colour).duplicate() as StyleBoxFlat
		sw.add_theme_stylebox_override("panel", sb)
		row.add_child(sw)
	var l: Label = UIKit.label(text, 19, UIKit.JASMINE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	if button_text != "":
		var locked: bool = button_text.begins_with(tr("UNLOCKS_AT_LV"))
		var icon: String = "lock" if locked else ("coin" if button_text.contains("₹") else "")
		var tone: UIKit.Tone = UIKit.Tone.PURPLE if locked else (UIKit.Tone.YELLOW if _current_tab == "TAB_PAINT" and _modal_title.text == tr("GARAGE") else _tone_for(colour))
		var b: Button = UIKit.button(button_text, tone, on_press, 20, icon)
		b.custom_minimum_size = Vector2(200, 64)
		b.disabled = not enabled
		row.add_child(b)
	_modal_body.add_child(tile)

func _choice_row(title: String, options: PackedStringArray, selected: int, on_pick: Callable) -> void:
	_modal_body.add_child(UIKit.label(title, 22, UIKit.YELLOW, true))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for i: int in options.size():
		var idx: int = i
		var b: Button = UIKit.button(options[i], UIKit.Tone.GREEN if i == selected else UIKit.Tone.PURPLE, func() -> void: on_pick.call(idx), 20)
		b.custom_minimum_size = Vector2(160, 58)
		row.add_child(b)
	_modal_body.add_child(row)

# --- Pause & settings ------------------------------------------------------------------------

func open_pause() -> void:
	_open_modal(tr("GAME_PAUSED"))
	# 4E: status chips, then the big RESUME and EXIT buttons, then progress and settings.
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 22)
	chips.add_child(UIKit.chip("coin", "₹" + UIKit.inr(GameState.wallet_inr)))
	chips.add_child(UIKit.chip("star", "%.1f" % GameState.star_rating))
	chips.add_child(UIKit.chip(UIKit.badge_for_level(GameState.driver_level()), "%s %d · %s" % [tr("DAY"), GameState.day, GameState.clock_text()]))
	_modal_body.add_child(chips)
	var resume: Button = UIKit.button("▶  " + tr("RESUME"), UIKit.Tone.GREEN, close_modal, 30)
	resume.custom_minimum_size = Vector2(0, 84)
	_modal_body.add_child(resume)
	_render_progress()
	_render_settings()
	var exit: Button = UIKit.button(tr("MAIN_MENU"), UIKit.Tone.RED, func() -> void:
		GameState.save_game()
		close_modal()
		get_tree().change_scene_to_file(MAIN_MENU_SCENE), 24)
	_modal_body.add_child(exit)
	_modal_body.add_child(UIKit.label(tr("SAVED_AUTOMATICALLY"), 16, UIKit.MUTED))

## Driver level + today's shift goals (pause menu and shift summary).
func _render_progress() -> void:
	var lvl: int = GameState.driver_level()
	var nxt: String = "" if lvl >= DriverProgress.MAX_LEVEL else "   (%d / %d XP)" % [GameState.progress.xp, DriverProgress.xp_for_level(lvl + 1)]
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UIKit.reward_icon(UIKit.badge_for_level(lvl), 56))
	var hv: VBoxContainer = VBoxContainer.new()
	hv.add_child(UIKit.label("%s %d · %s%s" % [tr("LV"), lvl, DriverProgress.title(lvl), nxt], 22, UIKit.YELLOW, true))
	hv.add_child(UIKit.bar(GameState.progress.level_progress(), UIKit.GREEN, 320, 12))
	head.add_child(hv)
	_modal_body.add_child(head)
	for g: Dictionary in GameState.progress.goals:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var done: bool = bool(g["done"])
		if done:
			row.add_child(UIKit.reward_icon("tick", 34))
		else:
			var ring: Panel = Panel.new()
			ring.custom_minimum_size = Vector2(30, 30)
			ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ring.add_theme_stylebox_override("panel", UIKit.pill_box(Color(0, 0, 0, 0), UIKit.GREEN))
			row.add_child(ring)
		row.add_child(UIKit.label("%s   %d / %d" % [PassengerHUD.goal_text(g), int(g["progress"]), int(g["target"])], 19,
			Color(0.6, 1.0, 0.65) if done else UIKit.JASMINE))
		_modal_body.add_child(row)

func _render_settings() -> void:
	var s: Dictionary = GameState.settings
	_choice_row(tr("CONTROLS"), PackedStringArray([tr("CTRL_WHEEL"), tr("CTRL_ARCADE"), tr("CTRL_TILT")]), int(s["control_scheme"]),
		func(i: int) -> void:
			GameState.set_setting("control_scheme", i)
			open_pause())
	_choice_row(tr("GRAPHICS"), PackedStringArray([tr("GFX_LOW"), tr("GFX_MED"), tr("GFX_HIGH")]), int(s["graphics"]),
		func(i: int) -> void:
			GameState.set_setting("graphics", i)
			open_pause())
	_choice_row(tr("LANGUAGE"), PackedStringArray(["English", "தமிழ்"]), 0 if str(s["language"]) == "en" else 1,
		func(i: int) -> void:
			GameState.set_setting("language", "en" if i == 0 else "ta")
			open_pause())
	_choice_row(tr("VIBRATION"), PackedStringArray([tr("ON"), tr("OFF")]), 0 if bool(s.get("vibration", true)) else 1,
		func(i: int) -> void:
			GameState.set_setting("vibration", i == 0)
			open_pause())
	_choice_row(tr("GUIDE_ARROW"), PackedStringArray([tr("ON"), tr("OFF")]), 0 if bool(s.get("guidance_arrow", true)) else 1,
		func(i: int) -> void:
			GameState.set_setting("guidance_arrow", i == 0)
			open_pause())
	_choice_row(tr("AUTO_REVERSE"), PackedStringArray([tr("ON"), tr("OFF")]), 0 if bool(s.get("auto_reverse", true)) else 1,
		func(i: int) -> void:
			GameState.set_setting("auto_reverse", i == 0)
			open_pause())
	var vl: Label = Label.new()
	vl.text = tr("VOLUME")
	vl.add_theme_font_size_override("font_size", 22)
	vl.add_theme_color_override("font_color", AMBER)
	_modal_body.add_child(vl)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(s["master_volume"])
	slider.custom_minimum_size = Vector2(300, 40)
	slider.value_changed.connect(func(v: float) -> void: GameState.set_setting("master_volume", v))
	_modal_body.add_child(slider)

func _refresh_texts() -> void:
	_clock.text = "%s %d · %s" % [tr("DAY"), GameState.day, GameState.clock_text()]
	if _service_kind != "":
		_render_service()

# --- Garage ----------------------------------------------------------------------------------

func open_garage() -> void:
	_open_modal(tr("GARAGE"))
	_render_garage()

func _render_garage() -> void:
	for c: Node in _modal_body.get_children():
		c.queue_free()
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for key: String in ["TAB_REPAIR", "TAB_UPGRADES", "TAB_HORN", "TAB_PAINT", "TAB_AUTOS"]:
		var k: String = key
		var b: Button = UIKit.button(tr(key), UIKit.Tone.ORANGE if key == _current_tab else UIKit.Tone.PURPLE, func() -> void:
			_current_tab = k
			_render_garage(), 18)
		b.custom_minimum_size = Vector2(140, 58)
		tabs.add_child(b)
	_modal_body.add_child(tabs)
	_modal_body.add_child(UIKit.chip("coin", "%s ₹%s" % [tr("WALLET"), UIKit.inr(GameState.wallet_inr)]))
	match _current_tab:
		"TAB_REPAIR":
			var cost: int = GameState.repair_cost()
			_row("%s: %d%%" % [tr("CONDITION"), roundi(GameState.condition)], ("%s ₹%d" % [tr("REPAIR_ALL"), cost]) if cost > 0 else tr("NOTHING_TO_REPAIR"),
				cost > 0 and GameState.wallet_inr > 0, func() -> void:
					GameState.repair()
					_render_garage())
		"TAB_UPGRADES":
			for kind: String in GameState.UPGRADES:
				var k: String = kind
				var u: Dictionary = GameState.UPGRADES[kind]
				var lvl: int = GameState.upgrade_level(GameState.active_vehicle, kind)
				var cost: int = GameState.next_upgrade_cost(kind)
				_row("%s — %s %d/3\n%s" % [u["name"], tr("LEVEL"), lvl, u["desc"]], tr("MAXED") if cost < 0 else "%s ₹%d" % [tr("BUY"), cost],
					cost >= 0 and GameState.wallet_inr >= cost, func() -> void:
						GameState.buy_upgrade(k)
						_render_garage())
		"TAB_HORN":
			for i: int in GameState.HORNS.size():
				var tier: int = i
				var h: Dictionary = GameState.HORNS[i]
				var owned: bool = i <= GameState.horns_owned
				var label: String = tr("EQUIPPED") if GameState.horn_equipped == i else (tr("EQUIP") if owned else "%s ₹%d" % [tr("BUY"), int(h["cost"])])
				var can: bool = GameState.horn_equipped != i and (owned or (i == GameState.horns_owned + 1 and GameState.wallet_inr >= int(h["cost"])))
				if not owned and not GameState.is_unlocked("horn:%d" % i):
					label = _locked_label("horn:%d" % i)
					can = false
				_row("%s\n%s" % [h["name"], h["desc"]], label, can, func() -> void:
					GameState.buy_horn(tier)
					_render_garage())
		"TAB_PAINT":
			for i: int in GameState.PAINTS.size():
				var idx: int = i
				var p: Dictionary = GameState.PAINTS[i]
				var owned: bool = GameState.paints_owned.has(i)
				var label: String = tr("EQUIPPED") if GameState.paint_equipped == i else (tr("EQUIP") if owned else "%s ₹%d" % [tr("BUY"), int(p["cost"])])
				var unlocked: bool = owned or GameState.is_unlocked("paint:%d" % i)
				if not unlocked:
					label = _locked_label("paint:%d" % i)
				_row("%s  (+%d%% Meter Mela odds)" % [p["name"], roundi(10.0 * float(p["prestige"]))], label,
					unlocked and GameState.paint_equipped != i and (owned or GameState.wallet_inr >= int(p["cost"])), func() -> void:
						GameState.buy_paint(idx)
						_render_garage(), p["body"] as Color)
		"TAB_AUTOS":
			for id: String in GameState.VEHICLE_ORDER:
				var vid: String = id
				var s: VehicleStats = GameState.base_stats(id)
				var owned: bool = GameState.owned_vehicles.has(id)
				var label: String = tr("DRIVING") if GameState.active_vehicle == id else (tr("DRIVE") if owned else "%s ₹%s" % [tr("BUY"), _inr(s.price_inr)])
				var unlocked: bool = owned or GameState.is_unlocked("vehicle:" + id)
				if not unlocked:
					label = _locked_label("vehicle:" + id)
				_row("%s — %d km/h\n%s" % [s.display_name, roundi(s.max_speed_kmh), s.blurb], label,
					unlocked and GameState.active_vehicle != id and (owned or GameState.wallet_inr >= s.price_inr), func() -> void:
						if GameState.owned_vehicles.has(vid):
							GameState.select_vehicle(vid)
						else:
							GameState.buy_vehicle(vid)
						_render_garage())

func _locked_label(key: String) -> String:
	return "%s %d" % [tr("UNLOCKS_AT_LV"), DriverProgress.required_level(key)]

func _inr(v: int) -> String:
	var s: String = str(v)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

# --- Shift summary -------------------------------------------------------------------------

func _on_shift_ended(summary: Dictionary) -> void:
	_shift_title = "%s %d — %s" % [tr("DAY"), int(summary["day"]), tr("SHIFT_OVER")]
	_open_modal(_shift_title)
	_row("%s:  ₹%d\n%s:  %d\n%s:  ₹%d\n%s:  ₹%d\n%s:  ₹%d    %s:  ★%.1f" % [
		tr("EARNED"), int(summary["earned"]), tr("RIDES"), int(summary["rides"]), tr("FUEL_SPENT"), int(summary["fuel_spent"]),
		tr("REPAIRS"), int(summary["repairs"]), tr("WALLET"), int(summary["wallet"]), tr("RATING"), float(summary["rating"])], "", false, Callable())
	_render_progress()
	_row("", tr("NEXT_DAY"), true, func() -> void:
		GameState.start_next_day()
		close_modal())

## The painted gold pause coin from the game-art atlas (same atlas as the driving buttons).
func _paint_pause_button() -> void:
	if not ResourceLoader.exists(TouchHUD.ART_ATLAS):
		return
	var tex: Texture2D = load(TouchHUD.ART_ATLAS) as Texture2D
	var cells: Array[String] = ["pause", "pause_p"]
	var icons: Array[AtlasTexture] = []
	for c: String in cells:
		var idx: int = int(TouchHUD.ART_CELLS[c])
		var at: AtlasTexture = AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((idx % TouchHUD.ART_COLS) * TouchHUD.ART_CELL, (idx / TouchHUD.ART_COLS) * TouchHUD.ART_CELL, TouchHUD.ART_CELL, TouchHUD.ART_CELL)
		icons.append(at)
	_pause_btn.text = ""
	_pause_btn.icon = icons[0]
	_pause_btn.expand_icon = true
	_pause_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_btn.custom_minimum_size = Vector2(80, 80)
	_pause_btn.size = Vector2(80, 80)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		_pause_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_pause_btn.button_down.connect(func() -> void: _pause_btn.icon = icons[1])
	_pause_btn.button_up.connect(func() -> void: _pause_btn.icon = icons[0])
