class_name KnockedVehicles
extends Node3D
## Real collision physics for MOVING traffic (Nov 14 owner request: "collision physics is
## applied only to parked vehicles, apply it to moving vehicles too").
##
## Traffic drives as pooled kinematic bodies on the road graph (cheap, 18 of them). When the
## player's auto hits a two-wheeler, a car or an auto hard enough, that vehicle is handed to
## one of SLOTS pre-built RigidBody3D bodies: same place, same size, its real mass, the speed
## it was driving at plus what the hit gave it. From then on Jolt owns it: a scooter topples
## and slides with its rider, a car is shoved and spun, both can be hit again and pushed.
## The traffic slot stays out of the pool until the body is returned (off screen or far away
## after HOLD_S, or at once when another hit needs the slot).
##
## Nothing is instanced while driving: the bodies are built in _ready, and a hand-over only
## re-parents the vehicle's own model nodes. Buses, lorries, service vehicles and cattle keep
## the old stop-honk-recoil (an auto can't throw a bus).
const SLOTS: int = 3
## Closing speed (m/s) from which a hit knocks the vehicle loose, per archetype (-1 = never).
const KNOCK_MPS: Array[float] = [2.2, 4.5, 3.8, -1.0, -1.0, -1.0, -1.0]
const HOLD_S: float = 9.0
const RETURN_FAR_M: float = 75.0
const RESTITUTION: float = 0.2
## Share of the hit that also spins the body (rad/s per m/s of delta-v).
const SPIN_PER_MPS: float = 0.35
const TOPPLE_RAD_S: float = 2.6
const TOPPLE_LEAN_RAD: float = 0.45
const COM_HEIGHT: Array[float] = [0.55, 0.4, 0.45, 0.4, 0.4, 0.4, 0.4]

class Slot:
	var body: RigidBody3D
	var shape: CollisionShape3D
	var owner: TrafficVehicleAI = null
	var nodes: Array[Node3D] = []
	var locals: Array[Transform3D] = []
	var held: float = 0.0

var slots: Array[Slot] = []

func _ready() -> void:
	name = "KnockedVehicles"
	for i: int in SLOTS:
		var s: Slot = Slot.new()
		var b: RigidBody3D = RigidBody3D.new()
		b.name = "Knocked_%d" % i
		b.add_to_group(ParkedVehicleSet.PARKED_GROUP) # a later hit counts as hitting a vehicle
		b.collision_layer = 1
		b.collision_mask = 1 | 2 | 4
		b.linear_damp = 0.2
		b.angular_damp = 0.8
		b.continuous_cd = true
		b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		var pm: PhysicsMaterial = PhysicsMaterial.new()
		pm.friction = 0.75
		pm.bounce = 0.05
		b.physics_material_override = pm
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.disabled = true
		b.add_child(cs)
		b.freeze = true
		b.visible = false
		b.position = Vector3(40.0 + float(i) * 12.0, -220.0, 0.0)
		add_child(b)
		s.body = b
		s.shape = cs
		slots.append(s)

