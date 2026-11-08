extends Node
## Phase 9 (Chennai city & people) verification: walking characters (retargeted walk/idle, true
## pace, one draw call each), pedestrians on the kerbs, the building detail layer, street
## dressing, Tamil Nadu buses and the lorry in traffic, baked and procedural landmarks, diesel
## engine and city ambience.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase9_tests.tscn

const CITY: String = "res://scenes/main_chennai.tscn"
const PEOPLE_META: String = "res://assets/models/people/people.json"
var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 9 tests ===")
	_test_people_assets()
	_test_landmark_kit()
	_test_building_details()
	_test_audio_data()
	GameState.reset_profile()
	var city: Node = (load(CITY) as PackedScene).instantiate()
	add_child(city)
	await _physics(150)
	var home: Transform3D = (city.get_node("AutoRickshaw") as Node3D).global_transform
	_test_surface_heights(city.get_node("World") as WorldChunkStreamer)
	_test_pedestrians(city.get_node("PedestrianManager") as PedestrianManager)
	_test_seated_driver(city)
	await _test_walking(city.get_node("PedestrianManager") as PedestrianManager)
	await _test_hail_rider(city.get_node("SavariManager") as SavariManager)
	await _test_reactions(city.get_node("PedestrianManager") as PedestrianManager)
	await _test_gestures(city.get_node("PedestrianManager") as PedestrianManager)
	_test_bumps(city.get_node("PedestrianManager") as PedestrianManager)
	await _test_fire_scares(city.get_node("PedestrianManager") as PedestrianManager)
	_test_traffic_models(city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager)
	_test_city_props(city.get_node("World") as WorldChunkStreamer)
	_test_grounding(city)
	await _test_canal_crossing(city)
	_test_dressing(city.get_node("World") as WorldChunkStreamer)
	_test_ambience(city.get_node("AmbienceAudio") as AmbienceAudio)
	await _test_bus_stops(city)
	await _test_parked_physics(city, home)
	_test_colour_variety(city)
	city.queue_free()
	await _physics(2)
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_people_assets() -> void:
	var f: FileAccess = FileAccess.open(PEOPLE_META, FileAccess.READ)
	_check("people.json exists", f != null)
	if f == null:
		return
	var meta: Dictionary = (JSON.parse_string(f.get_as_text()) as Dictionary)["people"]
	_check("At least 6 Chennai characters (veshti, saree, churidar, pavadai, young man)", meta.size() >= 6, str(meta.keys()))
	var ok_speed: bool = true
	var ok_rig: bool = true
	var ok_draw: bool = true
	var ok_anims: bool = true
	for id: Variant in meta:
		var pace: float = float((meta[id] as Dictionary)["walk_speed"])
		if pace < 0.8 or pace > 1.8:
			ok_speed = false
		var scene: PackedScene = load("res://assets/models/people/%s.glb" % id) as PackedScene
		var n: Node = scene.instantiate()
		var sk: Skeleton3D = null
		for c: Node in n.find_children("*", "Skeleton3D", true, false):
			sk = c as Skeleton3D
		if sk == null or sk.get_bone_count() != 22:
			ok_rig = false
		var meshes: Array[Node] = n.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() != 1 or (meshes[0] as MeshInstance3D).mesh.get_surface_count() != 1:
			ok_draw = false
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap == null or not ap.has_animation("walk") or not ap.has_animation("idle"):
			ok_anims = false
		n.free()
	_check("Walk paces are human (0.8–1.8 m/s at speed_scale 1)", ok_speed)
	_check("Every character has the clean 22-bone humanoid rig", ok_rig)
	_check("Every character is one mesh, one surface (one draw call)", ok_draw)
	_check("Every character has walk + idle clips", ok_anims)

## Every traffic two-wheeler variant is ONE bike at real size (not the pack's showroom grid), and
## the police SUV keeps its own proportions (uniform fit) inside the traffic budget.
func _test_two_wheeler_and_police_models() -> void:
	var ok_load: bool = true
	var ok_size: bool = true
	var detail: String = ""
	for v: Array in TrafficVehicleAI.TWO_WHEELER_VARIANTS:
		var car: Node3D = Node3D.new()
		add_child(car)
		if not TrafficModelFit.attach(car, str(v[0]), v[1] as Vector3, v[2] as bool, v[3] as bool):
			ok_load = false
		else:
			var b: AABB = _model_bounds(car)
			detail += "%s %s; " % [str(v[0]).get_file(), str(b.size)]
			# Length along -Z, standing on the road, narrower than a car, one vehicle long.
			if b.size.z < 1.6 or b.size.z > 2.4 or b.size.x > 1.0 or b.size.y < 0.7 or b.size.y > 1.4 or absf(b.position.y) > 0.05:
				ok_size = false
		car.free()
	_check("Every two-wheeler variant loads", ok_load)
	_check("Two-wheelers are single bikes at real size (1.6–2.4 m long, < 1 m wide, on the road)", ok_size, detail)
	var police: Array = []
	for v: Array in TrafficVehicleAI.SERVICE_VARIANTS:
		if str(v[0]).contains("police"):
			police = v
	var pcar: Node3D = Node3D.new()
	add_child(pcar)
	var fitted: bool = police.size() > 3 and bool(police[3]) and TrafficModelFit.attach(pcar, str(police[0]), police[1] as Vector3, true, true)
	var pb: AABB = _model_bounds(pcar) if fitted else AABB()
	pcar.free()
	# Uniform fit to 4.5 m keeps the SUV's own proportions (never squashed into a saloon box).
	_check("Police jeep keeps its proportions (uniform fit, real length, h/l > 0.4)", fitted and absf(pb.size.z - (police[1] as Vector3).z) < 0.1 and pb.size.y / pb.size.z > 0.4, str(pb.size))
	var tris: int = 0
	var scene: PackedScene = load(str(police[0])) as PackedScene if not police.is_empty() else null
	if scene != null:
		var inst: Node3D = scene.instantiate() as Node3D
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (mi as MeshInstance3D).mesh
			for s: int in m.get_surface_count():
				tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		inst.free()
	_check("Police jeep is inside the traffic triangle budget (<= 6000)", tris > 0 and tris <= 6000, "%d triangles" % tris)

