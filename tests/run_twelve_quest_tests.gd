extends Node
var passed: int = 0
var failed: int = 0
var director: MissionDirector

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
	check("original twelve definitions remain", director.registry.definitions.size() == 24)
	for id: String in ["sq_002", "sq_004", "sq_009", "sq_019", "sq_024", "sq_027"]:
		play(id, "")
	for variation: Array in [["sq_002", "SQ02_GARDEN_FIRST"], ["sq_004", "SQ04_MARKET"],
		["sq_009", "SQ09_CALM_FIRST"], ["sq_019", "SQ19_RED"],
		["sq_024", "SQ24_FUSE"], ["sq_027", "SQ27_WIDE"]]:
		play(variation[0], variation[1])
	quality_and_parking()
	director.queue_free()
	SignalBus.current_road_graph = null
	print("Twelve quests: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func play(id: String, alternate: String) -> void:
	GameState.reset_profile()
	var quest: MissionDef = director.registry.get_mission(id)
	pose(quest.start_anchor)
	if not director.start(id):
		check(id + " start is reachable", false)
		return
	check(id + " start is reachable", true)
	for _step: int in 20:
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
			"inspect", "calm", "park":
				pose(stage.target, stage.facing if stage.facing != Vector3.ZERO else Vector3.FORWARD)
				if stage.kind == "park":
					SignalBus.gear_changed.emit(-1)
				check(id + "/" + before + " interaction", director.interact(id, before))
		if director.run != null and director.run.stage_id == before:
			check(id + "/" + before + " progresses", false)
			break
	check(id + " completes", director.run == null and GameState.mission_completed.has(id))
	var reward: int = GameState.wallet_inr
	pose(quest.start_anchor)
	check(id + " replay can start", director.start(id))
	for _replay: int in 20:
		if director.run == null or director.run.status != "active":
			break
		var stage: MissionStage = director.current_stage()
		match stage.kind:
			"dialogue":
				director.choose(id, stage.id, stage.choices[0])
			"goto":
				pose(director._stage_target(stage))
				director.tick(0.1)
			"inspect", "calm", "park":
				pose(stage.target, stage.facing if stage.facing != Vector3.ZERO else Vector3.FORWARD)
				if stage.kind == "park":
					SignalBus.gear_changed.emit(-1)
				director.interact(id, stage.id)
	check(id + " replay cannot reward twice", director.run == null and GameState.wallet_inr == reward)
	check(id + " releases Career", not GameState.mission_active and GameState.mission_run.is_empty())

func quality_and_parking() -> void:
	GameState.reset_profile()
	pose(director.registry.get_mission("sq_002").start_anchor)
	check("coffee starts", director.start("sq_002"))
	director.choose("sq_002", "order", "SQ02_LUZ_FIRST")
	SignalBus.vehicle_dynamics.emit(2.0, 2.0, 0.0)
	SignalBus.player_impact.emit({"severity": 1.0})
	var coffee: float = float(director.run.flags.get("coffee", 100.0))
	check("dynamics and impact lower coffee", coffee < 82.0 and coffee > 0.0)
	check("quality serialized", float(GameState.mission_run.get("flags", {}).get("coffee", 100.0)) == coffee)
	director.run = null
	GameState.mission_active = false
	check("saved stage resumes", director.resume_saved() and director.current_stage().id == "first")
	check("resume preserves live quality", float(director.run.flags["coffee"]) == coffee)
	for _hit: int in 6:
		SignalBus.player_impact.emit({"severity": 1.0})
	check("quality bounded", float(director.run.flags["coffee"]) == 0.0)
	director.tick(0.1)
	check("spilled coffee fails", director.run.status == "failed")
	check("free retry", director.retry() and float(director.run.flags.get("coffee", 0.0)) == 100.0)
	director.abandon()
	GameState.reset_profile()
	pose(director.registry.get_mission("sq_009").start_anchor)
	check("puppy starts", director.start("sq_009"))
	director.choose("sq_009", "brief", "SQ09_CALM_FIRST")
	SignalBus.horn_blasted.emit(Vector3.ZERO, Vector3.FORWARD, 10.0, 0)
	check("horn distresses puppy", float(director.run.flags["comfort"]) == 88.0)
	pose(director.current_stage().target)
	check("calm stop works", director.interact("sq_009", "calm"))
	check("calm stop restores bounded comfort", float(director.run.flags["comfort"]) == 100.0)
	director.abandon()
	GameState.reset_profile()
	pose(director.registry.get_mission("sq_027").start_anchor)
	check("parking starts", director.start("sq_027"))
	director.choose("sq_027", "approach", "SQ27_NARROW")
	pose(director.current_stage().target)
	director.tick(0.1)
	var parking: MissionStage = director.current_stage()
	pose(parking.target, parking.facing)
	check("parking needs reverse", not director.interact("sq_027", "park"))
	SignalBus.gear_changed.emit(-1)
	pose(parking.target, -parking.facing)
	check("parking needs correct heading", not director.interact("sq_027", "park"))
	pose(parking.target, parking.facing)
	check("reverse parking progresses", director.interact("sq_027", "park"))
	director.abandon()
