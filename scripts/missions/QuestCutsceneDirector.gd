class_name QuestCutsceneDirector
extends Node3D
## Short real-time cinematic beats for SQ001. No quest progress or choice is made here.
## The mission owns acceptance and progression; this layer only frames existing dialogue.
const WEDDING: String = "sq_001"
const SHOTS: Dictionary = {
	"organiser": ["res://assets/models/people/man_casual.glb"],
	"meena": ["res://assets/models/people/woman_saree_maroon.glb"],
	"other": ["res://assets/models/people/woman_saree_violet.glb"],
	"receipt_clue": ["res://assets/models/people/man_casual.glb"],
	"seller": ["res://assets/models/people/old_man_veshti.glb"],
	"decision": ["res://assets/models/people/woman_saree_maroon.glb", "res://assets/models/people/woman_saree_violet.glb"],
	"resolution": ["res://assets/models/people/woman_saree_maroon.glb", "res://assets/models/people/woman_saree_violet.glb"]
}
const SHOT_SECONDS: float = 4.0
const ACTOR_DISTANCE: float = 3.4

var _auto: RigidBody3D
var _rig: CameraRig
var _camera: Camera3D
var _overlay: CanvasLayer
var _container: Control
var _subtitle: Label
var _skip: Button
var _actors: Array[Node3D] = []
var _actor_start: Array[Vector3] = []
var _actor_end: Array[Vector3] = []
var _running: bool = false
var _elapsed: float = 0.0
var _was_frozen: bool = false
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _focus: Vector3 = Vector3.ZERO
var _speed_kmh: float = 0.0
var _stage_id: String = ""

func _ready() -> void:
	_auto = get_parent().get_node_or_null("AutoRickshaw") as RigidBody3D
	_rig = get_parent().get_node_or_null("CameraRig") as CameraRig
	_camera = Camera3D.new()
	_camera.name = "QuestCinematicCamera"
	_camera.fov = 58.0
	_camera.near = 0.1
	_camera.far = 150.0
	add_child(_camera)
	_overlay = CanvasLayer.new()
	_overlay.layer = 24
	add_child(_overlay)
	_container = Control.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_container)
	var top: ColorRect = ColorRect.new()
	top.color = Color(0.01, 0.01, 0.02, 0.9)
	top.anchor_right = 1.0
	top.offset_bottom = 43.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(top)
	var bottom: ColorRect = ColorRect.new()
	bottom.color = Color(0.01, 0.01, 0.02, 0.92)
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -138.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(bottom)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 20)
	_subtitle.add_theme_color_override("font_color", Color.WHITE)
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_right = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_left = 160.0
	_subtitle.offset_right = -160.0
	_subtitle.offset_top = -128.0
	_subtitle.offset_bottom = -12.0
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_subtitle)
	_skip = Button.new()
	_skip.text = tr("QUEST_CINEMATIC_SKIP")
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.offset_left = -130.0
	_skip.offset_right = -14.0
	_skip.offset_top = 8.0
	_skip.offset_bottom = 48.0
	_skip.pressed.connect(skip)
	_container.add_child(_skip)
	_overlay.visible = false
	SignalBus.speed_updated.connect(func(speed: float) -> void: _speed_kmh = speed)
	SignalBus.mission_stage_info.connect(_on_stage)
	SignalBus.mission_finished.connect(func(_id: String, _status: String, _reason: String) -> void: skip())
	SignalBus.mission_profile_loaded.connect(skip)
	SignalBus.mission_ownership_changed.connect(func(active: bool) -> void:
		if not active:
			skip())

static func is_cinematic_stage(quest_id: String, stage_id: String) -> bool:
	return quest_id == WEDDING and SHOTS.has(stage_id)

func _on_stage(info: Dictionary) -> void:
	# A map preview, roadside marker, or Not Now must never invoke a cutscene.
	var id: String = str(info.get("id", ""))
	var stage: String = str(info.get("stage", ""))
	if not is_cinematic_stage(id, stage) or not GameState.mission_active:
		skip()
		return
	if _auto == null or _rig == null or absf(_speed_kmh) > 2.0:
		return
	# Delay until mission is committed; do not mutate mission state or choose for the player.
	skip()
	_stage_id = stage
	_start(str(info.get("objective", "")))

