class_name MissionDirector
extends Node
## Scene-owned runtime for the side quests in data/missions/career_quests.tres.
const LOCATED_KINDS: PackedStringArray = ["goto", "photo", "yield", "inspect", "calm", "park", "cargo", "ask", "spot"]
## A claimed cutscene that never reports back (its player was freed) moves on after this much more.
const CUTSCENE_SAFETY_S: float = 60.0
## Leaving the search circle by this factor brings the GPS route back.
const SEARCH_LEAVE_FACTOR: float = 1.35
@export var pack: MissionPack = preload("res://data/missions/career_quests.tres")
@export var quality_tuning: QuestQualityTuning = preload("res://data/missions/quality_tuning.tres")
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
var _reverse_seen: bool = false
var _action_ready: bool = false
var _action_in_range: bool = false
var _over_speed_s: float = 0.0
var _cinematic_claimed: bool = false
var _search_center: Vector3 = Vector3.ZERO
var _search_radius: float = 0.0
var _search_road: Vector3 = Vector3.ZERO # GPS destination while outside the circle
var _in_search: bool = false
var _shrunk: bool = false

func _ready() -> void:
	if not registry.load_pack(pack):
		CrashReporter.capture_message("Mission catalogue rejected: " + str(registry.errors))
	SignalBus.player_pose_updated.connect(_on_pose)
	SignalBus.speed_updated.connect(func(value: float) -> void: _speed = value)
	SignalBus.mission_start_requested.connect(start)
	SignalBus.mission_choice_requested.connect(choose)
	SignalBus.mission_interact_requested.connect(interact)
	SignalBus.mission_spot_requested.connect(spot)
	SignalBus.mission_cutscene_finished.connect(cutscene_finished)
	SignalBus.indicator_changed.connect(func(direction: int) -> void:
		if direction != 0:
			_signalled = true)
	SignalBus.gear_changed.connect(func(gear: int) -> void:
		if gear < 0:
			_reverse_seen = true)
	SignalBus.vehicle_dynamics.connect(_on_dynamics)
	SignalBus.player_impact.connect(_on_impact)
	SignalBus.horn_blasted.connect(func(_p: Vector3, _f: Vector3, _r: float, _t: int) -> void:
		if run != null and run.status == "active" and current_stage() != null and current_stage().quality_key == "comfort":
			_change_quality(-quality_tuning.horn_distress_loss))
	SignalBus.mission_retry_requested.connect(retry)
	SignalBus.mission_abandon_requested.connect(abandon)
	SignalBus.tow_requested.connect(func(_pos: Vector3) -> void: abandon("tow"))
	SignalBus.vehicle_wrecked.connect(_on_wrecked)
	SignalBus.rewarded_ad_failed.connect(func(placement: String, _reason: String) -> void:
		if placement == "ad_wreck_repair" and GameState.is_wrecked():
			_on_wrecked(true))
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
	if _busy or run != null or GameState.mission_active or GameState.tutorial_active or GameState.is_on_fire() or not _has_pose:
		return false
	if SignalBus.savari_busy_provider.is_valid() and bool(SignalBus.savari_busy_provider.call()):
		return false
	if not registry.available(id, GameState.driver_level(), GameState.mission_completed):
		return false
	var definition: MissionDef = registry.get_mission(id)
	# Validate every GoTo before taking ownership; never strand a run on an absent graph.
	for stage: MissionStage in definition.stages:
		if stage.kind in LOCATED_KINDS and not _reachable(stage.target):
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
	_reverse_seen = false
	_over_speed_s = 0.0
	if stage.quality_key != "" and not run.flags.has(stage.quality_key):
		run.flags[stage.quality_key] = 100.0
	if stage.checkpoint or run.checkpoint.is_empty():
		run.checkpoint = {"stage_id": stage.id, "flags": run.flags.duplicate(true)}
	_sync()
	GameState.save_game()
	_announce_stage()