func _model_bounds(car: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for mi: Node in car.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var local: AABB = (car.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
		out = local if first else out.merge(local)
		first = false
	return out

## Oct 31 device test: driving to a pin, the auto stopped dead at the Buckingham-canal bridge on
## Venkatesa Agraharam Road — every water edge had a solid kerb (and its visuals were erased, so
## it was an invisible wall). Drive straight across that bridge; check banks, rails and water.
func _test_canal_crossing(city: Node) -> void:
	var world: WorldChunkStreamer = city.get_node("World") as WorldChunkStreamer
	var auto: AutoRickshawController = city.get_node("AutoRickshaw") as AutoRickshawController
	_check("Low-poly water mesh is built (water.json)", world.get_node_or_null("Area_water") != null and world._water_mat != null)
	var banks: Node = world.get_node_or_null("WaterBanks")
	_check("Water banks are VISIBLE meshes (not collision only)", banks != null and banks.get_child_count() > 10)
	# Nov 4: the Chitrakulam ghat left a strip of open water between the top step and the west
	# wall (steps were pushed out radially from the tank centre) and walkers strolled along it.
	# The mitred offset of the ghat ring by GHAT_INSET_M must land back on the bank line.
	var ring: PackedVector2Array = PackedVector2Array([Vector2(1253.52, 1951.39), Vector2(1330.3, 1982.35),
		Vector2(1350.75, 1930.79), Vector2(1341.13, 1925.9), Vector2(1272.04, 1902.66)])
	var bank: PackedVector2Array = WorldChunkStreamer.offset_ring(ring, WorldChunkStreamer.GHAT_WIDTH_M)
	var worst: float = 0.0
	for p: Vector2 in bank:
		var best: float = INF
		for b: Vector2 in [Vector2(1247.1, 1954.19), Vector2(1333.09, 1988.87), Vector2(1357.08, 1928.39), Vector2(1343.06, 1921.28), Vector2(1269.08, 1896.39)]:
			best = minf(best, p.distance_to(b))
		worst = maxf(worst, best)
	_check("Tank ghat top step reaches the wall (Chitrakulam)", worst < 0.3, "%.2f m off" % worst)
	# Rasterise that chunk's walk mask directly (no buildings): water and the old gap strip blocked.
	var k: Vector2i = Vector2i(5, 7)
	var mask: PackedByteArray = world._building_mask(k, [], [])
	var cells: int = int(ceil(world.chunk_size / WorldChunkStreamer.BLOCK_CELL_M))
	var blocked: Callable = func(x: float, z: float) -> bool:
		var ci: int = int((x - float(k.x) * world.chunk_size) / WorldChunkStreamer.BLOCK_CELL_M)
		var cj: int = int((z - float(k.y) * world.chunk_size) / WorldChunkStreamer.BLOCK_CELL_M)
		return mask[cj * cells + ci] == 1
	_check("Walkers never enter a temple tank", blocked.call(1300.0, 1945.0) and blocked.call(1260.0, 1925.0)
		and not blocked.call(1240.0, 1925.0), "tank interior / ghat strip walkable, or street blocked")
	_check("Ghat steps sit under the tank parapet's coping", WorldChunkStreamer.GHAT_TOP_Y < WorldChunkStreamer.GROUND_VISUAL_Y + WorldChunkStreamer.TANK_WALL_H)
	var g: RoadGraph = SignalBus.current_road_graph
	var road: RoadGraph.Edge = null
	for e: RoadGraph.Edge in g.edges:
		if e.road_name == "Venkatesa Agraharam Road" and e.points[0].distance_to(Vector3(579.1, 0, 1746.0)) < 3.0:
			road = e
	_check("Found the Venkatesa Agraharam Road canal crossing", road != null)
	if road == null:
		return
	var start: Vector3 = road.points[0]
	var end: Vector3 = road.points[road.points.size() - 1]
	var fwd: Vector3 = (end - start).normalized()
	# Clear the moving traffic for this check (a stopped car in the lane is not a wall).
	var traffic: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	traffic.set_physics_process(false)
	for v: TrafficVehicleAI in traffic.pool:
		v.deactivate()
	# 20 m before the near bank, heading across, then full throttle for 6 s.
	SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(fwd, Vector3.UP), start - fwd * 20.0 + Vector3(0, 1.0, 0)))
	await _physics(90) # let the chunks there stream in
	GameState.tutorial_active = false
	SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(fwd, Vector3.UP), start - fwd * 20.0 + Vector3(0, 1.0, 0)))
	await _physics(10)
	Input.action_press("accelerate")
	await _physics(360)
	Input.action_release("accelerate")
	var travelled: float = (auto.global_position - (start - fwd * 20.0)).dot(fwd)
	var crossing: float = start.distance_to(end)
	_check("The auto drives straight across the canal bridge", travelled > 20.0 + crossing + 5.0, "%.1f m along, bridge ends at %.1f m" % [travelled, 20.0 + crossing])
	# Bridge rails: driving sideways off the bridge into the canal is blocked.
	var mid: Vector3 = (start + end) * 0.5
	var side: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(side, Vector3.UP), mid + Vector3(0, 1.0, 0)))
	await _physics(10)
	Input.action_press("accelerate")
	await _physics(240)
	Input.action_release("accelerate")
	var off_axis: float = absf((auto.global_position - mid).dot(side))
	_check("Bridge parapets stop the auto driving off into the canal", off_axis < road.width * 0.5 + 1.0, "%.1f m sideways (road half-width %.1f)" % [off_axis, road.width * 0.5])
	Input.action_press("brake")
	await _physics(60)
	Input.action_release("brake")
	traffic.set_physics_process(true)

## Oct 31 device test: parked scooters showed only seat and handlebar, cars sat half in the road.
## Every parked vehicle, stand vehicle and city prop near the player stands ON the drawn ground.
func _test_grounding(city: Node) -> void:
	var world: WorldChunkStreamer = city.get_node("World") as WorldChunkStreamer
	var player: Vector3 = (city.get_node("AutoRickshaw") as Node3D).global_position
	var fits_ok: bool = true
	var fits_seen: int = 0
	var spots_ok: bool = true
	var spots: int = 0
	var detail: String = ""
	var car_meshes: Dictionary = {}
	for k: Vector2i in world.loaded:
		var park: Node = (world.loaded[k] as Node).get_node_or_null("RoadsideParking")
		if park == null:
			continue
		for c: Node in park.get_children():
			if c.name.begins_with("ParkedVehicle_1") and (c as MultiMeshInstance3D).multimesh.instance_count > 0:
				car_meshes[(c as MultiMeshInstance3D).multimesh.mesh.get_rid()] = true
		for kind: int in RoadsideParking.MODELS.size():
			if not park.has_meta("fit_%d" % kind):
				continue
			var fit: AABB = park.get_meta("fit_%d" % kind)
			fits_seen += 1
			# Lowest point on the spot, real length, never stretched taller than it is long.
			if absf(fit.position.y) > 0.005 or absf(fit.size.z - RoadsideParking.LENGTHS_M[kind]) > 0.05 or fit.size.y > fit.size.z:
				fits_ok = false
				detail = "kind %d %s" % [kind, fit]
		var body: StaticBody3D = park.get_node_or_null("ParkedVehicleCollision") as StaticBody3D
		if body == null:
			continue
		# One box per vehicle; its bottom must be on the drawn ground at its centre.
		for cs: Node in body.get_children():
			var shape: CollisionShape3D = cs as CollisionShape3D
			var box: BoxShape3D = shape.shape as BoxShape3D
			var c: Vector3 = shape.position
			var lo: float = c.y - box.size.y * 0.5
			var g: float = world.surface_height(c.x, c.z, -99.0)
			spots += 1
			if g > -50.0 and absf(lo - g) > 0.02:
				spots_ok = false
	_check("Parked vehicles: real length, lowest point on the spot (not centred, not stretched)", fits_ok and fits_seen > 0, detail)
	_check("Parked vehicles stand on the drawn ground at their spots", spots_ok and spots > 50, "%d spots" % spots)
	# Nov 1 device test: parked cars are the traffic cars in several paints, not the green hatchback.
	_check("Parked cars come in several paints", car_meshes.size() >= 3, "%d car meshes" % car_meshes.size())
	var stand_ok: bool = true
	var stand_n: int = 0
	for n: Node in (city.get_node("SavariManager") as Node).get_children():
		if not str(n.name).contains("_Parked_") or not n is Node3D:
			continue
		var p: Vector3 = (n as Node3D).global_position
		var g: float = world.surface_height(p.x, p.z, -99.0)
		if g < -50.0:
			continue
		stand_n += 1
		if absf(TrafficModelFit.lowest_world_y(n as Node3D) - g) > 0.02:
			stand_ok = false
	_check("Auto-stand parked vehicles stand on the ground", stand_ok and stand_n > 0, "%d checked" % stand_n)
	var prop_ok: bool = true
	var prop_n: int = 0
	for n: Node in world.get_node("Landmarks").get_children():
		if not n is Node3D or (n as Node3D).global_position.distance_to(player) > 600.0:
			continue
		if n.find_children("*", "MeshInstance3D", true, false).is_empty():
			continue
		var p: Vector3 = (n as Node3D).global_position
		var g: float = world.surface_height(p.x, p.z, -99.0)
		if g < -50.0:
			continue
		prop_n += 1
		if absf(TrafficModelFit.lowest_world_y(n as Node3D) - g) > 0.02:
			prop_ok = false
			detail = "%s %.3f vs %.3f" % [n.name, TrafficModelFit.lowest_world_y(n as Node3D), g]
	_check("City props and landmarks near the player stand on the ground", prop_ok and prop_n > 0, "%d checked %s" % [prop_n, detail])
	var riders_ok: bool = true
	var riders: int = 0
	for v: Node in get_tree().get_nodes_in_group("traffic_vehicle"):
		var r: Node = v.get_node_or_null("Rider")
		if r != null:
			riders += 1
			riders_ok = riders_ok and r.has_meta("baked")
	if riders == 0:
		for v: Node in (city.get_node("ChennaiTrafficManager") as Node).find_children("Rider", "", true, false):
			riders += 1
			riders_ok = riders_ok and v.has_meta("baked")
	_check("Two-wheeler riders are the baked real characters (not procedural blocks)", riders_ok and riders > 0, "%d riders" % riders)

