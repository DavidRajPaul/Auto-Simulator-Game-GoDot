class_name PersonMesh
extends RefCounted
## Low-poly Chennai people built from MeshKit primitives with vertex colours: one shared
## material, one draw call per person, ~300–500 triangles. Used for scooter riders (seated)
## and roadside passengers (standing, waving). Meshes are cached per (pose, style, variant)
## so a pool of 18 riders shares a handful of ArrayMeshes.
##
## Coordinates: origin on the ground between the feet (standing) or on the seat (seated);
## forward is -Z, like every vehicle in the game.

enum Style { SHIRT_TROUSERS, VESHTI, SAREE, TSHIRT_JEANS, TOURIST }

const SKIN_TONES: Array[Color] = [Color(0.45, 0.3, 0.2), Color(0.55, 0.37, 0.25), Color(0.36, 0.24, 0.16), Color(0.62, 0.44, 0.31)]
const SHIRTS: Array[Color] = [Color(0.92, 0.92, 0.88), Color(0.35, 0.55, 0.85), Color(0.75, 0.2, 0.2), Color(0.2, 0.5, 0.3), Color(0.95, 0.75, 0.3), Color(0.5, 0.3, 0.6)]
const SAREES: Array[Color] = [Color(0.8, 0.1, 0.35), Color(0.95, 0.55, 0.1), Color(0.15, 0.45, 0.4), Color(0.55, 0.15, 0.55)]
const HELMETS: Array[Color] = [Color(0.1, 0.1, 0.12), Color(0.85, 0.85, 0.85), Color(0.75, 0.1, 0.1), Color(0.15, 0.3, 0.7)]
const HAIR: Color = Color(0.06, 0.05, 0.05)
const TROUSER: Color = Color(0.18, 0.2, 0.28)
const JEANS: Color = Color(0.2, 0.3, 0.5)
const VESHTI_WHITE: Color = Color(0.95, 0.94, 0.88)
const SANDAL: Color = Color(0.22, 0.14, 0.08)

static var _cache: Dictionary = {}
static var _material: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.85
	return _material

## Rider on a scooter/bike. Origin = seat top centre. `variant` picks colours.
static func seated_rider(variant: int) -> ArrayMesh:
	var key: String = "rider_%d" % (variant % 16)
	if _cache.has(key):
		return _cache[key]
	var skin: Color = SKIN_TONES[variant % SKIN_TONES.size()]
	var shirt: Color = SHIRTS[(variant / 2) % SHIRTS.size()]
	var helmet: Color = HELMETS[(variant / 3) % HELMETS.size()]
	var st: SurfaceTool = MeshKit.begin()
	# Hips on the seat, thighs forward, shins down to the footboard.
	for side: float in [-1.0, 1.0]:
		var hip: Vector3 = Vector3(0.11 * side, 0.08, 0.02)
		var knee: Vector3 = Vector3(0.16 * side, 0.12, -0.38)
		var foot: Vector3 = Vector3(0.15 * side, -0.38, -0.42)
		MeshKit.tube(st, hip, knee, 0.075, TROUSER, 6)
		MeshKit.tube(st, knee, foot, 0.06, TROUSER, 6)
		MeshKit.box(st, foot + Vector3(0, -0.02, -0.06), Vector3(0.1, 0.06, 0.2), SANDAL)
	# Torso leaning slightly forward.
	var lean: Basis = Basis(Vector3.RIGHT, -0.18)
	_torso(st, Vector3(0, 0.05, 0.04), lean, 0.5, shirt)
	var shoulder_y: float = 0.52
	for side: float in [-1.0, 1.0]:
		var sh: Vector3 = Vector3(0.21 * side, shoulder_y, -0.04)
		var elbow: Vector3 = Vector3(0.25 * side, shoulder_y - 0.2, -0.26)
		var hand: Vector3 = Vector3(0.3 * side, shoulder_y - 0.18, -0.5)
		MeshKit.tube(st, sh, elbow, 0.05, shirt, 6)
		MeshKit.tube(st, elbow, hand, 0.042, skin, 6)
	# Neck, head and full-face helmet with a dark visor.
	MeshKit.tube(st, Vector3(0, shoulder_y - 0.02, -0.06), Vector3(0, shoulder_y + 0.1, -0.08), 0.05, skin, 6)
	_ellipsoid(st, Vector3(0, shoulder_y + 0.24, -0.1), Vector3(0.135, 0.15, 0.15), helmet, 8, 5)
	MeshKit.box(st, Vector3(0, shoulder_y + 0.24, -0.235), Vector3(0.2, 0.08, 0.03), Color(0.05, 0.06, 0.08))
	var mesh: ArrayMesh = MeshKit.finish(st, material())
	_cache[key] = mesh
	return mesh

