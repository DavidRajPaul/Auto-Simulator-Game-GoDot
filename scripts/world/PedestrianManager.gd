class_name PedestrianManager
extends Node3D
## Chennai people on the pavements around the player: a fixed pool of animated characters
## (assets/models/people, made by tools/assets/process_people.py) that walk the road edges of the
## real OSM road graph, turn at junctions, and stand idle at the kerb.
##
## Walking properly: every character's in-place walk has a measured true pace (people.json).
## A walker's speed and its animation playback rate are set together (speed_scale = pace / native
## pace), so feet stay planted - no sliding. Position is eased through corners and facing turns
## at a human rate.
##
## Budget: POOL characters, 1 draw call each (one atlas, one primitive, auto LODs on import);
## only the nearest SHADOW_COUNT cast shadows; animation stops for anyone off-screen or far.
## Pooled - nothing is instanced or freed while driving.

const PEOPLE_DIR: String = "res://assets/models/people/"
const META_FILE: String = "res://assets/models/people/people.json"
# Chennai pavements should feel inhabited without blowing the mobile draw-call
# budget.  Keep the same pooled/LOD approach and add ten more walkers.
const POOL: int = 30
const IDLE_SHARE: float = 0.3
const SPAWN_MIN_M: float = 22.0
const SPAWN_MAX_M: float = 95.0
## People are recycled past DESPAWN_M only when off screen (on screen: past DESPAWN_FAR_M), and
## only appear on screen beyond SPAWN_ON_SCREEN_M — nobody pops in or vanishes in view.
const DESPAWN_M: float = 70.0
const DESPAWN_FAR_M: float = 125.0
const SPAWN_ON_SCREEN_M: float = 75.0
const VISIBLE_M: float = 130.0
const ANIMATE_M: float = 55.0
const SHADOW_COUNT: int = 2
const SHADOW_M: float = 23.0
const KERB_GAP_M: float = 1.2
## Closest a walker comes to the carriageway when a building leaves no pavement.
const ROAD_EDGE_M: float = 0.35
const BODY_M: float = 0.35
const IDLE_JUNCTION_CLEAR_M: float = 14.0
const KERB_SPREAD_M: float = 0.9
const WALK_Y: float = 0.08
## Limit abrupt height changes from overlapping sidewalk/terrain surface samples.
const GROUND_FOLLOW_MPS: float = 0.65
const TURN_RATE: float = 5.0
const UPDATE_S: float = 0.6
## Startle: an auto closing in fast makes walkers stop and step away from the road.
const STARTLE_M: float = 4.5
const STARTLE_SPEED_MPS: float = 2.0
## Comfortable street paces (m/s) per character; playback follows.
const PACE: Dictionary = {"old_man_veshti": Vector2(0.85, 1.0)}
const DEFAULT_PACE: Vector2 = Vector2(1.1, 1.35)
## Mixamo clips (tools/assets/add_mixamo_clips.py): a few walkers jog ("run"); anyone a moving
## vehicle — the player or traffic — is about to brush past jumps back ("dodge") or stumbles and
## falls ("stumble" → "fallen" on the road for a few seconds → back on their feet).
const RUN_SHARE: float = 0.07
const RUN_PACE: Vector2 = Vector2(0.9, 1.08) # × the clip's own pace
## Look-ahead to a vehicle, and how close its path must pass to count as "very close".
const REACT_M: float = 7.0
const NEAR_MISS_M: float = 1.7
const REACT_AHEAD_S: float = 1.1
const STUMBLE_SHARE: float = 0.3
const HIT_SPEED_MPS: float = 4.0
const FALLEN_S: Vector2 = Vector2(2.5, 4.5)
const GET_UP_BLEND_S: float = 0.7
## Clips in which the body is on the ground, and how far the node is raised for each (the
## stumble clip swings the forearms 15 cm under the node, lying puts the hands at node height).
const DOWN_CLIPS: Array[String] = ["stumble", "fallen", "get_up"]
const DOWN_LIFT_M: Dictionary = {"stumble": 0.17, "fallen": 0.08, "get_up": 0.05}
const DOWN_REACH_M: float = 0.85
const DOWN_LIFT_MPS: float = 0.5
## Standing people now and then do one Mixamo gesture (talking on a phone, sipping, waving at an
## auto). A gesture plays once, then they go back to standing; the gap is random per person.
const GESTURE_CLIPS: Array[String] = ["talk", "drink", "wave"]
## Two people chatting at the kerb (Nov 14, the owner's Talking_2 / Talking_4 Mixamo clips):
## a share of idlers get a partner standing CHAT_GAP_M away, face to face; they take turns, one
## talking (a talk clip) while the other listens (idle, now and then nodding into a talk clip
## too), swapping every CHAT_TURN_S. Either one reacting, fleeing or leaving ends the chat.
const CHAT_CLIPS: Array[String] = ["talk", "talk_2", "talk_4"]
const CHAT_SHARE: float = 0.55
const CHAT_GAP_M: float = 1.05
const CHAT_TURN_S: Vector2 = Vector2(3.5, 8.0)
## Shopkeepers and customers (ShopPeople, a static mesh) near a burning auto hand over to these
## pooled walkers, who then run like everyone else (SignalBus.shop_people_scattered).
const SCATTER_MAX: int = 8
const GESTURE_GAP_S: Vector2 = Vector2(6.0, 14.0)
## A burning auto scares everyone within FIRE_SCARE_M: they run straight away from it for FLEE_S.
const FIRE_SCARE_M: float = 22.0
const FLEE_S: Vector2 = Vector2(5.0, 8.0)
const FLEE_PACE: Vector2 = Vector2(1.0, 1.15) # × the clip's own pace, so the legs stay natural
const SCREAM_FILES: Array[String] = [
	"res://assets/audio/people/scream_1.ogg", "res://assets/audio/people/scream_2.ogg",
	"res://assets/audio/people/scream_3.ogg", "res://assets/audio/people/scream_4.ogg",
]
## Fire panic is one crowd moment, not a queue. When the auto catches fire, everyone in range
## screams together: up to PANIC_BURST voices, each starting a little apart (PANIC_ONSET_S) at its
## own pitch, so they overlap like a crowd. After that, someone who walks up to the fire late
## screams at most once every PANIC_LATE_GAP_S, and nobody screams twice for the same fire.
const SCREAM_VOICES: int = 6
const PANIC_BURST: int = 5
const PANIC_ONSET_S: Vector2 = Vector2(0.0, 0.45)
const PANIC_LATE_GAP_S: Vector2 = Vector2(2.5, 5.0)
## The recordings are women's voices; men get them lower so they don't sound like the women.
const MALE_PITCH: Vector2 = Vector2(0.74, 0.86)
const FEMALE_PITCH: Vector2 = Vector2(0.95, 1.12)
const SCREAM_DB: Vector2 = Vector2(-4.0, 0.0)
## Only traffic this close to the player can upset anyone (walkers further away aren't animated).
const THREAT_M: float = 60.0
## The auto's footprint for a body hit: a person it reaches (and who did not dodge in time) is struck.
const BUMP_HALF_WIDTH_M: float = 0.95
const BUMP_HALF_LENGTH_M: float = 1.5
const BUMP_MIN_MPS: float = 1.5
const BUMP_COOLDOWN_S: float = 1.0
## How many pool slots each character gets per round (Chennai pavements are mostly men).
## --- Time of day and weather (Nov 14 owner request: "liveliness must be realistic") ---------
## Early morning: women draw the kolam at their doorstep (dress "kolams", PoseModifier.KOLAM).
const KOLAM_MINUTES: Vector2 = Vector2(325.0, 455.0) # 05:25 - 07:35
const KOLAM_MAX: int = 4
const KOLAM_STAND_M: float = 0.85
const WOMEN: Array[String] = ["woman_saree_green", "woman_saree_maroon", "woman_saree_violet", "woman_modern", "girl_churidar"]
## Rain: walkers run to the nearest shop front and wait there; some open an umbrella and walk
## on; the rest hurry. Noon sun: a few women walk under an umbrella too.
const SHELTER_REACH_M: float = 45.0
const SHELTER_ARRIVE_M: float = 0.7
const SHELTER_PACE_MPS: float = 2.6
const RAIN_UMBRELLA_SHARE: float = 0.4
const SUN_UMBRELLA_SHARE: float = 0.2
const SUN_MINUTES: Vector2 = Vector2(660.0, 930.0) # 11:00 - 15:30
## Shopping bags (Nov 14 owner request: "more variations of the NPCs, shopping bags on some"):
## about a third of walkers carry one or two, re-rolled every spawn. Chennai's yellow cloth
## manja pai, printed cloth bags, white and blue plastic carry bags, a jute bag. All bags are
## ONE MultiMesh hung from the hand bones each frame (one draw call, as for umbrellas).
const BAG_SHARE: float = 0.35
const TWO_BAG_SHARE: float = 0.25
const BAG_COLOURS: Array[Color] = [Color(0.95, 0.78, 0.12), Color(0.95, 0.78, 0.12), Color(0.93, 0.93, 0.9), Color(0.25, 0.45, 0.8),
	Color(0.62, 0.48, 0.3), Color(0.75, 0.15, 0.2), Color(0.2, 0.55, 0.35), Color(0.95, 0.5, 0.65)]
