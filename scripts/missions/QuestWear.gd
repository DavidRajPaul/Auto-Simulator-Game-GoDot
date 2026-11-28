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
## "follow" (optional): the bone it moves with, when that differs from where it is placed. The
## towel is placed on the shoulder but follows the chest: the shoulder bone swings in the talk
## clips and turned the towel out into the air (Nov 28 owner report, "white projections").
## "hold": "overhead" (the umbrella): not on a bone at all. QuestActor stands it upright over the
## head at a grip in front of the right shoulder and poses the right arm to hold it (HoldPose).

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
	"towel": {"bone": "RightArm", "follow": "Spine1", "at": Vector3(0.05, -0.03, 0.01)},
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
	# A black umbrella held open over the head, the right hand on the shaft.
	"umbrella": {"bone": "RightHand", "hold": "overhead", "at": Vector3.ZERO},
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
		"pencil": MeshKit.tube(st, Vector3(-0.012, 0.004, 0.025), Vector3(-0.004, -0.012, -0.05), 0.005, Color(0.95, 0.75, 0.15), 5)
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

## Draped over the shoulder like a real thundu: a soft cloth band that wraps the top of the
## shoulder (an arc round its centre) and hangs as a long flap down the chest and a shorter one
## down the back, a red check border near each end. Origin = the middle of the shoulder top.
## It hugs the shoulder (no stiff box standing off it: Nov 28 owner report, "white projections").
static func _towel(st: SurfaceTool) -> void:
	var cloth: Color = Color(0.9, 0.88, 0.8)
	var check: Color = Color(0.7, 0.17, 0.15)
	var half_w: float = 0.055
	# Centre line, front hem → over the shoulder → back hem, in the person's YZ plane.
	var line: PackedVector3Array = PackedVector3Array()
	var front: float = 0.135
	var back: float = 0.12
	var top: float = 0.07
	for i: int in 6:
		line.append(Vector3(0.004 * i, -0.34 + 0.068 * i, front + 0.008 - 0.0016 * i))
	for i: int in range(1, 10):
		var a: float = PI * float(i) / 10.0
		line.append(Vector3(0.02, sin(a) * top, lerpf(front, -back, (1.0 - cos(a)) * 0.5)))
	for i: int in 5:
		line.append(Vector3(0.016 - 0.003 * i, -0.055 * i, -back - 0.004 * i))
	for i: int in line.size() - 1:
		var a: Vector3 = line[i]
		var b: Vector3 = line[i + 1]
		var colour: Color = check if (i == 1 or i == line.size() - 3) else cloth
		var wa: Vector3 = Vector3(half_w, 0, 0)
		# Outer face and inner face (the cloth is seen from every side).
		MeshKit.quad(st, a - wa, a + wa, b + wa, b - wa, colour, true)
		MeshKit.quad(st, a + wa, a - wa, b - wa, b + wa, colour.darkened(0.12), true)
	# A few loose threads of fringe at the front hem.
	for k: int in 5:
		var x: float = -half_w + 0.012 + k * 0.022
		MeshKit.tube(st, line[0] + Vector3(x, 0, 0), line[0] + Vector3(x, -0.03, 0.002), 0.003, cloth, 3)

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

