class_name BeachCartKit
extends RefCounted
## Chennai push-cart shops — the Marina's sundal / spring-potato / tiffin carts and the ones that
## line market kerbs — as plain triangles merged into each chunk's building mesh (like
## StreetStallKit). +Z faces the customers (the road / promenade), y = 0 is the ground.
##
## Five builds from the owner's Marina photos (Nov 7):
##   0 SIGN_BOX  — tall painted cabinet on small wheels with a big printed board box on top
##   1 TIFFIN    — cabinet on a frame with two big spoked wheels, flat menu board on top
##   2 PUSHCART  — flat wooden top with a lip, cabinet below, spoked wheels, wire-mesh racks
##   3 KIOSK     — tall narrow kiosk with a white board box
##   4 COVERED   — a cart shut for the day under a tarpaulin
## VARIANTS crosses them with paint and board colours; each variant records where its shop-name
## label goes (CartSigns puts the text there). Keep each under ~700 triangles.

enum Build { SIGN_BOX, TIFFIN, PUSHCART, KIOSK, COVERED }

const PAINT_LIFT: float = 1.2
const YELLOW: Color = Color(0.96, 0.7, 0.08)
const BLUE: Color = Color(0.12, 0.36, 0.76)
const PINK: Color = Color(0.86, 0.32, 0.56)
const RED: Color = Color(0.8, 0.16, 0.12)
const GREEN: Color = Color(0.14, 0.58, 0.3)
const ORANGE: Color = Color(0.95, 0.5, 0.1)
const SKY: Color = Color(0.32, 0.64, 0.88)
const WHITE: Color = Color(0.93, 0.93, 0.9)
const CREAM: Color = Color(0.96, 0.9, 0.7)
const DARK: Color = Color(0.08, 0.08, 0.09)
const RUBBER: Color = Color(0.1, 0.1, 0.1)
const STEEL: Color = Color(0.45, 0.47, 0.5)
const WOOD: Color = Color(0.42, 0.28, 0.16)
const RUST: Color = Color(0.45, 0.25, 0.14)
const TARP_YELLOW: Color = Color(0.96, 0.74, 0.06)
const TARP_BLUE: Color = Color(0.1, 0.32, 0.75)
## Menu photo tiles: corn, bajji, chilli, spring potato, lemon soda, sundal, fish fry, idli.
const FOOD: Array[Color] = [Color(0.98, 0.85, 0.3), Color(0.82, 0.5, 0.18), Color(0.85, 0.18, 0.1), Color(0.95, 0.7, 0.2),
	Color(0.55, 0.85, 0.45), Color(0.7, 0.55, 0.3), Color(0.7, 0.28, 0.12), Color(0.95, 0.95, 0.9)]

## [build, body paint, board colour]
const VARIANTS: Array = [
	[Build.SIGN_BOX, YELLOW, YELLOW], [Build.SIGN_BOX, BLUE, YELLOW], [Build.SIGN_BOX, PINK, WHITE],
	[Build.SIGN_BOX, GREEN, ORANGE], [Build.SIGN_BOX, RED, YELLOW],
	[Build.TIFFIN, BLUE, ORANGE], [Build.TIFFIN, SKY, YELLOW], [Build.TIFFIN, GREEN, WHITE], [Build.TIFFIN, ORANGE, RED],
	[Build.PUSHCART, BLUE, BLUE], [Build.PUSHCART, GREEN, GREEN], [Build.PUSHCART, RED, RED],
	[Build.KIOSK, PINK, WHITE], [Build.KIOSK, YELLOW, SKY], [Build.KIOSK, SKY, WHITE],
	[Build.COVERED, TARP_YELLOW, TARP_YELLOW], [Build.COVERED, TARP_BLUE, TARP_BLUE],
]

