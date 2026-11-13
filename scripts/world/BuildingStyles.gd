class_name BuildingStyles
extends RefCounted
## What each kind of Chennai building looks like: which facade-atlas cells its street front and
## its side walls use, its paint, its roof and its extras. Pure data and maths (no nodes), read by
## WorldChunkStreamer on the chunk worker threads.
##
## The building type ("t") and its street-facing walls ("fw") come from
## tools/osm/classify_buildings.py. Atlas cells are (column, row) in
## assets/textures/facade_atlas.png (tools/art/make_facade_atlas.py has the full map).

# --- atlas cells ---------------------------------------------------------------------------------
const WIN_GRILLE: Vector2 = Vector2(0, 0)
const BALCONY: Vector2 = Vector2(1, 0)
const WIN_TWIN: Vector2 = Vector2(2, 0)
const VENTS: Vector2 = Vector2(3, 0)
const WIN_AC: Vector2 = Vector2(4, 0)
const OFFICE_GLASS: Vector2 = Vector2(5, 0)
const OFFICE_STRIP: Vector2 = Vector2(6, 0)
const PLAIN: Vector2 = Vector2(7, 0)
const HOUSE_DOOR: Vector2 = Vector2(0, 1)
const COMPOUND: Vector2 = Vector2(1, 1)
const SHUTTER: Vector2 = Vector2(2, 1)
const KAAVI: Vector2 = Vector2(0, 3)
const KAAVI_DOOR: Vector2 = Vector2(1, 3)
const TERRACE: Vector2 = Vector2(2, 3)
const TERRACE_TANK: Vector2 = Vector2(3, 3)
const HERITAGE_WIN: Vector2 = Vector2(4, 3)
const THINNAI: Vector2 = Vector2(5, 3)
const CIVIC: Vector2 = Vector2(6, 3)
const CIVIC_DOOR: Vector2 = Vector2(7, 3)
const BALCONY_WASH: Vector2 = Vector2(0, 4)
const WIN_BOX: Vector2 = Vector2(1, 4)
const JAALI: Vector2 = Vector2(2, 4)
const PARTY_WALL: Vector2 = Vector2(3, 4)
const WALL_ADVERT: Vector2 = Vector2(4, 4)
const CLADDING: Vector2 = Vector2(5, 4)
const SHOW_GLASS: Vector2 = Vector2(6, 4)
const TENEMENT: Vector2 = Vector2(7, 4)
const STILT_BIKES: Vector2 = Vector2(0, 5)
const STILT_CAR: Vector2 = Vector2(1, 5)
const PORTICO: Vector2 = Vector2(2, 5)
const SHOW_SILK: Vector2 = Vector2(3, 5)
const SHOW_JEWEL: Vector2 = Vector2(4, 5)
const BANK: Vector2 = Vector2(5, 5)
const CLINIC: Vector2 = Vector2(6, 5)
const SMALL_DOOR: Vector2 = Vector2(7, 5)
const ROOF_TILES: Vector2 = Vector2(0, 7)
const ROOF_SHEET: Vector2 = Vector2(1, 7)
const ROOF_CLAY: Vector2 = Vector2(2, 7)
const ROOF_THATCH: Vector2 = Vector2(3, 7)
const CHURCH: Vector2 = Vector2(4, 7)
const MOSQUE: Vector2 = Vector2(5, 7)
const SCHOOL: Vector2 = Vector2(6, 7)
const HOSPITAL: Vector2 = Vector2(7, 7)
## Hoardings are row 6: silks, jewellers, Aadi sale, coaching, hospital, wedding hall, flats, paints.
const HOARDING_ROW: float = 6.0
const HOARDING_COUNT: int = 8
## Open shops: one board per cell (Tamil over English). The closed shutter is mixed in separately.
const SHOPS: Array[Vector2] = [Vector2(3, 1), Vector2(4, 1), Vector2(5, 1), Vector2(6, 1), Vector2(7, 1),
	Vector2(0, 2), Vector2(1, 2), Vector2(2, 2), Vector2(3, 2), Vector2(4, 2), Vector2(5, 2), Vector2(6, 2), Vector2(7, 2)]
