extends Node
var passed: int = 0
var failed: int = 0
var director: MissionDirector
var pack: MissionPack = preload("res://tests/fixtures/missions/foundation.tres")

func _ready() -> void:
	_run.call_deferred()

func check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func pose(x: float, speed: float = 0.0) -> void:
	SignalBus.player_pose_updated.emit(Vector3(x, 0, 0), Vector3.FORWARD)
	SignalBus.speed_updated.emit(speed)

func _run() -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	GameState.is_raining = false
	GameState.shift_minute = 600.0
	var graph: RoadGraph = RoadGraph.new()
	graph.add_node(Vector3.ZERO)
	graph.add_node(Vector3(100, 0, 0))
	graph.add_edge(0, 1, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]), 10.0, 1, 1)
	SignalBus.current_road_graph = graph
	_registry_tests()
	director = MissionDirector.new()
	director.pack = pack
	add_child(director)
	director.set_physics_process(false)
	pose(0)
	check("AC02 unknown ID refused", not director.start("missing"))
	GameState.tutorial_active = true
	check("AC02 tutorial refused", not director.start("test_foundation"))
	GameState.tutorial_active = false
	SignalBus.savari_busy_provider = func() -> bool: return true
	check("AC02 occupied fare refused", not director.start("test_foundation"))
	SignalBus.savari_busy_provider = Callable()
	check("AC02 starts once", director.start("test_foundation") and not director.start("test_foundation"))
	check("Scenario claimed", GameState.mission_active and GameState.is_raining and GameState.shift_minute == 1080.0 and not GameState.shift_running)
	director.tick(31.0)
	check("AC04 deadline failure", director.run.status == "failed")
	check("Failure restores Career", not GameState.mission_active and not GameState.is_raining and GameState.shift_minute == 600.0)
	GameState.shift_minute = 620.0
	director.abandon()
	check("Abandon failed run preserves subsequent Career time", GameState.shift_minute == 620.0)
	GameState.shift_minute = 600.0
	director.start("test_foundation")
	director.tick(31.0)
	check("Free retry", director.retry() and director.run.elapsed == 0.0)
	pose(0, 45)
	director.tick(0.1)
	check("Short speed breach only warns", director.run.status == "active")
	director.tick(director.quality_tuning.speed_grace_s)
	check("AC04 speed failure", director.run.status == "failed")
	pose(0)
	director.retry()
	GameState.condition = 85.0
	director.tick(0.1)
	check("AC04 damage failure", director.run.status == "failed")
	director.retry()
	check("Retry never repairs vehicle", GameState.condition == 85.0)
	pose(50, 10)
	director.tick(0.1)
	check("AC03 arrival requires stopped auto", director.run.stage_id == "drive")
	pose(50)
	director.tick(0.1)
	check("AC03 GoTo advances", director.run.stage_id == "talk")
	check("AC03 invalid choice ignored", not director.choose("test_foundation", "talk", "invalid"))
	check("AC03 stale callback ignored", not director.choose("test_foundation", "drive", "return"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict())) as Dictionary
	director.choose("test_foundation", "talk", "verify")
	GameState.from_dict(saved)
	check("Loaded scenario does not leak into menu", GameState.shift_minute == 600.0 and not GameState.is_raining)
	check("AC05 reload restores checkpoint", director.resume_saved() and director.run.stage_id == "talk" and director.run.flags.is_empty())
	check("Resource never mutated", pack.missions[0].stages[0].target == Vector3(50, 0, 0))
	var before_money: int = GameState.wallet_inr
	var before_xp: int = GameState.progress.xp
	director.choose("test_foundation", "talk", "return")
	director.tick(1.1)
	check("AC03 completed", director.run == null and GameState.mission_completed.has("test_foundation"))
	check("AC06 one payout", GameState.wallet_inr == before_money + 75 and GameState.progress.xp == before_xp + 10)
	check("AC08 release scenario", not GameState.mission_active and GameState.shift_minute == 600.0 and not GameState.is_raining and GameState.shift_running)
	check("Completion clears persisted active run", GameState.mission_run.is_empty())
	before_money = GameState.wallet_inr
	for i: int in 205:
		GameState.rewards.grant("test", 0, 0, "ordinary:%d" % i, "2026-11-04")
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())) as Dictionary)
	pose(0)
	_complete_replay()
	check("AC06 replay after pruning/reload does not pay", GameState.wallet_inr == before_money)
	_interrupt_tests()
	_reload_tests()
	_save_tests()
	_integration_tests()
	director.free()
	SignalBus.current_road_graph = null
	SignalBus.savari_busy_provider = Callable()
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _complete_replay() -> void:
	check("Replay can start", director.start("test_foundation"))
	pose(50)
	director.tick(0.1)
	director.choose("test_foundation", "talk", "return")
	director.tick(1.1)

