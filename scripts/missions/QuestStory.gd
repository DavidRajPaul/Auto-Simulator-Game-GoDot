class_name QuestStory
extends Node3D
## Plays the voiced story of a side quest (MissionDef.story, data/missions/QuestStoryData.gd):
## cutscenes with locked controls and their own camera, people and props standing in the world,
## lines spoken from the back seat, and the find-it-and-tap-it search of "spot" stages.
##
## The mission's progress stays in MissionDirector: this node only reports that a cutscene ended
## (SignalBus.mission_cutscene_finished) or that the thing was tapped (mission_spot_requested),
## and the director checks it. Cutscene camera marks are [right, up, forward] metres from the
## auto, "up" measured from the road, so a scene plays wherever the player stopped.
##
## Beat keys (QuestStoryData.cutscenes[id] is an Array of beats, played in order):
##   "cam": {"eye": mark, "eye_to": mark, "look": look, "fov": deg, "cockpit": bool}
##   "line": voice id, "line_at": s, "min_s": s, "max_s": s, "wait": role (until they arrive)
##   "act": {role: {"at", "to", "gait", "anim", "then", "face", "show", "kite", "roof"}}
##   "prop": {id: {"path": [marks], "secs", "to": "hand:<role>", "show", "string"}}
##   "fade_in": s, "fade_out": s, "if_choice": [stage id, choice], "hold": bool
## A mark is [r, u, f], "door" (the kerb-side door), "place:<stage>" (that stage's place_pos),
## "role:<name>" or a world Vector3. A look is a mark, "role:<name>", "prop:<id>" or "auto".

const FADE_DEFAULT_S: float = 0.45
const BEAT_GAP_S: float = 0.35
const DEFAULT_BEAT_S: float = 1.6
const LOOK_SHARPNESS: float = 5.0
const TAP_MAX_S: float = 0.45
const TAP_MOVE_PX: float = 30.0
const TAP_RADIUS_FRAC: float = 0.08 # of the screen height
const TAP_TOP_FRAC: float = 0.1 # top HUD row
const TAP_BOTTOM_FRAC: float = 0.64 # pedals, steering and mini-map below this
const WRONG_COOLDOWN_S: float = 3.5
const MISS_COOLDOWN_S: float = 7.0
const IMPACT_COOLDOWN_S: float = 6.0
const JOLT_COOLDOWN_S: float = 9.0
const HARD_BRAKE_G: float = 0.55
const JOLT_LEVEL: float = 0.9
const LINGER_M: float = 70.0
const STOPPED_KMH: float = 3.0
const DOOR: Vector3 = Vector3(-1.1, 0.0, 0.35) # local to the auto: kerb (left) side, behind the middle
const COCKPIT_EYE: Vector3 = CameraRig.COCKPIT_OFFSET

@export var director_path: NodePath = NodePath("../MissionDirector")
@export var auto_path: NodePath = NodePath("../AutoRickshaw")
@export var rig_path: NodePath = NodePath("../CameraRig")

var director: MissionDirector
var quest_id: String = ""
var stage_id: String = ""
var story: QuestStoryData
var cinematic: bool = false
var holding: bool = false
var actors: Dictionary = {} # role -> QuestActor
var props: Dictionary = {} # id -> KiteProp
var spoken: Dictionary = {} # role -> true once their street line was said
var lines_said: PackedStringArray = PackedStringArray() # every line started, for tests

var _auto: AutoRickshawController
var _rig: CameraRig
var _camera: Camera3D
var _voice: AudioStreamPlayer
var _queue: Array[String] = []
## Seconds left of the line being said. Timed from the file's own length, not the audio driver,
## so beats, subtitles and queued lines stay in step on every device (and in headless tests).
var _voice_left: float = 0.0
var _stalls: Dictionary = {} # role -> MeshInstance3D
var _scene_roles: Dictionary = {} # roles a cutscene brought in
var _lingering: Dictionary = {} # role -> true: walk off, freed once far from the player
var _was_frozen: bool = false
var _frame: Transform3D = Transform3D.IDENTITY
var _beats: Array = []
var _beat_i: int = -1
var _beat_t: float = 0.0
var _beat_len: float = 0.0
var _beat_max: float = 0.0
var _beat_wait: String = ""
var _line_pending: String = ""
var _line_at: float = 0.0
var _fade_out_at: float = -1.0
var _fade_out_s: float = 0.0
var _cam_from: Vector3 = Vector3.ZERO
var _cam_to: Vector3 = Vector3.ZERO
var _look_spec: Variant = null
var _look_now: Vector3 = Vector3.ZERO
var _prop_moves: Dictionary = {} # id -> {"points": PackedVector3Array, "secs": float, "t": float, "hand": String}
var _bark: Dictionary = {}
var _stage_t: float = 0.0
var _idle_next: float = 0.0
var _hint_done: bool = false
var _near_done: bool = false
var _miss_cd: float = 0.0
var _wrong_cd: float = 0.0
var _impact_cd: float = 0.0
var _jolt_cd: float = 0.0
var _speed: float = 0.0
var _pos: Vector3 = Vector3.ZERO
var _stage_target: Vector3 = Vector3.ZERO
var _stage_radius: float = 0.0
var _taps: Dictionary = {} # finger index -> [position, seconds held]
var _roof: float = INF

# Overlay
var _overlay: CanvasLayer
var _bars: Control
var _speaker: Label
var _subtitle: Label
var _skip: Button
var _fade: ColorRect
var _choice_box: HBoxContainer
var _choices: Array[Button] = []
var _ring: TapRing
## Lines said while driving: name and words under the top HUD row, between the quest panel on
## the left and the wallet on the right, over buildings and sky rather than the road.
var _drive_box: VBoxContainer
var _drive_name: Label
var _drive_text: Label
var _drive_left: float = 0.0
const DRIVE_X0: float = 0.29
const DRIVE_X1: float = 0.71
const DRIVE_Y: float = 0.16

