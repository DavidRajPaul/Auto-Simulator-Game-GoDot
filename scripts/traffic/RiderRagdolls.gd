class_name RiderRagdolls
extends Node3D
## Two-wheeler riders thrown off in a crash (Nov 27 owner request: "if I hit a person riding a
## two-wheeler, can he come off the bike in a rag doll and the bike fall down?").
##
## KnockedVehicles already hands a hit two-wheeler to a rigid body that topples. The rider used
## to stay glued to the seat. Now the seated rider mesh hides and the SAME person (the walking
## model the rider was baked from) takes over as a rag doll: Jolt PhysicalBone3D bodies on the
## 22-bone rig, posed as if seated, flung with the bike's speed plus the hit, a little up.
##
## Nothing is instanced while driving: one rag doll per rider model is built in _ready (four
## skinned people, hidden, animation off, bones not simulating). A throw re-poses one and starts
## its simulation; release() stops it and hides it again when KnockedVehicles hands the bike
## back (off screen or far away). Bones collide with the world (layer 1: ground, walls, the
## knocked bike body) but not with the player's auto, so the auto never bounces off a limb.
const BONES: Array[String] = ["Hips", "Spine1", "Head", "LeftArm", "LeftForeArm", "RightArm", "RightForeArm",
	"LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"]
## Bone -> the bone its body reaches to (capsule along that line), radius in metres, mass share.
const SHAPES: Dictionary = {
	"Hips": ["Spine1", 0.13, 0.16], "Spine1": ["Neck", 0.13, 0.2], "Head": ["", 0.1, 0.08],
	"LeftArm": ["LeftForeArm", 0.05, 0.035], "LeftForeArm": ["LeftHand", 0.045, 0.025],
	"RightArm": ["RightForeArm", 0.05, 0.035], "RightForeArm": ["RightHand", 0.045, 0.025],
	"LeftUpLeg": ["LeftLeg", 0.075, 0.11], "LeftLeg": ["LeftFoot", 0.06, 0.06],
	"RightUpLeg": ["RightLeg", 0.075, 0.11], "RightLeg": ["RightFoot", 0.06, 0.06],
}
const BODY_KG: float = 65.0
## Seated on a bike: thighs forward, knees bent down, upper arms reaching to the bars.
const THIGH_DEG: float = -82.0
const KNEE_DEG: float = 85.0
const ARM_DEG: float = -55.0
const THROW_UP_MPS: float = 2.4
const MAX_SPEED_MPS: float = 14.0

class Doll:
	var root: Node3D
	var skeleton: Skeleton3D
	var sim: PhysicalBoneSimulator3D
	var bones: Array[PhysicalBone3D] = []
	var source: String = ""
	var busy: bool = false
	var since: float = 0.0
	var rider: Node3D = null

var dolls: Array[Doll] = []

func _ready() -> void:
	name = "RiderRagdolls"
	for i: int in PersonMesh.RIDER_MODELS.size():
		var src: String = source_of(PersonMesh.RIDER_MODELS[i])
		var d: Doll = _build(src, i)
		if d != null:
			dolls.append(d)

func _process(delta: float) -> void:
	for d: Doll in dolls:
		if d.busy:
			d.since += delta

## The walking model a baked rider was made from ("riders/young_man_rider.glb" -> "young_man.glb").
static func source_of(rider_path: String) -> String:
	return rider_path.replace("/riders/", "/").replace("_rider.glb", ".glb")

func _build(path: String, index: int) -> Doll:
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return null
	var d: Doll = Doll.new()
	d.source = path
	d.root = scene.instantiate() as Node3D
	d.root.name = "Ragdoll_%d" % index
	d.root.visible = false
	add_child(d.root)
	d.root.position = Vector3(60.0 + float(index) * 4.0, -240.0, 0.0)
	for ap: Node in d.root.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).active = false
	for at: Node in d.root.find_children("*", "AnimationTree", true, false):
		(at as AnimationTree).active = false
	var found: Array[Node] = d.root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		d.root.queue_free()
		return null
	d.skeleton = found[0] as Skeleton3D
	for mi: Node in d.root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	d.sim = PhysicalBoneSimulator3D.new()
	d.sim.name = "Ragdoll"
	d.skeleton.add_child(d.sim)
	var sk: Skeleton3D = d.skeleton
	for b: String in BONES:
		var bi: int = sk.find_bone(b)
		if bi < 0:
			continue
		var spec: Array = SHAPES[b]
		var pb: PhysicalBone3D = PhysicalBone3D.new()
		pb.name = "PB_" + b
		pb.bone_name = b
		pb.mass = BODY_KG * float(spec[2])
		pb.collision_layer = 0
		pb.collision_mask = 1
		pb.friction = 0.8
		pb.bounce = 0.05
		pb.linear_damp = 0.1
		pb.angular_damp = 1.2
		# The body lies along the bone, from its joint to the next one (in the bone's own frame).
		var rest: Transform3D = sk.get_bone_global_rest(bi)
		var to_child: Vector3 = Vector3(0.0, 0.18, 0.0)
		var child: String = str(spec[0])
		if child != "" and sk.find_bone(child) >= 0:
			to_child = rest.basis.inverse() * (sk.get_bone_global_rest(sk.find_bone(child)).origin - rest.origin)
		var cs: CollisionShape3D = CollisionShape3D.new()
		var r: float = float(spec[1]) / maxf(sk.global_transform.basis.get_scale().x, 0.0001)
		if child == "":
			var sphere: SphereShape3D = SphereShape3D.new()
			sphere.radius = r
			cs.shape = sphere
			cs.position = to_child.normalized() * r * 0.8
		else:
			var cap: CapsuleShape3D = CapsuleShape3D.new()
			cap.radius = r
			cap.height = maxf(to_child.length(), r * 2.0 + 0.01)
			cs.shape = cap
			cs.position = to_child * 0.5
			cs.basis = _basis_y_to(to_child)
		pb.add_child(cs)
		if b == "Hips":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		elif b in ["LeftLeg", "RightLeg", "LeftForeArm", "RightForeArm"]:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			pb.set("joint_constraints/angular_limit_enabled", true)
			pb.set("joint_constraints/angular_limit_upper", 5.0)
			pb.set("joint_constraints/angular_limit_lower", -130.0)
		else:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", 55.0 if b in ["Head", "Spine1"] else 80.0)
			pb.set("joint_constraints/twist_span", 30.0)
		d.sim.add_child(pb)
		d.bones.append(pb)
	return d