## Standing pedestrian. With `waving` the right arm is left out: wave_arm() builds it
## separately (pivot at the shoulder) so it can be animated cheaply.
static func standing(style: Style, variant: int, waving: bool) -> ArrayMesh:
	var key: String = "stand_%d_%d_%s" % [style, variant % 12, waving]
	if _cache.has(key):
		return _cache[key]
	var skin: Color = SKIN_TONES[variant % SKIN_TONES.size()]
	var top: Color = _top_colour(style, variant)
	var st: SurfaceTool = MeshKit.begin()
	match style:
		Style.SAREE:
			var s: Color = SAREES[variant % SAREES.size()]
			_skirt(st, 0.02, 0.92, 0.22, 0.17, s)
			_torso(st, Vector3(0, 0.88, 0), Basis.IDENTITY, 0.5, s.darkened(0.15))
			# Pallu over the left shoulder.
			MeshKit.box(st, Vector3(-0.1, 1.2, 0.09), Vector3(0.2, 0.5, 0.04), s.lightened(0.15), Basis(Vector3.FORWARD, 0.35))
		Style.VESHTI:
			_skirt(st, 0.03, 0.92, 0.2, 0.17, VESHTI_WHITE)
			_torso(st, Vector3(0, 0.88, 0), Basis.IDENTITY, 0.52, top)
		_:
			var leg: Color = JEANS if style == Style.TSHIRT_JEANS or style == Style.TOURIST else TROUSER
			for side: float in [-1.0, 1.0]:
				MeshKit.tube(st, Vector3(0.09 * side, 0.05, 0), Vector3(0.1 * side, 0.92, 0), 0.075, leg, 6)
			_torso(st, Vector3(0, 0.88, 0), Basis.IDENTITY, 0.52, top)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.09 * side, 0.03, -0.04), Vector3(0.1, 0.06, 0.24), SANDAL)
	var shoulder: Vector3 = Vector3(0.21, 1.38, 0)
	# Left arm down (with a shopping bag for the T. Nagar shopper).
	MeshKit.tube(st, Vector3(-shoulder.x, shoulder.y, 0), Vector3(-0.26, 1.1, 0.02), 0.052, top, 6)
	MeshKit.tube(st, Vector3(-0.26, 1.1, 0.02), Vector3(-0.27, 0.86, -0.02), 0.043, skin, 6)
	if style == Style.SAREE:
		MeshKit.box(st, Vector3(-0.3, 0.68, -0.02), Vector3(0.1, 0.32, 0.28), Color(0.9, 0.8, 0.2))
	if not waving:
		MeshKit.tube(st, shoulder, Vector3(0.26, 1.1, 0.02), 0.052, top, 6)
		MeshKit.tube(st, Vector3(0.26, 1.1, 0.02), Vector3(0.27, 0.86, -0.02), 0.043, skin, 6)
	if style == Style.TOURIST:
		MeshKit.box(st, Vector3(0, 1.16, 0.2), Vector3(0.32, 0.42, 0.16), Color(0.85, 0.45, 0.1)) # backpack
	# Neck + head + hair (or cap for the tourist).
	MeshKit.tube(st, Vector3(0, 1.36, 0), Vector3(0, 1.47, 0), 0.05, skin, 6)
	_ellipsoid(st, Vector3(0, 1.58, 0), Vector3(0.1, 0.12, 0.11), skin, 8, 5)
	if style == Style.TOURIST:
		_ellipsoid(st, Vector3(0, 1.66, 0.005), Vector3(0.108, 0.06, 0.118), Color(0.9, 0.9, 0.85), 8, 3)
		MeshKit.box(st, Vector3(0, 1.645, -0.14), Vector3(0.16, 0.015, 0.1), Color(0.9, 0.9, 0.85))
	else:
		_ellipsoid(st, Vector3(0, 1.63, 0.012), Vector3(0.106, 0.08, 0.115), HAIR, 8, 4)
		if style == Style.SAREE:
			_ellipsoid(st, Vector3(0, 1.58, 0.12), Vector3(0.06, 0.06, 0.05), HAIR, 6, 3) # bun
	var mesh: ArrayMesh = MeshKit.finish(st, material())
	_cache[key] = mesh
	return mesh

