extends Node
var passed: int = 0
var failed: int = 0
var director: MissionDirector
var pack: MissionPack = preload("res://data/missions/career_quests.tres")
var ambulance_requests: int = 0

func _ready() -> void:
	_run.call_deferred()

func check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func _pose(p: Vector3, heading: Vector3 = Vector3.FORWARD) -> void:
	SignalBus.player_pose_updated.emit(p, heading)
	SignalBus.speed_updated.emit(0.0)

func _ambulance() -> bool:
	ambulance_requests += 1
	return true

func _run() -> void:
	GameState.persistence_enabled = false
	GameState.reset_profile()
	SignalBus.current_road_graph = RoadGraph.from_json_file("res://data/world/road_graph.json")
	SignalBus.scripted_ambulance_provider = Callable(self, "_ambulance")
	director = MissionDirector.new()
	director.pack = pack
	add_child(director)
	director.set_physics_process(false)
	check("original stories remain in twenty-four-quest pack", director.registry.definitions.size() == 24)
	for id: String in ["sq_001", "sq_006", "sq_012", "sq_016", "sq_021", "sq_026"]:
		_play(id, "")
	for branch: Array in [["sq_001", "SQ01_OTHER"], ["sq_012", "SQ12_RED"],
		["sq_021", "SQ21_PRINT"], ["sq_026", "SQ26_ROSES_FIRST"]]:
		_play(branch[0], branch[1])
	check("pooled ambulance was requested", ambulance_requests > 0)
	director.queue_free()
	SignalBus.scripted_ambulance_provider = Callable()
	SignalBus.current_road_graph = null
	print("Six quests: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _play(id: String, alternate: String) -> void:
	GameState.reset_profile()
	var quest: MissionDef = director.registry.get_mission(id)
	_pose(quest.start_anchor)
	if not director.start(id):
		check(id + " accepts at authored anchor", false)
		return
	check(id + " accepts at authored anchor", director.run != null and director.run.quest_id == id)
	for _step: int in 20:
		if director.run == null or director.run.status != "active":
			break
		var stage: MissionStage = director.current_stage()
		if stage == null:
			break
		var before: String = stage.id
		match stage.kind:
			"dialogue":
				var selected: String = alternate if stage.choices.has(alternate) else stage.choices[0]
				check(id + "/" + before + " choice", director.choose(id, before, selected))
			"goto":
				_pose(director._stage_target(stage))
				director.tick(0.1)
			"photo":
				_pose(director._stage_target(stage), stage.facing)
				check(id + "/" + before + " photo", director.interact(id, before))
			"yield":
				_pose(director._stage_target(stage))
				SignalBus.indicator_changed.emit(-1)
				director._physics_process(0.1)
		if director.run != null and director.run.stage_id == before:
			check(id + "/" + before + " progresses", false)
			break
	check(id + " completes", director.run == null and GameState.mission_completed.has(id))
	check(id + " reward recorded once", GameState.wallet_inr > 500)
	check(id + " Career restored", not GameState.mission_active and GameState.mission_run.is_empty())
