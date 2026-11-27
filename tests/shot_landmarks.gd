extends Node
## Dev-only: renders a landmark in the real city. SHOT_X / SHOT_Z = world target,
## SHOT_OUT = png path, SHOT_MIN = clock minute, SHOT_EYE_M = distance from target,
## SHOT_BEARING = degrees from +X towards +Z to the camera, SHOT_EYE_Y / SHOT_LOOK_Y = heights.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	GameState.shift_running = false
	GameState.shift_minute = float(OS.get_environment("SHOT_MIN")) if OS.has_environment("SHOT_MIN") else 660.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	var tx: float = float(OS.get_environment("SHOT_X"))
	var tz: float = float(OS.get_environment("SHOT_Z"))
	var dist: float = float(OS.get_environment("SHOT_EYE_M")) if OS.has_environment("SHOT_EYE_M") else 60.0
	var target: Vector3 = Vector3(tx, 0.0, tz)
	var bearing: float = deg_to_rad(float(OS.get_environment("SHOT_BEARING"))) if OS.has_environment("SHOT_BEARING") else PI * 0.25
	var eye_y: float = float(OS.get_environment("SHOT_EYE_Y")) if OS.has_environment("SHOT_EYE_Y") else 1.8
	var look_y: float = float(OS.get_environment("SHOT_LOOK_Y")) if OS.has_environment("SHOT_LOOK_Y") else 8.0
	var eye: Vector3 = target + Vector3(cos(bearing) * dist, eye_y, sin(bearing) * dist)
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
	cam.look_at(target + Vector3(0, look_y, 0))
	cam.reset_physics_interpolation()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("SHOT draw calls: ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		" primitives: ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
