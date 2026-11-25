extends Node
## Ads (Nov 25): the AdMob plugin is installed and wired, test and real ids can't drift apart,
## and AdMobProvider runs Google's order (consent -> initialize -> load) and never blocks play.
## The real plugin only exists on Android, so a stand-in node with the same signals and methods
## drives the provider here.
## Run: godot --headless --path . --fixed-fps 60 res://tests/run_ads_tests.tscn

const TEST_APP_ID: String = "ca-app-pub-3940256099942544~3347511713"

## Stand-in for addons/AdmobPlugin/Admob.gd: same signals, records calls.
class FakeAdmob extends Node:
	signal initialization_completed(status_data: Object)
	signal consent_info_updated
	signal consent_info_update_failed(error_data: Object)
	signal consent_form_loaded
	signal consent_form_failed_to_load(error_data: Object)
	signal consent_form_dismissed(error_data: Object)
	signal rewarded_ad_loaded(ad_info: Object, response_info: Object)
	signal rewarded_ad_failed_to_load(ad_info: Object, error_data: Object)
	signal rewarded_ad_user_earned_reward(ad_info: Object, reward_data: Object)
	signal rewarded_ad_dismissed_full_screen_content(ad_info: Object)
	signal rewarded_ad_failed_to_show_full_screen_content(ad_info: Object, error_data: Object)
	signal interstitial_ad_loaded(ad_info: Object, response_info: Object)
	signal interstitial_ad_failed_to_load(ad_info: Object, error_data: Object)
	signal interstitial_ad_dismissed_full_screen_content(ad_info: Object)
	signal interstitial_ad_failed_to_show_full_screen_content(ad_info: Object, error_data: Object)
	var calls: PackedStringArray = PackedStringArray()
	var consent_status: int = 1 # NOT_REQUIRED
	var form_available: bool = false
	func update_consent_info() -> void: calls.append("update_consent_info")
	func get_consent_status() -> Object:
		var c: FakeConsent = FakeConsent.new()
		c.status = consent_status
		return c
	func is_consent_form_available() -> bool: return form_available
	func load_consent_form() -> void: calls.append("load_consent_form")
	func show_consent_form() -> void: calls.append("show_consent_form")
	func initialize() -> void: calls.append("initialize")
	func load_rewarded_ad() -> void: calls.append("load_rewarded_ad")
	func load_interstitial_ad() -> void: calls.append("load_interstitial_ad")
	func show_rewarded_ad() -> void: calls.append("show_rewarded_ad")
	func show_interstitial_ad() -> void: calls.append("show_interstitial_ad")
	func count(c: String) -> int:
		var n: int = 0
		for x: String in calls:
			if x == c:
				n += 1
		return n

class FakeConsent extends RefCounted:
	var status: int = 0

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Ads tests ===")
	_test_install()
	_test_config_agrees()
	_test_mock_off_device()
	_test_node_ids()
	await _test_flow_no_consent_needed()
	await _test_flow_consent_form()
	await _test_consent_timeout()
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_install() -> void:
	_check("AdMob plugin v5.3 is in addons/AdmobPlugin (with its licence)",
		FileAccess.file_exists("res://addons/AdmobPlugin/plugin.cfg") and FileAccess.file_exists("res://addons/AdmobPlugin/LICENSE")
		and FileAccess.get_file_as_string("res://addons/AdmobPlugin/plugin.cfg").contains('version="5.3"'))
	_check("Release and debug Android libraries are there",
		FileAccess.file_exists("res://addons/AdmobPlugin/bin/release/AdmobPlugin-release.aar") and FileAccess.file_exists("res://addons/AdmobPlugin/bin/debug/AdmobPlugin-debug.aar"))
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	_check("Its export plugin is enabled (it writes the app id into the manifest)", enabled.has("res://addons/AdmobPlugin/plugin.cfg"))
	_check("…next to the daily reminder plugin", enabled.has("res://addons/namma_reminder/plugin.cfg"))

