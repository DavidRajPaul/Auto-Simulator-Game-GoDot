extends Node
## Chennai vehicles and street life (Nov 13): the built two-wheelers and cars
## (tools/art/make_chennai_vehicles.py, shaders/vehicle_paint.gdshader), mixed kerb parking at
## a flat draw budget (RoadsideParking.files_for), traffic variants swapped per respawn,
## kolams / dogs / festival flags (tools/osm/place_street_life.py, WorldChunkStreamer
## _street_life) and the bird flock (BirdFlock.gd, shaders/bird_flock.gdshader).
## Run: godot --headless --path . res://tests/run_street_life_tests.tscn

var _passed: int = 0
var _failed: int = 0

const CHENNAI_DIR: String = "res://assets/models/traffic/chennai/"
## Real lengths (m) the models are built to.
const LENGTHS: Dictionary = {
	"moped": 1.82, "commuter_bike": 1.92, "cruiser_bike": 2.1, "bicycle": 1.8,
	"hatchback": 3.87, "tallboy": 3.62, "micro_van": 3.39, "mini_truck": 3.82,
}

func _ready() -> void:
	print("\n=== Namma Auto — Chennai vehicles and street life tests ===")
	_run.call_deferred()

func _run() -> void:
	_test_models()
	_test_paint()
	_test_parking_mix()
	_test_traffic_variants()
	_test_street_life_data()
	_test_street_life_mesh()
	_test_birds()
	_test_road_condition()
	_test_wind()
	await _test_living_city()
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_models() -> void:
	var one_surface: bool = true
	var light: bool = true
	var sizes_ok: bool = true
	var painted: bool = true
	var detail: String = ""
	for name: String in LENGTHS:
		var path: String = CHENNAI_DIR + name + ".glb"
		if not ResourceLoader.exists(path):
			_check("Chennai vehicle %s is present" % name, false)
			continue
		var inst: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		var meshes: Array[Node] = inst.find_children("*", "MeshInstance3D", true, false)
		var surfaces: int = 0
		for n: Node in meshes:
			var mesh: Mesh = (n as MeshInstance3D).mesh
			surfaces += mesh.get_surface_count()
			var arrays: Array = mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.size() / 3 > 5000:
				light = false
				detail += "%s %d tris; " % [name, idx.size() / 3]
			var body: int = 0
			for c: Color in cols:
				if c.a < 0.5:
					body += 1
			if body < 20 or body > cols.size() - 20:
				painted = false
			var lo: Vector3 = Vector3.INF
			var hi: Vector3 = -Vector3.INF
			for v: Vector3 in verts:
				lo = lo.min(v)
				hi = hi.max(v)
			var length: float = hi.z - lo.z
			if absf(length - float(LENGTHS[name])) > 0.1 or lo.y < -0.01 or lo.y > 0.02 or hi.x - lo.x > 2.1:
				sizes_ok = false
				detail += "%s %s..%s; " % [name, lo, hi]
		one_surface = one_surface and surfaces == 1
		inst.free()
	_check("Every Chennai vehicle is one mesh with one surface (one draw call)", one_surface)
	_check("Every Chennai vehicle stays light (at most 5,000 triangles)", light, detail)
	_check("Every Chennai vehicle is real size, nose along +Z, wheels on y = 0", sizes_ok, detail)
	_check("Every Chennai vehicle marks its body panels for repainting", painted)

func _test_paint() -> void:
	var a: ShaderMaterial = PaintSwap.material_for(null, "hatchback", true)
	var b: ShaderMaterial = PaintSwap.material_for(null, "moped", true)
	var c: ShaderMaterial = PaintSwap.material_for(null, "moped", false)
	_check("All Chennai vehicles share one paint material per mode", a != null and a == b and c != null and c != a)
	_check("The parked paint material reads MultiMesh custom data", bool(a.get_shader_parameter("use_custom")) and not bool(c.get_shader_parameter("use_custom")))
	_check("Cars and two-wheelers have their own palettes", PaintSwap.vehicle_palette("tallboy") == PaintSwap.CAR_PAINTS and PaintSwap.vehicle_palette("moped") == PaintSwap.TWO_WHEELER_PAINTS)
	var sh: String = FileAccess.get_file_as_string("res://shaders/vehicle_paint.gdshader")
	_check("Vehicle paint needs no texture", not sh.contains("sampler2D"))

