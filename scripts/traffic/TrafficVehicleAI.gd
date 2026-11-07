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
## Align traffic to the drawn road surface.
const ROAD_VISUAL_Y: float = 0.06
## Optimised models per archetype (assets/models/traffic). "" keeps the box. Buses pick from BUS_FILES.
const MODEL_FILES: Array[String] = [
	"", # TWO_WHEELER picks from TWO_WHEELER_VARIANTS
	"res://assets/models/traffic/cars/sedan_white.glb", # HATCHBACK picks from CAR_VARIANTS
	"res://assets/models/traffic/share_auto.glb",
	"", # MTC_BUS picks from BUS_VARIANTS on every respawn
	"res://assets/models/traffic/stray_cow.glb",
	"res://assets/models/traffic/lorry.glb",
	"", # SERVICE picks from SERVICE_VARIANTS
]
## Passenger cars: the three CC0 Quaternius bodies in Chennai street colours, baked to one mesh
## each by tools/assets/bake_car_colours.py (one draw call per car; was ~13). Nov 1 device test:
## the Kenney hatchback (green, flared grey arches) looked odd and is gone. White and silver
## come round most often, like on Chennai roads. Mahindra Boleros (the owner's model,
## tools/assets/bake_bolero.py) are real size and fitted uniformly: entries with a third `true`.
const CAR_VARIANTS: Array = [
 ["res://assets/models/traffic/cars/sedan_white.glb", Vector3(1.8, 1.5, 4.2)],
 ["res://assets/models/traffic/cars/bolero_white.glb", Vector3(1.75, 1.85, 4.3), true],
 ["res://assets/models/traffic/cars/suv_silver.glb", Vector3(1.95, 1.9, 4.6)],
 ["res://assets/models/traffic/cars/sports_red.glb", Vector3(1.9, 1.25, 4.3)],
 ["res://assets/models/traffic/cars/bolero_silver.glb", Vector3(1.75, 1.85, 4.3), true],
 ["res://assets/models/traffic/cars/sedan_silver.glb", Vector3(1.8, 1.5, 4.2)],
 ["res://assets/models/traffic/cars/suv_white.glb", Vector3(1.95, 1.9, 4.6)],
 ["res://assets/models/traffic/cars/bolero_black.glb", Vector3(1.75, 1.85, 4.3), true],
 ["res://assets/models/traffic/cars/sedan_maroon.glb", Vector3(1.8, 1.5, 4.2)],
 ["res://assets/models/traffic/cars/sports_grey.glb", Vector3(1.9, 1.25, 4.3)],
 ["res://assets/models/traffic/cars/bolero_maroon.glb", Vector3(1.75, 1.85, 4.3), true],
 ["res://assets/models/traffic/cars/sedan_blue.glb", Vector3(1.8, 1.5, 4.2)],
 ["res://assets/models/traffic/cars/suv_black.glb", Vector3(1.95, 1.9, 4.6)],
 ["res://assets/models/traffic/cars/bolero_green.glb", Vector3(1.75, 1.85, 4.3), true],
 ["res://assets/models/traffic/cars/sports_white.glb", Vector3(1.9, 1.25, 4.3)],
]
static var _car_variant: int = 0
## Civil service vehicles (tools/assets/process_city.py, all baked front-to-+Z at real size):
## [file, footprint (w, h, l) m, spawn weight]. One pool slot carries all of them and shows a
## different one each time it respawns (ambulances and fire tenders rarer than the rest).
const SERVICE_VARIANTS: Array = [
	["res://assets/models/traffic/svc_garbage_truck.glb", Vector3(2.4, 2.66, 7.2), 3],
	["res://assets/models/traffic/svc_school_bus.glb", Vector3(2.6, 3.2, 9.5), 3],
	# Police: a Mahindra Bolero jeep like Chennai patrol vehicles, always the same livery (white,
	# blue/red waist band) with a flashing red/blue light bar (bake_bolero.py, _light_beacon),
	# fitted uniformly at real size. The Tripo police SUV rendered shredded and was removed.
	["res://assets/models/traffic/cars/bolero_police.glb", Vector3(1.75, 2.0, 4.3), 3, true],
	["res://assets/models/traffic/svc_tow_truck.glb", Vector3(2.19, 2.21, 6.4), 2],
	["res://assets/models/traffic/svc_ambulance.glb", Vector3(2.2, 2.2, 5.9), 2],
	["res://assets/models/traffic/svc_fire_truck.glb", Vector3(2.6, 3.02, 8.6), 1],
]
## Two-wheelers: [file, fit box (w, h, l) m, flip, uniform, spawn weight, rider seat].
## The Activa-style scooter is the everyday Chennai two-wheeler; the sport bikes come from the
## SymetrikGames pack, split into single bikes by tools/assets/process_vehicle_packs.py (the raw
## pack is one merged showroom grid and must never be fitted to a traffic box as a whole).
## Each pool slot takes the next entry of the weighted cycle, so the mix stays stable.
const TWO_WHEELER_VARIANTS: Array = [
	["res://assets/models/traffic/two_wheeler.glb", Vector3(0.8, 1.0, 2.0), false, false, 5, Vector3(0.0, 0.72, 0.22)],
	["res://assets/models/traffic/two_wheeler_pack/sport_bike_0.glb", Vector3(0.8, 1.0, 2.0), true, true, 1, Vector3(0.0, 0.70, 0.28)],
	["res://assets/models/traffic/two_wheeler_pack/sport_bike_1.glb", Vector3(0.8, 1.0, 2.0), true, true, 1, Vector3(0.0, 0.70, 0.28)],
	["res://assets/models/traffic/two_wheeler_pack/sport_bike_2.glb", Vector3(0.8, 1.0, 2.0), true, true, 1, Vector3(0.0, 0.70, 0.28)],
	["res://assets/models/traffic/two_wheeler_pack/sport_bike_3.glb", Vector3(0.8, 1.0, 2.0), true, true, 1, Vector3(0.0, 0.70, 0.28)],
]
static var _two_wheeler_variant: int = 0
## Buses on Chennai roads (Nov 2026 research, docs/BUSES.md): the owner's Tripo electric bus
## baked into every MTC livery + a college bus (tools/assets/bake_ebus.py), plus the TNSTC town
## bus and SETC coach passing through. [file, real size (w, h, l) m, weight, kind].
## kind: "mtc" stops at MTC stops and shows a real route; "premium" / "small" use their own
## routes; "college" (yellow, TN rule) runs mostly at college rush hours; "state" passes by.
## Every bus slot carries all of them and shows one per respawn (like the service slot).
const BUS_VARIANTS: Array = [
	["res://assets/models/traffic/buses/mtc_ordinary.glb", Vector3(2.6, 2.95, 10.1), 5, "mtc"],
	["res://assets/models/traffic/buses/mtc_pink.glb", Vector3(2.6, 2.95, 10.1), 4, "mtc"],
	["res://assets/models/traffic/buses/mtc_electric.glb", Vector3(2.6, 2.95, 10.1), 3, "mtc"],
	["res://assets/models/traffic/buses/mtc_electric_ac.glb", Vector3(2.6, 2.95, 10.1), 2, "mtc"],
	["res://assets/models/traffic/buses/mtc_ordinary_ac.glb", Vector3(2.6, 2.95, 10.1), 1, "mtc"],
	["res://assets/models/traffic/buses/mtc_premium.glb", Vector3(2.6, 2.95, 10.1), 1, "premium"],
	["res://assets/models/traffic/buses/mtc_small.glb", Vector3(2.6, 2.95, 7.55), 2, "small"],
	["res://assets/models/traffic/buses/college.glb", Vector3(2.6, 2.95, 8.8), 2, "college"],
	["res://assets/models/traffic/bus_tnstc.glb", Vector3(2.5, 3.2, 11.0), 1, "state"],
	["res://assets/models/traffic/bus_setc.glb", Vector3(2.5, 3.2, 11.0), 1, "state"],
]
## Every bus file faces +Z (side renders), so all are turned to drive along -Z.
const BUS_FLIP: bool = true
## MTC Premium routes (launched 11 Mar 2026): P570S Siruseri IT Park - CMBT, P91 Thiruvanmiyur - KCBT.
const PREMIUM_ROUTES: Array = [["P570S", "CMBT"], ["P91", "KCBT"]]
## Buses pull in at stops (BusStops) and dwell: look-ahead and dwell time.
const BUS_STOP_LOOK_M: float = 70.0
const BUS_DWELL_S: Vector2 = Vector2(6.0, 11.0)
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
var bus_variant: int = -1
## Paint shown this respawn (alpha 0 = the model's own colours) and whether this NPC auto is an
## electric one (blue / teal body; EVs carry green number plates).
var paint: Color = Color(0, 0, 0, 0)
var electric: bool = false
var _paintable: bool = false
var bus_route: String = ""
var _bus_models: Array[Node3D] = []
var _route_board: Label3D = null
var _dwell: float = 0.0
var _served_edge: int = -1
var _served_s: float = -1000.0

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
const PHYSICS: TrafficPhysics = preload("res://data/vehicles/traffic_physics.tres")
var recoil_mps: float = 0.0
var emergency_active: bool = false
var _siren: AudioStreamPlayer3D
var _emergency_bar: MeshInstance3D
static var _siren_stream: AudioStreamWAV
var _horn_timer: float = -1.0
var _horn_dir: int = 0
var _gap_seek_timer: float = 0.0
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
## Footprint of what is shown now (SERVICE swaps it per variant).
var body: Vector3 = Vector3.ONE
var service_variant: int = -1
## Where the seated rider goes (per two-wheeler model; share autos use the scooter seat).
var rider_seat: Vector3 = RIDER_SEAT_POS
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
	collision_mask = 7 # road/buildings, player and traffic for swept recoil tests
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
	var fit_size: Vector3 = Vector3(size.x, SCOOTER_MODEL_HEIGHT_M, size.z) if kind == Archetype.TWO_WHEELER else size
	if kind == Archetype.HATCHBACK:
		var car: Array = CAR_VARIANTS[_car_variant % CAR_VARIANTS.size()]
		_car_variant += 1
		if ResourceLoader.exists(str(car[0])):
			model_path = str(car[0])
			fit_size = car[1] as Vector3
			body = fit_size
			box.size = body
			_shape.position.y = body.y * 0.5
			_mesh.scale = body
			_mesh.position.y = body.y * 0.5
	var uniform: bool = kind == Archetype.HATCHBACK and CAR_VARIANTS[(_car_variant - 1) % CAR_VARIANTS.size()].size() > 2
	if kind == Archetype.TWO_WHEELER:
		var tw: Array = two_wheeler_variant(_two_wheeler_variant)
		_two_wheeler_variant += 1
		model_path = str(tw[0])
		fit_size = tw[1] as Vector3
		flip = tw[2] as bool
		uniform = tw[3] as bool
		rider_seat = tw[5] as Vector3
	if TrafficModelFit.attach(self, model_path, fit_size, flip, uniform):
		_mesh.visible = false
		# Colour variety (Nov 1): two-wheelers and NPC autos repaint per respawn (PaintSwap).
		if kind in [Archetype.TWO_WHEELER, Archetype.SHARE_AUTO]:
			_paintable = PaintSwap.prepare(get_node("Model"), PaintSwap.key_of(model_path)) > 0
	# Autos should never look driverless.  Reuse the compact seated mesh used by
	# scooters; its low-poly silhouette reads clearly through the open auto side.
	if kind in [Archetype.TWO_WHEELER, Archetype.SHARE_AUTO]:
		_add_rider()
	if kind == Archetype.SERVICE:
		_mesh.visible = false
		for v: Array in SERVICE_VARIANTS:
			if TrafficModelFit.attach(self, str(v[0]), v[1] as Vector3, true, v.size() > 3 and bool(v[3])):
				var holder: Node3D = get_node("Model") as Node3D
				holder.name = "Service_%s" % str(v[0]).get_file().get_basename()
				_light_beacon(holder)
				holder.visible = false
				_service_models.append(holder)
			else:
				_service_models.append(null)
	if kind == Archetype.MTC_BUS:
		_mesh.visible = false
		for v: Array in BUS_VARIANTS:
			var state: bool = str(v[3]) == "state"
			if TrafficModelFit.attach(self, str(v[0]), v[1] as Vector3, BUS_FLIP, not state):
				var holder: Node3D = get_node("Model") as Node3D
				holder.name = "Bus_%s" % str(v[0]).get_file().get_basename()
				holder.visible = false
				_bus_models.append(holder)
			else:
				_bus_models.append(null)
		# Orange LED destination board over the windscreen: route number + destination.
		_route_board = Label3D.new()
		_route_board.name = "RouteBoard"
		_route_board.pixel_size = 0.0055
		_route_board.font_size = 48
		_route_board.outline_size = 0
		_route_board.modulate = Color(1.0, 0.62, 0.12)
		_route_board.shaded = false
		_route_board.double_sided = false
		_route_board.rotation.y = PI # traffic faces -Z
		_route_board.visibility_range_end = 60.0
		add_child(_route_board)
	if kind == Archetype.SERVICE:
		_setup_emergency()
	deactivate()

