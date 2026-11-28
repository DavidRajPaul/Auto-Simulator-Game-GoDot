class_name QuestPlaceKit
extends RefCounted
## Simple, recognisable Chennai places for quest stops, each one vertex-painted mesh (1 draw call).
## +Z faces the road. z = -1.4 is the wall of the real building behind the origin, and nothing
## standing reaches past z = 0.7, because the kerb in front is often only a few metres wide.
const CREAM: Color = Color(0.93, 0.88, 0.76)
const WOOD: Color = Color(0.36, 0.22, 0.12)
const DARK: Color = Color(0.1, 0.08, 0.07)
const STEEL: Color = Color(0.42, 0.44, 0.47)
const GOLD: Color = Color(0.86, 0.66, 0.22)
const BRASS: Color = Color(0.72, 0.54, 0.2)
const WHITE: Color = Color(0.94, 0.94, 0.92)
const LEAF: Color = Color(0.2, 0.52, 0.22)
const SIGN_Y: float = 3.62
## Shop fronts: [wall, sign board, awning A, awning B].
const SHOPS: Dictionary = {
	"music": [Color(0.74, 0.86, 0.82), Color(0.42, 0.08, 0.1), Color(0.75, 0.12, 0.14), Color(0.96, 0.8, 0.3)],
	"tailor": [Color(0.95, 0.8, 0.66), Color(0.12, 0.25, 0.5), Color(0.15, 0.35, 0.7), WHITE],
	"books": [Color(0.8, 0.87, 0.72), Color(0.1, 0.32, 0.2), Color(0.12, 0.45, 0.28), WHITE],
	"tea": [Color(0.96, 0.84, 0.5), Color(0.4, 0.14, 0.06), Color(0.8, 0.3, 0.1), WHITE],
	"lamps": [Color(0.98, 0.78, 0.5), Color(0.5, 0.15, 0.04), Color(0.9, 0.45, 0.08), Color(0.98, 0.85, 0.3)],
	"print": [Color(0.8, 0.84, 0.92), Color(0.08, 0.14, 0.34), Color(0.1, 0.2, 0.5), Color(0.9, 0.9, 0.95)],
	"sports": [Color(0.78, 0.9, 0.78), Color(0.05, 0.3, 0.14), Color(0.06, 0.5, 0.26), Color(0.98, 0.85, 0.2)],
	"phones": [Color(0.86, 0.82, 0.94), Color(0.25, 0.08, 0.4), Color(0.45, 0.15, 0.65), WHITE],
	"glass": [Color(0.8, 0.92, 0.94), Color(0.05, 0.25, 0.32), Color(0.1, 0.45, 0.55), WHITE],
	"flowers": [Color(0.96, 0.82, 0.86), Color(0.5, 0.08, 0.3), Color(0.85, 0.2, 0.5), Color(0.98, 0.95, 0.85)],
	"office": [Color(0.86, 0.84, 0.8), Color(0.14, 0.2, 0.3), Color(0.3, 0.36, 0.44), Color(0.5, 0.55, 0.6)],
	"store": [Color(0.9, 0.76, 0.56), Color(0.32, 0.16, 0.06), Color(0.6, 0.32, 0.12), Color(0.85, 0.7, 0.45)],
	# Named shops with a lived-in, tube-lit inside (QuestPlaces paints their own board on them).
	"coffee_bar": [Color(0.96, 0.88, 0.62), Color(0.35, 0.16, 0.07), Color(0.45, 0.2, 0.08), Color(0.96, 0.86, 0.6)],
	"tailors": [Color(0.6, 0.76, 0.86), Color(0.11, 0.25, 0.54), Color(0.13, 0.3, 0.66), WHITE],
	"bookhouse": [Color(0.84, 0.9, 0.78), Color(0.12, 0.36, 0.21), Color(0.14, 0.42, 0.25), Color(0.97, 0.93, 0.78)],
	"tea_kadai": [Color(0.98, 0.86, 0.42), Color(0.72, 0.2, 0.11), Color(0.8, 0.18, 0.1), Color(0.99, 0.84, 0.25)],
}
## Shops drawn with an open, lit inside instead of the dark one.
const LIT_SHOPS: PackedStringArray = ["coffee_bar", "tailors", "bookhouse", "tea_kadai"]
const TILE: Color = Color(0.82, 0.78, 0.7)
const TUBE: Color = Color(1.0, 1.0, 0.97)
const STEEL_TOP: Color = Color(0.78, 0.8, 0.82)
const GARLAND: Array[Color] = [Color(0.98, 0.96, 0.86), Color(0.96, 0.55, 0.1), Color(0.9, 0.2, 0.3), Color(0.98, 0.85, 0.2)]

static var _cache: Dictionary = {}

static func mesh(kind: String) -> ArrayMesh:
	if not _cache.has(kind):
		_cache[kind] = _build(kind)
	return _cache[kind]

## True where a name can be painted on the board at SIGN_Y.
static func has_board(kind: String) -> bool:
	return SHOPS.has(kind) or kind in ["hall", "clinic", "school"]

static func _build(kind: String) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	if SHOPS.has(kind):
		if kind in LIT_SHOPS:
			_lit_inside(st, SHOPS[kind])
		_shop_front(st, SHOPS[kind], kind in LIT_SHOPS)
		match kind:
			"coffee_bar": _coffee_bar(st)
			"tailors": _tailors(st)
			"bookhouse": _bookhouse(st)
			"tea_kadai": _tea_kadai(st)
			"music": _music(st)
			"tailor": _tailor(st)
			"books": _books(st)
			"tea": _tea(st)
			"lamps": _lamps(st)
			"print": _print(st)
			"sports": _sports(st)
			"phones": _phones(st)
			"glass": _glass(st)
			"flowers": _hanging_garlands(st)
			"store": _sacks(st)
			_: _office(st)
	else:
		match kind:
			"hall": _hall(st)
			"stall": _stall(st)
			"house": _house(st)
			"gate": _gate(st)
			"school": _school(st)
			"clinic": _clinic(st)
			"tent": _tent(st)
			"power": _power_box(st)
			"auto": _stuck_auto(st)
			"photo": _board(st, Color(0.1, 0.35, 0.55))
			"warning": _board(st, Color(0.85, 0.65, 0.05))
			"closed": _barricade(st)
			_: _board(st, Color(0.16, 0.3, 0.2))
	return MeshKit.finish(st, LandmarkKit.material())