func _ready() -> void:
	director = get_node_or_null(director_path) as MissionDirector
	_auto = get_node_or_null(auto_path) as AutoRickshawController
	_rig = get_node_or_null(rig_path) as CameraRig
	_camera = Camera3D.new()
	_camera.name = "StoryCamera"
	_camera.near = 0.08
	_camera.far = 400.0
	add_child(_camera)
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	add_child(_voice)
	_build_overlay()
	SignalBus.quest_cinematic_provider = can_play
	SignalBus.mission_stage_info.connect(_on_stage)
	SignalBus.mission_finished.connect(func(_id: String, _status: String, _reason: String) -> void: end_story())
	SignalBus.mission_profile_loaded.connect(end_story)
	SignalBus.mission_ownership_changed.connect(func(active: bool) -> void:
		if not active:
			end_story())
	SignalBus.speed_updated.connect(func(v: float) -> void: _speed = absf(v))
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void:
		if open and not cinematic:
			_drive_box.visible = false)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _h: Vector3) -> void: _pos = p)
	SignalBus.player_impact.connect(func(_info: Dictionary) -> void: _on_rough("impact"))
	SignalBus.vehicle_dynamics.connect(func(_lat: float, lon: float, jolt: float) -> void:
		if lon < -HARD_BRAKE_G:
			_on_rough("impact")
		elif jolt > JOLT_LEVEL:
			_on_rough("jolt"))

func _exit_tree() -> void:
	if SignalBus.quest_cinematic_provider == Callable(self, "can_play"):
		SignalBus.quest_cinematic_provider = Callable()
	end_story()

# --- Overlay ---------------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 25
	add_child(_overlay)
	_bars = Control.new()
	_bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_bars)
	var top: ColorRect = ColorRect.new()
	top.color = Color(0.0, 0.0, 0.0, 0.94)
	top.anchor_right = 1.0
	top.offset_bottom = 52.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.add_child(top)
	var bottom: ColorRect = ColorRect.new()
	bottom.color = Color(0.0, 0.0, 0.0, 0.94)
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -150.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.add_child(bottom)
	_speaker = UIKit.label("", 18, UIKit.YELLOW, true)
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker.anchor_top = 1.0
	_speaker.anchor_right = 1.0
	_speaker.anchor_bottom = 1.0
	_speaker.offset_top = -142.0
	_speaker.offset_bottom = -116.0
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.add_child(_speaker)
	_subtitle = UIKit.label("", 22, Color.WHITE)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_right = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_left = 140.0
	_subtitle.offset_right = -140.0
	_subtitle.offset_top = -114.0
	_subtitle.offset_bottom = -10.0
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.add_child(_subtitle)
	_choice_box = HBoxContainer.new()
	_choice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice_box.add_theme_constant_override("separation", 18)
	_choice_box.anchor_top = 1.0
	_choice_box.anchor_right = 1.0
	_choice_box.anchor_bottom = 1.0
	_choice_box.offset_left = 40.0
	_choice_box.offset_right = -40.0
	_choice_box.offset_top = -108.0
	_choice_box.offset_bottom = -26.0
	_bars.add_child(_choice_box)
	for i: int in 3:
		var b: Button = UIKit.button("", UIKit.Tone.YELLOW, _choose.bind(i), 19)
		b.custom_minimum_size = Vector2(300, 64)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.visible = false
		_choice_box.add_child(b)
		_choices.append(b)
	_skip = Button.new()
	_skip.theme = UIKit.theme()
	_skip.text = tr("QUEST_CINEMATIC_SKIP")
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.offset_left = -140.0
	_skip.offset_right = -14.0
	_skip.offset_top = 6.0
	_skip.offset_bottom = 46.0
	_skip.pressed.connect(skip)
	_bars.add_child(_skip)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)
	_overlay.visible = false
	var hud: CanvasLayer = CanvasLayer.new()
	hud.layer = 13
	add_child(hud)
	_ring = TapRing.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_ring)
	_drive_box = VBoxContainer.new()
	_drive_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drive_box.add_theme_constant_override("separation", 0)
	hud.add_child(_drive_box)
	_drive_name = UIKit.label("", 16, UIKit.YELLOW, true, 6)
	_drive_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drive_box.add_child(_drive_name)
	_drive_text = UIKit.label("", 20, Color.WHITE, false, 6)
	_drive_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drive_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drive_box.add_child(_drive_text)
	_drive_box.visible = false

# --- Stage flow ------------------------------------------------------------------

## SignalBus.quest_cinematic_provider: true when this node will play that cutscene stage.
func can_play(id: String, stage: String) -> bool:
	if director == null or _auto == null or _rig == null or not is_inside_tree():
		return false
	var def: MissionDef = director.registry.get_mission(id)
	if def == null or def.story == null:
		return false
	var index: int = def.stage_index(stage)
	return index >= 0 and def.stages[index].kind == "cutscene" and def.story.cutscenes.has(def.stages[index].cutscene_id) and not GameState.is_on_fire()

func _on_stage(info: Dictionary) -> void:
	var id: String = str(info.get("id", ""))
	var def: MissionDef = director.registry.get_mission(id) if director != null else null
	if def == null or def.story == null:
		if quest_id != "":
			end_story()
		return
	if id != quest_id:
		end_story()
		quest_id = id
		story = def.story
	stage_id = str(info.get("stage", ""))
	_stage_target = info.get("target", Vector3.ZERO) as Vector3
	var stage: MissionStage = def.stages[def.stage_index(stage_id)]
	_stage_radius = stage.radius_m
	var kind: String = str(info.get("kind", ""))
	var plays: bool = kind == "cutscene" and can_play(id, stage_id)
	var holds: bool = kind == "dialogue" and holding
	if cinematic and not plays and not holds:
		_end_cinematic()
	_refresh_world()
	_start_barks()
	if plays:
		_play_scene(stage.cutscene_id)
	elif holds:
		_show_choices(info.get("choices", PackedStringArray()) as PackedStringArray)

## Everything this story put in the world goes; the camera and controls come back.
func end_story() -> void:
	if cinematic:
		_end_cinematic()
	_voice.stop()
	_voice_left = 0.0
	_queue.clear()
	_drive_box.visible = false
	_drive_left = 0.0
	for role: String in actors.keys():
		_free_actor(role)
	for id: String in props.keys():
		(props[id] as Node).queue_free()
	props.clear()
	_prop_moves.clear()
	_scene_roles.clear()
	_lingering.clear()
	spoken.clear()
	_bark = {}
	quest_id = ""
	stage_id = ""
	story = null