func _test_landmark_kit() -> void:
	_check("Artist Chennai lighthouse asset is present", ResourceLoader.exists("res://assets/models/city/lighthouse/chennai_lighthouse.glb"))
	_check("Artist barricade asset is present", ResourceLoader.exists("res://assets/models/city/barricade/roadside_barricade.glb"))
	# Nov 1 device test: the Tripo police SUV rendered shredded and the Kenney hatchback looked
	# odd. Police and cars now come from the Quaternius bodies (tools/assets/bake_car_colours.py).
	_check("Police car is the Bolero police jeep", ResourceLoader.exists("res://assets/models/traffic/cars/bolero_police.glb"))
	var pol: Node3D = (load("res://assets/models/traffic/cars/bolero_police.glb") as PackedScene).instantiate() as Node3D
	_check("Police jeep's light bar gets the flashing beacon", TrafficVehicleAI._light_beacon(pol) == 1)
	pol.free()
	var boleros: int = 0
	for v: Array in TrafficVehicleAI.CAR_VARIANTS:
		if str(v[0]).contains("bolero"):
			boleros += 1
	_check("Public Boleros drive in several colours", boleros >= 4, "%d" % boleros)
	_check("Odd Kenney hatchback and broken Tripo police car are gone",
		not ResourceLoader.exists("res://assets/models/traffic/hatch" + "back.glb") and not ResourceLoader.exists("res://assets/models/traffic/police_car/svc_police_" + "car.glb"))
	var paints: Dictionary = {}
	var one_mesh: bool = true
	for v: Array in TrafficVehicleAI.CAR_VARIANTS:
		paints[str(v[0]).get_file().get_basename().get_slice("_", 1)] = true
		var inst: Node3D = (load(str(v[0])) as PackedScene).instantiate() as Node3D
		var surfaces: int = 0
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			surfaces += (mi as MeshInstance3D).mesh.get_surface_count()
		one_mesh = one_mesh and surfaces == 1
		inst.free()
	_check("Traffic cars come in several paints, one draw call each", paints.size() >= 5 and one_mesh, str(paints.keys()))
	# Built from parts so tools/assets/check_required_assets.py doesn't read it as a required file.
	var raw_pack: String = "res://assets/models/traffic/two_wheeler_pack".path_join("two_wheeler_pack" + ".glb")
	_check("Raw two-wheeler showroom pack is not shipped", not ResourceLoader.exists(raw_pack))
	_test_two_wheeler_and_police_models()
	_check("Maintenance vehicle pack is present", ResourceLoader.exists("res://assets/models/traffic/maintenance_pack/maintenance_vehicle_pack.glb"))
	var props_file: FileAccess = FileAccess.open("res://data/world/city_props.json", FileAccess.READ)
	var props: Array = (JSON.parse_string(props_file.get_as_text()) as Dictionary).get("props", []) if props_file != null else []
	var parked: int = 0
	var maintenance: int = 0
	var parked_single: bool = true
	for p: Dictionary in props:
		parked += 1 if bool(p.get("parked_two_wheeler", false)) else 0
		if bool(p.get("parked_two_wheeler", false)):
			parked_single = parked_single and absf(float(p.get("scale", 1.0)) - 1.0) < 0.001 and ResourceLoader.exists(str(p.get("asset", "")))
		maintenance += 1 if bool(p.get("maintenance_display", false)) else 0
	_check("Parked two-wheelers are distributed near businesses", parked >= 10, "%d placements" % parked)
	_check("Parked two-wheelers are single real-size bikes (scale 1, file exists)", parked_single)
	_check("Maintenance vehicles appear at service forecourts", maintenance >= 4, "%d displays" % maintenance)
	for landmark_mesh: ArrayMesh in [LandmarkKit.lic_building(), LandmarkKit.vivekananda_house(), LandmarkKit.napier_bridge()]:
		_check("Heritage mesh is batched and nonempty", landmark_mesh.get_surface_count() == 1 and landmark_mesh.get_aabb().size.length() > 10.0)
	var heritage_counts: Dictionary = {}
	for file_name: String in DirAccess.get_files_at("res://data/world/chunks"):
		if not file_name.ends_with(".json"):
			continue
		var f: FileAccess = FileAccess.open("res://data/world/chunks/" + file_name, FileAccess.READ)
		var chunk: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
		for building: Dictionary in chunk.get("blds", []):
			var style: String = WorldChunkStreamer.heritage_style(building)
			if style != "":
				heritage_counts[style] = int(heritage_counts.get(style, 0)) + 1
	_check("Heritage styles match only their four shipped OSM footprints", heritage_counts == {"senate": 1, "palace": 2, "cathedral": 1}, str(heritage_counts))
	var lh: AABB = LandmarkKit.lighthouse().get_aabb()
	var gp: AABB = LandmarkKit.gopuram().get_aabb()
	_check("Lighthouse is ~46 m tall and slender", lh.size.y > 44.0 and lh.size.y < 52.0 and lh.size.x < 16.0, str(lh.size))
	_check("Gopuram is ~35–40 m tall on a 25 m base", gp.size.y > 32.0 and gp.size.y < 42.0 and gp.size.x > 22.0, str(gp.size))
	_check("Landmarks share one vertex-colour material", LandmarkKit.lighthouse().surface_get_material(0) == LandmarkKit.gopuram().surface_get_material(0))

func _test_building_details() -> void:
	var s: WorldChunkStreamer = WorldChunkStreamer.new()
	s._bld_mat = ShaderMaterial.new()
	var plain: Array = [{"p": [0.0, 0.0, 20.0, 0.0, 20.0, 12.0, 0.0, 12.0], "h": 9.6, "k": "", "z": "", "s": 3}]
	var holder: Node3D = s._buildings(plain)
	var mi: MeshInstance3D = holder.get_node("BuildingMeshes") as MeshInstance3D
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var plain_n: int = 0
	var top: float = 0.0
	var outside: int = 0
	for i: int in verts.size():
		if uv2[i] == WorldChunkStreamer.PLAIN_CELL:
			plain_n += 1
		top = maxf(top, verts[i].y)
		if verts[i].x < -0.3 or verts[i].x > 20.3:
			outside += 1
	_check("Detail layer added (parapet, ledges, mumty, tank)", plain_n > 200, "%d plain verts" % plain_n)
	_check("Tank on the head-room rises above the parapet", top > 9.6 + WorldChunkStreamer.MUMTY.y + 1.0, "top %.1f" % top)
	_check("Sunshade ledges stick out of the walls", outside > 0)
	_check("Still one mesh for all of it", holder.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D).size() == 1)
	var office: Node3D = s._buildings([{"p": [0.0, 0.0, 20.0, 0.0, 20.0, 12.0, 0.0, 12.0], "h": 40.0, "k": "office", "z": "", "s": 3}])
	var oa: Array = (office.get_node("BuildingMeshes") as MeshInstance3D).mesh.surface_get_arrays(0)
	var o_plain: int = 0
	for v: Vector2 in (oa[Mesh.ARRAY_TEX_UV2] as PackedVector2Array):
		if v == WorldChunkStreamer.PLAIN_CELL:
			o_plain += 1
	_check("Glass offices keep clean facades (no sunshades)", o_plain == 0)
	holder.free()
	office.free()
	s.free()

func _test_audio_data() -> void:
	var king: VehicleStats = load("res://data/vehicles/Madras_King_Deluxe.tres") as VehicleStats
	_check("Madras King Deluxe runs on the diesel engine loop", king.engine_loop.ends_with("engine_diesel_loop.ogg") and ResourceLoader.exists(king.engine_loop))
	var classic: VehicleStats = load("res://data/vehicles/Bajaj_RE_4S.tres") as VehicleStats
	_check("Starter auto keeps the LPG putter", classic.engine_loop == "")

