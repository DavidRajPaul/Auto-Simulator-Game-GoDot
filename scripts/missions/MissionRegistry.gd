class_name MissionRegistry
extends RefCounted
var definitions: Dictionary = {}
var errors: PackedStringArray = []

func load_pack(pack: MissionPack) -> bool:
	errors.clear()
	if pack == null or pack.id.is_empty() or pack.schema_version != 1:
		errors.append("Invalid pack or unsupported schema")
		return false
	var candidate: Dictionary = {}
	for mission: MissionDef in pack.missions:
		if mission == null:
			errors.append("Null mission")
			continue
		if mission.id.is_empty() or candidate.has(mission.id):
			errors.append("Empty or duplicate mission ID: " + mission.id)
		candidate[mission.id] = mission
		if mission.content_version < 1 or mission.unlock_level < 1 or mission.stages.is_empty() or mission.title_key.is_empty():
			errors.append("Invalid mission metadata: " + mission.id)
		if mission.reward_inr < 0 or mission.reward_xp < 0 or not is_finite(mission.scenario_minute) or mission.scenario_minute < -1.0 or mission.scenario_minute >= 1440.0 or mission.scenario_weather not in ["unchanged", "dry", "rain"]:
			errors.append("Invalid reward/scenario: " + mission.id)
		if mission.discoverable and (not mission.start_anchor.is_finite() or mission.start_anchor == Vector3.ZERO or mission.description_key.is_empty() or mission.estimated_minutes < 1):
			errors.append("Invalid discovery anchor/metadata: " + mission.id)
		var ids: Dictionary = {}
		for stage: MissionStage in mission.stages:
			if stage == null:
				errors.append("Null stage: " + mission.id)
				continue
			if stage.id.is_empty() or ids.has(stage.id) or stage.kind not in ["goto", "dialogue", "wait", "photo", "yield", "inspect", "calm", "park"] or stage.objective_key.is_empty():
				errors.append("Invalid stage: " + mission.id + "/" + stage.id)
			ids[stage.id] = true
			if not stage.target.is_finite() or not is_finite(stage.radius_m) or stage.radius_m <= 0 or stage.arrival_speed_kmh < 0 or not is_finite(stage.arrival_speed_kmh) or not is_finite(stage.duration_s) or stage.duration_s < 0 or not is_finite(stage.deadline_s) or stage.deadline_s < 0 or not is_finite(stage.max_speed_kmh) or stage.max_speed_kmh < 0 or not is_finite(stage.max_condition_loss) or stage.max_condition_loss < 0:
				errors.append("Invalid stage thresholds: " + stage.id)
			if stage.kind == "dialogue" and (stage.choices.is_empty() or stage.choices.has("")):
				errors.append("Dialogue needs choices: " + stage.id)
			if not stage.facing.is_finite() or stage.facing_tolerance_deg <= 0 or stage.facing_tolerance_deg > 180:
				errors.append("Invalid composition angle: " + stage.id)
			if not is_finite(stage.quality_floor) or stage.quality_floor < 0.0 or stage.quality_floor >= 100.0 or not is_finite(stage.quality_scale) or stage.quality_scale < 0.0:
				errors.append("Invalid quality rule: " + stage.id)
			for key: String in stage.target_options:
				if not stage.target_options[key] is Vector3 or not (stage.target_options[key] as Vector3).is_finite():
					errors.append("Invalid branch target: " + stage.id)
		for i: int in mission.stages.size():
			var stage: MissionStage = mission.stages[i]
			if stage == null:
				continue
			for key: String in stage.next_by_choice:
				if not stage.choices.has(key) or mission.stage_index(str(stage.next_by_choice[key])) <= i:
					errors.append("Invalid forward choice: " + stage.id)
			if not stage.target_options.is_empty():
				var source: int = mission.stage_index(stage.target_choice_stage)
				if source < 0 or source >= i or mission.stages[source] == null or mission.stages[source].kind != "dialogue":
					errors.append("Invalid target choice source: " + stage.id)
				else:
					for key: String in stage.target_options:
						if not mission.stages[source].choices.has(key):
							errors.append("Unknown target choice: " + stage.id)
	for id: String in candidate:
		_visit(id, candidate, {}, {})
	if not errors.is_empty():
		return false
	definitions = candidate
	return true

func _visit(id: String, all: Dictionary, visiting: Dictionary, done: Dictionary) -> void:
	if visiting.has(id):
		errors.append("Prerequisite cycle: " + id)
		return
	if done.has(id):
		return
	if not all.has(id):
		errors.append("Missing prerequisite: " + id)
		return
	visiting[id] = true
	for prerequisite: String in (all[id] as MissionDef).prerequisites:
		_visit(prerequisite, all, visiting, done)
	visiting.erase(id)
	done[id] = true

func get_mission(id: String) -> MissionDef:
	return definitions.get(id) as MissionDef

func available(id: String, level: int, completed: Dictionary) -> bool:
	var mission: MissionDef = get_mission(id)
	if mission == null or level < mission.unlock_level:
		return false
	for prerequisite: String in mission.prerequisites:
		if not completed.has(prerequisite):
			return false
	return true
