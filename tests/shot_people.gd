extends Node3D
## Dev-only: the new people mid-walk and idle beside an existing one → $SHOT_OUT.
func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 35, 0); add_child(sun)
	var x: float = -2.4
	for spec: Array in [["woman_modern", "walk", 0.4], ["woman_modern", "idle", 0.0], ["man_casual", "walk", 1.1], ["man_casual", "idle", 0.0], ["young_man", "walk", 0.4]]:
		var n: Node3D = (load("res://assets/models/people/%s.glb" % spec[0]) as PackedScene).instantiate()
		add_child(n); n.position = Vector3(x, 0, 0); n.rotation.y = 0.5 if spec[1] == "walk" else 0.0
		var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
		ap.play(spec[1]); ap.seek(float(spec[2]), true); ap.pause()
		x += 1.2
	var cam: Camera3D = Camera3D.new(); add_child(cam); cam.position = Vector3(-1.8, 1.3, 1.7); cam.look_at(Vector3(-1.8, 1.0, 0)); cam.make_current()
	for i: int in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