## Police light bar: a model surface whose material is named "Beacon" (bolero_police.glb) gets
## the flashing red/blue shader. Nov 1: "add some lights so it looks like a police car".
const BEACON_SHADER: Shader = preload("res://shaders/police_beacon.gdshader")
static var _beacon_material: ShaderMaterial = null

static func _light_beacon(root: Node) -> int:
	var lit: int = 0
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		for i: int in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			if m != null and m.resource_name == "Beacon":
				if _beacon_material == null:
					_beacon_material = ShaderMaterial.new()
					_beacon_material.shader = BEACON_SHADER
				mi.set_surface_override_material(i, _beacon_material)
				lit += 1
	return lit

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
	emergency_active = manager.claim_emergency()
	if emergency_active:
		pick = 4 # existing ambulance model; one service slot, no new moving bodies
		service_variant = pick
	_emergency_bar.visible = emergency_active
	if emergency_active:
		_siren.play()
	else:
		_siren.stop()
	for i: int in _service_models.size():
		if _service_models[i] != null:
			_service_models[i].visible = i == pick
	body = SERVICE_VARIANTS[pick][1] as Vector3
	(_shape.shape as BoxShape3D).size = body
	_shape.position.y = body.y * 0.5

## Mission-only override of an existing service slot after place() picks its normal variant.
func show_quest_ambulance() -> void:
	if archetype != Archetype.SERVICE or _service_models.size() <= 4:
		return
	service_variant = 4
	emergency_active = true
	_emergency_bar.visible = true
	_siren.play()
	for i: int in _service_models.size():
		if _service_models[i] != null:
			_service_models[i].visible = i == 4
	body = SERVICE_VARIANTS[4][1] as Vector3
	(_shape.shape as BoxShape3D).size = body
	_shape.position.y = body.y * 0.5
	cruise_speed_mps = PHYSICS.emergency_speed_mps

