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
		if mission.scenario_flood != "" and not FileAccess.file_exists(mission.scenario_flood):
			errors.append("Missing flood file: " + mission.id)
		if mission.discoverable and (not mission.start_anchor.is_finite() or mission.start_anchor == Vector3.ZERO or mission.description_key.is_empty() or mission.job_key.is_empty() or mission.estimated_minutes < 1):
			errors.append("Invalid discovery anchor/metadata: " + mission.id)
		if mission.reward_choice_stage != "":
			var reward_source: int = mission.stage_index(mission.reward_choice_stage)
			if reward_source < 0 or mission.stages[reward_source] == null or mission.stages[reward_source].kind != "dialogue":
				errors.append("Invalid reward choice stage: " + mission.id)
			else:
				for reward_choice: String in mission.reward_choice_inr:
					if not mission.stages[reward_source].choices.has(reward_choice) or not mission.reward_choice_inr[reward_choice] is int or int(mission.reward_choice_inr[reward_choice]) < 0:
						errors.append("Invalid choice reward: " + mission.id)
				for xp_choice: String in mission.reward_choice_xp:
					if not mission.stages[reward_source].choices.has(xp_choice) or not mission.reward_choice_xp[xp_choice] is int or int(mission.reward_choice_xp[xp_choice]) < 0:
						errors.append("Invalid choice XP: " + mission.id)
		var ids: Dictionary = {}
		for stage: MissionStage in mission.stages:
			if stage == null:
				errors.append("Null stage: " + mission.id)
				continue
			if stage.id.is_empty() or ids.has(stage.id) or stage.kind not in ["goto", "dialogue", "wait", "photo", "yield", "inspect", "calm", "park", "cargo", "cutscene", "ask", "spot"] or stage.objective_key.is_empty():
				errors.append("Invalid stage: " + mission.id + "/" + stage.id)
			ids[stage.id] = true
			if not stage.target.is_finite() or not is_finite(stage.radius_m) or stage.radius_m <= 0 or stage.arrival_speed_kmh < 0 or not is_finite(stage.arrival_speed_kmh) or not is_finite(stage.duration_s) or stage.duration_s < 0 or not is_finite(stage.deadline_s) or stage.deadline_s < 0 or not is_finite(stage.max_speed_kmh) or stage.max_speed_kmh < 0 or not is_finite(stage.max_condition_loss) or stage.max_condition_loss < 0:
				errors.append("Invalid stage thresholds: " + stage.id)
			if stage.kind == "dialogue" and (stage.choices.is_empty() or stage.choices.has("")):
				errors.append("Dialogue needs choices: " + stage.id)
			if stage.kind == "cutscene" and (stage.cutscene_id.is_empty() or stage.duration_s <= 0.0 \
					or (mission.story != null and not mission.story.cutscenes.has(stage.cutscene_id))):
				errors.append("Cutscene needs a story scene and a fallback duration: " + stage.id)
			if stage.kind == "spot" and (stage.spot_pos == Vector3.ZERO or not stage.spot_pos.is_finite() \
					or not is_finite(stage.spot_range_m) or stage.spot_range_m <= 0.0 or not is_finite(stage.spot_max_kmh) \
					or stage.spot_max_kmh <= 0.0 or stage.shrink_after_s < 0.0 or stage.shrink_radius_m <= 0.0):
				errors.append("Spot needs a thing to find: " + stage.id)
			if stage.kind in ["cutscene", "ask", "spot"] and mission.story == null:
				errors.append("Story stage without a story: " + stage.id)
			if not stage.facing.is_finite() or stage.facing_tolerance_deg <= 0 or stage.facing_tolerance_deg > 180:
				errors.append("Invalid composition angle: " + stage.id)
			if not is_finite(stage.quality_floor) or stage.quality_floor < 0.0 or stage.quality_floor >= 100.0 or not is_finite(stage.quality_scale) or stage.quality_scale < 0.0:
				errors.append("Invalid quality rule: " + stage.id)
			if stage.cargo_capacity < 1 or stage.cargo_capacity > 8 or abs(stage.cargo_delta) > stage.cargo_capacity or (stage.kind == "cargo" and stage.cargo_delta == 0):
				errors.append("Invalid cargo rule: " + stage.id)
			if not is_finite(stage.weather_loss_per_s) or stage.weather_loss_per_s < 0.0:
				errors.append("Invalid weather rule: " + stage.id)
			for key: String in stage.cargo_delta_options:
				if not stage.target_options.has(key) or not stage.cargo_delta_options[key] is int or abs(int(stage.cargo_delta_options[key])) > stage.cargo_capacity:
					errors.append("Invalid choice cargo: " + stage.id)
			if not stage.avoid_center.is_finite() or not is_finite(stage.avoid_radius_m) or stage.avoid_radius_m < 0.0:
				errors.append("Invalid diversion rule: " + stage.id)
			for key: String in stage.target_options:
				if not stage.target_options[key] is Vector3 or not (stage.target_options[key] as Vector3).is_finite():
					errors.append("Invalid branch target: " + stage.id)
		for i: int in mission.stages.size():
			var stage: MissionStage = mission.stages[i]
			if stage == null:
				continue
			if stage.objective_choice_stage != "":
				var objective_source: int = mission.stage_index(stage.objective_choice_stage)
				if objective_source < 0 or objective_source >= i or mission.stages[objective_source] == null or mission.stages[objective_source].kind != "dialogue":
					errors.append("Invalid objective choice source: " + stage.id)
				else:
					for option: String in stage.objective_options:
						if not mission.stages[objective_source].choices.has(option) or str(stage.objective_options[option]).is_empty():
							errors.append("Invalid objective choice: " + stage.id)
			if stage.next_id != "" and mission.stage_index(stage.next_id) <= i:
				errors.append("Invalid forward jump: " + stage.id)
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
