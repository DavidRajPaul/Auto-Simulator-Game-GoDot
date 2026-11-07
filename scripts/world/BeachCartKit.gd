class_name BeachCartKit
extends RefCounted
## Chennai push-cart shops — the Marina's sundal / spring-potato / tiffin carts, the fast-food,
## atho, pani-puri and ice-cream carts that stand in rows of five or six on a kerb — as plain
## triangles merged into each chunk's building mesh (like StreetStallKit). +Z faces the
## customers (the road / promenade), y = 0 is the ground.
##
## Builds (owner's Marina photos, Nov 7; shop rows, Nov 7 afternoon):
##   SIGN_BOX  — tall painted cabinet on small wheels with a big printed board box on top
##   TIFFIN    — cabinet on a frame with two big spoked wheels, flat menu board on top
##   PUSHCART  — flat wooden top with a lip, cabinet below, spoked wheels, wire-mesh racks
##   KIOSK     — tall narrow kiosk with a board box
##   COVERED   — a cart shut for the day under a tarpaulin
##   FAST_FOOD — steel counter cart, burner and wok, board on posts (fried rice, kothu, momos)
##   ICE_CREAM — insulated box cart with a beach umbrella
##   PANI_PURI — small cart with a glass case of puris and a pani pot
##
## Every cart is three parts: always there, OPEN-only (wares, open serving window, umbrella,
## bulb) and CLOSED-only (tarpaulin, cloth over the glass, folded umbrella). Per vertex "g" is
## 0 / 1 / 2; WorldChunkStreamer._cart writes the gate and the cart's hours into the vertex UV and
## shaders/building_facade.gdshader drops the part that doesn't match the shift clock — so carts
## open and close with the time of day at no draw-call cost. Shop names, types and hours live
## in data/world/cart_shops.json (tools/osm/build_beach_carts.py).

enum Build { SIGN_BOX, TIFFIN, PUSHCART, KIOSK, COVERED, FAST_FOOD, ICE_CREAM, PANI_PURI }

const SHOPS_FILE: String = "res://data/world/cart_shops.json"
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
const SHINY: Color = Color(0.72, 0.74, 0.76)
const WOOD: Color = Color(0.42, 0.28, 0.16)
const RUST: Color = Color(0.45, 0.25, 0.14)
const GLASS: Color = Color(0.62, 0.82, 0.86)
const BULB: Color = Color(1.0, 0.92, 0.55)
const TARP_YELLOW: Color = Color(0.96, 0.74, 0.06)
const TARP_BLUE: Color = Color(0.1, 0.32, 0.75)
const TARPS: Array[Color] = [Color(0.1, 0.32, 0.75), Color(0.96, 0.74, 0.06), Color(0.14, 0.5, 0.32), Color(0.75, 0.2, 0.2)]
## Menu photo tiles: corn, bajji, chilli, spring potato, lemon soda, sundal, fish fry, idli.
const FOOD: Array[Color] = [Color(0.98, 0.85, 0.3), Color(0.82, 0.5, 0.18), Color(0.85, 0.18, 0.1), Color(0.95, 0.7, 0.2),
	Color(0.55, 0.85, 0.45), Color(0.7, 0.55, 0.3), Color(0.7, 0.28, 0.12), Color(0.95, 0.95, 0.9)]

