class_name RoadsideParking
extends RefCounted
## Chunk-scoped, batched parked vehicle visuals and one combined collision hull.
## Uses the actual traffic GLBs, not greybox vehicle stand-ins.
##
## Every vehicle is scaled UNIFORMLY to its real length (LENGTHS_M) and stands with its lowest
## point on the drawn ground at its spot (sidewalk 0.08 / road 0.06 / bare ground -0.15).
## Oct 31 device test: the first version put each model's CENTRE at y 0.08 and stretched it to
## a fixed box, so parked scooters showed only seat and handlebar and cars sat half in the road.
const MODELS: Array[String] = [
	"res://assets/models/traffic/two_wheeler_pack/scooter_parked.glb",
	"res://assets/models/traffic/hatchback.glb",
	"res://assets/models/traffic/share_auto.glb"
]
## Real lengths: Activa-class scooter 1.83 m, hatchback 3.8 m, Ape-type share auto 2.9 m.
const LENGTHS_M: Array[float] = [1.83, 3.8, 2.9]
const VISIBILITY_M: float = 165.0

## `ground` is (x, z, fallback) -> drawn-ground height (WorldChunkStreamer.surface_height).
## Auto stands keep their own parked autos/car/scooter (SavariManager): no kerb parking there.
const STAND_CLEAR_M: float = 9.0

## `ground` is (x, z, fallback) -> drawn-ground height. `keep_clear` holds Vector2 (x, z) points
## that must stay free of kerb parking within STAND_CLEAR_M (auto stands).
static func populate(chunk: Node3D, world_dir: String, key: Vector2i, ground: Callable = Callable(), keep_clear: PackedVector2Array = PackedVector2Array()) -> void:
	var path: String = world_dir.path_join("dress/c_%d_%d.json" % [key.x, key.y])
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var parking: Array = (parsed as Dictionary).get("parking", [])
	if parking.is_empty():
		return
	var holder: Node3D = Node3D.new()
	holder.name = "RoadsideParking"
	chunk.add_child(holder)
	var faces: PackedVector3Array = PackedVector3Array()
	for kind: int in MODELS.size():
		var records: Array = []
		for record: Array in parking:
			if int(record[3]) == kind and not _near(record, keep_clear):
				records.append(record)
		if records.is_empty() or not ResourceLoader.exists(MODELS[kind]):
			continue
		var scene: PackedScene = load(MODELS[kind]) as PackedScene
		if scene == null:
			continue
		var source: Node3D = scene.instantiate() as Node3D
		holder.add_child(source)
		var meshes: Array[MeshInstance3D] = TrafficModelFit._meshes(source)
		if meshes.is_empty():
			source.queue_free()
			continue
		# The chunk is not in the scene tree yet (global transforms are invalid there), so every
		# transform below is accumulated from local transforms up to `holder`.
		var bounds: AABB = _local_bounds(meshes, holder)
		if bounds.size.x <= 0.001 or bounds.size.y <= 0.001 or bounds.size.z <= 0.001:
			source.queue_free()
			continue
		# Match GLB's long axis to the road tangent and fit to real-world vehicle size.
		var correction: float = PI * 0.5 if bounds.size.x > bounds.size.z else 0.0
		source.rotation.y = correction
		bounds = _local_bounds(meshes, holder)
		var long_side: float = maxf(bounds.size.x, bounds.size.z)
		var k: float = LENGTHS_M[kind] / long_side
		var fit: Vector3 = Vector3(k, k, k)
		# Centred on x/z, lowest point at y = 0 (then placed on the ground at each spot).
		var anchor: Vector3 = Vector3(bounds.position.x + bounds.size.x * 0.5, bounds.position.y, bounds.position.z + bounds.size.z * 0.5)
		var dim: Vector3 = bounds.size * k
		# For tests: the fitted vehicle's box relative to its spot (lowest point must be y = 0).
		var fitted: AABB = AABB((bounds.position - anchor) * k, bounds.size * k)
		holder.set_meta("fit_%d" % kind, fitted)
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null:
				continue
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mi.mesh
			mm.instance_count = records.size()
			var inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
			inst.name = "ParkedVehicle_%d" % kind
			inst.multimesh = mm
			inst.material_override = mi.material_override
			inst.visibility_range_end = VISIBILITY_M
			holder.add_child(inst)
			var relative: Transform3D = _relative(mi, holder)
			for i: int in records.size():
				var rec: Array = records[i]
				var yaw: float = float(rec[2])
				var origin: Vector3 = _spot(rec, ground)
				var placement: Transform3D = Transform3D(Basis(Vector3.UP, yaw), origin)
				var fit_transform: Transform3D = Transform3D(Basis.IDENTITY.scaled(fit), -anchor * fit)
				mm.set_instance_transform(i, placement * fit_transform * relative)
		# Collider for all parked vehicles in this chunk, without a body per vehicle.
		for rec: Array in records:
			_append_box(faces, _spot(rec, ground), float(rec[2]), dim)
		source.queue_free()
	if not faces.is_empty():
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "ParkedVehicleCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		holder.add_child(body)

## `node`'s transform in `ancestor`'s space from local transforms (works outside the tree).
static func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

static func _local_bounds(meshes: Array[MeshInstance3D], ancestor: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var b: AABB = _relative(mi, ancestor) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

static func _near(rec: Array, points: PackedVector2Array) -> bool:
	var p: Vector2 = Vector2(float(rec[0]), float(rec[1]))
	for q: Vector2 in points:
		if p.distance_squared_to(q) < STAND_CLEAR_M * STAND_CLEAR_M:
			return true
	return false

static func _spot(rec: Array, ground: Callable) -> Vector3:
	var x: float = float(rec[0])
	var z: float = float(rec[1])
	var y: float = float(ground.call(x, z, 0.08)) if ground.is_valid() else 0.08
	return Vector3(x, y, z)

static func _append_box(faces: PackedVector3Array, centre: Vector3, yaw: float, size: Vector3) -> void:
	var h: Vector3 = size * 0.5
	var base: Transform3D = Transform3D(Basis(Vector3.UP, yaw), centre + Vector3.UP * h.y)
	var corners: Array[Vector3] = []
	for v: Vector3 in [
		Vector3(-h.x,-h.y,-h.z), Vector3(h.x,-h.y,-h.z),
		Vector3(h.x,h.y,-h.z), Vector3(-h.x,h.y,-h.z),
		Vector3(-h.x,-h.y,h.z), Vector3(h.x,-h.y,h.z),
		Vector3(h.x,h.y,h.z), Vector3(-h.x,h.y,h.z)]:
		corners.append(base * v)
	for quad: Array in [[0,1,2,3],[5,4,7,6],[4,0,3,7],
			[1,5,6,2],[3,2,6,7],[4,5,1,0]]:
		faces.append_array(PackedVector3Array([
			corners[quad[0]],corners[quad[1]],corners[quad[2]],
			corners[quad[0]],corners[quad[2]],corners[quad[3]]]))