## Bag sizes (width, height, depth m): small carry bag, cloth bag, big shopping bag.
const BAG_SIZES: Array[Vector3] = [Vector3(0.24, 0.3, 0.1), Vector3(0.32, 0.36, 0.1), Vector3(0.4, 0.42, 0.14)]

const UMBRELLA_COLOURS: Array[Color] = [Color(0.06, 0.06, 0.07), Color(0.06, 0.06, 0.07), Color(0.08, 0.1, 0.25), Color(0.55, 0.08, 0.1),
	Color(0.1, 0.35, 0.2), Color(0.85, 0.3, 0.5), Color(0.9, 0.75, 0.2)]

const SHARE: Dictionary = {
    "young_man": 3, "man_casual": 2, "old_man_veshti": 3, "girl_churidar": 2,
    "woman_modern": 2, "woman_saree_violet": 2, "woman_saree_green": 2,
    "woman_saree_maroon": 2, "girl_pavadai": 2,
    "man_dhoti_new": 3, "man_pattern_shirt": 3, "woman_saree_new": 3
}

var graph: RoadGraph
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var people: Array[Walker] = []
var _scenes: Array[PackedScene] = []
var _ids: Array[String] = []
var _native_pace: Dictionary = {}
var _player: Vector3 = Vector3.ZERO
var _player_fwd: Vector3 = Vector3.FORWARD
var _player_vel: Vector3 = Vector3.ZERO
var _last_player: Vector3 = Vector3.ZERO
var _has_player: bool = false
var _timer: float = 0.0
var _run_pace: Dictionary = {}
var _flee_look_pace: Dictionary = {}
var _flee_pace: Dictionary = {}
var _fire_on: bool = false
var _screams: Array[AudioStreamPlayer3D] = []
var _scream_streams: Array[AudioStream] = []
var _scream_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Screams waiting for their onset: [seconds left, position, character id].
var _panic_pending: Array[Array] = []
## True from the moment the auto catches fire until the first scare check: that check is the burst.
var _panic_burst: bool = false
var _late_scream_in: float = 0.0
## id -> {clip: Vector3(local x, local z, seconds)}: where each root-motion clip leaves the body.
var _moves: Dictionary = {}
var _heights: Dictionary = {}
## One MultiMesh for every open umbrella (one draw call, hidden when nobody carries one).
var _umbrellas: MultiMeshInstance3D = null
## One MultiMesh for every shopping bag being carried.
var _bags: MultiMeshInstance3D = null
var _traffic: ChennaiTrafficManager
var _prev_traffic: Dictionary = {}
## [position, velocity] of every moving vehicle near the player, refreshed each frame.
var _threats: Array[Array] = []

## One pooled person.
class Walker:
	var node: Node3D
	var anim: AnimationPlayer
	var mesh: MeshInstance3D
	var id: String = ""
	var active: bool = false
	var idle: bool = false
	var edge: int = 0
	var dir: int = 1
	var s: float = 0.0
	var side: float = 1.0 # +1 = left of the travel direction, -1 = right
	var kerb: float = 0.0
	var pace: float = 1.2
	var pos: Vector3 = Vector3.ZERO
	var heading: Vector3 = Vector3.FORWARD
	var startle: float = 0.0
	var dodge: Vector3 = Vector3.ZERO
	var recovery: float = 0.0
	var running: bool = false
	## "" or the clip playing: "dodge", "stumble", "fallen", "get_up", "gesture".
	var react: String = ""
	var react_t: float = 0.0
	var move: Vector3 = Vector3.ZERO
	## Standing people: seconds until their next gesture.
	var gesture_in: float = 0.0
	## Running away from a fire: the clip, its pace, the direction and the time left.
	var fleeing: bool = false
	var flee_clip: String = ""
	var flee_pace: float = 2.2
	var flee_dir: Vector3 = Vector3.FORWARD
	var flee_t: float = 0.0
	var paintable: bool = false
	## Already screamed at the current fire (cleared when a new fire starts or it goes out).
	var fire_screamed: bool = false
	var paint: Color = Color(0, 0, 0, 0)
	## Extra height while stumbling / lying / getting up (see _apply).
	var lift: float = 0.0
	## "" (walker / idler), "kolam" (drawing at a doorstep) or "shelter" (out of the rain).
	var role: String = ""
	var goal: Vector3 = Vector3.ZERO
	var goal_heading: Vector3 = Vector3.FORWARD
	var sheltered: bool = false
	var umbrella: bool = false
	var umbrella_colour: Color = Color(0.06, 0.06, 0.07)
	var pose: PoseModifier = null
	## 0 none, 1 right hand, 2 both hands; colour and size per hand.
	var bags: int = 0
	var bag_colours: Array[Color] = [Color.WHITE, Color.WHITE]
	var bag_sizes: Array[int] = [0, 0]
	var skeleton: Skeleton3D = null
	var hand_bones: Array[int] = [-1, -1]
	## Chat partner (another Walker) while role == "chat"; talking now or listening; turn timer.
	var partner: Walker = null
	var talking: bool = false
	var chat_t: float = 0.0
	var height: float = 1.6

func _ready() -> void:
	rng.seed = 600028
	_scream_rng.seed = 600029
	SignalBus.vehicle_burning.connect(_on_vehicle_burning)
	SignalBus.shop_people_scattered.connect(_on_shop_people_scattered)
	_setup_screams()
	_load_people()
	var slots: Array[int] = []
	for k: int in _scenes.size():
		for n: int in int(SHARE.get(_ids[k], 1)):
			slots.append(k)
	for i: int in POOL:
		if _scenes.is_empty() or slots.is_empty():
			break
		var k: int = slots[i % slots.size()]
		var w: Walker = Walker.new()
		w.id = _ids[k]
		w.node = _scenes[k].instantiate() as Node3D
		w.node.name = "Person_%d_%s" % [i, w.id]
		# Moved every rendered frame in _process (not in physics ticks): no physics interpolation.
		w.node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(w.node)
		w.anim = w.node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		w.mesh = w.node.find_child("Body", true, false) as MeshInstance3D
		# Dress and saree colours vary per spawn (PaintSwap: the garment's block in the texture).
		w.paintable = PaintSwap.prepare(w.node, w.id) > 0
		if w.mesh != null:
			w.mesh.visibility_range_end = VISIBLE_M
			w.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sk: Skeleton3D = w.node.find_child("Skeleton3D", true, false) as Skeleton3D
		if sk != null:
			w.skeleton = sk
			w.hand_bones = [sk.find_bone("RightHand"), sk.find_bone("LeftHand")]
			w.pose = PoseModifier.new()
			w.pose.name = "Pose"
			sk.add_child(w.pose)
		w.height = float(_heights.get(w.id, 1.6))
		w.node.visible = false
		people.append(w)
	_build_umbrellas()
	_build_bags()
	SignalBus.weather_changed.connect(_on_weather)
	SignalBus.road_graph_ready.connect(func(g: RoadGraph) -> void: graph = g)
	if SignalBus.current_road_graph != null:
		graph = SignalBus.current_road_graph
	SignalBus.player_pose_updated.connect(_on_player)
	_traffic = get_parent().get_node_or_null("ChennaiTrafficManager") as ChennaiTrafficManager