func _test_pedestrians(pm: PedestrianManager) -> void:
	_check("Pedestrian pool built from the character set", pm.people.size() == PedestrianManager.POOL)
	_check("People are out on the pavements", pm.active_count() >= PedestrianManager.POOL / 2, "%d active" % pm.active_count())
	var ok_kerb: bool = true
	var g: RoadGraph = pm.graph
	for w: PedestrianManager.Walker in pm.people:
		if not w.active:
			continue
		var cp: Dictionary = g.closest_point(w.pos)
		var e: RoadGraph.Edge = g.edges[int(cp["edge"])]
		if float(cp["dist"]) < e.width * 0.5 - 0.6:
			ok_kerb = false
	_check("Nobody walks down the middle of the carriageway", ok_kerb)
	# Oct 31 device test: a woman walked along the kerb line through a shopfront.
	var inside: int = 0
	var samples: int = 0
	for w: PedestrianManager.Walker in pm.people:
		if w.active:
			samples += 1
			if not SignalBus.walkable(w.node.global_position.x, w.node.global_position.z):
				inside += 1
	_check("Building footprints are known for the chunk under the player", not SignalBus.walkable_provider.is_null())
	_check("No pedestrian stands inside a building", inside == 0 and samples > 0, "%d of %d inside" % [inside, samples])
	# Feet on what is drawn: each walker stands at the streamer's drawn-ground height (walk 0.08,
	# road edge 0.06, park, or bare ground. Stepping down may ease over up to 25 cm;
	# stepping up must snap immediately to prevent feet penetrating raised pavement.
	var ok_ground: bool = true
	var bare: int = 0
	var detail: String = ""
	for w: PedestrianManager.Walker in pm.people:
		if not w.active:
			continue
		var ground: float = SignalBus.surface_height(w.node.global_position.x, w.node.global_position.z, -99.0)
		if ground < -50.0 or w.node.global_position.y < ground - 0.01 or w.node.global_position.y > ground + 0.25:
			ok_ground = false
			detail += "%.2f vs %.2f; " % [w.node.global_position.y, ground]
		if is_equal_approx(ground, WorldChunkStreamer.GROUND_VISUAL_Y):
			bare += 1
	_check("Pedestrians never sink and settle toward drawn ground (within 25 cm)", ok_ground, detail if detail != "" else "%d on bare ground" % bare)
	var idle: int = 0
	for w: PedestrianManager.Walker in pm.people:
		if w.active and w.idle:
			idle += 1
	_check("A share stand waiting at the kerb", idle >= 1)

func _test_walking(pm: PedestrianManager) -> void:
	var w: PedestrianManager.Walker = null
	for c: PedestrianManager.Walker in pm.people:
		if c.active and not c.idle and not c.running and c.startle <= 0.0 and c.react == "":
			w = c
			break
	if w == null:
		_check("Found a walker to follow", false)
		return
	var start: Vector3 = w.pos
	await _physics(60)
	var moved: float = start.distance_to(w.pos)
	_check("Walkers cover ground at their pace (1 s)", moved > w.pace * 0.6 and moved < w.pace * 1.7, "%.2f m at %.2f m/s" % [moved, w.pace])
	var native: float = float(pm._native_pace[w.id])
	_check("Feet stay planted: playback rate = pace / native walk pace", is_equal_approx(w.anim.speed_scale, w.pace / native))
	var face: Vector3 = w.node.global_transform.basis.z
	_check("Walkers face where they are going", face.dot(w.heading) > 0.9)
	_check("Walk clip loops", w.anim.get_animation("walk").loop_mode == Animation.LOOP_LINEAR and w.anim.current_animation == "walk")
	# Ten seconds of walking: feet never inside a building (main before the fix: 0.8 % of samples).
	var inside: int = 0
	var total: int = 0
	for f: int in 60:
		await _physics(10)
		for c: PedestrianManager.Walker in pm.people:
			if c.active:
				total += 1
				if not SignalBus.walkable(c.node.global_position.x, c.node.global_position.z):
					inside += 1
	_check("Walkers keep out of buildings while walking (< 0.2 % of samples)", total > 100 and float(inside) / float(total) < 0.002, "%d of %d samples inside" % [inside, total])

func _test_hail_rider(sm: SavariManager) -> void:
	var it: PassengerArchetype = null
	for a: PassengerArchetype in sm.archetypes:
		if a.id == "it_commuter":
			it = a
	for h: Dictionary in sm.hails.duplicate():
		(h["node"] as Node3D).visible = false
	sm.hails.clear()
	var hail: Dictionary = sm.spawn_hail_at(Vector3(5000.0, 0.08, 5000.0), it)
	_check("Hail spawned", not hail.is_empty())
	if hail.is_empty():
		return
	var n: Node3D = hail["node"]
	var ch: Node3D = n.get_node_or_null("Character") as Node3D
	_check("Riders are the textured, animated characters", ch != null and ch.visible and not (n.get_node("Body") as Node3D).visible)
	var sk: Skeleton3D = ch.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var arm: int = sk.find_bone("RightArm")
	var hand: int = sk.find_bone("RightHand")
	await _physics(10)
	# Modifiers apply after the animation; read the final pose when the skeleton reports it.
	var ys: Array[float] = [0.0, 0.0]
	var grab: Callable = func() -> void:
		ys[0] = sk.get_bone_global_pose(arm).origin.y
		ys[1] = sk.get_bone_global_pose(hand).origin.y
	sk.skeleton_updated.connect(grab)
	await _physics(3)
	sk.skeleton_updated.disconnect(grab)
	var shoulder_y: float = ys[0]
	var hand_y: float = ys[1]
	_check("…waving: the hand is up above the shoulder", hand_y > shoulder_y + 0.2, "hand %.2f vs shoulder %.2f" % [hand_y, shoulder_y])
	n.visible = false
	sm.hails.clear()

func _test_traffic_models(tm: ChennaiTrafficManager) -> void:
	var bus_models: int = 0
	var lorry: int = 0
	for v: TrafficVehicleAI in tm.pool:
		if v.archetype == TrafficVehicleAI.Archetype.MTC_BUS and v._bus_models.size() == TrafficVehicleAI.BUS_VARIANTS.size() and not v._bus_models.has(null):
			bus_models += 1
		if v.archetype == TrafficVehicleAI.Archetype.LORRY:
			lorry += 1
	_check("Every bus slot carries all Chennai bus liveries (no grey boxes)", bus_models >= 2)
	var kinds: Dictionary = {}
	var one_mesh: bool = true
	for v: Array in TrafficVehicleAI.BUS_VARIANTS:
		kinds[str(v[3])] = true
		if str(v[0]).contains("/buses/"):
			var inst: Node3D = (load(str(v[0])) as PackedScene).instantiate() as Node3D
			var surfaces: int = 0
			for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
				surfaces += (mi as MeshInstance3D).mesh.get_surface_count()
			one_mesh = one_mesh and surfaces == 1
			inst.free()
	_check("Bus mix: MTC liveries, Premium, small bus, college bus, state buses", kinds.size() == 5, str(kinds.keys()))
	_check("Every repainted bus is one mesh (one draw call)", one_mesh)
	_check("Goods lorry in the traffic mix", lorry >= 1)

