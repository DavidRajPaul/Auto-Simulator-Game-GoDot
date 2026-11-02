extends Node
## Crash & error reporting (Sentry). The ONLY place in the game that talks to the Sentry SDK.
##
## The Sentry Godot addon (addons/sentry, installed by tools/sentry/install_sentry_addon.sh) is a
## GDExtension. It initialises itself from the `sentry/options/*` project settings before any
## autoload runs, so native crashes, GDScript errors and Android ANRs are captured with no code here.
## This autoload only ADDS context to those reports:
##   • breadcrumbs from SignalBus gameplay events (what the player did in the last minute),
##   • tags (vehicle, zone, graphics preset, weather, camera) for filtering in Sentry,
##   • a "player" context (position, speed, shift clock) refreshed every few seconds.
##
## Rules (AGENTS.md → Crash reporting):
##   • Never reference Sentry classes by name anywhere: the addon is optional (tests, local
##     checkouts without it). Everything goes through `_sdk: Object` + call().
##   • Listen on SignalBus only; never reach into other scenes.
##   • No personal data: no names, no save contents, no device ids beyond Sentry's own.
##   • Throttle anything that fires often (impacts, zone changes) — breadcrumbs are capped at 100.

const SDK_SINGLETON: StringName = &"SentrySDK"
const CONTEXT_INTERVAL_S: float = 5.0
const IMPACT_MIN: float = 6.0 # m/s of impact worth a breadcrumb
const IMPACT_COOLDOWN_S: float = 2.0
## SentrySDK.Level values (debug, info, warning, error, fatal).
const LEVEL_DEBUG: int = 0
const LEVEL_INFO: int = 1
const LEVEL_WARNING: int = 2
const LEVEL_ERROR: int = 3
## Set to true for one build (CI input `sentry_smoke_test`) to prove events reach Sentry.
const SMOKE_TEST_SETTING: String = "namma_auto/crash_reporting/send_smoke_test_on_boot"

var _sdk: Object = null
var _enabled: bool = false
var _clock_s: float = 0.0
var _next_context_s: float = 0.0
var _last_impact_s: float = -100.0
var _speed_kmh: float = 0.0
var _player_pos: Vector3 = Vector3.ZERO
var _shift_day: int = 0
var _shift_minute: float = 0.0
var _zone: String = ""
var _scene_path: String = ""
## Recorded locally too, so tests (and builds without the addon) can see what would be sent.
var recent_breadcrumbs: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton(SDK_SINGLETON):
		_sdk = Engine.get_singleton(SDK_SINGLETON)
		_enabled = bool(_sdk.call("is_enabled"))
	if _enabled:
		_set_static_tags()
	_connect_signals()
	if _enabled and bool(ProjectSettings.get_setting(SMOKE_TEST_SETTING, false)):
		send_test_event.call_deferred()

## True when the addon is installed AND initialised with a DSN (i.e. events are really sent).
func is_active() -> bool:
	return _enabled

## True when the addon is installed (even without a DSN, e.g. in CI tests).
func is_installed() -> bool:
	return _sdk != null

# --- Public API (use these instead of the SDK) -------------------------------------------------

func breadcrumb(message: String, category: String, data: Dictionary = {}, level: int = LEVEL_INFO) -> void:
	recent_breadcrumbs.append("%s: %s" % [category, message])
	if recent_breadcrumbs.size() > 50:
		recent_breadcrumbs.remove_at(0)
	if not _enabled:
		return
	var crumb: Object = ClassDB.class_call_static(&"SentryBreadcrumb", &"create", message) as Object
	if crumb == null:
		return
	crumb.set("category", category)
	crumb.set("level", level)
	if not data.is_empty():
		crumb.call("set_data", data)
	_sdk.call("add_breadcrumb", crumb)

func set_tag(key: String, value: String) -> void:
	if _enabled:
		_sdk.call("set_tag", key, value)

func set_context(key: String, value: Dictionary) -> void:
	if _enabled:
		_sdk.call("set_context", key, value)

## Report a handled problem (bad save, missing resource, impossible state) without crashing.
func capture_message(message: String, level: int = LEVEL_WARNING) -> String:
	if not _enabled:
		return ""
	return String(_sdk.call("capture_message", message, level))

## Sends one clearly-labelled event to prove the pipeline works end to end.
func send_test_event() -> String:
	breadcrumb("Smoke test requested", "crash_reporting")
	return capture_message("Namma Auto Sentry smoke test (%s)" % _app_version(), LEVEL_INFO)

# --- Context -----------------------------------------------------------------------------------

func _set_static_tags() -> void:
	set_tag("app_version", _app_version())
	set_tag("renderer", str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")))
	set_tag("debug_build", str(OS.is_debug_build()))
	set_tag("vehicle", GameState.active_vehicle)
	set_tag("graphics_preset", str(GameState.settings.get("graphics", -1)))
	set_tag("language", str(GameState.settings.get("language", "en")))

func _app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "unknown"))

func _process(delta: float) -> void:
	_clock_s += delta
	var tree: SceneTree = get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	var path: String = scene.scene_file_path if scene != null else ""
	if path != _scene_path:
		_scene_path = path
		breadcrumb("Scene " + path.get_file(), "navigation", {"path": path})
		set_tag("scene", path.get_file().get_basename())
	if _clock_s >= _next_context_s:
		_next_context_s = _clock_s + CONTEXT_INTERVAL_S
		set_context("player", {
			"position": "%.0f, %.0f, %.0f" % [_player_pos.x, _player_pos.y, _player_pos.z],
			"speed_kmh": snappedf(_speed_kmh, 0.1),
			"shift_day": _shift_day,
			"shift_minute": snappedf(_shift_minute, 1.0),
			"zone": _zone,
			"session_s": snappedf(_clock_s, 1.0),
		})

