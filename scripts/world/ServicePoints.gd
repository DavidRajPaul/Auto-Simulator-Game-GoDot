class_name ServicePoints
extends Node3D
## LPG bunks, EV kiosks and "Puncture & Tinkering" garages from manifest.json (Phase 4).
## Builds placeholder markers (drawn only within VIS_RANGE_M) and, when the player stops
## next to one, emits SignalBus.service_available so the HUD can offer the service.

const USE_RADIUS_M: float = 13.0
const STOPPED_KMH: float = 6.0
const VIS_RANGE_M: float = 220.0
const TOW_COST_INR: int = 150
const MYLAPORE_WORKSHOP_ASSET: String = "res://assets/models/city/garage_workshop/garage_workshop.glb"
const MYLAPORE_WORKSHOP_SCALE: float = 8.0

@export var world_dir: String = "res://data/world"

var services: Array[Dictionary] = []
var current: Dictionary = {}
var _player_pos: Vector3 = Vector3.ZERO
var _speed_kmh: float = 0.0

func _ready() -> void:
	var f: FileAccess = FileAccess.open(world_dir.path_join("manifest.json"), FileAccess.READ)
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	# LPG bunks with a real station model (city_props.json, tools/osm/place_city_props.py): the
	# refuelling spot moves onto that station's forecourt and the box placeholder is not built.
	var stations: Dictionary = {}
	var pf: FileAccess = FileAccess.open(world_dir.path_join("city_props.json"), FileAccess.READ)
	if pf != null:
		for pr: Dictionary in (JSON.parse_string(pf.get_as_text()) as Dictionary).get("props", []):
			if str(pr.get("model", "")) == "gas_station" and pr.has("service"):
				stations[str(pr["service"])] = pr
	for s: Dictionary in m.get("services", []):
		var sv: Dictionary = {"id": str(s["id"]), "name": str(s["name"]), "kind": str(s["kind"]),
			"pos": Vector3(float(s["x"]), 0.0, float(s["z"])), "yaw": float(s.get("yaw", 0.0))}
		if stations.has(sv["id"]):
			var st: Dictionary = stations[sv["id"]]
			sv["pos"] = Vector3(float(st["fx"]), 0.0, float(st["fz"]))
			sv["station"] = true
		services.append(sv)
		_build_marker(sv)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player_pos = p)
	SignalBus.speed_updated.connect(func(k: float) -> void: _speed_kmh = k)
	SignalBus.tow_requested.connect(func(from: Vector3) -> void:
		var r: Dictionary = tow_to_nearest_fuel(_player_pos if from == Vector3.ZERO else from)
		if not r.is_empty():
			SignalBus.teleport_requested.emit(r["transform"]))

func _physics_process(_delta: float) -> void:
	var near: Dictionary = {}
	for s: Dictionary in services:
		var p: Vector3 = s["pos"]
		if Vector2(p.x - _player_pos.x, p.z - _player_pos.z).length() <= USE_RADIUS_M:
			near = s
			break
	var usable: bool = not near.is_empty() and _speed_kmh <= STOPPED_KMH
	if usable and (current.is_empty() or str(current["id"]) != str(near["id"])):
		current = near
		SignalBus.service_available.emit(str(near["kind"]), {"id": near["id"], "name": near["name"], "kind": near["kind"]})
	elif not usable and not current.is_empty():
		current = {}
		SignalBus.service_unavailable.emit()

