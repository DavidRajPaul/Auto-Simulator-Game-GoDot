class_name TrafficPhysics
extends Resource
@export var masses_kg: PackedFloat32Array = PackedFloat32Array([180, 1200, 650, 10000, 450, 3500, 2800])
@export var restitution: float = 0.12
@export var max_recoil_mps: float = 3.0
@export var recoil_deceleration: float = 4.0
@export var emergency_interval_s: float = 100.0
@export var emergency_range_m: float = 65.0
@export var emergency_speed_mps: float = 12.5
@export var yield_time_s: float = 2.0
@export var pedestrian_contact_m: float = 1.0
@export var pedestrian_recovery_s: float = 2.5
@export var pedestrian_max_push_mps: float = 2.0

func recoil(kind: int, closing: float, player_mass: float) -> float:
	return minf(max_recoil_mps, (1.0 + restitution) * maxf(closing, 0.0) * player_mass / (player_mass + masses_kg[kind]))
