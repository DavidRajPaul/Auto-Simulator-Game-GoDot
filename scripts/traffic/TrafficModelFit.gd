class_name TrafficModelFit
extends RefCounted
## Puts an optimised .glb on a traffic vehicle's collision box: each axis is scaled to the box,
## the long side is turned to run along the car's forward axis (-Z), and the model stands on the road.
## Visual only: collision, lanes and horn logic stay on the box. Missing files return false, and the
## caller keeps the box.

## `flip` turns the model 180° for files that were authored facing -Z (the scooter).
## `uniform` keeps the model's own proportions: it is scaled by length only and centred on the
## box (use for real-size baked vehicles, so a tall SUV is never squashed into a saloon box).
static func attach(parent: Node3D, path: String, box: Vector3, flip: bool, uniform: bool = false) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false
	var holder: Node3D = Node3D.new()
	holder.name = "Model"
	parent.add_child(holder)
	var model: Node3D = packed.instantiate() as Node3D
	holder.add_child(model)
	var bounds: AABB = _bounds(model, holder)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		holder.queue_free()
		return false
	var yaw: float = 0.0
	if bounds.size.x > bounds.size.z:
		yaw += PI * 0.5
	if flip:
		yaw += PI
	model.rotation.y = yaw
	bounds = _bounds(model, holder)
	if uniform:
		var s: float = box.z / bounds.size.z
		holder.scale = Vector3(s, s, s)
		holder.position = Vector3(-bounds.size.x * s * 0.5, 0.0, -box.z * 0.5) - bounds.position * s
	else:
		holder.scale = Vector3(box.x / bounds.size.x, box.y / bounds.size.y, box.z / bounds.size.z)
		holder.position = Vector3(-box.x * 0.5, 0.0, -box.z * 0.5) - bounds.position * holder.scale
	return true

## Bounding box of every mesh under `model`, expressed in `space` (which must be untransformed).
static func _bounds(model: Node3D, space: Node3D) -> AABB:
	var inv: Transform3D = space.global_transform.affine_inverse()
	var out: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(model):
		var local: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out

static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		out.append_array(_meshes(child))
	return out
