extends Node
## Sea hazard and ocean visual patch for existing OSM-based Marina sea polygon.
const AREA_PATH: String = "res://data/world/areas.json"
const OCEAN_SHADER: String = "res://shaders/marina_sea.gdshader"
const CHECK_S: float = 0.1
var _polys: Array[PackedVector2Array] = []
var _safe: Transform3D = Transform3D.IDENTITY
var _has_safe: bool = false
var _elapsed: float = 0.0
var _sea_material: ShaderMaterial

func _ready() -> void:
	var f: FileAccess = FileAccess.open(AREA_PATH, FileAccess.READ)
	if f == null:
		return
	var areas: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	for raw: Array in areas.get("sea", []):
		var poly: PackedVector2Array = PackedVector2Array()
		for p: Array in raw:
			poly.append(Vector2(float(p[0]), float(p[1])))
		_polys.append(poly)
	_sea_material = ShaderMaterial.new()
	_sea_material.shader = load(OCEAN_SHADER) as Shader

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < CHECK_S:
		return
	_elapsed = 0.0
	var world: Node = get_tree().get_first_node_in_group("world_streamer")
	if world != null:
		var sea: MeshInstance3D = world.get_node_or_null("Area_sea") as MeshInstance3D
		if sea != null and sea.material_override != _sea_material:
			sea.material_override = _sea_material
	var auto: RigidBody3D = get_tree().get_first_node_in_group("player_auto") as RigidBody3D
	if auto == null:
		return
	var point: Vector2 = Vector2(auto.global_position.x, auto.global_position.z)
	var submerged: bool = false
	for poly: PackedVector2Array in _polys:
		if Geometry2D.is_point_in_polygon(point, poly):
			submerged = true
			break
	if submerged:
		if _has_safe:
			auto.global_transform = _safe
			auto.linear_velocity = Vector3.ZERO
			auto.angular_velocity = Vector3.ZERO
			auto.reset_physics_interpolation()
	elif auto.global_position.y > -0.5:
		_safe = auto.global_transform
		_has_safe = true