func _connect_signals() -> void:
	SignalBus.speed_updated.connect(func(k: float) -> void: _speed_kmh = k)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _h: Vector3) -> void: _player_pos = p)
	SignalBus.shift_clock_updated.connect(func(d: int, m: float) -> void:
		_shift_day = d
		_shift_minute = m)
	SignalBus.traffic_density_changed.connect(_on_zone)
	SignalBus.vehicle_loadout_changed.connect(func(_s: VehicleStats) -> void:
		set_tag("vehicle", GameState.active_vehicle)
		breadcrumb("Vehicle " + GameState.active_vehicle, "garage"))
	SignalBus.settings_changed.connect(func(s: Dictionary) -> void:
		set_tag("graphics_preset", str(s.get("graphics", -1)))
		set_tag("language", str(s.get("language", "en"))))
	SignalBus.camera_mode_changed.connect(func(m: String) -> void: set_tag("camera", m))
	SignalBus.weather_changed.connect(func(r: bool) -> void:
		set_tag("raining", str(r))
		breadcrumb("Rain on" if r else "Rain off", "weather"))
	SignalBus.ui_modal_changed.connect(func(o: bool) -> void: breadcrumb("Modal open" if o else "Modal closed", "ui"))
	SignalBus.pause_requested.connect(func(o: bool) -> void: breadcrumb("Pause" if o else "Resume", "ui"))
	SignalBus.back_requested.connect(func() -> void: breadcrumb("Back button", "ui"))
	# Vehicle
	SignalBus.engine_stalled_in_water.connect(func(p: Vector3) -> void:
		breadcrumb("Engine stalled in water", "vehicle", {"at": "%.0f, %.0f" % [p.x, p.z]}, LEVEL_WARNING))
	SignalBus.engine_restarted.connect(func() -> void: breadcrumb("Engine restarted", "vehicle"))
	SignalBus.engine_switched_off.connect(func() -> void: breadcrumb("Engine switched off", "vehicle"))
	SignalBus.lpg_empty.connect(func() -> void: breadcrumb("LPG empty", "vehicle", {}, LEVEL_WARNING))
	SignalBus.gear_changed.connect(func(g: int) -> void: breadcrumb("Gear %d" % g, "vehicle", {}, LEVEL_DEBUG))
	SignalBus.player_impact.connect(_on_impact)
	SignalBus.tow_requested.connect(func(_p: Vector3) -> void: breadcrumb("Tow requested", "vehicle"))
	SignalBus.recover_requested.connect(func() -> void: breadcrumb("Recover requested", "vehicle"))
	SignalBus.teleport_requested.connect(func(x: Transform3D) -> void:
		breadcrumb("Teleport", "vehicle", {"to": "%.0f, %.0f" % [x.origin.x, x.origin.z]}))
	# Savari loop
	SignalBus.haggle_started.connect(func(info: Dictionary, _s: float) -> void:
		breadcrumb("Haggle started", "savari", {"archetype": str(info.get("archetype", ""))}))
	SignalBus.haggle_resolved.connect(func(r: Dictionary) -> void:
		breadcrumb("Haggle resolved", "savari", {"accepted": str(r.get("accepted", "")), "offer": str(r.get("offer", ""))}))
	SignalBus.passenger_boarded.connect(func(n: int, kg: float) -> void:
		breadcrumb("Passenger boarded", "savari", {"count": n, "luggage_kg": kg}))
	SignalBus.passenger_alighted.connect(func() -> void: breadcrumb("Passenger alighted", "savari"))
	SignalBus.ride_completed.connect(func(b: Dictionary) -> void:
		breadcrumb("Ride completed", "savari", {"total": str(b.get("total", "")), "archetype": str(b.get("archetype", ""))}))
	SignalBus.shift_ended.connect(func(_s: Dictionary) -> void: breadcrumb("Shift ended", "savari"))
	# Tutorial & ads
	SignalBus.tutorial_step_started.connect(func(info: Dictionary) -> void:
		breadcrumb("Tutorial step " + str(info.get("id", "")), "tutorial"))
	SignalBus.tutorial_finished.connect(func(skipped: bool) -> void:
		breadcrumb("Tutorial skipped" if skipped else "Tutorial finished", "tutorial"))
	SignalBus.rewarded_ad_failed.connect(func(p: String, why: String) -> void:
		breadcrumb("Rewarded ad failed", "ads", {"placement": p, "reason": why}, LEVEL_WARNING))
	SignalBus.interstitial_closed.connect(func(p: String) -> void: breadcrumb("Interstitial closed", "ads", {"placement": p}))

func _on_zone(_density: float, zone_id: String, _is_peak: bool) -> void:
	if zone_id == _zone:
		return
	_zone = zone_id
	set_tag("zone", zone_id)
	breadcrumb("Zone " + zone_id, "world")

func _on_impact(info: Dictionary) -> void:
	var speed: float = float(info.get("speed_mps", 0.0))
	if speed < IMPACT_MIN or _clock_s - _last_impact_s < IMPACT_COOLDOWN_S:
		return
	_last_impact_s = _clock_s
	breadcrumb("Impact %.1f m/s" % speed, "vehicle", {"with": str(info.get("kind", ""))})
