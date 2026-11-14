class_name ShopPeople
extends MeshInstance3D
## A shopkeeper at every open shop and stall, and a customer or two in front of it (Nov 14
## owner request: "the shops are empty right now").
##
## The city has ~63,000 such spots (dress "shop_people", tools/osm/place_street_life.py):
## far too many for a node or a draw call each. The eight standing figures share one texture
## (tools/assets/bake_shop_people.py), so the nearest MAX_PEOPLE open spots are merged into
## ONE mesh round the camera: one draw call, no nodes, rebuilt only when the camera has moved
## REBUILD_M, a chunk has streamed in or out, or shops open or close. Each figure uses the
## coarse LOD Godot generated on import (about TARGET_TRIS triangles): they stand 5 to 60 m
## from the road.
const MODEL: String = "res://assets/models/people/shop_people.glb"
const MAX_PEOPLE: int = 40
const RANGE_M: float = 62.0
const REBUILD_M: float = 9.0
const TARGET_TRIS: int = 900
## Opening hours (shift clock): shops, and the kerb stalls that open with the morning market.
const SHOP_HOURS: Vector2 = Vector2(8.0, 22.0)
const STALL_HOURS: Vector2 = Vector2(6.0, 21.0)
## Drawn heights of carriageway layers (WorldChunkStreamer.SURF_STYLE): nobody stands there.
const ROAD_BAND: Vector2 = Vector2(0.045, 0.076)
## Nov 14 device report: "the people in front of the shops don't run away when the auto is on
## fire". They are a static mesh, so near a fire they are taken out of it and handed to pooled
## walkers (SignalBus.shop_people_scattered), who run with everyone else. The spots stay empty
## until the player has left (CLEAR_RETURN_M) or CLEAR_HOLD_S after the fire is out.
const FIRE_CLEAR_M: float = 22.0
const CLEAR_RETURN_M: float = 70.0
const CLEAR_HOLD_S: float = 120.0

var world: WorldChunkStreamer = null
## Per figure model: triangle soup at the chosen LOD (positions, normals, uvs).
var _verts: Array[PackedVector3Array] = []
var _norms: Array[PackedVector3Array] = []
var _uvs: Array[PackedVector2Array] = []
var _centre: Vector3 = Vector3(INF, 0.0, INF)
var _chunks: int = -1
var _open_state: int = -1
var _check_s: float = 0.0
var _material: Material = null
## Spots drawn in the last rebuild: [Vector3 position, yaw, kind] (tests, rain shelter).
var shown: Array = []
## Figure ids in model order (mesh names in shop_people.glb).
var ids: Array[String] = []
var _player: Vector3 = Vector3.ZERO
var _burning: bool = false
var _fire_at: Vector3 = Vector3.INF
var _clear_left: float = 0.0

func _ready() -> void:
	name = "ShopPeople"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = ArrayMesh.new()
	_load_models()
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)
	SignalBus.vehicle_burning.connect(_on_burning)

func _load_models() -> void:
	if not ResourceLoader.exists(MODEL):
		return
	var scene: Node3D = (load(MODEL) as PackedScene).instantiate() as Node3D
	var parts: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	parts.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	for n: Node in parts:
		var src: Mesh = (n as MeshInstance3D).mesh
		if src == null or src.get_surface_count() == 0:
			continue
		if _material == null:
			_material = src.surface_get_material(0)
		ids.append(str(n.name))
		var arrays: Array = src.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = _lod_indices(src, arrays[Mesh.ARRAY_INDEX] as PackedInt32Array, v.size())
		var sv: PackedVector3Array = PackedVector3Array()
		var sn: PackedVector3Array = PackedVector3Array()
		var su: PackedVector2Array = PackedVector2Array()
		sv.resize(idx.size())
		sn.resize(idx.size())
		su.resize(idx.size())
		for i: int in idx.size():
			sv[i] = v[idx[i]]
			sn[i] = nn[idx[i]]
			su[i] = uv[idx[i]]
		_verts.append(sv)
		_norms.append(sn)
		_uvs.append(su)
	scene.free()

