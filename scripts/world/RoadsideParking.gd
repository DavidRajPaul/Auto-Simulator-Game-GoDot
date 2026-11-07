class_name RoadsideParking
extends RefCounted
## Chunk-scoped, batched parked vehicle visuals; each vehicle a static box that turns into a real
## rigid body when the player's auto comes close (ParkedVehicleSet).
## Uses the actual traffic GLBs, not greybox vehicle stand-ins.
##
## Every vehicle is scaled UNIFORMLY to its real length (LENGTHS_M) and stands with its lowest
## point on the drawn ground at its spot (sidewalk 0.08 / road 0.06 / bare ground -0.15).
## Oct 31 device test: the first version put each model's CENTRE at y 0.08 and stretched it to
## a fixed box, so parked scooters showed only seat and handlebar and cars sat half in the road.
const MODELS: Array[String] = [
	"res://assets/models/traffic/two_wheeler_pack/scooter_parked.glb",
	"res://assets/models/traffic/cars/sedan_white.glb", # kind 1 picks from CAR_FILES
	"res://assets/models/traffic/share_auto.glb"
]
## Parked cars: the traffic cars' Chennai paint mix (tools/assets/bake_car_colours.py), one
## MultiMesh (= one draw call) per file. Nov 1 device test: the Kenney hatchback looked odd.
const CAR_FILES: Array[String] = [
	"res://assets/models/traffic/cars/sedan_white.glb",
	"res://assets/models/traffic/cars/sedan_silver.glb",
	"res://assets/models/traffic/cars/suv_white.glb",
	"res://assets/models/traffic/cars/sedan_maroon.glb",
	"res://assets/models/traffic/cars/sedan_blue.glb",
	"res://assets/models/traffic/cars/suv_silver.glb",
]
## Real lengths: Activa-class scooter 1.83 m, compact car 3.8 m, Ape-type share auto 2.9 m.
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
	var holder: ParkedVehicleSet = ParkedVehicleSet.new()
	holder.name = "RoadsideParking"
	chunk.add_child(holder)
	# [kind, file, records]: cars are split across the paint files by spot order.
	var groups: Array = []
	for kind: int in MODELS.size():
		var files: Array[String] = []
		if kind == 1:
			files.assign(CAR_FILES)
		else:
			files.append(MODELS[kind])
		var split: Array = []
		for f: String in files:
			split.append([])
		var n: int = 0
		for record: Array in parking:
			if int(record[3]) == kind and not _near(record, keep_clear):
				(split[n % files.size()] as Array).append(record)
				n += 1
		for i: int in files.size():
			groups.append([kind, files[i], split[i]])
	for group: Array in groups:
		var kind: int = int(group[0])
		var model_path: String = str(group[1])
		var records: Array = group[2]
		if records.is_empty() or not ResourceLoader.exists(model_path):
			continue
		var scene: PackedScene = load(model_path) as PackedScene
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
		var group_id: int = holder.groups.size()
		var group_info: Dictionary = {"mms": [] as Array[MultiMesh], "parts": []}
		holder.groups.append(group_info)
		var fit_transform: Transform3D = Transform3D(Basis.IDENTITY.scaled(fit), -anchor * fit)
		var pkey_group: String = PaintSwap.key_of(model_path)
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null:
				continue
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			# Parked scooters and autos vary in colour (PaintSwap via MultiMesh custom data);
			# set before the count (changing the count clears instance data).
			var pkey: String = PaintSwap.key_of(model_path)
			var swap: ShaderMaterial = PaintSwap.material_for(mi.mesh.surface_get_material(0), pkey, true) if pkey != "" and mi.mesh.get_surface_count() == 1 else null
			mm.use_custom_data = swap != null
			mm.mesh = mi.mesh
			mm.instance_count = records.size()
			var inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
			inst.name = "ParkedVehicle_%d_%s" % [kind, model_path.get_file().get_basename()]
			inst.multimesh = mm
			inst.material_override = swap if swap != null else mi.material_override
			inst.visibility_range_end = VISIBILITY_M
			holder.add_child(inst)
			var relative: Transform3D = _relative(mi, holder)
			(group_info["mms"] as Array[MultiMesh]).append(mm)
			# What a woken (rigid) copy of this vehicle draws: same mesh, single-instance paint.
			var solo: Material = PaintSwap.material_for(mi.mesh.surface_get_material(0), pkey, false) if swap != null else mi.material_override
			(group_info["parts"] as Array).append([mi.mesh, fit_transform * relative, solo])
			for i: int in records.size():
				var rec: Array = records[i]
				var yaw: float = float(rec[2])
				var origin: Vector3 = _spot(rec, ground)
				var placement: Transform3D = Transform3D(Basis(Vector3.UP, yaw), origin)
				mm.set_instance_transform(i, placement * fit_transform * relative)
				if swap != null:
					var h: int = absi(int(origin.x * 13.0) * 31 + int(origin.z * 7.0))
					var pc: Color = PaintSwap.NO_PAINT
					if pkey == "share_auto":
						pc = PaintSwap.AUTO_ELECTRIC[h % 2] if h % 3 == 0 else PaintSwap.NO_PAINT
					else:
						pc = PaintSwap.TWO_WHEELER_PAINTS[h % PaintSwap.TWO_WHEELER_PAINTS.size()]
					mm.set_instance_custom_data(i, pc)
		# One record per vehicle: static box until the auto comes close (ParkedVehicleSet).
		for i: int in records.size():
			var rec: Array = records[i]
			var origin: Vector3 = _spot(rec, ground)
			var paint: Color = PaintSwap.NO_PAINT
			if pkey_group != "":
				var h: int = absi(int(origin.x * 13.0) * 31 + int(origin.z * 7.0))
				if pkey_group == "share_auto":
					paint = PaintSwap.AUTO_ELECTRIC[h % 2] if h % 3 == 0 else PaintSwap.NO_PAINT
				else:
					paint = PaintSwap.TWO_WHEELER_PAINTS[h % PaintSwap.TWO_WHEELER_PAINTS.size()]
			holder.records.append({"kind": kind, "origin": origin, "yaw": float(rec[2]), "dim": dim,
				"group": group_id, "inst": i, "paint": paint})
		source.queue_free()
	if not holder.records.is_empty():
		holder.build_colliders()

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