func _load_people() -> void:
	var f: FileAccess = FileAccess.open(META_FILE, FileAccess.READ)
	if f == null:
		push_warning("PedestrianManager: no people.json - run tools/assets/process_people.py")
		return
	var meta: Dictionary = (JSON.parse_string(f.get_as_text()) as Dictionary).get("people", {})
	var ids: Array = meta.keys()
	ids.sort()
	for id: Variant in ids:
		var path: String = PEOPLE_DIR + str(id) + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		_scenes.append(scene)
		_ids.append(str(id))
		var info: Dictionary = meta[id]
		_native_pace[str(id)] = maxf(float(info.get("walk_speed", 1.2)), 0.1)
		_heights[str(id)] = float(info.get("height", 1.6))
		if info.has("run_speed"):
			_run_pace[str(id)] = maxf(float(info["run_speed"]), 0.1)
		if info.has("flee_look_speed"):
			_flee_look_pace[str(id)] = maxf(float(info["flee_look_speed"]), 0.1)
		if info.has("flee_speed"):
			_flee_pace[str(id)] = maxf(float(info["flee_speed"]), 0.1)
		var mv: Dictionary = {}
		for clip: String in (info.get("moves", {}) as Dictionary):
			var m: Array = info["moves"][clip]
			mv[clip] = Vector3(float(m[0]), float(m[1]), float(m[2]))
		_moves[str(id)] = mv

func _on_player(p: Vector3, f: Vector3) -> void:
	_player = p
	_player_fwd = f
	_has_player = true

func _process(delta: float) -> void:
	if graph == null or not _has_player or delta <= 0.0:
		return
	_player_vel = (_player - _last_player) / delta if _last_player != Vector3.ZERO else Vector3.ZERO
	_last_player = _player
	_gather_threats(delta)
	_check_player_bumps()
	_check_fire_scares()
	_step_screams(delta)
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_S
		_recycle()
	for w: Walker in people:
		if w.active:
			_step(w, delta)
	_place_umbrellas()
	_place_bags()

## Free far people and place inactive ones on pavements ahead of the player.
func _recycle() -> void:
	var near: Array[Array] = []
	for w: Walker in people:
		if w.active:
			var dd: float = w.pos.distance_to(_player)
			if dd > DESPAWN_FAR_M or (dd > DESPAWN_M and not ViewCheck.on_screen(get_viewport(), w.pos + Vector3(0, 0.9, 0), 1.2)):
				_deactivate(w)
		if not w.active:
			_spawn(w)
		if w.active:
			var d: float = w.pos.distance_to(_player)
			near.append([d, w])
			var animate: bool = d < ANIMATE_M
			if w.anim != null and w.anim.active != animate:
				w.anim.active = animate
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i: int in near.size():
		var w: Walker = near[i][1]
		if w.mesh != null:
			var on: bool = i < SHADOW_COUNT and float(near[i][0]) < SHADOW_M
			w.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _spawn(w: Walker) -> bool:
	_roll_bags(w)
	w.role = ""
	w.sheltered = false
	w.umbrella = false
	_set_pose(w)
	if _kolam_time() and WOMEN.has(w.id) and _role_count("kolam") < KOLAM_MAX and rng.randf() < 0.7:
		return _spawn_kolam(w)
	# All around the player (not only ahead): off-screen spots are mostly to the sides / behind.
	var cands: Array[Dictionary] = graph.spawn_candidates(_player, Vector3.ZERO, SPAWN_MIN_M, SPAWN_MAX_M)
	if cands.is_empty():
		return false
	var c: Dictionary = cands[rng.randi() % cands.size()]
	w.edge = int(c["edge"])
	var e: RoadGraph.Edge = graph.edges[w.edge]
	if e.road_class in ["motorway", "trunk_link", "motorway_link"]:
		return false
	w.dir = 1 if rng.randf() < 0.5 else -1
	w.s = clampf(float(c["s"]), 0.0, e.length)
	w.side = 1.0 if rng.randf() < 0.5 else -1.0
	w.kerb = KERB_GAP_M + rng.randf() * KERB_SPREAD_M
	w.idle = rng.randf() < IDLE_SHARE
	var pr: Vector2 = PACE.get(w.id, DEFAULT_PACE)
	w.pace = rng.randf_range(pr.x, pr.y)
	w.startle = 0.0
	w.dodge = Vector3.ZERO
	w.recovery = 0.0
	w.react = ""
	w.gesture_in = rng.randf_range(GESTURE_GAP_S.x, GESTURE_GAP_S.y)
	w.running = not w.idle and _run_pace.has(w.id) and rng.randf() < RUN_SHARE
	if w.running:
		w.pace = float(_run_pace[w.id]) * rng.randf_range(RUN_PACE.x, RUN_PACE.y)
	if w.idle and (w.s < IDLE_JUNCTION_CLEAR_M or w.s > e.length - IDLE_JUNCTION_CLEAR_M):
		return false
	var target: Array[Vector3] = _target(w)
	# The kerb line of one street can fall on another street's carriageway near junctions.
	if not _on_pavement(target[0]) or not SignalBus.walkable(target[0].x, target[0].z):
		return false
	w.pos = target[0]
	# Snap only on spawn, while hidden; thereafter follow ground smoothly.
	w.pos.y = SignalBus.surface_height(w.pos.x, w.pos.z, WALK_Y)
	w.heading = target[1]
	if w.idle:
		# Idlers face the road (waiting for a bus, an auto, a friend).
		var left: Vector3 = Vector3(target[1].z, 0.0, -target[1].x)
		w.heading = -left * w.side
	# Never pop into view right in front of the camera.
	var to_p: Vector3 = w.pos - _player
	if to_p.length() < SPAWN_MIN_M * 0.8:
		return false
	var seen: bool = ViewCheck.on_screen(get_viewport(), w.pos + Vector3(0, 0.9, 0), 1.2)
	if (seen and to_p.length() < SPAWN_ON_SCREEN_M) or (not seen and to_p.length() > DESPAWN_M - 5.0):
		return false
	w.active = true
	w.node.visible = true
	if w.paintable:
		# One in four keeps the model's own colours; the rest wear a palette colour.
		var pal: Array[Color] = PaintSwap.palette_for_person(w.id)
		w.paint = PaintSwap.NO_PAINT if rng.randf() < 0.25 else pal[rng.randi() % pal.size()]
		PaintSwap.set_paint(w.node, w.paint)
	if GameState.is_raining:
		if rng.randf() < RAIN_UMBRELLA_SHARE:
			_open_umbrella(w)
		elif not _seek_shelter(w):
			_hurry(w)
	elif _sun_time() and WOMEN.has(w.id) and rng.randf() < SUN_UMBRELLA_SHARE:
		_open_umbrella(w)
	_apply(w)
	_resume(w, 0.0)
	if w.anim != null and w.anim.current_animation != "":
		w.anim.seek(rng.randf() * w.anim.current_animation_length, true)
	if w.idle and w.role == "" and not GameState.is_raining and rng.randf() < CHAT_SHARE:
		_start_chat(w)
	return true

# --- People chatting ----------------------------------------------------------

## Give the idler `w` a partner from the free part of the pool, standing CHAT_GAP_M along the
## kerb, the two facing each other. False if nobody is free or there is no room.
func _start_chat(w: Walker) -> bool:
	if w.anim == null or not w.anim.has_animation("talk_2"):
		return false
	# A free walker, else one far off or out of view (the pool is usually all in use).
	var p: Walker = _free_walker("", w)
	if p == null or p.anim == null or not p.anim.has_animation("talk_2"):
		return false
	var along: Vector3 = Vector3(w.heading.z, 0.0, -w.heading.x) # w faces the road; along the kerb
	if rng.randf() < 0.5:
		along = -along
	var at: Vector3 = w.pos + along * CHAT_GAP_M
	if not SignalBus.walkable(at.x, at.z) or not _on_pavement(at) or not _clear_of_trunks(at) or not _clear_of_trunks(w.pos):
		return false
	# Turn a little towards the road, as people do when they stop to chat on a pavement.
	var road: Vector3 = w.heading
	w.heading = (along + road * 0.35).normalized()
	if p.active:
		_deactivate(p)
	p.edge = w.edge
	p.s = w.s
	p.dir = w.dir
	p.side = w.side
	p.idle = true
	p.running = false
	p.startle = 0.0
	p.dodge = Vector3.ZERO
	p.recovery = 0.0
	p.react = ""
	p.fleeing = false
	p.umbrella = false
	p.sheltered = false
	_roll_bags(p)
	p.pos = Vector3(at.x, SignalBus.surface_height(at.x, at.z, WALK_Y), at.z)
	p.heading = (-along + road * 0.35).normalized()
	p.active = true
	p.node.visible = true
	if p.paintable:
		var pal: Array[Color] = PaintSwap.palette_for_person(p.id)
		p.paint = PaintSwap.NO_PAINT if rng.randf() < 0.25 else pal[rng.randi() % pal.size()]
		PaintSwap.set_paint(p.node, p.paint)
	for q: Walker in [w, p]:
		q.role = "chat"
		_set_pose(q)
	w.partner = p
	p.partner = w
	w.talking = true
	p.talking = false
	w.chat_t = rng.randf_range(CHAT_TURN_S.x, CHAT_TURN_S.y)
	p.chat_t = w.chat_t
	_chat_clip(w)
	_chat_clip(p)
	if p.anim != null:
		p.anim.seek(rng.randf() * maxf(p.anim.current_animation_length, 0.1), true)
	_apply(w)
	_apply(p)
	return true