func _announce_stage() -> void:
	var stage: MissionStage = current_stage()
	_cinematic_claimed = stage.kind == "cutscene" and SignalBus.quest_cinematic_provider.is_valid() \
		and bool(SignalBus.quest_cinematic_provider.call(run.quest_id, stage.id))
	_set_search(stage)
	_publish_route()
	SignalBus.mission_stage_changed.emit(run.quest_id, stage.id, _stage_objective(stage), stage.choices)
	SignalBus.mission_stage_info.emit({"id": run.quest_id, "stage": stage.id,
		"kind": stage.kind, "objective": _stage_objective(stage), "choices": stage.choices,
		"action": stage.action_key, "place": _stage_place(stage), "target": _stage_target(stage),
		"place_pos": _stage_place_pos(stage), "located": stage.kind in LOCATED_KINDS,
		"title": registry.get_mission(run.quest_id).title_key,
		"reward": _current_reward(),
		"deadline": stage.deadline_s, "speed": stage.max_speed_kmh,
		"damage": stage.max_condition_loss, "quality_key": stage.quality_key,
		"quality": float(run.flags.get(stage.quality_key, 100.0)),
		"cutscene": stage.cutscene_id, "spot_pos": stage.spot_pos, "search_radius": _search_radius,
		"story": registry.get_mission(run.quest_id).story != null})
	_publish_action_state(true)

func _publish_route() -> void:
	var stage: MissionStage = current_stage()
	if stage == null or stage.hidden_route or stage.kind not in LOCATED_KINDS or (stage.kind == "spot" and _in_search):
		SignalBus.gps_route_changed.emit(null)
		SignalBus.route_updated.emit(PackedVector3Array())
		return
	var graph: RoadGraph = SignalBus.current_road_graph
	if graph == null:
		_route_dirty = true
		return
	var route: Dictionary = graph.find_route(_position, _search_road if stage.kind == "spot" else _stage_target(stage))
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
		_over_speed_s += delta
		SignalBus.mission_speed_warning.emit(maxf(0.0, quality_tuning.speed_grace_s - _over_speed_s))
		if _over_speed_s >= quality_tuning.speed_grace_s:
			_over_speed_s = 0.0
			SignalBus.mission_speed_warning.emit(0.0)
			_fail("speed")
			return
	elif _over_speed_s > 0.0:
		_over_speed_s = 0.0
		SignalBus.mission_speed_warning.emit(0.0)
	if run.condition_at_stage - GameState.condition > stage.max_condition_loss:
		_fail("damage")
		return
	if stage.quality_key != "" and float(run.flags.get(stage.quality_key, 100.0)) < stage.quality_floor:
		_fail("quality")
		return
	if stage.quality_key != "" and GameState.is_raining and stage.weather_loss_per_s > 0.0:
		_change_quality(-delta * stage.weather_loss_per_s)
		if float(run.flags[stage.quality_key]) < stage.quality_floor:
			_fail("quality")
			return
	if stage.avoid_radius_m > 0.0 and _has_pose and _position.distance_to(stage.avoid_center) < stage.avoid_radius_m:
		_fail("diversion")
		return
	if stage.kind in ["goto", "ask"] and _has_pose and _position.distance_to(_stage_target(stage)) <= stage.radius_m and absf(_speed) <= stage.arrival_speed_kmh and not rider_missing():
		_advance()
	elif stage.kind == "cutscene" and run.elapsed >= stage.duration_s + (CUTSCENE_SAFETY_S if _cinematic_claimed else 0.0):
		_advance()
	elif stage.kind == "spot":
		_tick_search(stage)
	elif stage.kind == "yield" and _signalled and _has_pose and _position.distance_to(_stage_target(stage)) <= stage.radius_m and absf(_speed) <= stage.arrival_speed_kmh:
		_advance()
	elif stage.kind == "wait" and run.elapsed >= stage.duration_s:
		_advance()
	else:
		_publish_action_state(false)

