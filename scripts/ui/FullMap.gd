class_name FullMap
extends Control
## Full-screen north-up Chennai map, opened by tapping the mini-map (or M). Real OSM streets
## with their names (English, Tamil underneath on main roads), water/parks/sea, the GPS route,
## waiting passengers, auto stands, LPG/EV bunks, garages and landmarks. Drag to pan, pinch or
## the +/− buttons to zoom, ◎ to re-centre. The game pauses while it is open.
##
## Drawing is cached: everything is redrawn only when the view changes, not every frame.

const BG: Color = Color(0.13, 0.14, 0.16, 1.0)
const ROAD_STYLE: Dictionary = { # class -> [colour, metres-width multiplier, min px]
	"trunk": [Color(0.98, 0.78, 0.35), 1.0, 3.0], "primary": [Color(0.98, 0.86, 0.5), 1.0, 2.5],
	"secondary": [Color(0.92, 0.92, 0.88), 1.0, 2.0], "tertiary": [Color(0.85, 0.85, 0.82), 1.0, 1.6],
}
const MINOR: Color = Color(0.62, 0.63, 0.65)
const MIN_SCALE: float = 0.05 # px per metre (whole city)
const MAX_SCALE: float = 3.0
const LABEL_CELL_PX: float = 170.0

var _on_foot: bool = false
var _parked_auto: Vector3 = Vector3.ZERO
var graph: RoadGraph
var scale_px: float = 0.6
var centre: Vector2 = Vector2.ZERO # world (x, z) at the screen centre
var _player: Vector3 = Vector3.ZERO
var _heading: Vector3 = Vector3.FORWARD
var _route: PackedVector3Array = PackedVector3Array()
var _hails: Array = []
var _areas: Dictionary = {}
var _pois: Array[Dictionary] = [] # {name, kind, pos: Vector2}
var _touches: Dictionary = {} # index -> Vector2
var _pinch_d: float = 0.0
var _font: Font
var _labels: Array[Dictionary] = [] # per named road: {name, ta, cls, a, b, len}
var _close_rect: Rect2
var _plus_rect: Rect2
var _minus_rect: Rect2
var _select_mode: int = 0 # 0 pan, 2 drop/drag destination pin
var _dragging_pin: bool = false
var _custom_destination: Vector3 = Vector3.ZERO
var _has_custom_destination: bool = false
var _destination_rect: Rect2
var _navigate_rect: Rect2
var _clear_rect: Rect2
var _press_at: Dictionary = {}
var _me_rect: Rect2

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_font = ThemeDB.fallback_font
	SignalBus.road_graph_ready.connect(_set_graph)
	if SignalBus.current_road_graph != null:
		_set_graph(SignalBus.current_road_graph)
	SignalBus.player_pose_updated.connect(func(p: Vector3, f: Vector3) -> void:
		_player = p
		_heading = f)
	SignalBus.route_updated.connect(func(pts: PackedVector3Array) -> void: _route = pts)
	SignalBus.hails_updated.connect(func(h: Array) -> void: _hails = h)
	SignalBus.full_map_requested.connect(set_open)
	SignalBus.on_foot_changed.connect(func(value: bool) -> void: _on_foot = value)
	SignalBus.parked_auto_position_changed.connect(func(pos: Vector3) -> void: _parked_auto = pos)
	SignalBus.custom_navigation_state_changed.connect(_on_custom_state)
	_load_world_extras()
	get_viewport().size_changed.connect(func() -> void:
		size = get_viewport().get_visible_rect().size
		queue_redraw())

func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	get_tree().paused = open
	if open:
		position = Vector2.ZERO
		size = get_viewport().get_visible_rect().size
		centre = Vector2(_player.x, _player.z)
		scale_px = 0.6
		queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_M:
		set_open(not visible)
	elif visible and k != null and k.pressed and k.physical_keycode == KEY_ESCAPE:
		set_open(false)

func _set_graph(g: RoadGraph) -> void:
	graph = g
	_labels.clear()
	var by_name: Dictionary = {}
	for e: RoadGraph.Edge in g.edges:
		if e.road_name == "" or e.points.size() < 2:
			continue
		# Longest edge per (name, ~400 m cell) carries the label: one label per stretch.
		var mid: Vector3 = e.points[e.points.size() / 2]
		var key: String = "%s|%d|%d" % [e.road_name, floori(mid.x / 400.0), floori(mid.z / 400.0)]
		if not by_name.has(key) or (by_name[key] as RoadGraph.Edge).length < e.length:
			by_name[key] = e
	for key: String in by_name:
		var e: RoadGraph.Edge = by_name[key]
		_labels.append({"name": e.road_name, "ta": e.road_name_ta, "cls": e.road_class, "edge": e})
	# Big roads first so they win label placement.
	_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank(str(a["cls"])) > _rank(str(b["cls"])))

