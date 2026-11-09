extends Node
## Dev-only: walks through a rider quest (sq_004, Paati) and saves a picture of each moment to
## $SHOT_DIR: waiting at the marker, climbing in, riding in the back, out of a burning auto, back in,
## and walking to the door at the end.
var city: Node
var rider: QuestRider
var director: MissionDirector
var auto: AutoRickshawController
var cam: Camera3D
var out_dir: String

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame

func _shot(name: String, look_at: Vector3, from: Vector3) -> void:
	cam.global_position = from
	cam.look_at(look_at)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
	print("SHOT ", name, " state=", QuestRider.State.keys()[rider.state])

func _run() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	GameState.reset_profile()
	GameState.tutorial_active = false
	city = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	await _frames(30)
	rider = city.get_node("QuestRider") as QuestRider
	director = city.get_node("MissionDirector") as MissionDirector
	auto = city.get_node("AutoRickshaw") as AutoRickshawController
	var rig: CameraRig = city.get_node("CameraRig") as CameraRig
	var quest: String = OS.get_environment("SHOT_QUEST") if OS.get_environment("SHOT_QUEST") != "" else "sq_004"
	var d: MissionDef = director.registry.get_mission(quest)
	# Park on the road beside the marker.
	var graph: RoadGraph = SignalBus.current_road_graph
	var cp: Dictionary = graph.closest_point(d.start_anchor)
	var pd: Array[Vector3] = graph.sample(int(cp["edge"]), float(cp["s"]), 1)
	var at: Vector3 = pd[0] - pd[1] * 4.0
	SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(pd[1], Vector3.UP), at + Vector3(0, 1.0, 0)))
	await _frames(120)
	rider._scan = 0.0
	await _frames(10)
	rig.set_process(false)
	rig.set_physics_process(false)
	cam = Camera3D.new()
	city.add_child(cam)
	cam.current = true
	var p: Vector3 = rider.body.global_position if rider.body != null else at
	var side: Vector3 = (p - auto.global_position)
	side.y = 0.0
	side = side.normalized()
	var fwd: Vector3 = -auto.global_basis.z
	await _shot("1_waiting", p + Vector3(0, 0.9, 0), p + side * 3.5 + fwd * 2.0 + Vector3(0, 1.6, 0))
	print("start ", director.start(quest))
	await _frames(70)
	p = rider.body.global_position
	await _shot("2_boarding", p + Vector3(0, 0.9, 0), auto.global_position + side * 5.0 + fwd * 3.5 + Vector3(0, 2.2, 0))
	for i: int in 900:
		if rider.state == QuestRider.State.ABOARD:
			break
		await get_tree().physics_frame
	await _frames(30)
	print("SEAT ", rider.seat_point_in_auto(), " target ", QuestRider.PASSENGER_HIP)
	var right: Vector3 = auto.global_basis.x
	await _shot("3_aboard_side", auto.global_position + Vector3(0, 0.9, 0) + auto.global_basis.z * 0.4, auto.global_position + right * 2.6 + auto.global_basis.z * 1.4 + Vector3(0, 1.4, 0))
	await _shot("4_aboard_back", auto.global_position + Vector3(0, 1.0, 0), auto.global_position + auto.global_basis.z * 4.0 - right * 1.5 + Vector3(0, 1.8, 0))
	await _shot("5b_aboard_above", auto.global_position + Vector3(0, 0.9, 0), auto.global_position + right * -2.2 + auto.global_basis.z * 1.0 + Vector3(0, 3.2, 0))
	await _shot("5_aboard_front", auto.global_position + Vector3(0, 1.0, 0) + auto.global_basis.z * 0.4, auto.global_position - auto.global_basis.z * 3.2 + right * 1.2 + Vector3(0, 1.5, 0))
	GameState.condition = 8.0
	SignalBus.condition_changed.emit(8.0)
	await _frames(240)
	p = rider.body.global_position
	await _shot("6_out_of_fire", p + Vector3(0, 0.9, 0), auto.global_position + right * 6.0 + fwd * 5.0 + Vector3(0, 2.6, 0))
	print("rider missing while out: ", director.rider_missing())
	GameState.repair_free()
	SignalBus.condition_changed.emit(GameState.condition)
	for i: int in 900:
		if rider.state == QuestRider.State.ABOARD:
			break
		await get_tree().physics_frame
	print("back aboard: ", rider.state == QuestRider.State.ABOARD, " missing: ", director.rider_missing())
	director._complete()
	await _frames(150)
	if rider.body != null:
		p = rider.body.global_position
		await _shot("7_walking_home", p + Vector3(0, 0.9, 0), auto.global_position + right * 5.0 + fwd * 4.0 + Vector3(0, 2.4, 0))
	get_tree().quit()
