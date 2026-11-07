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
	await _test_signals_falls_medians(city)
	_test_fx(city)
	_test_police_service_gas(city)
	_test_building_boards(city)
	_test_touch_layout()
	await _test_traffic_smooth(city)
	await _test_signals_work(city)
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

## Nov 6 device report: a signal pole in the middle of the road, boards that never fell, and
## bare gaps where Chennai has median kerbs and railings.
func _test_signals_falls_medians(city: Node) -> void:
	var tm: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var g: RoadGraph = tm.graph
	var spots: int = 0
	var in_road: int = 0
	var facing_ok: int = 0
	var junctions_with_posts: int = 0
	for node_id: int in tm._signal_nodes:
		var posts: Array[Transform3D] = tm.signal_post_spots(node_id)
		junctions_with_posts += 1 if not posts.is_empty() else 0
		for xf: Transform3D in posts:
			spots += 1
			var c: Dictionary = g.closest_point(xf.origin)
			if int(c["edge"]) >= 0 and float(c["dist"]) < g.edges[int(c["edge"])].width * 0.5:
				in_road += 1
			# Lamps (local +Z) look away from the junction, at the queue waiting to cross.
			var out: Vector3 = (xf.origin - g.nodes[node_id]) * Vector3(1, 0, 1)
			facing_ok += 1 if (xf.basis * Vector3.BACK).dot(out.normalized()) > 0.0 else 0
	_check("Signal posts measured on the kerb for nearly every signal junction",
		junctions_with_posts >= int(tm._signal_nodes.size() * 0.95), "%d / %d" % [junctions_with_posts, tm._signal_nodes.size()])
	_check("No signal post stands in a carriageway", spots > 300 and in_road == 0, "%d of %d in a lane" % [in_road, spots])
	_check("Signal lamps face the approaching traffic", facing_ok >= int(spots * 0.95), "%d / %d" % [facing_ok, spots])
	_check("Signal post = 2 draw calls (body + swapped lamp mesh)", tm._signal_posts[0].get_child_count() == 2)
	# Boards: the auto lives on physics layer 2; the impact sensor must see it, and one real hit flattens the board.
	var ss: StreetSigns = city.get_node("StreetSigns") as StreetSigns
	var area: Area3D = ss._pool[0].get_node("ImpactArea") as Area3D
	var auto: RigidBody3D = city.get_node("AutoRickshaw") as RigidBody3D
	_check("Board impact sensor sees the player auto's physics layer", (area.collision_mask & auto.collision_layer) != 0)
	var board: Node3D = null
	for n: Node3D in ss._pool:
		if n.visible:
			board = n
			break
	if board != null:
		ss.knock_down(board, board.global_basis * Vector3(0.0, 0.0, -8.0))
		for i: int in 60:
			await get_tree().physics_frame
		_check("A hit board falls flat and stops blocking", absf(board.rotation.x) > 1.3 and board.get_node("Solid").process_mode == Node.PROCESS_MODE_DISABLED,
			"tilt %.2f rad" % board.rotation.x)
	# Medians: real data on the divided roads, drawn and solid.
	var med_chunks: int = 0
	var styles: Dictionary = {}
	var sample: Array = []
	var dir: DirAccess = DirAccess.open("res://data/world/dress")
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/dress/" + f)) as Dictionary
		var meds: Array = d.get("medians", [])
		if not meds.is_empty():
			med_chunks += 1
			sample = meds
			for m: Array in meds:
				styles[str(m[0])] = true
	_check("Divided roads get centre medians (railing and delineator looks)", med_chunks > 40 and styles.has("A") and styles.has("B"), "%d chunks %s" % [med_chunks, styles.keys()])
	var world: WorldChunkStreamer = city.get_node("World") as WorldChunkStreamer
	var holder: Node3D = world._buildings([], {"medians": sample}, [])
	var shape: CollisionShape3D = null
	for ch: Node in holder.get_children():
		if ch is CollisionShape3D:
			shape = ch as CollisionShape3D
	_check("Medians are solid (in the chunk collider)", shape != null and (shape.shape as ConcavePolygonShape3D).get_faces().size() > 100)
	holder.free()

