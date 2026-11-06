class_name MissionStage
extends Resource
## Immutable authoring data. Mutable progress belongs to MissionRunState.
@export var id: String = ""
@export_enum("goto", "dialogue", "wait", "photo", "yield", "inspect", "calm", "park", "cargo") var kind: String = "goto"
@export var objective_key: String = ""
@export var target: Vector3 = Vector3.ZERO
@export var radius_m: float = 6.0
@export var arrival_speed_kmh: float = 2.0
@export var duration_s: float = 0.0
@export var deadline_s: float = 0.0
@export var max_speed_kmh: float = 0.0
@export var max_condition_loss: float = 100.0
@export var choices: PackedStringArray = []
## Branches may only point forward in the stage list. Missing choices use the next stage.
@export var next_by_choice: Dictionary = {}
## Choice made in an earlier dialogue chooses this stage's destination without mutating data.
@export var target_choice_stage: String = ""
@export var target_options: Dictionary = {}
## For the photo stage: facing relative to this horizontal vector when the shutter is pressed.
@export var facing: Vector3 = Vector3.ZERO
@export var facing_tolerance_deg: float = 65.0
@export var hidden_route: bool = false
@export var quality_key: String = ""
@export var quality_floor: float = 0.0
@export var quality_scale: float = 1.0
## Cargo is transferred only by a stopped interaction; negative values unload.
@export var cargo_delta: int = 0
@export var cargo_capacity: int = 3
@export var cargo_delta_options: Dictionary = {}
@export var weather_loss_per_s: float = 0.0
## Mission-only signed diversion zone. It is a rule, not a persistent road closure.
@export var avoid_center: Vector3 = Vector3.ZERO
@export var avoid_radius_m: float = 0.0
@export var checkpoint: bool = true
## The named real place this stop stands for: shown on the world sign and in the quest panel.
@export var place_key: String = ""
## Building front the sign and the waiting person stand at, beside the road target.
@export var place_pos: Vector3 = Vector3.ZERO
## Same as place_key / place_pos when an earlier choice picks the destination.
@export var place_options: Dictionary = {}
@export var place_pos_options: Dictionary = {}
## Button text for stop-and-do stages ("Load the drum"). Falls back to a word per stage kind.
@export var action_key: String = ""
