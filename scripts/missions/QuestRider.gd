class_name QuestRider
extends Node3D
## The person a side quest is about (MissionDef.rider_model), so the story has someone in it.
##
## Before the quest she sits on a stone ledge at the quest marker. When the quest starts she walks to
## the auto and climbs into the back seat, rides along for the whole quest, and at the end gets out
## and walks to the door (the last stage's place_pos). Riders follow the same rules as fares: nobody
## stays in a burning auto, so on fire she gets out and waits at the roadside until the fire is out
## and the auto stops beside her again. While she isn't aboard the quest's stops don't count
## (SignalBus.quest_rider_aboard_provider, read by MissionDirector).
##
## One rider at a time, one skinned mesh and one AnimationPlayer: about two draw calls plus a shadow.

enum State { NONE, WAITING, BOARDING, ABOARD, OUT, LEAVING }

const SCALE: float = 1.55 # the Tripo model is one unit tall; she is about 1.5 m
## Her hip on the auto's rear bench (AutoRickshawModel space; the auto drives along -Z).
const PASSENGER_HIP: Vector3 = Vector3(0.18, AutoRickshawModel.GROUND_Y + 0.78, 0.46)
const SHOW_WAITING_M: float = 140.0
const BOARD_FROM_M: float = 30.0
const PICKUP_M: float = 9.0
const PICKUP_KMH: float = 3.0
const DRIVE_OFF_KMH: float = 6.0
const WALK_MPS: float = 0.75
const DOOR_SIDE_M: float = 1.05 # where she stands beside the auto to climb in or out
const STEP_BACK_M: float = 4.0 # how far from a burning auto she waits
const LEDGE: Vector3 = Vector3(0.62, 0.48, 0.46)
const SCAN_S: float = 1.0
const WALK_CLIP: String = "walk"
const SIT_CLIP: String = "sit"

@export var director_path: NodePath = NodePath("../MissionDirector")

var director: MissionDirector
var state: State = State.NONE
var quest_id: String = ""
var body: Node3D
var _model_path: String = ""
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _seat_hip: Vector3 = Vector3(0.018, 0.354, 0.014) # hip above her feet in the sit clip
var _walk_native_mps: float = 1.0
var _ledge: Node3D
var _wait_spot: Transform3D
var _walk_target: Vector3
var _walk_follow_auto: bool = false
var _after_walk: State = State.NONE
var _player_pos: Vector3 = Vector3.ZERO
var _has_pose: bool = false
var _speed_kmh: float = 0.0
var _scan: float = 0.0
var _burning: bool = false

func _ready() -> void:
	director = get_node_or_null(director_path) as MissionDirector
	SignalBus.quest_rider_aboard_provider = func() -> bool: return state == State.ABOARD
	SignalBus.player_pose_updated.connect(func(p: Vector3, _h: Vector3) -> void:
		_player_pos = p
		_has_pose = true)
	SignalBus.speed_updated.connect(func(v: float) -> void: _speed_kmh = absf(v))
	SignalBus.mission_ownership_changed.connect(_on_ownership)
	SignalBus.mission_finished.connect(_on_finished)
	SignalBus.vehicle_burning.connect(_on_burning)

func _exit_tree() -> void:
	SignalBus.quest_rider_aboard_provider = Callable()

## The quest this rider belongs to needs her aboard for its stops to count.
func needs_rider(id: String) -> bool:
	return director != null and _definition(id) != null and _definition(id).rider_model != ""

func _definition(id: String) -> MissionDef:
	return director.registry.get_mission(id) if director != null and id != "" else null

func _process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_S
		_update_waiting()
	match state:
		State.BOARDING:
			if _speed_kmh > DRIVE_OFF_KMH:
				_stand_out() # the auto left without her: she waits where she is
			else:
				_walk_target = _door_point()
				if _step_walk(delta):
					_sit_in_auto()
		State.OUT:
			if not _burning and not GameState.is_on_fire() and _auto() != null and _speed_kmh <= PICKUP_KMH \
					and body.global_position.distance_to(_auto().global_position) <= PICKUP_M:
				_start_walk(_door_point(), State.ABOARD, true)
				state = State.BOARDING
		State.LEAVING:
			if _step_walk(delta):
				if _after_walk == State.OUT:
					state = State.OUT
					_stand()
				else:
					_clear()

