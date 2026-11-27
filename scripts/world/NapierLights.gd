class_name NapierLights
extends MeshInstance3D
## Napier Bridge's coloured LED arches after dark (LandmarkKit.napier_lights, shaders/
## napier_lights.gdshader). Hidden by day; fades in with the street lights (StreetLights.lit).

static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/napier_lights.gdshader") as Shader
	return _material

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update()

func _process(_delta: float) -> void:
	_update()

func _update() -> void:
	var on: float = StreetLights.lit(GameState.shift_minute)
	visible = on > 0.001
	if visible:
		material().set_shader_parameter("on", on)
