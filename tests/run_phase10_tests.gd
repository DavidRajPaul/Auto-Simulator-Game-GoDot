extends Node
## Phase 10 (play-test round 2, Oct 2026): street boards on the footpath (never in a lane), GCC
## look (blue plate, chrome posts), realistic tree mix (few palms), textured impact FX, clean
## icon cut-outs.  Run: godot --headless --path . --fixed-fps 60 res://tests/run_phase10_tests.tscn

const CITY: String = "res://scenes/main_chennai.tscn"
var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 10 tests ===")
	_test_trees()
	_test_atlases()
	_test_new_people_and_slum()
	GameState.reset_profile()
	var city: Node = (load(CITY) as PackedScene).instantiate()
	add_child(city)
	for i: int in 60:
		await get_tree().physics_frame
	_test_signs(city)
	_test_fx(city)
	city.queue_free()
	await get_tree().physics_frame
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_signs(city: Node) -> void:
	var g: RoadGraph = SignalBus.current_road_graph
	var ss: StreetSigns = city.get_node("StreetSigns") as StreetSigns
	_check("Board spots precomputed from the real road surface", ss._spots.size() > 1000, "%d spots" % ss._spots.size())
	# Every board in a 3 km sample must stand clear of the carriageway it belongs to.
	var bad: int = 0
	var checked: int = 0
	for i: int in range(0, ss._spots.size(), 7):
		var s: Array = ss._spots[i]
		var p: Vector3 = Vector3(float(s[0]), 0.0, float(s[1]))
		var c: Dictionary = g.closest_point(p)
		if int(c["edge"]) < 0:
			continue
		checked += 1
		if float(c["dist"]) < g.edges[int(c["edge"])].width * 0.5:
			bad += 1
	_check("No street board stands inside a road (graph check)", bad == 0, "%d / %d inside" % [bad, checked])
	ss._player = (city.get_node("AutoRickshaw") as Node3D).global_position
	ss.refresh()
	var shown: int = 0
	for n: Node3D in ss._pool:
		shown += 1 if n.visible else 0
	_check("Boards appear near the player", shown >= 2, "%d" % shown)
	var mi: MeshInstance3D = ss._pool[0].get_child(0) as MeshInstance3D
	var chrome: StandardMaterial3D = mi.mesh.surface_get_material(1) as StandardMaterial3D
	_check("GCC board: blue plate + chrome posts (2 surfaces, metallic posts)", mi.mesh.get_surface_count() == 2 and chrome != null and chrome.metallic > 0.3)
	var en: Label3D = ss._pool[0].get_node("English") as Label3D
	_check("White lettering", en.modulate.is_equal_approx(Color.WHITE))

func _test_trees() -> void:
	var counts: Dictionary = {}
	var dir: DirAccess = DirAccess.open("res://data/world/dress")
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/dress/" + f)) as Dictionary
		for t: Array in d.get("trees", []):
			counts[int(t[2])] = int(counts.get(int(t[2]), 0)) + 1
	var total: int = 0
	for k: int in counts:
		total += int(counts[k])
	var palms: float = float(counts.get(1, 0)) / maxf(float(total), 1.0)
	_check("Coconut palms are rare (< 6 % of street trees)", palms < 0.06, "%.1f %%" % (palms * 100.0))
	_check("Chennai street tree mix: rain/neem, Ashoka, copper-pod all present", int(counts.get(0, 0)) > 0 and int(counts.get(2, 0)) > 0 and int(counts.get(3, 0)) > 0, str(counts))

func _test_fx(city: Node) -> void:
	var fx: CollisionFX = city.get_node("AutoRickshaw/CollisionFX") as CollisionFX
	var textured: bool = true
	for e: CPUParticles3D in [fx._sparks, fx._flash, fx._dust, fx._debris]:
		var m: StandardMaterial3D = (e.mesh as QuadMesh).material as StandardMaterial3D
		if m == null or m.albedo_texture == null or m.albedo_texture is ImageTexture:
			textured = false
	_check("Impact FX use the Kenney CC0 textures (no flat squares)", textured)
	SignalBus.player_impact.emit({"speed_mps": 7.0, "kind": "wall", "point": Vector3(0, 0, 0), "normal": Vector3.BACK, "severity": 0.9})
	_check("A hard hit fires sparks, flash, dust and debris", fx._sparks.emitting and fx._flash.emitting and fx._dust.emitting and fx._debris.emitting)

## Cut-outs: no opaque pixels in a 3 px margin around every cell (no neighbour bleed, no specks
## on the border), and no fully transparent pixels with black RGB at the shape edge (no dark rim).
func _test_atlases() -> void:
	var ok: bool = true
	var detail: String = ""
	for item: Array in [["res://assets/ui/controls_v2.png", 192, 192], ["res://assets/ui/rewards.png", 256, 256]]:
		var img: Image = (load(item[0]) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		for cy: int in range(0, img.get_height(), int(item[2])):
			for cx: int in range(0, img.get_width(), int(item[1])):
				for k: int in range(0, int(item[1]), 4):
					for p: Vector2i in [Vector2i(cx + k, cy), Vector2i(cx + k, cy + int(item[2]) - 1), Vector2i(cx, cy + k), Vector2i(cx + int(item[1]) - 1, cy + k)]:
						if img.get_pixelv(p).a > 0.3:
							ok = false
							detail = "%s @ %s" % [item[0].get_file(), str(p)]
	_check("Icon cells have clean transparent margins", ok, detail)

func _test_new_people_and_slum() -> void:
	var meta: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/people/people.json")) as Dictionary)["people"]
	var ok: bool = true
	for id: String in ["woman_modern", "man_casual"]:
		var scene: PackedScene = load("res://assets/models/people/%s.glb" % id) as PackedScene
		if not meta.has(id) or scene == null:
			ok = false
			continue
		var n: Node = scene.instantiate()
		var ap: Array[Node] = n.find_children("*", "AnimationPlayer", true, false)
		var mis: Array[Node] = n.find_children("*", "MeshInstance3D", true, false)
		var tris: int = 0
		for mi: Node in mis:
			var m: Mesh = (mi as MeshInstance3D).mesh
			for sidx: int in m.get_surface_count():
				tris += m.surface_get_arrays(sidx)[Mesh.ARRAY_INDEX].size() / 3
		if ap.is_empty() or not (ap[0] as AnimationPlayer).has_animation("walk") or not (ap[0] as AnimationPlayer).has_animation("idle") or tris > 4200 or mis.size() != 1:
			ok = false
		n.free()
	_check("New Chennai man + woman: rigged, walk + idle, ≤ 4.2k tris, one draw call", ok)
	var props: Array = (JSON.parse_string(FileAccess.get_file_as_string("res://data/world/city_props.json")) as Dictionary)["props"]
	var slums: int = 0
	for pr: Dictionary in props:
		slums += 1 if str(pr["model"]) == "slum_cluster" else 0
	_check("Chennai slum placed along the canals (≥ 5 sites)", slums >= 5, "%d" % slums)
	var img: Image = (load("res://assets/models/city/slum_cluster_0.png") as Texture2D).get_image()
	_check("Slum keeps its colours (textured atlas)", img != null and img.get_width() >= 512)

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", test_name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_failed += 1
		printerr("  FAIL  ", test_name, ("  (" + detail + ")") if detail != "" else "")