## Nearest service of a kind ("lpg" / "ev" / "garage") to a position.
func nearest(kind: String, from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for s: Dictionary in services:
		if str(s["kind"]) != kind:
			continue
		var d: float = (s["pos"] as Vector3).distance_to(from)
		if d < best_d:
			best_d = d
			best = s
	return best

## Out of fuel: pay for a tow to the nearest compatible station. Returns the drop transform.
func tow_to_nearest_fuel(from: Vector3) -> Dictionary:
	var kind: String = "ev" if GameState.active_stats().fuel_type == 2 else "lpg"
	var target: Dictionary = nearest(kind, from)
	if target.is_empty() or not GameState.spend(mini(TOW_COST_INR, GameState.wallet_inr)):
		return {}
	var p: Vector3 = target["pos"]
	return {"transform": Transform3D(Basis(Vector3.UP, float(target["yaw"])), p + Vector3(0, 1.0, 0)), "name": target["name"]}

# --- Markers (simple silhouettes until Phase 5 art) -----------------------------------

func _build_marker(s: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	root.name = str(s["id"])
	root.transform = Transform3D(Basis(Vector3.UP, float(s["yaw"])), s["pos"])
	add_child(root)
	var label: Label3D = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56
	label.outline_size = 14
	label.visibility_range_end = VIS_RANGE_M
	root.add_child(label)
	match str(s["kind"]):
		"lpg" when bool(s.get("station", false)):
			label.text = "LPG AUTOGAS  ₹62/L"
			label.position.y = 7.5
			_add_station_activity(root)
		"lpg":
			_part(root, Vector3(10, 0.4, 7), Vector3(0, 5.2, 0), Color(0.95, 0.95, 0.95))
			_part(root, Vector3(10.2, 0.6, 7.2), Vector3(0, 5.7, 0), Color(0.95, 0.45, 0.05))
			for x: float in [-4.0, 4.0]:
				_part(root, Vector3(0.4, 5.0, 0.4), Vector3(x, 2.5, 0), Color(0.85, 0.85, 0.85))
			_part(root, Vector3(0.9, 1.6, 0.6), Vector3(0, 0.8, 0), Color(0.1, 0.5, 0.25))
			label.text = "LPG  ₹62/L"
			label.position.y = 7.2
		"ev":
			_part(root, Vector3(0.7, 2.0, 0.5), Vector3(0, 1.0, 0), Color(0.12, 0.62, 0.32))
			_part(root, Vector3(4.0, 0.15, 3.0), Vector3(0, 3.0, 0), Color(0.9, 0.95, 0.9))
			label.text = "EV CHARGING  ₹12/kWh"
			label.position.y = 4.0
		"garage":
			if str(s["id"]) == "garage_mylapore" and _add_mylapore_workshop(root):
				label.text = "Mylapore Auto Works"
				label.position.y = 6.0
				return
			_part(root, Vector3(6, 0.25, 5), Vector3(0, 3.2, 0), Color(0.35, 0.2, 0.12))
			_part(root, Vector3(0.25, 3.2, 5), Vector3(-3.0, 1.6, 0), Color(0.6, 0.45, 0.3))
			_part(root, Vector3(6, 3.2, 0.25), Vector3(0, 1.6, 2.5), Color(0.6, 0.45, 0.3))
			for i: int in 3:
				var tyre: CylinderMesh = CylinderMesh.new()
				tyre.top_radius = 0.35
				tyre.bottom_radius = 0.35
				tyre.height = 0.18
				_mesh(root, tyre, Vector3(2.3, 0.1 + i * 0.19, -1.5), Color(0.08, 0.08, 0.08))
			label.text = "Puncture & Tinkering"
			label.position.y = 4.4

## Phase 1A: one imported workshop, retaining the procedural shop as an asset fallback.
## The Tripo model is authored in a unit-sized cube (approx. 1 x .61 x 1).
## Placement/driveway clearance must be verified on the actual Chennai map before release.
func _add_mylapore_workshop(root: Node3D) -> bool:
	if not ResourceLoader.exists(MYLAPORE_WORKSHOP_ASSET):
		return false
	var scene: PackedScene = load(MYLAPORE_WORKSHOP_ASSET) as PackedScene
	if scene == null:
		return false
	var workshop: Node3D = scene.instantiate() as Node3D
	if workshop == null:
		return false
	workshop.name = "MylaporeWorkshop"
	workshop.scale = Vector3.ONE * MYLAPORE_WORKSHOP_SCALE
	root.add_child(workshop)
	# Lightweight side and rear guard colliders protect the workshop shell without
	# placing a solid collider across the vehicle-accessible front bay.
	# Exact correspondence to imported walls must be confirmed in an in-game review.
	_add_workshop_wall(root, "WorkshopRearGuard", Vector3(7.2, 3.5, 0.35), Vector3(0, 1.75, 3.78))
	_add_workshop_wall(root, "WorkshopLeftGuard", Vector3(0.35, 3.5, 7.2), Vector3(-3.65, 1.75, 0))
	_add_workshop_wall(root, "WorkshopRightGuard", Vector3(0.35, 3.5, 7.2), Vector3(3.65, 1.75, 0))
	return true

func _add_workshop_wall(root: Node3D, wall_name: String, wall_size: Vector3, offset: Vector3) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.name = wall_name
	wall.position = offset
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = wall_size
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)

## A busy Chennai forecourt: pump islands and vehicles waiting to refuel.
## These lightweight static GLB instances are built once with the service point.
func _add_station_activity(root: Node3D) -> void:
	for x: float in [-2.6, 2.6]:
		_part(root, Vector3(0.55, 1.25, 0.5), Vector3(x, 0.62, 1.6), Color(0.92, 0.88, 0.18))
		_part(root, Vector3(0.22, 0.18, 0.22), Vector3(x, 1.34, 1.6), Color(0.1, 0.12, 0.13))
	var models: Array[Dictionary] = [
		{"path": "res://assets/models/traffic/hatchback.glb", "pos": Vector3(-5.2, 0.0, -2.8), "size": Vector3(1.7, 1.5, 3.8)},
		{"path": "res://assets/models/traffic/share_auto.glb", "pos": Vector3(0.0, 0.0, -2.8), "size": Vector3(1.5, 1.8, 2.9)},
		{"path": "res://assets/models/traffic/two_wheeler_pack/scooter_parked.glb", "pos": Vector3(5.0, 0.0, -2.8), "size": Vector3(0.8, 1.2, 1.83)},
	]
	for i: int in models.size():
		var item: Dictionary = models[i]
		var path: String = str(item["path"])
		if not ResourceLoader.exists(path):
			continue
		# Real size (was 0.62x: toy cars) and stood on the forecourt (raw models were centred
		# on their origin, so the scooter sank). The holder cancels the station's own scale.
		var vehicle: Node3D = Node3D.new()
		vehicle.name = "RefuellingVehicle_%d" % i
		vehicle.position = item["pos"]
		root.add_child(vehicle)
		var inv: float = 1.0 / maxf(root.global_basis.get_scale().x, 0.01) if root.is_inside_tree() else 1.0
		vehicle.scale = Vector3.ONE * inv
		if not TrafficModelFit.attach(vehicle, path, item["size"] as Vector3, true, true):
			vehicle.queue_free()
			continue
		SignalBus.ground_snap_requested.emit(vehicle)

func _part(root: Node3D, size: Vector3, pos: Vector3, colour: Color) -> void:
	var b: BoxMesh = BoxMesh.new()
	b.size = size
	_mesh(root, b, pos, colour)

func _mesh(root: Node3D, mesh: PrimitiveMesh, pos: Vector3, colour: Color) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = colour
	mesh.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.visibility_range_end = VIS_RANGE_M
	root.add_child(mi)
