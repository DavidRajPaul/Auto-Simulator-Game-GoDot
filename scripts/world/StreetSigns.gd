class_name StreetSigns
extends Node3D
## Greater Chennai Corporation street-name boards at real junctions, with the real OSM names
## (Tamil on top, English below, white on a blue plate, two polished chrome posts).
##
## Spots come from data/world/street_signs.json (tools/osm/build_street_signs.py), which places
## every board on the footpath against the REAL osm2streets road surface — never in a lane.
## Pooled: MAX_SIGNS boards built once and re-assigned to the nearest spots as the player drives
## (no instantiate/free while driving). Per board: 1 mesh (2 surfaces: painted plate + chrome) +
## 2 Label3D, culled past VISIBLE_M, inside the 150-draw-call budget.

const SPOTS_FILE: String = "res://data/world/street_signs.json"
const MAX_SIGNS: int = 8
const SEARCH_M: float = 110.0
const VISIBLE_M: float = 95.0
const UPDATE_S: float = 0.75
const CELL_M: float = 60.0
const PLATE: Vector3 = Vector3(2.0, 0.66, 0.04)
const PLATE_HEIGHT_M: float = 2.55
const POST_GAP_M: float = 1.62
const POST_R: float = 0.035
const BLUE: Color = Color(0.03, 0.2, 0.58)
const LABEL_MAX_WIDTH_M: float = 1.84
const LABEL_MAX_HEIGHT_M: float = 0.23
const BEND_ANGLE_RAD: float = 0.19
const REPAIR_S: float = 35.0
const IMPACT_COOLDOWN_S: float = 0.8
var _damage: Dictionary = {} # spot key -> {hits, repair_at}
var _clock: float = 0.0

var _player: Vector3 = Vector3.ZERO
var _pool: Array[Node3D] = []
var _assigned: Dictionary = {} # spot index -> Node3D
var _spots: Array = [] # [x, z, yaw, name, name_ta]
var _grid: Dictionary = {} # Vector2i -> PackedInt32Array(spot indices)
var _timer: float = UPDATE_S

func _ready() -> void:
	_load_spots()
	var mesh: ArrayMesh = _sign_mesh()
	for i: int in MAX_SIGNS:
		var n: Node3D = Node3D.new()
		n.name = "Sign_%d" % i
		n.visible = false
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_end = VISIBLE_M
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		n.add_child(_label("Tamil", PLATE_HEIGHT_M + 0.14, 54))
		n.add_child(_label("English", PLATE_HEIGHT_M - 0.14, 46))
		# Solid posts and plate: the auto can no longer pass through the board.
		var solid: StaticBody3D = StaticBody3D.new()
		solid.name = "Solid"
		solid.collision_layer = 1
		solid.collision_mask = 0
		var plate_hit: CollisionShape3D = CollisionShape3D.new()
		var plate_box: BoxShape3D = BoxShape3D.new()
		plate_box.size = Vector3(PLATE.x, PLATE.y, 0.12)
		plate_hit.shape = plate_box
		plate_hit.position.y = PLATE_HEIGHT_M
		solid.add_child(plate_hit)
		for side: float in [-1.0, 1.0]:
			var post_hit: CollisionShape3D = CollisionShape3D.new()
			var post_shape: CylinderShape3D = CylinderShape3D.new()
			post_shape.radius = 0.065
			post_shape.height = PLATE_HEIGHT_M + 0.4
			post_hit.shape = post_shape
			post_hit.position = Vector3(side * POST_GAP_M * 0.5, post_shape.height * 0.5, 0.035)
			solid.add_child(post_hit)
		n.add_child(solid)
		var trigger: Area3D = Area3D.new()
		trigger.name = "ImpactArea"
		trigger.collision_layer = 0
		trigger.collision_mask = 1
		trigger.monitoring = true
		var trigger_shape: CollisionShape3D = CollisionShape3D.new()
		var trigger_box: BoxShape3D = BoxShape3D.new()
		trigger_box.size = Vector3(PLATE.x + 0.4, PLATE_HEIGHT_M + 0.7, 0.7)
		trigger_shape.shape = trigger_box
		trigger_shape.position.y = (PLATE_HEIGHT_M + 0.4) * 0.5
		trigger.add_child(trigger_shape)
		n.add_child(trigger)
		trigger.body_entered.connect(func(body: Node3D) -> void: _on_impact(n, body))

		add_child(n)
		_pool.append(n)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _load_spots() -> void:
	var f: FileAccess = FileAccess.open(SPOTS_FILE, FileAccess.READ)
	if f == null:
		push_warning("StreetSigns: %s missing — run tools/osm/build_street_signs.py" % SPOTS_FILE)
		return
	_spots = JSON.parse_string(f.get_as_text()) as Array
	for i: int in _spots.size():
		var s: Array = _spots[i]
		var k: Vector2i = Vector2i(floori(float(s[0]) / CELL_M), floori(float(s[1]) / CELL_M))
		var arr: PackedInt32Array = _grid.get(k, PackedInt32Array())
		arr.append(i)
		_grid[k] = arr

