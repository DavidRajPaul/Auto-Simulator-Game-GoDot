class_name RoadsideParking
extends RefCounted
## Chunk-scoped, batched parked vehicle visuals and one combined collision hull.
## Uses the actual traffic GLBs, not greybox vehicle stand-ins.
const MODELS: Array[String] = [
	"res://assets/models/traffic/two_wheeler.glb",
	"res://assets/models/traffic/hatchback.glb",
	"res://assets/models/traffic/share_auto.glb"
]
const DIMENSIONS: Array[Vector3] = [
	Vector3(0.85, 1.55, 2.0),
	Vector3(1.85, 1.65, 4.2),
	Vector3(1.55, 1.9, 2.8)
]
const VISIBILITY_M: float = 165.0

static func populate(chunk: Node3D, world_dir: String, key: Vector2i) -> void:
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
			if int(record[3]) == kind:
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
		var bounds: AABB = TrafficModelFit._bounds(source, holder)
		if bounds.size.x <= 0.001 or bounds.size.y <= 0.001 or bounds.size.z <= 0.001:
			source.queue_free()
			continue
		# Match GLB's long axis to the road tangent and fit to real-world vehicle size.
		var correction: float = PI * 0.5 if bounds.size.x > bounds.size.z else 0.0
		source.rotation.y = correction
		bounds = TrafficModelFit._bounds(source, holder)
		var dim: Vector3 = DIMENSIONS[kind]
		var fit: Vector3 = Vector3(dim.x / bounds.size.x, dim.y / bounds.size.y, dim.z / bounds.size.z)
		var centre: Vector3 = bounds.position + bounds.size * 0.5
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
			var relative: Transform3D = holder.global_transform.affine_inverse() * mi.global_transform
			for i: int in records.size():
				var rec: Array = records[i]
				var yaw: float = float(rec[2])
				var origin: Vector3 = Vector3(float(rec[0]), 0.08, float(rec[1]))
				var placement: Transform3D = Transform3D(Basis(Vector3.UP, yaw), origin)
				var fit_transform: Transform3D = Transform3D(Basis.IDENTITY.scaled(fit), -centre * fit)
				mm.set_instance_transform(i, placement * fit_transform * relative)
		# Collider for all parked vehicles in this chunk, without a body per vehicle.
		for rec: Array in records:
			_append_box(faces, Vector3(float(rec[0]), 0.08, float(rec[1])),
				float(rec[2]), dim)
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
