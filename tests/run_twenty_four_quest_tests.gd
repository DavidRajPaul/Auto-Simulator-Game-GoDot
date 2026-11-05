extends Node
var passed: int = 0
var failed: int = 0
var director: MissionDirector
const IDS = ["sq_003", "sq_005", "sq_007", "sq_008", "sq_010", "sq_014", "sq_015", "sq_017", "sq_018", "sq_020", "sq_023", "sq_025"]

func _ready() -> void:
	_run.call_deferred()

func check(label: String, okay: bool) -> void:
	if okay:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func pose(point: Vector3, heading: Vector3 = Vector3.FORWARD) -> void:
	SignalBus.player_pose_updated.emit(point, heading)
	SignalBus.speed_updated.emit(0.0)

func _run() -> void:
	GameState.persistence_enabled = false
	GameState.reset_profile()
	SignalBus.current_road_graph = RoadGraph.from_json_file("res://data/world/road_graph.json")
	director = MissionDirector.new()
	add_child(director)
	director.set_physics_process(false)
	check("24 production definitions", director.registry.definitions.size() == 24)
	for id: String in IDS:
		play(id, "")
	for variation: Array in [["sq_003", "SQ03_FRONT"], ["sq_005", "SQ05_TEMPLE"],
		["sq_007", "SQ07_BLUE"], ["sq_008", "SQ08_BOXES"],
		["sq_010", "SQ10_GENERAL"], ["sq_014", "SQ14_SKIP"],
		["sq_015", "SQ15_LIBRARY"], ["sq_017", "SQ17_DESK"],
		["sq_018", "SQ18_CHARGER"], ["sq_023", "SQ23_NARROW"], ["sq_025", "SQ25_ARCH"]]:
		play(variation[0], variation[1])
	capacity_and_weather()
	director.queue_free()
	SignalBus.current_road_graph = null
	print("Twenty-four quests: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func play(id: String, alternate: String) -> void:
	GameState.reset_profile()
	var quest: MissionDef = director.registry.get_mission(id)
	pose(quest.start_anchor)
	if not director.start(id):
		check(id + " starts on a connected road", false)
		return
	check(id + " starts on a connected road", true)
	for _step: int in 30:
		if director.run == null or director.run.status != "active":
			break
		var stage: MissionStage = director.current_stage()
		var before: String = stage.id
		match stage.kind:
			"dialogue":
				var choice: String = alternate if stage.choices.has(alternate) else stage.choices[0]
				check(id + "/" + before + " choice", director.choose(id, before, choice))
			"goto":
				pose(director._stage_target(stage))
				director.tick(0.1)
			"cargo", "inspect", "park", "photo":
				pose(director._stage_target(stage), stage.facing if stage.facing != Vector3.ZERO else Vector3.FORWARD)
				if stage.kind == "park":
					SignalBus.gear_changed.emit(-1)
				check(id + "/" + before + " interaction", director.interact(id, before))
		if director.run != null and director.run.stage_id == before:
			check(id + "/" + before + " progresses", false)
			break
	check(id + " completed", director.run == null and GameState.mission_completed.has(id))
	check(id + " cargo emptied", GameState.mission_run.is_empty())
	check(id + " releases Career", not GameState.mission_active)

func capacity_and_weather() -> void:
	GameState.reset_profile()
	pose(director.registry.get_mission("sq_015").start_anchor)
	check("bus relief starts", director.start("sq_015"))
	director.run.flags["_cargo"] = 1
	check("seat capacity prevents extra boarding", not director.interact("sq_015", "board") and int(director.run.flags["_cargo"]) == 1)
	director.run.flags["_cargo"] = 0
	check("two riders board", director.interact("sq_015", "board") and int(director.run.flags["_cargo"]) == 2)
	director.choose("sq_015", "order", "SQ15_LIBRARY")
	var first: MissionStage = director.current_stage()
	pose(director._stage_target(first))
	check("chosen rider unloads", director.interact("sq_015", "first") and int(director.run.flags["_cargo"]) == 1)
	director.abandon()
	GameState.reset_profile()
	var previous_weather: bool = GameState.is_raining
	pose(director.registry.get_mission("sq_008").start_anchor)
	check("rain pickup starts", director.start("sq_008") and GameState.is_raining)
	director.choose("sq_008", "order", "SQ08_PAPER")
	pose(director.current_stage().target)
	check("paper loaded", director.interact("sq_008", "first"))
	var before: float = float(director.run.flags["paper"])
	director.tick(10.0)
	check("rain degrades exposed paper", float(director.run.flags["paper"]) < before)
	director.abandon()
	check("weather restored", GameState.is_raining == previous_weather)
	GameState.reset_profile()
	pose(director.registry.get_mission("sq_005").start_anchor)
	check("detour starts", director.start("sq_005"))
	director.interact("sq_005", "lamps")
	director.choose("sq_005", "sign", "SQ05_OUTER")
	var outer: MissionStage = director.current_stage()
	pose(outer.avoid_center)
	director.tick(0.1)
	check("closed-route breach fails safely", director.run.status == "failed")
	check("retry restores two crates", director.retry() and int(director.run.flags["_cargo"]) == 2)
	director.abandon()