func _test_parking_mix() -> void:
	var bikes: Dictionary = {}
	var cars: Dictionary = {}
	var groups_ok: bool = true
	for i: int in range(-15, 15):
		for j: int in range(-13, 13):
			var k: Vector2i = Vector2i(i, j)
			var two: Array = RoadsideParking.files_for(0, k)
			var car: Array = RoadsideParking.files_for(1, k)
			var share: float = 0.0
			var names: Dictionary = {}
			for f: Array in two:
				bikes[str(f[0]).get_file()] = true
				names[str(f[0])] = true
				share += float(f[1])
			for f: Array in car:
				cars[str(f[0]).get_file()] = true
				share += float(f[1])
			if two.size() > 3 or car.size() > 4 or names.size() != two.size() or absf(share - 2.0) > 0.001:
				groups_ok = false
	_check("A chunk draws at most 3 two-wheeler and 4 car batches (was 1 + 6)", groups_ok)
	_check("Across the city every two-wheeler model is parked", bikes.size() == 1 + RoadsideParking.BIKE_FILES.size(), str(bikes.keys()))
	_check("Across the city every parked car model shows", cars.size() == RoadsideParking.CAR_FILES.size() + RoadsideParking.CAR_EXTRA_FILES.size(), str(cars.keys()))

func _test_traffic_variants() -> void:
	var tw: int = 0
	for v: Array in TrafficVehicleAI.TWO_WHEELER_VARIANTS:
		if str(v[0]).contains("/chennai/"):
			tw += 1
	var cars: int = 0
	for v: Array in TrafficVehicleAI.CAR_VARIANTS:
		if str(v[0]).contains("/chennai/"):
			cars += 1
	_check("Moving traffic rides the Chennai two-wheelers", tw >= 3, "%d" % tw)
	_check("Moving traffic drives the Chennai cars", cars >= 4, "%d" % cars)

func _test_street_life_data() -> void:
	var kolams: int = 0
	var dogs: int = 0
	var bunting: int = 0
	var bad: int = 0
	var dir: DirAccess = DirAccess.open("res://data/world/dress")
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/dress/" + f)) as Dictionary
		for k: Array in d.get("kolams", []):
			kolams += 1
			if k.size() != 5 or int(k[3]) < 0 or int(k[3]) > 3:
				bad += 1
		for g: Array in d.get("dogs", []):
			dogs += 1
			if g.size() != 5:
				bad += 1
		bunting += (d.get("bunting", []) as Array).size()
	_check("Thousands of kolams outside house gates", kolams > 3000, "%d" % kolams)
	_check("Hundreds of street dogs by the kerb stalls", dogs > 300, "%d" % dogs)
	_check("Festival flags on the wires near temples and churches", bunting > 300, "%d" % bunting)
	_check("Street life records are well formed", bad == 0, "%d bad" % bad)

func _test_street_life_mesh() -> void:
	var s: WorldChunkStreamer = WorldChunkStreamer.new()
	s._bld_mat = ShaderMaterial.new()
	var base: Node3D = s._buildings([], {"poles": [[0.0, 0.0, 0.0]]})
	var base_n: int = _verts(base)
	var life: Dictionary = {"poles": [[0.0, 0.0, 0.0]], "kolams": [[3.0, 3.0, 0.0, 0, -99.0], [6.0, 3.0, 0.0, 1, 0.012], [9.0, 3.0, 0.0, 2, 0.012], [12.0, 3.0, 0.0, 3, 0.012]],
		"dogs": [[0.0, 6.0, 0.0, 0, 0], [2.0, 6.0, 1.0, 1, 1]], "bunting": [[0.0, 10.0, 30.0, 10.0, 5]]}
	var full: Node3D = s._buildings([], life)
	var mi: MeshInstance3D = full.get_node("BuildingMeshes") as MeshInstance3D
	_check("Kolams, dogs and flags merge into the chunk's one building mesh", mi.mesh.get_surface_count() == 1 and _verts(full) > base_n + 600, "%d -> %d" % [base_n, _verts(full)])
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var kolam_ok: bool = true
	var flags_high: bool = false
	for v: Vector3 in verts:
		if v.z > 2.0 and v.z < 4.0 and v.x > 1.0 and v.x < 14.0 and v.y > 0.2:
			kolam_ok = false
		if v.z > 9.0 and v.z < 11.0 and v.y > 6.0:
			flags_high = true
	_check("Kolams lie flat on the ground", kolam_ok)
	_check("Festival flags hang up by the wires", flags_high)
	_check("Street life adds no colliders", (full.get_node("BuildingCollision") as CollisionShape3D).shape.get_faces().size() == (base.get_node("BuildingCollision") as CollisionShape3D).shape.get_faces().size()
		if full.has_node("BuildingCollision") and base.has_node("BuildingCollision") else true)
	base.free()
	full.free()
	s.free()

