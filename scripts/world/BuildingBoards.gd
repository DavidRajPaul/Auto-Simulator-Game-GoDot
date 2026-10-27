class_name BuildingBoards
extends Node3D
## Name boards on Chennai buildings, from real OpenStreetMap places
## (data/world/building_names.json, built by tools/osm/build_building_names.py).
##
##   shop  — a painted fascia across a ground-floor front, above the awnings (English).
##   panel — a big name panel high on a named building: colleges, hospitals, temples, towers
##           (English, with the Tamil name above it where OSM has one).
## Public places keep their real names; businesses carry Chennai parody names (see the tool).
## Every board sits on the wall that faces the street.
##
## Pooled like StreetSigns: MAX_BOARDS boards are built once and moved to the nearest spots as the
## player drives. Per board: 1 box (1 draw) + 1–2 Label3D, culled past VISIBLE_M.

const SPOTS_FILE: String = "res://data/world/building_names.json"
const MAX_BOARDS: int = 12
const SEARCH_M: float = 110.0
const VISIBLE_M: float = 90.0
const PANEL_VISIBLE_M: float = 150.0
const PANEL_BIAS: float = 0.6 # panels count as this fraction of their distance (seen from further away)
const UPDATE_S: float = 0.6
const CELL_M: float = 60.0
const DEPTH_M: float = 0.08
const SHOP_H: float = 0.72
const PANEL_H: float = 1.15
## [board colour, text colour] per style index (tool: 0 food, 1 cafe/office, 2 bank/electronics,
## 3 textiles, 4 jewellery/cinema, 5 hotel/halls, 6 stores, 7 medical, 8 buildings/apartments,
## 9 public, 10 temples, 11 government).
const STYLES: Array = [
	[Color(0.78, 0.1, 0.08), Color(1.0, 0.88, 0.2)],
	[Color(0.96, 0.95, 0.9), Color(0.08, 0.16, 0.45)],
	[Color(0.05, 0.25, 0.6), Color(1, 1, 1)],
	[Color(0.45, 0.05, 0.12), Color(1.0, 0.8, 0.35)],
	[Color(0.22, 0.06, 0.3), Color(1.0, 0.82, 0.3)],
	[Color(0.05, 0.36, 0.22), Color(1, 1, 1)],
	[Color(1.0, 0.82, 0.1), Color(0.75, 0.05, 0.05)],
	[Color(0.97, 0.97, 0.97), Color(0.0, 0.45, 0.2)],
	[Color(0.92, 0.87, 0.74), Color(0.3, 0.16, 0.06)],
	[Color(0.97, 0.97, 0.95), Color(0.06, 0.15, 0.42)],
	[Color(0.96, 0.55, 0.1), Color(0.42, 0.04, 0.04)],
	[Color(0.06, 0.4, 0.2), Color(1.0, 0.92, 0.3)],
]

var _player: Vector3 = Vector3.ZERO
var _pool: Array[Node3D] = []
var _assigned: Dictionary = {} # spot index -> Node3D
var _spots: Array = [] # [x, z, yaw, width, y, kind, en, ta, style]
var _grid: Dictionary = {}
var _timer: float = UPDATE_S

func _ready() -> void:
	_load_spots()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	for i: int in MAX_BOARDS:
		var n: Node3D = Node3D.new()
		n.name = "Board_%d" % i
		n.visible = false
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Plate"
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.roughness = 0.55
		mi.material_override = mat
		n.add_child(mi)
		n.add_child(_label("English"))
		n.add_child(_label("Tamil"))
		add_child(n)
		_pool.append(n)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _load_spots() -> void:
	var f: FileAccess = FileAccess.open(SPOTS_FILE, FileAccess.READ)
	if f == null:
		push_warning("BuildingBoards: %s missing — run tools/osm/build_building_names.py" % SPOTS_FILE)
		return
	_spots = JSON.parse_string(f.get_as_text()) as Array
	for i: int in _spots.size():
		var s: Array = _spots[i]
		var k: Vector2i = Vector2i(floori(float(s[0]) / CELL_M), floori(float(s[1]) / CELL_M))
		var arr: PackedInt32Array = _grid.get(k, PackedInt32Array())
		arr.append(i)
		_grid[k] = arr