## Two-wheelers: a Chennai street colour (or the model's own); NPC autos: mostly the stock
## yellow, ~30 % electric (blue / teal), ~8 % women-driven pink autos.
func pick_paint(rng: RandomNumberGenerator) -> void:
	electric = false
	paint = PaintSwap.NO_PAINT
	if not _paintable:
		return
	if archetype == Archetype.TWO_WHEELER:
		paint = PaintSwap.TWO_WHEELER_PAINTS[rng.randi() % PaintSwap.TWO_WHEELER_PAINTS.size()]
	elif archetype == Archetype.SHARE_AUTO:
		var roll: float = rng.randf()
		if roll < 0.3:
			electric = true
			paint = PaintSwap.AUTO_ELECTRIC[rng.randi() % PaintSwap.AUTO_ELECTRIC.size()]
		elif roll < 0.38:
			paint = PaintSwap.AUTO_PINK
	PaintSwap.set_paint(get_node("Model"), paint)

## MTC_BUS: show one livery (weighted; college buses mostly at college rush hours), size the
## collision box to it and put a real route on the destination board: one that serves the MTC
## stop nearest to where the bus appears (Premium and small buses use their own routes).
func pick_bus_variant(rng: RandomNumberGenerator) -> void:
	if archetype != Archetype.MTC_BUS or _bus_models.is_empty():
		return
	var minute: float = GameState.shift_minute
	var rush: bool = (minute >= 420.0 and minute <= 570.0) or (minute >= 930.0 and minute <= 1080.0)
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total: float = 0.0
	for i: int in BUS_VARIANTS.size():
		var w: float = float(BUS_VARIANTS[i][2])
		if str(BUS_VARIANTS[i][3]) == "college":
			w *= 2.5 if rush else 0.25
		if _bus_models[i] == null:
			w = 0.0
		weights.append(w)
		total += w
	var roll: float = rng.randf() * total
	var pick: int = 0
	for i: int in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			pick = i
			break
	bus_variant = pick
	for i: int in _bus_models.size():
		if _bus_models[i] != null:
			_bus_models[i].visible = i == pick
	body = BUS_VARIANTS[pick][1] as Vector3
	(_shape.shape as BoxShape3D).size = body
	_shape.position.y = body.y * 0.5
	_dwell = 0.0
	_served_edge = -1
	bus_route = _pick_route(str(BUS_VARIANTS[pick][3]), rng)
	_route_board.visible = bus_route != ""
	_route_board.text = bus_route
	_route_board.position = Vector3(0.0, body.y - 0.32, -body.z * 0.5 - 0.04)

