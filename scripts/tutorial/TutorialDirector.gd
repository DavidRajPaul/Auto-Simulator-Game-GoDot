class_name TutorialDirector
extends Node3D
## Guided first ride with Murugan Anna (Plan Phase 2). A step machine over the data in
## data/tutorial/first_ride.tres: each step shows a line, spotlights a control and waits until
## the player has actually done the thing (complete_on), never on a timer alone.
##
##   kick_start → pull_out → steer_brake → indicate → horn → pick_up → haggle → follow_gps →
##   drop_off (+₹100 first-savari bonus) → free_roam
##
## While it runs, GameState.tutorial_active tells the rest of the game to keep the world gentle
## (no interstitials, no fuel burn, thin traffic, no random riders, crashes floor at 80 %).
## Everything goes through SignalBus; the UI (TutorialOverlay, TouchHUD spotlight) just listens.
## Progress is saved after every step, so quitting resumes where the player left off.

const DEFAULT_SCRIPT: String = "res://data/tutorial/first_ride.tres"
## The stop line: how far past it counts as "missed" (then it moves further ahead).
const MARKER_OVERSHOOT_M: float = 10.0
const MARKER_LOST_M: float = 160.0
const STOPPED_KMH: float = 2.0
## Road surfaces sit at +0.045…+0.08 (AGENTS.md world layers); the stripe goes just above them.
const MARKER_LIFT_M: float = 0.1

@export var script_path: String = DEFAULT_SCRIPT
## Start automatically for a driver who has not finished it. Never in test runs (persistence
## off) — suites that need it call start() themselves.
@export var auto_start: bool = true

var data: TutorialScript
var active: bool = false
var step_index: int = -1
var step_seconds: float = 0.0
var total_seconds: float = 0.0

var _pending_start: int = -2 # -2 = none, -1 = resume from save, ≥0 = that step
var _hint_timer: float = 0.0
var _done_flag: bool = false
var _ride_done: bool = false
var _indicator_used: bool = false
var _remaining_m: float = INF
var _speed_kmh: float = 0.0
var _player_pos: Vector3 = Vector3.ZERO
var _player_fwd: Vector3 = Vector3.FORWARD
var _have_pose: bool = false
var _marker: Node3D
var _marker_fwd: Vector3 = Vector3.FORWARD
var _marker_half_width: float = 4.0
var _voice: AudioStreamPlayer

func _ready() -> void:
	data = load(script_path) as TutorialScript
	_build_marker()
	_voice = AudioStreamPlayer.new()
	_voice.name = "MentorVoice"
	add_child(_voice)
	SignalBus.speed_updated.connect(func(kmh: float) -> void: _speed_kmh = kmh)
	SignalBus.player_pose_updated.connect(func(p: Vector3, f: Vector3) -> void:
		_player_pos = p
		_player_fwd = Vector3(f.x, 0.0, f.z).normalized() if Vector2(f.x, f.z).length() > 0.01 else _player_fwd
		_have_pose = true)
	SignalBus.engine_restarted.connect(func() -> void: _flag("engine_restarted"))
	SignalBus.signalled_turn.connect(func(_d: int) -> void: _flag("signalled_turn"))
	SignalBus.indicator_changed.connect(func(d: int) -> void:
		if d != 0:
			_indicator_used = true)
	SignalBus.horn_blasted.connect(func(_o: Vector3, _f: Vector3, _r: float, _t: int) -> void: _flag("horn"))
	SignalBus.haggle_started.connect(func(_i: Dictionary, _s: float) -> void: _flag("haggle_started"))
	SignalBus.haggle_resolved.connect(_on_haggle_resolved)
	SignalBus.ride_updated.connect(func(info: Dictionary) -> void: _remaining_m = float(info.get("remaining_m", INF)))
	SignalBus.ride_completed.connect(func(_b: Dictionary) -> void:
		_ride_done = true
		_flag("ride_completed"))
	SignalBus.tutorial_skip_requested.connect(skip)
	SignalBus.tutorial_replay_requested.connect(func() -> void: start(0))
	if auto_start and GameState.persistence_enabled and not bool(GameState.settings.get("first_ride_done", false)):
		_pending_start = -1

# --- Lifecycle ---------------------------------------------------------------------------------

## Begin (or resume) the tutorial. from_step = -1 resumes from the saved step. The actual start
## waits until the road graph and the player auto are live.
func start(from_step: int = -1) -> void:
	_pending_start = from_step
	if is_inside_tree() and _world_ready():
		_begin(from_step)

