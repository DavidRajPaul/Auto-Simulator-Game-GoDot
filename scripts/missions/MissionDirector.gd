class_name MissionDirector
extends Node
## Scene-owned runtime; the production pack is deliberately empty in Phase 1.
@export var pack: MissionPack = preload("res://data/missions/career_quests.tres")
var registry: MissionRegistry = MissionRegistry.new()
var run: MissionRunState
var _position: Vector3 = Vector3.ZERO
var _has_pose: bool = false
var _speed: float = 0.0
var _busy: bool = false
var _resume_pending: bool = true
var _route_dirty: bool = false
var _heading: Vector3 = Vector3.FORWARD
var _signalled: bool = false
var _ambulance_placed: bool = false
var _ambulance_retry_s: float = 0.0
var _timer_broadcast: float = 0.0

func _ready() -> void:
	if not registry.load_pack(pack):
		CrashReporter.capture_message("Mission catalogue rejected: " + str(registry.errors))
	SignalBus.player_pose_updated.connect(_on_pose)
	SignalBus.speed_updated.connect(func(value: float) -> void: _speed = value)
	SignalBus.mission_start_requested.connect(start)
	SignalBus.mission_choice_requested.connect(choose)
	SignalBus.mission_interact_requested.connect(interact)
	SignalBus.indicator_changed.connect(func(direction: int) -> void:
		if direction != 0:
			_signalled = true)
	SignalBus.mission_retry_requested.connect(retry)
	SignalBus.mission_abandon_requested.connect(abandon)
	SignalBus.tow_requested.connect(func(_pos: Vector3) -> void: abandon("tow"))
	SignalBus.vehicle_wrecked.connect(func(wrecked: bool) -> void:
		if wrecked: abandon("wreck"))
	SignalBus.shift_ended.connect(func(_summary: Dictionary) -> void: abandon("shift_end"))
	SignalBus.road_graph_ready.connect(func(_graph: RoadGraph) -> void: _route_dirty = true)
	SignalBus.mission_profile_loaded.connect(_on_profile_loaded)

func _on_profile_loaded() -> void:
	# The profile is authoritative; do not write an old scene's run into a new career.
	run = null
	_resume_pending = true
	SignalBus.mission_ownership_changed.emit(false)

func _exit_tree() -> void:
	if run != null:
		_sync()
		_restore_scenario()
		GameState.mission_active = false
		SignalBus.mission_ownership_changed.emit(false)
		GameState.save_game()

func _on_pose(position: Vector3, _heading: Vector3) -> void:
	_position = position
	_has_pose = true
	self._heading = _heading

func _physics_process(delta: float) -> void:
	if _resume_pending and _has_pose and SignalBus.current_road_graph != null:
		_resume_pending = false
		resume_saved()
	if _route_dirty and run != null and run.status == "active":
		_route_dirty = false
		_publish_route()
	if run != null and run.status == "active" and run.quest_id == "sq_016" and not _ambulance_placed and current_stage() != null and current_stage().kind == "yield" and SignalBus.scripted_ambulance_provider.is_valid():
		_ambulance_retry_s -= delta
		if _ambulance_retry_s <= 0.0:
			_ambulance_retry_s = 0.5
			_ambulance_placed = bool(SignalBus.scripted_ambulance_provider.call())
	tick(delta)

func start(id: String) -> bool:
	if _busy or run != null or GameState.mission_active or GameState.tutorial_active or GameState.is_wrecked() or not _has_pose:
		return false
	if SignalBus.savari_busy_provider.is_valid() and bool(SignalBus.savari_busy_provider.call()):
		return false
	if not registry.available(id, GameState.driver_level(), GameState.mission_completed):
		return false
	var definition: MissionDef = registry.get_mission(id)
	# Validate every GoTo before taking ownership; never strand a run on an absent graph.
	for stage: MissionStage in definition.stages:
		if stage.kind in ["goto", "photo", "yield"] and not _reachable(stage.target):
			return false
		for option: String in stage.target_options:
			if not _reachable(stage.target_options[option] as Vector3):
				return false
	_busy = true
	_resume_pending = false
	run = MissionRunState.new()
	run.quest_id = id
	_ambulance_placed = false
	_ambulance_retry_s = 0.0
	run.content_version = definition.content_version
	run.scenario = {"minute": GameState.shift_minute, "running": GameState.shift_running,
		"rain": [GameState.rain_window.x, GameState.rain_window.y], "raining": GameState.is_raining}
	_claim()
	_enter_stage(0)
	_busy = false
	return true

func _reachable(target: Vector3) -> bool:
	var graph: RoadGraph = SignalBus.current_road_graph
	return graph != null and bool(graph.find_route(_position, target).get("ok", false))