## The talker plays a talk clip; the listener idles (a quarter of the time chiming in).
func _chat_clip(w: Walker) -> void:
	if w.anim == null:
		return
	var clip: String = "idle"
	if w.talking or rng.randf() < 0.25:
		var have: Array[String] = []
		for c: String in CHAT_CLIPS:
			if w.anim.has_animation(c):
				have.append(c)
		if not have.is_empty():
			clip = have[rng.randi() % have.size()]
	if not w.anim.has_animation(clip):
		return
	w.anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	w.anim.play(clip, 0.35)
	w.anim.speed_scale = 1.0

## No tree trunk or EB pole where a person would stand (the walk mask only holds buildings).
func _clear_of_trunks(at: Vector3) -> bool:
	return SignalBus.street_spots("trees", at, 0.9).is_empty() and SignalBus.street_spots("poles", at, 0.5).is_empty()

func _step_chat(w: Walker, delta: float) -> void:
	var p: Walker = w.partner
	if p == null or not p.active or p.role != "chat" or p.partner != w or p.fleeing:
		_end_chat(w)
		w.idle = true
		_resume(w, 0.3)
		_apply(w)
		return
	# Turns are kept by the talker: when its time is up, both swap.
	if w.talking:
		w.chat_t -= delta
		if w.chat_t <= 0.0:
			w.talking = false
			p.talking = true
			p.chat_t = rng.randf_range(CHAT_TURN_S.x, CHAT_TURN_S.y)
			_chat_clip(w)
			_chat_clip(p)
	_apply(w)

## Leave a chat (the partner, if still in it, finishes on its next step).
func _end_chat(w: Walker) -> void:
	if w.role == "chat":
		w.role = ""
	w.partner = null
	w.talking = false

func chat_count() -> int:
	var n: int = 0
	for w: Walker in people:
		if w.active and w.role == "chat":
			n += 1
	return n

# --- Shop people running from a fire ---------------------------------------------

## ShopPeople hid the shopkeepers and customers near a burning auto; stand pooled walkers in
## their places (the same characters where the pool has them), so the fire scare runs them off
## with everyone else. `spots`: [Vector3 position, yaw, figure id].
func _on_shop_people_scattered(spots: Array) -> void:
	var used: int = 0
	for s: Array in spots:
		if used >= SCATTER_MAX:
			break
		var w: Walker = _free_walker(String(s[2]))
		if w == null:
			break
		var at: Vector3 = s[0]
		if graph == null:
			break
		var cp: Dictionary = graph.closest_point(at)
		if int(cp["edge"]) < 0:
			continue
		if w.active:
			_deactivate(w)
		w.edge = int(cp["edge"])
		w.s = float(cp["s"])
		w.dir = 1
		w.idle = true
		w.running = false
		w.startle = 0.0
		w.dodge = Vector3.ZERO
		w.recovery = 0.0
		w.react = ""
		w.fleeing = false
		w.role = ""
		w.umbrella = false
		w.fire_screamed = false
		_roll_bags(w)
		w.pos = Vector3(at.x, SignalBus.surface_height(at.x, at.z, WALK_Y), at.z)
		w.heading = Vector3(sin(float(s[1])), 0.0, cos(float(s[1])))
		w.active = true
		w.node.visible = true
		if w.anim != null:
			w.anim.active = true
		_set_pose(w)
		_resume(w, 0.0)
		_apply(w)
		used += 1
	# Run the scare check now, so they set off with the first screams, not a frame later.
	_check_fire_scares()

## A walker to borrow: a free one (the same character first), else one far off or out of view.
func _free_walker(id: String, not_this: Walker = null) -> Walker:
	var best: Walker = null
	for w: Walker in people:
		if w == not_this:
			continue
		if not w.active:
			if w.id == id:
				return w
			if best == null:
				best = w
	if best != null:
		return best
	for w: Walker in people:
		if w == not_this or w.fleeing or w.react != "" or w.role == "chat":
			continue
		var d: float = w.pos.distance_to(_player)
		if d > FIRE_SCARE_M * 2.0 or not ViewCheck.on_screen(get_viewport(), w.pos + Vector3(0, 0.9, 0), 1.2):
			return w
	return null

## Back to the walker's own loop: idle, walk or (joggers) run, with playback matched to the pace.
func _resume(w: Walker, blend: float) -> void:
	if w.anim == null:
		return
	var clip: String = "idle" if w.idle else ("run" if w.running and w.anim.has_animation("run") else "walk")
	if not w.anim.has_animation(clip):
		return
	w.anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	w.anim.play(clip, blend)
	if w.idle:
		w.anim.speed_scale = 1.0
	elif clip == "run":
		w.anim.speed_scale = w.pace / float(_run_pace.get(w.id, 2.2))
	else:
		w.anim.speed_scale = w.pace / float(_native_pace.get(w.id, 1.2))

## True when `p` is clear of every carriageway (closest road centre-line further than half its width).
func _on_pavement(p: Vector3) -> bool:
	var cp: Dictionary = graph.closest_point(p)
	if cp.is_empty() or int(cp.get("edge", -1)) < 0:
		return true
	var e: RoadGraph.Edge = graph.edges[int(cp["edge"])]
	return float(cp["dist"]) >= e.width * 0.5 + 0.4

func _deactivate(w: Walker) -> void:
	w.active = false
	w.react = ""
	w.lift = 0.0
	_end_chat(w)
	w.role = ""
	w.umbrella = false
	_set_pose(w)
	w.node.visible = false
	if w.anim != null:
		w.anim.active = false

## Kerb-side point and travel direction for the walker's spot on its edge.
## Kerb-side point and travel direction for the walker's spot on its edge. The walker keeps to
## its own kerb distance where it is clear, else the widest strip between the road edge and the
## nearest wall (Oct 31 device test: people walked through shopfronts where buildings stand
## closer to the road than the kerb line).
func _target(w: Walker) -> Array[Vector3]:
	var pd: Array[Vector3] = graph.sample(w.edge, w.s, w.dir)
	var e: RoadGraph.Edge = graph.edges[w.edge]
	var left: Vector3 = Vector3(pd[1].z, 0.0, -pd[1].x)
	var edge_off: float = e.width * 0.5
	var off: float = edge_off + w.kerb
	while off > edge_off + ROAD_EDGE_M and not _clear(pd[0] + left * off * w.side, left * w.side):
		off -= 0.25
	var p: Vector3 = pd[0] + left * maxf(off, edge_off + ROAD_EDGE_M) * w.side
	p.y = WALK_Y
	return [p, pd[1]]

## A person (BODY_M radius) fits at `p`: the spot and a body's width toward the wall are free.
func _clear(p: Vector3, out: Vector3) -> bool:
	var q: Vector3 = p + out * BODY_M
	return SignalBus.walkable(p.x, p.z) and SignalBus.walkable(q.x, q.z)

