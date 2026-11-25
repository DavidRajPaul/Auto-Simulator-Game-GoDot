class_name AdMobProvider
extends AdProvider
## Real ads through the godot-sdk-integrations AdMob plugin v5.3 (addons/AdmobPlugin, MIT; built
## for Godot 4.5.1). AdMonetizationManager picks it when ad_config.provider = "admob" AND the
## plugin's Android singleton exists, so the editor, desktop and headless tests keep the mock.
##
## Start-up order (Google's guidance): consent first (UMP; the form only appears where the law
## requires it, e.g. the EEA / UK), then MobileAds initialize, then the first ad requests. Loads
## asked for before that are queued. Each ad reloads itself after it closes, so the next one is
## ready (a rewarded ad closed early used to leave nothing loaded). Game audio is muted while a
## full-screen ad plays and restored after.
##
## Test vs real: config.use_test_ads = true uses Google's demo ad units (the Admob node's
## android_debug_* defaults) and, through addons/AdmobPlugin/android_export.cfg, the test app id.
## Flip both only with the real ids from the AdMob console (see docs/ADS.md).

const SINGLETON: String = "AdmobPlugin"
const ADMOB_SCRIPT: String = "res://addons/AdmobPlugin/Admob.gd"
## UMP form / MobileAds start-up can take a while on a slow network; loads wait at most this long
## for consent before going ahead (the SDK then serves non-personalised ads where required).
const CONSENT_TIMEOUT_S: float = 12.0

## The plugin's Admob node (or a test double with the same signals and methods).
var ads: Node
var initialized: bool = false
var consent_done: bool = false
var _want_rewarded: bool = false
var _want_interstitial: bool = false
var _loading_rewarded: bool = false
var _loading_interstitial: bool = false
var _rewarded_ready: bool = false
var _interstitial_ready: bool = false
var _placement_r: String = ""
var _placement_i: String = ""
var _muted_before: bool = false
var _showing: bool = false
var _consent_wait_s: float = 0.0

static func plugin_available() -> bool:
	return Engine.has_singleton(SINGLETON)

func provider_name() -> String:
	return "admob"

func setup(cfg: AdConfig) -> void:
	super.setup(cfg)
	if ads == null:
		ads = _make_admob_node(cfg)
		add_child(ads)
	_connect(ads)
	set_process(true)
	_request_consent()

## The plugin node, with ids set BEFORE it enters the tree (it reads them in _ready).
## Debug builds (the APKs the owner side-loads from CI to test) ALWAYS get Google's demo ad
## units, even once ad_config goes live, so tapping ads while testing can never count as invalid
## clicks on the real account. Only release builds (the Play Store AAB) can show real ads.
static func use_demo_ads(cfg: AdConfig, debug_build: bool = OS.is_debug_build()) -> bool:
	return cfg.use_test_ads or debug_build

static func _make_admob_node(cfg: AdConfig, debug_build: bool = OS.is_debug_build()) -> Node:
	var node: Node = (load(ADMOB_SCRIPT) as GDScript).new() as Node
	node.name = "Admob"
	var demo: bool = use_demo_ads(cfg, debug_build)
	node.set("is_real", not demo)
	node.set("auto_configure_on_initialize", true)
	node.set("max_ad_content_rating", ["G", "PG", "T", "MA"].find(cfg.max_ad_content_rating) if cfg.max_ad_content_rating in ["G", "PG", "T", "MA"] else 1)
	if not demo:
		node.set("android_real_application_id", cfg.admob_app_id)
		node.set("android_real_rewarded_id", cfg.rewarded_unit_id)
		node.set("android_real_interstitial_id", cfg.interstitial_unit_id)
		node.set("android_real_banner_id", cfg.banner_unit_id)
	return node

