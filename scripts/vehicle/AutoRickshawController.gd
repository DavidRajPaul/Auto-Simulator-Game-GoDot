class_name AutoRickshawController
extends RigidBody3D
## 3-wheel delta-trike raycast vehicle (1 steerable front wheel, 2 rear drive wheels).
## All tunables come from `stats` (VehicleStats .tres). Input is read from the InputMap,
## so keyboard, the TouchHUD and the headless tests all drive it the same way.

const TELEMETRY_INTERVAL_S: float = 0.1
const LOW_FUEL_FRACTION: float = 0.20
const IDLE_FUEL_UNITS_PER_HOUR: float = 0.08
const STALL_MAX_SPEED_KMH: float = 12.0
const WATER_DRAG_N_PER_MPS: float = 240.0
const WATER_DRAG_MAX_N: float = 2200.0
const SPLASH_MIN_SPEED_KMH: float = 6.0
const SPLASH_MAX_SPEED_KMH: float = 42.0
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

var _driver_on_foot: bool = false
var current_speed_kmh: float = 0.0
var forward_speed_mps: float = 0.0
var current_steer_rad: float = 0.0
var current_roll_deg: float = 0.0
var fuel_level: float = 0.0
var _low_fuel_warned: bool = false
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
var _wheel_splashes: Array[GPUParticles3D] = []
## --- Collisions (modelled on BUSSID / Car Parking Multiplayer / Truckers of Europe feel) ---
## Low body friction so a glancing hit SLIDES along the wall instead of gluing the auto to it,
## a little restitution for a believable bump-back, chamfered hull corners so building corners
## and kerb edges don't snag, impact = pre-impact closing speed along the contact normal
## (not a frame-to-frame velocity guess), and a short post-impact stabiliser so hits never
## flip or spin the trike wildly.
const BODY_FRICTION: float = 0.12
const BODY_BOUNCE: float = 0.16
const IMPACT_MIN_MPS: float = 1.2 # below this it's a scrape/touch, no damage
const IMPACT_HARD_MPS: float = 8.0 # severity 1.0
const IMPACT_COOLDOWN_S: float = 0.3
const POST_IMPACT_S: float = 0.5
const POST_IMPACT_TILT_DAMP: float = 0.7 # fraction of roll/pitch rate removed per tick
const POST_IMPACT_MAX_YAW: float = 1.4 # rad/s
const SCRAPE_MIN_MPS: float = 1.5
var _impact_cooldown: float = 0.0
var _post_impact_t: float = 0.0
var _scraping: bool = false
var last_impact_mps: float = 0.0
## Velocity going into the last physics solve (contacts reported now come from that solve).
var _pre_step_velocity: Vector3 = Vector3.ZERO

## Off in the cockpit view: the canopy/frame shadows sweeping over the dash as the auto turns
## read as flickering dark bands right in the driver's eyes.
var _self_shadows: bool = true
var _police_stop_timer: float = 0.0

func _ready() -> void:
	if use_player_profile:
		stats = GameState.active_stats()
	if stats == null:
		stats = VehicleStats.new()
	add_to_group("player_auto")
	SignalBus.on_foot_changed.connect(func(value: bool) -> void: _driver_on_foot = value)
	fuel_level = stats.fuel_capacity if GameState.fuel_level < 0.0 or not use_player_profile else minf(GameState.fuel_level, stats.fuel_capacity)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_setup_collision()
	_apply_mass()
	_setup_wheel_rays()
	_setup_wheel_splashes()
	SignalBus.water_depth_changed.connect(_on_water_depth_changed)
	SignalBus.police_intercept_requested.connect(_on_police_intercept)
	SignalBus.passenger_boarded.connect(_on_passenger_boarded)
	SignalBus.passenger_alighted.connect(_on_passenger_alighted)
	SignalBus.refueled.connect(func(level: float) -> void: fuel_level = minf(level, stats.fuel_capacity))
	SignalBus.teleport_requested.connect(func(xform: Transform3D) -> void:
		global_transform = xform
		reset_physics_interpolation()
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_prev_velocity = Vector3.ZERO
		current_water_depth_m = 0.0)
	if use_player_profile:
		SignalBus.vehicle_loadout_changed.connect(apply_stats)
		SignalBus.engine_switch_off_requested.connect(switch_off_engine)
	_recolour.call_deferred()
	_build_lamps()
	SignalBus.camera_mode_changed.connect(func(mode_name: String) -> void:
		_self_shadows = mode_name != "Cockpit"
		_apply_self_shadows())

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
	_apply_self_shadows()
	var procedural_wheels: bool = model == null or not model.uses_real_model
	for wheel_name: String in ["FrontWheelMesh", "RearLeftWheelMesh", "RearRightWheelMesh"]:
		var w: Node3D = get_node_or_null(wheel_name) as Node3D
		if w != null:
			w.visible = procedural_wheels

