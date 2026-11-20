class_name KiteProp
extends Node3D
## A paper kite for quest stories (QuestStory): a diamond with its two sticks, a tail of bows and
## a string. Two draw calls: the body (one shared mesh) and one ImmediateMesh for the string and
## tail, rebuilt each frame because both move. Faces +Z; flutters by itself.

const BODY_H: float = 0.9
const BODY_W: float = 0.72
const TAIL_M: float = 1.5
const TAIL_BOWS: int = 5
const STRING_W: float = 0.018

static var _body_mesh: ArrayMesh
static var _line_material: StandardMaterial3D

## Where the string goes (world). INF = no string.
var string_end: Vector3 = Vector3.INF
## Flying kites sway more than one caught on a wire.
var flutter: float = 1.0
var colour: Color = Color(0.86, 0.08, 0.1)
var _t: float = 0.0
var _body: MeshInstance3D
var _lines: MeshInstance3D
var _im: ImmediateMesh

func _ready() -> void:
	_t = randf() * 10.0
	_body = MeshInstance3D.new()
	_body.mesh = body_mesh()
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	# Paper glows a little against the sky, so it reads from a moving auto.
	m.emission_enabled = true
	m.emission = colour * 0.35
	_body.material_override = m
	_tint(m)
	add_child(_body)
	_im = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _im
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.material_override = line_material()
	_lines.top_level = true
	add_child(_lines)

func _tint(m: StandardMaterial3D) -> void:
	# The mesh is painted red; any other colour comes from the albedo multiply (a decoy kid's kite).
	m.albedo_color = Color.WHITE
	if not colour.is_equal_approx(Color(0.86, 0.08, 0.1)):
		m.vertex_color_use_as_albedo = false
		m.albedo_color = colour

static func body_mesh() -> ArrayMesh:
	if _body_mesh != null:
		return _body_mesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Vector3 = Vector3(0.0, BODY_H * 0.62, 0.0)
	var bottom: Vector3 = Vector3(0.0, -BODY_H * 0.38, 0.0)
	var left: Vector3 = Vector3(-BODY_W * 0.5, BODY_H * 0.18, 0.0)
	var right: Vector3 = Vector3(BODY_W * 0.5, BODY_H * 0.18, 0.0)
	var centre: Vector3 = Vector3(0.0, BODY_H * 0.18, 0.02)
	var red: Color = Color(0.86, 0.08, 0.1)
	var dark: Color = Color(0.62, 0.04, 0.06)
	for tri: Array in [[top, right, centre, red], [right, bottom, centre, dark], [bottom, left, centre, red], [left, top, centre, dark]]:
		for k: int in 3:
			st.set_color(tri[3] as Color)
			st.set_normal(Vector3.BACK)
			st.add_vertex(tri[k] as Vector3)
	# Bamboo sticks: a spine and a bow, thin pale boxes just in front of the paper.
	var stick: Color = Color(0.86, 0.78, 0.6)
	_quad_line(st, top + Vector3(0, 0, 0.03), bottom + Vector3(0, 0, 0.03), 0.016, stick)
	_quad_line(st, left + Vector3(0, 0, 0.03), right + Vector3(0, 0, 0.03), 0.016, stick)
	_body_mesh = st.commit()
	return _body_mesh

static func _quad_line(st: SurfaceTool, a: Vector3, b: Vector3, w: float, c: Color) -> void:
	var d: Vector3 = (b - a).normalized()
	var side: Vector3 = d.cross(Vector3.BACK).normalized() * w
	for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
		st.set_color(c)
		st.set_normal(Vector3.BACK)
		st.add_vertex(v)

static func line_material() -> StandardMaterial3D:
	if _line_material == null:
		_line_material = StandardMaterial3D.new()
		_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_line_material.vertex_color_use_as_albedo = true
		_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _line_material

func _process(delta: float) -> void:
	_t += delta
	var sway: float = flutter
	# A flat kite seen edge-on vanishes: it turns its face to the viewer (on the wire the string
	# lets it swing round; in the sky a kite faces the wind, which is where a player looks from).
	var face_yaw: float = 0.0
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		var to_cam: Vector3 = cam.global_position - global_position
		var local: Vector3 = global_transform.basis.inverse() * to_cam
		if Vector2(local.x, local.z).length_squared() > 0.01:
			face_yaw = atan2(local.x, local.z)
	_body.rotation = Vector3(sin(_t * 2.3) * 0.12 * sway, face_yaw + sin(_t * 1.7) * 0.18 * sway, sin(_t * 3.1) * 0.14 * sway)
	_draw_lines()

func _draw_lines() -> void:
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye: Vector3 = cam.global_position if cam != null else global_position + Vector3.BACK * 5.0
	var bridle: Vector3 = _body.global_transform * Vector3(0.0, BODY_H * 0.18, 0.0)
	if string_end != Vector3.INF:
		_ribbon(bridle, string_end, STRING_W, Color(0.95, 0.95, 0.9), eye)
	# Tail: hangs down and streams back, waving; bows every few decimetres.
	var tail_top: Vector3 = _body.global_transform * Vector3(0.0, -BODY_H * 0.38, 0.0)
	var prev: Vector3 = tail_top
	var segs: int = 8
	for i: int in range(1, segs + 1):
		var f: float = float(i) / float(segs)
		var p: Vector3 = tail_top + Vector3(sin(_t * 4.0 + f * 5.0) * 0.18 * f * flutter, -TAIL_M * f, cos(_t * 3.0 + f * 4.0) * 0.12 * f * flutter)
		_ribbon(prev, p, 0.02, Color(0.98, 0.92, 0.3), eye)
		if i % (segs / TAIL_BOWS + 1) == 0:
			_ribbon(p + Vector3(-0.07, 0.0, 0.0), p + Vector3(0.07, 0.0, 0.0), 0.05, Color(0.2, 0.45, 0.95), eye)
		prev = p
	_im.surface_end()

## A thin strip from a to b that turns to face the camera.
func _ribbon(a: Vector3, b: Vector3, w: float, c: Color, eye: Vector3) -> void:
	var d: Vector3 = b - a
	if d.length_squared() < 0.0001:
		return
	var to_eye: Vector3 = eye - (a + b) * 0.5
	var side: Vector3 = d.cross(to_eye).normalized() * w * 0.5
	if not side.is_finite() or side.length_squared() < 1e-10:
		side = Vector3(w * 0.5, 0.0, 0.0)
	for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_im.surface_set_color(c)
		_im.surface_add_vertex(v)
