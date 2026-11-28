class_name QuestWear
extends RefCounted
## Small things a story person wears or carries, so a quest's people look like themselves and not
## like the street crowd on the same model: a tailor's measuring tape, a teacher's spectacles and
## jasmine, a tea master's towel. Each item is one vertex-painted mesh (LandmarkKit material),
## fixed to a bone of the street-people rig (QuestActor.wear), placed where it sits in the idle
## clip, so it moves with every gesture.
##
## Placement is in the person's own space at idle: +Z is the front, -X the right hand, metres.
## "bone" is the rig bone it follows; "at" is the offset from that bone in the person's space.

const BRASS: Color = Color(0.78, 0.6, 0.24)
const STEEL: Color = Color(0.74, 0.76, 0.78)
const ITEMS: Dictionary = {
	# Yellow tape round the neck, both ends hanging down the chest.
	"tape": {"bone": "Neck", "at": Vector3(0.0, -0.02, 0.03)},
	# Thin dark-rimmed spectacles on the nose.
	"specs": {"bone": "Head", "at": Vector3(0.0, 0.055, 0.1)},
	# A string of jasmine pinned at the back of the head.
	"jasmine": {"bone": "Head", "at": Vector3(0.0, 0.1, -0.085)},
	# A checked towel (thundu) over the right shoulder.
	"towel": {"bone": "RightShoulder", "at": Vector3(-0.035, 0.06, 0.0)},
	# Brass davara and tumbler, held in the right hand.
	"davara": {"bone": "RightHand", "at": Vector3(-0.02, -0.08, 0.05)},
	# A steel tea glass in the right hand.
	"glass": {"bone": "RightHand", "at": Vector3(-0.01, -0.09, 0.05)},
	# A hardback book in the left hand.
	"book": {"bone": "LeftHand", "at": Vector3(0.03, -0.1, 0.05)},
	# A pencil tucked behind the right ear.
	"pencil": {"bone": "Head", "at": Vector3(-0.075, 0.07, 0.0)},
	# A traffic constable's whistle on a white cord.
	"whistle": {"bone": "Neck", "at": Vector3(0.0, -0.02, 0.03)},
	# A nurse's stethoscope round the neck, the chest piece on the front.
	"stethoscope": {"bone": "Neck", "at": Vector3(0.0, -0.02, 0.03)},
	# A wicker basket of greens, carried by the handle in the right hand.
	"basket": {"bone": "RightHand", "at": Vector3(-0.01, -0.06, 0.05)},
	# A black umbrella held up in the right hand.
	"umbrella": {"bone": "RightHand", "at": Vector3(-0.01, -0.09, 0.05)},
	# A clipboard with a sheet and a steel clip, in the left hand.
	"clipboard": {"bone": "LeftHand", "at": Vector3(0.03, -0.1, 0.05)},
}

static var _cache: Dictionary = {}

static func has(item: String) -> bool:
	return ITEMS.has(item)

static func spec(item: String) -> Dictionary:
	return ITEMS.get(item, {}) as Dictionary

static func mesh(item: String) -> ArrayMesh:
	if not _cache.has(item):
		_cache[item] = _build(item)
	return _cache[item]

static func _build(item: String) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	match item:
		"tape": _tape(st)
		"specs": _specs(st)
		"jasmine": _jasmine(st)
		"towel": _towel(st)
		"davara": _davara(st)
		"glass": _glass(st)
		"book": _book(st)
		"pencil": MeshKit.tube(st, Vector3(0, 0, 0.06), Vector3(0, -0.02, -0.07), 0.006, Color(0.95, 0.75, 0.15), 5)
		"whistle": _whistle(st)
		"stethoscope": _stethoscope(st)
		"basket": _basket(st)
		"umbrella": _umbrella(st)
		"clipboard": _clipboard(st)
	return MeshKit.finish(st, LandmarkKit.material())