func _start(objective_key: String) -> void:
	_running = true
	_elapsed = 0.0
	_was_frozen = _auto.freeze
	_auto.linear_velocity = Vector3.ZERO
	_auto.angular_velocity = Vector3.ZERO
	_auto.freeze = true
	_make_actors()
	# Put the shot beside the real player auto, not inside a distant mission building.
	var forward: Vector3 = -_auto.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side: Vector3 = _auto.global_transform.basis.x
	side.y = 0.0
	side = side.normalized()
	_focus = _auto.global_position + forward * 1.7 + Vector3.UP * 1.5
	_from = _auto.global_position + forward * 5.6 + side * 5.0 + Vector3.UP * 2.7
	_to = _auto.global_position + forward * 4.6 + side * 3.2 + Vector3.UP * 2.3
	_camera.global_position = _from
	_camera.look_at(_focus, Vector3.UP)
	_camera.make_current()
	_subtitle.text = tr(objective_key)
	_skip.text = tr("QUEST_CINEMATIC_SKIP")
	_overlay.visible = true
	SignalBus.quest_cinematic_changed.emit(true)
	SignalBus.ui_modal_changed.emit(true)

func _make_actors() -> void:
	var models: Array = SHOTS.get(_stage_id, [])
	var forward: Vector3 = -_auto.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side: Vector3 = _auto.global_transform.basis.x
	side.y = 0.0
	side = side.normalized()
	for i: int in models.size():
		var path: String = str(models[i])
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		var person: Node3D = scene.instantiate() as Node3D
		add_child(person)
		var at: Vector3 = _auto.global_position + forward * ACTOR_DISTANCE + side * (float(i) * 1.65 - 0.25)
		at.y = SignalBus.surface_height(at.x, at.z, _auto.global_position.y)
		# Source rigs are at different origin heights; ground the visible feet.
		var lift: float = -QuestMarkers.lowest_point(person)
		var destination: Vector3 = at + Vector3.UP * lift
		var origin: Vector3 = destination + forward * 1.1
		person.global_position = origin
		var face: Vector3 = _auto.global_position - person.global_position
		face.y = 0.0
		if face.length_squared() > 0.01:
			person.look_at(person.global_position + face.normalized(), Vector3.UP, true)
		var animation: AnimationPlayer = person.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animation != null:
			# "talk" is the phone-call clip (QuestActor.PHONE_CLIP): people in a scene talk with their hands.
			for clip: String in QuestActor.TALK_CLIPS + PackedStringArray(["idle"]):
				if animation.has_animation(clip):
					animation.play(clip)
					break
		_actors.append(person)
		_actor_start.append(origin)
		_actor_end.append(destination)

func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	var t: float = smoothstep(0.0, SHOT_SECONDS, _elapsed)
	_camera.global_position = _from.lerp(_to, t)
	_camera.look_at(_focus, Vector3.UP)
	var approach: float = smoothstep(0.0, 1.35, _elapsed)
	for i: int in _actors.size():
		if is_instance_valid(_actors[i]):
			_actors[i].global_position = _actor_start[i].lerp(_actor_end[i], approach)
	if _elapsed >= SHOT_SECONDS:
		skip()

func skip() -> void:
	if not _running:
		return
	_running = false
	_overlay.visible = false
	for actor: Node3D in _actors:
		if is_instance_valid(actor):
			actor.queue_free()
	_actors.clear()
	_actor_start.clear()
	_actor_end.clear()
	if _auto != null and is_instance_valid(_auto):
		_auto.freeze = _was_frozen
	if _rig != null and is_instance_valid(_rig) and _rig._camera != null:
		_rig._camera.make_current()
	SignalBus.quest_cinematic_changed.emit(false)
	SignalBus.ui_modal_changed.emit(false)

func _exit_tree() -> void:
	skip()
