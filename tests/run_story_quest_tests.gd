extends Node
## Story quests (MissionDef.story, QuestStory): "The Little Red Kite" played end to end with the
## real auto, camera rig, director and story player. Checks that cutscenes lock the controls and
## give them back, that dialogue never overlaps, that searching means finding the thing on screen
## (taps that miss, come from too far, too fast or hit a look-alike don't count), the branches,
## skip and abandon, and that every line has its voice and subtitles in both languages.
## "Paati Knows the Way" (sq_004) is played the same way with its rider (QuestRider): she walks up
## and boards in the intro, rides in the back, gets out in the scenes and climbs back in.

const QUEST: String = "sq_007"
const PAATI: String = "sq_004"
const WEDDING: String = "sq_001"
const MARGAZHI: String = "sq_003"
const COFFEE: String = "sq_002"
const AMBULANCE: String = "sq_016"
const MONSOON: String = "sq_017"
const MAX_SCENE_S: float = 80.0

var passed: int = 0
var failed: int = 0
var root: Node3D
var auto: AutoRickshawController
var rig: CameraRig
var director: MissionDirector
var flood: QuestFlood
var story: QuestStory
var rider: QuestRider
var test_cam: Camera3D
var line_times: Array[Dictionary] = [] # {line, t}
var clock: float = 0.0
var search: Vector2 = Vector2(-1.0, -1.0) # last (radius, -) published
var modal_open: bool = false
var last_reward: Vector2i = Vector2i(-1, -1) # (inr, xp) of the last mission reward
## Nov 25 device report: in cutscenes the auto hid the person talking, and the cast played the
## phone-call clip. While true, every cutscene frame is checked for both.
var watch_cast: bool = false
var hidden_shots: Dictionary = {} # role -> frames the auto stood between the lens and their head
var phone_frames: Dictionary = {} # role -> frames spent in the phone-call clip

func _ready() -> void:
	_run.call_deferred()

func check(label: String, okay: bool) -> void:
	if okay:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func _process(delta: float) -> void:
	clock += delta
	if watch_cast and story != null and story.cinematic:
		for role: String in story.actors:
			var actor: QuestActor = story.actors[role] as QuestActor
			var player: AnimationPlayer = actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if actor.visible and player != null and player.current_animation == QuestActor.PHONE_CLIP:
				phone_frames[role] = int(phone_frames.get(role, 0)) + 1
		var look: Variant = story._look_spec
		if not story.cockpit_shot and look is String and str(look).begins_with("role:") and story.actors.has(str(look).substr(5)):
			var who: QuestActor = story.actors[str(look).substr(5)] as QuestActor
			if who.visible and story.auto_hides(story._camera.global_position, who.head_point()):
				hidden_shots[str(look)] = int(hidden_shots.get(str(look), 0)) + 1
				if int(hidden_shots[str(look)]) == 1:
					print("hidden shot: beat %d look %s eye %s head %s auto %s" % [story._beat_i, look, story._camera.global_position, who.head_point(), auto.global_position])