## Where the name board sits inside a shop cell (u0, v bottom, u1, v top in bay/floor UVs).
const SHOP_BOARD_UV: Rect2 = Rect2(0.012, 0.758, 0.976, 0.222)
## A whole cell on one quad. Just inside 0..1: the shader takes fract(), so an exact 1.0 wraps.
const FULL_CELL: Rect2 = Rect2(0.004, 0.004, 0.992, 0.992)

# --- paint ---------------------------------------------------------------------------------------
## Exterior emulsion as Chennai actually buys it: creams and peaches first, then the mint, sky
## blue, lavender and salmon that mark the newer flats.
const PAINT_HOME: Array[Color] = [Color(0.95, 0.90, 0.76), Color(0.96, 0.84, 0.66), Color(0.93, 0.93, 0.88),
	Color(0.97, 0.88, 0.58), Color(0.74, 0.88, 0.78), Color(0.72, 0.83, 0.93), Color(0.95, 0.76, 0.74),
	Color(0.84, 0.78, 0.93), Color(0.90, 0.80, 0.68), Color(0.80, 0.90, 0.70), Color(0.97, 0.78, 0.58),
	Color(0.88, 0.86, 0.80)]
const PAINT_SHOPS: Array[Color] = [Color(0.93, 0.88, 0.76), Color(0.90, 0.78, 0.60), Color(0.82, 0.84, 0.86),
	Color(0.95, 0.90, 0.62), Color(0.78, 0.86, 0.80), Color(0.92, 0.74, 0.70), Color(0.86, 0.82, 0.74),
	Color(0.74, 0.80, 0.90)]
const PAINT_SHOWROOM: Array[Color] = [Color(0.96, 0.95, 0.92), Color(0.62, 0.10, 0.16), Color(0.90, 0.80, 0.56),
	Color(0.14, 0.22, 0.44), Color(0.82, 0.16, 0.14), Color(0.30, 0.31, 0.34), Color(0.96, 0.78, 0.20)]
const PAINT_OLD: Array[Color] = [Color(0.96, 0.95, 0.90), Color(0.93, 0.80, 0.50), Color(0.74, 0.86, 0.90),
	Color(0.80, 0.90, 0.78), Color(0.93, 0.84, 0.70), Color(0.90, 0.72, 0.62)]
const PAINT_HAMLET: Array[Color] = [Color(0.20, 0.62, 0.86), Color(0.96, 0.52, 0.66), Color(0.38, 0.80, 0.56),
	Color(0.98, 0.84, 0.30), Color(0.30, 0.78, 0.78), Color(0.96, 0.62, 0.34), Color(0.70, 0.56, 0.90),
	Color(0.94, 0.94, 0.90)]
const PAINT_TENEMENT: Array[Color] = [Color(0.90, 0.84, 0.66), Color(0.86, 0.76, 0.70), Color(0.82, 0.84, 0.76),
	Color(0.92, 0.80, 0.56), Color(0.80, 0.80, 0.82)]
const PAINT_INSTITUTION: Dictionary = {
	"sc": [Color(0.97, 0.90, 0.62), Color(0.95, 0.92, 0.80), Color(0.93, 0.80, 0.64)],
	"hp": [Color(0.96, 0.97, 0.96), Color(0.86, 0.93, 0.95), Color(0.88, 0.95, 0.90)],
	"ch": [Color(0.97, 0.96, 0.92), Color(0.95, 0.90, 0.78), Color(0.90, 0.86, 0.80)],
	"mq": [Color(0.96, 0.97, 0.94), Color(0.84, 0.94, 0.86)],
	"bk": [Color(0.86, 0.86, 0.84), Color(0.93, 0.90, 0.82), Color(0.80, 0.84, 0.90)],
	"gv": [Color(0.93, 0.88, 0.76), Color(0.85, 0.50, 0.40), Color(0.95, 0.95, 0.92)],
	"tp": [Color(0.96, 0.82, 0.5), Color(0.93, 0.7, 0.45), Color(0.98, 0.93, 0.8)],
	"of": [Color(0.6, 0.68, 0.74), Color(0.75, 0.78, 0.8), Color(0.55, 0.6, 0.62)],
	"sd": [Color(0.55, 0.58, 0.62), Color(0.45, 0.5, 0.6), Color(0.62, 0.55, 0.48)],
}
## Road dust and years of sun: every wall drifts a little towards this.
const DUST: Color = Color(0.66, 0.61, 0.52)
const SHEET_COLOURS: Array[Color] = [Color(0.22, 0.46, 0.74), Color(0.24, 0.58, 0.46), Color(0.80, 0.82, 0.84),
	Color(0.62, 0.30, 0.24), Color(0.22, 0.46, 0.74), Color(0.70, 0.72, 0.74)]