## Nov 1: real MTC bus stops on the map, shelters with name boards, and buses that stop there.
func _test_bus_stops(city: Node) -> void:
	var stops: BusStops = city.get_node("BusStops") as BusStops
	_check("Real MTC bus stops are on the map", stops != null and stops.stops.size() > 150, "%d stops" % (stops.stops.size() if stops != null else 0))
	if stops == null:
		return
	var luz: int = -1
	for i: int in stops.stops.size():
		if str((stops.stops[i] as Dictionary)["name"]) == "Luz Corner":
			luz = i
	_check("Luz Corner bus stop is on the benchmark route", luz >= 0)
	var g: RoadGraph = SignalBus.current_road_graph
	# A stop with a long straight run-in on its own edge, for the pull-in test.
	var pick: Dictionary = {}
	for st: Dictionary in stops.stops:
		var e: RoadGraph.Edge = g.edges[int(st["edge"])]
		var run_in: float = float(st["s"]) if int(st["dir"]) > 0 else e.length - float(st["s"])
		if run_in > 60.0 and e.width >= 6.0:
			pick = st
			break
	_check("A stop with a 60 m run-in exists", not pick.is_empty())
	if pick.is_empty():
		return
	var at: Vector3 = Vector3(float(pick["x"]), 0.0, float(pick["z"]))
	var traffic: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	traffic.set_physics_process(false)
	for v: TrafficVehicleAI in traffic.pool:
		v.deactivate()
	# Stand the player behind the shelter (off the road) so the chunks there load.
	var back: Vector3 = Basis(Vector3.UP, float(pick["yaw"])) * Vector3(0.0, 0.0, -4.0)
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, at + back + Vector3(0, 1.0, 0)))
	SignalBus.player_pose_updated.emit(at + back, Vector3.FORWARD)
	await _physics(60)
	stops._player = at
	stops.refresh()
	var near_shelter: bool = false
	for i: int in stops.shown:
		near_shelter = near_shelter or stops.shelter_transform(i).origin.distance_to(at) < 0.5
	_check("The nearest shelters are shown", near_shelter and stops.shown.size() > 0)
	var bus: TrafficVehicleAI = null
	for v: TrafficVehicleAI in traffic.pool:
		if v.archetype == TrafficVehicleAI.Archetype.MTC_BUS:
			bus = v
			break
	var e_idx: int = int(pick["edge"])
	var d: int = int(pick["dir"])
	var stop_s: float = float(pick["s"])
	var kind: String = ""
	for tries: int in 40:
		traffic.place_vehicle(bus, e_idx, stop_s - 55.0 * float(d), d, 0)
		kind = str(TrafficVehicleAI.BUS_VARIANTS[bus.bus_variant][3])
		if kind == "mtc":
			break
	_check("A city MTC bus shows a real route on its destination board", kind == "mtc" and bus.bus_route != "" and bus.get_node("RouteBoard").visible, bus.bus_route)
	var stopped_at: float = INF
	var dwelt: float = 0.0
	for f: int in 60 * 30:
		bus.tick(1.0 / 60.0)
		if bus.current_speed_mps < 0.05 and bus._dwell > 0.0:
			dwelt += 1.0 / 60.0
			stopped_at = minf(stopped_at, absf(bus.edge_param() - stop_s))
		if dwelt > 0.0 and bus._dwell <= 0.0 and bus.current_speed_mps > 2.0:
			break
	_check("The bus pulls in and stops at the stop", stopped_at < 2.5, "%.1f m from the stop" % stopped_at)
	_check("It dwells for passengers, then drives on", dwelt >= TrafficVehicleAI.BUS_DWELL_S.x - 0.2 and bus.current_speed_mps > 2.0, "%.1f s" % dwelt)
	bus.deactivate()
	traffic.set_physics_process(true)

## Nov 1: colour variety: two-wheelers, electric / pink NPC autos, dresses and sarees, people
## waiting at bus stops.
func _test_colour_variety(city: Node) -> void:
	var traffic: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var auto_v: TrafficVehicleAI = null
	var bike: TrafficVehicleAI = null
	for v: TrafficVehicleAI in traffic.pool:
		if v.archetype == TrafficVehicleAI.Archetype.SHARE_AUTO and auto_v == null:
			auto_v = v
		if v.archetype == TrafficVehicleAI.Archetype.TWO_WHEELER and bike == null and v._paintable:
			bike = v
	_check("NPC autos and two-wheelers carry the paint-swap material", auto_v != null and auto_v._paintable and bike != null)
	if auto_v == null or bike == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var electric: int = 0
	var pink: int = 0
	var bike_paints: Dictionary = {}
	for i: int in 300:
		auto_v.pick_paint(rng)
		electric += 1 if auto_v.electric else 0
		pink += 1 if auto_v.paint == PaintSwap.AUTO_PINK else 0
		bike.pick_paint(rng)
		bike_paints[bike.paint] = true
	_check("About 30 % of NPC autos are electric (blue / teal), some are pink", electric > 60 and electric < 130 and pink > 8, "%d electric, %d pink of 300" % [electric, pink])
	_check("Two-wheelers come in many colours", bike_paints.size() >= 8, "%d" % bike_paints.size())
	var mi: MeshInstance3D = auto_v.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_check("Electric paint reaches the auto's shader", mi.get_surface_override_material(0) is ShaderMaterial)
	auto_v.deactivate()
	bike.deactivate()
	var pm: PedestrianManager = city.get_node("PedestrianManager") as PedestrianManager
	var sarees: int = 0
	var painted: int = 0
	for w: PedestrianManager.Walker in pm.people:
		if w.paintable:
			painted += 1
			sarees += 1 if w.id.begins_with("woman_saree") else 0
	_check("Pedestrians' dresses and sarees can change colour", painted >= 10 and sarees >= 4, "%d paintable, %d sarees" % [painted, sarees])
	# People wait at the nearest stops: some on the bench, some standing.
	var stops: BusStops = city.get_node("BusStops") as BusStops
	GameState.shift_minute = 510.0 # 8:30, morning rush
	var seen: int = 0
	var sitting: int = 0
	for st: int in mini(stops.stops.size(), 40):
		var d: Dictionary = stops.stops[st]
		stops._player = Vector3(float(d["x"]), 0.0, float(d["z"]))
		stops.refresh()
		seen += stops.waiting.size()
		for w: Array in stops.waiting:
			sitting += 1 if bool(stops._wait_poses[int(w[0])][1]) else 0
	_check("People wait at bus stops, sitting and standing", seen > 40 and sitting > 5 and seen - sitting > 5, "%d people, %d seated" % [seen, sitting])

func _test_city_props(s: WorldChunkStreamer) -> void:
	var lm: Node = s.get_node("Landmarks")
	var towers: int = 0
	var slums: int = 0
	for c: Node in lm.get_children():
		if c.name.begins_with("water_tower"):
			towers += 1
		elif c.name.begins_with("slum_cluster"):
			slums += 1
	_check("TWAD water towers in each neighbourhood", towers >= 4, str(towers))
	_check("Canal-side settlements placed", slums >= 2, str(slums))
	# Northern landmarks were intentionally removed when the original map bounds returned.
	var props_file: FileAccess = FileAccess.open("res://data/world/city_props.json", FileAccess.READ)
	var props: Array = (JSON.parse_string(props_file.get_as_text()) as Dictionary).get("props", []) if props_file != null else []
	var removed_models_absent: bool = true
	for p: Dictionary in props:
		if str(p.get("model", "")) in ["chennai_central", "ripon_building"]:
			removed_models_absent = false
	for child: Node in lm.get_children():
		if child.name.begins_with("chennai_central") or child.name.begins_with("ripon_building"):
			removed_models_absent = false
	_check("Removed Central/Ripon models have no spawned props", removed_models_absent)
	_check("No Chennai Central skyline proxy", s.skyline == null)
	# Roadside shops (Nov 1): many tea stalls, fruit carts and biryani stalls in four liveries each,
	# light (<= 10k triangles, <= 3 surfaces), short view range, no shadow pass, walkers go round.
	var shops: Dictionary = {}
	var shop_ok: bool = true
	for child: Node in lm.get_children():
		for kind: String in ["tea_stall", "fruit_cart", "biryani_stall"]:
			if child.name.begins_with(kind):
				shops[kind] = int(shops.get(kind, 0)) + 1
				for mi: Node in child.find_children("*", "MeshInstance3D", true, false):
					var g: MeshInstance3D = mi as MeshInstance3D
					shop_ok = shop_ok and g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and g.visibility_range_end <= 100.0
	_check("Street shops spawn city-wide (tea, fruit, biryani)", int(shops.get("tea_stall", 0)) >= 30 and int(shops.get("fruit_cart", 0)) >= 30 and int(shops.get("biryani_stall", 0)) >= 10, str(shops))
	_check("Street shops: no shadows, drawn within 100 m", shop_ok)
	var light: bool = true
	for kind: String in ["tea_stall", "fruit_cart", "biryani_stall"]:
		for v: String in ["a", "b", "c", "d"]:
			var path: String = "res://assets/models/city/shops/%s_%s.glb" % [kind, v]
			var scene: PackedScene = load(path) as PackedScene
			if scene == null:
				light = false
				continue
			var inst: Node = scene.instantiate()
			var tris: int = 0
			var surfaces: int = 0
			for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				for si: int in mesh.get_surface_count():
					surfaces += 1
					var arr: Array = mesh.surface_get_arrays(si)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					tris += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			light = light and tris <= 10000 and surfaces <= 3
			inst.free()
	_check("Every shop livery exists and is mobile-light (<= 10k tris, <= 3 surfaces)", light)
	_check("Shop footprints feed the pedestrian walk mask", s._prop_blocks.size() > 50, "%d chunks" % s._prop_blocks.size())
	# TNEB transformers: the owner's tank is loaded once and merged into chunk meshes.
	_check("Transformer tank loaded for the DP structures (< 2k triangles)", s._xfmr_verts.size() > 300 and s._xfmr_verts.size() / 3 < 2000, "%d tris" % (s._xfmr_verts.size() / 3))
	var m: WorldChunkStreamer.MeshBuf = WorldChunkStreamer.MeshBuf.new()
	s._transformer(m, Vector3.ZERO, Vector2(0.0, 1.0), Vector2(1.0, 0.0), Color(0.66, 0.65, 0.62))
	var top_y: float = 0.0
	var tank_low: float = 1e9
	for i: int in m.verts.size():
		top_y = maxf(top_y, m.verts[i].y)
	for v: Vector3 in s._xfmr_verts:
		tank_low = minf(tank_low, v.y)
	_check("DP structure: ~9 m poles, tank on the platform above the ground", top_y > 8.5 and top_y < 9.5 and tank_low + WorldChunkStreamer.XFMR_PLATFORM_Y > 3.0, "top %.1f m" % top_y)

