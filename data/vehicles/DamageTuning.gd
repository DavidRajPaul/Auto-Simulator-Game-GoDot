class_name DamageTuning
extends Resource
## Gameplay calibration, not a crash-safety model. Normal closing speed removes glancing energy.
@export var minimum_speed_mps: float = 1.2
@export var damage_per_speed_squared: float = 0.28
@export var maximum_damage: float = 40.0
@export var component_multiplier: float = 1.6
@export var minimum_power: float = 0.45
@export var minimum_grip: float = 0.65
@export var minimum_damping: float = 0.65
## Steering pull towards the damaged side at 100 % steering wear. 0 = off (Nov 3 playtest: the
## auto drifting by itself read as a control bug, not as damage).
@export var steering_pull_deg: float = 0.0
@export var tyre_friction: float = 1.15
@export var damage_cooldown_s: float = 0.65

func points(speed_mps: float) -> float:
	if not is_finite(speed_mps) or speed_mps < minimum_speed_mps:
		return 0.0
	return clampf((speed_mps * speed_mps - minimum_speed_mps * minimum_speed_mps) * damage_per_speed_squared, 0.0, maximum_damage)
