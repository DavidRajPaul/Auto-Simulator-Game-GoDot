class_name LandmarkModels
extends RefCounted
## Procedural heritage landmarks baked by tools/art/make_landmarks.py (San Thome Basilica, the
## Kapaleeshwarar temple and its tank mandapam): one vertex-coloured mesh each (one draw call),
## placed from data/world/landmark_models.json with oriented box colliders. Built once while the
## world loads (WorldChunkStreamer._build_landmarks), never during play.

const VISIBLE_M: float = 650.0

static var _material: StandardMaterial3D

## glTF vertex colours are linear (the generator converts), so not vertex_color_is_srgb.
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.88
	return _material

## Adds every model under `parent` and its colliders to `body`. Returns the number placed.
static func build(json_path: String, parent: Node3D, body: StaticBody3D) -> int:
	var f: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return 0
	var data: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var placed: int = 0
	for entry: Dictionary in data.get("models", []):
		var path: String = str(entry.get("glb", ""))
		if not ResourceLoader.exists(path):
			push_warning("LandmarkModels: missing " + path)
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		var node: Node3D = scene.instantiate() as Node3D
		node.name = str(entry.get("id", "landmark"))
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, float(entry.get("yaw", 0.0))),
			Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0))))
		node.transform = xf
		parent.add_child(node)
		for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi as MeshInstance3D
			m.material_override = material()
			m.visibility_range_end = VISIBLE_M
		for b: Array in entry.get("boxes", []):
			var shape: CollisionShape3D = CollisionShape3D.new()
			var box: BoxShape3D = BoxShape3D.new()
			box.size = Vector3(float(b[3]), float(b[4]), float(b[5]))
			shape.shape = box
			shape.transform = xf * Transform3D(Basis(Vector3.UP, float(b[6])), Vector3(float(b[0]), float(b[1]), float(b[2])))
			body.add_child(shape)
		placed += 1
	return placed
