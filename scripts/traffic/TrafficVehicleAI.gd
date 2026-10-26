class_name TrafficVehicleAI
extends AnimatableBody3D
## One pooled AI vehicle following the RoadGraph on the left-hand carriageway.
## Keeps a gap to whatever is ahead, seeks open sub-lanes (two-wheelers aggressively),
## turns at junctions and dodges horns. Spawned once, recycled — never freed while driving.

enum Archetype { TWO_WHEELER, HATCHBACK, SHARE_AUTO, MTC_BUS, STRAY_COW }

const SIZES: Array[Vector3] = [Vector3(0.8, 1.3, 2.0), Vector3(1.7, 1.5, 3.8), Vector3(1.4, 1.8, 3.0), Vector3(2.5, 3.0, 11.0), Vector3(0.7, 1.4, 2.0)]
const SPEED_RANGES_KMH: Array[Vector2] = [Vector2(32.0, 46.0), Vector2(28.0, 42.0), Vector2(22.0, 32.0), Vector2(20.0, 30.0), Vector2(0.0, 3.0)]
## Lowest horn tier this archetype reacts to (0 bulb, 1 twin electric, 2 musical air-horn).
const MIN_HORN_TIER: Array[int] = [1, 1, 2, 2, 2]
const GAP_SEEK_COOLDOWN_S: Array[float] = [0.6, 2.5, 3.5, 99.0, 99.0]
const LATERAL_SPEED_MPS: float = 2.6
const HORN_REACTION_DELAY_S: float = 0.35
const TURN_SLOWDOWN_M: float = 12.0
## Optimised models per archetype (assets/models/traffic). "" keeps the box (the MTC bus has no fitting model yet).
const MODEL_FILES: Array[String] = [
	"res://assets/models/traffic/two_wheeler.glb",
	"res://assets/models/traffic/hatchback.glb",
	"res://assets/models/traffic/share_auto.glb",
	"",
	"res://assets/models/traffic/stray_cow.glb",
]
## Stray cows pick one of these at random when the pool is built.
const COW_FILES: Array[String] = [
	"res://assets/models/traffic/stray_cow.glb",
	"res://assets/models/traffic/stray_cow_fadly.glb",
]
## Traffic drives along -Z (Basis.looking_at). Most glTF files face +Z, so they need a half turn;
## the scooter already faces -Z. Checked with side renders: forgetting this drives them tail-first.
const MODEL_FLIP: Array[bool] = [false, true, true, false, true]
## Per-file flip for the cow variants (same order as COW_FILES).
const COW_FLIP: Array[bool] = [true, true]
## Two-wheelers: the scooter model is fitted to this height (the collision box stays 1.3 m tall
## so it covers the rider too) and a seated rider sits on the seat.
const SCOOTER_MODEL_HEIGHT_M: float = 1.0
const RIDER_SEAT_POS: Vector3 = Vector3(0.0, 0.72, 0.22)
static var _rider_variant: int = 0

var manager: ChennaiTrafficManager
var archetype: Archetype = Archetype.HATCHBACK
var cruise_speed_mps: float = 10.0
var current_speed_mps: float = 10.0
var active: bool = false

# Road-graph state.
var edge: int = 0
var dir: int = 1
## Distance travelled along the edge in the direction of travel (0 … edge length).
var t: float = 0.0
var sub_lane: int = 0
var lateral: float = 0.0 # current left offset (m) — eases toward the sub-lane target

var _enable_collision_next_tick: bool = false
var courtesy_timer: float = 0.0
## After the player hits us: stop dead, honk, then pull away (instead of a kinematic body
## bulldozing the auto). Seconds left.
var bumped_timer: float = 0.0
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
	var cow: int = randi() % COW_FILES.size()
	var model_path: String = COW_FILES[cow] if kind == Archetype.STRAY_COW else MODEL_FILES[kind]
	var flip: bool = COW_FLIP[cow] if kind == Archetype.STRAY_COW else MODEL_FLIP[kind]
	var fit_size: Vector3 = Vector3(size.x, SCOOTER_MODEL_HEIGHT_M, size.z) if kind == Archetype.TWO_WHEELER else size
	if TrafficModelFit.attach(self, model_path, fit_size, flip):
		_mesh.visible = false
	if kind == Archetype.TWO_WHEELER:
		_add_rider()
	deactivate()

## Nobody rides a scooter by remote control in Chennai: one helmeted rider per two-wheeler.
func _add_rider() -> void:
	var rider: MeshInstance3D = MeshInstance3D.new()
	rider.name = "Rider"
	rider.mesh = PersonMesh.seated_rider(_rider_variant)
	_rider_variant += 1
	rider.position = RIDER_SEAT_POS
	add_child(rider)