func _verts(holder: Node3D) -> int:
	var mi: MeshInstance3D = holder.get_node_or_null("BuildingMeshes") as MeshInstance3D
	if mi == null or mi.mesh == null:
		return 0
	return (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

func _test_birds() -> void:
	var flock: BirdFlock = BirdFlock.new()
	add_child(flock)
	_check("Birds are one MultiMesh (one draw call) with no shadows", flock.multimesh.instance_count == BirdFlock.COUNT and flock.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check("The flock is never culled by its rest bounds", flock.multimesh.custom_aabb.size.x >= 400.0)
	flock.recentre(Vector3(100.0, 0.0, 200.0))
	var spread_ok: bool = true
	var kites: int = 0
	for i: int in BirdFlock.COUNT:
		var p: Vector3 = flock.centres[i]
		if p.y < 10.0 or p.y > 70.0 or Vector2(p.x - 100.0, p.z - 200.0).length() > BirdFlock.SPREAD_M * 1.5 + 20.0:
			spread_ok = false
		if flock.customs[i].a < 0.5:
			kites += 1
	_check("Birds circle above the roofs around the camera", spread_ok)
	_check("A couple of kites soar among the crows", kites == 2, "%d" % kites)
	GameState.shift_minute = 22.0 * 60.0
	flock._check_s = 0.0
	flock._process(0.1)
	_check("Crows roost at night", not flock.visible)
	GameState.shift_minute = 9.0 * 60.0
	flock._check_s = 0.0
	flock._process(0.1)
	_check("Birds fly by day", flock.visible)
	flock.queue_free()

func _test_road_condition() -> void:
	var clean: int = 0
	var dusty: int = 0
	var broken: int = 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in 3000:
		var c: float = WorldChunkStreamer.road_condition(rng.randf_range(-3500.0, 3300.0), rng.randf_range(-3000.0, 2900.0))
		if c < 0.45:
			clean += 1
		elif c < 0.62:
			dusty += 1
		else:
			broken += 1
	_check("Roads are a mix: clean, dusty and broken stretches", clean > 600 and dusty > 600 and broken > 450, "%d clean, %d dusty, %d broken of 3000" % [clean, dusty, broken])
	_check("Road condition is the same from either side of a chunk border", absf(WorldChunkStreamer.road_condition(249.99, 80.0) - WorldChunkStreamer.road_condition(250.01, 80.0)) < 0.01)
	var s: WorldChunkStreamer = WorldChunkStreamer.new()
	s._street_mat = ShaderMaterial.new()
	var mesh: ArrayMesh = s._surface_mesh({"road": {"v": [0, 0, 10, 0, 10, 10], "i": [0, 1, 2]}, "walk": {"v": [0, 0, 5, 0, 5, 5], "i": [0, 1, 2]}}, {})
	var kinds: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var on_road: bool = false
	var off_walk: bool = true
	for k: Vector2 in kinds:
		if k.x < 0.5 and k.y > 0.0:
			on_road = true
		if k.x > 0.5 and k.x < 1.5 and k.y != 0.0:
			off_walk = false
	_check("Road vertices carry their condition, footpaths don't", on_road and off_walk)
	s.free()
	var sh: String = FileAccess.get_file_as_string("res://shaders/street_surface.gdshader")
	_check("Potholes and dust add no texture lookup", sh.count("texture(") == 2 and sh.contains("puddle"))

func _test_wind() -> void:
	var morning: Vector2 = Wind.direction_at(7.0)
	var afternoon: Vector2 = Wind.direction_at(16.0)
	_check("Mornings have the land breeze, afternoons the sea breeze", morning.dot(Wind.LAND_BREEZE.normalized()) > 0.99 and afternoon.dot(Wind.SEA_BREEZE.normalized()) > 0.99)
	_check("The afternoon wind is the strongest of the day", Wind.strength_at(16.0) > Wind.strength_at(7.0) + 0.2 and Wind.strength_at(16.0) > Wind.strength_at(2.0))
	Wind.direction = Vector2(0.6, 0.8)
	Wind.strength = 0.7
	Wind.gust = 0.4
	Wind.push()
	# The headless (dummy) renderer keeps no globals: check them only where a renderer does.
	var got: Variant = RenderingServer.global_shader_parameter_get("wind_dir")
	_check("The wind reaches every shader as globals", ProjectSettings.has_setting("shader_globals/wind_dir") and ProjectSettings.has_setting("shader_globals/wind_gust")
		and (got == null or (got as Vector2).is_equal_approx(Vector2(0.6, 0.8))))
	for path: String in ["res://shaders/tree_near.gdshader", "res://shaders/tree_impostor.gdshader", "res://shaders/rain_splash.gdshader"]:
		_check("%s follows the city wind" % path.get_file(), FileAccess.get_file_as_string(path).contains("global uniform vec2 wind_dir"))
	# Potholes: the CPU copy of the painted holes.
	var deepest: float = 0.0
	var holes: int = 0
	var clean_holes: int = 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	for i: int in 20000:
		var x: float = rng.randf_range(-3000.0, 3000.0)
		var z: float = rng.randf_range(-2500.0, 2500.0)
		var dd: float = RoadWear.pothole_depth(x, z)
		deepest = maxf(deepest, dd)
		if dd > 0.01:
			holes += 1
			if WorldChunkStreamer.road_condition(x, z) < 0.6:
				clean_holes += 1
	_check("Broken roads have potholes up to %.0f cm deep" % (RoadWear.MAX_DEPTH_M * 100.0), holes > 100 and deepest <= RoadWear.MAX_DEPTH_M + 0.0001 and deepest > 0.05, "%d holes, deepest %.3f" % [holes, deepest])
	_check("Clean and dusty roads have no potholes", clean_holes == 0)

## Moving-traffic physics, fallen bodies, shop people, kolam drawing, rain: in the real city.
func _test_living_city() -> void:
	GameState.reset_profile()
	GameState.shift_minute = 630.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	var at: Vector3 = Vector3(-3069.5, 1.0, 2056.5)
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, at))
	SignalBus.player_pose_updated.emit(Vector3(at.x, 0, at.z), Vector3.FORWARD)
	var world: WorldChunkStreamer = city.get_node("World") as WorldChunkStreamer
	world.update_streaming(true)
	for i: int in 120:
		await get_tree().physics_frame
	var traffic: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var peds: PedestrianManager = city.get_node("PedestrianManager") as PedestrianManager
	# --- A hit two-wheeler becomes a real rigid body and comes back afterwards.
	var bike: TrafficVehicleAI = traffic.place_scripted_vehicle("two_wheeler", 25.0)
	_check("A two-wheeler rides ahead of the auto", bike != null and bike.active)
	if bike != null:
		for i: int in 5:
			await get_tree().physics_frame
		var model: Node3D = bike._model
		var where: Vector3 = bike.global_position
		traffic._on_bumped(bike, 6.0)
		var slot: KnockedVehicles.Slot = traffic.knocked.slots[0]
		_check("A hard hit hands the two-wheeler to a rigid body", bike.knocked and not bike.active and traffic.knocked.busy_count() == 1 and slot.owner == bike)
		_check("The rigid body carries the bike's own model and rider from where it was", model.get_parent() == slot.body and slot.nodes.size() == 2
			and not slot.body.freeze and slot.body.global_position.distance_to(where) < 0.5, "%d nodes" % slot.nodes.size())
		_check("It has the bike's real mass and the speed the hit gave it", is_equal_approx(slot.body.mass, 180.0) and slot.body.linear_velocity.length() > 1.5, "%.1f m/s" % slot.body.linear_velocity.length())
		for i: int in 90:
			await get_tree().physics_frame
		var up: float = slot.body.global_basis.y.dot(Vector3.UP)
		_check("The knocked bike is thrown and goes over on its side", slot.body.global_position.distance_to(where) > 0.6 and up < 0.75, "moved %.1f m, up %.2f" % [slot.body.global_position.distance_to(where), up])
		_check("A knocked vehicle is never respawned while it lies there", not traffic._respawn_queue.has(bike))
		traffic.knocked.give_back(slot)
		_check("Handing it back returns the model to its traffic slot", not bike.knocked and model.get_parent() == bike and traffic.knocked.busy_count() == 0 and slot.body.freeze)
	var bus: TrafficVehicleAI = null
	for v: TrafficVehicleAI in traffic.pool:
		if v.archetype == TrafficVehicleAI.Archetype.MTC_BUS:
			bus = v
	_check("An auto can't throw a bus: buses keep the stop-and-honk recoil", bus != null and not traffic.knocked.knock(bus, 9.0, Vector3.FORWARD, 365.0, Vector3.ZERO))
	# --- A fallen body lies on top of the ground.
	var w: PedestrianManager.Walker = peds.people[0]
	for o: PedestrianManager.Walker in peds.people:
		if o.active:
			w = o
	if w.active:
		w.react = "fallen"
		w.react_t = 3.0
		w.move = Vector3.ZERO
		for i: int in 30:
			await get_tree().process_frame
		var ground: float = SignalBus.surface_height(w.pos.x, w.pos.z, 0.08)
		_check("A fallen body rests above the ground under it", w.node.global_position.y >= ground + 0.07, "%.3f over %.3f" % [w.node.global_position.y, ground])
		w.react = ""
	else:
		_check("A fallen body rests above the ground under it", false, "no active walker")
	# --- Shopkeepers and customers: one mesh, only while shops are open.
	var shops: ShopPeople = world.shop_people
	shops.rebuild(Vector3(at.x, 0.0, at.z))
	var keepers: int = 0
	for s: Array in shops.shown:
		if int(s[2]) == 0:
			keepers += 1
	_check("Open shops have a shopkeeper and customers (%d people)" % shops.shown.size(), shops.shown.size() >= 8 and shops.shown.size() <= ShopPeople.MAX_PEOPLE and keepers >= 2 and keepers < shops.shown.size())
	_check("All of them are one mesh: one draw call", shops.mesh.get_surface_count() == 1 and shops.visible)
	GameState.shift_minute = 150.0
	shops.rebuild(Vector3(at.x, 0.0, at.z))
	_check("At 2:30 am the shops are shut and nobody stands there", shops.shown.is_empty() and not shops.visible)
	GameState.shift_minute = 630.0
	# --- Rain: shelter, umbrellas, and back to normal after it.
	GameState.set_rain(true, 60.0)
	for i: int in 20:
		await get_tree().process_frame
	var sheltering: int = 0
	var umbrellas: int = 0
	var active: int = 0
	for o: PedestrianManager.Walker in peds.people:
		if o.active:
			active += 1
			sheltering += 1 if o.role == "shelter" else 0
			umbrellas += 1 if o.umbrella else 0
	_check("When it rains people run for the shop fronts", active > 4 and sheltering >= 2, "%d of %d" % [sheltering, active])
	_check("Some walk on under umbrellas (one MultiMesh for all)", umbrellas >= 1 and peds.umbrella_count() >= 1 and peds.umbrella_count() <= umbrellas, "%d umbrellas" % umbrellas)
	GameState.set_rain(false, 0.0)
	for i: int in 10:
		await get_tree().process_frame
	var left: int = 0
	for o: PedestrianManager.Walker in peds.people:
		if o.active and (o.role == "shelter" or o.umbrella):
			left += 1
	_check("After the rain umbrellas close and everyone walks on", left == 0 and peds.umbrella_count() == 0)
	# --- Rain splashes on the ground, rings on the road.
	var splashes: RainSplashes = world.get_node("RainSplashes") as RainSplashes
	GameState.set_rain(true, 60.0)
	splashes.rain = 1.0
	for i: int in 3:
		await get_tree().process_frame
	_check("Rain splashes on the ground round the camera (one MultiMesh)", splashes.splash_count() == RainSplashes.COUNT and (world._street_mat.get_shader_parameter("rain_rings") as float) > 0.5)
	GameState.set_rain(false, 0.0)
	splashes.rain = 0.0
	for i: int in 3:
		await get_tree().process_frame
	_check("No splashes when it is dry", splashes.splash_count() == 0)
	# --- Shopping bags.
	var bagged: int = 0
	var walkers: int = 0
	for o: PedestrianManager.Walker in peds.people:
		peds._roll_bags(o)
		walkers += 1
		bagged += 1 if o.bags > 0 else 0
	_check("About a third of walkers carry shopping bags", bagged > 0 and bagged < walkers, "%d of %d" % [bagged, walkers])
	for i: int in 5:
		await get_tree().process_frame
	var carrying: int = 0
	for o: PedestrianManager.Walker in peds.people:
		if o.active and o.bags > 0 and o.role != "kolam":
			carrying += o.bags
	_check("Every carried bag is drawn, all in one MultiMesh", peds.bag_count() > 0 and peds.bag_count() <= carrying, "%d drawn, %d carried" % [peds.bag_count(), carrying])
	# --- Potholes you can feel: the player's wheel drops in and the far lip is a jolt.
	var auto: AutoRickshawController = city.get_node("AutoRickshaw") as AutoRickshawController
	var hole_at: Vector3 = Vector3.INF
	for r: int in range(0, 600):
		var a: float = float(r) * 2.399
		var p: Vector3 = Vector3(at.x + cos(a) * sqrt(float(r)) * 4.0, 0.0, at.z + sin(a) * sqrt(float(r)) * 4.0)
		if RoadWear.pothole_depth(p.x, p.z) > 0.05 and RoadWear.on_asphalt(p.x, p.z):
			hole_at = p
			break
	if hole_at == Vector3.INF:
		# This street is a clean one: go to a broken stretch.
		var broken: Vector3 = Vector3(-1675.7, 1.0, 1004.2)
		SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, broken))
		world.update_streaming(true)
		for i: int in 30:
			await get_tree().physics_frame
		for r: int in range(0, 1500):
			var a: float = float(r) * 2.399
			var p: Vector3 = Vector3(broken.x + cos(a) * sqrt(float(r)) * 4.0, 0.0, broken.z + sin(a) * sqrt(float(r)) * 4.0)
			if RoadWear.pothole_depth(p.x, p.z) > 0.05 and RoadWear.on_asphalt(p.x, p.z):
				hole_at = p
				break
	_check("A pothole is found on the asphalt", hole_at != Vector3.INF)
	if hole_at != Vector3.INF:
		var hits: Array[float] = []
		var cb: Callable = func(_p: Vector3, sev: float) -> void: hits.append(sev)
		SignalBus.pothole_hit.connect(cb)
		var ray: RayCast3D = auto.rear_left_wheel_ray
		auto.forward_speed_mps = 9.0
		var inside: float = auto._pothole_at(ray, hole_at, 0.016)
		_check("A wheel over a pothole drops into it", inside > 0.05, "%.3f m" % inside)
		var out_pt: Vector3 = hole_at
		for k: int in 40:
			out_pt = hole_at + Vector3(0.1 * float(k), 0.0, 0.0)
			if RoadWear.pothole_depth(out_pt.x, out_pt.z) == 0.0:
				break
		auto._pothole_at(ray, out_pt, 0.016)
		_check("Climbing out of it at speed is a jolt (thump, shake)", hits.size() == 1 and hits[0] > 0.1, str(hits))
		SignalBus.pothole_hit.disconnect(cb)
	# --- Early morning: women draw the kolam at the doorstep.
	GameState.shift_minute = 360.0
	var home: Vector3 = Vector3(-2351.0, 1.0, -217.0)
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, home))
	SignalBus.player_pose_updated.emit(Vector3(home.x, 0, home.z), Vector3.FORWARD)
	world.update_streaming(true)
	for i: int in 60:
		await get_tree().physics_frame
	var spots: Array = SignalBus.street_spots("kolams", home, 90.0)
	_check("Kolam spots are known round the auto", spots.size() >= 5, "%d" % spots.size())
	var lady: PedestrianManager.Walker = null
	for o: PedestrianManager.Walker in peds.people:
		if PedestrianManager.WOMEN.has(o.id):
			lady = o
	var placed: bool = lady != null and not spots.is_empty() and peds.place_kolam(lady, spots[0])
	_check("A woman bends over her kolam at dawn", placed and lady.role == "kolam" and lady.pose != null and lady.pose.mode == PoseModifier.Mode.KOLAM
		and lady.pos.distance_to(spots[0][0] as Vector3) < 1.5)
	GameState.shift_minute = 600.0
	for i: int in 10:
		await get_tree().process_frame
	_check("By mid-morning she has finished", lady != null and lady.role == "" and lady.pose.mode == PoseModifier.Mode.NONE)
	city.queue_free()

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  " + name)
	else:
		_failed += 1
		print("  FAIL  " + name + ("" if detail == "" else "  (" + detail + ")"))