## The raised hailing arm, built pointing up from a pivot at the shoulder (origin).
static func wave_arm(style: Style, variant: int) -> ArrayMesh:
	var key: String = "arm_%d_%d" % [style, variant % 12]
	if _cache.has(key):
		return _cache[key]
	var skin: Color = SKIN_TONES[variant % SKIN_TONES.size()]
	var top: Color = _top_colour(style, variant)
	if style == Style.SAREE:
		top = SAREES[variant % SAREES.size()].darkened(0.15)
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.tube(st, Vector3.ZERO, Vector3(0.08, 0.24, -0.04), 0.052, top, 6)
	MeshKit.tube(st, Vector3(0.08, 0.24, -0.04), Vector3(0.1, 0.5, -0.08), 0.043, skin, 6)
	MeshKit.box(st, Vector3(0.1, 0.56, -0.08), Vector3(0.07, 0.1, 0.03), skin) # open palm
	var mesh: ArrayMesh = MeshKit.finish(st, material())
	_cache[key] = mesh
	return mesh

static func _top_colour(style: Style, variant: int) -> Color:
	if style == Style.VESHTI:
		return Color(0.96, 0.96, 0.94) if variant % 2 == 0 else SHIRTS[variant % SHIRTS.size()]
	return SHIRTS[(variant + int(style)) % SHIRTS.size()]

static func _torso(st: SurfaceTool, base: Vector3, b: Basis, height: float, colour: Color) -> void:
	var rings: Array[PackedVector3Array] = []
	var prof: Array[Vector3] = [Vector3(0.0, 0.16, 0.11), Vector3(0.25, 0.17, 0.12), Vector3(0.85, 0.2, 0.12), Vector3(1.0, 0.13, 0.09)]
	for p: Vector3 in prof:
		rings.append(_ring(base + b * Vector3(0, p.x * height, 0), p.y, p.z, 10, b))
	MeshKit.loft(st, rings, colour, true, true, true)

static func _skirt(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, colour: Color) -> void:
	MeshKit.loft(st, [_ring(Vector3(0, y0, 0), r0, r0 * 0.85, 10), _ring(Vector3(0, y1, 0), r1, r1 * 0.75, 10)], colour, true, true, true)

static func _ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, colour: Color, segs: int, stacks: int) -> void:
	var rings: Array[PackedVector3Array] = []
	for i: int in range(1, stacks * 2):
		var phi: float = PI * float(i) / float(stacks * 2) - PI * 0.5 # -90°..90° exclusive
		rings.append(_ring(c + Vector3(0, sin(phi) * r.y, 0), cos(phi) * r.x, cos(phi) * r.z, segs))
	MeshKit.loft(st, rings, colour, true, true, true)

## Horizontal ellipse ring, wound the same way MeshKit.tube winds its rings.
static func _ring(c: Vector3, rx: float, rz: float, segs: int, b: Basis = Basis.IDENTITY) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for s: int in segs:
		var a: float = TAU * float(s) / float(segs)
		out.append(c + b * Vector3(-sin(a) * rx, 0.0, -cos(a) * rz))
	return out
