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

## The same, plus the banner half of the plugin's API.
class FakeBannerAdmob extends FakeAdmob:
	signal banner_ad_loaded(ad_info: Object, response_info: Object)
	signal banner_ad_failed_to_load(ad_info: Object, error_data: Object)
	func load_banner_ad() -> void: calls.append("load_banner_ad")
	func show_banner_ad() -> void: calls.append("show_banner_ad")
	func hide_banner_ad() -> void: calls.append("hide_banner_ad")

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
	await _test_admob_banner()
	_test_banner_policy()
	await _test_banner_layout()
	_test_rewarded_placements()
	_test_test_drive()
	_test_paint_trial()
	_test_daily_and_quest_double()
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

# --- Banners (Nov 27) ------------------------------------------------------------------------

func _test_admob_banner() -> void:
	var cfg: AdConfig = (load("res://data/monetization/ad_config.tres") as AdConfig).duplicate() as AdConfig
	var n: Node = AdMobProvider._make_admob_node(cfg)
	_check("Banner: standard 320 × 50, bottom centre, inside the safe area",
		int(n.get("banner_position")) == 1 and int(n.get("banner_size")) == 0 and bool(n.get("banner_anchor_to_safe_area")))
	n.free()
	cfg.use_test_ads = false
	cfg.banner_unit_id = ""
	_check("Release build without a real banner unit id: banners stay off", not AdMobProvider.banner_enabled(cfg, false))
	_check("…debug builds still get Google's demo banner", AdMobProvider.banner_enabled(cfg, true))
	cfg.banner_unit_id = "ca-app-pub-1111111111111111/5555555555"
	var r: Node = AdMobProvider._make_admob_node(cfg, false)
	_check("Real mode: the node gets the real banner unit id", str(r.get("android_real_banner_id")) == cfg.banner_unit_id)
	r.free()
	var fake: FakeBannerAdmob = FakeBannerAdmob.new()
	var p: AdMobProvider = _make(fake)
	var shown: Array[bool] = []
	p.banner_visibility_changed.connect(func(v: bool) -> void: shown.append(v))
	p.show_banner(true)
	_check("A banner asked for before the SDK starts waits (no request yet)", fake.count("load_banner_ad") == 0 and not p.is_banner_showing())
	fake.consent_info_updated.emit()
	fake.initialization_completed.emit(null)
	_check("After start-up the banner is requested once", fake.count("load_banner_ad") == 1)
	p.show_banner(true)
	_check("No duplicate banner request while one loads", fake.count("load_banner_ad") == 1)
	fake.banner_ad_loaded.emit(null, null)
	_check("Loaded banner goes on screen and the screens are told", fake.count("show_banner_ad") == 1 and p.is_banner_showing() and shown == [true])
	p.show_banner(false)
	_check("Leaving the screen hides it (driving never has a banner)", fake.count("hide_banner_ad") == 1 and not p.is_banner_showing() and shown == [true, false])
	p.show_banner(true)
	_check("Coming back re-shows the same banner without a new request", fake.count("load_banner_ad") == 1 and fake.count("show_banner_ad") == 2)
	p.show_banner(false)
	fake.banner_ad_loaded.emit(null, null) # a refresh arriving while no screen wants it
	_check("A banner that loads while hidden is hidden straight away", not p.is_banner_showing() and fake.count("hide_banner_ad") >= 2)
	p.queue_free()
	await get_tree().process_frame

func _test_banner_policy() -> void:
	var m: Node = AdMonetizationManager
	var was_tutorial: bool = GameState.tutorial_active
	GameState.tutorial_active = false
	GameState.no_ads = false
	for screen: String in ["main_menu", "garage", "pause", "full_map", "shift_summary"]:
		_check("Banner allowed on the calm screen '%s'" % screen, bool(m.call("banner_allowed", screen)))
	for screen: String in ["driving", "loading", "fine", ""]:
		_check("No banner on '%s'" % screen, not bool(m.call("banner_allowed", screen)))
	GameState.tutorial_active = true
	_check("No banner during the tutorial", not bool(m.call("banner_allowed", "main_menu")))
	GameState.tutorial_active = false
	GameState.no_ads = true
	_check("No banner for No Ads buyers", not bool(m.call("banner_allowed", "pause")))
	GameState.no_ads = false
	GameState.tutorial_active = was_tutorial
	_check("Interstitials stay limited to their natural breaks (back to menu still unused)",
		AdMonetizationManager.config.allowed_placements == PackedStringArray(["after_fare_summary", "shift_end", "back_to_menu"]))

