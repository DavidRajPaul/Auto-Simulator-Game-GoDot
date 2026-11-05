extends Node
var passed: int = 0
var failed: int = 0
var hints: int = 0

func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.persistence_enabled = false
	GameState.reset_profile()
	var graph: RoadGraph = RoadGraph.new()
	graph.add_node(Vector3.ZERO)
	graph.add_node(Vector3(200, 0, 0))
	graph.add_edge(0, 1, PackedVector3Array([Vector3.ZERO, Vector3(200, 0, 0)]), 10.0, 1, 1)
	SignalBus.current_road_graph = graph
	var stage: MissionStage = MissionStage.new()
	stage.id = "arrival"
	stage.kind = "goto"
	stage.objective_key = "TEST_DRIVE"
	stage.target = Vector3(150, 0, 0)
	var mission: MissionDef = MissionDef.new()
	mission.id = "roadside_test"
	mission.title_key = "TEST_QUEST"
	mission.description_key = "TEST_DRIVE"
	mission.discoverable = true
	mission.start_anchor = Vector3(100, 0, 0)
	mission.stages = [stage]
	var pack: MissionPack = MissionPack.new()
	pack.id = "discovery_fixture"
	pack.missions = [mission]
	var discovery: QuestDiscovery = QuestDiscovery.new()
	discovery.pack = pack
	add_child(discovery)
	discovery.set_physics_process(false)
	SignalBus.hint_requested.connect(_count_hint)
	check("catalogue loads a discoverable quest", discovery.catalogue().size() == 1)
	check("cannot start before a pose", not discovery.can_start(mission.id))
	SignalBus.player_pose_updated.emit(Vector3(100, 0, 0), Vector3.FORWARD)
	SignalBus.speed_updated.emit(20.0)
	check("moving auto cannot begin", not discovery.can_start(mission.id))
	SignalBus.speed_updated.emit(0.0)
	check("stopped roadside auto can begin", discovery.can_start(mission.id))
	discovery._physics_process(0.3)
	check("nearby hint appears once", hints == 1)
	discovery._physics_process(0.3)
	check("staying inside does not repeat", hints == 1)
	SignalBus.player_pose_updated.emit(Vector3(500, 0, 0), Vector3.FORWARD)
	discovery._physics_process(0.3)
	SignalBus.player_pose_updated.emit(Vector3(100, 0, 0), Vector3.FORWARD)
	discovery._physics_process(0.3)
	check("reentry obeys cooldown", hints == 1)
	GameState.tutorial_active = true
	check("tutorial suppresses start", not discovery.can_start(mission.id))
	GameState.tutorial_active = false
	SignalBus.savari_busy_provider = func() -> bool: return true
	check("active fare suppresses start", not discovery.can_start(mission.id))
	SignalBus.savari_busy_provider = Callable()
	GameState.mission_run = {"quest_id": "previous_failed", "status": "failed"}
	check("failed quest must be resolved before a new start", not discovery.can_start(mission.id))
	GameState.mission_run = {}
	check("tracking does not start the mission", discovery.track(mission.id) and not GameState.mission_active and str(GameState.settings.get("quest_track_id")) == mission.id)
	SignalBus.player_pose_updated.emit(Vector3(140, 0, 0), Vector3.FORWARD)
	check("distant auto cannot begin", not discovery.can_start(mission.id))
	SignalBus.player_pose_updated.emit(Vector3(100, 0, 0), Vector3.FORWARD)
	GameState.mission_completed[mission.id] = {"completed": true}
	check("completed quest cannot restart from marker", not discovery.can_start(mission.id))
	check("completion reflected in journal", bool(discovery.catalogue()[0]["completed"]))
	GameState.mission_completed.clear()
	check("bad ID refused", not discovery.track("missing"))
	discovery.free()
	# Godot 4.5.1 empties every Packed*Array when export converts text resources to binary:
	# quests then fail validation in the APK only, while every source-tree test still passes.
	check("export keeps text resources", not bool(ProjectSettings.get_setting("editor/export/convert_text_resources_to_binary", true)))
	# Career creates the map controls before it registers the production catalogue.
	var full: FullMap = FullMap.new()
	var mini: MiniMap = MiniMap.new()
	add_child(full)
	add_child(mini)
	var production: QuestDiscovery = QuestDiscovery.new()
	add_child(production)
	check("Career catalogue reaches both maps", full._quest_rows.size() == 24 and mini._quests.size() == 24)
	check("tracking reaches both maps", production.track("sq_001") and bool(full._quest_rows[0]["tracked"]) and bool(mini._quests[0]["tracked"]))
	full.free()
	mini.free()
	production.free()
	SignalBus.current_road_graph = null
	print("Quest discovery: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _count_hint(_message: String, _seconds: float) -> void:
	hints += 1
