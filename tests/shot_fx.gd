extends Node
## Dev-only: drive into a wall in the city at noon and save frames just after impact.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	GameState.shift_minute = 660.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 40:
		await get_tree().physics_frame
	var auto: AutoRickshawController = city.get_node("AutoRickshaw") as AutoRickshawController
	var fwd: Vector3 = -auto.global_basis.z
	var wall: StaticBody3D = StaticBody3D.new()
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bx: BoxShape3D = BoxShape3D.new(); bx.size = Vector3(10, 3, 0.6); cs.shape = bx; wall.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new(); var bm: BoxMesh = BoxMesh.new(); bm.size = bx.size; mi.mesh = bm; wall.add_child(mi)
	city.add_child(wall)
	wall.global_position = auto.global_position + fwd * 30.0 + Vector3(0, 1.0, 0)
	wall.look_at(wall.global_position + fwd.rotated(Vector3.UP, 0.5), Vector3.UP)
	var hit: Array[int] = [-1]
	SignalBus.player_impact.connect(func(_i: Dictionary) -> void: if hit[0] < 0: hit[0] = Engine.get_process_frames())
	Input.action_press("accelerate")
	for i: int in 400:
		await get_tree().process_frame
		if hit[0] > 0:
			var k: int = Engine.get_process_frames() - hit[0]
			if k in [3, 12, 40]:
				get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT").replace(".png", "_%d.png" % k))
			if k > 40:
				break
	get_tree().quit()
