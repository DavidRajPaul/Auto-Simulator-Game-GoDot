extends Node3D
## Dev-only: every traffic / parked two-wheeler side-on and front three-quarter, one PNG each, fitted
## the way the game fits it. SHOT_DIR=/tmp/tw SHOT_RIDER=1 (seat the rider as traffic does).
func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.7, 0.78, 0.86)
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.45, 0.47)
	ground.material_override = gm
	add_child(ground)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.current = true
	var label: Label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color.BLACK)
	add_child(label)
	var dir: String = OS.get_environment("SHOT_DIR") if OS.has_environment("SHOT_DIR") else "/tmp/tw"
	DirAccess.make_dir_recursive_absolute(dir)
	var rider: bool = OS.get_environment("SHOT_RIDER") == "1"
	var n: int = 0
	for v: Array in TrafficVehicleAI.TWO_WHEELER_VARIANTS:
		n += 1
		var holders: Array[Node3D] = []
		for k: int in 2:
			var car: Node3D = Node3D.new()
			add_child(car)
			holders.append(car)
			car.position = Vector3(-1.5 if k == 0 else 1.5, 0, 0)
			car.rotation.y = PI * 0.5 if k == 0 else deg_to_rad(-35.0)
			TrafficModelFit.attach(car, v[0] as String, v[1] as Vector3, v[2] as bool, v[3] as bool)
			var key: String = PaintSwap.key_of(v[0] as String)
			if PaintSwap.prepare(car, key) > 0:
				var pal: Array[Color] = PaintSwap.vehicle_palette(key)
				PaintSwap.set_paint(car, pal[(n * 3 + k) % pal.size()])
			if rider:
				var r: Node3D = PersonMesh.rider_node(n + k)
				if r != null:
					car.add_child(r)
					r.position = (v[5] as Vector3) + PersonMesh.PROCEDURAL_HIP
		label.text = "%d. %s" % [n, (v[0] as String).get_file()]
		cam.position = Vector3(0, 1.5, float(OS.get_environment("SHOT_CAM_Z")) if OS.has_environment("SHOT_CAM_Z") else 7.2)
		cam.look_at(Vector3(0, 0.7, 0))
		for f: int in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [dir, n, (v[0] as String).get_file().get_basename()])
		for h: Node3D in holders:
			remove_child(h)
			h.free()
	get_tree().quit()
