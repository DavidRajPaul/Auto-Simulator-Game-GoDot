extends Node
## What the player sees: every quest playable on every branch, every stop named, words translated,
## the start card and panel usable, and the panel clear of the road and the top HUD buttons.
var passed: int = 0
var failed: int = 0
var director: MissionDirector
var discovery: QuestDiscovery
var prompt: Dictionary = {}
var action_ready: bool = false
var action_in_range: bool = false

func _ready() -> void:
	_run.call_deferred()

func check(label: String, okay: bool) -> void:
	if okay:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func pose(point: Vector3, speed: float = 0.0) -> void:
	SignalBus.player_pose_updated.emit(point, Vector3.FORWARD)
	SignalBus.speed_updated.emit(speed)

func _translated(key: String) -> bool:
	for locale: String in ["en", "ta"]:
		TranslationServer.set_locale(locale)
		if tr(key) == key or tr(key).strip_edges() == "":
			TranslationServer.set_locale("en")
			return false
	TranslationServer.set_locale("en")
	return true

func _run() -> void:
	GameState.persistence_enabled = false
	GameState.reset_profile()
	GameState.tutorial_active = false
	SignalBus.current_road_graph = RoadGraph.from_json_file("res://data/world/road_graph.json")
	director = MissionDirector.new()
	add_child(director)
	director.set_physics_process(false)
	SignalBus.mission_action_ready.connect(func(ready: bool, in_range: bool) -> void:
		action_ready = ready
		action_in_range = in_range)
	SignalBus.quest_prompt_changed.connect(func(quest: Dictionary) -> void: prompt = quest)
	_check_words()
	for id: String in director.registry.definitions:
		_play(id, false)
		_play(id, true)
	_check_load_rules()
	_check_prompt()
	_check_hud()
	await _check_markers()
	print("Quest experience: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _check_words() -> void:
	for id: String in director.registry.definitions:
		var q: MissionDef = director.registry.get_mission(id)
		var missing: PackedStringArray = PackedStringArray()
		var keys: PackedStringArray = PackedStringArray([q.title_key, q.description_key, q.job_key])
		for stage: MissionStage in q.stages:
			keys.append(stage.objective_key)
			keys.append_array(stage.choices)
			if stage.place_key != "":
				keys.append(stage.place_key)
			if stage.action_key != "":
				keys.append(stage.action_key)
			for option: String in stage.place_options:
				keys.append(str(stage.place_options[option]))
			var located: bool = stage.kind in MissionDirector.LOCATED_KINDS
			if located and stage.place_key == "":
				missing.append("place:" + stage.id)
			if located and stage.place_pos == Vector3.ZERO:
				missing.append("sign:" + stage.id)
			if stage.hidden_route:
				missing.append("hidden route:" + stage.id)
			if stage.facing != Vector3.ZERO:
				missing.append("unseen facing rule:" + stage.id)
			if tr(stage.objective_key) in stage.choices or _is_choice_text(q, stage):
				missing.append("objective is a button label:" + stage.id)
		for key: String in keys:
			if not _translated(key):
				missing.append(key)
		check("%s: every stop named and every word translated %s" % [id, str(missing)], missing.is_empty())

func _is_choice_text(q: MissionDef, stage: MissionStage) -> bool:
	for other: MissionStage in q.stages:
		for choice: String in other.choices:
			if tr(choice) == tr(stage.objective_key):
				return true
	return false

## Walks the quest as a player would, taking the first or last answer at each question.
func _play(id: String, last_answers: bool) -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	var q: MissionDef = director.registry.get_mission(id)
	var at: Vector3 = q.start_anchor
	pose(at)
	if not director.start(id):
		check(id + " starts", false)
		return
	var steps: int = 0
	var problems: PackedStringArray = PackedStringArray()
	while director.run != null and director.run.status == "active" and steps < 40:
		steps += 1
		var stage: MissionStage = director.current_stage()
		var before: String = stage.id
		if stage.kind == "dialogue":
			director.choose(id, stage.id, stage.choices[stage.choices.size() - 1 if last_answers else 0])
			continue
		var target: Vector3 = director._stage_target(stage)
		if stage.avoid_radius_m > 0.0:
			var route: Dictionary = SignalBus.current_road_graph.find_route(at, target)
			for point: Vector3 in GpsRoute.build(SignalBus.current_road_graph, route).path:
				if point.distance_to(stage.avoid_center) < stage.avoid_radius_m:
					problems.append("GPS route enters closed road at " + stage.id)
					break
		at = target
		if stage.kind in ["photo", "inspect", "calm", "park", "cargo"]:
			pose(target + Vector3(60, 0, 0))
			director.tick(0.0)
			if director._action_ready:
				problems.append("button offered far away at " + stage.id)
			if director.interact(id, stage.id):
				problems.append("far tap worked at " + stage.id)
		pose(target)
		if stage.kind == "park":
			SignalBus.gear_changed.emit(-1)
		if stage.kind == "yield":
			SignalBus.indicator_changed.emit(1)
		director.tick(0.05)
		if stage.kind in ["photo", "inspect", "calm", "park", "cargo"] and director.run != null and director.run.stage_id == before:
			if not director._action_ready:
				problems.append("no button at " + stage.id)
			director.interact(id, stage.id)
		if director.run != null and director.run.stage_id == before and director.run.status == "active":
			problems.append("stuck at " + stage.id)
			break
	check("%s (%s answers) plays to the end %s" % [id, "last" if last_answers else "first", str(problems)], GameState.mission_completed.has(id) and problems.is_empty())
	if director.run != null:
		director.abandon()

## Nothing is at risk until it is in the auto; a knock before pick-up costs nothing.
func _check_load_rules() -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	var q: MissionDef = director.registry.get_mission("sq_003")
	pose(q.start_anchor)
	director.start("sq_003")
	director.choose("sq_003", "brief", "SQ03_READY")
	check("Drum takes no harm before it is loaded", director.current_stage().id == "case" and director.current_stage().quality_key == "")
	director.abandon()

func _check_prompt() -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	discovery = QuestDiscovery.new()
	add_child(discovery)
	discovery.set_physics_process(false)
	var anchor: Vector3 = discovery.registry.get_mission("sq_003").start_anchor
	pose(anchor, 30.0)
	discovery._update_prompt()
	check("No card while driving past", prompt.is_empty())
	pose(anchor + Vector3(3, 0, 0))
	discovery._update_prompt()
	check("Card appears when stopped at the marker", str(prompt.get("id", "")) == "sq_003")
	check("Card has the job and reward", str(prompt.get("job", "")).length() > 40 and int(prompt.get("reward", 0)) > 0)
	SignalBus.quest_prompt_dismissed.emit()
	discovery._update_prompt()
	check("Not now keeps the card away while parked here", prompt.is_empty())
	pose(anchor + Vector3(400, 0, 0), 30.0)
	discovery._update_prompt()
	pose(anchor)
	discovery._update_prompt()
	check("Card returns on a later visit", str(prompt.get("id", "")) == "sq_003")
	check("Start from the card begins the quest", bool(SignalBus.quest_action_provider.call("start", "sq_003")) or director.run != null)

func _check_hud() -> void:
	var hud: QuestHUD = QuestHUD.new()
	add_child(hud)
	for vp: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720)]:
		get_window().content_scale_size = vp
		get_viewport().get_visible_rect()
		hud._layout()
		var stage: MissionStage = null
		director.abandon()
		GameState.reset_profile()
		GameState.tutorial_active = false
		var q: MissionDef = director.registry.get_mission("sq_001")
		pose(q.start_anchor)
		director.start("sq_001")
		pose(director._stage_target(director.current_stage()))
		director.tick(0.05)
		stage = director.current_stage()
		check("Question stage shows its answers", stage.kind == "dialogue" and hud._buttons[0].visible and hud._buttons[1].visible)
		var panel: Rect2 = Rect2(hud._card.position, Vector2(hud._card.custom_minimum_size.x, 300.0))
		check("Panel stays on the left kerb at %s" % str(vp), panel.position.x + panel.size.x <= 0.27 * maxf(float(vp.x), 1280.0))
		check("Panel starts below the top row", panel.position.y >= 100.0)
	director.abandon()
	hud.queue_free()

func _check_markers() -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	var markers: QuestMarkers = QuestMarkers.new()
	add_child(markers)
	await get_tree().process_frame
	var anchor: Vector3 = discovery.registry.get_mission("sq_003").start_anchor
	pose(anchor + Vector3(20, 0, 0), 20.0)
	markers._refresh()
	check("Gold marker near a quest start", markers._mm.visible_instance_count >= 1)
	check("Title sign near a quest start", markers._sign.visible)
	pose(Vector3(-6000, 0, -6000), 20.0)
	markers._refresh()
	check("No marker far from every quest", markers._mm.visible_instance_count == 0 and not markers._sign.visible)
	pose(anchor)
	director.start("sq_003")
	director.choose("sq_003", "brief", "SQ03_READY")
	markers._refresh()
	check("A job shows only its own stop, named", markers._mm.visible_instance_count == 1 and markers._sign.text == tr("SQ03_P_SHOP"))
	check("Someone waits at the stop", markers._person == null or markers._person.visible)
	director.abandon()
	markers._refresh()
	check("Job stop clears after leaving", not markers._person.visible)
	check("Budget: one multimesh for all markers", QuestMarkers.MAX_MARKERS <= 4)