func _test_config_agrees() -> void:
	var cfg: AdConfig = load("res://data/monetization/ad_config.tres") as AdConfig
	var exp: ConfigFile = ConfigFile.new()
	var ok: bool = exp.load("res://addons/AdmobPlugin/android_export.cfg") == OK
	_check("Ads use the AdMob provider", cfg.provider == "admob")
	_check("Export config and ad config agree on test vs real", ok and bool(exp.get_value("General", "is_real", true)) == (not cfg.use_test_ads))
	_check("Test builds carry Google's TEST app id", ok and str(exp.get_value("Debug", "app_id", "")) == TEST_APP_ID)
	if not cfg.use_test_ads:
		var real_ok: bool = cfg.admob_app_id.begins_with("ca-app-pub-") and cfg.admob_app_id.contains("~") \
			and cfg.rewarded_unit_id.begins_with("ca-app-pub-") and cfg.interstitial_unit_id.begins_with("ca-app-pub-") \
			and str(exp.get_value("Release", "app_id", "")) == cfg.admob_app_id
		_check("Real ads: every real id is filled in and the manifest gets the same app id", real_ok)
	else:
		_check("Real ids stay empty until AdMob approval (no half-real config)", cfg.admob_app_id == "" or cfg.admob_app_id.begins_with("ca-app-pub-"))
	_check("Ad content ceiling is a valid rating", cfg.max_ad_content_rating in ["G", "PG", "T", "MA"])

func _test_mock_off_device() -> void:
	_check("Off the phone (no plugin singleton) the placeholder ads stay in use",
		not AdMobProvider.plugin_available() and AdMonetizationManager.provider.provider_name() == "mock")

func _test_node_ids() -> void:
	var cfg: AdConfig = (load("res://data/monetization/ad_config.tres") as AdConfig).duplicate() as AdConfig
	cfg.use_test_ads = true
	var n: Node = AdMobProvider._make_admob_node(cfg)
	_check("Test mode: the Admob node keeps Google's demo ad units", not bool(n.get("is_real"))
		and str(n.get("android_debug_rewarded_id")) == "ca-app-pub-3940256099942544/5224354917"
		and str(n.get("android_debug_interstitial_id")) == "ca-app-pub-3940256099942544/1033173712")
	_check("PG ad content rating is passed on", int(n.get("max_ad_content_rating")) == 1)
	n.free()
	cfg.use_test_ads = false
	cfg.admob_app_id = "ca-app-pub-1111111111111111~2222222222"
	cfg.rewarded_unit_id = "ca-app-pub-1111111111111111/3333333333"
	cfg.interstitial_unit_id = "ca-app-pub-1111111111111111/4444444444"
	var dbg: Node = AdMobProvider._make_admob_node(cfg, true)
	_check("Debug builds (side-loaded test APKs) show Google's demo ads even when real ads are on",
		not bool(dbg.get("is_real")) and AdMobProvider.use_demo_ads(cfg, true))
	dbg.free()
	var r: Node = AdMobProvider._make_admob_node(cfg, false)
	_check("Real mode: the node gets the real app and unit ids", bool(r.get("is_real"))
		and str(r.get("android_real_rewarded_id")) == cfg.rewarded_unit_id and str(r.get("android_real_interstitial_id")) == cfg.interstitial_unit_id
		and str(r.get("android_real_application_id")) == cfg.admob_app_id)
	r.free()

func _make(fake: FakeAdmob) -> AdMobProvider:
	var p: AdMobProvider = AdMobProvider.new()
	add_child(p)
	p.ads = fake
	p.add_child(fake)
	p.setup(load("res://data/monetization/ad_config.tres") as AdConfig)
	return p