func _definition() -> MissionDef:
	return director.registry.get_mission(quest_id) if director != null and quest_id != "" else null

func _stage_def(id: String) -> MissionStage:
	var def: MissionDef = _definition()
	if def == null:
		return null
	var i: int = def.stage_index(id)
	return def.stages[i] if i >= 0 else null

## Puts the people and props of this stage where they stand, and lets the rest walk off.
func _refresh_world() -> void:
	for role: String in story.cast:
		var c: Dictionary = story.cast[role]
		var here: bool = _in_stage(c)
		if here and not actors.has(role) and c.has("world"):
			var actor: QuestActor = _spawn(role)
			if actor != null:
				actor.place(c["world"] as Vector3)
				if c.has("face"):
					actor.face(c["face"] as Vector3)
				actor.play(str(c.get("anim", "idle")))
				if bool(c.get("kite", false)):
					_give_kite(actor, "fly", c.get("kite_colour", Color(0.86, 0.08, 0.1)) as Color)
				if c.has("stall"):
					_add_stall(role, str(c["stall"]), c["world"] as Vector3, c.get("face", Vector3.INF) as Vector3)
		elif here and actors.has(role):
			_lingering.erase(role)
		elif not here and actors.has(role) and not _scene_roles.has(role):
			_lingering[role] = true
	for id: String in story.props:
		var p: Dictionary = story.props[id]
		var here_p: bool = _in_stage(p)
		if here_p and not props.has(id):
			var kite: KiteProp = _make_kite(p.get("colour", Color(0.86, 0.08, 0.1)) as Color)
			kite.flutter = 0.35
			kite.global_position = p["world"] as Vector3
			kite.string_end = p.get("hang", Vector3.INF) as Vector3
			props[id] = kite
		elif not here_p and props.has(id) and not _held_by_actor(props[id] as KiteProp):
			(props[id] as Node).queue_free()
			props.erase(id)

func _in_stage(entry: Dictionary) -> bool:
	var stages: Variant = entry.get("stages", PackedStringArray())
	return (stages is PackedStringArray and (stages as PackedStringArray).has(stage_id)) or (stages is Array and (stages as Array).has(stage_id))

func _held_by_actor(kite: KiteProp) -> bool:
	for role: String in actors:
		if (actors[role] as QuestActor).kite == kite:
			return true
	return false

func _spawn(role: String) -> QuestActor:
	if actors.has(role):
		return actors[role] as QuestActor
	if story == null or not story.cast.has(role):
		return null
	var c: Dictionary = story.cast[role]
	var actor: QuestActor = QuestActor.create(role, str(c.get("model", "")), float(c.get("scale", 1.0)), c.get("paint", Color(0, 0, 0, 0)) as Color)
	if actor == null:
		return null
	add_child(actor)
	actors[role] = actor
	return actor

func _free_actor(role: String) -> void:
	var actor: QuestActor = actors.get(role) as QuestActor
	if actor != null:
		if actor.kite != null and is_instance_valid(actor.kite):
			for id: String in props.keys():
				if props[id] == actor.kite:
					props.erase(id)
			actor.kite.queue_free()
		actor.queue_free()
	actors.erase(role)
	_lingering.erase(role)
	_scene_roles.erase(role)
	if _stalls.has(role):
		(_stalls[role] as Node).queue_free()
		_stalls.erase(role)

func _add_stall(role: String, kind: String, at: Vector3, face_to: Vector3) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = QuestPlaceKit.mesh(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var dir: Vector3 = (face_to - at) if face_to != Vector3.INF else Vector3.BACK
	dir.y = 0.0
	var yaw: float = atan2(dir.x, dir.z)
	var side: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var p: Vector3 = at + side * 1.4
	mi.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, SignalBus.surface_height(p.x, p.z, 0.0), p.z))
	_stalls[role] = mi

func _make_kite(colour: Color) -> KiteProp:
	var kite: KiteProp = KiteProp.new()
	kite.colour = colour
	add_child(kite)
	return kite

func _give_kite(actor: QuestActor, mode: String, colour: Color) -> void:
	if actor.kite == null or not is_instance_valid(actor.kite):
		actor.kite = _make_kite(colour)
		actor.kite.global_position = actor.global_position + actor.kite_offset
	actor.kite_mode = mode
	actor.kite.flutter = 1.0 if mode == "fly" else 0.3

# --- Cutscenes -------------------------------------------------------------------

func _play_scene(id: String) -> void:
	if not cinematic:
		_begin_cinematic()
	holding = false
	_set_choices_visible(false)
	_frame = _auto_frame()
	_beats = story.cutscenes[id] as Array
	_beat_i = -1
	_next_beat()

func _begin_cinematic() -> void:
	cinematic = true
	_voice.stop()
	_voice_left = 0.0
	_queue.clear()
	var moving: bool = _auto.linear_velocity.length() > 1.0
	_was_frozen = _auto.freeze
	_auto.linear_velocity = Vector3.ZERO
	_auto.angular_velocity = Vector3.ZERO
	_auto.freeze = true
	_overlay.visible = true
	_fade.color.a = 1.0 if moving else 0.0
	_subtitle.text = ""
	_speaker.text = ""
	_skip.text = tr("QUEST_CINEMATIC_SKIP")
	var from: Camera3D = get_viewport().get_camera_3d()
	if from != null and from != _camera:
		_camera.global_transform = from.global_transform
		_camera.fov = from.fov
	_camera.make_current()
	_look_now = _camera.global_position - _camera.global_transform.basis.z * 10.0
	SignalBus.quest_cinematic_changed.emit(true)
	SignalBus.ui_modal_changed.emit(true)

