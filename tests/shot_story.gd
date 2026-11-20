extends Node
## Dev-only: renders "The Little Red Kite" in the real city to $SHOT_OUT (default /tmp/story_shots):
## every cutscene at a few moments, the search views and the letterbox choice. Run with
## xvfb-run godot --path . --rendering-method gl_compatibility --fixed-fps 60 res://tests/shot_story.tscn

var out: String = "/tmp/story_shots"
## SHOT_ONLY=07,08,12: only these shot prefixes are rendered; other scenes are skipped through.
var only: PackedStringArray = PackedStringArray()
var city: Node
var auto: AutoRickshawController
var director: MissionDirector
var story: QuestStory
var world: WorldChunkStreamer
var rig: CameraRig

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.has_environment("SHOT_OUT"):
		out = OS.get_environment("SHOT_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	if OS.has_environment("SHOT_ONLY"):
		only = OS.get_environment("SHOT_ONLY").split(",")
	GameState.reset_profile()
	GameState.tutorial_active = false
	GameState.shift_minute = float(OS.get_environment("SHOT_MIN")) if OS.has_environment("SHOT_MIN") else 600.0
	city = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	auto = city.get_node("AutoRickshaw") as AutoRickshawController
	director = city.get_node("MissionDirector") as MissionDirector
	story = city.get_node("QuestStory") as QuestStory
	world = city.get_node("World") as WorldChunkStreamer
	rig = city.get_node("CameraRig") as CameraRig
	for i: int in 30:
		await get_tree().physics_frame
	GameState.tutorial_active = false
	var def: MissionDef = director.registry.get_mission("sq_007")
	await _go(def.start_anchor)
	print("start ok=", director.start("sq_007"))
	await _shots("01_intro", [0.4, 1.4, 2.0, 4.6, 7.0, 10.0, 14.0, 17.0, 19.0], "ask_tea")
	# The flower seller and the tea stall.
	var akka: QuestActor = story.actors.get("flower_akka") as QuestActor
	if akka != null:
		await _go(akka.global_position + Vector3(-7.0, 0.0, -4.0))
		await _wait(0.6)
		_save("02_flower_seller_drive")
	await _go(director.current_stage().target)
	await _shots("03_tea", [0.6, 2.0, 4.5, 7.5], "spot_kite")
	# Searching for the kite from Sullivan Street.
	var st: MissionStage = director.current_stage()
	var look_from: Vector3 = Vector3(st.spot_pos.x, 0.0, st.spot_pos.z) + Vector3(22.0, 0.0, -2.0)
	await _go(look_from, st.spot_pos)
	await _wait(0.8)
	_save("04_search_chase")
	await _cockpit("05_search_kite_cockpit")
	director.spot("sq_007", "spot_kite")
	await _shots("06_kids", [0.5, 2.5, 4.5, 6.5, 8.5], "spot_boy")
	st = director.current_stage()
	await _go(st.target, st.spot_pos)
	await _wait(0.8)
	_save("07_beach_chase")
	await _cockpit("08_beach_crowd_cockpit")
	director.spot("sq_007", "spot_boy")
	await _shots("09_reunion", [0.5, 2.2, 3.4, 6.0, 9.0, 12.0, 15.0], "choice")
	await _wait(1.0)
	_save("10_choice_letterbox")
	story._choose(1)
	await _shots("11_promise", [0.5, 2.5, 4.5], "rescue")
	await _go(director.current_stage().target)
	await _shots("12_climb", [0.5, 1.8, 2.8, 3.6], "ride_home")
	await _go(director.current_stage().target)
	await _shots("13_home", [0.6, 2.5, 5.0], "payoff")
	await _wait(0.5)
	_save("14_payoff_letterbox")
	story._choose(1)
	await _shots("15_thanks", [0.5, 2.5, 5.0], "")
	print("done stage=", director.run.stage_id if director.run != null else "complete")
	get_tree().quit()

## Teleports to a road point near `at` (facing along the road) and waits for the city to load.
func _go(at: Vector3, face: Vector3 = Vector3.INF) -> void:
	var graph: RoadGraph = SignalBus.current_road_graph
	var heading: Vector3 = Vector3.FORWARD
	var p: Vector3 = at
	var cp: Dictionary = graph.closest_point(at)
	if int(cp["edge"]) >= 0:
		var pd: Array[Vector3] = graph.sample(int(cp["edge"]), float(cp["s"]), 1)
		p = pd[0]
		heading = pd[1]
	if face != Vector3.INF:
		heading = Vector3(face.x - p.x, 0.0, face.z - p.z)
	heading.y = 0.0
	SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), Vector3(p.x, 1.0, p.z)))
	await get_tree().physics_frame
	world.update_streaming(true)
	for i: int in 45:
		await get_tree().physics_frame

func _wait(seconds: float) -> void:
	for i: int in int(seconds * 60.0):
		await get_tree().process_frame

## Saves frames at the given seconds into the current cutscene chain, then runs on to `until`.
func _shots(name: String, times: Array, until: String) -> void:
	if not _wanted(name):
		for i: int in 40:
			if story.cinematic and not story.holding:
				story.skip()
			await get_tree().process_frame
			if director.run == null or director.run.stage_id == until:
				return
		return
	var t: float = 0.0
	var i: int = 0
	for at: Variant in times:
		while t < float(at):
			await get_tree().process_frame
			t += 1.0 / 60.0
		_save("%s_%02d" % [name, i])
		i += 1
	var guard: int = 0
	while director.run != null and until != "" and director.run.stage_id != until and guard < 60 * 90:
		await get_tree().process_frame
		guard += 1
	if until == "":
		while director.run != null and guard < 60 * 40:
			await get_tree().process_frame
			guard += 1

## The player's own view from the driver's seat (cockpit camera), then back to the chase camera.
func _cockpit(name: String) -> void:
	while int(rig.mode) != CameraRig.Mode.COCKPIT:
		rig.cycle_mode()
	await _wait(0.5)
	_save(name)
	while int(rig.mode) != CameraRig.Mode.CHASE:
		rig.cycle_mode()

func _look(from: Vector3, at: Vector3, fov: float, name: String) -> void:
	var cam: Camera3D = Camera3D.new()
	cam.fov = fov
	cam.far = 400.0
	city.add_child(cam)
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.make_current()
	_save(name)
	cam.queue_free()
	rig._camera.make_current()

func _wanted(name: String) -> bool:
	if only.is_empty():
		return true
	for prefix: String in only:
		if name.begins_with(prefix):
			return true
	return false

var _pending: String = ""
func _save(name: String) -> void:
	if not _wanted(name):
		return
	_pending = name
	RenderingServer.force_draw(false)
	_save_now()

func _save_now() -> void:
	if _pending == "":
		return
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, _pending])
	print("shot ", _pending, " stage=", director.run.stage_id if director.run != null else "-")
	_pending = ""