func _run() -> void:
	GameState.persistence_enabled = false
	GameState.reset_profile()
	GameState.tutorial_active = false
	TranslationServer.set_locale("en")
	SignalBus.current_road_graph = RoadGraph.from_json_file("res://data/world/road_graph.json")
	SignalBus.quest_search_area_changed.connect(func(_c: Vector3, r: float) -> void: search = Vector2(r, 0.0))
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void: modal_open = open)
	SignalBus.reward_granted.connect(func(source: String, inr: int, xp: int) -> void:
		if source == "mission":
			last_reward = Vector2i(inr, xp))
	_build_scene()
	_registry_rules()
	_content_checks(QUEST)
	_content_checks(PAATI)
	_content_checks(WEDDING)
	_content_checks(MARGAZHI)
	_content_checks(COFFEE)
	_content_checks(AMBULANCE)
	_content_checks(MONSOON)
	await _full_playthrough()
	await _skip_and_home_branch()
	await _abandon_mid_scene()
	await _paati_playthrough()
	await _paati_skips()
	await _margazhi_playthrough()
	await _coffee_playthrough("SQ02_LUZ_FIRST", 0)
	await _coffee_playthrough("SQ02_GARDEN_FIRST", 1)
	await _ambulance_playthrough()
	await _monsoon_playthrough("SQ17_SHELTER")
	await _monsoon_playthrough("SQ17_DESK")
	_language_check()
	root.queue_free()
	SignalBus.current_road_graph = null
	print("Story quests: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

# --- Data ----------------------------------------------------------------------------

func _registry_rules() -> void:
	# The director's own pack: a direct load() here returns an untyped copy (script load order).
	var pack: MissionPack = director.pack
	var registry: MissionRegistry = MissionRegistry.new()
	check("Pack with the story quest loads", registry.load_pack(pack))
	var def: MissionDef = registry.get_mission(QUEST)
	check("Red Kite has a story", def != null and def.story != null)
	# Quest files are external resources, so a deep duplicate shares them: break, check, restore.
	var stages: Array[MissionStage] = def.stages
	var old_scene: String = stages[0].cutscene_id
	stages[0].cutscene_id = "nope"
	check("Cutscene without a scene rejected", not MissionRegistry.new().load_pack(pack))
	stages[0].cutscene_id = old_scene
	var old_spot: Vector3 = stages[3].spot_pos
	stages[3].spot_pos = Vector3.ZERO
	check("Search without a thing to find rejected", not MissionRegistry.new().load_pack(pack))
	stages[3].spot_pos = old_spot
	var old_next: String = stages[10].next_id
	stages[10].next_id = "intro"
	check("Backward jump rejected", not MissionRegistry.new().load_pack(pack))
	stages[10].next_id = old_next
	var old_story: QuestStoryData = def.story
	def.story = null
	check("Story stages need a story", not MissionRegistry.new().load_pack(pack))
	def.story = old_story
	check("Restored pack loads again", MissionRegistry.new().load_pack(pack))

func _mission(pack: MissionPack) -> MissionDef:
	for m: MissionDef in pack.missions:
		if m.id == QUEST:
			return m
	return null

func _content_checks(quest: String) -> void:
	var def: MissionDef = director.registry.get_mission(quest)
	var s: QuestStoryData = def.story
	var missing: PackedStringArray = PackedStringArray()
	for line: String in s.all_lines():
		for lang: String in ["en", "ta"]:
			if not ResourceLoader.exists("%s/%s_%s.ogg" % [s.voice_dir, line, lang]):
				missing.append(line + "_" + lang)
		if s.speaker_key(line) == "":
			missing.append("speaker:" + line)
	# A new story's voices come from the Generate quest voices workflow after the push that adds its
	# script; until its folder exists, the lines still need speakers and subtitles (checked below).
	var voiced: bool = DirAccess.dir_exists_absolute(s.voice_dir)
	if not voiced:
		var speakers_only: PackedStringArray = PackedStringArray()
		for m: String in missing:
			if m.begins_with("speaker:"):
				speakers_only.append(m)
		missing = speakers_only
	check(quest + ": every line is voiced in English and Tamil %s" % str(missing), missing.is_empty() and s.all_lines().size() >= 35)
	var untranslated: PackedStringArray = PackedStringArray()
	for locale: String in ["en", "ta"]:
		TranslationServer.set_locale(locale)
		for line: String in s.all_lines():
			for key: String in ["VO_" + line.to_upper(), s.speaker_key(line)]:
				if tr(key) == key or tr(key).strip_edges() == "":
					untranslated.append(locale + ":" + key)
	TranslationServer.set_locale("en")
	check(quest + ": every line has subtitles in both languages %s" % str(untranslated), untranslated.is_empty())
	var bad: PackedStringArray = PackedStringArray()
	for id: String in s.cutscenes:
		for beat: Dictionary in s.cutscenes[id]:
			for role: String in (beat.get("act", {}) as Dictionary):
				if not s.cast.has(role):
					bad.append(id + ":" + role)
			for key: String in ["look"]:
				var look: Variant = (beat.get("cam", {}) as Dictionary).get(key, null)
				if not story.cockpit_shot and look is String and str(look).begins_with("role:") and not s.cast.has(str(look).substr(5)):
					bad.append(id + ":" + str(look))
		var found: bool = false
		for stage: MissionStage in def.stages:
			found = found or stage.cutscene_id == id
		if not found:
			bad.append("unused scene " + id)
	for role: String in s.cast:
		if not ResourceLoader.exists(str((s.cast[role] as Dictionary).get("model", ""))):
			bad.append("model " + role)
	check(quest + ": every cutscene uses known people and every scene is played %s" % str(bad), bad.is_empty())

# --- Scene -----------------------------------------------------------------------------

func _build_scene() -> void:
	root = Node3D.new()
	root.name = "StoryTestRoot"
	add_child(root)
	var ground: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	root.add_child(ground)
	auto = (load("res://scenes/vehicles/auto_rickshaw.tscn") as PackedScene).instantiate() as AutoRickshawController
	auto.name = "AutoRickshaw"
	root.add_child(auto)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.target_path = NodePath("../AutoRickshaw")
	root.add_child(rig)
	director = MissionDirector.new()
	director.name = "MissionDirector"
	root.add_child(director)
	rider = QuestRider.new()
	rider.name = "QuestRider"
	root.add_child(rider)
	story = QuestStory.new()
	story.name = "QuestStory"
	root.add_child(story)
	flood = QuestFlood.new()
	flood.name = "QuestFlood"
	root.add_child(flood)
	test_cam = Camera3D.new()
	test_cam.far = 400.0
	# Projected the same frame it moves: no interpolation lag.
	test_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(test_cam)

## Puts the auto (and the pose the director reads) at a road point, facing along the road.
func place_auto(at: Vector3, kmh: float = 0.0) -> void:
	var graph: RoadGraph = SignalBus.current_road_graph
	var heading: Vector3 = Vector3.FORWARD
	var cp: Dictionary = graph.closest_point(at)
	if int(cp["edge"]) >= 0:
		var pd: Array[Vector3] = graph.sample(int(cp["edge"]), float(cp["s"]), 1)
		heading = pd[1]
	heading.y = 0.0
	auto.global_transform = Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), Vector3(at.x, 0.9, at.z))
	auto.linear_velocity = Vector3.ZERO
	auto.reset_physics_interpolation()
	SignalBus.player_pose_updated.emit(Vector3(at.x, 0.0, at.z), heading.normalized())
	SignalBus.speed_updated.emit(kmh)

func stage() -> String:
	return director.run.stage_id if director.run != null else ""

## Lets the game run until the quest reaches `id` (or `seconds` of game time pass).
func run_until(id: String, seconds: float) -> bool:
	var start: float = clock
	while stage() != id and clock - start < seconds:
		_note_lines()
		await get_tree().process_frame
	_note_lines()
	return stage() == id

func _note_lines() -> void:
	while line_times.size() < story.lines_said.size():
		line_times.append({"line": story.lines_said[line_times.size()], "t": clock})

## Aims the test camera from the auto's driving height at a point and taps where it shows.
func tap_at(point: Vector3) -> String:
	test_cam.global_position = auto.global_position + Vector3(0.0, 1.0, 0.0)
	test_cam.look_at(point, Vector3.UP)
	test_cam.make_current()
	var screen: Vector2 = test_cam.unproject_position(point)
	var result: String = story.try_tap(screen)
	return result

func _said(line: String) -> bool:
	return story.lines_said.has(line)

## Lines in a scene start only after the previous one has finished (no talking over each other).
func _no_overlap(lines: PackedStringArray) -> bool:
	var last_end: float = -INF
	for entry: Dictionary in line_times:
		if not lines.has(str(entry["line"])):
			continue
		if float(entry["t"]) + 0.05 < last_end:
			print("  overlap at ", entry["line"])
			return false
		last_end = float(entry["t"]) + story.line_seconds(str(entry["line"]))
	return true

# --- The whole quest ---------------------------------------------------------------

