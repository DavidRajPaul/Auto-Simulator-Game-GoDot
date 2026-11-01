extends Node3D
## Dev-only: renders any .glb (absolute path, loaded at runtime with GLTFDocument, no import)
## from four sides: front 3/4, left side, rear 3/4, right side, stacked in a 2x2 grid.
## Run: SHOT_GLB=/abs/model.glb SHOT_OUT=/tmp/m.png xvfb-run godot --path . res://tests/shot_glb.tscn
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var doc: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if doc.append_from_file(OS.get_environment("SHOT_GLB"), state) != OK:
		push_error("cannot load " + OS.get_environment("SHOT_GLB"))
		get_tree().quit(1)
		return
	var model: Node3D = doc.generate_scene(state) as Node3D
	add_child(model)
	TrafficVehicleAI._light_beacon(model)
	var aabb: AABB = TrafficModelFit._bounds(model, self)
	var c: Vector3 = aabb.get_center()
	var r: float = aabb.size.length() * 0.75
	var cam: Camera3D = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.make_current()
	var dirs: Array[Vector3] = [Vector3(0.7, 0.35, 1.0), Vector3(-1.0, 0.2, 0.0), Vector3(-0.7, 0.35, -1.0), Vector3(1.0, 0.2, 0.0)]
	var shots: Array[Image] = []
	for d: Vector3 in dirs:
		cam.position = c + d.normalized() * r * 1.6
		cam.look_at(c)
		for i: int in 6:
			await get_tree().process_frame
		shots.append(get_viewport().get_texture().get_image())
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var out: Image = Image.create(w * 2, h * 2, false, shots[0].get_format())
	for i: int in 4:
		out.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
	out.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