## [build, body paint, board colour] — tools/osm/build_beach_carts.py BUILDS mirrors the builds.
const VARIANTS: Array = [
	[Build.SIGN_BOX, YELLOW, YELLOW], [Build.SIGN_BOX, BLUE, YELLOW], [Build.SIGN_BOX, PINK, WHITE],
	[Build.SIGN_BOX, GREEN, ORANGE], [Build.SIGN_BOX, RED, YELLOW],
	[Build.TIFFIN, BLUE, ORANGE], [Build.TIFFIN, SKY, YELLOW], [Build.TIFFIN, GREEN, WHITE], [Build.TIFFIN, ORANGE, RED],
	[Build.PUSHCART, BLUE, BLUE], [Build.PUSHCART, GREEN, GREEN], [Build.PUSHCART, RED, RED],
	[Build.KIOSK, PINK, WHITE], [Build.KIOSK, YELLOW, SKY], [Build.KIOSK, SKY, WHITE],
	[Build.COVERED, TARP_YELLOW, TARP_YELLOW], [Build.COVERED, TARP_BLUE, TARP_BLUE],
	[Build.FAST_FOOD, RED, YELLOW], [Build.FAST_FOOD, BLUE, WHITE], [Build.FAST_FOOD, GREEN, ORANGE], [Build.FAST_FOOD, ORANGE, RED],
	[Build.ICE_CREAM, WHITE, SKY], [Build.ICE_CREAM, PINK, WHITE], [Build.ICE_CREAM, SKY, YELLOW],
	[Build.PANI_PURI, RED, YELLOW], [Build.PANI_PURI, BLUE, WHITE], [Build.PANI_PURI, GREEN, YELLOW],
]

static var _shops: Dictionary = {}

## data/world/cart_shops.json: {"names": [[English, Tamil, type], …], "types": {type: [open, close, [builds]]}}.
static func shops() -> Dictionary:
	if _shops.is_empty() and FileAccess.file_exists(SHOPS_FILE):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHOPS_FILE))
		if parsed is Dictionary:
			_shops = parsed
	return _shops

static func shop_name(index: int) -> String:
	var names: Array = shops().get("names", [])
	return "" if names.is_empty() else str((names[index % names.size()] as Array)[0])

## Open right now? `hour` 0–24; hours as stored per cart (close may run past 24; open == close
## means shut all day). Same test as the facade shader.
static func is_open(open_h: float, close_h: float, hour: float) -> bool:
	return (hour >= open_h and hour < close_h) or (hour + 24.0 >= open_h and hour + 24.0 < close_h)

## One cart's three parts while it is being built.
class Parts:
	var base: SurfaceTool = MeshKit.begin()
	var open: SurfaceTool = MeshKit.begin()
	var shut: SurfaceTool = MeshKit.begin()

