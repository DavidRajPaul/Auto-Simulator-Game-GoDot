class_name QuestHUD
extends CanvasLayer
## Side quest panel on the left kerb, clear of the road ahead and of the top HUD row. Shows what
## to do next in plain words. Its button appears only when a tap will work, and the same panel is
## the "you stopped at a quest" card with Start. Nodes are preallocated; text is data-driven.
const PANEL_X: float = 16.0
const PANEL_W: float = 306.0
const PROMPT_W: float = 410.0
const PANEL_TOP_ROUTE: float = 226.0 # Under the top row and a three-line GPS turn card.
const PANEL_TOP_BARE: float = 112.0
const SAFE_COLOUR: Color = Color("3ddc84")
const WARN_COLOUR: Color = Color("ff9f43")
const DANGER_COLOUR: Color = Color("ff5a4f")
const LEAVE_ARM_S: float = 3.0
const MAP_START_W: float = 170.0
const MAP_START_H: float = 50.0
const FAIL_TIPS: PackedStringArray = ["speed", "quality", "damage", "deadline", "diversion", "unreachable"]

var _card: PanelContainer
var _title: Label
var _objective: Label
var _job: Label
var _meta: Label
var _limits: Label
var _quality: Label
var _quality_bar: ProgressBar
var _buttons: Array[Button] = []
var _photo: Button
var _retry: Button
var _start: Button
var _later: Button
var _leave: Button
var _map_start: Button
var _quest_id: String = ""
var _stage_id: String = ""
var _kind: String = ""
var _objective_text: String = ""
var _action_text: String = ""
var _place: String = ""
var _located: bool = false
var _failed: bool = false
var _action_ready: bool = false
var _in_range: bool = false
var _speed_warning: float = 0.0
var _modal: bool = false
var _map_open: bool = false
var _deadline: float = 0.0
var _speed_limit: float = 0.0
var _damage_limit: float = 100.0
var _reward: int = 0
var _prompt: Dictionary = {}
var _leave_armed_s: float = 0.0

func _ready() -> void:
	layer = 12
	_card = PanelContainer.new()
	_card.theme = UIKit.theme()
	_card.add_theme_stylebox_override("panel", UIKit.card_box(Color(0.08, 0.09, 0.12, 0.84), 16))
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_card)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	_card.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	col.add_child(head)
	_title = UIKit.label("", 15, UIKit.JASMINE, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	_leave = Button.new()
	_leave.text = "×"
	_leave.custom_minimum_size = Vector2(44, 34)
	_leave.add_theme_font_size_override("font_size", 16)
	_leave.pressed.connect(_on_leave)
	head.add_child(_leave)
	_objective = _wrapped(UIKit.label("", 18, UIKit.YELLOW, true))
	col.add_child(_objective)
	_job = _wrapped(UIKit.label("", 16, Color.WHITE))
	_job.visible = false
	col.add_child(_job)
	_meta = UIKit.label("", 16, SAFE_COLOUR, true)
	_meta.visible = false
	col.add_child(_meta)
	_limits = _wrapped(UIKit.label("", 15, UIKit.JASMINE))
	col.add_child(_limits)
	_quality = UIKit.label("", 15, Color.WHITE)
	_quality.visible = false
	col.add_child(_quality)
	_quality_bar = UIKit.bar(100.0, SAFE_COLOUR, PANEL_W - 28.0, 10.0)
	_quality_bar.visible = false
	col.add_child(_quality_bar)
	for i: int in 3:
		var choice: Button = UIKit.button("", UIKit.Tone.YELLOW, _choose.bind(i), 18)
		choice.custom_minimum_size = Vector2(0, 48)
		choice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choice.visible = false
		col.add_child(choice)
		_buttons.append(choice)
	_photo = UIKit.button("", UIKit.Tone.GREEN, func() -> void: SignalBus.mission_interact_requested.emit(_quest_id, _stage_id), 20)
	_photo.custom_minimum_size = Vector2(0, 54)
	_photo.visible = false
	col.add_child(_photo)
	_retry = UIKit.button("", UIKit.Tone.GREEN, func() -> void: SignalBus.mission_retry_requested.emit(), 20)
	_retry.custom_minimum_size = Vector2(0, 54)
	_retry.visible = false
	_retry.text = tr("QUEST_RETRY")
	col.add_child(_retry)
	_start = UIKit.button(tr("QUEST_START"), UIKit.Tone.GREEN, _begin_prompt, 22)
	_start.custom_minimum_size = Vector2(0, 56)
	_start.visible = false
	col.add_child(_start)
	_later = _panel_button(func() -> void: SignalBus.quest_prompt_dismissed.emit())
	_later.text = tr("QUEST_NOT_NOW")
	col.add_child(_later)
	_card.visible = false
	# The second way in: a Start button sitting on top of the minimap.
	_map_start = UIKit.button(tr("QUEST_START"), UIKit.Tone.GREEN, _begin_prompt, 20)
	_map_start.theme = UIKit.theme()
	_map_start.size = Vector2(MAP_START_W, MAP_START_H)
	_map_start.visible = false
	add_child(_map_start)
	SignalBus.mission_stage_info.connect(_on_stage)
	SignalBus.mission_timer_updated.connect(_on_timer)
	SignalBus.mission_quality_changed.connect(func(kind: String, value: float) -> void: _set_quality(kind, value))
	SignalBus.mission_action_ready.connect(_on_action_ready)
	SignalBus.mission_speed_warning.connect(func(seconds_left: float) -> void:
		_speed_warning = seconds_left
		_on_timer(_deadline))
	SignalBus.mission_finished.connect(_on_finished)
	SignalBus.quest_prompt_changed.connect(func(quest: Dictionary) -> void:
		_prompt = quest
		_refresh())
	SignalBus.mission_profile_loaded.connect(func() -> void:
		_quest_id = ""
		_failed = false
		_prompt = {}
		_refresh())
	SignalBus.full_map_state_changed.connect(func(open: bool) -> void:
		_map_open = open
		_refresh())
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void:
		_modal = open
		_refresh())
	SignalBus.route_updated.connect(func(_path: PackedVector3Array) -> void: _layout())
	get_viewport().size_changed.connect(_layout)
	_layout()

