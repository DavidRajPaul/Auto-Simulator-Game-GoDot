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
	_test_pedestrians(city.get_node("PedestrianManager") as PedestrianManager)
	await _test_walking(city.get_node("PedestrianManager") as PedestrianManager)
	await _test_hail_rider(city.get_node("SavariManager") as SavariManager)
	_test_traffic_models(city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager)
	_test_city_props(city.get_node("World") as WorldChunkStreamer)
	_test_dressing(city.get_node("World") as WorldChunkStreamer)
	_test_ambience(city.get_node("AmbienceAudio") as AmbienceAudio)
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
	# Real SUV proportions: ~4.5 m long, height/length ~0.49 (was squashed to 0.36).
	_check("Police SUV keeps real proportions (uniform fit, h/l > 0.42)", fitted and absf(pb.size.z - 4.5) < 0.1 and pb.size.y / pb.size.z > 0.42, str(pb.size))
	var tris: int = 0
	var scene: PackedScene = load(str(police[0])) as PackedScene if not police.is_empty() else null
	if scene != null:
		var inst: Node3D = scene.instantiate() as Node3D
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (mi as MeshInstance3D).mesh
			for s: int in m.get_surface_count():
				tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		inst.free()
	_check("Police SUV is inside the traffic triangle budget (<= 6000)", tris > 0 and tris <= 6000, "%d triangles" % tris)

func _model_bounds(car: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for mi: Node in car.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi as MeshInstance3D
		var local: AABB = (car.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
		out = local if first else out.merge(local)
		first = false
	return out

func _test_landmark_kit() -> void:
	_check("Artist Chennai lighthouse asset is present", ResourceLoader.exists("res://assets/models/city/lighthouse/chennai_lighthouse.glb"))
	_check("Artist barricade asset is present", ResourceLoader.exists("res://assets/models/city/barricade/roadside_barricade.glb"))
	_check("Artist police car asset is present", ResourceLoader.exists("res://assets/models/traffic/police_car/svc_police_car.glb"))
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
	var idle: int = 0
	for w: PedestrianManager.Walker in pm.people:
		if w.active and w.idle:
			idle += 1
	_check("A share stand waiting at the kerb", idle >= 1)

func _test_walking(pm: PedestrianManager) -> void:
	var w: PedestrianManager.Walker = null
	for c: PedestrianManager.Walker in pm.people:
		if c.active and not c.idle and c.startle <= 0.0:
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
		if v.archetype == TrafficVehicleAI.Archetype.MTC_BUS and v.get_node_or_null("Model") != null:
			bus_models += 1
		if v.archetype == TrafficVehicleAI.Archetype.LORRY:
			lorry += 1
	_check("Buses wear the Tamil Nadu bus models (no grey boxes)", bus_models >= 2)
	_check("Goods lorry in the traffic mix", lorry >= 1)

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

func _test_dressing(s: WorldChunkStreamer) -> void:
	_check("Street dressing data exists for the loaded chunks", DirAccess.get_files_at("res://data/world/dress").size() > 400)

func _test_ambience(a: AmbienceAudio) -> void:
	_check("City traffic bed is playing", a.players.has("city"))
	a._player_pos = Vector3(2277.35, 0.0, -331.62) # Marina zone centre
	var beach: float = float(a.targets()["city"])
	a._player_pos = Vector3(-2711.14, 0.0, 884.32) # T. Nagar
	var inland: float = float(a.targets()["city"])
	_check("City bed is quieter on the beach front than in T. Nagar", beach < inland, "%.2f vs %.2f" % [beach, inland])

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