func _pick_route(kind: String, rng: RandomNumberGenerator) -> String:
	if kind == "college":
		return "COLLEGE"
	if kind == "state":
		return ""
	if kind == "premium":
		var p: Array = PREMIUM_ROUTES[rng.randi() % PREMIUM_ROUTES.size()]
		return "%s  %s" % [p[0], p[1]]
	var stops: BusStops = SignalBus.current_bus_stops as BusStops
	if stops == null or stops.stops.is_empty():
		return ""
	var i: int = stops.nearest(global_position)
	if i < 0:
		return ""
	var rs: Array = (stops.stops[i] as Dictionary)["routes"]
	var pool: Array = []
	for r: Variant in rs:
		var code: String = str(r)
		if " " in code or "(" in code:
			continue # depot / section variants ("18A CT SEC")
		if (kind == "small") == code.begins_with("S"):
			pool.append(code)
	if pool.is_empty():
		for r: Variant in rs:
			if not (" " in str(r)):
				pool.append(str(r))
	if pool.is_empty():
		return ""
	var route: String = str(pool[rng.randi() % pool.size()])
	var dest: String = str(stops.routes.get(route, ""))
	return ("%s  %s" % [route, dest.to_upper()]).strip_edges()

## Stops: the gap to the next MTC stop ahead (treated like a stopped lead vehicle), INF if none.
## While dwelling the bus stands at the kerb. MTC liveries only.
func _bus_stop_gap(delta: float) -> float:
	if archetype != Archetype.MTC_BUS or turning or bus_variant < 0:
		return INF
	var kind: String = str(BUS_VARIANTS[bus_variant][3])
	if kind != "mtc" and kind != "small" and kind != "premium":
		return INF
	var stops: BusStops = SignalBus.current_bus_stops as BusStops
	if stops == null:
		return INF
	var ep: float = edge_param()
	if _dwell > 0.0:
		_dwell -= delta
		return 0.0
	var skip: float = _served_s if _served_edge == edge else -1000.0
	var ahead: float = stops.distance_ahead(edge, dir, ep, BUS_STOP_LOOK_M, skip)
	if ahead == INF:
		return INF
	if ahead < 0.8 and current_speed_mps < 0.4:
		_dwell = randf_range(BUS_DWELL_S.x, BUS_DWELL_S.y)
		_served_edge = edge
		_served_s = stops.stop_param(edge, dir, ep, ahead)
		SignalBus.bus_stopped.emit(global_position, bus_route)
		return 0.0
	return ahead

