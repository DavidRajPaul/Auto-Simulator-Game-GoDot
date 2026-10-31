extends Node3D
## Dev-only visual check: every GameState.PAINTS entry on the real player auto, side by side.
## Run: SHOT_VIEW=side|rear SHOT_OUT=/tmp/p.png xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_paint.tscn
func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(60, 30)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.35, 0.37)
	ground.material_override = gm
	add_child(ground)
	var rear: bool = OS.get_environment("SHOT_VIEW") == "rear"
	var x: float = 0.0
	for p: Dictionary in GameState.PAINTS:
		var auto: AutoRickshawModel = AutoRickshawModel.new()
		auto.paint = p["body"] as Color
		auto.trim = p["canopy"] as Color
		auto.position = Vector3(x, -AutoRickshawModel.GROUND_Y, 0.0)
		auto.rotation.y = PI * 0.5 if not rear else PI * 0.82
		add_child(auto)
		x += 3.2
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.position = Vector3((x - 3.2) * 0.5, 2.6, 9.5)
	cam.look_at(Vector3((x - 3.2) * 0.5, 0.9, 0.0))
	cam.make_current()
	for i: int in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
