extends Node
## Dev-only: renders the first-ride tutorial (mentor card + spotlight, STOP line) to
## $SHOT_OUT_<n>.png. Run under xvfb with the compatibility renderer.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	await _frames(60)
	var dir: TutorialDirector = city.get_node("TutorialDirector") as TutorialDirector
	var out: String = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "user://tutorial"
	TranslationServer.set_locale(OS.get_environment("SHOT_LANG") if OS.has_environment("SHOT_LANG") else "en")
	dir.start(0)
	await _frames(40)
	await _save(out + "_1_kick.png")
	dir.start(2) # steer & brake: STOP line ahead
	await _frames(40)
	# Roll up to 25 m short of the line so it fills the frame.
	var mp: Vector3 = dir.marker_position()
	SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(dir._marker_fwd, Vector3.UP), mp - dir._marker_fwd * 25.0 + Vector3(0, 0.8, 0)))
	await _frames(60)
	await _save(out + "_2_stopline.png")
	dir.start(4) # horn with a scooter ahead
	await _frames(40)
	await _save(out + "_3_horn.png")
	get_tree().quit()

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
