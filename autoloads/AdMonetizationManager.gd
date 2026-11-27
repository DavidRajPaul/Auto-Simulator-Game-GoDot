extends Node
## Non-intrusive ad policy (AGENTS.md autoload). The rest of the game asks this service
## "may I show X here?" and never talks to an ad SDK directly.
##
## Rules (all numbers in data/monetization/ad_config.tres):
##   • Rewarded ads are always opt-in and pay only when the network confirms (RewardsEngine).
##   • Forced interstitials only at natural breaks (fare summary, shift end, back to menu), never
##     while moving, never in the first 8 minutes of a new install, ≥ 3 min apart, ≤ 2 per
##     10 minutes, ≤ 3 per session, only every 3rd ride — and never for "No Ads" buyers.
##   • A watched rewarded ad resets the interstitial cooldown.
##   • Nothing ever waits on an ad: if none is cached, the game just carries on.

const CONFIG_PATH: String = "res://data/monetization/ad_config.tres"
## Clear space kept between the banner and the nearest button (AdMob: no ads right next to
## interactive elements — accidental clicks get the account "Confirmed Click" or worse).
const BANNER_GAP_PX: float = 24.0

## Bottom room (viewport px) screens must leave free: banner + gap, or 0 with no banner.
signal banner_inset_changed(inset_px: float)

var config: AdConfig
var provider: AdProvider
var session_s: float = 0.0
var install_play_s: float = 0.0 # total play time on this install (saved via GameState settings)
var last_interstitial_s: float = -100000.0
var interstitials_this_session: int = 0
var _recent: Array[float] = [] # session times of recent interstitials
var _rides_since_interstitial: int = 0
var _speed_kmh: float = 0.0
var _pending: Dictionary = {} # placement -> context for an in-flight rewarded ad

var _ad_serial: int = 0
var screen: String = ""
## A plain footer band behind the banner: the ad never floats over map, menu or game content
## (AdMob policy), and taps that miss the ad land on this band, not on whatever is under it.
var _strip_layer: CanvasLayer
var _strip: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = load(CONFIG_PATH) as AdConfig if ResourceLoader.exists(CONFIG_PATH) else AdConfig.new()
	provider = _make_provider(config.provider)
	add_child(provider)
	provider.setup(config)
	provider.rewarded_earned.connect(_on_rewarded_earned)
	provider.rewarded_failed.connect(func(p: String, why: String) -> void:
		_pending.erase(p)
		SignalBus.rewarded_ad_failed.emit(p, why))
	provider.interstitial_closed.connect(func(p: String) -> void: SignalBus.interstitial_closed.emit(p))
	_build_strip()
	provider.banner_visibility_changed.connect(func(_v: bool) -> void:
		_fit_strip()
		banner_inset_changed.emit(banner_inset_px()))
	get_viewport().size_changed.connect(_fit_strip)
	provider.load_rewarded()
	provider.load_interstitial()
	SignalBus.speed_updated.connect(func(k: float) -> void: _speed_kmh = k)
	SignalBus.ride_completed.connect(func(_b: Dictionary) -> void: _rides_since_interstitial += 1)
	install_play_s = float(GameState.settings.get("install_play_s", 0.0))

func _make_provider(kind: String) -> AdProvider:
	if kind == "admob" and AdMobProvider.plugin_available():
		return AdMobProvider.new()
	return MockAdProvider.new()

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	session_s += delta
	install_play_s += delta
	if int(session_s) % 30 == 0 and int(session_s - delta) % 30 != 0:
		GameState.settings["install_play_s"] = install_play_s

# --- Rewarded (opt-in) ----------------------------------------------------------

func can_offer_rewarded(placement: String) -> bool:
	return config.rewarded_enabled_placements.has(placement) and provider.is_rewarded_ready() \
		and GameState.rewards.remaining_today(placement, RewardsEngine.today_string()) > 0

## Show a rewarded ad. `context` is handed back with the confirmed reward (e.g. ride_id, inr).
func show_rewarded(placement: String, context: Dictionary = {}) -> bool:
	if not can_offer_rewarded(placement):
		SignalBus.rewarded_ad_failed.emit(placement, "unavailable")
		return false
	# One id per ad view: rewards were keyed by the in-game minute, which stands still during a
	# quest, so a second repair ad was refused as a duplicate (Nov 9 device report).
	_ad_serial += 1
	context = context.duplicate()
	context["ad_id"] = "%d-%d" % [int(Time.get_unix_time_from_system()), _ad_serial]
	_pending[placement] = context
	if not provider.show_rewarded(placement):
		_pending.erase(placement)
		SignalBus.rewarded_ad_failed.emit(placement, "not_loaded")
		provider.load_rewarded()
		return false
	return true

