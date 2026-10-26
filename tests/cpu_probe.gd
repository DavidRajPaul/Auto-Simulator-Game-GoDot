extends Node
## CPU budget probe (headless): drives the city with an active ride for 20 s and reports
## script process/physics time per frame (avg, p95, max) plus spot timings of hot paths.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.reset_profile()
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 120:
		await get_tree().physics_frame
	var g: RoadGraph = SignalBus.current_road_graph
	var auto: Node3D = city.get_node("AutoRickshaw") as Node3D
	var t0: int = Time.get_ticks_usec()
	for i: int in 5:
		g.closest_point(auto.global_position + Vector3(i * 50, 0, 0))
	print("CPU closest_point avg: %.2f ms" % ((Time.get_ticks_usec() - t0) / 5000.0))
	t0 = Time.get_ticks_usec()
	var r: Dictionary = g.find_route(auto.global_position, auto.global_position + Vector3(1500, 0, 900))
	print("CPU find_route: %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	var gps: GpsRoute = GpsRoute.build(g, r)
	print("CPU GpsRoute.build: %.2f ms (%d pts)" % [(Time.get_ticks_usec() - t0) / 1000.0, gps.path.size()])
	var sm: SavariManager = city.get_node("SavariManager") as SavariManager
	var h: Dictionary = sm.spawn_hail_at(auto.global_position + (-auto.global_basis.z) * 3.0, sm.archetypes[0])
	t0 = Time.get_ticks_usec()
	sm.start_haggle(h)
	print("CPU start_haggle: %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	SignalBus.haggle_choice_made.emit(0)
	var proc: Array[float] = []
	var phys: Array[float] = []
	var frame: Array[float] = []
	Input.action_press("accelerate", 0.8)
	var last: int = Time.get_ticks_usec()
	for i: int in 1200:
		var s: float = sin(float(i) / 60.0) * 0.3
		Input.action_press("steer_left" if s > 0.0 else "steer_right", absf(s))
		Input.action_release("steer_right" if s > 0.0 else "steer_left")
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		frame.append((now - last) / 1000.0)
		last = now
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	Input.action_release("accelerate")
	print("CPU process ms: ", _stats(proc))
	print("CPU physics ms: ", _stats(phys))
	print("CPU wall frame ms: ", _stats(frame))
	get_tree().quit()

func _stats(a: Array[float]) -> String:
	var b: Array[float] = a.duplicate()
	b.sort()
	var avg: float = 0.0
	for v: float in b:
		avg += v
	avg /= b.size()
	return "avg %.2f  p95 %.2f  p99 %.2f  max %.2f" % [avg, b[int(b.size() * 0.95)], b[int(b.size() * 0.99)], b[b.size() - 1]]
