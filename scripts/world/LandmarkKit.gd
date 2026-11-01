class_name LandmarkKit
extends RefCounted
## Procedural Chennai landmarks (vertex-coloured, one material, one draw call each).
## Used where no commercially usable model exists: the free Marina lighthouse and temple
## models on Sketchfab are CC BY-NC (no commercial use), so these are built in code instead.

static var _material: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.85
	return _material

## Marina lighthouse: a tall banded red-and-white tower on a museum base, with the viewing
## gallery, lantern room and dome on top (~46 m, like the real one).
static func lighthouse() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var red: Color = Color(0.78, 0.13, 0.12)
	var white: Color = Color(0.95, 0.94, 0.9)
	var stone: Color = Color(0.82, 0.78, 0.7)
	# Museum base: two storeys, octagonal.
	_prism(st, 8, 7.0, 6.8, 0.0, 4.0, stone, true)
	_prism(st, 8, 7.3, 7.3, 4.0, 4.4, white, true)
	_prism(st, 8, 6.1, 5.9, 4.4, 8.6, stone, true)
	_prism(st, 8, 6.3, 6.3, 8.6, 9.0, white, true)
	# Tower: rounded triangle in plan, tapering, in alternating bands.
	var bands: int = 9
	var y0: float = 9.0
	var y1: float = 41.0
	for b: int in bands:
		var ya: float = lerpf(y0, y1, float(b) / float(bands))
		var yb: float = lerpf(y0, y1, float(b + 1) / float(bands))
		var ra: float = lerpf(4.2, 3.2, float(b) / float(bands))
		var rb: float = lerpf(4.2, 3.2, float(b + 1) / float(bands))
		_tri_tower(st, ra, rb, ya, yb, red if b % 2 == 0 else white)
	# Gallery deck + railing posts, lantern, dome, finial.
	_prism(st, 12, 5.0, 5.0, 41.0, 41.6, white, true)
	for k: int in 16:
		var a: float = TAU * float(k) / 16.0
		MeshKit.box(st, Vector3(cos(a) * 4.8, 42.2, sin(a) * 4.8), Vector3(0.12, 1.2, 0.12), red)
	_prism(st, 12, 4.9, 4.9, 42.7, 42.85, red, false)
	_prism(st, 10, 2.6, 2.6, 41.6, 42.6, white, true)
	_prism(st, 10, 2.2, 2.2, 42.6, 45.2, Color(0.2, 0.3, 0.32), false)
	for k: int in 10:
		var a2: float = TAU * float(k) / 10.0
		MeshKit.box(st, Vector3(cos(a2) * 2.25, 43.9, sin(a2) * 2.25), Vector3(0.14, 2.6, 0.14), white)
	_prism(st, 10, 2.5, 0.4, 45.2, 47.2, red, true)
	MeshKit.tube(st, Vector3(0, 47.2, 0), Vector3(0, 48.6, 0), 0.08, Color(0.2, 0.2, 0.2), 6)
	return MeshKit.finish(st, material())

