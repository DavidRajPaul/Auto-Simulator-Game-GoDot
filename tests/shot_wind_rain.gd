extends Node
## Dev-only: SHOT_MODE rain (splashes, rings, tyre spray), bags (walkers with bags),
## wind (two frames of the same trees a second apart, strong gust) or pothole (auto in a hole).
## SHOT_LOOK "x,z,cx,cy,cz", SHOT_DIR output folder.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	var mode: String = OS.get_environment("SHOT_MODE")
	GameState.shift_minute = 960.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	var v: PackedFloat64Array = PackedFloat64Array(Array(OS.get_environment("SHOT_LOOK").split(",")).map(func(t: String) -> float: return float(t)))
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, Vector3(v[2], 1.0, v[4])))
	SignalBus.player_pose_updated.emit(Vector3(v[2], 0, v[4]), Vector3.FORWARD)
	for i: int in 120:
		await get_tree().physics_frame
	var rig: CameraRig = city.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	var cam: Camera3D = rig.get_node("Camera") as Camera3D
	cam.global_position = Vector3(v[2], v[3], v[4])
	cam.look_at(Vector3(v[0], 1.0, v[1]))
	(city.get_node("AutoRickshaw") as Node3D).visible = mode == "pothole"
	var dir: String = OS.get_environment("SHOT_DIR")
	if mode == "rain":
		GameState.set_rain(true, 120.0)
		for i: int in 400:
			await get_tree().process_frame
	elif mode == "wind":
		var wind: Wind = city.get_node("World/Wind") as Wind
		wind.set_process(false)
		Wind.strength = 0.9
		Wind.gust = 0.0
		Wind.push()
		for i: int in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(dir.path_join("wind_calm.png"))
		Wind.gust = 1.0
		Wind.push()
		for i: int in 40:
			await get_tree().process_frame
	else:
		for i: int in 60:
			await get_tree().process_frame
		if mode == "chat":
			var pc: PedestrianManager = city.get_node("PedestrianManager") as PedestrianManager
			for w: PedestrianManager.Walker in pc.people:
				if w.active and ((w.role == "chat" and w.partner != null) or (w.idle and w.role == "" and pc._start_chat(w))):
					print("CHAT at ", w.pos)
					var mid: Vector3 = (w.pos + w.partner.pos) * 0.5
					var side: Vector3 = Vector3(w.heading.z, 0.0, -w.heading.x)
					for i: int in 40:
						await get_tree().process_frame
					var road: Vector3 = (w.heading + w.partner.heading).normalized()
					cam.global_position = mid + road * 4.0 + Vector3(0, 1.6, 0)
					cam.look_at(mid + Vector3(0, 1.0, 0))
					for i: int in 3:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(dir.path_join("chat_0.png"))
					break
		if mode == "bags":
			var pm: PedestrianManager = city.get_node("PedestrianManager") as PedestrianManager
			var k: int = 0
			for w: PedestrianManager.Walker in pm.people:
				if w.active and w.bags > 0 and k < 3:
					var side: Vector3 = Vector3(w.heading.z, 0.0, -w.heading.x)
					cam.global_position = w.pos + side * 2.6 + w.heading * 1.2 + Vector3(0, 1.4, 0)
					cam.look_at(w.pos + Vector3(0, 0.9, 0))
					for i: int in 3:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(dir.path_join("bags_%d.png" % k))
					k += 1
	get_viewport().get_texture().get_image().save_png(dir.path_join(mode + ".png"))
	var peds: PedestrianManager = city.get_node("PedestrianManager") as PedestrianManager
	print("BAGS ", peds.bag_count())
	get_tree().quit()