func _step(w: Walker, delta: float) -> void:
	# A gesture is harmless to interrupt: a vehicle about to pass takes priority over it.
	if w.react == "gesture" and w.recovery <= 0.0 and _has_reactions(w) and _check_threats(w):
		return
	if w.react != "":
		_step_react(w, delta)
		return
	if _has_reactions(w):
		if w.recovery <= 0.0 and w.startle <= 0.0 and _check_threats(w):
			return
	else:
		_check_startle(w, delta)
	if w.recovery > 0.0:
		w.recovery = maxf(0.0, w.recovery - delta)
		var displaced: Vector3 = w.pos + w.dodge * delta
		if SignalBus.walkable(displaced.x, displaced.z):
			w.pos = displaced
		w.dodge = w.dodge.move_toward(Vector3.ZERO, TrafficVehicleAI.PHYSICS.recoil_deceleration * delta)
		_apply(w)
		w.node.rotate_object_local(Vector3.FORWARD, deg_to_rad(18.0) * minf(w.recovery, 1.0))
		return
	if w.fleeing:
		_step_flee(w, delta)
		return
	if w.role == "shelter":
		_step_shelter(w, delta)
		return
	if w.role == "chat":
		_step_chat(w, delta)
		return
	if w.role == "kolam":
		if not _kolam_time():
			w.role = ""
			_set_pose(w)
		_apply(w)
		return
	if w.idle and w.startle <= 0.0:
		w.gesture_in -= delta
		if w.gesture_in <= 0.0:
			w.gesture_in = rng.randf_range(GESTURE_GAP_S.x, GESTURE_GAP_S.y)
			if _start_gesture(w):
				return
		_apply(w)
		return
	if w.startle > 0.0:
		# Stopped and stepping back from the road for a moment.
		w.startle -= delta
		var step: Vector3 = w.pos + w.dodge * delta
		if SignalBus.walkable(step.x, step.z):
			w.pos = step
		if w.startle <= 0.0 and not w.idle:
			_resume(w, 0.2)
		_apply(w)
		return
	var e: RoadGraph.Edge = graph.edges[w.edge]
	w.s += w.pace * delta * float(w.dir)
	if w.s > e.length or w.s < 0.0:
		_next_edge(w)
	var target: Array[Vector3] = _target(w)
	# Ease toward the kerb line (corners and edge changes never teleport), facing where we go.
	var to_t: Vector3 = target[0] - w.pos
	to_t.y = 0.0
	var max_move: float = w.pace * delta * 1.6
	var next_pos: Vector3 = w.pos + (to_t.limit_length(max_move) if to_t.length() > max_move else to_t)
	if SignalBus.walkable(next_pos.x, next_pos.z):
		w.pos = next_pos
	else:
		w.dir = -w.dir
		w.side = -w.side
	var want: Vector3 = target[1]
	if to_t.length() > 0.3:
		want = (target[1] + to_t.normalized()).normalized()
	w.heading = w.heading.slerp(want, clampf(TURN_RATE * delta, 0.0, 1.0)).normalized()
	_apply(w)

## Continue onto another street at the junction (never a U-turn unless it's a dead end).
func _next_edge(w: Walker) -> void:
	var e: RoadGraph.Edge = graph.edges[w.edge]
	var node: int = e.b if w.dir > 0 else e.a
	var options: Array[int] = []
	for other: int in graph.node_edges[node]:
		if other != w.edge and not (graph.edges[other].road_class in ["motorway", "motorway_link"]):
			options.append(other)
	if options.is_empty():
		w.dir = -w.dir
		w.side = -w.side
		w.s = clampf(w.s, 0.0, e.length)
		return
	# Prefer the street that keeps us on the same side of the junction (turning the near corner).
	var nxt: int = options[rng.randi() % options.size()]
	var o: RoadGraph.Edge = graph.edges[nxt]
	w.edge = nxt
	w.dir = 1 if o.a == node else -1
	w.s = 0.0 if w.dir > 0 else o.length

func _check_startle(w: Walker, delta: float) -> void:
	var to_w: Vector3 = w.pos - _player
	to_w.y = 0.0
	var d: float = to_w.length()
	if d > STARTLE_M or d < 0.01:
		return
	var closing: float = _player_vel.dot(to_w / d)
	if d < TrafficVehicleAI.PHYSICS.pedestrian_contact_m and closing > STARTLE_SPEED_MPS and w.recovery <= 0.0:
		w.recovery = TrafficVehicleAI.PHYSICS.pedestrian_recovery_s
		w.dodge = (to_w / d) * minf(closing * 0.3, TrafficVehicleAI.PHYSICS.pedestrian_max_push_mps)
		w.startle = w.recovery
		if w.anim != null and w.anim.has_animation("idle"):
			w.anim.play("idle", 0.1)
		SignalBus.pedestrian_startled.emit(w.pos)
		return
	if closing < STARTLE_SPEED_MPS or w.startle > 0.0:
		return
	# Step sideways, away from the auto's path.
	var side_dir: Vector3 = Vector3(_player_fwd.z, 0.0, -_player_fwd.x)
	if side_dir.dot(to_w) < 0.0:
		side_dir = -side_dir
	w.dodge = side_dir.normalized() * 1.8
	w.startle = 0.7
	if w.anim != null and w.anim.has_animation("idle"):
		w.anim.play("idle", 0.15)
		w.anim.speed_scale = 1.0
	SignalBus.pedestrian_startled.emit(w.pos)

## Every moving vehicle near the player: the player's auto plus pooled traffic (velocity from the
## last frame's position — traffic speeds are along the lane, this also covers recoil and turns).
func _gather_threats(delta: float) -> void:
	_threats.clear()
	if _player_vel.length() > 0.5:
		_threats.append([_player, _player_vel])
	if _traffic == null:
		return
	for v: TrafficVehicleAI in _traffic.active_vehicles():
		var p: Vector3 = v.global_position
		var id: int = v.get_instance_id()
		var last: Variant = _prev_traffic.get(id)
		_prev_traffic[id] = p
		if p.distance_squared_to(_player) > THREAT_M * THREAT_M or last == null:
			continue
		var vel: Vector3 = (p - (last as Vector3)) / delta
		if vel.length() > 1.0 and vel.length() < 40.0:
			_threats.append([p, vel])

func _has_reactions(w: Walker) -> bool:
	return w.anim != null and w.anim.has_animation("dodge") and (_moves.get(w.id, {}) as Dictionary).has("dodge")

## The auto has a body. Someone it reaches who is not already dodging or falling is hit: they go
## down along the auto's path, and SignalBus.pedestrian_bumped slows the auto by their share of its mass.
func _check_player_bumps() -> void:
	var speed: float = _player_vel.length()
	if not _has_player or speed < BUMP_MIN_MPS:
		return
	var fwd: Vector3 = Vector3(_player_fwd.x, 0.0, _player_fwd.z).normalized()
	var side: Vector3 = Vector3(-fwd.z, 0.0, fwd.x)
	var dir: Vector3 = Vector3(_player_vel.x, 0.0, _player_vel.z).normalized()
	for w: Walker in people:
		if not w.active or w.recovery > 0.0 or (w.react != "" and w.react != "gesture"):
			continue
		var rel: Vector3 = w.pos - _player
		rel.y = 0.0
		if absf(rel.dot(side)) > BUMP_HALF_WIDTH_M or absf(rel.dot(fwd)) > BUMP_HALF_LENGTH_M:
			continue
		w.recovery = BUMP_COOLDOWN_S # one hit per pass, however many frames the body stays in the footprint
		if not _start_react(w, "stumble", dir) and not _start_react(w, "dodge", dir):
			if w.anim.has_animation("fallen"):
				w.react = "fallen"
				w.react_t = FALLEN_S.x
				w.anim.get_animation("fallen").loop_mode = Animation.LOOP_LINEAR
				w.anim.play("fallen", 0.1)
		_scream(w.pos, w.id)
		SignalBus.pedestrian_startled.emit(w.pos)
		SignalBus.pedestrian_bumped.emit(w.pos, _player_vel)

## A vehicle whose path passes within NEAR_MISS_M in the next REACT_AHEAD_S: jump back, or
## stumble and fall (always, if it's going to hit at speed).
func _check_threats(w: Walker) -> bool:
	if not w.anim.active:
		return false
	for t: Array in _threats:
		var rel: Vector3 = w.pos - (t[0] as Vector3)
		rel.y = 0.0
		var d: float = rel.length()
		if d > REACT_M:
			continue
		var v: Vector3 = t[1]
		v.y = 0.0
		var sp: float = v.length()
		if sp < STARTLE_SPEED_MPS:
			continue
		var dir: Vector3 = v / sp
		var ahead: float = rel.dot(dir)
		if ahead < -0.3 or ahead / sp > REACT_AHEAD_S:
			continue
		var side: Vector3 = rel - dir * ahead
		var lateral: float = side.length()
		if lateral > NEAR_MISS_M:
			continue
		var away: Vector3 = side / lateral if lateral > 0.05 else Vector3(dir.z, 0.0, -dir.x)
		var hit: bool = lateral < TrafficVehicleAI.PHYSICS.pedestrian_contact_m and sp > HIT_SPEED_MPS
		var first: String = "stumble" if hit or rng.randf() < STUMBLE_SHARE else "dodge"
		var second: String = "dodge" if first == "stumble" else "stumble"
		if _start_react(w, first, away) or _start_react(w, second, away):
			SignalBus.pedestrian_startled.emit(w.pos)
			return true
		return false
	return false

