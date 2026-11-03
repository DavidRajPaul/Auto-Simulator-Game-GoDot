extends Node
## P0 regression: damage lifecycle, hybrid recoil, emergency pooling, compound collision.
var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func hit(speed: float, point: Vector3) -> void:
	SignalBus.player_collision.emit(speed)
	SignalBus.player_impact.emit({"speed_mps": speed, "local_point": point})

## Nov 3: visible damage (dents, mirrors, windshield, smoke -> fire, wreck + rewarded repair).
func _visible_damage(main: Node, model: AutoRickshawModel, auto: RigidBody3D) -> void:
	GameState.repair_free()
	auto.linear_velocity = Vector3.ZERO
	auto.angular_velocity = Vector3.ZERO
	await get_tree().physics_frame
	check("Player auto carries baked part ids (mirrors, windshield)", model._body_mi != null and model.glass_material != null)
	var arrays: Array = model._body_mi.mesh.surface_get_arrays(0)
	var ids: Dictionary = {}
	for v: Vector2 in (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array):
		ids[roundi(v.x)] = true
	check("Body mesh tags both mirrors and the headlamp", ids.has(1) and ids.has(2) and ids.has(5))
	check("Mirror debris is pre-built (no instantiate on break)", model._debris.size() == 2)
	# A hard hit on the nose: a dent where it hit, a cracked windshield.
	var nose: Vector3 = auto.global_transform * Vector3(0.15, 0.2, -1.3)
	SignalBus.player_collision.emit(7.0)
	SignalBus.player_impact.emit({"speed_mps": 7.0, "point": nose, "local_point": Vector3(0.15, 0.2, -1.3)})
	await get_tree().process_frame
	await get_tree().process_frame
	var dents: Array = GameState.marks()["dents"]
	check("Front hit leaves a dent on the body", dents.size() == 1 and float((dents[0] as Array)[3]) > 0.0)
	check("Dent reaches the body shader", int(model.paint_material.get_shader_parameter("dent_count")) == 1)
	check("Front hit cracks the windshield", float(model.glass_material.get_shader_parameter("crack")) > 0.0)
	# A hard side hit on the left snaps the left mirror; the right one stays.
	SignalBus.player_impact.emit({"speed_mps": 8.0, "point": auto.global_transform * Vector3(-0.7, 0.4, 0.0), "local_point": Vector3(-0.7, 0.4, 0.0)})
	await get_tree().process_frame
	await get_tree().process_frame
	check("Hard left hit breaks the left mirror only", bool(model.paint_material.get_shader_parameter("mirror_l_broken")) and not bool(model.paint_material.get_shader_parameter("mirror_r_broken")))
	check("Broken mirror falls off as debris", (model._debris[AutoRickshawModel.PART_MIRROR_L] as RigidBody3D).visible)
	# Smoke builds with the damage, then fire.
	var fx: DamageFX = auto.get_node("DamageFX") as DamageFX
	check("Smoke stages grow then catch fire", DamageFX.stage_for(0.2, false) == 0 and DamageFX.stage_for(0.4, false) == 1
		and DamageFX.stage_for(0.7, false) == 2 and DamageFX.stage_for(0.85, false) == 3 and DamageFX.stage_for(0.9, false) == 4 and DamageFX.stage_for(1.0, true) == 5)
	GameState.condition = 55.0
	SignalBus.condition_changed.emit(GameState.condition)
	check("Light damage: light smoke, no fire", fx.smoke.emitting and not fx.fire.emitting and fx.stage == 1)
	GameState.condition = 8.0
	SignalBus.condition_changed.emit(GameState.condition)
	check("Near wrecked: black smoke and fire", fx.smoke.emitting and fx.fire.emitting and fx.glow.visible)
	# Wrecked: engine dead, the wreck signal fires, the free repair is a rewarded placement.
	var wrecked_seen: Array[bool] = []
	var on_wreck: Callable = func(w: bool) -> void: wrecked_seen.append(w)
	SignalBus.vehicle_wrecked.connect(on_wreck)
	SignalBus.player_collision.emit(12.0)
	check("Crash to 0 % wrecks the auto", GameState.is_wrecked() and wrecked_seen.has(true))
	var start: Vector3 = auto.global_position
	Input.action_press("accelerate")
	for i: int in 90:
		await get_tree().physics_frame
	Input.action_release("accelerate")
	check("Wrecked auto has no engine power", auto.global_position.distance_to(start) < 1.0)
	check("Free wreck repair is an opt-in rewarded placement",
		AdMonetizationManager.config.rewarded_enabled_placements.has("ad_wreck_repair") and RewardsEngine.DAILY_CAPS.has("ad_wreck_repair"))
	SignalBus.rewarded_ad_completed.emit("ad_wreck_repair", {})
	await get_tree().process_frame
	await get_tree().process_frame
	check("Watched ad repairs everything", GameState.condition == 100.0 and not GameState.is_wrecked() and wrecked_seen.has(false)
		and (GameState.marks()["dents"] as Array).is_empty() and float(GameState.damage_state()["mirror_l"]) == 0.0)
	check("Repaired auto: mirrors back, glass clear, fire out", not bool(model.paint_material.get_shader_parameter("mirror_l_broken"))
		and float(model.glass_material.get_shader_parameter("crack")) == 0.0 and not fx.fire.emitting)
	# No money and no ad left: the patch-up gets the auto moving again.
	SignalBus.player_collision.emit(14.0)
	SignalBus.player_collision.emit(14.0)
	SignalBus.player_collision.emit(14.0)
	GameState.patch_up()
	check("Patch-up un-wrecks at low condition", not GameState.is_wrecked() and GameState.condition == GameState.PATCH_UP_CONDITION)
	# Dents survive a save and fade with a paid repair.
	GameState.add_dent(Vector3(30, 80, 118), 0.8)
	var saved: Dictionary = GameState.to_dict()
	GameState.from_dict(saved)
	check("Dents are saved", (GameState.marks()["dents"] as Array).size() == 1)
	GameState.wallet_inr = 100000
	GameState.repair()
	check("Full paid repair removes dents", (GameState.marks()["dents"] as Array).is_empty())
	SignalBus.vehicle_wrecked.disconnect(on_wreck)
	GameState.repair_free()