## Over the back of the neck and down both sides of the chest, the ends a little apart.
static func _tape(st: SurfaceTool) -> void:
	var yellow: Color = Color(0.98, 0.82, 0.12)
	for side: float in [-1.0, 1.0]:
		var top: Vector3 = Vector3(side * 0.075, 0.0, 0.0)
		var bend: Vector3 = Vector3(side * 0.09, -0.07, 0.1)
		var end: Vector3 = Vector3(side * 0.075, -0.32, 0.13)
		MeshKit.tube(st, top, bend, 0.011, yellow, 5)
		MeshKit.tube(st, bend, end, 0.011, yellow, 5)
		MeshKit.box(st, end + Vector3(0, -0.012, 0), Vector3(0.026, 0.02, 0.012), Color(0.15, 0.15, 0.15))
	MeshKit.tube(st, Vector3(-0.075, 0.0, 0.0), Vector3(0.0, 0.01, -0.07), 0.011, yellow, 5)
	MeshKit.tube(st, Vector3(0.0, 0.01, -0.07), Vector3(0.075, 0.0, 0.0), 0.011, yellow, 5)

static func _specs(st: SurfaceTool) -> void:
	var rim: Color = Color(0.12, 0.1, 0.08)
	for side: float in [-1.0, 1.0]:
		var c: Vector3 = Vector3(side * 0.032, 0.0, 0.0)
		var steps: int = 10
		for i: int in steps:
			var a0: float = TAU * float(i) / steps
			var a1: float = TAU * float(i + 1) / steps
			MeshKit.tube(st, c + Vector3(cos(a0) * 0.022, sin(a0) * 0.017, 0), c + Vector3(cos(a1) * 0.022, sin(a1) * 0.017, 0), 0.0028, rim, 4)
		MeshKit.disc(st, c + Vector3(0, 0, 0.001), Vector3.BACK, 0.019, Color(0.78, 0.86, 0.9, 1.0), 10)
		MeshKit.tube(st, Vector3(side * 0.054, 0.004, 0.0), Vector3(side * 0.07, 0.008, -0.09), 0.0025, rim, 4)
	MeshKit.tube(st, Vector3(-0.01, 0.004, 0.0), Vector3(0.01, 0.004, 0.0), 0.003, rim, 4)

static func _jasmine(st: SurfaceTool) -> void:
	var white: Color = Color(0.97, 0.97, 0.92)
	for i: int in 9:
		var a: float = lerpf(-1.0, 1.0, float(i) / 8.0)
		var p: Vector3 = Vector3(a * 0.07, -abs(a) * 0.02 - float(i % 2) * 0.004, -abs(a) * 0.012)
		MeshKit.box(st, p, Vector3(0.022, 0.022, 0.022), white)
	for i: int in 6:
		MeshKit.box(st, Vector3(0.0, -0.035 - i * 0.03, -0.012), Vector3(0.02, 0.022, 0.02), white)
	MeshKit.box(st, Vector3(0.0, -0.21, -0.012), Vector3(0.016, 0.016, 0.016), Color(0.3, 0.6, 0.25))

## Folded over the shoulder: a strip on top, a longer flap down the front, a shorter one behind.
static func _towel(st: SurfaceTool) -> void:
	var cloth: Color = Color(0.93, 0.92, 0.86)
	var check: Color = Color(0.72, 0.18, 0.16)
	MeshKit.box(st, Vector3(0, 0.0, 0.0), Vector3(0.1, 0.018, 0.22), cloth)
	MeshKit.box(st, Vector3(0, -0.15, 0.11), Vector3(0.1, 0.3, 0.016), cloth, Basis(Vector3.RIGHT, deg_to_rad(-8.0)))
	MeshKit.box(st, Vector3(0, -0.1, -0.11), Vector3(0.1, 0.2, 0.016), cloth)
	for y: float in [-0.06, -0.17, -0.27]:
		MeshKit.box(st, Vector3(0, y, 0.122), Vector3(0.102, 0.014, 0.012), check)
	MeshKit.box(st, Vector3(0.025, -0.15, 0.122), Vector3(0.012, 0.3, 0.012), check)

