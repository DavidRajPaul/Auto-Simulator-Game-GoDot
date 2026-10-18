class_name GreyboxDressing
extends Node3D
## Fills the Anna Salai test strip with lane dashes and placeholder buildings using
## two MultiMeshInstance3D nodes (2 draw calls total). Runs once at load.

@export var road_length_m: float = 3000.0
@export var lane_count: int = 2
@export var sub_lane_width_m: float = 2.2
@export var dash_spacing_m: float = 12.0
@export var building_spacing_m: float = 26.0

func _ready() -> void:
	_build_lane_dashes()
	_build_buildings()

func _build_lane_dashes() -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.15, 0.02, 3.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.9)
	mesh.material = mat
	var half_road: float = sub_lane_width_m * lane_count * 3 * 0.5
	var lane_w: float = sub_lane_width_m * 3.0
	var count_z: int = int(road_length_m / dash_spacing_m)
	var xs: Array[float] = []
	for i: int in range(1, lane_count):
		xs.append(-half_road + lane_w * i)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count_z * maxi(xs.size(), 1)
	var idx: int = 0
	for x: float in xs:
		for i: int in count_z:
			var z: float = -road_length_m * 0.5 + i * dash_spacing_m
			mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY, Vector3(x, 0.011, z)))
			idx += 1
	mm.visible_instance_count = idx
	_add_mmi("LaneDashes", mm)

func _build_buildings() -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.72, 0.62)
	mesh.material = mat
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 600002 # Chennai PIN — deterministic layout
	var per_side: int = int(road_length_m / building_spacing_m)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = per_side * 2
	var offset_x: float = sub_lane_width_m * lane_count * 3 * 0.5 + 9.0
	var idx: int = 0
	for side: int in [-1, 1]:
		for i: int in per_side:
			var h: float = rng.randf_range(6.0, 22.0)
			var w: float = rng.randf_range(10.0, 18.0)
			var d: float = rng.randf_range(8.0, 14.0)
			var z: float = -road_length_m * 0.5 + i * building_spacing_m
			var b: Basis = Basis.IDENTITY.scaled(Vector3(d, h, w))
			mm.set_instance_transform(idx, Transform3D(b, Vector3(side * (offset_x + d * 0.5), h * 0.5, z)))
			mm.set_instance_color(idx, Color.from_hsv(rng.randf_range(0.0, 0.15), rng.randf_range(0.1, 0.4), rng.randf_range(0.6, 0.95)))
			idx += 1
	mat.vertex_color_use_as_albedo = true
	_add_mmi("Buildings", mm)

func _add_mmi(node_name: String, mm: MultiMesh) -> void:
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