static func _rank(cls: String) -> int:
	return {"trunk": 5, "primary": 4, "secondary": 3, "tertiary": 2}.get(cls, 1)

func _load_world_extras() -> void:
	var f: FileAccess = FileAccess.open("res://data/world/areas.json", FileAccess.READ)
	if f != null:
		_areas = JSON.parse_string(f.get_as_text()) as Dictionary
	var mf: FileAccess = FileAccess.open("res://data/world/manifest.json", FileAccess.READ)
	if mf == null:
		return
	var m: Dictionary = JSON.parse_string(mf.get_as_text()) as Dictionary
	for l: Dictionary in m.get("landmarks", []):
		_pois.append({"name": str(l["name"]), "kind": "landmark", "pos": Vector2(float(l["x"]), float(l["z"]))})
	for s: Dictionary in m.get("auto_stands", []):
		_pois.append({"name": str(s["name"]), "kind": "stand", "pos": Vector2(float(s["x"]), float(s["z"]))})
	for s: Dictionary in m.get("services", []):
		_pois.append({"name": str(s["name"]), "kind": str(s["kind"]), "pos": Vector2(float(s["x"]), float(s["z"]))})
	# Real-world landmarks built from the city-props file, with their fixed OSM coordinates.
	var props_file: FileAccess = FileAccess.open("res://data/world/city_props.json", FileAccess.READ)
	if props_file != null:
		var city: Dictionary = JSON.parse_string(props_file.get_as_text()) as Dictionary
		for prop: Dictionary in city.get("props", []):
			if not bool(prop.get("landmark", false)) and not bool(prop.get("tea_cluster", false)):
				continue
			var label: String = "Tea Kadai"
			_pois.append({"name": label, "kind": "landmark",
				"pos": Vector2(float(prop["x"]), float(prop["z"]))})

# --- Input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_touches[t.index] = t.position
			_press_at[t.index] = t.position
			if _touches.size() == 1 and _tap_button(t.position):
				_touches.erase(t.index)
		else:
			if _dragging_pin:
				_select_point(t.position)
				_dragging_pin = false
			elif _press_at.has(t.index) and (t.position as Vector2).distance_to(_press_at[t.index] as Vector2) < 14.0 and _select_mode != 0:
				_select_point(t.position)
			_press_at.erase(t.index)
			_touches.erase(t.index)
		_pinch_d = _pinch_distance()
		accept_event()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if _touches.size() >= 2:
			_touches[d.index] = d.position
			var nd: float = _pinch_distance()
			if _pinch_d > 1.0:
				_zoom_at(nd / _pinch_d, _pinch_mid())
			_pinch_d = nd
		else:
			_touches[d.index] = d.position
			if _select_mode == 2 or _dragging_pin:
				_dragging_pin = true
				_select_point(d.position)
			else:
				centre -= d.relative / scale_px
		queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			if not _tap_button(mb.position) and _select_mode != 0:
				_select_point(mb.position)
		accept_event()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT and not DisplayServer.is_touchscreen_available():
		centre -= (event as InputEventMouseMotion).relative / scale_px
		queue_redraw()

func _tap_button(p: Vector2) -> bool:
	if _destination_rect.has_point(p):
		_select_mode = 2
		queue_redraw()
	elif _navigate_rect.has_point(p):
		if _has_custom_destination:
			SignalBus.custom_navigation_requested.emit(_player, _custom_destination)
			set_open(false)
		else:
			SignalBus.hint_requested.emit("Drop a pin on the map first", 2.0)
	elif _clear_rect.has_point(p):
		_has_custom_destination = false
		_select_mode = 0
		SignalBus.custom_navigation_cleared.emit()
		queue_redraw()
	elif _close_rect.has_point(p):
		set_open(false)
	elif _plus_rect.has_point(p):
		_zoom_at(1.5, size * 0.5)
	elif _minus_rect.has_point(p):
		_zoom_at(1.0 / 1.5, size * 0.5)
	elif _me_rect.has_point(p):
		centre = Vector2(_player.x, _player.z)
		queue_redraw()
	else:
		return false
	return true