## The south Indian filter-coffee set: a wide brass bowl and the tall tumbler standing in it.
static func _davara(st: SurfaceTool) -> void:
	var bowl: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.05, 0.02), Vector2(0.06, 0.045), Vector2(0.062, 0.05)])
	_upright_lathe(st, Vector3.ZERO, bowl, BRASS)
	var cup: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.01), Vector2(0.026, 0.01), Vector2(0.03, 0.06), Vector2(0.036, 0.11), Vector2(0.038, 0.115)])
	_upright_lathe(st, Vector3.ZERO, cup, BRASS.lightened(0.12))
	MeshKit.disc(st, Vector3(0, 0.105, 0), Vector3.UP, 0.034, Color(0.86, 0.74, 0.56), 10) # Froth.

static func _glass(st: SurfaceTool) -> void:
	var cup: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.03, 0.05), Vector2(0.034, 0.1)])
	_upright_lathe(st, Vector3.ZERO, cup, STEEL)
	MeshKit.disc(st, Vector3(0, 0.085, 0), Vector3.UP, 0.031, Color(0.72, 0.5, 0.3), 10) # Tea.

static func _book(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3.ZERO, Vector3(0.03, 0.17, 0.12), Color(0.55, 0.12, 0.1))
	MeshKit.box(st, Vector3(0.0, 0.0, 0.004), Vector3(0.024, 0.16, 0.112), Color(0.95, 0.92, 0.82))
	MeshKit.box(st, Vector3(0.0, 0.03, 0.061), Vector3(0.031, 0.024, 0.002), Color(0.86, 0.7, 0.25))

## A white cord over the neck to the chest, a steel whistle at the end.
static func _whistle(st: SurfaceTool) -> void:
	var cord: Color = Color(0.96, 0.96, 0.94)
	for side: float in [-1.0, 1.0]:
		var top: Vector3 = Vector3(side * 0.07, 0.0, 0.0)
		var bend: Vector3 = Vector3(side * 0.08, -0.07, 0.1)
		var end: Vector3 = Vector3(side * 0.01, -0.2, 0.125)
		MeshKit.tube(st, top, bend, 0.004, cord, 4)
		MeshKit.tube(st, bend, end, 0.004, cord, 4)
	MeshKit.tube(st, Vector3(-0.07, 0.0, 0.0), Vector3(0.0, 0.01, -0.07), 0.004, cord, 4)
	MeshKit.tube(st, Vector3(0.0, 0.01, -0.07), Vector3(0.07, 0.0, 0.0), 0.004, cord, 4)
	MeshKit.box(st, Vector3(0.0, -0.215, 0.13), Vector3(0.022, 0.022, 0.05), STEEL)
	MeshKit.box(st, Vector3(0.0, -0.205, 0.13), Vector3(0.008, 0.01, 0.052), Color(0.1, 0.1, 0.1))

## Thick dark tubing over the neck, two lines down the chest to a silver chest piece.
static func _stethoscope(st: SurfaceTool) -> void:
	var tube: Color = Color(0.13, 0.14, 0.16)
	for side: float in [-1.0, 1.0]:
		var top: Vector3 = Vector3(side * 0.08, 0.0, 0.0)
		var bend: Vector3 = Vector3(side * 0.095, -0.08, 0.1)
		var end: Vector3 = Vector3(side * 0.03, -0.25, 0.13)
		MeshKit.tube(st, top, bend, 0.009, tube, 5)
		MeshKit.tube(st, bend, end, 0.009, tube, 5)
	MeshKit.tube(st, Vector3(-0.08, 0.0, 0.0), Vector3(0.0, 0.01, -0.075), 0.009, tube, 5)
	MeshKit.tube(st, Vector3(0.0, 0.01, -0.075), Vector3(0.08, 0.0, 0.0), 0.009, tube, 5)
	MeshKit.tube(st, Vector3(-0.03, -0.25, 0.13), Vector3(0.0, -0.285, 0.135), 0.009, tube, 5)
	MeshKit.tube(st, Vector3(0.03, -0.25, 0.13), Vector3(0.0, -0.285, 0.135), 0.009, tube, 5)
	MeshKit.disc(st, Vector3(0.0, -0.3, 0.138), Vector3.BACK, 0.028, STEEL, 12)

