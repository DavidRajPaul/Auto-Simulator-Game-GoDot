extends Node3D
## Dev-only: the Chennai two-wheelers and cars (tools/art/make_chennai_vehicles.py) lined up
## at a kerb in street paints, as RoadsideParking draws them (vehicle_paint.gdshader).
## Run: SHOT_OUT=/tmp/v.png xvfb-run godot --path . --rendering-method gl_compatibility res://tests/shot_chennai_vehicles.tscn
const BIKES: Array[String] = ["moped", "commuter_bike", "cruiser_bike", "bicycle"]
const CARS: Array[String] = ["hatchback", "tallboy", "micro_van", "mini_truck"]

func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.72, 0.72)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(60, 30)
	ground.mesh = pm
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.41, 0.4)
	ground.material_override = gm
	add_child(ground)
	var x: float = 0.0
	var k: int = 0
	for name: String in BIKES:
		for j: int in 3:
			_place(name, Vector3(x, 0.0, 0.0), PaintSwap.TWO_WHEELER_PAINTS[(k * 3 + 1) % PaintSwap.TWO_WHEELER_PAINTS.size()], 0.25)
			x += 0.95
			k += 1
	x = -6.0
	for name: String in CARS:
		for j: int in 2:
			_place(name, Vector3(x, 0.0, 4.2), PaintSwap.CAR_PAINTS[(k * 5) % PaintSwap.CAR_PAINTS.size()], PI * 0.5)
			x += 4.4
			k += 1
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(float(OS.get_environment("CAM_X")) if OS.has_environment("CAM_X") else 6.0, float(OS.get_environment("CAM_Y")) if OS.has_environment("CAM_Y") else 5.5, float(OS.get_environment("CAM_Z")) if OS.has_environment("CAM_Z") else -10.5)
	cam.look_at(Vector3(float(OS.get_environment("LOOK_X")) if OS.has_environment("LOOK_X") else 6.0, 0.5, float(OS.get_environment("LOOK_Z")) if OS.has_environment("LOOK_Z") else 2.6))
	cam.fov = float(OS.get_environment("CAM_FOV")) if OS.has_environment("CAM_FOV") else 66.0
	cam.make_current()
	for i: int in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()

func _place(name: String, at: Vector3, paint: Color, yaw: float) -> void:
	var path: String = "res://assets/models/traffic/chennai/%s.glb" % name
	var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	model.position = at
	model.rotation.y = yaw
	add_child(model)
	PaintSwap.prepare(model, name)
	PaintSwap.set_paint(model, paint)
