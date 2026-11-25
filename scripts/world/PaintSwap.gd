class_name PaintSwap
extends RefCounted
## Colour variety without new models or draw calls (Nov 1: "variations with colours" for
## two-wheelers, electric autos, dresses and sarees). Every model listed in CONFIG gets the
## paint_swap shader on its textured surfaces; each instance then picks a paint from a
## palette (instance uniform, or MultiMesh custom data for parked vehicles).
##
## CONFIG: model file -> [source colour (the part to repaint, sRGB), hue tolerance (0..0.5),
## min saturation, UV rect (u0, v0, u1, v1) of the garment / body in that model's texture,
## optional true = tint mode for WHITE cloth (min saturation then means "at most this saturated"),
## optional second UV rect + minimum model-space height (m) painted the same way].
## The rects were read off each texture (sarees: the solid block at top right, etc.).

const SHADER: Shader = preload("res://shaders/paint_swap.gdshader")
const NO_PAINT: Color = Color(0, 0, 0, 0)

const CONFIG: Dictionary = {
	# Vehicles: repaint the body colour wherever it is in the atlas.
	"share_auto": [Color8(227, 198, 0), 0.07, 0.45, Vector4(0, 0, 1, 1)],
	"two_wheeler": [Color8(71, 110, 94), 0.07, 0.2, Vector4(0, 0, 1, 1)],
	"scooter_parked": [Color8(71, 110, 94), 0.07, 0.2, Vector4(0, 0, 1, 1)],
	"sport_bike_0": [Color8(255, 204, 24), 0.05, 0.4, Vector4(0, 0, 1, 1)],
	"sport_bike_1": [Color8(38, 188, 35), 0.06, 0.4, Vector4(0, 0, 1, 1)],
	"sport_bike_2": [Color8(215, 0, 38), 0.03, 0.6, Vector4(0, 0, 1, 1)],
	"sport_bike_3": [Color8(252, 97, 133), 0.03, 0.4, Vector4(0, 0, 1, 1)],
	# People: the garment's block in the texture.
	# Nov 20: rects and colours come from people.json "paint" (process_people.py writes them when
	# it rebuilds a character); the atlas layout changed with the face / hands fix.
	"woman_saree_green": [Color8(48, 139, 84), 0.12, 0.2, Vector4(0.5, 0.7656, 0.5156, 0.7812)],
	"woman_saree_maroon": [Color8(155, 38, 56), 0.12, 0.2, Vector4(0.5, 0.7656, 0.5156, 0.7812)],
	"woman_saree_violet": [Color8(179, 76, 186), 0.12, 0.2, Vector4(0.5, 0.7656, 0.5156, 0.7812)],
	"girl_churidar": [Color8(108, 131, 0), 0.12, 0.2, Vector4(0.0, 0.0, 0.5, 0.5)],
	"girl_pavadai": [Color8(200, 70, 120), 0.5, 0.15, Vector4(0.0, 0.0, 0.5, 0.5)], # patterned: rotate every hue
	"woman_saree_kanchi": [Color8(53, 14, 0), 0.04, 0.3, Vector4(0.0, 0.0, 0.5, 0.5)],
	"woman_coat": [Color8(183, 131, 93), 0.06, 0.25, Vector4(0.5, 0.0, 1.0, 0.5)],
	"man_casual": [Color8(110, 125, 175), 0.12, 0.12, Vector4(0.5, 0.0, 1.0, 0.5)],
	# Nov 25 (owner: "same models often"): the men vary too. Rects found by mapping each texture
	# block to body height on the mesh: the old man's shirt is the right-hand white block (his
	# veshti, the left block, stays white); the Mixamo man's jeans are the blue block at left.
	# young_man stays as he is: his striped shirt shares one block with his face (eye whites).
	# His veshti's waist band shows above the shirt hem: painted with the shirt above 0.88 m.
	"old_man_veshti": [Color8(231, 231, 231), 0.0, 0.08, Vector4(0.5, 0.0, 0.875, 0.5), true, Vector4(0.0, 0.35, 0.5, 0.5), 0.88],
	"mixamo_ch22": [Color8(29, 43, 77), 0.08, 0.3, Vector4(0.0, 0.1, 0.28, 0.5)],
}