## Three tiny GPU emitters, each reusing one shared material and quad mesh.
## Emission is off when dry, slow, airborne, or the flood has drained.
func _setup_wheel_splashes() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.11, 0.20)
	var surface: StandardMaterial3D = StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.albedo_color = Color(0.67, 0.70, 0.68, 0.55)
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	surface.vertex_color_use_as_albedo = true
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = surface
	var motion: ParticleProcessMaterial = ParticleProcessMaterial.new()
	motion.direction = Vector3(0.0, 1.0, 0.0)
	motion.spread = 55.0
	motion.initial_velocity_min = 1.1
	motion.initial_velocity_max = 2.7
	motion.gravity = Vector3(0.0, -7.0, 0.0)
	motion.scale_min = 0.5
	motion.scale_max = 1.2
	for origin: Vector3 in [FRONT_WHEEL_POS, REAR_LEFT_WHEEL_POS, REAR_RIGHT_WHEEL_POS]:
		var spray: GPUParticles3D = GPUParticles3D.new()
		spray.name = "WheelSplash%d" % _wheel_splashes.size()
		spray.position = origin + Vector3(0.0, -stats.wheel_radius_m * 0.45, 0.0)
		spray.amount = 10
		spray.lifetime = 0.42
		spray.explosiveness = 0.0
		spray.process_material = motion
		spray.draw_pass_1 = quad
		spray.emitting = false
		spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spray)
		_wheel_splashes.append(spray)

func _update_wheel_splashes() -> void:
	var active: bool = current_water_depth_m > 0.06 and current_speed_kmh > SPLASH_MIN_SPEED_KMH and wheels_grounded > 0
	for i: int in _wheel_splashes.size():
		var spray: GPUParticles3D = _wheel_splashes[i]
		var ray: RayCast3D = front_wheel_ray if i == 0 else (rear_left_wheel_ray if i == 1 else rear_right_wheel_ray)
		spray.emitting = active and ray.is_colliding()
		if spray.emitting:
			spray.amount_ratio = clampf((current_speed_kmh - SPLASH_MIN_SPEED_KMH) / (SPLASH_MAX_SPEED_KMH - SPLASH_MIN_SPEED_KMH), 0.15, 1.0)

func _setup_collision() -> void:
	var pm: PhysicsMaterial = PhysicsMaterial.new()
	pm.friction = BODY_FRICTION
	pm.bounce = BODY_BOUNCE
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 6
	var cs: CollisionShape3D = get_node_or_null("ChassisCollision") as CollisionShape3D
	if cs != null and cs.shape is BoxShape3D:
		cs.shape = chamfered_hull((cs.shape as BoxShape3D).size, 0.22)

