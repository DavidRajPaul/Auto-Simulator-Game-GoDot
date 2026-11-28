extends Node3D
## Dev-only: a quest person with their QuestWear items, as QuestStory builds them, in idle and in
## mid-conversation, from the front, three-quarter, side and back → $SHOT_OUT/wear_<id>.png.
## SHOT_WEAR="model:item,item;model:item" (default: the SQ17 people with their umbrella / lanyard).

const PEOPLE: String = "res://assets/models/people/"
const PANEL: int = 360

func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.55)
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	add_child(ground)
	get_viewport().size = Vector2i(PANEL, PANEL)
	var spec: String = OS.get_environment("SHOT_WEAR")
	if spec == "":
		spec = "old_man_veshti:umbrella,towel;girl_churidar:pencil,lanyard;woman_saree_green:glass,jasmine"
	for entry: String in spec.split(";", false):
		var parts: PackedStringArray = entry.split(":")
		await _shoot(parts[0], parts[1].split(",", false) if parts.size() > 1 else PackedStringArray())
	get_tree().quit()

func _shoot(model: String, items: PackedStringArray) -> void:
	var actor: QuestActor = QuestActor.create("shot", PEOPLE + model + ".glb", 1.0, Color(0, 0, 0, 0))
	if actor == null:
		push_error("no model " + model)
		return
	actor.wear(items)
	add_child(actor)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.make_current()
	var rows: Array[String] = ["idle", "talk"]
	var dirs: Array[Vector3] = [Vector3(0, 0.15, 1), Vector3(-0.8, 0.2, 0.8), Vector3(-1, 0.1, 0), Vector3(0.3, 0.3, -1)]
	var sheet: Image = Image.create(PANEL * dirs.size(), PANEL * rows.size(), false, Image.FORMAT_RGBA8)
	for row: int in rows.size():
		actor.play(rows[row], 0.0)
		for i: int in 40:
			await get_tree().process_frame
		for v: int in dirs.size():
			var target: Vector3 = Vector3(0, 1.15, 0)
			var span: float = float(OS.get_environment("SHOT_SPAN")) if OS.get_environment("SHOT_SPAN") != "" else 4.2
			var aim_y: float = float(OS.get_environment("SHOT_AIM_Y")) if OS.get_environment("SHOT_AIM_Y") != "" else 1.15
			target = Vector3(0, aim_y, 0)
			cam.look_at_from_position(target + dirs[v].normalized() * span, target)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, PANEL, PANEL), Vector2i(v * PANEL, row * PANEL))
	var out: String = OS.get_environment("SHOT_OUT")
	sheet.save_png(out.path_join("wear_%s.png" % model))
	print("shot wear_", model)
	actor.queue_free()
	cam.queue_free()
	await get_tree().process_frame