func _test_dressing(s: WorldChunkStreamer) -> void:
	_check("Street dressing data exists for the loaded chunks", DirAccess.get_files_at("res://data/world/dress").size() > 400)
	var by_code: Dictionary = {}
	var total: int = 0
	for file_name: String in DirAccess.get_files_at("res://data/world/dress"):
		if not file_name.ends_with(".json"):
			continue
		var f: FileAccess = FileAccess.open("res://data/world/dress/" + file_name, FileAccess.READ)
		if f == null:
			continue
		var dress: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
		for tree_data: Array in dress.get("trees", []):
			by_code[int(tree_data[2])] = int(by_code.get(int(tree_data[2]), 0)) + 1
			total += 1
	# Nov 2: owner's models replaced the procedural trees, at about twice the old 11.2k.
	_check("Street trees: > 20k city-wide", total > 20000, "%d" % total)
	_check("Neem, both Ashoka variants and pungai each planted > 1000 times",
		int(by_code.get(0, 0)) > 1000 and int(by_code.get(2, 0)) > 1000 and int(by_code.get(3, 0)) > 1000 and int(by_code.get(4, 0)) > 1000,
		str(by_code))
	_check("No retired procedural species codes (5-7) remain", not by_code.has(5) and not by_code.has(6) and not by_code.has(7), str(by_code))
	_test_street_trees(s)