func _full_playthrough() -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	var def: MissionDef = director.registry.get_mission(QUEST)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	check("Red Kite starts at its marker", director.start(QUEST))
	check("Start plays the kite cutscene at once", story.cinematic and stage() == "intro")
	check("Controls are locked: auto frozen and the HUD hidden", auto.freeze and modal_open)
	await get_tree().process_frame
	check("The story camera is in charge", story._camera.current)
	var model: AutoRickshawModel = auto.get_node("Model") as AutoRickshawModel
	check("Inside-the-auto view hides the driver's own body", model.driver == null or not model.driver.visible)
	await get_tree().create_timer(1.0).timeout
	check("The kite swoops past the windscreen", story.props.has("swoop") and (story.props["swoop"] as Node3D).visible)
	check("Intro ends on the tea-stall search", await run_until("ask_tea", MAX_SCENE_S))
	check("Controls come back after the cutscene", not story.cinematic and not auto.freeze and rig._camera.current and not modal_open)
	check("The swooping kite goes with its scene", not story.props.has("swoop"))
	check("Driver visible again", model.driver == null or model.driver.visible)
	check("Lakshmi ran up, pleaded and got in", _said("sq07_d01") and _said("sq07_l01") and _said("sq07_l02") and _said("sq07_l03") and _said("sq07_d02") and not story.actors.has("lakshmi"))
	check("Intro dialogue is in order and never overlaps", _no_overlap(PackedStringArray(["sq07_d01", "sq07_l01", "sq07_l02", "sq07_l03", "sq07_d02"])))
	check("Lakshmi says to ask the tea stall man", _said("sq07_l07"))

	# The flower seller on the way: a wrong lead, said once when you stop by her.
	check("Flower seller and tea stall man stand in the street", story.actors.has("flower_akka") and story.actors.has("tea_anna"))
	var akka: Vector3 = (story.actors["flower_akka"] as QuestActor).global_position
	place_auto(akka + Vector3(-5.0, 0.0, 0.0))
	await get_tree().create_timer(0.3).timeout
	check("Stopping by the flower seller gets her (wrong) answer", _said("sq07_f01"))
	check("Ask stage has no button: stopping is the action", stage() == "ask_tea")

	var tea: MissionStage = director.current_stage()
	place_auto(tea.target)
	check("Stopping beside the tea stall man starts the talk", await run_until("tea", 2.0))
	check("Tea stall man's scene plays", story.cinematic)
	check("He points the way to the church", await run_until("spot_kite", MAX_SCENE_S) and _said("sq07_t01") and _said("sq07_l04"))

	# Searching for the kite.
	var kite_stage: MissionStage = director.current_stage()
	check("The search circle shows on the map", is_equal_approx(search.x, kite_stage.radius_m))
	check("The kite hangs on the wire", story.props.has("kite") and story.props.has("blue_kite"))
	var kite: Vector3 = (story.props["kite"] as Node3D).global_position
	var near_kite: Vector3 = kite_stage.spot_pos + Vector3(0.0, 0.0, -12.0)
	near_kite.y = 0.0
	place_auto(kite_stage.target + Vector3(0.0, 0.0, 0.0))
	director.tick(0.0)
	check("Inside the circle the GPS goes quiet", director._in_search)
	place_auto(near_kite + Vector3(120.0, 0.0, 0.0))
	await get_tree().process_frame
	check("A tap from far away does not count", tap_at(kite) == "far" and stage() == "spot_kite")
	place_auto(near_kite, 30.0) # no frame in between: the auto reports its real speed every tick
	check("A tap while driving fast does not count", tap_at(kite) == "fast" and stage() == "spot_kite")
	place_auto(near_kite)
	await get_tree().process_frame
	check("Tapping the empty sky does nothing", story.try_tap(Vector2(40.0, 200.0)) == "" and stage() == "spot_kite")
	var blue: Vector3 = (story.props["blue_kite"] as Node3D).global_position
	check("The blue kite is the wrong one", tap_at(blue) == "decoy" and stage() == "spot_kite")
	await get_tree().create_timer(0.2).timeout
	check("Lakshmi says that's not it", _said("sq07_l10"))
	check("Tapping the red kite up close finds it", tap_at(kite) == "found")
	check("The children's scene plays", stage() == "kids" and story.cinematic)
	check("Children run up and send you to the beach", await run_until("spot_boy", MAX_SCENE_S) and _said("sq07_k01") and _said("sq07_k02") and _said("sq07_l11"))

	# The beach crowd.
	var boy_stage: MissionStage = director.current_stage()
	check("Six children on the sand, Karthik among them", story.actors.has("karthik") and story.actors.has("boy_blue_kite") and story.actors.has("girl_churidar"))
	check("Some of them fly kites", (story.actors["boy_blue_kite"] as QuestActor).kite != null and (story.actors["karthik"] as QuestActor).kite == null)
	place_auto(boy_stage.target)
	await get_tree().create_timer(0.2).timeout
	check("Lakshmi describes him", _said("sq07_l12"))
	var decoy_result: String = tap_at((story.actors["boy_blue_kite"] as QuestActor).chest_point())
	check("A boy in a blue shirt with a kite is not him (%s)" % decoy_result, decoy_result == "decoy")
	check("Tapping Karthik finds him", tap_at((story.actors["karthik"] as QuestActor).chest_point()) == "found")
	check("Reunion ends on the choice, held in the cutscene", await run_until("choice", MAX_SCENE_S) and story.cinematic and story.holding)
	check("Choices show in the letterbox", story._choices[0].visible and story._choices[1].visible and not story._choices[2].visible)
	check("Reunion lines played in order", _no_overlap(PackedStringArray(["sq07_l15", "sq07_l16", "sq07_b01", "sq07_l17", "sq07_b02"])) and _said("sq07_b02"))
	check("Mother and son stand by the auto", story.actors.has("lakshmi") and story.actors.has("karthik"))
	story._choose(1) # "I know where your kite is!"
	check("The promise plays and then you drive back to the kite", await run_until("rescue", MAX_SCENE_S) and _said("sq07_d04") and _said("sq07_b03"))
	check("Controls are back for the drive", not story.cinematic and not auto.freeze)

	# Park under the kite.
	var rescue: MissionStage = director.current_stage()
	var dir: Vector3 = Vector3(1.0, 0.0, 0.0)
	place_auto(rescue.target + dir * 6.0)
	await get_tree().create_timer(0.3).timeout
	check("Not close enough: Karthik can't reach", _said("sq07_b04") and stage() == "rescue")
	place_auto(rescue.target)
	check("Parked under the kite: Karthik climbs up", await run_until("climb", 2.0))
	await get_tree().create_timer(0.4).timeout
	var karthik: QuestActor = story.actors.get("karthik") as QuestActor
	check("Karthik stands on the roof %s" % str(karthik.global_position.y if karthik != null else -1.0), karthik != null and karthik.on_roof and karthik.global_position.y > auto.global_position.y + 0.5 and karthik.global_position.y < auto.global_position.y + 1.7)
	await get_tree().create_timer(3.9).timeout
	karthik = story.actors.get("karthik") as QuestActor
	check("He takes the kite off the wire", _said("sq07_b05") and karthik != null and story.props.has("kite") and karthik.kite == story.props["kite"] and karthik.kite_mode == "held")
	check("The ride home skips the 'kite is gone' line", await run_until("ride_home", MAX_SCENE_S) and not _said("sq07_d03"))

	# The ride home.
	await get_tree().create_timer(0.2).timeout
	check("Karthik chats on the way", _said("sq07_b06"))
	SignalBus.player_impact.emit({"severity": 0.6})
	await get_tree().create_timer(0.2).timeout
	check("A knock and Lakshmi shouts about the child", _said("sq07_l21"))
	var home: MissionStage = director.current_stage()
	place_auto(home.target)
	check("At the house they get out and talk", await run_until("payoff", MAX_SCENE_S) and story.holding and _said("sq07_l22") and _said("sq07_l23"))
	check("Karthik holds his kite at home", story.actors.has("karthik") and (story.actors["karthik"] as QuestActor).kite_mode == "held")
	story._choose(1) # refuse the fare
	var done: bool = false
	var t0: float = clock
	while clock - t0 < MAX_SCENE_S and director.run != null:
		_note_lines()
		await get_tree().process_frame
	done = director.run == null and GameState.mission_completed.has(QUEST)
	check("Thanks plays and the quest completes", done and _said("sq07_l24") and _said("sq07_b08"))
	check("Refusing the fare earns respect, not money %s" % str(last_reward), last_reward == Vector2i(0, 65))
	check("Everything is put back", not story.cinematic and not auto.freeze and story.actors.is_empty() and story.props.is_empty() and rig._camera.current and not modal_open)
	check("Search circle cleared", is_zero_approx(search.x))