## Face the vehicle's path and play `clip`, which carries the body `away` from it. Refused when
## the spot the clip ends on (or half-way there) is a wall, a shop or the water.
func _start_react(w: Walker, clip: String, away: Vector3) -> bool:
	var mv: Dictionary = _moves.get(w.id, {})
	if not w.anim.has_animation(clip) or not mv.has(clip):
		return false
	var m: Vector3 = mv[clip]
	var offset: Vector3 = Basis.looking_at(away, Vector3.UP) * Vector3(m.x, 0.0, m.y)
	var land: Vector3 = w.pos + offset
	var half: Vector3 = w.pos + offset * 0.5
	if not SignalBus.walkable(land.x, land.z) or not SignalBus.walkable(half.x, half.z):
		return false
	w.heading = -away
	w.react = clip
	w.react_t = m.z
	w.move = offset
	w.startle = 0.0
	w.anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	w.anim.play(clip, 0.12)
	w.anim.speed_scale = 1.0
	_apply(w)
	return true

func _step_react(w: Walker, delta: float) -> void:
	w.react_t -= delta
	if w.react_t > 0.0:
		_apply(w)
		return
	if w.react == "fallen":
		# Up again: Mixamo's getting-up clip where the model has one, else a slow blend to the feet.
		w.react = ""
		if w.anim.has_animation("get_up"):
			_play_once(w, "get_up")
		else:
			_resume(w, GET_UP_BLEND_S)
		_apply(w)
		return
	if w.react == "get_up" or w.react == "gesture":
		# Clip finished (both stay where they are): back to walking or standing.
		w.react = ""
		_resume(w, 0.2)
		_apply(w)
		return
	# The clip has carried the body `move` from the node: put the node there and continue from
	# a pose that starts at the node again (no blend, or the body would slide back).
	w.pos += w.move
	w.move = Vector3.ZERO
	if w.react == "stumble" and w.anim.has_animation("fallen"):
		w.react = "fallen"
		w.react_t = rng.randf_range(FALLEN_S.x, FALLEN_S.y)
		w.anim.get_animation("fallen").loop_mode = Animation.LOOP_LINEAR
		w.anim.play("fallen", 0.0)
	else:
		w.react = ""
		_resume(w, 0.0)
	w.anim.advance(0.0)
	_apply(w)

func _on_vehicle_burning(on: bool) -> void:
	if on == _fire_on:
		return
	_fire_on = on
	_panic_burst = on
	_panic_pending.clear()
	_late_scream_in = 0.0
	for w: Walker in people:
		w.fire_screamed = false

## A burning auto scares everyone close to it: they run off from it, screaming (see PANIC_BURST).
func _check_fire_scares() -> void:
	if not _fire_on or not _has_player:
		return
	var burst: bool = _panic_burst
	_panic_burst = false
	var voiced: int = 0
	for w: Walker in people:
		if not w.active or w.fleeing or w.anim == null or (w.react != "" and w.react != "gesture"):
			continue
		var d: Vector3 = w.pos - _player
		d.y = 0.0
		if d.length() > FIRE_SCARE_M or not _start_flee(w) or w.fire_screamed:
			continue
		# Silent extras still run: a crowd's screams blend, they don't need one voice each.
		w.fire_screamed = true
		if burst:
			if voiced < PANIC_BURST:
				voiced += 1
				_panic_pending.append([_scream_rng.randf_range(PANIC_ONSET_S.x, PANIC_ONSET_S.y), w.pos, w.id])
		elif _late_scream_in <= 0.0:
			_late_scream_in = _scream_rng.randf_range(PANIC_LATE_GAP_S.x, PANIC_LATE_GAP_S.y)
			_panic_pending.append([0.0, w.pos, w.id])

## Plays the screams whose onset has come, and counts down the gap before a late one.
func _step_screams(delta: float) -> void:
	_late_scream_in = maxf(_late_scream_in - delta, 0.0)
	for i: int in range(_panic_pending.size() - 1, -1, -1):
		var e: Array = _panic_pending[i]
		e[0] = float(e[0]) - delta
		if float(e[0]) <= 0.0:
			_panic_pending.remove_at(i)
			_scream(e[1] as Vector3, String(e[2]))

## Starts a run straight away from the auto: a running clip, or the look-back run, at its own pace.
## False when this person has no running clip.
func _start_flee(w: Walker) -> bool:
	var options: Array[String] = []
	if w.anim.has_animation("run"):
		options.append("run")
	if w.anim.has_animation("flee_look"):
		options.append("flee_look")
	if w.anim.has_animation("flee"):
		options.append("flee")
	if options.is_empty():
		return false
	var away: Vector3 = w.pos - _player
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
	w.flee_clip = options[rng.randi() % options.size()]
	var native: float = float(_run_pace.get(w.id, 2.2))
	if w.flee_clip == "flee_look":
		native = float(_flee_look_pace.get(w.id, 1.6))
	elif w.flee_clip == "flee":
		native = float(_flee_pace.get(w.id, 2.2))
	w.flee_pace = native * rng.randf_range(FLEE_PACE.x, FLEE_PACE.y)
	w.flee_dir = away.normalized()
	_end_chat(w)
	w.role = ""
	w.flee_t = rng.randf_range(FLEE_S.x, FLEE_S.y)
	w.react = ""
	w.fleeing = true
	w.anim.get_animation(w.flee_clip).loop_mode = Animation.LOOP_LINEAR
	w.anim.play(w.flee_clip, 0.2)
	w.anim.speed_scale = w.flee_pace / native
	return true

## Running off from the fire, straight away from the auto. Stops at the kerb or when the time is up,
## then the usual path walking takes over again (the walker eases back onto the kerb line).
func _step_flee(w: Walker, delta: float) -> void:
	w.flee_t -= delta
	var step: Vector3 = w.pos + w.flee_dir * w.flee_pace * delta
	if w.flee_t <= 0.0 or not SignalBus.walkable(step.x, step.z) or not _on_pavement(step):
		w.fleeing = false
		_resume(w, 0.4)
		_apply(w)
		return
	w.pos = step
	w.heading = w.heading.slerp(w.flee_dir, clampf(TURN_RATE * delta, 0.0, 1.0)).normalized()
	_apply(w)

## Screams come from a small pool of 3D players, so a crowd costs at most SCREAM_VOICES voices.
func _setup_screams() -> void:
	for path: String in SCREAM_FILES:
		if ResourceLoader.exists(path):
			_scream_streams.append(load(path) as AudioStream)
	for i: int in SCREAM_VOICES:
		var pl: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		pl.unit_size = 6.0
		pl.max_distance = 60.0
		add_child(pl)
		_screams.append(pl)

## One scream from a free voice, so it never cuts off a scream still playing. With every voice busy,
## the one nearest its end is reused. Men's voices are pitched lower than women's.
func _scream(p: Vector3, id: String) -> void:
	if _scream_streams.is_empty() or _screams.is_empty():
		return
	var pl: AudioStreamPlayer3D = null
	var most_done: float = -1.0
	for v: AudioStreamPlayer3D in _screams:
		if not v.playing:
			pl = v
			break
		var length: float = v.stream.get_length() if v.stream != null else 0.0
		var done: float = v.get_playback_position() / maxf(length, 0.01)
		if done > most_done:
			most_done = done
			pl = v
	var female: bool = id.begins_with("woman") or id.begins_with("girl")
	var pitch: Vector2 = FEMALE_PITCH if female else MALE_PITCH
	pl.stream = _scream_streams[_scream_rng.randi() % _scream_streams.size()]
	pl.pitch_scale = _scream_rng.randf_range(pitch.x, pitch.y)
	pl.volume_db = _scream_rng.randf_range(SCREAM_DB.x, SCREAM_DB.y)
	pl.global_position = p + Vector3(0.0, 1.5, 0.0)
	pl.play()