func _end_cinematic() -> void:
	cinematic = false
	holding = false
	_overlay.visible = false
	_fade.color.a = 0.0
	_set_choices_visible(false)
	_prop_moves.clear()
	# Props only a scene used (the swooping kite) go with it; story props and kites in a hand stay.
	for id: String in props.keys():
		if story != null and not story.props.has(id) and not _held_by_actor(props[id] as KiteProp):
			(props[id] as Node).queue_free()
			props.erase(id)
	if _auto != null and is_instance_valid(_auto):
		_auto.freeze = _was_frozen
		_auto.set_cinematic_eye(false)
	if _rig != null and is_instance_valid(_rig) and _rig._camera != null:
		_rig._camera.make_current()
	# People a scene brought in walk off (along the kerb, away from the auto) instead of vanishing.
	for role: String in _scene_roles.keys():
		var actor: QuestActor = actors.get(role) as QuestActor
		if actor == null:
			continue
		if not actor.visible:
			_free_actor(role)
			continue
		var away: Vector3 = actor.global_position - _auto.global_position if _auto != null else Vector3.FORWARD
		away.y = 0.0
		var to: Vector3 = actor.global_position + (away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD) * 25.0
		if SignalBus.walkable(to.x, to.z):
			actor.walk_to(to, "walk")
		_lingering[role] = true
	_scene_roles.clear()
	SignalBus.quest_cinematic_changed.emit(false)
	SignalBus.ui_modal_changed.emit(false)

## The auto's position on the road and its flat heading (-Z forward), frozen for the scene.
func _auto_frame() -> Transform3D:
	var t: Transform3D = _auto.global_transform
	var fwd: Vector3 = -t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD
	var o: Vector3 = t.origin
	o.y = SignalBus.surface_height(o.x, o.z, o.y - 0.8)
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), o)

func _beat_applies(b: Dictionary) -> bool:
	if not b.has("if_choice") or director == null or director.run == null:
		return true
	var cond: Array = b["if_choice"] as Array
	return cond.size() == 2 and str(director.run.flags.get(str(cond[0]), "")) == str(cond[1])

func _next_beat() -> void:
	_beat_i += 1
	while _beat_i < _beats.size() and not _beat_applies(_beats[_beat_i] as Dictionary):
		_beat_i += 1
	if _beat_i >= _beats.size():
		_finish_scene()
		return
	_begin_beat(_beats[_beat_i] as Dictionary)

func _begin_beat(b: Dictionary) -> void:
	_beat_t = 0.0
	if b.has("cam"):
		var cam: Dictionary = b["cam"] as Dictionary
		var cockpit: bool = bool(cam.get("cockpit", false))
		_auto.set_cinematic_eye(cockpit)
		_look_spec = cam.get("look", [0.0, 1.2, 10.0])
		if cockpit:
			_cam_from = _auto.global_transform * COCKPIT_EYE
			_cam_to = _cam_from
		else:
			var raw: Vector3 = _eye(cam.get("eye", [0.0, 1.6, -5.0]))
			_cam_from = _clear_eye(raw, cam.get("eye", []), _resolve_look(_look_spec))
			# A dolly keeps its move, from wherever the clear start ended up.
			_cam_to = _cam_from + (_eye(cam["eye_to"]) - raw if cam.has("eye_to") else Vector3.ZERO)
		_camera.fov = float(cam.get("fov", 70.0 if cockpit else 55.0))
		_camera.global_position = _cam_from
		_look_now = _resolve_look(_look_spec)
		_aim()
	for role: String in (b.get("act", {}) as Dictionary):
		_apply_act(role, (b["act"] as Dictionary)[role] as Dictionary, false)
	for id: String in (b.get("prop", {}) as Dictionary):
		_apply_prop(id, (b["prop"] as Dictionary)[id] as Dictionary, false)
	var fade_in: float = float(b.get("fade_in", 0.0))
	if fade_in > 0.0:
		_fade.color.a = 1.0
		create_tween().tween_property(_fade, "color:a", 0.0, fade_in)
	elif _fade.color.a > 0.0:
		create_tween().tween_property(_fade, "color:a", 0.0, FADE_DEFAULT_S)
	_line_pending = str(b.get("line", ""))
	_line_at = float(b.get("line_at", 0.0))
	var length: float = line_seconds(_line_pending)
	_subtitle.text = ""
	_speaker.text = ""
	_beat_len = maxf(float(b.get("min_s", DEFAULT_BEAT_S)), (_line_at + length + BEAT_GAP_S) if _line_pending != "" else 0.0)
	_beat_max = maxf(_beat_len, float(b.get("max_s", _beat_len + 6.0)))
	_beat_wait = str(b.get("wait", ""))
	_fade_out_s = float(b.get("fade_out", 0.0))
	_fade_out_at = _beat_len - _fade_out_s if _fade_out_s > 0.0 else -1.0
	if _line_pending != "" and _line_at <= 0.0:
		_speak_scene_line()

func _speak_scene_line() -> void:
	var line: String = _line_pending
	_line_pending = ""
	_speaker.text = tr(story.speaker_key(line))
	_subtitle.text = tr("VO_" + line.to_upper())
	_play_voice(line)

func _process(delta: float) -> void:
	_voice_left = maxf(0.0, _voice_left - delta)
	if _drive_left > 0.0:
		_drive_left -= delta
		if _drive_left <= 0.0 or cinematic:
			_drive_box.visible = false
	if _voice_left <= 0.0 and not cinematic and not _queue.is_empty():
		_play_queue()
	_tick_props(delta)
	if cinematic and not holding and _beat_i >= 0 and _beat_i < _beats.size():
		_tick_beat(delta)
	elif not cinematic and quest_id != "":
		_tick_barks(delta)
	_tick_lingering()
	for id: int in _taps.keys():
		(_taps[id] as Array)[1] = float((_taps[id] as Array)[1]) + delta

