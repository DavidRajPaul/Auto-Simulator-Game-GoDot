class_name ServicePoints
extends Node3D
## LPG bunks, EV kiosks and "Puncture & Tinkering" garages from manifest.json (Phase 4).
## Builds placeholder markers (drawn only within VIS_RANGE_M) and, when the player stops
## next to one, emits SignalBus.service_available so the HUD can offer the service.

const USE_RADIUS_M: float = 13.0
const STOPPED_KMH: float = 6.0
const VIS_RANGE_M: float = 220.0
const TOW_COST_INR: int = 150

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
		var r: Dictionary = tow_to_nearest_fuel(from)
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
