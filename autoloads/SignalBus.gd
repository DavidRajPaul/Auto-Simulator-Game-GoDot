extends Node
## Global typed event bus. Subsystems never reach into each other's node trees;
## they emit and connect here instead (AGENTS.md Rule 1).

# --- Vehicle -------------------------------------------------------------
signal speed_updated(speed_kmh: float)
## Low-rate (10 Hz) dashboard snapshot. Keys: speed_kmh, lpg_liters, lpg_capacity,
## odometer_km, roll_deg, is_stalled, is_on_two_wheels.
signal telemetry_updated(data: Dictionary)
signal two_wheel_tilt_changed(is_on_two_wheels: bool)
signal gethu_stunt_bonus_earned(stunt_name: String, bonus_inr: int)
signal engine_stalled_in_water(world_pos: Vector3)
signal kick_start_attempt(progress_ratio: float)
signal engine_restarted()
signal lpg_empty()

# --- World ---------------------------------------------------------------
## Emitted by waterlogging zones when the player auto enters/leaves (depth 0 = dry).
signal water_depth_changed(depth_m: float)

# --- Horn / traffic ------------------------------------------------------
signal horn_blasted(origin: Vector3, forward_dir: Vector3, radius_m: float, horn_tier: int)
signal traffic_vehicle_shifted(sub_lane: int)

# --- UI / controls -------------------------------------------------------
signal wiper_toggled(is_on: bool)
signal camera_mode_changed(mode_name: String)

# --- Passengers & economy (Phase 3+) -------------------------------------
signal passenger_boarded(passenger_count: int, luggage_weight_kg: float)
signal passenger_alighted()
signal ride_completed(base_fare_inr: int, comfort_tip_inr: int, stunt_bonus_inr: int)
signal wallet_balance_changed(new_balance_inr: int, delta_inr: int)
signal stand_respect_changed(new_xp: int, star_rating: float)