func _registry_tests() -> void:
	var registry: MissionRegistry = MissionRegistry.new()
	check("AC01 resource pack loads", registry.load_pack(pack))
	var invalid: MissionPack = pack.duplicate(true) as MissionPack
	invalid.missions.append(invalid.missions[0])
	check("Duplicate mission IDs rejected atomically", not registry.load_pack(invalid) and registry.definitions.size() == 1)
	invalid = pack.duplicate(true) as MissionPack
	invalid.missions[0].stages[0].kind = "unsupported"
	check("Unsupported stage rejected", not registry.load_pack(invalid))
	invalid = pack.duplicate(true) as MissionPack
	invalid.missions[0].stages[1].id = "drive"
	check("Duplicate stage IDs rejected", not registry.load_pack(invalid))
	invalid = pack.duplicate(true) as MissionPack
	invalid.missions[0].prerequisites = ["missing"]
	check("Missing prerequisite rejected", not registry.load_pack(invalid))
	invalid.missions[0].prerequisites = ["test_foundation"]
	check("Prerequisite cycle rejected", not registry.load_pack(invalid))
	invalid = pack.duplicate(true) as MissionPack
	invalid.missions[0].stages[0].radius_m = -1
	check("Invalid threshold rejected", not registry.load_pack(invalid))
	check("Level gate", not registry.available("test_foundation", 0, {}))
	check("Production twenty-four-quest pack valid", registry.load_pack(load("res://data/missions/career_quests.tres") as MissionPack) and registry.definitions.size() == 24)

func _interrupt_tests() -> void:
	for reason: String in ["abandoned", "tow", "shift_end"]:
		pose(0)
		director.start("test_foundation")
		if reason == "tow":
			SignalBus.tow_requested.emit(Vector3.ZERO)
		elif reason == "shift_end":
			SignalBus.shift_ended.emit({})
		else:
			director.abandon(reason)
		check("AC08 cleanup on " + reason, director.run == null and not GameState.mission_active and GameState.shift_minute == 600.0)
	_wreck_rule_tests()
	pose(0)
	director.start("test_foundation")
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	(saved["missions"]["run"] as Dictionary)["content_version"] = 999
	GameState.from_dict(saved)
	check("AC09 incompatible version cancelled", not director.resume_saved() and GameState.mission_run.is_empty() and not GameState.mission_active)
	check("Completed history retained", GameState.mission_completed.has("test_foundation"))
	GameState.mission_completed["future_pack_quest"] = {"stars": 3}
	GameState.from_dict(GameState.to_dict().duplicate(true))
	check("Unknown history retained", GameState.mission_completed.has("future_pack_quest"))

## Owner rules (Nov 9) for a wreck mid-quest: a timed quest is quit and starts over; any other quest
## waits while the driver can still pay or watch an ad for a repair, and fails when they can't.
func _wreck_rule_tests() -> void:
	var definition: MissionDef = director.registry.get_mission("test_foundation")
	var deadlines: Array[float] = []
	for stage: MissionStage in definition.stages:
		deadlines.append(stage.deadline_s)
		stage.deadline_s = 0.0
	var config: AdConfig = AdMonetizationManager.config
	var placements: PackedStringArray = config.rewarded_enabled_placements
	var no_wreck_ad: PackedStringArray = PackedStringArray()
	for p: String in placements:
		if p != "ad_wreck_repair":
			no_wreck_ad.append(p)
	var wallet: int = GameState.wallet_inr
	# Not timed, money for a repair: the quest waits.
	pose(0)
	GameState.wallet_inr = 500
	director.start("test_foundation")
	SignalBus.vehicle_wrecked.emit(true)
	check("Wreck, not timed, money left: the quest carries on", director.run != null and director.run.status == "active")
	director.abandon()
	# Not timed, no money and no repair ad: it fails (and can be retried later).
	pose(0)
	GameState.wallet_inr = 0
	config.rewarded_enabled_placements = no_wreck_ad
	director.start("test_foundation")
	SignalBus.vehicle_wrecked.emit(true)
	check("Wreck, not timed, no money and no ad: the quest fails", director.run != null and director.run.status == "failed" and not GameState.mission_active)
	director.abandon()
	# Not timed, no money, the ad was offered but would not show: it fails then.
	config.rewarded_enabled_placements = placements + PackedStringArray(["ad_wreck_repair"])
	pose(0)
	director.start("test_foundation")
	GameState.condition = 0.0
	SignalBus.vehicle_wrecked.emit(true)
	var waiting: bool = director.run != null and director.run.status == "active" and AdMonetizationManager.can_offer_rewarded("ad_wreck_repair")
	config.rewarded_enabled_placements = no_wreck_ad
	SignalBus.rewarded_ad_failed.emit("ad_wreck_repair", "not_loaded")
	check("…and when the repair ad fails to show", waiting and director.run != null and director.run.status == "failed")
	director.abandon()
	GameState.repair_free()
	config.rewarded_enabled_placements = placements
	# Timed: quit and back to the start, whatever the wallet.
	definition.stages[0].deadline_s = 999.0
	GameState.wallet_inr = 500
	pose(0)
	director.start("test_foundation")
	SignalBus.vehicle_wrecked.emit(true)
	check("Wreck on a timed quest: it is quit and starts over", director.is_timed("test_foundation") and director.run == null
			and GameState.mission_run.is_empty() and not GameState.mission_active and not GameState.mission_completed.has("test_foundation_never"))
	for i: int in definition.stages.size():
		definition.stages[i].deadline_s = deadlines[i]
	GameState.wallet_inr = wallet

