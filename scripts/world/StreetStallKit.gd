class_name StreetStallKit
extends RefCounted
## Chennai kerb stalls as plain triangles, merged into each chunk's building mesh. +Z faces the
## road, y = 0 is the pavement. Types: 0-1 vegetable, 2-3 fancy store, 4-5 petti kadai, 6 flower cart.
##
## Nov 27 owner report: "the shops look very low poly, make them realistic". Every stall used to be a
## handful of boxes (~300 triangles). They are now modelled the way the real ones are put together:
## a sagging tarp on bamboo poles with a folded hem, round produce heaped in woven baskets, plastic
## crates with slats, a hanging scale, a tin petti kadai with a propped flap, glass jars and hanging
## snack strips, a wooden flower cart on spoked wheels under the big striped umbrella, garlands
## hanging in loops. Colours vary a little piece by piece so nothing reads as flat paint. Each kind
## stays around 1,000-1,600 triangles; the city has ~1,500 stalls but a chunk holds only a few, and
## they cost no draw calls (one chunk mesh). The flower stall (Nov 27: coiled jasmine, lotuses, a
## curtain of garland strands) is the richest at ~2.2k.
const PAINT_LIFT: float = 1.5
const WOOD: Color = Color(0.42, 0.27, 0.15)
const WOOD_LIGHT: Color = Color(0.6, 0.44, 0.27)
const BAMBOO: Color = Color(0.7, 0.6, 0.36)
const STEEL: Color = Color(0.45, 0.47, 0.5)
const LEAF: Color = Color(0.22, 0.55, 0.22)
const TOMATO: Color = Color(0.82, 0.14, 0.1)
const CARROT: Color = Color(0.93, 0.48, 0.1)
const ONION: Color = Color(0.68, 0.3, 0.38)
const BRINJAL: Color = Color(0.3, 0.12, 0.42)
const BANANA: Color = Color(0.93, 0.8, 0.22)
const LIME: Color = Color(0.55, 0.78, 0.2)
const BASKET: Color = Color(0.62, 0.47, 0.25)
const GARLAND: Array[Color] = [Color(0.98, 0.96, 0.86), Color(0.96, 0.55, 0.1), Color(0.9, 0.2, 0.3), Color(0.98, 0.85, 0.2)]
const TARP: Array[Color] = [Color(0.12, 0.35, 0.72), Color(0.14, 0.5, 0.3), Color(0.85, 0.2, 0.5), Color(0.95, 0.72, 0.1), Color(0.1, 0.42, 0.62), Color(0.16, 0.5, 0.36), Color(0.82, 0.25, 0.3)]

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func arrays() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: int in 7:
		_rng.seed = 7919 * (kind + 1)
		var st: SurfaceTool = MeshKit.begin()
		match kind:
			0, 1: _vegetable(st, TARP[kind], kind == 1)
			2, 3: _fancy(st, TARP[kind], kind == 3)
			4, 5: _petti(st, TARP[kind], kind == 5)
			_: _flower(st, TARP[kind])
		st.generate_normals()
		var a: Array = st.commit_to_arrays()
		var colours: PackedColorArray = a[Mesh.ARRAY_COLOR]
		for i: int in colours.size():
			# The building shader darkens plain cells, so stalls start brighter to stay vivid.
			colours[i] = Color(minf(colours[i].r * PAINT_LIFT, 1.0), minf(colours[i].g * PAINT_LIFT, 1.0), minf(colours[i].b * PAINT_LIFT, 1.0))
		out.append({"v": a[Mesh.ARRAY_VERTEX], "n": a[Mesh.ARRAY_NORMAL], "c": colours})
	return out

# --- Small modelling helpers --------------------------------------------------------------

## A colour nudged a little in value and hue, so repeated pieces don't look painted from one tin.
static func _vary(c: Color, amount: float = 0.08) -> Color:
	var v: float = _rng.randf_range(-amount, amount)
	return Color(clampf(c.r + v + _rng.randf_range(-0.02, 0.02), 0.0, 1.0), clampf(c.g + v, 0.0, 1.0),
		clampf(c.b + v + _rng.randf_range(-0.02, 0.02), 0.0, 1.0))