## Shop names in the style of Chennai cart boards (invented, not real businesses):
## [English, Tamil, what they sell].
const NAMES: Array = [
	["SRI MURUGAN SUNDAL", "முருகன் சுண்டல்", "sundal"],
	["LAKSHMI BAJJI STALL", "லட்சுமி பஜ்ஜி", "bajji"],
	["ANBU TIFFIN SHOP", "அன்பு டிபன் கடை", "tiffin"],
	["KANMANI SPRING POTATO", "கண்மணி ஸ்பிரிங் பொட்டேட்டோ", "potato"],
	["RAJA LEMON SODA", "ராஜா லெமன் சோடா", "soda"],
	["MARINA SWEET CORN", "மெரினா ஸ்வீட் கார்ன்", "corn"],
	["VELU MASALA PORI", "வேலு மசாலா பொரி", "pori"],
	["SELVI MANGO SLICE", "செல்வி மாங்காய்", "mango"],
	["THANGAM FISH FRY", "தங்கம் மீன் வறுவல்", "fish"],
	["AMMU MURUKKU KADAI", "அம்மு முறுக்கு கடை", "murukku"],
	["GANESH ICE CREAM", "கணேஷ் ஐஸ்கிரீம்", "ice"],
	["PRIYA PANI PURI", "பிரியா பானி பூரி", "chaat"],
	["MANI KAADAI FRY", "மணி காடை வறுவல்", "fry"],
	["JEEVA JUICE CORNER", "ஜீவா ஜூஸ் கார்னர்", "juice"],
	["KAVIYA CUTLET SHOP", "காவியா கட்லெட்", "cutlet"],
	["SARAVANAN SOUP STALL", "சரவணன் சூப்", "soup"],
	["DEVI BHEL PURI", "தேவி பேல் பூரி", "chaat"],
	["ARUN EGG BONDA", "அருண் முட்டை போண்டா", "bonda"],
	["MEENA ELANEER", "மீனா இளநீர்", "coconut"],
	["PANDIAN TEA STALL", "பாண்டியன் டீ கடை", "tea"],
	["KUMAR KAMBU KOOZH", "குமார் கம்பங்கூழ்", "koozh"],
	["SUGANYA SPRING POTATO", "சுகன்யா ஸ்பிரிங் பொட்டேட்டோ", "potato"],
	["AK TIFFIN SHOP", "ஏகே டிபன் கடை", "tiffin"],
	["VIJI SUNDAL & CORN", "விஜி சுண்டல் கார்ன்", "sundal"],
]

## Per variant: {"v","n","c"} arrays plus "label": [local position, max width, text colour] or
## an empty array when the build carries no board.
static func arrays() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in VARIANTS.size():
		var spec: Array = VARIANTS[i]
		var st: SurfaceTool = MeshKit.begin()
		var label: Array = []
		match int(spec[0]):
			Build.SIGN_BOX: label = _sign_box(st, spec[1], spec[2], i)
			Build.TIFFIN: label = _tiffin(st, spec[1], spec[2], i)
			Build.PUSHCART: label = _pushcart(st, spec[1], i)
			Build.KIOSK: label = _kiosk(st, spec[1], spec[2], i)
			_: label = _covered(st, spec[1])
		st.generate_normals()
		var a: Array = st.commit_to_arrays()
		var colours: PackedColorArray = a[Mesh.ARRAY_COLOR]
		for k: int in colours.size():
			colours[k] = Color(minf(colours[k].r * PAINT_LIFT, 1.0), minf(colours[k].g * PAINT_LIFT, 1.0), minf(colours[k].b * PAINT_LIFT, 1.0))
		out.append({"v": a[Mesh.ARRAY_VERTEX], "n": a[Mesh.ARRAY_NORMAL], "c": colours, "label": label})
	return out

static func text_colour(board: Color) -> Color:
	return Color(0.75, 0.08, 0.08) if board.get_luminance() > 0.6 else WHITE

# --- parts ----------------------------------------------------------------------------------

