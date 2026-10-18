class_name TrafficVehicleAI
extends AnimatableBody3D
## One pooled AI vehicle. Drives toward -Z along its sub-lane, keeps a gap to whatever
## is ahead, seeks open gaps (two-wheelers aggressively) and dodges horns.
## Spawned once by ChennaiTrafficManager and recycled — never freed while driving.

enum Archetype { TWO_WHEELER, HATCHBACK, SHARE_AUTO, MTC_BUS }

const SIZES: Array[Vector3] = [Vector3(0.8, 1.3, 2.0), Vector3(1.7, 1.5, 3.8), Vector3(1.4, 1.8, 3.0), Vector3(2.5, 3.0, 11.0)]
const SPEED_RANGES_KMH: Array[Vector2] = [Vector2(36.0, 48.0), Vector2(30.0, 44.0), Vector2(24.0, 34.0), Vector2(22.0, 32.0)]
## Lowest horn tier this archetype reacts to (0 bulb, 1 twin electric, 2 musical air-horn).
const MIN_HORN_TIER: Array[int] = [1, 1, 2, 2]
const GAP_SEEK_COOLDOWN_S: Array[float] = [0.6, 2.5, 3.5, 99.0]
const LATERAL_SPEED_MPS: float = 2.6
const HORN_REACTION_DELAY_S: float = 0.35

var manager: ChennaiTrafficManager
var archetype: Archetype = Archetype.HATCHBACK
var cruise_speed_mps: float = 10.0
var current_speed_mps: float = 10.0
var sub_lane: int = 2
var active: bool = false
var _enable_collision_next_tick: bool = false
var _horn_timer: float = -1.0
var _horn_dir: int = 0
var _gap_seek_timer: float = 0.0
var _mesh: MeshInstance3D
var _shape: CollisionShape3D

func setup(owner_manager: ChennaiTrafficManager, kind: Archetype, material: Material) -> void:
	manager = owner_manager
	archetype = kind
	_mesh = $Body as MeshInstance3D
	_shape = $Collision as CollisionShape3D
	_shape.disabled = true
	var size: Vector3 = SIZES[kind]
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	_shape.shape = box
	_shape.position.y = size.y * 0.5
	_mesh.scale = size
	_mesh.position.y = size.y * 0.5
	_mesh.material_override = material
	deactivate()

func activate(at: Vector3, lane: int) -> void:
	sub_lane = lane
	global_position = at
	var r: Vector2 = SPEED_RANGES_KMH[archetype]
	cruise_speed_mps = randf_range(r.x, r.y) / 3.6
	current_speed_mps = cruise_speed_mps
	_horn_timer = -1.0
	_gap_seek_timer = randf() * 2.0
	active = true
	visible = true
	# Teleport with collision off; re-enable next tick so Jolt never sweeps a
	# kinematic body through the world (that launched the player auto).
	_enable_collision_next_tick = true

func deactivate() -> void:
	active = false
	visible = false
	_enable_collision_next_tick = false
	_shape.disabled = true
	global_position = Vector3(0.0, -200.0, float(get_index()) * 15.0)

func half_width() -> float:
	return SIZES[archetype].x * 0.5

func half_length() -> float:
	return SIZES[archetype].z * 0.5

func reacts_to_horn(horn_tier: int) -> bool:
	return horn_tier >= MIN_HORN_TIER[archetype]

## Queue a sideways dodge away from the horn after a human-like reaction delay.
func hear_horn(away_dir: int) -> void:
	if _horn_timer >= 0.0:
		return
	_horn_dir = away_dir
	_horn_timer = HORN_REACTION_DELAY_S

func tick(delta: float) -> void:
	if not active:
		return
	if _enable_collision_next_tick:
		_enable_collision_next_tick = false
		_shape.disabled = false
	# Horn reaction.
	if _horn_timer >= 0.0:
		_horn_timer -= delta
		if _horn_timer < 0.0:
			_try_shift(_horn_dir, true)

	# Gap keeping against vehicles (and the player) ahead in our corridor.
	var lead_gap: float = manager.gap_ahead(self, sub_lane)
	var safe_gap: float = current_speed_mps * 1.1 + 3.0
	var target_speed: float = cruise_speed_mps
	if lead_gap < safe_gap:
		target_speed = cruise_speed_mps * clampf((lead_gap - 2.0) / safe_gap, 0.0, 1.0)
		_gap_seek_timer -= delta
		if _gap_seek_timer <= 0.0:
			_gap_seek_timer = GAP_SEEK_COOLDOWN_S[archetype]
			if not _try_shift(-1, false):
				_try_shift(1, false)
	current_speed_mps = move_toward(current_speed_mps, target_speed, 6.0 * delta)

	var pos: Vector3 = global_position
	pos.z -= current_speed_mps * delta
	pos.x = move_toward(pos.x, manager.sub_lane_x(sub_lane), LATERAL_SPEED_MPS * delta)
	global_position = pos

func _try_shift(dir: int, from_horn: bool) -> bool:
	if dir == 0:
		return false
	var lanes: int = manager.sub_lane_count()
	var target: int = sub_lane + dir
	if archetype == Archetype.MTC_BUS and not from_horn:
		return false
	if target < 0 or target >= lanes:
		return false
	if not manager.is_sub_lane_free(self, target):
		return false
	sub_lane = target
	SignalBus.traffic_vehicle_shifted.emit(sub_lane)
	return true
