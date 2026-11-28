class_name QuestFlood
extends Node3D
## A quest's monsoon flood (MissionDef.scenario_flood; data from tools/quests/build_flood.py):
## water standing on the real streets round the quest's places while the quest runs, cleared when
## it ends. Owner request (Nov 28, The Monsoon Supply Run): "it is raining but it does not look
## like a serious situation … add a realistic flood".
##  * Drawn: ONE mesh (one draw call) over the wet grid cells, the surface at road height + depth,
##    shaders/flood_water.gdshader (muddy, rain rings, sheen, foam at the edges). The material is
##    made once in _ready (no pipeline compile in play); the mesh is filled when a quest asks.
##  * Felt: the water depth under the player's auto goes out on SignalBus.water_depth_changed, so
##    the auto's existing water drag, wheel spray and stall-in-deep-water rules apply (stall depth
##    0.28 m: only the basin at the junction the quest says to avoid is that deep).
## MissionDirector asks for it with SignalBus.quest_flood_requested(path) ("" = clear).

const MIN_ABOVE_ROAD_M: float = 0.03
const DEPTH_STEP_M: float = 0.015
const DEPTH_NORM_M: float = 0.6

var active: bool = false
var origin: Vector2 = Vector2.ZERO
var cell: float = 1.5
var nx: int = 0
var nz: int = 0
var road_y: float = 0.06
var _depth: PackedFloat32Array = PackedFloat32Array()
var _wet: PackedFloat32Array = PackedFloat32Array()
var _water: MeshInstance3D
var _mat: ShaderMaterial
var _player: Vector3 = Vector3.INF
var _sent: float = 0.0

func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/flood_water.gdshader") as Shader
	_mat.render_priority = -1
	_water = MeshInstance3D.new()
	_water.name = "FloodWater"
	_water.material_override = _mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.visible = false
	add_child(_water)
	SignalBus.quest_flood_requested.connect(show_flood)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

## Fills the flood from a build_flood.py file, or clears it for "".
func show_flood(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		_clear()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		CrashReporter.capture_message("Quest flood file unreadable: " + path)
		_clear()
		return
	var d: Dictionary = parsed as Dictionary
	var o: Array = d.get("origin", [0.0, 0.0]) as Array
	origin = Vector2(float(o[0]), float(o[1]))
	cell = float(d.get("cell", 1.5))
	nx = int(d.get("nx", 0))
	nz = int(d.get("nz", 0))
	road_y = float(d.get("road_y", 0.06))
	var depth_cm: Array = d.get("depth_cm", []) as Array
	var wet: Array = d.get("wet", []) as Array
	if nx < 2 or nz < 2 or depth_cm.size() != nx * nz or wet.size() != nx * nz:
		CrashReporter.capture_message("Quest flood file has a bad grid: " + path)
		_clear()
		return
	_depth.resize(nx * nz)
	_wet.resize(nx * nz)
	for i: int in nx * nz:
		_depth[i] = float(depth_cm[i]) * 0.01
		_wet[i] = float(wet[i]) * 0.01
	_water.mesh = _build_mesh()
	_water.visible = _water.mesh != null
	active = true

func _clear() -> void:
	active = false
	_water.visible = false
	_water.mesh = null
	_depth = PackedFloat32Array()
	_wet = PackedFloat32Array()
	if _sent > 0.0:
		_sent = 0.0
		SignalBus.water_depth_changed.emit(0.0)

func _build_mesh() -> ArrayMesh:
	var index_of: PackedInt32Array = PackedInt32Array()
	index_of.resize(nx * nz)
	index_of.fill(-1)
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var idx: PackedInt32Array = PackedInt32Array()
	for j: int in nz - 1:
		for i: int in nx - 1:
			var a: int = j * nx + i
			var corners: PackedInt32Array = PackedInt32Array([a, a + 1, a + nx + 1, a + nx])
			var any_wet: bool = false
			for c: int in corners:
				if _wet[c] > 0.0:
					any_wet = true
					break
			if not any_wet:
				continue
			for c: int in corners:
				if index_of[c] < 0:
					index_of[c] = verts.size()
					var gi: int = c % nx
					var gj: int = c / nx
					verts.append(Vector3(origin.x + gi * cell, road_y + MIN_ABOVE_ROAD_M + _depth[c], origin.y + gj * cell))
					cols.append(Color(_wet[c], clampf(_depth[c] / DEPTH_NORM_M, 0.0, 1.0), 0.0, 1.0))
			# Clockwise seen from above (Godot's front face).
			idx.append_array(PackedInt32Array([index_of[corners[0]], index_of[corners[1]], index_of[corners[2]],
				index_of[corners[0]], index_of[corners[2]], index_of[corners[3]]]))
	if idx.is_empty():
		return null
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Water depth at a point (0 where dry): bilinear over the grid, counted only where the spot is
## properly wet (the thin feathered edge is a film, not depth).
func depth_at(x: float, z: float) -> float:
	if not active:
		return 0.0
	var fx: float = (x - origin.x) / cell
	var fz: float = (z - origin.y) / cell
	var i: int = floori(fx)
	var j: int = floori(fz)
	if i < 0 or j < 0 or i >= nx - 1 or j >= nz - 1:
		return 0.0
	var tx: float = fx - i
	var tz: float = fz - j
	var a: int = j * nx + i
	var w: float = lerpf(lerpf(_wet[a], _wet[a + 1], tx), lerpf(_wet[a + nx], _wet[a + nx + 1], tx), tz)
	if w < 0.35:
		return 0.0
	return lerpf(lerpf(_depth[a], _depth[a + 1], tx), lerpf(_depth[a + nx], _depth[a + nx + 1], tx), tz)

func _physics_process(_delta: float) -> void:
	if not active or not _player.is_finite():
		return
	var d: float = depth_at(_player.x, _player.z)
	if absf(d - _sent) >= DEPTH_STEP_M or (d == 0.0 and _sent > 0.0):
		_sent = d
		SignalBus.water_depth_changed.emit(d)
