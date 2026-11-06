class_name QuestMarkers
extends Node3D
## World signs for the side quests. One MultiMesh (a small spinning gem over a ring on the road)
## marks nearby quest starts and the current job's stop; one Label3D names the nearest of them,
## and one pre-built person waits at a job's stop so it reads as a place, not a road coordinate.
const MAX_MARKERS: int = 4
const REFRESH_S: float = 0.3
const GOLD: Color = Color("ffc21a")
const JOB: Color = Color("3ddc84")
const GEM_Y: float = 3.1
const RING_R: float = 2.7
const PERSON: String = "res://assets/models/people/waiting/man_casual_stand.glb"
@export var tuning: QuestDiscoveryTuning = preload("res://data/missions/discovery_tuning.tres")
var _mm: MultiMesh
var _sign: Label3D
var _person: Node3D
var _player: Vector3 = Vector3.ZERO
var _has_pose: bool = false
var _elapsed: float = 0.0
var _job: Dictionary = {}
var _sign_text: String = ""

func _ready() -> void:
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = marker_mesh()
	_mm.instance_count = MAX_MARKERS
	_mm.visible_instance_count = 0
	instance.multimesh = _mm
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = preload("res://shaders/quest_marker.gdshader")
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 16384.0
	add_child(instance)
	_sign = Label3D.new()
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.fixed_size = true
	_sign.pixel_size = 0.0011
	_sign.font = UIKit.title_font()
	_sign.font_size = 34
	_sign.outline_size = 12
	_sign.outline_modulate = Color(0.05, 0.05, 0.08, 0.95)
	_sign.no_depth_test = true
	_sign.width = 460.0
	_sign.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sign.visible = false
	add_child(_sign)
	var scene: PackedScene = load(PERSON) as PackedScene
	if scene != null:
		_person = scene.instantiate() as Node3D
		_person.visible = false
		add_child(_person)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void:
		_player = p
		_has_pose = true)
	SignalBus.mission_stage_info.connect(_on_stage)
	SignalBus.mission_finished.connect(func(_id: String, _status: String, _reason: String) -> void:
		_job = {}
		_refresh())
	SignalBus.mission_profile_loaded.connect(func() -> void:
		_job = {}
		_refresh())

func _on_stage(info: Dictionary) -> void:
	_job = info if bool(info.get("located", false)) else {}
	_refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_S or not _has_pose:
		return
	_elapsed = 0.0
	_refresh()

## Quest starts nearest first. Job stops replace them: a running job shows only its own stop.
func _refresh() -> void:
	var entries: Array[Dictionary] = []
	if not _job.is_empty():
		entries.append({"pos": _job["target"], "colour": JOB})
	elif not GameState.mission_active and not GameState.tutorial_active and SignalBus.quest_discovery_provider.is_valid():
		var rows: Array = SignalBus.quest_discovery_provider.call()
		for row: Dictionary in rows:
			var at: Vector3 = row["position"]
			var d: float = at.distance_to(_player)
			if bool(row["unlocked"]) and not bool(row["completed"]) and d <= tuning.marker_range_m:
				entries.append({"pos": at, "colour": GOLD, "d": d, "title": row["title"]})
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var count: int = mini(entries.size(), MAX_MARKERS)
	_mm.visible_instance_count = count
	for i: int in count:
		var at: Vector3 = entries[i]["pos"]
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(at.x, 0.12, at.z)))
		_mm.set_instance_color(i, entries[i]["colour"] as Color)
	_refresh_sign(entries)

func _refresh_sign(entries: Array[Dictionary]) -> void:
	var text: String = ""
	var at: Vector3 = Vector3.ZERO
	var colour: Color = GOLD
	if not _job.is_empty():
		at = _job["place_pos"] if _job["place_pos"] != Vector3.ZERO else _job["target"]
		text = tr(str(_job["place"])) if str(_job["place"]) != "" else ""
		colour = JOB
	elif not entries.is_empty() and float(entries[0]["d"]) <= tuning.marker_label_m:
		at = entries[0]["pos"]
		text = str(entries[0]["title"])
	_sign.visible = text != ""
	if text == "":
		_show_person(false, Vector3.ZERO)
		return
	if text != _sign_text:
		_sign_text = text
		_sign.text = text
	_sign.modulate = colour
	_sign.position = Vector3(at.x, 5.2, at.z)
	var by_road: Vector3 = at
	if not _job.is_empty():
		by_road = at.move_toward(_job["target"] as Vector3, 1.3) # In front of the shop, not inside.
	_show_person(not _job.is_empty() and _job["place_pos"] != Vector3.ZERO, by_road)

func _show_person(show_it: bool, at: Vector3) -> void:
	if _person == null:
		return
	_person.visible = show_it
	if show_it:
		_person.position = Vector3(at.x, SignalBus.surface_height(at.x, at.z, 0.08), at.z)
		_person.look_at(Vector3(_player.x, _person.position.y, _player.z) + Vector3(0.01, 0.0, 0.01), Vector3.UP, true)

## Gem (UV.x = 1, spun by the shader) over a thin flat ring. One surface, vertex data only.
static func marker_mesh() -> ArrayMesh:
	var v: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	var col: PackedColorArray = PackedColorArray()
	var top: Vector3 = Vector3(0.0, GEM_Y + 0.42, 0.0)
	var low: Vector3 = Vector3(0.0, GEM_Y - 0.42, 0.0)
	var sides: int = 4
	for i: int in sides:
		var a: Vector3 = Vector3(cos(TAU * i / sides), 0.0, sin(TAU * i / sides)) * 0.28 + Vector3(0.0, GEM_Y, 0.0)
		var b: Vector3 = Vector3(cos(TAU * (i + 1) / sides), 0.0, sin(TAU * (i + 1) / sides)) * 0.28 + Vector3(0.0, GEM_Y, 0.0)
		var shade: float = 1.0 if i % 2 == 0 else 0.72
		for tri: Array in [[top, a, b, shade], [low, b, a, shade * 0.8]]:
			for corner: int in 3:
				v.append(tri[corner] as Vector3)
				uv.append(Vector2(1.0, 0.0))
				col.append(Color(float(tri[3]), float(tri[3]), float(tri[3])))
	var segments: int = 32
	for i: int in segments:
		var a0: float = TAU * i / segments
		var a1: float = TAU * (i + 1) / segments
		var inner: float = RING_R - 0.22
		var p0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var p1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		for point: Vector3 in [p0 * inner, p0 * RING_R, p1 * RING_R, p0 * inner, p1 * RING_R, p1 * inner]:
			v.append(point)
			uv.append(Vector2.ZERO)
			col.append(Color.WHITE)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = col
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
