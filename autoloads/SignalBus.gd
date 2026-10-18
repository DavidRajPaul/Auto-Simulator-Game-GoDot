extends Node
## Global Decoupled Event Bus for Namma Auto: Chennai Rickshaw Simulator 3D.

signal telemetry_updated(data: Dictionary)
signal gethu_stunt_bonus_earned(stunt_name: String, bonus_inr: int)
signal engine_stalled_in_water(world_pos: Vector3)
signal kick_start_attempt(progress_ratio: float)
signal engine_restarted()
signal wiper_toggled(is_on: bool)
signal touch_controls_updated(throttle: float, brake: float, steer: float, handbrake: bool)
signal horn_requested()
signal horn_blasted(origin: Vector3, forward_dir: Vector3, radius_m: float, horn_tier: int)
signal kick_start_pulled()
signal camera_Cycle_requested()
signal passenger_boarded(passenger_count: int, luggage_weight_kg: float)
signal passenger_alighted()
signal ride_completed(base_fare_inr: int, comfort_tip_inr: int, stunt_bonus_inr: int)
signal wallet_balance_changed(new_balance_inr: int, delta_inr: int)
signal stand_respect_changed(new_xp: int, star_rating: float)