## Kapaleeshwarar-style gopuram: granite base with the doorway, seven tapering painted tiers
## with cornices, the barrel-vault crown and a row of golden kalasams (~37 m).
static func gopuram() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var granite: Color = Color(0.62, 0.6, 0.56)
	var w: float = 24.0
	var d: float = 14.0
	MeshKit.box(st, Vector3(0, 0.5, 0), Vector3(w + 1.5, 1.0, d + 1.5), granite.darkened(0.15))
	MeshKit.box(st, Vector3(0, 5.5, 0), Vector3(w, 9.0, d), granite)
	MeshKit.box(st, Vector3(0, 10.4, 0), Vector3(w + 0.8, 0.8, d + 0.8), granite.lightened(0.15))
	# Doorway (dark recess) on both long faces.
	for s: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0, 4.2, s * (d * 0.5 + 0.02)), Vector3(4.0, 7.6, 0.1), Color(0.12, 0.08, 0.06))
		MeshKit.box(st, Vector3(0, 8.4, s * (d * 0.5 + 0.06)), Vector3(5.0, 0.6, 0.2), Color(0.9, 0.75, 0.3))
	var palette: Array[Color] = [Color(0.95, 0.55, 0.6), Color(0.45, 0.7, 0.9), Color(0.98, 0.85, 0.35),
		Color(0.5, 0.8, 0.55), Color(0.95, 0.62, 0.3), Color(0.7, 0.55, 0.85), Color(0.95, 0.9, 0.8)]
	var tiers: int = 7
	var y: float = 10.8
	var tw: float = w - 1.0
	var td: float = d - 1.0
	for t: int in tiers:
		var h: float = 3.4 - float(t) * 0.12
		var nw: float = tw - 2.2
		var nd: float = td - 1.1
		var col: Color = palette[t % palette.size()]
		_frustum(st, tw, td, nw + 0.6, nd + 0.3, y, y + h, col)
		# Niches: darker bays on the long faces give the sculpted rhythm.
		var niches: int = maxi(3, int(nw / 2.6))
		for k: int in niches:
			var x: float = lerpf(-nw * 0.4, nw * 0.4, float(k) / float(maxi(niches - 1, 1)))
			for s2: float in [-1.0, 1.0]:
				MeshKit.box(st, Vector3(x, y + h * 0.45, s2 * (lerpf(td, nd, 0.45) * 0.5 + 0.05)), Vector3(0.9, h * 0.55, 0.12),
					palette[(t + k + 3) % palette.size()].darkened(0.1))
		# Cornice.
		MeshKit.box(st, Vector3(0, y + h + 0.15, 0), Vector3(nw + 1.0, 0.3, nd + 0.6), Color(0.96, 0.92, 0.82))
		y += h + 0.3
		tw = nw
		td = nd
	# Barrel-vault crown (shala) along the long axis, with the kalasams on its ridge.
	var crown_w: float = tw
	var crown_r: float = td * 0.5
	var rings: Array[PackedVector3Array] = []
	for side: float in [-1.0, 1.0]:
		var ring: PackedVector3Array = PackedVector3Array()
		for k: int in 9:
			var a: float = PI * float(k) / 8.0
			ring.append(Vector3(side * crown_w * 0.5, y + sin(a) * crown_r * 1.2, cos(a) * crown_r))
		rings.append(ring)
	MeshKit.loft(st, rings, Color(0.98, 0.7, 0.35), false, true, true, true)
	var gold: Color = Color(0.95, 0.75, 0.2)
	var n: int = 9
	for k: int in n:
		var x2: float = lerpf(-crown_w * 0.42, crown_w * 0.42, float(k) / float(n - 1))
		var top: float = y + crown_r * 1.2
		MeshKit.tube(st, Vector3(x2, top - 0.2, 0), Vector3(x2, top + 0.9, 0), 0.28, gold, 6)
		MeshKit.tube(st, Vector3(x2, top + 0.9, 0), Vector3(x2, top + 1.6, 0), 0.1, gold, 6)
	# Granite entrance piers, cream lintels and niches remain inside the reserved plot.
	for side: float in [-1.0, 1.0]:
		for x: float in [-3.0, 3.0]:
			MeshKit.box(st, Vector3(x, 4.0, side * 7.3), Vector3(0.65, 7.8, 0.6), granite.lightened(0.12))
	# Abstract sculptural reliefs: alternating seated forms in the existing painted tiers.
	for row: int in 6:
		var relief_y: float = 12.0 + float(row) * 3.0
		var half_w: float = 9.0 - float(row) * 1.0
		var depth: float = 6.4 - float(row) * 0.55
		for k: int in 5:
			var relief_x: float = lerpf(-half_w, half_w, float(k) / 4.0)
			for side: float in [-1.0, 1.0]:
				var col: Color = palette[(row + k + 2) % palette.size()]
				MeshKit.box(st, Vector3(relief_x, relief_y, side * depth), Vector3(0.7, 0.8, 0.5), col)
				MeshKit.box(st, Vector3(relief_x, relief_y + 0.65, side * depth), Vector3(0.4, 0.4, 0.4), col.lightened(0.12))
	return MeshKit.finish(st, material())

## Regular n-sided prism (or frustum) between y0 and y1.
static func _prism(st: SurfaceTool, sides: int, r0: float, r1: float, y0: float, y1: float, col: Color, cap: bool) -> void:
	var a: PackedVector3Array = PackedVector3Array()
	var b: PackedVector3Array = PackedVector3Array()
	for k: int in sides:
		var ang: float = -TAU * float(k) / float(sides)
		a.append(Vector3(cos(ang) * r0, y0, sin(ang) * r0))
		b.append(Vector3(cos(ang) * r1, y1, sin(ang) * r1))
	MeshKit.loft(st, [a, b], col, true, false, cap, true)

## Rounded-triangle tower section (the lighthouse's plan).
static func _tri_tower(st: SurfaceTool, r0: float, r1: float, y0: float, y1: float, col: Color) -> void:
	var a: PackedVector3Array = PackedVector3Array()
	var b: PackedVector3Array = PackedVector3Array()
	for k: int in 15:
		var ang: float = -TAU * float(k) / 15.0
		# Radius swells at three corners: a soft triangle.
		var swell: float = 1.0 + 0.16 * cos(3.0 * ang)
		a.append(Vector3(cos(ang) * r0 * swell, y0, sin(ang) * r0 * swell))
		b.append(Vector3(cos(ang) * r1 * swell, y1, sin(ang) * r1 * swell))
	MeshKit.loft(st, [a, b], col, true, false, false, true)

