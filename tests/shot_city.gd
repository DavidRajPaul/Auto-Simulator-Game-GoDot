extends Node
## Dev-only: renders the city scene to $SHOT_OUT. SHOT_CAM=0/1/2 camera mode, SHOT_DRIVE=seconds of throttle,
## SHOT_RIDE=1 starts a ride (to show the guide line + nav banner), SHOT_MAP=1 opens the full map.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	if OS.has_environment("SHOT_MIN"):
		GameState.shift_minute = float(OS.get_environment("SHOT_MIN"))
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	var rig: CameraRig = city.get_node("CameraRig") as CameraRig
	if OS.has_environment("SHOT_LOOK"):
		# "x,z,cx,cy,cz": park the camera at cam pos looking at (x, 2, z).
		var v: PackedFloat64Array = PackedFloat64Array(Array(OS.get_environment("SHOT_LOOK").split(",")).map(func(t: String) -> float: return float(t)))
		var auto0: Node3D = city.get_node("AutoRickshaw") as Node3D
		SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, Vector3(v[2], 1.0, v[4])))
		SignalBus.player_pose_updated.emit(Vector3(v[2], 0, v[4]), Vector3.FORWARD)
		for i: int in 90:
			await get_tree().physics_frame
		rig.set_process(false)
		var cam0: Camera3D = rig.get_node("Camera") as Camera3D
		cam0.global_position = Vector3(v[2], v[3], v[4])
		cam0.look_at(Vector3(v[0], 3.0, v[1]))
		auto0.visible = false
	var cam_mode: int = int(OS.get_environment("SHOT_CAM")) if OS.has_environment("SHOT_CAM") else 0
	while int(rig.mode) != cam_mode:
		rig.cycle_mode()
	if OS.get_environment("SHOT_RIDE") == "1":
		var sm: SavariManager = city.get_node("SavariManager") as SavariManager
		var auto: Node3D = city.get_node("AutoRickshaw") as Node3D
		var arche: PassengerArchetype = sm.archetypes[0]
		var h: Dictionary = sm.spawn_hail_at(auto.global_position + (-auto.global_basis.z) * 3.0, arche)
		sm.start_haggle(h)
		SignalBus.haggle_choice_made.emit(0)
	var drive: float = float(OS.get_environment("SHOT_DRIVE")) if OS.has_environment("SHOT_DRIVE") else 0.0
	if drive > 0.0:
		Input.action_press("accelerate")
		for i: int in int(drive * 60.0):
			await get_tree().physics_frame
		Input.action_release("accelerate")
	if OS.get_environment("SHOT_SIGN") == "1":
		# Park the camera in front of the nearest street board.
		var ss: StreetSigns = city.get_node("StreetSigns") as StreetSigns
		ss._player = (city.get_node("AutoRickshaw") as Node3D).global_position
		ss.refresh()
		for n: Node3D in ss._pool:
			if n.visible:
				rig.set_process(false)
				var cam: Camera3D = rig.get_node("Camera") as Camera3D
				cam.global_position = n.global_position + n.global_basis * Vector3(float(OS.get_environment("SHOT_SX")) if OS.has_environment("SHOT_SX") else 0.6, 1.9, -5.5)
				cam.look_at(n.global_position + Vector3(0, 2.2, 0))
				print("SIGN ", (n.get_node("English") as Label3D).text)
				break
	if OS.has_environment("SHOT_SVC"):
		# Put the service-vehicle slot, showing variant SHOT_SVC, on the road just ahead.
		var tm: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
		var auto2: Node3D = city.get_node("AutoRickshaw") as Node3D
		for v: TrafficVehicleAI in tm.pool:
			if v.archetype == TrafficVehicleAI.Archetype.SERVICE:
				var c: Dictionary = tm.graph.closest_point(auto2.global_position + (-auto2.global_basis.z) * 16.0)
				tm.place_vehicle(v, int(c["edge"]), float(c["s"]), 1, 0)
				var want: int = int(OS.get_environment("SHOT_SVC"))
				for i: int in v._service_models.size():
					v._service_models[i].visible = i == want
				v.cruise_speed_mps = 0.0
				v.current_speed_mps = 0.0
				v.bumped_timer = 999.0
	if OS.get_environment("SHOT_MAP") == "1":
		SignalBus.full_map_requested.emit(true)
	for i: int in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