static func _wrapped(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _panel_button(on_press: Callable) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 17)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(on_press)
	button.visible = false
	return button

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var showing_prompt: bool = _quest_id == "" and not _prompt.is_empty()
	var width: float = minf(PROMPT_W if showing_prompt else PANEL_W, vp.x - 32.0)
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.size = Vector2(width, 0.0)
	_card.position = Vector2(PANEL_X, PANEL_TOP_BARE if showing_prompt or not _located else PANEL_TOP_ROUTE)
	_map_start.position = Vector2((vp.x - MAP_START_W) * 0.5, vp.y - 22.0 - PassengerHUD.MINIMAP_SIZE * 1.17 - MAP_START_H - 6.0)

func _process(delta: float) -> void:
	if _leave_armed_s > 0.0:
		_leave_armed_s -= delta
		if _leave_armed_s <= 0.0:
			_leave.text = "×"

## Leaving needs two taps: the × is close to the steering thumb.
func _on_leave() -> void:
	if _leave_armed_s > 0.0:
		_leave_armed_s = 0.0
		_leave.text = "×"
		SignalBus.mission_abandon_requested.emit("player_left")
	else:
		_leave_armed_s = LEAVE_ARM_S
		_leave.text = tr("QUEST_LEAVE_SURE")

func _begin_prompt() -> void:
	if not _prompt.is_empty() and SignalBus.quest_action_provider.is_valid():
		if not bool(SignalBus.quest_action_provider.call("start", str(_prompt["id"]))):
			SignalBus.hint_requested.emit(tr("QUEST_NOT_ON_FIRE") if GameState.is_on_fire() else tr("QUEST_STOP_AT_KERB"), 3.0)

func _refresh() -> void:
	var hidden: bool = _modal or _map_open or GameState.tutorial_active
	var showing_prompt: bool = _quest_id == "" and not _prompt.is_empty()
	_card.visible = (_quest_id != "" or showing_prompt) and not hidden
	_map_start.visible = showing_prompt and not hidden
	if showing_prompt:
		_show_prompt()
	elif _quest_id != "":
		_show_run()
	_layout()

func _show_prompt() -> void:
	_title.text = tr("QUEST_NEARBY_TITLE")
	_leave.visible = false
	_objective.text = str(_prompt["title"])
	_job.text = "%s\n%s" % [str(_prompt["description"]), str(_prompt["job"])]
	_job.visible = true
	_meta.text = tr("QUEST_REWARD") % [UIKit.inr(int(_prompt["reward"])), int(_prompt["minutes"])]
	_meta.visible = true
	_limits.visible = false
	_quality.visible = false
	_quality_bar.visible = false
	for button: Button in _buttons:
		button.visible = false
	_photo.visible = false
	_retry.visible = false
	_start.visible = true
	_later.visible = true

