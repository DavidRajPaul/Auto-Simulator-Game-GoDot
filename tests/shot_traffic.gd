extends Node3D
## Dev-only visual check: lines up every traffic model exactly as TrafficModelFit places it
## (same footprints as TrafficVehicleAI) next to its collision box outline, side and 3/4 views.
## Run: SHOT_OUT=/tmp/t.png xvfb-run godot --path . --rendering-driver opengl3 res://tests/shot_traffic.tscn
func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(80, 40)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.35, 0.37)
	ground.material_override = gm
	add_child(ground)
	var items: Array = []
	for i: int in TrafficVehicleAI.TWO_WHEELER_VARIANTS.size():
		var v: Array = TrafficVehicleAI.TWO_WHEELER_VARIANTS[i]
		items.append([v[0], v[1] as Vector3, v[2] as bool, v[3] as bool, v[5] as Vector3])
	for v: Array in TrafficVehicleAI.SERVICE_VARIANTS:
		if (v[0] as String).contains("police"):
			items.append([v[0], v[1] as Vector3, true, true, Vector3.ZERO])
	var side: bool = OS.get_environment("SHOT_VIEW") == "side"
	var x: float = 0.0
	for it: Array in items:
		var size: Vector3 = it[1]
		var car: Node3D = Node3D.new()
		add_child(car)
		var span: float = size.z if side else size.x
		car.position = Vector3(x + span * 0.5, 0.0, 0.0)
		if side:
			car.rotation.y = PI * 0.5 # nose to -X: the camera sees the left flank
		TrafficModelFit.attach(car, it[0] as String, size, it[2] as bool, it[3] as bool)
		var seat: Vector3 = it[4]
		if seat != Vector3.ZERO and OS.get_environment("SHOT_RIDERS") != "0":
			var rider: Node3D = PersonMesh.rider_node(items.find(it))
			rider.position = seat + PersonMesh.PROCEDURAL_HIP
			car.add_child(rider)
		var box: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = size
		box.mesh = bm
		box.position.y = size.y * 0.5
		var wm: StandardMaterial3D = StandardMaterial3D.new()
		wm.albedo_color = Color(1, 0.2, 0.2, 0.07)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material_override = wm
		car.add_child(box)
		x += span + 1.2
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	if side:
		cam.position = Vector3(x * 0.5, 1.4, 9.0)
		cam.look_at(Vector3(x * 0.5, 0.8, 0.0))
	else:
		cam.position = Vector3(x * 0.5, 4.0, 7.5)
		cam.look_at(Vector3(x * 0.5, 0.7, 0.0))
	cam.fov = 60.0
	cam.make_current()
	for i: int in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
