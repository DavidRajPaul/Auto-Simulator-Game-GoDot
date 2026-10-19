class_name AutoRickshawController
extends RigidBody3D
## 3-wheel delta-trike raycast vehicle (1 steerable front wheel, 2 rear drive wheels).
## All tunables come from `stats` (VehicleStats .tres). Input is read from the InputMap,
## so keyboard, the TouchHUD and the headless tests all drive it the same way.

const TELEMETRY_INTERVAL_S: float = 0.1
const STALL_MAX_SPEED_KMH: float = 12.0
const GETHU_MIN_SPEED_KMH: float = 20.0
const GETHU_BONUS_INR: int = 15

@export var stats: VehicleStats
## Use the player's garage loadout from GameState (off = use `stats` as-is, e.g. demos).
@export var use_player_profile: bool = true
## Kick-start needs a steady rhythm (main game). Off in the greybox/test arena.
@export var kick_rhythm_enabled: bool = false

## Wheel ray origins sit below the chassis origin so the origin (and the CoM offset from
## VehicleStats) ends up ~0.55 m above the road, like a real loaded auto.
const FRONT_WHEEL_POS: Vector3 = Vector3(0.0, -0.3, -1.05)
const REAR_LEFT_WHEEL_POS: Vector3 = Vector3(-0.58, -0.3, 0.88)
const REAR_RIGHT_WHEEL_POS: Vector3 = Vector3(0.58, -0.3, 0.88)

var front_wheel_ray: RayCast3D
var rear_left_wheel_ray: RayCast3D
var rear_right_wheel_ray: RayCast3D

var current_speed_kmh: float = 0.0
var forward_speed_mps: float = 0.0
var current_steer_rad: float = 0.0
var current_roll_deg: float = 0.0
var fuel_level: float = 0.0
var odometer_km: float = 0.0
var is_engine_stalled: bool = false
var kick_start_pulls: int = 0
var current_water_depth_m: float = 0.0
var is_on_two_wheels: bool = false
var passenger_count: int = 0
var luggage_kg: float = 0.0
var wheels_grounded: int = 0

## Gears: the Bajaj RE has a separate reverse gear. +1 drive, -1 reverse.
const GEAR_DRIVE: int = 1
const GEAR_REVERSE: int = -1
const GEAR_SHIFT_MAX_KMH: float = 4.0
## Holding BRAKE while stopped this long engages reverse (when the auto-reverse setting is on).
const AUTO_REVERSE_HOLD_S: float = 0.6
const INDICATOR_BLINK_HZ: float = 1.5
## A turn of this much heading change, followed by straightening up, cancels the indicator.
const INDICATOR_CANCEL_TURN_RAD: float = 0.9
const KICK_RHYTHM_MIN_S: float = 0.3
const KICK_RHYTHM_MAX_S: float = 1.4

var gear: int = GEAR_DRIVE
var indicator: int = 0 # -1 left, 0 off, +1 right
var indicator_lamp_on: bool = false
var is_braking: bool = false
var _brake_hold_s: float = 0.0
var _auto_reversed: bool = false
var _blink_t: float = 0.0
var _indicator_start_yaw: float = 0.0
var _indicator_turned: bool = false
var _brake_lamps: MeshInstance3D
var _indicator_lamps: Array[MeshInstance3D] = [] # [left, right]
var _last_kick_s: float = -10.0
var _clock_s: float = 0.0 # physics time (deterministic under --fixed-fps)
var _telemetry_timer: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _wheel_visuals: Dictionary = {}