## A spoked wheel in the cart's YZ plane at `centre` (axle along X).
static func _spoked_wheel(st: SurfaceTool, centre: Vector3, radius: float, colour: Color) -> void:
	var segs: int = 10
	for k: int in segs:
		var a0: float = TAU * float(k) / float(segs)
		var a1: float = TAU * float(k + 1) / float(segs)
		var p0: Vector3 = centre + Vector3(0.0, sin(a0), cos(a0)) * radius
		var p1: Vector3 = centre + Vector3(0.0, sin(a1), cos(a1)) * radius
		MeshKit.tube(st, p0, p1, 0.028, colour, 4)
	for k: int in 5:
		var a: float = TAU * float(k) / 5.0
		MeshKit.tube(st, centre, centre + Vector3(0.0, sin(a), cos(a)) * radius, 0.009, colour.darkened(0.2), 3)
	MeshKit.box(st, centre, Vector3(0.12, 0.08, 0.08), DARK)

static func _small_wheel(st: SurfaceTool, centre: Vector3, radius: float) -> void:
	MeshKit.disc(st, centre + Vector3(0.05, 0.0, 0.0), Vector3.RIGHT, radius, RUBBER, 10)
	MeshKit.disc(st, centre - Vector3(0.05, 0.0, 0.0), Vector3.LEFT, radius, RUBBER, 10)
	MeshKit.disc(st, centre + Vector3(0.055, 0.0, 0.0), Vector3.RIGHT, radius * 0.5, RED.darkened(0.2), 8)

## Menu photo tiles on a board face at z = `face_z`, filling the rectangle centre/size.
static func _tiles(st: SurfaceTool, centre: Vector3, size: Vector2, cols: int, rows: int, salt: int, face_z: float, facing: float = 1.0) -> void:
	var tw: float = size.x / float(cols)
	var th: float = size.y / float(rows)
	for r: int in rows:
		for c: int in cols:
			var food: Color = FOOD[(salt * 7 + r * cols + c * 3) % FOOD.size()]
			var p: Vector3 = Vector3(centre.x - size.x * 0.5 + tw * (float(c) + 0.5), centre.y + size.y * 0.5 - th * (float(r) + 0.5), face_z)
			MeshKit.box(st, p, Vector3(tw * 0.84, th * 0.8, 0.012), WHITE)
			MeshKit.box(st, p + Vector3(0.0, 0.0, 0.004 * facing), Vector3(tw * 0.7, th * 0.62, 0.012), food)

## Panel seams on a cabinet face (the hinged doors in the photos).
static func _doors(st: SurfaceTool, centre: Vector3, w: float, h: float, face_z: float, colour: Color) -> void:
	var seam: Color = colour.darkened(0.45)
	MeshKit.box(st, Vector3(centre.x, centre.y, face_z), Vector3(0.025, h * 0.9, 0.01), seam)
	MeshKit.box(st, Vector3(centre.x, centre.y + h * 0.05, face_z), Vector3(w * 0.92, 0.025, 0.01), seam)
	MeshKit.box(st, Vector3(centre.x + w * 0.12, centre.y + h * 0.1, face_z + 0.01), Vector3(0.05, 0.08, 0.02), STEEL) # padlock

