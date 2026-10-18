class_name PassengerArchetype
extends Resource
## Passenger behaviour for the haggling and comfort systems (used from Phase 3).

@export var archetype_name: String = "IT Corridor Commuter"
@export var luggage_kg: float = 0.0
@export_range(0.0, 1.0) var haggle_patience: float = 0.5
@export_range(0.0, 1.0) var accept_meter_chance: float = 1.0
@export_range(0.0, 1.0) var accept_meter_mela_chance: float = 0.75
@export_range(0.0, 1.0) var accept_fixed_rate_chance: float = 0.3
@export var comfort_tolerance_g: float = 0.45
@export var max_tip_inr: int = 25
@export var likes_fast_driving: bool = false
