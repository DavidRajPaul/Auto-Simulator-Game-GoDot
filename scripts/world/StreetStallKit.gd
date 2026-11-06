class_name StreetStallKit
extends RefCounted
## Chennai kerb stalls as plain triangles, merged into each chunk's building mesh. +Z faces the
## road, y = 0 is the pavement. Keep them under ~400 triangles: the city carries about 1,500.
## Types: 0-1 vegetable, 2-3 fancy store, 4-5 petti kadai, 6 flower cart.
const PAINT_LIFT: float = 1.5
const WOOD: Color = Color(0.4, 0.26, 0.15)
const STEEL: Color = Color(0.4, 0.42, 0.45)
const LEAF: Color = Color(0.22, 0.55, 0.22)
const TOMATO: Color = Color(0.82, 0.14, 0.1)
const CARROT: Color = Color(0.93, 0.48, 0.1)
const ONION: Color = Color(0.68, 0.3, 0.38)
const BRINJAL: Color = Color(0.3, 0.12, 0.42)
const BANANA: Color = Color(0.93, 0.8, 0.22)
const COCONUT: Color = Color(0.42, 0.28, 0.14)
const GARLAND: Array[Color] = [Color(0.98, 0.96, 0.86), Color(0.96, 0.55, 0.1), Color(0.9, 0.2, 0.3), Color(0.98, 0.85, 0.2)]
const TARP: Array[Color] = [Color(0.12, 0.35, 0.72), Color(0.14, 0.5, 0.3), Color(0.85, 0.2, 0.5), Color(0.95, 0.72, 0.1), Color(0.1, 0.42, 0.62), Color(0.16, 0.5, 0.36), Color(0.82, 0.25, 0.3)]

static func arrays() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: int in 7:
		var st: SurfaceTool = MeshKit.begin()
		match kind:
			0, 1: _vegetable(st, TARP[kind])
			2, 3: _fancy(st, TARP[kind])
			4, 5: _petti(st, TARP[kind])
			_: _flower(st, TARP[kind])
		st.generate_normals()
		var a: Array = st.commit_to_arrays()
		var colours: PackedColorArray = a[Mesh.ARRAY_COLOR]
		for i: int in colours.size():
			# The building shader darkens plain cells, so stalls start brighter to stay vivid.
			colours[i] = Color(minf(colours[i].r * PAINT_LIFT, 1.0), minf(colours[i].g * PAINT_LIFT, 1.0), minf(colours[i].b * PAINT_LIFT, 1.0))
		out.append({"v": a[Mesh.ARRAY_VERTEX], "n": a[Mesh.ARRAY_NORMAL], "c": colours})
	return out

static func _canopy(st: SurfaceTool, colour: Color, w: float, d: float, h: float) -> void:
	for x: float in [-w * 0.5, w * 0.5]:
		for z: float in [-d * 0.5, d * 0.5]:
			MeshKit.box(st, Vector3(x, h * 0.5, z), Vector3(0.06, h, 0.06), STEEL)
	MeshKit.box(st, Vector3(0, h + 0.08, 0), Vector3(w + 0.5, 0.04, d + 0.5), colour, Basis(Vector3.RIGHT, 0.1))

## A small heap of one vegetable: a stepped mound keeps the triangle count low.
static func _heap(st: SurfaceTool, at: Vector3, colour: Color) -> void:
	MeshKit.box(st, at + Vector3(0, 0.05, 0), Vector3(0.46, 0.1, 0.4), colour)
	MeshKit.box(st, at + Vector3(0, 0.14, 0), Vector3(0.3, 0.1, 0.26), colour.lightened(0.08))

static func _vegetable(st: SurfaceTool, tarp: Color) -> void:
	_canopy(st, tarp, 3.0, 1.9, 2.4)
	MeshKit.box(st, Vector3(0, 0.62, 0.1), Vector3(2.8, 0.08, 1.3), WOOD)
	for x: float in [-1.3, 1.3]:
		MeshKit.box(st, Vector3(x, 0.3, 0.1), Vector3(0.08, 0.6, 1.2), WOOD)
	var goods: Array[Color] = [TOMATO, CARROT, ONION, LEAF, BRINJAL, TOMATO.darkened(0.15), LEAF.lightened(0.2), CARROT.darkened(0.1)]
	for i: int in 8:
		_heap(st, Vector3(-1.05 + (i % 4) * 0.7, 0.66, -0.25 + (i / 4) * 0.62), goods[i])
	MeshKit.box(st, Vector3(1.35, 1.65, -0.8), Vector3(0.1, 0.9, 0.3), BANANA) # Hanging bananas.
	MeshKit.box(st, Vector3(-1.35, 1.75, -0.8), Vector3(0.3, 0.5, 0.3), LEAF)
	for i: int in 3:
		MeshKit.box(st, Vector3(-0.9 + i * 0.9, 0.2, -0.75), Vector3(0.7, 0.4, 0.4), Color(0.72, 0.6, 0.4)) # Crates.
	MeshKit.tube(st, Vector3(0.4, 0.7, 0.72), Vector3(0.4, 1.15, 0.72), 0.015, STEEL, 4) # Scale.
	MeshKit.box(st, Vector3(0.4, 1.15, 0.72), Vector3(0.5, 0.02, 0.02), STEEL)

