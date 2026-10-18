class_name ChennaiTrafficManager
extends Node3D
## Object-pooled mixed traffic on a straight road running along Z (traffic heads -Z).
## Each lane is split into 3 sub-lanes (LeftEdge, Center, RightOvertake).
## Hard limits from AGENTS.md: ≤ 18 active vehicles within 120 m; no instantiate()/queue_free()
## after _ready.

const MAX_POOL: int = 18
const RECYCLE_RADIUS_M: float = 120.0
const SPAWN_MIN_AHEAD_M: float = 45.0
const SPAWN_MAX_AHEAD_M: float = 110.0
const SUB_LANE_WIDTH_M: float = 2.2
## Weights for TWO_WHEELER, HATCHBACK, SHARE_AUTO, MTC_BUS.
const ARCHETYPE_MIX: Array[int] = [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 0, 1, 2]
const ARCHETYPE_COLOURS: Array[Color] = [Color(0.15, 0.25, 0.75), Color(0.85, 0.85, 0.85), Color(0.2, 0.6, 0.25), Color(0.25, 0.45, 0.85)]

@export var vehicle_scene: PackedScene
@export var player_path: NodePath
@export var lane_count: int = 2
@export var road_min_z: float = -1500.0
@export var road_max_z: float = 1500.0
@export var active_count: int = 12

var pool: Array[TrafficVehicleAI] = []
var _player: Node3D

func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	var materials: Array[StandardMaterial3D] = []
	for c: Color in ARCHETYPE_COLOURS:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = c
		materials.append(m)
	for i: int in MAX_POOL:
		var v: TrafficVehicleAI = vehicle_scene.instantiate() as TrafficVehicleAI
		v.name = "Traffic_%02d" % i
		v.position = Vector3(0.0, -200.0, float(i) * 15.0) # parked far below the map
		add_child(v)
		var kind: TrafficVehicleAI.Archetype = ARCHETYPE_MIX[i % ARCHETYPE_MIX.size()] as TrafficVehicleAI.Archetype
		v.setup(self, kind, materials[kind])
		pool.append(v)
	SignalBus.horn_blasted.connect(_on_horn_blasted)
	call_deferred("_initial_spawn")

func _initial_spawn() -> void:
	for i: int in mini(active_count, MAX_POOL):
		_respawn(pool[i])

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	for v: TrafficVehicleAI in pool:
		if not v.active:
			continue
		v.tick(delta)
		var d: float = v.global_position.distance_to(_player.global_position)
		if d > RECYCLE_RADIUS_M or v.global_position.z < road_min_z:
			_respawn(v)

func sub_lane_count() -> int:
	return lane_count * 3

func sub_lane_x(index: int) -> float:
	return (float(index) - float(sub_lane_count() - 1) * 0.5) * SUB_LANE_WIDTH_M

func sub_lane_of_x(x: float) -> int:
	return clampi(roundi(x / SUB_LANE_WIDTH_M + float(sub_lane_count() - 1) * 0.5), 0, sub_lane_count() - 1)

func active_vehicles() -> Array[TrafficVehicleAI]:
	var out: Array[TrafficVehicleAI] = []
	for v: TrafficVehicleAI in pool:
		if v.active:
			out.append(v)
	return out

## Distance from `me`'s front bumper to the nearest obstacle ahead whose width overlaps
## the corridor of sub-lane `lane` (other AI and the player auto).
func gap_ahead(me: TrafficVehicleAI, lane: int) -> float:
	var x: float = sub_lane_x(lane)
	var my_front: float = me.global_position.z - me.half_length()
	var best: float = INF
	for o: TrafficVehicleAI in pool:
		if o == me or not o.active:
			continue
		if absf(o.global_position.x - x) > me.half_width() + o.half_width():
			continue
		var gap: float = my_front - (o.global_position.z + o.half_length())
		if gap > -0.5 and gap < best:
			best = gap
	if _player != null and absf(_player.global_position.x - x) < me.half_width() + 0.75:
		var pgap: float = my_front - (_player.global_position.z + 1.4)
		if pgap > -0.5 and pgap < best:
			best = pgap
	return best

func is_sub_lane_free(me: TrafficVehicleAI, lane: int) -> bool:
	var x: float = sub_lane_x(lane)
	var z: float = me.global_position.z
	for o: TrafficVehicleAI in pool:
		if o == me or not o.active:
			continue
		if absf(o.global_position.x - x) > me.half_width() + o.half_width() + 0.2:
			continue
		if absf(o.global_position.z - z) < me.half_length() + o.half_length() + 2.0:
			return false
	return true

func _respawn(v: TrafficVehicleAI) -> void:
	var heading: float = -1.0
	if _player != null:
		var fwd_z: float = -_player.global_transform.basis.z.z
		heading = -1.0 if fwd_z <= 0.0 else 1.0
	var base_z: float = _player.global_position.z if _player != null else 0.0
	for attempt: int in 8:
		var lane: int = randi() % sub_lane_count()
		var z: float = clampf(base_z + heading * randf_range(SPAWN_MIN_AHEAD_M, SPAWN_MAX_AHEAD_M), road_min_z + 20.0, road_max_z - 20.0)
		var pos: Vector3 = Vector3(sub_lane_x(lane), 0.0, z)
		if _spawn_spot_free(v, pos):
			v.activate(pos, lane)
			return
	v.deactivate()

func _spawn_spot_free(v: TrafficVehicleAI, pos: Vector3) -> bool:
	for o: TrafficVehicleAI in pool:
		if o == v or not o.active:
			continue
		if absf(o.global_position.x - pos.x) < v.half_width() + o.half_width() + 0.3 \
				and absf(o.global_position.z - pos.z) < v.half_length() + o.half_length() + 4.0:
			return false
	return true

func _on_horn_blasted(origin: Vector3, forward_dir: Vector3, radius_m: float, horn_tier: int) -> void:
	for v: TrafficVehicleAI in pool:
		if not v.active or not v.reacts_to_horn(horn_tier):
			continue
		var to_v: Vector3 = v.global_position - origin
		to_v.y = 0.0
		if to_v.length() > radius_m:
			continue
		if to_v.normalized().dot(forward_dir) < 0.25: # forward cone only
			continue
		var away: int = 1 if v.global_position.x >= origin.x else -1
		v.hear_horn(away)