func _ready() -> void:
	if use_player_profile:
		stats = GameState.active_stats()
	if stats == null:
		stats = VehicleStats.new()
	add_to_group("player_auto")
	fuel_level = stats.fuel_capacity if GameState.fuel_level < 0.0 or not use_player_profile else minf(GameState.fuel_level, stats.fuel_capacity)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_apply_mass()
	_setup_wheel_rays()
	SignalBus.water_depth_changed.connect(_on_water_depth_changed)
	SignalBus.passenger_boarded.connect(_on_passenger_boarded)
	SignalBus.passenger_alighted.connect(_on_passenger_alighted)
	SignalBus.refueled.connect(func(level: float) -> void: fuel_level = minf(level, stats.fuel_capacity))
	SignalBus.teleport_requested.connect(func(xform: Transform3D) -> void:
		global_transform = xform
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_prev_velocity = Vector3.ZERO)
	if use_player_profile:
		SignalBus.vehicle_loadout_changed.connect(apply_stats)
	_recolour.call_deferred()
	_build_lamps()

## Swap to new effective stats at runtime (garage purchase/upgrade/paint).
func apply_stats(new_stats: VehicleStats) -> void:
	stats = new_stats
	fuel_level = minf(fuel_level, stats.fuel_capacity)
	_apply_mass()
	_recolour()

func _recolour() -> void:
	var model: AutoRickshawModel = get_node_or_null("Model") as AutoRickshawModel
	if model != null and (model.paint != stats.body_colour or model.trim != stats.canopy_colour):
		model.paint = stats.body_colour
		model.trim = stats.canopy_colour
		model.build()

func _setup_wheel_rays() -> void:
	var ray_len: float = stats.suspension_rest_dist_m + stats.wheel_radius_m + 0.15
	front_wheel_ray = _create_ray("FrontWheelRay", FRONT_WHEEL_POS, ray_len)
	rear_left_wheel_ray = _create_ray("RearLeftWheelRay", REAR_LEFT_WHEEL_POS, ray_len)
	rear_right_wheel_ray = _create_ray("RearRightWheelRay", REAR_RIGHT_WHEEL_POS, ray_len)
	# Optional visual wheels inside this prefab (local children only).
	for wheel_name: String in ["FrontWheelMesh", "RearLeftWheelMesh", "RearRightWheelMesh"]:
		var n: Node3D = get_node_or_null(wheel_name) as Node3D
		if n != null:
			_wheel_visuals[wheel_name] = n

func _create_ray(ray_name: String, pos: Vector3, length: float) -> RayCast3D:
	var r: RayCast3D = RayCast3D.new()
	r.name = ray_name
	r.position = pos
	r.target_position = Vector3(0.0, -length, 0.0)
	r.collision_mask = 1 # Environment_Roads only
	r.add_exception(self)
	add_child(r)
	return r

func _apply_mass() -> void:
	var load_kg: float = passenger_count * stats.passenger_mass_kg + luggage_kg
	mass = stats.base_mass_kg + load_kg
	# Rear bench sits behind the CoM, so load pushes it further back and slightly up.
	var shift: Vector3 = Vector3(0.0, 0.08, 0.35) * (load_kg / maxf(mass, 1.0))
	center_of_mass = stats.center_of_mass_offset + shift