## Two piers, a dark interior, a half-rolled shutter, a painted board and a striped awning.
static func _shop_front(st: SurfaceTool, c: Array, lit: bool = false) -> void:
	var w: float = 6.8
	var wall: Color = c[0]
	if not lit:
		MeshKit.box(st, Vector3(0, 1.45, -1.32), Vector3(w, 2.9, 0.12), DARK.lightened(0.08)) # Interior.
	MeshKit.box(st, Vector3(-w * 0.5 + 0.3, 2.0, -0.9), Vector3(0.6, 4.0, 1.0), wall)
	MeshKit.box(st, Vector3(w * 0.5 - 0.3, 2.0, -0.9), Vector3(0.6, 4.0, 1.0), wall)
	MeshKit.box(st, Vector3(0, 0.1, -0.9), Vector3(w, 0.2, 1.0), Color(0.62, 0.6, 0.56)) # Step.
	MeshKit.box(st, Vector3(0, 3.0, -0.9), Vector3(w - 1.2, 0.3, 1.0), Color(0.75, 0.72, 0.66)) # Shutter box.
	MeshKit.box(st, Vector3(0, SIGN_Y, -0.36), Vector3(w + 0.1, 0.92, 0.12), c[1])
	MeshKit.box(st, Vector3(0, SIGN_Y + 0.5, -0.33), Vector3(w + 0.2, 0.07, 0.14), GOLD)
	MeshKit.box(st, Vector3(0, SIGN_Y - 0.5, -0.33), Vector3(w + 0.2, 0.07, 0.14), GOLD)
	var stripes: int = 8
	var tilt: Basis = Basis(Vector3.RIGHT, deg_to_rad(24.0))
	for i: int in stripes:
		var x: float = lerpf(-w * 0.5 + 0.42, w * 0.5 - 0.42, float(i) / float(stripes - 1))
		var colour: Color = c[2] if i % 2 == 0 else c[3]
		MeshKit.box(st, Vector3(x, 2.72, 0.02), Vector3((w - 0.05) / stripes, 0.05, 1.3), colour, tilt)
		MeshKit.box(st, Vector3(x, 2.33, 0.66), Vector3((w - 0.05) / stripes, 0.22, 0.04), colour) # Valance.

static func _shelf(st: SurfaceTool, y: float, x0: float = -2.6, x1: float = 2.6) -> void:
	MeshKit.box(st, Vector3((x0 + x1) * 0.5, y, -1.05), Vector3(x1 - x0, 0.06, 0.42), WOOD)

## Barrel around X from (position along X, radius) points; MeshKit takes them the other way round.
static func _lathe(st: SurfaceTool, at: Vector3, points: PackedVector2Array, segments: int, colour: Color) -> void:
	var swapped: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		swapped.append(Vector2(point.y, point.x))
	MeshKit.lathe_x(st, at, swapped, segments, colour)

## Mridangam lying on its side: a barrel with dark tuning skins and leather straps.
static func _mridangam(st: SurfaceTool, at: Vector3, colour: Color) -> void:
	var p: PackedVector2Array = PackedVector2Array([Vector2(-0.42, 0.0), Vector2(-0.42, 0.17), Vector2(-0.2, 0.25), Vector2(0.0, 0.27), Vector2(0.2, 0.24), Vector2(0.42, 0.15), Vector2(0.42, 0.0)])
	_lathe(st, at, p, 12, colour)
	MeshKit.disc(st, at + Vector3(0.425, 0, 0), Vector3.RIGHT, 0.13, DARK, 10)
	MeshKit.disc(st, at + Vector3(-0.425, 0, 0), Vector3.LEFT, 0.15, DARK, 10)
	for i: int in 5:
		MeshKit.box(st, at + Vector3(lerpf(-0.3, 0.3, i / 4.0), 0.26, 0.0), Vector3(0.02, 0.03, 0.42), Color(0.8, 0.7, 0.5))

## Veena laid along the wall: big gourd, long neck with frets, small gourd, curved peg-box.
static func _veena(st: SurfaceTool, at: Vector3) -> void:
	var gourd: PackedVector2Array = PackedVector2Array([Vector2(-0.32, 0.0), Vector2(-0.26, 0.17), Vector2(-0.08, 0.3), Vector2(0.14, 0.27), Vector2(0.3, 0.1), Vector2(0.32, 0.0)])
	_lathe(st, at, gourd, 12, Color(0.62, 0.3, 0.12))
	MeshKit.tube(st, at + Vector3(0.28, 0.02, 0), at + Vector3(1.75, 0.02, 0), 0.085, Color(0.48, 0.22, 0.09), 8)
	for i: int in 9:
		MeshKit.box(st, at + Vector3(0.45 + i * 0.13, 0.1, 0), Vector3(0.018, 0.02, 0.14), GOLD)
	var small: PackedVector2Array = PackedVector2Array([Vector2(-0.14, 0.0), Vector2(-0.1, 0.1), Vector2(0.06, 0.13), Vector2(0.14, 0.0)])
	_lathe(st, at + Vector3(1.28, -0.12, 0), small, 8, Color(0.66, 0.36, 0.14))
	MeshKit.tube(st, at + Vector3(1.75, 0.02, 0), at + Vector3(1.95, -0.1, 0), 0.05, GOLD, 6)

static func _tabla(st: SurfaceTool, at: Vector3) -> void:
	MeshKit.tube(st, at + Vector3(-0.13, 0, 0), at + Vector3(-0.13, 0.26, 0), 0.1, WOOD.lightened(0.15), 10)
	MeshKit.disc(st, at + Vector3(-0.13, 0.265, 0), Vector3.UP, 0.09, DARK, 10)
	MeshKit.tube(st, at + Vector3(0.13, 0, 0), at + Vector3(0.13, 0.22, 0), 0.13, BRASS, 10)
	MeshKit.disc(st, at + Vector3(0.13, 0.225, 0), Vector3.UP, 0.11, DARK, 10)

static func _harmonium(st: SurfaceTool, at: Vector3) -> void:
	MeshKit.box(st, at + Vector3(0, 0.1, 0), Vector3(0.62, 0.2, 0.32), WOOD)
	MeshKit.box(st, at + Vector3(0, 0.205, 0.08), Vector3(0.52, 0.015, 0.1), WHITE)
	for i: int in 9:
		MeshKit.box(st, at + Vector3(-0.2 + i * 0.05, 0.215, 0.06), Vector3(0.02, 0.012, 0.06), DARK)

static func _music(st: SurfaceTool) -> void:
	_shelf(st, 0.95)
	_shelf(st, 1.85)
	_veena(st, Vector3(-2.2, 2.32, -1.1))
	_mridangam(st, Vector3(-1.95, 1.26, -1.05), Color(0.5, 0.26, 0.12))
	_mridangam(st, Vector3(-0.95, 1.26, -1.05), Color(0.62, 0.33, 0.14))
	_tabla(st, Vector3(0.05, 0.98, -1.05))
	_harmonium(st, Vector3(0.85, 0.98, -1.05))
	_tabla(st, Vector3(1.75, 0.98, -1.05))
	# Nadaswaram: long black pipe with a brass bell, leaning at the side.
	MeshKit.tube(st, Vector3(2.45, 1.05, -1.0), Vector3(2.15, 2.65, -1.1), 0.035, DARK, 6)
	MeshKit.tube(st, Vector3(2.47, 0.96, -1.0), Vector3(2.45, 1.1, -1.0), 0.09, BRASS, 8)
	# Thalam cymbals and record sleeves on the top shelf.
	for i: int in 3:
		MeshKit.tube(st, Vector3(-2.3 + i * 0.32, 1.89, -1.05), Vector3(-2.3 + i * 0.32, 1.93, -1.05), 0.12, BRASS, 10)
	for i: int in 6:
		MeshKit.box(st, Vector3(0.5 + i * 0.32, 2.05, -1.12), Vector3(0.26, 0.34, 0.03), Color.from_hsv(0.08 + i * 0.13, 0.55, 0.8))
	_mridangam(st, Vector3(1.6, 0.55, -0.72), Color(0.5, 0.26, 0.12)) # On a stool by the door.
	MeshKit.box(st, Vector3(1.6, 0.14, -0.72), Vector3(0.95, 0.28, 0.5), WOOD)