## Quad a-b-c-d (a loop in either direction) whose front faces `out`.
static func _q(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
	if (b - a).cross(d - a).dot(out) < 0.0:
		MeshKit.quad(st, a, d, c, b, col)
	else:
		MeshKit.quad(st, a, b, c, d, col)

## Both sides of a thin sheet (cloth, board).
static func _sheet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n: Vector3 = (b - a).cross(d - a)
	_q(st, a, b, c, d, col, n)
	_q(st, a, b, c, d, col.darkened(0.12), -n)

## Upright solid of revolution: profile points are (radius, height) from `base`. Open at both ends
## unless the first / last radius is 0.
static func _lathe(st: SurfaceTool, base: Vector3, profile: PackedVector2Array, segs: int, col: Color) -> void:
	for k: int in range(1, profile.size()):
		var p0: Vector2 = profile[k - 1]
		var p1: Vector2 = profile[k]
		for s: int in segs:
			var a0: float = TAU * float(s) / float(segs)
			var a1: float = TAU * float(s + 1) / float(segs)
			var d0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
			var d1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
			var out: Vector3 = (d0 + d1).normalized()
			_q(st, base + d0 * p0.x + Vector3.UP * p0.y, base + d1 * p0.x + Vector3.UP * p0.y,
				base + d1 * p1.x + Vector3.UP * p1.y, base + d0 * p1.x + Vector3.UP * p1.y, col, out)

## A low-poly ball (a double cone pinched at the poles): tomatoes, onions, limes, flowers.
static func _ball(st: SurfaceTool, c: Vector3, r: float, col: Color, segs: int = 5) -> void:
	_lathe(st, c, PackedVector2Array([Vector2(0.0, -r), Vector2(r, -r * 0.1), Vector2(0.0, r)]), segs, col)

## Round produce heaped in a mound: a ring of balls under a smaller ring under a top one.
static func _heap(st: SurfaceTool, at: Vector3, col: Color, r: float = 0.07, spread: float = 0.2) -> void:
	var layers: Array = [[4, spread, 0.0], [1, 0.0, r * 1.6]]
	for layer: Array in layers:
		var n: int = int(layer[0])
		for i: int in n:
			var a: float = TAU * float(i) / float(n) + 0.4
			var p: Vector3 = at + Vector3(cos(a) * float(layer[1]), r + float(layer[2]), sin(a) * float(layer[1]))
			_ball(st, p, r * _rng.randf_range(0.85, 1.12), _vary(col, 0.07), 4)

## A woven basket: flared open bowl with a rim.
static func _basket(st: SurfaceTool, at: Vector3, r: float, h: float, col: Color = BASKET) -> void:
	_lathe(st, at, PackedVector2Array([Vector2(0.0, 0.0), Vector2(r * 0.7, 0.0), Vector2(r, h), Vector2(r * 1.05, h + 0.02)]), 6, _vary(col, 0.06))

## Bamboo / steel pole.
static func _pole(st: SurfaceTool, from: Vector3, to: Vector3, r: float, col: Color) -> void:
	MeshKit.tube(st, from, to, r, _vary(col, 0.05), 4)

## A tarp roof that sags between its four corners and ends in a folded hem on the road side, in
## stripes of `col` and a lighter shade (tarps and shade cloths on Chennai kerbs often are).
static func _tarp(st: SurfaceTool, col: Color, w: float, d: float, h_back: float, h_front: float, sag: float = 0.12) -> void:
	var nx: int = 6
	var nz: int = 3
	var pts: Array = []
	for iz: int in nz + 1:
		var row: Array[Vector3] = []
		var tz: float = float(iz) / float(nz)
		for ix: int in nx + 1:
			var tx: float = float(ix) / float(nx)
			var y: float = lerpf(h_back, h_front, tz) - sag * sin(PI * tx) * sin(PI * tz)
			row.append(Vector3((tx - 0.5) * w, y, (tz - 0.5) * d))
		pts.append(row)
	var light: Color = col.lerp(Color(0.95, 0.94, 0.9), 0.55)
	for iz: int in nz:
		for ix: int in nx:
			var c: Color = col if ix % 2 == 0 else light
			var r0: Array[Vector3] = pts[iz]
			var r1: Array[Vector3] = pts[iz + 1]
			_sheet(st, r0[ix], r0[ix + 1], r1[ix + 1], r1[ix], _vary(c, 0.03))
	# Folded hem: a short valance with a zig-zag lower edge.
	var front: Array[Vector3] = pts[nz]
	for ix: int in nx:
		var a: Vector3 = front[ix]
		var b: Vector3 = front[ix + 1]
		var drop: float = 0.24 if ix % 2 == 0 else 0.18
		_sheet(st, a, b, b + Vector3(0, -drop, 0.02), a + Vector3(0, -0.24 + 0.06 * float(ix % 2), 0.02), col if ix % 2 == 0 else light)

## Plastic crate with slatted sides (two slats a side) on a base.
static func _crate(st: SurfaceTool, at: Vector3, size: Vector3, col: Color) -> void:
	var c: Color = _vary(col, 0.05)
	MeshKit.box(st, at + Vector3(0, 0.02, 0), Vector3(size.x, 0.04, size.z), c.darkened(0.1))
	for y: float in [size.y * 0.4, size.y - 0.03]:
		MeshKit.box(st, at + Vector3(0, y, size.z * 0.5), Vector3(size.x, 0.06, 0.03), c)
		MeshKit.box(st, at + Vector3(0, y, -size.z * 0.5), Vector3(size.x, 0.06, 0.03), c)
		MeshKit.box(st, at + Vector3(size.x * 0.5, y, 0), Vector3(0.03, 0.06, size.z), c)
		MeshKit.box(st, at + Vector3(-size.x * 0.5, y, 0), Vector3(0.03, 0.06, size.z), c)
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			MeshKit.box(st, at + Vector3(size.x * sx, size.y * 0.5, size.z * sz), Vector3(0.04, size.y, 0.04), c.darkened(0.08))

## Hanging pan scale (thraasu) from a hook.
static func _scale(st: SurfaceTool, top: Vector3) -> void:
	_pole(st, top, top + Vector3(0, -0.25, 0), 0.008, STEEL)
	MeshKit.box(st, top + Vector3(0, -0.25, 0), Vector3(0.5, 0.025, 0.025), STEEL)
	for sx: float in [-0.23, 0.23]:
		_pole(st, top + Vector3(sx, -0.25, 0), top + Vector3(sx, -0.55, 0), 0.005, STEEL)
		_lathe(st, top + Vector3(sx, -0.58, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.11, 0.02), Vector2(0.13, 0.04)]), 8, STEEL.lightened(0.1))

