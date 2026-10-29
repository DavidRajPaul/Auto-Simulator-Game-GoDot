class_name TrafficVehicleAI
extends AnimatableBody3D
## One pooled AI vehicle following the RoadGraph on the left-hand carriageway.
## Keeps a gap to whatever is ahead, seeks open sub-lanes (two-wheelers aggressively),
## turns at junctions and dodges horns. Spawned once, recycled — never freed while driving.

enum Archetype { TWO_WHEELER, HATCHBACK, SHARE_AUTO, MTC_BUS, STRAY_COW, LORRY, SERVICE }

const SIZES: Array[Vector3] = [Vector3(0.8, 1.3, 2.0), Vector3(1.7, 1.5, 3.8), Vector3(1.4, 1.8, 3.0), Vector3(2.5, 3.2, 11.0), Vector3(0.7, 1.4, 2.0), Vector3(1.6, 2.0, 4.2), Vector3(2.2, 2.2, 5.9)]
const SPEED_RANGES_KMH: Array[Vector2] = [Vector2(32.0, 46.0), Vector2(28.0, 42.0), Vector2(22.0, 32.0), Vector2(20.0, 30.0), Vector2(0.0, 3.0), Vector2(22.0, 34.0), Vector2(24.0, 38.0)]
## Lowest horn tier this archetype reacts to (0 bulb, 1 twin electric, 2 musical air-horn).
const MIN_HORN_TIER: Array[int] = [1, 1, 2, 2, 2, 1, 2]
const GAP_SEEK_COOLDOWN_S: Array[float] = [0.6, 2.5, 3.5, 99.0, 99.0, 4.0, 3.5]
const LATERAL_SPEED_MPS: float = 2.6
const HORN_REACTION_DELAY_S: float = 0.35
const TURN_SLOWDOWN_M: float = 12.0
const FOLLOW_TIME_S: float = 1.5
const FOLLOW_MIN_GAP_M: float = 3.0
const COMFORT_BRAKE_MPS2: float = 4.0
const EMERGENCY_BRAKE_MPS2: float = 9.0
## Junctions are driven as a smooth curve from TURN_BLEND_M before the node to TURN_BLEND_M
## after it (was: a snap from one road's lane offset to the next, a sideways jump of several
## metres on a right-angle turn, plus an instant change of heading).
const TURN_BLEND_M: float = 7.0
## Optimised models per archetype (assets/models/traffic). "" keeps the box. Buses pick from BUS_FILES.
const MODEL_FILES: Array[String] = [
	"res://assets/models/traffic/two_wheeler.glb",
	"res://assets/models/traffic/hatchback.glb",
	"res://assets/models/traffic/share_auto.glb",
	"res://assets/models/traffic/bus_tnstc.glb",
	"res://assets/models/traffic/stray_cow.glb",
	"res://assets/models/traffic/lorry.glb",
	"", # SERVICE picks from SERVICE_VARIANTS
]
## Civil service vehicles (tools/assets/process_city.py, all baked front-to-+Z at real size):
## [file, footprint (w, h, l) m, spawn weight]. One pool slot carries all of them and shows a
## different one each time it respawns (ambulances and fire tenders rarer than the rest).
const SERVICE_VARIANTS: Array = [
	["res://assets/models/traffic/svc_garbage_truck.glb", Vector3(2.4, 2.66, 7.2), 3],
	["res://assets/models/traffic/svc_school_bus.glb", Vector3(2.6, 3.2, 9.5), 3],
	["res://assets/models/traffic/svc_police_car.glb", Vector3(1.78, 1.67, 4.6), 3],
	["res://assets/models/traffic/svc_tow_truck.glb", Vector3(2.19, 2.21, 6.4), 2],
	["res://assets/models/traffic/svc_ambulance.glb", Vector3(2.2, 2.2, 5.9), 2],
	["res://assets/models/traffic/svc_fire_truck.glb", Vector3(2.6, 3.02, 8.6), 1],
]
## Tamil Nadu buses: the green-and-yellow town bus and the white SETC coach.
const BUS_FILES: Array[String] = [
	"res://assets/models/traffic/bus_tnstc.glb",
	"res://assets/models/traffic/bus_setc.glb",
]
const BUS_FLIP: bool = true
## Stray cows pick one of these at random when the pool is built.
const COW_FILES: Array[String] = [
	"res://assets/models/traffic/stray_cow.glb",
	"res://assets/models/traffic/stray_cow_fadly.glb",
]
## Traffic drives along -Z (Basis.looking_at). Most glTF files face +Z, so they need a half turn;
## the scooter already faces -Z. Checked with side renders: forgetting this drives them tail-first.
const MODEL_FLIP: Array[bool] = [false, true, true, true, true, true, true]
## Per-file flip for the cow variants (same order as COW_FILES).
const COW_FLIP: Array[bool] = [true, true]
## Two-wheelers: the scooter model is fitted to this height (the collision box stays 1.3 m tall
## so it covers the rider too) and a seated rider sits on the seat.
const SCOOTER_MODEL_HEIGHT_M: float = 1.0
const RIDER_SEAT_POS: Vector3 = Vector3(0.0, 0.72, 0.22)
static var _rider_variant: int = 0
static var _bus_variant: int = 0

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
## Footprint of what is shown now (SERVICE swaps it per variant).
var body: Vector3 = Vector3.ONE
var service_variant: int = -1
var _service_models: Array[Node3D] = []

