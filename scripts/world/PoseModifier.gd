class_name PoseModifier
extends SkeletonModifier3D
## Small procedural poses on top of the idle / walk clip, for any rig from
## tools/assets/process_people.py (bones aimed in skeleton space, like WaveModifier):
##  KOLAM     bent at the waist over the doorstep, right hand tracing the pattern on the ground
##            (how a kolam is drawn standing: from the hips, legs straight, so sarees drape well)
##  UMBRELLA  right forearm raised in front of the chest, holding an umbrella shaft
enum Mode { NONE, KOLAM, UMBRELLA }

var mode: int = Mode.NONE:
	set(value):
		mode = value
		active = value != Mode.NONE

const BEND_RAD: float = 0.5 # per spine joint (three joints: about 85 degrees in all)
const DRAW_SPEED: float = 2.4

var _t: float = 0.0
var _bones: Dictionary = {}

func _ready() -> void:
	active = mode != Mode.NONE
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	for b: String in ["Spine", "Spine1", "Spine2", "Neck", "RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand"]:
		_bones[b] = sk.find_bone(b)

func _process_modification() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null or mode == Mode.NONE or int(_bones.get("RightArm", -1)) < 0:
		return
	_t += get_process_delta_time()
	var shoulder: Vector3 = sk.get_bone_global_pose(int(_bones["RightArm"])).origin
	var side: Vector3 = Vector3(signf(shoulder.x) if absf(shoulder.x) > 0.001 else -1.0, 0.0, 0.0)
	if mode == Mode.KOLAM:
		# Characters face +Z: turning a joint about +X tips the body forward. A slow sway, as
		# the hand moves on to the next dot.
		var bend: float = BEND_RAD + 0.03 * sin(_t * 0.7)
		for b: String in ["Spine", "Spine1", "Spine2"]:
			_turn(sk, int(_bones[b]), Vector3.RIGHT, bend)
		_turn(sk, int(_bones["Neck"]), Vector3.RIGHT, -0.35) # eyes on the pattern, not the feet
		# Right hand down to the ground, pinching flour in small loops.
		var loop: Vector3 = Vector3(sin(_t * DRAW_SPEED) * 0.22, 0.0, cos(_t * DRAW_SPEED * 0.8) * 0.2)
		var reach: Vector3 = (Vector3(0.0, -1.0, 0.3) + side * 0.12 + loop).normalized()
		_aim(sk, int(_bones["RightArm"]), int(_bones["RightForeArm"]), reach)
		_aim(sk, int(_bones["RightForeArm"]), int(_bones["RightHand"]), (reach + Vector3(0.0, -0.2, 0.1)).normalized())
		# Left hand holds the flour bowl against the knee.
		_aim(sk, int(_bones["LeftArm"]), int(_bones["LeftForeArm"]), (Vector3(0.0, -1.0, 0.25) - side * 0.1).normalized())
		_aim(sk, int(_bones["LeftForeArm"]), int(_bones["LeftHand"]), (Vector3(0.0, -0.5, 0.8) + side * 0.3).normalized())
	else:
		_aim(sk, int(_bones["RightArm"]), int(_bones["RightForeArm"]), (Vector3(0.0, -0.85, 0.42) + side * 0.12).normalized())
		_aim(sk, int(_bones["RightForeArm"]), int(_bones["RightHand"]), (Vector3(0.0, 0.92, 0.36) - side * 0.12).normalized())

## Turn `bone` about `axis` (skeleton space) through its own origin.
func _turn(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0:
		return
	var g: Transform3D = sk.get_bone_global_pose(bone)
	sk.set_bone_global_pose(bone, Transform3D(Basis(axis, angle) * g.basis, g.origin))

## Rotate `bone` (in skeleton space) so the direction to `child` becomes `want`.
func _aim(sk: Skeleton3D, bone: int, child: int, want: Vector3) -> void:
	if bone < 0 or child < 0:
		return
	var g: Transform3D = sk.get_bone_global_pose(bone)
	var cur: Vector3 = sk.get_bone_global_pose(child).origin - g.origin
	if cur.length() < 0.0001:
		return
	var q: Quaternion = Quaternion(cur.normalized(), want)
	sk.set_bone_global_pose(bone, Transform3D(Basis(q) * g.basis, g.origin))
