class_name QuestActor
extends Node3D
## One person in a quest story (QuestStory): a street-people model (assets/models/people, the
## pedestrians' rig and clips) that walks or runs to a mark at the model's own pace, plays a clip,
## faces something and can hold a kite. Feet stay on the drawn ground (SignalBus.surface_height).

const PEOPLE_JSON: String = "res://assets/models/people/people.json"
const LOOPING: PackedStringArray = ["walk", "run", "idle", "flee", "flee_look"]
## "talk" in story data means talking to the people in the scene. The street clip named "talk" is
## Mixamo's "Talking" = a PHONE CALL (one hand held at the ear the whole clip), so in quests it
## plays only when a scene asks for "phone" (Nov 25 device report: Sundal thatha and Meena looked
## like they were on the phone in every cutscene). Conversation = these hand-gesture clips, taken
## in turn so a long scene doesn't loop one gesture.
const PHONE: String = "phone"
const PHONE_CLIP: String = "talk"
const TALK_CLIPS: PackedStringArray = ["talk_2", "talk_4"]
const ARRIVE_M: float = 0.2
const TURN_RATE: float = 8.0

static var _people: Dictionary = {}

var role: String = ""
var model_id: String = ""
var height_m: float = 1.6
var body: Node3D
var kite: KiteProp
## "fly": the kite flies high on its string from the hand; "held": the kite is in the hand.
var kite_mode: String = ""
var kite_offset: Vector3 = Vector3(2.5, 11.0, -4.0)
## Clip to play on arriving at a walk target (instead of idle).
var then_clip: String = ""
## Standing on the auto's roof (the kite rescue): height is set by the story, not the ground.
var on_roof: bool = false
var roof_y: float = 0.0
var _anim: AnimationPlayer
var _lift: float = 0.0
var _clip: String = ""
var _target: Vector3 = Vector3.INF
var _gait: String = "walk"
var _pace: float = 1.3
var _face: Vector3 = Vector3.INF
var _scale: float = 1.0
var _t: float = 0.0
var _talk_i: int = 0

static func create(role_name: String, model_path: String, scale_factor: float, paint: Color) -> QuestActor:
	if not ResourceLoader.exists(model_path):
		return null
	var scene: PackedScene = QuestAssets.get_resource(model_path) as PackedScene
	if scene == null:
		return null
	var actor: QuestActor = QuestActor.new()
	actor.name = "Actor_" + role_name
	actor.role = role_name
	actor.model_id = model_path.get_file().get_basename()
	actor._scale = maxf(scale_factor, 0.05)
	actor.body = scene.instantiate() as Node3D
	actor.add_child(actor.body)
	actor.body.scale = Vector3.ONE * actor._scale
	actor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var key: String = PaintSwap.key_of(model_path)
	if key != "" and paint.a > 0.0:
		PaintSwap.prepare(actor.body, key)
		PaintSwap.set_paint(actor.body, paint)
	var players: Array[Node] = actor.body.find_children("*", "AnimationPlayer", true, false)
	actor._anim = players[0] as AnimationPlayer if not players.is_empty() else null
	actor._lift = -QuestMarkers.lowest_point(actor.body) * actor._scale
	actor.body.position = Vector3(0.0, actor._lift, 0.0)
	var info: Dictionary = people_info(actor.model_id)
	actor.height_m = float(info.get("height", 1.6)) * actor._scale
	return actor

