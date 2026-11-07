class_name ParkedVehicleSet
extends Node3D
## One chunk's kerb-parked vehicles (built by RoadsideParking.populate). They are drawn as
## MultiMesh instances and stand as static boxes — cheap — until the player's auto comes within
## WAKE_MARGIN_M of one. That vehicle then becomes a real RigidBody3D with its real mass, so Jolt
## resolves the hit with momentum: a 110 kg scooter is knocked over and skids, a 480 kg share auto
## is shoved, a 1.15 t car barely rocks and stops the auto (Nov 7 owner request: parked vehicles
## didn't move at all when hit).
##
## The woken body keeps its pose wherever it ends up; it never goes back to the MultiMesh (the
## chunk rebuilds it fresh when it streams in again).

const WAKE_MARGIN_M: float = 0.9
## Real kerb weights: Activa-class scooter (with stand), compact car, Ape-type share auto.
const MASS_KG: Array[float] = [110.0, 1150.0, 480.0]
## Sliding friction against the road: scooter tyres skid; parked car/auto have the brake on.
const FRICTION: Array[float] = [0.6, 0.8, 0.7]
## A two-wheeler only stands on its side stand: its body rests on a narrow base, so a knock tips
## it over (and a hit gives it the sideways twist a real scooter takes).
const SCOOTER_BASE_W: float = 0.36
const SCOOTER_KNOCK_ROLL: float = 9.0 # N·m·s per m/s of closing speed
## Centre of mass above the spot, as a share of height: scooters are top-heavy.
const COM_HEIGHT: Array[float] = [0.5, 0.35, 0.42]
const MAX_AWAKE: int = 8
const PARKED_GROUP: StringName = &"parked_vehicle"

## Per vehicle: {"kind", "origin", "yaw", "dim", "group", "inst", "paint"}.
var records: Array[Dictionary] = []
## Per group (one model file): {"mms": Array[MultiMesh], "parts": Array[[mesh, local xf, material]]}.
var groups: Array[Dictionary] = []
var awake: Dictionary = {} # record index -> RigidBody3D
var _order: Array[int] = []
var _static: StaticBody3D = null
var _touch: Area3D = null
var _shape_of: Array[CollisionShape3D] = []
var _touch_of: Array[CollisionShape3D] = []

## Build the static boxes and the wake sensor for every record (call after filling records).
func build_colliders() -> void:
	_static = StaticBody3D.new()
	_static.name = "ParkedVehicleCollision"
	_static.collision_layer = 1
	_static.collision_mask = 0
	add_child(_static)
	_touch = Area3D.new()
	_touch.name = "ParkedWake"
	_touch.collision_layer = 0
	_touch.collision_mask = 2 # the player auto
	_touch.monitorable = false
	add_child(_touch)
	for i: int in records.size():
		var r: Dictionary = records[i]
		var dim: Vector3 = r["dim"]
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, float(r["yaw"])), (r["origin"] as Vector3) + Vector3.UP * dim.y * 0.5)
		var cs: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = dim
		cs.shape = box
		cs.transform = xf
		cs.set_meta("rec", i)
		_static.add_child(cs)
		_shape_of.append(cs)
		var ts: CollisionShape3D = CollisionShape3D.new()
		var tbox: BoxShape3D = BoxShape3D.new()
		tbox.size = dim + Vector3(WAKE_MARGIN_M * 2.0, 0.6, WAKE_MARGIN_M * 2.0)
		ts.shape = tbox
		ts.transform = xf
		ts.set_meta("rec", i)
		_touch.add_child(ts)
		_touch_of.append(ts)
	_touch.body_shape_entered.connect(_on_touch)

func _on_touch(_rid: RID, body: Node3D, _body_shape: int, local_shape: int) -> void:
	if body == null or not body.is_in_group("player_auto"):
		return
	var owner_id: int = _touch.shape_find_owner(local_shape)
	var node: Object = _touch.shape_owner_get_owner(owner_id)
	if node is CollisionShape3D and (node as CollisionShape3D).has_meta("rec"):
		wake.call_deferred(int((node as CollisionShape3D).get_meta("rec")))

## Swap vehicle `i` from a static MultiMesh instance to a live rigid body (public for tests).
func wake(i: int) -> RigidBody3D:
	if awake.has(i):
		return awake[i]
	var r: Dictionary = records[i]
	var kind: int = int(r["kind"])
	var dim: Vector3 = r["dim"]
	var g: Dictionary = groups[int(r["group"])]
	for mm: MultiMesh in g["mms"]:
		mm.set_instance_transform(int(r["inst"]), Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -50.0, 0.0)))
	_shape_of[i].disabled = true
	_touch_of[i].disabled = true
	var body: RigidBody3D = RigidBody3D.new()
	body.name = "Parked_%d" % i
	body.add_to_group(PARKED_GROUP)
	body.mass = MASS_KG[kind]
	body.collision_layer = 1
	body.collision_mask = 1 | 2
	body.continuous_cd = kind == 0
	body.linear_damp = 0.15
	body.angular_damp = 0.6
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3(0.0, dim.y * COM_HEIGHT[kind], 0.0)
	var pm: PhysicsMaterial = PhysicsMaterial.new()
	pm.friction = FRICTION[kind]
	pm.bounce = 0.05
	body.physics_material_override = pm
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(minf(dim.x, SCOOTER_BASE_W), dim.y, dim.z) if kind == 0 else dim
	cs.shape = box
	cs.position = Vector3.UP * dim.y * 0.5
	body.add_child(cs)
	if kind == 0:
		body.contact_monitor = true
		body.max_contacts_reported = 4
		# Not one-shot: the first body it touches is usually the ground.
		body.body_entered.connect(_on_scooter_hit.bind(body))
	for part: Array in g["parts"]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		if part[2] != null:
			mi.material_override = part[2]
		body.add_child(mi)
		if r.get("paint", PaintSwap.NO_PAINT) != PaintSwap.NO_PAINT:
			mi.set_instance_shader_parameter("paint", r["paint"])
	body.transform = Transform3D(Basis(Vector3.UP, float(r["yaw"])), r["origin"])
	add_child(body)
	awake[i] = body
	_order.append(i)
	# Bound the live simulation: the oldest woken vehicle that has come to rest is frozen
	# (still solid, still where it ended up, no longer simulated).
	if _order.size() > MAX_AWAKE:
		for k: int in _order.size():
			var old: RigidBody3D = awake[_order[k]]
			if old.sleeping or old.linear_velocity.length() < 0.1:
				old.freeze = true
				_order.remove_at(k)
				break
	return body

func _on_scooter_hit(other: Node, body: RigidBody3D) -> void:
	if other == null or not other.is_in_group("player_auto") or body.has_meta("knocked"):
		return
	body.set_meta("knocked", true)
	# The hitter's own speed (by the time this fires the scooter is already moving with it).
	var closing: float = (other as RigidBody3D).linear_velocity.length() if other is RigidBody3D else 3.0
	var along: Vector3 = body.global_basis.z
	var side: float = 1.0 if int(body.global_position.x * 10.0) % 2 == 0 else -1.0
	body.apply_torque_impulse(along * side * SCOOTER_KNOCK_ROLL * closing)

## The nearest still-parked vehicle to `p` (tests).
func nearest_parked(p: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in records.size():
		if awake.has(i):
			continue
		var d: float = (records[i]["origin"] as Vector3).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best
