class_name WaterlogZone
extends Area3D
## Reports the maximum depth across overlapping flood zones, not the last
## entered/exited zone. Shared per-player state is cleared when rain stops.

@export var depth_m: float = 0.35

static var _active_depths: Dictionary = {} # instance id -> depth

static func clear_active_flooding() -> void:
	_active_depths.clear()
	SignalBus.water_depth_changed.emit(0.0)

static func _publish_depth() -> void:
	var deepest: float = 0.0
	for value: Variant in _active_depths.values():
		deepest = maxf(deepest, float(value))
	SignalBus.water_depth_changed.emit(deepest)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _exit_tree() -> void:
	# Streaming/unloading a zone must not leave stale flood depth behind.
	_active_depths.erase(get_instance_id())
	_publish_depth()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_auto"):
		_active_depths[get_instance_id()] = depth_m
		_publish_depth()

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_auto"):
		_active_depths.erase(get_instance_id())
		_publish_depth()