## Kerb lane offset for a bus pulling in to a stop.
func _kerb_lateral() -> float:
	var half: float = manager.graph.edges[edge].width * 0.5
	return maxf(manager.graph.sub_lane_offset(edge, dir, 0), half - half_width() - 0.35)

## Nobody rides a scooter by remote control in Chennai: one helmeted rider per two-wheeler.
func _add_rider() -> void:
	var rider: Node3D = PersonMesh.rider_node(_rider_variant)
	_rider_variant += 1
	# rider_seat is the old procedural mesh origin; the rider node's origin is the hip.
	rider.position = rider_seat + PersonMesh.PROCEDURAL_HIP
	add_child(rider)

## The n-th entry of the weighted two-wheeler cycle (weights from TWO_WHEELER_VARIANTS).
static func two_wheeler_variant(n: int) -> Array:
	var total: int = 0
	for v: Array in TWO_WHEELER_VARIANTS:
		total += int(v[4])
	var slot: int = posmod(n, total)
	# Spread the rare entries through the cycle: scooter, bike, scooter, scooter, bike, ...
	var order: Array[int] = []
	var counts: Array[int] = []
	for v: Array in TWO_WHEELER_VARIANTS:
		counts.append(0)
	for k: int in total:
		var best: int = 0
		var best_deficit: float = -INF
		for i: int in TWO_WHEELER_VARIANTS.size():
			var want: float = float(TWO_WHEELER_VARIANTS[i][4]) * float(k + 1) / float(total)
			var deficit: float = want - float(counts[i])
			if deficit > best_deficit:
				best_deficit = deficit
				best = i
		counts[best] += 1
		order.append(best)
	return TWO_WHEELER_VARIANTS[order[slot]]