func _skip_and_home_branch() -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	story.lines_said.clear()
	line_times.clear()
	var def: MissionDef = director.registry.get_mission(QUEST)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	check("Second run starts", director.start(QUEST))
	await get_tree().create_timer(0.5).timeout
	story.skip()
	check("Skip ends the intro at once, Lakshmi aboard", stage() == "ask_tea" and not story.cinematic and not auto.freeze and not story.actors.has("lakshmi"))
	# Jump to the reunion through the stages without scenes.
	place_auto(director.current_stage().target)
	await run_until("tea", 2.0)
	story.skip()
	var kite_stage: MissionStage = director.current_stage()
	place_auto(Vector3(kite_stage.spot_pos.x, 0.0, kite_stage.spot_pos.z))
	director.spot(QUEST, "spot_kite")
	story.skip()
	var boy: MissionStage = director.current_stage()
	place_auto(Vector3(boy.spot_pos.x, 0.0, boy.spot_pos.z) + Vector3(-30.0, 0.0, 0.0))
	director.spot(QUEST, "spot_boy")
	story.skip()
	check("Skipping a held scene still asks the question", stage() == "choice" and story.holding and story._choices[0].visible)
	story._choose(0) # "The kite's gone. Let's go home."
	check("The other branch says the kite is gone and heads home", await run_until("ride_home", MAX_SCENE_S) and _said("sq07_d03") and not _said("sq07_d04"))
	place_auto(director.current_stage().target)
	await run_until("payoff", MAX_SCENE_S)
	check("No kite in his hand on this branch", story.actors.has("karthik") and (story.actors["karthik"] as QuestActor).kite == null)
	director.choose(QUEST, "payoff", "SQ07_TAKE_FARE")
	var t0: float = clock
	while clock - t0 < MAX_SCENE_S and director.run != null:
		await get_tree().process_frame
	check("Taking the fare pays %s" % str(last_reward), last_reward == Vector2i(220, 25) and GameState.mission_completed.has(QUEST))

func _abandon_mid_scene() -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	var def: MissionDef = director.registry.get_mission(QUEST)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	director.start(QUEST)
	await get_tree().create_timer(1.5).timeout
	director.abandon("player_left")
	await get_tree().process_frame
	check("Leaving mid-scene gives the auto back", not story.cinematic and not auto.freeze and rig._camera.current and story.actors.is_empty() and not modal_open)
	# A scene that never reports back can't lock the quest forever.
	place_auto(def.start_anchor)
	director.start(QUEST)
	story.end_story()
	director.tick(def.stages[0].duration_s + MissionDirector.CUTSCENE_SAFETY_S + 1.0)
	check("A lost cutscene times out", stage() == "ask_tea")
	director.abandon()

# --- Paati Knows the Way: a story with a rider ---------------------------------------

func _wait_rider(state: QuestRider.State, seconds: float) -> bool:
	var start: float = clock
	while rider.state != state and clock - start < seconds:
		_note_lines()
		await get_tree().process_frame
	return rider.state == state

