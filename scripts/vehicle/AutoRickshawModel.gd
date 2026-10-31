@tool
class_name AutoRickshawModel
extends Node3D
## Procedural low-poly Bajaj RE "Singara Classic" body (Chennai yellow & black).
## Built once at load into ONE mesh with 3 surfaces (paint/trim, glass, lamps):
## ≈ 3 draw calls for the whole body, ~3k triangles (budget 6.5k incl. wheels).
## Real-world proportions: 2.6 m long, 1.3 m wide, 1.75 m tall, 0.17 m clearance.
## Phase 5 can swap in an artist's GLTF; this keeps the silhouette honest until then.

const GROUND_Y: float = -0.80 # road height relative to the chassis origin at rest
## The downloaded Chennai auto (rSquare, CC BY 4.0) replaces the procedural body while the paint
## is stock yellow. Never swap the chassis when paint changes: this caused purchased colors
## to replace the player auto with a different procedural mesh. Until a paint-mask asset
## exists, custom paint is saved but the imported model keeps its original texture.
## The file's wheels are baked into the body, so the WheelModel nodes are hidden.
const REAL_MODEL: String = "res://assets/models/vehicles/player_auto.glb"
const REAL_SIZE: Vector3 = Vector3(1.3, 1.75, 2.6)

@export var paint: Color = Color(0.98, 0.76, 0.02) # Chennai auto yellow
@export var trim: Color = Color(0.07, 0.07, 0.07) # black canopy / skirts
@export var seat: Color = Color(0.45, 0.08, 0.1) # maroon rexine bench
@export var chrome: Color = Color(0.82, 0.83, 0.86)

var body_mesh: MeshInstance3D
var real_body: Node3D
var uses_real_model: bool = false

func _ready() -> void:
	build()

func g(h: float) -> float:
	return GROUND_Y + h

func build() -> void:
	if body_mesh != null:
		body_mesh.queue_free()
	var mesh: ArrayMesh = ArrayMesh.new()
	var st: SurfaceTool = MeshKit.begin()
	_build_body(st)
	var opaque: StandardMaterial3D = StandardMaterial3D.new()
	opaque.vertex_color_use_as_albedo = true
	opaque.vertex_color_is_srgb = true
	opaque.roughness = 0.42
	opaque.metallic_specular = 0.6
	opaque.cull_mode = BaseMaterial3D.CULL_DISABLED # thin canvas & arches are single sheets
	MeshKit.finish(st, opaque, mesh)

	var glass: SurfaceTool = MeshKit.begin()
	_build_glass(glass)
	var glass_mat: StandardMaterial3D = StandardMaterial3D.new()
	glass_mat.vertex_color_use_as_albedo = true
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.05
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	MeshKit.finish(glass, glass_mat, mesh)

	var lamps: SurfaceTool = MeshKit.begin()
	_build_lamps(lamps)
	var lamp_mat: StandardMaterial3D = StandardMaterial3D.new()
	lamp_mat.vertex_color_use_as_albedo = true
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	MeshKit.finish(lamps, lamp_mat, mesh)

	body_mesh = MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	body_mesh.mesh = mesh
	add_child(body_mesh)
	_attach_real_model()

## Stock Chennai yellow (Singara Classic, King Deluxe) with a dark canopy.
func is_stock_yellow() -> bool:
	return paint.h > 0.09 and paint.h < 0.17 and paint.s > 0.7 and paint.v > 0.8 and trim.v < 0.25

func _attach_real_model() -> void:
	if real_body != null:
		real_body.queue_free()
		real_body = null
	uses_real_model = false
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var holder: Node3D = Node3D.new()
	holder.name = "RealBody"
	holder.position.y = GROUND_Y
	add_child(holder)
	if TrafficModelFit.attach(holder, REAL_MODEL, REAL_SIZE, true):
		real_body = holder
		uses_real_model = true
		body_mesh.visible = false
	else:
		holder.queue_free()