func _run() -> void:
	GameState.reset_profile()
	check("Parking contacts do not damage", GameState.DAMAGE.points(0.6) == 0.0)
	check("Hard impacts exceed glancing normal-speed impacts", GameState.DAMAGE.points(10.0) > GameState.DAMAGE.points(3.0) * 3.0)
	check("Invalid impact is ignored", GameState.DAMAGE.points(NAN) == 0.0)
	hit(6.0, Vector3(0, 0, -1.2))
	check("Front impact damages steering, not rear engine", float(GameState.damage_state()["steering"]) > 0.0 and float(GameState.damage_state()["engine"]) == 0.0)
	var first: float = GameState.condition
	hit(6.0, Vector3(0, 0, 1.2))
	check("Second collision accumulates damage", GameState.condition < first and float(GameState.damage_state()["engine"]) > 0.0)
	var saved: Dictionary = GameState.to_dict()
	var engine: float = float(GameState.damage_state()["engine"])
	GameState.reset_profile()
	GameState.from_dict(saved)
	check("Component damage survives save reload", is_equal_approx(float(GameState.damage_state()["engine"]), engine))
	GameState.wallet_inr = 15
	GameState.repair()
	check("Partial repair reduces but preserves remaining damage", float(GameState.damage_state()["engine"]) > 0.0 and float(GameState.damage_state()["engine"]) < engine)
	GameState.wallet_inr = 1000
	GameState.repair()
	check("Full garage repair restores components", is_zero_approx(float(GameState.damage_state()["engine"])) and is_equal_approx(GameState.condition, 100.0))
	GameState.from_dict({"condition": 75.0})
	check("Old saves migrate without faults", float(GameState.damage_state()["steering"]) == 0.0)
	GameState.reset_profile()
	GameState.tutorial_active = true
	GameState._on_component_impact({"speed_mps": 20.0})
	check("Tutorial protects mechanical components", float(GameState.damage_state()["steering"]) == 0.0)
	GameState.tutorial_active = false
	var main: Node = (load("res://scenes/main_phase1_greybox.tscn") as PackedScene).instantiate()
	add_child(main)
	for i: int in 40:
		await get_tree().physics_frame
	var manager: ChennaiTrafficManager = main.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	manager.set_physics_process(false)
	for v: TrafficVehicleAI in manager.pool:
		v.deactivate()
	var bike: TrafficVehicleAI = manager.pool[0]
	manager.place_vehicle(bike, 0, 200.0, 1, 0)
	bike.tick(1.0 / 60.0)
	bike.bumped(6.0, -bike.global_basis.z)
	var before: float = bike.t
	bike.tick(1.0 / 60.0)
	check("Hit NPC recoils within road graph", bike.t > before and bike.current_speed_mps == 0.0)
	check("Bus inertia exceeds bike inertia", TrafficVehicleAI.PHYSICS.recoil(3, 6, 365) < TrafficVehicleAI.PHYSICS.recoil(0, 6, 365))
	bike.deactivate()
	manager.place_vehicle(bike, 0, 220.0, 1, 0)
	check("Recycling clears collision response and defers collider", bike.bumped_timer == 0.0 and bike.recoil_mps == 0.0 and bike._shape.disabled)
	var ambulance: TrafficVehicleAI = manager.pool[5]
	manager.emergency_cooldown = 0.0
	manager.place_vehicle(ambulance, 0, 160.0, 1, 1)
	ambulance.tick(1.0 / 60.0)
	check("Due service slot becomes a lit ambulance", ambulance.service_variant == 4 and ambulance.emergency_active and ambulance._emergency_bar.visible)
	check("Dispatch starts a cooldown", not manager.claim_emergency())
	manager._yield_to_emergency()
	check("Vehicles ahead give way", bike.courtesy_timer > 0.0)
	ambulance.deactivate()
	check("Deactivation stops siren and beacon", not ambulance._siren.playing and not ambulance._emergency_bar.visible)
	check("Emergency uses existing pool", manager.pool.size() == 18)
	var model: AutoRickshawModel = main.get_node("AutoRickshaw/Model") as AutoRickshawModel
	hit(8.0, Vector3(0, 0, -1.2))
	model._process(0.0)
	check("Stock auto gains visible damage material", model.paint_material != null and (model.paint_material.get_shader_parameter("panel_damage") as Vector4).x > 0.0)
	# Nov 3 device test: the damage/repaint shader read the ORM metallic (1.0 everywhere) without the
	# file's metallicFactor 0, so a damaged auto turned to chrome and went black in shade.
	check("Damaged/painted auto stays non-metal like the stock material",
		model.paint_material != null and float(model.paint_material.get_shader_parameter("metallic_scale")) == 0.0)
	# Nov 3 device test: front-crash steering wear made the auto curve left with no steering input.
	var auto: RigidBody3D = main.get_node("AutoRickshaw") as RigidBody3D
	var wear: Dictionary = GameState.damage_state()
	wear["steering"] = 100.0
	wear["front"] = 100.0
	var start: Transform3D = auto.global_transform
	Input.action_press("accelerate")
	for i: int in 240:
		await get_tree().physics_frame
	Input.action_release("accelerate")
	var moved: Vector3 = auto.global_position - start.origin
	check("Worn steering still drives straight on throttle alone (%.2f m sideways in %.0f m)" % [moved.dot(start.basis.x), moved.dot(-start.basis.z)],
		absf(moved.dot(start.basis.x)) < 0.5 and moved.dot(-start.basis.z) > 20.0)
	await _visible_damage(main, model, auto)
	var stream: WorldChunkStreamer = WorldChunkStreamer.new()
	stream.chunk_size = 250.0
	var walls: Array = [[2.0, 2.0, 12.0, 2.0, 1.65, 0.22, "osm", 1]]
	var mask: PackedByteArray = stream._building_mask(Vector2i.ZERO, [], walls)
	check("Compound blocks pedestrian walk mask", mask[4 * 500 + 10] == 1)
	var holder: StaticBody3D = stream._buildings([], {}, walls) as StaticBody3D
	var shape: CollisionShape3D = holder.get_child(holder.get_child_count() - 1) as CollisionShape3D
	check("Compound has physical triangle collision", shape != null and (shape.shape as ConcavePolygonShape3D).get_faces().size() >= 36)
	holder.free()
	stream.free()
	main.queue_free()
	await get_tree().process_frame
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
