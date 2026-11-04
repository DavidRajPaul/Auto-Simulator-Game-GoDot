class_name MissionDef
extends Resource
@export var id: String = ""
@export var content_version: int = 1
@export var title_key: String = ""
@export var unlock_level: int = 1
@export var prerequisites: PackedStringArray = []
@export var stages: Array[MissionStage] = []
@export var reward_inr: int = 0
@export var reward_xp: int = 0
@export var scenario_minute: float = -1.0
@export_enum("unchanged", "dry", "rain") var scenario_weather: String = "unchanged"

func stage_index(stage_id: String) -> int:
	for i: int in stages.size():
		if stages[i].id == stage_id:
			return i
	return -1