func skip() -> void:
	if active:
		_finish(true)

func is_running() -> bool:
	return active

func current_step() -> TutorialStep:
	return data.steps[step_index] if active and step_index >= 0 and step_index < data.steps.size() else null

func current_step_id() -> String:
	var s: TutorialStep = current_step()
	return s.id if s != null else ""

## Step to restart from after a reload mid-tutorial.
func resume_index(saved: int) -> int:
	var i: int = clampi(saved, 0, data.steps.size() - 1)
	var to: int = data.steps[i].resume_to
	return to if to >= 0 else i

func _world_ready() -> bool:
	return SignalBus.current_road_graph != null and _have_pose

func _begin(from_step: int) -> void:
	_pending_start = -2
	if data == null or data.steps.is_empty():
		return
	var saved: int = int(GameState.settings.get("first_ride_step", 0))
	var idx: int = resume_index(saved) if from_step < 0 else clampi(from_step, 0, data.steps.size() - 1)
	active = true
	total_seconds = 0.0
	GameState.tutorial_active = true
	GameState.tutorial_min_condition = data.min_condition
	GameState.settings["first_ride_done"] = false
	_enter(idx)

func _finish(skipped: bool) -> void:
	active = false
	_marker.visible = false
	GameState.tutorial_active = false
	GameState.tutorial_min_condition = 0.0
	GameState.settings["first_ride_done"] = true
	GameState.settings["first_ride_step"] = 0
	GameState.save_game()
	SignalBus.tutorial_highlight.emit("")
	SignalBus.tutorial_finished.emit(skipped)
	step_index = -1

# --- Steps ---------------------------------------------------------------------------------------

func _enter(i: int) -> void:
	step_index = i
	step_seconds = 0.0
	_done_flag = false
	_indicator_used = false
	_marker.visible = false
	GameState.settings["first_ride_step"] = i
	GameState.save_game()
	var s: TutorialStep = data.steps[i]
	_hint_timer = s.hint_after_s
	match s.complete_on:
		"engine_restarted":
			SignalBus.engine_switch_off_requested.emit()
		"stop_marker":
			_place_marker(float(s.params.get("ahead_m", 70.0)))
		"horn":
			SignalBus.scripted_traffic_requested.emit(str(s.params.get("spawn", "two_wheeler")), float(s.params.get("ahead_m", 22.0)))
		"haggle_started":
			_ride_done = false
			_remaining_m = INF
			_request_rider(s)
		"ride_completed":
			if _ride_done:
				_done_flag = true # dropped off while the GPS step was still open
	SignalBus.tutorial_step_started.emit({
		"index": i, "count": data.steps.size(), "id": s.id, "line": tr(s.line_key),
		"mentor": tr(data.mentor_name_key), "highlight": s.highlight,
	})
	SignalBus.tutorial_highlight.emit(s.highlight)
	if s.voice_path != "" and ResourceLoader.exists(s.voice_path):
		_voice.stream = load(s.voice_path) as AudioStream
		_voice.play()

func _complete() -> void:
	var s: TutorialStep = data.steps[step_index]
	SignalBus.tutorial_step_completed.emit(s.id, step_seconds)
	if s.complete_on == "ride_completed" and data.completion_bonus_inr > 0:
		GameState.grant_reward("tutorial", data.completion_bonus_inr, 0, data.completion_bonus_id)
	var next: int = step_index + 1
	if next >= data.steps.size():
		_finish(false)
	else:
		_enter(next)

func _flag(kind: String) -> void:
	var s: TutorialStep = current_step()
	if s != null and s.complete_on == kind:
		_done_flag = true

func _on_haggle_resolved(r: Dictionary) -> void:
	var s: TutorialStep = current_step()
	if s == null:
		return
	if bool(r.get("accepted", false)):
		_flag("haggle_accepted")
	elif s.complete_on == "haggle_accepted":
		# Rider walked off (timer ran out): place them again and repeat the pick-up.
		_enter(_index_of("haggle_started", step_index))

func _index_of(complete_on: String, fallback: int) -> int:
	for i: int in data.steps.size():
		if data.steps[i].complete_on == complete_on:
			return i
	return fallback

func _request_rider(s: TutorialStep) -> void:
	SignalBus.scripted_hail_requested.emit({
		"near": _player_pos + _player_fwd * float(s.params.get("ahead_m", 70.0)),
		"archetype": str(s.params.get("archetype", "it_commuter")),
		"trip_min_m": float(s.params.get("trip_min_m", 500.0)),
		"trip_max_m": float(s.params.get("trip_max_m", 750.0)),
	})