func _physics_process(delta: float) -> void:
	_clock_s += delta
	var throttle_in: float = Input.get_action_strength("accelerate")
	var brake_in: float = Input.get_action_strength("brake")
	var steer_in: float = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var handbrake_on: bool = Input.is_action_pressed("handbrake")

	if Input.is_action_just_pressed("horn"):
		blow_horn()
	if Input.is_action_just_pressed("kick_start"):
		pull_hand_kick_starter()
	if Input.is_action_just_pressed("gear_toggle"):
		set_gear(GEAR_REVERSE if gear == GEAR_DRIVE else GEAR_DRIVE)
	if Input.is_action_just_pressed("indicator_left"):
		set_indicator(0 if indicator == -1 else -1)
	if Input.is_action_just_pressed("indicator_right"):
		set_indicator(0 if indicator == 1 else 1)
	_auto_gear(throttle_in, brake_in, delta)
	if gear == GEAR_REVERSE and _auto_reversed:
		var tmp: float = throttle_in # auto-reverse: BRAKE pedal drives backwards, ACCEL brakes
		throttle_in = brake_in
		brake_in = tmp

	if fuel_level <= 0.0:
		throttle_in = 0.0

	var forward_dir: Vector3 = -global_transform.basis.z
	forward_speed_mps = linear_velocity.dot(forward_dir)
	current_speed_kmh = absf(forward_speed_mps) * 3.6

	var speed_steer_factor: float = clampf(1.0 - (current_speed_kmh / 95.0) * 0.55, 0.38, 1.0)
	var target_steer: float = steer_in * deg_to_rad(stats.max_steer_angle_deg) * speed_steer_factor
	current_steer_rad = move_toward(current_steer_rad, target_steer, stats.steer_response_speed * delta)
	front_wheel_ray.rotation.y = current_steer_rad

	wheels_grounded = 0
	_solve_wheel(front_wheel_ray, true, throttle_in, brake_in, handbrake_on, delta)
	_solve_wheel(rear_left_wheel_ray, false, throttle_in, brake_in, handbrake_on, delta)
	_solve_wheel(rear_right_wheel_ray, false, throttle_in, brake_in, handbrake_on, delta)
	_apply_stabilizer()
	_apply_aero_drag()
	_update_fuel_and_odometer(delta)
	_check_water_stall()
	_update_lamps(brake_in, delta)
	_emit_telemetry(delta)

func _solve_wheel(ray: RayCast3D, is_front: bool, throttle_in: float, brake_in: float, handbrake_on: bool, delta: float) -> void:
	ray.force_raycast_update()
	var visual_name: String = "FrontWheelMesh" if is_front else ("RearLeftWheelMesh" if ray == rear_left_wheel_ray else "RearRightWheelMesh")
	if not ray.is_colliding():
		_place_wheel_visual(visual_name, ray, stats.suspension_rest_dist_m)
		return
	wheels_grounded += 1
	var hit_pt: Vector3 = ray.get_collision_point()
	var hit_n: Vector3 = ray.get_collision_normal()
	var dist: float = ray.global_position.distance_to(hit_pt)
	var spring_len: float = clampf(dist - stats.wheel_radius_m, 0.0, stats.suspension_rest_dist_m)
	var compression: float = clampf(stats.suspension_rest_dist_m - spring_len, 0.0, stats.max_spring_compression_m)
	_place_wheel_visual(visual_name, ray, spring_len)

	var offset: Vector3 = hit_pt - global_position
	var pt_vel: Vector3 = linear_velocity + angular_velocity.cross(offset)
	var stiffness: float = stats.front_spring_stiffness if is_front else stats.rear_spring_stiffness
	var spring_f: float = maxf(0.0, compression * stiffness - hit_n.dot(pt_vel) * stats.spring_damping_coeff)
	apply_force(hit_n * spring_f, offset)

	# Lateral tyre grip, capped by the normal load on this wheel.
	var w_right: Vector3 = ray.global_transform.basis.x
	var w_fwd: Vector3 = -ray.global_transform.basis.z
	var grip: float = stats.front_lateral_grip if is_front else stats.rear_lateral_grip
	var lat_f: float = clampf((-w_right.dot(pt_vel) * grip / maxf(delta, 0.008)) * mass * 0.04, -spring_f, spring_f)
	apply_force(w_right * lat_f, offset)

	# Longitudinal: rear-wheel drive, brakes on all wheels, rolling resistance.
	var wheel_fwd_speed: float = w_fwd.dot(pt_vel)
	var long_f: float = -wheel_fwd_speed * 12.0
	if not is_front and not is_engine_stalled and throttle_in > 0.01:
		if gear == GEAR_DRIVE and current_speed_kmh < stats.max_speed_kmh:
			var torque_curve: float = 1.0 - stats.torque_falloff * clampf(current_speed_kmh / stats.max_speed_kmh, 0.0, 1.0)
			long_f += throttle_in * stats.engine_peak_force_n * 0.5 * torque_curve
		elif gear == GEAR_REVERSE and (forward_speed_mps > 0.0 or current_speed_kmh < stats.reverse_max_speed_kmh):
			long_f -= throttle_in * stats.engine_peak_force_n * 0.25 # reverse gear: ACCEL drives backwards
	# Brakes oppose whichever way the wheel is rolling (forwards or in reverse).
	if brake_in > 0.01 and absf(wheel_fwd_speed) > 0.3:
		long_f -= signf(wheel_fwd_speed) * brake_in * stats.service_brake_force_n / 3.0
	if handbrake_on and not is_front:
		long_f -= signf(wheel_fwd_speed) * minf(stats.handbrake_force_n * 0.5, absf(wheel_fwd_speed) * mass * 2.0)
	# Drive/brake act at CoM height so throttle doesn't wheelie the trike.
	var up: Vector3 = global_transform.basis.y
	var com_global: Vector3 = global_transform.basis * center_of_mass
	var long_offset: Vector3 = offset - up * (up.dot(offset) - up.dot(com_global))
	apply_force(w_fwd * long_f, long_offset)