func _test_banner_layout() -> void:
	GameState.tutorial_active = false
	AdMonetizationManager.set_screen("pause")
	await get_tree().process_frame
	var r: Rect2 = AdMonetizationManager.banner_rect_px()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var inset: float = AdMonetizationManager.banner_inset_px()
	_check("Mock banner shows on the pause screen", AdMonetizationManager.provider.is_banner_showing())
	_check("Banner rect: 320 × 50 dp shape at the bottom centre", r.size.x > 0.0 and is_equal_approx(r.size.x / r.size.y, 320.0 / 50.0)
		and absf(r.get_center().x - vp.x * 0.5) < 1.0 and absf(r.end.y - vp.y) < 1.0, str(r))
	_check("Screens keep the banner plus a %d px gap free" % int(AdMonetizationManager.BANNER_GAP_PX),
		is_equal_approx(inset, vp.y - r.position.y + AdMonetizationManager.BANNER_GAP_PX), "%.1f" % inset)
	var strip: ColorRect = AdMonetizationManager.get("_strip") as ColorRect
	_check("A solid footer band sits behind the banner (no ad over game content, stray taps land on it)",
		(AdMonetizationManager.get("_strip_layer") as CanvasLayer).visible and strip.mouse_filter == Control.MOUSE_FILTER_STOP
		and strip.position.y <= r.position.y and is_equal_approx(strip.size.x, vp.x))
	# The garage / pause card sits above the banner with the gap (no button next to the ad).
	var ui: GarageUI = (load("res://scripts/ui/GarageUI.gd") as GDScript).new() as GarageUI
	add_child(ui)
	await get_tree().process_frame
	_check("Entering the driving scene hides the banner", not AdMonetizationManager.provider.is_banner_showing())
	ui.open_garage()
	await get_tree().process_frame
	var modal: Control = ui.get("_modal") as Control
	_check("Garage card opens with a banner under it", AdMonetizationManager.provider.is_banner_showing() and AdMonetizationManager.screen == "garage")
	_check("…and ends at least %d px above the banner" % int(AdMonetizationManager.BANNER_GAP_PX),
		modal.position.y + modal.size.y <= AdMonetizationManager.banner_rect_px().position.y - AdMonetizationManager.BANNER_GAP_PX + 0.5,
		"card bottom %.0f, banner top %.0f" % [modal.position.y + modal.size.y, AdMonetizationManager.banner_rect_px().position.y])
	ui.close_modal()
	_check("Back to driving: banner gone, room given back", not AdMonetizationManager.provider.is_banner_showing() and AdMonetizationManager.banner_inset_px() == 0.0)
	ui.queue_free()
	get_tree().paused = false
	await get_tree().process_frame

# --- Rewarded ads (Nov 27) --------------------------------------------------------------------

func _test_rewarded_placements() -> void:
	var cfg: AdConfig = AdMonetizationManager.config
	for placement: String in ["ad_test_drive", "ad_paint_trial", "ad_daily_double", "ad_quest_double"]:
		_check("Rewarded placement '%s' is enabled and capped per day" % placement,
			cfg.rewarded_enabled_placements.has(placement) and RewardsEngine.DAILY_CAPS.has(placement) and RewardsEngine.AD_OFFERS.has(placement))
	_check("Daily bonus can be doubled only once a day", int(RewardsEngine.DAILY_CAPS["ad_daily_double"]) == 1)