## Keeps the stop-and-do button honest: it appears only when a tap will actually work.
func _publish_action_state(force: bool) -> void:
	var stage: MissionStage = current_stage()
	if stage == null or not _has_pose:
		return
	# A search circle is not a stop: being inside it never means "stop here".
	var in_range: bool = stage.kind in LOCATED_KINDS and stage.kind != "spot" and _position.distance_to(_stage_target(stage)) <= stage.radius_m
	var ready: bool = in_range and absf(_speed) <= stage.arrival_speed_kmh and not rider_missing()
	if force or ready != _action_ready or in_range != _action_in_range:
		_action_ready = ready
		_action_in_range = in_range
		SignalBus.mission_action_ready.emit(ready, in_range)

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
	if stage.kind not in ["photo", "inspect", "calm", "park", "cargo"] or not _has_pose or _position.distance_to(_stage_target(stage)) > stage.radius_m or absf(_speed) > stage.arrival_speed_kmh:
		return false
	if rider_missing():
		return false
	if stage.quality_key != "" and float(run.flags.get(stage.quality_key, 100.0)) < stage.quality_floor:
		_fail("quality")
		return false
	if stage.kind == "cargo":
		var delta: int = int(stage.cargo_delta_options.get(str(run.flags.get(stage.target_choice_stage, "")), stage.cargo_delta))
		var next_load: int = int(run.flags.get("_cargo", 0)) + delta
		if next_load < 0 or next_load > stage.cargo_capacity:
			SignalBus.hint_requested.emit(tr("QUEST_CARGO_CAPACITY"), 2.5)
			return false
		run.flags["_cargo"] = next_load
	if stage.kind == "park" and not _reverse_seen:
		SignalBus.hint_requested.emit(tr("QUEST_REVERSE_FIRST"), 2.5)
		return false
	var facing: Vector3 = Vector3(stage.facing.x, 0.0, stage.facing.z).normalized()
	var heading: Vector3 = Vector3(_heading.x, 0.0, _heading.z).normalized()
	if facing != Vector3.ZERO and (heading == Vector3.ZERO or rad_to_deg(heading.angle_to(facing)) > stage.facing_tolerance_deg):
		SignalBus.hint_requested.emit(tr("QUEST_FACE_VIEW"), 2.5)
		return false
	if stage.kind == "calm" and stage.quality_key != "":
		_change_quality(quality_tuning.calm_restore)
	_advance()
	return true

## A search: the GPS leads to the circle and goes quiet inside it; after shrink_after_s the circle
## closes in on the thing (not centred on it, so it is still a search).
func _tick_search(stage: MissionStage) -> void:
	if not _has_pose:
		return
	if not _shrunk and stage.shrink_after_s > 0.0 and run.elapsed >= stage.shrink_after_s:
		_shrunk = true
		var thing: Vector3 = Vector3(stage.spot_pos.x, 0.0, stage.spot_pos.z)
		var toward: Vector3 = Vector3(stage.target.x, 0.0, stage.target.z) - thing
		_search_center = thing + (toward.normalized() * stage.shrink_radius_m * 0.4 if toward.length_squared() > 1.0 else Vector3.ZERO)
		_search_radius = stage.shrink_radius_m
		_search_road = _road_near(_search_center, stage.target)
		SignalBus.quest_search_area_changed.emit(_search_center, _search_radius)
		SignalBus.hint_requested.emit(tr("QUEST_SEARCH_SMALLER"), 3.0)
		_in_search = false
		_publish_route()
	var flat: Vector3 = Vector3(_position.x, 0.0, _position.z)
	var d: float = flat.distance_to(_search_center)
	if not _in_search and d <= _search_radius:
		_in_search = true
		_publish_route()
	elif _in_search and d > _search_radius * SEARCH_LEAVE_FACTOR:
		_in_search = false
		_publish_route()

