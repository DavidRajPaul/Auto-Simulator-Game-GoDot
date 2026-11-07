class_name CartSigns
extends Node3D
## Shop names on the push-cart boards (data/world/carts.json, tools/osm/build_beach_carts.py).
## The carts themselves are merged into the chunk meshes; only the nearest POOL_SIZE carts that
## carry a board get a Label3D, so the names cost a handful of draw calls near the player only.

const DATA_FILE: String = "res://data/world/carts.json"
const POOL_SIZE: int = 8
const SHOW_M: float = 45.0
const CELL_M: float = 50.0
const REFRESH_S: float = 0.4

var _carts: Array = []
var _grid: Dictionary = {}
var _labels: Array[Dictionary] = [] # per variant: [local pos, max width, colour] or []
var _pool: Array[Label3D] = []
var _assigned: PackedInt32Array = PackedInt32Array()
var _player: Vector3 = Vector3.INF
var _clock: float = 0.0

func _ready() -> void:
	if not FileAccess.file_exists(DATA_FILE):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
	if not (parsed is Array):
		return
	_carts = parsed as Array
	for i: int in _carts.size():
		var c: Array = _carts[i]
		var k: Vector2i = Vector2i(floori(float(c[0]) / CELL_M), floori(float(c[1]) / CELL_M))
		var arr: PackedInt32Array = _grid.get(k, PackedInt32Array())
		arr.append(i)
		_grid[k] = arr
	for v: Dictionary in BeachCartKit.arrays():
		_labels.append({"label": v["label"]})
	for i: int in POOL_SIZE:
		var l: Label3D = Label3D.new()
		l.name = "CartName_%d" % i
		l.font_size = 64
		l.outline_size = 10
		l.outline_modulate = Color(0, 0, 0, 0.35)
		l.shaded = false
		l.double_sided = false
		l.visible = false
		l.visibility_range_end = SHOW_M + 5.0
		add_child(l)
		_pool.append(l)
		_assigned.append(-1)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _process(delta: float) -> void:
	_clock += delta
	if _clock < REFRESH_S or _player == Vector3.INF or _carts.is_empty():
		return
	_clock = 0.0
	refresh(_player)

## Put names on the nearest carts with boards (public for tests).
func refresh(origin: Vector3) -> void:
	var near: Array = []
	var ck: Vector2i = Vector2i(floori(origin.x / CELL_M), floori(origin.z / CELL_M))
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			for i: int in _grid.get(ck + Vector2i(dx, dz), PackedInt32Array()):
				var c: Array = _carts[i]
				var label: Array = _labels[int(c[3])]["label"] if int(c[3]) < _labels.size() else []
				if label.is_empty():
					continue
				var d: float = Vector2(float(c[0]) - origin.x, float(c[1]) - origin.z).length()
				if d <= SHOW_M:
					near.append([d, i])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k: int in _pool.size():
		var l: Label3D = _pool[k]
		if k >= near.size():
			l.visible = false
			_assigned[k] = -1
			continue
		var idx: int = int(near[k][1])
		l.visible = true
		if _assigned[k] == idx:
			continue
		_assigned[k] = idx
		_place(l, _carts[idx])

func _place(l: Label3D, c: Array) -> void:
	var label: Array = _labels[int(c[3])]["label"]
	var local: Vector3 = label[0]
	var max_w: float = float(label[1])
	l.text = BeachCartKit.shop_name(int(c[4]))
	l.modulate = label[2]
	var font: Font = ThemeDB.fallback_font
	var px: float = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.font_size).x
	l.pixel_size = minf(0.0045, max_w / maxf(px, 1.0))
	var yaw: float = float(c[2])
	var basis: Basis = Basis(Vector3.UP, yaw)
	l.global_transform = Transform3D(basis, Vector3(float(c[0]), float(c[5]), float(c[1])) + basis * local)

func shown_count() -> int:
	var n: int = 0
	for l: Label3D in _pool:
		n += 1 if l.visible else 0
	return n