# Junction curve (cubic Hermite from the old lane to the new lane).
var turning: bool = false
var _turn_s: float = 0.0
var _turn_len: float = 1.0
var _turn_p0: Vector3
var _turn_p1: Vector3
var _turn_m0: Vector3
var _turn_m1: Vector3
var _turn_next: Dictionary = {}
var _turn_lut: PackedFloat32Array = PackedFloat32Array()
const TURN_LUT_N: int = 16
var _turn_t_after: float = 0.0
var _turn_lat_after: float = 0.0

func setup(owner_manager: ChennaiTrafficManager, kind: Archetype, material: Material) -> void:
	manager = owner_manager
	archetype = kind
	_mesh = $Body as MeshInstance3D
	_shape = $Collision as CollisionShape3D
	_shape.disabled = true
	var size: Vector3 = SIZES[kind]
	body = size
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
	if kind == Archetype.MTC_BUS:
		model_path = BUS_FILES[_bus_variant % BUS_FILES.size()]
		flip = BUS_FLIP
		_bus_variant += 1
	var fit_size: Vector3 = Vector3(size.x, SCOOTER_MODEL_HEIGHT_M, size.z) if kind == Archetype.TWO_WHEELER else size
	if TrafficModelFit.attach(self, model_path, fit_size, flip):
		_mesh.visible = false
	if kind == Archetype.TWO_WHEELER:
		_add_rider()
	if kind == Archetype.SERVICE:
		_mesh.visible = false
		for v: Array in SERVICE_VARIANTS:
			if TrafficModelFit.attach(self, str(v[0]), v[1] as Vector3, true):
				var holder: Node3D = get_node("Model") as Node3D
				holder.name = "Service_%s" % str(v[0]).get_file().get_basename()
				holder.visible = false
				_service_models.append(holder)
			else:
				_service_models.append(null)
	deactivate()

## SERVICE: show one variant (weighted pick) and size the collision box to it.
func pick_service_variant(rng: RandomNumberGenerator) -> void:
	if archetype != Archetype.SERVICE or _service_models.is_empty():
		return
	var total: int = 0
	for v: Array in SERVICE_VARIANTS:
		total += int(v[2])
	var roll: int = rng.randi() % total
	var pick: int = 0
	for i: int in SERVICE_VARIANTS.size():
		roll -= int(SERVICE_VARIANTS[i][2])
		if roll < 0:
			pick = i
			break
	service_variant = pick
	for i: int in _service_models.size():
		if _service_models[i] != null:
			_service_models[i].visible = i == pick
	body = SERVICE_VARIANTS[pick][1] as Vector3
	(_shape.shape as BoxShape3D).size = body
	_shape.position.y = body.y * 0.5

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
	turning = false
	pick_service_variant(manager.rng)
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
	turning = false
	visible = false
	_enable_collision_next_tick = false
	_shape.disabled = true
	global_position = Vector3(0.0, -200.0, float(get_index()) * 15.0)
	if is_inside_tree():
		reset_physics_interpolation()

func half_width() -> float:
	return body.x * 0.5