func _test_flow_no_consent_needed() -> void:
	var fake: FakeAdmob = FakeAdmob.new()
	var p: AdMobProvider = _make(fake)
	_check("Start-up asks for consent info first, before anything else", fake.calls.size() == 1 and fake.calls[0] == "update_consent_info")
	p.load_rewarded()
	p.load_interstitial()
	_check("Loads asked for before start-up wait (nothing requested yet)", fake.count("load_rewarded_ad") == 0 and not p.is_rewarded_ready())
	fake.consent_info_updated.emit()
	_check("Consent not required (India): straight to initialize, no form", fake.count("initialize") == 1 and fake.count("load_consent_form") == 0)
	fake.initialization_completed.emit(null)
	_check("After initialize, the queued loads go out once each", fake.count("load_rewarded_ad") == 1 and fake.count("load_interstitial_ad") == 1)
	p.load_rewarded()
	_check("No duplicate request while one is loading", fake.count("load_rewarded_ad") == 1)
	_check("show_* returns false at once when nothing is loaded (never blocks play)", not p.show_rewarded("ad_tow") and not p.show_interstitial("shift_end"))
	fake.rewarded_ad_loaded.emit(null, null)
	fake.interstitial_ad_loaded.emit(null, null)
	_check("Loaded ads report ready", p.is_rewarded_ready() and p.is_interstitial_ready())
	var earned: Array[String] = []
	var closed: Array[String] = []
	p.rewarded_earned.connect(func(pl: String) -> void: earned.append(pl))
	p.rewarded_closed.connect(func(pl: String) -> void: closed.append(pl))
	AudioServer.set_bus_mute(0, false)
	_check("Showing a rewarded ad works and mutes the game", p.show_rewarded("ad_wreck_repair") and fake.count("show_rewarded_ad") == 1 and AudioServer.is_bus_mute(0))
	_check("Nothing else can start while one is on screen", not p.is_interstitial_ready())
	fake.rewarded_ad_user_earned_reward.emit(null, null)
	fake.rewarded_ad_dismissed_full_screen_content.emit(null)
	_check("Reward and close reach the game with the right placement", earned == ["ad_wreck_repair"] and closed == ["ad_wreck_repair"])
	_check("Sound comes back after the ad", not AudioServer.is_bus_mute(0))
	_check("The next rewarded ad is requested by itself", fake.count("load_rewarded_ad") == 2)
	# A rewarded ad closed early still reloads; a failed show reports failure and unmutes.
	fake.rewarded_ad_loaded.emit(null, null)
	var failed: Array[String] = []
	p.rewarded_failed.connect(func(pl: String, _why: String) -> void: failed.append(pl))
	p.show_rewarded("ad_tow")
	fake.rewarded_ad_failed_to_show_full_screen_content.emit(null, null)
	_check("A rewarded ad that fails to show reports it, unmutes and reloads", failed == ["ad_tow"] and not AudioServer.is_bus_mute(0) and fake.count("load_rewarded_ad") == 3)
	var i_closed: Array[String] = []
	p.interstitial_closed.connect(func(pl: String) -> void: i_closed.append(pl))
	p.show_interstitial("after_fare_summary")
	fake.interstitial_ad_dismissed_full_screen_content.emit(null)
	_check("Interstitial close reaches the game and the next one loads", i_closed == ["after_fare_summary"] and fake.count("load_interstitial_ad") == 2)
	p.queue_free()
	await get_tree().process_frame

func _test_flow_consent_form() -> void:
	var fake: FakeAdmob = FakeAdmob.new()
	fake.consent_status = 2 # REQUIRED (EEA / UK)
	fake.form_available = true
	var p: AdMobProvider = _make(fake)
	fake.consent_info_updated.emit()
	_check("Consent required: the form is loaded, and ads wait", fake.count("load_consent_form") == 1 and fake.count("initialize") == 0)
	fake.consent_form_loaded.emit()
	_check("…then shown", fake.count("show_consent_form") == 1)
	fake.consent_form_dismissed.emit(null)
	_check("After the player answers, the ads SDK starts", fake.count("initialize") == 1)
	fake.consent_info_update_failed.emit(null)
	_check("A late consent error never starts it twice", fake.count("initialize") == 1)
	p.queue_free()
	await get_tree().process_frame

func _test_consent_timeout() -> void:
	var fake: FakeAdmob = FakeAdmob.new()
	var p: AdMobProvider = _make(fake)
	for i: int in int((AdMobProvider.CONSENT_TIMEOUT_S + 0.5) * 60.0):
		await get_tree().process_frame
	_check("No consent answer (offline): ads start anyway after %.0f s" % AdMobProvider.CONSENT_TIMEOUT_S, fake.count("initialize") == 1)
	p.queue_free()
	await get_tree().process_frame

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s  %s" % [label, detail])
