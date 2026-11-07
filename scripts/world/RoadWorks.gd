class_name RoadWorks
extends Node3D
## Metro rail works at the Lighthouse (data/world/road_works.json, tools/osm/build_road_works.py):
## a hoarded station-box site beside Kamarajar Salai, the Foreshore Estate slip closed with
## water-filled barrier rows, ROAD CLOSED boards on the barriers and TAKE DIVERSION boards on the
## approaches. The closed roads are taken out of traffic, GPS and hail spots by apply_closures()
## (called by ChennaiTrafficManager as soon as the graph loads).
##
## Draw cost: one merged mesh (vertex colours) + a few Label3D boards culled past BOARD_VISIBLE_M.

const DATA_FILE: String = "res://data/world/road_works.json"
const MESH_VISIBLE_M: float = 650.0
const BOARD_VISIBLE_M: float = 110.0
const HOARD_H: float = 2.5
const PANEL_W: float = 2.0
const GATE_W: float = 8.0
const BLUE: Color = Color(0.12, 0.3, 0.62)
const WHITE: Color = Color(0.93, 0.93, 0.9)
const GREEN: Color = Color(0.08, 0.55, 0.32)
const STEEL: Color = Color(0.45, 0.47, 0.48)
const YELLOW: Color = Color(0.96, 0.72, 0.06)
const DARK: Color = Color(0.12, 0.12, 0.13)
const EARTH: Color = Color(0.42, 0.3, 0.2)
const EARTH_DARK: Color = Color(0.27, 0.19, 0.13)
const CONCRETE: Color = Color(0.64, 0.63, 0.6)
const RUST: Color = Color(0.5, 0.26, 0.12)
const RED: Color = Color(0.86, 0.1, 0.08)
const ORANGE: Color = Color(0.98, 0.45, 0.05)

var data: Dictionary = {}
var site_count: int = 0
var row_count: int = 0
var board_count: int = 0

## Close the works' roads on the live graph (traffic, GPS and kerb picks skip closed edges).
static func apply_closures(graph: RoadGraph) -> int:
	var d: Dictionary = load_data()
	var n: int = 0
	for ei: Variant in d.get("closed_edges", []):
		var i: int = int(ei)
		if i >= 0 and i < graph.edges.size():
			graph.edges[i].closed = true
			n += 1
	return n

