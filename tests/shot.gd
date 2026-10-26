extends Node3D
## Dev-only visual check: renders PersonMesh riders/passengers next to a scooter into user://shot.png.
func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.6, 0.7, 0.8)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new(); pm.size = Vector2(20, 20); ground.mesh = pm
	add_child(ground)
	# Scooter with rider (same fit as traffic).
	var bike: Node3D = Node3D.new(); add_child(bike); bike.position = Vector3(-1.2, 0, 0); bike.rotation.y = PI * 0.5
	TrafficModelFit.attach(bike, "res://assets/models/traffic/two_wheeler.glb", Vector3(0.8, TrafficVehicleAI.SCOOTER_MODEL_HEIGHT_M, 2.0), false)
	var r: MeshInstance3D = MeshInstance3D.new(); r.mesh = PersonMesh.seated_rider(1); r.position = TrafficVehicleAI.RIDER_SEAT_POS; bike.add_child(r)
	var x: float = 0.6
	for s: int in 5:
		var p: MeshInstance3D = MeshInstance3D.new(); p.mesh = PersonMesh.standing(s as PersonMesh.Style, s * 3, s % 2 == 0)
		p.position = Vector3(x, 0, 0); p.rotation.y = PI; add_child(p)
		if s % 2 == 0:
			var a: MeshInstance3D = MeshInstance3D.new(); a.mesh = PersonMesh.wave_arm(s as PersonMesh.Style, s * 3)
			a.position = Vector3(0.21, 1.38, 0); a.rotation.z = -0.35; p.add_child(a)
		x += 0.75
	var cam: Camera3D = Camera3D.new(); add_child(cam)
	cam.position = Vector3(1.2, 1.6, 5.2); cam.look_at(Vector3(1.0, 0.9, 0))
	cam.make_current()
	for i: int in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
