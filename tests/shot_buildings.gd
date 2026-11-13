extends Node
## Dev-only: street-level renders of the city's buildings with the HUD hidden.
##   SHOT_DIR   folder for the PNGs
##   SHOT_LIST  "name|x,z,cx,cy,cz;name|…": stand the camera at (cx, cy, cz) looking at (x, 3, z)
##   SHOT_MIN   shift minute (default 600 = 10 am);  SHOT_TREES=0 hides the street trees
##   SHOT_TYPED=0 renders the older generic building skin (before / after pairs)
## xvfb-run -a godot --path . --rendering-method gl_compatibility res://tests/shot_buildings.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	WorldChunkStreamer.typed_enabled = OS.get_environment("SHOT_TYPED") != "0"
	GameState.shift_minute = float(OS.get_environment("SHOT_MIN")) if OS.has_environment("SHOT_MIN") else 600.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	for n: Node in city.get_children():
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	var rig: CameraRig = city.get_node("CameraRig") as CameraRig
	var cam: Camera3D = rig.get_node("Camera") as Camera3D
	var auto: Node3D = city.get_node("AutoRickshaw") as Node3D
	var world: WorldChunkStreamer = city.get_node("World") as WorldChunkStreamer
	if OS.get_environment("SHOT_TREES") == "0":
		world.trees.visible = false
	rig.set_process(false)
	auto.visible = false
	for item: String in OS.get_environment("SHOT_LIST").split(";", false):
		var parts: PackedStringArray = item.split("|")
		var v: PackedFloat64Array = PackedFloat64Array(Array(parts[1].split(",")).map(func(t: String) -> float: return float(t)))
		SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, Vector3(v[2], 1.0, v[4])))
		SignalBus.player_pose_updated.emit(Vector3(v[2], 0.0, v[4]), Vector3.FORWARD)
		for i: int in 8:
			await get_tree().physics_frame
		world.update_streaming(true)
		for i: int in 50:
			await get_tree().physics_frame
		cam.global_position = Vector3(v[2], v[3], v[4])
		cam.look_at(Vector3(v[0], 3.0, v[1]))
		for i: int in 12:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(parts[0] + ".png"))
		print("SHOT ", parts[0], " draws ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			" prims ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	get_tree().quit()