func place(edge_idx: int, travelled: float, direction: int, lane: int) -> void:
	_shape.disabled = true
	bumped_timer = 0.0
	recoil_mps = 0.0
	courtesy_timer = 0.0
	edge = edge_idx
	dir = direction
	t = travelled
	sub_lane = clampi(lane, 0, maxi(manager.graph.sub_lane_count(edge, dir) - 1, 0))
	lateral = manager.graph.sub_lane_offset(edge, dir, sub_lane)
	turning = false
	pick_service_variant(manager.rng)
	var r: Vector2 = SPEED_RANGES_KMH[archetype]
	cruise_speed_mps = randf_range(r.x, r.y) / 3.6
	if emergency_active:
		cruise_speed_mps = PHYSICS.emergency_speed_mps
	current_speed_mps = cruise_speed_mps
	_horn_timer = -1.0
	_gap_seek_timer = randf() * 2.0
	active = true
	visible = true
	_apply_transform()
	pick_bus_variant(manager.rng)
	pick_paint(manager.rng)
	reset_physics_interpolation() # a recycled vehicle must not smear across the map
	# Teleport with collision off; re-enable next tick so Jolt never sweeps a
	# kinematic body through the world (that launched the player auto).
	_enable_collision_next_tick = true

func deactivate() -> void:
	emergency_active = false
	recoil_mps = 0.0
	bumped_timer = 0.0
	if _siren != null:
		_siren.stop()
		_emergency_bar.visible = false
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

