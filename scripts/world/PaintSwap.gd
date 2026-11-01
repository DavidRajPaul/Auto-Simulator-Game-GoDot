class_name PaintSwap
extends RefCounted
## Colour variety without new models or draw calls (Nov 1: "variations with colours" for
## two-wheelers, electric autos, dresses and sarees). Every model listed in CONFIG gets the
## paint_swap shader on its textured surfaces; each instance then picks a paint from a
## palette (instance uniform, or MultiMesh custom data for parked vehicles).
##
## CONFIG: model file -> [source colour (the part to repaint, sRGB), hue tolerance (0..0.5),
## min saturation, UV rect (u0, v0, u1, v1) of the garment / body in that model's texture].
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
	"woman_saree_green": [Color8(46, 139, 84), 0.12, 0.2, Vector4(0.5, 0.0, 1.0, 0.5)],
	"woman_saree_maroon": [Color8(152, 36, 52), 0.12, 0.2, Vector4(0.5, 0.0, 1.0, 0.5)],
	"woman_saree_violet": [Color8(174, 76, 186), 0.12, 0.2, Vector4(0.5, 0.0, 1.0, 0.5)],
	"girl_churidar": [Color8(140, 160, 15), 0.12, 0.2, Vector4(0.0, 0.0, 0.5, 0.5)],
	"girl_pavadai": [Color8(200, 70, 120), 0.5, 0.15, Vector4(0.0, 0.0, 0.5, 0.42)], # patterned: rotate every hue
	"man_casual": [Color8(110, 125, 175), 0.12, 0.12, Vector4(0.5, 0.0, 1.0, 0.5)],
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

static var _materials: Dictionary = {} # "<key>|<texture rid>|<custom>" -> ShaderMaterial

## Config key for a model path ("" = not repaintable).
static func key_of(path: String) -> String:
	var k: String = path.get_file().get_basename()
	return k if CONFIG.has(k) else ""

## Palette for a person (sarees vs other dress), or [] if the model is not repaintable.
static func palette_for_person(id: String) -> Array[Color]:
	if not CONFIG.has(id):
		return []
	return SAREE_PAINTS if id.begins_with("woman_saree") or id == "girl_pavadai" else DRESS_PAINTS

## Put the paint_swap material on every textured surface under `root` (once per node).
## `multimesh` = the material reads INSTANCE_CUSTOM (parked vehicles). Returns surfaces set.
static func prepare(root: Node, key: String, multimesh: bool = false) -> int:
	if key == "" or not CONFIG.has(key):
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