## Per variant: {"v","n","c","g"} arrays (g = 0 always, 1 open-only, 2 closed-only) plus
## "label": [local position, max width, text colour] or an empty array when there is no board.
static func arrays() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in VARIANTS.size():
		var spec: Array = VARIANTS[i]
		var p: Parts = Parts.new()
		var label: Array = []
		match int(spec[0]):
			Build.SIGN_BOX: label = _sign_box(p, spec[1], spec[2], i)
			Build.TIFFIN: label = _tiffin(p, spec[1], spec[2], i)
			Build.PUSHCART: label = _pushcart(p, spec[1], i)
			Build.KIOSK: label = _kiosk(p, spec[1], spec[2], i)
			Build.FAST_FOOD: label = _fast_food(p, spec[1], spec[2], i)
			Build.ICE_CREAM: label = _ice_cream(p, spec[1], spec[2], i)
			Build.PANI_PURI: label = _pani_puri(p, spec[1], spec[2], i)
			_: label = _covered(p.base, spec[1])
		var v: PackedVector3Array = PackedVector3Array()
		var n: PackedVector3Array = PackedVector3Array()
		var c: PackedColorArray = PackedColorArray()
		var g: PackedByteArray = PackedByteArray()
		var gate: int = 0
		for st: SurfaceTool in [p.base, p.open, p.shut]:
			st.generate_normals()
			var a: Array = st.commit_to_arrays()
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX] if a[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			if not verts.is_empty():
				v.append_array(verts)
				n.append_array(a[Mesh.ARRAY_NORMAL])
				var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
				for k: int in cols.size():
					c.append(Color(minf(cols[k].r * PAINT_LIFT, 1.0), minf(cols[k].g * PAINT_LIFT, 1.0), minf(cols[k].b * PAINT_LIFT, 1.0)))
					g.append(gate)
			gate += 1
		out.append({"v": v, "n": n, "c": c, "g": g, "label": label})
	return out

static func text_colour(board: Color) -> Color:
	return Color(0.75, 0.08, 0.08) if board.get_luminance() > 0.6 else WHITE

## Open: a few food trays and steel vessels on a counter top. Closed: a tarpaulin over it.
static func _counter_states(p: Parts, top: Vector3, size: Vector2, front_drop: float, salt: int) -> void:
	for k: int in 3:
		var x: float = top.x - size.x * 0.32 + size.x * 0.32 * float(k)
		MeshKit.box(p.open, Vector3(x, top.y + 0.04, top.z + 0.05), Vector3(size.x * 0.24, 0.06, size.y * 0.4), SHINY)
		MeshKit.box(p.open, Vector3(x, top.y + 0.09, top.z + 0.05), Vector3(size.x * 0.18, 0.06, size.y * 0.3), FOOD[(salt + k * 3) % FOOD.size()])
	MeshKit.tube(p.open, Vector3(top.x + size.x * 0.4, top.y, top.z - size.y * 0.25), Vector3(top.x + size.x * 0.4, top.y + 0.3, top.z - size.y * 0.25), 0.13, SHINY, 8)
	var tarp: Color = TARPS[salt % TARPS.size()]
	MeshKit.box(p.shut, Vector3(top.x, top.y + 0.05, top.z), Vector3(size.x + 0.08, 0.08, size.y + 0.08), tarp)
	MeshKit.box(p.shut, Vector3(top.x, top.y - front_drop * 0.5, top.z + size.y * 0.5 + 0.04), Vector3(size.x + 0.08, front_drop, 0.03), tarp.darkened(0.1))
	MeshKit.box(p.shut, Vector3(top.x - size.x * 0.25, top.y + 0.1, top.z), Vector3(0.025, 0.02, size.y + 0.12), DARK) # rope
	MeshKit.box(p.shut, Vector3(top.x + size.x * 0.25, top.y + 0.1, top.z), Vector3(0.025, 0.02, size.y + 0.12), DARK)

## Open: a lit bulb hanging under the board's front edge.
static func _bulb(p: Parts, at: Vector3) -> void:
	MeshKit.box(p.open, at + Vector3(0.0, 0.08, 0.0), Vector3(0.01, 0.16, 0.01), DARK)
	MeshKit.box(p.open, at, Vector3(0.09, 0.11, 0.09), BULB)

## Open: a dark serving window and a shelf with wares on a cabinet front at z = face_z.
## Closed: a padlocked shutter over the window.
static func _window_states(p: Parts, centre: Vector3, size: Vector2, face_z: float, paint: Color, salt: int) -> void:
	MeshKit.box(p.open, Vector3(centre.x, centre.y, face_z + 0.004), Vector3(size.x, size.y, 0.012), Color(0.13, 0.1, 0.08))
	MeshKit.box(p.open, Vector3(centre.x, centre.y - size.y * 0.5 - 0.02, face_z + 0.16), Vector3(size.x + 0.1, 0.04, 0.32), paint.darkened(0.2))
	for k: int in 3:
		var x: float = centre.x - size.x * 0.3 + size.x * 0.3 * float(k)
		MeshKit.box(p.open, Vector3(x, centre.y - size.y * 0.5 + 0.04, face_z + 0.18), Vector3(size.x * 0.22, 0.08, 0.2), FOOD[(salt * 5 + k) % FOOD.size()])
	MeshKit.box(p.shut, Vector3(centre.x, centre.y, face_z + 0.006), Vector3(size.x, size.y, 0.012), paint.darkened(0.25))
	for k: int in 4:
		MeshKit.box(p.shut, Vector3(centre.x, centre.y - size.y * 0.5 + size.y * (float(k) + 0.5) / 4.0, face_z + 0.014), Vector3(size.x, 0.015, 0.006), paint.darkened(0.45))
	MeshKit.box(p.shut, Vector3(centre.x, centre.y - size.y * 0.4, face_z + 0.03), Vector3(0.06, 0.08, 0.03), STEEL)

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

static func _sign_box(p: Parts, paint: Color, board: Color, salt: int) -> Array:
	var st: SurfaceTool = p.base
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
	_window_states(p, Vector3(0.0, 1.32, 0.0), Vector2(w * 0.72, 0.62), d * 0.5 + 0.01, paint, salt)
	_bulb(p, Vector3(0.0, sy - sh * 0.5 - 0.14, sd * 0.5 - 0.1))
	return [Vector3(-0.05, sy + 0.2, sd * 0.5 + 0.02), 1.9, text_colour(board)]

static func _tiffin(p: Parts, paint: Color, board: Color, salt: int) -> Array:
	var st: SurfaceTool = p.base
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
	_counter_states(p, Vector3(0.0, 1.53, 0.2), Vector2(w - 0.1, 0.55), 0.7, salt)
	_bulb(p, Vector3(0.0, by - 0.5, -0.1))
	return [Vector3(0.0, by + 0.22, -0.2 + 0.06), w - 0.1, text_colour(board)]

static func _pushcart(p: Parts, paint: Color, salt: int) -> Array:
	var st: SurfaceTool = p.base
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
	# Wares on top when open, a tarp when shut.
	for k: int in 3:
		MeshKit.box(p.open, Vector3(-0.55 + float(k) * 0.55, 1.02, 0.1), Vector3(0.38, 0.1, 0.38), FOOD[(salt + k) % FOOD.size()])
	var tarp: Color = TARPS[salt % TARPS.size()]
	MeshKit.box(p.shut, Vector3(0.0, 1.0, 0.0), Vector3(w + 0.1, 0.08, d + 0.1), tarp)
	MeshKit.box(p.shut, Vector3(0.0, 0.8, d * 0.5 + 0.05), Vector3(w + 0.1, 0.4, 0.03), tarp.darkened(0.1))
	return []

static func _kiosk(p: Parts, paint: Color, board: Color, salt: int) -> Array:
	var st: SurfaceTool = p.base
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
	_window_states(p, Vector3(0.0, 1.3, 0.0), Vector2(w * 0.78, 0.7), d * 0.5 + 0.01, paint, salt)
	_bulb(p, Vector3(0.0, sy - 0.52, (d + 0.1) * 0.5 - 0.1))
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

## Fried rice / noodles / kothu / momos cart: steel-topped counter with a painted front, burner and
## wok, gas cylinder, a board on two posts.
static func _fast_food(p: Parts, paint: Color, board: Color, salt: int) -> Array:
	var st: SurfaceTool = p.base
	var w: float = 1.9
	var d: float = 0.95
	MeshKit.box(st, Vector3(0.0, 0.62, 0.0), Vector3(w, 0.8, d), paint)
	MeshKit.box(st, Vector3(0.0, 1.04, 0.0), Vector3(w + 0.06, 0.05, d + 0.06), SHINY)
	MeshKit.box(st, Vector3(0.0, 0.62, d * 0.5 + 0.006), Vector3(w * 0.9, 0.5, 0.01), board) # painted front panel
	_tiles(st, Vector3(0.0, 0.62, 0.0), Vector2(w * 0.8, 0.36), 4, 1, salt, d * 0.5 + 0.014)
	for x: float in [-w * 0.42, w * 0.42]:
		for z: float in [-d * 0.36, d * 0.36]:
			_small_wheel(st, Vector3(x, 0.16, z), 0.16)
	MeshKit.box(st, Vector3(0.0, 0.24, 0.0), Vector3(w - 0.1, 0.04, d - 0.1), STEEL)
	# Board on posts at the back.
	for x: float in [-w * 0.47, w * 0.47]:
		MeshKit.box(st, Vector3(x, 1.55, -d * 0.45), Vector3(0.05, 1.0, 0.05), STEEL)
	var by: float = 2.25
	MeshKit.box(st, Vector3(0.0, by, -d * 0.45), Vector3(w + 0.1, 0.5, 0.06), board)
	MeshKit.box(st, Vector3(0.0, by, -d * 0.45), Vector3(w + 0.16, 0.56, 0.03), DARK)
	# Open: burner, wok, ladle, bowls, cylinder by the wheel, tube light under the board.
	MeshKit.box(p.open, Vector3(-0.45, 1.1, 0.05), Vector3(0.4, 0.08, 0.4), DARK)
	MeshKit.tube(p.open, Vector3(-0.45, 1.13, 0.05), Vector3(-0.45, 1.25, 0.05), 0.3, Color(0.16, 0.16, 0.17), 10)
	MeshKit.box(p.open, Vector3(-0.45, 1.24, 0.05), Vector3(0.42, 0.04, 0.42), FOOD[(salt + 1) % FOOD.size()]) # rice in the wok
	MeshKit.box(p.open, Vector3(-0.2, 1.33, 0.05), Vector3(0.5, 0.02, 0.03), SHINY) # ladle
	for k: int in 3:
		MeshKit.box(p.open, Vector3(0.25 + float(k) * 0.22, 1.1, 0.15), Vector3(0.18, 0.06, 0.18), SHINY)
	MeshKit.tube(p.open, Vector3(w * 0.5 + 0.18, 0.0, 0.1), Vector3(w * 0.5 + 0.18, 0.62, 0.1), 0.15, RED, 8)
	MeshKit.box(p.open, Vector3(0.0, by - 0.32, -d * 0.4), Vector3(1.2, 0.05, 0.05), BULB)
	var tarp: Color = TARPS[salt % TARPS.size()]
	MeshKit.box(p.shut, Vector3(0.0, 1.1, 0.0), Vector3(w + 0.1, 0.08, d + 0.1), tarp)
	MeshKit.box(p.shut, Vector3(0.0, 0.85, d * 0.5 + 0.06), Vector3(w + 0.1, 0.5, 0.03), tarp.darkened(0.1))
	return [Vector3(0.0, by, -d * 0.45 + 0.04), w - 0.05, text_colour(board)]

## Ice-cream box cart: insulated box with a coloured band, big wheels, handle; a beach umbrella
## when open (folded when shut).
static func _ice_cream(p: Parts, paint: Color, board: Color, salt: int) -> Array:
	var st: SurfaceTool = p.base
	var w: float = 1.3
	var d: float = 0.8
	MeshKit.box(st, Vector3(0.0, 0.85, 0.0), Vector3(w, 0.75, d), WHITE)
	MeshKit.box(st, Vector3(0.0, 0.85, d * 0.5 + 0.006), Vector3(w, 0.32, 0.01), paint)
	MeshKit.box(st, Vector3(0.0, 1.25, 0.0), Vector3(w + 0.04, 0.05, d + 0.04), paint.darkened(0.2)) # lid
	for x: float in [-w * 0.5 - 0.05, w * 0.5 + 0.05]:
		_spoked_wheel(st, Vector3(x, 0.38, 0.0), 0.38, DARK)
	MeshKit.box(st, Vector3(-w * 0.5 - 0.4, 1.0, 0.0), Vector3(0.8, 0.04, 0.04), STEEL)
	MeshKit.box(st, Vector3(w * 0.3, 1.33, d * 0.3), Vector3(0.06, 0.1, 0.06), Color(0.85, 0.7, 0.2)) # bell
	MeshKit.box(st, Vector3(0.0, 1.15, 0.0), Vector3(0.05, 0.25, 0.05), STEEL) # umbrella socket
	# Open umbrella: striped canopy on a pole.
	MeshKit.box(p.open, Vector3(0.0, 1.85, 0.0), Vector3(0.04, 1.2, 0.04), STEEL)
	var stripes: Array[Color] = [board, WHITE]
	for k: int in 8:
		var a: float = TAU * float(k) / 8.0
		var tip: Vector3 = Vector3(sin(a), 0.0, cos(a)) * 1.0
		var b0: float = TAU * float(k + 1) / 8.0
		var tip2: Vector3 = Vector3(sin(b0), 0.0, cos(b0)) * 1.0
		var top: Vector3 = Vector3(0.0, 2.55, 0.0)
		var rim: Vector3 = Vector3(0.0, 2.3, 0.0)
		p.open.set_color(stripes[k % 2])
		p.open.set_smooth_group(-1)
		MeshKit._tri(p.open, top, rim + tip2, rim + tip) # upper face
		p.open.set_color(stripes[k % 2].darkened(0.25))
		MeshKit._tri(p.open, top, rim + tip, rim + tip2) # underside
	# Shut: umbrella folded, cone wrapped.
	MeshKit.box(p.shut, Vector3(0.0, 1.85, 0.0), Vector3(0.12, 1.2, 0.12), board.darkened(0.15))
	return [Vector3(0.0, 0.85, d * 0.5 + 0.02), w - 0.1, WHITE if paint.get_luminance() < 0.6 else Color(0.75, 0.08, 0.08)]

## Pani-puri cart: small table cart, glass case of puris on top, steel pani pot, onion tray; a
## cloth thrown over the glass case when shut.
static func _pani_puri(p: Parts, paint: Color, board: Color, salt: int) -> Array:
	var st: SurfaceTool = p.base
	var w: float = 1.4
	var d: float = 0.85
	MeshKit.box(st, Vector3(0.0, 0.88, 0.0), Vector3(w, 0.06, d), paint.darkened(0.15))
	MeshKit.box(st, Vector3(0.0, 0.58, 0.0), Vector3(w - 0.1, 0.55, d - 0.1), paint)
	for x: float in [-w * 0.5 - 0.04, w * 0.5 + 0.04]:
		_spoked_wheel(st, Vector3(x, 0.36, 0.0), 0.36, DARK)
	# Glass case with a board strip on top.
	var gc: Vector3 = Vector3(-0.15, 1.15, -0.1)
	MeshKit.box(st, gc, Vector3(0.95, 0.48, 0.5), GLASS)
	for x: float in [-0.475, 0.475]:
		MeshKit.box(st, gc + Vector3(x, 0.0, 0.25), Vector3(0.03, 0.48, 0.03), SHINY)
	var by: float = gc.y + 0.4
	MeshKit.box(st, Vector3(gc.x, by, gc.z), Vector3(1.05, 0.3, 0.06), board)
	MeshKit.box(st, Vector3(gc.x, by, gc.z), Vector3(1.1, 0.34, 0.03), DARK)
	for x: float in [-0.5, 0.5]:
		MeshKit.box(st, Vector3(gc.x + x, by - 0.2, gc.z), Vector3(0.03, 0.15, 0.03), SHINY)
	# Open: heaps of golden puris in the case, pani pot, onion tray.
	for k: int in 3:
		MeshKit.box(p.open, gc + Vector3(-0.3 + float(k) * 0.3, -0.12, 0.0), Vector3(0.24, 0.16, 0.3), Color(0.92, 0.7, 0.3))
	MeshKit.tube(p.open, Vector3(0.5, 0.91, 0.15), Vector3(0.5, 1.2, 0.15), 0.16, SHINY, 10)
	MeshKit.box(p.open, Vector3(0.5, 0.95, -0.25), Vector3(0.28, 0.05, 0.22), Color(0.82, 0.55, 0.62))
	# Shut: a cloth over the glass case.
	MeshKit.box(p.shut, gc + Vector3(0.0, 0.02, 0.0), Vector3(1.02, 0.54, 0.56), [WHITE, RED, TARP_BLUE][salt % 3])
	return [Vector3(gc.x, by, gc.z + 0.04), 1.0, text_colour(board)]