static func _tailor(st: SurfaceTool) -> void:
	_shelf(st, 1.9)
	for i: int in 10:
		MeshKit.box(st, Vector3(-2.4 + i * 0.52, 2.15, -1.05), Vector3(0.44, 0.42, 0.3), Color.from_hsv(float(i) * 0.31, 0.6, 0.85))
	MeshKit.box(st, Vector3(-0.8, 0.75, -0.95), Vector3(1.0, 0.06, 0.5), WOOD) # Sewing table.
	MeshKit.box(st, Vector3(-0.8, 0.38, -0.95), Vector3(0.9, 0.7, 0.04), DARK)
	MeshKit.box(st, Vector3(-0.8, 0.92, -0.95), Vector3(0.42, 0.26, 0.14), DARK)
	MeshKit.tube(st, Vector3(1.6, 0.25, -0.9), Vector3(1.6, 1.2, -0.9), 0.17, Color(0.85, 0.72, 0.55), 8) # Dress form.
	MeshKit.tube(st, Vector3(1.6, 0.0, -0.9), Vector3(1.6, 0.3, -0.9), 0.03, WOOD, 6)

static func _books(st: SurfaceTool) -> void:
	for y: float in [0.8, 1.45, 2.1]:
		_shelf(st, y)
		for i: int in 34:
			var height: float = 0.32 + fmod(float(i) * 0.37, 0.18)
			MeshKit.box(st, Vector3(-2.5 + i * 0.15, y + 0.03 + height * 0.5, -1.05), Vector3(0.13, height, 0.3), Color.from_hsv(fmod(i * 0.17 + y, 1.0), 0.55, 0.75))

static func _tea(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 0.55, -0.72), Vector3(3.0, 1.1, 0.5), Color(0.72, 0.72, 0.74)) # Counter.
	MeshKit.tube(st, Vector3(-0.6, 1.1, -0.72), Vector3(-0.6, 1.72, -0.72), 0.2, Color(0.8, 0.72, 0.5), 10) # Brass urn.
	MeshKit.tube(st, Vector3(-0.6, 1.72, -0.72), Vector3(-0.6, 1.82, -0.72), 0.08, DARK, 8)
	for i: int in 6:
		MeshKit.tube(st, Vector3(0.2 + i * 0.2, 1.1, -0.72), Vector3(0.2 + i * 0.2, 1.22, -0.72), 0.04, Color(0.9, 0.92, 0.95), 6)
	for i: int in 5:
		MeshKit.box(st, Vector3(-2.2 + i * 1.1, 2.3, -1.1), Vector3(0.2, 0.34, 0.1), Color(0.9, 0.8, 0.4)) # Biscuit packets.

static func _lamps(st: SurfaceTool) -> void:
	for y: float in [0.9, 1.8]:
		_shelf(st, y)
		for i: int in 7:
			var at: Vector3 = Vector3(-2.3 + i * 0.77, y, -1.05)
			MeshKit.tube(st, at, at + Vector3(0, 0.05, 0), 0.13, BRASS, 8)
			MeshKit.tube(st, at + Vector3(0, 0.05, 0), at + Vector3(0, 0.46, 0), 0.03, BRASS, 6)
			MeshKit.tube(st, at + Vector3(0, 0.46, 0), at + Vector3(0, 0.52, 0), 0.11, GOLD, 8)

static func _print(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(-1.2, 0.55, -0.9), Vector3(1.1, 1.1, 0.7), Color(0.85, 0.85, 0.82)) # Copier.
	MeshKit.box(st, Vector3(-1.2, 1.15, -0.9), Vector3(1.0, 0.1, 0.6), DARK)
	MeshKit.box(st, Vector3(-0.55, 0.9, -0.9), Vector3(0.3, 0.03, 0.34), WHITE)
	_shelf(st, 1.6, 0.0, 2.6)
	for i: int in 6:
		MeshKit.box(st, Vector3(0.3 + i * 0.4, 1.74, -1.05), Vector3(0.3, 0.22, 0.26), Color(0.95, 0.95, 0.9))

static func _sports(st: SurfaceTool) -> void:
	for i: int in 7:
		var x: float = -2.3 + i * 0.3
		MeshKit.box(st, Vector3(x, 1.5, -1.15), Vector3(0.11, 0.8, 0.05), Color(0.85, 0.72, 0.48)) # Bats.
		MeshKit.tube(st, Vector3(x, 1.9, -1.15), Vector3(x, 2.25, -1.15), 0.022, DARK, 5)
	_shelf(st, 1.1, 0.0, 2.6)
	for i: int in 5:
		MeshKit.tube(st, Vector3(0.3 + i * 0.5, 1.13, -1.05), Vector3(0.3 + i * 0.5, 1.31, -1.05), 0.09, Color(0.65, 0.08, 0.08), 8)
	for i: int in 3:
		MeshKit.box(st, Vector3(0.6 + i * 0.75, 0.42, -0.9), Vector3(0.62, 0.34, 0.3), [Color(0.1, 0.3, 0.75), Color(0.75, 0.12, 0.12), Color(0.1, 0.3, 0.75)][i])

static func _phones(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 0.55, -0.82), Vector3(4.2, 1.1, 0.5), Color(0.8, 0.85, 0.92))
	for row: int in 2:
		for i: int in 11:
			MeshKit.box(st, Vector3(-2.3 + i * 0.46, 1.55 + row * 0.5, -1.2), Vector3(0.2, 0.36, 0.03), Color(0.1, 0.13, 0.2))

static func _glass(st: SurfaceTool) -> void:
	for i: int in 3:
		var x: float = -1.7 + i * 1.7
		MeshKit.box(st, Vector3(x, 1.25, -1.0), Vector3(1.3, 2.1, 0.08), WOOD)
		MeshKit.box(st, Vector3(x, 1.25, -0.95), Vector3(1.14, 1.94, 0.04), Color(0.72, 0.86, 0.92))

static func _hanging_garlands(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 2.2, -0.9), Vector3(5.0, 0.05, 0.05), WOOD)
	for i: int in 13:
		var x: float = -2.4 + i * 0.4
		for k: int in 7:
			MeshKit.tube(st, Vector3(x, 2.15 - k * 0.16, -0.9), Vector3(x, 2.05 - k * 0.16, -0.9), 0.065, GARLAND[(i + k / 3) % GARLAND.size()], 6)

static func _office(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 0.45, -0.95), Vector3(2.6, 0.9, 0.6), WOOD)
	MeshKit.box(st, Vector3(0, 1.0, -0.95), Vector3(0.5, 0.34, 0.04), Color(0.12, 0.15, 0.22))
	_shelf(st, 1.9)
	for i: int in 12:
		MeshKit.box(st, Vector3(-2.4 + i * 0.44, 2.14, -1.05), Vector3(0.36, 0.42, 0.3), [Color(0.2, 0.3, 0.55), Color(0.65, 0.55, 0.35)][i % 2])