func _set_search(stage: MissionStage) -> void:
	_shrunk = false
	_in_search = false
	if stage.kind == "spot":
		_search_center = Vector3(stage.target.x, 0.0, stage.target.z)
		_search_radius = stage.radius_m
		_search_road = stage.target
		_in_search = _has_pose and Vector3(_position.x, 0.0, _position.z).distance_to(_search_center) <= _search_radius
	else:
		_search_center = Vector3.ZERO
		_search_radius = 0.0
	SignalBus.quest_search_area_changed.emit(_search_center, _search_radius)

func _road_near(at: Vector3, fallback: Vector3) -> Vector3:
	var graph: RoadGraph = SignalBus.current_road_graph
	if graph == null:
		return fallback
	var cp: Dictionary = graph.closest_point(at)
	if int(cp.get("edge", -1)) < 0:
		return fallback
	var p: Vector3 = graph.sample(int(cp["edge"]), float(cp["s"]), 1)[0]
	return p if bool(graph.find_route(_position, p).get("ok", false)) else fallback

## The thing was found on screen (QuestStory checked the tap): accept it if the auto really is
## close and slow enough, so a tap from across the city never counts.
func spot(quest_id: String, stage_id: String) -> bool:
	if _busy or run == null or run.status != "active" or quest_id != run.quest_id or stage_id != run.stage_id:
		return false
	var stage: MissionStage = current_stage()
	if stage.kind != "spot" or not _has_pose or absf(_speed) > stage.spot_max_kmh or rider_missing():
		return false
	var flat: Vector3 = Vector3(_position.x, 0.0, _position.z)
	if flat.distance_to(Vector3(stage.spot_pos.x, 0.0, stage.spot_pos.z)) > stage.spot_range_m:
		return false
	_advance()
	return true

func cutscene_finished(quest_id: String, stage_id: String) -> bool:
	if _busy or run == null or run.status != "active" or quest_id != run.quest_id or stage_id != run.stage_id:
		return false
	if current_stage().kind != "cutscene":
		return false
	_advance()
	return true

func _on_dynamics(lateral_g: float, longitudinal_g: float, vertical_jolt: float) -> void:
	if run == null or run.status != "active":
		return
	var stage: MissionStage = current_stage()
	if stage == null or stage.quality_key == "":
		return
	var excess: float = maxf(0.0, absf(lateral_g) - quality_tuning.g_deadzone) + maxf(0.0, absf(longitudinal_g) - quality_tuning.g_deadzone) + maxf(0.0, absf(vertical_jolt) - quality_tuning.jolt_deadzone)
	if excess > 0.0:
		_change_quality(-excess * quality_tuning.loss_per_excess_g_second * stage.quality_scale * get_physics_process_delta_time())

func _on_impact(info: Dictionary) -> void:
	if run != null and run.status == "active" and current_stage() != null and current_stage().quality_key != "":
		_change_quality(-clampf(float(info.get("severity", 0.0)), 0.0, 1.0) * quality_tuning.collision_loss * current_stage().quality_scale)
		SignalBus.hint_requested.emit(tr("QUEST_KNOCK"), 2.0)

func _change_quality(delta: float) -> void:
	var stage: MissionStage = current_stage()
	if stage == null or stage.quality_key == "":
		return
	var value: float = clampf(float(run.flags.get(stage.quality_key, 100.0)) + delta, 0.0, 100.0)
	run.flags[stage.quality_key] = value
	_sync()
	SignalBus.mission_quality_changed.emit(stage.quality_key, value)

func _current_reward() -> int:
	var definition: MissionDef = registry.get_mission(run.quest_id)
	if definition.reward_choice_stage != "":
		var choice: String = str(run.flags.get(definition.reward_choice_stage, ""))
		return int(definition.reward_choice_inr.get(choice, definition.reward_inr))
	return definition.reward_inr

func _stage_objective(stage: MissionStage) -> String:
	if run != null and stage.objective_choice_stage != "":
		var choice: String = str(run.flags.get(stage.objective_choice_stage, ""))
		if stage.objective_options.has(choice):
			return str(stage.objective_options[choice])
	return stage.objective_key