func _select_point(screen_point: Vector2) -> void:
	var w: Vector2 = to_world(screen_point)
	var point: Vector3 = Vector3(w.x, 0.0, w.y)
	_custom_destination = point
	_has_custom_destination = true
	# Keep selection mode active so the pin can be dragged until Set Route.
	_select_mode = 2
	queue_redraw()

func _on_custom_state(active: bool, start: Vector3, destination: Vector3) -> void:
	if active:
		_custom_destination = destination
		_has_custom_destination = true
	else:
		_has_custom_destination = false
	queue_redraw()

func _zoom_at(factor: float, screen_pt: Vector2) -> void:
	var before: Vector2 = to_world(screen_pt)
	scale_px = clampf(scale_px * factor, MIN_SCALE, MAX_SCALE)
	centre += before - to_world(screen_pt)
	queue_redraw()

func _pinch_distance() -> float:
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1] as Vector2) if v.size() >= 2 else 0.0

func _pinch_mid() -> Vector2:
	var v: Array = _touches.values()
	return ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5 if v.size() >= 2 else size * 0.5

func to_screen(w: Vector2) -> Vector2:
	return size * 0.5 + (w - centre) * scale_px

func to_world(s: Vector2) -> Vector2:
	return centre + (s - size * 0.5) / scale_px

# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var view: Rect2 = Rect2(to_world(Vector2.ZERO), size / scale_px).grow(60.0)
	_draw_areas(view)
	if graph != null:
		_draw_roads(view)
	_draw_route()
	_draw_pois(view)
	if graph != null:
		_draw_labels(view)
	_draw_hails()
	_draw_player()
	if _on_foot:
		var pin: Vector2 = to_screen(Vector2(_parked_auto.x, _parked_auto.z))
		draw_circle(pin, 13.0, Color.BLACK)
		draw_circle(pin, 10.0, Color(0.2, 0.95, 0.4))
		draw_string(_font, pin + Vector2(14.0, 5.0), "Parked Auto", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	_draw_custom_pins()
	_draw_chrome()

func _draw_areas(view: Rect2) -> void:
	var cols: Dictionary = {"sea": Color(0.12, 0.3, 0.45), "water": Color(0.16, 0.36, 0.52), "park": Color(0.17, 0.33, 0.2), "beach": Color(0.55, 0.5, 0.36)}
	for kind: String in ["sea", "beach", "park", "water"]:
		for poly: Array in _areas.get(kind, []):
			if poly.size() < 3:
				continue
			var pts: PackedVector2Array = PackedVector2Array()
			var bb: Rect2 = Rect2(Vector2(float(poly[0][0]), float(poly[0][1])), Vector2.ZERO)
			for p: Array in poly:
				var w: Vector2 = Vector2(float(p[0]), float(p[1]))
				bb = bb.expand(w)
				pts.append(to_screen(w))
			if not bb.intersects(view):
				continue
			if Geometry2D.triangulate_polygon(pts).is_empty():
				draw_polyline(pts, cols[kind], 2.0) # rivers drawn as lines (non-simple polygons)
			else:
				draw_colored_polygon(pts, cols[kind])

func _draw_roads(view: Rect2) -> void:
	var minor: PackedVector2Array = PackedVector2Array()
	var major: Dictionary = {}
	for e: RoadGraph.Edge in graph.edges:
		var a0: Vector3 = e.points[0]
		if not view.has_point(Vector2(a0.x, a0.z)) and not view.has_point(Vector2(e.points[e.points.size() - 1].x, e.points[e.points.size() - 1].z)):
			continue
		var target: PackedVector2Array = minor
		if ROAD_STYLE.has(e.road_class):
			if not major.has(e.road_class):
				major[e.road_class] = PackedVector2Array()
			target = major[e.road_class]
		elif scale_px < 0.12:
			continue # residential lanes vanish when zoomed far out
		for i: int in range(1, e.points.size()):
			target.append(to_screen(Vector2(e.points[i - 1].x, e.points[i - 1].z)))
			target.append(to_screen(Vector2(e.points[i].x, e.points[i].z)))
		if target != minor:
			major[e.road_class] = target
		else:
			minor = target
	if not minor.is_empty():
		draw_multiline(minor, MINOR, maxf(1.0, 6.0 * scale_px))
	for cls: String in ["tertiary", "secondary", "primary", "trunk"]:
		if major.has(cls):
			var st: Array = ROAD_STYLE[cls]
			draw_multiline(major[cls], st[0], maxf(float(st[2]), 12.0 * scale_px * float(st[1])))

func _draw_route() -> void:
	if _route.size() < 2:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for p: Vector3 in _route:
		pts.append(to_screen(Vector2(p.x, p.z)))
	draw_polyline(pts, Color(1, 1, 1, 0.9), maxf(7.0, 14.0 * scale_px))
	draw_polyline(pts, Color(0.16, 0.55, 1.0), maxf(4.5, 10.0 * scale_px))
	var dest: Vector2 = pts[pts.size() - 1]
	draw_circle(dest, 10.0, Color.WHITE)
	draw_circle(dest, 7.0, Color(0.2, 0.85, 0.4))

func _draw_pois(view: Rect2) -> void:
	var icon: Dictionary = {"landmark": ["★", Color(1, 0.8, 0.3)], "stand": ["A", Color(1, 0.75, 0.1)], "lpg": ["⛽", Color(0.95, 0.4, 0.3)], "ev": ["⚡", Color(0.4, 0.9, 1)], "garage": ["🔧", Color(0.8, 0.8, 0.85)]}
	for p: Dictionary in _pois:
		var w: Vector2 = p["pos"]
		if not view.has_point(w):
			continue
		var s: Vector2 = to_screen(w)
		var ic: Array = icon.get(str(p["kind"]), ["•", Color.WHITE])
		draw_circle(s, 11.0, Color(0, 0, 0, 0.7))
		draw_string(_font, s + Vector2(-7, 7), str(ic[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ic[1])
		if scale_px >= 0.25 or str(p["kind"]) == "landmark":
			draw_string_outline(_font, s + Vector2(14, 6), str(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85))
			draw_string(_font, s + Vector2(14, 6), str(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ic[1])

## Street names along the roads, rotated to the road, decluttered on a screen grid.
func _draw_labels(view: Rect2) -> void:
	var used: Dictionary = {}
	var min_rank: int = 4 if scale_px < 0.15 else (3 if scale_px < 0.35 else (2 if scale_px < 0.8 else 1))
	for l: Dictionary in _labels:
		if _rank(str(l["cls"])) < min_rank:
			continue
		var e: RoadGraph.Edge = l["edge"]
		var mid_i: int = e.points.size() / 2
		var a: Vector3 = e.points[maxi(mid_i - 1, 0)]
		var b: Vector3 = e.points[mini(mid_i, e.points.size() - 1)]
		if a.is_equal_approx(b):
			b = e.points[e.points.size() - 1]
		var mid: Vector2 = Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		if not view.has_point(mid) or e.length * scale_px < 60.0:
			continue
		var s: Vector2 = to_screen(mid)
		var cell: Vector2i = Vector2i(floori(s.x / LABEL_CELL_PX), floori(s.y / (LABEL_CELL_PX * 0.4)))
		if used.has(cell):
			continue
		used[cell] = true
		var ang: float = atan2(b.z - a.z, b.x - a.x)
		if ang > PI * 0.5:
			ang -= PI
		elif ang < -PI * 0.5:
			ang += PI
		var name: String = str(l["name"])
		var fs: int = 15 if _rank(str(l["cls"])) >= 3 else 13
		var w: float = _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(s, ang, Vector2.ONE)
		draw_string_outline(_font, Vector2(-w * 0.5, 5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(_font, Vector2(-w * 0.5, 5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var ta: String = str(l["ta"])
		if ta != "" and scale_px >= 0.5:
			var tw: float = _font.get_string_size(ta, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2).x
			draw_string_outline(_font, Vector2(-tw * 0.5, 22), ta, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, 4, Color(0, 0, 0, 0.9))
			draw_string(_font, Vector2(-tw * 0.5, 22), ta, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(1, 0.9, 0.6))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hails() -> void:
	for h: Dictionary in _hails:
		var p: Vector3 = h["position"]
		var s: Vector2 = to_screen(Vector2(p.x, p.z))
		draw_circle(s, 9.0, Color(0, 0, 0, 0.7))
		draw_circle(s, 6.5, Color(1.0, 0.82, 0.1))

func _draw_player() -> void:
	var s: Vector2 = to_screen(Vector2(_player.x, _player.z))
	var f: Vector2 = Vector2(_heading.x, _heading.z).normalized()
	if f == Vector2.ZERO:
		f = Vector2(0, -1)
	var r: Vector2 = Vector2(-f.y, f.x)
	draw_circle(s, 16.0, Color(1.0, 0.85, 0.0, 0.25))
	draw_colored_polygon(PackedVector2Array([s + f * 14.0, s - f * 9.0 + r * 9.0, s - f * 4.0, s - f * 9.0 - r * 9.0]), Color(1.0, 0.82, 0.0))
	draw_polyline(PackedVector2Array([s + f * 14.0, s - f * 9.0 + r * 9.0, s - f * 4.0, s - f * 9.0 - r * 9.0, s + f * 14.0]), Color.BLACK, 2.0)

func _draw_custom_pins() -> void:
	for entry: Array in [[_has_custom_destination, _custom_destination, "●", Color(1.0, 0.4, 0.25)]]:
		if not bool(entry[0]):
			continue
		var p: Vector3 = entry[1]
		var screen: Vector2 = to_screen(Vector2(p.x, p.z))
		draw_circle(screen, 14.0, Color.BLACK)
		draw_circle(screen, 11.0, entry[3] as Color)
		draw_string(_font, screen + Vector2(-6.0, 5.0), str(entry[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)

func _draw_chrome() -> void:
	var b: float = 64.0
	_close_rect = Rect2(Vector2(size.x - b - 20.0, 20.0), Vector2(b, b))
	_plus_rect = Rect2(Vector2(size.x - b - 20.0, size.y * 0.5 - b - 6.0), Vector2(b, b))
	_minus_rect = Rect2(Vector2(size.x - b - 20.0, size.y * 0.5 + 6.0), Vector2(b, b))
	_me_rect = Rect2(Vector2(size.x - b - 20.0, size.y * 0.5 + b + 18.0), Vector2(b, b))
	for pair: Array in [[_close_rect, "✕"], [_plus_rect, "+"], [_minus_rect, "−"], [_me_rect, "◎"]]:
		var rc: Rect2 = pair[0]
		draw_rect(rc, Color(0.05, 0.05, 0.06, 0.85))
		draw_rect(rc, Color(1.0, 0.72, 0.1), false, 2.0)
		draw_string(_font, rc.position + Vector2(0, rc.size.y * 0.68), str(pair[1]), HORIZONTAL_ALIGNMENT_CENTER, rc.size.x, 34, Color.WHITE)
	draw_string_outline(_font, Vector2(24, 48), "CHENNAI", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color.BLACK)
	draw_string(_font, Vector2(24, 48), "CHENNAI", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1.0, 0.72, 0.1))
	draw_string(_font, Vector2(24, size.y - 18.0), "Map data © OpenStreetMap contributors", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	var button_width: float = minf(175.0, (size.x - 44.0) / 3.0)
	var gap: float = 6.0
	var y: float = size.y - 98.0
	_destination_rect = Rect2(Vector2(16.0, y), Vector2(button_width, 56.0))
	_navigate_rect = Rect2(Vector2(16.0 + button_width + gap, y), Vector2(button_width, 56.0))
	_clear_rect = Rect2(Vector2(16.0 + (button_width + gap) * 2.0, y), Vector2(button_width, 56.0))
	for entry: Array in [[_destination_rect, "Drop Pin", 2], [_navigate_rect, "Set Route", 0], [_clear_rect, "Clear", 0]]:
		var rc: Rect2 = entry[0]
		var selected: bool = _select_mode == int(entry[2]) and _select_mode != 0
		draw_rect(rc, Color(0.7, 0.47, 0.08) if selected else Color(0.05, 0.05, 0.06, 0.92))
		draw_rect(rc, Color(1.0, 0.72, 0.1), false, 2.0)
		draw_string(_font, rc.position + Vector2(0.0, 35.0), str(entry[1]), HORIZONTAL_ALIGNMENT_CENTER, rc.size.x, 17, Color.WHITE)
	if _select_mode != 0:
		draw_string(_font, Vector2(20.0, size.y - 114.0), "Tap or drag to position the pin", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	# North arrow.
	var n: Vector2 = Vector2(48, 96)
	draw_colored_polygon(PackedVector2Array([n + Vector2(0, -18), n + Vector2(9, 8), n + Vector2(-9, 8)]), Color(1, 0.4, 0.35))
	draw_string(_font, n + Vector2(-6, 28), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
