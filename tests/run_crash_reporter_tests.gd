extends Node
## Crash reporting (Sentry) wiring. Passes with OR without the addon installed.
## Run: godot --headless --path . --fixed-fps 60 res://tests/run_crash_reporter_tests.tscn

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Crash reporter tests ===")
	_test_config()
	await _test_breadcrumbs()
	_test_throttles()
	_test_safe_without_dsn()
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_config() -> void:
	var dsn: String = str(ProjectSettings.get_setting("sentry/options/dsn", "MISSING"))
	_check("Committed project.godot has an EMPTY Sentry DSN (CI injects the secret)", dsn == "", dsn)
	_check("No personal data sent by default", ProjectSettings.get_setting("sentry/options/send_default_pii", true) == false)
	_check("Smoke-test flag is off in git", ProjectSettings.get_setting(CrashReporter.SMOKE_TEST_SETTING, true) == false)
	var presets: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	_check("Android presets ask for INTERNET (Sentry uploads)", presets.count("permissions/internet=true") >= 2 and not presets.contains("permissions/internet=false"))
	_check("Every Android preset uses the Gradle build (Sentry Android plugin)", not presets.contains("gradle_build/use_gradle_build=false"))
	_check("CrashReporter autoload is loaded", get_node_or_null("/root/CrashReporter") != null)
	print("    addon installed: %s, active: %s" % [CrashReporter.is_installed(), CrashReporter.is_active()])

func _test_breadcrumbs() -> void:
	CrashReporter.recent_breadcrumbs.clear()
	SignalBus.engine_stalled_in_water.emit(Vector3(10.0, 0.0, -20.0))
	SignalBus.engine_restarted.emit()
	SignalBus.haggle_resolved.emit({"accepted": true, "offer": 1, "fare": 120})
	SignalBus.ride_completed.emit({"total": 150, "archetype": "it_commuter"})
	SignalBus.weather_changed.emit(true)
	SignalBus.rewarded_ad_failed.emit("double_fare", "no_fill")
	await get_tree().process_frame
	var crumbs: String = "\n".join(CrashReporter.recent_breadcrumbs)
	_check("Stall + restart leave breadcrumbs", crumbs.contains("vehicle: Engine stalled in water") and crumbs.contains("vehicle: Engine restarted"), crumbs)
	_check("Savari haggle + ride leave breadcrumbs", crumbs.contains("savari: Haggle resolved") and crumbs.contains("savari: Ride completed"))
	_check("Weather + ad failure leave breadcrumbs", crumbs.contains("weather: Rain on") and crumbs.contains("ads: Rewarded ad failed"))
	for i: int in 80:
		CrashReporter.breadcrumb("spam %d" % i, "test")
	_check("Local breadcrumb log is capped", CrashReporter.recent_breadcrumbs.size() <= 50, str(CrashReporter.recent_breadcrumbs.size()))

func _test_throttles() -> void:
	CrashReporter.recent_breadcrumbs.clear()
	for i: int in 10:
		SignalBus.player_impact.emit({"speed_mps": 9.0, "kind": "traffic"})
	SignalBus.player_impact.emit({"speed_mps": 1.0, "kind": "kerb"})
	var impacts: int = 0
	for c: String in CrashReporter.recent_breadcrumbs:
		impacts += 1 if c.begins_with("vehicle: Impact") else 0
	_check("Impacts are throttled (one per cooldown, small bumps ignored)", impacts == 1, str(impacts))
	CrashReporter.recent_breadcrumbs.clear()
	for i: int in 5:
		SignalBus.traffic_density_changed.emit(0.5, "mylapore", false)
	SignalBus.traffic_density_changed.emit(0.5, "marina", false)
	_check("Zone breadcrumb only on change", CrashReporter.recent_breadcrumbs.size() == 2, str(CrashReporter.recent_breadcrumbs))

func _test_safe_without_dsn() -> void:
	# In tests there is never a DSN, so nothing may be sent even if the addon is installed.
	_check("Inactive in test runs (no DSN)", not CrashReporter.is_active())
	_check("capture_message is a no-op when inactive", CrashReporter.capture_message("test") == "")
	CrashReporter.set_tag("k", "v")
	CrashReporter.set_context("c", {"a": 1})
	_check("Tag/context calls are safe when inactive", true)

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  " + test_name)
	else:
		_failed += 1
		print("  FAIL  %s  (%s)" % [test_name, detail])