func _tick_beat(delta: float) -> void:
	_beat_t += delta
	if _line_pending != "" and _beat_t >= _line_at:
		_speak_scene_line()
	var t: float = smoothstep(0.0, maxf(_beat_len, 0.01), _beat_t)
	_camera.global_position = _cam_from.lerp(_cam_to, t)
	_look_now = _look_now.lerp(_resolve_look(_look_spec), 1.0 - exp(-LOOK_SHARPNESS * delta))
	_aim()
	if _fade_out_at >= 0.0 and _beat_t >= _fade_out_at:
		_fade_out_at = -1.0
		create_tween().tween_property(_fade, "color:a", 1.0, maxf(_fade_out_s, 0.05))
	var waiting: bool = _beat_wait != "" and actors.has(_beat_wait) and not (actors[_beat_wait] as QuestActor).arrived()
	var talking: bool = _voice_left > 0.0
	if _beat_t >= _beat_max or (_beat_t >= _beat_len and not waiting and not talking):
		_next_beat()

func _aim() -> void:
	if _camera.global_position.distance_squared_to(_look_now) > 0.0004:
		_camera.look_at(_look_now, Vector3.UP)

func _finish_scene() -> void:
	var last: Dictionary = {}
	for i: int in range(_beats.size() - 1, -1, -1):
		if _beat_applies(_beats[i] as Dictionary):
			last = _beats[i] as Dictionary
			break
	_beat_i = _beats.size()
	var finished_stage: String = stage_id
	holding = bool(last.get("hold", false))
	if not holding:
		_subtitle.text = ""
		_speaker.text = ""
	SignalBus.mission_cutscene_finished.emit(quest_id, finished_stage)
	# The director refused (the stage moved on some other way): never leave the controls locked.
	if cinematic and stage_id == finished_stage and not holding:
		_end_cinematic()

## Skip: everything the rest of the scene would do happens at once.
func skip() -> void:
	if not cinematic or holding:
		return
	_voice.stop()
	_voice_left = 0.0
	_line_pending = ""
	var last_cam: Dictionary = {}
	for i: int in range(maxi(_beat_i, 0), _beats.size()):
		var b: Dictionary = _beats[i] as Dictionary
		if not _beat_applies(b):
			continue
		for role: String in (b.get("act", {}) as Dictionary):
			_apply_act(role, (b["act"] as Dictionary)[role] as Dictionary, true)
		for id: String in (b.get("prop", {}) as Dictionary):
			_apply_prop(id, (b["prop"] as Dictionary)[id] as Dictionary, true)
		if b.has("cam"):
			last_cam = b["cam"] as Dictionary
	if not last_cam.is_empty() and not bool(last_cam.get("cockpit", false)):
		_auto.set_cinematic_eye(false)
		_look_now = _resolve_look(last_cam.get("look", [0.0, 1.2, 10.0]))
		_camera.global_position = _clear_eye(_eye(last_cam.get("eye", [0.0, 1.6, -5.0])), last_cam.get("eye", []), _look_now)
		_aim()
	_fade.color.a = 0.0
	_finish_scene()

func _apply_act(role: String, a: Dictionary, instant: bool) -> void:
	var actor: QuestActor = actors.get(role) as QuestActor
	if actor == null:
		actor = _spawn(role)
		if actor == null:
			return
		_scene_roles[role] = true
		actor.place(_mark(a.get("at", [-3.0, 0.0, 8.0]), true))
	_lingering.erase(role)
	if a.has("roof"):
		actor.on_roof = bool(a["roof"])
		actor.roof_y = roof_height()
	if a.has("show"):
		actor.visible = bool(a["show"])
		if actor.kite != null and is_instance_valid(actor.kite):
			actor.kite.visible = actor.visible
	if a.has("at"):
		actor.place(_mark(a["at"], true))
	if a.has("to"):
		var to: Vector3 = _mark(a["to"], true)
		if instant:
			actor.place(to)
		else:
			actor.then_clip = str(a.get("then", ""))
			actor.walk_to(to, str(a.get("gait", "walk")))
	if a.has("anim") and not (a.has("to") and not instant):
		actor.play(str(a["anim"]))
	elif instant and a.has("then"):
		actor.play(str(a["then"]))
	if a.has("face"):
		actor.face(_face_point(a["face"]))
	if a.has("kite"):
		var k: Variant = a["kite"]
		if k is bool and not bool(k):
			if actor.kite != null and is_instance_valid(actor.kite) and not props.values().has(actor.kite):
				actor.kite.queue_free()
			actor.kite = null
			actor.kite_mode = ""
		elif k is String and props.has(str(k)):
			actor.kite = props[str(k)] as KiteProp
			actor.kite_mode = "held"
			actor.kite.flutter = 0.3
			actor.kite.string_end = Vector3.INF
			actor.kite.visible = actor.visible
		else:
			# true or "fly": a kite flying on its string; any other name: one in the hand.
			_give_kite(actor, "fly" if (k is bool or str(k) == "fly") else "held", Color(0.86, 0.08, 0.1))

func _apply_prop(id: String, p: Dictionary, instant: bool) -> void:
	var kite: KiteProp = props.get(id) as KiteProp
	if kite == null:
		kite = _make_kite(Color(0.86, 0.08, 0.1))
		props[id] = kite
		kite.string_end = Vector3.INF
		kite.flutter = 1.0
	if p.has("show"):
		kite.visible = bool(p["show"])
	if p.has("string") and not bool(p["string"]):
		kite.string_end = Vector3.INF
	if p.has("path"):
		var points: PackedVector3Array = PackedVector3Array()
		for m: Variant in (p["path"] as Array):
			points.append(_mark(m, false))
		if instant or points.size() == 1:
			kite.global_position = points[points.size() - 1]
			_prop_moves.erase(id)
		else:
			kite.global_position = points[0]
			_prop_moves[id] = {"points": points, "secs": float(p.get("secs", 2.0)), "t": 0.0, "hand": ""}
	if p.has("to"):
		var target: String = str(p["to"])
		var parts: PackedStringArray = target.split(":")
		if parts.size() >= 2 and parts[0] == "hand" and actors.has(parts[1]):
			var actor: QuestActor = actors[parts[1]] as QuestActor
			if instant:
				_hand_kite(id, actor)
			else:
				var pts: PackedVector3Array = PackedVector3Array([kite.global_position, actor.hand_point(true)])
				_prop_moves[id] = {"points": pts, "secs": float(p.get("secs", 1.2)), "t": 0.0, "hand": parts[1]}