func _test_test_drive() -> void:
	GameState.reset_profile()
	GameState.condition = 62.0
	GameState.fuel_level = 3.0
	SignalBus.rewarded_ad_completed.emit("ad_test_drive", {"vehicle": "namma_green_ev", "ad_id": "t1"})
	_check("Test drive: the EV (locked at this level) is driven without buying it",
		GameState.active_vehicle == "namma_green_ev" and not GameState.owned_vehicles.has("namma_green_ev") and GameState.on_test_drive())
	_check("…with a full battery and no scratches", GameState.condition == 100.0 and is_equal_approx(GameState.fuel_level, GameState.base_stats("namma_green_ev").fuel_capacity))
	_check("Upgrades can't be bought for a lent auto", not GameState.buy_upgrade("engine"))
	var saved: Dictionary = GameState.to_dict()
	GameState.from_dict(saved)
	_check("An app restart in the same shift keeps the test drive", GameState.active_vehicle == "namma_green_ev" and GameState.on_test_drive())
	var lapsed: Dictionary = saved.duplicate(true)
	lapsed["day"] = int(lapsed["day"]) + 1
	GameState.from_dict(lapsed)
	_check("A save from a later day hands it back, with your own tank and condition",
		GameState.active_vehicle == "singara_classic" and not GameState.on_test_drive() and is_equal_approx(GameState.condition, 62.0) and is_equal_approx(GameState.fuel_level, 3.0))
	GameState.from_dict(saved)
	GameState.end_shift()
	_check("Shift end: back in your own auto as you parked it",
		GameState.active_vehicle == "singara_classic" and is_equal_approx(GameState.condition, 62.0) and is_equal_approx(GameState.fuel_level, 3.0) and GameState.trial_vehicle == "")
	GameState.start_next_day()
	GameState.start_test_drive("madras_king_deluxe")
	GameState.select_vehicle("singara_classic")
	_check("Picking your own auto ends the test drive", GameState.active_vehicle == "singara_classic" and GameState.trial_vehicle == "")
	GameState.start_test_drive("madras_king_deluxe")
	GameState.progress.xp = 1000000
	GameState.wallet_inr = 10000000
	_check("Buying the auto on test drive keeps it", GameState.buy_vehicle("madras_king_deluxe") and GameState.active_vehicle == "madras_king_deluxe"
		and GameState.owned_vehicles.has("madras_king_deluxe") and GameState.trial_vehicle == "")
	_check("Can't test-drive an auto you own", not GameState.start_test_drive("madras_king_deluxe"))
	GameState.reset_profile()

func _test_paint_trial() -> void:
	GameState.reset_profile()
	var idx: int = GameState.PAINTS.size() - 1
	SignalBus.rewarded_ad_completed.emit("ad_paint_trial", {"paint": idx, "ad_id": "p1"})
	_check("Paint trial: an unowned paint goes on the auto", GameState.shown_paint() == idx and not GameState.paints_owned.has(idx)
		and GameState.active_stats().body_colour == GameState.PAINTS[idx]["body"])
	_check("…and its Meter Mela prestige counts", GameState.prestige() >= float(GameState.PAINTS[idx]["prestige"]) - 0.001)
	GameState.from_dict(GameState.to_dict())
	_check("It survives an app restart in the same shift", GameState.shown_paint() == idx)
	GameState.end_shift()
	_check("Shift end takes it off", GameState.shown_paint() == GameState.paint_equipped and GameState.trial_paint == -1)
	_check("Can't trial a paint you own", not GameState.start_paint_trial(0))
	GameState.start_next_day()
	GameState.reset_profile()

func _test_daily_and_quest_double() -> void:
	GameState.reset_profile()
	var claimed: Dictionary = GameState.claim_daily_reward()
	var before: int = GameState.wallet_inr
	SignalBus.rewarded_ad_completed.emit("ad_daily_double", {"inr": int(claimed["inr"]), "ad_id": "d1"})
	_check("2× daily bonus pays today's bonus again", GameState.wallet_inr == before + int(claimed["inr"]), "%d -> %d" % [before, GameState.wallet_inr])
	SignalBus.rewarded_ad_completed.emit("ad_daily_double", {"inr": int(claimed["inr"]), "ad_id": "d2"})
	_check("…only once a day", GameState.wallet_inr == before + int(claimed["inr"]))
	_check("…and the offer is gone for today", GameState.rewards.remaining_today("ad_daily_double", RewardsEngine.today_string()) == 0)
	before = GameState.wallet_inr
	SignalBus.rewarded_ad_completed.emit("ad_quest_double", {"quest_id": "sq_test", "inr": 300, "ad_id": "q1"})
	_check("2× quest reward pays the quest's ₹ again", GameState.wallet_inr == before + 300)
	SignalBus.rewarded_ad_completed.emit("ad_quest_double", {"quest_id": "sq_test", "inr": 300, "ad_id": "q2"})
	_check("…once per quest", GameState.wallet_inr == before + 300)
	GameState.reset_profile()

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s  %s" % [label, detail])