## Garland hanging in a loop: small flowers along a sagging string.
static func _garland(st: SurfaceTool, a: Vector3, b: Vector3, drop: float, cols: Array[Color], count: int = 9) -> void:
	for i: int in count:
		var t: float = (float(i) + 0.5) / float(count)
		var p: Vector3 = a.lerp(b, t) + Vector3(0, -drop * sin(PI * t), 0)
		_ball(st, p, 0.04, cols[i % cols.size()], 3)

## Loose flowers piled on a leaf: a soft mound in the flower colour with a few heads on top.
static func _mound(st: SurfaceTool, at: Vector3, col: Color, r: float, h: float) -> void:
	_lathe(st, at, PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.85, h * 0.45), Vector2(r * 0.5, h * 0.85), Vector2(0.0, h)]), 8, _vary(col, 0.04))
	for k: int in 5:
		var a: float = TAU * float(k) / 5.0 + 0.3
		var d: float = r * (0.35 + 0.3 * float(k % 2))
		_ball(st, at + Vector3(cos(a) * d, h * (0.9 - d / r * 0.6), sin(a) * d), 0.035, _vary(col, 0.08), 4)

## A coil of jasmine string lying in a basket: a ring of small white buds.
static func _coil(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var n: int = maxi(7, int(r * 45.0))
	for k: int in n:
		var a: float = TAU * float(k) / float(n)
		_ball(st, c + Vector3(cos(a) * r, 0.0, sin(a) * r), 0.03, _vary(col, 0.03), 3)

## A pink lotus: a cup of pointed petals round a yellow centre.
static func _lotus(st: SurfaceTool, at: Vector3) -> void:
	var pink: Color = Color(0.96, 0.55, 0.7)
	for k: int in 6:
		var a: float = TAU * float(k) / 6.0
		var d: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var base: Vector3 = at + d * 0.02
		var tip: Vector3 = at + d * 0.07 + Vector3.UP * 0.08
		var side: Vector3 = Vector3(-d.z, 0.0, d.x) * 0.03
		_sheet(st, base - side, base + side, tip, tip, pink.lerp(Color.WHITE, 0.2 * float(k % 2)))
	_ball(st, at + Vector3.UP * 0.03, 0.025, Color(0.95, 0.8, 0.2), 4)

## A banana bunch: two tiers of curved fingers round a stalk.
static func _bananas(st: SurfaceTool, top: Vector3) -> void:
	_pole(st, top, top + Vector3(0, -0.5, 0), 0.02, Color(0.35, 0.3, 0.15))
	for k: int in 2:
		for i: int in 4:
			var a: float = TAU * float(i) / 4.0 + float(k) * 0.78
			var at: Vector3 = top + Vector3(cos(a) * 0.09, -0.16 - float(k) * 0.18, sin(a) * 0.09)
			MeshKit.box(st, at, Vector3(0.05, 0.05, 0.2), _vary(BANANA, 0.06), Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, -0.7))

