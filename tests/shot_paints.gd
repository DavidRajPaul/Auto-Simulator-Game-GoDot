extends Node3D
## Dev-only: lines up PaintSwap variants (NPC autos, two-wheelers, sarees, dresses) to check
## the recolours. Run: SHOT_OUT=/tmp/p.png xvfb-run godot --path . res://tests/shot_paints.tscn
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 25, 0)
	add_child(sun)
	var rows: Array = [
		["res://assets/models/traffic/share_auto.glb", Vector3(1.5, 1.8, 2.9), [PaintSwap.NO_PAINT, PaintSwap.AUTO_ELECTRIC[0], PaintSwap.AUTO_ELECTRIC[1], PaintSwap.AUTO_PINK]],
		["res://assets/models/traffic/two_wheeler.glb", Vector3(0.8, 1.0, 2.0), PaintSwap.TWO_WHEELER_PAINTS.slice(0, 7)],
		["res://assets/models/traffic/two_wheeler_pack/sport_bike_0.glb", Vector3(0.8, 1.0, 2.0), PaintSwap.TWO_WHEELER_PAINTS.slice(0, 7)],
		["res://assets/models/people/waiting/woman_saree_green_stand.glb", Vector3(0.6, 1.6, 0.5), PaintSwap.SAREE_PAINTS.slice(0, 7)],
		["res://assets/models/people/waiting/man_casual_stand.glb", Vector3(0.6, 1.7, 0.5), PaintSwap.DRESS_PAINTS.slice(0, 7)],
		["res://assets/models/people/waiting/girl_churidar_stand.glb", Vector3(0.6, 1.6, 0.5), PaintSwap.DRESS_PAINTS.slice(3, 10)],
	]
	var z: float = 0.0
	for r: Array in rows:
		var path: String = r[0]
		var key: String = path.get_file().get_basename().trim_suffix("_stand")
		var paints: Array = r[2]
		var size: Vector3 = r[1]
		var person: bool = path.contains("/people/")
		for i: int in paints.size():
			var holder: Node3D = Node3D.new()
			holder.position = Vector3(i * 2.6, 0.0, z)
			add_child(holder)
			if person:
				var n: Node3D = (load(path) as PackedScene).instantiate() as Node3D
				n.position.y = 0.85
				n.rotation.y = 0.5
				holder.add_child(n)
			else:
				TrafficModelFit.attach(holder, path, size, true, path.contains("two_wheeler_pack"))
				holder.rotation.y = -0.9
			PaintSwap.prepare(holder, key)
			PaintSwap.set_paint(holder, paints[i] as Color)
		z += 3.2
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(7.8, 9.5, z + 6.0)
	add_child(cam)
	cam.look_at(Vector3(7.8, 0.6, z * 0.5 - 0.5))
	cam.fov = 50.0
	cam.make_current()
	for i: int in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