# --- Waiting at the marker -------------------------------------------------------

## Shows the rider of the nearest available quest sitting at its marker, and hides her when the
## player is far away or another quest owns the career.
func _update_waiting() -> void:
	if state not in [State.NONE, State.WAITING] or director == null or not _has_pose:
		return
	var best: MissionDef = null
	if not GameState.mission_active and not GameState.tutorial_active:
		var best_d: float = SHOW_WAITING_M
		for id: String in director.registry.definitions:
			var d: MissionDef = director.registry.get_mission(id)
			if d.rider_model == "" or not director.registry.available(id, GameState.driver_level(), GameState.mission_completed):
				continue
			var dist: float = _player_pos.distance_to(d.start_anchor)
			if dist < best_d:
				best_d = dist
				best = d
	if best == null:
		if state == State.WAITING:
			_clear()
		return
	if state == State.WAITING and quest_id == best.id:
		return
	_clear()
	if not _spawn(best):
		return
	_wait_spot = _ledge_spot(best.start_anchor)
	_ledge = _make_ledge()
	add_child(_ledge)
	_ledge.global_transform = _wait_spot
	_place_sitting(_wait_spot.origin + Vector3(0.0, LEDGE.y + 0.07, 0.0), _wait_spot.basis.z)
	state = State.WAITING

## A kerb point beside the marker, facing the road.
func _ledge_spot(anchor: Vector3) -> Transform3D:
	var graph: RoadGraph = SignalBus.current_road_graph
	var spot: Vector3 = anchor + Vector3(2.5, 0.0, 0.0)
	var facing: Vector3 = Vector3(-1.0, 0.0, 0.0)
	if graph != null:
		var cp: Dictionary = graph.closest_point(anchor)
		if int(cp["edge"]) >= 0:
			var pd: Array[Vector3] = graph.sample(int(cp["edge"]), float(cp["s"]), 1)
			var left: Vector3 = Vector3(pd[1].z, 0.0, -pd[1].x).normalized()
			var side: float = signf((anchor - pd[0]).dot(left))
			side = side if side != 0.0 else 1.0
			spot = pd[0] + left * side * (graph.edges[int(cp["edge"])].width * 0.5 + 1.3)
			facing = -left * side
	spot.y = SignalBus.surface_height(spot.x, spot.z, anchor.y)
	return Transform3D(Basis.looking_at(facing, Vector3.UP, true), spot)

## A worn granite thinnai for her to wait on (one box, one draw call).
func _make_ledge() -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "Ledge"
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = LEDGE
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.58, 0.52)
	mat.roughness = 0.95
	mi.material_override = mat
	# The box is centred: lift it onto the pavement, a little behind her hip (she faces +Z).
	mi.position = Vector3(0.0, LEDGE.y * 0.5, -0.1)
	holder.add_child(mi)
	return holder

# --- Quest life cycle ------------------------------------------------------------

func _on_ownership(active: bool) -> void:
	if not active or director == null or director.run == null or not needs_rider(director.run.quest_id):
		return
	var id: String = director.run.quest_id
	if state == State.WAITING and quest_id == id and _auto() != null \
			and body.global_position.distance_to(_auto().global_position) <= BOARD_FROM_M:
		_clear_ledge_later()
		_start_walk(_door_point(), State.ABOARD, true)
		state = State.BOARDING
		return
	if state in [State.BOARDING, State.ABOARD, State.OUT] and quest_id == id:
		return
	# Resumed or retried away from the marker: she is already in the auto.
	_clear()
	if _spawn(_definition(id)):
		_sit_in_auto()

func _on_finished(id: String, status: String, _reason: String) -> void:
	if id != quest_id or state in [State.NONE, State.WAITING]:
		return
	var door: Vector3 = Vector3.INF
	if status == "completed":
		var d: MissionDef = _definition(id)
		var last: MissionStage = d.stages[d.stages.size() - 1] if d != null and not d.stages.is_empty() else null
		if last != null and last.place_pos != Vector3.ZERO:
			door = last.place_pos
	_get_out(door, State.NONE)