func triangle_count() -> int:
	var n: int = 0
	if body_mesh == null:
		return 0
	for s: int in body_mesh.mesh.get_surface_count():
		n += (body_mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n

# --- Body -------------------------------------------------------------------

func _build_body(st: SurfaceTool) -> void:
	var dark_paint: Color = paint.darkened(0.25)

	# Passenger tub: rounded section from the driver bulkhead back to the rounded tail.
	var tub: Array[PackedVector3Array] = []
	var tub_z: Array[float] = [-0.42, 0.0, 0.6, 1.05, 1.2, 1.27]
	var tub_w: Array[float] = [1.20, 1.28, 1.30, 1.28, 1.20, 1.02]
	var tub_top: Array[float] = [0.80, 0.80, 0.82, 0.84, 0.84, 0.80]
	for i: int in tub_z.size():
		tub.append(MeshKit.rounded_ring(tub_z[i], tub_w[i], g(0.30), g(tub_top[i]), 0.13))
	MeshKit.loft(st, tub, paint, true, true, true)
	# Black skirt band along the bottom of the tub.
	var skirt: Array[PackedVector3Array] = []
	for i: int in tub_z.size():
		skirt.append(MeshKit.rounded_ring(tub_z[i], tub_w[i] + 0.02, g(0.28), g(0.42), 0.06))
	MeshKit.loft(st, skirt, trim, true, true, true)

	# Front nose / cowl: the iconic tapering Bajaj snout, top rising into the dash.
	var nose: Array[PackedVector3Array] = []
	var nz: Array[float] = [-0.42, -0.70, -0.98, -1.18, -1.30]
	var nw: Array[float] = [1.20, 1.02, 0.80, 0.62, 0.50]
	var nb: Array[float] = [0.30, 0.32, 0.36, 0.42, 0.48]
	var nt: Array[float] = [1.08, 1.06, 1.00, 0.94, 0.86]
	for i: int in nz.size():
		nose.append(MeshKit.rounded_ring(nz[i], nw[i], g(nb[i]), g(nt[i]), 0.16))
	MeshKit.loft(st, nose, paint, true, false, true)
	# Chrome strip around the snout's nose.
	MeshKit.loft(st, [MeshKit.rounded_ring(-1.24, 0.585, g(0.445), g(0.905), 0.16), MeshKit.rounded_ring(-1.27, 0.555, g(0.46), g(0.885), 0.16)], chrome, true)
	# Dashboard lip under the windscreen.
	MeshKit.box(st, Vector3(0, g(1.10), -0.55), Vector3(1.08, 0.05, 0.22), trim)

	# Canopy: black canvas arch from the windscreen header to the rear.
	var arch: Array[PackedVector3Array] = []
	var cz: Array[float] = [-0.66, -0.55, 0.0, 0.6, 1.08, 1.22]
	var cw: Array[float] = [1.20, 1.30, 1.34, 1.34, 1.32, 1.22]
	for i: int in cz.size():
		arch.append(_arch(cz[i], cw[i] * 0.5, g(1.18), g(1.76)))
	MeshKit.loft(st, arch, trim, false)
	# Rear canopy panel (closed back with a small window, drawn in the glass pass).
	_fan(st, arch[arch.size() - 1], Vector3(0, g(1.40), 1.22), trim)
	MeshKit.box(st, Vector3(0, g(1.0), 1.24), Vector3(1.0, 0.36, 0.03), trim)
	# Pillars: windscreen A-pillars, B-pillars behind the driver, rear C-pillars.
	for sx: float in [-1.0, 1.0]:
		MeshKit.tube(st, Vector3(sx * 0.55, g(1.08), -0.70), Vector3(sx * 0.62, g(1.66), -0.58), 0.025, trim)
		MeshKit.tube(st, Vector3(sx * 0.63, g(0.82), 0.02), Vector3(sx * 0.66, g(1.30), 0.02), 0.022, chrome)
		MeshKit.tube(st, Vector3(sx * 0.62, g(0.84), 1.15), Vector3(sx * 0.64, g(1.25), 1.15), 0.025, trim)
		# Chrome grab rail along the passenger opening.
		MeshKit.tube(st, Vector3(sx * 0.665, g(1.28), 0.02), Vector3(sx * 0.665, g(1.26), 1.12), 0.018, chrome)
		# Rear mudguards over the drive wheels.
		MeshKit.arc_shell(st, Vector3(sx * 0.58, g(0.20), 0.88), 0.27, 0.2, deg_to_rad(-15.0), deg_to_rad(195.0), trim)
		# Mirror stalks + heads.
		MeshKit.tube(st, Vector3(sx * 0.50, g(1.10), -0.62), Vector3(sx * 0.68, g(1.32), -0.66), 0.012, chrome)
		MeshKit.box(st, Vector3(sx * 0.70, g(1.36), -0.66), Vector3(0.09, 0.13, 0.03), trim)
		# Side indicator housings on the snout.
		MeshKit.box(st, Vector3(sx * 0.33, g(0.78), -1.14), Vector3(0.07, 0.05, 0.06), dark_paint)

	# Seats.
	MeshKit.box(st, Vector3(0, g(0.88), -0.12), Vector3(0.46, 0.10, 0.36), trim) # driver
	MeshKit.box(st, Vector3(0, g(0.89), 0.78), Vector3(1.16, 0.12, 0.52), seat) # rear bench
	MeshKit.box(st, Vector3(0, g(1.12), 1.08), Vector3(1.16, 0.40, 0.10), seat, Basis(Vector3.RIGHT, deg_to_rad(-8.0)))

	# Handlebar, steering column, fare meter box.
	MeshKit.tube(st, Vector3(0, g(0.70), -0.78), Vector3(0, g(1.08), -0.60), 0.03, trim)
	MeshKit.tube(st, Vector3(-0.34, g(1.10), -0.56), Vector3(0.34, g(1.10), -0.56), 0.017, chrome)
	MeshKit.tube(st, Vector3(-0.34, g(1.10), -0.56), Vector3(-0.27, g(1.10), -0.56), 0.026, trim)
	MeshKit.tube(st, Vector3(0.27, g(1.10), -0.56), Vector3(0.34, g(1.10), -0.56), 0.026, trim)
	MeshKit.box(st, Vector3(-0.44, g(1.16), -0.64), Vector3(0.11, 0.08, 0.07), trim) # meter box

	# Front chrome bumper guard + number plate.
	MeshKit.tube(st, Vector3(-0.36, g(0.40), -1.36), Vector3(0.36, g(0.40), -1.36), 0.02, chrome)
	for sx: float in [-0.3, 0.3]:
		MeshKit.tube(st, Vector3(sx, g(0.40), -1.36), Vector3(sx * 0.8, g(0.52), -1.28), 0.016, chrome)
	MeshKit.box(st, Vector3(0, g(0.58), -1.315), Vector3(0.26, 0.10, 0.02), Color(0.95, 0.85, 0.1))
	MeshKit.box(st, Vector3(0, g(0.48), 1.285), Vector3(0.32, 0.12, 0.02), Color(0.95, 0.85, 0.1))
	# Rear bumper bar.
	MeshKit.tube(st, Vector3(-0.5, g(0.34), 1.31), Vector3(0.5, g(0.34), 1.31), 0.02, chrome)

## Canopy cross-section: open arch from left side, over the roof, to right side.
func _arch(z: float, half_w: float, y_side: float, y_top: float) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	var n: int = 10
	for i: int in n + 1:
		var t: float = PI * float(i) / float(n) # 0 = right side, PI = left side
		var c: float = cos(t)
		var s: float = pow(sin(t), 0.32) # flat-topped hood
		pts.append(Vector3(c * half_w, y_side + (y_top - y_side) * s, z))
	return pts

func _fan(st: SurfaceTool, ring: PackedVector3Array, centre: Vector3, colour: Color) -> void:
	st.set_color(colour)
	st.set_smooth_group(-1)
	for i: int in ring.size() - 1:
		st.add_vertex(centre)
		st.add_vertex(ring[i])
		st.add_vertex(ring[i + 1])

func _build_glass(st: SurfaceTool) -> void:
	var tint: Color = Color(0.55, 0.7, 0.8, 0.32)
	MeshKit.quad(st, Vector3(-0.54, g(1.10), -0.70), Vector3(0.54, g(1.10), -0.70), Vector3(0.6, g(1.66), -0.58), Vector3(-0.6, g(1.66), -0.58), tint)
	MeshKit.quad(st, Vector3(-0.32, g(1.42), 1.225), Vector3(0.32, g(1.42), 1.225), Vector3(0.28, g(1.62), 1.225), Vector3(-0.28, g(1.62), 1.225), tint)

func _build_lamps(st: SurfaceTool) -> void:
	MeshKit.disc(st, Vector3(0, g(0.80), -1.305), Vector3.BACK * -1.0, 0.085, Color(1.0, 0.98, 0.85), 14) # headlamp
	MeshKit.disc(st, Vector3(0, g(0.80), -1.300), Vector3.FORWARD, 0.105, chrome.darkened(0.2), 14)
	for sx: float in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(sx * 0.37, g(0.78), -1.14), Vector3(0.02, 0.035, 0.045), Color(1.0, 0.55, 0.05)) # indicators
		MeshKit.box(st, Vector3(sx * 0.46, g(0.68), 1.275), Vector3(0.12, 0.08, 0.02), Color(0.9, 0.05, 0.05)) # tail lamps
	# Red digits on the fare meter, facing the driver.
	MeshKit.box(st, Vector3(-0.44, g(1.165), -0.603), Vector3(0.08, 0.03, 0.005), Color(1.0, 0.12, 0.08))