func _paati_playthrough() -> void:
	GameState.reset_profile()
	GameState.tutorial_active = false
	story.lines_said.clear()
	line_times.clear()
	var def: MissionDef = director.registry.get_mission(PAATI)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	rider._scan = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check("Paati waits on her thinnai by the marker", rider.state == QuestRider.State.WAITING and rider.quest_id == PAATI)
	check("Paati's quest starts", director.start(PAATI))
	check("…with a cutscene, controls locked", story.cinematic and stage() == "intro" and auto.freeze and modal_open)
	check("She gets up and walks to the auto (not popping in)", rider.state in [QuestRider.State.BOARDING, QuestRider.State.LEAVING] and rider.body.get_parent() == rider)
	await get_tree().create_timer(0.5).timeout
	var head: Vector3 = rider.head_point()
	check("The camera can look at her face %s" % str(head), head.is_finite() and head.y > rider.story_point().y + 0.8)
	check("Intro ends with Paati aboard, on to the flower stall", await run_until("ask_flower", MAX_SCENE_S) and rider.is_aboard() and not director.rider_missing())
	check("Controls come back after her scene", not story.cinematic and not auto.freeze and rig._camera.current and not modal_open)
	check("Intro dialogue in order, never overlapping", _said("sq04_d03") and _no_overlap(PackedStringArray(["sq04_p01", "sq04_d01", "sq04_p02", "sq04_d02", "sq04_p03", "sq04_p04", "sq04_d03"])))
	check("Paati chats from the back seat", _said("sq04_p05"))

	# The watchman on the way: a joke, not a lead.
	check("Valli and the watchman stand in the street", story.actors.has("valli") and story.actors.has("watchman"))
	place_auto((story.actors["watchman"] as QuestActor).global_position + Vector3(0.0, 0.0, 3.5))
	# The watchman's joke, then Paati's reply: wait for both voice files to play out.
	var t_w: float = clock
	while not _said("sq04_p08") and clock - t_w < 15.0:
		_note_lines()
		await get_tree().process_frame
	check("Stopping by the watchman: a hundred new flats, and Paati's reply", _said("sq04_w01") and _said("sq04_p08") and stage() == "ask_flower")
	SignalBus.player_impact.emit({"severity": 0.6})
	await get_tree().create_timer(0.2).timeout
	check("A knock: Paati shouts", _said("sq04_p14"))

	place_auto(director.current_stage().target)
	check("Stopping beside Valli starts her scene", await run_until("flowers", 2.0) and story.cinematic)
	check("Valli remembers her; the scene ends on the choice", await run_until("guess", MAX_SCENE_S) and story.holding and story._choices[1].visible)
	check("Valli walked over to the auto", (story.actors["valli"] as QuestActor).global_position.distance_to(auto.global_position) < 3.5)
	check("Flower stall lines in order", _no_overlap(PackedStringArray(["sq04_v01", "sq04_p09", "sq04_v02", "sq04_p10"])) and _said("sq04_p10"))
	story._choose(1) # "The market"
	check("Market: Paati says no, it was the tank, and you drive on", await run_until("ask_sundal", MAX_SCENE_S) and _said("sq04_d04") and _said("sq04_p11") and _said("sq04_v03") and not _said("sq04_d05"))
	check("Paati remembers the sundal seller", _said("sq04_p13") and story.actors.has("sundal"))

	hidden_shots.clear()
	phone_frames.clear()
	watch_cast = true
	place_auto(director.current_stage().target)
	check("Stopping beside the sundal seller starts his scene", await run_until("sundal", 2.0))
	var sundal_head: Vector3 = (story.actors["sundal"] as QuestActor).head_point()
	var behind: Vector3 = auto.global_position + (auto.global_position - sundal_head).normalized() * 3.0
	check("A lens with the auto between it and him counts as hidden", story.auto_hides(Vector3(behind.x, auto.global_position.y + 0.6, behind.z), sundal_head))
	check("He saw Meena: on to the search", await run_until("spot_meena", MAX_SCENE_S) and _said("sq04_s01") and _said("sq04_s03") and _said("sq04_p16"))

	# Looking for Meena.
	var search_stage: MissionStage = director.current_stage()
	check("Meena and four look-alikes stand by the temple", story.actors.has("meena") and story.actors.has("green_churidar") and story.actors.has("office_coat"))
	place_auto(search_stage.target)
	await get_tree().create_timer(0.2).timeout
	check("Paati describes her", _said("sq04_p28"))
	var wrong: String = tap_at((story.actors["green_churidar"] as QuestActor).chest_point())
	check("The street's green churidar is not her (%s)" % wrong, wrong == "decoy" and stage() == "spot_meena")
	await get_tree().create_timer(0.2).timeout
	check("Paati: that's not Meena", _said("sq04_p20"))
	check("Tapping Meena finds her", tap_at((story.actors["meena"] as QuestActor).chest_point()) == "found" and stage() == "reunion")
	var out_seen: bool = false
	var t_out: float = clock
	while stage() == "reunion" and clock - t_out < MAX_SCENE_S:
		_note_lines()
		out_seen = out_seen or (rider.state == QuestRider.State.OUT and rider.body.get_parent() == rider)
		await get_tree().process_frame
	check("Paati gets out to meet Meena", out_seen)
	check("…and climbs back in for the ride home", stage() == "ride_home" and rider.is_aboard() and not director.rider_missing() and not story.cinematic)
	check("Reunion lines in order", _no_overlap(PackedStringArray(["sq04_m01", "sq04_m02", "sq04_p21", "sq04_m03", "sq04_p22", "sq04_m04", "sq04_d06"])) and _said("sq04_d06"))
	check("Meena rides along (not left standing in the street)", not story.actors.has("meena") or not (story.actors["meena"] as QuestActor).visible)
	await get_tree().create_timer(0.3).timeout
	check("Meena scolds, Paati teases", _said("sq04_m05"))
	watch_cast = false
	check("No cutscene shot of Sundal thatha or Meena has the auto in front of them %s" % str(hidden_shots), hidden_shots.is_empty())
	check("Nobody in the scenes plays the phone-call clip %s" % str(phone_frames), phone_frames.is_empty())

	place_auto(director.current_stage().target)
	check("At the green gate they get out; Meena asks the fare", await run_until("payoff", MAX_SCENE_S) and story.holding and _said("sq04_m06") and _said("sq04_p25") and _said("sq04_m07"))
	check("Paati stands on the pavement, not in the seat", rider.state == QuestRider.State.OUT and rider.body.get_parent() == rider)
	story._choose(1) # no fare
	var t0: float = clock
	while clock - t0 < MAX_SCENE_S and director.run != null:
		_note_lines()
		await get_tree().process_frame
	check("Paati blesses you, gives athirasam, and the quest completes", director.run == null and GameState.mission_completed.has(PAATI) and _said("sq04_p26") and _said("sq04_p27") and _said("sq04_d07") and not _said("sq04_m08"))
	check("No fare: respect, not money %s" % str(last_reward), last_reward == Vector2i(0, 65))
	check("Everything is put back", not story.cinematic and not auto.freeze and story.actors.is_empty() and rig._camera.current and not modal_open)
	check("Paati walks in at the gate", rider.state in [QuestRider.State.LEAVING, QuestRider.State.NONE] and not rider.story_hold)

func _paati_skips() -> void:
	rider._clear()
	GameState.reset_profile()
	GameState.tutorial_active = false
	story.lines_said.clear()
	var def: MissionDef = director.registry.get_mission(PAATI)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	rider._scan = 0.0
	await get_tree().process_frame
	check("Paati again (replay)", director.start(PAATI))
	await get_tree().create_timer(0.4).timeout
	story.skip()
	check("Skipping the intro seats her at once", stage() == "ask_flower" and rider.is_aboard() and not story.cinematic and not auto.freeze)
	place_auto(director.current_stage().target)
	await run_until("flowers", 2.0)
	story.skip()
	check("Skipping a held scene still asks where she went", stage() == "guess" and story.holding)
	story._choose(0) # "The temple tank"
	check("Tank: the driver knows the way", await run_until("ask_sundal", MAX_SCENE_S) and _said("sq04_d05") and _said("sq04_p12") and not _said("sq04_p11"))
	place_auto(director.current_stage().target)
	await run_until("sundal", 2.0)
	story.skip()
	var search_stage: MissionStage = director.current_stage()
	place_auto(search_stage.target)
	director.spot(PAATI, "spot_meena")
	await get_tree().create_timer(0.3).timeout
	story.skip()
	check("Skipping the reunion: Paati back in her seat, off home", stage() == "ride_home" and rider.is_aboard() and not story.cinematic)
	place_auto(director.current_stage().target)
	await run_until("payoff", MAX_SCENE_S)
	director.choose(PAATI, "payoff", "SQ04_TAKE_FARE")
	var t0: float = clock
	while clock - t0 < MAX_SCENE_S and director.run != null:
		await get_tree().process_frame
	check("Taking the fare pays %s" % str(last_reward), last_reward == Vector2i(180, 25) and _said("sq04_m08"))
	rider._clear()