# --- The stalls ----------------------------------------------------------------------------

## Vegetable stall: sloping table of baskets under a tarp, crates and sacks below, a hanging scale.
static func _vegetable(st: SurfaceTool, tarp: Color, wide: bool) -> void:
	var w: float = 3.2 if wide else 2.8
	for x: float in [-w * 0.5, w * 0.5]:
		_pole(st, Vector3(x, 0, -0.85), Vector3(x, 2.35, -0.85), 0.035, BAMBOO)
		_pole(st, Vector3(x, 0, 0.95), Vector3(x * 1.02, 2.1, 0.95), 0.035, BAMBOO)
	_pole(st, Vector3(-w * 0.5, 2.3, -0.85), Vector3(w * 0.5, 2.3, -0.85), 0.03, BAMBOO)
	_tarp(st, tarp, w + 0.5, 2.3, 2.45, 2.15)
	# Table: plank top sloping towards the road, legs, front skirt board.
	MeshKit.box(st, Vector3(0, 0.66, 0.1), Vector3(w - 0.2, 0.05, 1.3), WOOD_LIGHT, Basis(Vector3.RIGHT, 0.12))
	for x: float in [-w * 0.5 + 0.15, w * 0.5 - 0.15]:
		for z: float in [-0.45, 0.65]:
			_pole(st, Vector3(x, 0, z), Vector3(x, 0.64 + (0.05 if z < 0 else -0.06), z), 0.025, WOOD)
	MeshKit.box(st, Vector3(0, 0.45, 0.76), Vector3(w - 0.2, 0.3, 0.03), WOOD)
	var goods: Array[Color] = [TOMATO, CARROT, ONION, LIME, BRINJAL, TOMATO.darkened(0.12), Color(0.92, 0.85, 0.7), CARROT.darkened(0.1)]
	var cols: int = 4
	for i: int in 8:
		var x: float = (-0.5 + (float(i % cols) + 0.5) / float(cols)) * (w - 0.5)
		var z: float = -0.25 + float(i / cols) * 0.62
		var y: float = 0.7 - (z - 0.1) * 0.12
		_basket(st, Vector3(x, y, z), 0.27, 0.1)
		if i == 2 or i == 6:
			# Leafy greens: bundles of flat leaves.
			for k: int in 5:
				var a: float = TAU * float(k) / 5.0
				MeshKit.box(st, Vector3(x + cos(a) * 0.1, y + 0.12, z + sin(a) * 0.1), Vector3(0.08, 0.14, 0.16), _vary(LEAF, 0.08), Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.5))
		else:
			_heap(st, Vector3(x, y + 0.05, z), goods[i], 0.07, 0.12)
	# Hanging: bananas and a bunch of curry leaves at the back corners, the scale up front.
	_bananas(st, Vector3(w * 0.5 - 0.2, 2.2, -0.7))
	_scale(st, Vector3(0.5, 2.15, 0.55))
	# Under the table: crates, a jute sack of onions.
	_crate(st, Vector3(-0.7, 0, -0.1), Vector3(0.6, 0.32, 0.42), Color(0.15, 0.4, 0.75))
	_lathe(st, Vector3(-w * 0.5 + 0.35, 0, -0.55), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.2, 0.02), Vector2(0.24, 0.25), Vector2(0.18, 0.5), Vector2(0.08, 0.56)]), 7, Color(0.7, 0.58, 0.38))

