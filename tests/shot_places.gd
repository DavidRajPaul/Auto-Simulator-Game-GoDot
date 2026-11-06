extends Node
## Dev-only: renders each quest place model in a row, or the real music shop in the city.
## PLACE_OUT = png path, PLACE_MIN = clock minute.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	GameState.shift_running = false
	GameState.shift_minute = float(OS.get_environment("PLACE_MIN")) if OS.has_environment("PLACE_MIN") else 660.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	var places: QuestPlaces = city.get_node("QuestPlaces") as QuestPlaces
	var key: String = OS.get_environment("PLACE_KEY") if OS.has_environment("PLACE_KEY") else "SQ03_P_SHOP"
	var at: Transform3D = Transform3D.IDENTITY
	for place: Dictionary in places.places:
		if str(place["key"]) == key:
			at = (place["node"] as Node3D).global_transform
	var eye: Vector3 = at.origin + at.basis.z * 7.0 + at.basis.x * 2.2 + Vector3(0, 1.8, 0)
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, Vector3(eye.x, 1.0, eye.z)))
	SignalBus.player_pose_updated.emit(Vector3(eye.x, 0, eye.z), Vector3.FORWARD)
	for i: int in 120:
		await get_tree().physics_frame
	var rig: CameraRig = city.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	(city.get_node("AutoRickshaw") as Node3D).visible = false
	for node: Node in city.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	var cam: Camera3D = rig.get_node("Camera") as Camera3D
	cam.global_position = eye
	cam.look_at(at.origin + Vector3(0, 1.7, 0))
	places._process(1.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("PLACE_OUT") if OS.has_environment("PLACE_OUT") else "/tmp/place.png")
	get_tree().quit()