## The import LOD closest to TARGET_TRIS (never coarser than half of it); the full mesh when the
## renderer keeps no LODs (headless tests).
static func _lod_indices(src: Mesh, full: PackedInt32Array, vertex_count: int) -> PackedInt32Array:
	var best: PackedInt32Array = full
	var surface: Dictionary = RenderingServer.mesh_get_surface(src.get_rid(), 0)
	for lod: Variant in surface.get("lods", []):
		# 4.5 hands each LOD back as a dictionary or as a plain [edge length, index bytes] array.
		var bytes: PackedByteArray = PackedByteArray()
		if lod is Dictionary:
			bytes = (lod as Dictionary).get("index_data", PackedByteArray())
		elif lod is Array:
			for part: Variant in (lod as Array):
				if part is PackedByteArray:
					bytes = part
		var wide: bool = vertex_count > 65535
		var count: int = bytes.size() / (4 if wide else 2)
		if count < TARGET_TRIS * 3 / 2 or count >= best.size():
			continue
		var idx: PackedInt32Array = PackedInt32Array()
		idx.resize(count)
		for i: int in count:
			idx[i] = bytes.decode_u32(i * 4) if wide else bytes.decode_u16(i * 2)
		if count >= TARGET_TRIS * 3:
			best = idx
		elif best.size() > TARGET_TRIS * 6:
			best = idx
	return best

func _on_burning(on: bool) -> void:
	_burning = on
	if not on:
		_clear_left = CLEAR_HOLD_S
		return
	_fire_at = Vector3(_player.x, 0.0, _player.z)
	var leaving: Array = []
	for s: Array in shown:
		var p: Vector3 = s[0]
		if Vector2(p.x - _fire_at.x, p.z - _fire_at.z).length() <= FIRE_CLEAR_M:
			leaving.append([p, float(s[1]), str(s[3])])
	rebuild(_centre if _centre.x != INF else _fire_at)
	if not leaving.is_empty():
		SignalBus.shop_people_scattered.emit(leaving)

## True while the spots round the last fire are kept empty.
func clearing() -> bool:
	return _fire_at != Vector3.INF

func _process(delta: float) -> void:
	if _fire_at != Vector3.INF and not _burning:
		_clear_left -= delta
		if _clear_left <= 0.0 or Vector2(_player.x - _fire_at.x, _player.z - _fire_at.z).length() > CLEAR_RETURN_M:
			_fire_at = Vector3.INF
			_chunks = -1 # people come back on the next check
	_check_s -= delta
	if _check_s > 0.0 or world == null or _verts.is_empty():
		return
	_check_s = 0.5
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var at: Vector3 = cam.global_position
	var state: int = open_state(WorldChunkStreamer.clock_hour(GameState.shift_minute))
	if Vector2(at.x - _centre.x, at.z - _centre.z).length() < REBUILD_M and world.loaded.size() == _chunks and state == _open_state:
		return
	rebuild(Vector3(at.x, 0.0, at.z))

## Bit 0 = shops open, bit 1 = stalls open.
static func open_state(hour: float) -> int:
	return (1 if hour >= SHOP_HOURS.x and hour < SHOP_HOURS.y else 0) | (2 if hour >= STALL_HOURS.x and hour < STALL_HOURS.y else 0)

func rebuild(centre: Vector3) -> void:
	_centre = centre
	_chunks = world.loaded.size()
	_open_state = open_state(WorldChunkStreamer.clock_hour(GameState.shift_minute))
	var near: Array = []
	if _open_state != 0:
		for s: Array in world.street_spots("shop_people", centre, RANGE_M):
			var rec: Array = s[2]
			var kind: int = int(rec[4])
			if (_open_state & (2 if kind == 2 else 1)) == 0:
				continue
			var p: Vector3 = s[0]
			if _fire_at != Vector3.INF and Vector2(p.x - _fire_at.x, p.z - _fire_at.z).length() <= FIRE_CLEAR_M:
				continue
			var h: float = world.surface_height(p.x, p.z, -99.0)
			if h < -50.0 or (h >= ROAD_BAND.x and h <= ROAD_BAND.y) or not world.is_walkable(p.x, p.z):
				continue
			near.append([p.distance_squared_to(centre), Vector3(p.x, h, p.z), float(s[1]), kind, int(rec[3])])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if near.size() > MAX_PEOPLE:
		near.resize(MAX_PEOPLE)
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	shown.clear()
	for n: Array in near:
		var m: int = int(n[4]) % _verts.size()
		var basis: Basis = Basis(Vector3.UP, float(n[2]))
		# Transform * PackedVector3Array runs natively: no per-vertex script work.
		verts.append_array(Transform3D(basis, n[1] as Vector3) * _verts[m])
		norms.append_array(Transform3D(basis, Vector3.ZERO) * _norms[m])
		uvs.append_array(_uvs[m])
		shown.append([n[1], n[2], n[3], ids[m] if m < ids.size() else ""])
	var am: ArrayMesh = mesh as ArrayMesh
	am.clear_surfaces()
	visible = not verts.is_empty()
	if verts.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _material)