func _show_run() -> void:
	_leave.visible = true
	_job.visible = false
	_meta.visible = false
	_start.visible = false
	_later.visible = false
	_limits.visible = not _failed
	if _failed:
		return
	_objective.text = _objective_text
	# A stop-and-do stage: the button replaces "drive there" only when it will work.
	_photo.visible = _kind in ["photo", "inspect", "calm", "park", "cargo"] and _action_ready
	_photo.text = _action_text
	if _located and _in_range and not _action_ready:
		_objective.text = tr("QUEST_STOP_HERE")

func _choose(index: int) -> void:
	if index < _buttons.size() and _buttons[index].visible:
		SignalBus.mission_choice_requested.emit(_quest_id, _stage_id, str(_buttons[index].get_meta("choice")))

func _on_stage(info: Dictionary) -> void:
	_quest_id = str(info["id"])
	_stage_id = str(info["stage"])
	_kind = str(info["kind"])
	_failed = false
	_deadline = float(info["deadline"])
	_speed_limit = float(info["speed"])
	_damage_limit = float(info["damage"])
	_speed_warning = 0.0
	_reward = int(info["reward"])
	_located = bool(info["located"])
	_title.text = tr(str(info["title"]))
	_place = tr(str(info["place"])) if str(info["place"]) != "" else ""
	_objective_text = tr(str(info["objective"]))
	var fallback: String = {"photo": "QUEST_TAKE_PHOTO", "calm": "QUEST_CALM", "park": "QUEST_PARK", "cargo": "QUEST_TRANSFER"}.get(_kind, "QUEST_INSPECT")
	_action_text = tr(str(info["action"]) if str(info["action"]) != "" else fallback)
	var choices: PackedStringArray = info["choices"]
	for i: int in _buttons.size():
		_buttons[i].visible = i < choices.size()
		if i < choices.size():
			_buttons[i].text = tr(choices[i])
			_buttons[i].set_meta("choice", choices[i])
	var has_quality: bool = str(info.get("quality_key", "")) != ""
	_quality.visible = has_quality
	_quality_bar.visible = has_quality
	if has_quality:
		_set_quality(str(info["quality_key"]), float(info["quality"]))
	_retry.visible = false
	_on_timer(_deadline)
	_refresh()

func _set_quality(kind: String, value: float) -> void:
	_quality.text = tr("QUEST_QUALITY_" + kind.to_upper()) % int(value)
	_quality_bar.value = value
	var colour: Color = SAFE_COLOUR if value >= 60.0 else (WARN_COLOUR if value >= 35.0 else DANGER_COLOUR)
	_quality_bar.add_theme_stylebox_override("fill", UIKit._bar_fill(colour))

func _on_action_ready(ready: bool, in_range: bool) -> void:
	_action_ready = ready
	_in_range = in_range
	if _quest_id != "":
		_show_run()

func _on_timer(remaining: float) -> void:
	var parts: PackedStringArray = PackedStringArray()
	if _place != "":
		parts.append(_place)
	if _deadline > 0.0:
		parts.append(tr("QUEST_TIME_LEFT") % ceili(remaining))
	if _speed_limit > 0.0:
		parts.append(tr("QUEST_SPEED_LIMIT") % int(_speed_limit))
	if _damage_limit < 100.0:
		parts.append(tr("QUEST_DAMAGE_LIMIT"))
	if _speed_warning > 0.0:
		_limits.text = tr("QUEST_SLOW_DOWN") % ceili(_speed_warning)
		_limits.add_theme_color_override("font_color", DANGER_COLOUR)
	else:
		_limits.text = "  ·  ".join(parts)
		_limits.add_theme_color_override("font_color", UIKit.JASMINE)

func _on_finished(id: String, status: String, reason: String) -> void:
	if _quest_id != id:
		return
	if status == "failed":
		_failed = true
		_objective.text = tr("QUEST_FAILED") % tr("QUEST_FAIL_" + reason.to_upper())
		_limits.text = ""
		_quality.visible = false
		_quality_bar.visible = false
		for button: Button in _buttons:
			button.visible = false
		_photo.visible = false
		_retry.visible = true
		_refresh()
	else:
		_quest_id = ""
		_failed = false
		_located = false
		_refresh()
		if status == "completed":
			SignalBus.hint_requested.emit(tr("QUEST_COMPLETED") % UIKit.inr(_reward), 4.0)
		elif reason == "wreck_timed":
			SignalBus.hint_requested.emit(tr("QUEST_RESET_WRECK"), 5.0)