static func load_data() -> Dictionary:
	if not FileAccess.file_exists(DATA_FILE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
	return parsed as Dictionary if parsed is Dictionary else {}

func _ready() -> void:
	data = load_data()
	if data.is_empty():
		return
	var st: SurfaceTool = MeshKit.begin()
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for site: Dictionary in data.get("sites", []):
		_build_site(st, body, site)
		site_count += 1
	for row: Dictionary in data.get("rows", []):
		_build_row(st, body, row)
		row_count += 1
	for board: Dictionary in data.get("boards", []):
		_build_board(st, body, board)
		board_count += 1
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Works"
	mi.mesh = MeshKit.finish(st, mat)
	mi.visibility_range_end = MESH_VISIBLE_M
	add_child(mi)

# --- helpers ------------------------------------------------------------------------------------

static func _v2(a: Variant) -> Vector2:
	var arr: Array = a as Array
	return Vector2(float(arr[0]), float(arr[1]))

## Box in a frame turned by `yaw` about Y around world point `origin` (local x across, z along).
static func _obox(st: SurfaceTool, origin: Vector3, yaw: float, local: Vector3, size: Vector3, colour: Color, extra: Basis = Basis.IDENTITY) -> void:
	var b: Basis = Basis(Vector3.UP, yaw)
	MeshKit.box(st, origin + b * local, size, colour, b * extra)

func _solid(body: StaticBody3D, origin: Vector3, yaw: float, local: Vector3, size: Vector3) -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	var b: Basis = Basis(Vector3.UP, yaw)
	cs.transform = Transform3D(b, origin + b * local)
	body.add_child(cs)

func _ground_y(p: Vector2) -> float:
	var g: RoadGraph = SignalBus.current_road_graph
	if g == null:
		return 0.0
	var c: Dictionary = g.closest_point(Vector3(p.x, 0.0, p.y))
	return 0.0 if int(c["edge"]) < 0 else g.sample(int(c["edge"]), float(c["s"]), 1)[0].y

# --- the station-box site -----------------------------------------------------------------------

## Local frame: +Z along the road (length), +X across (width). The long wall nearer the road has
## the gate; inside: earth, the diaphragm-wall trench round the station box, a crawler crane, a
## piling rig, rebar cages, site cabins and a floodlight mast.
func _build_site(st: SurfaceTool, body: StaticBody3D, site: Dictionary) -> void:
	var c: Vector2 = _v2(site["c"])
	var yaw: float = float(site["yaw"])
	var length: float = float(site["len"])
	var wid: float = float(site["wid"])
	var o: Vector3 = Vector3(c.x, _ground_y(c), c.y)
	var hx: float = wid * 0.5
	var hz: float = length * 0.5
	# Which long side faces the road: towards the nearest open road from the centre.
	var road_side: float = 1.0
	var g: RoadGraph = SignalBus.current_road_graph
	if g != null:
		var near: Dictionary = g.closest_point(o)
		if int(near["edge"]) >= 0:
			var rp: Vector3 = g.sample(int(near["edge"]), float(near["s"]), 1)[0]
			road_side = signf((Basis(Vector3.UP, yaw).inverse() * (rp - o)).x)
			if road_side == 0.0:
				road_side = 1.0
	set_meta("road_side", road_side)
	# Ground inside.
	_obox(st, o, yaw, Vector3(0.0, 0.02, 0.0), Vector3(wid - 0.2, 0.04, length - 0.2), EARTH)
	# Station box: a dark pit outline (excavation) ringed by grey guide walls.
	var bx: float = hx * 0.55
	var bz: float = hz * 0.62
	_obox(st, o, yaw, Vector3(-road_side * 1.5, 0.045, 0.0), Vector3(bx * 2.0, 0.02, bz * 2.0), EARTH_DARK)
	for sz: float in [-1.0, 1.0]:
		_obox(st, o, yaw, Vector3(-road_side * 1.5, 0.25, sz * bz), Vector3(bx * 2.0 + 0.6, 0.5, 0.6), CONCRETE)
	for sx: float in [-1.0, 1.0]:
		_obox(st, o, yaw, Vector3(-road_side * 1.5 + sx * bx, 0.25, 0.0), Vector3(0.6, 0.5, bz * 2.0), CONCRETE)
	# Spoil heaps.
	for k: int in 3:
		var p: Vector3 = Vector3(-road_side * (hx - 3.2), 0.6 + 0.2 * float(k), -hz + 5.0 + float(k) * 3.4)
		_obox(st, o, yaw, p, Vector3(4.0 - float(k), 1.2 + 0.4 * float(k), 3.2), EARTH.darkened(0.1 * float(k)), Basis(Vector3.UP, 0.4 * float(k)))
	# Hoarding round the site, gate in the road-side wall.
	var walls: Array = [
		[Vector3(road_side * hx, 0.0, 0.0), length, true, true],
		[Vector3(-road_side * hx, 0.0, 0.0), length, true, false],
		[Vector3(0.0, 0.0, hz), wid, false, false],
		[Vector3(0.0, 0.0, -hz), wid, false, false],
	]
	for w: Array in walls:
		_hoarding(st, body, o, yaw, w[0] as Vector3, float(w[1]), bool(w[2]), bool(w[3]))
	# Gate: a red/white boom across the opening and a guard booth.
	var gx: float = road_side * (hx + 0.4)
	_obox(st, o, yaw, Vector3(gx, 0.5, -GATE_W * 0.5), Vector3(0.25, 1.0, 0.25), DARK)
	for k: int in 8:
		_obox(st, o, yaw, Vector3(gx, 1.0, -GATE_W * 0.5 + 0.5 + float(k) * 0.9), Vector3(0.1, 0.1, 0.9), RED if k % 2 == 0 else WHITE)
	_obox(st, o, yaw, Vector3(road_side * (hx - 1.4), 1.2, -GATE_W * 0.5 - 2.2), Vector3(1.6, 2.4, 1.6), WHITE)
	_obox(st, o, yaw, Vector3(road_side * (hx - 1.4), 2.45, -GATE_W * 0.5 - 2.2), Vector3(1.9, 0.1, 1.9), BLUE)
	# Site cabins: two stacked portacabins at the far end.
	for lvl: int in 2:
		var y: float = 1.3 + float(lvl) * 2.6
		_obox(st, o, yaw, Vector3(road_side * (hx - 2.0), y, hz - 5.5), Vector3(2.6, 2.5, 6.0), WHITE)
		_obox(st, o, yaw, Vector3(road_side * (hx - 2.0), y + 0.55, hz - 5.5), Vector3(2.62, 0.35, 6.02), BLUE)
	_obox(st, o, yaw, Vector3(road_side * (hx - 3.4), 3.9, hz - 5.5), Vector3(0.3, 0.1, 6.0), STEEL) # walkway
	_solid(body, o, yaw, Vector3(road_side * (hx - 2.0), 2.6, hz - 5.5), Vector3(2.6, 5.2, 6.0))
	# Crawler crane beside the box, boom raised over it.
	var cr: Vector3 = Vector3(-road_side * 1.5 + road_side * (bx + 3.4), 0.0, -bz * 0.4)
	for sx: float in [-1.0, 1.0]:
		_obox(st, o, yaw, cr + Vector3(sx * 1.6, 0.55, 0.0), Vector3(0.9, 1.1, 6.4), DARK)
	_obox(st, o, yaw, cr + Vector3(0.0, 1.9, 0.6), Vector3(3.6, 1.6, 4.4), YELLOW)
	_obox(st, o, yaw, cr + Vector3(road_side * 1.2, 3.1, 1.8), Vector3(1.2, 1.4, 1.4), YELLOW.darkened(0.15))
	_obox(st, o, yaw, cr + Vector3(0.0, 2.2, -1.9), Vector3(3.2, 1.8, 1.2), DARK) # counterweight
	var boom_len: float = 26.0
	var boom_pitch: float = deg_to_rad(58.0)
	var boom_dir: Vector3 = Vector3(-road_side * cos(boom_pitch), sin(boom_pitch), 0.0)
	var boom_base: Vector3 = cr + Vector3(0.0, 2.8, 1.6)
	var boom_basis: Basis = Basis(Vector3.BACK, -road_side * (PI * 0.5 - boom_pitch))
	for sz: float in [-0.45, 0.45]:
		_obox(st, o, yaw, boom_base + boom_dir * boom_len * 0.5 + Vector3(0.0, 0.0, sz), Vector3(0.18, boom_len, 0.18), YELLOW, boom_basis)
	for k: int in 12:
		var p: Vector3 = boom_base + boom_dir * (1.0 + float(k) * 2.1)
		_obox(st, o, yaw, p, Vector3(0.1, 0.1, 0.9), YELLOW.darkened(0.2), boom_basis)
	var tip: Vector3 = boom_base + boom_dir * boom_len
	_obox(st, o, yaw, Vector3(tip.x, tip.y * 0.5 + 2.5, tip.z), Vector3(0.05, tip.y - 5.0, 0.05), DARK) # hoist rope
	_obox(st, o, yaw, Vector3(tip.x, 4.6, tip.z), Vector3(0.5, 0.8, 0.4), RED) # hook block
	_solid(body, o, yaw, cr + Vector3(0.0, 1.5, 0.0), Vector3(4.2, 3.0, 6.4))
	# Piling rig on the other side of the box: tracks, cab, tall mast.
	var pr: Vector3 = Vector3(-road_side * 1.5 - road_side * (bx - 2.5), 0.0, bz * 0.45)
	_obox(st, o, yaw, pr + Vector3(0.0, 0.6, 0.0), Vector3(3.4, 1.2, 5.2), DARK)
	_obox(st, o, yaw, pr + Vector3(0.0, 2.0, -0.6), Vector3(2.8, 1.6, 3.2), YELLOW)
	_obox(st, o, yaw, pr + Vector3(0.0, 11.0, 1.6), Vector3(0.7, 18.0, 0.7), YELLOW)
	_obox(st, o, yaw, pr + Vector3(0.0, 9.0, 2.1), Vector3(0.25, 15.0, 0.25), STEEL) # kelly bar
	_obox(st, o, yaw, pr + Vector3(0.0, 1.2, 2.3), Vector3(1.2, 1.4, 1.2), DARK) # auger
	_solid(body, o, yaw, pr + Vector3(0.0, 1.5, 0.0), Vector3(3.4, 3.0, 5.2))
	# Rebar cages on timber sleepers.
	for k: int in 3:
		var rp2: Vector3 = Vector3(-road_side * (hx - 3.0), 0.0, -hz + 14.0 + float(k) * 1.6)
		_obox(st, o, yaw, rp2 + Vector3(0.0, 0.12, 0.0), Vector3(9.0, 0.24, 0.3), RUST.darkened(0.4))
		_obox(st, o, yaw, rp2 + Vector3(0.0, 0.85, 0.0), Vector3(10.0, 1.1, 1.1), RUST)
	# Floodlight mast at the gate corner.
	var fl: Vector3 = Vector3(road_side * (hx - 1.0), 0.0, hz - 1.0)
	_obox(st, o, yaw, fl + Vector3(0.0, 5.5, 0.0), Vector3(0.22, 11.0, 0.22), STEEL)
	_obox(st, o, yaw, fl + Vector3(0.0, 11.2, 0.0), Vector3(1.6, 0.7, 0.3), WHITE)

## One hoarding wall: blue sheet panels, a white top band with a green stripe, steel posts.
## The gate wall leaves GATE_W open, centred a little towards -Z.
func _hoarding(st: SurfaceTool, body: StaticBody3D, o: Vector3, yaw: float, centre: Vector3, span: float, along_z: bool, gate: bool) -> void:
	var panels: int = maxi(1, roundi(span / PANEL_W))
	var w: float = span / float(panels)
	var solid_from: float = -span * 0.5
	for k: int in panels:
		var t: float = -span * 0.5 + w * (float(k) + 0.5)
		if gate and t > -GATE_W and t < 0.0:
			# Gate opening: close off the solid run before it.
			if t - w * 0.5 > solid_from + 0.1:
				_wall_solid(body, o, yaw, centre, along_z, solid_from, t - w * 0.5)
			solid_from = t + w * 0.5
			continue
		var p: Vector3 = centre + (Vector3(0.0, 0.0, t) if along_z else Vector3(t, 0.0, 0.0))
		var size_low: Vector3 = Vector3(0.06, 1.85, w) if along_z else Vector3(w, 1.85, 0.06)
		var size_top: Vector3 = Vector3(0.06, 0.62, w) if along_z else Vector3(w, 0.62, 0.06)
		var size_stripe: Vector3 = Vector3(0.08, 0.16, w) if along_z else Vector3(w, 0.16, 0.08)
		_obox(st, o, yaw, p + Vector3(0.0, 0.925, 0.0), size_low, BLUE)
		_obox(st, o, yaw, p + Vector3(0.0, 2.16, 0.0), size_top, WHITE)
		_obox(st, o, yaw, p + Vector3(0.0, 2.0, 0.0), size_stripe, GREEN)
		var post: Vector3 = p + (Vector3(0.0, 0.0, -w * 0.5) if along_z else Vector3(-w * 0.5, 0.0, 0.0))
		_obox(st, o, yaw, post + Vector3(0.0, HOARD_H * 0.5, 0.0), Vector3(0.1, HOARD_H, 0.1), STEEL)
	if span * 0.5 > solid_from + 0.1:
		_wall_solid(body, o, yaw, centre, along_z, solid_from, span * 0.5)

func _wall_solid(body: StaticBody3D, o: Vector3, yaw: float, centre: Vector3, along_z: bool, from_t: float, to_t: float) -> void:
	var mid: float = (from_t + to_t) * 0.5
	var run: float = to_t - from_t
	var p: Vector3 = centre + (Vector3(0.0, HOARD_H * 0.5, mid) if along_z else Vector3(mid, HOARD_H * 0.5, 0.0))
	_solid(body, o, yaw, p, Vector3(0.3, HOARD_H, run) if along_z else Vector3(run, HOARD_H, 0.3))

# --- closed-road barrier rows -------------------------------------------------------------------

## Water-filled plastic barriers (alternating red and white) across the closed road, an orange
## blinker on every other one. Row faces back along `yaw` towards the open junction.
func _build_row(st: SurfaceTool, body: StaticBody3D, row: Dictionary) -> void:
	var c: Vector2 = _v2(row["c"])
	var yaw: float = float(row["yaw"])
	var width: float = float(row["width"])
	var o: Vector3 = Vector3(c.x, _ground_y(c), c.y)
	var units: int = maxi(2, ceili(width / 1.25))
	var unit_w: float = width / float(units)
	for k: int in units:
		var x: float = -width * 0.5 + unit_w * (float(k) + 0.5)
		var col: Color = RED if k % 2 == 0 else WHITE
		_obox(st, o, yaw, Vector3(x, 0.3, 0.0), Vector3(unit_w - 0.04, 0.6, 0.55), col)
		_obox(st, o, yaw, Vector3(x, 0.72, 0.0), Vector3(unit_w - 0.12, 0.24, 0.32), col)
		_obox(st, o, yaw, Vector3(x, 0.86, 0.0), Vector3(0.18, 0.06, 0.18), DARK) # filler cap
		if k % 2 == 1:
			_obox(st, o, yaw, Vector3(x, 1.0, 0.0), Vector3(0.16, 0.2, 0.08), ORANGE)
	_solid(body, o, yaw, Vector3(0.0, 0.6, 0.0), Vector3(width, 1.2, 0.6))

# --- boards ---------------------------------------------------------------------------------------

## "closed": white plate, red border, on two legs. "diversion": yellow plate with a black arrow.
## "metro": a big panel on the hoarding. Local +Z (the readable face) turns to `yaw`.
func _build_board(st: SurfaceTool, body: StaticBody3D, board: Dictionary) -> void:
	var c: Vector2 = _v2(board["c"])
	var yaw: float = float(board["yaw"])
	var kind: String = str(board["kind"])
	var o: Vector3 = Vector3(c.x, _ground_y(c), c.y)
	var holder: Node3D = Node3D.new()
	holder.name = "Board_%s_%d" % [kind, board_count]
	holder.position = o
	holder.rotation.y = yaw
	add_child(holder)
	match kind:
		"closed":
			for sx: float in [-0.7, 0.7]:
				_obox(st, o, yaw, Vector3(sx, 0.8, 0.0), Vector3(0.07, 1.6, 0.07), STEEL)
			_obox(st, o, yaw, Vector3(0.0, 1.95, 0.0), Vector3(1.9, 1.15, 0.05), RED)
			_obox(st, o, yaw, Vector3(0.0, 1.95, 0.01), Vector3(1.72, 0.97, 0.05), WHITE)
			_solid(body, o, yaw, Vector3(0.0, 1.2, 0.0), Vector3(1.6, 2.4, 0.2))
			holder.add_child(_label("ROAD CLOSED", Vector3(0.0, 2.2, 0.045), 48, Color(0.75, 0.05, 0.05), 1.55))
			holder.add_child(_label("சாலை மூடப்பட்டுள்ளது", Vector3(0.0, 1.78, 0.045), 40, DARK, 1.5))
		"diversion":
			for sx: float in [-0.8, 0.8]:
				_obox(st, o, yaw, Vector3(sx, 1.0, 0.0), Vector3(0.08, 2.0, 0.08), STEEL)
			_obox(st, o, yaw, Vector3(0.0, 2.4, 0.0), Vector3(2.2, 1.5, 0.05), DARK)
			_obox(st, o, yaw, Vector3(0.0, 2.4, 0.01), Vector3(2.06, 1.36, 0.05), YELLOW)
			# Arrow pointing up: "keep going straight", the closed turn is no way through.
			_obox(st, o, yaw, Vector3(0.75, 2.25, 0.04), Vector3(0.12, 0.8, 0.02), DARK)
			_obox(st, o, yaw, Vector3(0.75, 2.62, 0.04), Vector3(0.36, 0.36, 0.02), DARK, Basis(Vector3.BACK, PI * 0.25))
			_solid(body, o, yaw, Vector3(0.0, 1.5, 0.0), Vector3(1.8, 3.0, 0.2))
			holder.add_child(_label("TAKE\nDIVERSION", Vector3(-0.25, 2.62, 0.045), 48, DARK, 1.35))
			holder.add_child(_label("மாற்றுப் பாதை", Vector3(-0.25, 2.0, 0.045), 40, DARK, 1.35))
		"metro":
			_obox(st, o, yaw, Vector3(0.0, 1.55, 0.0), Vector3(7.0, 1.6, 0.05), WHITE)
			_obox(st, o, yaw, Vector3(0.0, 0.85, 0.01), Vector3(7.0, 0.22, 0.05), GREEN)
			holder.add_child(_label("METRO RAIL WORK IN PROGRESS", Vector3(0.0, 1.98, 0.045), 56, BLUE, 6.4))
			holder.add_child(_label("மெட்ரோ ரயில் பணி நடைபெறுகிறது", Vector3(0.0, 1.5, 0.045), 48, BLUE, 5.6))
			holder.add_child(_label("Inconvenience regretted · சிரமத்திற்கு வருந்துகிறோம்", Vector3(0.0, 1.07, 0.045), 36, DARK, 5.0))

## Board text, scaled to fill `max_w` metres (never larger than 1 cm per pixel).
func _label(text: String, pos: Vector3, size: int, colour: Color, max_w: float) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	var font: Font = l.font if l.font != null else ThemeDB.fallback_font
	var px: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	l.pixel_size = minf(0.01, max_w / maxf(px.x, 1.0))
	l.outline_size = 0
	l.modulate = colour
	l.shaded = false
	l.double_sided = false
	l.visibility_range_end = BOARD_VISIBLE_M
	return l