## Box tapering from (w0, d0) at y0 to (w1, d1) at y1, with a top cap.
static func _frustum(st: SurfaceTool, w0: float, d0: float, w1: float, d1: float, y0: float, y1: float, col: Color) -> void:
	var c0: Array[Vector3] = [Vector3(-w0 * 0.5, y0, -d0 * 0.5), Vector3(w0 * 0.5, y0, -d0 * 0.5), Vector3(w0 * 0.5, y0, d0 * 0.5), Vector3(-w0 * 0.5, y0, d0 * 0.5)]
	var c1: Array[Vector3] = [Vector3(-w1 * 0.5, y1, -d1 * 0.5), Vector3(w1 * 0.5, y1, -d1 * 0.5), Vector3(w1 * 0.5, y1, d1 * 0.5), Vector3(-w1 * 0.5, y1, d1 * 0.5)]
	for k: int in 4:
		var j: int = (k + 1) % 4
		var shade: Color = col if k % 2 == 1 else col.darkened(0.08)
		MeshKit.quad(st, c0[k], c0[j], c1[j], c1[k], shade)
	MeshKit.quad(st, c1[0], c1[1], c1[2], c1[3], col.lightened(0.1))

## Architectural approximation within the existing landmark footprint.
## Window grids and recessed bands provide depth without extra materials.
static func lic_building() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var stone: Color = Color(0.72, 0.72, 0.67)
	var glass: Color = Color(0.19, 0.29, 0.32)
	MeshKit.box(st, Vector3(0, 27, 0), Vector3(18, 54, 18), stone)
	for floor_i: int in 14:
		var y: float = 2.0 + float(floor_i) * 3.65
		for side: float in [-1.0, 1.0]:
			MeshKit.box(st, Vector3(0, y, side * 9.025), Vector3(16.8, 2.7, 0.05), glass)
			MeshKit.box(st, Vector3(0, y - 1.45, side * 9.16), Vector3(18.2, 0.3, 0.32), stone.lightened(0.08))
			for bay: int in 9:
				MeshKit.box(st, Vector3(-8.0 + float(bay) * 2.0, y, side * 9.11), Vector3(0.16, 2.9, 0.18), stone)
	MeshKit.box(st, Vector3(0, 54.3, 0), Vector3(18.5, 0.6, 18.5), stone)
	return MeshKit.finish(st, material())

## Vivekananda House approximation: curved pink frontage, cream cornices and dark
## recessed openings. Dimensions intentionally fit the existing reserved plot.
static func vivekananda_house() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var pink: Color = Color(0.76, 0.43, 0.39)
	var cream: Color = Color(0.89, 0.83, 0.71)
	var recess: Color = Color(0.17, 0.13, 0.12)
	MeshKit.box(st, Vector3(0, 4.5, 0), Vector3(28, 9, 12), pink)
	_prism(st, 20, 8.5, 8.5, 0.0, 9.0, pink, true)
	for y: float in [0.4, 4.5, 8.9]:
		_prism(st, 20, 8.75, 8.75, y, y + 0.3, cream, true)
		MeshKit.box(st, Vector3(0, y + 0.15, 0), Vector3(28.4, 0.3, 12.3), cream)
	for k: int in 11:
		var a: float = PI + float(k) * PI / 10.0
		var outward: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var basis: Basis = Basis(Vector3.UP, PI * 0.5 - a)
		for y: float in [2.3, 6.7]:
			MeshKit.box(st, outward * 8.51 + Vector3(0, y, 0), Vector3(1.2, 2.6, 0.08), recess, basis)
			MeshKit.box(st, outward * 8.64 + Vector3(0, y + 1.42, 0), Vector3(1.5, 0.24, 0.3), cream, basis)
	return MeshKit.finish(st, material())


## Repeating white arch ribs on each side of the existing road corridor.
## There is no new deck or collision across the road surface.
static func napier_bridge() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var white: Color = Color(0.84, 0.83, 0.78)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(side * 9.0, 0.65, 0), Vector3(0.65, 1.1, 40), white)
		for span: int in 4:
			var start_z: float = -20.0 + float(span) * 10.0
			var previous: Vector3 = Vector3(side * 9.0, 0.8, start_z)
			for segment: int in range(1, 13):
				var t: float = float(segment) / 12.0
				var next: Vector3 = Vector3(side * 9.0, 0.8 + sin(t * PI) * 4.2, start_z + t * 10.0)
				MeshKit.tube(st, previous, next, 0.28, white, 5)
				previous = next
			for post: int in range(1, 5):
				var t: float = float(post) / 5.0
				var h: float = sin(t * PI) * 4.2
				MeshKit.box(st, Vector3(side * 9.0, 0.8 + h * 0.5, start_z + t * 10.0), Vector3(0.16, h, 0.16), white)
	return MeshKit.finish(st, material())