func _label(label_name: String, y: float, font_size: int) -> Label3D:
	var l: Label3D = Label3D.new()
	l.name = label_name
	# Both faces of the plate carry the name (boards are read from either direction).
	l.position = Vector3(0.0, y, -PLATE.z * 0.5 - 0.006)
	l.rotation.y = PI
	l.pixel_size = 0.0042
	l.font_size = font_size
	l.outline_size = 0
	l.modulate = Color.WHITE
	l.double_sided = true
	l.width = 480.0
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.visibility_range_end = VISIBLE_M * 0.8
	l.shaded = false
	return l

func _process(delta: float) -> void:
	_clock += delta
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
		keep[c["key"]] = c
	for key: Variant in _assigned.keys():
		if not keep.has(key):
			(_assigned[key] as Node3D).visible = false
			_assigned.erase(key)
	for c: Dictionary in wanted:
		if _assigned.has(c["key"]):
			continue
		if _damage.has(c["key"]):
			if _clock < float(_damage[c["key"]].get("repair_at", 0.0)):
				continue
			_damage.erase(c["key"])
		var n: Node3D = _free_board()
		if n == null:
			break
		_place(n, c)
		_assigned[c["key"]] = n

func _free_board() -> Node3D:
	for n: Node3D in _pool:
		if not n.visible:
			return n
	return null

