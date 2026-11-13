extends Node
## Chennai building types: classified data, facade atlas, BuildingStyles, the typed geometry
## and its triangle budget (scripts/world/BuildingStyles.gd, WorldChunkStreamer._typed_building,
## tools/osm/classify_buildings.py, tools/art/make_facade_atlas.py).
## Run: godot --headless --path . res://tests/run_buildings_tests.tscn

const SQUARE: Array = [0.0, 0.0, 20.0, 0.0, 20.0, 12.0, 0.0, 12.0]

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("\n=== Namma Auto — Chennai building tests ===")
	_run.call_deferred()

func _run() -> void:
	_test_atlas()
	_test_styles()
	_test_world_data()
	_test_geometry()
	_test_budget()
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_atlas() -> void:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/facade_atlas.png"))
	_check("Facade atlas is 2048 x 2048 (8 x 8 cells of 256 px)", img != null and img.get_width() == 2048 and img.get_height() == 2048)
	if img == null:
		return
	# Every vertex-painted prop in the chunk mesh samples this one point: it must stay flat, near white and tintable.
	var px: Vector2i = Vector2i(int((WorldChunkStreamer.PLAIN_CELL.x + WorldChunkStreamer.PLAIN_UV.x) * 256.0),
		int((WorldChunkStreamer.PLAIN_CELL.y + 1.0 - WorldChunkStreamer.PLAIN_UV.y) * 256.0))
	var flat: bool = true
	for dx: int in range(-12, 13, 4):
		for dy: int in range(-12, 13, 4):
			var c: Color = img.get_pixel(px.x + dx, px.y + dy)
			if c.a < 0.99 or c.r < 0.9 or absf(c.r - c.g) > 0.02:
				flat = false
	_check("PLAIN cell stays flat near-white plaster round PLAIN_UV", flat, str(img.get_pixel(px.x, px.y)))
	var board: Color = img.get_pixel(3 * 256 + 40, 256 + 30)
	_check("Shop boards keep their own colour (tint mask 0)", board.a < 0.05, str(board))
	var hoarding: Color = img.get_pixel(128, 6 * 256 + 128)
	_check("Hoardings keep their own colour (tint mask 0)", hoarding.a < 0.05, str(hoarding))
	var imp: String = FileAccess.get_file_as_string("res://assets/textures/facade_atlas.png.import")
	_check("Atlas ships VRAM-compressed with mipmaps", imp.contains("compress/mode=2") and imp.contains("mipmaps/generate=true"))
	var shader: String = FileAccess.get_file_as_string("res://shaders/building_facade.gdshader")
	_check("Facade shader reads an 8 x 8 atlas and caps the mip level", shader.contains("vec2(8.0, 8.0)") and shader.contains("MAX_TEXELS_PER_PIXEL"))

func _test_styles() -> void:
	var keys_ok: bool = true
	var cells_ok: bool = true
	for t: String in BuildingStyles.TYPES:
		for zone: String in ["", "t_nagar", "anna_salai", "mylapore", "marina"]:
			for seed_i: int in [1, 77, 4242]:
				var st: Dictionary = BuildingStyles.style(t, zone, 12.0, seed_i, 3)
				for k: String in ["entrance", "front_ground", "front_upper", "side_ground", "side_upper", "balcony", "stair", "shops", "ledges", "roof", "sign", "hoarding", "advert"]:
					if not st.has(k):
						keys_ok = false
				for k: String in ["front_ground", "front_upper", "side_ground", "side_upper"]:
					for c: Vector2 in (st[k] as Array):
						if c.x < 0.0 or c.x > 7.0 or c.y < 0.0 or c.y > 7.0:
							cells_ok = false
				if int(st["sign"]) >= BuildingStyles.HOARDING_COUNT or int(st["hoarding"]) >= BuildingStyles.HOARDING_COUNT:
					cells_ok = false
				var p: Color = BuildingStyles.paint(t, zone, seed_i)
				if p.r < 0.0 or p.r > 1.0:
					cells_ok = false
	_check("Every building type has a complete style", keys_ok)
	_check("Styles only name cells inside the 8 x 8 atlas", cells_ok)
	_check("Styles are deterministic", BuildingStyles.style("sh", "t_nagar", 9.0, 5, 4).hash() == BuildingStyles.style("sh", "t_nagar", 9.0, 5, 4).hash()
		and BuildingStyles.paint("fl", "", 9) == BuildingStyles.paint("fl", "", 9))
	_check("Shop rows put a shop in every street bay", bool(BuildingStyles.style("sh", "", 9.0, 3, 4)["shops"]) and BuildingStyles.SHOPS.size() == 13)
	_check("Showrooms carry a giant sign", int(BuildingStyles.style("sr", "t_nagar", 16.0, 3, 4)["sign"]) >= 0)
	_check("Old houses take a tiled roof, sheds a sheet roof", str(BuildingStyles.style("ah", "mylapore", 6.0, 3, 1)["roof"]) == "tiles"
		and str(BuildingStyles.style("sd", "", 6.0, 3, 1)["roof"]) == "sheet")
	var spread: float = 0.0
	for i: int in 200:
		spread += BuildingStyles.h01(i, 7)
	_check("Seed hash is well spread over 0..1", spread > 80.0 and spread < 120.0, "%.1f" % spread)