## Box with bevelled vertical edges and a rounded nose/tail: glides off corners.
static func chamfered_hull(size: Vector3, c: float) -> ConvexPolygonShape3D:
	var h: Vector3 = size * 0.5
	var pts: PackedVector3Array = PackedVector3Array()
	for y: float in [-h.y, h.y]:
		var cy: float = c * 0.5 if y > 0.0 else 0.0 # roof corners a bit rounder
		for p: Vector2 in [Vector2(-h.x + c + cy, -h.z), Vector2(h.x - c - cy, -h.z), Vector2(h.x, -h.z + c + cy), Vector2(h.x, h.z - c),
				Vector2(h.x - c, h.z), Vector2(-h.x + c, h.z), Vector2(-h.x, h.z - c), Vector2(-h.x, -h.z + c + cy)]:
			pts.append(Vector3(p.x, y, p.y))
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = pts
	return shape

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	_impact_cooldown = maxf(0.0, _impact_cooldown - dt)
	var best: float = 0.0
	var best_i: int = -1
	var scrape_speed: float = 0.0
	var scrape_pt: Vector3 = Vector3.ZERO
	for i: int in state.get_contact_count():
		var n: Vector3 = state.get_contact_local_normal(i)
		if n.y > 0.6:
			continue # resting on the road / a ramp — not a hit
		var v_rel: Vector3 = _pre_step_velocity - state.get_contact_collider_velocity_at_position(i)
		var closing: float = -v_rel.dot(n)
		if closing > best:
			best = closing
			best_i = i
		var tangential: float = (v_rel + n * v_rel.dot(n)).length()
		if tangential > scrape_speed:
			scrape_speed = tangential
			scrape_pt = state.get_contact_collider_position(i)
	if best_i >= 0 and best >= IMPACT_MIN_MPS and _impact_cooldown <= 0.0:
		_impact_cooldown = IMPACT_COOLDOWN_S
		_post_impact_t = POST_IMPACT_S
		last_impact_mps = best
		var collider: Object = state.get_contact_collider_object(best_i)
		var kind: String = "wall"
		if collider is TrafficVehicleAI:
			kind = "vehicle"
			SignalBus.traffic_bumped.emit(collider as Node3D, best)
		elif collider is StaticBody3D and (collider as StaticBody3D).collision_layer & 8:
			kind = "prop"
		SignalBus.player_collision.emit(best)
		SignalBus.player_impact.emit({"speed_mps": best, "kind": kind, "point": state.get_contact_collider_position(best_i),
			"normal": state.get_contact_local_normal(best_i), "severity": clampf(best / IMPACT_HARD_MPS, 0.0, 1.0)})
	var now_scraping: bool = scrape_speed >= SCRAPE_MIN_MPS and state.get_contact_count() > 0 and best_i >= 0
	if now_scraping or _scraping:
		SignalBus.player_scraping.emit(scrape_speed if now_scraping else 0.0, scrape_pt)
	_scraping = now_scraping
	# Post-impact stabiliser: bleed off roll/pitch, cap spin. Keeps hits readable, never a flip.
	if _post_impact_t > 0.0:
		_post_impact_t -= dt
		var b: Basis = state.transform.basis
		var w: Vector3 = state.angular_velocity
		var pitch: float = w.dot(b.x)
		var roll: float = w.dot(b.z)
		w -= b.x * pitch * POST_IMPACT_TILT_DAMP + b.z * roll * POST_IMPACT_TILT_DAMP
		var yaw: float = w.dot(b.y)
		if absf(yaw) > POST_IMPACT_MAX_YAW:
			w -= b.y * (yaw - signf(yaw) * POST_IMPACT_MAX_YAW)
		state.angular_velocity = w
	_pre_step_velocity = state.linear_velocity

func _apply_self_shadows() -> void:
	var setting: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _self_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D and n.name not in ["BrakeLamps", "IndicatorLeft", "IndicatorRight"]:
			(n as GeometryInstance3D).cast_shadow = setting
		stack.append_array(n.get_children())

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
	_police_stop_timer = maxf(0.0, _police_stop_timer - delta)
	var throttle_in: float = Input.get_action_strength("accelerate")
	var brake_in: float = Input.get_action_strength("brake")
	var steer_in: float = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var handbrake_on: bool = Input.is_action_pressed("handbrake")

	# Read current physics velocity BEFORE handling gear changes and auto-reverse.
	# Previously _auto_gear()/set_gear() used last tick's current_speed_kmh,
	# allowing a one-frame stale reading near the 4 km/h shift safety limit.
	var forward_dir: Vector3 = -global_transform.basis.z
	forward_speed_mps = linear_velocity.dot(forward_dir)
	current_speed_kmh = absf(forward_speed_mps) * 3.6

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
	if _police_stop_timer > 0.0:
		throttle_in = 0.0
		brake_in = 1.0
		handbrake_on = true

	if fuel_level <= 0.0:
		throttle_in = 0.0

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
	_apply_water_drag()
	_update_fuel_and_odometer(delta)
	_check_water_stall()
	_update_lamps(brake_in, delta)
	_emit_telemetry(delta)