## Two-wheeler colours seen on Chennai roads (Activa/Jupiter/Splendor/Pulsar): black, white,
## grey, silver, red, maroon, blue, matte green; NO_PAINT keeps the model's own colour.
const TWO_WHEELER_PAINTS: Array[Color] = [
	Color(0, 0, 0, 0), Color8(28, 28, 32), Color8(236, 236, 232), Color8(118, 122, 128), Color8(176, 180, 186),
	Color8(178, 24, 30), Color8(110, 22, 34), Color8(30, 70, 160), Color8(70, 90, 60), Color8(220, 130, 30),
]
## NPC autos: the stock yellow, then electric autos (blue / teal body: Treo, M Auto feeders; all
## EVs carry a green number plate) and the women-driven CNG pink autos (TN, 2025).
const AUTO_YELLOW: Color = Color(0, 0, 0, 0)
const AUTO_ELECTRIC: Array[Color] = [Color8(30, 96, 196), Color8(0, 150, 140)]
const AUTO_PINK: Color = Color8(236, 92, 160)
## Sarees: maroon, mustard, magenta, royal blue, parrot green, orange, peacock blue, purple, red,
## pink, turmeric yellow, bottle green.
const SAREE_PAINTS: Array[Color] = [
	Color8(128, 20, 40), Color8(212, 160, 23), Color8(200, 30, 120), Color8(30, 60, 170),
	Color8(70, 170, 50), Color8(235, 110, 20), Color8(0, 110, 130), Color8(100, 40, 140),
	Color8(200, 20, 30), Color8(240, 120, 170), Color8(240, 200, 30), Color8(20, 90, 50),
]
## Shirts / kurtas / churidars.
const DRESS_PAINTS: Array[Color] = [
	Color8(235, 235, 230), Color8(150, 190, 230), Color8(230, 200, 150), Color8(200, 60, 60),
	Color8(60, 120, 80), Color8(240, 180, 40), Color8(120, 80, 160), Color8(40, 50, 90),
	Color8(250, 150, 120), Color8(90, 160, 170),
]

## Men's shirts in Chennai: white leads, then pale blue, cream, light grey, sandal, pale green,
## light pink, lavender, then a few darker ones (navy, maroon, olive).
const SHIRT_PAINTS: Array[Color] = [
	Color8(170, 200, 235), Color8(240, 228, 196), Color8(196, 198, 200), Color8(222, 196, 150),
	Color8(176, 214, 176), Color8(236, 190, 196), Color8(196, 180, 222), Color8(44, 58, 104),
	Color8(122, 32, 44), Color8(98, 104, 60),
]
## Trousers: black, charcoal, navy, khaki, olive, brown, grey.
const TROUSER_PAINTS: Array[Color] = [
	Color8(22, 22, 26), Color8(58, 58, 64), Color8(30, 40, 78), Color8(170, 150, 110),
	Color8(84, 90, 56), Color8(92, 64, 44), Color8(120, 122, 126),
]

## Chennai vehicles built by tools/art/make_chennai_vehicles.py: no texture; the body panels
## carry vertex alpha 0 and shaders/vehicle_paint.gdshader repaints them per instance.
const VERTEX_PAINTED: Array[String] = ["moped", "commuter_bike", "cruiser_bike", "bicycle", "hatchback", "tallboy", "micro_van", "mini_truck"]
const VERTEX_SHADER: Shader = preload("res://shaders/vehicle_paint.gdshader")
## Car colours on Chennai roads: white and silver lead, then grey, red, maroon, dark blue, black,
## and the brighter small-car colours (orange, sky blue, beige). NO_PAINT keeps the silver.
const CAR_PAINTS: Array[Color] = [
	Color8(236, 236, 232), Color8(240, 240, 236), Color8(232, 232, 228), Color(0, 0, 0, 0), Color8(176, 180, 186),
	Color8(104, 108, 114), Color8(178, 30, 28), Color8(112, 26, 34), Color8(34, 58, 112), Color8(30, 31, 34),
	Color8(214, 110, 36), Color8(96, 150, 196), Color8(206, 190, 160), Color8(236, 236, 232),
]

