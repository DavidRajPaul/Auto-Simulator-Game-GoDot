extends Node3D
## Dev-only: every StreetTrees species standing in a row, drawn by StreetTrees itself (near models,
## then the same row from far away as impostor cards), to check a re-bake (bake_trees.py,
## bake_cc_trees.py). SHOT_NEAR_M / SHOT_FAR_M move the cameras (e.g. 50 / 70 to compare a model with its
## card at the fade band); SHOT_TREES=new shows only the CC BY trees. Run: SHOT_OUT=/tmp/trees.png xvfb-run godot --path . res://tests/shot_trees.tscn
const GAP_M: float = 11.0
const PER_SHOT: int = 4

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.88)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	ground.mesh = plane
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.5, 0.42)
	ground.material_override = gm
	add_child(ground)
	var trees: StreetTrees = StreetTrees.new()
	add_child(trees)
	trees.remap_enabled = false
	var codes: Array[int] = []
	for c: int in trees.species:
		codes.append(c)
	codes.sort()
	var only: String = OS.get_environment("SHOT_TREES")
	if only == "new":
		codes = codes.filter(func(c: int) -> bool: return bool((trees.species[c] as Dictionary).get("cutout", false)))
	var rec: PackedFloat32Array = PackedFloat32Array()
	for i: int in codes.size():
		rec.append_array(PackedFloat32Array([float(i) * GAP_M, 0.0, 0.0, float(codes[i]), 1.0, 0.6, 1.0, 1.0, 1.0]))
	trees.add_chunk(Vector2i.ZERO, rec)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	var shots: Array[Image] = []
	for first: int in range(0, codes.size(), PER_SHOT):
		var last: int = mini(first + PER_SHOT, codes.size()) - 1
		var mid: float = (float(first + last) * 0.5) * GAP_M
		cam.position = Vector3(mid, 4.0, float(OS.get_environment("SHOT_NEAR_M")) if OS.has_environment("SHOT_NEAR_M") else 26.0)
		cam.look_at(Vector3(mid, 4.5, 0.0))
		shots.append(await _grab(trees, cam))
	# The same trees as cards: far enough that every one is past the fade band.
	var mid_all: float = float(codes.size() - 1) * 0.5 * GAP_M
	var far_m: float = float(OS.get_environment("SHOT_FAR_M")) if OS.has_environment("SHOT_FAR_M") else 290.0
	cam.fov = 22.0 * 290.0 / far_m
	cam.position = Vector3(mid_all, 8.0, far_m)
	cam.look_at(Vector3(mid_all, 5.0, 0.0))
	shots.append(await _grab(trees, cam))
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var cols: int = 2
	var rows: int = (shots.size() + 1) / 2
	var out: Image = Image.create(w * cols, h * rows, false, shots[0].get_format())
	for i: int in shots.size():
		out.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	out.save_png(OS.get_environment("SHOT_OUT"))
	print("trees: ", codes, " near species ", trees.near_species)
	get_tree().quit()

func _grab(trees: StreetTrees, cam: Camera3D) -> Image:
	for i: int in 8:
		trees.update(cam.global_position)
		await get_tree().process_frame
	return get_viewport().get_texture().get_image()
