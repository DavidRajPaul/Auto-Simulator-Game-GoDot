class_name VehicleStats
extends Resource
## Every tunable number for a playable auto. Balance in .tres, never in physics code.

@export var id: String = "singara_classic"
@export var display_name: String = "Singara Classic"
@export_enum("LPG", "Petrol", "EV") var fuel_type: int = 0
## Engine loop for this model (empty = the stock LPG putter; EVs synthesise a whine).
@export_file("*.ogg") var engine_loop: String = ""
@export var passenger_capacity: int = 3

@export_group("Mass")
@export var base_mass_kg: float = 365.0
@export var center_of_mass_offset: Vector3 = Vector3(0.0, -0.25, 0.35)
@export var passenger_mass_kg: float = 65.0

@export_group("Drivetrain")
@export var max_speed_kmh: float = 58.0
@export var reverse_max_speed_kmh: float = 16.0
@export var engine_peak_force_n: float = 4200.0
## Fraction of peak force lost at top speed (0 = flat torque, 0.7 = strong low-end bias).
@export var torque_falloff: float = 0.55
## Air drag force = coeff × v² (N, v in m/s).
@export var aero_drag_coeff: float = 0.9
@export var service_brake_force_n: float = 5400.0
@export var handbrake_force_n: float = 7500.0

@export_group("Steering")
@export var max_steer_angle_deg: float = 45.0
@export var steer_response_speed: float = 7.5

@export_group("Suspension")
@export var suspension_rest_dist_m: float = 0.34
@export var max_spring_compression_m: float = 0.22
@export var front_spring_stiffness: float = 26000.0
@export var rear_spring_stiffness: float = 34000.0
@export var spring_damping_coeff: float = 3600.0
@export var wheel_radius_m: float = 0.203
@export var front_lateral_grip: float = 5.8
@export var rear_lateral_grip: float = 6.4

@export_group("Stability")
@export var anti_roll_torque_strength: float = 8200.0
## Roll angle (deg) where the stabiliser starts working; lower = stiffer, less Gethu.
@export var anti_roll_start_deg: float = 6.0
@export var two_wheel_tilt_min_deg: float = 12.0
@export var max_safe_roll_angle_deg: float = 18.0

@export_group("Fuel & Environment")
@export var fuel_capacity: float = 8.0
## Units burnt per km (map is 1 : 1). Game-ified (~4x a real RE) so a tank lasts ~25–30 rides.
@export var fuel_burn_per_km: float = 0.1
@export var water_stall_depth_m: float = 0.28
@export var kick_start_pulls_needed: int = 3

@export_group("Garage & economy")
@export var price_inr: int = 0
## Fuel price per unit (₹/litre LPG, ₹/kWh EV).
@export var fuel_price_inr: float = 62.0
## Multiplies passenger comfort loss (heavy-duty shocks = 0.5).
@export var comfort_damping: float = 1.0
## Extra tip fraction from IT commuters for a green ride (EV +0.25).
@export var green_tip_bonus: float = 0.0
@export var body_colour: Color = Color(0.98, 0.76, 0.02)
@export var canopy_colour: Color = Color(0.07, 0.07, 0.07)
@export var chrome_bumper: bool = true
@export_multiline var blurb: String = ""

@export_group("Horn")
@export var horn_radius_m: float = 18.0
@export_range(0, 2) var horn_tier: int = 1
