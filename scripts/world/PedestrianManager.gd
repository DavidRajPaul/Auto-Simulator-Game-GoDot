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
## Standing people now and then do one Mixamo gesture (talking on a phone, sipping, waving at an
## auto). A gesture plays once, then they go back to standing; the gap is random per person.
const GESTURE_CLIPS: Array[String] = ["talk", "drink", "wave"]
const GESTURE_GAP_S: Vector2 = Vector2(6.0, 14.0)
## Only traffic this close to the player can upset anyone (walkers further away aren't animated).
const THREAT_M: float = 60.0
## How many pool slots each character gets per round (Chennai pavements are mostly men).
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
## id -> {clip: Vector3(local x, local z, seconds)}: where each root-motion clip leaves the body.
var _moves: Dictionary = {}
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
	var paintable: bool = false
	var paint: Color = Color(0, 0, 0, 0)

func _ready() -> void:
	rng.seed = 600028
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
		w.node.visible = false
		people.append(w)
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
		if info.has("run_speed"):
			_run_pace[str(id)] = maxf(float(info["run_speed"]), 0.1)
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
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_S
		_recycle()
	for w: Walker in people:
		if w.active:
			_step(w, delta)

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
	_apply(w)
	_resume(w, 0.0)
	if w.anim != null and w.anim.current_animation != "":
		w.anim.seek(rng.randf() * w.anim.current_animation_length, true)
	return true

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
	w.pos.y = ground_y if ground_y > w.pos.y else move_toward(w.pos.y, ground_y, GROUND_FOLLOW_MPS * get_process_delta_time())
	# Characters are authored facing +Z: looking at -fwd puts their face along fwd.
	w.node.global_transform = Transform3D(Basis.looking_at(-fwd.normalized(), Vector3.UP), w.pos)

func active_count() -> int:
	var n: int = 0
	for w: Walker in people:
		if w.active:
			n += 1
	return n