static var _materials: Dictionary = {} # "<key>|<texture rid>|<custom>" -> ShaderMaterial

## Config key for a model path ("" = not repaintable).
static func key_of(path: String) -> String:
	var k: String = path.get_file().get_basename()
	return k if CONFIG.has(k) or VERTEX_PAINTED.has(k) else ""

## Palette for a vehicle key (cars vs two-wheelers).
static func vehicle_palette(key: String) -> Array[Color]:
	return CAR_PAINTS if key in ["hatchback", "tallboy", "micro_van", "mini_truck"] else TWO_WHEELER_PAINTS

## Palette for a person (sarees vs other dress), or [] if the model is not repaintable.
static func palette_for_person(id: String) -> Array[Color]:
	if not CONFIG.has(id):
		return []
	if id.begins_with("woman_saree") or id == "girl_pavadai":
		return SAREE_PAINTS
	if id == "old_man_veshti":
		return SHIRT_PAINTS
	if id == "mixamo_ch22":
		return TROUSER_PAINTS
	return DRESS_PAINTS

## Put the paint_swap material on every textured surface under `root` (once per node).
## `multimesh` = the material reads INSTANCE_CUSTOM (parked vehicles). Returns surfaces set.
static func prepare(root: Node, key: String, multimesh: bool = false) -> int:
	if key == "" or not (CONFIG.has(key) or VERTEX_PAINTED.has(key)):
		return 0
	var n: int = 0
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node: Node in meshes:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var m: ShaderMaterial = material_for(mi.mesh.surface_get_material(s), key, multimesh)
			if m != null:
				mi.set_surface_override_material(s, m)
				n += 1
	return n

## Shared ShaderMaterial for an imported material's albedo texture.
static func material_for(src: Material, key: String, multimesh: bool) -> ShaderMaterial:
	if VERTEX_PAINTED.has(key):
		var vid: String = "vertex|%s" % multimesh
		if not _materials.has(vid):
			var vm: ShaderMaterial = ShaderMaterial.new()
			vm.shader = VERTEX_SHADER
			vm.set_shader_parameter("use_custom", multimesh)
			_materials[vid] = vm
		return _materials[vid]
	var base: BaseMaterial3D = src as BaseMaterial3D
	if base == null or base.albedo_texture == null:
		return null
	var id: String = "%s|%d|%s" % [key, base.albedo_texture.get_rid().get_id(), multimesh]
	if _materials.has(id):
		return _materials[id]
	var cfg: Array = CONFIG[key]
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_tex", base.albedo_texture)
	m.set_shader_parameter("src_colour", cfg[0])
	m.set_shader_parameter("hue_tol", cfg[1])
	m.set_shader_parameter("min_sat", cfg[2])
	m.set_shader_parameter("rect", cfg[3])
	m.set_shader_parameter("tint_mode", cfg.size() > 4 and bool(cfg[4]))
	if cfg.size() > 6:
		m.set_shader_parameter("rect2", cfg[5])
		m.set_shader_parameter("rect2_min_y", float(cfg[6]))
	m.set_shader_parameter("use_custom", multimesh)
	m.set_shader_parameter("roughness_value", base.roughness)
	m.set_shader_parameter("metallic_value", base.metallic)
	_materials[id] = m
	return m

## Set the paint of everything under `root` (after prepare). NO_PAINT = original colours.
static func set_paint(root: Node, paint: Color) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node: Node in meshes:
		(node as GeometryInstance3D).set_instance_shader_parameter("paint", paint)
