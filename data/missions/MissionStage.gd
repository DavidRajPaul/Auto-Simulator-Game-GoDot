class_name MissionStage
extends Resource
## Immutable authoring data. Mutable progress belongs to MissionRunState.
@export var id: String = ""
@export_enum("goto", "dialogue", "wait") var kind: String = "goto"
@export var objective_key: String = ""
@export var target: Vector3 = Vector3.ZERO
@export var radius_m: float = 6.0
@export var arrival_speed_kmh: float = 2.0
@export var duration_s: float = 0.0
@export var deadline_s: float = 0.0
@export var max_speed_kmh: float = 0.0
@export var max_condition_loss: float = 100.0
@export var choices: PackedStringArray = []
@export var checkpoint: bool = true