static func _fancy(st: SurfaceTool, tarp: Color) -> void:
	_canopy(st, tarp, 2.8, 1.6, 2.5)
	MeshKit.box(st, Vector3(0, 1.3, -0.72), Vector3(2.6, 2.1, 0.06), Color(0.95, 0.9, 0.82)) # Pegboard.
	MeshKit.box(st, Vector3(0, 0.6, 0.0), Vector3(2.5, 0.06, 0.9), WOOD)
	MeshKit.box(st, Vector3(0, 0.3, 0.0), Vector3(2.4, 0.6, 0.8), tarp.darkened(0.25))
	for row: int in 3:
		for i: int in 8:
			var c: Color = Color.from_hsv(fmod(float(i) * 0.13 + float(row) * 0.31, 1.0), 0.75, 0.95)
			MeshKit.box(st, Vector3(-1.1 + i * 0.32, 1.95 - row * 0.5, -0.67), Vector3(0.24, 0.34, 0.05), c) # Bangles, clips, toys.
	for i: int in 7:
		var c: Color = Color.from_hsv(fmod(float(i) * 0.19, 1.0), 0.7, 1.0)
		MeshKit.box(st, Vector3(-1.05 + i * 0.35, 0.72, 0.0 + (i % 2) * 0.2), Vector3(0.26, 0.18, 0.24), c) # Trays.
	for i: int in 5:
		var at: Vector3 = Vector3(-1.2 + i * 0.6, 2.25, 0.72)
		MeshKit.box(st, at, Vector3(0.2, 0.26, 0.2), Color.from_hsv(fmod(float(i) * 0.27 + 0.05, 1.0), 0.8, 1.0)) # Balloons.

static func _petti(st: SurfaceTool, paint: Color) -> void:
	MeshKit.box(st, Vector3(0, 0.5, -0.1), Vector3(2.2, 1.0, 1.7), paint)
	MeshKit.box(st, Vector3(-1.05, 1.5, -0.1), Vector3(0.1, 1.0, 1.7), paint)
	MeshKit.box(st, Vector3(1.05, 1.5, -0.1), Vector3(0.1, 1.0, 1.7), paint)
	MeshKit.box(st, Vector3(0, 1.5, -0.92), Vector3(2.2, 1.0, 0.08), paint.darkened(0.15))
	MeshKit.box(st, Vector3(0, 2.06, -0.1), Vector3(2.4, 0.12, 1.9), paint.darkened(0.3))
	MeshKit.box(st, Vector3(0, 2.0, 1.1), Vector3(2.2, 0.04, 0.9), Color(0.85, 0.2, 0.15), Basis(Vector3.RIGHT, 0.22)) # Flap.
	MeshKit.box(st, Vector3(0, 1.02, 0.45), Vector3(2.1, 0.04, 0.55), Color(0.86, 0.84, 0.8))
	for i: int in 6:
		MeshKit.tube(st, Vector3(-0.9 + i * 0.36, 1.05, 0.45), Vector3(-0.9 + i * 0.36, 1.32, 0.45), 0.07, Color.from_hsv(float(i) * 0.15, 0.2 + float(i % 2) * 0.6, 0.9), 5) # Jars.
	for i: int in 9:
		MeshKit.box(st, Vector3(-0.95 + i * 0.24, 1.75 - float(i % 2) * 0.12, 0.72), Vector3(0.14, 0.34, 0.03), Color.from_hsv(fmod(float(i) * 0.23, 1.0), 0.8, 0.95)) # Snack strips.
	MeshKit.box(st, Vector3(0.7, 0.42, 0.72), Vector3(0.5, 0.84, 0.4), Color(0.85, 0.12, 0.12)) # Soda crate.

static func _flower(st: SurfaceTool, tarp: Color) -> void:
	_canopy(st, tarp, 2.4, 1.4, 2.3)
	MeshKit.box(st, Vector3(0, 0.72, 0), Vector3(2.2, 0.08, 1.1), WOOD)
	MeshKit.box(st, Vector3(0, 0.34, 0), Vector3(2.0, 0.68, 0.06), WOOD)
	for i: int in 8:
		MeshKit.box(st, Vector3(-0.9 + (i % 4) * 0.6, 0.82, -0.25 + (i / 4) * 0.5), Vector3(0.5, 0.12, 0.42), GARLAND[i % GARLAND.size()])
	for i: int in 7:
		for k: int in 3:
			MeshKit.box(st, Vector3(-0.9 + i * 0.3, 2.05 - k * 0.2, 0.6), Vector3(0.1, 0.18, 0.1), GARLAND[(i + k) % GARLAND.size()])