static func _sign_box(st: SurfaceTool, paint: Color, board: Color, salt: int) -> Array:
	var w: float = 1.5
	var d: float = 1.0
	var h: float = 1.55
	MeshKit.box(st, Vector3(0.0, 0.22 + h * 0.5, 0.0), Vector3(w, h, d), paint)
	_doors(st, Vector3(0.0, 0.22 + h * 0.5, 0.0), w, h, d * 0.5 + 0.006, paint)
	for x: float in [-w * 0.42, w * 0.42]:
		for z: float in [-d * 0.36, d * 0.36]:
			_small_wheel(st, Vector3(x, 0.18, z), 0.18)
	# Sign box overhanging the cabinet.
	var sw: float = 2.1
	var sd: float = 1.25
	var sh: float = 0.78
	var sy: float = 0.22 + h + sh * 0.5
	MeshKit.box(st, Vector3(0.0, sy, 0.0), Vector3(sw, sh, sd), board)
	MeshKit.box(st, Vector3(0.0, sy - sh * 0.5 + 0.02, 0.0), Vector3(sw + 0.02, 0.04, sd + 0.02), board.darkened(0.35))
	_tiles(st, Vector3(-0.15, sy - 0.14, 0.0), Vector2(1.5, 0.42), 4, 2, salt, sd * 0.5 + 0.008)
	# Side faces: two tiles each.
	for sx: float in [-1.0, 1.0]:
		for k: int in 2:
			var food: Color = FOOD[(salt + k * 5) % FOOD.size()]
			MeshKit.box(st, Vector3(sx * (sw * 0.5 + 0.006), sy - 0.1, -0.22 + float(k) * 0.44), Vector3(0.012, 0.36, 0.36), food)
	# A drinks/fruit splash on the right of the front face.
	MeshKit.box(st, Vector3(0.78, sy - 0.1, sd * 0.5 + 0.01), Vector3(0.36, 0.5, 0.012), FOOD[(salt + 4) % FOOD.size()])
	return [Vector3(-0.05, sy + 0.2, sd * 0.5 + 0.02), 1.9, text_colour(board)]

static func _tiffin(st: SurfaceTool, paint: Color, board: Color, salt: int) -> Array:
	var w: float = 1.7
	var d: float = 1.0
	# Frame, bottom shelf and the cabinet.
	MeshKit.box(st, Vector3(0.0, 0.42, 0.0), Vector3(w, 0.05, d), paint.darkened(0.25))
	MeshKit.box(st, Vector3(0.0, 0.98, 0.0), Vector3(w, 1.0, d), paint)
	MeshKit.box(st, Vector3(0.0, 1.5, 0.08), Vector3(w + 0.1, 0.06, d + 0.25), paint.darkened(0.15)) # counter lip
	_doors(st, Vector3(0.0, 0.98, 0.0), w, 1.0, d * 0.5 + 0.006, paint)
	for x: float in [-w * 0.5 - 0.06, w * 0.5 + 0.06]:
		_spoked_wheel(st, Vector3(x, 0.42, -0.15), 0.42, DARK)
	MeshKit.box(st, Vector3(0.0, 0.2, d * 0.45), Vector3(0.06, 0.4, 0.06), STEEL) # front leg
	# Menu board on top: a flat two-sided board.
	var by: float = 1.53 + 0.4
	MeshKit.box(st, Vector3(0.0, by, -0.2), Vector3(w + 0.1, 0.72, 0.08), board)
	MeshKit.box(st, Vector3(0.0, by, -0.2), Vector3(w + 0.16, 0.78, 0.04), DARK)
	_tiles(st, Vector3(0.0, by - 0.12, 0.0), Vector2(w - 0.1, 0.4), 5, 2, salt, -0.2 + 0.046)
	return [Vector3(0.0, by + 0.22, -0.2 + 0.06), w - 0.1, text_colour(board)]

