extends Node3D
## Dev-only: the seven kerb stall kinds (StreetStallKit) in a row, front 3/4 and from the road,
## with their triangle counts. SHOT_OUT=/tmp/stalls.png xvfb-run godot --path . res://tests/shot_stalls.tscn
func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.66, 0.76, 0.86)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(60, 30)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.53, 0.5)
	ground.material_override = gm
	add_child(ground)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var kit: Array[Dictionary] = StreetStallKit.arrays()
	var counts: PackedStringArray = PackedStringArray()
	for i: int in kit.size():
		var d: Dictionary = kit[i]
		var a: Array = []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = d["v"]
		a[Mesh.ARRAY_NORMAL] = d["n"]
		var cols: PackedColorArray = d["c"]
		for k: int in cols.size():
			cols[k] = Color(cols[k].r / StreetStallKit.PAINT_LIFT, cols[k].g / StreetStallKit.PAINT_LIFT, cols[k].b / StreetStallKit.PAINT_LIFT)
		a[Mesh.ARRAY_COLOR] = cols
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(0, mat)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(-12.0 + float(i) * 4.0, 0.0, 0.0)
		add_child(mi)
		counts.append("%d: %d tris" % [i, (d["v"] as PackedVector3Array).size() / 3])
	print("stall triangles: ", ", ".join(counts))
	# The roadside fruit carts (tools/art/make_fruit_cart.py), front (-Z) towards the camera.
	for k: int in 2:
		var cart: Node3D = (load("res://assets/models/city/shops/fruit_cart_%s.glb" % ["a", "c"][k]) as PackedScene).instantiate() as Node3D
		cart.position = Vector3(16.5 + float(k) * 3.2, 0.0, 0.0)
		cart.rotation.y = PI
		add_child(cart)
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 40
	var out: String = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "/tmp/stalls.png"
	var views: Array = [[Vector3(0.0, 3.6, 17.0), Vector3(0.0, 1.0, 0.0)], [Vector3(11.0, 2.0, 4.6), Vector3(12.0, 1.1, 0.0)],
		[Vector3(18.6, 2.2, 5.6), Vector3(18.1, 1.0, 0.0)]]
	for view: int in views.size():
		cam.position = views[view][0] as Vector3
		cam.look_at(views[view][1] as Vector3)
		for f: int in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "_%d.png" % view))
	get_tree().quit()