static func _sacks(st: SurfaceTool) -> void:
	for i: int in 7:
		MeshKit.box(st, Vector3(-2.2 + i * 0.73, 0.5, -0.95), Vector3(0.62, 0.7, 0.5), Color(0.8, 0.72, 0.55).darkened(float(i % 3) * 0.08))
	for i: int in 5:
		MeshKit.box(st, Vector3(-1.4 + i * 0.7, 1.1, -0.98), Vector3(0.6, 0.5, 0.44), Color(0.72, 0.62, 0.42))

## Wedding or music hall: portico on white columns, gold band, banana trees at the gate.
static func _hall(st: SurfaceTool) -> void:
	var w: float = 9.4
	MeshKit.box(st, Vector3(0, 2.4, -1.3), Vector3(w, 4.8, 0.14), Color(0.96, 0.9, 0.8))
	MeshKit.box(st, Vector3(0, 1.3, -1.2), Vector3(2.4, 2.6, 0.08), Color(0.42, 0.12, 0.08)) # Doors.
	MeshKit.box(st, Vector3(0, 2.75, -1.17), Vector3(2.7, 0.12, 0.1), GOLD)
	MeshKit.box(st, Vector3(0, 0.12, -0.5), Vector3(w, 0.24, 1.7), Color(0.72, 0.69, 0.64))
	for i: int in 6:
		var x: float = lerpf(-w * 0.5 + 0.5, w * 0.5 - 0.5, i / 5.0)
		MeshKit.tube(st, Vector3(x, 0.24, -0.05), Vector3(x, 3.1, -0.05), 0.2, WHITE, 10)
	MeshKit.box(st, Vector3(0, SIGN_Y, -0.2), Vector3(w + 0.3, 1.1, 0.5), Color(0.5, 0.1, 0.12))
	MeshKit.box(st, Vector3(0, SIGN_Y + 0.6, -0.2), Vector3(w + 0.4, 0.1, 0.55), GOLD)
	for s: float in [-1.0, 1.0]:
		var x: float = s * (w * 0.5 + 0.45)
		MeshKit.tube(st, Vector3(x, 0.0, 0.1), Vector3(x, 2.5, 0.1), 0.1, Color(0.45, 0.6, 0.25), 7)
		for k: int in 5:
			var a: float = TAU * k / 5.0
			MeshKit.box(st, Vector3(x + cos(a) * 0.5, 2.55, 0.1 + sin(a) * 0.5), Vector3(1.0, 0.04, 0.26), LEAF, Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.45))
	for i: int in 19:
		var x: float = lerpf(-4.4, 4.4, i / 18.0)
		var y: float = 3.02 - sin(float(i % 6) / 5.0 * PI) * 0.22
		MeshKit.box(st, Vector3(x, y, 0.2), Vector3(0.1, 0.16, 0.05), GARLAND[i % GARLAND.size()]) # Toran.

static func _stall(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 0.82, -0.3), Vector3(2.6, 0.08, 1.2), WOOD)
	for s: float in [-1.0, 1.0]:
		MeshKit.tube(st, Vector3(s * 1.1, 0.3, -0.85), Vector3(s * 1.1, 0.3, 0.25), 0.3, Color(0.2, 0.2, 0.22), 10) # Cart wheels.
		for z: float in [-0.8, 0.2]:
			MeshKit.box(st, Vector3(s * 1.25, 1.5, z), Vector3(0.06, 3.0, 0.06), WOOD)
	for i: int in 7:
		var colour: Color = Color(0.1, 0.5, 0.3) if i % 2 == 0 else Color(0.95, 0.85, 0.3)
		MeshKit.box(st, Vector3(-1.5 + i * 0.5, 2.9, -0.3), Vector3(0.5, 0.05, 1.8), colour, Basis(Vector3.RIGHT, 0.18))
	for i: int in 14:
		var at: Vector3 = Vector3(-1.1 + i % 7 * 0.36, 0.92, -0.65 + (i / 7) * 0.5)
		MeshKit.box(st, at, Vector3(0.28, 0.14, 0.34), GARLAND[i % GARLAND.size()])
	for i: int in 9:
		for k: int in 4:
			MeshKit.tube(st, Vector3(-1.2 + i * 0.3, 2.45 - k * 0.14, 0.42), Vector3(-1.2 + i * 0.3, 2.36 - k * 0.14, 0.42), 0.05, GARLAND[(i + k) % GARLAND.size()], 5)

## Chennai house: small porch on two pillars, grille window, tulasi pot and a kolam at the door.
static func _house(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 1.75, -1.3), Vector3(6.2, 3.5, 0.14), Color(0.92, 0.76, 0.66))
	MeshKit.box(st, Vector3(-1.3, 1.1, -1.21), Vector3(1.1, 2.2, 0.06), Color(0.24, 0.36, 0.42)) # Door.
	MeshKit.box(st, Vector3(1.3, 1.65, -1.21), Vector3(1.5, 1.2, 0.06), Color(0.16, 0.18, 0.22))
	for i: int in 7:
		MeshKit.box(st, Vector3(0.65 + i * 0.22, 1.65, -1.16), Vector3(0.04, 1.2, 0.04), Color(0.2, 0.55, 0.5))
	MeshKit.box(st, Vector3(0, 2.9, -0.55), Vector3(6.4, 0.16, 1.7), Color(0.75, 0.72, 0.66)) # Sunshade.
	for s: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(s * 2.9, 1.45, 0.2), Vector3(0.26, 2.9, 0.26), WHITE)
	MeshKit.tube(st, Vector3(2.1, 0.0, -0.3), Vector3(2.1, 0.75, -0.3), 0.26, Color(0.8, 0.4, 0.3), 8) # Tulasi maadam.
	MeshKit.tube(st, Vector3(2.1, 0.75, -0.3), Vector3(2.1, 1.05, -0.3), 0.2, LEAF, 7)
	MeshKit.disc(st, Vector3(-1.3, 0.11, 0.0), Vector3.UP, 0.62, WHITE, 16) # Kolam.
	MeshKit.disc(st, Vector3(-1.3, 0.12, 0.0), Vector3.UP, 0.46, Color(0.75, 0.55, 0.45), 8)
	MeshKit.disc(st, Vector3(-1.3, 0.13, 0.0), Vector3.UP, 0.26, WHITE, 4)

static func _gate(st: SurfaceTool) -> void:
	for s: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(s * 4.0, 1.1, -0.5), Vector3(3.6, 2.2, 0.3), CREAM)
		MeshKit.box(st, Vector3(s * 2.15, 1.5, -0.5), Vector3(0.6, 3.0, 0.6), Color(0.72, 0.28, 0.18))
		MeshKit.box(st, Vector3(s * 2.15, 3.08, -0.5), Vector3(0.76, 0.16, 0.76), CREAM)
		MeshKit.box(st, Vector3(s * 0.92, 1.1, -0.5), Vector3(1.8, 2.0, 0.06), Color(0.12, 0.3, 0.45))
		for i: int in 8:
			MeshKit.box(st, Vector3(s * (0.15 + i * 0.22), 1.1, -0.46), Vector3(0.05, 2.0, 0.05), Color(0.2, 0.42, 0.6))

