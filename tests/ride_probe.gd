extends Node
## Ride-smoothness probe: drives the city scene straight and through a turn, measures
## frame-to-frame body jerk (pitch/roll rate change and vertical accel). Lower = smoother.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	var auto: AutoRickshawController = city.get_node("AutoRickshaw") as AutoRickshawController
	for i: int in 120:
		await get_tree().physics_frame
	var r: Dictionary = await _measure(auto, 0.0, 300)
	print("RIDE straight: ", r)
	r = await _measure(auto, 0.5, 180)
	print("RIDE turning: ", r)
	Input.action_release("accelerate"); Input.action_release("steer_left")
	get_tree().quit(0)

func _measure(auto: AutoRickshawController, steer: float, frames: int) -> Dictionary:
	Input.action_press("accelerate")
	if steer > 0.0:
		Input.action_press("steer_left", steer)
	var prev_w: Vector3 = auto.angular_velocity
	var prev_vy: float = auto.linear_velocity.y
	var jerk_sum: float = 0.0
	var vy_sum: float = 0.0
	var max_jerk: float = 0.0
	for i: int in frames:
		await get_tree().physics_frame
		var b: Basis = auto.global_transform.basis
		var w: Vector3 = auto.angular_velocity
		var dw: Vector3 = w - prev_w
		var pr: float = Vector2(dw.dot(b.x), dw.dot(b.z)).length() # pitch+roll rate change
		jerk_sum += pr
		max_jerk = maxf(max_jerk, pr)
		if pr > 0.2 and OS.has_environment("RIDE_VERBOSE"):
			print("  spike f=%d pr=%.3f grounded=%d roll=%.1f kmh=%.1f" % [i, pr, auto.wheels_grounded, auto.current_roll_deg, auto.current_speed_kmh])
		vy_sum += absf(auto.linear_velocity.y - prev_vy)
		prev_w = w
		prev_vy = auto.linear_velocity.y
	return {"mean_pr_jerk": snappedf(jerk_sum / frames, 0.0001), "max_pr_jerk": snappedf(max_jerk, 0.001), "mean_dvy": snappedf(vy_sum / frames, 0.0001), "kmh": snappedf(auto.current_speed_kmh, 0.1)}