static func people_info(id: String) -> Dictionary:
	if _people.is_empty():
		var f: FileAccess = FileAccess.open(PEOPLE_JSON, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_people = ((parsed as Dictionary).get("people", {}) as Dictionary)
	return _people.get(id, {}) as Dictionary

## Native speed of a gait in m/s at this actor's size (the clip's own stride).
func pace_of(gait: String) -> float:
	var info: Dictionary = people_info(model_id)
	var native: float = float(info.get(gait + "_speed", 0.0))
	if native <= 0.0:
		native = float(info.get("walk_speed", 1.3)) * (2.3 if gait == "run" else 1.0)
	return native * _scale

## Fixes QuestWear items (tape, specs, towel, davara, …) to the rig, each where it sits in the idle
## clip, so the same street model reads as this quest's own person. A few draw calls per person:
## only for the handful of story people in a scene, never for street walkers.
func wear(items: Variant) -> void:
	if body == null or not (items is Array or items is PackedStringArray):
		return
	var found: Array[Node] = body.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		_wear_unrigged(items)
		return
	var skel: Skeleton3D = found[0] as Skeleton3D
	if _anim != null and _anim.has_animation("idle"):
		_anim.play("idle", 0.0)
		_anim.seek(0.4, true)
	skel.force_update_all_bone_transforms()
	# Skeleton space -> this person's space, walked up the node chain (works before entering the tree).
	var to_me: Transform3D = Transform3D.IDENTITY
	var n: Node = skel
	while n != null and n != self:
		if n is Node3D:
			to_me = (n as Node3D).transform * to_me
		n = n.get_parent()
	for raw: Variant in items:
		var item: String = str(raw)
		var spec: Dictionary = QuestWear.spec(item)
		if spec.is_empty():
			continue
		if str(spec.get("hold", "")) == "overhead":
			_hold_overhead(item, skel, to_me)
			continue
		var bone: int = skel.find_bone(str(spec["bone"]))
		var follow_name: String = str(spec.get("follow", spec["bone"]))
		var follow: int = skel.find_bone(follow_name)
		if bone < 0 or follow < 0:
			continue
		var place_at: Vector3 = (to_me * skel.get_bone_global_pose(bone)).origin + (spec["at"] as Vector3)
		var bone_me: Transform3D = to_me * skel.get_bone_global_pose(follow)
		var want: Transform3D = Transform3D(Basis.IDENTITY, place_at)
		var att: BoneAttachment3D = BoneAttachment3D.new()
		att.name = "Wear_" + item
		att.bone_name = follow_name
		skel.add_child(att)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = QuestWear.mesh(item)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		att.add_child(mi)
		mi.transform = bone_me.affine_inverse() * want
	if _clip != "":
		play(_clip, 0.0)

## Where the hand closes on an overhead umbrella, from the right shoulder in the person's space
## (+Z front, -X right): a little in, well in front, a hand's length below the shoulder, so the
## elbow is bent and the shaft stands clear of the face.
const OVERHEAD_GRIP: Vector3 = Vector3(0.09, -0.2, 0.3)
## The canopy's centre sits this far above the top of the head, the shaft leaning to it.
const OVERHEAD_CLEAR_M: float = 0.42

## An open umbrella held over the head: the umbrella stands in the person's space (upright, leaning
## from the grip towards the head, so it shelters the head and moves with the person), and a
## HoldPose on the skeleton bends the right arm so the hand is on the shaft in every clip.
func _hold_overhead(item: String, skel: Skeleton3D, to_me: Transform3D) -> void:
	var b_arm: int = skel.find_bone("RightArm")
	var b_head: int = skel.find_bone("Head")
	if b_arm < 0 or b_head < 0:
		return
	var shoulder: Vector3 = (to_me * skel.get_bone_global_pose(b_arm)).origin
	var head: Vector3 = (to_me * skel.get_bone_global_pose(b_head)).origin
	var grip: Vector3 = shoulder + OVERHEAD_GRIP * _scale
	var crown: Vector3 = Vector3(head.x, head.y + 0.2 * _scale + OVERHEAD_CLEAR_M, head.z)
	var axis: Vector3 = (crown - grip).normalized()
	var side: Vector3 = Vector3.FORWARD.cross(axis).normalized() if absf(axis.z) < 0.99 else Vector3.RIGHT
	var basis_up: Basis = Basis(side, axis, side.cross(axis).normalized())
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Wear_" + item
	mi.mesh = QuestWear.mesh(item)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.transform = Transform3D(basis_up, grip)
	var to_skel: Transform3D = to_me.affine_inverse()
	var pose: HoldPose = HoldPose.new()
	pose.name = "HoldPose_" + item
	pose.grip = to_skel * grip
	pose.pole = to_skel * (shoulder + Vector3(-0.35, -0.35, -0.1) * _scale)
	skel.add_child(pose)

## Unrigged models (the constable) have no bones: neck and head items hang from the body root at a fixed height.
const UNRIGGED_ANCHORS: Dictionary = {"Neck": Vector3(0.0, 1.42, 0.0), "Head": Vector3(0.0, 1.6, 0.0)}

func _wear_unrigged(items: Variant) -> void:
	for raw: Variant in items:
		var item: String = str(raw)
		var spec: Dictionary = QuestWear.spec(item)
		if spec.is_empty() or not UNRIGGED_ANCHORS.has(str(spec["bone"])):
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Wear_" + item
		mi.mesh = QuestWear.mesh(item)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		mi.position = (UNRIGGED_ANCHORS[str(spec["bone"])] as Vector3) + (spec["at"] as Vector3)

func place(at: Vector3) -> void:
	_target = Vector3.INF
	global_position = _grounded(at)

func walk_to(to: Vector3, gait: String = "walk") -> void:
	_target = to
	_gait = gait if gait in ["walk", "run", "flee"] else "walk"
	_pace = pace_of("run" if _gait == "flee" else _gait)
	play(_gait)

func arrived() -> bool:
	return _target == Vector3.INF

func face(point: Vector3) -> void:
	_face = point

func play(clip: String, blend: float = 0.25) -> void:
	_clip = clip
	if _anim == null:
		return
	var name_in: String = clip_for(clip)
	if name_in == "":
		return
	_anim.play(name_in, blend)
	_anim.speed_scale = 1.0

## The model clip a story clip name plays: "talk" → a conversation gesture (never the phone call),
## "phone" → the phone call, anything missing → idle.
func clip_for(clip: String) -> String:
	var name_in: String = clip
	if clip == "talk":
		name_in = ""
		for k: int in TALK_CLIPS.size():
			var c: String = TALK_CLIPS[(_talk_i + k) % TALK_CLIPS.size()]
			if _anim.has_animation(c):
				name_in = c
				break
		_talk_i += 1
	elif clip == PHONE:
		name_in = PHONE_CLIP
	return name_in if name_in != "" and _anim.has_animation(name_in) else ("idle" if _anim.has_animation("idle") else "")

## A point at the hand of a raised right arm (reaching up for a kite) or at a hanging hand.
func hand_point(raised: bool = false) -> Vector3:
	var right: Vector3 = global_transform.basis.x.normalized()
	if raised:
		return global_position + Vector3.UP * height_m * 1.18 + right * -0.18 * _scale
	return global_position + Vector3.UP * height_m * 0.55 + right * -0.22 * _scale

func head_point() -> Vector3:
	return global_position + Vector3.UP * height_m * 0.92

func chest_point() -> Vector3:
	return global_position + Vector3.UP * height_m * 0.68

func _process(delta: float) -> void:
	_t += delta
	if _anim != null and not _anim.is_playing() and _clip != "":
		# Gestures (talk, wave) play once in the street; in a scene they keep going.
		play(_clip, 0.0)
	var flat_dir: Vector3 = Vector3.ZERO
	if _target != Vector3.INF:
		var to: Vector3 = _target - global_position
		to.y = 0.0
		var d: float = to.length()
		if d <= ARRIVE_M:
			_target = Vector3.INF
			if _clip in ["walk", "run", "flee"]:
				play(then_clip if then_clip != "" else "idle")
				then_clip = ""
		else:
			flat_dir = to / d
			var p: Vector3 = global_position + flat_dir * minf(_pace * delta, d)
			global_position = _grounded(p)
	var look: Vector3 = flat_dir
	if look == Vector3.ZERO and _face != Vector3.INF:
		look = _face - global_position
		look.y = 0.0
	if look.length_squared() > 0.0004:
		var want: Basis = Basis.looking_at(look.normalized(), Vector3.UP, true)
		global_transform.basis = global_transform.basis.orthonormalized().slerp(want, minf(1.0, TURN_RATE * delta))
	if kite != null and is_instance_valid(kite):
		if kite_mode == "fly":
			var drift: Vector3 = Vector3(sin(_t * 0.4 + float(get_instance_id() % 7)) * 1.2, 0.0, 0.0)
			kite.global_position = kite.global_position.lerp(global_position + kite_offset + drift, minf(1.0, 2.0 * delta))
			kite.string_end = hand_point()
		elif kite_mode == "held":
			# Held at his side and a little behind, so it never fills a close-up.
			var b: Basis = global_transform.basis.orthonormalized()
			kite.global_transform = Transform3D(b.scaled(Vector3.ONE * 0.7), hand_point() + Vector3.UP * 0.15 - b.z * 0.22 - b.x * 0.12)
			kite.string_end = Vector3.INF

func _grounded(p: Vector3) -> Vector3:
	if on_roof:
		return Vector3(p.x, roof_y, p.z)
	return Vector3(p.x, SignalBus.surface_height(p.x, p.z, p.y), p.z)