static func _school(st: SurfaceTool) -> void:
	_gate(st)
	MeshKit.box(st, Vector3(0, SIGN_Y, -0.5), Vector3(5.4, 0.9, 0.12), Color(0.08, 0.2, 0.42))
	for s: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(s * 2.15, 3.3, -0.5), Vector3(0.14, 0.9, 0.14), STEEL)

static func _clinic(st: SurfaceTool) -> void:
	_shop_front(st, [WHITE, Color(0.06, 0.4, 0.36), Color(0.1, 0.55, 0.5), WHITE])
	MeshKit.box(st, Vector3(0, 1.3, -1.2), Vector3(2.2, 2.5, 0.06), Color(0.68, 0.82, 0.86))
	MeshKit.box(st, Vector3(0, 1.75, -1.15), Vector3(0.66, 0.2, 0.04), Color(0.82, 0.1, 0.12))
	MeshKit.box(st, Vector3(0, 1.75, -1.15), Vector3(0.2, 0.66, 0.04), Color(0.82, 0.1, 0.12))
	for s: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(s * 2.1, 0.46, -0.85), Vector3(1.3, 0.06, 0.46), STEEL) # Waiting bench.

## Shamiana: striped canopy on four poles with a table below.
static func _tent(st: SurfaceTool) -> void:
	for x: float in [-2.1, 2.1]:
		for z: float in [-1.2, 0.5]:
			MeshKit.tube(st, Vector3(x, 0.0, z), Vector3(x, 2.7, z), 0.05, STEEL, 6)
	for i: int in 9:
		var colour: Color = Color(0.8, 0.14, 0.14) if i % 2 == 0 else Color(0.96, 0.84, 0.3)
		var x: float = -2.2 + i * 0.55
		MeshKit.box(st, Vector3(x, 2.93, -0.75), Vector3(0.55, 0.04, 1.2), colour, Basis(Vector3.RIGHT, -0.32))
		MeshKit.box(st, Vector3(x, 2.93, 0.05), Vector3(0.55, 0.04, 1.2), colour, Basis(Vector3.RIGHT, 0.32))
		MeshKit.box(st, Vector3(x, 2.55, 0.62), Vector3(0.55, 0.26, 0.03), colour)
	MeshKit.box(st, Vector3(0, 0.76, -0.4), Vector3(2.8, 0.06, 0.8), Color(0.2, 0.3, 0.6))
	for s: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(s * 1.3, 0.38, -0.4), Vector3(0.05, 0.76, 0.7), STEEL)
	for i: int in 5:
		MeshKit.box(st, Vector3(-1.0 + i * 0.5, 0.95, -0.4), Vector3(0.36, 0.32, 0.36), Color(0.76, 0.62, 0.42))

## Painted street-corner EB box with a warning strip and cables up the wall.
static func _power_box(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 0.15, -0.5), Vector3(1.8, 0.3, 1.0), Color(0.6, 0.58, 0.54))
	MeshKit.box(st, Vector3(0, 1.0, -0.5), Vector3(1.5, 1.45, 0.75), Color(0.32, 0.42, 0.36))
	MeshKit.box(st, Vector3(0, 1.76, -0.5), Vector3(1.7, 0.06, 0.92), Color(0.26, 0.34, 0.3))
	MeshKit.box(st, Vector3(0, 1.2, -0.11), Vector3(0.44, 0.44, 0.02), Color(0.95, 0.8, 0.1))
	MeshKit.box(st, Vector3(0, 1.2, -0.095), Vector3(0.05, 0.28, 0.02), DARK)
	for s: float in [-0.35, 0.0, 0.35]:
		MeshKit.tube(st, Vector3(s, 1.75, -0.7), Vector3(s, 3.6, -1.3), 0.03, DARK, 5)

## A broken-down auto with its bonnet-side lid up and a warning triangle behind it.
static func _stuck_auto(st: SurfaceTool) -> void:
	var yellow: Color = Color(0.95, 0.75, 0.1)
	MeshKit.box(st, Vector3(0, 0.75, -0.4), Vector3(2.4, 0.75, 1.2), Color(0.12, 0.22, 0.14))
	MeshKit.box(st, Vector3(-0.1, 1.5, -0.4), Vector3(2.0, 0.08, 1.24), DARK)
	MeshKit.box(st, Vector3(1.0, 0.95, -0.4), Vector3(0.4, 1.0, 1.0), yellow)
	MeshKit.box(st, Vector3(-1.1, 0.72, -0.4), Vector3(0.5, 0.62, 1.2), yellow)
	MeshKit.box(st, Vector3(-1.5, 1.1, -0.4), Vector3(0.05, 0.7, 1.1), yellow, Basis(Vector3.BACK, 0.5)) # Lid up.
	for x: float in [-0.9, 1.1]:
		MeshKit.tube(st, Vector3(x, 0.24, -1.0), Vector3(x, 0.24, -1.05), 0.24, DARK, 10)
		MeshKit.tube(st, Vector3(x, 0.24, 0.2), Vector3(x, 0.24, 0.25), 0.24, DARK, 10)
	MeshKit.box(st, Vector3(-2.2, 0.35, 0.1), Vector3(0.5, 0.05, 0.05), Color(0.9, 0.15, 0.1))
	MeshKit.box(st, Vector3(-2.33, 0.2, 0.1), Vector3(0.45, 0.05, 0.05), Color(0.9, 0.15, 0.1), Basis(Vector3.BACK, 1.05))
	MeshKit.box(st, Vector3(-2.07, 0.2, 0.1), Vector3(0.45, 0.05, 0.05), Color(0.9, 0.15, 0.1), Basis(Vector3.BACK, -1.05))

static func _board(st: SurfaceTool, colour: Color) -> void:
	for s: float in [-1.0, 1.0]:
		MeshKit.tube(st, Vector3(s * 0.75, 0.0, -0.4), Vector3(s * 0.75, 2.5, -0.4), 0.04, STEEL, 6)
	MeshKit.box(st, Vector3(0, 1.95, -0.4), Vector3(1.9, 1.15, 0.05), colour)
	MeshKit.box(st, Vector3(0, 1.95, -0.37), Vector3(1.72, 0.97, 0.02), WHITE)
	for i: int in 4:
		MeshKit.box(st, Vector3(-0.1 + fmod(i * 0.17, 0.3), 2.25 - i * 0.2, -0.355), Vector3(1.2, 0.05, 0.01), DARK.lightened(0.2))

## Red and white road-closed barrier with a sign.
static func _barricade(st: SurfaceTool) -> void:
	for s: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(s * 1.5, 0.55, -0.3), Vector3(0.1, 1.1, 0.5), STEEL)
	for i: int in 7:
		MeshKit.box(st, Vector3(-1.5 + i * 0.5, 0.92, -0.3), Vector3(0.5, 0.26, 0.05), Color(0.85, 0.1, 0.1) if i % 2 == 0 else WHITE)
		MeshKit.box(st, Vector3(-1.5 + i * 0.5, 0.5, -0.3), Vector3(0.5, 0.2, 0.05), WHITE if i % 2 == 0 else Color(0.85, 0.1, 0.1))
	MeshKit.box(st, Vector3(0, 1.55, -0.3), Vector3(1.3, 0.8, 0.05), Color(0.85, 0.65, 0.05))

