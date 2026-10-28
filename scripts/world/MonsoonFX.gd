class_name MonsoonFX
extends Node3D
## Monsoon presentation + hazards (GDD §3 "Madras Monsoon"):
##  • Screen rain streaks; windscreen drops and a working wiper in the cockpit view.
##  • Flood spots from manifest.json fill with water while it rains (WaterlogZone → stall risk).
##  • Wet-road look is handled by WorldChunkStreamer (it listens to weather_changed itself).
## Everything is driven by SignalBus / GameState; no other node is referenced.

const FADE_PER_S: float = 0.35
const DROPS_FILL_PER_S: float = 0.09
const WIPER_PERIOD_S: float = 1.1
const PUDDLE_COLOUR: Color = Color(0.36, 0.33, 0.26, 0.82)

@export var world_dir: String = "res://data/world"

var flood_spots: Array[Dictionary] = []
var rain: float = 0.0 # 0 dry … 1 full rain (smoothed)
var drops: float = 0.0
var wiper_on: bool = false
var _wiper_t: float = 0.0
var _cockpit: bool = false
var _overlay: ColorRect
var _mat: ShaderMaterial
var _zones: Array[WaterlogZone] = []
var _puddles: Array[MeshInstance3D] = []
var _puddle_mat: ShaderMaterial

func _ready() -> void:
	_build_overlay()
	_load_flood_spots()
	rain = 1.0 if GameState.is_raining else 0.0
	_set_flooded(GameState.is_raining)
	SignalBus.weather_changed.connect(_set_flooded)
	SignalBus.wiper_toggled.connect(func(on: bool) -> void: wiper_on = on)
	SignalBus.camera_mode_changed.connect(func(m: String) -> void: _cockpit = m == "Cockpit")

func _process(delta: float) -> void:
	rain = move_toward(rain, 1.0 if GameState.is_raining else 0.0, delta * FADE_PER_S)
	var angle: float = -2.0
	if wiper_on:
		_wiper_t = fmod(_wiper_t + delta, WIPER_PERIOD_S)
		angle = sin(_wiper_t / WIPER_PERIOD_S * TAU) * 1.15
		drops = move_toward(drops, 0.05, delta * 1.5)
	else:
		drops = move_toward(drops, 0.4 * rain, delta * DROPS_FILL_PER_S)
	_overlay.visible = rain > 0.01
	if _overlay.visible:
		_mat.set_shader_parameter("intensity", rain)
		_mat.set_shader_parameter("drops", drops)
		_mat.set_shader_parameter("wiper_angle", angle)
		_mat.set_shader_parameter("cockpit", 1.0 if _cockpit else 0.0)
	for p: MeshInstance3D in _puddles:
		p.visible = rain > 0.05
		p.scale = Vector3.ONE * clampf(rain, 0.05, 1.0)

func _build_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "RainLayer"
	layer.layer = -1 # under the HUD, over the 3D world
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/rain_overlay.gdshader") as Shader
	_overlay.material = _mat
	_overlay.visible = false
	layer.add_child(_overlay)

func _load_flood_spots() -> void:
	var f: FileAccess = FileAccess.open(world_dir.path_join("manifest.json"), FileAccess.READ)
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	_puddle_mat = ShaderMaterial.new()
	_puddle_mat.shader = load("res://shaders/monsoon_puddle.gdshader") as Shader
	_puddle_mat.set_shader_parameter("muddy_water", PUDDLE_COLOUR)
	for s: Dictionary in m.get("flood_spots", []):
		var spot: Dictionary = {"id": str(s["id"]), "name": str(s["name"]), "depth": float(s["depth"]), "r": float(s["r"]),
			"pos": Vector3(float(s["x"]), 0.0, float(s["z"]))}
		flood_spots.append(spot)
		var zone: WaterlogZone = WaterlogZone.new()
		zone.name = spot["id"]
		zone.depth_m = spot["depth"]
		zone.collision_layer = 0
		zone.collision_mask = 2 # player auto
		zone.position = spot["pos"]
		var cs: CollisionShape3D = CollisionShape3D.new()
		var cyl: CylinderShape3D = CylinderShape3D.new()
		cyl.radius = spot["r"]
		cyl.height = 3.0
		cs.shape = cyl
		cs.position.y = 1.0
		zone.add_child(cs)
		add_child(zone)
		_zones.append(zone)
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = spot["r"]
		disc.bottom_radius = spot["r"]
		disc.height = 0.02
		disc.radial_segments = 20
		disc.rings = 1
		disc.material = _puddle_mat
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = spot["id"] + "_water"
		mi.mesh = disc
		mi.position = spot["pos"] + Vector3(0, 0.1, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 250.0
		mi.visible = false
		add_child(mi)
		_puddles.append(mi)

## Flood spots only hold water while it rains.
func _set_flooded(raining: bool) -> void:
	for z: WaterlogZone in _zones:
		z.set_deferred("monitoring", raining)
	if not raining and not _zones.is_empty():
		WaterlogZone.clear_active_flooding()