func half_length() -> float:
	return body.z * 0.5

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

	var lead: Dictionary = manager.lead_ahead(self)
	var lead_gap: float = float(lead["gap"])
	var lead_speed: float = float(lead["speed"])
	var signal_gap: float = manager.signal_stop_gap(self)
	if signal_gap < lead_gap:
		lead_gap = signal_gap
		lead_speed = 0.0
	var safe_gap: float = FOLLOW_MIN_GAP_M + current_speed_mps * FOLLOW_TIME_S
	var target_speed: float = cruise_speed_mps * manager.speed_factor
	var remaining: float = manager.graph.edges[edge].length - t
	if remaining < TURN_SLOWDOWN_M:
		target_speed *= 0.7
	if courtesy_timer > 0.0:
		courtesy_timer -= delta
		target_speed *= 0.5
	if lead_gap < INF:
		# Respect the lead's actual speed and the closing-distance braking budget.
		var closing: float = maxf(current_speed_mps - lead_speed, 0.0)
		var stopping_room: float = maxf(lead_gap - FOLLOW_MIN_GAP_M, 0.0)
		var allowed_closing: float = sqrt(2.0 * COMFORT_BRAKE_MPS2 * stopping_room)
		var following_cap: float = maxf(0.0, lead_speed + allowed_closing)
		if lead_gap < safe_gap:
			following_cap = minf(following_cap, lead_speed * clampf(lead_gap / safe_gap, 0.0, 1.0))
			target_speed = minf(target_speed, following_cap)
			_gap_seek_timer -= delta
			if _gap_seek_timer <= 0.0:
				_gap_seek_timer = GAP_SEEK_COOLDOWN_S[archetype]
				if not _try_shift(1, false):
					_try_shift(-1, false)
		elif closing > 0.0:
			target_speed = minf(target_speed, following_cap)
	var brake_rate: float = COMFORT_BRAKE_MPS2
	if lead_gap < FOLLOW_MIN_GAP_M + current_speed_mps * 0.45:
		brake_rate = EMERGENCY_BRAKE_MPS2
	var rate: float = brake_rate if target_speed < current_speed_mps else 2.5
	current_speed_mps = move_toward(current_speed_mps, target_speed, rate * delta)
	# Never advance through a lead bumper on this tick, even at low frame rates.
	if lead_gap < INF:
		current_speed_mps = minf(current_speed_mps, maxf(lead_gap - 0.15, 0.0) / maxf(delta, 0.001))

	var step: float = current_speed_mps * delta
	if turning:
		_turn_s += step
		t = minf(t + step, manager.graph.edges[edge].length) # followers on this road see us move on
		if _turn_s >= _turn_len:
			_finish_turn(_turn_s - _turn_len)
		else:
			_apply_turn_transform()
			return
	else:
		t += step
	var length: float = manager.graph.edges[edge].length
	if not turning and t >= length - _blend_before(length):
		if not _start_turn():
			manager.request_respawn(self)
			return
		_apply_turn_transform()
		return
	var target_lat: float = manager.graph.sub_lane_offset(edge, dir, sub_lane)
	lateral = move_toward(lateral, target_lat, LATERAL_SPEED_MPS * 2.0 * delta)
	_apply_transform()

func _blend_before(length: float) -> float:
	return minf(TURN_BLEND_M, length * 0.45)

## Pick the next road and build the curve from here (current lane) to TURN_BLEND_M into it.
func _start_turn() -> bool:
	var g: RoadGraph = manager.graph
	var nxt: Dictionary = g.next_edge(edge, dir, manager.rng)
	if nxt.is_empty():
		return false
	var ne: int = int(nxt["edge"])
	var nd: int = int(nxt["dir"])
	var nlen: float = g.edges[ne].length
	var after: float = minf(TURN_BLEND_M, nlen * 0.45)
	var lane_after: int = clampi(sub_lane, 0, maxi(g.sub_lane_count(ne, nd) - 1, 0))
	var lat_after: float = g.sub_lane_offset(ne, nd, lane_after)
	var here: Array[Vector3] = _pose_on(edge, dir, edge_param(), lateral)
	var e_param: float = after if nd > 0 else nlen - after
	var there: Array[Vector3] = _pose_on(ne, nd, e_param, lat_after)
	var chord: float = here[0].distance_to(there[0])
	if chord < 0.05:
		chord = 0.05
	# A U-turn at a dead end: swing out wide instead of reversing on the spot.
	var tangent_scale: float = chord * (1.6 if here[1].dot(there[1]) < -0.5 else 1.0)
	_turn_p0 = here[0]
	_turn_p1 = there[0]
	_turn_m0 = here[1] * tangent_scale
	_turn_m1 = there[1] * tangent_scale
	# Arc-length table so the vehicle keeps a constant speed along the curve.
	_turn_lut = PackedFloat32Array([0.0])
	var last: Vector3 = _turn_p0
	for k: int in range(1, TURN_LUT_N + 1):
		var q: Vector3 = _hermite(float(k) / float(TURN_LUT_N))
		_turn_lut.append(_turn_lut[k - 1] + q.distance_to(last))
		last = q
	_turn_len = maxf(_turn_lut[TURN_LUT_N], 0.05)
	_turn_s = 0.0
	_turn_next = {"edge": ne, "dir": nd, "lane": lane_after}
	_turn_t_after = after
	_turn_lat_after = lat_after
	turning = true
	return true