func _connect(n: Node) -> void:
	n.connect("consent_info_updated", _on_consent_info_updated)
	n.connect("consent_info_update_failed", func(_e: Object) -> void: _consent_finished())
	n.connect("consent_form_loaded", func() -> void: n.call("show_consent_form"))
	n.connect("consent_form_failed_to_load", func(_e: Object) -> void: _consent_finished())
	n.connect("consent_form_dismissed", func(_e: Object) -> void: _consent_finished())
	n.connect("initialization_completed", func(_s: Object) -> void:
		initialized = true
		_flush_loads())
	n.connect("rewarded_ad_loaded", func(_i: Object, _r: Object) -> void:
		_loading_rewarded = false
		_rewarded_ready = true)
	n.connect("rewarded_ad_failed_to_load", func(_i: Object, _e: Object) -> void:
		_loading_rewarded = false
		_rewarded_ready = false)
	n.connect("rewarded_ad_user_earned_reward", func(_i: Object, _r: Object) -> void: rewarded_earned.emit(_placement_r))
	n.connect("rewarded_ad_dismissed_full_screen_content", func(_i: Object) -> void:
		_end_show()
		rewarded_closed.emit(_placement_r)
		load_rewarded())
	n.connect("rewarded_ad_failed_to_show_full_screen_content", func(_i: Object, _e: Object) -> void:
		_end_show()
		rewarded_failed.emit(_placement_r, "show_failed")
		load_rewarded())
	n.connect("interstitial_ad_loaded", func(_i: Object, _r: Object) -> void:
		_loading_interstitial = false
		_interstitial_ready = true)
	n.connect("interstitial_ad_failed_to_load", func(_i: Object, _e: Object) -> void:
		_loading_interstitial = false
		_interstitial_ready = false)
	n.connect("interstitial_ad_dismissed_full_screen_content", func(_i: Object) -> void:
		_end_show()
		interstitial_closed.emit(_placement_i)
		load_interstitial())
	n.connect("interstitial_ad_failed_to_show_full_screen_content", func(_i: Object, _e: Object) -> void:
		_end_show()
		interstitial_closed.emit(_placement_i)
		load_interstitial())

# --- Consent, then start-up ----------------------------------------------------------------

func _request_consent() -> void:
	ads.call("update_consent_info")

func _on_consent_info_updated() -> void:
	var status: Object = ads.call("get_consent_status") as Object
	var required: bool = status != null and int(status.get("status")) == 2 # UserConsent.Status.REQUIRED
	if required and bool(ads.call("is_consent_form_available")):
		ads.call("load_consent_form") # shown on consent_form_loaded
	else:
		_consent_finished()

func _consent_finished() -> void:
	if consent_done:
		return
	consent_done = true
	ads.call("initialize")

func _process(delta: float) -> void:
	if consent_done:
		set_process(false)
		return
	_consent_wait_s += delta
	if _consent_wait_s >= CONSENT_TIMEOUT_S:
		_consent_finished()

func _flush_loads() -> void:
	if _want_rewarded:
		load_rewarded()
	if _want_interstitial:
		load_interstitial()

# --- AdProvider ----------------------------------------------------------------------------

func load_rewarded() -> void:
	_want_rewarded = true
	if not initialized or _loading_rewarded or _rewarded_ready:
		return
	_loading_rewarded = true
	ads.call("load_rewarded_ad")

func load_interstitial() -> void:
	_want_interstitial = true
	if not initialized or _loading_interstitial or _interstitial_ready:
		return
	_loading_interstitial = true
	ads.call("load_interstitial_ad")

func is_rewarded_ready() -> bool:
	return _rewarded_ready and not _showing

func is_interstitial_ready() -> bool:
	return _interstitial_ready and not _showing

func show_rewarded(placement: String) -> bool:
	if not is_rewarded_ready():
		return false
	_placement_r = placement
	_rewarded_ready = false
	_begin_show()
	ads.call("show_rewarded_ad")
	return true

func show_interstitial(placement: String) -> bool:
	if not is_interstitial_ready():
		return false
	_placement_i = placement
	_interstitial_ready = false
	_begin_show()
	ads.call("show_interstitial_ad")
	return true

## Banners stay off for the first release (AdConfig.banner_screens is not wired to real ads).
func show_banner(_visible: bool) -> void:
	pass

func _begin_show() -> void:
	_showing = true
	_muted_before = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)

func _end_show() -> void:
	if not _showing:
		return
	_showing = false
	AudioServer.set_bus_mute(0, _muted_before)