func _on_burning(on: bool) -> void:
	_burning = on
	if on and state == State.ABOARD:
		_get_out(Vector3.INF, State.OUT)
		SignalBus.hint_requested.emit(tr("RIDER_OUT_FIRE") % _name(), 5.0)

## Climbs out on the kerb side and walks to `to` (a door), or a few steps away from the auto.
func _get_out(to: Vector3, then: State) -> void:
	var auto: AutoRickshawController = _auto()
	if auto != null and state == State.ABOARD:
		var out: Vector3 = _door_point()
		_detach_to_world(out)
	if to == Vector3.INF:
		var away: Vector3 = body.global_position - (auto.global_position if auto != null else body.global_position + Vector3.FORWARD)
		away.y = 0.0
		to = body.global_position + away.normalized() * STEP_BACK_M
	_start_walk(to, then, false)
	state = State.LEAVING

func _stand_out() -> void:
	state = State.OUT
	_stand()
	SignalBus.hint_requested.emit(tr("RIDER_LEFT_BEHIND") % _name(), 4.0)

# --- Body ------------------------------------------------------------------------

func _spawn(d: MissionDef) -> bool:
	if d == null or d.rider_model == "" or not ResourceLoader.exists(d.rider_model):
		return false
	var scene: PackedScene = load(d.rider_model) as PackedScene
	if scene == null:
		return false
	body = scene.instantiate() as Node3D
	body.name = "Rider"
	body.scale = Vector3.ONE * SCALE
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(body)
	quest_id = d.id
	_model_path = d.rider_model
	_anim = body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer if not body.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	_skeleton = body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if not body.find_children("*", "Skeleton3D", true, false).is_empty() else null
	_prepare_clips()
	return true

## Tripo exports `sit.001` / `walk.001` that play once and walk forward. Make looping, in-place
## copies; the node moves by code so her feet stay on the pavement. Where her hip sits and how fast
## she walks are measured on the posed skeleton (track values are bone-local, not model units).
func _prepare_clips() -> void:
	if _anim == null:
		return
	var lib: AnimationLibrary = AnimationLibrary.new()
	for clip: String in _anim.get_animation_list():
		var key: String = WALK_CLIP if clip.begins_with("walk") else (SIT_CLIP if clip.begins_with("sit") else "")
		if key == "":
			continue
		var source: Animation = _anim.get_animation(clip)
		var a: Animation = source.duplicate(true) as Animation
		a.loop_mode = Animation.LOOP_LINEAR
		if key == SIT_CLIP:
			_seat_hip = _hip_at(clip, 0.0)
		else:
			var drift: Vector3 = _hip_at(clip, source.length) - _hip_at(clip, 0.0)
			drift.y = 0.0
			_walk_native_mps = maxf(drift.length() / maxf(source.length, 0.01), 0.05)
			_strip_root_motion(a)
		lib.add_animation(key, a)
	_anim.add_animation_library("rider", lib)
	_anim.stop()

## Her Hip bone in body space (model units, before SCALE) at `time` into `clip`.
func _hip_at(clip: String, time: float) -> Vector3:
	if _skeleton == null:
		return _seat_hip
	_anim.play(clip)
	_anim.seek(time, true)
	_skeleton.force_update_all_bone_transforms()
	var hip: int = _skeleton.find_bone("Hip")
	if hip < 0:
		return _seat_hip
	var world: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(hip).origin
	return body.global_transform.affine_inverse() * world

## Removes the walk clip's forward travel from the Hip track, in that track's own space.
func _strip_root_motion(a: Animation) -> void:
	for t: int in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or not str(a.track_get_path(t)).ends_with(":Hip"):
			continue
		var n: int = a.track_get_key_count(t)
		if n < 2:
			return
		var first: Vector3 = a.track_get_key_value(t, 0) as Vector3
		var last: Vector3 = a.track_get_key_value(t, n - 1) as Vector3
		var drift: Vector3 = Vector3(last.x - first.x, 0.0, last.z - first.z)
		for k: int in n:
			var v: Vector3 = a.track_get_key_value(t, k) as Vector3
			var f: float = a.track_get_key_time(t, k) / maxf(a.length, 0.01)
			a.track_set_key_value(t, k, Vector3(v.x - drift.x * f, v.y, v.z - drift.z * f))

