extends Node3D
## Dev-only: renders a landmark GLB (tools/art/make_landmarks.py) from several sides, read straight
## from disk (no import needed). SHOT_GLB = file path, SHOT_DIR = output folder, SHOT_VIEWS =
## "name:yaw_deg:pitch_deg:dist:target_x:target_y:target_z;..." in model space (yaw 0 looks along +x).

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.56, 0.72, 0.9)
	env.environment.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.5, 0.48)
	ground.material_override = gm
	add_child(ground)
	var path: String = OS.get_environment("SHOT_GLB")
	var doc: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot read " + path)
		get_tree().quit(1)
		return
	var model: Node = doc.generate_scene(state)
	add_child(model)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	var cam: Camera3D = Camera3D.new()
	cam.fov = 45
	cam.far = 2000.0
	add_child(cam)
	cam.current = true
	var dir: String = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	for spec: String in OS.get_environment("SHOT_VIEWS").split(";", false):
		var f: PackedStringArray = spec.split(":")
		var yaw: float = deg_to_rad(float(f[1]))
		var pitch: float = deg_to_rad(float(f[2]))
		var dist: float = float(f[3])
		var target: Vector3 = Vector3(float(f[4]), float(f[5]), float(f[6]))
		var back: Vector3 = Vector3(-cos(yaw) * cos(pitch), sin(pitch), -sin(yaw) * cos(pitch))
		cam.global_position = target + back * dist
		cam.look_at(target)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join(f[0] + ".png"))
	get_tree().quit()
