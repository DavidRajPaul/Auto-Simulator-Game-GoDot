class_name CustomNavigation
extends Node
## User-selected navigation (a dropped pin, a side quest's "Go there"), independent of the Savari
## fare loop. Keeps the road graph as the only source of routable streets.
##
## GPS ownership: a side-quest mission > a Savari ride > this. While a rider is on board the
## passenger's route stays on the GPS; a pin set during the ride is kept as a queued destination
## and becomes the route the moment the rider gets out (Nov 9 device test: a pin set mid-ride
## replaced the passenger's route, then Savari's reroute fought it back).

var _graph: RoadGraph
var _start: Vector3 = Vector3.ZERO
var _destination: Vector3 = Vector3.ZERO
const OFF_ROUTE_M: float = 24.0
const REROUTE_INTERVAL_S: float = 2.0
const ARRIVAL_M: float = 12.0
var _last_position: Vector3 = Vector3.ZERO
var _gps: GpsRoute
var _progress_index: int = 0
var _reroute_cooldown: float = 0.0
var _has_start: bool = false
var _has_destination: bool = false
var _active: bool = false
var _mission_suspended: bool = false
var _ride_suspended: bool = false

## True while a destination is waiting for the rider or the side quest to finish.
func is_queued() -> bool:
	return _active and (_mission_suspended or _ride_suspended)

func _ready() -> void:
	SignalBus.mission_ownership_changed.connect(_on_mission_ownership)
	SignalBus.road_graph_ready.connect(_on_graph)
	SignalBus.custom_navigation_requested.connect(_on_request)
	SignalBus.custom_navigation_cleared.connect(_clear)
	SignalBus.player_pose_updated.connect(_on_player_pose)
	SignalBus.passenger_boarded.connect(func(_count: int, _kg: float) -> void: _ride_suspended = true)
	# Savari clears its own route right after this signal, so the queued route goes up a frame later.
	SignalBus.passenger_alighted.connect(func() -> void:
		_ride_suspended = false
		_resume_queued.call_deferred())
	if SignalBus.current_road_graph != null:
		_on_graph(SignalBus.current_road_graph)

func _on_graph(graph: RoadGraph) -> void:
	_graph = graph

func _process(delta: float) -> void:
	_reroute_cooldown = maxf(0.0, _reroute_cooldown - delta)

func _on_player_pose(position: Vector3, _heading: Vector3) -> void:
	_last_position = position
	if _mission_suspended or _ride_suspended or not _active or _gps == null or _gps.path.is_empty():
		return
	if position.distance_to(_destination) <= ARRIVAL_M:
		_clear()
		SignalBus.hint_requested.emit("You've arrived!", 3.0)
		return
	var hit: Array = _gps.progress_from(position, maxi(0, _progress_index - 25), 180)
	if float(hit[2]) <= OFF_ROUTE_M:
		_progress_index = int(hit[0])
		return
	# Check the whole route before declaring a deviation (hairpins may revisit a road).
	var nearest: Array = _gps.progress_from(position, 0, _gps.path.size())
	if float(nearest[2]) <= OFF_ROUTE_M:
		_progress_index = int(nearest[0])
		return
	if _reroute_cooldown <= 0.0:
		_reroute_cooldown = REROUTE_INTERVAL_S
		_build_route(position, _destination, true)

func _on_request(start: Vector3, destination: Vector3) -> void:
	if GameState.mission_active or _mission_suspended:
		SignalBus.hint_requested.emit(tr("NAV_BLOCKED_MISSION"), 3.0)
		return
	if _ride_suspended:
		# The rider's route keeps the GPS; remember the pin and show it on the map.
		_destination = destination
		_has_destination = true
		_active = true
		SignalBus.custom_navigation_state_changed.emit(true, _last_position, destination)
		SignalBus.hint_requested.emit(tr("NAV_QUEUED_RIDE"), 3.5)
		return
	# Starting position is always the player/auto; discard stale map origins.
	_build_route(_last_position, destination, false)

func _resume_queued() -> void:
	if _active and not _mission_suspended and not _ride_suspended:
		_build_route(_last_position, _destination, true)

func _build_route(start: Vector3, destination: Vector3, rerouting: bool) -> void:
	if _graph == null:
		SignalBus.hint_requested.emit("Map is still loading", 3.0)
		return
	var route: Dictionary = _graph.find_route(start, destination)
	if not bool(route.get("ok", false)):
		SignalBus.hint_requested.emit("No drivable route found", 3.0)
		return
	var gps: GpsRoute = GpsRoute.build(_graph, route)
	if gps.path.size() < 2:
		SignalBus.hint_requested.emit("Select two different road locations", 3.0)
		return
	_gps = gps
	_progress_index = 0
	_start = start
	_destination = destination
	_has_start = true
	_has_destination = true
	_active = true
	SignalBus.gps_route_changed.emit(gps)
	SignalBus.route_updated.emit(gps.path)
	SignalBus.custom_navigation_state_changed.emit(true, start, destination)
	if not rerouting:
		SignalBus.hint_requested.emit("Route ready", 2.0)

func _clear() -> void:
	if not _active:
		return
	var owns_gps: bool = not _mission_suspended and not _ride_suspended
	_active = false
	_has_start = false
	_has_destination = false
	_gps = null
	_progress_index = 0
	# A queued pin never put a route on the GPS, so clearing it must leave the rider's or the
	# mission's route alone — but the map still has to drop the pin.
	if owns_gps:
		SignalBus.gps_route_changed.emit(null)
		SignalBus.route_updated.emit(PackedVector3Array())
	SignalBus.custom_navigation_state_changed.emit(false, Vector3.ZERO, Vector3.ZERO)

func _on_mission_ownership(active: bool) -> void:
	_mission_suspended = active
	if not active and _active and not _ride_suspended:
		_build_route(_last_position, _destination, true)
