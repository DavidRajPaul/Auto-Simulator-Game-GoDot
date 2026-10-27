class_name ComfortAssist
extends Node3D
## Player-comfort helpers (MVP polish):
##  • Auto-recover when the auto is flipped; "Reset auto" offer when stuck.
##  • Guidance arrow above the auto: along the GPS route, or to the nearest rider.
##  (First-run guidance moved to TutorialDirector — the guided first ride.)
##  • Haptic feedback (horn, crashes, near misses, deals).
## Talks to the rest of the game through SignalBus; finds the player via its group.

## Below this the auto is on its side or roof (cos 53°). Side-tilt stunts peak near 18°, far above it.
const FLIP_UP_Y: float = 0.6
const FLIP_RESET_S: float = 2.0
const STUCK_S: float = 4.0
const ARROW_HEIGHT_M: float = 2.6
const ARROW_LOOKAHEAD_M: float = 35.0
const ARROW_HIDE_NEAR_M: float = 18.0

var _player: RigidBody3D
var _flip_timer: float = 0.0
var _stuck_timer: float = 0.0
var _recover_offered: bool = false
var _route: PackedVector3Array = PackedVector3Array()
var _route_idx: int = 0
var _hails: Array = []
var _speed_kmh: float = 0.0
var _arrow: MeshInstance3D

func _ready() -> void:
	_build_arrow()
	SignalBus.route_updated.connect(func(p: PackedVector3Array) -> void:
		_route = p
		_route_idx = 0)
	SignalBus.hails_updated.connect(func(h: Array) -> void: _hails = h)
	SignalBus.speed_updated.connect(func(k: float) -> void: _speed_kmh = k)
	SignalBus.recover_requested.connect(recover)
	# Haptics.
	SignalBus.horn_blasted.connect(func(_o: Vector3, _f: Vector3, _r: float, _t: int) -> void: vibrate(30))
	SignalBus.player_collision.connect(func(i: float) -> void: vibrate(clampi(int(i * 25.0), 40, 300)))
	SignalBus.near_miss.connect(func(_c: float) -> void: vibrate(40))
	SignalBus.haggle_resolved.connect(func(r: Dictionary) -> void:
		if bool(r["accepted"]):
			vibrate(70))

func _physics_process(delta: float) -> void:
	if _player == null:
		var autos: Array[Node] = get_tree().get_nodes_in_group("player_auto")
		if autos.is_empty():
			return
		_player = autos[0] as RigidBody3D
	_watch_flip_and_stuck(delta)
	_update_arrow()

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

## The guide arrow: a thick 3D chevron with a dark rim, floating over the auto and tilted back
## toward the camera (a flat one seen from the chase camera was a thin, barely visible sliver).
## Yellow = heading to the nearest waiting rider, green = following the GPS route to the drop.
## A small label under it says which, and how far.
const ARROW_TILT_RAD: float = 0.75
const ARROW_SCALE: float = 1.1
const ARROW_RIDER: Color = Color(1.0, 0.8, 0.1)
const ARROW_ROUTE: Color = Color(0.2, 0.95, 0.4)
var _arrow_mat: StandardMaterial3D
var _arrow_label: Label3D
var _arrow_time: float = 0.0
var _label_tick: int = -1

func _build_arrow() -> void:
	var pts: PackedVector2Array = PackedVector2Array([Vector2(0, -1.1), Vector2(0.8, 0.2), Vector2(0.3, 0.2),
		Vector2(0.3, 0.9), Vector2(-0.3, 0.9), Vector2(-0.3, 0.2), Vector2(-0.8, 0.2)])
	for i: int in pts.size():
		pts[i] *= ARROW_SCALE
	var mesh: ArrayMesh = ArrayMesh.new()
	# Surface 0: dark rim (drawn first, a little bigger and below the body).
	var rim: PackedVector2Array = Geometry2D.offset_polygon(pts, 0.11, Geometry2D.JOIN_MITER)[0]
	_add_prism(mesh, rim, -0.11, 0.06, Color(0.05, 0.08, 0.05), Color(0.05, 0.08, 0.05), 9)
	# Surface 1: the body — bright top, darker sides, so it reads from any angle.
	_arrow_mat = _add_prism(mesh, pts, -0.09, 0.09, Color.WHITE, Color(0.62, 0.62, 0.62), 10)
	_arrow = MeshInstance3D.new()
	_arrow.name = "GuidanceArrow"
	_arrow.mesh = mesh
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.visible = false
	add_child(_arrow)
	_arrow_label = Label3D.new()
	_arrow_label.name = "GuidanceLabel"
	_arrow_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_arrow_label.no_depth_test = true
	_arrow_label.render_priority = 11
	_arrow_label.font_size = 54
	_arrow_label.outline_size = 14
	_arrow_label.outline_modulate = Color(0, 0, 0, 0.85)
	_arrow_label.pixel_size = 0.0055
	_arrow_label.shaded = false
	_arrow_label.visible = false
	add_child(_arrow_label)

