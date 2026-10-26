extends Node
## Collision feel probe (greybox): drives into a wall head-on, a wall at 35°, and a stopped
## AI car. Prints peak spin, roll, rebound and whether the auto flipped or got stuck.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	for scenario: String in ["wall_head_on", "wall_glancing", "ai_rear_end", "ai_side_swipe"]:
		var main: Node = (load("res://scenes/main_phase1_greybox.tscn") as PackedScene).instantiate()
		add_child(main)
		var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
		var traffic: ChennaiTrafficManager = main.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
		for v: TrafficVehicleAI in traffic.pool:
			v.deactivate()
		traffic.set_physics_process(false)
		await _phys(30)
		var fwd: Vector3 = -auto.global_basis.z
		var hits: Array[float] = []
		SignalBus.player_collision.connect(func(i: float) -> void: hits.append(i))
		if scenario.begins_with("wall"):
			var wall: StaticBody3D = StaticBody3D.new()
			var cs: CollisionShape3D = CollisionShape3D.new()
			var bx: BoxShape3D = BoxShape3D.new(); bx.size = Vector3(14, 4, 1)
			cs.shape = bx; wall.add_child(cs); main.add_child(wall)
			wall.global_position = auto.global_position + fwd * 40.0 + Vector3(0, 1.5, 0)
			wall.look_at(wall.global_position + fwd.rotated(Vector3.UP, deg_to_rad(35.0 if scenario == "wall_glancing" else 0.0)), Vector3.UP)
		elif scenario == "ai_side_swipe":
			# AI overtakes the stopped player and shifts lane into it.
			var v: TrafficVehicleAI = traffic.pool[6]
			traffic.set_physics_process(true)
			var c: Dictionary = traffic.graph.closest_point(auto.global_position - fwd * 30.0)
			traffic.place_vehicle(v, int(c["edge"]), float(c["s"]), -1, 2)
			v.cruise_speed_mps = 9.0; v.current_speed_mps = 9.0
			_swipe = v
		else:
			var v: TrafficVehicleAI = traffic.pool[6]
			traffic.set_physics_process(true)
			var c: Dictionary = traffic.graph.closest_point(auto.global_position + fwd * 40.0)
			traffic.place_vehicle(v, int(c["edge"]), float(c["s"]), -1, 1)
			v.cruise_speed_mps = 0.0; v.current_speed_mps = 0.0
			v.global_position = auto.global_position + fwd * 40.0
		if scenario != "ai_side_swipe":
			Input.action_press("accelerate")
		var first_hit: int = -1
		var slide: float = -1.0
		var push: float = 0.0
		var max_w: float = 0.0; var max_roll: float = 0.0; var min_fwd: float = 99.0; var max_up: float = 0.0
		for i: int in 420:
			await get_tree().physics_frame
			max_w = maxf(max_w, auto.angular_velocity.length())
			max_roll = maxf(max_roll, auto.current_roll_deg)
			min_fwd = minf(min_fwd, auto.forward_speed_mps)
			max_up = maxf(max_up, auto.linear_velocity.y)
			if first_hit < 0 and not hits.is_empty():
				first_hit = i
			if first_hit >= 0 and i == first_hit + 30:
				slide = Vector2(auto.linear_velocity.x, auto.linear_velocity.z).length()
			if scenario == "ai_side_swipe":
				push = maxf(push, Vector2(auto.linear_velocity.x, auto.linear_velocity.z).length())
				if _swipe != null and i == 40:
					_swipe.sub_lane = 0
			if i == 200:
				Input.action_release("accelerate")
		var up_dot: float = auto.global_basis.y.dot(Vector3.UP)
		print("COLL %s: peak_spin=%.2f rad/s roll=%.1f° rebound=%.1f m/s up_vel=%.2f flipped=%s slide_after=%.1f push=%.1f hits=%s" % [scenario, max_w, max_roll, -minf(min_fwd, 0.0), max_up, up_dot < 0.5, slide, push, str(hits.slice(0, 4))])
		main.queue_free()
		await _phys(3)
	get_tree().quit()

var _swipe: TrafficVehicleAI

func _phys(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