func _physics_process(delta: float) -> void:
	if _pending_start != -2 and _world_ready():
		_begin(_pending_start)
	if not active:
		return
	step_seconds += delta
	total_seconds += delta
	var s: TutorialStep = data.steps[step_index]
	if not _done_flag:
		_done_flag = _polled_done(s)
	if _done_flag:
		_complete()
		return
	if s.hint_after_s > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint_timer = s.hint_after_s
			_on_stuck(s)

func _polled_done(s: TutorialStep) -> bool:
	match s.complete_on:
		"speed":
			return _speed_kmh >= float(s.params.get("kmh", 15.0))
		"stop_marker":
			return _check_marker(float(s.params.get("radius_m", 3.0)), float(s.params.get("ahead_m", 70.0)))
		"signalled_turn":
			# No junction coming up? Switching the indicator on and driving a while is enough.
			var fallback: float = float(s.params.get("fallback_s", 45.0))
			return _indicator_used and fallback > 0.0 and step_seconds >= fallback
		"near_destination":
			return _remaining_m <= float(s.params.get("remaining_m", 120.0)) or _ride_done
		"timer":
			return step_seconds >= float(s.params.get("seconds", 6.0))
	return false

func _on_stuck(s: TutorialStep) -> void:
	if s.hint_key != "":
		SignalBus.tutorial_hint.emit(tr(s.hint_key))
	SignalBus.tutorial_highlight.emit(s.highlight) # re-pulse the spotlight
	match s.complete_on:
		"haggle_started":
			_request_rider(s) # drove past her or wandered off: she waves from just ahead again
		"horn":
			SignalBus.scripted_traffic_requested.emit(str(s.params.get("spawn", "two_wheeler")), float(s.params.get("ahead_m", 22.0)))

# --- Stop line ------------------------------------------------------------------------------------

func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "StopLine"
	var stripe: MeshInstance3D = MeshInstance3D.new()
	stripe.name = "Stripe"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.0, 0.05, 1.4)
	stripe.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	stripe.material_override = mat
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(stripe)
	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = "STOP"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.pixel_size = 0.02 # ~2 m tall: readable from 70 m in the chase camera
	label.outline_size = 18
	label.modulate = Color(1.0, 0.95, 0.3)
	label.position = Vector3(0.0, 3.0, 0.0)
	label.no_depth_test = true
	_marker.add_child(label)
	_marker.visible = false
	add_child(_marker)

func marker_position() -> Vector3:
	return _marker.global_position

func _place_marker(ahead_m: float) -> void:
	var graph: RoadGraph = SignalBus.current_road_graph
	var target: Vector3 = _player_pos + _player_fwd * ahead_m
	var pos: Vector3 = target
	var fwd: Vector3 = _player_fwd
	_marker_half_width = 4.0
	if graph != null:
		var cp: Dictionary = graph.closest_point(target)
		if int(cp["edge"]) >= 0:
			var pd: Array[Vector3] = graph.sample(int(cp["edge"]), float(cp["s"]), 1)
			pos = pd[0]
			fwd = pd[1] if pd[1].dot(_player_fwd) >= 0.0 else -pd[1]
			_marker_half_width = graph.edges[int(cp["edge"])].width * 0.5
	_marker_fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	_marker.global_transform = Transform3D(Basis.looking_at(_marker_fwd, Vector3.UP), pos + Vector3(0.0, MARKER_LIFT_M, 0.0))
	(_marker.get_node("Stripe") as MeshInstance3D).scale = Vector3(_marker_half_width * 2.0, 1.0, 1.0)
	_marker.visible = true

func _check_marker(radius_m: float, ahead_m: float) -> bool:
	var rel: Vector3 = _player_pos - _marker.global_position
	rel.y = 0.0
	var along: float = rel.dot(_marker_fwd)
	var left: Vector3 = Vector3(_marker_fwd.z, 0.0, -_marker_fwd.x)
	var lateral: float = absf(rel.dot(left))
	if along > MARKER_OVERSHOOT_M or rel.length() > MARKER_LOST_M:
		SignalBus.tutorial_hint.emit(tr("TUT_STOP_LINE_MISSED"))
		_place_marker(ahead_m) # try again further on
		return false
	return _speed_kmh <= STOPPED_KMH and absf(along) <= radius_m and lateral <= _marker_half_width + 2.0