func _on_rewarded_earned(placement: String) -> void:
	var ctx: Dictionary = _pending.get(placement, {})
	_pending.erase(placement)
	if config.rewarded_resets_cooldown:
		last_interstitial_s = session_s
	SignalBus.rewarded_ad_completed.emit(placement, ctx)
	provider.load_rewarded()

# --- Interstitials (forced, rare) ------------------------------------------------

## Why not (empty string = allowed). Exposed for the debug overlay and tests.
func interstitial_block_reason(placement: String) -> String:
	if GameState.no_ads:
		return "no_ads_purchased"
	if not config.allowed_placements.has(placement):
		return "placement_not_allowed"
	if GameState.tutorial_active:
		return "tutorial"
	if install_play_s < config.first_session_grace_s:
		return "first_session_grace"
	if _speed_kmh > config.max_speed_kmh:
		return "moving"
	if session_s - last_interstitial_s < config.interstitial_cooldown_s:
		return "cooldown"
	if interstitials_this_session >= config.max_per_session:
		return "session_cap"
	var in_window: int = 0
	for t: float in _recent:
		if session_s - t < 600.0:
			in_window += 1
	if in_window >= config.max_per_10_min:
		return "ten_minute_cap"
	if placement == "after_fare_summary" and _rides_since_interstitial < config.rides_between_interstitials:
		return "ride_spacing"
	if not provider.is_interstitial_ready():
		return "not_loaded"
	return ""

## Call at a natural break. Returns true if an ad is being shown.
func maybe_show_interstitial(placement: String) -> bool:
	if interstitial_block_reason(placement) != "":
		return false
	if not provider.show_interstitial(placement):
		provider.load_interstitial()
		return false
	last_interstitial_s = session_s
	interstitials_this_session += 1
	_recent.append(session_s)
	if _recent.size() > 8:
		_recent.pop_front()
	_rides_since_interstitial = 0
	provider.load_interstitial()
	SignalBus.ad_state_changed.emit({"interstitials": interstitials_this_session})
	return true

# --- Banners ------------------------------------------------------------------

## Screens call this when they open/close. Banners show only on AdConfig.banner_screens (menus,
## garage, pause, full map, shift summary) — never over driving, never in the tutorial, never
## for "No Ads" buyers. Any other name ("driving", "loading", "fine") hides the banner.
func set_screen(name: String) -> void:
	screen = name
	provider.show_banner(banner_allowed(name))

func banner_allowed(name: String) -> bool:
	return not GameState.no_ads and not GameState.tutorial_active and config.banner_screens.has(name)

## The banner's rectangle in viewport pixels: 320 x 50 dp, bottom centre, above the safe-area edge.
func banner_rect_px() -> Rect2:
	var vp: Vector2 = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	var win: Vector2i = DisplayServer.window_get_size()
	var to_vp: float = vp.y / float(win.y) if win.y > 0 else 1.0
	# Android: 1 dp = dpi / 160 physical pixels. Desktop/editor: treat a dp as one window pixel.
	var dp: float = DisplayServer.screen_get_dpi() / 160.0 if OS.get_name() == "Android" else 1.0
	var safe_bottom: float = 0.0
	if win.y > 0 and OS.get_name() in ["Android", "iOS"]:
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window_pos: Vector2i = DisplayServer.window_get_position()
		safe_bottom = maxf(0.0, float(window_pos.y + win.y) - float(safe.position.y + safe.size.y))
	var w: float = AdProvider.BANNER_W_DP * dp * to_vp
	var h: float = AdProvider.BANNER_H_DP * dp * to_vp
	var bottom: float = vp.y - safe_bottom * to_vp
	return Rect2(Vector2((vp.x - w) * 0.5, bottom - h), Vector2(w, h))

func _build_strip() -> void:
	_strip_layer = CanvasLayer.new()
	_strip_layer.layer = 109 # above every game screen, under the placeholder banner (110)
	_strip_layer.visible = false
	add_child(_strip_layer)
	_strip = ColorRect.new()
	_strip.color = Color(0.07, 0.05, 0.11)
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip_layer.add_child(_strip)

func _fit_strip() -> void:
	var on: bool = provider.is_banner_showing()
	_strip_layer.visible = on
	if on:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var top: float = banner_rect_px().position.y - BANNER_GAP_PX * 0.5
		_strip.position = Vector2(0.0, top)
		_strip.size = Vector2(vp.x, vp.y - top)

## Room to leave at the bottom of the screen while a banner shows (banner + gap), else 0.
func banner_inset_px() -> float:
	if not provider.is_banner_showing():
		return 0.0
	var r: Rect2 = banner_rect_px()
	var vp_h: float = get_viewport().get_visible_rect().size.y if get_viewport() != null else 720.0
	return vp_h - r.position.y + BANNER_GAP_PX

## Test helper: pretend this many seconds of play happened.
func debug_advance(seconds: float) -> void:
	session_s += seconds
	install_play_s += seconds
