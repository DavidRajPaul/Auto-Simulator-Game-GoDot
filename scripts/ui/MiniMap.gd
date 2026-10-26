class_name MiniMap
extends Control
## Circular heading-up mini-map (GDD HUD: top-left). Roads come from the published
## RoadGraph via a segment grid; everything else via SignalBus. Roads draw with one
## draw_multiline call, redrawn at ~15 Hz.

const RANGE_M: float = 300.0
const CELL_M: float = 100.0
const REDRAW_INTERVAL_S: float = 1.0 / 15.0

var _grid: Dictionary = {} # Vector2i -> PackedVector2Array (pairs of segment endpoints)
var _player: Vector3 = Vector3.ZERO
var _heading: Vector3 = Vector3.FORWARD
var _route: PackedVector3Array = PackedVector3Array()
var _hails: Array = []
var _timer: float = 0.0

## Painted ring and pins (TouchHUD.HUD_ATLAS). The ring turns with north, so its "N" stays true.
var _hud_tex: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(TouchHUD.HUD_ATLAS):
		_hud_tex = load(TouchHUD.HUD_ATLAS) as Texture2D
	SignalBus.road_graph_ready.connect(_build_grid)
	if SignalBus.current_road_graph != null:
		_build_grid(SignalBus.current_road_graph)
	SignalBus.player_pose_updated.connect(func(p: Vector3, f: Vector3) -> void:
		_player = p
		_heading = f)
	SignalBus.route_updated.connect(func(pts: PackedVector3Array) -> void: _route = pts)
	SignalBus.hails_updated.connect(func(h: Array) -> void: _hails = h)

func _build_grid(graph: RoadGraph) -> void:
	_grid.clear()
	for e: RoadGraph.Edge in graph.edges:
		for i: int in range(1, e.points.size()):
			var a: Vector3 = e.points[i - 1]
			var b: Vector3 = e.points[i]
			var key: Vector2i = Vector2i(floori((a.x + b.x) * 0.5 / CELL_M), floori((a.z + b.z) * 0.5 / CELL_M))
			if not _grid.has(key):
				_grid[key] = PackedVector2Array()
			var arr: PackedVector2Array = _grid[key]
			arr.append(Vector2(a.x, a.z))
			arr.append(Vector2(b.x, b.z))
			_grid[key] = arr

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= REDRAW_INTERVAL_S:
		_timer = 0.0
		queue_redraw()

## World (x, z) → minimap pixels, rotated so the player's heading points up.
func _to_map(p: Vector2, centre: Vector2, scale_px: float, rot: float) -> Vector2:
	return centre + (p - Vector2(_player.x, _player.z)).rotated(rot) * scale_px

