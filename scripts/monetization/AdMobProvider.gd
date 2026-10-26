class_name AdMobProvider
extends AdProvider
## Bridge to the Poing Studios "godot-admob" Android plugin (MIT, Godot 4). NOT ACTIVE until
## the plugin is installed into android/plugins and `provider = "admob"` is set in
## data/monetization/ad_config.tres; until then AdMonetizationManager uses MockAdProvider.
##
## Integration checklist (do in this order):
##   1. Install the plugin from the Godot Asset Library ("AdMob" by Poing Studios) and enable it.
##   2. Add the AdMob app id to android/build/AndroidManifest.xml (meta-data
##      com.google.android.gms.ads.APPLICATION_ID) — keep Google's TEST id until approval.
##   3. Keep `use_test_ads = true` for closed testing; real unit ids only for production.
##   4. Show the UMP consent form before the first ad request (GDPR / India DPDP Act).
##   5. Add app-ads.txt on the developer website (Play listing → Store settings).
## The calls below follow the plugin's documented loader/callback API; they are reached via
## dynamic calls so this file compiles without the plugin present.

var _rewarded: Object
var _interstitial: Object
var _placement_r: String = ""
var _placement_i: String = ""

static func plugin_available() -> bool:
	return ClassDB.class_exists("RewardedAdLoader") and ClassDB.class_exists("InterstitialAdLoader")

func provider_name() -> String:
	return "admob"

func setup(cfg: AdConfig) -> void:
	super.setup(cfg)
	if Engine.has_singleton("PoingGodotAdMob") and ClassDB.class_exists("MobileAds"):
		ClassDB.instantiate("MobileAds").call("initialize")

func load_rewarded() -> void:
	if not plugin_available():
		return
	var loader: Object = ClassDB.instantiate("RewardedAdLoader")
	var cb: Object = ClassDB.instantiate("RewardedAdLoadCallback")
	cb.set("on_ad_loaded", func(ad: Object) -> void: _rewarded = ad)
	cb.set("on_ad_failed_to_load", func(_err: Object) -> void: _rewarded = null)
	loader.call("load", config.rewarded_unit_id, ClassDB.instantiate("AdRequest"), cb)

func load_interstitial() -> void:
	if not plugin_available():
		return
	var loader: Object = ClassDB.instantiate("InterstitialAdLoader")
	var cb: Object = ClassDB.instantiate("InterstitialAdLoadCallback")
	cb.set("on_ad_loaded", func(ad: Object) -> void: _interstitial = ad)
	cb.set("on_ad_failed_to_load", func(_err: Object) -> void: _interstitial = null)
	loader.call("load", config.interstitial_unit_id, ClassDB.instantiate("AdRequest"), cb)

func is_rewarded_ready() -> bool:
	return _rewarded != null

func is_interstitial_ready() -> bool:
	return _interstitial != null

func show_rewarded(placement: String) -> bool:
	if _rewarded == null:
		return false
	_placement_r = placement
	var earned: Object = ClassDB.instantiate("OnUserEarnedRewardListener")
	earned.set("on_user_earned_reward", func(_item: Object) -> void: rewarded_earned.emit(_placement_r))
	var fs: Object = ClassDB.instantiate("FullScreenContentCallback")
	fs.set("on_ad_dismissed_full_screen_content", func() -> void:
		rewarded_closed.emit(_placement_r)
		_rewarded = null)
	fs.set("on_ad_failed_to_show_full_screen_content", func(_e: Object) -> void:
		rewarded_failed.emit(_placement_r, "show_failed")
		_rewarded = null)
	_rewarded.set("full_screen_content_callback", fs)
	_rewarded.call("show", earned)
	return true

func show_interstitial(placement: String) -> bool:
	if _interstitial == null:
		return false
	_placement_i = placement
	var fs: Object = ClassDB.instantiate("FullScreenContentCallback")
	fs.set("on_ad_dismissed_full_screen_content", func() -> void:
		interstitial_closed.emit(_placement_i)
		_interstitial = null)
	_interstitial.set("full_screen_content_callback", fs)
	_interstitial.call("show")
	return true