func _stage_place(stage: MissionStage) -> String:
	if run != null and stage.place_options.has(str(run.flags.get(stage.target_choice_stage, ""))):
		return str(stage.place_options[str(run.flags[stage.target_choice_stage])])
	return stage.place_key

func _stage_place_pos(stage: MissionStage) -> Vector3:
	if run != null and stage.place_pos_options.has(str(run.flags.get(stage.target_choice_stage, ""))):
		return stage.place_pos_options[str(run.flags[stage.target_choice_stage])] as Vector3
	return stage.place_pos

func _stage_target(stage: MissionStage) -> Vector3:
	if run != null and stage.target_options.has(str(run.flags.get(stage.target_choice_stage, ""))):
		return stage.target_options[str(run.flags[stage.target_choice_stage])] as Vector3
	return stage.target

func _advance(next_id: String = "") -> void:
	_busy = true
	var definition: MissionDef = registry.get_mission(run.quest_id)
	if next_id == "" and current_stage() != null and current_stage().next_id != "":
		next_id = current_stage().next_id
	var index: int = definition.stage_index(next_id) if next_id != "" else definition.stage_index(run.stage_id) + 1
	_enter_stage(index)
	_busy = false

## Wrecked mid-quest (owner rules, Nov 9). A timed quest can't be finished fairly after a wreck, so
## it is quit and starts again from the beginning. Any other quest waits while the driver gets the
## auto going again, and fails only when there is no way to: no money for a repair and no repair ad.
func _on_wrecked(wrecked: bool) -> void:
	if not wrecked or _busy or run == null or run.status != "active":
		return
	if is_timed(run.quest_id):
		abandon("wreck_timed")
	elif not _wreck_recoverable():
		_fail("wreck_stranded")

## A quest with a rider (MissionDef.rider_model) only counts its stops while she is in the auto.
func rider_missing() -> bool:
	if run == null or not SignalBus.quest_rider_aboard_provider.is_valid():
		return false
	var definition: MissionDef = registry.get_mission(run.quest_id)
	return definition != null and definition.rider_model != "" and not bool(SignalBus.quest_rider_aboard_provider.call())

func is_timed(quest_id: String) -> bool:
	var definition: MissionDef = registry.get_mission(quest_id)
	if definition == null:
		return false
	for stage: MissionStage in definition.stages:
		if stage.deadline_s > 0.0:
			return true
	return false

func _wreck_recoverable() -> bool:
	return GameState.wallet_inr >= GameState.REPAIR_COST_PER_POINT or AdMonetizationManager.can_offer_rewarded("ad_wreck_repair")

func _fail(reason: String) -> void:
	run.status = "failed"
	SignalBus.quest_search_area_changed.emit(Vector3.ZERO, 0.0)
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
	if _busy or run == null or run.status != "failed" or GameState.is_on_fire():
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
	_announce_stage()
	return true

func _complete() -> void:
	var definition: MissionDef = registry.get_mission(run.quest_id)
	var id: String = run.quest_id
	# Completion and reward are a single synchronous state transition. The permanent
	# ledger key also protects replay after its display entry has been pruned.
	GameState.mission_reward_transaction = true
	GameState.mission_completed[id] = {"content_version": run.content_version, "completed": true}
	var earned_inr: int = _current_reward()
	var earned_xp: int = definition.reward_xp
	if definition.reward_choice_stage != "":
		earned_xp += int(definition.reward_choice_xp.get(str(run.flags.get(definition.reward_choice_stage, "")), 0))
	GameState.grant_reward("mission", earned_inr, earned_xp, "mission:" + id + ":complete")
	_finish("completed", "")

func abandon(reason: String = "abandoned") -> void:
	if run != null and not _busy:
		_finish("abandoned", reason)

func _finish(status: String, reason: String) -> void:
	var id: String = run.quest_id
	SignalBus.quest_search_area_changed.emit(Vector3.ZERO, 0.0)
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