func _hand_kite(id: String, actor: QuestActor) -> void:
	var kite: KiteProp = props.get(id) as KiteProp
	if kite == null:
		return
	actor.kite = kite
	actor.kite_mode = "held"
	kite.flutter = 0.3
	kite.string_end = Vector3.INF
	_prop_moves.erase(id)

func _tick_props(delta: float) -> void:
	for id: String in _prop_moves.keys():
		var m: Dictionary = _prop_moves[id]
		var kite: KiteProp = props.get(id) as KiteProp
		if kite == null:
			_prop_moves.erase(id)
			continue
		m["t"] = float(m["t"]) + delta
		var f: float = clampf(float(m["t"]) / maxf(float(m["secs"]), 0.01), 0.0, 1.0)
		kite.global_position = _along(m["points"] as PackedVector3Array, f)
		if f >= 1.0:
			var hand: String = str(m["hand"])
			_prop_moves.erase(id)
			if hand != "" and actors.has(hand):
				_hand_kite(id, actors[hand] as QuestActor)

## A smooth path through the points (Catmull-Rom), f from 0 to 1.
static func _along(points: PackedVector3Array, f: float) -> Vector3:
	if points.size() == 1:
		return points[0]
	var span: float = f * float(points.size() - 1)
	var i: int = mini(int(span), points.size() - 2)
	var t: float = span - float(i)
	var p0: Vector3 = points[maxi(i - 1, 0)]
	var p1: Vector3 = points[i]
	var p2: Vector3 = points[i + 1]
	var p3: Vector3 = points[mini(i + 2, points.size() - 1)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)

## A mark to a world point. Actors stand on the ground; cameras are "up" metres above the road.
func _mark(spec: Variant, ground: bool) -> Vector3:
	var p: Vector3 = _frame.origin
	if spec is Vector3:
		p = spec as Vector3
		if not ground:
			return p
	elif spec is Array and (spec as Array).size() == 3:
		var a: Array = spec as Array
		p = _frame * Vector3(float(a[0]), float(a[1]), -float(a[2]))
	elif spec is String:
		var s: String = str(spec)
		if s == "door":
			p = _auto.global_transform * DOOR
		elif s.begins_with("place:"):
			var st: MissionStage = _stage_def(s.substr(6))
			p = st.place_pos if st != null else _frame.origin
		elif s.begins_with("role:") and actors.has(s.substr(5)):
			p = (actors[s.substr(5)] as QuestActor).global_position
	if ground:
		# Never ask anyone to stand inside a building: mirror a blocked kerb mark to the other side.
		if not SignalBus.walkable(p.x, p.z) and spec is Array:
			var a2: Array = spec as Array
			var mirrored: Vector3 = _frame * Vector3(-float(a2[0]), 0.0, -float(a2[2]))
			if SignalBus.walkable(mirrored.x, mirrored.z):
				p = mirrored
		p.y = SignalBus.surface_height(p.x, p.z, _frame.origin.y)
	return p

## A camera position: a mark, or {"from": "role:x" | "prop:x", "toward": "auto", "dist": m,
## "up": m, "side": m} for a shot framed on a person or prop wherever they are.
func _eye(spec: Variant) -> Vector3:
	if spec is Dictionary:
		var d: Dictionary = spec as Dictionary
		var base: Vector3 = _resolve_look(str(d.get("from", "auto")))
		if str(d.get("from", "")).begins_with("role:") and actors.has(str(d["from"]).substr(5)):
			base = (actors[str(d["from"]).substr(5)] as QuestActor).global_position
		var toward: Vector3 = _auto.global_position
		var dir: Vector3 = toward - base
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 0.01 else -_frame.basis.z
		var side: Vector3 = dir.cross(Vector3.UP).normalized()
		var p: Vector3 = base + dir * float(d.get("dist", 5.0)) + side * float(d.get("side", 0.0))
		var ground: float = SignalBus.surface_height(p.x, p.z, _frame.origin.y)
		if str(d.get("from", "")).begins_with("prop:"):
			return Vector3(p.x, base.y + float(d.get("up", 0.0)), p.z)
		return Vector3(p.x, ground + float(d.get("up", 1.4)), p.z)
	return _mark(spec, false)

## Never film from inside a wall or from behind a parked car or a bus: try the shot from the other
## side, then step towards the subject, then lift it, and keep the first clear one.
func _clear_eye(eye: Vector3, spec: Variant, target: Vector3) -> Vector3:
	var tries: Array[Vector3] = [eye]
	if spec is Array and (spec as Array).size() == 3:
		var a: Array = spec as Array
		tries.append(_mark([-float(a[0]), float(a[1]), float(a[2])], false))
	for base: Vector3 in tries.duplicate():
		for f: float in [0.35, 0.6]:
			tries.append(base.lerp(target, f) + Vector3.UP * 0.2)
	tries.append(eye + Vector3.UP * 1.6)
	for p: Vector3 in tries:
		# The subject and the auto both in clear view (a trunk beside the lens hides half the frame).
		if SignalBus.walkable(p.x, p.z) and not _occluded(p, target) and not _occluded(p, _auto.global_position + Vector3.UP * 0.6):
			return p
	return eye

func _resolve_look(spec: Variant) -> Vector3:
	if spec is String:
		var s: String = str(spec)
		if s.begins_with("role:") and actors.has(s.substr(5)):
			return (actors[s.substr(5)] as QuestActor).head_point()
		if s.begins_with("prop:") and props.has(s.substr(5)):
			return (props[s.substr(5)] as Node3D).global_position
		if s == "auto":
			return _auto.global_position + Vector3.UP * 0.5
		return _look_now
	return _mark(spec, false)

func _face_point(spec: Variant) -> Vector3:
	if spec is String:
		var s: String = str(spec)
		if s == "auto":
			return _auto.global_position
		if s == "camera":
			return _camera.global_position
		if s.begins_with("prop:") and props.has(s.substr(5)):
			return (props[s.substr(5)] as Node3D).global_position
	return _resolve_look(spec) if spec is String else _mark(spec, true)

