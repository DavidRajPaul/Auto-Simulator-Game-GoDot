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
			if idx.size() / 3 > 1500:
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
			if absf(length - float(LENGTHS[name])) > 0.1 or lo.y < -0.01 or lo.y > 0.02 or hi.x - lo.x > 1.9:
				sizes_ok = false
				detail += "%s %s..%s; " % [name, lo, hi]
		one_surface = one_surface and surfaces == 1
		inst.free()
	_check("Every Chennai vehicle is one mesh with one surface (one draw call)", one_surface)
	_check("Every Chennai vehicle stays light (at most 1,500 triangles)", light, detail)
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

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  " + name)
	else:
		_failed += 1
		print("  FAIL  " + name + ("" if detail == "" else "  (" + detail + ")"))
