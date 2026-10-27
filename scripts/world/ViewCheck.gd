class_name ViewCheck
extends RefCounted
## "Could the player see this right now?" — used so traffic and pedestrians are only ever
## spawned or recycled where the camera isn't looking (no popping in or vanishing on screen).

## True if a sphere of `radius` m around `pos` touches the active camera's view frustum.
## No camera (headless tools) counts as "not visible".
static func on_screen(vp: Viewport, pos: Vector3, radius: float = 2.0) -> bool:
	if vp == null:
		return false
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return false
	for plane: Plane in cam.get_frustum():
		if plane.distance_to(pos) > radius: # frustum plane normals point outwards
			return false
	return true