func _test_world_data() -> void:
	var total: int = 0
	var typed: int = 0
	var fronted: int = 0
	var bad_wall: int = 0
	var counts: Dictionary = {}
	for file_name: String in DirAccess.get_files_at("res://data/world/chunks"):
		if not file_name.ends_with(".json"):
			continue
		var chunk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/chunks/" + file_name)) as Dictionary
		for b: Dictionary in chunk.get("blds", []):
			total += 1
			if not b.has("t"):
				continue
			typed += 1
			var t: String = str(b["t"])
			counts[t] = int(counts.get(t, 0)) + 1
			if b.has("fw"):
				fronted += 1
				for w: Array in (b["fw"] as Array):
					if int(w[0]) < 0 or int(w[0]) >= (b["p"] as Array).size() / 2 or int(w[1]) < 1 or int(w[1]) > 5:
						bad_wall += 1
	_check("Every building in the world is classified", total > 40000 and typed == total, "%d of %d" % [typed, total])
	var known: bool = true
	for t: String in counts:
		if not BuildingStyles.TYPES.has(t):
			known = false
	_check("Only known building types are used", known, str(counts.keys()))
	_check("Thousands of shop rows line the main roads", int(counts.get("sh", 0)) > 4000, str(counts.get("sh", 0)))
	_check("Showrooms, old houses, hamlets and tenements all exist", int(counts.get("sr", 0)) > 200 and int(counts.get("ah", 0)) > 300
		and int(counts.get("kp", 0)) > 150 and int(counts.get("tn", 0)) > 50, str(counts))
	_check("Homes still outnumber shops", int(counts.get("hs", 0)) + int(counts.get("fl", 0)) > int(counts.get("sh", 0)) * 3)
	_check("About half the buildings face a street", fronted > total * 0.4 and fronted < total * 0.75, "%d of %d" % [fronted, total])
	_check("Street-facing walls point at real walls with a valid road rank", bad_wall == 0, "%d bad" % bad_wall)

func _arrays(s: WorldChunkStreamer, blds: Array) -> Array:
	var holder: Node3D = s._buildings(blds)
	var mi: MeshInstance3D = holder.get_node("BuildingMeshes") as MeshInstance3D
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var out: Array = [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_TEX_UV2], arrays[Mesh.ARRAY_TEX_UV],
		holder.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D).size()]
	holder.free()
	return out

func _uses(uv2: PackedVector2Array, cells: Array) -> int:
	var n: int = 0
	for v: Vector2 in uv2:
		if cells.has(v):
			n += 1
	return n

