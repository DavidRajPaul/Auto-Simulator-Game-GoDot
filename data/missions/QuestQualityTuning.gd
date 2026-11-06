class_name QuestQualityTuning
extends Resource
@export var g_deadzone: float = 0.45
@export var jolt_deadzone: float = 0.3
@export var loss_per_excess_g_second: float = 1.2
@export var collision_loss: float = 12.0
@export var horn_distress_loss: float = 12.0
@export var calm_restore: float = 25.0
## Seconds above a stage speed limit before the job stops; the HUD warns during this time.
@export var speed_grace_s: float = 4.0