func _claim() -> void:
	GameState.mission_active = true
	GameState.shift_running = false
	var definition: MissionDef = registry.get_mission(run.quest_id)
	if definition.scenario_minute >= 0:
		GameState.shift_minute = definition.scenario_minute
	if definition.scenario_weather != "unchanged":
		GameState.is_raining = definition.scenario_weather == "rain"
		SignalBus.weather_changed.emit(GameState.is_raining)
	SignalBus.shift_clock_updated.emit(GameState.day, GameState.shift_minute)
	SignalBus.mission_ownership_changed.emit(true)

func current_stage() -> MissionStage:
	if run == null:
		return null
	var definition: MissionDef = registry.get_mission(run.quest_id)
	var index: int = definition.stage_index(run.stage_id)
	return definition.stages[index] if index >= 0 else null

func _enter_stage(index: int) -> void:
	var definition: MissionDef = registry.get_mission(run.quest_id)
	if index >= definition.stages.size():
		_complete()
		return
	var stage: MissionStage = definition.stages[index]
	run.stage_id = stage.id
	run.elapsed = 0.0
	run.condition_at_stage = GameState.condition
	_signalled = false
	if stage.checkpoint or run.checkpoint.is_empty():
		run.checkpoint = {"stage_id": stage.id, "flags": run.flags.duplicate(true)}
	_sync()
	GameState.save_game()
	_publish_route()
	SignalBus.mission_stage_changed.emit(run.quest_id, stage.id, stage.objective_key, stage.choices)
	SignalBus.mission_stage_info.emit({"id": run.quest_id, "stage": stage.id,
		"kind": stage.kind, "objective": stage.objective_key, "choices": stage.choices,
		"deadline": stage.deadline_s, "speed": stage.max_speed_kmh,
		"damage": stage.max_condition_loss})

func _publish_route() -> void:
	var stage: MissionStage = current_stage()
	if stage == null or stage.kind not in ["goto", "photo", "yield"]:
		SignalBus.gps_route_changed.emit(null)
		SignalBus.route_updated.emit(PackedVector3Array())
		return
	var graph: RoadGraph = SignalBus.current_road_graph
	if graph == null:
		_route_dirty = true
		return
	var route: Dictionary = graph.find_route(_position, _stage_target(stage))
	if not bool(route.get("ok", false)):
		_fail("unreachable")
		return
	var gps: GpsRoute = GpsRoute.build(graph, route)
	SignalBus.gps_route_changed.emit(gps)
	SignalBus.route_updated.emit(gps.path)

func tick(delta: float) -> void:
	if _busy or run == null or run.status != "active" or delta < 0 or not is_finite(delta):
		return
	var stage: MissionStage = current_stage()
	run.elapsed += delta
	_timer_broadcast += delta
	if _timer_broadcast >= 0.25 and stage.deadline_s > 0.0:
		_timer_broadcast = 0.0
		SignalBus.mission_timer_updated.emit(maxf(0.0, stage.deadline_s - run.elapsed))
	if stage.deadline_s > 0 and run.elapsed > stage.deadline_s:
		_fail("deadline")
		return
	if stage.max_speed_kmh > 0 and absf(_speed) > stage.max_speed_kmh:
		_fail("speed")
		return
	if run.condition_at_stage - GameState.condition > stage.max_condition_loss:
		_fail("damage")
		return
	if stage.kind == "goto" and _has_pose and _position.distance_to(_stage_target(stage)) <= stage.radius_m and absf(_speed) <= stage.arrival_speed_kmh:
		_advance()
	elif stage.kind == "yield" and _signalled and _has_pose and _position.distance_to(_stage_target(stage)) <= stage.radius_m and absf(_speed) <= stage.arrival_speed_kmh:
		_advance()
	elif stage.kind == "wait" and run.elapsed >= stage.duration_s:
		_advance()

func choose(quest_id: String, stage_id: String, choice: String) -> bool:
	if _busy or run == null or run.status != "active" or run.quest_id != quest_id or run.stage_id != stage_id:
		return false
	var stage: MissionStage = current_stage()
	if stage.kind != "dialogue" or not stage.choices.has(choice):
		return false
	run.flags[stage.id] = choice
	var destination: String = str(stage.next_by_choice.get(choice, ""))
	_advance(destination)
	return true

func interact(quest_id: String, stage_id: String) -> bool:
	if _busy or run == null or run.status != "active" or quest_id != run.quest_id or stage_id != run.stage_id:
		return false
	var stage: MissionStage = current_stage()
	if stage.kind != "photo" or not _has_pose or _position.distance_to(_stage_target(stage)) > stage.radius_m or absf(_speed) > stage.arrival_speed_kmh:
		return false
	var facing: Vector3 = Vector3(stage.facing.x, 0.0, stage.facing.z).normalized()
	var heading: Vector3 = Vector3(_heading.x, 0.0, _heading.z).normalized()
	if facing != Vector3.ZERO and (heading == Vector3.ZERO or rad_to_deg(heading.angle_to(facing)) > stage.facing_tolerance_deg):
		SignalBus.hint_requested.emit(tr("QUEST_FACE_VIEW"), 2.5)
		return false
	_advance()
	return true