## True if `v` was handed to a rigid body (the caller then skips the kinematic recoil).
func knock(v: TrafficVehicleAI, impact_mps: float, push: Vector3, player_mass: float, player_pos: Vector3) -> bool:
	var limit: float = KNOCK_MPS[v.archetype]
	if limit < 0.0 or impact_mps < limit or v.knocked or v.emergency_active or GameState.tutorial_active:
		return false
	var visuals: Array[Node3D] = v.knock_visuals()
	if visuals.is_empty():
		return false
	var s: Slot = _free_slot()
	if s == null:
		return false
	var mass: float = TrafficVehicleAI.PHYSICS.masses_kg[v.archetype]
	var size: Vector3 = v.body
	var xf: Transform3D = v.global_transform
	var forward: Vector3 = -xf.basis.z
	var drive: Vector3 = forward * v.current_speed_mps
	# Momentum exchange along the line of the hit (the auto has already bounced off the
	# kinematic body this step; this is the other half of that collision).
	var dv: float = (1.0 + RESTITUTION) * impact_mps * player_mass / (player_mass + mass)
	var flat: Vector3 = Vector3(push.x, 0.0, push.z).normalized() if Vector3(push.x, 0.0, push.z).length() > 0.01 else forward
	s.owner = v
	s.held = 0.0
	s.nodes = visuals
	s.locals.clear()
	for n: Node3D in visuals:
		s.locals.append(n.transform)
	var b: RigidBody3D = s.body
	(s.shape.shape as BoxShape3D).size = Vector3(minf(size.x, 0.5) if v.archetype == TrafficVehicleAI.Archetype.TWO_WHEELER else size.x, size.y, size.z)
	s.shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	b.mass = mass
	b.center_of_mass = Vector3(0.0, size.y * COM_HEIGHT[v.archetype], 0.0)
	v.release_for_knock()
	for n: Node3D in visuals:
		n.get_parent().remove_child(n)
		b.add_child(n)
	var start: Basis = xf.basis.orthonormalized()
	var lean_side: float = 0.0
	if v.archetype == TrafficVehicleAI.Archetype.TWO_WHEELER:
		# A two-wheeler has no balance once it is hit: start it past its tipping angle, falling
		# away from the auto, and let gravity do the rest.
		lean_side = signf(flat.dot(xf.basis.x)) if absf(flat.dot(xf.basis.x)) > 0.15 else (1.0 if randf() < 0.5 else -1.0)
		start = Basis(forward, -lean_side * TOPPLE_LEAN_RAD) * start
	b.global_transform = Transform3D(start, xf.origin + Vector3(0.0, 0.05, 0.0))
	b.reset_physics_interpolation()
	b.visible = true
	s.shape.disabled = false
	b.freeze = false
	b.sleeping = false
	b.linear_velocity = drive + flat * dv
	# Spin: a hit off the centre line turns the body; a two-wheeler also goes over on its side.
	var arm: Vector3 = xf.origin - player_pos
	var yaw_sign: float = signf(Vector3(arm.x, 0.0, arm.z).cross(flat).y)
	var spin: Vector3 = Vector3.UP * yaw_sign * dv * SPIN_PER_MPS
	if v.archetype == TrafficVehicleAI.Archetype.TWO_WHEELER:
		spin += forward * -lean_side * TOPPLE_RAD_S
	b.angular_velocity = spin
	return true

func _free_slot() -> Slot:
	var oldest: Slot = null
	for s: Slot in slots:
		if s.owner == null:
			return s
		if oldest == null or s.held > oldest.held:
			oldest = s
	# All busy: take back the one knocked longest ago, if the first moments of its tumble are over.
	if oldest != null and oldest.held > 2.0:
		give_back(oldest)
		return oldest
	return null

func _physics_process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	for s: Slot in slots:
		if s.owner == null:
			continue
		s.held += delta
		if s.held < HOLD_S:
			continue
		var p: Vector3 = s.body.global_position
		var far: bool = cam == null or cam.global_position.distance_to(p) > RETURN_FAR_M
		if far or p.y < -20.0 or not ViewCheck.on_screen(get_viewport(), p + Vector3.UP, 3.0):
			give_back(s)

## Hand the model nodes back to their traffic slot and park the rigid body under the map.
func give_back(s: Slot) -> void:
	var v: TrafficVehicleAI = s.owner
	for i: int in s.nodes.size():
		var n: Node3D = s.nodes[i]
		if is_instance_valid(n):
			s.body.remove_child(n)
			v.add_child(n)
			n.transform = s.locals[i]
	s.owner = null
	s.nodes = []
	s.shape.disabled = true
	s.body.freeze = true
	s.body.visible = false
	s.body.linear_velocity = Vector3.ZERO
	s.body.angular_velocity = Vector3.ZERO
	s.body.global_position = Vector3(40.0 + float(slots.find(s)) * 12.0, -220.0, 0.0)
	s.body.reset_physics_interpolation()
	if is_instance_valid(v):
		v.knocked = false

## A traffic slot is being placed again while its model is still out: take it back first.
func reclaim(v: TrafficVehicleAI) -> void:
	for s: Slot in slots:
		if s.owner == v:
			give_back(s)

func busy_count() -> int:
	var n: int = 0
	for s: Slot in slots:
		if s.owner != null:
			n += 1
	return n