## Top of the auto's canopy (world height), for someone standing on the roof.
func roof_height() -> float:
	var top: float = -INF
	var model: Node = _auto.get_node_or_null("Model")
	if model != null:
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = node as MeshInstance3D
			if not mi.visible or mi.mesh == null:
				continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			# Only the body itself: the pre-built mirror debris waits far away until a crash.
			var c: Vector3 = box.get_center()
			if box.size.length() > 6.0 or Vector2(c.x - _auto.global_position.x, c.z - _auto.global_position.z).length() > 2.5:
				continue
			top = maxf(top, box.end.y)
	return clampf(top, _auto.global_position.y + 0.6, _auto.global_position.y + 1.6) if top > -INF else _auto.global_position.y + 1.05

# --- Choices held in the letterbox -----------------------------------------------

func _show_choices(choices: PackedStringArray) -> void:
	for i: int in _choices.size():
		_choices[i].visible = i < choices.size()
		if i < choices.size():
			_choices[i].text = tr(choices[i])
			_choices[i].set_meta("choice", choices[i])
	_subtitle.visible = false
	_speaker.visible = false
	_skip.visible = false

func _set_choices_visible(on: bool) -> void:
	if not on:
		for b: Button in _choices:
			b.visible = false
		_subtitle.visible = true
		_speaker.visible = true
		_skip.visible = true

func _choose(index: int) -> void:
	if not holding or index >= _choices.size() or not _choices[index].visible:
		return
	_set_choices_visible(false)
	SignalBus.mission_choice_requested.emit(quest_id, stage_id, str(_choices[index].get_meta("choice")))

# --- Voice -----------------------------------------------------------------------

func _language() -> String:
	return "ta" if str(GameState.settings.get("language", "en")) == "ta" else "en"

func line_seconds(line: String) -> float:
	if line == "" or story == null:
		return 0.0
	var path: String = story.voice_path(line, _language())
	var stream: AudioStream = load(path) as AudioStream if path != "" else null
	return stream.get_length() if stream != null else 1.8

func _play_voice(line: String) -> void:
	lines_said.append(line)
	_voice_left = line_seconds(line)
	var path: String = story.voice_path(line, _language())
	var stream: AudioStream = load(path) as AudioStream if path != "" else null
	_voice.stop()
	if stream != null:
		_voice.stream = stream
		_voice.play()

## Says a line from the back seat or the street, after whatever is being said (interrupt: now).
func say(line: String, interrupt: bool = false) -> void:
	if story == null or line == "":
		return
	if interrupt:
		_queue.clear()
		_voice.stop()
		_voice_left = 0.0
	_queue.append(line)
	if _voice_left <= 0.0:
		_play_queue()

func _play_queue() -> void:
	if cinematic or _queue.is_empty() or story == null:
		return
	var line: String = _queue.pop_front()
	_play_voice(line)
	show_drive_line(tr(story.speaker_key(line)), tr("VO_" + line.to_upper()), line_seconds(line) + 0.8)

func show_drive_line(speaker: String, text: String, seconds: float) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_drive_box.position = Vector2(vp.x * DRIVE_X0, vp.y * DRIVE_Y)
	_drive_box.size = Vector2(vp.x * (DRIVE_X1 - DRIVE_X0), 0.0)
	_drive_box.custom_minimum_size = Vector2(vp.x * (DRIVE_X1 - DRIVE_X0), 0.0)
	_drive_name.text = speaker
	_drive_text.text = text
	_drive_left = seconds
	_drive_box.visible = true

# --- Barks: lines while driving --------------------------------------------------

func _start_barks() -> void:
	_bark = story.barks.get(stage_id, {}) as Dictionary
	_stage_t = 0.0
	_hint_done = false
	_near_done = false
	var idle_s: Vector2 = _bark.get("idle_s", Vector2(24.0, 36.0)) as Vector2
	_idle_next = randf_range(idle_s.x, idle_s.y)
	if not cinematic:
		for line: Variant in (_bark.get("enter", []) as Array):
			say(str(line))

func _tick_barks(delta: float) -> void:
	_stage_t += delta
	_miss_cd = maxf(0.0, _miss_cd - delta)
	_wrong_cd = maxf(0.0, _wrong_cd - delta)
	_impact_cd = maxf(0.0, _impact_cd - delta)
	_jolt_cd = maxf(0.0, _jolt_cd - delta)
	var idle: Array = _bark.get("idle", []) as Array
	if not idle.is_empty() and _stage_t >= _idle_next:
		var idle_s: Vector2 = _bark.get("idle_s", Vector2(24.0, 36.0)) as Vector2
		_idle_next = _stage_t + randf_range(idle_s.x, idle_s.y)
		if _voice_left <= 0.0 and _queue.is_empty():
			say(str(idle[randi() % idle.size()]))
	if not _hint_done and _bark.has("hint") and _stage_t >= float(_bark.get("hint_after_s", 45.0)):
		_hint_done = true
		for line: Variant in (_bark["hint"] as Array):
			say(str(line))
	var to_target: float = Vector2(_pos.x - _stage_target.x, _pos.z - _stage_target.z).length()
	if not _near_done and _bark.has("near") and to_target <= float(_bark.get("near_m", 25.0)):
		_near_done = true
		say(str(_bark["near"]))
	if _bark.has("miss") and _miss_cd <= 0.0 and _speed <= 2.0 and to_target <= float(_bark.get("miss_m", 9.0)) and to_target > _stage_radius:
		_miss_cd = MISS_COOLDOWN_S
		say(str(_bark["miss"]), true)
	# People in the street say their piece once when the auto stops beside them.
	for role: String in actors:
		var c: Dictionary = story.cast.get(role, {}) as Dictionary
		if not c.has("line") or spoken.has(role) or not _in_stage(c):
			continue
		var actor: QuestActor = actors[role] as QuestActor
		if _speed <= STOPPED_KMH and actor.global_position.distance_to(_pos) <= float(c.get("near_m", 8.0)):
			spoken[role] = true
			actor.face(_pos)
			actor.play("talk")
			say(str(c["line"]), true)
			if c.has("reply"):
				say(str(c["reply"]))