## A black cloth umbrella, open. The origin is the grip (where the hand closes on the shaft); +Y up
## the shaft. A wooden crook handle below the hand, a steel shaft, eight ribs and a scalloped black
## canopy whose panels sag between the ribs, drawn on both sides (it is seen from below in the
## cutscenes), and a short steel tip on top. Ribs are dark under the canopy, not bright steel.
const UMBRELLA_R: float = 0.52
static func _umbrella(st: SurfaceTool) -> void:
	var cloth: Color = Color(0.06, 0.06, 0.075)
	var inner: Color = Color(0.11, 0.11, 0.13)
	var wood: Color = Color(0.32, 0.19, 0.1)
	var rib: Color = Color(0.2, 0.2, 0.22)
	var apex: Vector3 = Vector3(0.0, 0.86, 0.0)
	# Shaft from just below the hand to the apex, and the crook handle hooking forward under the hand.
	MeshKit.tube(st, Vector3(0.0, -0.06, 0.0), apex, 0.0075, Color(0.45, 0.46, 0.48), 6)
	MeshKit.tube(st, Vector3(0.0, -0.02, 0.0), Vector3(0.0, -0.13, 0.0), 0.014, wood, 6)
	MeshKit.tube(st, Vector3(0.0, -0.13, 0.0), Vector3(0.0, -0.17, 0.035), 0.014, wood, 6)
	MeshKit.tube(st, Vector3(0.0, -0.17, 0.035), Vector3(0.0, -0.15, 0.07), 0.014, wood, 6)
	MeshKit.tube(st, Vector3(0.0, -0.15, 0.07), Vector3(0.0, -0.12, 0.075), 0.013, wood, 6)
	MeshKit.tube(st, apex, apex + Vector3(0.0, 0.07, 0.0), 0.006, Color(0.45, 0.46, 0.48), 5)
	# The runner (the sliding collar the stretchers meet) and eight stretchers up to the ribs.
	MeshKit.tube(st, Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.55, 0.0), 0.014, rib, 6)
	var n: int = 8
	for i: int in n:
		var a0: float = TAU * float(i) / n
		var a1: float = TAU * float(i + 1) / n
		var am: float = (a0 + a1) * 0.5
		var tip0: Vector3 = Vector3(cos(a0) * UMBRELLA_R, 0.62, sin(a0) * UMBRELLA_R)
		var tip1: Vector3 = Vector3(cos(a1) * UMBRELLA_R, 0.62, sin(a1) * UMBRELLA_R)
		var mid_r: float = UMBRELLA_R * 0.93
		var mid: Vector3 = Vector3(cos(am) * mid_r, 0.655, sin(am) * mid_r)
		var ring0: Vector3 = Vector3(cos(a0) * 0.29, 0.79, sin(a0) * 0.29)
		var ring1: Vector3 = Vector3(cos(a1) * 0.29, 0.79, sin(a1) * 0.29)
		var ringm: Vector3 = Vector3(cos(am) * 0.275, 0.8, sin(am) * 0.275)
		# Outer cloth (up and out), with the inner face under it.
		_cloth_tri(st, apex, ring1, ringm, cloth, inner)
		_cloth_tri(st, apex, ringm, ring0, cloth, inner)
		_cloth_tri(st, ring0, ringm, mid, cloth, inner)
		_cloth_tri(st, ring0, mid, tip0, cloth, inner)
		_cloth_tri(st, ringm, ring1, tip1, cloth, inner)
		_cloth_tri(st, ringm, tip1, mid, cloth, inner)
		# The rib under the cloth, and its stretcher from the runner.
		var rib_in: Vector3 = tip0 * Vector3(0.96, 1.0, 0.96) + Vector3(0.0, -0.012, 0.0)
		MeshKit.tube(st, apex + Vector3(0.0, -0.02, 0.0), ring0 + Vector3(0.0, -0.012, 0.0), 0.004, rib, 4)
		MeshKit.tube(st, ring0 + Vector3(0.0, -0.012, 0.0), rib_in, 0.004, rib, 4)
		MeshKit.tube(st, Vector3(0.0, 0.54, 0.0), ring0 * Vector3(1.25, 1.0, 1.25) + Vector3(0.0, -0.03, 0.0), 0.003, rib, 4)
		MeshKit.box(st, tip0 + Vector3(0.0, -0.008, 0.0), Vector3(0.014, 0.018, 0.014), rib)

## One canopy triangle, outer face (a, b, c in this winding) and the inner face just under it.
static func _cloth_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outer: Color, inner: Color) -> void:
	st.set_smooth_group(-1)
	st.set_color(outer)
	MeshKit._tri(st, a, c, b)
	var dn: Vector3 = Vector3(0.0, -0.004, 0.0)
	st.set_color(inner)
	MeshKit._tri(st, a + dn, b + dn, c + dn)

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
