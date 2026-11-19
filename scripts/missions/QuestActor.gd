class_name QuestActor
extends Node3D
## One person in a quest story (QuestStory): a street-people model (assets/models/people, the
## pedestrians' rig and clips) that walks or runs to a mark at the model's own pace, plays a clip,
## faces something and can hold a kite. Feet stay on the drawn ground (SignalBus.surface_height).

const PEOPLE_JSON: String = "res://assets/models/people/people.json"
const LOOPING: PackedStringArray = ["walk", "run", "idle", "flee", "flee_look"]
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

static func create(role_name: String, model_path: String, scale_factor: float, paint: Color) -> QuestActor:
	if not ResourceLoader.exists(model_path):
		return null
	var scene: PackedScene = load(model_path) as PackedScene
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
	var name_in: String = clip if _anim.has_animation(clip) else ("idle" if _anim.has_animation("idle") else "")
	if name_in == "":
		return
	_anim.play(name_in, blend)
	_anim.speed_scale = 1.0

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
