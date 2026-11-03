@tool
class_name AutoRickshawModel
extends Node3D
## Procedural low-poly Bajaj RE "Singara Classic" body (Chennai yellow & black).
## Built once at load into ONE mesh with 3 surfaces (paint/trim, glass, lamps):
## ≈ 3 draw calls for the whole body, ~3k triangles (budget 6.5k incl. wheels).
## Real-world proportions: 2.6 m long, 1.3 m wide, 1.75 m tall, 0.17 m clearance.
## Phase 5 can swap in an artist's GLTF; this keeps the silhouette honest until then.

## Correct for drawn asphalt being 0.06 m above physics ground.
const GROUND_Y: float = -0.745
## The downloaded Chennai auto (rSquare, CC BY 4.0) is ALWAYS the body. Never swap the chassis
## when paint changes (that once replaced the player auto with a different procedural mesh).
## Paint is a real recolour: PAINT_SHADER + PAINT_MASK repaint only the yellow panels (R) and
## the canopy (G) of the original texture; wheels, chrome, seat and chassis are untouched.
## The file's wheels are baked into the body, so the WheelModel nodes are hidden.
const REAL_MODEL: String = "res://assets/models/vehicles/player_auto.glb"
const PAINT_SHADER: String = "res://shaders/auto_paint.gdshader"
const PAINT_MASK: String = "res://assets/models/vehicles/player_auto_paint_mask.png"
const GLASS_SHADER: String = "res://shaders/auto_glass.gdshader"
## Part ids baked into UV2.x by tools/assets/bake_auto_parts.py.
const PART_MIRROR_L: int = 1
const PART_MIRROR_R: int = 2
const LAMP_BREAK_WEAR: float = 70.0
const REAL_SIZE: Vector3 = Vector3(1.3, 1.75, 2.6)
## The driver is the owner's hero (namma_auto_hero.glb) baked once into a static seated pose by
## tools/assets/bake_seated_hero.py: one mesh, one material (the animated file is 33 parts =
## 33 draw calls). Origin = his hip joint, so DRIVER_HIP is the hip point on the front bench.
## PersonMesh's procedural driver is only the fallback if the baked file is missing.
## First release: the driver never leaves the auto (on-foot mode is planned for a later release).
const DRIVER_MODEL: String = "res://assets/models/hero/namma_auto_hero_seated.glb"
const DRIVER_HIP: Vector3 = Vector3(0.0, GROUND_Y + 0.80, -0.20)
const DRIVER_SEAT: Vector3 = Vector3(0.0, GROUND_Y + 0.66, -0.36)

@export var paint: Color = Color(0.98, 0.76, 0.02) # Chennai auto yellow
@export var trim: Color = Color(0.07, 0.07, 0.07) # black canopy / skirts
@export var seat: Color = Color(0.45, 0.08, 0.1) # maroon rexine bench
@export var chrome: Color = Color(0.82, 0.83, 0.86)

var body_mesh: MeshInstance3D
var driver: Node3D
var real_body: Node3D
var uses_real_model: bool = false
## The repaint material on the textured body surface (null until the real model loads).
var paint_material: ShaderMaterial
## The glass shader (windshield crack, mirror glass); null until the real model loads.
var glass_material: ShaderMaterial
var _damage_materials: Array[ShaderMaterial] = []
var _body_mi: MeshInstance3D
var _damage_dirty: bool = false
var _mirror_was_broken: Dictionary = {} # part -> bool
var _debris: Dictionary = {} # part -> RigidBody3D
## True for the auto the player drives (crashes dent it, mirrors fall off); false in menus/garage.
var _live: bool = false

func _ready() -> void:
	build()
	if Engine.is_editor_hint():
		return
	SignalBus.damage_changed.connect(func() -> void: _damage_dirty = true)
	var ctrl: AutoRickshawController = get_parent() as AutoRickshawController
	_live = ctrl != null and ctrl.use_player_profile
	if _live:
		SignalBus.player_impact.connect(_on_player_impact)
		_build_mirror_debris()

func g(h: float) -> float:
	return GROUND_Y + h

func build() -> void:
	_damage_materials.clear()
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
	if driver == null:
		driver = _make_driver()
		add_child(driver)

func _make_driver() -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "Driver"
	var scene: PackedScene = load(DRIVER_MODEL) as PackedScene if ResourceLoader.exists(DRIVER_MODEL) else null
	if scene != null:
		var hero: Node3D = scene.instantiate() as Node3D
		hero.name = "Hero"
		hero.rotation.y = PI # baked facing +Z like every glTF; the auto drives along -Z
		holder.add_child(hero)
		holder.position = DRIVER_HIP
		holder.set_meta("hero", true)
	else:
		var fallback: MeshInstance3D = MeshInstance3D.new()
		fallback.mesh = PersonMesh.seated_auto_driver(0)
		holder.add_child(fallback)
		holder.position = DRIVER_SEAT
	return holder

