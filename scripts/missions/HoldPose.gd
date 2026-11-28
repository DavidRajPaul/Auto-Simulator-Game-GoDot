class_name HoldPose
extends SkeletonModifier3D
## Keeps one arm holding something at a fixed point in front of the body (the umbrella shaft in
## SQ17), whatever clip the rest of the body plays. A two-bone reach (upper arm, forearm) to a grip
## point, the elbow bent down and out towards a pole point, applied after the animation each frame.
## Points are in the skeleton's own space (QuestActor converts them from the person's space).
## Nov 28 owner report: the umbrella hung from the hand at the hip; a held umbrella needs the arm
## up, so the arm is posed rather than the umbrella following the hanging hand.

var upper: String = "RightArm"
var fore: String = "RightForeArm"
var hand: String = "RightHand"
var grip: Vector3 = Vector3.ZERO
var pole: Vector3 = Vector3.ZERO

func _process_modification() -> void:
	var skel: Skeleton3D = get_skeleton()
	if skel == null:
		return
	var b_up: int = skel.find_bone(upper)
	var b_fore: int = skel.find_bone(fore)
	var b_hand: int = skel.find_bone(hand)
	if b_up < 0 or b_fore < 0 or b_hand < 0:
		return
	var up_pose: Transform3D = skel.get_bone_global_pose(b_up)
	var s: Vector3 = up_pose.origin
	var e: Vector3 = skel.get_bone_global_pose(b_fore).origin
	var h: Vector3 = skel.get_bone_global_pose(b_hand).origin
	var l1: float = s.distance_to(e)
	var l2: float = e.distance_to(h)
	if l1 < 0.001 or l2 < 0.001:
		return
	var to_target: Vector3 = grip - s
	var dist: float = clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir: Vector3 = to_target.normalized()
	var bend: Vector3 = (pole - s) - dir * (pole - s).dot(dir)
	if bend.length_squared() < 0.000001:
		bend = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	bend = bend.normalized()
	# Law of cosines: the shoulder angle between the reach line and the upper arm.
	var cos_a: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a: float = acos(cos_a)
	var elbow: Vector3 = s + dir * cos(a) * l1 + bend * sin(a) * l1
	skel.set_bone_global_pose(b_up, Transform3D(_turn(e - s, elbow - s) * up_pose.basis, s))
	var fore_pose: Transform3D = skel.get_bone_global_pose(b_fore)
	var h2: Vector3 = skel.get_bone_global_pose(b_hand).origin
	skel.set_bone_global_pose(b_fore, Transform3D(_turn(h2 - fore_pose.origin, s + dir * dist - fore_pose.origin) * fore_pose.basis, fore_pose.origin))

static func _turn(from: Vector3, to: Vector3) -> Basis:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return Basis.IDENTITY
	var f: Vector3 = from.normalized()
	var t: Vector3 = to.normalized()
	if f.dot(t) > 0.99999:
		return Basis.IDENTITY
	if f.dot(t) < -0.99999:
		return Basis(f.cross(Vector3.UP).normalized() if absf(f.y) < 0.9 else Vector3.RIGHT, PI)
	return Basis(Quaternion(f, t))
