@tool
class_name WheelModel
extends Node3D
## Procedural tyre + chrome hub (+ leading-link fork and mudguard on the front wheel).
## One vertex-coloured surface = 1 draw call per wheel. Node origin = wheel centre;
## AutoRickshawController moves/steers this node with the suspension.

@export var is_front: bool = false
@export var radius: float = 0.203
@export var width: float = 0.12

func _ready() -> void:
	var st: SurfaceTool = MeshKit.begin()
	var rubber: Color = Color(0.09, 0.09, 0.09)
	var r: float = radius
	var w: float = width * 0.5
	MeshKit.lathe_x(st, Vector3.ZERO, PackedVector2Array([
		Vector2(r * 0.6, -w), Vector2(r * 0.86, -w * 1.08), Vector2(r * 0.98, -w * 0.7),
		Vector2(r, 0.0), Vector2(r * 0.98, w * 0.7), Vector2(r * 0.86, w * 1.08), Vector2(r * 0.6, w)]), 16, rubber)
	for side: float in [-1.0, 1.0]:
		MeshKit.disc(st, Vector3(side * w * 1.0, 0, 0), Vector3(side, 0, 0), r * 0.6, Color(0.78, 0.79, 0.82), 14)
		MeshKit.disc(st, Vector3(side * w * 1.02, 0, 0), Vector3(side, 0, 0), r * 0.18, Color(0.25, 0.25, 0.27), 8)
	if is_front:
		var black: Color = Color(0.07, 0.07, 0.07)
		for side: float in [-1.0, 1.0]:
			# Leading-link fork: arm from the axle back to the pivot, then up into the snout.
			MeshKit.tube(st, Vector3(side * 0.085, 0, 0), Vector3(side * 0.085, 0.05, 0.16), 0.022, black)
			MeshKit.tube(st, Vector3(side * 0.085, 0.05, 0.16), Vector3(side * 0.07, 0.40, 0.12), 0.026, black)
		MeshKit.arc_shell(st, Vector3.ZERO, r + 0.05, 0.15, deg_to_rad(15.0), deg_to_rad(165.0), Color(0.07, 0.07, 0.07)) # black suits every paint
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "WheelMesh"
	mi.mesh = MeshKit.finish(st, mat)
	add_child(mi)