const WASHING: Array[Color] = [Color(0.84, 0.16, 0.24), Color(0.94, 0.67, 0.12), Color(0.12, 0.47, 0.75),
	Color(0.16, 0.59, 0.35), Color(0.78, 0.24, 0.59), Color(0.96, 0.96, 0.94), Color(0.47, 0.24, 0.67),
	Color(0.94, 0.43, 0.16)]

const TYPES: PackedStringArray = ["sh", "sr", "of", "fl", "hs", "ah", "kp", "tn", "sc", "hp", "ch", "mq", "tp", "bk",
	"ht", "cn", "ml", "gv", "sd"]

## Deterministic 0..1 from a building seed and a salt (same building, same look, every load).
static func h01(seed_i: int, salt: int) -> float:
	var v: int = (seed_i * 2654435761 + salt * 40503 + 12345) & 0xFFFFFFFF
	v ^= v >> 15
	v = (v * 2246822519) & 0xFFFFFFFF
	v ^= v >> 13
	return float(v & 0xFFFF) / 65536.0

static func pick(cells: Array, seed_i: int, salt: int) -> Vector2:
	return cells[int(h01(seed_i, salt) * float(cells.size())) % cells.size()]

## The building's paint, aged by its seed: older walls are duller and dustier.
static func paint(t: String, zone: String, seed_i: int) -> Color:
	var palette: Array = PAINT_HOME
	match t:
		"sh", "ht":
			palette = PAINT_SHOPS
		"sr", "cn", "ml":
			palette = PAINT_SHOWROOM
		"ah":
			palette = PAINT_OLD
		"kp":
			palette = PAINT_HAMLET
		"tn":
			palette = PAINT_TENEMENT
		_:
			if PAINT_INSTITUTION.has(t):
				palette = PAINT_INSTITUTION[t]
	if t == "sh" and zone == "anna_salai":
		palette = [Color(0.80, 0.80, 0.82), Color(0.88, 0.85, 0.78), Color(0.70, 0.74, 0.80), Color(0.93, 0.92, 0.88)]
	var c: Color = palette[int(h01(seed_i, 11) * float(palette.size())) % palette.size()]
	if t in ["sr", "cn", "ml", "of", "sd"]:
		return c
	var age: float = h01(seed_i, 12)
	if t in ["ah", "tn"]:
		age = 0.5 + age * 0.5
	return c.lerp(DUST, age * 0.2).darkened(age * 0.1)