func _draw() -> void:
	var r: float = size.x * 0.5
	var centre: Vector2 = Vector2(r, r)
	var scale_px: float = r / RANGE_M
	var rot: float = -atan2(_heading.x, -_heading.z)
	draw_circle(centre, r, Color(0.08, 0.09, 0.1, 0.78))
	# Roads.
	var lines: PackedVector2Array = PackedVector2Array()
	var c: Vector2i = Vector2i(floori(_player.x / CELL_M), floori(_player.z / CELL_M))
	var n: int = ceili(RANGE_M / CELL_M) + 1
	for dx: int in range(-n, n + 1):
		for dz: int in range(-n, n + 1):
			var seg: Variant = _grid.get(c + Vector2i(dx, dz))
			if seg == null:
				continue
			var arr: PackedVector2Array = seg
			for i: int in range(0, arr.size(), 2):
				var a: Vector2 = _to_map(arr[i], centre, scale_px, rot)
				var b: Vector2 = _to_map(arr[i + 1], centre, scale_px, rot)
				var clipped: PackedVector2Array = _clip(a, b, centre, r - 3.0)
				if clipped.size() == 2:
					lines.append_array(clipped)
	if not lines.is_empty():
		draw_multiline(lines, Color(0.75, 0.75, 0.72, 0.9), 2.0)
	# Route.
	if _route.size() >= 2:
		var route_lines: PackedVector2Array = PackedVector2Array()
		for i: int in range(1, _route.size()):
			var a: Vector2 = _to_map(Vector2(_route[i - 1].x, _route[i - 1].z), centre, scale_px, rot)
			var b: Vector2 = _to_map(Vector2(_route[i].x, _route[i].z), centre, scale_px, rot)
			var clipped: PackedVector2Array = _clip(a, b, centre, r - 3.0)
			if clipped.size() == 2:
				route_lines.append_array(clipped)
		if not route_lines.is_empty():
			draw_multiline(route_lines, Color(0.25, 1.0, 0.45), 4.0)
		var dest: Vector2 = _to_map(Vector2(_route[_route.size() - 1].x, _route[_route.size() - 1].z), centre, scale_px, rot)
		draw_circle(_clamp_to(dest, centre, r - 7.0), 6.0, Color(0.25, 1.0, 0.45))
	# Hails.
	for h: Dictionary in _hails:
		var p: Vector3 = h["position"]
		var m: Vector2 = _to_map(Vector2(p.x, p.z), centre, scale_px, rot)
		var hp: Vector2 = _clamp_to(m, centre, r - 6.0)
		if _hud_tex != null:
			# Pin tip on the rider's spot.
			draw_texture_rect_region(_hud_tex, Rect2(hp - Vector2(11, 26), Vector2(22, 26)), TouchHUD.HUD_REGIONS["pin_rider"] as Rect2)
		else:
			draw_circle(hp, 5.0, Color(1.0, 0.82, 0.1))
	# Player arrow + north tick + rim.
	if _hud_tex != null:
		draw_texture_rect_region(_hud_tex, Rect2(centre - Vector2(13, 15), Vector2(26, 30)), TouchHUD.HUD_REGIONS["pin_player"] as Rect2)
		var ring: float = r * 2.0 / 0.84
		draw_set_transform(centre, rot, Vector2.ONE)
		draw_texture_rect_region(_hud_tex, Rect2(-Vector2(ring, ring) * 0.5, Vector2(ring, ring)), TouchHUD.HUD_REGIONS["map_frame"] as Rect2)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -9), centre + Vector2(6, 7), centre + Vector2(-6, 7)]), Color(1.0, 0.85, 0.0))
	var north: Vector2 = centre + Vector2(0, -1).rotated(rot) * (r - 9.0)
	draw_string(ThemeDB.fallback_font, north - Vector2(5, -6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.4, 0.35))
	draw_arc(centre, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)

func _clamp_to(p: Vector2, centre: Vector2, radius: float) -> Vector2:
	var d: Vector2 = p - centre
	return centre + d.limit_length(radius)

## Clip segment ab to a circle; returns [] when fully outside.
func _clip(a: Vector2, b: Vector2, centre: Vector2, radius: float) -> PackedVector2Array:
	var ain: bool = a.distance_to(centre) <= radius
	var bin: bool = b.distance_to(centre) <= radius
	if ain and bin:
		return PackedVector2Array([a, b])
	var d: Vector2 = b - a
	var f: Vector2 = a - centre
	var qa: float = d.dot(d)
	if qa < 0.0001:
		return PackedVector2Array()
	var qb: float = 2.0 * f.dot(d)
	var qc: float = f.dot(f) - radius * radius
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return PackedVector2Array()
	var sq: float = sqrt(disc)
	var t1: float = clampf((-qb - sq) / (2.0 * qa), 0.0, 1.0)
	var t2: float = clampf((-qb + sq) / (2.0 * qa), 0.0, 1.0)
	if t2 - t1 < 0.0001:
		return PackedVector2Array()
	return PackedVector2Array([a + d * t1, a + d * t2])