func _label(label_name: String) -> Label3D:
	var l: Label3D = Label3D.new()
	l.name = label_name
	l.position.z = DEPTH_M * 0.5 + 0.008
	l.font_size = 64
	l.outline_size = 0
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.shaded = false
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l

func _process(delta: float) -> void:
	if _spots.is_empty():
		return
	_timer += delta
	if _timer < UPDATE_S:
		return
	_timer = 0.0
	refresh()

## Re-pick the nearest boards. Public for tests.
func refresh() -> void:
	var wanted: Array[Dictionary] = candidates(_player)
	var keep: Dictionary = {}
	for c: Dictionary in wanted:
		keep[c["key"]] = true
	for key: Variant in _assigned.keys():
		if not keep.has(key):
			(_assigned[key] as Node3D).visible = false
			_assigned.erase(key)
	for c: Dictionary in wanted:
		if _assigned.has(c["key"]):
			continue
		var n: Node3D = _free_board()
		if n == null:
			break
		_place(n, c["key"])
		_assigned[c["key"]] = n

func _free_board() -> Node3D:
	for n: Node3D in _pool:
		if not n.visible:
			return n
	return null

## Spots near `p`, nearest (bias-weighted) first: {key, dist}.
func candidates(p: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r: int = ceili(SEARCH_M / CELL_M)
	var c: Vector2i = Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))
	for dx: int in range(-r, r + 1):
		for dz: int in range(-r, r + 1):
			for i: int in _grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var s: Array = _spots[i]
				var d: float = Vector2(float(s[0]) - p.x, float(s[1]) - p.z).length()
				if d > SEARCH_M:
					continue
				if str(s[5]) == "panel":
					d *= PANEL_BIAS
				out.append({"key": i, "dist": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	if out.size() > MAX_BOARDS:
		out.resize(MAX_BOARDS)
	return out

func spot(i: int) -> Array:
	return _spots[i]

func spot_count() -> int:
	return _spots.size()

func active_boards() -> int:
	var n: int = 0
	for b: Node3D in _pool:
		n += 1 if b.visible else 0
	return n

func _place(n: Node3D, i: int) -> void:
	var s: Array = _spots[i]
	var width: float = float(s[3])
	var panel: bool = str(s[5]) == "panel"
	var en_text: String = str(s[6])
	var ta_text: String = str(s[7]) if panel else ""
	var style: Array = STYLES[clampi(int(s[8]), 0, STYLES.size() - 1)]
	# Panels higher up get bigger lettering (same factor as the tool's width).
	var k_size: float = clampf(float(s[4]) / 9.0, 1.0, 2.2)
	var h: float = PANEL_H * k_size * (1.35 if ta_text != "" else 1.0) if panel else SHOP_H
	var range_m: float = PANEL_VISIBLE_M if panel else VISIBLE_M
	n.position = Vector3(float(s[0]), float(s[4]), float(s[1]))
	n.rotation = Vector3(0.0, float(s[2]), 0.0)
	var plate: MeshInstance3D = n.get_node("Plate") as MeshInstance3D
	plate.scale = Vector3(width, h, DEPTH_M)
	plate.visibility_range_end = range_m
	(plate.material_override as StandardMaterial3D).albedo_color = style[0]
	var en: Label3D = n.get_node("English") as Label3D
	var ta: Label3D = n.get_node("Tamil") as Label3D
	var text: String = en_text.to_upper() if not panel or en_text.length() <= 22 else en_text
	_fit(en, text, width * 0.9, (h * (0.42 if ta_text != "" else 0.62)), style[1], range_m)
	en.position.y = -h * 0.2 if ta_text != "" else 0.0
	ta.visible = ta_text != ""
	if ta.visible:
		_fit(ta, ta_text, width * 0.9, h * 0.36, style[1], range_m)
		ta.position.y = h * 0.24
	n.visible = true

## Size a label to fill (but not overflow) `max_w` × `max_h` metres.
static func _fit(l: Label3D, text: String, max_w: float, max_h: float, col: Color, range_m: float) -> void:
	l.text = text
	l.modulate = col
	l.visibility_range_end = range_m * 0.85
	var font: Font = l.font if l.font != null else ThemeDB.fallback_font
	var px: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size)
	var by_w: float = max_w / maxf(px.x, 1.0)
	var by_h: float = max_h / maxf(float(l.font_size) * 1.1, 1.0)
	l.pixel_size = minf(by_w, by_h)