## How a building of type `t` is skinned.
##   front_ground / front_upper: cells picked per bay on walls that face a street
##   entrance:  ground cell used once, on the middle bay of each street front (null = none):
##              the door, gate or portico. front_ground then fills the other bays
##   side_ground / side_upper:   one cell per wall on the others (repeats along the wall)
##   balcony:   share of front bays that get a real projecting balcony
##   stair:     one front bay becomes the staircase jaali
##   shops:     ground bays are shops (awnings, boards repeated on the first floor)
##   ledges:    3D sunshade band over each front floor
##   roof:      "terrace", "tiles", "sheet", "thatch" or "flat" (flat = no terrace clutter)
##   sign:      hoarding cell stretched across the main front (-1 = none)
##   hoarding:  hoarding cell on a rooftop frame over the main front (-1 = none)
##   advert:    a side wall may carry the painted wall advert
static func style(t: String, zone: String, h: float, seed_i: int, rank: int) -> Dictionary:
	var s: Dictionary = {
		"entrance": null, "front_ground": [HOUSE_DOOR], "front_upper": [WIN_GRILLE, WIN_TWIN], "side_ground": [PLAIN],
		"side_upper": [WIN_GRILLE, VENTS, PLAIN, PARTY_WALL], "balcony": 0.0, "stair": false, "shops": false,
		"ledges": true, "roof": "terrace", "sign": -1, "hoarding": -1, "advert": false,
	}
	var r: float = h01(seed_i, 21)
	match t:
		"sh":
			s["front_ground"] = SHOPS
			s["shops"] = true
			s["front_upper"] = [WIN_GRILLE, BALCONY, WIN_TWIN, WIN_AC, WIN_BOX, BALCONY_WASH, WIN_AC, WIN_BOX]
			if zone == "anna_salai" and h > 13.0:
				s["front_upper"] = [OFFICE_STRIP, WIN_AC, OFFICE_STRIP, WIN_TWIN]
			s["side_upper"] = [PARTY_WALL, VENTS, PLAIN, PARTY_WALL]
			s["balcony"] = 0.5
			s["advert"] = true
			if rank >= 3 and h >= 6.0 and r < 0.22:
				s["hoarding"] = int(h01(seed_i, 22) * float(HOARDING_COUNT)) % HOARDING_COUNT
		"sr", "cn", "ml":
			var line: int = int(h01(seed_i, 23) * 4.0)
			var ground: Vector2 = [SHOW_SILK, SHOW_JEWEL, SHOW_GLASS, SHOW_SILK][line]
			s["front_ground"] = [ground]
			s["front_upper"] = [CLADDING, CLADDING, SHOW_GLASS]
			s["side_ground"] = [CLADDING]
			s["side_upper"] = [CLADDING, PARTY_WALL]
			s["ledges"] = false
			s["roof"] = "flat"
			s["sign"] = [0, 1, 2, 0][line] if t == "sr" else ([2, 7][line % 2])
			if h01(seed_i, 24) < 0.5:
				s["hoarding"] = [0, 1, 2, 7][line] if h01(seed_i, 25) < 0.6 else int(h01(seed_i, 26) * float(HOARDING_COUNT)) % HOARDING_COUNT
		"of":
			s["front_ground"] = [SHOW_GLASS, OFFICE_GLASS]
			s["front_upper"] = [OFFICE_GLASS] if seed_i % 2 == 0 else [OFFICE_STRIP]
			s["side_ground"] = [OFFICE_GLASS] if seed_i % 2 == 0 else [OFFICE_STRIP]
			s["side_upper"] = s["front_upper"]
			s["ledges"] = false
			s["roof"] = "flat"
		"fl":
			# Newer flats stand on stilt parking; older ones have a gate, a door and ground-floor homes.
			var stilts: bool = h >= 8.6 and h01(seed_i, 28) < 0.6
			s["front_ground"] = [STILT_BIKES, STILT_CAR, STILT_BIKES] if stilts else [WIN_GRILLE, COMPOUND, WIN_TWIN]
			if not stilts:
				s["entrance"] = PORTICO
			s["front_upper"] = [BALCONY, WIN_GRILLE, BALCONY_WASH, WIN_AC, BALCONY, WIN_BOX, WIN_TWIN]
			s["side_ground"] = [STILT_CAR, PLAIN] if stilts else [PLAIN, WIN_GRILLE]
			s["side_upper"] = [VENTS, WIN_GRILLE, WIN_BOX, PARTY_WALL, WIN_TWIN]
			s["balcony"] = 1.0
			s["stair"] = true
		"hs":
			s["entrance"] = PORTICO if r < 0.6 else HOUSE_DOOR
			s["front_ground"] = [WIN_GRILLE, COMPOUND, WIN_TWIN]
			s["front_upper"] = [BALCONY, WIN_GRILLE, WIN_TWIN, WIN_AC, BALCONY_WASH]
			s["side_upper"] = [WIN_GRILLE, VENTS, PLAIN, WIN_TWIN, PARTY_WALL]
			s["balcony"] = 0.7
			if h01(seed_i, 27) < 0.06 and rank > 0:   # the corner provision shop in a house front
				s["front_ground"] = [SHOPS[1], WIN_GRILLE, SHOPS[0]]
		"ah":
			s["front_ground"] = [THINNAI]
			s["front_upper"] = [HERITAGE_WIN]
			s["side_upper"] = [PARTY_WALL, HERITAGE_WIN, PLAIN]
			s["ledges"] = false
			s["roof"] = "tiles"
		"kp":
			s["entrance"] = SMALL_DOOR
			s["front_ground"] = [SMALL_DOOR, PLAIN, SMALL_DOOR]
			s["front_upper"] = [TENEMENT]
			s["side_upper"] = [PARTY_WALL, PLAIN]
			s["ledges"] = false
			s["roof"] = "thatch" if (h < 4.2 and r < 0.2) else ("sheet" if r < 0.75 else "terrace")
		"tn":
			s["front_ground"] = [TENEMENT]
			s["front_upper"] = [TENEMENT, TENEMENT, BALCONY_WASH]
			s["side_ground"] = [TENEMENT]
			s["side_upper"] = [TENEMENT, PARTY_WALL]
			s["stair"] = true
		"sc":
			s["entrance"] = COMPOUND
			s["front_ground"] = [SCHOOL]
			s["front_upper"] = [SCHOOL]
			s["side_ground"] = [SCHOOL]
			s["side_upper"] = [SCHOOL]
			s["ledges"] = false
		"hp":
			s["entrance"] = CLINIC
			s["front_ground"] = [SHOW_GLASS, HOSPITAL]
			s["front_upper"] = [HOSPITAL]
			s["side_upper"] = [HOSPITAL, WIN_AC]
			s["ledges"] = false
			if h >= 9.0:
				s["hoarding"] = 4
		"ch":
			s["entrance"] = CIVIC_DOOR
			s["front_ground"] = [CHURCH]
			s["front_upper"] = [CHURCH]
			s["side_ground"] = [CHURCH]
			s["side_upper"] = [CHURCH]
			s["ledges"] = false
			s["roof"] = "tiles"
		"mq":
			s["front_ground"] = [MOSQUE]
			s["front_upper"] = [MOSQUE]
			s["side_ground"] = [MOSQUE]
			s["side_upper"] = [MOSQUE]
			s["ledges"] = false
			s["roof"] = "flat"
		"tp":
			s["entrance"] = KAAVI_DOOR
			s["front_ground"] = [KAAVI]
			s["front_upper"] = [KAAVI]
			s["side_ground"] = [KAAVI]
			s["side_upper"] = [KAAVI]
			s["ledges"] = false
			s["roof"] = "flat"
		"bk":
			s["entrance"] = BANK
			s["front_ground"] = [SHOW_GLASS, OFFICE_STRIP]
			s["front_upper"] = [OFFICE_STRIP, WIN_AC]
			s["side_upper"] = [OFFICE_STRIP, PLAIN]
		"ht":
			s["front_ground"] = [SHOPS[4], SHOW_GLASS, SHOPS[6]]
			s["shops"] = true
			s["front_upper"] = [WIN_AC, BALCONY, WIN_AC, WIN_TWIN]
			s["side_upper"] = [WIN_AC, VENTS, PARTY_WALL]
			s["balcony"] = 0.5
			s["stair"] = true
		"gv":
			s["entrance"] = CIVIC_DOOR
			s["front_ground"] = [CIVIC]
			s["front_upper"] = [CIVIC]
			s["side_ground"] = [CIVIC]
			s["side_upper"] = [CIVIC]
			s["ledges"] = false
		"sd":
			s["front_ground"] = [PLAIN, SHUTTER]
			s["front_upper"] = [PLAIN]
			s["side_upper"] = [PLAIN]
			s["ledges"] = false
			s["roof"] = "sheet"
	return s
