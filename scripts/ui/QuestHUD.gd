class_name QuestHUD
extends CanvasLayer
## Preallocated compact mission strip. Choices are data-driven; no per-stage UI nodes.
var _card: PanelContainer
var _objective: Label
var _limits: Label
var _quality: Label
var _buttons: Array[Button] = []
var _photo: Button
var _retry: Button
var _leave: Button
var _quest_id: String = ""
var _stage_id: String = ""
var _kind: String = ""
var _modal: bool = false
var _map_open: bool = false
var _deadline: float = 0.0
var _speed_limit: float = 0.0
var _damage_limit: float = 100.0

func _ready() -> void:
	layer = 12
	_card = PanelContainer.new()
	_card.theme = UIKit.theme()
	_card.add_theme_stylebox_override("panel", UIKit.card_box(Color(0.08, 0.09, 0.12, 0.92), 18))
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_card)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_card.add_child(col)
	_objective = UIKit.label("", 20, UIKit.YELLOW, true)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_objective)
	_limits = UIKit.label("", 14, UIKit.JASMINE)
	col.add_child(_limits)
	_quality = UIKit.label("", 15, UIKit.YELLOW)
	_quality.visible = false
	col.add_child(_quality)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for i: int in 3:
		var choice: Button = Button.new()
		choice.custom_minimum_size = Vector2(122, 48)
		choice.add_theme_font_size_override("font_size", 17)
		choice.pressed.connect(_choose.bind(i))
		choice.visible = false
		row.add_child(choice)
		_buttons.append(choice)
	_photo = Button.new()
	_photo.text = tr("QUEST_TAKE_PHOTO")
	_photo.custom_minimum_size = Vector2(145, 48)
	_photo.pressed.connect(func() -> void: SignalBus.mission_interact_requested.emit(_quest_id, _stage_id))
	_photo.visible = false
	row.add_child(_photo)
	_retry = Button.new()
	_retry.text = tr("QUEST_RETRY")
	_retry.custom_minimum_size = Vector2(125, 48)
	_retry.pressed.connect(func() -> void: SignalBus.mission_retry_requested.emit())
	_retry.visible = false
	row.add_child(_retry)
	_leave = Button.new()
	_leave.text = tr("QUEST_LEAVE")
	_leave.custom_minimum_size = Vector2(125, 48)
	_leave.pressed.connect(func() -> void: SignalBus.mission_abandon_requested.emit("player_left"))
	_leave.visible = false
	row.add_child(_leave)
	_card.visible = false
	SignalBus.mission_stage_info.connect(_on_stage)
	SignalBus.mission_timer_updated.connect(_on_timer)
	SignalBus.mission_quality_changed.connect(func(kind: String, value: float) -> void:
		_quality.text = tr("QUEST_QUALITY_" + kind.to_upper()) % int(value))
	SignalBus.mission_finished.connect(_on_finished)
	SignalBus.mission_profile_loaded.connect(func() -> void:
		_quest_id = ""
		_refresh())
	SignalBus.full_map_state_changed.connect(func(open: bool) -> void:
		_map_open = open
		_refresh())
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void:
		_modal = open
		_refresh())
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_card.custom_minimum_size = Vector2(minf(510.0, vp.x - 32.0), 0.0)
	_card.position = Vector2(maxf(16.0, (vp.x - _card.custom_minimum_size.x) * 0.5), 12.0)

func _refresh() -> void:
	_card.visible = _quest_id != "" and not _modal and not _map_open and not GameState.tutorial_active

func _choose(index: int) -> void:
	if index < _buttons.size() and _buttons[index].visible:
		SignalBus.mission_choice_requested.emit(_quest_id, _stage_id, str(_buttons[index].get_meta("choice")))

func _on_stage(info: Dictionary) -> void:
	_quest_id = str(info["id"])
	_stage_id = str(info["stage"])
	_kind = str(info["kind"])
	_deadline = float(info["deadline"])
	_speed_limit = float(info["speed"])
	_damage_limit = float(info["damage"])
	_objective.text = tr(str(info["objective"]))
	var choices: PackedStringArray = info["choices"]
	for i: int in _buttons.size():
		_buttons[i].visible = i < choices.size()
		if i < choices.size():
			_buttons[i].text = tr(choices[i])
			_buttons[i].set_meta("choice", choices[i])
	_photo.visible = _kind in ["photo", "inspect", "calm", "park"]
	_photo.text = tr({"photo": "QUEST_TAKE_PHOTO", "inspect": "QUEST_INSPECT", "calm": "QUEST_CALM", "park": "QUEST_PARK"}.get(_kind, "QUEST_INSPECT"))
	_quality.visible = str(info.get("quality_key", "")) != ""
	if _quality.visible:
		_quality.text = tr("QUEST_QUALITY_" + str(info["quality_key"]).to_upper()) % int(info["quality"])
	_retry.visible = false
	_leave.visible = true
	_on_timer(_deadline)
	_refresh()

func _on_timer(remaining: float) -> void:
	var parts: PackedStringArray = PackedStringArray()
	if _deadline > 0.0:
		parts.append(tr("QUEST_TIME_LEFT") % ceili(remaining))
	if _speed_limit > 0.0:
		parts.append(tr("QUEST_SPEED_LIMIT") % int(_speed_limit))
	if _damage_limit < 100.0:
		parts.append(tr("QUEST_DAMAGE_LIMIT") % int(_damage_limit))
	_limits.text = "  ·  ".join(parts)

func _on_finished(id: String, status: String, reason: String) -> void:
	if _quest_id != id:
		return
	if status == "failed":
		_objective.text = tr("QUEST_FAILED") % tr("QUEST_FAIL_" + reason.to_upper())
		_limits.text = ""
		_quality.visible = false
		for button: Button in _buttons:
			button.visible = false
		_photo.visible = false
		_retry.visible = true
		_leave.visible = true
	else:
		_quest_id = ""
		_refresh()
		if status == "completed":
			SignalBus.hint_requested.emit(tr("QUEST_COMPLETED"), 4.0)
