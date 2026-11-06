extends Node
## Dev-only: renders the sky through the day into one contact sheet per direction.
## SKY_OUT = folder, SKY_ONE=1 for noon only, SKY_POS = "x,z" camera spot, SKY_RAIN=1 for monsoon, SKY_DAY = day number.
const ALL_MINUTES: Array[float] = [330.0, 360.0, 400.0, 480.0, 720.0, 960.0, 1050.0, 1095.0, 1110.0, 1125.0, 1140.0, 1165.0, 1260.0]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	GameState.shift_running = false
	GameState.day = int(OS.get_environment("SKY_DAY")) if OS.has_environment("SKY_DAY") else 3
	var out: String = OS.get_environment("SKY_OUT") if OS.has_environment("SKY_OUT") else "/tmp"
	var rain: float = float(OS.get_environment("SKY_RAIN")) if OS.has_environment("SKY_RAIN") else 0.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	var rig: CameraRig = city.get_node("CameraRig") as CameraRig
	var atmo: Atmosphere = city.get_node("Atmosphere") as Atmosphere
	atmo.set_process(false)
	var spot: PackedStringArray = (OS.get_environment("SKY_POS") if OS.has_environment("SKY_POS") else "2020,1000").split(",")
	var at: Vector3 = Vector3(float(spot[0]), float(OS.get_environment("SKY_Y")) if OS.has_environment("SKY_Y") else 6.0, float(spot[1]))
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, Vector3(at.x, 1.0, at.z)))
	SignalBus.player_pose_updated.emit(Vector3(at.x, 0, at.z), Vector3.FORWARD)
	for i: int in 60:
		await get_tree().physics_frame
	rig.set_process(false)
	var cam: Camera3D = rig.get_node("Camera") as Camera3D
	cam.fov = 70.0
	(city.get_node("AutoRickshaw") as Node3D).visible = false
	for layer: Node in get_tree().get_nodes_in_group("hud"):
		layer.set("visible", false)
	for node: Node in city.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	if OS.has_environment("SKY_SUN"):
		# Follow the sun and moon: each shot looks straight at them.
		cam.fov = 75.0
		for minute: float in [375.0, 720.0, 1080.0, 1100.0, 1112.0, 1200.0, 1290.0]:
			GameState.shift_minute = minute
			atmo.apply(minute, 0.0)
			var look: Vector3 = (atmo._sky.get_shader_parameter("moon_dir") if minute >= 1200.0 else atmo._sky.get_shader_parameter("sun_dir")) as Vector3
			look.y = maxf(look.y, 0.1)
			cam.global_position = at
			cam.look_at(at + look)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/sun_%04d.png" % [out, int(minute)])
		get_tree().quit()
		return
	for dir: Array in [["west", Vector3(-1, 0.32, 0.25)], ["east", Vector3(1, 0.32, 0.25)]]:
		for minute: float in ([720.0] if OS.has_environment("SKY_ONE") else ALL_MINUTES):
			GameState.shift_minute = minute
			atmo.apply(minute, rain)
			atmo._sun_dir = atmo._sun_target
			cam.global_position = at
			cam.look_at(at + (dir[1] as Vector3))
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/sky_%s_%04d.png" % [out, str(dir[0]), int(minute)])
	get_tree().quit()
