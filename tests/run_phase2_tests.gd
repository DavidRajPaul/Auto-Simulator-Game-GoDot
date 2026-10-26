extends Node
## Phase 2 verification: OSM Chennai world data, chunk streaming, traffic on real roads.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase2_tests.tscn

const MAIN_SCENE: String = "res://scenes/main_chennai.tscn"
const WORLD_DIR: String = "res://data/world"

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 2 tests ===")
	var manifest: Dictionary = _test_manifest()
	var graph: RoadGraph = _test_graph()

	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	var world: WorldChunkStreamer = main.get_node("World") as WorldChunkStreamer
	var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
	var traffic: ChennaiTrafficManager = main.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	await _physics(5)

	_test_spawn(auto, graph)
	_test_chunk_content(world)
	_test_landmarks(world, manifest)
	await _physics(120)
	_test_traffic_on_roads(traffic, auto)
	await _test_traffic_follows_graph(traffic)
	_test_cattle(traffic)
	await _test_drive(auto)
	await _test_streaming(world, auto)

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Data ------------------------------------------------------------------

func _test_manifest() -> Dictionary:
	var f: FileAccess = FileAccess.open(WORLD_DIR.path_join("manifest.json"), FileAccess.READ)
	_check("manifest.json present", f != null)
	if f == null:
		return {}
	var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var b: Array = m["bounds"]
	var span: Vector2 = Vector2(float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	_check("Real-size map: 1 : 1 scale, 5–8 km each axis", is_equal_approx(float(m.get("map_scale", 0.0)), 1.0) and span.x > 5000.0 and span.x < 8000.0 and span.y > 5000.0 and span.y < 8000.0, "%.0f × %.0f m" % [span.x, span.y])
	_check("Real road geometry from osm2streets", str(m.get("road_source", "")) == "osm2streets")
	var st: Dictionary = m.get("stats", {})
	_check("≥ 15k real OSM building footprints", int(st.get("real_buildings", 0)) >= 15000, "%d" % int(st.get("real_buildings", 0)))
	_check("≥ 50 chunks of 250 m", (m["chunks"] as Array).size() >= 50 and is_equal_approx(float(m["chunk_size"]), 250.0), "%d chunks" % (m["chunks"] as Array).size())
	var zone_ids: Array = (m["zones"] as Array).map(func(z: Dictionary) -> String: return str(z["id"]))
	_check("3 MVP zones present (Marina, Mylapore, Anna Salai/T. Nagar)", zone_ids.has("marina") and zone_ids.has("mylapore") and zone_ids.has("anna_salai") and zone_ids.has("t_nagar"))
	_check("8 landmarks present", (m["landmarks"] as Array).size() == 8)
	_check("3 auto stands present", (m["auto_stands"] as Array).size() == 3)
	_check("OSM attribution recorded", str(m.get("attribution", "")).contains("OpenStreetMap"))
	return m

func _test_graph() -> RoadGraph:
	var g: RoadGraph = RoadGraph.from_json_file(WORLD_DIR.path_join("road_graph.json"))
	_check("road_graph.json loads", g != null)
	if g == null:
		return RoadGraph.new()
	_check("Road graph has > 1000 edges", g.edges.size() > 1000, "%d edges, %d nodes" % [g.edges.size(), g.nodes.size()])
	# Connectivity: BFS over undirected edges reaches every node.
	var seen: Dictionary = {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var n: int = stack.pop_back()
		for ei: int in g.node_edges[n]:
			var e: RoadGraph.Edge = g.edges[ei]
			for m: int in [e.a, e.b]:
				if not seen.has(m):
					seen[m] = true
					stack.append(m)
	_check("Road network is fully connected", seen.size() == g.nodes.size(), "%d / %d nodes" % [seen.size(), g.nodes.size()])
	var bad: int = 0
	for e: RoadGraph.Edge in g.edges:
		if e.length <= 0.0 or e.width < 4.0 or (e.lanes_fwd == 0 and e.lanes_back == 0):
			bad += 1
	_check("All edges valid (length, width, lanes)", bad == 0, "%d bad" % bad)
	return g

# --- World -----------------------------------------------------------------

func _test_spawn(auto: AutoRickshawController, graph: RoadGraph) -> void:
	var cp: Dictionary = graph.closest_point(auto.global_position)
	_check("Player spawns on a road at Mylapore auto stand", float(cp["dist"]) < 6.0, "%.1f m from road centre" % float(cp["dist"]))

func _test_chunk_content(world: WorldChunkStreamer) -> void:
	_check("3×3 chunks around player loaded", world.loaded.size() >= 4 and world.loaded.size() <= 9, "%d loaded" % world.loaded.size())
	var roads: int = 0
	var colliders: int = 0
	for k: Vector2i in world.loaded:
		var ch: Node3D = world.loaded[k]
		if ch.get_node_or_null("Roads") != null:
			roads += 1
		var b: Node = ch.get_node_or_null("Buildings")
		if b != null:
			for c: Node in b.get_children():
				if c is CollisionShape3D and (c as CollisionShape3D).shape is ConcavePolygonShape3D:
					colliders += ((c as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size() / 6 # walls
	_check("Loaded chunks have road meshes", roads >= 4, "%d chunks with roads" % roads)
	_check("Building walls have colliders", colliders > 200, "%d wall colliders" % colliders)

func _test_landmarks(world: WorldChunkStreamer, manifest: Dictionary) -> void:
	var holder: Node = world.get_node_or_null("Landmarks")
	_check("Landmark placeholders built", holder != null and holder.get_node_or_null("marina_lighthouse") != null and holder.get_node_or_null("kapaleeshwarar") != null)
	var sea: Node = world.get_node_or_null("Area_sea")
	_check("Bay of Bengal (sea area) present", sea != null)

func _test_traffic_on_roads(traffic: ChennaiTrafficManager, auto: AutoRickshawController) -> void:
	var active: Array[TrafficVehicleAI] = traffic.active_vehicles()
	_check("Traffic spawns on the Chennai graph", active.size() >= 5, "active=%d" % active.size())
	var off_road: int = 0
	var far: int = 0
	for v: TrafficVehicleAI in active:
		var centre: Vector3 = traffic.graph.sample(v.edge, v.edge_param(), v.dir)[0]
		if Vector2(v.global_position.x - centre.x, v.global_position.z - centre.z).length() > traffic.graph.edges[v.edge].width * 0.5 + 0.5:
			off_road += 1
		if v.global_position.distance_to(auto.global_position) > ChennaiTrafficManager.RECYCLE_RADIUS_M + 5.0:
			far += 1
	_check("All traffic within its road width", off_road == 0, "%d off-road" % off_road)
	_check("All traffic within 120 m", far == 0, "%d far" % far)
	_check("Pool still ≤ 18", traffic.pool.size() <= 18)

func _test_traffic_follows_graph(traffic: ChennaiTrafficManager) -> void:
	var edges_before: Dictionary = {}
	for v: TrafficVehicleAI in traffic.pool:
		edges_before[v] = v.edge
	var children: int = traffic.get_child_count()
	await _physics(900) # 15 s of driving
	var changed: int = 0
	var bad_pos: int = 0
	for v: TrafficVehicleAI in traffic.pool:
		if v.active and int(edges_before.get(v, -1)) != v.edge:
			changed += 1
		if not v.global_position.is_finite():
			bad_pos += 1
	_check("AI turns onto new roads at junctions", changed >= 2, "%d vehicles changed edge" % changed)
	_check("No NaN/inf AI positions", bad_pos == 0)
	_check("No traffic instantiate/free while driving", traffic.get_child_count() == children)

func _test_cattle(traffic: ChennaiTrafficManager) -> void:
	var cows_active: int = 0
	var cows_outside: int = 0
	for v: TrafficVehicleAI in traffic.pool:
		if v.active and v.archetype == TrafficVehicleAI.Archetype.STRAY_COW:
			cows_active += 1
			if not traffic.in_market_zone(v.global_position):
				cows_outside += 1
	_check("Stray cattle disabled for now (no cows on the road)", cows_active == 0, "%d cows" % cows_active)
	_check("Cattle stay inside market zones", cows_outside == 0)

func _test_drive(auto: AutoRickshawController) -> void:
	var start: Vector3 = auto.global_position
	Input.action_press("accelerate")
	var max_speed: float = 0.0
	for i: int in 240:
		await get_tree().physics_frame
		max_speed = maxf(max_speed, auto.current_speed_kmh)
	Input.action_release("accelerate")
	_check("Auto drives in the city (≥ 25 km/h, upright)", max_speed >= 25.0 and auto.global_transform.basis.y.y > 0.8, "max %.0f km/h, moved %.0f m" % [max_speed, auto.global_position.distance_to(start)])

func _test_streaming(world: WorldChunkStreamer, auto: AutoRickshawController) -> void:
	var before: Array = world.loaded.keys()
	var far_chunk: Vector2i = world.chunk_of(auto.global_position)
	# Teleport ~1 km west (towards Anna Salai) and let the threaded streamer catch up.
	auto.global_transform = world.stand_transform("stand_tnagar")
	auto.linear_velocity = Vector3.ZERO
	var target: Vector2i = world.chunk_of(auto.global_position)
	var frames: int = 0
	while frames < 600 and (not world.loaded.has(target) or not world._pending.is_empty()):
		world.update_streaming(false)
		await get_tree().process_frame
		frames += 1
	_check("Threaded streaming loads new chunks after a 1 km move", world.loaded.has(target), "%d frames" % frames)
	_check("Old chunks unloaded (memory bounded)", not world.loaded.has(far_chunk) and world.loaded.size() <= 25, "%d loaded" % world.loaded.size())
	_check("Never more than (2r+3)² chunks resident", world.loaded.size() <= (2 * world.load_radius_chunks + 3) * (2 * world.load_radius_chunks + 3))
	var _unused: Array = before

# --- Helpers ---------------------------------------------------------------

func _physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", test_name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_failed += 1
		printerr("  FAIL  ", test_name, ("  (" + detail + ")") if detail != "" else "")
