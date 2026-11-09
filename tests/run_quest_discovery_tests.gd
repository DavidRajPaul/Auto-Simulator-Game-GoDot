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
	mission.job_key = "TEST_DRIVE"
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
	await _navigation_tests(discovery, mission)
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
	_full_map_tests(full)
	full.free()
	mini.free()
	production.free()
	SignalBus.current_road_graph = null
	print("Quest discovery: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

## Nov 9 device test: "Go there" drew no route, a pin set mid-ride replaced the rider's route,
## and "Clear route" left the quest marked as on route.
func _navigation_tests(discovery: QuestDiscovery, mission: MissionDef) -> void:
	var nav: CustomNavigation = CustomNavigation.new()
	add_child(nav)
	var routes: Array[int] = [0]
	var on_route: Callable = func(_pts: PackedVector3Array) -> void: routes[0] += 1
	SignalBus.route_updated.connect(on_route)
	SignalBus.player_pose_updated.emit(Vector3(20, 0, 0), Vector3.FORWARD)
	discovery.track(mission.id)
	check("Go there builds a GPS route to the quest", nav._active and nav._gps != null and nav._destination == mission.start_anchor and routes[0] == 1)
	discovery.track("")
	check("Clear route removes the GPS route and the tracking", not nav._active and discovery.tracked_id() == "" and routes[0] == 2)
	discovery.track(mission.id)
	SignalBus.custom_navigation_cleared.emit()
	check("map Clear also ends quest tracking", discovery.tracked_id() == "" and not nav._active)
	discovery.track(mission.id)
	SignalBus.passenger_boarded.emit(1, 0.0)
	var before: int = routes[0]
	SignalBus.custom_navigation_requested.emit(Vector3.ZERO, Vector3(180, 0, 0))
	check("pin set mid-ride is queued, rider route untouched", nav.is_queued() and nav._destination == Vector3(180, 0, 0) and routes[0] == before)
	check("a new pin replaces quest tracking", discovery.tracked_id() == "")
	SignalBus.player_pose_updated.emit(Vector3(60, 0, 0), Vector3.FORWARD)
	check("queued route never reroutes over the rider's", routes[0] == before)
	SignalBus.passenger_alighted.emit()
	await get_tree().process_frame
	check("queued route goes up after drop-off", nav._active and not nav.is_queued() and nav._gps != null and routes[0] == before + 1)
	SignalBus.custom_navigation_cleared.emit()
	SignalBus.route_updated.disconnect(on_route)
	nav.free()

func _full_map_tests(full: FullMap) -> void:
	full.size = Vector2(1280, 720)
	check("journal pages fit the catalogue", full._journal_pages() == ceili(full._quest_rows.size() / 5.0))
	full._journal_open = true
	full._journal_page = full._journal_pages() - 1
	full._journal_next = Rect2(Vector2(500, 500), Vector2(20, 20))
	full._tap_button(Vector2(505, 505))
	check("next stops on the last page with quests", full._journal_page == full._journal_pages() - 1)
	full._journal_panel = Rect2(Vector2.ZERO, Vector2(100, 100))
	full._tap_button(Vector2(900, 900))
	check("a tap on the map closes the quest list", not full._journal_open)
	full._quest_selected = "sq_001"
	full._tap_map(Vector2(-5000, -5000))
	check("a tap on empty map closes the quest card", full._quest_selected == "")
	full._quest_selected = "sq_001"
	full._clear_rect = Rect2(Vector2(700, 700), Vector2(40, 40))
	full._tap_button(Vector2(710, 710))
	check("Clear closes the quest card", full._quest_selected == "")
	full._legend_rect = Rect2(Vector2(300, 0), Vector2(40, 40))
	full._tap_button(Vector2(310, 10))
	check("Legend opens", full._legend_open and not full._journal_open)
	var missing: Array[String] = []
	for kind: String in FullMap.LEGEND_ITEMS:
		if tr("MAP_KEY_" + kind.to_upper()) == "MAP_KEY_" + kind.to_upper():
			missing.append(kind)
	check("every legend entry has a string " + str(missing), missing.is_empty())

func _count_hint(_message: String, _seconds: float) -> void:
	hints += 1