func _test_geometry() -> void:
	var s: WorldChunkStreamer = WorldChunkStreamer.new()
	s._bld_mat = ShaderMaterial.new()
	# Wall 1 runs (0,0) → (20,0): the street front. The other three face nothing.
	var shop: Array = _arrays(s, [{"p": SQUARE, "h": 9.6, "k": "", "z": "", "s": 3, "t": "sh", "fw": [[1, 4]]}])
	var verts: PackedVector3Array = shop[0]
	var uv2: PackedVector2Array = shop[1]
	_check("Typed building is still one mesh", int(shop[3]) == 1)
	var front_shops: int = 0
	var other_shops: int = 0
	for i: int in verts.size():
		if BuildingStyles.SHOPS.has(uv2[i]) or uv2[i] == BuildingStyles.SHUTTER:
			if verts[i].z < 0.5:
				front_shops += 1
			else:
				other_shops += 1
	_check("Shops stand on the street front, one per bay", front_shops >= 6 * 5, "%d verts" % front_shops)
	_check("Walls that face no street get no shops", other_shops == 0, "%d verts" % other_shops)
	var out_front: int = 0
	var out_other: int = 0
	for v: Vector3 in verts:
		if v.z < -0.3 and v.y > 3.0:
			out_front += 1
		if v.x < -0.3 or v.x > 20.3 or v.z > 12.3:
			out_other += 1
	_check("Sunshades and balconies stick out over the street", out_front > 0)
	_check("Blind walls stay flat (no detail triangles spent there)", out_other == 0, "%d verts" % out_other)

	var flats: Array = _arrays(s, [{"p": SQUARE, "h": 12.8, "k": "", "z": "", "s": 5, "t": "fl", "fw": [[1, 1]]}])
	_check("Flats show balconies or the staircase jaali on the street front",
		_uses(flats[1], [BuildingStyles.BALCONY, BuildingStyles.BALCONY_WASH, BuildingStyles.JAALI]) > 0)
	var showroom: Array = _arrays(s, [{"p": SQUARE, "h": 16.0, "k": "", "z": "t_nagar", "s": 5, "t": "sr", "fw": [[1, 4]]}])
	var signs: int = 0
	for v: Vector2 in (showroom[1] as PackedVector2Array):
		if is_equal_approx(v.y, BuildingStyles.HOARDING_ROW):
			signs += 1
	_check("Showroom carries its name across the front", signs >= 6, "%d verts" % signs)
	_check("Showroom walls are cladding and glass", _uses(showroom[1], [BuildingStyles.CLADDING, BuildingStyles.SHOW_GLASS]) > 0)

	var old_house: Array = _arrays(s, [{"p": [0.0, 0.0, 9.0, 0.0, 9.0, 6.0, 0.0, 6.0], "h": 3.4, "k": "", "z": "mylapore", "s": 5, "t": "ah", "fw": [[1, 1]]}])
	var top: float = 0.0
	for v: Vector3 in (old_house[0] as PackedVector3Array):
		top = maxf(top, v.y)
	_check("Old house gets a pitched tiled roof", _uses(old_house[1], [BuildingStyles.ROOF_TILES]) >= 12 and top > 3.4 + 0.8, "ridge %.1f" % top)
	_check("…with a thinnai on the street", _uses(old_house[1], [BuildingStyles.THINNAI]) > 0)

	var hut: Array = _arrays(s, [{"p": [0.0, 0.0, 6.0, 0.0, 6.0, 4.0, 0.0, 4.0], "h": 3.0, "k": "", "z": "marina", "s": 2, "t": "kp", "fw": [[1, 1]]}])
	_check("Hamlet dwelling has a door on the lane", _uses(hut[1], [BuildingStyles.SMALL_DOOR]) > 0)

	# Roof UVs are world metres / 6 and run high; UV2.y must never reach the shop-hours gate (> 50).
	var gate_safe: bool = true
	for arr: Array in [shop, flats, showroom, old_house, hut]:
		for v: Vector2 in (arr[1] as PackedVector2Array):
			if v.y > 50.0 or v.x > 7.5:
				gate_safe = false
	_check("Typed buildings never touch the shop-hours gate in UV2", gate_safe)

	# No "t": the older generic skin still builds (tests, partial data, an OSM rebuild in progress).
	var legacy: Array = _arrays(s, [{"p": SQUARE, "h": 9.6, "k": "", "z": "", "s": 3}])
	_check("A building without a type still draws (older skin)", (legacy[0] as PackedVector3Array).size() > 100)
	WorldChunkStreamer.typed_enabled = false
	var off: Array = _arrays(s, [{"p": SQUARE, "h": 9.6, "k": "", "z": "", "s": 3, "t": "sh", "fw": [[1, 4]]}])
	WorldChunkStreamer.typed_enabled = true
	_check("typed_enabled = false falls back to the older skin", (off[0] as PackedVector3Array).size() == (legacy[0] as PackedVector3Array).size())
	s.free()

## The new look must not cost more triangles than the old one did: detail moved to the street
## fronts, it was not added on top.
func _test_budget() -> void:
	var s: WorldChunkStreamer = WorldChunkStreamer.new()
	s._bld_mat = ShaderMaterial.new()
	var new_total: int = 0
	var old_total: int = 0
	var worst: int = 0
	var slowest_ms: int = 0
	for key: String in ["c_0_0", "c_-12_8", "c_6_-4", "c_4_6", "c_-9_4", "c_-3_-2"]:
		var chunk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/chunks/%s.json" % key)) as Dictionary
		var blds: Array = chunk.get("blds", [])
		var t0: int = Time.get_ticks_msec()
		var now: int = (_arrays(s, blds)[0] as PackedVector3Array).size()
		slowest_ms = maxi(slowest_ms, Time.get_ticks_msec() - t0)
		WorldChunkStreamer.typed_enabled = false
		var before: int = (_arrays(s, blds)[0] as PackedVector3Array).size()
		WorldChunkStreamer.typed_enabled = true
		new_total += now
		old_total += before
		worst = maxi(worst, now)
	_check("Typed buildings cost no more vertices than the older skin", new_total <= old_total, "%d vs %d" % [new_total, old_total])
	_check("No sampled chunk's building mesh passes 180k vertices", worst < 180000, "%d" % worst)
	print("        vertices in 6 chunks: %d typed vs %d older skin; worst chunk %d; slowest build %d ms (info only)" % [new_total, old_total, worst, slowest_ms])
	s.free()

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  " + name)
	else:
		_failed += 1
		print("  FAIL  " + name + ("" if detail == "" else "  (" + detail + ")"))