func _place_wheel_visual(visual_name: String, ray: RayCast3D, spring_len: float) -> void:
	if not _wheel_visuals.has(visual_name):
		return
	var n: Node3D = _wheel_visuals[visual_name]
	n.position = ray.position + Vector3(0.0, -spring_len, 0.0)
	if visual_name == "FrontWheelMesh":
		n.rotation.y = current_steer_rad

func _apply_aero_drag() -> void:
	var v: Vector3 = linear_velocity
	var spd: float = v.length()
	if spd > 0.5:
		apply_central_force(-v.normalized() * stats.aero_drag_coeff * spd * spd)

func _apply_stabilizer() -> void:
	var roll_rad: float = global_transform.basis.get_euler().z
	current_roll_deg = absf(rad_to_deg(roll_rad))
	var now_two_wheel: bool = current_roll_deg >= stats.two_wheel_tilt_min_deg \
		and current_roll_deg <= stats.max_safe_roll_angle_deg \
		and wheels_grounded == 2
	if now_two_wheel != is_on_two_wheels:
		is_on_two_wheels = now_two_wheel
		SignalBus.two_wheel_tilt_changed.emit(is_on_two_wheels)
		if is_on_two_wheels and current_speed_kmh >= GETHU_MIN_SPEED_KMH:
			SignalBus.gethu_stunt_bonus_earned.emit("Two-Wheel Side-Tilt Gethu", GETHU_BONUS_INR)
	var start: float = stats.anti_roll_start_deg
	if current_roll_deg > start:
		var ratio: float = clampf((current_roll_deg - start) / maxf(stats.max_safe_roll_angle_deg - start, 1.0), 0.0, 2.5)
		apply_torque(global_transform.basis.z * (-signf(roll_rad) * stats.anti_roll_torque_strength * ratio))
		# Kill roll-rate so the trike does not oscillate.
		var roll_rate: float = angular_velocity.dot(global_transform.basis.z)
		apply_torque(global_transform.basis.z * (-roll_rate * stats.anti_roll_torque_strength * 0.15))

func _update_fuel_and_odometer(delta: float) -> void:
	var km: float = current_speed_kmh / 3600.0 * delta
	odometer_km += km
	if is_engine_stalled:
		return
	var was_full: bool = fuel_level > 0.0
	fuel_level = maxf(0.0, fuel_level - km * stats.fuel_burn_per_km)
	if was_full and fuel_level <= 0.0:
		SignalBus.lpg_empty.emit()

func _check_water_stall() -> void:
	if is_engine_stalled or current_water_depth_m < stats.water_stall_depth_m:
		return
	if current_speed_kmh < STALL_MAX_SPEED_KMH and Input.get_action_strength("accelerate") < 0.9:
		is_engine_stalled = true
		kick_start_pulls = 0
		SignalBus.engine_stalled_in_water.emit(global_position)

