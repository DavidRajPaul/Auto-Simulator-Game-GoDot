class_name ComfortAssist
extends Node3D
## Player-comfort helpers (MVP polish):
##  • Auto-recover when the auto is flipped; "Reset auto" offer when stuck.
##  • Guidance arrow above the auto: along the GPS route, or to the nearest rider.
##  • First-run hints that walk a new driver through one full ride.
##  • Haptic feedback (horn, crashes, near misses, deals).
## Talks to the rest of the game through SignalBus; finds the player via its group.

## Below this the auto is on its side or roof (cos 53°). Side-tilt stunts peak near 18°, far above it.
const FLIP_UP_Y: float = 0.6
const FLIP_RESET_S: float = 2.0
const STUCK_S: float = 4.0
const ARROW_HEIGHT_M: float = 2.6
const ARROW_LOOKAHEAD_M: float = 35.0
const ARROW_HIDE_NEAR_M: float = 18.0

const HINTS: Array[Dictionary] = [
	{"id": "drive", "text": "HINT_DRIVE"},
	{"id": "hail", "text": "HINT_HAIL"},
	{"id": "haggle", "text": "HINT_HAGGLE"},
	{"id": "ride", "text": "HINT_RIDE"},
	{"id": "dropoff", "text": "HINT_DONE"},
]

var _player: RigidBody3D
var _flip_timer: float = 0.0
var _stuck_timer: float = 0.0
var _recover_offered: bool = false
var _route: PackedVector3Array = PackedVector3Array()
var _hails: Array = []
var _speed_kmh: float = 0.0
var _arrow: MeshInstance3D
var _hint_cooldown: float = 1.5

func _ready() -> void:
	_build_arrow()
	SignalBus.route_updated.connect(func(p: PackedVector3Array) -> void: _route = p)
	SignalBus.hails_updated.connect(func(h: Array) -> void: _hails = h)
	SignalBus.speed_updated.connect(func(k: float) -> void: _speed_kmh = k)
	SignalBus.recover_requested.connect(recover)
	# Haptics.
	SignalBus.horn_blasted.connect(func(_o: Vector3, _f: Vector3, _r: float, _t: int) -> void: vibrate(30))
	SignalBus.player_collision.connect(func(i: float) -> void: vibrate(clampi(int(i * 25.0), 40, 300)))
	SignalBus.near_miss.connect(func(_c: float) -> void: vibrate(40))
	SignalBus.haggle_resolved.connect(func(r: Dictionary) -> void:
		if bool(r["accepted"]):
			vibrate(70)
			_advance_hint("haggle")
			_advance_hint("ride", true))
	SignalBus.haggle_started.connect(func(_i: Dictionary, _s: float) -> void: _advance_hint("hail"))
	SignalBus.ride_completed.connect(func(_b: Dictionary) -> void: _advance_hint("ride"))

func _physics_process(delta: float) -> void:
	if _player == null:
		var autos: Array[Node] = get_tree().get_nodes_in_group("player_auto")
		if autos.is_empty():
			return
		_player = autos[0] as RigidBody3D
	_watch_flip_and_stuck(delta)
	_update_arrow()
	_tick_hints(delta)

# --- Recovery ----------------------------------------------------------------------------

func _watch_flip_and_stuck(delta: float) -> void:
	# A frozen body (tow, scripted pose) is never "flipped": recovering it would also cancel the stuck offer.
	var frozen: bool = _player is RigidBody3D and (_player as RigidBody3D).freeze
	if not frozen and _player.global_transform.basis.y.y < FLIP_UP_Y:
		_flip_timer += delta
		if _flip_timer >= FLIP_RESET_S:
			recover()
	else:
		_flip_timer = 0.0
	var pushing: bool = Input.get_action_strength("accelerate") > 0.5 or Input.get_action_strength("brake") > 0.5
	if pushing and _speed_kmh < 1.5:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	var should_offer: bool = _stuck_timer >= STUCK_S
	if should_offer != _recover_offered:
		_recover_offered = should_offer
		SignalBus.recover_available.emit(should_offer)

