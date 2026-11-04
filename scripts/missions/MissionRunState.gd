class_name MissionRunState
extends RefCounted
var quest_id: String = ""
var content_version: int = 1
var stage_id: String = ""
var status: String = "active"
var elapsed: float = 0.0
var flags: Dictionary = {}
var checkpoint: Dictionary = {}
var scenario: Dictionary = {}
var condition_at_stage: float = 100.0

func to_dict() -> Dictionary:
	return {"quest_id": quest_id, "content_version": content_version, "stage_id": stage_id,
		"status": status, "elapsed": elapsed, "flags": flags.duplicate(true),
		"checkpoint": checkpoint.duplicate(true), "scenario": scenario.duplicate(true),
		"condition_at_stage": condition_at_stage}

static func read(data: Dictionary) -> MissionRunState:
	var state: MissionRunState = MissionRunState.new()
	state.quest_id = str(data.get("quest_id", ""))
	state.content_version = int(data.get("content_version", 0))
	state.stage_id = str(data.get("stage_id", ""))
	state.status = str(data.get("status", "active"))
	state.elapsed = float(data.get("elapsed", 0.0))
	state.condition_at_stage = float(data.get("condition_at_stage", 100.0))
	for key: String in ["flags", "checkpoint", "scenario"]:
		if data.get(key) is Dictionary:
			state.set(key, (data[key] as Dictionary).duplicate(true))
	return state