## "Margazhi Missing Beat": Sankaran rides in the back, Ganesan brings the drum, the front-gate
## choice (the wrong gate sends you round), the back gate, and staying for the concert.
func _margazhi_playthrough() -> void:
	rider._clear()
	GameState.reset_profile()
	GameState.tutorial_active = false
	story.lines_said.clear()
	line_times.clear()
	hidden_shots.clear()
	phone_frames.clear()
	var def: MissionDef = director.registry.get_mission(MARGAZHI)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	rider._scan = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check("Sankaran waits by the marker", rider.state == QuestRider.State.WAITING and rider.quest_id == MARGAZHI)
	check("Margazhi starts with a cutscene, controls locked", director.start(MARGAZHI) and story.cinematic and stage() == "intro" and auto.freeze)
	watch_cast = true
	check("Intro ends with Sankaran aboard, on to the music shop", await run_until("ask_shop", MAX_SCENE_S) and rider.is_aboard() and not director.rider_missing())
	check("Intro dialogue in order, never overlapping", _said("sq03_d03") and _no_overlap(PackedStringArray(["sq03_s01", "sq03_d01", "sq03_s02", "sq03_d02", "sq03_s03", "sq03_s04", "sq03_d03"])))
	check("Controls come back after the intro", not story.cinematic and not auto.freeze and not modal_open)
	check("Ganesan stands at his shop", story.actors.has("ganesan"))
	place_auto(director.current_stage().target)
	check("Stopping beside Ganesan starts his scene", await run_until("shop", 2.0) and story.cinematic)
	check("He brings the drum and tells you about the back gate", await run_until("approach", MAX_SCENE_S) and _said("sq03_g04") and _said("sq03_g05"))
	check("Shop lines in order", _no_overlap(PackedStringArray(["sq03_g01", "sq03_s09", "sq03_g02", "sq03_d04", "sq03_g03", "sq03_g04", "sq03_d05", "sq03_g05"])))
	var drive: MissionStage = director.current_stage()
	check("The drive is timed, capped at 32 km/h and the drum can be hurt", drive.deadline_s > 0.0 and drive.max_speed_kmh == 32.0 and drive.quality_key == "instrument")
	await get_tree().create_timer(0.2).timeout
	check("Sankaran: slowly now", _said("sq03_s10"))
	SignalBus.player_impact.emit({"severity": 0.6})
	await get_tree().create_timer(0.3).timeout
	check("A knock: Sankaran cries out for his drum", _said("sq03_s13"))
	check("The queue and the volunteer are at the front gate", story.actors.has("volunteer") and story.actors.has("rasika_1"))
	place_auto(drive.target)
	check("At the front gate: the volunteer asks which way; the scene holds on the choice", await run_until("gate", MAX_SCENE_S) and story.holding and _said("sq03_v02") and _said("sq03_s16"))
	story._choose(1) # "Front gate": the wrong one
	check("Front gate: the volunteer sends you round to the back", await run_until("to_back", MAX_SCENE_S) and _said("sq03_v03") and _said("sq03_s17") and not _said("sq03_s18"))
	check("Lalitha waits at the back gate", story.actors.has("lalitha"))
	place_auto(director.current_stage().target)
	check("Back gate: Sankaran gets out, tests the drum, and the fare choice holds", await run_until("payoff", MAX_SCENE_S) and story.holding and _said("sq03_s20") and _said("sq03_l03"))
	check("Sankaran stands on the pavement with Lalitha", rider.state == QuestRider.State.OUT and rider.body.get_parent() == rider)
	story._choose(1) # stay for the concert
	var t0: float = clock
	while clock - t0 < MAX_SCENE_S and director.run != null:
		_note_lines()
		await get_tree().process_frame
	watch_cast = false
	check("Staying for the concert: the quest completes", director.run == null and GameState.mission_completed.has(MARGAZHI) and _said("sq03_d10") and _said("sq03_l04") and _said("sq03_s23") and not _said("sq03_s22"))
	check("Staying pays respect, not money %s" % str(last_reward), last_reward == Vector2i(0, 60))
	check("No Margazhi shot has the auto in front of the speaker %s" % str(hidden_shots), hidden_shots.is_empty())
	check("Nobody plays the phone-call clip %s" % str(phone_frames), phone_frames.is_empty())
	check("Everything is put back", not story.cinematic and not auto.freeze and story.actors.is_empty() and not modal_open)
	rider._clear()

