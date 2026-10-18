class_name WaterlogZone
extends Area3D
## Monsoon puddle. Tells the player auto (via SignalBus) how deep the water is.

@export var depth_m: float = 0.35

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_auto"):
		SignalBus.water_depth_changed.emit(depth_m)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_auto"):
		SignalBus.water_depth_changed.emit(0.0)