static func _basis_y_to(dir: Vector3) -> Basis:
	var y: Vector3 = dir.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)

## Throw the person seated at `rider` (its origin is the hip, facing -Z, PersonMesh.rider_node)
## off the bike with world velocity `velocity`. Returns the doll, or null if none was free.
func throw(rider: Node3D, velocity: Vector3) -> Doll:
	var src: String = str(rider.get_meta("model_path", ""))
	var d: Doll = _pick(source_of(src))
	if d == null:
		return null
	release(d)
	d.busy = true
	d.since = 0.0
	d.rider = rider
	# The walking model faces +Z with its origin at the feet; the rider node's origin is the hip
	# and faces -Z (traffic direction). Stand the doll so its hips land on the rider's hips.
	var sk: Skeleton3D = d.skeleton
	var hips: int = sk.find_bone("Hips")
	sk.reset_bone_poses()
	_seat(sk)
	var hip_local: Vector3 = (d.root.global_transform.affine_inverse() * sk.global_transform) * sk.get_bone_global_pose(hips).origin
	var facing: Basis = rider.global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI)
	d.root.global_transform = Transform3D(facing, rider.global_position - facing * hip_local)
	d.root.reset_physics_interpolation()
	d.root.visible = true
	d.sim.active = true
	d.sim.physical_bones_start_simulation()
	var v: Vector3 = (velocity + Vector3.UP * THROW_UP_MPS).limit_length(MAX_SPEED_MPS)
	for pb: PhysicalBone3D in d.bones:
		pb.linear_velocity = v
		pb.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0), randf_range(-2.0, 2.0))
	return d

## Sitting pose on the rest skeleton: thighs forward, shins down, upper arms forward. Rotations
## are about the character's own lateral axis in skeleton space, so they don't depend on how
## each bone's local axes happen to point.
func _seat(sk: Skeleton3D) -> void:
	for side: String in ["Left", "Right"]:
		_turn(sk, side + "UpLeg", THIGH_DEG)
		_turn(sk, side + "Leg", KNEE_DEG)
		_turn(sk, side + "Arm", ARM_DEG)
		_turn(sk, side + "ForeArm", -25.0)

func _turn(sk: Skeleton3D, bone: String, deg: float) -> void:
	var bi: int = sk.find_bone(bone)
	if bi < 0:
		return
	var g: Transform3D = sk.get_bone_global_pose(bi)
	var turned: Transform3D = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(deg)) * g.basis, g.origin)
	sk.set_bone_global_pose(bi, turned)

## A free doll of that person if there is one, else the one thrown longest ago (never one that
## was thrown in the last second).
func _pick(source: String) -> Doll:
	var oldest: Doll = null
	for d: Doll in dolls:
		if d.source == source and not d.busy:
			return d
	for d: Doll in dolls:
		if not d.busy:
			oldest = d if oldest == null else oldest
	if oldest != null:
		return oldest
	for d: Doll in dolls:
		if d.since > 1.0 and (oldest == null or d.since > oldest.since):
			oldest = d
	return oldest

## Stop a doll and hide it (KnockedVehicles.give_back, or reuse).
func release(d: Doll) -> void:
	if d == null:
		return
	if d.sim.is_simulating_physics():
		d.sim.physical_bones_stop_simulation()
	d.sim.active = false
	d.skeleton.reset_bone_poses()
	d.root.visible = false
	d.root.position = Vector3(60.0 + float(dolls.find(d)) * 4.0, -240.0, 0.0)
	d.root.reset_physics_interpolation()
	d.busy = false
	d.rider = null

func busy_count() -> int:
	var n: int = 0
	for d: Doll in dolls:
		n += 1 if d.busy else 0
	return n
