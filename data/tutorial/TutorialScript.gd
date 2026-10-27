class_name TutorialScript
extends Resource
## An ordered list of TutorialStep resources plus the world rules while it runs.

@export var id: String = "first_ride"
## Mentor shown on the subtitle card.
@export var mentor_name_key: String = "TUT_MENTOR"
@export var steps: Array[TutorialStep] = []
## Paid once (idempotent reward id) when the rider is dropped off.
@export var completion_bonus_inr: int = 100
@export var completion_bonus_id: String = "first_savari"
## World rules while the tutorial runs.
@export var max_traffic: int = 4
@export var min_condition: float = 80.0
