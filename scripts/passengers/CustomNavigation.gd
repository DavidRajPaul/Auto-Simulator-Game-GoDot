class_name CustomNavigation
extends Node
## User-selected navigation, independent of the Savari fare loop.
## Keeps the road graph as the only source of routable streets.

var _graph: RoadGraph
var _start: Vector3 = Vector3.ZERO
var _destination: Vector3 = Vector3.ZERO
var _has_start: bool = false
var _has_destination: bool = false
var _active: bool = false

func _ready() -> void:
	SignalBus.road_graph_ready.connect(_on_graph)
	SignalBus.custom_navigation_requested.connect(_on_request)
	SignalBus.custom_navigation_cleared.connect(_clear)
	if SignalBus.current_road_graph != null:
		_on_graph(SignalBus.current_road_graph)

func _on_graph(graph: RoadGraph) -> void:
	_graph = graph

func _on_request(start: Vector3, destination: Vector3) -> void:
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
	_start = start
	_destination = destination
	_has_start = true
	_has_destination = true
	_active = true
	SignalBus.gps_route_changed.emit(gps)
	SignalBus.route_updated.emit(gps.path)
	SignalBus.custom_navigation_state_changed.emit(true, start, destination)
	SignalBus.hint_requested.emit("Custom route ready", 2.0)

func _clear() -> void:
	if not _active:
		return
	_active = false
	_has_start = false
	_has_destination = false
	SignalBus.gps_route_changed.emit(null)
	SignalBus.route_updated.emit(PackedVector3Array())
	SignalBus.custom_navigation_state_changed.emit(false, Vector3.ZERO, Vector3.ZERO)
