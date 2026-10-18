extends Node
## Performance budget probe. Needs a real renderer (CI uses xvfb + Mesa):
##   xvfb-run godot --path . --rendering-method gl_compatibility --fixed-fps 60 res://tests/run_perf_probe.tscn
## Drives the greybox with live traffic for 12 s, samples budget monitors, writes a
## markdown report to $PERF_REPORT (or prints it) and exits 1 if a hard budget breaks.
## Frame/physics times are informational only — CI runs on software GL, not a phone.

const MAX_DRAW_CALLS: int = 150
const MAX_ACTIVE_TRAFFIC: int = 18
const SAMPLE_FRAMES: int = 720

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = (load("res://scenes/main_phase1_greybox.tscn") as PackedScene).instantiate()
	add_child(main)
	var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
	var traffic: ChennaiTrafficManager = main.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	for i: int in 60:
		await get_tree().process_frame

	var draws: Array[int] = []
	var prims_max: int = 0
	var objects_max: int = 0
	var phys_ms: Array[float] = []
	var traffic_max: int = 0
	var children_start: int = traffic.get_child_count()
	Input.action_press("accelerate", 0.8)
	for i: int in SAMPLE_FRAMES:
		# Weave a little so the camera sees both sides of the road.
		var s: float = sin(float(i) / 50.0) * 0.35
		Input.action_press("steer_left" if s > 0.0 else "steer_right", absf(s))
		Input.action_release("steer_right" if s > 0.0 else "steer_left")
		await get_tree().process_frame
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims_max = maxi(prims_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		objects_max = maxi(objects_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		traffic_max = maxi(traffic_max, traffic.active_vehicles().size())
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	Input.action_release("steer_right")

	draws.sort()
	var draw_max: int = draws[draws.size() - 1]
	var draw_p95: int = draws[int(draws.size() * 0.95)]
	var phys_avg: float = 0.0
	for v: float in phys_ms:
		phys_avg += v
	phys_avg /= float(phys_ms.size())
	var mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var renderer: String = RenderingServer.get_video_adapter_name()

	var failures: PackedStringArray = []
	if draw_max == 0:
		failures.append("draw calls read 0 — probe needs a real renderer (not --headless)")
	if draw_max > MAX_DRAW_CALLS:
		failures.append("draw calls %d > %d" % [draw_max, MAX_DRAW_CALLS])
	if traffic_max > MAX_ACTIVE_TRAFFIC:
		failures.append("active traffic %d > %d" % [traffic_max, MAX_ACTIVE_TRAFFIC])
	if traffic.get_child_count() != children_start:
		failures.append("traffic nodes instantiated/freed while driving")

	var report: String = """### Performance probe (Phase 1 greybox)
| Metric | Value | Budget |
|---|---|---|
| Draw calls (max / p95) | %d / %d | ≤ %d |
| Rendered objects (max) | %d | — |
| Primitives (max) | %d | — |
| Active traffic (max) | %d | ≤ %d |
| Physics process avg | %.2f ms | info only |
| Static memory | %.0f MB | < 400 MB |
| Distance driven | %.0f m | — |
| Renderer | %s | — |

**Result:** %s
""" % [draw_max, draw_p95, MAX_DRAW_CALLS, objects_max, prims_max, traffic_max, MAX_ACTIVE_TRAFFIC,
		phys_avg, mem_mb, auto.odometer_km * 1000.0, renderer,
		"✅ within budget" if failures.is_empty() else "❌ " + ", ".join(failures)]
	print(report)
	var out_path: String = OS.get_environment("PERF_REPORT")
	if out_path != "":
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(report)
	get_tree().quit(0 if failures.is_empty() else 1)