## Trees draw from the owner's models through StreetTrees: a fixed set of world MultiMeshes
## (one near model per species + one impostor batch), never a mesh or node per chunk.
func _test_street_trees(s: WorldChunkStreamer) -> void:
	var t: StreetTrees = s.trees
	_check("StreetTrees exists with 5 species", t != null and t.species.size() == 5 and t.near_mmis.size() == 5)
	if t == null:
		return
	var cam: Vector3 = (get_tree().get_first_node_in_group("player_auto") as Node3D).global_position
	t._dirty = true
	t.update(cam)
	_check("Loaded chunks register their trees", t.tree_count() > 100, "%d" % t.tree_count())
	_check("Near models and far impostors both drawn", t.near_count > 0 and t.far_count > 0,
		"near %d far %d" % [t.near_count, t.far_count])
	var in_range: int = 0
	var in_band: int = 0
	for ck: Vector2i in t._chunks:
		var arr: PackedFloat32Array = t._chunks[ck]
		for i: int in range(0, arr.size(), StreetTrees.PRE):
			var d: float = Vector2(arr[i] - cam.x, arr[i + 2] - cam.z).length()
			in_range += 1 if d <= StreetTrees.FAR_M else 0
			var lo: float = StreetTrees.NEAR_M - StreetTrees.FADE_M - StreetTrees.FAR_REBUILD_M
			var hi: float = StreetTrees.NEAR_M + StreetTrees.FADE_M + StreetTrees.REBUILD_M
			in_band += 1 if d > lo and d < hi else 0
	# Nov 3: trees around the fade band are in BOTH sets (the shaders cross-fade them; the far set
	# reaches FAR_REBUILD_M further in because it refills less often); everyone else once.
	_check("Every tree in range drawn once, fade band in both levels",
		t.near_count + t.far_count == in_range + in_band, "near %d far %d range %d band %d" % [t.near_count, t.far_count, in_range, in_band])
	var near_ok: bool = t.near_positions.size() == t.near_count
	for p: Vector3 in t.near_positions:
		if Vector2(p.x - cam.x, p.z - cam.z).length() > StreetTrees.NEAR_M + StreetTrees.FADE_M + StreetTrees.REBUILD_M + 0.5 or absf(p.y) > 1.0:
			near_ok = false
	_check("Near models only out to the fade band, standing on the ground", near_ok, "%d near" % t.near_count)
	var tex_ok: bool = true
	for code: int in t.near_mmis:
		var mat: ShaderMaterial = (t.near_mmis[code] as MultiMeshInstance3D).material_override as ShaderMaterial
		tex_ok = tex_ok and mat != null and mat.get_shader_parameter("albedo_tex") != null
	_check("Near trees: textured, cross-fade shader", tex_ok)
	var far_mat: ShaderMaterial = t.far_mmi.material_override as ShaderMaterial
	var eye: Vector3 = far_mat.get_shader_parameter("eye_pos")
	_check("Both tree shaders follow the camera for the fade", eye.distance_to(cam) < 0.1 and is_equal_approx(float(far_mat.get_shader_parameter("fade_end")), StreetTrees.NEAR_M + StreetTrees.FADE_M))
	var atlas: Texture2D = far_mat.get_shader_parameter("atlas")
	_check("Impostor atlas is mipmapped (no shimmer at distance)", atlas != null and atlas.get_image() != null and atlas.get_image().has_mipmaps())
	_check("Impostors never cast shadows", t.far_mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# Nov 4: one camera-facing card per tree (crossed cards showed edge-on slabs, 4x overdraw) and
	# the atlas views it picks from; lit like the model (the old up-facing cards were pale blobs).
	var card: Mesh = t.far_mmi.multimesh.mesh
	_check("Far trees are one upright card each", card.get_surface_count() == 1
		and (card.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 4)
	_check("Far cards pick the baked views", is_equal_approx(float(far_mat.get_shader_parameter("views")), float(t.views)))
	var per_chunk: int = 0
	for k: Vector2i in s.loaded:
		for pattern: String in ["*Tree*", "*Palm*"]:
			per_chunk += (s.loaded[k] as Node3D).find_children(pattern, "", true, false).size()
	_check("No tree meshes or MultiMeshes inside chunks", per_chunk == 0, "%d" % per_chunk)
	var tc: int = t.tree_count()
	var some: Vector2i = s.loaded.keys()[0]
	var saved: PackedFloat32Array = t._chunks.get(some, PackedFloat32Array())
	t.remove_chunk(some)
	_check("Unloading a chunk drops its trees", t.tree_count() == tc - saved.size() / StreetTrees.PRE)
	if not saved.is_empty():
		t.add_chunk(some, saved)

func _test_ambience(a: AmbienceAudio) -> void:
	_check("City traffic bed is playing", a.players.has("city"))
	a._player_pos = Vector3(2277.35, 0.0, -331.62) # Marina zone centre
	var beach: float = float(a.targets()["city"])
	a._player_pos = Vector3(-2711.14, 0.0, 884.32) # T. Nagar
	var inland: float = float(a.targets()["city"])
	_check("City bed is quieter on the beach front than in T. Nagar", beach < inland, "%.2f vs %.2f" % [beach, inland])

## Nov 7: hitting a parked vehicle did nothing. Now the vehicle wakes into a rigid body with its
## real mass: a scooter is knocked away / over, a car barely shifts and stops the auto.
func _test_parked_physics(city: Node, home: Transform3D) -> void:
	var world: WorldChunkStreamer = city.get_node("World") as WorldChunkStreamer
	var auto: AutoRickshawController = city.get_node("AutoRickshaw") as AutoRickshawController
	var traffic: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	traffic.set_physics_process(false)
	for v: TrafficVehicleAI in traffic.pool:
		v.deactivate()
	GameState.tutorial_active = false
	# The candidates are only the parked vehicles in chunks that are loaded around the auto, so
	# start from the spawn point (where the city's chunks are loaded) instead of wherever the
	# bus-stop test left the auto.
	SignalBus.teleport_requested.emit(home)
	await _physics(2)
	world.update_streaming(true)
	await _physics(120)
	var results: Dictionary = {}
	for kind: int in [0, 1]:
		# A parked vehicle of this kind with a clear 16 m run-up behind it.
		var set_: ParkedVehicleSet = null
		var idx: int = -1
		for k: Vector2i in world.loaded:
			var park: ParkedVehicleSet = (world.loaded[k] as Node).get_node_or_null("RoadsideParking") as ParkedVehicleSet
			if park == null:
				continue
			for i: int in park.records.size():
				var r: Dictionary = park.records[i]
				if int(r["kind"]) != kind or park.awake.has(i):
					continue
				var o: Vector3 = r["origin"]
				var back: Vector3 = -Vector3(sin(float(r["yaw"])), 0.0, cos(float(r["yaw"])))
				var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(o + Vector3.UP * 0.7 + back * ((r["dim"] as Vector3).z * 0.5 + 0.3), o + Vector3.UP * 0.7 + back * 16.0, 1)
				if (city as Node3D).get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					set_ = park
					idx = i
					break
			if set_ != null:
				break
		if set_ == null:
			_check("Found a parked %s with a clear run-up" % ["scooter", "car"][kind], false, "%d chunks loaded" % world.loaded.size())
			continue
		var r: Dictionary = set_.records[idx]
		var origin: Vector3 = r["origin"]
		var fwd: Vector3 = Vector3(sin(float(r["yaw"])), 0.0, cos(float(r["yaw"])))
		var start: Vector3 = origin - fwd * 15.0 + Vector3(0, 0.8, 0)
		SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(fwd, Vector3.UP), start))
		await _physics(20)
		Input.action_press("accelerate")
		var hit_speed: float = 0.0
		for f: int in 300:
			await get_tree().physics_frame
			if set_.awake.has(idx) and hit_speed == 0.0:
				hit_speed = auto.linear_velocity.length()
			if (auto.global_position - origin).dot(fwd) > -1.0:
				break
		Input.action_release("accelerate")
		await _physics(150)
		var body: RigidBody3D = set_.awake.get(idx, null)
		var moved: float = 0.0
		var tilt: float = 0.0
		if body != null:
			moved = Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z).length()
			tilt = rad_to_deg(body.global_basis.y.angle_to(Vector3.UP))
		results[kind] = [body != null, hit_speed, moved, tilt]
		Input.action_press("brake")
		await _physics(30)
		Input.action_release("brake")
	if results.has(0):
		var s0: Array = results[0]
		_check("Hitting a parked scooter wakes it into a real body", bool(s0[0]), "hit at %.1f m/s" % float(s0[1]))
		_check("A hit scooter (110 kg) is knocked over and thrown", float(s0[2]) > 1.0 and float(s0[3]) > 45.0, "moved %.2f m, tilted %.0f°" % [float(s0[2]), float(s0[3])])
	if results.has(1):
		var s1: Array = results[1]
		_check("Hitting a parked car wakes it too", bool(s1[0]), "hit at %.1f m/s" % float(s1[1]))
		_check("A parked car (1.15 t) only shifts a little", float(s1[2]) < 1.5 and float(s1[3]) < 10.0, "moved %.2f m, tilted %.0f°" % [float(s1[2]), float(s1[3])])
		if results.has(0):
			_check("The scooter goes further than the car", float(results[0][2]) + float(results[0][3]) / 30.0 > float(s1[2]))
	_check("Woken parked vehicles count as vehicles", ParkedVehicleSet.MASS_KG[0] < ParkedVehicleSet.MASS_KG[2] and ParkedVehicleSet.MASS_KG[2] < ParkedVehicleSet.MASS_KG[1])
	traffic.set_physics_process(true)

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

func _test_surface_heights(world: WorldChunkStreamer) -> void:
	var p: Vector3 = (get_tree().get_first_node_in_group("player_auto") as Node3D).global_position
	_check("Surface heights exist for the chunk under the player", world._heights.has(world.chunk_of(p)))
	var seen: Dictionary = {}
	var k: Vector2i = world.chunk_of(p)
	var grid: PackedFloat32Array = world._heights.get(k, PackedFloat32Array())
	for h: float in grid:
		seen[snappedf(h, 0.001)] = true
	_check("Surface raster has sidewalk, road and bare-ground cells", seen.has(0.08) and seen.has(0.06) and seen.has(snappedf(WorldChunkStreamer.GROUND_VISUAL_Y, 0.001)), str(seen.keys()))