## Put the auto back on the nearest road, upright, in the left lane, facing traffic flow.
func recover() -> void:
	_flip_timer = 0.0
	_stuck_timer = 0.0
	if _recover_offered:
		_recover_offered = false
		SignalBus.recover_available.emit(false)
	var graph: RoadGraph = SignalBus.current_road_graph
	if graph == null or _player == null:
		return
	var cp: Dictionary = graph.closest_point(_player.global_position)
	if int(cp["edge"]) < 0:
		return
	var e: int = int(cp["edge"])
	var dir: int = 1 if graph.lanes_in_dir(e, 1) > 0 else -1
	# Prefer the direction we were roughly facing.
	var fwd: Vector3 = -_player.global_transform.basis.z
	var pd: Array[Vector3] = graph.sample(e, float(cp["s"]), 1)
	if graph.lanes_in_dir(e, -1) > 0 and fwd.dot(pd[1]) < 0.0:
		dir = -1
	var lp: Array[Vector3] = graph.lane_position(e, float(cp["s"]), dir, 0) # kerb-side sub-lane
	SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(lp[1], Vector3.UP), lp[0] + Vector3(0, 1.0, 0)))
	vibrate(60)

# --- Guidance arrow ----------------------------------------------------------------------

func _build_arrow() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.25, 1.0, 0.45))
	# Flat chevron pointing -Z, lying in the XZ plane.
	var pts: Array[Vector3] = [Vector3(0, 0, -1.1), Vector3(0.8, 0, 0.2), Vector3(0.3, 0, 0.2), Vector3(0.3, 0, 0.9),
		Vector3(-0.3, 0, 0.9), Vector3(-0.3, 0, 0.2), Vector3(-0.8, 0, 0.2)]
	for tri: Array in [[0, 1, 6], [2, 3, 5], [3, 4, 5]]:
		for i: int in tri:
			st.add_vertex(pts[i])
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 10
	_arrow = MeshInstance3D.new()
	_arrow.name = "GuidanceArrow"
	_arrow.mesh = st.commit()
	_arrow.material_override = mat
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.visible = false
	add_child(_arrow)

func guidance_target() -> Vector3:
	var p: Vector3 = _player.global_position
	if _route.size() >= 2:
		# Point a little ahead along the route from where we are.
		var best_i: int = 0
		var best_d: float = INF
		for i: int in _route.size():
			var d: float = _route[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best_i = i
		var acc: float = 0.0
		for i: int in range(best_i, _route.size() - 1):
			acc += _route[i].distance_to(_route[i + 1])
			if acc >= ARROW_LOOKAHEAD_M:
				return _route[i + 1]
		return _route[_route.size() - 1]
	var best: Vector3 = Vector3.INF
	for h: Dictionary in _hails:
		var hp: Vector3 = h["position"]
		if best == Vector3.INF or hp.distance_squared_to(p) < best.distance_squared_to(p):
			best = hp
	return best

func _update_arrow() -> void:
	var enabled: bool = bool(GameState.settings.get("guidance_arrow", true))
	var target: Vector3 = guidance_target()
	var p: Vector3 = _player.global_position
	var flat: Vector3 = Vector3(target.x - p.x, 0.0, target.z - p.z)
	if not enabled or target == Vector3.INF or flat.length() < ARROW_HIDE_NEAR_M:
		_arrow.visible = false
		return
	_arrow.visible = true
	_arrow.global_transform = Transform3D(Basis.looking_at(flat.normalized(), Vector3.UP), p + Vector3(0, ARROW_HEIGHT_M, 0))

# --- First-run hints ---------------------------------------------------------------------

func _tick_hints(delta: float) -> void:
	_hint_cooldown -= delta
	var step: int = int(GameState.settings.get("tutorial_step", 0))
	if step >= HINTS.size():
		return
	var id: String = str(HINTS[step]["id"])
	if id == "drive" and _speed_kmh > 15.0:
		_advance_hint("drive") # as soon as they get going, not when the hint next repeats
		return
	if _hint_cooldown <= 0.0 and id in ["drive", "hail", "dropoff"]:
		_show_hint(step)

func _show_hint(step: int) -> void:
	SignalBus.hint_requested.emit(tr(str(HINTS[step]["text"])), 6.0)
	_hint_cooldown = 7.0

## Move the tutorial on once the player has done `id` (no-op if they're past it).
func _advance_hint(id: String, show_next: bool = false) -> void:
	var step: int = int(GameState.settings.get("tutorial_step", 0))
	if step >= HINTS.size() or str(HINTS[step]["id"]) != id:
		return
	GameState.settings["tutorial_step"] = step + 1
	GameState.save_game()
	_hint_cooldown = 0.0 if show_next else 1.5
	if show_next and step + 1 < HINTS.size():
		_show_hint(step + 1)

# --- Haptics -------------------------------------------------------------------------------

func vibrate(ms: int) -> void:
	if bool(GameState.settings.get("vibration", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, 0.6)
