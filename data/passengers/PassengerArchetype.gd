class_name PassengerArchetype
extends Resource
## Passenger behaviour for haggling, comfort and tips. All balance numbers live in the
## per-archetype .tres files (data/passengers/*.tres), never in code.

@export var id: String = "it_commuter"
@export var archetype_name: String = "IT Corridor Commuter"
@export var colour: Color = Color(0.3, 0.5, 0.9)
@export var luggage_kg: float = 0.0
@export var party_size: int = 1

@export_group("Haggling (GDD risk–reward matrix)")
@export_range(0.0, 1.0) var accept_meter_chance: float = 1.0
@export_range(0.0, 1.0) var accept_meter_mela_chance: float = 0.75
@export_range(0.0, 1.0) var accept_fixed_rate_chance: float = 0.3
## Fare multiplier this rider pays (1.5–2.0 = "one-and-a-half / double meter").
@export var surge_multiplier: float = 1.0

@export_group("Comfort & tips")
## Lateral g above which the tea-cup starts spilling.
@export var comfort_tolerance_g: float = 0.45
@export var max_tip_inr: int = 25
## College students tip for near misses and speed instead of penalising them.
@export var likes_fast_driving: bool = false
@export var near_miss_tip_inr: int = 0
## Seconds of slack on top of the estimated drive time.
@export var timer_slack_s: float = 40.0

@export_group("Spawning")
## Zone ids from data/world/manifest.json where this rider hails most (empty = anywhere).
@export var home_zones: PackedStringArray = []
## Relative spawn weight.
@export var spawn_weight: float = 1.0

@export_group("Tanglish lines")
@export var line_hail: String = "Anna, auto varuma?"
@export var line_accept: String = "Sari, polaam!"
@export var line_reject: String = "Romba over-aa kekkuraanga!"
@export var line_happy: String = "Super driving anna!"
@export var line_upset: String = "Konjam medhuva po pa!"