## Stand-still gesture for a person waiting at the kerb; _step_react resumes them when it ends.
func _start_gesture(w: Walker) -> bool:
	var clip: String = GESTURE_CLIPS[rng.randi() % GESTURE_CLIPS.size()]
	if w.anim == null or not w.anim.has_animation(clip):
		return false
	_play_once(w, clip)
	w.react = "gesture"
	return true

## Plays a non-looping clip in place (getting up, a gesture) and times the reaction to its length.
func _play_once(w: Walker, clip: String) -> void:
	var anim: Animation = w.anim.get_animation(clip)
	anim.loop_mode = Animation.LOOP_NONE
	w.react = clip
	w.react_t = anim.length
	w.anim.play(clip, 0.1)
	w.anim.speed_scale = 1.0

func _apply(w: Walker) -> void:
	var fwd: Vector3 = Vector3(w.heading.x, 0.0, w.heading.z)
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	# Stand on whatever is drawn there (sidewalk, road edge, park or bare ground), not at a fixed
	# sidewalk height: most kerb spots have no sidewalk polygon and people floated 23 cm.
	var ground_y: float = SignalBus.surface_height(w.pos.x, w.pos.z, WALK_Y)
	# Nov 14 device report: "people who fall down sometimes go below the road". A lying body
	# is 1.7 m long and often straddles two drawn layers (bare ground at -0.15, road at +0.06),
	# and the fall clips put the hands and forearms at or under the node's own height. So a
	# body that is down rests on the HIGHEST ground under its whole length, plus a small lift
	# for the thickness of the limbs.
	var want_lift: float = 0.0
	if w.react in DOWN_CLIPS:
		want_lift = float(DOWN_LIFT_M[w.react])
		var body: Vector3 = w.pos + w.move
		var along: Vector3 = fwd.normalized() * DOWN_REACH_M
		for q: Vector3 in [w.pos + w.move * 0.5, body, body + along, body - along]:
			ground_y = maxf(ground_y, SignalBus.surface_height(q.x, q.z, WALK_Y))
	var dt: float = get_process_delta_time()
	w.lift = move_toward(w.lift, want_lift, DOWN_LIFT_MPS * dt)
	w.pos.y = ground_y if ground_y > w.pos.y else move_toward(w.pos.y, ground_y, GROUND_FOLLOW_MPS * dt)
	# Characters are authored facing +Z: looking at -fwd puts their face along fwd.
	w.node.global_transform = Transform3D(Basis.looking_at(-fwd.normalized(), Vector3.UP), w.pos + Vector3(0.0, w.lift, 0.0))

# --- Time of day and weather -------------------------------------------------

func _kolam_time() -> bool:
	var m: float = fmod(GameState.shift_minute, 1440.0)
	return m >= KOLAM_MINUTES.x and m <= KOLAM_MINUTES.y and not GameState.is_raining

func _sun_time() -> bool:
	var m: float = fmod(GameState.shift_minute, 1440.0)
	return m >= SUN_MINUTES.x and m <= SUN_MINUTES.y

func _role_count(role: String) -> int:
	var n: int = 0
	for w: Walker in people:
		if w.active and w.role == role:
			n += 1
	return n

func _set_pose(w: Walker) -> void:
	if w.pose == null:
		return
	if w.role == "kolam":
		w.pose.mode = PoseModifier.Mode.KOLAM
	elif w.umbrella:
		w.pose.mode = PoseModifier.Mode.UMBRELLA
	else:
		w.pose.mode = PoseModifier.Mode.NONE

## A woman at her doorstep, bent over the kolam she is drawing (early morning only).
func _spawn_kolam(w: Walker) -> bool:
	var spots: Array = SignalBus.street_spots("kolams", _player, SPAWN_MAX_M)
	if spots.is_empty():
		return false
	var s: Array = spots[rng.randi() % spots.size()]
	var at: Vector3 = (s[0] as Vector3) - Vector3(sin(float(s[1])), 0.0, cos(float(s[1]))) * KOLAM_STAND_M
	var to_p: Vector3 = at - _player
	to_p.y = 0.0
	if to_p.length() < SPAWN_MIN_M:
		return false
	if ViewCheck.on_screen(get_viewport(), at + Vector3(0, 0.9, 0), 1.2) and to_p.length() < SPAWN_ON_SCREEN_M:
		return false
	return place_kolam(w, s)

## Stand `w` at kolam spot `s` ([centre, yaw, record]) bent over the pattern (public for tests
## and the dev shot scene).
func place_kolam(w: Walker, s: Array) -> bool:
	var centre: Vector3 = s[0]
	var out: Vector3 = Vector3(sin(float(s[1])), 0.0, cos(float(s[1]))) # from the gate to the street
	var across: Vector3 = Vector3(out.z, 0.0, -out.x)
	# She stands on the gate side of the pattern; where the gate pier is in the way, beside it.
	var at: Vector3 = Vector3.INF
	for from: Vector3 in [-out, across, -across, out]:
		var q: Vector3 = centre + from * KOLAM_STAND_M
		if SignalBus.walkable(q.x, q.z):
			at = q
			out = -from
			break
	if at == Vector3.INF:
		return false
	for o: Walker in people:
		if o != w and o.active and o.role == "kolam" and o.pos.distance_to(at) < 2.0:
			return false
	var cp: Dictionary = graph.closest_point(at)
	if int(cp["edge"]) < 0:
		return false
	w.edge = int(cp["edge"])
	w.s = float(cp["s"])
	w.dir = 1
	w.idle = true
	w.running = false
	w.startle = 0.0
	w.dodge = Vector3.ZERO
	w.recovery = 0.0
	w.react = ""
	w.role = "kolam"
	w.pos = Vector3(at.x, SignalBus.surface_height(at.x, at.z, WALK_Y), at.z)
	w.heading = out
	w.active = true
	w.node.visible = true
	if w.paintable:
		var pal: Array[Color] = PaintSwap.palette_for_person(w.id)
		w.paint = pal[rng.randi() % pal.size()]
		PaintSwap.set_paint(w.node, w.paint)
	_set_pose(w)
	_apply(w)
	_resume(w, 0.0)
	return true

func _on_weather(raining: bool) -> void:
	for w: Walker in people:
		if not w.active:
			continue
		if raining:
			if w.role == "kolam":
				w.role = "" # the rain washes the flour away: she goes in
				w.idle = false
			if rng.randf() < RAIN_UMBRELLA_SHARE:
				_open_umbrella(w)
			elif not _seek_shelter(w):
				_hurry(w)
		else:
			w.umbrella = false
			if w.role == "shelter":
				w.role = ""
				w.sheltered = false
				w.idle = false
				w.running = false
				var pr: Vector2 = PACE.get(w.id, DEFAULT_PACE)
				w.pace = rng.randf_range(pr.x, pr.y)
			if w.react == "":
				_resume(w, 0.3)
		_set_pose(w)

func _open_umbrella(w: Walker) -> void:
	w.umbrella = true
	w.umbrella_colour = UMBRELLA_COLOURS[rng.randi() % UMBRELLA_COLOURS.size()]
	_set_pose(w)

## Caught in the rain with no shop near: run for it.
func _hurry(w: Walker) -> void:
	if w.idle or not _run_pace.has(w.id):
		return
	w.running = true
	w.pace = float(_run_pace[w.id]) * rng.randf_range(RUN_PACE.x, RUN_PACE.y)
	if w.react == "":
		_resume(w, 0.2)

## Head for the nearest shop front (a shopkeeper's spot) within SHELTER_REACH_M.
func _seek_shelter(w: Walker) -> bool:
	var best: Array = []
	var best_d: float = INF
	for s: Array in SignalBus.street_spots("shop_people", w.pos, SHELTER_REACH_M):
		if int((s[2] as Array)[4]) != 0:
			continue
		var d: float = (s[0] as Vector3).distance_squared_to(Vector3(w.pos.x, 0.0, w.pos.z))
		if d < best_d:
			best_d = d
			best = s
	if best.is_empty():
		return false
	var out: Vector3 = Vector3(sin(float(best[1])), 0.0, cos(float(best[1])))
	var along: Vector3 = Vector3(out.z, 0.0, -out.x)
	w.goal = (best[0] as Vector3) + along * rng.randf_range(-1.6, 1.6) - out * 0.15
	w.goal_heading = out
	w.role = "shelter"
	w.sheltered = false
	w.idle = false
	w.running = true
	w.umbrella = false
	w.startle = 0.0
	if w.react == "":
		_resume(w, 0.2)
	return true

