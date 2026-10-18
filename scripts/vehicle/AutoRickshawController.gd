class_name AutoRickshawController
extends RigidBody3D
## 3-Wheel Delta-Trike Raycast Physics Controller for "Namma Auto: Chennai Rickshaw Simulator 3D"

@export var base_mass_kg: float = 365.0
@export var center_of_mass_offset: Vector3 = Vector3(0.0, -0.26, 0.32)
@export var max_speed_kmh: float = 60.0
@export var reverse_max_speed_kmh: float = 16.0
@export var engine_peak_force_n: float = 4200.0
@export var service_brake_force_n: float = 5400.0
@export var handbrake_force_n: float = 7500.0
@export var max_steer_angle_deg: float = 44.0
@export var steer_response_speed: float = 7.5
@export var suspension_rest_dist_m: float = 0.34
@export var max_spring_compression_m: float = 0.22
@export var front_spring_stiffness: float = 26000.0
@export var rear_spring_stiffness: float = 34000.0
@export var spring_damping_coeff: float = 3600.0
@export var wheel_radius_m: float = 0.203
@export var front_lateral_grip: float = 5.8
@export var rear_lateral_grip: float = 6.4
@export var anti_roll_torque_strength: float = 8200.0
@export var two_wheel_tilt_min_deg: float = 11.5
@export var max_safe_roll_angle_deg: float = 19.5
@export var lpg_capacity_liters: float = 8.0
@export var lpg_burn_rate_per_km: float = 0.032
@export var horn_blast_radius_m: float = 18.0
@export var water_stall_depth_threshold_m: float = 0.28

var front_wheel_ray: RayCast3D
var rear_left_wheel_ray: RayCast3D
var rear_right_wheel_ray: RayCast3D
var current_speed_kmh: float = 0.0
var forward_speed_mps: float = 0.0
var current_steer_rad: float = 0.0
var current_lpg_liters: float = 8.0
var is_engine_stalled: bool = false
var kick_start_progress: float = 0.0
var in_waterlogged_zone: bool = false
var current_water_depth_m: float = 0.0
var is_on_two_wheels: bool = false

func _ready() -> void:
	mass = base_mass_kg
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset
	current_lpg_liters = lpg_capacity_liters
	_setup_wheel_rays()

func _setup_wheel_rays() -> void:
	var ray_len: float = suspension_rest_dist_m + wheel_radius_m + 0.15
	front_wheel_ray = _create_ray("FrontWheelRay", Vector3(0.0, 0.25, -1.05), ray_len)
	rear_left_wheel_ray = _create_ray("RearLeftWheelRay", Vector3(-0.58, 0.25, 0.88), ray_len)
	rear_right_wheel_ray = _create_ray("RearRightWheelRay", Vector3(0.58, 0.25, 0.88), ray_len)

func _create_ray(ray_name: String, pos: Vector3, length: float) -> RayCast3D:
	var r := RayCast3D.new()
	r.name = ray_name
	r.position = pos
	r.target_position = Vector3(0.0, -length, 0.0)
	r.enabled = true
	r.add_exception(self)
	add_child(r)
	return r

func _physics_process(delta: float) -> void:
	var throttle_in: float = Input.get_action_strength("ui_up")
	var brake_in: float = Input.get_action_strength("ui_down")
	var steer_in: float = Input.get_axis("ui_right", "ui_left")
	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	forward_speed_mps = linear_velocity.dot(forward_dir)
	current_speed_kmh = absf(forward_speed_mps) * 3.6

	var speed_steer_factor: float = clampf(1.0 - (current_speed_kmh / 95.0) * 0.55, 0.38, 1.0)
	var target_steer_rad: float = steer_in * deg_to_rad(max_steer_angle_deg) * speed_steer_factor
	current_steer_rad = move_toward(current_steer_rad, target_steer_rad, steer_response_speed * delta)
	front_wheel_ray.rotation.y = current_steer_rad

	_solve_wheel(front_wheel_ray, true, throttle_in, brake_in, delta)
	_solve_wheel(rear_left_wheel_ray, false, throttle_in, brake_in, delta)
	_solve_wheel(rear_right_wheel_ray, false, throttle_in, brake_in, delta)
	_apply_stabilizer()

func _solve_wheel(ray: RayCast3D, is_front: bool, throttle_in: float, brake_in: float, delta: float) -> void:
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var hit_pt: Vector3 = ray.get_collision_point()
	var hit_n: Vector3 = ray.get_collision_normal()
	var dist: float = ray.global_position.distance_to(hit_pt)
	var spring_len: float = clampf(dist - wheel_radius_m, 0.0, suspension_rest_dist_m)
	var compression: float = clampf(suspension_rest_dist_m - spring_len, 0.0, max_spring_compression_m)
	var offset: Vector3 = hit_pt - global_position
	var pt_vel: Vector3 = linear_velocity + angular_velocity.cross(offset)
	var stiffness: float = front_spring_stiffness if is_front else rear_spring_stiffness
	var spring_f: float = maxf(0.0, (compression * stiffness) - (hit_n.dot(pt_vel) * spring_damping_coeff))
	apply_force(hit_n * spring_f, offset)

	var w_right: Vector3 = ray.global_transform.basis.x.normalized()
	var w_fwd: Vector3 = -ray.global_transform.basis.z.normalized()
	var grip: float = front_lateral_grip if is_front else rear_lateral_grip
	var lat_f: float = clampf((-w_right.dot(pt_vel) * grip / maxf(delta, 0.008)) * mass * 0.04, -spring_f, spring_f)
	apply_force(w_right * lat_f, offset)

	if not is_front and not is_engine_stalled:
		var drive_f: float = 0.0
		if throttle_in > 0.01 and current_speed_kmh < max_speed_kmh:
			drive_f = throttle_in * (engine_peak_force_n * 0.5)
		elif brake_in > 0.01 and forward_speed_mps > 0.5:
			drive_f = -brake_in * (service_brake_force_n * 0.5)
		apply_force(w_fwd * drive_f, offset)

func _apply_stabilizer() -> void:
	var roll_rad: float = global_transform.basis.get_euler().z
	var abs_roll_deg: float = absf(rad_to_deg(roll_rad))
	is_on_two_wheels = (abs_roll_deg >= two_wheel_tilt_min_deg and abs_roll_deg <= max_safe_roll_angle_deg)
	if abs_roll_deg > 6.0:
		var ratio: float = clampf((abs_roll_deg - 6.0) / (max_safe_roll_angle_deg - 6.0), 0.0, 2.0)
		apply_torque(global_transform.basis.z * (-signf(roll_rad) * anti_roll_torque_strength * ratio))

func pull_hand_kick_starter() -> bool:
	if not is_engine_stalled:
		return true
	kick_start_progress += 0.38
	if kick_start_progress >= 1.0:
		is_engine_stalled = false
		kick_start_progress = 0.0
		return true
	return false