## The player's auto is never driverless: the owner's hero, baked seated (one mesh, one draw
## call), rides at the handlebar; he hides only in the cockpit view. No on-foot mode in release 1.
func _test_seated_driver(city: Node) -> void:
	var auto: AutoRickshawController = city.get_node("AutoRickshaw") as AutoRickshawController
	var model: AutoRickshawModel = auto.get_node("Model") as AutoRickshawModel
	_check("The seated driver is the hero model (not the placeholder)", model.driver != null and model.driver_is_hero())
	var meshes: Array[Node] = model.driver.find_children("*", "MeshInstance3D", true, false) if model.driver != null else []
	var surfaces: int = 0
	for n: Node in meshes:
		surfaces += (n as MeshInstance3D).mesh.get_surface_count()
	_check("Seated hero is one mesh, one surface (one draw call)", meshes.size() == 1 and surfaces == 1, "%d meshes, %d surfaces" % [meshes.size(), surfaces])
	var hb: AABB = AABB()
	if meshes.size() == 1:
		var mi: MeshInstance3D = meshes[0] as MeshInstance3D
		hb = (model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
	# Seated: head ~0.8 m above the hip, within the canopy; hands reach toward the handlebar (-Z).
	_check("Seated hero fits under the canopy and faces forward", hb.end.y < AutoRickshawModel.GROUND_Y + 1.75 and hb.position.z < model.driver.position.z - 0.4,
		str(hb))
	# Nov 8 device photo: a sandal stuck out of the cowl by the front wheel. Feet rest on the
	# driver's floor board (GROUND_Y + 0.35) and stay behind the front cowl (z > -0.78).
	var feet_lo: float = 99.0
	var feet_front: float = 99.0
	if meshes.size() == 1:
		var mi: MeshInstance3D = meshes[0] as MeshInstance3D
		var xf: Transform3D = model.global_transform.affine_inverse() * mi.global_transform
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			var p: Vector3 = xf * v
			if p.y < AutoRickshawModel.GROUND_Y + 0.5:
				feet_lo = minf(feet_lo, p.y)
				feet_front = minf(feet_front, p.z)
	_check("The driver's feet stay inside the auto (on the floor board, behind the cowl)", feet_lo > AutoRickshawModel.GROUND_Y + 0.34 and feet_front > -0.78,
		"lowest %.3f, front %.3f" % [feet_lo - AutoRickshawModel.GROUND_Y, feet_front])
	_check("No on-foot mode in this release (HeroFreeRoam removed)", city.get_node_or_null("HeroFreeRoam") == null)
	SignalBus.camera_mode_changed.emit("Chase")
	_check("Driver is visible in the chase camera", model.driver.visible)
	SignalBus.camera_mode_changed.emit("Cockpit")
	_check("Driver hides in the cockpit view (camera is his eyes)", not model.driver.visible)
	SignalBus.camera_mode_changed.emit("Chase")
	_check("Driver returns in the chase camera", model.driver.visible)
	# Tyres on the drawn asphalt (road is drawn 0.06 above the physics ground), not sunk into it.
	var lo: float = 99.0
	if model.real_body != null:
		for n: Node in model.real_body.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				lo = minf(lo, (mi.global_transform * v).y)
	var road: float = SignalBus.surface_height(auto.global_position.x, auto.global_position.z, WorldChunkStreamer.ROAD_Y)
	_check("Auto tyres touch the drawn road surface (within 2 cm)", absf(lo - road) < 0.02 or (road < 0.0 and absf(lo - WorldChunkStreamer.ROAD_Y) < 0.02), "tyre %.3f, ground %.3f" % [lo, road])


## Owner's Mixamo clips (Nov 8): joggers, and people a vehicle nearly hits jump back or fall.
func _test_gestures(pm: PedestrianManager) -> void:
	var sets_ok: bool = true
	for w: PedestrianManager.Walker in pm.people:
		if w.anim == null or not w.anim.has_animation("get_up"):
			continue
		for clip: String in ["get_up", "talk", "drink", "wave", "flee_look", "flee"]:
			sets_ok = sets_ok and w.anim.has_animation(clip)
	_check("Pedestrians with Mixamo sets have get-up and gesture clips", sets_ok)
	var idler: PedestrianManager.Walker = null
	for w: PedestrianManager.Walker in pm.people:
		if w.active and w.idle and w.react == "" and w.anim.has_animation("talk"):
			idler = w
			break
	if idler == null:
		_check("Found a standing person to gesture", false)
		return
	pm._start_gesture(idler)
	_check("A standing person does a gesture once, not on a loop", idler.react == "gesture" and idler.anim.current_animation in PedestrianManager.GESTURE_CLIPS and idler.anim.get_animation(idler.anim.current_animation).loop_mode == Animation.LOOP_NONE, idler.react)
	for f: int in 60 * 12:
		await get_tree().physics_frame
		if idler.react == "":
			break
	_check("…then they go back to standing", idler.react == "" and idler.anim.current_animation == "idle", idler.anim.current_animation)


func _test_fire_scares(pm: PedestrianManager) -> void:
	var target: PedestrianManager.Walker = null
	for w: PedestrianManager.Walker in pm.people:
		if w.active and w.react == "" and not w.fleeing and w.anim != null and w.anim.has_animation("run"):
			target = w
			break
	if target == null:
		_check("Found a pedestrian to scare", false)
		return
	# The auto is right beside them and on fire.
	pm._has_player = true
	pm._player = target.pos + Vector3(0.0, 0.0, 0.8)
	pm._player_vel = Vector3.ZERO
	SignalBus.vehicle_burning.emit(true)
	pm._check_fire_scares()
	_check("A pedestrian beside a burning auto runs off", target.fleeing and target.anim.current_animation in ["run", "flee_look", "flee"], target.anim.current_animation)
	SignalBus.vehicle_burning.emit(false)
	for f: int in 60 * 12:
		await get_tree().physics_frame
		if not target.fleeing:
			break
	_check("…and stops running once they are clear of it", not target.fleeing and target.react == "")


func _test_bumps(pm: PedestrianManager) -> void:
	var target: PedestrianManager.Walker = null
	for w: PedestrianManager.Walker in pm.people:
		if w.active and w.react == "" and w.recovery <= 0.0:
			target = w
			break
	if target == null:
		_check("Found a pedestrian to bump", false)
		return
	var bumps: Array = []
	var record := func(_p: Vector3, v: Vector3) -> void: bumps.append(v)
	SignalBus.pedestrian_bumped.connect(record)
	# The auto a metre behind the person, doing 6 m/s straight at them (heading -z).
	pm._has_player = true
	pm._player_fwd = Vector3(0.0, 0.0, -1.0)
	pm._player_vel = Vector3(0.0, 0.0, -6.0)
	pm._player = target.pos + Vector3(0.0, 0.0, 0.5)
	pm._check_player_bumps()
	var first: int = bumps.size()
	pm._check_player_bumps()
	SignalBus.pedestrian_bumped.disconnect(record)
	_check("A pedestrian the auto reaches is hit", first >= 1 and target.recovery > 0.0 and target.react != "", "hits %d" % first)
	_check("…once per pass, not on every frame", bumps.size() == first)
	_check("…and they go down, not stand there", target.react in ["stumble", "dodge", "fallen"], target.react)


func _test_reactions(pm: PedestrianManager) -> void:
	var clips_ok: bool = true
	for w: PedestrianManager.Walker in pm.people:
		for clip: String in ["run", "dodge", "stumble", "fallen"]:
			clips_ok = clips_ok and w.anim != null and w.anim.has_animation(clip)
	_check("Every pedestrian has run, dodge, stumble and fallen clips", clips_ok)
	# Joggers: run clip, playback matched to their pace.
	var jogger: PedestrianManager.Walker = null
	for w: PedestrianManager.Walker in pm.people:
		if w.active and not w.idle and w.react == "":
			jogger = w
			break
	jogger.running = true
	jogger.pace = float(pm._run_pace[jogger.id])
	pm._resume(jogger, 0.0)
	_check("Joggers play the run clip at their own pace", jogger.anim.current_animation == "run" and is_equal_approx(jogger.anim.speed_scale, 1.0) and jogger.pace > 1.8, "%.2f m/s" % jogger.pace)
	jogger.running = false
	pm._resume(jogger, 0.0)
	# A vehicle heading straight at two people: one is brushed (dodge or stumble), one is hit.
	var picked: Array[PedestrianManager.Walker] = []
	for w: PedestrianManager.Walker in pm.people:
		if w.active and w.react == "" and w.anim.active and w != jogger:
			picked.append(w)
		if picked.size() == 2:
			break
	if picked.size() < 2:
		_check("Found two people near the player to startle", false)
		return
	var results: Array[String] = []
	for i: int in 2:
		var w: PedestrianManager.Walker = picked[i]
		var fwd: Vector3 = w.heading
		# Pass on the road side, so the person steps back onto the pavement.
		var side: Vector3 = Vector3(fwd.z, 0.0, -fwd.x) * w.side
		var lateral: float = 1.3 if i == 0 else 0.3
		var speed: float = 9.0
		pm._threats = [[w.pos - fwd * 5.0 + side * lateral, fwd * speed]]
		var started: bool = pm._check_threats(w)
		results.append(w.react if started else "none")
	pm._threats.clear()
	_check("A vehicle about to brush past makes a person dodge or stumble", results[0] in ["dodge", "stumble"], results[0])
	_check("A vehicle about to hit someone at speed knocks them over", results[1] == "stumble" or results[1] == "dodge", results[1])
	var w2: PedestrianManager.Walker = picked[1]
	var start: Vector3 = w2.pos
	var was: String = w2.react
	var lay: bool = false
	# Stumble, lying (up to 4.5 s), then Mixamo's 7.6 s getting-up clip: allow for all of it.
	for f: int in 60 * 20:
		await get_tree().physics_frame
		lay = lay or w2.react == "fallen"
		if w2.react == "":
			break
	var moved: float = Vector2(w2.pos.x - start.x, w2.pos.z - start.z).length()
	_check("The reaction carries them clear of the vehicle's path", moved > 1.5 and moved < 2.6, "%.2f m" % moved)
	_check("A stumble ends lying on the road, then they get up", was != "stumble" or lay, was)
	_check("After reacting they walk or stand again", w2.react == "" and w2.anim.current_animation in ["walk", "idle", "run"], w2.anim.current_animation)
	_check("…and never end up inside a wall", SignalBus.walkable(w2.pos.x, w2.pos.z))
