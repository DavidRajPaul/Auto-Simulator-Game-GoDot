class_name WaveModifier
extends SkeletonModifier3D
## "Auto!" — raises a character's right arm and waves the hand, on top of whatever the
## AnimationPlayer plays (the idle). Works on any rig from tools/assets/process_people.py
## (bones RightArm / RightForeArm / RightHand), whatever their local axes, by aiming bones in
## skeleton space.

@export var wave_speed: float = 7.0
@export var wave_amount: float = 0.45

var _t: float = 0.0
var _arm: int = -1
var _fore: int = -1
var _hand: int = -1

func _ready() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk != null:
		_arm = sk.find_bone("RightArm")
		_fore = sk.find_bone("RightForeArm")
		_hand = sk.find_bone("RightHand")

func _process_modification() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null or _arm < 0 or _fore < 0 or _hand < 0:
		return
	_t += get_process_delta_time()
	var shoulder: Vector3 = sk.get_bone_global_pose(_arm).origin
	# The waving side: away from the body centre line.
	var side: Vector3 = Vector3(signf(shoulder.x) if absf(shoulder.x) > 0.001 else -1.0, 0.0, 0.0)
	# Upper arm up and out, a little forward (characters face +Z).
	_aim(sk, _arm, _fore, (Vector3.UP * 0.75 + side * 0.55 + Vector3(0.0, 0.0, 0.25)).normalized())
	# Forearm straight up, swinging side to side.
	var w: float = sin(_t * wave_speed) * wave_amount
	_aim(sk, _fore, _hand, (Vector3.UP * cos(w) + side * sin(w) + Vector3(0.0, 0.0, 0.15)).normalized())

## Rotate `bone` (in skeleton space) so the direction to `child` becomes `want`.
func _aim(sk: Skeleton3D, bone: int, child: int, want: Vector3) -> void:
	var g: Transform3D = sk.get_bone_global_pose(bone)
	var cur: Vector3 = sk.get_bone_global_pose(child).origin - g.origin
	if cur.length() < 0.0001:
		return
	var q: Quaternion = Quaternion(cur.normalized(), want)
	sk.set_bone_global_pose(bone, Transform3D(Basis(q) * g.basis, g.origin))