## Fancy store: a pegboard of bangles, clips and toys, a counter of trays, stacked buckets.
static func _fancy(st: SurfaceTool, tarp: Color, umbrella: bool) -> void:
	var w: float = 2.8
	for x: float in [-w * 0.5, w * 0.5]:
		_pole(st, Vector3(x, 0, -0.75), Vector3(x, 2.45, -0.75), 0.035, STEEL)
		_pole(st, Vector3(x, 0, 0.8), Vector3(x, 2.25, 0.8), 0.035, STEEL)
	_tarp(st, tarp, w + 0.4, 2.0, 2.55, 2.3, 0.1)
	# Pegboard in a frame.
	MeshKit.box(st, Vector3(0, 1.35, -0.74), Vector3(w - 0.2, 1.9, 0.04), Color(0.93, 0.88, 0.78))
	for y: float in [0.4, 2.3]:
		MeshKit.box(st, Vector3(0, y, -0.71), Vector3(w - 0.1, 0.06, 0.06), WOOD)
	# Bangles on rods (rings of 6 short sides), hair clips and small toys.
	for row: int in 3:
		var y: float = 2.0 - float(row) * 0.5
		MeshKit.box(st, Vector3(0, y + 0.12, -0.66), Vector3(w - 0.4, 0.02, 0.02), STEEL)
		for i: int in 7:
			var c: Color = Color.from_hsv(fmod(float(i) * 0.13 + float(row) * 0.31, 1.0), 0.75, 0.95)
			var cx: float = -1.05 + float(i) * 0.35
			if row == 1:
				MeshKit.box(st, Vector3(cx, y, -0.66), Vector3(0.22, 0.3, 0.04), c) # Clip cards.
				MeshKit.box(st, Vector3(cx, y + 0.02, -0.63), Vector3(0.14, 0.05, 0.03), c.lightened(0.3))
			else:
				# A roll of glass bangles stacked on the rod.
				MeshKit.tube(st, Vector3(cx - 0.13, y + 0.04, -0.62), Vector3(cx + 0.13, y + 0.04, -0.62), 0.09, c, 6)
	# Counter with trays of goods and a glass top edge.
	MeshKit.box(st, Vector3(0, 0.35, 0.05), Vector3(w - 0.3, 0.7, 0.8), tarp.darkened(0.3))
	MeshKit.box(st, Vector3(0, 0.72, 0.05), Vector3(w - 0.2, 0.04, 0.9), WOOD_LIGHT)
	for i: int in 6:
		var c2: Color = Color.from_hsv(fmod(float(i) * 0.19, 1.0), 0.7, 1.0)
		var at: Vector3 = Vector3(-1.0 + float(i) * 0.4, 0.75, -0.05 + float(i % 2) * 0.3)
		MeshKit.box(st, at + Vector3(0, 0.02, 0), Vector3(0.32, 0.04, 0.26), Color(0.9, 0.9, 0.88))
		for k: int in 4:
			_ball(st, at + Vector3(-0.09 + float(k % 2) * 0.18, 0.07, -0.06 + float(k / 2) * 0.12), 0.04, _vary(c2, 0.1), 4)
	# Stacked plastic buckets and mugs at the side, balloons tied up front.
	for k: int in 3:
		_lathe(st, Vector3(w * 0.5 + 0.3, float(k) * 0.12, 0.4), PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.18, 0.3)]), 8, Color.from_hsv(0.55 + float(k) * 0.12, 0.7, 0.9))
	for i: int in 5:
		var top: Vector3 = Vector3(-1.1 + float(i) * 0.55, 2.0 + float(i % 2) * 0.12, 0.92)
		_pole(st, Vector3(top.x, 1.6, 0.85), top, 0.004, Color(0.9, 0.9, 0.9))
		_ball(st, top + Vector3(0, 0.12, 0), 0.12, Color.from_hsv(fmod(float(i) * 0.27 + 0.05, 1.0), 0.8, 1.0), 6)
	if umbrella:
		_umbrella(st, Vector3(-w * 0.5 - 0.5, 0, 0.6), 1.0, tarp)