static func _pushcart(st: SurfaceTool, paint: Color, salt: int) -> Array:
	var w: float = 1.9
	var d: float = 1.05
	MeshKit.box(st, Vector3(0.0, 0.9, 0.0), Vector3(w, 0.06, d), paint)
	for z: float in [-d * 0.5, d * 0.5]:
		MeshKit.box(st, Vector3(0.0, 0.96, z), Vector3(w, 0.08, 0.05), paint.darkened(0.15)) # lip
	for x: float in [-w * 0.5, w * 0.5]:
		MeshKit.box(st, Vector3(x, 0.96, 0.0), Vector3(0.05, 0.08, d), paint.darkened(0.15))
	MeshKit.box(st, Vector3(0.25, 0.62, 0.05), Vector3(1.0, 0.5, 0.8), paint) # cabinet
	_doors(st, Vector3(0.25, 0.62, 0.05), 1.0, 0.5, 0.46, paint)
	for x: float in [-w * 0.5 + 0.1, w * 0.5 - 0.1]:
		for z: float in [-d * 0.42, d * 0.42]:
			MeshKit.box(st, Vector3(x, 0.45, z), Vector3(0.05, 0.9, 0.05), paint.darkened(0.3))
	for x: float in [-w * 0.5 - 0.05, w * 0.5 + 0.05]:
		_spoked_wheel(st, Vector3(x, 0.45, 0.0), 0.45, paint.darkened(0.3))
	MeshKit.box(st, Vector3(-w * 0.5 - 0.35, 0.95, 0.0), Vector3(0.7, 0.04, 0.04), STEEL) # handle
	# Wire-mesh racks at the back corners.
	for x: float in [-0.65, 0.65]:
		var c: Vector3 = Vector3(x, 1.55, -d * 0.45)
		MeshKit.box(st, c, Vector3(0.55, 1.15, 0.02), Color(0.2, 0.2, 0.2, 1.0))
		MeshKit.box(st, c + Vector3(0.0, 0.0, 0.015), Vector3(0.5, 1.08, 0.01), Color(0.55, 0.55, 0.5))
	# Wares on top: a few mounds.
	for k: int in 3:
		MeshKit.box(st, Vector3(-0.55 + float(k) * 0.55, 1.02, 0.1), Vector3(0.38, 0.1, 0.38), FOOD[(salt + k) % FOOD.size()])
	return []

static func _kiosk(st: SurfaceTool, paint: Color, board: Color, salt: int) -> Array:
	var w: float = 1.25
	var d: float = 1.0
	var h: float = 1.9
	MeshKit.box(st, Vector3(0.0, 0.1 + h * 0.5, 0.0), Vector3(w, h, d), paint)
	_doors(st, Vector3(0.0, 0.1 + h * 0.5, 0.0), w, h, d * 0.5 + 0.006, paint)
	MeshKit.box(st, Vector3(0.0, 0.05, 0.0), Vector3(w + 0.1, 0.1, d + 0.1), DARK)
	var sy: float = 0.1 + h + 0.38
	MeshKit.box(st, Vector3(0.0, sy, 0.0), Vector3(w + 0.2, 0.76, d + 0.1), board)
	_tiles(st, Vector3(0.0, sy - 0.12, 0.0), Vector2(w, 0.4), 3, 2, salt, (d + 0.1) * 0.5 + 0.008)
	for sx: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(sx * ((w + 0.2) * 0.5 + 0.006), sy - 0.05, 0.0), Vector3(0.012, 0.45, 0.6), FOOD[(salt * 3 + int(sx + 1.0)) % FOOD.size()])
	return [Vector3(0.0, sy + 0.2, (d + 0.1) * 0.5 + 0.02), w + 0.1, text_colour(board)]

static func _covered(st: SurfaceTool, tarp: Color) -> Array:
	MeshKit.box(st, Vector3(0.0, 0.85, 0.0), Vector3(1.7, 1.2, 1.05), tarp)
	MeshKit.box(st, Vector3(0.0, 1.5, 0.0), Vector3(1.5, 0.14, 0.9), tarp.darkened(0.08))
	MeshKit.box(st, Vector3(0.0, 1.62, 0.0), Vector3(1.1, 0.12, 0.6), tarp.darkened(0.12))
	for x: float in [-0.5, 0.5]:
		MeshKit.box(st, Vector3(x, 1.0, 0.53), Vector3(0.03, 1.0, 0.01), Color(0.2, 0.2, 0.2)) # rope
	for x: float in [-0.92, 0.92]:
		_spoked_wheel(st, Vector3(x, 0.4, 0.0), 0.4, DARK)
	return []