func _on_rough(kind: String) -> void:
	if cinematic or quest_id == "" or not _bark.has(kind):
		return
	if kind == "impact" and _impact_cd <= 0.0:
		_impact_cd = IMPACT_COOLDOWN_S
		say(str(_bark[kind]), true)
	elif kind == "jolt" and _jolt_cd <= 0.0 and _voice_left <= 0.0:
		_jolt_cd = JOLT_COOLDOWN_S
		say(str(_bark[kind]))

func _tick_lingering() -> void:
	for role: String in _lingering.keys():
		var actor: QuestActor = actors.get(role) as QuestActor
		if actor == null or actor.global_position.distance_to(_pos) > LINGER_M:
			_free_actor(role)

# --- Spot: find it and tap it ----------------------------------------------------

func _spot_stage() -> MissionStage:
	if cinematic or quest_id == "" or director == null or director.run == null or director.run.status != "active":
		return null
	var st: MissionStage = director.current_stage()
	return st if st != null and st.kind == "spot" and st.id == stage_id else null

func _input(event: InputEvent) -> void:
	if _spot_stage() == null:
		_taps.clear()
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_taps[touch.index] = [touch.position, 0.0]
		elif _taps.has(touch.index):
			var down: Array = _taps[touch.index] as Array
			_taps.erase(touch.index)
			if float(down[1]) <= TAP_MAX_S and (down[0] as Vector2).distance_to(touch.position) <= TAP_MOVE_PX:
				try_tap(touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _taps.has(drag.index) and ((_taps[drag.index] as Array)[0] as Vector2).distance_to(drag.position) > TAP_MOVE_PX:
			_taps.erase(drag.index)
	elif event is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_taps[-1] = [mb.position, 0.0]
		elif _taps.has(-1):
			var down2: Array = _taps[-1] as Array
			_taps.erase(-1)
			if float(down2[1]) <= TAP_MAX_S and (down2[0] as Vector2).distance_to(mb.position) <= TAP_MOVE_PX:
				try_tap(mb.position)

## A tap on the screen during a search. Returns what it hit: "found", "decoy", "far", "fast",
## "hidden" or "" (nothing there). Only "found" asks the director to move on.
func try_tap(screen: Vector2) -> String:
	var st: MissionStage = _spot_stage()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if st == null or cam == null:
		return ""
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if screen.y < vp.y * TAP_TOP_FRAC or screen.y > vp.y * TAP_BOTTOM_FRAC:
		return ""
	var best: Dictionary = {}
	var best_d: float = INF
	for entry: Dictionary in _spot_candidates(st.id):
		var point: Vector3 = entry["point"] as Vector3
		if cam.is_position_behind(point):
			continue
		var at: Vector2 = cam.unproject_position(point)
		var top: Vector2 = cam.unproject_position(point + Vector3.UP * float(entry["size"]) * 0.5)
		var allow: float = maxf(TAP_RADIUS_FRAC * vp.y, at.distance_to(top) * 1.3)
		var d: float = at.distance_to(screen)
		if d <= allow and d < best_d:
			best_d = d
			best = entry
	if best.is_empty():
		_ring.show_at(screen, false)
		return ""
	if not bool(best["target"]):
		_ring.show_at(screen, false)
		if _wrong_cd <= 0.0 and (story.barks.get(st.id, {}) as Dictionary).has("wrong"):
			_wrong_cd = WRONG_COOLDOWN_S
			say(str((story.barks[st.id] as Dictionary)["wrong"]), true)
		return "decoy"
	var point2: Vector3 = best["point"] as Vector3
	if Vector2(_pos.x - point2.x, _pos.z - point2.z).length() > st.spot_range_m:
		SignalBus.hint_requested.emit(tr("QUEST_SPOT_CLOSER"), 2.5)
		_ring.show_at(screen, false)
		return "far"
	if _speed > st.spot_max_kmh:
		SignalBus.hint_requested.emit(tr("QUEST_SPOT_SLOWER"), 2.5)
		_ring.show_at(screen, false)
		return "fast"
	if _occluded(cam.global_position, point2):
		_ring.show_at(screen, false)
		return "hidden"
	_ring.show_at(screen, true)
	SignalBus.mission_spot_requested.emit(quest_id, st.id)
	return "found"

## The thing to find and the people it can be mistaken for, as tap targets.
func _spot_candidates(spot_stage: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in story.props:
		var p: Dictionary = story.props[id]
		if props.has(id) and (str(p.get("target_for", "")) == spot_stage or str(p.get("decoy_for", "")) == spot_stage):
			out.append({"point": (props[id] as Node3D).global_position, "size": KiteProp.BODY_H * 1.4,
				"target": str(p.get("target_for", "")) == spot_stage})
	for role: String in actors:
		var c: Dictionary = story.cast.get(role, {}) as Dictionary
		var actor: QuestActor = actors[role] as QuestActor
		if not actor.visible:
			continue
		if str(c.get("target_for", "")) == spot_stage:
			out.append({"point": actor.chest_point(), "size": actor.height_m, "target": true})
		elif str(c.get("decoy_for", "")) == spot_stage:
			out.append({"point": actor.chest_point(), "size": actor.height_m, "target": false})
	return out

func _occluded(from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	if _auto != null:
		query.exclude = [_auto.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.is_empty() and from.distance_to(hit["position"] as Vector3) < from.distance_to(to) - 0.6

## A small ring where the player tapped: green when it found the thing.
class TapRing:
	extends Control
	var _at: Vector2 = Vector2.ZERO
	var _t: float = 1.0
	var _good: bool = false

	func show_at(p: Vector2, good: bool) -> void:
		_at = p
		_t = 0.0
		_good = good
		queue_redraw()

	func _process(delta: float) -> void:
		if _t < 1.0:
			_t = minf(1.0, _t + delta * 2.2)
			queue_redraw()

	func _draw() -> void:
		if _t >= 1.0:
			return
		var c: Color = Color(0.25, 1.0, 0.45) if _good else Color(1.0, 1.0, 1.0)
		c.a = 1.0 - _t
		draw_arc(_at, 18.0 + 30.0 * _t, 0.0, TAU, 32, c, 4.0)