## Nov 7: "did you check the traffic signals work?" — they didn't: every road at a junction got
## green at the same time, and the red-light check could never fire.
func _test_signals_work(city: Node) -> void:
	var tm: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var g: RoadGraph = tm.graph
	var auto: RigidBody3D = city.get_node("AutoRickshaw") as RigidBody3D
	# 1. Conflicting roads never share a green, every junction has two phases, all lights cycle.
	var both_phases: int = 0
	var clash: int = 0
	var cycles: int = 0
	for node_id: int in tm._signal_nodes:
		var groups: Dictionary = tm._signal_group[node_id]
		var has: Array[bool] = [false, false]
		for ei: Variant in groups:
			has[int(groups[ei])] = true
		both_phases += 1 if has[0] and has[1] else 0
		var seen: Dictionary = {}
		for step: int in 64:
			tm.signal_clock_override = float(step) * ChennaiTrafficManager.SIGNAL_CYCLE_S / 64.0
			var green_groups: Dictionary = {}
			for ei: Variant in groups:
				var l: int = tm.approach_light(node_id, int(ei))
				seen[l] = true
				if l != ChennaiTrafficManager.Light.RED:
					green_groups[int(groups[ei])] = true
			clash += 1 if green_groups.size() > 1 else 0
		cycles += 1 if seen.size() == 3 else 0
	var n: int = tm._signal_nodes.size()
	_check("Every signal junction has a main-road and a cross-road phase", both_phases == n, "%d / %d" % [both_phases, n])
	_check("Cross roads never get green / amber together", clash == 0, "%d clashes" % clash)
	_check("Every signal cycles green → amber → red", cycles == n, "%d / %d" % [cycles, n])
	# Pick a junction with a long two-way approach for the live checks.
	var node_id: int = -1
	var approach: int = -1
	for nid: int in tm._signal_nodes:
		for ei: int in g.node_edges[nid]:
			var e: RoadGraph.Edge = g.edges[ei]
			var dir_in: int = 1 if e.b == nid else -1
			if e.length > 90.0 and (e.lanes_fwd if dir_in > 0 else e.lanes_back) > 0:
				node_id = nid
				approach = ei
				break
		if node_id >= 0:
			break
	if node_id < 0:
		_check("Found a signal approach to test", false)
		return
	var edge: RoadGraph.Edge = g.edges[approach]
	var dir: int = 1 if edge.b == node_id else -1
	var group: int = int((tm._signal_group[node_id] as Dictionary)[approach])
	var half: float = ChennaiTrafficManager.SIGNAL_CYCLE_S * 0.5
	# Clock values (before the node's own offset) that put this approach at red / green.
	var offset: float = float(node_id * 7)
	var red_clock: float = fposmod(float(group) * half + ChennaiTrafficManager.SIGNAL_GREEN_S + ChennaiTrafficManager.SIGNAL_AMBER_S + 0.5 - offset, ChennaiTrafficManager.SIGNAL_CYCLE_S)
	var green_clock: float = fposmod(float(group) * half + 1.0 - offset, ChennaiTrafficManager.SIGNAL_CYCLE_S)
	tm.signal_clock_override = red_clock
	_check("Clock helper: approach is red", tm.approach_light(node_id, approach) == ChennaiTrafficManager.Light.RED)
	# 2. Traffic queues at the stop line on red and goes on green.
	auto.freeze = true
	auto.global_position = g.nodes[node_id] + Vector3(0, 1.0, 0) + (g.edges[approach].points[0] - g.nodes[node_id]).normalized() * 0.0 + Vector3(18, 0, 18)
	for o: TrafficVehicleAI in tm.pool:
		if o.active:
			o.deactivate()
	var v: TrafficVehicleAI = tm.pool[0]
	tm.place_vehicle(v, approach, edge.length - 70.0 if dir > 0 else 70.0, dir, 0)
	v.current_speed_mps = v.cruise_speed_mps
	# Up to 20 s of red: the car must come to rest and never roll past the stop line.
	var closest: float = INF
	for i: int in 1200:
		await get_tree().physics_frame
		if v.edge == approach and not v.turning:
			closest = minf(closest, g.edges[approach].length - v.t - v.half_length())
		if i > 300 and v.current_speed_mps < 0.2:
			break
	var left_to_node: float = g.edges[v.edge].length - v.t if v.edge == approach else -1.0
	_check("On red, traffic stops before the stop line (not in the junction)",
		v.active and v.edge == approach and v.current_speed_mps < 0.5 and closest >= tm.signal_stop_back(node_id) - 0.05 and left_to_node - v.half_length() < tm.signal_stop_back(node_id) + 4.5 and not v.turning,
		"bumper %.1f m from the junction centre, stop line %.1f m, %.1f m/s" % [left_to_node - v.half_length(), tm.signal_stop_back(node_id), v.current_speed_mps])
	tm.signal_clock_override = green_clock
	for i: int in 600:
		await get_tree().physics_frame
	_check("On green, the queue drives through", v.edge != approach or v.turning, "edge %d (approach %d)" % [v.edge, approach])
	# Amber: too close to stop comfortably → keep going; far away → stop.
	tm.place_vehicle(v, approach, edge.length - 20.0 if dir > 0 else 20.0, dir, 0)
	v.current_speed_mps = 12.0
	var amber_clock: float = fposmod(float(group) * half + ChennaiTrafficManager.SIGNAL_GREEN_S + 0.2 - offset, ChennaiTrafficManager.SIGNAL_CYCLE_S)
	tm.signal_clock_override = amber_clock
	_check("Amber when too close to brake: drive on", tm.signal_stop_gap(v) == INF)
	tm.place_vehicle(v, approach, edge.length - 80.0 if dir > 0 else 80.0, dir, 0)
	_check("Amber with room to brake: stop", tm.signal_stop_gap(v) < INF)
	v.deactivate()
	# 3. Lamps: each post shows its own road's light.
	tm.signal_clock_override = green_clock
	auto.global_position = g.nodes[node_id] + Vector3(0, 1.0, 0)
	tm._refresh_signal_lights()
	var shown_ok: int = 0
	var shown: int = 0
	for i: int in tm._signal_posts.size():
		var post: Node3D = tm._signal_posts[i]
		if not post.visible or tm._signal_post_edge[i] < 0:
			continue
		shown += 1
		var l: int = tm.approach_light(tm._signal_post_node[i], tm._signal_post_edge[i])
		var want: ArrayMesh = tm._signal_lamp_meshes[2 if l == 0 else (1 if l == 1 else 0)]
		shown_ok += 1 if (post.get_node("Lamps") as MeshInstance3D).mesh == want else 0
	_check("Each signal post shows its own road's light", shown > 0 and shown_ok == shown, "%d / %d" % [shown_ok, shown])
	# 4. Red-light fine: crossing the stop line on red at a watched junction costs ₹200; green is free.
	tm._enforced_signal_nodes[node_id] = true
	tm._last_player_ticket_s = -100.0
	var outward: Vector3 = (edge.points[1] - edge.points[0]) if edge.a == node_id else (edge.points[edge.points.size() - 2] - edge.points[edge.points.size() - 1])
	outward = (outward * Vector3(1, 0, 1)).normalized()
	var r: float = tm.signal_stop_back(node_id)
	var before: Vector3 = g.nodes[node_id] + outward * (r + 1.0)
	var after: Vector3 = g.nodes[node_id] + outward * (r - 0.5)
	GameState.add_inr(1000)
	auto.freeze = false
	auto.linear_velocity = -outward * 8.0
	tm.signal_clock_override = red_clock
	var wallet: int = GameState.wallet_inr
	tm._previous_player_pos = before
	tm._on_player_signal_pose(after, -outward)
	_check("Running a red at a watched junction = ₹200 fine", GameState.wallet_inr == wallet - ChennaiTrafficManager.SIGNAL_ENFORCEMENT_FINE_INR, "₹%d → ₹%d" % [wallet, GameState.wallet_inr])
	tm._last_player_ticket_s = -100.0
	tm.signal_clock_override = green_clock
	wallet = GameState.wallet_inr
	tm._previous_player_pos = before
	tm._on_player_signal_pose(after, -outward)
	_check("Crossing on green is free", GameState.wallet_inr == wallet)
	auto.linear_velocity = Vector3.ZERO
	tm.signal_clock_override = -1.0

func _test_trees() -> void:
	var counts: Dictionary = {}
	var median_palms: int = 0
	var dir: DirAccess = DirAccess.open("res://data/world/dress")
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/dress/" + f)) as Dictionary
		for t: Array in d.get("trees", []):
			# Median palms (tools/osm/build_medians.py, seed ≥ 900000) are planted on purpose, like
			# Chennai's divided roads; the rarity rule is about the roadside mix.
			if t.size() > 4 and int(t[4]) >= 900000:
				median_palms += 1
				continue
			counts[int(t[2])] = int(counts.get(int(t[2]), 0)) + 1
	var total: int = 0
	for k: int in counts:
		total += int(counts[k])
	var palms: float = float(counts.get(1, 0)) / maxf(float(total), 1.0)
	_check("Coconut palms are rare (< 6 % of street trees)", palms < 0.06, "%.1f %%" % (palms * 100.0))
	_check("Divided roads carry median palms", median_palms > 200, str(median_palms))
	_check("Chennai street tree mix: neem, both Ashoka variants, pungai all present", int(counts.get(0, 0)) > 0 and int(counts.get(2, 0)) > 0 and int(counts.get(3, 0)) > 0 and int(counts.get(4, 0)) > 0, str(counts))

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