func _emit_telemetry(delta: float) -> void:
	SignalBus.speed_updated.emit(current_speed_kmh)
	var fwd: Vector3 = -global_transform.basis.z
	SignalBus.player_pose_updated.emit(global_position, fwd)
	# Ride dynamics for the passenger comfort meter.
	var dv: Vector3 = linear_velocity - _prev_velocity
	_prev_velocity = linear_velocity
	var accel: Vector3 = dv / maxf(delta, 0.001)
	var right: Vector3 = global_transform.basis.x
	SignalBus.vehicle_dynamics.emit(accel.dot(right) / 9.8, accel.dot(fwd) / 9.8, absf(dv.y))
	# A sudden horizontal speed change far beyond braking ability = we hit something.
	var horizontal_dv: float = Vector2(dv.x, dv.z).length()
	if horizontal_dv > 2.5:
		SignalBus.player_collision.emit(horizontal_dv)
	_telemetry_timer += delta
	if _telemetry_timer < TELEMETRY_INTERVAL_S:
		return
	_telemetry_timer = 0.0
	SignalBus.fuel_changed.emit(fuel_level, stats.fuel_capacity)
	SignalBus.telemetry_updated.emit({
		"speed_kmh": current_speed_kmh,
		"lpg_liters": fuel_level,
		"lpg_capacity": stats.fuel_capacity,
		"odometer_km": odometer_km,
		"roll_deg": current_roll_deg,
		"is_stalled": is_engine_stalled,
		"is_on_two_wheels": is_on_two_wheels,
		"gear": gear,
		"indicator": indicator,
	})

# --- Gears, indicators, lamps -------------------------------------------------------------

## Change gear; only allowed (nearly) stopped, like the real lever. Returns true if it changed.
func set_gear(g: int) -> bool:
	if g == gear:
		return true
	if current_speed_kmh > GEAR_SHIFT_MAX_KMH:
		SignalBus.gear_change_refused.emit()
		return false
	gear = g
	_auto_reversed = false
	_brake_hold_s = 0.0
	SignalBus.gear_changed.emit(gear)
	return true

## Auto-reverse (setting, on by default), the way most phone driving games work: hold BRAKE
## at a standstill to engage R, then BRAKE drives backwards and ACCEL stops you / returns to D.
## The manual R/D button always works too: in a manually selected R, ACCEL drives backwards.
func _auto_gear(throttle_in: float, brake_in: float, delta: float) -> void:
	if not bool(GameState.settings.get("auto_reverse", true)):
		_brake_hold_s = 0.0
		return
	if gear == GEAR_DRIVE and current_speed_kmh < 1.5 and brake_in > 0.5 and throttle_in < 0.05:
		_brake_hold_s += delta
		if _brake_hold_s >= AUTO_REVERSE_HOLD_S and set_gear(GEAR_REVERSE):
			_auto_reversed = true
	else:
		_brake_hold_s = 0.0
	if gear == GEAR_REVERSE and _auto_reversed and throttle_in > 0.3 and current_speed_kmh < 1.0:
		set_gear(GEAR_DRIVE)

## -1 left, 0 off, +1 right.
func set_indicator(d: int) -> void:
	indicator = clampi(d, -1, 1)
	_blink_t = 0.0
	indicator_lamp_on = indicator != 0
	_indicator_start_yaw = global_rotation.y
	_indicator_turned = false
	SignalBus.indicator_changed.emit(indicator)
	SignalBus.indicator_blink.emit(indicator, indicator_lamp_on)