# --- Named shops with a lit inside ------------------------------------------------------------------

## A shallow room a real shop would have: plastered back and side walls in the shop's own colour,
## a tiled floor, a ceiling with a tube light and a fan, a calendar and a framed founder's photo.
static func _lit_inside(st: SurfaceTool, c: Array) -> void:
	var inner: Color = (c[0] as Color).darkened(0.1)
	MeshKit.box(st, Vector3(0, 1.45, -1.36), Vector3(5.6, 2.9, 0.06), inner)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(side * 2.82, 1.45, -0.9), Vector3(0.06, 2.9, 0.9), inner.darkened(0.12))
	MeshKit.box(st, Vector3(0, 0.215, -0.9), Vector3(5.6, 0.03, 0.92), TILE)
	for i: int in 7:
		MeshKit.box(st, Vector3(-2.4 + i * 0.8, 0.232, -0.9), Vector3(0.015, 0.004, 0.92), TILE.darkened(0.2))
	MeshKit.box(st, Vector3(0, 2.86, -0.9), Vector3(5.6, 0.04, 0.92), inner.lightened(0.3))
	MeshKit.box(st, Vector3(-1.2, 2.8, -0.95), Vector3(1.22, 0.05, 0.06), TUBE)
	MeshKit.box(st, Vector3(1.4, 2.8, -0.95), Vector3(1.22, 0.05, 0.06), TUBE)
	# Ceiling fan.
	MeshKit.tube(st, Vector3(0.1, 2.84, -0.8), Vector3(0.1, 2.62, -0.8), 0.015, Color(0.45, 0.25, 0.15), 5)
	MeshKit.tube(st, Vector3(0.1, 2.62, -0.8), Vector3(0.1, 2.55, -0.8), 0.09, Color(0.5, 0.28, 0.16), 8)
	for k: int in 3:
		var a: float = TAU * k / 3.0 + 0.4
		MeshKit.box(st, Vector3(0.1 + cos(a) * 0.36, 2.58, -0.8 + sin(a) * 0.36), Vector3(0.58, 0.012, 0.11), Color(0.62, 0.36, 0.2), Basis(Vector3.UP, -a))
	# Calendar (bright print, dark date grid) and a garlanded photo frame.
	MeshKit.box(st, Vector3(2.3, 1.95, -1.32), Vector3(0.42, 0.62, 0.02), WHITE)
	MeshKit.box(st, Vector3(2.3, 2.1, -1.31), Vector3(0.36, 0.26, 0.01), Color(0.85, 0.35, 0.2))
	MeshKit.box(st, Vector3(2.3, 1.8, -1.31), Vector3(0.34, 0.2, 0.01), Color(0.3, 0.3, 0.32))
	MeshKit.box(st, Vector3(-2.35, 2.25, -1.32), Vector3(0.44, 0.52, 0.03), GOLD)
	MeshKit.box(st, Vector3(-2.35, 2.25, -1.3), Vector3(0.34, 0.42, 0.01), Color(0.5, 0.45, 0.42))
	for k: int in 9:
		var t: float = float(k) / 8.0
		MeshKit.box(st, Vector3(-2.57 + t * 0.44, 1.98 + absf(t - 0.5) * 0.3, -1.28), Vector3(0.05, 0.05, 0.05), [Color(0.98, 0.6, 0.1), WHITE][k % 2])

## Kannan's filter coffee bar: a steel-topped counter at the front with the brass filter boilers,
## davara sets in a row, a milk pot on a stove, snack jars and the menu on the wall.
static func _coffee_bar(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0.6, 0.55, -0.32), Vector3(3.6, 0.9, 0.55), Color(0.5, 0.28, 0.12))
	MeshKit.box(st, Vector3(0.6, 1.02, -0.32), Vector3(3.7, 0.04, 0.6), STEEL_TOP)
	for i: int in 3:
		MeshKit.box(st, Vector3(-0.8 + i * 1.2, 0.55, -0.04), Vector3(0.9, 0.7, 0.02), Color(0.62, 0.36, 0.16))
	# The decoction tower: two brass filters on a big brass boiler with a tap.
	var p: PackedVector2Array = PackedVector2Array([Vector2(0.0, 1.04), Vector2(0.26, 1.04), Vector2(0.28, 1.5), Vector2(0.22, 1.62), Vector2(0.0, 1.66)])
	_vessel(st, Vector3(-1.85, 0, -0.95), p, BRASS)
	MeshKit.box(st, Vector3(-1.85, 0.52, -0.95), Vector3(0.6, 1.02, 0.5), Color(0.45, 0.45, 0.47))
	for k: int in 2:
		var at: Vector3 = Vector3(-2.0 + k * 0.3, 1.66, -0.95)
		MeshKit.tube(st, at, at + Vector3(0, 0.3, 0), 0.08, BRASS.lightened(0.15), 10)
		MeshKit.tube(st, at + Vector3(0, 0.3, 0), at + Vector3(0, 0.36, 0), 0.05, BRASS, 8)
	MeshKit.tube(st, Vector3(-1.85, 1.3, -0.68), Vector3(-1.85, 1.3, -0.6), 0.025, DARK, 6)
	# Gas stove with the milk pot boiling.
	MeshKit.box(st, Vector3(-0.85, 1.08, -0.42), Vector3(0.5, 0.08, 0.36), Color(0.2, 0.2, 0.22))
	MeshKit.tube(st, Vector3(-0.85, 1.12, -0.42), Vector3(-0.85, 1.38, -0.42), 0.15, Color(0.82, 0.84, 0.86), 12)
	MeshKit.disc(st, Vector3(-0.85, 1.381, -0.42), Vector3.UP, 0.14, WHITE, 12)
	# Davara sets waiting on the counter.
	for i: int in 7:
		var at: Vector3 = Vector3(-0.25 + i * 0.3, 1.04, -0.25)
		MeshKit.tube(st, at, at + Vector3(0, 0.035, 0), 0.075, BRASS, 10)
		MeshKit.tube(st, at, at + Vector3(0, 0.15, 0), 0.04, BRASS.lightened(0.1), 8)
	# Snack jars with coloured lids.
	for i: int in 4:
		var at: Vector3 = Vector3(1.75 + i * 0.22, 1.04, -0.45)
		MeshKit.tube(st, at, at + Vector3(0, 0.3, 0), 0.085, Color(0.85, 0.9, 0.92), 10)
		MeshKit.tube(st, at + Vector3(0, 0.03, 0), at + Vector3(0, 0.2, 0), 0.075, [Color(0.85, 0.55, 0.2), Color(0.95, 0.8, 0.4), Color(0.6, 0.32, 0.12), Color(0.9, 0.7, 0.3)][i], 10)
		MeshKit.tube(st, at + Vector3(0, 0.3, 0), at + Vector3(0, 0.34, 0), 0.07, [Color(0.85, 0.1, 0.1), Color(0.1, 0.5, 0.2), Color(0.95, 0.75, 0.1), Color(0.15, 0.3, 0.7)][i], 10)
	# Menu board on the back wall.
	MeshKit.box(st, Vector3(1.0, 2.05, -1.32), Vector3(1.5, 0.8, 0.03), Color(0.1, 0.22, 0.15))
	for r: int in 5:
		MeshKit.box(st, Vector3(0.85, 2.32 - r * 0.13, -1.3), Vector3(0.9, 0.04, 0.01), Color(0.95, 0.95, 0.85))
		MeshKit.box(st, Vector3(1.55, 2.32 - r * 0.13, -1.3), Vector3(0.2, 0.04, 0.01), Color(0.98, 0.85, 0.3))

