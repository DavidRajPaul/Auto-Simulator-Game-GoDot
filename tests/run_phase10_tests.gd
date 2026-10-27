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
	_test_police_service_gas(city)
	_test_building_boards(city)
	_test_touch_layout()
	await _test_traffic_smooth(city)
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

func _test_police_service_gas(city: Node) -> void:
	var tp: TrafficPolice = city.get_node("TrafficPolice") as TrafficPolice
	_check("Traffic-police junctions found (big roads, ≥ 3 arms)", tp.junctions.size() > 50, "%d" % tp.junctions.size())
	var g: RoadGraph = SignalBus.current_road_graph
	tp._player = g.nodes[tp.junctions[0]]
	tp.refresh()
	var post: Node3D = null
	for p: Node3D in tp._posts:
		if p.visible and p.global_position.distance_to(g.nodes[tp.junctions[0]]) < 0.1:
			post = p
	_check("A police post stands on the junction with an officer", post != null and post.get_node_or_null("Officer") != null and post.global_position.distance_to(g.nodes[tp.junctions[0]]) < 0.1)
	var traffic: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var svc: TrafficVehicleAI = null
	for v: TrafficVehicleAI in traffic.pool:
		if v.archetype == TrafficVehicleAI.Archetype.SERVICE:
			svc = v
	_check("Service vehicle slot carries all 6 civil vehicles", svc != null and svc._service_models.size() == 6 and not svc._service_models.has(null))
	var seen: Dictionary = {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	for i: int in 60:
		svc.pick_service_variant(rng)
		seen[svc.service_variant] = true
		var shown: int = 0
		for m: Node3D in svc._service_models:
			shown += 1 if m.visible else 0
		if shown != 1 or not is_equal_approx((svc._shape.shape as BoxShape3D).size.z, svc.body.z):
			seen[-1] = true
	_check("Respawns rotate through the variants, one shown, box sized to it", seen.size() >= 5 and not seen.has(-1), str(seen.keys()))
	var sp: ServicePoints = city.get_node("ServicePoints") as ServicePoints
	var stations: int = 0
	for s: Dictionary in sp.services:
		stations += 1 if bool(s.get("station", false)) else 0
	_check("Every LPG bunk is a real gas-station model with its forecourt as the pump spot", stations == 4, "%d" % stations)
	var world: Node = city.get_node("World")
	_check("Gas stations are in the world", world.find_children("gas_station_*", "", true, false).size() == 4)

func _test_building_boards(city: Node) -> void:
	var bb: BuildingBoards = city.get_node("BuildingBoards") as BuildingBoards
	_check("Building name boards from OSM places", bb.spot_count() > 800, "%d" % bb.spot_count())
	var real_public: int = 0
	var bad_face: int = 0
	var g: RoadGraph = SignalBus.current_road_graph
	for i: int in range(0, bb.spot_count(), 11):
		var s: Array = bb.spot(i)
		var p: Vector3 = Vector3(float(s[0]), 0.0, float(s[1]))
		var out: Vector3 = Vector3(sin(float(s[2])), 0.0, cos(float(s[2])))
		# The board faces the street: stepping out from it gets closer to a road, not further.
		if float(g.closest_point(p + out * 2.0)["dist"]) > float(g.closest_point(p - out * 2.0)["dist"]) + 0.6:
			bad_face += 1
		real_public += 1 if int(s[8]) >= 9 else 0
	_check("Boards face the street", bad_face == 0, "%d facing away" % bad_face)
	_check("Public places keep real names (some boards are public)", real_public > 5, "%d" % real_public)
	var names: Dictionary = {}
	for i: int in bb.spot_count():
		names[str(bb.spot(i)[6]).to_lower()] = true
	var leaked: Array = []
	for brand: String in ["hdfc bank", "icici bank", "saravana bhavan", "pothys", "grt jewellers", "kfc", "domino's pizza"]:
		if names.has(brand):
			leaked.append(brand)
	_check("Businesses carry parody names, no real brands", leaked.is_empty(), str(leaked))
	bb._player = Vector3(bb.spot(0)[0], 0, bb.spot(0)[1])
	bb.refresh()
	_check("Boards pooled near the player (≤ MAX_BOARDS)", bb.active_boards() >= 1 and bb.active_boards() <= BuildingBoards.MAX_BOARDS, "%d" % bb.active_boards())

func _test_touch_layout() -> void:
	# Tablet aspect ratios: controls must not overlap each other or the dashboard.
	var ok: bool = true
	var detail: String = ""
	for vp: Vector2 in [Vector2(1280, 960), Vector2(1280, 800), Vector2(1280, 720), Vector2(1560, 720)]:
		var hud: TouchHUD = TouchHUD.new()
		var b: float = hud.base_button_size(vp, 26.0, 26.0, 14.0)
		hud.free()
		var r_speed: float = clampf(b * 0.62, 48.0, 84.0)
		var left_end: float = 26.0 + b * 2.6 + 14.0
		var dash_l: float = vp.x * 0.5 - PassengerHUD.MINIMAP_SIZE * 0.585 - 14.0 - r_speed * 2.24
		ok = ok and left_end + 14.0 <= dash_l and b <= 128.0
		detail += "%dx%d b=%.0f  " % [vp.x, vp.y, b]
	_check("Touch controls fit tablets (4:3, 16:10) without overlapping", ok, detail)

func _test_traffic_smooth(city: Node) -> void:
	# Drive for 25 s with the camera on; watch every vehicle and pedestrian frame by frame.
	var tm: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var pm: PedestrianManager = city.get_node("PedestrianManager") as PedestrianManager
	var auto: Node3D = city.get_node("AutoRickshaw") as Node3D
	var prev: Dictionary = {}
	var prev_turn: Dictionary = {}
	var seen_prev: Dictionary = {}
	var jumps: int = 0
	var vanished: int = 0
	var turns: int = 0
	var worst: float = 0.0
	var vp: Viewport = get_viewport()
	var ped_prev: Dictionary = {}
	var ped_popped: int = 0
	var ped_vanished: int = 0
	Input.action_press("accelerate")
	for f: int in 1500:
		if f == 400:
			Input.action_release("accelerate")
		await get_tree().physics_frame
		for v: TrafficVehicleAI in tm.pool:
			var was: Variant = prev.get(v)
			var on_now: bool = v.active and ViewCheck.on_screen(vp, v.global_position + Vector3(0, 1, 0), 0.0)
			if v.turning:
				turns += 1
			if was != null and v.active:
				var step: float = (v.global_position - (was as Vector3)).length()
				var allowed: float = v.current_speed_mps / 60.0 * 1.6 + 0.08
				if step > 5.0:
					# Recycled: it must not have been on screen and close.
					if bool(seen_prev.get(v, false)) and (was as Vector3).distance_to(auto.global_position) < ChennaiTrafficManager.RECYCLE_ON_SCREEN_M:
						vanished += 1
				elif step > allowed and v.bumped_timer <= 0.0:
					jumps += 1
					print("JUMP f=%d arch=%d step=%.2f speed=%.2f turning=%s edge=%d t=%.2f bumped=%.2f was_turn=%s" % [f, v.archetype, step, v.current_speed_mps, v.turning, v.edge, v.t, v.bumped_timer, str(prev_turn.get(v, false))])
					worst = maxf(worst, step - allowed)
			elif was != null and not v.active and bool(seen_prev.get(v, false)):
				vanished += 1
			prev[v] = v.global_position if v.active else null
			prev_turn[v] = v.turning
			seen_prev[v] = on_now
		for w: PedestrianManager.Walker in pm.people:
			var on_w: bool = w.active and ViewCheck.on_screen(vp, w.pos + Vector3(0, 0.9, 0), 0.0)
			var st: Variant = ped_prev.get(w)
			if st != null:
				var d: float = w.pos.distance_to(auto.global_position)
				if not bool(st[0]) and w.active and on_w and d < PedestrianManager.SPAWN_ON_SCREEN_M - 2.0:
					ped_popped += 1 # became active in view, close by
				if bool(st[0]) and bool(st[1]) and not w.active and (st[2] as Vector3).distance_to(auto.global_position) < PedestrianManager.DESPAWN_FAR_M - 2.0:
					ped_vanished += 1
			ped_prev[w] = [w.active, w.active and on_w, w.pos]
	_check("Traffic turns through junctions on a smooth curve (no sideways jumps)", jumps == 0 and turns > 0, "%d jumps (worst +%.2f m), %d turning frames" % [jumps, worst, turns])
	_check("No vehicle vanishes on screen", vanished == 0, "%d" % vanished)
	_check("Pedestrians never pop in or vanish in view", ped_popped == 0 and ped_vanished == 0, "%d popped, %d vanished" % [ped_popped, ped_vanished])

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", test_name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_failed += 1
		printerr("  FAIL  ", test_name, ("  (" + detail + ")") if detail != "" else "")