## Board spots near `p`, nearest first: {key, pos, yaw, name, ta, dist}.
func candidates(p: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r: int = ceili(SEARCH_M / CELL_M)
	var c: Vector2i = Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))
	for dx: int in range(-r, r + 1):
		for dz: int in range(-r, r + 1):
			for i: int in _grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var s: Array = _spots[i]
				var d: float = Vector2(float(s[0]) - p.x, float(s[1]) - p.z).length()
				if d <= SEARCH_M:
					out.append({"key": i, "pos": Vector3(float(s[0]), 0.0, float(s[1])), "yaw": float(s[2]),
						"name": str(s[3]), "ta": str(s[4]), "dist": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	if out.size() > MAX_SIGNS:
		out.resize(MAX_SIGNS)
	return out

func _place(n: Node3D, c: Dictionary) -> void:
	n.global_position = c["pos"]
	n.rotation = Vector3(0.0, float(c["yaw"]), 0.0)
	var ta: Label3D = n.get_node("Tamil") as Label3D
	var en: Label3D = n.get_node("English") as Label3D
	n.set_meta("spot_key", int(c["key"]))
	n.set_meta("last_hit", -10.0)
	var solid: StaticBody3D = n.get_node("Solid") as StaticBody3D
	solid.process_mode = Node.PROCESS_MODE_INHERIT
	n.get_node("ImpactArea").process_mode = Node.PROCESS_MODE_INHERIT
	n.rotation.z = 0.0
	var english: String = _short(str(c["name"])).to_upper()
	ta.text = str(c["ta"])
	en.text = english
	en.position.y = PLATE_HEIGHT_M - 0.14 if ta.text != "" else PLATE_HEIGHT_M - 0.02
	en.font_size = 46 if ta.text != "" else 56
	_fit_label(en, LABEL_MAX_WIDTH_M, LABEL_MAX_HEIGHT_M)
	_fit_label(ta, LABEL_MAX_WIDTH_M, LABEL_MAX_HEIGHT_M)
	n.visible = true

## Measure rendered glyphs, not character count (Tamil and English differ greatly).
func _fit_label(l: Label3D, max_width: float, max_height: float) -> void:
	l.pixel_size = 0.0042
	if l.text.is_empty():
		return
	var font: Font = l.font if l.font != null else ThemeDB.fallback_font
	var dimensions: Vector2 = font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.font_size)
	var width_m: float = maxf(dimensions.x * l.pixel_size, 0.001)
	var height_m: float = maxf(dimensions.y * l.pixel_size, 0.001)
	l.pixel_size *= minf(1.0, minf(max_width / width_m, max_height / height_m))

func _on_impact(n: Node3D, body: Node3D) -> void:
	if not body.is_in_group("player_auto") or not n.visible:
		return
	if _clock - float(n.get_meta("last_hit", -10.0)) < IMPACT_COOLDOWN_S:
		return
	n.set_meta("last_hit", _clock)
	var key: int = int(n.get_meta("spot_key", -1))
	if key < 0:
		return
	var state: Dictionary = _damage.get(key, {"hits": 0, "repair_at": 0.0})
	state["hits"] = int(state["hits"]) + 1
	if int(state["hits"]) == 1:
		# First strike: lean the board and posts while keeping physical collision.
		n.rotation.z = BEND_ANGLE_RAD
	else:
		# Second strike: detach visually, fall, then rebuild after a cooldown.
		state["repair_at"] = _clock + REPAIR_S
		var solid: StaticBody3D = n.get_node("Solid") as StaticBody3D
		solid.process_mode = Node.PROCESS_MODE_DISABLED
		n.get_node("ImpactArea").process_mode = Node.PROCESS_MODE_DISABLED
		var tween: Tween = create_tween()
		tween.tween_property(n, "rotation:z", 1.45, 0.55)
		tween.parallel().tween_property(n, "position:y", -1.2, 0.55)
		tween.tween_callback(func() -> void:
			if is_instance_valid(n):
				n.visible = false
				_assigned.erase(key))
	_damage[key] = state

## Chennai boards abbreviate: "Road" → "Rd", "Street" → "St", "Salai" stays.
static func _short(s: String) -> String:
	return s.replace(" Road", " Rd").replace(" Street", " St").replace(" Avenue", " Ave").replace("Doctor ", "Dr ")

static func _sign_mesh() -> ArrayMesh:
	# Surface 0: the painted plate (blue face, white rim + white back frame).
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.box(st, Vector3(0, PLATE_HEIGHT_M, 0), PLATE, BLUE)
	MeshKit.box(st, Vector3(0, PLATE_HEIGHT_M, 0.0), PLATE + Vector3(0.05, 0.05, -0.012), Color(0.95, 0.95, 0.95))
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.45
	var mesh: ArrayMesh = MeshKit.finish(st, paint)
	# Surface 1: polished chrome posts with end caps and clamp bands.
	var ch: SurfaceTool = MeshKit.begin()
	var silver: Color = Color(0.9, 0.91, 0.94)
	var top_y: float = PLATE_HEIGHT_M + PLATE.y * 0.5 + 0.06
	for side: float in [-1.0, 1.0]:
		var x: float = side * POST_GAP_M * 0.5
		MeshKit.tube(ch, Vector3(x, 0.0, 0.035), Vector3(x, top_y, 0.035), POST_R, silver, 10)
		MeshKit.disc(ch, Vector3(x, top_y, 0.035), Vector3.UP, POST_R * 1.25, silver, 10)
		for band_y: float in [PLATE_HEIGHT_M - PLATE.y * 0.35, PLATE_HEIGHT_M + PLATE.y * 0.35]:
			MeshKit.tube(ch, Vector3(x, band_y - 0.02, 0.035), Vector3(x, band_y + 0.02, 0.035), POST_R * 1.35, silver, 10)
		MeshKit.tube(ch, Vector3(x, 0.0, 0.035), Vector3(x, 0.05, 0.035), POST_R * 2.2, Color(0.55, 0.55, 0.57), 10) # base flange
	var chrome: StandardMaterial3D = StandardMaterial3D.new()
	chrome.vertex_color_use_as_albedo = true
	# Bright, half-metallic: a fully metallic surface turns black wherever there is no sky
	# reflection to show (compatibility renderer, budget GPUs). This reads as polished steel
	# everywhere, with a sharp highlight from rim lighting.
	chrome.metallic = 0.45
	chrome.metallic_specular = 0.9
	chrome.roughness = 0.22
	chrome.rim_enabled = true
	chrome.rim = 0.6
	chrome.rim_tint = 0.2
	MeshKit.finish(ch, chrome, mesh)
	return mesh
