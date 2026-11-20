extends Node3D
## Dev-only: close-ups of every person model's face and hands → $SHOT_DIR/<id>.png.
## One image per model: full body, face, left hand, right hand; rows idle, mid-"talk", mid-"walk"
## (the walk row's body view is from the side). SHOT_ONLY=id,id limits the models; SHOT_GLB=res://path.glb renders one extra file.

const DIR := "res://assets/models/people/"
const PANEL := 360


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
	get_viewport().size = Vector2i(PANEL, PANEL)
	var out_dir: String = OS.get_environment("SHOT_DIR")
	var only: PackedStringArray = OS.get_environment("SHOT_ONLY").split(",", false)
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(DIR):
		if f.ends_with(".glb") and f != "shop_people.glb":
			if only.is_empty() or only.has(f.get_basename()):
				files.append(DIR + f)
	for sub: String in ["quest/", "riders/"]:
		if DirAccess.dir_exists_absolute(DIR + sub):
			for f: String in DirAccess.get_files_at(DIR + sub):
				if f.ends_with(".glb") and (only.is_empty() or only.has(f.get_basename())):
					files.append(DIR + sub + f)
	var extra: String = OS.get_environment("SHOT_GLB")
	if extra != "":
		files = [extra]
	for path: String in files:
		await _shoot(path, out_dir)
	get_tree().quit()


func _shoot(path: String, out_dir: String) -> void:
	var n: Node3D = (load(path) as PackedScene).instantiate()
	add_child(n)
	var ap: AnimationPlayer = null
	var aps: Array[Node] = n.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		ap = aps[0]
	var sk: Skeleton3D = null
	var sks: Array[Node] = n.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		sk = sks[0]
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.make_current()
	var rows: Array[String] = ["idle", "talk", "walk"]
	var sheet: Image = Image.create(PANEL * 4, PANEL * rows.size(), false, Image.FORMAT_RGBA8)
	for row: int in rows.size():
		var clip: String = _pick(ap, rows[row])
		if ap != null and clip != "":
			ap.play(clip)
			ap.seek([0.3, 1.2, 0.35][row], true)
			ap.pause()
		for i: int in 3:
			await get_tree().process_frame
		var aabb: AABB = _bounds(n)
		var top: float = aabb.end.y
		var head: Vector3 = _bone(sk, n, ["Head", "head", "CC_Base_Head"], Vector3(0, top - 0.12, 0))
		var lh: Vector3 = _bone(sk, n, ["LeftHand", "mixamorig_LeftHand", "CC_Base_L_Hand"], Vector3(0.3, 0.8, 0))
		var rh: Vector3 = _bone(sk, n, ["RightHand", "mixamorig_RightHand", "CC_Base_R_Hand"], Vector3(-0.3, 0.8, 0))
		var views: Array = [
			[Vector3(0, aabb.get_center().y, 0), aabb.size.y * 1.2, Vector3(1, 0.1, 0.25) if row == 2 else Vector3(0.3, 0.1, 1)],
			[head + Vector3(0, 0.04, 0), 0.32, Vector3(0.15, 0.05, 1)],
			[lh, 0.32, Vector3(0.6, 0.1, 1)],
			[rh, 0.32, Vector3(-0.6, 0.1, 1)],
		]
		for v: int in views.size():
			var target: Vector3 = views[v][0]
			var span: float = views[v][1]
			var dir: Vector3 = (views[v][2] as Vector3).normalized()
			cam.fov = 30.0
			var dist: float = span * 0.5 / tan(deg_to_rad(cam.fov * 0.5))
			cam.position = target + dir * dist
			cam.look_at(target)
			cam.near = 0.02
			for i: int in 3:
				await get_tree().process_frame
			var img: Image = get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, PANEL, PANEL), Vector2i(v * PANEL, row * PANEL))
	sheet.save_png(out_dir.path_join(path.get_file().get_basename() + ".png"))
	n.queue_free()
	cam.queue_free()
	await get_tree().process_frame


func _pick(ap: AnimationPlayer, want: String) -> String:
	if ap == null:
		return ""
	var list: PackedStringArray = ap.get_animation_list()
	for name: String in list:
		if name == want:
			return name
	for name: String in list:
		if name.begins_with(want) or (want == "idle" and (name.begins_with("sit") or name == "idle")):
			return name
	return list[0] if list.size() > 0 else ""


func _bone(sk: Skeleton3D, root: Node3D, names: Array[String], fallback: Vector3) -> Vector3:
	if sk == null:
		return fallback
	for b: String in names:
		var i: int = sk.find_bone(b)
		if i >= 0:
			return sk.global_transform * sk.get_bone_global_pose(i).origin
	return fallback


func _bounds(root: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