## "Filter Coffee, No Spill": no rider; three shopkeepers walk up to the driver, the first-shop
## choice decides which scene plays at which stop, and the tea man's secret sets the reward.
func _coffee_playthrough(first: String, secret: int) -> void:
	rider._clear()
	GameState.reset_profile()
	GameState.tutorial_active = false
	story.lines_said.clear()
	line_times.clear()
	hidden_shots.clear()
	phone_frames.clear()
	last_reward = Vector2i(-1, -1)
	var def: MissionDef = director.registry.get_mission(COFFEE)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	check("Coffee starts with Kannan's scene, controls locked", director.start(COFFEE) and story.cinematic and stage() == "intro" and auto.freeze)
	check("Kannan wears his davara and the tea man has a customer", story.actors.has("kannan") and (story.actors["kannan"] as QuestActor).find_child("Wear_davara", true, false) != null)
	watch_cast = true
	check("Kannan briefs you and holds on the first-shop choice", await run_until("order", MAX_SCENE_S) and story.holding and _said("sq02_k06"))
	check("Intro lines in order, never overlapping", _no_overlap(PackedStringArray(["sq02_k01", "sq02_d01", "sq02_k02", "sq02_k03", "sq02_d02", "sq02_k04", "sq02_k05", "sq02_d03", "sq02_k06"])))
	check("Kannan came to the driver's side", (story.actors["kannan"] as QuestActor).global_position.distance_to(auto.global_position) < 2.6)
	story._choose(0 if first == "SQ02_LUZ_FIRST" else 1)
	check("The choice starts the timed coffee run", await run_until("first", 3.0) and director.current_stage().deadline_s > 0.0 and director.current_stage().quality_key == "coffee")
	await get_tree().create_timer(0.2).timeout
	check("The driver talks to the coffee", _said("sq02_d04"))
	check("The shopkeepers wear their own things", story.actors.has("selvam") and (story.actors["selvam"] as QuestActor).find_child("Wear_tape", true, false) != null and story.actors.has("mohana") and (story.actors["mohana"] as QuestActor).find_child("Wear_specs", true, false) != null)
	SignalBus.player_impact.emit({"severity": 0.4})
	await get_tree().create_timer(0.3).timeout
	check("A knock: the driver fears for the foam", _said("sq02_d07"))
	place_auto(director._stage_target(director.current_stage()))
	var tailor_first: bool = first == "SQ02_LUZ_FIRST"
	check("First stop plays the chosen shop's scene", await run_until("second", MAX_SCENE_S) and (_said("sq02_s04") if tailor_first else _said("sq02_m04")) and not (_said("sq02_m01") if tailor_first else _said("sq02_s01")))
	place_auto(director._stage_target(director.current_stage()))
	check("Second stop plays the other shop", await run_until("third", MAX_SCENE_S) and _said("sq02_s04") and _said("sq02_m04"))
	check("Book house lines in order", _no_overlap(PackedStringArray(["sq02_m01", "sq02_d10", "sq02_m02", "sq02_d11", "sq02_m03", "sq02_d12", "sq02_m04"])))
	check("Murugan waits at the tea stall", story.actors.has("murugan") and story.actors.has("tea_customer"))
	place_auto(director.current_stage().target)
	check("The tea man's secret holds on the choice", await run_until("secret", MAX_SCENE_S) and story.holding and _said("sq02_r04"))
	story._choose(secret)
	var t0: float = clock
	while clock - t0 < MAX_SCENE_S and director.run != null:
		_note_lines()
		await get_tree().process_frame
	watch_cast = false
	var keep: bool = secret == 0
	check("The ending follows the choice", director.run == null and GameState.mission_completed.has(COFFEE) and _said("sq02_r07") and _said("sq02_d16") and (_said("sq02_r05") if keep else _said("sq02_r06")) and not (_said("sq02_r06") if keep else _said("sq02_r05")))
	check("Reward: keeping the secret earns respect, teasing earns ₹20 %s" % str(last_reward), last_reward == (Vector2i(145, 45) if keep else Vector2i(165, 15)))
	check("No coffee shot has the auto in front of the speaker %s" % str(hidden_shots), hidden_shots.is_empty())
	check("Nobody plays the phone-call clip %s" % str(phone_frames), phone_frames.is_empty())
	check("Everything is put back", not story.cinematic and not auto.freeze and story.actors.is_empty() and not modal_open)

## "Room for an Ambulance" (sq_016): the constable's scene, then three pull-overs. At each one the
## indicator goes on, the auto stops on the marker and the person there plays their scene.
func _ambulance_playthrough() -> void:
	rider._clear()
	GameState.reset_profile()
	GameState.tutorial_active = false
	story.lines_said.clear()
	line_times.clear()
	hidden_shots.clear()
	phone_frames.clear()
	last_reward = Vector2i(-1, -1)
	var def: MissionDef = director.registry.get_mission(AMBULANCE)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	check("Ambulance starts with the constable's scene, controls locked", director.start(AMBULANCE) and story.cinematic and stage() == "intro" and auto.freeze)
	check("The constable wears his whistle", story.actors.has("pandian") and (story.actors["pandian"] as QuestActor).find_child("Wear_whistle", true, false) != null)
	watch_cast = true
	check("Pandian briefs you and holds on the choice", await run_until("brief", MAX_SCENE_S) and story.holding and _said("sq16_p06"))
	check("Intro lines in order, never overlapping", _no_overlap(PackedStringArray(["sq16_p01", "sq16_d01", "sq16_p02", "sq16_d02", "sq16_p03", "sq16_d03", "sq16_p04", "sq16_d04", "sq16_p05", "sq16_p06"])))
	check("The constable came to the driver's side", (story.actors["pandian"] as QuestActor).global_position.distance_to(auto.global_position) < 2.6)
	story._choose(0)
	check("The choice starts the first pull-over", await run_until("yield_1", 3.0) and director.current_stage().kind == "yield")
	await get_tree().create_timer(0.2).timeout
	check("The driver talks himself through it", _said("sq16_d05"))
	var scenes: Array = [["yield_1", "scene_a", "kanagu", "Wear_basket", "sq16_k04"], ["yield_2", "scene_b", "sundar", "Wear_towel", "sq16_s05"], ["yield_3", "scene_c", "nurse", "Wear_stethoscope", "sq16_n07"]]
	for i: int in scenes.size():
		var entry: Array = scenes[i]
		check("%s: %s is waiting and wears their own things" % [entry[0], entry[2]], stage() == entry[0] and story.actors.has(entry[2]) and (story.actors[entry[2]] as QuestActor).find_child(entry[3], true, false) != null)
		place_auto(director._stage_target(director.current_stage()))
		SignalBus.indicator_changed.emit(-1)
		var next_stage: String = "yield_%d" % (i + 2) if i < 2 else ""
		if i < 2:
			check("%s: indicator then stop plays the scene" % entry[0], await run_until(next_stage, MAX_SCENE_S) and _said(entry[4]))
		else:
			var t0: float = clock
			while clock - t0 < MAX_SCENE_S and director.run != null:
				_note_lines()
				await get_tree().process_frame
	watch_cast = false
	check("Kanagu lines in order", _no_overlap(PackedStringArray(["sq16_k01", "sq16_d11", "sq16_k02", "sq16_d12", "sq16_k03", "sq16_d13", "sq16_k04"])))
	check("Sundar lines in order", _no_overlap(PackedStringArray(["sq16_s01", "sq16_d14", "sq16_s02", "sq16_d15", "sq16_s03", "sq16_s04", "sq16_d16", "sq16_s05"])))
	check("The nurse's news and the baby's name", _said("sq16_n02") and _said("sq16_n05") and _said("sq16_d22"))
	check("Nurse lines in order", _no_overlap(PackedStringArray(["sq16_n01", "sq16_d17", "sq16_n02", "sq16_d18", "sq16_n03", "sq16_d19", "sq16_n04", "sq16_d20", "sq16_n05", "sq16_d21", "sq16_n06", "sq16_d22", "sq16_n07"])))
	check("The quest ends complete with its reward %s" % str(last_reward), director.run == null and GameState.mission_completed.has(AMBULANCE) and last_reward.x == 170)
	check("No ambulance shot has the auto in front of the speaker %s" % str(hidden_shots), hidden_shots.is_empty())
	check("Nobody plays the phone-call clip %s" % str(phone_frames), phone_frames.is_empty())
	check("Everything is put back", not story.cinematic and not auto.freeze and story.actors.is_empty() and not modal_open)