func _on_police_intercept(_position: Vector3, _heading: Vector3, _fine_inr: int) -> void:
	_police_stop_timer = 1.8
	linear_velocity *= 0.55
	angular_velocity *= 0.5

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

## Bounded depth-dependent resistance, not a fluid simulation.
func _apply_water_drag() -> void:
	if current_water_depth_m <= 0.05:
		return
	var horizontal: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if horizontal.length_squared() < 0.01:
		return
	var ratio: float = clampf(current_water_depth_m / maxf(stats.water_stall_depth_m, 0.1), 0.0, 1.5)
	var force_n: float = minf(WATER_DRAG_MAX_N, horizontal.length() * WATER_DRAG_N_PER_MPS * ratio)
	apply_central_force(-horizontal.normalized() * force_n)

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
	if is_engine_stalled or (use_player_profile and GameState.tutorial_active):
		return # guided first ride: no fuel burn
	var was_full: bool = fuel_level > 0.0
	# Fuel is consumed by driving and by an idling engine; no consumption
	# while stalled or switched off. A slow city journey must still cost fuel.
	var idle_burn: float = IDLE_FUEL_UNITS_PER_HOUR * delta / 3600.0
	fuel_level = maxf(0.0, fuel_level - km * stats.fuel_burn_per_km - idle_burn)
	var low: bool = fuel_level > 0.0 and fuel_level <= stats.fuel_capacity * LOW_FUEL_FRACTION
	if low and not _low_fuel_warned:
		_low_fuel_warned = true
		SignalBus.fuel_low.emit(fuel_level, stats.fuel_capacity)
	elif not low:
		_low_fuel_warned = false
	if was_full and fuel_level <= 0.0:
		SignalBus.lpg_empty.emit()

func _check_water_stall() -> void:
	if is_engine_stalled or current_water_depth_m < stats.water_stall_depth_m:
		return
	if current_speed_kmh < STALL_MAX_SPEED_KMH or current_water_depth_m >= stats.water_stall_depth_m * 1.35:
		is_engine_stalled = true
		kick_start_pulls = 0
		SignalBus.engine_stalled_in_water.emit(global_position)

func _emit_telemetry(delta: float) -> void:
	SignalBus.speed_updated.emit(current_speed_kmh)
	var fwd: Vector3 = -global_transform.basis.z
	if not _driver_on_foot:
		SignalBus.player_pose_updated.emit(global_position, fwd)
	# Ride dynamics for the passenger comfort meter.
	var dv: Vector3 = linear_velocity - _prev_velocity
	_prev_velocity = linear_velocity
	var accel: Vector3 = dv / maxf(delta, 0.001)
	var right: Vector3 = global_transform.basis.x
	SignalBus.vehicle_dynamics.emit(accel.dot(right) / 9.8, accel.dot(fwd) / 9.8, absf(dv.y))
	# Impacts are detected from real contacts in _integrate_forces.
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

## Engine off (tutorial start, later: key-off at a stand). The kick-starter brings it back.
func switch_off_engine() -> void:
	if is_engine_stalled:
		return
	is_engine_stalled = true
	kick_start_pulls = 0
	SignalBus.engine_switched_off.emit()

func blow_horn() -> void:
	SignalBus.horn_blasted.emit(global_position, -global_transform.basis.z, stats.horn_radius_m, stats.horn_tier)

## Returns true once the engine is running again.
## With kick_rhythm_enabled, pulls only count when they keep a steady rhythm
## (KICK_RHYTHM_MIN_S–KICK_RHYTHM_MAX_S apart) — mashing the button floods the engine.
func pull_hand_kick_starter() -> bool:
	if not is_engine_stalled:
		return true
	# Restarting while intake-height water surrounds the engine is unsafe.
	if current_water_depth_m >= stats.water_stall_depth_m:
		SignalBus.flood_restart_blocked.emit()
		return false
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
