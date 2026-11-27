extends Node
## Dev-only: knock a two-wheeler in the city and photograph the rider's rag doll as it falls.
## SHOT_DIR=/tmp/rag xvfb-run godot --path . --fixed-fps 60 res://tests/shot_ragdoll.tscn
func _ready() -> void:
	GameState.shift_minute = 630.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 30:
		await get_tree().physics_frame
	var at: Vector3 = Vector3(-3069.5, 1.0, 2056.5)
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, at))
	(city.get_node("World") as WorldChunkStreamer).update_streaming(true)
	for i: int in 120:
		await get_tree().physics_frame
	var traffic: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var bike: TrafficVehicleAI = traffic.place_scripted_vehicle("two_wheeler", 12.0)
	for i: int in 5:
		await get_tree().physics_frame
	var where: Vector3 = bike.global_position
	var cam: Camera3D = Camera3D.new()
	city.add_child(cam)
	cam.current = true
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var side: Vector3 = bike.global_basis.x
	cam.global_position = where + side * 5.5 + Vector3.UP * 2.2 - bike.global_basis.z * 2.0
	cam.look_at(where - bike.global_basis.z * 2.0 + Vector3.UP * 0.5)
	traffic._on_bumped(bike, 7.0)
	var dir: String = OS.get_environment("SHOT_DIR") if OS.has_environment("SHOT_DIR") else "/tmp/rag"
	DirAccess.make_dir_recursive_absolute(dir)
	var t: float = 0.0
	for shot: float in [0.1, 0.35, 0.7, 1.2, 2.5]:
		while t < shot:
			await get_tree().physics_frame
			t += 1.0 / 60.0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/rag_%03d.png" % [dir, int(shot * 100.0)])
	var slot: KnockedVehicles.Slot = traffic.knocked.slots[0]
	if slot.doll != null:
		var hips: PhysicalBone3D = slot.doll.sim.get_node("PB_Hips") as PhysicalBone3D
		print("hips y ", hips.global_position.y, " bike y ", slot.body.global_position.y)
	get_tree().quit()