## A round wicker basket hanging from its handle, heaped with leafy greens.
static func _basket(st: SurfaceTool) -> void:
	var wicker: Color = Color(0.72, 0.52, 0.28)
	var bowl: PackedVector2Array = PackedVector2Array([Vector2(0.0, -0.17), Vector2(0.09, -0.17), Vector2(0.14, -0.1), Vector2(0.17, -0.03)])
	_upright_lathe(st, Vector3.ZERO, bowl, wicker, 12)
	for i: int in 9:
		var a: float = TAU * float(i) / 9.0
		var base: Vector3 = Vector3(cos(a) * 0.08, -0.03, sin(a) * 0.08)
		MeshKit.tube(st, base, base + Vector3(cos(a) * 0.05, 0.09, sin(a) * 0.05), 0.02, Color(0.2, 0.55, 0.2), 5)
	MeshKit.tube(st, Vector3(-0.14, -0.04, 0.0), Vector3(0.0, 0.1, 0.0), 0.007, wicker, 5)
	MeshKit.tube(st, Vector3(0.0, 0.1, 0.0), Vector3(0.14, -0.04, 0.0), 0.007, wicker, 5)

## A black umbrella: curved handle, steel shaft, ribbed canopy with a rim of spokes.
static func _umbrella(st: SurfaceTool) -> void:
	var black: Color = Color(0.08, 0.08, 0.1)
	MeshKit.tube(st, Vector3(0.0, -0.04, 0.0), Vector3(0.0, 0.5, 0.0), 0.007, STEEL, 5)
	MeshKit.tube(st, Vector3(0.0, -0.04, 0.0), Vector3(0.025, -0.075, 0.0), 0.009, black, 5)
	MeshKit.tube(st, Vector3(0.025, -0.075, 0.0), Vector3(0.06, -0.06, 0.0), 0.009, black, 5)
	var dome: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.62), Vector2(0.12, 0.6), Vector2(0.26, 0.55), Vector2(0.38, 0.47), Vector2(0.43, 0.42)])
	_upright_lathe(st, Vector3.ZERO, dome, black, 10)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		MeshKit.tube(st, Vector3(0.0, 0.6, 0.0), Vector3(cos(a) * 0.43, 0.42, sin(a) * 0.43), 0.004, STEEL, 4)

## A hardboard clipboard with a sheet of paper and a steel clip at the top.
static func _clipboard(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3.ZERO, Vector3(0.012, 0.3, 0.22), Color(0.5, 0.33, 0.18))
	MeshKit.box(st, Vector3(0.0, -0.01, 0.0), Vector3(0.014, 0.27, 0.195), Color(0.97, 0.96, 0.9))
	MeshKit.box(st, Vector3(0.0, 0.14, 0.0), Vector3(0.02, 0.03, 0.06), STEEL)
	for y: float in [0.07, 0.03, -0.01, -0.05]:
		MeshKit.box(st, Vector3(0.0, y, 0.0), Vector3(0.016, 0.004, 0.15), Color(0.5, 0.55, 0.7))

## A round vessel standing on its base: profile points are (radius, height).
static func _upright_lathe(st: SurfaceTool, at: Vector3, profile: PackedVector2Array, colour: Color, segments: int = 12) -> void:
	for i: int in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for k: int in segments:
			var t0: float = TAU * float(k) / segments
			var t1: float = TAU * float(k + 1) / segments
			var p0: Vector3 = at + Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p1: Vector3 = at + Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p2: Vector3 = at + Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			var p3: Vector3 = at + Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			MeshKit.quad(st, p0, p1, p2, p3, colour, true)
