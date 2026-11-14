extends Node
## Dev-only: renders the city scene to $SHOT_OUT. SHOT_CAM=0/1/2 camera mode, SHOT_DRIVE=seconds of throttle,
## SHOT_RIDE=1 starts a ride (to show the guide line + nav banner), SHOT_MAP=1 opens the full map;
## SHOT_MAP_PANEL=legend / journal / route then shows the map key, the last side-quest page, or
## "Go there" on the first quest, or pin = Drop Pin mode with a pin placed. SHOT_STRIKE=metres[,deg]
## renders a lightning strike ahead in the rain (and the frame before it, *_dark.png).
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	# SHOT_DEVICE=1: what an Android phone gets from the engine's ".mobile" defaults (desktop
	# renders never see those overrides): hard 2048 directional shadows, 0.85 3D scale, no MSAA.
	if OS.get_environment("SHOT_DEVICE") == "1":
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		get_tree().root.scaling_3d_scale = 0.85
	if OS.has_environment("SHOT_GFX"):
		GameState.set_setting("graphics", int(OS.get_environment("SHOT_GFX")))
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
	if OS.has_environment("SHOT_BOARD"):
		# Stand across the street from building board #SHOT_BOARD (SHOT_BD = distance, m).
		var bb: BuildingBoards = city.get_node("BuildingBoards") as BuildingBoards
		var s: Array = bb.spot(int(OS.get_environment("SHOT_BOARD")))
		var at: Vector3 = Vector3(float(s[0]), float(s[4]), float(s[1]))
		var out: Vector3 = Vector3(sin(float(s[2])), 0.0, cos(float(s[2])))
		var dist: float = float(OS.get_environment("SHOT_BD")) if OS.has_environment("SHOT_BD") else 12.0
		var eye: Vector3 = at + out * dist + out.cross(Vector3.UP) * dist * 0.35
		eye.y = 1.7 if str(s[5]) == "shop" else maxf(2.0, at.y * 0.35)
		SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, Vector3(eye.x, 1.0, eye.z) + out * 3.0))
		bb._player = at
		bb.refresh()
		for i: int in 90:
			await get_tree().physics_frame
		bb._player = at
		bb.refresh()
		rig.set_process(false)
		var camb: Camera3D = rig.get_node("Camera") as Camera3D
		camb.global_position = eye
		camb.look_at(at)
		(city.get_node("AutoRickshaw") as Node3D).visible = false
		print("BOARD ", s)
	if OS.has_environment("SHOT_RAIN"):
		# SHOT_RAIN=0..1: weather blend for the sky / fog / light (Atmosphere.apply).
		var atmo: Atmosphere = city.get_node("Atmosphere") as Atmosphere
		atmo.set_process(false)
		atmo.apply(GameState.shift_minute, float(OS.get_environment("SHOT_RAIN")))
	if OS.has_environment("SHOT_TILT"):
		# SHOT_TILT=deg: lift the camera's view up into the sky (sky / cloud check).
		rig.set_process(false)
		var camt: Camera3D = rig.get_node("Camera") as Camera3D
		camt.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(OS.get_environment("SHOT_TILT"))))
	if OS.has_environment("SHOT_BUSSTOP"):
		# SHOT_BUSSTOP=<stop index>: a bus (SHOT_BUSLIV = livery index) pulls in there; the camera
		# stands across the road looking at the shelter.
		var bs: BusStops = city.get_node("BusStops") as BusStops
		var tm2: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
		var st: Dictionary = bs.stops[int(OS.get_environment("SHOT_BUSSTOP"))]
		var at: Vector3 = Vector3(float(st["x"]), 0.0, float(st["z"]))
		var front: Vector3 = Basis(Vector3.UP, float(st["yaw"])) * Vector3(0, 0, 1)
		SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, at - front * 4.0 + Vector3(0, 1, 0)))
		SignalBus.player_pose_updated.emit(at, Vector3.FORWARD)
		for i: int in 60:
			await get_tree().physics_frame
		bs._player = at
		bs.refresh()
		var bus: TrafficVehicleAI = null
		for v: TrafficVehicleAI in tm2.pool:
			if v.archetype == TrafficVehicleAI.Archetype.MTC_BUS and bus == null:
				bus = v
			elif v.archetype != TrafficVehicleAI.Archetype.MTC_BUS:
				v.deactivate()
		tm2.set_physics_process(false)
		var want: int = int(OS.get_environment("SHOT_BUSLIV")) if OS.has_environment("SHOT_BUSLIV") else 0
		for tries: int in 60:
			tm2.place_vehicle(bus, int(st["edge"]), float(st["s"]) - 45.0 * float(st["dir"]), int(st["dir"]), 0)
			if bus.bus_variant == want:
				break
		for f: int in 60 * 12:
			bus.tick(1.0 / 60.0)
			if bus._dwell > 0.0:
				break
		rig.set_process(false)
		var camb2: Camera3D = rig.get_node("Camera") as Camera3D
		var along: Vector3 = Vector3(front.z, 0, -front.x)
		camb2.global_position = at + front * 16.0 + along * 9.0 + Vector3(0, 3.0, 0)
		camb2.look_at(at + Vector3(0, 1.8, 0))
		(city.get_node("AutoRickshaw") as Node3D).visible = false
	if OS.get_environment("SHOT_MAP") == "1":
		SignalBus.full_map_requested.emit(true)
		var fm: FullMap = (city.get_node("PassengerHUD") as PassengerHUD).full_map
		match OS.get_environment("SHOT_MAP_PANEL"):
			"legend":
				fm._legend_open = true
			"journal":
				fm._journal_open = true
				fm._journal_page = 999 # clamps to the last page that has quests
			"pin":
				# Drop Pin mode with a pin placed a few hundred metres ahead of the auto.
				fm._select_mode = 2
				fm._custom_destination = Vector3(fm._player.x + 140.0, 0.0, fm._player.z - 90.0)
				fm._has_custom_destination = true
			"route":
				# A quest 400-1500 m away, so the route is long enough to see.
				fm._quest_selected = str(fm._quest_rows[0]["id"])
				for q: Dictionary in fm._quest_rows:
					var d: float = Vector2((q["position"] as Vector3).x - fm._player.x, (q["position"] as Vector3).z - fm._player.z).length()
					if d > 400.0 and d < 1500.0 and bool(q["unlocked"]):
						fm._quest_selected = str(q["id"])
						break
				fm._track_selected()
		fm.queue_redraw()
	for i: int in 20:
		await get_tree().process_frame
	if OS.has_environment("SHOT_STRIKE"):
		# SHOT_STRIKE=metres[,degrees right of the view]: rain, a frame before the strike
		# ($SHOT_OUT with _dark), then the flash at its peak ($SHOT_OUT).
		var v: PackedStringArray = OS.get_environment("SHOT_STRIKE").split(",")
		GameState.thunder_override = 0
		GameState.set_rain(true, 300.0)
		if OS.has_environment("SHOT_PITCH"):
			rig._orbit_pitch = float(OS.get_environment("SHOT_PITCH"))
		for i: int in 300:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT").replace(".png", "_dark.png"))
		var cam: Camera3D = get_viewport().get_camera_3d()
		var fwd: Vector3 = -cam.global_transform.basis.z
		var ts: Thunderstorm = city.get_node("Thunderstorm") as Thunderstorm
		var bearing: float = atan2(fwd.z, fwd.x) + deg_to_rad(float(v[1]) if v.size() > 1 else 0.0)
		ts.strike(float(v[0]), bearing, true)
		for i: int in 3:
			await get_tree().process_frame
		var smat: ShaderMaterial = ((city.get_node("WorldEnvironment") as WorldEnvironment).environment.sky.sky_material as ShaderMaterial)
		print("strike: light %.2f sky flash %.2f overcast %.2f" % [ts.light.light_energy, float(smat.get_shader_parameter("flash")), float(smat.get_shader_parameter("overcast"))])
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