## Petti kadai: a tin box shop on legs with a propped front flap, jars, hanging snack strips,
## a soda crate and a plastic stool.
static func _petti(st: SurfaceTool, paint: Color, blue_board: bool) -> void:
	var w: float = 2.2
	var body: Color = _vary(paint, 0.04)
	# Legs, body, back, sides and a roof with a lip.
	for x: float in [-w * 0.5 + 0.08, w * 0.5 - 0.08]:
		for z: float in [-0.85, 0.6]:
			MeshKit.box(st, Vector3(x, 0.15, z), Vector3(0.08, 0.3, 0.08), STEEL.darkened(0.2))
	MeshKit.box(st, Vector3(0, 0.65, -0.12), Vector3(w, 0.7, 1.5), body)
	MeshKit.box(st, Vector3(0, 1.0, 0.64), Vector3(w + 0.04, 0.06, 0.06), body.darkened(0.25)) # Counter lip.
	for x: float in [-w * 0.5, w * 0.5]:
		MeshKit.box(st, Vector3(x, 1.55, -0.12), Vector3(0.05, 1.1, 1.5), body)
	MeshKit.box(st, Vector3(0, 1.55, -0.86), Vector3(w, 1.1, 0.05), body.darkened(0.15))
	MeshKit.box(st, Vector3(0, 2.13, -0.12), Vector3(w + 0.12, 0.07, 1.62), body.darkened(0.3))
	# Painted name board along the top (generic colours, no text) and a stripe.
	var board: Color = Color(0.1, 0.3, 0.7) if blue_board else Color(0.85, 0.15, 0.12)
	MeshKit.box(st, Vector3(0, 2.38, 0.6), Vector3(w + 0.1, 0.42, 0.04), board)
	MeshKit.box(st, Vector3(0, 2.38, 0.625), Vector3(w - 0.3, 0.12, 0.02), Color(0.98, 0.9, 0.3))
	# The front flap propped open on two sticks.
	_sheet(st, Vector3(-w * 0.5, 2.1, 0.62), Vector3(w * 0.5, 2.1, 0.62), Vector3(w * 0.5, 2.2, 1.35), Vector3(-w * 0.5, 2.2, 1.35), body.darkened(0.1))
	for x: float in [-w * 0.5 + 0.1, w * 0.5 - 0.1]:
		_pole(st, Vector3(x, 1.02, 0.62), Vector3(x, 2.18, 1.3), 0.015, WOOD)
	# Shelves inside with cartons; jars with lids on the counter.
	for y: float in [1.35, 1.75]:
		MeshKit.box(st, Vector3(0, y, -0.55), Vector3(w - 0.1, 0.03, 0.55), WOOD_LIGHT)
		for i: int in 7:
			MeshKit.box(st, Vector3(-0.9 + float(i) * 0.3, y + 0.1, -0.6), Vector3(0.22, 0.18, 0.3), Color.from_hsv(fmod(float(i) * 0.21 + y, 1.0), 0.65, 0.9))
	for i: int in 6:
		var jar: Vector3 = Vector3(-0.85 + float(i) * 0.34, 1.03, 0.35)
		var fill: Color = Color.from_hsv(fmod(float(i) * 0.15 + 0.05, 1.0), 0.6, 0.85)
		_lathe(st, jar, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.0), Vector2(0.1, 0.22), Vector2(0.07, 0.27)]), 7, fill)
		_lathe(st, jar + Vector3(0, 0.27, 0), PackedVector2Array([Vector2(0.075, 0.0), Vector2(0.075, 0.05), Vector2(0.0, 0.06)]), 7, Color(0.85, 0.15, 0.12) if i % 2 == 0 else Color(0.95, 0.85, 0.2))
	# Snack sachet strips hanging from the flap, each a chain of small packets.
	for i: int in 8:
		var x2: float = -0.92 + float(i) * 0.26
		var c3: Color = Color.from_hsv(fmod(float(i) * 0.23, 1.0), 0.8, 0.95)
		for k: int in 4:
			MeshKit.box(st, Vector3(x2, 1.95 - float(k) * 0.14, 0.8 + float(k) * 0.02), Vector3(0.12, 0.12, 0.015), _vary(c3, 0.05))
	_bananas(st, Vector3(w * 0.5 - 0.15, 2.1, 1.0))
	# Soda crate with bottles, a red plastic stool.
	_crate(st, Vector3(0.75, 0, 1.0), Vector3(0.45, 0.3, 0.32), Color(0.85, 0.12, 0.12))
	for i: int in 6:
		var b: Vector3 = Vector3(0.6 + float(i % 3) * 0.15, 0.3, 0.92 + float(i / 3) * 0.15)
		_lathe(st, b, PackedVector2Array([Vector2(0.035, 0.0), Vector2(0.035, 0.12), Vector2(0.015, 0.2)]), 5, Color(0.15, 0.4, 0.2) if i % 2 == 0 else Color(0.3, 0.18, 0.1))
	_stool(st, Vector3(-0.7, 0, 1.15), Color(0.85, 0.15, 0.15))