## True when the seated driver is the owner's hero model (not the procedural fallback).
func driver_is_hero() -> bool:
	return driver != null and driver.has_meta("hero")

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
		_apply_paint_material()
	else:
		holder.queue_free()

## Swaps the textured body surface to the repaint shader (same textures, stock yellow keeps the
## texture's own colours) and the glass to the glass shader. Both draw the visible crash damage
## (dents, broken mirrors, cracked windshield, smashed headlamp) from GameState, so they are always
## on: with no damage they look exactly like the file's own materials. `_force` is kept for callers.
func _apply_paint_material(_force: bool = false) -> void:
	paint_material = null
	glass_material = null
	_damage_materials.clear()
	_body_mi = null
	if real_body == null or not ResourceLoader.exists(PAINT_SHADER) or not ResourceLoader.exists(PAINT_MASK):
		return
	for node: Node in real_body.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		for s: int in mi.mesh.get_surface_count():
			var src: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			if src.albedo_texture == null:
				if src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and ResourceLoader.exists(GLASS_SHADER):
					var gm: ShaderMaterial = ShaderMaterial.new()
					gm.shader = load(GLASS_SHADER) as Shader
					gm.set_shader_parameter("glass_colour", src.albedo_color)
					gm.set_shader_parameter("roughness", src.roughness)
					mi.set_surface_override_material(s, gm)
					glass_material = gm
				continue
			var mat: ShaderMaterial = ShaderMaterial.new()
			mat.shader = load(PAINT_SHADER) as Shader
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			mat.set_shader_parameter("mask_tex", load(PAINT_MASK) as Texture2D)
			if src.normal_enabled and src.normal_texture != null:
				mat.set_shader_parameter("normal_tex", src.normal_texture)
				mat.set_shader_parameter("has_normal", true)
			if src.roughness_texture != null:
				mat.set_shader_parameter("orm_tex", src.roughness_texture)
				mat.set_shader_parameter("has_orm", true)
			# glTF scales the ORM texture by the material factors; keep doing that (metallic 0 here).
			mat.set_shader_parameter("metallic_scale", src.metallic)
			mat.set_shader_parameter("roughness_scale", src.roughness)
			mat.set_shader_parameter("body_colour", paint)
			mat.set_shader_parameter("canopy_colour", trim)
			mat.set_shader_parameter("stock_paint", is_stock_yellow())
			mat.set_shader_parameter("mesh_centre", mi.mesh.get_aabb().get_center())
			mat.set_shader_parameter("mesh_size", mi.mesh.get_aabb().size)
			mi.set_surface_override_material(s, mat)
			paint_material = mat
			_damage_materials.append(mat)
			_body_mi = mi
	_mirror_was_broken = {}
	_refresh_damage()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or real_body == null:
		return
	if _damage_dirty:
		_damage_dirty = false
		_refresh_damage()

## Pushes GameState's damage into the shaders (on SignalBus.damage_changed, deferred one frame so
## GameState and this model have both handled the same impact).
func _refresh_damage() -> void:
	if real_body == null:
		return
	var wear: Dictionary = GameState.damage_state()
	var marks: Dictionary = GameState.marks()
	var panels: Vector4 = Vector4(float(wear["front"]), float(wear["rear"]), float(wear["left"]), float(wear["right"])) / 100.0
	var dents: Array = marks.get("dents", [])
	var packed: Array[Vector4] = []
	for q: Array in dents:
		packed.append(Vector4(float(q[0]), float(q[1]), float(q[2]), float(q[3])))
	while packed.size() < GameState.MAX_DENTS:
		packed.append(Vector4.ZERO)
	var broken_l: bool = float(wear["mirror_l"]) >= 50.0
	var broken_r: bool = float(wear["mirror_r"]) >= 50.0
	for mat: ShaderMaterial in _damage_materials:
		mat.set_shader_parameter("panel_damage", panels)
		mat.set_shader_parameter("dents", packed)
		mat.set_shader_parameter("dent_count", mini(dents.size(), GameState.MAX_DENTS))
		mat.set_shader_parameter("mirror_l_broken", broken_l)
		mat.set_shader_parameter("mirror_r_broken", broken_r)
		mat.set_shader_parameter("lamp_broken", 1.0 if float(wear["lights"]) >= LAMP_BREAK_WEAR else 0.0)
	if glass_material != null:
		var c: Array = marks.get("crack", [0.0, 136.0])
		glass_material.set_shader_parameter("crack", float(wear["glass"]) / 100.0)
		glass_material.set_shader_parameter("crack_origin", Vector2(float(c[0]), float(c[1])))
		glass_material.set_shader_parameter("mirror_l_broken", broken_l)
		glass_material.set_shader_parameter("mirror_r_broken", broken_r)
	# A mirror that just broke falls off (only on the live player auto, never in menus/garage).
	for part: int in [PART_MIRROR_L, PART_MIRROR_R]:
		var now: bool = broken_l if part == PART_MIRROR_L else broken_r
		if now and _mirror_was_broken.has(part) and not bool(_mirror_was_broken[part]) and _live:
			_drop_mirror(part)
		_mirror_was_broken[part] = now

