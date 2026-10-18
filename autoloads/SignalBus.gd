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

# --- Navigation ------------------------------------------------------------
## Latest published road graph, for listeners that start after road_graph_ready fired.
var current_road_graph: RoadGraph = null
signal road_graph_ready(graph: RoadGraph)
## Player pose for the mini-map / ride logic (every physics frame).
signal player_pose_updated(position: Vector3, heading: Vector3)
## Active GPS route polyline (empty = no route).
signal route_updated(points: PackedVector3Array)
## Gap-la Gethu: passed a moving vehicle with < 0.6 m clearance above 35 km/h.
signal near_miss(clearance_m: float)
signal player_collision(impulse: float)
## Per-physics-frame ride dynamics for the comfort meter (g units; jolt = vertical speed change).
signal vehicle_dynamics(lateral_g: float, longitudinal_g: float, vertical_jolt: float)

# --- Passengers & economy (Phase 3) --------------------------------------
## Hails visible to the HUD / mini-map: Array of {id, position, archetype}.
signal hails_updated(hails: Array)
## Haggle card. info: {archetype, name, line, destination, distance_km, quotes: [int, int, int], odds: [f, f, f]}.
signal haggle_started(info: Dictionary, seconds: float)
signal haggle_choice_made(offer: int)
## result: {accepted, offer, fare, line}
signal haggle_resolved(result: Dictionary)
signal passenger_boarded(passenger_count: int, luggage_weight_kg: float)
## Ride HUD tick. info: {destination, remaining_m, time_left_s, comfort, fare, near_misses}
signal ride_updated(info: Dictionary)
signal passenger_alighted()
## breakdown from FareCalculator.settle() plus {destination, archetype_name, line}
signal ride_completed(breakdown: Dictionary)
signal wallet_balance_changed(new_balance_inr: int, delta_inr: int)
signal stand_respect_changed(new_xp: int, star_rating: float)