## Metres still to drive on the curve before reaching the next road at its TURN_BLEND_M mark.
func turn_remaining() -> float:
	return maxf(_turn_len - _turn_s, 0.0)

func turn_next_edge() -> Dictionary:
	return _turn_next if turning else {}

func _finish_turn(overshoot: float) -> void:
	turning = false
	edge = int(_turn_next["edge"])
	dir = int(_turn_next["dir"])
	sub_lane = int(_turn_next["lane"])
	t = _turn_t_after + overshoot
	lateral = _turn_lat_after
	_apply_transform()

func _apply_turn_transform() -> void:
	# Distance along the curve -> curve parameter u (linear inside each table step).
	var u: float = 1.0
	for k: int in range(1, _turn_lut.size()):
		if _turn_lut[k] >= _turn_s:
			var seg: float = maxf(_turn_lut[k] - _turn_lut[k - 1], 1e-5)
			u = (float(k - 1) + (_turn_s - _turn_lut[k - 1]) / seg) / float(TURN_LUT_N)
			break
	u = clampf(u, 0.0, 1.0)
	var u2: float = u * u
	var pos: Vector3 = _hermite(u)
	var vel: Vector3 = (6.0 * u2 - 6.0 * u) * _turn_p0 + (3.0 * u2 - 4.0 * u + 1.0) * _turn_m0 \
		+ (-6.0 * u2 + 6.0 * u) * _turn_p1 + (3.0 * u2 - 2.0 * u) * _turn_m1
	vel.y = 0.0
	if vel.length_squared() < 0.0001:
		vel = -global_transform.basis.z
	global_transform = Transform3D(Basis.looking_at(vel.normalized(), Vector3.UP), pos)

func _hermite(u: float) -> Vector3:
	var u2: float = u * u
	var u3: float = u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * _turn_p0 + (u3 - 2.0 * u2 + u) * _turn_m0 \
		+ (-2.0 * u3 + 3.0 * u2) * _turn_p1 + (u3 - u2) * _turn_m1

## [position, forward] on an edge at edge parameter `s`, offset `lat` m to the left.
func _pose_on(e: int, d: int, s: float, lat: float) -> Array[Vector3]:
	var g: RoadGraph = manager.graph
	var length: float = g.edges[e].length
	var pd: Array[Vector3] = g.sample(e, s, d)
	var fwd: Vector3 = g.sample(e, clampf(s + SMOOTH_M * float(d), 0.0, length), d)[0] - g.sample(e, clampf(s - SMOOTH_M * float(d), 0.0, length), d)[0]
	if fwd.length_squared() < 0.0001:
		fwd = pd[1]
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var left: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	return [pd[0] + left * lat, fwd]

## Heading is smoothed over ±SMOOTH_M along the road: at a bend in the road polyline the raw
## segment direction flips, which made the lane offset (and the body) step sideways.
const SMOOTH_M: float = 2.5

func _apply_transform() -> void:
	var g: RoadGraph = manager.graph
	var length: float = g.edges[edge].length
	var ep: float = edge_param()
	var pd: Array[Vector3] = g.sample(edge, ep, dir)
	var a: Vector3 = g.sample(edge, clampf(ep - SMOOTH_M * float(dir), 0.0, length), dir)[0]
	var b: Vector3 = g.sample(edge, clampf(ep + SMOOTH_M * float(dir), 0.0, length), dir)[0]
	var fwd: Vector3 = b - a
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = pd[1]
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var left: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pd[0] + left * lateral)

func _try_shift(step: int, from_horn: bool) -> bool:
	if step == 0 or turning:
		return false
	if (archetype == Archetype.MTC_BUS or archetype == Archetype.STRAY_COW or archetype == Archetype.SERVICE) and not from_horn:
		return false
	var target: int = sub_lane + step
	if target < 0 or target >= manager.graph.sub_lane_count(edge, dir):
		return false
	if not manager.is_sub_lane_free(self, target):
		return false
	sub_lane = target
	SignalBus.traffic_vehicle_shifted.emit(sub_lane)
	return true