## A moulded plastic stool.
static func _stool(st: SurfaceTool, at: Vector3, col: Color) -> void:
	MeshKit.box(st, at + Vector3(0, 0.44, 0), Vector3(0.34, 0.04, 0.34), col)
	for sx: float in [-0.14, 0.14]:
		for sz: float in [-0.14, 0.14]:
			_pole(st, at + Vector3(sx * 1.2, 0, sz * 1.2), at + Vector3(sx, 0.43, sz), 0.02, col.darkened(0.1))

## The big striped vendor umbrella on a pole (10 panels, alternating colours).
static func _umbrella(st: SurfaceTool, at: Vector3, r: float, col: Color) -> void:
	_pole(st, at, at + Vector3(0, 2.35, 0), 0.025, STEEL)
	var apex: Vector3 = at + Vector3(0, 2.6, 0)
	var light: Color = Color(0.97, 0.95, 0.9)
	for i: int in 10:
		var a0: float = TAU * float(i) / 10.0
		var a1: float = TAU * float(i + 1) / 10.0
		var p0: Vector3 = at + Vector3(cos(a0) * r, 2.15, sin(a0) * r)
		var p1: Vector3 = at + Vector3(cos(a1) * r, 2.15, sin(a1) * r)
		var c: Color = col if i % 2 == 0 else light
		var n: Vector3 = (p1 - apex).cross(p0 - apex)
		if n.y < 0.0:
			n = -n
		st.set_color(c)
		st.set_smooth_group(-1)
		# Both sides: seen from under it on the kerb and from above in the chase camera.
		for tri: Array in [[apex, p1, p0], [apex, p0, p1]]:
			st.add_vertex(tri[0] as Vector3)
			st.add_vertex(tri[1] as Vector3)
			st.add_vertex(tri[2] as Vector3)