func _step_shelter(w: Walker, delta: float) -> void:
	var to: Vector3 = w.goal - w.pos
	to.y = 0.0
	if w.sheltered:
		_apply(w)
		return
	if to.length() < SHELTER_ARRIVE_M:
		# Under the shop's awning: stand and watch the rain.
		w.sheltered = true
		w.idle = true
		w.running = false
		w.heading = w.goal_heading
		_resume(w, 0.25)
		_apply(w)
		return
	var dir: Vector3 = to.normalized()
	var pace: float = float(_run_pace.get(w.id, SHELTER_PACE_MPS))
	var step: Vector3 = w.pos + dir * pace * delta
	if SignalBus.walkable(step.x, step.z):
		w.pos = step
	else:
		# A wall or a stall in the way: slide along it.
		var slide: Vector3 = Vector3(dir.z, 0.0, -dir.x) * (1.0 if w.side > 0.0 else -1.0)
		step = w.pos + slide * pace * delta
		if SignalBus.walkable(step.x, step.z):
			w.pos = step
		else:
			w.sheltered = true # boxed in under some eave: good enough
			w.idle = true
			w.running = false
			_resume(w, 0.25)
	w.heading = w.heading.slerp(dir, minf(1.0, TURN_RATE * delta)) if w.heading.length() > 0.01 else dir
	_apply(w)

func _build_umbrellas() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ribs: int = 8
	var top: Vector3 = Vector3(0.0, 0.2, 0.0)
	for k: int in ribs:
		var a0: float = TAU * float(k) / float(ribs)
		var a1: float = TAU * float(k + 1) / float(ribs)
		var mid0: Vector3 = Vector3(cos(a0) * 0.3, 0.13, sin(a0) * 0.3)
		var mid1: Vector3 = Vector3(cos(a1) * 0.3, 0.13, sin(a1) * 0.3)
		var rim0: Vector3 = Vector3(cos(a0) * 0.56, 0.0, sin(a0) * 0.56)
		var rim1: Vector3 = Vector3(cos(a1) * 0.56, 0.0, sin(a1) * 0.56)
		for v: Vector3 in [top, mid1, mid0, mid0, mid1, rim1, mid0, rim1, rim0]:
			st.set_color(Color(1, 1, 1))
			st.add_vertex(v)
	# Shaft and handle: a thin dark square bar from the hand to the tip.
	for q: Array in [[Vector3(-0.008, -0.72, 0.0), Vector3(0.008, -0.72, 0.0), Vector3(0.008, 0.22, 0.0), Vector3(-0.008, 0.22, 0.0)],
			[Vector3(0.0, -0.72, -0.008), Vector3(0.0, -0.72, 0.008), Vector3(0.0, 0.22, 0.008), Vector3(0.0, 0.22, -0.008)]]:
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(0.25, 0.25, 0.25))
			st.add_vertex(q[i])
	st.generate_normals()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = POOL
	mm.visible_instance_count = 0
	# Umbrellas go wherever the walkers go: never cull the batch by its rest bounds.
	mm.custom_aabb = AABB(Vector3(-6000.0, -50.0, -6000.0), Vector3(12000.0, 250.0, 12000.0))
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	_umbrellas = MultiMeshInstance3D.new()
	_umbrellas.name = "Umbrellas"
	_umbrellas.multimesh = mm
	_umbrellas.material_override = mat
	_umbrellas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_umbrellas.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_umbrellas.visible = false
	add_child(_umbrellas)

## Every open umbrella sits over its walker's head, tipped a little forward (one MultiMesh).
func _place_umbrellas() -> void:
	if _umbrellas == null:
		return
	var mm: MultiMesh = _umbrellas.multimesh
	var n: int = 0
	for w: Walker in people:
		if not w.active or not w.umbrella or w.role != "" or w.react in DOWN_CLIPS or not w.node.visible:
			continue
		var xf: Transform3D = w.node.global_transform
		var tip: Basis = xf.basis * Basis(Vector3.RIGHT, 0.12)
		mm.set_instance_transform(n, Transform3D(tip, xf.origin + xf.basis * Vector3(-0.13, w.height + 0.2, 0.16)))
		mm.set_instance_color(n, w.umbrella_colour)
		n += 1
	mm.visible_instance_count = n
	_umbrellas.visible = n > 0

func _roll_bags(w: Walker) -> void:
	w.bags = 0
	if rng.randf() < BAG_SHARE:
		w.bags = 2 if rng.randf() < TWO_BAG_SHARE else 1
	for k: int in 2:
		w.bag_colours[k] = BAG_COLOURS[rng.randi() % BAG_COLOURS.size()]
		w.bag_sizes[k] = rng.randi() % BAG_SIZES.size()

## A bag with two loop handles, its origin at the top of the handles (where the hand holds it).
static func bag_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Unit body (scaled per instance): x -0.5..0.5, y -1..-0.32 (below the handles), z -0.5..0.5,
	# a little wider at the bottom like a filled bag.
	var top: float = -0.32
	var b: Array[Vector3] = [Vector3(-0.5, -1.0, -0.5), Vector3(0.5, -1.0, -0.5), Vector3(0.5, -1.0, 0.5), Vector3(-0.5, -1.0, 0.5),
		Vector3(-0.44, top, -0.32), Vector3(0.44, top, -0.32), Vector3(0.44, top, 0.32), Vector3(-0.44, top, 0.32)]
	var faces: Array = [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]
	for f: Array in faces:
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(1, 1, 1))
			st.add_vertex(b[f[i]])
	# Handles: two thin arches from the bag mouth up to the hand.
	for side: float in [-0.25, 0.25]:
		for seg: Array in [[Vector3(side - 0.06, top, 0.0), Vector3(-0.03, 0.0, 0.0)], [Vector3(side + 0.06, top, 0.0), Vector3(0.03, 0.0, 0.0)]]:
			var p0: Vector3 = seg[0]
			var p1: Vector3 = seg[1]
			for q: Array in [[Vector3(-0.02, 0, 0), Vector3(0.02, 0, 0)], [Vector3(0, 0, -0.02), Vector3(0, 0, 0.02)]]:
				var a: Vector3 = q[0]
				var c: Vector3 = q[1]
				for v: Vector3 in [p0 + a, p0 + c, p1 + c, p0 + a, p1 + c, p1 + a]:
					st.set_color(Color(0.85, 0.85, 0.85))
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _build_bags() -> void:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bag_mesh()
	mm.instance_count = POOL * 2
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-6000.0, -50.0, -6000.0), Vector3(12000.0, 250.0, 12000.0))
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	_bags = MultiMeshInstance3D.new()
	_bags.name = "ShoppingBags"
	_bags.multimesh = mm
	_bags.material_override = mat
	_bags.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bags.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_bags.visible = false
	add_child(_bags)

## Each bag hangs straight down from its hand bone (gravity, not the hand's rotation), turned
## with the walker. Lying, kolam-drawing or umbrella-holding hands carry no bag.
func _place_bags() -> void:
	if _bags == null:
		return
	var mm: MultiMesh = _bags.multimesh
	var n: int = 0
	for w: Walker in people:
		if not w.active or w.bags == 0 or w.skeleton == null or not w.node.visible or w.role == "kolam" or w.react in DOWN_CLIPS:
			continue
		var facing: Basis = Basis(Vector3.UP, atan2(w.heading.x, w.heading.z))
		for k: int in w.bags:
			var bone: int = w.hand_bones[k]
			if bone < 0 or (k == 0 and w.umbrella):
				continue
			var hand: Vector3 = (w.skeleton.global_transform * w.skeleton.get_bone_global_pose(bone)).origin
			var size: Vector3 = BAG_SIZES[w.bag_sizes[k]]
			# The bag's width runs along the walking direction, its flat side against the leg.
			var b: Basis = facing * Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(size)
			mm.set_instance_transform(n, Transform3D(b, hand + Vector3(0.0, -0.03, 0.0)))
			mm.set_instance_color(n, w.bag_colours[k])
			n += 1
	mm.visible_instance_count = n
	_bags.visible = n > 0

func bag_count() -> int:
	return _bags.multimesh.visible_instance_count if _bags != null else 0

func umbrella_count() -> int:
	return _umbrellas.multimesh.visible_instance_count if _umbrellas != null else 0

func active_count() -> int:
	var n: int = 0
	for w: Walker in people:
		if w.active:
			n += 1
	return n
