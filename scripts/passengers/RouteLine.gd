class_name RouteLine
extends MeshInstance3D
## GPS route drawn onto the road (GDD: "GPS route splines drawn directly onto the road").
## Rebuilt from SignalBus.route_updated; a ribbon of chevron-coloured quads, 1 draw call.

const WIDTH_M: float = 1.4
const Y: float = 0.14

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	SignalBus.route_updated.connect(_on_route)

func _on_route(points: PackedVector3Array) -> void:
	if points.size() < 2:
		mesh = null
		return
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var travelled: float = 0.0
	for i: int in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var seg: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
		if seg.length() < 0.05:
			continue
		var n: Vector3 = Vector3(-seg.z, 0.0, seg.x).normalized() * WIDTH_M * 0.5
		# Alternate bright/dim every ~4 m so direction reads as moving dashes.
		var bright: bool = int(travelled / 4.0) % 2 == 0
		st.set_color(Color(0.2, 1.0, 0.4, 0.85) if bright else Color(0.1, 0.75, 0.3, 0.6))
		var a3: Vector3 = Vector3(a.x, Y, a.z)
		var b3: Vector3 = Vector3(b.x, Y, b.z)
		st.add_vertex(a3 + n)
		st.add_vertex(a3 - n)
		st.add_vertex(b3 + n)
		st.add_vertex(b3 + n)
		st.add_vertex(a3 - n)
		st.add_vertex(b3 - n)
		travelled += seg.length()
	mesh = st.commit()