## "The Monsoon Supply Run" (sq_017): the order of the two deliveries follows the choice.
func _monsoon_playthrough(first: String) -> void:
	rider._clear()
	GameState.reset_profile()
	GameState.tutorial_active = false
	story.lines_said.clear()
	line_times.clear()
	hidden_shots.clear()
	phone_frames.clear()
	last_reward = Vector2i(-1, -1)
	var def: MissionDef = director.registry.get_mission(MONSOON)
	check("Monsoon is a rain quest with a story", def.scenario_weather == "rain" and def.story != null)
	place_auto(def.start_anchor)
	await get_tree().physics_frame
	check("Monsoon starts with Vasanthi's scene, controls locked", director.start(MONSOON) and story.cinematic and stage() == "intro" and auto.freeze)
	check("The streets flood for the quest: shallow at the store, too deep to drive at the junction to avoid", flood.active and flood.depth_at(def.start_anchor.x, def.start_anchor.z) > 0.06 and flood.depth_at(def.start_anchor.x, def.start_anchor.z) < 0.25 and flood.depth_at(412.8, -253.6) > auto.stats.water_stall_depth_m)
	var water_felt: Array[float] = []
	var felt: Callable = func(d: float) -> void: water_felt.append(d)
	SignalBus.water_depth_changed.connect(felt)
	SignalBus.player_pose_updated.emit(def.start_anchor, Vector3.FORWARD)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("The auto feels the water it stands in %s" % str(water_felt), not water_felt.is_empty() and water_felt.back() > 0.06)
	SignalBus.water_depth_changed.disconnect(felt)
	check("Vasanthi has her clipboard and Rafiq his tea glass", story.actors.has("vasanthi") and (story.actors["vasanthi"] as QuestActor).find_child("Wear_clipboard", true, false) != null and story.actors.has("rafiq") and (story.actors["rafiq"] as QuestActor).find_child("Wear_glass", true, false) != null)
	watch_cast = true
	check("The intro ends and the load stop is next", await run_until("load", MAX_SCENE_S) and _said("sq17_v05"))
	check("Intro lines in order, never overlapping", _no_overlap(PackedStringArray(["sq17_v01", "sq17_d01", "sq17_v02", "sq17_r01", "sq17_v03", "sq17_d02", "sq17_v04", "sq17_d03", "sq17_v05"])))
	check("Loading is a stop-and-do stage, not a scene", director.current_stage().kind == "cargo" and director.current_stage().cargo_delta == 3)
	place_auto(director._stage_target(director.current_stage()))
	check("Loading the bundles moves on to the flood sign", director.interact(MONSOON, "load") and stage() == "warning")
	var waited: float = 0.0
	while not _said("sq17_d09") and waited < 15.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	check("The driver reads the road", _said("sq17_d09"))
	place_auto(director._stage_target(director.current_stage()))
	check("Reading the sign starts the watchman's scene", director.interact(MONSOON, "warning") and stage() == "watch")
	check("Jeyaraj holds an umbrella", story.actors.has("jeyaraj") and (story.actors["jeyaraj"] as QuestActor).find_child("Wear_umbrella", true, false) != null)
	check("The watchman warns you and holds on the order choice", await run_until("order", MAX_SCENE_S) and story.holding and _said("sq17_j05"))
	check("Watchman lines in order", _no_overlap(PackedStringArray(["sq17_j01", "sq17_d10", "sq17_j02", "sq17_d11", "sq17_j03", "sq17_j04", "sq17_d12", "sq17_j05"])))
	check("Jeyaraj came to the driver's side", (story.actors["jeyaraj"] as QuestActor).global_position.distance_to(auto.global_position) < 2.6)
	var shelter_first: bool = first == "SQ17_SHELTER"
	story._choose(0 if shelter_first else 1)
	check("The choice starts the timed first delivery", await run_until("first", 3.0) and director.current_stage().deadline_s > 0.0 and director.current_stage().quality_key == "supplies")
	check("The two people at the drops have their own things", story.actors.has("maragatham") and (story.actors["maragatham"] as QuestActor).find_child("Wear_glass", true, false) != null and story.actors.has("pooja") and (story.actors["pooja"] as QuestActor).find_child("Wear_pencil", true, false) != null)
	place_auto(director._stage_target(director.current_stage()))
	check("First drop: interact hands over and plays the chosen scene", director.interact(MONSOON, "first") and stage() == "first_drop")
	check("The first scene is the chosen one", await run_until("second", MAX_SCENE_S) and (_said("sq17_m05") if shelter_first else _said("sq17_p05")) and not (_said("sq17_p01") if shelter_first else _said("sq17_m01")))
	place_auto(director._stage_target(director.current_stage()))
	check("Second drop plays the other scene", director.interact(MONSOON, "second") and stage() == "second_drop")
	var t0: float = clock
	while clock - t0 < MAX_SCENE_S and director.run != null:
		_note_lines()
		await get_tree().process_frame
	watch_cast = false
	check("Both scenes played, then the ending line", _said("sq17_m05") and _said("sq17_p05") and _said("sq17_d18"))
	check("Shelter lines in order", _no_overlap(PackedStringArray(["sq17_m01", "sq17_d13", "sq17_m02", "sq17_m03", "sq17_d14", "sq17_m04", "sq17_d15", "sq17_m05"])))
	check("Desk lines in order", _no_overlap(PackedStringArray(["sq17_p01", "sq17_d16", "sq17_p02", "sq17_p03", "sq17_d17", "sq17_p04", "sq17_p05"])))
	check("The quest ends complete with its reward %s" % str(last_reward), director.run == null and GameState.mission_completed.has(MONSOON) and last_reward.x >= 190)
	check("No monsoon shot has the auto in front of the speaker %s" % str(hidden_shots), hidden_shots.is_empty())
	check("Nobody plays the phone-call clip %s" % str(phone_frames), phone_frames.is_empty())
	check("Everything is put back", not story.cinematic and not auto.freeze and story.actors.is_empty() and not modal_open)
	check("The flood drains when the quest ends", not flood.active and flood.depth_at(412.8, -253.6) == 0.0)

func _language_check() -> void:
	GameState.settings["language"] = "ta"
	story.story = director.registry.get_mission(QUEST).story
	check("Tamil players hear Tamil", story.story.voice_path("sq07_l01", story._language()).ends_with("_ta.ogg"))
	GameState.settings["language"] = "en"
	check("English players hear English", story.story.voice_path("sq07_l01", story._language()).ends_with("_en.ogg"))
	story.story = null