func bumped(impact_mps: float, push: Vector3 = Vector3.ZERO, player_mass: float = 365.0) -> void:
	bumped_timer = clampf(1.5 + impact_mps * 0.35, 1.5, 4.5)
	# Motion remains constrained to the road: the light bike yields farther than a bus.
	# Swept primitive collision below prevents the recoil crossing another vehicle/wall.
	recoil_mps = PHYSICS.recoil(archetype, impact_mps, player_mass) * push.dot(-global_basis.z)
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
		if emergency_active:
			manager.emergency_cooldown = PHYSICS.emergency_interval_s
	if bumped_timer > 0.0:
		bumped_timer -= delta
		current_speed_mps = 0.0
		if not turning and absf(recoil_mps) > 0.01:
			var motion: Vector3 = -global_basis.z * recoil_mps * delta
			if not test_move(global_transform, motion):
				t = clampf(t + recoil_mps * delta, 0.0, maxf(manager.graph.edges[edge].length - TURN_BLEND_M, 0.0))
				_apply_transform()
			else:
				recoil_mps = 0.0
			recoil_mps = move_toward(recoil_mps, 0.0, PHYSICS.recoil_deceleration * delta)
		return
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
	# MTC buses pull in at real stops: the stop is a "stopped lead" FOLLOW_MIN_GAP_M further on,
	# so the normal braking brings the bus to rest right at it.
	var stop_gap: float = _bus_stop_gap(delta)
	var at_stop: bool = stop_gap < INF
	if at_stop and stop_gap + FOLLOW_MIN_GAP_M < lead_gap:
		lead_gap = stop_gap + FOLLOW_MIN_GAP_M
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
	var target_lat: float = _kerb_lateral() if at_stop and stop_gap < 40.0 else manager.graph.sub_lane_offset(edge, dir, sub_lane)
	# Sideways drift scales with forward speed: a bike creeping up to a red light edges over,
	# it doesn't slide 5 m/s sideways on the spot.
	var lat_rate: float = LATERAL_SPEED_MPS * 2.0 * clampf(0.35 + current_speed_mps / 4.0, 0.35, 1.0)
	lateral = move_toward(lateral, target_lat, lat_rate * delta)
	_apply_transform()

func _setup_emergency() -> void:
	_siren = AudioStreamPlayer3D.new()
	_siren.max_distance = PHYSICS.emergency_range_m * 2.0
	_siren.unit_size = 15.0
	_siren.volume_db = -12.0
	if _siren_stream == null:
		var bytes: PackedByteArray = PackedByteArray()
		var count: int = 44100
		bytes.resize(count * 2)
		var phase: float = 0.0
		for i: int in count:
			var seconds: float = float(i) / 22050.0
			phase += TAU * (750.0 + 250.0 * sin(TAU * seconds * 0.5)) / 22050.0
			bytes.encode_s16(i * 2, int(sin(phase) * 16000.0))
		_siren_stream = AudioStreamWAV.new()
		_siren_stream.format = AudioStreamWAV.FORMAT_16_BITS
		_siren_stream.mix_rate = 22050
		_siren_stream.data = bytes
		_siren_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_siren_stream.loop_end = count
	_siren.stream = _siren_stream
	add_child(_siren)
	_emergency_bar = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.9, 0.14, 0.25)
	_emergency_bar.mesh = box
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = BEACON_SHADER
	mat.set_shader_parameter("ambulance_colours", true)
	_emergency_bar.material_override = mat
	_emergency_bar.position = Vector3(0.0, 2.28, -1.2)
	_emergency_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_emergency_bar)

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
	global_transform = Transform3D(Basis.looking_at(vel.normalized(), Vector3.UP), pos + Vector3.UP * ROAD_VISUAL_Y)

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
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pd[0] + left * lateral + Vector3.UP * ROAD_VISUAL_Y)

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
