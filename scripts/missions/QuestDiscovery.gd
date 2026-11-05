class_name QuestDiscovery
extends Node
## Scene-owned discovery service. Never changes mission or passenger route ownership.
@export var pack: MissionPack = preload("res://data/missions/career_quests.tres")
@export var tuning: QuestDiscoveryTuning = preload("res://data/missions/discovery_tuning.tres")
var registry: MissionRegistry = MissionRegistry.new()
var _grid: Dictionary = {}
var _position: Vector3
var _speed_kmh: float = 0.0
var _has_pose: bool = false
var _elapsed: float = 0.0
var _hinted: Dictionary = {}
var _inside: Dictionary = {}
var _modal: bool = false

func _ready() -> void:
	if not registry.load_pack(pack):
		push_error("Discovery catalogue invalid: " + str(registry.errors))
		return
	_build_grid()
	SignalBus.quest_discovery_provider = Callable(self, "catalogue")
	SignalBus.quest_action_provider = Callable(self, "action")
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void:
		_position = p
		_has_pose = true)
	SignalBus.speed_updated.connect(func(s: float) -> void: _speed_kmh = s)
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void: _modal = open)
	SignalBus.mission_profile_loaded.connect(func() -> void:
		_hinted.clear()
		_inside.clear()
		SignalBus.quest_catalogue_changed.emit())
	SignalBus.tutorial_finished.connect(func(_skipped: bool) -> void: _teach_once())
	_teach_once.call_deferred()
	SignalBus.quest_catalogue_changed.emit()

func _exit_tree() -> void:
	if SignalBus.quest_discovery_provider.is_valid() and SignalBus.quest_discovery_provider.get_object() == self:
		SignalBus.quest_discovery_provider = Callable()
		SignalBus.quest_action_provider = Callable()

func action(kind: String, id: String) -> bool:
	match kind:
		"track": return track(id)
		"start": return request_start(id)
	return false

func _build_grid() -> void:
	_grid.clear()
	for id: String in registry.definitions:
		var quest: MissionDef = registry.get_mission(id)
		if not quest.discoverable:
			continue
		var key: Vector2i = _cell(quest.start_anchor)
		if not _grid.has(key):
			_grid[key] = PackedStringArray()
		var ids: PackedStringArray = _grid[key]
		ids.append(id)
		_grid[key] = ids

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / tuning.cell_size_m), floori(p.z / tuning.cell_size_m))

func catalogue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in registry.definitions:
		var q: MissionDef = registry.get_mission(id)
		if not q.discoverable:
			continue
		var completed: bool = GameState.mission_completed.has(id)
		var unlocked: bool = registry.available(id, GameState.driver_level(), GameState.mission_completed)
		result.append({"id": id, "title": tr(q.title_key), "description": tr(q.description_key),
			"position": q.start_anchor, "category": q.category, "minutes": q.estimated_minutes,
			"completed": completed, "unlocked": unlocked,
			"locked_reason": tr("QUEST_LEVEL") % q.unlock_level if GameState.driver_level() < q.unlock_level else tr("QUEST_PREREQUISITE"),
			"tracked": str(GameState.settings.get("quest_track_id", "")) == id})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return result

func track(id: String) -> bool:
	if id != "" and (registry.get_mission(id) == null or not registry.get_mission(id).discoverable):
		return false
	GameState.settings["quest_track_id"] = id
	GameState.save_game()
	SignalBus.quest_tracking_changed.emit(id)
	return true

func can_start(id: String) -> bool:
	var q: MissionDef = registry.get_mission(id)
	if q == null or not q.discoverable or not _has_pose or _speed_kmh > tuning.stopped_kmh or GameState.tutorial_active or GameState.mission_active or not GameState.mission_run.is_empty() or GameState.is_wrecked():
		return false
	if SignalBus.savari_busy_provider.is_valid() and bool(SignalBus.savari_busy_provider.call()):
		return false
	if GameState.mission_completed.has(id) or not registry.available(id, GameState.driver_level(), GameState.mission_completed):
		return false
	if _position.distance_to(q.start_anchor) > tuning.interact_m or not SignalBus.walkable(q.start_anchor.x, q.start_anchor.z):
		return false
	return _road_approach(q.start_anchor, 5.0) and _road_approach(_position, 5.0)

func request_start(id: String) -> bool:
	if not can_start(id):
		return false
	var graph: RoadGraph = SignalBus.current_road_graph
	for stage: MissionStage in registry.get_mission(id).stages:
		if stage.kind in ["goto", "photo", "yield", "inspect", "calm", "park", "cargo"] and not bool(graph.find_route(_position, stage.target).get("ok", false)):
			return false
		for option: String in stage.target_options:
			if not bool(graph.find_route(_position, stage.target_options[option] as Vector3).get("ok", false)):
				return false
	SignalBus.mission_start_requested.emit(id)
	return true

func _road_approach(anchor: Vector3, radius: float) -> bool:
	var graph: RoadGraph = SignalBus.current_road_graph
	if graph == null:
		return false
	var closest: Dictionary = graph.closest_point(anchor)
	if int(closest.get("edge", -1)) < 0:
		return false
	return float(closest.get("dist", INF)) <= radius

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if not _has_pose or _elapsed < tuning.check_interval_s:
		return
	var step: float = _elapsed
	_elapsed = 0.0
	for id: String in _hinted:
		_hinted[id] = maxf(0.0, float(_hinted[id]) - step)
	for id: String in _inside.keys():
		if _position.distance_to(registry.get_mission(id).start_anchor) > tuning.hint_exit_m:
			_inside.erase(id)
	if GameState.tutorial_active or GameState.mission_active or _modal or (SignalBus.savari_busy_provider.is_valid() and bool(SignalBus.savari_busy_provider.call())):
		return
	var c: Vector2i = _cell(_position)
	var n: int = ceili(tuning.hint_exit_m / tuning.cell_size_m)
	for dx: int in range(-n, n + 1):
		for dz: int in range(-n, n + 1):
			for id: String in _grid.get(c + Vector2i(dx, dz), PackedStringArray()):
				var q: MissionDef = registry.get_mission(id)
				var distance: float = _position.distance_to(q.start_anchor)
				if distance > tuning.hint_exit_m:
					_inside.erase(id)
					continue
				if _inside.has(id) or distance > tuning.hint_enter_m or float(_hinted.get(id, 0.0)) > 0.0 or GameState.mission_completed.has(id) or not registry.available(id, GameState.driver_level(), GameState.mission_completed):
					continue
				if not SignalBus.walkable(q.start_anchor.x, q.start_anchor.z) or not _road_approach(q.start_anchor, 11.0):
					continue
				var graph: RoadGraph = SignalBus.current_road_graph
				var route: Dictionary = graph.find_route(_position, q.start_anchor)
				if not bool(route.get("ok", false)) or float(route.get("length", INF)) > tuning.hint_enter_m * tuning.max_route_factor:
					continue
				_inside[id] = true
				_hinted[id] = tuning.hint_cooldown_s
				SignalBus.hint_requested.emit(tr("QUEST_NEARBY") % tr(q.title_key), 3.5)
				return

func _teach_once() -> void:
	if not GameState.persistence_enabled or GameState.tutorial_active or not bool(GameState.settings.get("first_ride_done", false)) or bool(GameState.settings.get("quest_lesson_done", false)):
		return
	GameState.settings["quest_lesson_done"] = true
	GameState.save_game()
	SignalBus.hint_requested.emit(tr("QUEST_LESSON"), 6.0)