## Extrude `poly` (XZ plane) from y0 to y1 into `mesh` as one surface; returns its material.
static func _add_prism(mesh: ArrayMesh, poly: PackedVector2Array, y0: float, y1: float, top: Color, side: Color, prio: int) -> StandardMaterial3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	for y: float in [y0, y1]:
		st.set_color(top if y == y1 else side)
		for k: int in tri:
			st.add_vertex(Vector3(poly[k].x, y, poly[k].y))
	st.set_color(side)
	for i: int in poly.size():
		var a: Vector2 = poly[i - 1]
		var b: Vector2 = poly[i]
		for v: Vector3 in [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y),
				Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]:
			st.add_vertex(v)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = prio
	st.set_material(mat)
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mat

func guidance_target() -> Vector3:
	var p: Vector3 = _player.global_position
	if _route.size() >= 2:
		# Point a little ahead along the route from where we are.
		# Windowed search around the last match (the GPS path is dense; a full scan every
		# frame was a measurable cost on low-end phones). Full rescan only when far off.
		var best_i: int = clampi(_route_idx, 0, _route.size() - 1)
		var best_d: float = INF
		for i: int in range(maxi(_route_idx - 15, 0), mini(_route_idx + 120, _route.size())):
			var d: float = _route[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best_i = i
		if best_d > 900.0:
			for i: int in _route.size():
				var d: float = _route[i].distance_squared_to(p)
				if d < best_d:
					best_d = d
					best_i = i
		_route_idx = best_i
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
		_arrow_label.visible = false
		return
	var on_route: bool = _route.size() >= 2
	_arrow_time += get_physics_process_delta_time()
	var bob: float = sin(_arrow_time * 3.0) * 0.12
	var basis: Basis = Basis.looking_at(flat.normalized(), Vector3.UP)
	basis = basis * Basis(Vector3.RIGHT, ARROW_TILT_RAD) # lean back toward the chase camera
	var at: Vector3 = p + Vector3(0, ARROW_HEIGHT_M + 0.4 + bob, 0)
	_arrow.global_transform = Transform3D(basis, at)
	_arrow.visible = true
	_arrow_mat.albedo_color = ARROW_ROUTE if on_route else ARROW_RIDER
	_arrow_label.modulate = ARROW_ROUTE if on_route else ARROW_RIDER
	_arrow_label.global_position = at + Vector3(0, -0.85, 0) # between the arrow and the roof
	_arrow_label.visible = true
	var tick: int = int(_arrow_time * 4.0) # text 4× a second (the route sum walks the whole path)
	if tick == _label_tick:
		return
	_label_tick = tick
	var dist: float = _route_remaining() if on_route else Vector2(flat.x, flat.z).length()
	var what: String = tr("GUIDE_DROP") if on_route else tr("GUIDE_RIDER")
	_arrow_label.text = "%s  %s" % [what, ("%.1f km" % (dist / 1000.0)) if dist >= 1000.0 else ("%d m" % int(roundf(dist / 10.0) * 10.0))]

## Metres left along the GPS route from where we are.
func _route_remaining() -> float:
	var acc: float = 0.0
	for i: int in range(clampi(_route_idx, 0, _route.size() - 1), _route.size() - 1):
		acc += _route[i].distance_to(_route[i + 1])
	return acc

# --- Haptics -------------------------------------------------------------------------------

func vibrate(ms: int) -> void:
	if bool(GameState.settings.get("vibration", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, 0.6)