func _update_lamps(brake_in: float, delta: float) -> void:
	var braking: bool = brake_in > 0.05
	if braking != is_braking:
		is_braking = braking
		SignalBus.brake_lights_changed.emit(is_braking)
	if _brake_lamps != null:
		_brake_lamps.visible = is_braking or gear == GEAR_REVERSE
	if indicator == 0:
		for l: MeshInstance3D in _indicator_lamps:
			l.visible = false
		return
	_blink_t += delta
	var on: bool = fmod(_blink_t * INDICATOR_BLINK_HZ, 1.0) < 0.5
	if on != indicator_lamp_on:
		indicator_lamp_on = on
		SignalBus.indicator_blink.emit(indicator, on)
	if _indicator_lamps.size() == 2:
		_indicator_lamps[0].visible = indicator == -1 and on
		_indicator_lamps[1].visible = indicator == 1 and on
	# Self-cancel after the turn is made and the handlebar straightens, like a real switch.
	var turned: float = angle_difference(_indicator_start_yaw, global_rotation.y)
	if absf(turned) > INDICATOR_CANCEL_TURN_RAD:
		if not _indicator_turned:
			_indicator_turned = true
			# Turned the way we signalled (left = yaw increases in Godot's +Y rotation).
			if signf(turned) == -float(indicator):
				SignalBus.signalled_turn.emit(indicator)
		if absf(current_steer_rad) < 0.08:
			set_indicator(0)

## Emissive brake/reverse and indicator lamp glows (hidden when off). One shared material each.
func _build_lamps() -> void:
	var red: StandardMaterial3D = StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1.0, 0.12, 0.08)
	var amber: StandardMaterial3D = StandardMaterial3D.new()
	amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amber.albedo_color = Color(1.0, 0.62, 0.05)
	_brake_lamps = _lamp_mesh("BrakeLamps", [Vector3(-0.46, -0.12, 1.29), Vector3(0.46, -0.12, 1.29)], Vector3(0.14, 0.1, 0.03), red)
	_indicator_lamps = [
		_lamp_mesh("IndicatorLeft", [Vector3(-0.37, -0.02, -1.16), Vector3(-0.58, -0.12, 1.29)], Vector3(0.05, 0.06, 0.07), amber),
		_lamp_mesh("IndicatorRight", [Vector3(0.37, -0.02, -1.16), Vector3(0.58, -0.12, 1.29)], Vector3(0.05, 0.06, 0.07), amber),
	]

func _lamp_mesh(lamp_name: String, centres: Array[Vector3], size: Vector3, mat: Material) -> MeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Vector3 in centres:
		var bm: BoxMesh = BoxMesh.new()
		bm.size = size
		st.append_from(bm, 0, Transform3D(Basis.IDENTITY, c))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = lamp_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

func blow_horn() -> void:
	SignalBus.horn_blasted.emit(global_position, -global_transform.basis.z, stats.horn_radius_m, stats.horn_tier)

## Returns true once the engine is running again.
## With kick_rhythm_enabled, pulls only count when they keep a steady rhythm
## (KICK_RHYTHM_MIN_S–KICK_RHYTHM_MAX_S apart) — mashing the button floods the engine.
func pull_hand_kick_starter() -> bool:
	if not is_engine_stalled:
		return true
	var now: float = _clock_s
	if kick_rhythm_enabled and kick_start_pulls > 0:
		var gap: float = now - _last_kick_s
		var good: bool = gap >= KICK_RHYTHM_MIN_S and gap <= KICK_RHYTHM_MAX_S
		SignalBus.kick_timed.emit(good)
		_last_kick_s = now
		if not good:
			kick_start_pulls = 1 if gap > KICK_RHYTHM_MAX_S else kick_start_pulls # too slow restarts, too fast doesn't count
			return false
	_last_kick_s = now
	kick_start_pulls += 1
	SignalBus.kick_start_attempt.emit(float(kick_start_pulls) / float(stats.kick_start_pulls_needed))
	if kick_start_pulls >= stats.kick_start_pulls_needed:
		is_engine_stalled = false
		kick_start_pulls = 0
		SignalBus.engine_restarted.emit()
		return true
	return false

func _on_water_depth_changed(depth_m: float) -> void:
	current_water_depth_m = depth_m

func _on_passenger_boarded(count: int, luggage_weight_kg: float) -> void:
	passenger_count = clampi(count, 0, stats.passenger_capacity)
	luggage_kg = luggage_weight_kg
	_apply_mass()

func _on_passenger_alighted() -> void:
	passenger_count = 0
	luggage_kg = 0.0
	_apply_mass()