## The player's crash, in this model's mesh space: a dent where it hit, the windshield crack
## origin for front hits. GameState handles the wear itself.
func _on_player_impact(info: Dictionary) -> void:
	if _body_mi == null or not info.has("point"):
		return
	var pm: Vector3 = _body_mi.global_transform.affine_inverse() * (info["point"] as Vector3)
	var strength: float = GameState.DAMAGE.points(float(info.get("speed_mps", 0.0))) / maxf(GameState.DAMAGE.maximum_damage, 0.001)
	if strength <= 0.0:
		return
	# The contact point can sit a little off the hull: pull it onto the body's bounds.
	var box: AABB = _body_mi.mesh.get_aabb()
	pm = pm.clamp(box.position, box.end)
	GameState.add_dent(pm, clampf(strength * 1.6, 0.1, 1.0))
	if pm.z > box.get_center().z + box.size.z * 0.2:
		GameState.set_crack_origin(clampf(pm.x, -40.0, 40.0), clampf(pm.y, 120.0, 152.0))

## Hidden, frozen bodies built once (no instantiate during driving): one per mirror.
func _build_mirror_debris() -> void:
	if _body_mi == null:
		return
	for part: int in [PART_MIRROR_L, PART_MIRROR_R]:
		var mesh: ArrayMesh = _part_mesh(part)
		if mesh == null:
			continue
		var body: RigidBody3D = RigidBody3D.new()
		body.name = "MirrorDebris%d" % part
		body.top_level = true
		body.freeze = true
		body.visible = false
		body.mass = 0.4
		body.collision_layer = 0
		body.collision_mask = 1
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		var cs: CollisionShape3D = CollisionShape3D.new()
		cs.shape = BoxShape3D.new() # sized in metres when it drops
		body.add_child(cs)
		add_child(body)
		_debris[part] = body

## The triangles of one tagged part (both surfaces), with the body's own materials.
func _part_mesh(part: int) -> ArrayMesh:
	var out: ArrayMesh = ArrayMesh.new()
	for node: Node in real_body.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		for s: int in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
			if uv2.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var v: PackedVector3Array = PackedVector3Array()
			var n: PackedVector3Array = PackedVector3Array()
			var t: PackedVector2Array = PackedVector2Array()
			for i: int in range(0, idx.size(), 3):
				if absf(uv2[idx[i]].x - float(part)) > 0.5:
					continue
				for k: int in 3:
					v.append(verts[idx[i + k]])
					n.append(norms[idx[i + k]])
					if not uvs.is_empty():
						t.append(uvs[idx[i + k]])
			if v.is_empty():
				continue
			var a: Array = []
			a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = v
			a[Mesh.ARRAY_NORMAL] = n
			if not t.is_empty():
				a[Mesh.ARRAY_TEX_UV] = t
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			out.surface_set_material(out.get_surface_count() - 1, mi.mesh.surface_get_material(s))
	return out if out.get_surface_count() > 0 else null

## Drop the mirror: the debris copy starts where the mirror was and tumbles off, gone after 6 s.
func _drop_mirror(part: int) -> void:
	if not _debris.has(part) or _body_mi == null:
		return
	var body: RigidBody3D = _debris[part]
	var mi: MeshInstance3D = body.get_child(0) as MeshInstance3D
	var box: AABB = mi.mesh.get_aabb()
	var xf: Transform3D = _body_mi.global_transform
	# Physics bodies stay unscaled: the model's scale (0.01 x fit) goes on the mesh, and the copy is
	# re-centred on its own bounds so it spins about itself.
	var sc: Vector3 = xf.basis.get_scale()
	mi.transform = Transform3D(Basis.from_scale(sc), -box.get_center() * sc)
	((body.get_child(1) as CollisionShape3D).shape as BoxShape3D).size = (box.size * sc).max(Vector3.ONE * 0.04)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf * box.get_center())
	body.visible = true
	body.freeze = false
	var outward: Vector3 = (xf * box.get_center() - global_position)
	outward.y = 0.0
	body.linear_velocity = outward.normalized() * 2.5 + Vector3.UP * 1.5
	body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.freeze = true
			body.visible = false)

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