func place(edge_idx: int, travelled: float, direction: int, lane: int) -> void:
	edge = edge_idx
	dir = direction
	t = travelled
	sub_lane = clampi(lane, 0, maxi(manager.graph.sub_lane_count(edge, dir) - 1, 0))
	lateral = manager.graph.sub_lane_offset(edge, dir, sub_lane)
	var r: Vector2 = SPEED_RANGES_KMH[archetype]
	cruise_speed_mps = randf_range(r.x, r.y) / 3.6
	current_speed_mps = cruise_speed_mps
	_horn_timer = -1.0
	_gap_seek_timer = randf() * 2.0
	active = true
	visible = true
	_apply_transform()
	reset_physics_interpolation() # a recycled vehicle must not smear across the map
	# Teleport with collision off; re-enable next tick so Jolt never sweeps a
	# kinematic body through the world (that launched the player auto).
	_enable_collision_next_tick = true

func deactivate() -> void:
	active = false
	visible = false
	_enable_collision_next_tick = false
	_shape.disabled = true
	global_position = Vector3(0.0, -200.0, float(get_index()) * 15.0)
	if is_inside_tree():
		reset_physics_interpolation()

func half_width() -> float:
	return SIZES[archetype].x * 0.5

func half_length() -> float:
	return SIZES[archetype].z * 0.5

func reacts_to_horn(horn_tier: int) -> bool:
	return horn_tier >= MIN_HORN_TIER[archetype]

## Queue a sideways dodge (+1 = to the right/centre, -1 = to the left/kerb).
## The player is indicating into this vehicle's path: ease off for a few seconds.
func give_way(seconds: float) -> void:
	courtesy_timer = maxf(courtesy_timer, seconds)

func bumped(impact_mps: float) -> void:
	bumped_timer = clampf(1.5 + impact_mps * 0.35, 1.5, 4.5)
	current_speed_mps = 0.0
	_horn_timer = -1.0

func hear_horn(away_dir: int) -> void:
	if _horn_timer >= 0.0:
		return
	_horn_dir = away_dir
	_horn_timer = HORN_REACTION_DELAY_S

func edge_param() -> float:
	return t if dir > 0 else manager.graph.edges[edge].length - t

func tick(delta: float) -> void:
	if not active:
		return
	if _enable_collision_next_tick:
		_enable_collision_next_tick = false
		_shape.disabled = false
	if bumped_timer > 0.0:
		bumped_timer -= delta
		current_speed_mps = 0.0
		return # stands still (kinematic body stays put, no shove)
	if _horn_timer >= 0.0:
		_horn_timer -= delta
		if _horn_timer < 0.0:
			_try_shift(_horn_dir, true)

	var lead_gap: float = manager.gap_ahead(self)
	var safe_gap: float = current_speed_mps * 1.1 + 3.0
	var target_speed: float = cruise_speed_mps * manager.speed_factor # rush hour crawl
	var remaining: float = manager.graph.edges[edge].length - t
	if remaining < TURN_SLOWDOWN_M:
		target_speed *= 0.7 # ease off into junctions
	if courtesy_timer > 0.0:
		courtesy_timer -= delta
		target_speed *= 0.5 # letting the indicating auto merge or turn
	if lead_gap < safe_gap:
		target_speed = minf(target_speed, cruise_speed_mps * clampf((lead_gap - 2.0) / safe_gap, 0.0, 1.0))
		_gap_seek_timer -= delta
		if _gap_seek_timer <= 0.0:
			_gap_seek_timer = GAP_SEEK_COOLDOWN_S[archetype]
			if not _try_shift(1, false):
				_try_shift(-1, false)
	current_speed_mps = move_toward(current_speed_mps, target_speed, 6.0 * delta)

	t += current_speed_mps * delta
	var length: float = manager.graph.edges[edge].length
	if t >= length:
		var nxt: Dictionary = manager.graph.next_edge(edge, dir, manager.rng)
		if nxt.is_empty():
			manager.request_respawn(self)
			return
		t -= length
		edge = int(nxt["edge"])
		dir = int(nxt["dir"])
		sub_lane = clampi(sub_lane, 0, maxi(manager.graph.sub_lane_count(edge, dir) - 1, 0))
	var target_lat: float = manager.graph.sub_lane_offset(edge, dir, sub_lane)
	lateral = move_toward(lateral, target_lat, LATERAL_SPEED_MPS * 2.0 * delta)
	_apply_transform()

func _apply_transform() -> void:
	var pd: Array[Vector3] = manager.graph.sample(edge, edge_param(), dir)
	var fwd: Vector3 = pd[1]
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	var left: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pd[0] + left * lateral)

func _try_shift(step: int, from_horn: bool) -> bool:
	if step == 0:
		return false
	if (archetype == Archetype.MTC_BUS or archetype == Archetype.STRAY_COW) and not from_horn:
		return false
	var target: int = sub_lane + step
	if target < 0 or target >= manager.graph.sub_lane_count(edge, dir):
		return false
	if not manager.is_sub_lane_free(self, target):
		return false
	sub_lane = target
	SignalBus.traffic_vehicle_shifted.emit(sub_lane)
	return true