func _play(clip: String, pace: float = 1.0, blend: float = 0.25) -> void:
	if _anim != null and _anim.has_animation("rider/" + clip):
		_anim.play("rider/" + clip, blend)
		_anim.speed_scale = pace

func _stand() -> void:
	if _anim != null:
		_anim.stop()
	if _skeleton != null:
		_skeleton.reset_bone_poses() # the bind pose is a natural standing pose

## Sits with her hip at `hip`, facing `facing`.
func _place_sitting(hip: Vector3, facing: Vector3) -> void:
	var b: Basis = Basis.looking_at(facing, Vector3.UP, true)
	body.global_transform = Transform3D(b.scaled(Vector3.ONE * SCALE), hip - b * (_seat_hip * SCALE))
	_play(SIT_CLIP, 1.0, 0.0)

func _sit_in_auto() -> void:
	var auto: AutoRickshawController = _auto()
	if auto == null or body == null:
		return
	var model: Node3D = auto.get_node_or_null("Model") as Node3D
	var parent: Node3D = model if model != null else auto
	body.reparent(parent, false)
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	var b: Basis = Basis(Vector3.UP, PI) # glTF faces +Z; the auto drives along -Z
	body.transform = Transform3D(b.scaled(Vector3.ONE * SCALE), PASSENGER_HIP - b * (_seat_hip * SCALE))
	_play(SIT_CLIP, 1.0, 0.0) # no blend: a walking pose sliding into the seat reads as a glitch
	_clear_ledge_later()
	state = State.ABOARD

func _detach_to_world(at: Vector3) -> void:
	body.reparent(self, false)
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	at.y = SignalBus.surface_height(at.x, at.z, at.y)
	body.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * SCALE), at)

## Beside the auto on the kerb side (the side she is on, else the left), just behind the middle.
func _door_point() -> Vector3:
	var auto: AutoRickshawController = _auto()
	if auto == null:
		return body.global_position if body != null else Vector3.ZERO
	var t: Transform3D = auto.global_transform
	var right: Vector3 = t.basis.x.normalized()
	var side: float = 1.0
	if body != null and body.get_parent() == self:
		side = signf((body.global_position - t.origin).dot(right))
		side = side if side != 0.0 else 1.0
	var p: Vector3 = t.origin + right * side * DOOR_SIDE_M + t.basis.z.normalized() * 0.35
	p.y = SignalBus.surface_height(p.x, p.z, t.origin.y)
	return p

func _start_walk(to: Vector3, then: State, follow_auto: bool) -> void:
	_walk_target = to
	_after_walk = then
	_walk_follow_auto = follow_auto
	if body.get_parent() != self:
		_detach_to_world(body.global_position)
	elif body.global_position.distance_to(to) > 0.3:
		# Standing up from the ledge: feet on the pavement in front of it.
		var p: Vector3 = body.global_position
		p.y = SignalBus.surface_height(p.x, p.z, p.y)
		body.global_position = p
	_play(WALK_CLIP, WALK_MPS / (_walk_native_mps * SCALE))

## Moves her toward the walk target. True on arrival.
func _step_walk(delta: float) -> bool:
	var to: Vector3 = _walk_target - body.global_position
	to.y = 0.0
	var d: float = to.length()
	if d <= 0.25:
		return true
	var step: Vector3 = to / d * minf(WALK_MPS * delta, d)
	var p: Vector3 = body.global_position + step
	p.y = SignalBus.surface_height(p.x, p.z, p.y)
	body.global_transform = Transform3D(Basis.looking_at(to / d, Vector3.UP, true).scaled(Vector3.ONE * SCALE), p)
	return false

func _clear_ledge_later() -> void:
	if _ledge != null:
		_ledge.queue_free()
		_ledge = null

func _clear() -> void:
	_clear_ledge_later()
	if body != null:
		body.queue_free()
		body = null
	_anim = null
	_skeleton = null
	quest_id = ""
	state = State.NONE

func _auto() -> AutoRickshawController:
	return get_tree().get_first_node_in_group("player_auto") as AutoRickshawController

func _name() -> String:
	var d: MissionDef = _definition(quest_id)
	return tr(d.rider_name_key) if d != null and d.rider_name_key != "" else ""
