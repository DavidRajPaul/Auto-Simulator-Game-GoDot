extends Node
## Dev-only: renders the living-city moments to $SHOT_DIR.
##   SHOT_LOOK "x,z" where the auto stands;  SHOT_MODE kolam | rain | shops
## Run: SHOT_MODE=kolam SHOT_LOOK=-2351,-217 SHOT_DIR=/tmp/life xvfb-run godot --path . --rendering-method gl_compatibility res://tests/shot_life.tscn
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	var mode: String = OS.get_environment("SHOT_MODE")
	GameState.shift_minute = 360.0 if mode == "kolam" else 630.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	var v: PackedStringArray = OS.get_environment("SHOT_LOOK").split(",")
	var at: Vector3 = Vector3(float(v[0]), 1.0, float(v[1]))
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, at))
	SignalBus.player_pose_updated.emit(Vector3(at.x, 0, at.z), Vector3.FORWARD)
	for i: int in 120:
		await get_tree().physics_frame
	var rig: CameraRig = city.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	var cam: Camera3D = rig.get_node("Camera") as Camera3D
	var peds: PedestrianManager = city.get_node("PedestrianManager") as PedestrianManager
	(city.get_node("AutoRickshaw") as Node3D).visible = false
	var dir: String = OS.get_environment("SHOT_DIR")
	match mode:
		"kolam":
			var spots: Array = SignalBus.street_spots("kolams", at, 90.0)
			spots.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector3).distance_to(at) < (b[0] as Vector3).distance_to(at))
			var n: int = 0
			for w: PedestrianManager.Walker in peds.people:
				if n >= mini(2, spots.size()) or not PedestrianManager.WOMEN.has(w.id):
					continue
				if peds.place_kolam(w, spots[n]):
					var c: Vector3 = spots[n][0]
					var out: Vector3 = Vector3(sin(float(spots[n][1])), 0.0, cos(float(spots[n][1])))
					var side: Vector3 = Vector3(out.z, 0.0, -out.x)
					for i: int in 50:
						await get_tree().process_frame
					cam.global_position = c + out * 2.6 + side * 2.2 + Vector3(0, 1.5, 0)
					cam.look_at(c - out * 0.5 + Vector3(0, 0.7, 0))
					for i: int in 8:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(dir.path_join("kolam_%d.png" % n))
				n += 1
		"rain":
			cam.global_position = at + Vector3(0, 2.6, 0)
			cam.look_at(at + Vector3(0, 1.2, -30.0))
			GameState.set_rain(true, 120.0)
			for k: int in 3:
				for i: int in 150:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(dir.path_join("rain_%d.png" % k))
			var roles: Dictionary = {}
			for w: PedestrianManager.Walker in peds.people:
				if w.active:
					var key: String = "umbrella" if w.umbrella else (w.role + ("+in" if w.sheltered else ""))
					roles[key] = int(roles.get(key, 0)) + 1
			print("RAIN roles ", roles, " umbrellas ", peds.umbrella_count())
		_:
			var world: WorldChunkStreamer = city.get_node("World") as WorldChunkStreamer
			for i: int in 60:
				await get_tree().process_frame
			print("SHOPS shown ", world.shop_people.shown.size())
			if not world.shop_people.shown.is_empty():
				var s: Array = world.shop_people.shown[0]
				var p: Vector3 = s[0]
				var out: Vector3 = Vector3(sin(float(s[1])), 0.0, cos(float(s[1])))
				if int(s[2]) == 1:
					out = -out
				cam.global_position = p + out * 7.0 + Vector3(out.z, 0.0, -out.x) * 3.0 + Vector3(0, 1.9, 0)
				cam.look_at(p + Vector3(0, 1.2, 0))
				for i: int in 8:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(dir.path_join("shops_0.png"))
			cam.global_position = at + Vector3(0, 2.4, 0)
			cam.look_at(at + Vector3(0, 1.4, -30.0))
			for i: int in 8:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(dir.path_join("shops_1.png"))
	get_tree().quit()