## Flower cart: a wooden cart on two spoked wheels under a striped umbrella, heaps of jasmine,
## marigold and roses, garlands hanging in loops from a rail.
static func _flower(st: SurfaceTool, cloth: Color) -> void:
	var w: float = 2.2
	# Cart bed with plank sides and handles towards the back.
	MeshKit.box(st, Vector3(0, 0.78, 0), Vector3(w, 0.06, 1.1), WOOD_LIGHT)
	for z: float in [-0.55, 0.55]:
		MeshKit.box(st, Vector3(0, 0.88, z), Vector3(w, 0.16, 0.04), WOOD)
	for x: float in [-w * 0.5, w * 0.5]:
		MeshKit.box(st, Vector3(x, 0.88, 0), Vector3(0.04, 0.16, 1.1), WOOD)
	for z: float in [-0.4, 0.4]:
		_pole(st, Vector3(-w * 0.5, 0.82, z), Vector3(-w * 0.5 - 0.7, 0.95, z), 0.025, WOOD)
	# Two spoked wheels with a rim and hub, and a prop leg at the handle end.
	for z: float in [-0.62, 0.62]:
		var hub: Vector3 = Vector3(0.35, 0.42, z)
		for k: int in 12:
			var a0: float = TAU * float(k) / 12.0
			var a1: float = TAU * float(k + 1) / 12.0
			MeshKit.tube(st, hub + Vector3(cos(a0), sin(a0), 0) * 0.4, hub + Vector3(cos(a1), sin(a1), 0) * 0.4, 0.025, Color(0.15, 0.13, 0.12), 3)
			if k % 3 == 0:
				MeshKit.tube(st, hub, hub + Vector3(cos(a0), sin(a0), 0) * 0.38, 0.012, WOOD, 3)
		MeshKit.tube(st, hub + Vector3(0, 0, -0.05), hub + Vector3(0, 0, 0.05), 0.05, STEEL, 6)
	_pole(st, Vector3(-w * 0.5 + 0.1, 0, 0), Vector3(-w * 0.5 + 0.1, 0.78, 0), 0.03, WOOD)
	# Nov 27 (owner: "the flower stalls can be even more realistic"), modelled on the Mylapore
	# kerb sellers: coiled strings of jasmine (malli) in flat baskets, heaps of marigold, roses and
	# kanakambaram on banana leaves, a few pink lotuses, and a curtain of garlands hanging in
	# strands from the front rail with a tassel at each end.
	var heaps: Array[Color] = [GARLAND[1], GARLAND[2], Color(0.98, 0.5, 0.2), GARLAND[3]]
	for i: int in 4:
		var at: Vector3 = Vector3(-0.8 + float(i % 2) * 0.55, 0.82, -0.25 + float(i / 2) * 0.48)
		MeshKit.box(st, at + Vector3(0, 0.005, 0), Vector3(0.5, 0.01, 0.4), _vary(LEAF, 0.05))
		_mound(st, at, heaps[i], 0.2, 0.12)
	for i: int in 2:
		var bc: Vector3 = Vector3(0.45, 0.82, -0.22 + float(i) * 0.46)
		_basket(st, bc, 0.28, 0.06)
		_coil(st, bc + Vector3(0, 0.07, 0), 0.2, GARLAND[0])
		_coil(st, bc + Vector3(0, 0.1, 0), 0.12, GARLAND[0].darkened(0.05))
	for i: int in 3:
		_lotus(st, Vector3(0.85, 0.84, -0.3 + float(i) * 0.3))
	# Front rail and the garland curtain.
	for x: float in [-w * 0.5 + 0.05, w * 0.5 - 0.05]:
		_pole(st, Vector3(x, 0.8, 0.5), Vector3(x, 1.8, 0.5), 0.02, BAMBOO)
	_pole(st, Vector3(-w * 0.5, 1.8, 0.5), Vector3(w * 0.5, 1.8, 0.5), 0.02, BAMBOO)
	for i: int in 9:
		var x: float = -w * 0.5 + 0.15 + float(i) * (w - 0.3) / 8.0
		var c0: Color = GARLAND[i % 4]
		var c1: Color = GARLAND[(i + 2) % 4]
		var drop: int = 6 + 2 * ((i * 7) % 2)
		# A thick rope of flowers in coloured bands, a rounded end and a tassel.
		for k: int in drop / 2:
			var y0: float = 1.78 - float(k) * 0.18
			MeshKit.tube(st, Vector3(x, y0, 0.53), Vector3(x + 0.006 * float(k % 2), y0 - 0.18, 0.53), 0.036,
				_vary(c0 if k % 2 == 0 else c1, 0.04), 6)
		var end_y: float = 1.78 - float(drop / 2) * 0.18
		_ball(st, Vector3(x, end_y, 0.53), 0.04, c1, 5)
		MeshKit.box(st, Vector3(x, end_y - 0.07, 0.53), Vector3(0.025, 0.08, 0.01), Color(0.95, 0.75, 0.2))
	_umbrella(st, Vector3(0.0, 0.0, -0.2), 1.35, cloth)