## Selvam Tailors: two machines on wooden tables, a dress form in a half-made shirt, a rail of
## finished clothes, cloth rolls on the shelf, a long mirror and a cutting table with a tape.
static func _tailors(st: SurfaceTool) -> void:
	for x: float in [-1.6, -0.1]:
		MeshKit.box(st, Vector3(x, 0.78, -0.85), Vector3(1.05, 0.05, 0.55), WOOD)
		for sx: float in [-0.45, 0.45]:
			MeshKit.box(st, Vector3(x + sx, 0.48, -0.85), Vector3(0.05, 0.6, 0.5), DARK.lightened(0.1))
		MeshKit.box(st, Vector3(x, 0.3, -0.85), Vector3(0.7, 0.05, 0.3), DARK.lightened(0.1)) # Treadle.
		_machine(st, Vector3(x, 0.805, -0.85))
	# Dress form with a half-made blue shirt.
	MeshKit.tube(st, Vector3(1.25, 0.22, -0.7), Vector3(1.25, 0.95, -0.7), 0.025, WOOD, 6)
	var torso: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.95), Vector2(0.15, 0.97), Vector2(0.17, 1.2), Vector2(0.19, 1.4), Vector2(0.12, 1.55), Vector2(0.04, 1.62), Vector2(0.0, 1.62)])
	_vessel(st, Vector3(1.25, 0, -0.7), torso, Color(0.25, 0.45, 0.85))
	# Clothes rail with shirts on hangers.
	MeshKit.tube(st, Vector3(-2.6, 2.3, -1.05), Vector3(0.4, 2.3, -1.05), 0.015, STEEL, 6)
	var cloth: Array[Color] = [Color(0.95, 0.95, 0.92), Color(0.86, 0.3, 0.3), Color(0.3, 0.55, 0.85), Color(0.98, 0.82, 0.3), Color(0.35, 0.65, 0.4), Color(0.6, 0.3, 0.6), Color(0.95, 0.95, 0.92), Color(0.9, 0.55, 0.2)]
	for i: int in cloth.size():
		var x: float = -2.45 + i * 0.36
		MeshKit.box(st, Vector3(x, 1.95, -1.05), Vector3(0.3, 0.62, 0.06), cloth[i])
		MeshKit.box(st, Vector3(x, 2.25, -1.05), Vector3(0.3, 0.03, 0.08), cloth[i].darkened(0.2))
	# Cloth rolls on the high shelf.
	_shelf(st, 2.52, 0.6, 2.6)
	for i: int in 7:
		var x: float = 0.75 + i * 0.27
		MeshKit.tube(st, Vector3(x, 2.66, -1.25), Vector3(x, 2.66, -0.85), 0.11, Color.from_hsv(fmod(0.07 + i * 0.29, 1.0), 0.55, 0.85), 10)
	# Long mirror and a cutting table at the side.
	MeshKit.box(st, Vector3(2.1, 1.35, -1.32), Vector3(0.6, 1.6, 0.04), Color(0.4, 0.26, 0.14))
	MeshKit.box(st, Vector3(2.1, 1.35, -1.3), Vector3(0.5, 1.5, 0.01), Color(0.72, 0.82, 0.88))
	MeshKit.box(st, Vector3(2.0, 0.9, -0.55), Vector3(1.1, 0.05, 0.6), Color(0.62, 0.45, 0.28))
	MeshKit.box(st, Vector3(2.0, 0.55, -0.55), Vector3(1.0, 0.65, 0.5), Color(0.5, 0.34, 0.2))
	MeshKit.box(st, Vector3(1.9, 0.935, -0.55), Vector3(0.8, 0.02, 0.45), Color(0.9, 0.9, 0.85)) # Cloth laid out.
	MeshKit.box(st, Vector3(2.15, 0.95, -0.5), Vector3(0.5, 0.008, 0.03), Color(0.98, 0.82, 0.12)) # Tape.

## An Usha-style black sewing machine: base, curved arm, wheel.
static func _machine(st: SurfaceTool, at: Vector3) -> void:
	var black: Color = Color(0.07, 0.07, 0.08)
	MeshKit.box(st, at + Vector3(0, 0.04, 0), Vector3(0.5, 0.08, 0.2), black)
	MeshKit.box(st, at + Vector3(0.18, 0.2, 0), Vector3(0.1, 0.26, 0.12), black)
	MeshKit.box(st, at + Vector3(0.0, 0.32, 0), Vector3(0.46, 0.08, 0.11), black)
	MeshKit.box(st, at + Vector3(-0.2, 0.22, 0), Vector3(0.08, 0.16, 0.1), black)
	MeshKit.box(st, at + Vector3(0.0, 0.33, 0.056), Vector3(0.3, 0.025, 0.002), GOLD)
	MeshKit.tube(st, at + Vector3(0.26, 0.26, 0), at + Vector3(0.3, 0.26, 0), 0.09, Color(0.55, 0.56, 0.58), 10)

## Mohana Book House: books to the ceiling on three walls, a table of stacked books at the front,
## a reading chair and a teacher's lamp.
static func _bookhouse(st: SurfaceTool) -> void:
	for y: float in [0.62, 1.12, 1.62, 2.12]:
		_shelf(st, y, -2.75, 2.75)
		var n: int = 36
		for i: int in n:
			var height: float = 0.3 + fmod(float(i) * 0.37 + y, 0.14)
			var lean: Basis = Basis(Vector3.BACK, 0.12) if (i * 7 + int(y * 10.0)) % 11 == 0 else Basis.IDENTITY
			MeshKit.box(st, Vector3(-2.62 + i * 0.148, y + 0.03 + height * 0.5, -1.08), Vector3(0.12, height, 0.24), Color.from_hsv(fmod(i * 0.173 + y * 0.31, 1.0), 0.45, 0.62 + fmod(i * 0.11, 0.25)), lean)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(side * 2.68, 1.4, -0.8), Vector3(0.24, 2.4, 0.5), WOOD)
		for y: float in [0.75, 1.3, 1.85]:
			for i: int in 3:
				MeshKit.box(st, Vector3(side * 2.62, y + 0.18, -1.0 + i * 0.16), Vector3(0.22, 0.34, 0.12), Color.from_hsv(fmod(0.11 + i * 0.3 + y, 1.0), 0.5, 0.7))
	# Display table at the front with stacks of books.
	MeshKit.box(st, Vector3(0.2, 0.72, -0.25), Vector3(2.6, 0.05, 0.6), WOOD.lightened(0.1))
	for sx: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.2 + sx * 1.22, 0.45, -0.25), Vector3(0.06, 0.55, 0.55), WOOD)
	for i: int in 8:
		var x: float = -0.85 + i * 0.3
		var stack: int = 2 + (i * 5) % 4
		for k: int in stack:
			MeshKit.box(st, Vector3(x + fmod(k * 0.013, 0.03), 0.765 + k * 0.045, -0.25), Vector3(0.22, 0.04, 0.3), Color.from_hsv(fmod(i * 0.21 + k * 0.37, 1.0), 0.5, 0.75))
	# Reading chair and lamp by the side wall.
	MeshKit.box(st, Vector3(-1.9, 0.45, -0.6), Vector3(0.5, 0.06, 0.5), WOOD)
	MeshKit.box(st, Vector3(-1.9, 0.75, -0.83), Vector3(0.5, 0.6, 0.05), WOOD)
	for p: Vector2 in [Vector2(-0.22, -0.22), Vector2(0.22, -0.22), Vector2(-0.22, 0.22), Vector2(0.22, 0.22)]:
		MeshKit.box(st, Vector3(-1.9 + p.x, 0.32, -0.6 + p.y), Vector3(0.04, 0.24, 0.04), WOOD.darkened(0.2))
	MeshKit.tube(st, Vector3(-2.35, 0.22, -0.9), Vector3(-2.35, 1.4, -0.9), 0.015, STEEL, 6)
	MeshKit.tube(st, Vector3(-2.35, 1.38, -0.9), Vector3(-2.35, 1.55, -0.9), 0.12, Color(0.95, 0.85, 0.55), 10)