func _stage_target(stage: MissionStage) -> Vector3:
	if run != null and stage.target_options.has(str(run.flags.get(stage.target_choice_stage, ""))):
		return stage.target_options[str(run.flags[stage.target_choice_stage])] as Vector3
	return stage.target

func _advance(next_id: String = "") -> void:
	_busy = true
	var definition: MissionDef = registry.get_mission(run.quest_id)
	var index: int = definition.stage_index(next_id) if next_id != "" else definition.stage_index(run.stage_id) + 1
	_enter_stage(index)
	_busy = false

func _fail(reason: String) -> void:
	run.status = "failed"
	_restore_scenario()
	run.scenario = {}
	GameState.mission_active = false
	SignalBus.gps_route_changed.emit(null)
	SignalBus.route_updated.emit(PackedVector3Array())
	SignalBus.mission_ownership_changed.emit(false)
	_sync()
	GameState.save_game()
	SignalBus.mission_finished.emit(run.quest_id, "failed", reason)

func retry() -> bool:
	if _busy or run == null or run.status != "failed" or GameState.is_wrecked():
		return false
	if GameState.tutorial_active or (SignalBus.savari_busy_provider.is_valid() and bool(SignalBus.savari_busy_provider.call())):
		return false
	run.scenario = {"minute": GameState.shift_minute, "running": GameState.shift_running,
		"rain": [GameState.rain_window.x, GameState.rain_window.y], "raining": GameState.is_raining}
	_ambulance_placed = false
	_ambulance_retry_s = 0.0
	_claim()
	return _restore_checkpoint()

func _restore_checkpoint() -> bool:
	var definition: MissionDef = registry.get_mission(run.quest_id)
	var index: int = definition.stage_index(str(run.checkpoint.get("stage_id", "")))
	if index < 0 or not run.checkpoint.get("flags") is Dictionary:
		abandon("invalid_checkpoint")
		return false
	run.flags = (run.checkpoint["flags"] as Dictionary).duplicate(true)
	run.status = "active"
	_enter_stage(index)
	return true

func resume_saved() -> bool:
	if run != null or GameState.mission_run.is_empty():
		return false
	run = MissionRunState.read(GameState.mission_run)
	var definition: MissionDef = registry.get_mission(run.quest_id)
	if definition == null or definition.content_version != run.content_version or definition.stage_index(run.stage_id) < 0 or run.status not in ["active", "failed"]:
		CrashReporter.capture_message("Mission resume rejected: incompatible definition")
		abandon("content_changed")
		return false
	if GameState.tutorial_active or GameState.is_wrecked() or (SignalBus.savari_busy_provider.is_valid() and bool(SignalBus.savari_busy_provider.call())):
		abandon("career_busy")
		return false
	if run.status == "failed":
		_restore_scenario()
		return true
	_ambulance_placed = false
	_claim()
	return _restore_checkpoint()

func _complete() -> void:
	var definition: MissionDef = registry.get_mission(run.quest_id)
	var id: String = run.quest_id
	# Completion and reward are a single synchronous state transition. The permanent
	# ledger key also protects replay after its display entry has been pruned.
	GameState.mission_reward_transaction = true
	GameState.mission_completed[id] = {"content_version": run.content_version, "completed": true}
	GameState.grant_reward("mission", definition.reward_inr, definition.reward_xp, "mission:" + id + ":complete")
	_finish("completed", "")

func abandon(reason: String = "abandoned") -> void:
	if run != null and not _busy:
		_finish("abandoned", reason)

func _finish(status: String, reason: String) -> void:
	var id: String = run.quest_id
	_restore_scenario()
	run = null
	GameState.mission_run = {}
	GameState.mission_active = false
	SignalBus.gps_route_changed.emit(null)
	SignalBus.route_updated.emit(PackedVector3Array())
	SignalBus.mission_ownership_changed.emit(false)
	GameState.mission_reward_transaction = false
	GameState.save_game()
	SignalBus.mission_finished.emit(id, status, reason)

func _restore_scenario() -> void:
	if not run.scenario.has("minute"):
		return
	GameState.shift_minute = float(run.scenario["minute"])
	GameState.shift_running = bool(run.scenario.get("running", true))
	var rain: Variant = run.scenario.get("rain", [-1.0, -1.0])
	if rain is Array and rain.size() == 2:
		GameState.rain_window = Vector2(float(rain[0]), float(rain[1]))
	GameState.is_raining = bool(run.scenario.get("raining", false))
	SignalBus.weather_changed.emit(GameState.is_raining)
	SignalBus.shift_clock_updated.emit(GameState.day, GameState.shift_minute)

func _sync() -> void:
	if run != null:
		GameState.mission_run = run.to_dict()