func _save_tests() -> void:
	var original_path: String = GameState.save_path
	GameState.save_path = "user://phase13-test-save.dat"
	GameState.persistence_enabled = true
	var legacy: Dictionary = GameState.to_dict().duplicate(true)
	legacy.erase("missions")
	legacy["version"] = 1
	legacy["wallet"] = 1234
	var legacy_key: String = "namma-auto-1|%s" % OS.get_unique_id()
	var payload: String = JSON.stringify(legacy)
	var file: FileAccess = FileAccess.open_encrypted_with_pass(GameState.save_path, FileAccess.WRITE, legacy_key)
	file.store_string(JSON.stringify({"p": payload, "h": (payload + legacy_key).sha256_text()}))
	file.close()
	check("AC07 real encrypted v1 load", GameState.load_game() and GameState.wallet_inr == 1234 and GameState.mission_run.is_empty())
	check("AC10 atomic save writes", GameState.save_game() and not FileAccess.file_exists(GameState.save_path + ".tmp"))
	GameState.wallet_inr = 0
	check("AC10 reload has entire payload", GameState.load_game() and GameState.wallet_inr == 1234)
	var orphan: FileAccess = FileAccess.open(GameState.save_path + ".tmp", FileAccess.WRITE)
	orphan.store_string("interrupted write")
	orphan.close()
	check("Interrupted temporary file leaves prior save readable", GameState.load_game() and GameState.wallet_inr == 1234)
	# Persist a full real mission, including the grant, then read the encrypted file.
	GameState.rewards = RewardsEngine.new()
	var before: int = GameState.wallet_inr
	pose(0)
	_complete_replay()
	check("AC10 completion transaction reaches disk", GameState.load_game() and GameState.mission_run.is_empty() and GameState.mission_completed.has("test_foundation") and GameState.wallet_inr == before + 75)
	pose(0)
	_complete_replay()
	check("AC10 disk reload and replay retain one payout", GameState.load_game() and GameState.wallet_inr == before + 75)
	DirAccess.remove_absolute(GameState.save_path)
	DirAccess.remove_absolute(GameState.save_path + ".tmp")
	GameState.save_path = original_path
	GameState.persistence_enabled = false

func _integration_tests() -> void:
	var nav: CustomNavigation = CustomNavigation.new()
	add_child(nav)
	pose(0)
	SignalBus.custom_navigation_requested.emit(Vector3.ZERO, Vector3(90, 0, 0))
	check("Custom route active before mission", nav._active)
	director.start("test_foundation")
	check("Custom route suspended", nav._mission_suspended and nav._active)
	SignalBus.custom_navigation_requested.emit(Vector3.ZERO, Vector3(80, 0, 0))
	check("Mission route not replaced", nav._destination == Vector3(90, 0, 0))
	director.abandon()
	check("Custom destination restored", not nav._mission_suspended and nav._active and nav._destination == Vector3(90, 0, 0))
	nav.free()
	var savari: SavariManager = SavariManager.new()
	add_child(savari)
	pose(0)
	savari.state = SavariManager.State.HAGGLING
	check("Real Savari blocks start", not director.start("test_foundation"))
	savari.state = SavariManager.State.CRUISING
	check("Real Savari permits idle start", director.start("test_foundation"))
	savari._physics_process(1.0)
	check("Mission suppresses normal hails", savari.hails.is_empty())
	director.abandon()
	savari.free()

func _reload_tests() -> void:
	pose(0)
	director.start("test_foundation")
	pose(50)
	director.tick(0.1)
	director.free()
	check("AC08 scene unload releases scenario but keeps checkpoint", not GameState.mission_active and GameState.shift_minute == 600.0 and not GameState.mission_run.is_empty())
	director = MissionDirector.new()
	director.pack = pack
	add_child(director)
	director.set_physics_process(false)
	pose(0)
	check("AC05 replacement scene resumes safe objective", director.resume_saved() and director.run.stage_id == "talk")
	director.abandon()
	director.start("test_foundation")
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	(saved["missions"]["run"] as Dictionary)["stage_id"] = "removed_stage"
	GameState.from_dict(saved)
	check("AC09 missing stage cancels safely", not director.resume_saved() and not GameState.mission_active)
	director.start("test_foundation")
	director.tick(31.0)
	GameState.from_dict(GameState.to_dict().duplicate(true))
	check("Failed run stays failed on reload", director.resume_saved() and director.run.status == "failed" and not GameState.mission_active)
	director.abandon()
	director.start("test_foundation")
	var tutorial: TutorialDirector = TutorialDirector.new()
	add_child(tutorial)
	tutorial.start()
	check("Tutorial cannot steal mission ownership", not tutorial.active)
	tutorial.free()
	director.abandon()