## Murugan Tea Stall: the steel tea boiler with its tap, glass tumblers upside down on a tray,
## biscuit jars, hanging banana bunches and snack strips, newspapers pegged on a string.
static func _tea_kadai(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0.3, 0.55, -0.3), Vector3(3.8, 0.9, 0.55), Color(0.2, 0.42, 0.62))
	MeshKit.box(st, Vector3(0.3, 1.02, -0.3), Vector3(3.9, 0.04, 0.6), STEEL_TOP)
	MeshKit.box(st, Vector3(0.3, 0.55, -0.02), Vector3(3.7, 0.12, 0.01), Color(0.98, 0.84, 0.25))
	# The boiler: a big polished steel drum with a chimney and a brass tap.
	var boiler: PackedVector2Array = PackedVector2Array([Vector2(0.0, 1.04), Vector2(0.24, 1.04), Vector2(0.27, 1.12), Vector2(0.27, 1.6), Vector2(0.18, 1.7), Vector2(0.06, 1.72), Vector2(0.0, 1.72)])
	_vessel(st, Vector3(-1.2, 0, -0.42), boiler, Color(0.84, 0.86, 0.88))
	MeshKit.tube(st, Vector3(-1.2, 1.72, -0.42), Vector3(-1.2, 2.1, -0.42), 0.04, Color(0.55, 0.56, 0.58), 8)
	MeshKit.tube(st, Vector3(-1.2, 1.24, -0.16), Vector3(-1.2, 1.24, -0.08), 0.03, BRASS, 6)
	MeshKit.tube(st, Vector3(-0.65, 1.04, -0.32), Vector3(-0.65, 1.22, -0.32), 0.1, Color(0.8, 0.82, 0.84), 10) # Milk can.
	# Upside-down glasses on a tray.
	MeshKit.box(st, Vector3(0.25, 1.05, -0.3), Vector3(0.85, 0.02, 0.4), Color(0.65, 0.67, 0.7))
	for r: int in 2:
		for i: int in 5:
			var at: Vector3 = Vector3(-0.05 + i * 0.15, 1.06, -0.4 + r * 0.17)
			MeshKit.tube(st, at, at + Vector3(0, 0.11, 0), 0.036, Color(0.86, 0.9, 0.9), 8)
	# Biscuit jars.
	for i: int in 5:
		var at: Vector3 = Vector3(1.05 + i * 0.22, 1.04, -0.42)
		MeshKit.tube(st, at, at + Vector3(0, 0.28, 0), 0.085, Color(0.85, 0.9, 0.92), 10)
		MeshKit.tube(st, at + Vector3(0, 0.02, 0), at + Vector3(0, 0.2, 0), 0.075, [Color(0.85, 0.6, 0.25), Color(0.95, 0.85, 0.55), Color(0.55, 0.3, 0.12), Color(0.95, 0.7, 0.3), Color(0.98, 0.9, 0.7)][i], 10)
		MeshKit.tube(st, at + Vector3(0, 0.28, 0), at + Vector3(0, 0.32, 0), 0.07, Color(0.85, 0.12, 0.1), 10)
	# Banana bunches and snack strips hanging from the beam.
	MeshKit.tube(st, Vector3(-2.7, 2.42, -0.15), Vector3(2.7, 2.42, -0.15), 0.02, WOOD, 6)
	for x: float in [-2.2, 2.25]:
		MeshKit.tube(st, Vector3(x, 2.42, -0.15), Vector3(x, 2.15, -0.15), 0.01, Color(0.4, 0.3, 0.15), 4)
		for k: int in 5:
			var yy: float = 2.12 - k * 0.09
			for j: int in 5:
				var a: float = TAU * j / 5.0
				MeshKit.box(st, Vector3(x + cos(a) * 0.08, yy, -0.15 + sin(a) * 0.08), Vector3(0.04, 0.16, 0.04), Color(0.9, 0.78, 0.15).darkened(float(k) * 0.03), Basis(Vector3(sin(a), 0, -cos(a)), 0.35))
	for i: int in 6:
		var x: float = -1.6 + i * 0.6
		for k: int in 4:
			MeshKit.box(st, Vector3(x, 2.3 - k * 0.15, -0.15), Vector3(0.14, 0.13, 0.015), Color.from_hsv(fmod(0.02 + i * 0.17, 1.0), 0.75, 0.9))
	# Newspapers pegged on a string at the side.
	MeshKit.tube(st, Vector3(1.9, 1.95, -0.9), Vector3(2.7, 1.95, -0.9), 0.006, Color(0.3, 0.3, 0.3), 4)
	for i: int in 3:
		MeshKit.box(st, Vector3(2.0 + i * 0.27, 1.72, -0.9), Vector3(0.24, 0.42, 0.01), Color(0.92, 0.9, 0.84))
		MeshKit.box(st, Vector3(2.0 + i * 0.27, 1.88, -0.89), Vector3(0.2, 0.05, 0.005), Color(0.3, 0.3, 0.32))
	# A narrow bench along the front for customers (inside the z = 0.7 limit).
	MeshKit.box(st, Vector3(1.9, 0.45, 0.42), Vector3(1.4, 0.05, 0.32), WOOD.lightened(0.1))
	for sx: float in [-0.6, 0.6]:
		MeshKit.box(st, Vector3(1.9 + sx, 0.22, 0.42), Vector3(0.05, 0.44, 0.28), WOOD)

## A round vessel standing upright at `at`: profile points are (radius, height).
static func _vessel(st: SurfaceTool, at: Vector3, profile: PackedVector2Array, colour: Color, segments: int = 14) -> void:
	for i: int in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for k: int in segments:
			var t0: float = TAU * float(k) / segments
			var t1: float = TAU * float(k + 1) / segments
			MeshKit.quad(st, at + Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x), at + Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x),
				at + Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x), at + Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x), colour, true)
